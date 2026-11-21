--!strict
-- EnemyRenderer: move os inimigos NA TELA de cada jogador.
-- O servidor nao move inimigos todo frame. Cada inimigo guarda BaseDistance, BaseTime e Speed,
-- e a distancia agora e: BaseDistance + Speed * (agora - BaseTime).
-- Aqui, todo frame, calculamos isso e movemos a copia local do modelo com PivotTo.
-- Tambem desenhamos a barra de vida e um flash branco quando o inimigo leva dano.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- WaitForChild: no cliente, as pastas podem chegar um pouco depois do script rodar.
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local PathMath = require(Shared:WaitForChild("Util"):WaitForChild("PathMath"))
local EnemyMath = require(Shared:WaitForChild("Util"):WaitForChild("EnemyMath"))

local BOB_SPEED = 6 -- velocidade do balanco (radianos por segundo)
local BOB_HEIGHT = 0.35 -- altura do balanco em studs
local BAR_COLOR_LOW = Color3.fromRGB(255, 50, 70)
local BAR_COLOR_HIGH = Color3.fromRGB(120, 255, 90)
local BAR_BACK_COLOR = Color3.fromRGB(20, 12, 40)
local FILL_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Tudo que sabemos de um inimigo fica numa tabela so (evita procurar atributos todo frame).
type Entry = {
	model: Model,
	root: BasePart?,
	baseDistance: number,
	baseTime: number,
	speed: number,
	heightOffset: number,
	phase: number, -- cada inimigo balanca em um ritmo diferente
	health: number,
	maxHealth: number,
	billboard: BillboardGui?,
	fill: Frame?,
	highlight: Highlight?,
	flashTween: Tween?,
	fillTween: Tween?,
	connections: { RBXScriptConnection },
	alive: boolean,
}

local EnemyRenderer = {}

local entries: { [Model]: Entry } = {}
local pathData: Types.PathData? = nil
local globalConnections: { RBXScriptConnection } = {}

local function getNumber(inst: Instance, name: string, default: number): number
	local value = inst:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end
	return default
end

local function readMotion(entry: Entry)
	local model = entry.model
	entry.baseDistance = getNumber(model, "BaseDistance", 0)
	entry.baseTime = getNumber(model, "BaseTime", workspace:GetServerTimeNow())
	entry.speed = getNumber(model, "Speed", 0)
	entry.heightOffset = getNumber(model, "HeightOffset", 0)
end

-- Cria o flash branco (Highlight) so na primeira vez que o inimigo leva dano.
local function flash(entry: Entry)
	local highlight = entry.highlight
	if not highlight then
		local created = Instance.new("Highlight")
		created.Name = "HitFlash"
		created.Adornee = entry.model
		created.FillColor = Color3.new(1, 1, 1)
		created.FillTransparency = 1
		created.OutlineTransparency = 1
		created.Enabled = false
		created.Parent = entry.model
		entry.highlight = created
		highlight = created
	end

	local old = entry.flashTween
	if old then
		old:Cancel()
	end
	highlight.Enabled = true
	highlight.FillTransparency = 0.15
	local tween = TweenService:Create(highlight, FLASH_INFO, { FillTransparency = 1 })
	entry.flashTween = tween
	local shown = highlight
	tween.Completed:Once(function()
		-- So desliga se ainda for o nosso tween (outro flash pode ter comecado).
		if entry.alive and entry.flashTween == tween then
			shown.Enabled = false
		end
	end)
	tween:Play()
end

local function updateHealth(entry: Entry, animate: boolean)
	local newHealth = getNumber(entry.model, "Health", entry.health)
	local maxHealth = math.max(1, getNumber(entry.model, "MaxHealth", entry.maxHealth))
	local tookDamage = newHealth < entry.health
	entry.health = newHealth
	entry.maxHealth = maxHealth

	local ratio = math.clamp(newHealth / maxHealth, 0, 1)
	local billboard = entry.billboard
	local fill = entry.fill
	if billboard and fill then
		-- A barra so aparece depois do primeiro dano (menos coisa na tela).
		billboard.Enabled = ratio < 1 and ratio > 0
		local goal = {
			Size = UDim2.fromScale(ratio, 1),
			BackgroundColor3 = BAR_COLOR_LOW:Lerp(BAR_COLOR_HIGH, ratio),
		}
		local old = entry.fillTween
		if old then
			old:Cancel()
		end
		if animate then
			local tween = TweenService:Create(fill, FILL_INFO, goal)
			entry.fillTween = tween
			tween:Play()
		else
			fill.Size = goal.Size
			fill.BackgroundColor3 = goal.BackgroundColor3
		end
	end

	if tookDamage and animate then
		flash(entry)
	end
end

-- Monta a barra de vida (BillboardGui) em cima do inimigo. Tamanho em studs (Scale).
local function buildBar(entry: Entry, root: BasePart)
	local width = math.clamp(root.Size.X * 1.3, 3, 8)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Adornee = root
	billboard.Size = UDim2.fromScale(width, 0.55)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, root.Size.Y / 2 + 1.5, 0)
	billboard.MaxDistance = 120 -- longe demais nao precisa desenhar
	billboard.AlwaysOnTop = false
	billboard.Active = false
	billboard.Enabled = false
	billboard.Parent = root

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = BAR_BACK_COLOR
	back.BorderSizePixel = 0
	back.Parent = billboard

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0.5, 0)
	backCorner.Parent = back

	local backStroke = Instance.new("UIStroke")
	backStroke.Color = Color3.new(1, 1, 1)
	backStroke.Thickness = 1
	backStroke.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = BAR_COLOR_HIGH
	fill.BorderSizePixel = 0
	fill.Parent = back

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	entry.billboard = billboard
	entry.fill = fill
	updateHealth(entry, false)
