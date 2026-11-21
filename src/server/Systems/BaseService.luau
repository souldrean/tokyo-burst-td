--!strict
-- BaseService: guarda a vida da base. So o servidor muda esse numero.
-- MatchService escuta onChanged para copiar o valor para o atributo MatchState.BaseHealth.
-- (Assim BaseService nao precisa conhecer MatchService: evita require circular.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local BaseService = {}

local health: number = Config.BASE_MAX_HEALTH
local baseHitRemote: RemoteEvent? = nil

type ChangedCallback = (health: number, maxHealth: number) -> ()
local listeners: { ChangedCallback } = {}

local function notify()
	for _, callback in listeners do
		callback(health, Config.BASE_MAX_HEALTH)
	end
end

function BaseService.init()
	baseHitRemote = Net.event("BaseHit")
end

-- Registra uma funcao chamada quando a vida muda. Devolve uma funcao para cancelar.
function BaseService.onChanged(callback: ChangedCallback): () -> ()
	table.insert(listeners, callback)
	return function()
		local index = table.find(listeners, callback)
		if index then
			table.remove(listeners, index)
		end
	end
end

function BaseService.getHealth(): number
	return health
end

function BaseService.isDead(): boolean
	return health <= 0
end

function BaseService.damage(amount: number)
	-- Defesa: ignora valores estranhos (NaN, negativo, zero) e base ja destruida.
	if amount ~= amount or amount <= 0 or health <= 0 then
		return
	end
	local dealt = math.min(amount, health)
	health = math.max(0, health - amount)
	if baseHitRemote then
		baseHitRemote:FireAllClients(dealt, health)
	end
	notify()
end

function BaseService.reset()
	health = Config.BASE_MAX_HEALTH
	notify()
end

return BaseService
