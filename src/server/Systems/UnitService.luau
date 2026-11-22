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
local UnitMath = require(Shared:WaitForChild("Util"):WaitForChild("UnitMath"))
local UnitModels = require(script.Parent.Parent:WaitForChild("Units"):WaitForChild("UnitModels"))

local UnitService = {}

local MAX_NAME_LENGTH = 16
local RATE_PER_SECOND = 4 -- maximo de PlaceUnit/UpgradeUnit/SellUnit por segundo (cada remote tem o seu balde)
local BURST = 4

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
	level: number, -- 1..MAX_UNIT_LEVEL
	spent: number, -- dinheiro total gasto nesta unidade (compra + upgrades); base do reembolso
	stats: UnitMath.UnitStats, -- dano/alcance/cooldown/habilidade do nivel atual
	attackCount: number, -- quantos ataques ja fez (para o Crit: a cada N-esimo)
}

type Bucket = { tokens: number, last: number }

local units: { [string]: Unit } = {} -- por id (nunca varremos o workspace)
local slotUnit: { [string]: string } = {} -- nome do slot -> id da unidade que ocupa
local unitCount: { [Player]: number } = {} -- quantas unidades cada jogador tem
local buckets: { [Player]: { [string]: Bucket } } = {} -- um balde por jogador POR remote
local slots: { [string]: BasePart } = {} -- cache dos slots (lidos uma vez no init)
local placementFolder: Instance? = nil
local container: Folder? = nil
local nextId = 0

local placeRemote: RemoteEvent? = nil
local placedRemote: RemoteEvent? = nil
local attackedRemote: RemoteEvent? = nil
local notifyRemote: RemoteEvent? = nil
local upgradeRemote: RemoteEvent? = nil
local sellRemote: RemoteEvent? = nil
local upgradedRemote: RemoteEvent? = nil
local soldRemote: RemoteEvent? = nil

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

-- "Balde de fichas": cada pedido gasta 1 ficha; as fichas voltam com o tempo.
-- "key" separa os baldes (spam de Sell nao atrapalha o Place do mesmo jogador).
local function allow(player: Player, key: string): boolean
	local now = os.clock()
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local bucket = playerBuckets[key]
	if not bucket then
		bucket = { tokens = BURST, last = now }
		playerBuckets[key] = bucket
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

-- O visual (modelo chibi de cada personagem) mora em src/server/Units/UnitModels.luau.
-- Aqui so pedimos para montar: mesmo contrato de antes (Root, Hitbox, frente = -Z).

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

-- Quando o estado saiu de Intermission pela ultima vez (os.clock). Serve para dar uma folga
-- na venda: o botao do cliente mostrava 100% no fim da pausa e o pedido chega um pouco depois.
local lastState: string? = nil
local leftIntermissionAt = -math.huge

local function onMatchStateChanged()
	local current = matchStateName()
	if lastState == "Intermission" and current ~= "Intermission" then
		leftIntermissionAt = os.clock()
	end
	lastState = current
end

-- Estado usado so para calcular o reembolso: dentro da folga ainda vale o de Intermission.
local function sellStateName(): string?
	local current = matchStateName()
	if current == "Wave" and os.clock() - leftIntermissionAt <= Config.SELL_GRACE_SECONDS then
		return "Intermission"
	end
	return current
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
	if not allow(player, "Place") then
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
	-- 7. Sem container nao da para criar a unidade: confere ANTES de gastar o dinheiro.
	local folder = container
	if not folder then
		return
	end
	-- 8. Dinheiro: trySpend confere e desconta numa tacada so.
	if not EconomyService.trySpend(player, def.cost) then
		notify(player, "Not enough cash!")
		return
	end

	-- Tudo certo: cria a unidade em cima do slot, virada para a estrada.
	nextId += 1
	local id = `U{nextId}`
	local ground = Vector3.new(slot.Position.X, slot.Position.Y + slot.Size.Y / 2, slot.Position.Z)
	local roadPoint = nearestRoadPoint(ground)
	local lookTarget = Vector3.new(roadPoint.X, ground.Y, roadPoint.Z)
	local baseCFrame = CFrame.new(ground)
	if (lookTarget - ground).Magnitude > 1e-3 then
		baseCFrame = CFrame.lookAt(ground, lookTarget)
	end

	local model, root = UnitModels.build(id, kind, UnitModels.lookFor(kind, def), baseCFrame)
	-- Atributos ANTES de parentar: o cliente ja ve tudo certo quando o modelo aparece.
	model:SetAttribute("Id", id)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Slot", slotName)
	model:SetAttribute("Level", 1)
	model:SetAttribute("Spent", def.cost)
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
		level = 1,
		spent = def.cost,
		stats = UnitMath.statsAt(def, 1),
		attackCount = 0,
	}

	if placedRemote then
		placedRemote:FireAllClients(id, kind, ground, player.UserId)
	end
