--!strict
-- DebugService: ferramenta de teste SO para o Studio.
-- O cliente clica num inimigo e manda DebugHitEnemy(id); o servidor valida tudo
-- (nunca confie no cliente) e aplica dano pelo mesmo caminho do jogo real.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local EnemyService = require(script.Parent.EnemyService)

local DebugService = {}

local MAX_ID_LENGTH = 16
local RATE_PER_SECOND = 10 -- maximo de cliques por segundo por jogador
local BURST = 10

type Bucket = { tokens: number, last: number }
local buckets: { [Player]: Bucket } = {}
local connections: { RBXScriptConnection } = {}

-- "Balde de fichas": cada clique gasta 1 ficha; as fichas voltam com o tempo.
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

function DebugService.init()
	-- Fora do Studio nem criamos o remote nem ligamos o handler.
	if not RunService:IsStudio() then
		return
	end

	local remote = Net.event("DebugHitEnemy")
	table.insert(
		connections,
		remote.OnServerEvent:Connect(function(player: Player, id: unknown)
			if not allow(player) then
				return
			end
			-- Tipo e tamanho primeiro; so depois usamos o valor.
			if typeof(id) ~= "string" then
				return
			end
			if #id > MAX_ID_LENGTH then
				return
			end
			-- O inimigo precisa existir (getDistance devolve nil se nao existir).
			if EnemyService.getDistance(id) == nil then
				return
			end
			EnemyService.damage(id, Config.DEBUG_HIT_DAMAGE)
		end)
	)

	-- Jogador saiu: apaga o balde dele (senao a tabela guardaria o Player para sempre).
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			buckets[player] = nil
		end)
	)
end

-- Limpeza explicita (nao usada no jogo normal).
function DebugService.destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(buckets)
end

return DebugService
