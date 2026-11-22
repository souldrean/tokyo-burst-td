--!strict
-- A rua: bordas de neon, faixa tracejada, postes de luz, o portao por onde os
-- inimigos entram e o escudo da base. Tudo segue os waypoints do mapa, entao se
-- o gen_map.py mudar o caminho, a decoracao acompanha sozinha.

local WorldKit = require(script.Parent.WorldKit)

type MapInfo = WorldKit.MapInfo

local Colors = WorldKit.Colors

local WorldStreet = {}

local ROAD_TOP = 0.1 -- a estrada tem 0.2 de altura e centro em y = 0
local DASH_LENGTH = 3.5
local DASH_STEP = 8
local LAMP_SPACING = 40
local MAX_LAMPS = 12 -- cada poste tem uma luz; luz demais pesa no celular

-- Direcao "para a esquerda" de quem anda na direcao d (no plano XZ).
local function leftOf(d: Vector3): Vector3
	return Vector3.new(-d.Z, 0, d.X)
end

-- Uma barra fina deitada no chao, indo de "from" ate "to".
local function strip(name: string, from: Vector3, to: Vector3, width: number, height: number, color: Color3, parent: Instance, neon: boolean)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, mid + (to - from).Unit)
	WorldKit.part(name, Vector3.new(width, height, length), cf, color, parent, {
		material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
	})
end

-- Bordas de neon dos dois lados de cada trecho.
-- Na curva, o lado de DENTRO encolhe e o lado de FORA estica: assim a borda
-- contorna a esquina sem atravessar a estrada.
local function buildEdges(info: MapInfo, parent: Instance)
	local wps = info.waypoints
	local half = info.roadWidth / 2
	local y = ROAD_TOP + 0.08
	for i = 1, #wps - 1 do
		local a, b = wps[i], wps[i + 1]
		local d = (b - a).Unit
		local left = leftOf(d)
		for _, side in { 1, -1 } do
			local sideDir = left * side
			local startPoint = a - d * half -- ponta do mapa: estica ate a borda da junta
			if i > 1 then
				local cameFrom = (wps[i - 1] - a).Unit
				startPoint = if cameFrom:Dot(sideDir) > 0 then a + d * half else a - d * half
			end
			local endPoint = b + d * half
			if i < #wps - 1 then
				local goesTo = (wps[i + 2] - b).Unit
				endPoint = if goesTo:Dot(sideDir) > 0 then b - d * half else b + d * half
			end
			local offset = sideDir * (half - 0.25) + Vector3.new(0, y, 0)
			strip(`Edge_{i}_{side}`, startPoint + offset, endPoint + offset, 0.35, 0.15, Colors.cyan, parent, true)
		end
	end
end

-- Faixa tracejada no meio da rua (mostra o caminho dos inimigos).
local function buildDashes(info: MapInfo, parent: Instance)
	local wps = info.waypoints
	local half = info.roadWidth / 2
	local y = Vector3.new(0, ROAD_TOP + 0.06, 0)
	for i = 1, #wps - 1 do
		local a, b = wps[i], wps[i + 1]
		local d = (b - a).Unit
		local usable = (b - a).Magnitude - 2 * (half + 2)
		local count = math.floor(usable / DASH_STEP)
		for k = 0, count do
			local from = a + d * (half + 2 + k * DASH_STEP)
			strip(`Dash_{i}_{k}`, from + y, from + d * DASH_LENGTH + y, 0.3, 0.12, Colors.white, parent, false)
		end
	end
end