end

-- Valida o comeco comum de Upgrade/Sell (passos 1 a 4). Devolve a unidade ou nil.
local function resolveOwnUnit(player: Player, key: string, id: unknown): Unit?
	-- 1. Limite de pedidos (silencioso).
	if not allow(player, key) then
		return nil
	end
	-- 2. Tipo e tamanho (silencioso: nao ajudamos exploiter).
	if typeof(id) ~= "string" or #id > MAX_NAME_LENGTH then
		return nil
	end
	-- 3. A unidade existe? (silencioso)
	local unit = units[id]
	if not unit then
		return nil
	end
	-- 4. E dele? O dono vem do SERVIDOR, nunca do cliente.
	if unit.owner ~= player then
		notify(player, "Not your unit")
		return nil
	end
	return unit
end

local function onUpgradeUnit(player: Player, id: unknown, fromLevel: unknown)
	local unit = resolveOwnUnit(player, "Upgrade", id)
	if not unit then
		return
	end
	-- Pedido velho (silencioso): o cliente viu outro nivel que o real, entao ja houve um upgrade.
	-- Sem isso, dois cliques rapidos comprariam dois niveis.
	if typeof(fromLevel) ~= "number" or fromLevel ~= unit.level then
		return
	end
	-- 5. So da para melhorar durante Intermission/Wave.
	local stateName = matchStateName()
	if stateName == nil or not Config.UPGRADE_ALLOWED_STATES[stateName] then
		notify(player, "Wait for the next round")
		return
	end
	-- 6. Nivel maximo?
	if unit.level >= Config.MAX_UNIT_LEVEL then
		notify(player, "Max level!")
		return
	end
	local cost = UnitMath.upgradeCost(unit.def, unit.level)
	if cost == nil then
		notify(player, "Max level!")
		return
	end
	-- 7. Dinheiro: trySpend confere e desconta de uma vez.
	if not EconomyService.trySpend(player, cost) then
		notify(player, "Not enough cash!")
		return
	end

	-- Tudo certo. nextAttack fica como esta (melhorar nao da ataque instantaneo de graca).
	unit.level += 1
	unit.stats = UnitMath.statsAt(unit.def, unit.level)
	unit.spent += cost
	unit.model:SetAttribute("Level", unit.level)
	unit.model:SetAttribute("Spent", unit.spent)
	-- No nivel maximo aparecem as pecas de evolucao (capa, chifres, coroa...).
	UnitModels.setLevel(unit.model, unit.level, Config.MAX_UNIT_LEVEL)
	if upgradedRemote then
		upgradedRemote:FireAllClients(unit.id, unit.level, unit.position)
	end
end

local function onSellUnit(player: Player, id: unknown)
	local unit = resolveOwnUnit(player, "Sell", id)
	if not unit then
		return
	end
	-- 5. Reembolso depende do estado (100% na pausa, 60% na onda, nil = nao pode).
	local refund = UnitMath.refundFor(unit.spent, sellStateName())
	if refund == nil then
		notify(player, "Can't sell right now")
		return
	end

	-- Guarda os dados ANTES de remover (o modelo some) e manda o tipo para o cliente achar a altura.
	local position = unit.position
	local unitId = unit.id
	local kind = unit.kind
	removeUnit(unit) -- libera o slot e a contagem
	EconomyService.add(player, refund)
	if soldRemote then
		soldRemote:FireAllClients(unitId, position, refund, player.UserId, kind)
	end
end

