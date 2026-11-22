--!strict
-- A cidade: pinta o mapa de "noite", poe faixas de janela acesas e letreiros
-- nos predios, cria o horizonte de arranha-ceus em volta e o canal de agua.
-- Assim o mapa para de "flutuar no ceu" e parece um bairro de Toquio neon.

local WorldKit = require(script.Parent.WorldKit)

type MapInfo = WorldKit.MapInfo

local Colors = WorldKit.Colors
local ACCENTS = WorldKit.ACCENTS

local WorldCity = {}

-- Palavras dos letreiros (inventadas, nenhuma marca real).
local ROOF_WORDS = { "BURST", "RAMEN", "ARCADE", "KARAOKE", "NEON 24", "HOTEL" }
local SIDE_WORDS = { "RAMEN", "GAMES", "SUSHI", "MANGA", "CAFE" }

local BAND_STEP = 5 -- uma faixa de janelas a cada 5 studs de altura
local CANAL_WIDTH = 16
local CITY_EDGE = 350 -- ate onde vai o chao da cidade em volta
local SKYLINE_TOWERS = 70

-- Pinta as pecas do MAPA (so cor/material; posicao e tamanho nao mudam).
function WorldCity.restyleMap(info: MapInfo, rng: Random)
	local ground = info.map:FindFirstChild("Ground")
	if ground and ground:IsA("BasePart") then
		ground.Color = Colors.night
	end
	local road = info.map:FindFirstChild("Road")
	if road then
		for _, p in road:GetChildren() do
			if p:IsA("BasePart") then
				p.Color = Colors.asphalt
			end
		end
	end
	for _, building in info.buildings do
		local shade = rng:NextInteger(26, 44)
		building.Color = Color3.fromRGB(shade, shade - 4, shade + 14)
	end
end

