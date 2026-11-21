--!strict
-- EnemyService: cria, guarda e remove os inimigos.
-- IDEIA CENTRAL: o servidor NAO move inimigos todo frame. Cada inimigo guarda
-- (BaseDistance, BaseTime, Speed) e a distancia agora e:
--   BaseDistance + Speed * (agora - BaseTime)
-- O servidor confere isso 10 vezes por segundo (so para saber se chegou ao fim).
-- Cada cliente calcula a mesma formula todo frame e move a sua copia local do modelo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Types = require(Shared:WaitForChild("Types"))
local PathMath = require(Shared:WaitForChild("Util"):WaitForChild("PathMath"))
local EnemyMath = require(Shared:WaitForChild("Util"):WaitForChild("EnemyMath"))

local PathService = require(script.Parent.PathService)
local BaseService = require(script.Parent.BaseService)

local EnemyService = {}

type Enemy = {
	model: Model,
	kind: string,
	health: number,
	maxHealth: number,
	speed: number,
	baseDistance: number,
	baseTime: number,
	baseDamage: number,
	reward: number,
	heightOffset: number,
}

-- reward: o que o inimigo vale (0 se vazou). Quem so quer id/reason pode ignorar o resto.
type RemovedCallback = (id: string, reason: Types.DeathReason, reward: number) -> ()

-- Tabela por id: assim nunca precisamos varrer o workspace a cada tick.
local enemies: { [string]: Enemy } = {}
local aliveCount = 0
local nextId = 0
local container: Folder? = nil
local diedRemote: RemoteEvent? = nil
local tickConnection: RBXScriptConnection? = nil
local removedListeners: { RemovedCallback } = {}

-- Lista reaproveitada a cada tick (evita criar uma tabela nova 10x por segundo).
local leakedBuffer: { string } = {}

-- Lista reaproveitada do snapshot(): as linhas sao tabelas fixas que so tem os campos reescritos.
local snapshotBuffer: { Types.SnapshotEntry } = {}

local HORN_COLOR = Color3.fromRGB(235, 228, 205)

-- Cria uma peca de enfeite soldada ao Root.
local function makeDecoration(name: string, root: BasePart, size: Vector3, color: Color3, offset: CFrame, neon: boolean)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false -- so o Root e clicavel
	part.CFrame = root.CFrame * offset
	part.Parent = root.Parent
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

-- Monta o visual "demonio": corpo em bloco + 2 olhos Neon + chifres (Tank/Oni).
-- Feito pelo SERVIDOR uma vez no spawn; depois so os clientes movem a copia local.
local function buildModel(id: string, kind: string, def: Types.EnemyDef, startCFrame: CFrame): Model
	local model = Instance.new("Model")
	model.Name = id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = def.size
	root.Color = def.color
	root.Material = Enum.Material.SmoothPlastic
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = true -- clicavel (debug)
	root.CFrame = startCFrame
	root.Parent = model
	model.PrimaryPart = root

	-- Olhos na frente (a frente do CFrame.lookAt e o eixo -Z).
	local eye = math.max(0.35, def.size.X * 0.14)
	local eyeSize = Vector3.new(eye, eye, eye * 0.6)
	for _, side in { -1, 1 } do
		makeDecoration(
			"Eye",
			root,
			eyeSize,
			def.eyeColor,
			CFrame.new(side * def.size.X * 0.22, def.size.Y * 0.15, -def.size.Z / 2),
			true
		)
	end

	if def.horns then
		local hornHeight = def.size.Y * 0.35
		local hornWidth = math.max(0.4, def.size.X * 0.12)
		for _, side in { -1, 1 } do
			makeDecoration(
				"Horn",
				root,
				Vector3.new(hornWidth, hornHeight, hornWidth),
				HORN_COLOR,
				CFrame.new(side * def.size.X * 0.3, def.size.Y / 2 + hornHeight / 2 - 0.05, 0)
					* CFrame.Angles(0, 0, -side * 0.3),
				false
			)
		end
	end

	return model
end

-- Remove o inimigo da tabela, destroi o modelo e avisa quem escuta.
local function remove(id: string, reason: Types.DeathReason)
	local enemy = enemies[id]
	if not enemy then
		return
	end
	enemies[id] = nil
	aliveCount -= 1
	enemy.model:Destroy()
	-- Vazou nao da dinheiro; so quem foi morto vale a recompensa.
	local reward = if reason == "Killed" then enemy.reward else 0
	for _, callback in removedListeners do
		callback(id, reason, reward)
	end
end

local function currentDistance(enemy: Enemy, now: number): number
	return EnemyMath.distanceAt(enemy.baseDistance, enemy.baseTime, enemy.speed, now)
end

-- Posicao do centro do inimigo (para os efeitos dos clientes).
local function centerPosition(enemy: Enemy, distance: number): Vector3
	return PathMath.positionAt(PathService.getPathData(), distance) + Vector3.yAxis * enemy.heightOffset
end

local function fireDied(id: string, reason: Types.DeathReason, position: Vector3, reward: number)
	if diedRemote then
		diedRemote:FireAllClients(id, reason, position, reward)
	end
end

function EnemyService.init()
	local folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = workspace
	container = folder
	diedRemote = Net.event("EnemyDied")
end

