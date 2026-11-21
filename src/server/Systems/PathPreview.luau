--!strict
-- PathPreview: um cubo de teste que anda pelo caminho em loop.
-- Serve para PROVAR que os waypoints formam um caminho correto.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PathMath = require(Shared:WaitForChild("Util"):WaitForChild("PathMath"))
-- Modulos sao "cacheados": este e o MESMO PathService que o servidor ja iniciou.
local PathService = require(script.Parent.PathService)

local PathPreview = {}

local connection: RBXScriptConnection? = nil

function PathPreview.init() end

function PathPreview.start()
	if not Config.PATH_PREVIEW_ENABLED then
		return
	end

	-- Sobe os pontos para a altura do cubo (feito uma vez, nao todo frame).
	local points: { Vector3 } = {}
	for i, p in PathService.getWaypoints() do
		points[i] = Vector3.new(p.X, Config.PATH_PREVIEW_HEIGHT, p.Z)
	end
	local data = PathMath.build(points)
	if data.total <= 0 then
		warn("PathPreview: caminho com tamanho zero, cubo desligado")
		return
	end

	-- Pasta "Debug" guarda coisas de teste, longe do mapa.
	local existing = workspace:FindFirstChild("Debug")
	local debugFolder: Instance
	if existing then
		debugFolder = existing
	else
		local folder = Instance.new("Folder")
		folder.Name = "Debug"
		folder.Parent = workspace
		debugFolder = folder
	end

	local cube = Instance.new("Part")
	cube.Name = "PathPreviewCube"
	cube.Size = Vector3.one * Config.PATH_PREVIEW_CUBE_SIZE
	cube.Material = Enum.Material.Neon
	cube.Color = Color3.fromRGB(255, 51, 153) -- rosa
	cube.Anchored = true -- sem fisica: nos movemos o cubo na mao
	cube.CanCollide = false
	cube.Position = points[1]

	-- Contorno ciano para o cubo aparecer bem de longe.
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.fromRGB(0, 240, 255)
	outline.Parent = cube

	cube.Parent = debugFolder

	-- Variaveis fora da funcao do Heartbeat: nada novo e criado a cada frame.
	local distance = 0
	local speed = Config.PATH_PREVIEW_SPEED
	local total = data.total

	-- ATENCAO: isto e so uma ferramenta de teste. Mover pecas no servidor a cada frame
	-- manda ~60 atualizacoes por segundo pra cada jogador. Nos inimigos de verdade
	-- (semana 2) o servidor guarda so a distancia e o cliente desenha o movimento.
	connection = RunService.Heartbeat:Connect(function(dt: number)
		-- Anda um pouco; ao passar do fim, volta ao comeco (loop).
		distance = (distance + speed * dt) % total
		cube.Position = PathMath.positionAt(data, distance)
	end)

	-- Se o cubo for destruido, solta a conexao (evita vazamento de memoria).
	cube.Destroying:Once(function()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end)
end

return PathPreview
