--!strict
-- Monta o "Neon District" inteiro: clima, rua, cidade e objetos.
-- Le o Workspace.Map (que o gen_map.py gera) e cria Workspace.World so com
-- decoracao. Nada aqui muda a jogabilidade: slots, estrada e waypoints continuam
-- iguais, so ganham cor.
--
-- Pode rodar de novo quantas vezes quiser: apaga o World antigo e refaz igual
-- (mesma semente = mesmo resultado).

local WorldKit = require(script.Parent.WorldKit)
local WorldLighting = require(script.Parent.WorldLighting)
local WorldStreet = require(script.Parent.WorldStreet)
local WorldCity = require(script.Parent.WorldCity)
local WorldProps = require(script.Parent.WorldProps)

local WorldBuilder = {}

function WorldBuilder.build(): Folder?
	local map = workspace:FindFirstChild("Map")
	if not map or not map:IsA("Model") then
		warn("[World] Workspace.Map nao encontrado; decoracao cancelada")
		return nil
	end
	local info = WorldKit.readMap(map)
	if not info then
		return nil
	end

	local old = workspace:FindFirstChild("World")
	if old then
		old:Destroy()
	end

	WorldLighting.apply()
	-- Cada parte tem a propria semente: mudar uma nao bagunca as outras.
	WorldCity.restyleMap(info, Random.new(WorldKit.SEED))

	-- Monta tudo FORA do Workspace e so no fim coloca la dentro (uma replicacao so).
	local root = Instance.new("Folder")
	root.Name = "World"
	WorldStreet.build(info, WorldKit.folder("Street", root))
	WorldCity.build(info, Random.new(WorldKit.SEED + 1), WorldKit.folder("City", root))
	WorldProps.build(info, Random.new(WorldKit.SEED + 2), WorldKit.folder("Props", root))
	root.Parent = workspace
	return root
end

return WorldBuilder