local function dist2dSq(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return dx * dx + dz * dz
end

-- Lista reaproveitada: alvos escolhidos por uma unidade (ordenados do mais avancado ao menos).
local targetBuffer: { Types.SnapshotEntry } = {}

-- Escolhe ate "maxTargets" inimigos DIFERENTES no alcance, os mais avancados primeiro.
-- Devolve quantos achou (os dados ficam em targetBuffer; sem criar tabelas novas).
local function collectTargets(
	unit: Unit,
	list: { Types.SnapshotEntry },
	count: number,
	maxTargets: number
): number
	local rangeSq = unit.stats.range * unit.stats.range
	local found = 0
	for i = 1, count do
		local enemy = list[i]
		if deadThisTick[enemy.id] or dist2dSq(enemy.position, unit.position) > rangeSq then
			continue
		end
		if found >= maxTargets and enemy.distance <= targetBuffer[found].distance then
			continue
		end
		-- Insercao ordenada (lista pequena): empurra os menos avancados para baixo.
		local slot = math.min(found + 1, maxTargets)
		while slot > 1 and targetBuffer[slot - 1].distance < enemy.distance do
			targetBuffer[slot] = targetBuffer[slot - 1]
			slot -= 1
		end
		targetBuffer[slot] = enemy
		found = math.min(found + 1, maxTargets)
	end
	return found
end

-- Fator de slow para este inimigo (chefes sao menos afetados).
local function slowFactorFor(kind: string, ability: Types.UnitAbility): number
	if Config.BOSS_KINDS[kind] then
		return Config.BOSS_SLOW_FACTOR
	end
	return ability.factor or 1
end

-- Um ataque contra UM alvo principal (mais dano em area e slow, se tiver).
local function strikeTarget(
	unit: Unit,
	target: Types.SnapshotEntry,
	list: { Types.SnapshotEntry },
	count: number
)
	local stats = unit.stats
	local ability = stats.ability
	local damage = stats.damage
	-- A spec so multiplica o dano do alvo principal: o splash fica com o dano base.
	local splashDamage = stats.damage
	local special: string? = nil
	if ability and ability.kind == "Crit" then
		-- Todo N-esimo ataque e critico.
		unit.attackCount += 1
		local every = ability.every or 1
		if unit.attackCount % every == 0 then
			damage *= ability.multiplier or 1
			special = "Crit"
		end
	end
	local slowAbility: Types.UnitAbility? = if ability and ability.kind == "Slow"
		then ability
		else nil

	local targetPosition = target.position
	local targetId = target.id
	EnemyService.damage(targetId, damage)
	if slowAbility then
		EnemyService.slow(
			targetId,
			slowFactorFor(target.kind, slowAbility),
			slowAbility.duration or 0
		)
		special = "Slow"
	end

	-- Dano em area: todo outro inimigo perto do ponto atingido.
	if stats.splashRadius > 0 then
		local splashSq = stats.splashRadius * stats.splashRadius
		for i = 1, count do
			local other = list[i]
			if
				other.id ~= targetId
				and not deadThisTick[other.id]
				and dist2dSq(other.position, targetPosition) <= splashSq
			then
				EnemyService.damage(other.id, splashDamage)
				if slowAbility then
					EnemyService.slow(
						other.id,
						slowFactorFor(other.kind, slowAbility),
						slowAbility.duration or 0
					)
				end
			end
		end
	end

	-- UM evento por alvo principal (o cliente desenha a area se for splash).
	if attackedRemote then
		attackedRemote:FireAllClients(unit.id, unit.kind, unit.muzzle, targetPosition, special)
	end
end

-- Um tick de combate: cada unidade pronta escolhe o(s) inimigo(s) mais avancado(s) no alcance.
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
		local ability = unit.stats.ability
		local maxTargets = 1
		if ability and ability.kind == "MultiShot" then
			maxTargets = math.max(1, ability.targets or 1)
		end
		local found = collectTargets(unit, list, count, maxTargets)
		if found == 0 then
			continue
		end

		-- Soma ao proximo ataque (nao ao "now") para a quantizacao do tick nao alongar o cooldown.
		unit.nextAttack = math.max(unit.nextAttack + unit.stats.cooldown, now)
		for i = 1, found do
			strikeTarget(unit, targetBuffer[i], list, count)
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
	upgradeRemote = Net.event("UpgradeUnit")
	sellRemote = Net.event("SellUnit")
	upgradedRemote = Net.event("UnitUpgraded")
	soldRemote = Net.event("UnitSold")

	if placeRemote then
		table.insert(connections, placeRemote.OnServerEvent:Connect(onPlaceUnit))
	end
	if upgradeRemote then
		table.insert(connections, upgradeRemote.OnServerEvent:Connect(onUpgradeUnit))
	end
	if sellRemote then
		table.insert(connections, sellRemote.OnServerEvent:Connect(onSellUnit))
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
	local matchFolder = ReplicatedStorage:FindFirstChild("MatchState")
	if matchFolder then
		lastState = matchStateName()
		table.insert(
			connections,
			matchFolder:GetAttributeChangedSignal("State"):Connect(onMatchStateChanged)
		)
	end
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