-- Cria um inimigo no inicio do caminho. Devolve o id, ou nil se nao puder criar.
function EnemyService.spawn(kind: string): string?
	local folder = container
	if not folder then
		return nil
	end
	local def = Config.ENEMIES[kind]
	if not def then
		warn(`EnemyService.spawn: tipo desconhecido "{kind}"`)
		return nil
	end
	if aliveCount >= Config.MAX_ENEMIES_ALIVE then
		return nil -- limite de seguranca
	end

	nextId += 1
	local id = `E{nextId}`
	local data = PathService.getPathData()
	local heightOffset = def.size.Y / 2
	local startPos = PathMath.positionAt(data, 0) + Vector3.yAxis * heightOffset
	local startCFrame = CFrame.lookAt(startPos, startPos + PathMath.directionAt(data, 0))
	local now = workspace:GetServerTimeNow()

	local model = buildModel(id, kind, def, startCFrame)
	model:SetAttribute("Id", id)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Health", def.health)
	model:SetAttribute("MaxHealth", def.health)
	model:SetAttribute("Speed", def.speed)
	model:SetAttribute("BaseDistance", 0)
	model:SetAttribute("BaseTime", now)
	model:SetAttribute("HeightOffset", heightOffset)
	model.Parent = folder

	enemies[id] = {
		model = model,
		kind = kind,
		health = def.health,
		maxHealth = def.health,
		speed = def.speed,
		baseDistance = 0,
		baseTime = now,
		baseDamage = def.baseDamage,
		reward = def.reward,
		heightOffset = heightOffset,
	}
	aliveCount += 1
	return id
end

-- Tira vida do inimigo. Se chegar a 0: avisa os clientes (Killed) e remove.
function EnemyService.damage(id: string, amount: number)
	local enemy = enemies[id]
	if not enemy then
		return
	end
	if amount ~= amount or amount <= 0 then
		return
	end
	enemy.health = math.max(0, enemy.health - amount)
	enemy.model:SetAttribute("Health", enemy.health)
	if enemy.health <= 0 then
		local position = centerPosition(enemy, currentDistance(enemy, workspace:GetServerTimeNow()))
		fireDied(id, "Killed", position, enemy.reward)
		remove(id, "Killed")
	end
end

-- Muda a velocidade fazendo "rebase": guarda onde o inimigo esta AGORA como nova base.
-- Sem isso, o inimigo daria um pulo para tras/frente quando a velocidade mudasse.
function EnemyService.setSpeed(id: string, speed: number)
	local enemy = enemies[id]
	if not enemy then
		return
	end
	if speed ~= speed or speed < 0 then
		return
	end
	local now = workspace:GetServerTimeNow()
	enemy.baseDistance = currentDistance(enemy, now)
	enemy.baseTime = now
	enemy.speed = speed
	-- Ordem nao importa para o cliente: ele le tudo do mesmo jeito (atributos replicam juntos).
	enemy.model:SetAttribute("BaseDistance", enemy.baseDistance)
	enemy.model:SetAttribute("BaseTime", now)
	enemy.model:SetAttribute("Speed", speed)
end

function EnemyService.getDistance(id: string): number?
	local enemy = enemies[id]
	if not enemy then
		return nil
	end
	return currentDistance(enemy, workspace:GetServerTimeNow())
end

-- "Retrato" dos inimigos vivos para o combate das unidades (chamado 10x por segundo).
-- Devolve (lista, quantidade). So as primeiras "quantidade" linhas valem: o resto e lixo
-- de chamadas anteriores. A lista e REUSADA, entao nao guarde ela entre ticks.
function EnemyService.snapshot(): ({ Types.SnapshotEntry }, number)
	local now = workspace:GetServerTimeNow()
	local count = 0
	for id, enemy in enemies do
		count += 1
		local distance = currentDistance(enemy, now)
		local entry = snapshotBuffer[count]
		if not entry then
			entry = { id = id, distance = distance, position = Vector3.zero }
			snapshotBuffer[count] = entry
		end
		entry.id = id
		entry.distance = distance
		entry.position = centerPosition(enemy, distance)
	end
	return snapshotBuffer, count
end

-- Remove todos sem disparar eventos (usado ao terminar/reiniciar a partida).
function EnemyService.clearAll()
	for id, enemy in enemies do
		enemies[id] = nil
		enemy.model:Destroy()
	end
	aliveCount = 0
end

function EnemyService.aliveCount(): number
	return aliveCount
end

-- Registra uma funcao chamada quando um inimigo sai (Killed ou Leaked).
-- Devolve uma funcao para cancelar.
function EnemyService.onEnemyRemoved(callback: RemovedCallback): () -> ()
	table.insert(removedListeners, callback)
	return function()
		local index = table.find(removedListeners, callback)
		if index then
			table.remove(removedListeners, index)
		end
	end
end

-- Confere quem chegou ao fim do caminho.
local function checkLeaks()
	local total = PathService.getPathData().total
	local now = workspace:GetServerTimeNow()

	-- Primeiro juntamos os ids; so depois removemos (nao mexer na tabela enquanto percorre).
	table.clear(leakedBuffer)
	for id, enemy in enemies do
		if currentDistance(enemy, now) >= total then
			table.insert(leakedBuffer, id)
		end
	end

	for _, id in leakedBuffer do
		local enemy = enemies[id]
		if enemy then
			fireDied(id, "Leaked", centerPosition(enemy, total), 0)
			BaseService.damage(enemy.baseDamage)
			remove(id, "Leaked")
		end
	end
end

function EnemyService.start()
	if tickConnection then
		return
	end
	-- Acumula o tempo do Heartbeat e roda a conferencia 10x por segundo.
	local interval = 1 / Config.SERVER_TICK_RATE
	local accumulated = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt: number)
		accumulated += dt
		if accumulated < interval then
			return
		end
		accumulated %= interval
		checkLeaks()
	end)
end

-- Para o loop (nao usado no jogo normal, mas deixa a limpeza explicita).
function EnemyService.stop()
	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end
end

return EnemyService
