--!strict
-- UnitService: unidades (torres) dos jogadores.
-- Faz: validar PlaceUnit, criar o visual, marcar slots e rodar o combate a 10 Hz.
-- Unidades nunca se movem. O servidor decide TUDO (dano, alvo, dinheiro);
-- o cliente so recebe eventos para desenhar os efeitos.
-- Este modulo NAO pode dar require no MatchService (evita require circular):
-- o estado da partida e lido direto do atributo ReplicatedStorage.MatchState.State.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Types = require(Shared:WaitForChild("Types"))

local EnemyService = require(script.Parent.EnemyService)
local EconomyService = require(script.Parent.EconomyService)
local PathService = require(script.Parent.PathService)

local UnitService = {}

local MAX_NAME_LENGTH = 16
local RATE_PER_SECOND = 4 -- maximo de PlaceUnit por segundo por jogador
local BURST = 4
local PEDESTAL_HEIGHT = 0.3

type Unit = {
	id: string,
	kind: string,
	def: Types.UnitDef,
	owner: Player,
	slotName: string,
	model: Model,
	position: Vector3, -- pe da unidade (usado no alcance, plano XZ)
	muzzle: Vector3, -- de onde sai o ataque
	nextAttack: number, -- os.clock() em que pode atacar de novo
}

type Bucket = { tokens: number, last: number }

local units: { [string]: Unit } = {} -- por id (nunca varremos o workspace)
local slotUnit: { [string]: string } = {} -- nome do slot -> id da unidade que ocupa
local unitCount: { [Player]: number } = {} -- quantas unidades cada jogador tem
local buckets: { [Player]: Bucket } = {}
local slots: { [string]: BasePart } = {} -- cache dos slots (lidos uma vez no init)
local placementFolder: Instance? = nil
local container: Folder? = nil
local nextId = 0

local placeRemote: RemoteEvent? = nil
local placedRemote: RemoteEvent? = nil
local attackedRemote: RemoteEvent? = nil
local notifyRemote: RemoteEvent? = nil

local connections: { RBXScriptConnection } = {}
local cleanups: { () -> () } = {}
local tickConnection: RBXScriptConnection? = nil

-- Ids de inimigos mortos neste tick (o retrato do EnemyService nao sabe que morreram).
local deadThisTick: { [string]: boolean } = {}

local function notify(player: Player, text: string)
	if notifyRemote then
		notifyRemote:FireClient(player, text)
	end
end

-- "Balde de fichas": cada PlaceUnit gasta 1 ficha; as fichas voltam com o tempo.
local function allow(player: Player): boolean
	local now = os.clock()
	local bucket = buckets[player]
	if not bucket then
		bucket = { tokens = BURST, last = now }
		buckets[player] = bucket
	end
	bucket.tokens = math.min(BURST, bucket.tokens + (now - bucket.last) * RATE_PER_SECOND)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- Ponto da estrada (plano XZ) mais perto de "from". A unidade olha para la.
local function nearestRoadPoint(from: Vector3): Vector3
	local data = PathService.getPathData()
	local best = from
	local bestDistSq = math.huge
	for i = 1, #data.points - 1 do
		local a = data.points[i]
		local b = data.points[i + 1]
		local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local lenSq = ab.X * ab.X + ab.Z * ab.Z
		local t = 0
		if lenSq > 1e-6 then
			t = math.clamp(((from.X - a.X) * ab.X + (from.Z - a.Z) * ab.Z) / lenSq, 0, 1)
		end
		local point = Vector3.new(a.X + ab.X * t, 0, a.Z + ab.Z * t)
		local dx = point.X - from.X
		local dz = point.Z - from.Z
		local distSq = dx * dx + dz * dz
		if distSq < bestDistSq then
			bestDistSq = distSq
			best = point
		end
	end
	return best
end

-- Peca de enfeite soldada ao Root. offset e relativo ao "baseCFrame" (o chao, ja virado).
local function decorate(
	model: Model,
	root: BasePart,
	baseCFrame: CFrame,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	neon: boolean,
	offset: CFrame
)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CFrame = baseCFrame * offset
	part.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