-- Texto neon numa face de uma peca (SurfaceGui na frente).
local function addText(board: BasePart, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0 -- o texto "acende" sozinho, mesmo a noite
	gui.Brightness = 1.6
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Colors.white
	stroke.Thickness = 1.5
	stroke.Transparency = 0.5
	stroke.Parent = label
	gui.Parent = board
end

-- Placa com moldura neon atras. A FRENTE da placa olha para "facing".
local function sign(name: string, center: Vector3, facing: Vector3, size: Vector3, text: string, color: Color3, parent: Instance)
	local model = Instance.new("Model")
	model.Name = name
	local cf = CFrame.lookAt(center, center + facing)
	WorldKit.part("Frame", size + Vector3.new(0.6, 0.6, -size.Z / 2), cf * CFrame.new(0, 0, size.Z * 0.6), color, model, { material = Enum.Material.Neon })
	local board = WorldKit.part("Board", size, cf, Color3.fromRGB(10, 10, 16), model)
	addText(board, text, color)
	model.Parent = parent
end

-- Contorno neon (4 barras finas) em volta do topo de um bloco.
-- So o contorno, nao a tampa inteira: vista de cima, tampa cheia vira um quadrado
-- de luz que ofusca o resto.
local function roofOutline(name: string, center: Vector3, sx: number, sz: number, color: Color3, parent: Instance)
	local t = 0.5
	local options = { material = Enum.Material.Neon }
	WorldKit.part(`{name}_N`, Vector3.new(sx + t, t, t), CFrame.new(center + Vector3.new(0, 0, sz / 2)), color, parent, options)
	WorldKit.part(`{name}_S`, Vector3.new(sx + t, t, t), CFrame.new(center - Vector3.new(0, 0, sz / 2)), color, parent, options)
	WorldKit.part(`{name}_E`, Vector3.new(t, t, sz + t), CFrame.new(center + Vector3.new(sx / 2, 0, 0)), color, parent, options)
	WorldKit.part(`{name}_W`, Vector3.new(t, t, sz + t), CFrame.new(center - Vector3.new(sx / 2, 0, 0)), color, parent, options)
end

-- Faixas de janelas + borda neon no topo de cada predio do mapa.
local function dressBuildings(info: MapInfo, rng: Random, parent: Instance)
	for index, building in info.buildings do
		local accent = ACCENTS[rng:NextInteger(1, #ACCENTS)]
		local size = building.Size
		local bottom = building.Position.Y - size.Y / 2
		local top = bottom + size.Y
		local center = Vector3.new(building.Position.X, 0, building.Position.Z)
		local y = bottom + 4
		while y < top - 3 do
			-- Nem todo andar acende: fica com cara de "janelas" e gasta menos pecas.
			if rng:NextNumber() < 0.6 then
				WorldKit.part(`Band_{index}_{math.floor(y)}`, Vector3.new(size.X + 0.25, 0.5, size.Z + 0.25), CFrame.new(center + Vector3.new(0, y, 0)), WorldKit.dim(accent, 0.45), parent, {
					material = Enum.Material.Neon,
				})
			end
			y += BAND_STEP
		end
		roofOutline(`Roof_{index}`, center + Vector3.new(0, top, 0), size.X, size.Z, accent, parent)
	end
end

-- Letreiros: placas no telhado dos predios mais altos e placas verticais
-- penduradas na lateral dos medios (bem "rua de Toquio").
local function buildSigns(info: MapInfo, rng: Random, parent: Instance)
	local sorted = table.clone(info.buildings)
	table.sort(sorted, function(a, b)
		return a.Size.Y > b.Size.Y
	end)
	for i = 1, math.min(#ROOF_WORDS, #sorted) do
		local building = sorted[i]
		local top = building.Position.Y + building.Size.Y / 2
		local width = math.min(building.Size.X, building.Size.Z) * 0.9
		local center = Vector3.new(building.Position.X, top + 2.8, building.Position.Z)
		local toMiddle = Vector3.new(-center.X, 0, -center.Z)
		local facing = if toMiddle.Magnitude > 1 then toMiddle.Unit else Vector3.new(0, 0, 1)
		sign(`RoofSign_{i}`, center, facing, Vector3.new(width, 4.5, 0.5), ROOF_WORDS[i], ACCENTS[(i - 1) % #ACCENTS + 1], parent)
	end
	local sideIndex = 0
	for i = #ROOF_WORDS + 1, #sorted do
		local building = sorted[i]
		if sideIndex >= #SIDE_WORDS or building.Size.Y < 16 then
			continue
		end
		sideIndex += 1
		-- Lado do predio que olha para o centro do mapa.
		local pos = building.Position
		local normal = if math.abs(pos.X) > math.abs(pos.Z)
			then Vector3.new(-math.sign(pos.X), 0, 0)
			else Vector3.new(0, 0, -math.sign(pos.Z))
		local halfDepth = math.abs(normal.X) * building.Size.X / 2 + math.abs(normal.Z) * building.Size.Z / 2
		local along = Vector3.new(normal.Z, 0, -normal.X)
		local halfWidth = math.abs(along.X) * building.Size.X / 2 + math.abs(along.Z) * building.Size.Z / 2
		local height = 11
		local bottom = pos.Y - building.Size.Y / 2
		local centerY = math.min(bottom + building.Size.Y - height / 2 - 2, bottom + 14)
		local center = Vector3.new(pos.X, centerY, pos.Z) + normal * (halfDepth + 1.2) + along * (halfWidth - 1.6)
		local word = SIDE_WORDS[sideIndex]
		-- Uma letra por linha: "RAMEN" vira "R\nA\nM\nE\nN".
		local letters: { string } = {}
		for letter in string.gmatch(word, ".") do
			table.insert(letters, letter)
		end
		local vertical = table.concat(letters, "\n")
		sign(`SideSign_{sideIndex}`, center, normal, Vector3.new(2.4, height, 0.4), vertical, ACCENTS[rng:NextInteger(1, #ACCENTS)], parent)
	end
end

-- Chao da cidade em volta + canal de agua entre o mapa e a cidade.
local function buildSurroundings(info: MapInfo, parent: Instance)
	local inner = info.groundHalf + CANAL_WIDTH -- onde a cidade comeca
	local depth = CITY_EDGE - inner
	local mid = (inner + CITY_EDGE) / 2
	local slabY = -0.5 - 1.25 -- topo na altura da calcada (y = -0.5)
	local floorColor = Color3.fromRGB(18, 17, 26)
	WorldKit.part("CityNorth", Vector3.new(CITY_EDGE * 2, 2.5, depth), CFrame.new(0, slabY, mid), floorColor, parent, { material = Enum.Material.Concrete })
	WorldKit.part("CitySouth", Vector3.new(CITY_EDGE * 2, 2.5, depth), CFrame.new(0, slabY, -mid), floorColor, parent, { material = Enum.Material.Concrete })
	WorldKit.part("CityEast", Vector3.new(depth, 2.5, inner * 2), CFrame.new(mid, slabY, 0), floorColor, parent, { material = Enum.Material.Concrete })
	WorldKit.part("CityWest", Vector3.new(depth, 2.5, inner * 2), CFrame.new(-mid, slabY, 0), floorColor, parent, { material = Enum.Material.Concrete })
	-- Fundo do canal.
	WorldKit.part("CanalBed", Vector3.new(inner * 2, 1, inner * 2), CFrame.new(0, -4.5, 0), Color3.fromRGB(10, 12, 20), parent)

	-- Agua de verdade (Terrain), em 4 faixas em volta do mapa.
	local terrain = workspace.Terrain
	local waterMid = info.groundHalf + CANAL_WIDTH / 2
	local long = inner * 2
	local waterY = -2.5
	terrain:FillBlock(CFrame.new(0, waterY, waterMid), Vector3.new(long, 2, CANAL_WIDTH), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(0, waterY, -waterMid), Vector3.new(long, 2, CANAL_WIDTH), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(waterMid, waterY, 0), Vector3.new(CANAL_WIDTH, 2, long), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(-waterMid, waterY, 0), Vector3.new(CANAL_WIDTH, 2, long), Enum.Material.Water)

	-- Borda neon rosa na beira do mapa (o "cais").
	local edge = info.groundHalf
	for i, dir in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local along = Vector3.new(dir.Z, 0, dir.X)
		local center = dir * edge + Vector3.new(0, 0.05, 0)
		WorldKit.part(`Pier_{i}`, Vector3.new(0.5, 0.3, edge * 2), CFrame.lookAt(center, center + along), Colors.pink, parent, {
			material = Enum.Material.Neon,
		})
	end
end

-- Arranha-ceus la longe. A neblina roxa apaga os mais distantes, dando profundidade.
local function buildSkyline(info: MapInfo, rng: Random, parent: Instance)
	local inner = info.groundHalf + CANAL_WIDTH + 6
	local made = 0
	local tries = 0
	while made < SKYLINE_TOWERS and tries < 2000 do
		tries += 1
		local x = rng:NextNumber(-CITY_EDGE + 20, CITY_EDGE - 20)
		local z = rng:NextNumber(-CITY_EDGE + 20, CITY_EDGE - 20)
		local w, d = rng:NextInteger(14, 30), rng:NextInteger(14, 30)
		if math.max(math.abs(x) - w / 2, math.abs(z) - d / 2) < inner then
			continue
		end
		made += 1
		-- Perto do mapa = baixo (nao tampa a camera); longe = alto (horizonte).
		local far = math.clamp((math.max(math.abs(x), math.abs(z)) - inner) / (CITY_EDGE - inner), 0, 1)
		local h = rng:NextInteger(20 + math.floor(far * 40), 45 + math.floor(far * 115))
		local shade = rng:NextInteger(16, 28)
		local center = Vector3.new(x, -0.5 + h / 2, z)
		WorldKit.part(`Tower_{made}`, Vector3.new(w, h, d), CFrame.new(center), Color3.fromRGB(shade, shade - 2, shade + 10), parent)
		if rng:NextNumber() < 0.55 then
			local accent = ACCENTS[rng:NextInteger(1, #ACCENTS)]
			roofOutline(`TowerTop_{made}`, Vector3.new(x, -0.5 + h, z), w, d, accent, parent)
		end
	end
end

function WorldCity.build(info: MapInfo, rng: Random, parent: Instance)
	dressBuildings(info, rng, WorldKit.folder("BuildingLights", parent))
	buildSigns(info, rng, WorldKit.folder("Signs", parent))
	buildSurroundings(info, WorldKit.folder("Surroundings", parent))
	buildSkyline(info, rng, WorldKit.folder("Skyline", parent))
end

return WorldCity
