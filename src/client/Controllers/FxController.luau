--!strict
-- FxController: o "suco" do jogo! Confete, numeros flutuantes, banners, tremor de camera.
-- Tudo roda so no cliente e so DESENHA: quem decide o que aconteceu e o servidor (via remotes).
-- Para ficar leve no celular: usamos POOLS (objetos criados uma vez e reaproveitados),
-- limites de quantidade e nada de criar objetos a cada frame.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
-- Config como "any": Config.UNITS pode ainda nao existir; lemos com cuidado e usamos cores reserva.
local Config = require(Shared:WaitForChild("Config")) :: any

-- Paleta neon (rosa, ciano, amarelo, lima, roxo).
local PALETTE: { Color3 } = {
	Color3.fromRGB(255, 51, 153),
	Color3.fromRGB(0, 240, 255),
	Color3.fromRGB(255, 225, 60),
	Color3.fromRGB(120, 255, 90),
	Color3.fromRGB(170, 80, 255),
}
local RED = Color3.fromRGB(255, 50, 70)
local GOLD = Color3.fromRGB(255, 200, 40)
local DARK = Color3.fromRGB(20, 12, 40)

-- Limites e ajustes (mexa aqui para deixar mais ou menos intenso).
local BURST_POOL_SIZE = 8 -- explosoes de confete ao mesmo tempo
local LEAK_POOL_SIZE = 4
local NUMBER_POOL_SIZE = 20 -- numeros flutuantes ao mesmo tempo (limite do spec)
local CONFETTI_PER_COLOR = 6 -- 5 cores x 6 = 30 pedacinhos por explosao
local VICTORY_PIECES = 50
local SOUND_ENABLED = true
local SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"
local SHAKE_BIND_NAME = "TokyoBurstCameraShake"

-- Limites dos efeitos das unidades (semana 3).
local PROJECTILE_POOL_SIZE = 40 -- maximo de projeteis ao mesmo tempo (se lotar, ignora o novo)
local SPARK_POOL_SIZE = 12
local RING_POOL_SIZE = 8
local PLACE_POOL_SIZE = 4
local STYLE_SHURIKEN = 1 -- numeros em vez de textos: comparar numero e mais barato no loop
local STYLE_SLASH = 2
local STYLE_ORB = 3
local HIDDEN_POSITION = Vector3.new(0, -500, 0)

-- Semana 4 (upgrade e venda). Nao criamos pools novos: reaproveitamos faiscas (12),
-- aneis (8), explosoes (4), confete (8) e numeros (20) que ja existem. Limites iguais ao da semana 3.
local DEFAULT_MAX_LEVEL = 4
local EVOLVE_ANTICIPATION = 0.25 -- segundos de "carregando" antes da explosao da evolucao
local EVOLVE_POWER = 1.5 -- a explosao do Lv4 e 50% maior que a de colocar
local EVOLVE_SHAKE_RANGE = 90 -- so treme a camera de quem esta perto da evolucao
local SLOW_RING_COLOR = Color3.fromRGB(170, 225, 255)
local CRIT_COLOR = Color3.fromRGB(255, 235, 120)
local COIN_COLOR = Color3.fromRGB(255, 205, 40)
local SLOW_RING_FALLBACK_DIAMETER = 10

-- Animacoes reaproveitadas.
local POP_IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local NUMBER_POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local NUMBER_RISE = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local NUMBER_FADE =
	TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.5)
local BANNER_FADE = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FLASH_FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LIGHT_FADE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GRADE_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type BurstSlot = {
	part: Part,
	emitters: { ParticleEmitter },
	light: PointLight,
	lightTween: Tween?,
}

type NumberSlot = {
	part: Part,
	gui: BillboardGui,
	label: TextLabel,
	scale: UIScale,
	stroke: UIStroke,
	token: number, -- sobe a cada uso; tweens antigos conferem o token antes de agir
	tweens: { Tween },
}

type UnitVisual = {
	style: number,
	color: Color3,
	accent: Color3,
	splash: number,
	height: number,
}

type ProjectileSlot = {
	part: Part,
	aux: Part, -- segunda peca: cruz da shuriken, nucleo branco do slash, brilho do orb
	active: boolean,
	style: number,
	t: number,
	duration: number,
	from: Vector3,
	to: Vector3,
	base: CFrame,
	arc: number,
	visual: UnitVisual,
}

type SparkSlot = {
	part: Part,
	emitter: ParticleEmitter,
	light: PointLight,
	lightTween: Tween?,
}

type RingSlot = {
	part: Part,
	tweens: { Tween },
}

type PlaceSlot = {
	sphere: Part,
	pillar: Part,
	ring: RingSlot,
	light: PointLight,
	tweens: { Tween },
}

local FxController = {}

local connections: { RBXScriptConnection } = {}

local fxFolder: Folder? = nil
local burstSlots: { BurstSlot } = {}
local leakSlots: { BurstSlot } = {}
local numberSlots: { NumberSlot } = {}
local nextBurst = 1
local nextLeak = 1
local nextNumber = 1

local projectileSlots: { ProjectileSlot } = {}
local sparkSlots: { SparkSlot } = {}
local ringSlots: { RingSlot } = {}
local placeSlots: { PlaceSlot } = {}
local nextProjectile = 1
local nextSpark = 1
local nextRing = 1
local nextPlace = 1
local activeProjectiles = 0
local projectileConnection: RBXScriptConnection? = nil
local visualCache: { [string]: UnitVisual } = {}
local evoVisualCache: { [string]: UnitVisual } = {}
local isDestroyed = false

local flashFrame: Frame? = nil
local flashTween: Tween? = nil

local bannerLabel: TextLabel? = nil
local bannerStroke: UIStroke? = nil
local bannerScale: UIScale? = nil
local bannerTweens: { Tween } = {}
local bannerToken = 0

local victoryHolder: Frame? = nil
local victoryPieces: { Frame } = {}
local victoryTokens: { number } = {}

local gradeEffect: ColorCorrectionEffect? = nil
local gradeTween: Tween? = nil

local pingSound: Sound? = nil

-- Tremor de camera (estado simples, sem tabelas).
local shakeTime = 0
local shakeDuration = 0.4
local shakeMagnitude = 0
local shakeBound = false

