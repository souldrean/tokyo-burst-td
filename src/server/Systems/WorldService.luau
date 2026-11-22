--!strict
-- WorldService: liga o "Neon District" quando o servidor comeca.
-- A logica toda mora em src/server/World/ (WorldBuilder e amigos).
-- init() nao faz nada (regra: init rapido, sem trabalho pesado);
-- start() monta o mundo uma vez.

local WorldBuilder = require(script.Parent.Parent:WaitForChild("World"):WaitForChild("WorldBuilder"))

local WorldService = {}

function WorldService.init() end

function WorldService.start()
	local ok, err = pcall(WorldBuilder.build)
	if not ok then
		-- Decoracao quebrada nunca pode derrubar a partida: so avisa.
		warn(`[World] falhou ao montar o mundo: {err}`)
	end
end

return WorldService