local function buildLamp(index: number, ground: Vector3, overRoad: Vector3, parent: Instance)
	local lamp = Instance.new("Model")
	lamp.Name = `Lamp_{index}`
	local poleHeight = 9
	WorldKit.part("Pole", Vector3.new(0.4, poleHeight, 0.4), CFrame.new(ground + Vector3.new(0, poleHeight / 2, 0)), Colors.metal, lamp, { material = Enum.Material.Metal })
	local armStart = ground + Vector3.new(0, poleHeight, 0)
	local armEnd = armStart + overRoad * 2.5
	strip("Arm", armStart, armEnd, 0.3, 0.3, Colors.metal, lamp, false)
	local head = WorldKit.part("Head", Vector3.new(1.3, 0.5, 1.3), CFrame.new(armEnd - Vector3.new(0, 0.3, 0)), Colors.warm, lamp, { material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Color = Colors.warm
	light.Range = 18
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = head
	lamp.Parent = parent
end

-- Postes na beira da rua, lados alternados, longe das esquinas e dos slots.
local function buildLamps(info: MapInfo, parent: Instance)
	local wps = info.waypoints
	local half = info.roadWidth / 2
	local placed = 0
	local walked = 0
	local nextAt = LAMP_SPACING / 2
	for i = 1, #wps - 1 do
		local a, b = wps[i], wps[i + 1]
		local d = (b - a).Unit
		local length = (b - a).Magnitude
		while nextAt <= walked + length and placed < MAX_LAMPS do
			local t = nextAt - walked
			nextAt += LAMP_SPACING
			if t > info.roadWidth and t < length - info.roadWidth then
				for _, side in { if placed % 2 == 0 then 1 else -1, if placed % 2 == 0 then -1 else 1 } do
					local sideDir = leftOf(d) * side
					local ground = a + d * t + sideDir * (half + 1.2)
					local rect = { cx = ground.X, cz = ground.Z, sx = 0.6, sz = 0.6 }
					if WorldKit.isClear(rect, info.slotRects, 0.6) and WorldKit.isClear(rect, info.blockedRects, 1) then
						placed += 1
						buildLamp(placed, ground, -sideDir, parent)
						break
					end
				end
			end
		end
		walked += length
	end
end

-- Portao vermelho (original, estilo "arco de rua") onde os inimigos nascem.
local function buildGate(info: MapInfo, parent: Instance)
	local wps = info.waypoints
	local p = wps[1]
	local d = (wps[2] - wps[1]).Unit
	local across = leftOf(d)
	local gate = Instance.new("Model")
	gate.Name = "EnemyGate"
	local reach = info.roadWidth / 2 + 1.2
	local height = 14
	for _, side in { 1, -1 } do
		local base = p + across * reach * side
		WorldKit.part(`Pillar_{side}`, Vector3.new(1.6, height, 1.6), CFrame.new(base + Vector3.new(0, height / 2, 0)), Colors.red, gate, { shadow = true })
	end
	local top = p + Vector3.new(0, height + 0.6, 0)
	WorldKit.part("TopBeam", Vector3.new(1.8, 1.2, reach * 2 + 5), CFrame.lookAt(top, top + across), Colors.pink, gate, { material = Enum.Material.Neon })
	local low = p + Vector3.new(0, height - 2.6, 0)
	WorldKit.part("LowBeam", Vector3.new(1.2, 0.8, reach * 2 + 1.6), CFrame.lookAt(low, low + across), Colors.red, gate)
	local glow = Instance.new("PointLight")
	glow.Color = Colors.pink
	glow.Range = 22
	glow.Brightness = 2
	glow.Parent = gate:FindFirstChild("TopBeam")
	gate.Parent = parent
end

-- Escudo e farol da base: o jogador sempre sabe o que precisa proteger.
local function buildBaseShield(info: MapInfo, parent: Instance)
	local base = info.playerBase
	if not base then
		return
	end
	local shield = Instance.new("Model")
	shield.Name = "BaseShield"
	local ground = Vector3.new(base.Position.X, 0, base.Position.Z)
	local radius = math.max(base.Size.X, base.Size.Z) * 0.85
	WorldKit.part("Dome", Vector3.new(radius * 2, radius * 2, radius * 2), CFrame.new(ground), Colors.cyan, shield, {
		material = Enum.Material.ForceField,
		shape = Enum.PartType.Ball,
	})
	-- Cilindro deitado: o eixo do Cylinder e o X, entao giramos 90 graus no Z.
	WorldKit.part("Ring", Vector3.new(0.2, radius * 2 + 2, radius * 2 + 2), CFrame.new(ground + Vector3.new(0, ROAD_TOP + 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), Colors.cyan, shield, {
		material = Enum.Material.Neon,
		shape = Enum.PartType.Cylinder,
		transparency = 0.45,
	})
	local beaconHeight = 60
	local beacon = WorldKit.part("Beacon", Vector3.new(0.8, beaconHeight, 0.8), CFrame.new(ground + Vector3.new(0, base.Size.Y + beaconHeight / 2, 0)), Colors.cyan, shield, {
		material = Enum.Material.Neon,
		transparency = 0.5,
	})
	local light = Instance.new("PointLight")
	light.Color = Colors.cyan
	light.Range = 24
	light.Brightness = 2
	light.Parent = beacon
	shield.Parent = parent
end

function WorldStreet.build(info: MapInfo, parent: Instance)
	buildEdges(info, WorldKit.folder("Edges", parent))
	buildDashes(info, WorldKit.folder("Dashes", parent))
	buildLamps(info, WorldKit.folder("Lamps", parent))
	buildGate(info, parent)
	buildBaseShield(info, parent)
end

return WorldStreet