end

local function track(model: Model)
	if entries[model] then
		return
	end

	local entry: Entry = {
		model = model,
		root = nil,
		baseDistance = 0,
		baseTime = workspace:GetServerTimeNow(),
		speed = 0,
		heightOffset = 0,
		phase = math.random() * math.pi * 2,
		health = getNumber(model, "Health", 1),
		maxHealth = getNumber(model, "MaxHealth", 1),
		billboard = nil,
		fill = nil,
		highlight = nil,
		flashTween = nil,
		fillTween = nil,
		connections = {},
		alive = true,
	}
	entries[model] = entry
	readMotion(entry)

	-- Um unico listener de atributos por inimigo: vida OU movimento (ex.: lentidao = "rebase").
	table.insert(
		entry.connections,
		model.AttributeChanged:Connect(function(name: string)
			if name == "Health" or name == "MaxHealth" then
				updateHealth(entry, true)
			else
				readMotion(entry)
			end
		end)
	)

	-- O Root pode demorar para chegar (streaming), entao esperamos sem travar o resto.
	task.spawn(function()
		local rootInst = model:WaitForChild("Root", 10)
		if not entry.alive then
			return
		end
		if rootInst and rootInst:IsA("BasePart") then
			entry.root = rootInst
			buildBar(entry, rootInst)
		end
	end)
end

local function untrack(model: Model)
	local entry = entries[model]
	if not entry then
		return
	end
	entry.alive = false
	entries[model] = nil

	for _, connection in entry.connections do
		connection:Disconnect()
	end
	table.clear(entry.connections)

	if entry.flashTween then
		entry.flashTween:Cancel()
	end
	if entry.fillTween then
		entry.fillTween:Cancel()
	end
	-- O modelo pode so ter saido do streaming (nao destruido): limpamos o que criamos.
	if entry.billboard then
		entry.billboard:Destroy()
	end
	if entry.highlight then
		entry.highlight:Destroy()
	end
end

-- Roda todo frame. Nada de criar tabelas aqui (so numeros e Vector3/CFrame).
local function onRenderStep()
	local data = pathData
	if not data then
		return
	end
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	for _, entry in entries do
		if entry.root then
			local distance = EnemyMath.distanceAt(entry.baseDistance, entry.baseTime, entry.speed, now)
			-- (sin * 0.5 + 0.5) vai de 0 a 1: o inimigo so sobe, nunca afunda no chao.
			-- O 0.1 extra deixa ele acima da estrada (que tem 0.1 de altura).
			local bob = 0.1 + (math.sin(clock * BOB_SPEED + entry.phase) * 0.5 + 0.5) * BOB_HEIGHT
			local position = PathMath.positionAt(data, distance) + Vector3.new(0, entry.heightOffset + bob, 0)
			local direction = PathMath.directionAt(data, distance)
			entry.model:PivotTo(CFrame.lookAt(position, position + direction))
		end
	end
end

function EnemyRenderer.init() end

function EnemyRenderer.start()
	-- 1) Caminho: montado a partir da pasta replicada (nunca do workspace, que pode "sumir").
	local pointsFolder = ReplicatedStorage:WaitForChild("PathPoints", 30)
	if not pointsFolder then
		warn("[EnemyRenderer] PathPoints nao apareceu em 30s.")
		return
	end

	local indexed: { { index: number, position: Vector3 } } = {}
	for _, child in pointsFolder:GetChildren() do
		local index = tonumber(child.Name)
		if index and child:IsA("Vector3Value") then
			table.insert(indexed, { index = index, position = child.Value })
		end
	end
	table.sort(indexed, function(a, b)
		return a.index < b.index
	end)
	local points: { Vector3 } = {}
	for _, item in indexed do
		table.insert(points, item.position)
	end
	if #points < 2 then
		warn("[EnemyRenderer] caminho com menos de 2 pontos.")
		return
	end
	pathData = PathMath.build(points)

	-- 2) Inimigos: os que ja existem + os que chegarem/sairem depois.
	local enemiesInst = workspace:WaitForChild("Enemies", 30)
	if not enemiesInst then
		warn("[EnemyRenderer] workspace.Enemies nao apareceu em 30s.")
		return
	end

	table.insert(
		globalConnections,
		enemiesInst.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Model") then
				track(child)
			end
		end)
	)
	table.insert(
		globalConnections,
		enemiesInst.ChildRemoved:Connect(function(child: Instance)
			if child:IsA("Model") then
				untrack(child)
			end
		end)
	)
	for _, child in enemiesInst:GetChildren() do
		if child:IsA("Model") then
			track(child)
		end
	end

	table.insert(globalConnections, RunService.RenderStepped:Connect(onRenderStep))
end

-- Desliga tudo (nao usado no jogo normal, mas deixa a limpeza explicita).
function EnemyRenderer.destroy()
	for _, connection in globalConnections do
		connection:Disconnect()
	end
	table.clear(globalConnections)
	for model in entries do
		untrack(model)
	end
end

return EnemyRenderer