-- Disco achatado (cilindro deitado para ficar "em pe" no eixo Y).
local FLAT = CFrame.Angles(0, 0, math.pi / 2)

-- Monta o visual low-poly. baseCFrame fica no chao (topo do slot), olhando para a estrada.
-- O Root e um pedestal fino no chao; corpo, cabeca e acessorios sao soldados nele.
local function buildModel(id: string, kind: string, def: Types.UnitDef, baseCFrame: CFrame): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Shape = Enum.PartType.Cylinder
	root.Size = Vector3.new(PEDESTAL_HEIGHT, 3.2, 3.2)
	root.Color = def.accentColor
	root.Material = Enum.Material.Neon
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = baseCFrame * CFrame.new(0, PEDESTAL_HEIGHT / 2, 0) * FLAT
	root.Parent = model
	model.PrimaryPart = root

	local h = def.height
	local bodyH = h * 0.45
	local headD = h * 0.28
	local bodyY = PEDESTAL_HEIGHT + bodyH / 2
	local headY = PEDESTAL_HEIGHT + bodyH + headD * 0.45
	local headTop = headY + headD / 2
	local ball = Enum.PartType.Ball
	local block = Enum.PartType.Block
	local cyl = Enum.PartType.Cylinder

	-- Corpo e cabeca (iguais para todos; so a cor muda).
	decorate(model, root, baseCFrame, "Body", block, Vector3.new(2.1, bodyH, 1.5), def.color, false, CFrame.new(0, bodyY, 0))
	decorate(model, root, baseCFrame, "Head", ball, Vector3.new(headD, headD, headD), def.color, false, CFrame.new(0, headY, 0))

	if kind == "Ninja" then
		-- Faixa neon na cabeca + cachecol neon com ponta solta atras (+Z = costas).
		decorate(
			model, root, baseCFrame, "Headband", block,
			Vector3.new(headD * 1.06, 0.25, headD * 1.06), def.accentColor, true,
			CFrame.new(0, headY + headD * 0.1, 0)
		)
		decorate(
			model, root, baseCFrame, "Scarf", block,
			Vector3.new(1.7, 0.35, 1.7), def.accentColor, true,
			CFrame.new(0, PEDESTAL_HEIGHT + bodyH + 0.05, 0)
		)
		decorate(
			model, root, baseCFrame, "ScarfTail", block,
			Vector3.new(0.4, 0.2, 1.4), def.accentColor, true,
			CFrame.new(0.5, PEDESTAL_HEIGHT + bodyH, 1.2) * CFrame.Angles(0.5, 0, 0)
		)
	elseif kind == "Samurai" then
		-- Chapeu largo (disco) + katana neon ao lado.
		decorate(
			model, root, baseCFrame, "Hat", cyl,
			Vector3.new(0.4, headD * 2.3, headD * 2.3), def.color:Lerp(Color3.new(0, 0, 0), 0.35), false,
			CFrame.new(0, headTop - 0.05, 0) * FLAT
		)
		decorate(
			model, root, baseCFrame, "Katana", block,
			Vector3.new(0.18, h * 0.75, 0.18), def.accentColor, true,
			CFrame.new(1.5, PEDESTAL_HEIGHT + bodyH * 0.8, -0.2) * CFrame.Angles(0, 0, -0.25)
		)
	elseif kind == "Mage" then
		-- Chapeu "cone" feito de 3 discos que diminuem + orbe neon flutuando.
		local widths = { headD * 1.9, headD * 1.4, headD * 0.8 }
		for i, width in widths do
			decorate(
				model, root, baseCFrame, "HatPart" .. tostring(i), cyl,
				Vector3.new(0.45, width, width), def.color:Lerp(Color3.new(0, 0, 0), 0.25), false,
				CFrame.new(0, headTop + (i - 1) * 0.42, 0) * FLAT
			)
		end
		decorate(
			model, root, baseCFrame, "Orb", ball,
			Vector3.new(1.1, 1.1, 1.1), def.accentColor, true,
			CFrame.new(1.6, PEDESTAL_HEIGHT + bodyH + 0.6, 0)
		)
	end

	return model, root
end