local function cancelAll(tweens: { Tween })
	for _, tween in tweens do
		tween:Cancel()
	end
	table.clear(tweens)
end

local function randomColor(): Color3
	return PALETTE[math.random(1, #PALETTE)]
end

local function playPing(volume: number, minSpeed: number, maxSpeed: number)
	local sound = pingSound
	if not SOUND_ENABLED or not sound then
		return
	end
	sound.Volume = volume
	sound.PlaybackSpeed = minSpeed + math.random() * (maxSpeed - minSpeed) -- varia o tom para nao cansar
	sound:Play()
end

-- ---------------------------------------------------------------------------
-- Confete 3D (pool de Parts com ParticleEmitters)
-- ---------------------------------------------------------------------------

local function makeBurstSlot(
	folder: Folder,
	colors: { Color3 },
	speedMax: number,
	sizeMax: number
): BurstSlot
	-- ParticleEmitter precisa de um Part "normal" (invisivel e sem colisao).
	local part = Instance.new("Part")
	part.Name = "BurstSlot"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Position = Vector3.new(0, -500, 0) -- guardado longe ate ser usado
	part.Parent = folder

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local emitters: { ParticleEmitter } = {}
	for i, color in colors do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false -- so solta particulas quando chamamos :Emit()
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(0.6, 1.2)
		emitter.Speed = NumberRange.new(speedMax * 0.4, speedMax)
		emitter.SpreadAngle = Vector2.new(360, 360)
		emitter.Acceleration = Vector3.new(0, -60, 0)
		emitter.Drag = 2
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-300, 300)
		emitter.LightEmission = 0.6
		emitter.LightInfluence = 0
		emitter.Size = NumberSequence.new(sizeMax, 0)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		-- Gradiente da cor para a proxima cor da paleta: cada pedacinho muda de cor ao cair.
		emitter.Color = ColorSequence.new(color, colors[i % #colors + 1])
		emitter.Parent = attachment
		table.insert(emitters, emitter)
	end

	-- Um brilho rapido de luz (so 1 PointLight por slot, sem sombras: barato).
	local light = Instance.new("PointLight")
	light.Range = 12
	light.Brightness = 0
	light.Shadows = false
	light.Parent = part

	return { part = part, emitters = emitters, light = light, lightTween = nil }
end

local function burst(
	slots: { BurstSlot },
	index: number,
	position: Vector3,
	perColor: number,
	lightColor: Color3
)
	local slot = slots[index]
	slot.part.Position = position
	for _, emitter in slot.emitters do
		emitter:Emit(perColor)
	end
	local old = slot.lightTween
	if old then
		old:Cancel()
	end
	slot.light.Color = lightColor
	slot.light.Brightness = 4
	local tween = TweenService:Create(slot.light, LIGHT_FADE, { Brightness = 0 })
	slot.lightTween = tween
	tween:Play()
end

-- ---------------------------------------------------------------------------
-- Numeros flutuantes (pool de BillboardGuis)
-- ---------------------------------------------------------------------------

local function makeNumberSlot(folder: Folder): NumberSlot
	local part = Instance.new("Part")
	part.Name = "NumberSlot"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Position = Vector3.new(0, -500, 0)
	part.Parent = folder

	local gui = Instance.new("BillboardGui")
	gui.Adornee = part
	gui.Size = UDim2.fromScale(5, 2) -- em studs
	gui.AlwaysOnTop = true
	gui.MaxDistance = 200
	gui.Active = false
	gui.Enabled = false
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = ""
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = gui

	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 12
	limit.MaxTextSize = 60
	limit.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = DARK
	stroke.Thickness = 3
	stroke.Parent = label

	local scale = Instance.new("UIScale")
	scale.Parent = label

	return {
		part = part,
		gui = gui,
		label = label,
		scale = scale,
		stroke = stroke,
		token = 0,
		tweens = {},
	}
end

-- color e popScale sao opcionais: sem eles, cor aleatoria da paleta e pop normal.
local function showNumber(position: Vector3, text: string, color: Color3?, popScale: number?)
	local slot = numberSlots[nextNumber]
	nextNumber = nextNumber % #numberSlots + 1 -- se todos estao em uso, reaproveita o mais antigo

	slot.token += 1
	local myToken = slot.token
	cancelAll(slot.tweens)

	slot.part.Position = position
		+ Vector3.new((math.random() - 0.5) * 3, 1, (math.random() - 0.5) * 3)
	slot.gui.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	slot.label.Text = text
	slot.label.TextColor3 = color or randomColor()
	slot.label.TextTransparency = 0
	slot.stroke.Transparency = 0
	slot.scale.Scale = 0.2
	slot.gui.Enabled = true

	local pop = TweenService:Create(slot.scale, NUMBER_POP, { Scale = popScale or 1.2 })
	local rise =
		TweenService:Create(slot.gui, NUMBER_RISE, { StudsOffsetWorldSpace = Vector3.new(0, 6, 0) })
	local fadeText = TweenService:Create(slot.label, NUMBER_FADE, { TextTransparency = 1 })
	local fadeStroke = TweenService:Create(slot.stroke, NUMBER_FADE, { Transparency = 1 })
	table.insert(slot.tweens, pop)
	table.insert(slot.tweens, rise)
	table.insert(slot.tweens, fadeText)
	table.insert(slot.tweens, fadeStroke)

	fadeText.Completed:Once(function()
		if slot.token == myToken then
			slot.gui.Enabled = false
		end
	end)
	pop:Play()
	rise:Play()
	fadeText:Play()
	fadeStroke:Play()
end

-- ---------------------------------------------------------------------------
-- Visual das unidades (lido do Config, com valores reserva)
-- ---------------------------------------------------------------------------

local function styleFromName(name: unknown, kind: string): number
	if name == "Shuriken" then
		return STYLE_SHURIKEN
	elseif name == "Slash" then
		return STYLE_SLASH
	elseif name == "Orb" then
		return STYLE_ORB
	end
	-- Sem Config: adivinha pelo nome do tipo para o efeito ainda fazer sentido.
	if kind == "Ninja" then
		return STYLE_SHURIKEN
	elseif kind == "Samurai" then
		return STYLE_SLASH
	end
	return STYLE_ORB
end

-- Guardamos o resultado numa tabela (cache) para nao recalcular a cada ataque.
local function getVisual(kind: string): UnitVisual
	local cached = visualCache[kind]
	if cached then
		return cached
	end
	local entry: any = nil
	local units: any = Config.UNITS
	if typeof(units) == "table" then
		entry = units[kind]
	end
	local visual: UnitVisual
	if typeof(entry) == "table" then
		visual = {
			style = styleFromName(entry.attackStyle, kind),
			color = if typeof(entry.color) == "Color3" then entry.color else PALETTE[5],
			accent = if typeof(entry.accentColor) == "Color3"
				then entry.accentColor
				else PALETTE[2],
			splash = if typeof(entry.splashRadius) == "number" then entry.splashRadius else 0,
			height = if typeof(entry.height) == "number" then entry.height else 4,
		}
	else
		visual = {
			style = styleFromName(nil, kind),
			color = PALETTE[5],
			accent = PALETTE[2],
			splash = 0,
			height = 4,
		}
	end
	visualCache[kind] = visual
	return visual
end

-- Visual do Lv4: igual ao normal, mas com a cor da evolucao e o splash do nivel 4.
-- Tambem fica em cache (uma tabela por tipo, criada so na primeira vez).
local function getEvoVisual(kind: string): UnitVisual
	local cached = evoVisualCache[kind]
	if cached then
		return cached
	end
	local base = getVisual(kind)
	local accent = base.accent
	local splash = base.splash
	local entry: any = nil
	local units: any = Config.UNITS
	if typeof(units) == "table" then
		entry = units[kind]
	end
	if typeof(entry) == "table" and typeof(entry.upgrades) == "table" then
		local lastLevel: any = entry.upgrades[Config.MAX_UNIT_LEVEL - 1]
		if typeof(lastLevel) == "table" then
			if typeof(lastLevel.splashRadius) == "number" then
				splash = lastLevel.splashRadius
			end
			if
				typeof(lastLevel.evolution) == "table"
				and typeof(lastLevel.evolution.accentColor) == "Color3"
			then
				accent = lastLevel.evolution.accentColor
			end
		end
	end
	local visual: UnitVisual = {
		style = base.style,
		color = base.color,
		accent = accent,
		splash = splash,
		height = base.height,
	}
	evoVisualCache[kind] = visual
	return visual
end

local function getMaxLevel(): number
	local value: any = Config.MAX_UNIT_LEVEL
	if typeof(value) == "number" and value >= 1 then
		return math.floor(value)
	end
	return DEFAULT_MAX_LEVEL
end

-- Acha o modelo da unidade pelo id (o servidor nomeia o modelo com o id). Pode nao existir (ja vendida).
local function findUnitModel(id: string): Instance?
	local units = workspace:FindFirstChild("Units")
	if units then
		return units:FindFirstChild(id)
	end
	return nil
end

-- Visual certo para um ataque: evoluida (Lv4) usa a cor da evolucao.
local function visualFor(id: string, kind: string): UnitVisual
	local model = findUnitModel(id)
	if model then
		local level = model:GetAttribute("Level")
		if typeof(level) == "number" and level >= getMaxLevel() then
			return getEvoVisual(kind)
		end
	end
	return getVisual(kind)
end

-- ---------------------------------------------------------------------------
-- Faiscas de impacto (pool: 1 emissor + 1 luz por slot)
-- ---------------------------------------------------------------------------

local function makeSparkSlot(folder: Folder): SparkSlot
	local part = Instance.new("Part")
	part.Name = "SparkSlot"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Position = HIDDEN_POSITION
	part.Parent = folder

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.2, 0.45)
	emitter.Speed = NumberRange.new(14, 34)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Drag = 4
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new(0.55, 0)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = attachment

	local light = Instance.new("PointLight")
	light.Range = 10
	light.Brightness = 0
	light.Shadows = false
	light.Parent = part

	return { part = part, emitter = emitter, light = light, lightTween = nil }
end

local function spark(position: Vector3, color: Color3, count: number)
	local slot = sparkSlots[nextSpark]
	nextSpark = nextSpark % #sparkSlots + 1
	slot.part.Position = position
	-- Particulas nascem com a cor do momento: assim cada unidade solta faiscas da sua cor.
	slot.emitter.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(color, 0.5), color)
	slot.emitter:Emit(count)
	local old = slot.lightTween
	if old then
		old:Cancel()
	end
	slot.light.Color = color
	slot.light.Brightness = 3
	local tween = TweenService:Create(slot.light, LIGHT_FADE, { Brightness = 0 })
	slot.lightTween = tween
	tween:Play()
end

-- ---------------------------------------------------------------------------
-- Aneis de explosao (pool de cilindros finos, deitados no chao)
-- ---------------------------------------------------------------------------

local RING_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function makeRingSlot(folder: Folder): RingSlot
	local part = Instance.new("Part")
	part.Name = "RingSlot"
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.3, 1, 1)
	part.Position = HIDDEN_POSITION
	part.Parent = folder
	return { part = part, tweens = {} }
