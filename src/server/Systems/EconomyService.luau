--!strict
-- EconomyService: dinheiro da partida de cada jogador.
-- So o servidor mexe no dinheiro. Guardamos numa tabela (fonte da verdade) e copiamos
-- para o atributo "Cash" do Player, so para o HUD do cliente conseguir ler.
-- Regra co-op: quando um inimigo e MORTO, TODOS os jogadores ganham a recompensa.
-- Este modulo NAO pode dar require no MatchService (evita require circular):
-- o MatchService e quem chama resetAll().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local EnemyService = require(script.Parent.EnemyService)

local EconomyService = {}

-- Tabela por jogador. E limpa no PlayerRemoving (senao guardaria o Player para sempre).
local cash: { [Player]: number } = {}
local connections: { RBXScriptConnection } = {}
local cleanups: { () -> () } = {}

-- Numero valido = nao e NaN e nao e infinito.
local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function setCash(player: Player, value: number)
	cash[player] = value
	player:SetAttribute("Cash", value) -- o HUD le este atributo
end

local function onPlayerAdded(player: Player)
	-- Quem entra no meio da partida tambem comeca com START_CASH.
	setCash(player, Config.START_CASH)
end

function EconomyService.init()
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			cash[player] = nil
		end)
	)

	-- Inimigo morto -> todo mundo ganha. Vazou (Leaked) nao da nada.
	table.insert(
		cleanups,
		EnemyService.onEnemyRemoved(function(_id: string, reason: Types.DeathReason, reward: number)
			if reason == "Killed" then
				EconomyService.addAll(reward)
			end
		end)
	)
end

function EconomyService.get(player: Player): number
	return cash[player] or 0
end

-- Soma dinheiro (n precisa ser positivo e finito; senao ignora).
function EconomyService.add(player: Player, n: number)
	if not isFinite(n) or n <= 0 then
		return
	end
	local current = cash[player]
	if current == nil then
		return -- jogador que ja saiu
	end
	setCash(player, current + n)
end

-- Tenta gastar. Devolve true so se tinha dinheiro (e ja desconta).
function EconomyService.trySpend(player: Player, n: number): boolean
	if not isFinite(n) or n < 0 then
		return false
	end
	local current = cash[player]
	if current == nil or current < n then
		return false
	end
	setCash(player, current - n)
	return true
end

function EconomyService.addAll(n: number)
	for player in cash do
		EconomyService.add(player, n)
	end
end

-- Volta todo mundo para START_CASH (nova partida).
function EconomyService.resetAll()
	for player in cash do
		setCash(player, Config.START_CASH)
	end
end

-- Limpeza explicita (nao usada no jogo normal).
function EconomyService.destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, cleanup in cleanups do
		cleanup()
	end
	table.clear(cleanups)
	table.clear(cash)
end

return EconomyService