local function matchStateName(): string?
	local folder = ReplicatedStorage:FindFirstChild("MatchState")
	if not folder then
		return nil
	end
	local value = folder:GetAttribute("State")
	if typeof(value) == "string" then
		return value
	end
	return nil
end

-- Destroi uma unidade e libera o slot dela.
local function removeUnit(unit: Unit)
	units[unit.id] = nil
	if slotUnit[unit.slotName] == unit.id then
		slotUnit[unit.slotName] = nil
		local slot = slots[unit.slotName]
		if slot then
			slot:SetAttribute("Occupied", false)
		end
	end
	local count = unitCount[unit.owner]
	if count then
		unitCount[unit.owner] = math.max(0, count - 1)
	end
	unit.model:Destroy()
end

local function onPlaceUnit(player: Player, kind: unknown, slotName: unknown)
	-- 1. Limite de pedidos (antes de tudo: nem gasta CPU com spam).
	if not allow(player) then
		return
	end
	-- 2. Tipos e tamanhos. Pedido malformado e descartado em silencio (nao ajudamos exploiter).
	if typeof(kind) ~= "string" or typeof(slotName) ~= "string" then
		return
	end
	if #kind > MAX_NAME_LENGTH or #slotName > MAX_NAME_LENGTH then
		return
	end
	-- 3. O tipo existe? O custo vem do Config do SERVIDOR, nunca do cliente.
	local def = Config.UNITS[kind]
	if not def then
		return
	end
	-- 4. A partir daqui o jogador recebe um aviso do motivo.
	local stateName = matchStateName()
	if stateName == nil or not Config.PLACE_ALLOWED_STATES[stateName] then
		notify(player, "Wait for the next round")
		return
	end
	-- 5. O slot existe e e uma Part do mapa?
	local slot = slots[slotName]
	if not slot or slot.Parent ~= placementFolder then
		return
	end
	if slotUnit[slotName] ~= nil or slot:GetAttribute("Occupied") == true then
		notify(player, "Slot taken")
		return
	end
	-- 6. Limite de unidades por jogador.
	local count = unitCount[player] or 0
	if count >= Config.MAX_UNITS_PER_PLAYER then
		notify(player, "Unit limit reached")
		return
	end
	-- 7. Dinheiro: trySpend confere e desconta numa tacada so.
	if not EconomyService.trySpend(player, def.cost) then
		notify(player, "Not enough cash!")
		return
	end

	-- Tudo certo: cria a unidade em cima do slot, virada para a estrada.
	local folder = container
	if not folder then
		return
	end
	nextId += 1
	local id = `U{nextId}`
	local ground = Vector3.new(slot.Position.X, slot.Position.Y + slot.Size.Y / 2, slot.Position.Z)
	local roadPoint = nearestRoadPoint(ground)
	local lookTarget = Vector3.new(roadPoint.X, ground.Y, roadPoint.Z)
	local baseCFrame = CFrame.new(ground)
	if (lookTarget - ground).Magnitude > 1e-3 then
		baseCFrame = CFrame.lookAt(ground, lookTarget)
	end

	local model, root = buildModel(id, kind, def, baseCFrame)
	-- Atributos ANTES de parentar: o cliente ja ve tudo certo quando o modelo aparece.
	model:SetAttribute("Id", id)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Slot", slotName)
	model.Parent = folder

	slot:SetAttribute("Occupied", true)
	slotUnit[slotName] = id
	unitCount[player] = count + 1
	units[id] = {
		id = id,
		kind = kind,
		def = def,
		owner = player,
		slotName = slotName,
		model = model,
		position = ground,
		muzzle = root.Position + Vector3.yAxis * def.height * 0.7,
		nextAttack = 0,
	}

	if placedRemote then
		placedRemote:FireAllClients(id, kind, ground, player.UserId)
	end
end

