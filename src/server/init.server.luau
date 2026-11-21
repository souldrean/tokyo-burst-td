--!strict
-- Ponto de entrada do servidor: o UNICO Script do servidor.
-- Inicia em duas fases: primeiro init() de todos, depois start() de todos.
-- Assim nenhum sistema comeca a rodar antes de os outros estarem prontos.

local Systems = script:WaitForChild("Systems")

local loaded: { any } = {}
for _, child in Systems:GetChildren() do
	if child:IsA("ModuleScript") then
		table.insert(loaded, require(child))
	end
end

-- Fase 1: preparar (rapida, sem loops longos).
for _, system in loaded do
	if typeof(system.init) == "function" then
		system.init()
	end
end

-- Fase 2: comecar. task.spawn evita que um start travado bloqueie os outros.
for _, system in loaded do
	if typeof(system.start) == "function" then
		task.spawn(system.start)
	end
end