end

-- O cilindro do Roblox tem o eixo no X; girar 90 graus em Z deixa ele "deitado" (fino na vertical).
local FLAT = CFrame.Angles(0, 0, math.rad(90))

local function playRing(
	slot: RingSlot,
	position: Vector3,
	color: Color3,
	diameter: number,
	info: TweenInfo
)
	cancelAll(slot.tweens)
	local part = slot.part
	part.Color = color
	part.Size = Vector3.new(0.35, 1, 1)
	part.Transparency = 0.15
	part.CFrame = CFrame.new(position) * FLAT
	local grow = TweenService:Create(
		part,
		info,
		{ Size = Vector3.new(0.35, diameter, diameter), Transparency = 1 }
	)
	table.insert(slot.tweens, grow)
	grow:Play()
end

-- Anel que SOBE enquanto cresce (explosao de upgrade): CFrame e Size animam juntos num tween so.
local function playRingRise(
	slot: RingSlot,
	position: Vector3,
	color: Color3,
	diameter: number,
	rise: number,
	info: TweenInfo
)
	cancelAll(slot.tweens)
	local part = slot.part
	part.Color = color
	part.Size = Vector3.new(0.35, 1, 1)
	part.Transparency = 0.15
	part.CFrame = CFrame.new(position) * FLAT
	local grow = TweenService:Create(part, info, {
		Size = Vector3.new(0.35, diameter, diameter),
		Transparency = 1,
		CFrame = CFrame.new(position + Vector3.new(0, rise, 0)) * FLAT,
	})
	table.insert(slot.tweens, grow)
	grow:Play()
