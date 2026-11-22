--!strict
-- Caixa de ferramentas do "mundo" (a decoracao em volta do jogo).
-- Aqui ficam: as cores neon, a funcao que cria pecas "fantasma" e a leitura
-- do mapa (estrada, slots, predios) para a decoracao nunca ficar em cima deles.
--
-- Por que "fantasma"? Toda peca de decoracao NAO colide, NAO entra em raycast e
-- NAO dispara Touched. Assim ela nunca atrapalha o toque para posicionar ou
-- selecionar unidades (esses raycasts usam filtro Include, mas melhor garantir).

local WorldKit = {}

-- Semente fixa: toda vez que o servidor liga, o mundo sai IGUAL.
WorldKit.SEED = 20261122

WorldKit.Colors = {
	cyan = Color3.fromRGB(0, 229, 255),
	pink = Color3.fromRGB(255, 61, 165),
	purple = Color3.fromRGB(170, 90, 255),
	yellow = Color3.fromRGB(255, 214, 64),
	red = Color3.fromRGB(230, 40, 70),
	warm = Color3.fromRGB(255, 196, 140),
	white = Color3.fromRGB(235, 235, 245),
	asphalt = Color3.fromRGB(16, 16, 22),
	night = Color3.fromRGB(30, 28, 42),
	metal = Color3.fromRGB(45, 45, 58),
}

-- As 4 cores de destaque que os predios/letreiros sorteiam.
WorldKit.ACCENTS = {
	WorldKit.Colors.cyan,
	WorldKit.Colors.pink,
	WorldKit.Colors.purple,
	WorldKit.Colors.yellow,
}

-- Retangulo no chao (plano XZ): centro + tamanho.
export type Rect = { cx: number, cz: number, sx: number, sz: number }

-- Tudo o que a decoracao precisa saber do mapa.
export type MapInfo = {
	map: Model,
	waypoints: { Vector3 },
	roadWidth: number,
	groundHalf: number,
	roadRects: { Rect },
	slotRects: { Rect },
	buildings: { BasePart },
	blockedRects: { Rect }, -- spawn do inimigo, base, spawn do jogador
	enemySpawn: BasePart?,
	playerBase: BasePart?,
}

export type PartOptions = {
	material: Enum.Material?,
	transparency: number?,
	shape: Enum.PartType?,
	shadow: boolean?,
}

-- Cria uma peca de decoracao ja ancorada e "fantasma".
function WorldKit.part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance,
	options: PartOptions?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = false
	if options then
		if options.material then
			p.Material = options.material
		end
		if options.transparency then
			p.Transparency = options.transparency
		end
		if options.shape then
			p.Shape = options.shape
		end
		if options.shadow ~= nil then
			p.CastShadow = options.shadow
		end
	end
	p.Parent = parent
	return p
end

-- Cria uma pasta filha (para organizar o Explorer).
function WorldKit.folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Escurece uma cor (t = 0 nada, t = 1 preto). Neon muito forte "estoura" a tela.
function WorldKit.dim(color: Color3, t: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), t)
end

function WorldKit.rectOf(part: BasePart): Rect
	return { cx = part.Position.X, cz = part.Position.Z, sx = part.Size.X, sz = part.Size.Z }
end

-- Distancia entre as bordas de dois retangulos (0 = encostam ou se sobrepoem).
function WorldKit.gap(a: Rect, b: Rect): number
	local dx = math.max(0, math.abs(a.cx - b.cx) - (a.sx + b.sx) / 2)
	local dz = math.max(0, math.abs(a.cz - b.cz) - (a.sz + b.sz) / 2)
	return math.max(dx, dz)
end

-- true se o retangulo fica a pelo menos "margin" de TODOS da lista.
function WorldKit.isClear(rect: Rect, others: { Rect }, margin: number): boolean
	for _, other in others do
		if WorldKit.gap(rect, other) < margin then
			return false
		end
	end
	return true
end

local function partsIn(map: Model, folderName: string): { BasePart }
	local list: { BasePart } = {}
	local folder = map:FindFirstChild(folderName)
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(list, child)
			end
		end
	end
	return list
end

local function partNamed(map: Model, name: string): BasePart?
	local found = map:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

-- Le o Workspace.Map (gerado pelo tools/gen_map.py) e monta o MapInfo.
function WorldKit.readMap(map: Model): MapInfo?
	-- Waypoints em ordem pelo atributo Index.
	local indexed: { { index: number, position: Vector3 } } = {}
	for _, wp in partsIn(map, "Waypoints") do
		local index = wp:GetAttribute("Index")
		if typeof(index) == "number" then
			table.insert(indexed, { index = index, position = wp.Position })
		end
	end
	if #indexed < 2 then
		warn("[World] Map.Waypoints sem pontos suficientes; decoracao cancelada")
		return nil
	end
	table.sort(indexed, function(a, b)
		return a.index < b.index
	end)
	local waypoints: { Vector3 } = {}
	for _, item in indexed do
		table.insert(waypoints, Vector3.new(item.position.X, 0, item.position.Z))
	end

	local road = partsIn(map, "Road")
	local roadRects: { Rect } = {}
	local roadWidth = 12
	for _, p in road do
		table.insert(roadRects, WorldKit.rectOf(p))
		if p.Name == "Joint_1" then
			roadWidth = p.Size.X
		end
	end

	local slotRects: { Rect } = {}
	for _, p in partsIn(map, "Placement") do
		table.insert(slotRects, WorldKit.rectOf(p))
	end

	local blocked: { Rect } = {}
	local enemySpawn = partNamed(map, "EnemySpawn")
	local playerBase = partNamed(map, "PlayerBase")
	for _, p in { enemySpawn, playerBase, partNamed(map, "PlayerSpawn") } do
		if p then
			table.insert(blocked, WorldKit.rectOf(p))
		end
	end

	local ground = partNamed(map, "Ground")
	return {
		map = map,
		waypoints = waypoints,
		roadWidth = roadWidth,
		groundHalf = if ground then ground.Size.X / 2 else 110,
		roadRects = roadRects,
		slotRects = slotRects,
		buildings = partsIn(map, "Buildings"),
		blockedRects = blocked,
		enemySpawn = enemySpawn,
		playerBase = playerBase,
	}
end

return WorldKit
