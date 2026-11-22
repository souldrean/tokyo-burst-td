--!strict
-- Objetos pequenos que dao vida a rua: maquinas de venda, cerejeiras,
-- lanternas e petalas caindo. Cada objeto procura um lugar LIVRE:
-- longe da estrada, dos slots, dos predios, das bases e dos outros objetos.

local WorldKit = require(script.Parent.WorldKit)

type MapInfo = WorldKit.MapInfo
type Rect = WorldKit.Rect

local Colors = WorldKit.Colors

local WorldProps = {}

local VENDING_PAIRS = 3
local SAKURA_TREES = 4
local LANTERNS = 6
local PETAL_HEIGHT = 45

local SAKURA_PINK = Color3.fromRGB(255, 170, 205)

-- Procura um lugar livre do tamanho pedido. Devolve o centro no chao (ou nil).
local function findSpot(info: MapInfo, rng: Random, taken: { Rect }, sx: number, sz: number): Vector3?
	local limit = info.groundHalf - math.max(sx, sz) - 3
	local buildingRects: { Rect } = {}
	for _, b in info.buildings do
		table.insert(buildingRects, WorldKit.rectOf(b))
	end
	for _ = 1, 400 do
		local rect = { cx = rng:NextNumber(-limit, limit), cz = rng:NextNumber(-limit, limit), sx = sx, sz = sz }
		if
			WorldKit.isClear(rect, info.roadRects, 3)
			and WorldKit.isClear(rect, info.slotRects, 2)
			and WorldKit.isClear(rect, buildingRects, 1.5)
			and WorldKit.isClear(rect, info.blockedRects, 3)
			and WorldKit.isClear(rect, taken, 2)
		then
			table.insert(taken, rect)
			return Vector3.new(rect.cx, 0, rect.cz)
		end
	end
	return nil
end

-- Vira o objeto para o centro do mapa (fica "de frente" para a camera).
local function facingMiddle(ground: Vector3): CFrame
	local toMiddle = Vector3.new(-ground.X, 0, -ground.Z)
	if toMiddle.Magnitude < 1 then
		return CFrame.new(ground)
	end
	return CFrame.lookAt(ground, ground + toMiddle.Unit)
end

-- Par de maquinas de venda: corpo colorido + painel neon na frente.
local function buildVendingPair(index: number, origin: CFrame, parent: Instance)
	local pair = Instance.new("Model")
	pair.Name = `Vending_{index}`
	local bodies = { Color3.fromRGB(235, 60, 80), Color3.fromRGB(60, 120, 235) }
	for k, offset in { -1.7, 1.7 } do
		local cf = origin * CFrame.new(offset, 3, 0)
		WorldKit.part(`Body_{k}`, Vector3.new(3, 6, 2), cf, bodies[k], pair, { shadow = true })
		WorldKit.part(`Panel_{k}`, Vector3.new(2.4, 3.2, 0.1), cf * CFrame.new(0, 0.8, -1.05), Colors.white, pair, {
			material = Enum.Material.Neon,
			transparency = 0.15,
		})
		WorldKit.part(`Slot_{k}`, Vector3.new(2, 0.6, 0.1), cf * CFrame.new(0, -2, -1.05), Colors.metal, pair)
	end
	pair.Parent = parent
end

-- Cerejeira low-poly: tronco + 3 bolas rosa.
local function buildSakura(index: number, ground: Vector3, rng: Random, parent: Instance)
	local tree = Instance.new("Model")
	tree.Name = `Sakura_{index}`
	WorldKit.part("Trunk", Vector3.new(1.2, 7, 1.2), CFrame.new(ground + Vector3.new(0, 3.5, 0)), Color3.fromRGB(80, 50, 45), tree, {
		material = Enum.Material.Wood,
		shadow = true,
	})
	for k, size in { 7, 6, 5 } do
		local angle = (k / 3) * math.pi * 2 + rng:NextNumber()
		local offset = Vector3.new(math.cos(angle) * 1.6, 7 + k * 0.6, math.sin(angle) * 1.6)
		WorldKit.part(`Leaves_{k}`, Vector3.new(size, size, size), CFrame.new(ground + offset), SAKURA_PINK, tree, {
			shape = Enum.PartType.Ball,
			shadow = true,
		})
	end
	tree.Parent = parent
end

-- Lanterna de papel num poste (neon vermelho, sem luz de verdade para poupar o celular).
local function buildLantern(index: number, ground: Vector3, parent: Instance)
	local lantern = Instance.new("Model")
	lantern.Name = `Lantern_{index}`
	WorldKit.part("Post", Vector3.new(0.3, 6, 0.3), CFrame.new(ground + Vector3.new(0, 3, 0)), Color3.fromRGB(60, 40, 35), lantern, {
		material = Enum.Material.Wood,
	})
	-- Cylinder: o comprimento fica no eixo X; girando 90 graus no Z ele fica em pe.
	local paperCFrame = CFrame.new(ground + Vector3.new(0, 6.8, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	WorldKit.part("Paper", Vector3.new(2.2, 1.6, 1.6), paperCFrame, Colors.red, lantern, {
		material = Enum.Material.Neon,
		shape = Enum.PartType.Cylinder,
	})
	lantern.Parent = parent
end

-- Petalas de cerejeira caindo devagar sobre o mapa inteiro.
local function buildPetals(info: MapInfo, parent: Instance)
	local area = info.groundHalf * 2
	local emitterPart = WorldKit.part("PetalSky", Vector3.new(area, 1, area), CFrame.new(0, PETAL_HEIGHT, 0), SAKURA_PINK, parent, {
		transparency = 1,
	})
	local petals = Instance.new("ParticleEmitter")
	petals.Name = "Petals"
	petals.Shape = Enum.ParticleEmitterShape.Box
	petals.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	petals.EmissionDirection = Enum.NormalId.Bottom
	petals.Rate = 18
	petals.Lifetime = NumberRange.new(10, 14)
	petals.Speed = NumberRange.new(2, 4)
	petals.Acceleration = Vector3.new(1.2, -0.4, 0.6) -- vento leve
	petals.Rotation = NumberRange.new(0, 360)
	petals.RotSpeed = NumberRange.new(-90, 90)
	petals.Size = NumberSequence.new(0.35)
	petals.Color = ColorSequence.new(SAKURA_PINK)
	petals.LightEmission = 0.4
	petals.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.1),
		NumberSequenceKeypoint.new(0.85, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	petals.Parent = emitterPart
end

function WorldProps.build(info: MapInfo, rng: Random, parent: Instance)
	local taken: { Rect } = {}
	local street = WorldKit.folder("StreetProps", parent)
	for i = 1, VENDING_PAIRS do
		local spot = findSpot(info, rng, taken, 7, 3)
		if spot then
			buildVendingPair(i, facingMiddle(spot), street)
		end
	end
	for i = 1, SAKURA_TREES do
		local spot = findSpot(info, rng, taken, 8, 8)
		if spot then
			buildSakura(i, spot, rng, street)
		end
	end
	for i = 1, LANTERNS do
		local spot = findSpot(info, rng, taken, 2, 2)
		if spot then
			buildLantern(i, spot, street)
		end
	end
	buildPetals(info, parent)
end

return WorldProps
