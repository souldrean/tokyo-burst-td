--!strict
-- PathService: le os waypoints do mapa (Workspace.Map.Waypoints) e guarda a lista.
-- Os outros sistemas pedem o caminho aqui, em vez de cada um ler o mapa por conta propria.

local PathService = {}

local waypoints: { Vector3 } = {}

type Entry = { index: number, position: Vector3 }

function PathService.init()
	-- WaitForChild com tempo limite: se o mapa nao existir, damos um erro claro.
	local map = workspace:WaitForChild("Map", 10)
	assert(map, "PathService: nao achei workspace.Map (o mapa foi construido pelo Rojo?)")
	local folder = map:WaitForChild("Waypoints", 10)
	assert(folder, "PathService: nao achei workspace.Map.Waypoints")

	local entries: { Entry } = {}
	for _, child in folder:GetChildren() do
		assert(child:IsA("BasePart"), `PathService: "{child.Name}" em Waypoints nao e uma Part`)
		local index = child:GetAttribute("Index")
		assert(typeof(index) == "number", `PathService: waypoint "{child.Name}" sem atributo numerico Index`)
		table.insert(entries, { index = index, position = child.Position })
	end

	assert(#entries >= 2, `PathService: preciso de pelo menos 2 waypoints, achei {#entries}`)

	-- A ordem dos filhos nao e garantida, entao ordenamos pelo atributo Index.
	table.sort(entries, function(a: Entry, b: Entry)
		return a.index < b.index
	end)

	-- Valida: Index tem que ser 1, 2, 3... sem buracos e sem repetidos.
	local list: { Vector3 } = {}
	for i, entry in entries do
		assert(entry.index == i, `PathService: Index esperado {i} mas achei {entry.index} (buraco ou repetido)`)
		list[i] = entry.position
	end

	waypoints = list
end

-- Devolve uma COPIA, assim ninguem estraga a lista original sem querer.
function PathService.getWaypoints(): { Vector3 }
	return table.clone(waypoints)
end

return PathService
