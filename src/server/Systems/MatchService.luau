--!strict
-- MatchService: dono da partida. Cria ReplicatedStorage.MatchState (atributos que
-- replicam sozinhos para os clientes) e roda o loop:
-- Waiting -> Intermission -> ondas 1..N -> Victory/Defeat -> espera -> recomeca.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Types = require(Shared:WaitForChild("Types"))

local EnemyService = require(script.Parent.EnemyService)
local BaseService = require(script.Parent.BaseService)

local MatchService = {}

local POLL_SECONDS = 0.1 -- espera curta usada para conferir condicoes (barato)

local state: Folder? = nil
local waveStartedRemote: RemoteEvent? = nil
local matchEndedRemote: RemoteEvent? = nil
local cleanups: { () -> () } = {}

local function setAttr(name: string, value: string | number)
	if state then
		state:SetAttribute(name, value)
	end
end

local function setState(name: Types.MatchStateName, endsAt: number)
	setAttr("State", name)
	setAttr("StateEndsAt", endsAt)
end

function MatchService.init()
	local folder = Instance.new("Folder")
	folder.Name = "MatchState"
	folder:SetAttribute("State", "Waiting")
	folder:SetAttribute("Wave", 0)
	folder:SetAttribute("WaveCount", #Config.WAVES)
	folder:SetAttribute("BaseHealth", BaseService.getHealth())
	folder:SetAttribute("BaseMaxHealth", Config.BASE_MAX_HEALTH)
	folder:SetAttribute("StateEndsAt", 0)
	folder:SetAttribute("EnemiesAlive", 0)
	folder.Parent = ReplicatedStorage
	state = folder

	waveStartedRemote = Net.event("WaveStarted")
	matchEndedRemote = Net.event("MatchEnded")

	-- Copia a vida da base e a contagem de inimigos para os atributos.
	table.insert(
		cleanups,
		BaseService.onChanged(function(health: number, maxHealth: number)
			setAttr("BaseHealth", health)
			setAttr("BaseMaxHealth", maxHealth)
		end)
	)
	table.insert(
		cleanups,
		EnemyService.onEnemyRemoved(function()
			setAttr("EnemiesAlive", EnemyService.aliveCount())
		end)
	)
end

-- Espera ate existir pelo menos 1 jogador (a partida nao gasta ondas sem ninguem olhando).
local function waitForPlayers()
	while #Players:GetPlayers() < 1 do
		task.wait(0.5)
	end
end

-- Spawna os grupos da onda em sequencia. Para cedo se a base cair.
local function spawnWave(wave: Types.WaveDef)
	for _, group in wave.groups do
		for _ = 1, group.count do
			if BaseService.isDead() then
				return
			end
			-- Se o limite de inimigos vivos for atingido, spawn devolve nil: so pulamos.
			EnemyService.spawn(group.kind)
			setAttr("EnemiesAlive", EnemyService.aliveCount())
			task.wait(group.interval)
		end
	end
end

local function endMatch(result: Types.MatchResult)
	setState(result, workspace:GetServerTimeNow() + Config.RESTART_DELAY_SECONDS)
	if result == "Defeat" then
		EnemyService.clearAll()
		setAttr("EnemiesAlive", 0)
	end
	if matchEndedRemote then
		matchEndedRemote:FireAllClients(result)
	end
end

-- Roda uma partida completa. Devolve "Victory" ou "Defeat".
local function runMatch(): Types.MatchResult
	-- Intermission: contagem regressiva antes da onda 1.
	local endsAt = workspace:GetServerTimeNow() + Config.INTERMISSION_SECONDS
	setState("Intermission", endsAt)
	while workspace:GetServerTimeNow() < endsAt do
		task.wait(POLL_SECONDS)
	end

	local waveCount = #Config.WAVES
	for index, wave in Config.WAVES do
		setAttr("Wave", index)
		setState("Wave", 0) -- onda nao tem hora certa para acabar
		if waveStartedRemote then
			waveStartedRemote:FireAllClients(index, waveCount, wave.boss == true)
		end

		local waveStart = os.clock()
		spawnWave(wave)

		-- A proxima onda comeca quando: terminou de spawnar E (todos sumiram OU deu o tempo).
		-- Na ultima onda esperamos todos sumirem (nao existe "proxima" para adiantar).
		local isLast = index == waveCount
		while not BaseService.isDead() do
			if EnemyService.aliveCount() == 0 then
				break
			end
			if not isLast and os.clock() - waveStart >= Config.WAVE_TIMEOUT_SECONDS then
				break
			end
			task.wait(POLL_SECONDS)
		end

		if BaseService.isDead() then
			return "Defeat"
		end
	end

	return "Victory"
end

function MatchService.start()
	while true do
		setState("Waiting", 0)
		waitForPlayers()

		local result = runMatch()
		endMatch(result)
		task.wait(Config.RESTART_DELAY_SECONDS)

		-- Reinicia tudo para a proxima partida.
		EnemyService.clearAll()
		BaseService.reset()
		setAttr("Wave", 0)
		setAttr("EnemiesAlive", 0)
	end
end

-- Limpeza explicita das conexoes (nao e chamada no jogo normal).
function MatchService.destroy()
	for _, cleanup in cleanups do
		cleanup()
	end
	table.clear(cleanups)
end

return MatchService