end

-- Anel que ENCOLHE ate o centro (venda: a unidade "implode").
local function playRingShrink(
	slot: RingSlot,
	position: Vector3,
	color: Color3,
	diameter: number,
	info: TweenInfo
)
	cancelAll(slot.tweens)
	local part = slot.part
	part.Color = color
	part.Size = Vector3.new(0.35, diameter, diameter)
	part.Transparency = 0.15
	part.CFrame = CFrame.new(position) * FLAT
	local shrink =
		TweenService:Create(part, info, { Size = Vector3.new(0.35, 0.6, 0.6), Transparency = 1 })
	table.insert(slot.tweens, shrink)
	shrink:Play()
end

-- rise e opcional: com ele o anel sobe enquanto cresce.
local function ring(position: Vector3, color: Color3, diameter: number, rise: number?)
	local slot = ringSlots[nextRing]
	nextRing = nextRing % #ringSlots + 1
	if rise then
		playRingRise(slot, position, color, diameter, rise, RING_INFO)
	else
		playRing(slot, position, color, diameter, RING_INFO)
	end
end

-- ---------------------------------------------------------------------------
-- Projeteis das unidades (pool de 2 pecas por slot + UM loop so enquanto houver ataque)
-- ---------------------------------------------------------------------------

local function makeEffectPart(folder: Folder, name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.5
	part.Position = HIDDEN_POSITION
	part.Parent = folder
	return part
end

local function makeProjectileSlot(folder: Folder): ProjectileSlot
	return {
		part = makeEffectPart(folder, "ProjectileSlot"),
		aux = makeEffectPart(folder, "ProjectileAux"),
		active = false,
		style = STYLE_SHURIKEN,
		t = 0,
		duration = 0.2,
		from = Vector3.zero,
		to = Vector3.zero,
		base = CFrame.new(),
		arc = 0,
		visual = getVisual("Ninja"),
	}
end

local function finishProjectile(slot: ProjectileSlot)
	slot.active = false
	slot.part.Transparency = 1
	slot.aux.Transparency = 1
	activeProjectiles -= 1
	local accent = slot.visual.accent
	if slot.style == STYLE_ORB then
		-- Orb: anel no tamanho da area de dano + um pouco de confete.
		local diameter = if slot.visual.splash > 0 then slot.visual.splash * 2 else 5
		-- Anel no chao (to e o centro do inimigo, no ar); a faisca fica no inimigo.
		ring(Vector3.new(slot.to.X, 0.3, slot.to.Z), accent, diameter)
		spark(slot.to, accent, 14)
		burst(burstSlots, nextBurst, slot.to, 2, accent)
		nextBurst = nextBurst % #burstSlots + 1
	elseif slot.style == STYLE_SLASH then
		spark(slot.to, Color3.new(1, 1, 1), 12)
	else
		spark(slot.to, accent, 8)
	end
end

local function onProjectileStep(dt: number)
	for _, slot in projectileSlots do
		if not slot.active then
			continue
		end
		slot.t += dt
		local a = slot.t / slot.duration
		if a >= 1 then
			finishProjectile(slot)
			continue
		end
		local style = slot.style
		if style == STYLE_SHURIKEN then
			local cf = CFrame.new(slot.from:Lerp(slot.to, a)) * CFrame.Angles(0, slot.t * 45, 0)
			slot.part.CFrame = cf
			slot.aux.CFrame = cf * CFrame.Angles(0, math.rad(90), 0)
		elseif style == STYLE_SLASH then
			-- Gira em volta do eixo de frente: parece um talho cruzando o inimigo.
			local eased = 1 - (1 - a) * (1 - a)
			local angle = -1.2 + 2.4 * eased
			local cf = slot.base * CFrame.Angles(0, 0, angle)
			slot.part.CFrame = cf
			slot.aux.CFrame = cf
			local fade = 0.1 + 0.9 * a * a
			slot.part.Transparency = fade
			slot.aux.Transparency = fade
		else
			local pos = slot.from:Lerp(slot.to, a) + Vector3.new(0, slot.arc * 4 * a * (1 - a), 0)
			local cf = CFrame.new(pos)
			slot.part.CFrame = cf
			slot.aux.CFrame = cf
		end
	end
	if activeProjectiles <= 0 then
		-- Nada voando: desliga o loop (nao gasta nada parado).
		local connection = projectileConnection
		if connection then
			connection:Disconnect()
			projectileConnection = nil
		end
	end
end

local function launchProjectile(visual: UnitVisual, from: Vector3, to: Vector3): boolean
	local count = #projectileSlots
	local slot: ProjectileSlot? = nil
	for i = 0, count - 1 do
		local index = (nextProjectile + i - 1) % count + 1
		local candidate = projectileSlots[index]
		if not candidate.active then
			slot = candidate
			nextProjectile = index % count + 1
			break
		end
	end
	if not slot then
		return false -- limite atingido: melhor perder um efeito do que travar o celular
	end

	local delta = to - from
	local distance = delta.Magnitude
	local part = slot.part
	local aux = slot.aux
	local accent = visual.accent

	slot.visual = visual
	slot.style = visual.style
	slot.t = 0
	slot.from = from
	slot.to = to
	part.Color = accent

	if visual.style == STYLE_SHURIKEN then
		slot.duration = math.clamp(distance / 90, 0.12, 0.2)
		part.Shape = Enum.PartType.Block
		aux.Shape = Enum.PartType.Block
		part.Size = Vector3.new(1.3, 0.1, 0.3)
		aux.Size = Vector3.new(1.3, 0.1, 0.3)
		aux.Color = Color3.new(1, 1, 1)
		part.Transparency = 0
		aux.Transparency = 0
		part.CFrame = CFrame.new(from)
		aux.CFrame = CFrame.new(from)
	elseif visual.style == STYLE_SLASH then
		slot.duration = 0.2
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude < 0.01 then
			flat = Vector3.zAxis
		end
		slot.base = CFrame.lookAt(to, to + flat.Unit)
		part.Shape = Enum.PartType.Block
		aux.Shape = Enum.PartType.Block
		part.Size = Vector3.new(5, 0.16, 0.6)
		aux.Size = Vector3.new(5.4, 0.07, 0.22)
		aux.Color = Color3.new(1, 1, 1)
		part.Transparency = 0.1
		aux.Transparency = 0.1
		part.CFrame = slot.base
		aux.CFrame = slot.base
		spark(to, Color3.new(1, 1, 1), 4) -- clarao branco logo no inicio do talho
	else
		slot.duration = math.clamp(distance / 45, 0.25, 0.45)
		slot.arc = 3 + distance * 0.15
		part.Shape = Enum.PartType.Ball
		aux.Shape = Enum.PartType.Ball
		part.Size = Vector3.one * 1.4
		aux.Size = Vector3.one * 2.6
		aux.Color = accent
		part.Transparency = 0
		aux.Transparency = 0.65
		part.CFrame = CFrame.new(from)
		aux.CFrame = CFrame.new(from)
	end

	slot.active = true
	activeProjectiles += 1
	if not projectileConnection then
		projectileConnection = RunService.Heartbeat:Connect(onProjectileStep)
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Explosao de luz ao colocar uma unidade (pool de esfera + pilar + anel + luz)
-- ---------------------------------------------------------------------------

local SPHERE_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PILLAR_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PLACE_RING_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function makePlaceSlot(folder: Folder): PlaceSlot
	local sphere = makeEffectPart(folder, "PlaceSphere")
	sphere.Shape = Enum.PartType.Ball

	local pillar = makeEffectPart(folder, "PlacePillar")
	pillar.Shape = Enum.PartType.Cylinder

	local light = Instance.new("PointLight")
	light.Range = 26
	light.Brightness = 0
	light.Shadows = false
	light.Parent = sphere

	return {
		sphere = sphere,
		pillar = pillar,
		ring = makeRingSlot(folder),
		light = light,
		tweens = {},
	}
end

-- power (opcional, padrao 1) aumenta tudo; pillarMix (opcional) = quanto da cor entra no pilar
-- (0 = pilar todo branco, 1 = pilar todo colorido). A evolucao usa power alto e pilar quase branco.
local function placeExplosion(
	position: Vector3,
	visual: UnitVisual,
	power: number?,
	pillarMix: number?
)
	local slot = placeSlots[nextPlace]
	nextPlace = nextPlace % #placeSlots + 1
	cancelAll(slot.tweens)

	local accent = visual.accent
	local strength = power or 1

	-- Esfera de luz que cresce e some.
	slot.sphere.Color = accent
	slot.sphere.Size = Vector3.one * 1.5
	slot.sphere.Transparency = 0.2
	-- position e o pe da unidade: centra a esfera na altura do corpo.
	slot.sphere.Position = position + Vector3.new(0, visual.height * 0.5, 0)
	local grow = TweenService:Create(
		slot.sphere,
		SPHERE_INFO,
		{ Size = Vector3.one * 11 * strength, Transparency = 1 }
	)

	-- Pilar de luz vertical (cilindro em pe: Size.X e a altura).
	local pillarHeight = 18 * strength
	slot.pillar.Color = Color3.new(1, 1, 1):Lerp(accent, pillarMix or 0.4)
	slot.pillar.Size = Vector3.new(pillarHeight, 4 * strength, 4 * strength)
	slot.pillar.Transparency = 0.2
	slot.pillar.CFrame = CFrame.new(position + Vector3.new(0, pillarHeight * 0.5 + 0.2, 0)) * FLAT
	-- So a espessura encolhe; o comprimento fica fixo para a base nao afundar no chao.
	local rise = TweenService:Create(
		slot.pillar,
		PILLAR_INFO,
		{ Size = Vector3.new(pillarHeight, 0.4, 0.4), Transparency = 1 }
	)

	-- Flash de luz.
	slot.light.Color = accent
	slot.light.Brightness = 8
	local flash = TweenService:Create(slot.light, LIGHT_FADE, { Brightness = 0 })

	table.insert(slot.tweens, grow)
	table.insert(slot.tweens, rise)
	table.insert(slot.tweens, flash)
	grow:Play()
	rise:Play()
	flash:Play()

	-- Anel no chao (usa o proprio anel do slot, reservado para esta explosao).
	cancelAll(slot.ring.tweens)
	playRing(slot.ring, position + Vector3.new(0, 0.35, 0), accent, 14 * strength, PLACE_RING_INFO)
end

-- Antecipacao da evolucao: uma esfera de luz grande e fraca SUGA para dentro da unidade (0.25 s).
local function anticipationGlow(position: Vector3, visual: UnitVisual)
	local slot = placeSlots[nextPlace]
	nextPlace = nextPlace % #placeSlots + 1
	cancelAll(slot.tweens)

	slot.sphere.Color = Color3.new(1, 1, 1):Lerp(visual.accent, 0.5)
	slot.sphere.Size = Vector3.one * 9
	slot.sphere.Transparency = 0.5
	slot.sphere.Position = position + Vector3.new(0, visual.height * 0.5, 0)
	local info = TweenInfo.new(EVOLVE_ANTICIPATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	-- Termina invisivel (Transparency 1), entao nao precisa limpar nada depois.
	local pull =
		TweenService:Create(slot.sphere, info, { Size = Vector3.one * 2, Transparency = 1 })
	slot.light.Color = visual.accent
	slot.light.Brightness = 2
	local glow = TweenService:Create(slot.light, info, { Brightness = 8 })
	-- A explosao usa o PROXIMO slot, entao esta luz (alcance 26) ficaria acesa ate ser reusada:
	-- apagamos ao terminar. So no Completed (um Cancelled significa que o slot ja foi reusado).
	glow.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			slot.light.Brightness = 0
		end
	end)
	table.insert(slot.tweens, pull)
	table.insert(slot.tweens, glow)
	pull:Play()
	glow:Play()
end

-- Venda: esfera dourada e anel encolhem ate o centro (implode).
local IMPLODE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function implodeEffect(position: Vector3, height: number)
	local slot = placeSlots[nextPlace]
	nextPlace = nextPlace % #placeSlots + 1
	cancelAll(slot.tweens)

	local center = position + Vector3.new(0, height * 0.5, 0)
	slot.sphere.Color = COIN_COLOR
	slot.sphere.Size = Vector3.one * 9
	slot.sphere.Transparency = 0.5
	slot.sphere.Position = center
	local shrink = TweenService:Create(
		slot.sphere,
		IMPLODE_INFO,
		{ Size = Vector3.one * 0.8, Transparency = 1 }
	)
	slot.light.Color = COIN_COLOR
	slot.light.Brightness = 5
	local flash = TweenService:Create(slot.light, IMPLODE_INFO, { Brightness = 0 })
	table.insert(slot.tweens, shrink)
	table.insert(slot.tweens, flash)
	shrink:Play()
	flash:Play()

	playRingShrink(slot.ring, position + Vector3.new(0, 0.35, 0), COIN_COLOR, 12, IMPLODE_INFO)
end

-- ---------------------------------------------------------------------------
-- Tremor de camera
-- ---------------------------------------------------------------------------

local function stopShake()
	if shakeBound then
		shakeBound = false
		RunService:UnbindFromRenderStep(SHAKE_BIND_NAME)
	end
end

local function onShakeStep(dt: number)
	shakeTime += dt
	local alpha = 1 - shakeTime / shakeDuration
	if alpha <= 0 then
		-- Acabou: desliga o passo de render para nunca brigar com a camera.
		stopShake()
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local magnitude = shakeMagnitude * alpha * alpha -- vai diminuindo rapido
	local offsetX = (math.random() - 0.5) * 2 * magnitude
	local offsetY = (math.random() - 0.5) * 2 * magnitude
	local roll = (math.random() - 0.5) * 0.04 * alpha
	-- Deslocamento em cima da camera padrao, que se recalcula todo frame (nao acumula).
	camera.CFrame = camera.CFrame * CFrame.new(offsetX, offsetY, 0) * CFrame.Angles(0, 0, roll)
end

local function startShake(magnitude: number, duration: number)
	shakeTime = 0
	shakeDuration = duration
	shakeMagnitude = magnitude
	if not shakeBound then
		shakeBound = true
		-- Prioridade logo DEPOIS da camera: ela calcula primeiro, nos deslocamos depois.
		RunService:BindToRenderStep(
			SHAKE_BIND_NAME,
			Enum.RenderPriority.Camera.Value + 1,
			onShakeStep
		)
	end
end

-- ---------------------------------------------------------------------------
-- Flash vermelho, banner e confete de UI
-- ---------------------------------------------------------------------------

local function redFlash()
	local frame = flashFrame
	if not frame then
		return
	end
	local old = flashTween
	if old then
		old:Cancel()
	end
	frame.BackgroundTransparency = 0.55
	local tween = TweenService:Create(frame, FLASH_FADE, { BackgroundTransparency = 1 })
	flashTween = tween
	tween:Play()
end

local function showBanner(text: string, fill: Color3, outline: Color3, hold: number)
	local label = bannerLabel
	local stroke = bannerStroke
	local scale = bannerScale
	if not label or not stroke or not scale then
		return
	end

	bannerToken += 1
	local myToken = bannerToken
	cancelAll(bannerTweens)

	label.Text = text
	label.TextColor3 = fill
	label.TextTransparency = 0
	stroke.Color = outline
	stroke.Transparency = 0
	scale.Scale = 0
	label.Visible = true

	-- Entra com "pop" (Back passa um pouco do tamanho e volta).
	local pop = TweenService:Create(scale, POP_IN, { Scale = 1 })
	table.insert(bannerTweens, pop)
	pop:Play()

	-- Depois de um tempo, some. Se outro banner chegar antes, o token mudou e nada acontece.
	task.delay(hold, function()
		if bannerToken ~= myToken then
			return
		end
		local fadeText = TweenService:Create(label, BANNER_FADE, { TextTransparency = 1 })
		local fadeStroke = TweenService:Create(stroke, BANNER_FADE, { Transparency = 1 })
		table.insert(bannerTweens, fadeText)
		table.insert(bannerTweens, fadeStroke)
		fadeText.Completed:Once(function()
			if bannerToken == myToken then
				label.Visible = false
			end
		end)
		fadeText:Play()
		fadeStroke:Play()
	end)
end

local function launchVictoryConfetti()
	local holder = victoryHolder
	if not holder then
		return
	end
	-- Cria os pedacinhos so na primeira vitoria; depois reaproveita os mesmos.
	if #victoryPieces == 0 then
		for i = 1, VICTORY_PIECES do
			local piece = Instance.new("Frame")
			piece.Name = "Piece"
			piece.Size = UDim2.fromScale(0.012, 0.022)
			piece.BorderSizePixel = 0
			piece.Visible = false
			piece.Parent = holder
			victoryPieces[i] = piece
			victoryTokens[i] = 0
		end
	end

	for i, piece in victoryPieces do
		victoryTokens[i] += 1
		local myToken = victoryTokens[i]
		local startX = math.random()
		local startRotation = math.random(0, 360)
		piece.BackgroundColor3 = randomColor()
		piece.Position = UDim2.fromScale(startX, -0.08)
		piece.Rotation = startRotation
		piece.Visible = true

		-- DelayTime escalona a queda sem precisar de task.delay.
		local info = TweenInfo.new(
			2.2 + math.random() * 1.8,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out,
			0,
			false,
			math.random() * 0.9
		)
		local tween = TweenService:Create(piece, info, {
			Position = UDim2.fromScale(startX + (math.random() - 0.5) * 0.3, 1.08),
			Rotation = startRotation + math.random(-720, 720),
		})
		tween.Completed:Once(function()
			if victoryTokens[i] == myToken then
				piece.Visible = false
			end
		end)
		tween:Play()
	end
end

-- Cor da tela (ColorCorrection local): cinza na derrota, normal nas outras fases.
local function setGrade(saturation: number, brightness: number)
	local effect = gradeEffect
	if not effect then
		return
	end
	local old = gradeTween
	if old then
		old:Cancel()
	end
	local tween = TweenService:Create(
		effect,
		GRADE_INFO,
		{ Saturation = saturation, Brightness = brightness }
	)
	gradeTween = tween
	tween:Play()
end

-- ---------------------------------------------------------------------------
-- Eventos do servidor
-- ---------------------------------------------------------------------------

local function onEnemyDied(_id: string, reason: string, position: Vector3, reward: number)
	if typeof(position) ~= "Vector3" then
		return
	end
	if reason == "Killed" then
		burst(
			burstSlots,
			nextBurst,
			position,
			CONFETTI_PER_COLOR,
			PALETTE[math.random(1, #PALETTE)]
		)
		nextBurst = nextBurst % #burstSlots + 1
		showNumber(position, "+" .. tostring(reward))
		playPing(0.25, 1.2, 1.8)
	else
		-- Vazou: explosao vermelha pequena.
		burst(leakSlots, nextLeak, position, 5, RED)
		nextLeak = nextLeak % #leakSlots + 1
		playPing(0.2, 0.6, 0.8)
	end
end

local function onBaseHit(damage: number, _healthLeft: number)
	-- Quanto maior o dano, mais forte o tremor (com limites).
	local magnitude = math.clamp(0.4 + damage * 0.05, 0.4, 2)
	startShake(magnitude, 0.45)
	redFlash()
	playPing(0.3, 0.4, 0.55)
end

local function onWaveStarted(wave: number, _waveCount: number, isBoss: boolean)
	if isBoss then
		showBanner("BOSS WAVE!", RED, GOLD, 2)
	else
		showBanner("WAVE " .. tostring(wave), Color3.new(1, 1, 1), PALETTE[1], 1.4)
	end
	playPing(0.25, 0.9, 1.1)
end

local function onMatchEnded(result: string)
	if result == "Victory" then
		showBanner("VICTORY!", GOLD, PALETTE[1], 3.5)
		launchVictoryConfetti()
		playPing(0.3, 1.4, 1.6)
	else
		showBanner("DEFEAT", Color3.fromRGB(190, 190, 200), DARK, 3.5)
		setGrade(-0.85, -0.05)
	end
end

local function onUnitPlaced(_id: string, kind: string, position: Vector3, ownerUserId: number)
	if typeof(position) ~= "Vector3" or typeof(kind) ~= "string" then
		return
	end
	local visual = getVisual(kind)
	placeExplosion(position, visual)
	-- Confete da paleta toda (reaproveita o pool de confete que ja existe).
	burst(burstSlots, nextBurst, position + Vector3.new(0, 2, 0), CONFETTI_PER_COLOR, visual.accent)
	nextBurst = nextBurst % #burstSlots + 1
	showNumber(position + Vector3.new(0, visual.height, 0), "NEW!")
	playPing(0.3, 1.0, 1.3)
	-- Tremor so para quem colocou a unidade, bem leve.
	if ownerUserId == Players.LocalPlayer.UserId then
		startShake(0.25, 0.25)
	end
end

-- special: "Crit", "Slow" ou nil (5o argumento novo da semana 4; MultiShot manda 1 evento por alvo).
local function onUnitAttacked(
	id: string,
	kind: string,
	from: Vector3,
	to: Vector3,
	special: string?
)
	if
		typeof(id) ~= "string"
		or typeof(kind) ~= "string"
		or typeof(from) ~= "Vector3"
		or typeof(to) ~= "Vector3"
	then
		return
	end
	local visual = visualFor(id, kind) -- Lv4 usa a cor da evolucao
	launchProjectile(visual, from, to)

	if special == "Crit" then
		-- Faisca bigger + texto "CRIT!" (usa o pool de numeros, nada novo e criado).
		spark(to, CRIT_COLOR, 26)
		showNumber(to + Vector3.new(0, 1.5, 0), "CRIT!", CRIT_COLOR, 1.5)
	elseif special == "Slow" then
		-- Anel azul claro no chao com o tamanho da area de dano do Lv4.
		local diameter = if visual.splash > 0
			then visual.splash * 2
			else SLOW_RING_FALLBACK_DIAMETER
		ring(Vector3.new(to.X, 0.3, to.Z), SLOW_RING_COLOR, diameter)
	end
end

-- Upgrade: Lv2/3 = explosao subindo; Lv4 = momento de EVOLUCAO.
local function onUnitUpgraded(id: string, level: number, position: Vector3)
	if typeof(id) ~= "string" or typeof(level) ~= "number" or typeof(position) ~= "Vector3" then
		return
	end
	-- Descobre o tipo pelo modelo; se ele nao chegou, usa visual reserva (ninguem quebra).
	local model = findUnitModel(id)
	local kindValue = if model then model:GetAttribute("Kind") else nil
	local kind = if typeof(kindValue) == "string" then kindValue else "Ninja"
	local evolved = level >= getMaxLevel()
	local visual = if evolved then getEvoVisual(kind) else getVisual(kind)
	local accent = visual.accent
	local center = position + Vector3.new(0, visual.height * 0.5, 0)

	if not evolved then
		-- Lv2/3: anel que sobe + faiscas na cor da unidade + texto.
		ring(position + Vector3.new(0, 0.35, 0), accent, 9 + level * 2, visual.height)
		spark(center, accent, 20)
		showNumber(
			position + Vector3.new(0, visual.height, 0),
			"LV " .. tostring(level) .. "!",
			accent,
			1.3
		)
		playPing(0.3, 0.9 + level * 0.15, 1.2 + level * 0.15)
		return
	end

	-- Lv4: primeiro a antecipacao (0.25 s), depois a explosao grande.
	anticipationGlow(position, visual)
	playPing(0.2, 0.6, 0.7)
	task.delay(EVOLVE_ANTICIPATION, function()
		if isDestroyed then
			return
		end
		-- Flash: pilar quase todo branco + esfera + anel (placeExplosion), com forca extra.
		placeExplosion(position, visual, EVOLVE_POWER, 0.15)
		-- Anel duplo: um colorido subindo e um branco menor logo atras.
		ring(position + Vector3.new(0, 0.5, 0), accent, 24, visual.height)
		ring(position + Vector3.new(0, 0.5, 0), Color3.new(1, 1, 1), 14)
		-- Confete (reaproveita o pool) e faiscas.
		burst(burstSlots, nextBurst, center, CONFETTI_PER_COLOR * 2, accent)
		nextBurst = nextBurst % #burstSlots + 1
		spark(center, accent, 30)
		showNumber(position + Vector3.new(0, visual.height + 1, 0), "EVOLVED!", accent, 1.6)
		playPing(0.35, 1.4, 1.7)
		-- Tremor pequeno e curto, so se a camera esta perto.
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - position).Magnitude < EVOLVE_SHAKE_RANGE then
			startShake(0.3, 0.3)
		end
	end)
end

-- Venda: implode + moedinhas. O texto "+$" so aparece para o dono da unidade.
local function onUnitSold(
	id: string,
	position: Vector3,
	refund: number,
	ownerUserId: number,
	kind: string?
)
	if typeof(id) ~= "string" or typeof(position) ~= "Vector3" or typeof(refund) ~= "number" then
		return
	end
	-- O servidor remove o modelo ANTES de avisar, entao o tipo vem no proprio evento.
	-- O modelo fica so como plano B; sem nenhum dos dois, usa altura reserva.
	local kindValue: unknown = kind
	if typeof(kindValue) ~= "string" then
		local model = findUnitModel(id)
		kindValue = if model then model:GetAttribute("Kind") else nil
	end
	local height = if typeof(kindValue) == "string" then getVisual(kindValue).height else 4
	local center = position + Vector3.new(0, height * 0.5, 0)

	implodeEffect(position, height)
	playPing(0.25, 0.7, 0.9)
	-- As moedas saltam quando a implosao termina.
	task.delay(0.28, function()
		if isDestroyed then
			return
		end
		spark(center, COIN_COLOR, 24)
		spark(center, Color3.new(1, 1, 1), 8)
		playPing(0.3, 1.6, 2)
	end)
	if ownerUserId == Players.LocalPlayer.UserId then
		showNumber(
			position + Vector3.new(0, height, 0),
			"+$" .. tostring(math.floor(refund)),
			COIN_COLOR,
			1.3
		)
	end
end

local function makeLabelBase(parent: Instance): (TextLabel, UIStroke, UIScale)
	local label = Instance.new("TextLabel")
	label.Name = "Banner"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.35)
	label.Size = UDim2.fromScale(0.6, 0.16)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = ""
	label.ZIndex = 10 -- acima do confete e do flash
	label.Visible = false
	label.Parent = parent

	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 14
	limit.MaxTextSize = 110
	limit.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Parent = label

	local scale = Instance.new("UIScale")
	scale.Parent = label

	return label, stroke, scale
end

function FxController.init() end

function FxController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Pasta local no workspace para as pecas dos efeitos (so este jogador ve).
	local folder = Instance.new("Folder")
	folder.Name = "ClientFx"
	folder.Parent = workspace
	fxFolder = folder

	for _ = 1, BURST_POOL_SIZE do
		table.insert(burstSlots, makeBurstSlot(folder, PALETTE, 45, 0.7))
	end
	local leakColors: { Color3 } = { RED, Color3.fromRGB(255, 140, 40) }
	for _ = 1, LEAK_POOL_SIZE do
		table.insert(leakSlots, makeBurstSlot(folder, leakColors, 25, 0.5))
	end
	for _ = 1, NUMBER_POOL_SIZE do
		table.insert(numberSlots, makeNumberSlot(folder))
	end

	for _ = 1, PROJECTILE_POOL_SIZE do
		table.insert(projectileSlots, makeProjectileSlot(folder))
	end
	for _ = 1, SPARK_POOL_SIZE do
		table.insert(sparkSlots, makeSparkSlot(folder))
	end
	for _ = 1, RING_POOL_SIZE do
		table.insert(ringSlots, makeRingSlot(folder))
	end
	for _ = 1, PLACE_POOL_SIZE do
		table.insert(placeSlots, makePlaceSlot(folder))
	end

	-- Interface dos efeitos: tela cheia (IgnoreGuiInset) para o flash cobrir tudo.
	local gui = Instance.new("ScreenGui")
	gui.Name = "Fx"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Parent = playerGui

	local flash = Instance.new("Frame")
	flash.Name = "RedFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = RED
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Active = false
	flash.ZIndex = 1
	flash.Parent = gui
	flashFrame = flash

	local holder = Instance.new("Frame")
	holder.Name = "VictoryConfetti"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Active = false
	holder.ZIndex = 5
	holder.Parent = gui
	victoryHolder = holder

	bannerLabel, bannerStroke, bannerScale = makeLabelBase(gui)

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "TokyoBurstGrade"
	grade.Parent = Lighting
	gradeEffect = grade

	if SOUND_ENABLED then
		local sound = Instance.new("Sound")
		sound.Name = "FxPing"
		sound.SoundId = SOUND_ID
		sound.Volume = 0.25
		sound.Parent = SoundService
		pingSound = sound
	end

	-- Remotes: Net.event espera o servidor criar (tempo limite dentro do Net).
	table.insert(connections, Net.event("EnemyDied").OnClientEvent:Connect(onEnemyDied))
	table.insert(connections, Net.event("BaseHit").OnClientEvent:Connect(onBaseHit))
	table.insert(connections, Net.event("WaveStarted").OnClientEvent:Connect(onWaveStarted))
	table.insert(connections, Net.event("MatchEnded").OnClientEvent:Connect(onMatchEnded))
	table.insert(connections, Net.event("UnitPlaced").OnClientEvent:Connect(onUnitPlaced))
	table.insert(connections, Net.event("UnitAttacked").OnClientEvent:Connect(onUnitAttacked))

	-- Sai do modo cinza assim que a partida deixa o estado Defeat (ex.: reiniciou).
	local matchState = ReplicatedStorage:WaitForChild("MatchState", 30)
	if matchState then
		table.insert(
			connections,
			matchState:GetAttributeChangedSignal("State"):Connect(function()
				if matchState:GetAttribute("State") ~= "Defeat" then
					setGrade(0, 0)
				end
			end)
		)
	end

	-- Eventos da semana 4 por ultimo: se o servidor ainda nao criou o remote, o resto ja esta ligado.
	table.insert(connections, Net.event("UnitUpgraded").OnClientEvent:Connect(onUnitUpgraded))
	table.insert(connections, Net.event("UnitSold").OnClientEvent:Connect(onUnitSold))
end

-- Limpeza explicita (nao usada no jogo normal): desliga tudo e solta a camera.
function FxController.destroy()
	isDestroyed = true -- os task.delay pendentes (evolucao/venda) conferem isto e nao fazem nada
	stopShake()
	local projectileLoop = projectileConnection
	if projectileLoop then
		projectileLoop:Disconnect()
		projectileConnection = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if fxFolder then
		fxFolder:Destroy()
	end
	if gradeEffect then
		gradeEffect:Destroy()
	end
end

return FxController
