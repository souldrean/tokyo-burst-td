--!strict
-- DebugController: SO no Studio. Clicar (ou tocar) num inimigo causa dano de teste,
-- para podermos ver confete e recompensas sem ter torres ainda.
-- O cliente so manda "cliquei no inimigo X"; o servidor valida e decide o dano.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)

local RAY_LENGTH = 1000
local MIN_CLICK_INTERVAL = 0.1 -- no maximo 10 cliques por segundo (o servidor tambem limita)

local DebugController = {}

local connections: { RBXScriptConnection } = {}

function DebugController.init() end

function DebugController.start()
	-- Fora do Studio este controller nao faz nada (nem cria o remote nem a interface).
	if not RunService:IsStudio() then
		return
	end

	local enemiesInst = workspace:WaitForChild("Enemies", 30)
	if not enemiesInst then
		warn("[DebugController] workspace.Enemies nao apareceu em 30s.")
		return
	end
	local enemies: Instance = enemiesInst
	local hitRemote = Net.event("DebugHitEnemy")

	-- Etiqueta pequena no canto inferior esquerdo.
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "DebugGui"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.fromScale(0.01, 0.99)
	label.Size = UDim2.fromScale(0.2, 0.035)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 225, 60)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "DEBUG: click enemies"
	label.Parent = gui

	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 12
	limit.MaxTextSize = 18
	limit.Parent = label

	-- O raio so enxerga coisas dentro de workspace.Enemies (ignora mapa e jogadores).
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { enemies }

	local lastClick = 0

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then
				return -- clique em botao/interface nao conta
			end
			local inputType = input.UserInputType
			if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
				return
			end

			local now = os.clock()
			if now - lastClick < MIN_CLICK_INTERVAL then
				return
			end

			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			-- ScreenPointToRay ja considera a barra superior do Roblox (inset).
			local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
			local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)
			if not result then
				return
			end

			local model = result.Instance:FindFirstAncestorOfClass("Model")
			if model and model.Parent == enemies then
				lastClick = now
				hitRemote:FireServer(model.Name)
			end
		end)
	)
end

function DebugController.destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return DebugController