local function dist2dSq(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return dx * dx + dz * dz
end

-- Um tick de combate: cada unidade pronta escolhe o inimigo mais avancado no alcance.
local function combatTick()
	if next(units) == nil then
		return
	end
	local list, count = EnemyService.snapshot() -- UMA vez por tick
	if count == 0 then
		return
	end
	table.clear(deadThisTick)
	local now = os.clock()

	for _, unit in units do
		if now < unit.nextAttack then
			continue
		end
		local def = unit.def
		local rangeSq = def.range * def.range

		-- Alvo = "first": o inimigo com MAIOR distancia andada que esta no alcance.
		local target: Types.SnapshotEntry? = nil
		local bestDistance = -1
		for i = 1, count do
			local enemy = list[i]
			if
				not deadThisTick[enemy.id]
				and enemy.distance > bestDistance
				and dist2dSq(enemy.position, unit.position) <= rangeSq
			then
				target = enemy
				bestDistance = enemy.distance
			end
		end
		if not target then
			continue
		end

		unit.nextAttack = now + def.cooldown
		local targetPosition = target.position
		local targetId = target.id
		EnemyService.damage(targetId, def.damage)

		-- Dano em area: todo outro inimigo perto do ponto atingido.
		if def.splashRadius > 0 then
			local splashSq = def.splashRadius * def.splashRadius
			for i = 1, count do
				local other = list[i]
				if
					other.id ~= targetId
					and not deadThisTick[other.id]
					and dist2dSq(other.position, targetPosition) <= splashSq
				then
					EnemyService.damage(other.id, def.damage)
				end
			end
		end

		-- UM evento por ataque (o cliente desenha a area se for splash).
		if attackedRemote then
			attackedRemote:FireAllClients(unit.id, unit.kind, unit.muzzle, targetPosition)
		end
	end
end

function UnitService.init()
	local folder = Instance.new("Folder")
	folder.Name = "Units"
	folder.Parent = workspace
	container = folder

	-- Le os slots UMA vez (o mapa ja vem pronto; init nao pode esperar/yieldar).
	local map = workspace:FindFirstChild("Map")
	assert(map, "UnitService: nao achei workspace.Map")
	local placement = map:FindFirstChild("Placement")
	assert(placement, "UnitService: nao achei workspace.Map.Placement")
	placementFolder = placement
	for _, child in placement:GetChildren() do
		if child:IsA("BasePart") then
			slots[child.Name] = child
			child:SetAttribute("Occupied", false)
		end
	end

	placeRemote = Net.event("PlaceUnit")
	placedRemote = Net.event("UnitPlaced")
	attackedRemote = Net.event("UnitAttacked")
	notifyRemote = Net.event("Notify")

	if placeRemote then
		table.insert(connections, placeRemote.OnServerEvent:Connect(onPlaceUnit))
	end

	-- Jogador saiu: some com as unidades dele (senao o slot ficaria preso) e com o balde.
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			local mine: { Unit } = {}
			for _, unit in units do
				if unit.owner == player then
					table.insert(mine, unit)
				end
			end
			for _, unit in mine do
				removeUnit(unit)
			end
			unitCount[player] = nil
			buckets[player] = nil
		end)
	)

	-- Quem morreu neste tick nao pode ser alvo de outra unidade.
	table.insert(
		cleanups,
		EnemyService.onEnemyRemoved(function(id: string, reason: Types.DeathReason)
			if reason == "Killed" then
				deadThisTick[id] = true
			end
		end)
	)
end

function UnitService.start()
	if tickConnection then
		return
	end
	-- Acumula o tempo do Heartbeat e roda o combate 10x por segundo.
	local interval = 1 / Config.SERVER_TICK_RATE
	local accumulated = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt: number)
		accumulated += dt
		if accumulated < interval then
			return
		end
		accumulated %= interval
		combatTick()
	end)
end

-- Apaga todas as unidades, libera os slots e zera as contagens (sem eventos).
function UnitService.clearAll()
	for _, unit in units do
		unit.model:Destroy()
	end
	table.clear(units)
	table.clear(slotUnit)
	table.clear(unitCount)
	for _, slot in slots do
		slot:SetAttribute("Occupied", false)
	end
end

function UnitService.countOf(player: Player): number
	return unitCount[player] or 0
end

-- Limpeza explicita (nao usada no jogo normal).
function UnitService.destroy()
	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, cleanup in cleanups do
		cleanup()
	end
	table.clear(cleanups)
	table.clear(buckets)
end

return UnitService
