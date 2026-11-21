--!strict
-- Ponto de entrada do cliente: o UNICO LocalScript.
-- Mesma ideia do servidor: init() de todos os Controllers, depois start().

local Controllers = script:WaitForChild("Controllers")

local loaded: { any } = {}
for _, child in Controllers:GetChildren() do
	if child:IsA("ModuleScript") then
		table.insert(loaded, require(child))
	end
end

for _, controller in loaded do
	if typeof(controller.init) == "function" then
		controller.init()
	end
end

for _, controller in loaded do
	if typeof(controller.start) == "function" then
		task.spawn(controller.start)
	end
end
