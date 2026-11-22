--!strict
-- UnitFxController: "vida" das unidades (so no cliente, so visual).
-- Faz estas coisas com UM unico loop de RenderStepped:
--   1) pop-in: unidade nova cresce de 0.2 ate 1 com efeito "Back" (passa um pouco e volta);
--   2) pulso: o ataque faz a unidade dar uma "inchada" rapida (1 -> 1.08 -> 1);
--   3) idle: partes neon pulsam de leve e o orb do Mage flutua (se der para mexer nele);
--   4) nivel (semana 4): o atributo "Level" do modelo muda o brilho da unidade (Lv1 a Lv4).
-- Para ficar leve no celular: listas de partes sao criadas UMA vez por unidade (no registro),
-- e o loop nao cria tabelas nem Instances. Nada de Highlight (o Roblox so desenha 31 por vez).
--
-- REGRA DE ESCALA: cada unidade tem uma escala-base (1, ou 1.12 quando evoluida no Lv4).
-- Todo efeito de escala (pop-in, pulso) e MULTIPLICADO pela base. Nunca fazemos ScaleTo(1)
-- direto, senao uma unidade evoluida encolheria de volta.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
-- Config como "any": os dados de upgrades podem nao existir ainda; lemos com cuidado.
local Config = require(Shared:WaitForChild("Config")) :: any

local POP_START_SCALE = 0.2
local POP_DURATION = 0.45
local PULSE_DURATION = 0.18
local PULSE_STRENGTH = 0.08
local PULSE_SPEED = 3 -- velocidade do brilho neon
local PULSE_DEPTH = 0.3 -- o quanto o neon fica transparente no ponto mais fraco
local BOB_HEIGHT = 0.35 -- studs que o orb sobe e desce
local BOB_SPEED = 2.2
local PULSE_WRITE_INTERVAL = 1 / 30 -- neon nao precisa de 60 Hz; economiza escritas de propriedade

-- Niveis (semana 4).
local DEFAULT_MAX_LEVEL = 4
local EVOLVED_SCALE = 1.12 -- escala-base do Lv4
local GROW_DURATION = 0.4 -- tempo do "pop" de 1 ate 1.12
local EVOLVE_ANTICIPATION = 0.25 -- espera antes do pop (o FxController faz o brilho de antecipacao)
local BRIGHTEN_AMOUNT = 0.35 -- Lv2/3: o quanto a cor clareia em direcao ao branco
local ACCENT_MATCH_DISTANCE = 0.45 -- parte "de acento" = cor parecida com a cor de acento da unidade
local RING_DIAMETER = 4.4 -- anel de rank em volta do pedestal (que tem 3.2)
local RING_THICKNESS = 0.2
local RING_LIFT = 0.15 -- levanta um pouco para nao brigar com o chao
local RING_TRANSPARENCY = 0.25
local AURA_SEGMENTS = 4 -- pedacinhos de neon que giram e formam o "anel de aura" do Lv4
local AURA_RADIUS = 2.6
local AURA_LIFT = 0.45
local AURA_SPIN_SPEED = 0.9 -- radianos por segundo (devagar)
local AURA_SEGMENT_SIZE = Vector3.new(1.5, 0.16, 0.4)
local LIGHT_RANGE = 8
local LIGHT_BRIGHTNESS = 1.5
local SPARK_RATE_LV3 = 4 -- faiscas por segundo (limite do spec: ate 6)
local SPARK_RATE_LV4 = 6
local STARS_MAX_DISTANCE = 120
local STAR_GOLD = Color3.fromRGB(255, 215, 80)
local FALLBACK_ACCENT = Color3.fromRGB(0, 240, 255)
local FALLBACK_EVO = Color3.fromRGB(170, 80, 255)
local WHITE = Color3.new(1, 1, 1)
-- O cilindro do Roblox tem o eixo no X; girar 90 graus em Z deixa ele "deitado" (fino na vertical).
local FLAT = CFrame.Angles(0, 0, math.rad(90))

type UnitState = {
	model: Model,
	kind: string,
	root: BasePart,
	parts: { BasePart }, -- partes neon (menos o Root)
	baseTransparency: { number },
	baseColors: { Color3 }, -- cor original de cada parte (para voltar/clarear)
	isAccent: { boolean }, -- true = a parte usa a cor de acento da unidade (essas mudam com o nivel)
	rootColor: Color3,
	partCount: number,
	phase: number, -- cada unidade pulsa em um ritmo diferente
	popTime: number, -- segundos desde o inicio do pop; negativo = sem pop
	pulseTime: number, -- segundos desde o ataque; negativo = sem pulso
	appliedScale: number,
	orbWeld: Weld?, -- junta que prende o orb ao corpo (se o servidor usou Weld)
	orbBaseC0: CFrame,
	upLocal: Vector3, -- "cima" do mundo no espaco do Root (o Root e cilindro deitado)
	-- Nivel e escala-base.
	level: number,
	baseScale: number, -- escala-base de destino (1 ou 1.12)
	baseFrom: number, -- de onde o "pop" de nivel comeca
	currentBase: number, -- escala-base de agora (so muda durante o pop de nivel)
	growing: boolean,
	growTime: number, -- negativo = ainda esperando a antecipacao
	-- Efeitos locais de nivel (criados uma vez no registro, destruidos no unregister).
	footPosition: Vector3,
	accent: Color3, -- cor de acento normal da unidade
	evoColor: Color3, -- cor de acento do Lv4
	height: number,
	ring: Part,
	attachment: Attachment,
	light: PointLight,
	emitter: ParticleEmitter,
	stars: BillboardGui,
	starsLabel: TextLabel,
	aura: { Part }?, -- so existe depois do primeiro Lv4
	evolved: boolean,
	levelConnection: RBXScriptConnection?,
}

local UnitFxController = {}

local connections: { RBXScriptConnection } = {}
local renderConnection: RBXScriptConnection? = nil
local pulseAccumulator = 0
local states: { [Model]: UnitState } = {}
local statesById: { [string]: UnitState } = {}
local fxFolder: Folder? = nil

-- ---------------------------------------------------------------------------
-- Leitura do Config (tudo com checagem: se faltar dado, usamos valores reserva)
-- ---------------------------------------------------------------------------

local function getMaxLevel(): number
	local value: any = Config.MAX_UNIT_LEVEL
	if typeof(value) == "number" and value >= 1 then
		return math.floor(value)
	end
	return DEFAULT_MAX_LEVEL
end

local function getUnitEntry(kind: string): any?
	local units: any = Config.UNITS
	if typeof(units) ~= "table" then
		return nil
	end
	local entry: any = units[kind]
	if typeof(entry) ~= "table" then
		return nil
	end
	return entry
end

local function getAccent(kind: string): Color3
	local entry = getUnitEntry(kind)
	if entry and typeof(entry.accentColor) == "Color3" then
		return entry.accentColor
	end
	return FALLBACK_ACCENT
end

-- Cor do Lv4: Config.UNITS[kind].upgrades[Config.MAX_UNIT_LEVEL - 1].evolution.accentColor.
local function getEvoColor(kind: string): Color3
	local entry = getUnitEntry(kind)
	if entry and typeof(entry.upgrades) == "table" then
		local lastLevel: any = entry.upgrades[Config.MAX_UNIT_LEVEL - 1]
		if typeof(lastLevel) == "table" and typeof(lastLevel.evolution) == "table" then
			local color: any = lastLevel.evolution.accentColor
			if typeof(color) == "Color3" then
				return color
			end
		end
	end
	return FALLBACK_EVO
end

local function getHeight(kind: string): number
	local entry = getUnitEntry(kind)
	if entry and typeof(entry.height) == "number" then
		return entry.height
	end
	return 4
end

local function colorDistance(a: Color3, b: Color3): number
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B)
end

local function readLevel(model: Model): number
	local value = model:GetAttribute("Level")
	if typeof(value) ~= "number" then
		return 1
	end
	return math.clamp(math.floor(value), 1, getMaxLevel())
end

-- Procura o Weld que prende o orb. WeldConstraint nao tem offset editavel, entao so Weld serve.
local function findOrbWeld(model: Model, orb: BasePart): Weld?
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Weld") and descendant.Part1 == orb then
			return descendant
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Efeitos locais de nivel (anel, luz, faiscas, estrelas, aura)
-- ---------------------------------------------------------------------------

-- Uma peca so guarda: anel de rank (a propria peca), luz, faiscas e as estrelas (BillboardGui).
-- Ela fica numa pasta local FORA de workspace.Units, entao nunca atrapalha o clique na unidade.
local function makeLevelEffects(folder: Folder, footPosition: Vector3, height: number)
	local ring = Instance.new("Part")
	ring.Name = "RankRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Transparency = 1 -- Lv1: escondido
	ring.Size = Vector3.new(RING_THICKNESS, RING_DIAMETER, RING_DIAMETER)
	-- As unidades nunca se mexem, entao posicionamos so UMA vez.
	ring.CFrame = CFrame.new(footPosition + Vector3.new(0, RING_LIFT, 0)) * FLAT
	ring.Parent = folder

	-- O anel esta deitado (girado), entao giramos o attachment de volta: assim "Top" aponta para cima.
	local attachment = Instance.new("Attachment")
	attachment.CFrame = CFrame.new(height * 0.3, 0, 0) * FLAT:Inverse()
	attachment.Parent = ring

	local light = Instance.new("PointLight")
	light.Range = LIGHT_RANGE
	light.Brightness = LIGHT_BRIGHTNESS
	light.Shadows = false
	light.Enabled = false
	light.Parent = attachment

	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Rate = SPARK_RATE_LV3
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = attachment

	local stars = Instance.new("BillboardGui")
	stars.Name = "LevelStars"
	stars.Adornee = ring
	stars.Size = UDim2.fromOffset(80, 22)
	stars.StudsOffsetWorldSpace = Vector3.new(0, height + 1.2, 0)
	stars.MaxDistance = STARS_MAX_DISTANCE
	stars.AlwaysOnTop = false
	stars.Active = false
	stars.Parent = ring

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 18
	label.Text = ""
	label.TextColor3 = STAR_GOLD
	label.TextStrokeColor3 = Color3.fromRGB(20, 12, 40)
	label.TextStrokeTransparency = 0.3
	label.Parent = stars

	return ring, attachment, light, emitter, stars, label
end

-- Pedacinhos neon do anel de aura (so no Lv4). Criados uma vez e reaproveitados.
local function makeAura(folder: Folder): { Part }
	local segments: { Part } = {}
	for i = 1, AURA_SEGMENTS do
		local part = Instance.new("Part")
		part.Name = "AuraSegment"
		part.Material = Enum.Material.Neon
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = AURA_SEGMENT_SIZE
		part.Parent = folder
		segments[i] = part
	end
	return segments
end

-- Cor de acento de um nivel: Lv4 troca para a cor da evolucao; Lv2/3 clareiam; Lv1 fica original.
local function tintFor(level: number, maxLevel: number, base: Color3, evo: Color3): Color3
	if level >= maxLevel then
		return evo
	elseif level >= 2 then
		return base:Lerp(WHITE, BRIGHTEN_AMOUNT)
	end
	return base
end

-- Aplica TUDO que depende do nivel. animate = true quando o nivel mudou ao vivo (com "pop").
local function applyLevel(state: UnitState, level: number, animate: boolean)
	local maxLevel = getMaxLevel()
	state.level = level
	local evolved = level >= maxLevel
	state.evolved = evolved
	local evo = state.evoColor

	-- Escala-base de destino.
	local targetBase = if evolved then EVOLVED_SCALE else 1
	if animate and math.abs(targetBase - state.currentBase) > 0.001 then
		state.baseFrom = state.currentBase
		state.baseScale = targetBase
		state.growing = true
		-- Evolucao espera a antecipacao (0.25 s) antes de crescer: o brilho do FxController vem primeiro.
		state.growTime = if evolved then -EVOLVE_ANTICIPATION else 0
	elseif not animate then
		state.baseScale = targetBase
		state.baseFrom = targetBase
		state.currentBase = targetBase
		state.growing = false
	else
		state.baseScale = targetBase
	end

	-- Cor das partes de acento.
	for i = 1, state.partCount do
		if state.isAccent[i] then
			state.parts[i].Color = tintFor(level, maxLevel, state.baseColors[i], evo)
		end
	end
	state.root.Color = tintFor(level, maxLevel, state.rootColor, evo)

	-- Cor dos efeitos: evo no Lv4, acento clareado nos outros.
	local effectColor = if evolved then evo else state.accent:Lerp(WHITE, 0.2)

	-- Anel de rank: aparece no Lv2+.
	local ring = state.ring
	if level >= 2 then
		ring.Transparency = RING_TRANSPARENCY
		ring.Color = effectColor
		local diameter = RING_DIAMETER * targetBase
		ring.Size = Vector3.new(RING_THICKNESS, diameter, diameter)
	else
		ring.Transparency = 1
	end

	-- Luz + faiscas: Lv3+.
	local hasGlow = level >= 3
	state.light.Enabled = hasGlow
	state.light.Color = effectColor
	state.emitter.Enabled = hasGlow
	state.emitter.Rate = if evolved then SPARK_RATE_LV4 else SPARK_RATE_LV3
	state.emitter.Color = ColorSequence.new(WHITE:Lerp(effectColor, 0.4), effectColor)

	-- Aura giratoria: so Lv4. Cria so na primeira vez que precisar.
	local folder = fxFolder
	if evolved and folder and not state.aura then
		state.aura = makeAura(folder)
	end
	local aura = state.aura
	if aura then
		for _, segment in aura do
			segment.Color = effectColor
			segment.Transparency = if evolved then 0.1 else 1
		end
	end

	-- Estrelas de nivel.
	state.starsLabel.Text = string.rep("★", level)
	state.starsLabel.TextColor3 = if evolved then evo else STAR_GOLD
	state.stars.StudsOffsetWorldSpace = Vector3.new(0, (state.height + 1.2) * targetBase, 0)
end

local function register(model: Model, withPop: boolean)
	if states[model] then
		return
	end
	local folder = fxFolder
	if not folder then
		return
	end
	local root = model:FindFirstChild("Root")
	if not root or not root:IsA("BasePart") then
		return
	end

	local kindValue = model:GetAttribute("Kind")
	local kind = if typeof(kindValue) == "string" then kindValue else ""
	local accent = getAccent(kind)

	local parts: { BasePart } = {}
	local bases: { number } = {}
	local colors: { Color3 } = {}
	local flags: { boolean } = {}
	local orb: BasePart? = nil
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and descendant ~= root
			and descendant.Material == Enum.Material.Neon
		then
			table.insert(parts, descendant)
			table.insert(bases, descendant.Transparency)
			table.insert(colors, descendant.Color)
			table.insert(flags, colorDistance(descendant.Color, accent) <= ACCENT_MATCH_DISTANCE)
			local isOrbName = string.find(string.lower(descendant.Name), "orb", 1, true) ~= nil
			if
				orb == nil
				and (
					isOrbName
					or (
						kind == "Mage"
						and descendant:IsA("Part")
						and descendant.Shape == Enum.PartType.Ball
					)
				)
			then
				orb = descendant
			end
		end
	end
	-- Se nenhuma parte parece "de acento" (Config sem cor, por ex.), tratamos todas como acento.
	local anyAccent = false
	for _, flag in flags do
		anyAccent = anyAccent or flag
	end
	if not anyAccent then
		for i in flags do
			flags[i] = true
		end
	end

	local weld: Weld? = nil
	local baseC0 = CFrame.new()
	if orb then
		weld = findOrbWeld(model, orb)
		if weld then
			baseC0 = weld.C0
		end
	end

	local height = getHeight(kind)
	local footPosition = root.Position
	local ring, attachment, light, emitter, stars, starsLabel =
		makeLevelEffects(folder, footPosition, height)

	local state: UnitState = {
		model = model,
		kind = kind,
		root = root,
		parts = parts,
		baseTransparency = bases,
		baseColors = colors,
		isAccent = flags,
		rootColor = root.Color,
		partCount = #parts,
		phase = math.random() * math.pi * 2,
		popTime = if withPop then 0 else -1,
		pulseTime = -1,
		appliedScale = 1,
		orbWeld = weld,
		orbBaseC0 = baseC0,
		upLocal = root.CFrame:VectorToObjectSpace(Vector3.yAxis),
		level = 1,
		baseScale = 1,
		baseFrom = 1,
		currentBase = 1,
		growing = false,
		growTime = 0,
		footPosition = footPosition,
		accent = accent,
		evoColor = getEvoColor(kind),
		height = height,
		ring = ring,
		attachment = attachment,
		light = light,
		emitter = emitter,
		stars = stars,
		starsLabel = starsLabel,
		aura = nil,
		evolved = false,
		levelConnection = nil,
	}
	states[model] = state
	local id = model:GetAttribute("Id")
	if typeof(id) == "string" then
		statesById[id] = state
	end

	-- Nivel inicial (quem entra no meio da partida ja ve o nivel certo) + mudancas futuras.
	applyLevel(state, readLevel(model), false)
	state.levelConnection = model:GetAttributeChangedSignal("Level"):Connect(function()
		local current = states[model]
		if current then
			applyLevel(current, readLevel(model), true)
		end
	end)

	-- Escala inicial: base (1 ou 1.12) vezes o fator do pop-in, se tiver.
	local initialScale = state.currentBase * (if withPop then POP_START_SCALE else 1)
	if math.abs(initialScale - 1) > 0.001 then
		model:ScaleTo(initialScale)
		state.appliedScale = initialScale
	end
end

local function unregister(model: Model)
	local state = states[model]
	if not state then
		return
	end
	states[model] = nil
	local id = model:GetAttribute("Id")
	if typeof(id) == "string" and statesById[id] == state then
		statesById[id] = nil
	end
	-- Solta tudo que criamos para esta unidade (senao vazaria memoria e pecas no mundo).
	local connection = state.levelConnection
	if connection then
		connection:Disconnect()
		state.levelConnection = nil
	end
	state.ring:Destroy() -- leva junto attachment, luz, faiscas e estrelas
	local aura = state.aura
	if aura then
		for _, segment in aura do
			segment:Destroy()
		end
		state.aura = nil
	end
end

local function onChildAdded(child: Instance, withPop: boolean)
	if not child:IsA("Model") then
		return
	end
	if child:FindFirstChild("Root") then
		register(child, withPop)
		return
	end
	-- O Root ainda nao chegou (streaming): espera um pouco sem travar nada.
	task.spawn(function()
		if child:WaitForChild("Root", 5) and child.Parent then
			register(child, withPop)
		end
	end)
end

-- O 5o argumento (special) nao importa aqui: so o FxController usa.
local function onUnitAttacked(id: string, _kind: string, _from: Vector3, _to: Vector3)
	if typeof(id) ~= "string" then
		return
	end
	local state = statesById[id]
	if state then
		state.pulseTime = 0 -- reinicia o pulso (rajada de ataques fica "vibrando")
	end
end

-- UM loop para todas as unidades. Sem tabelas novas, sem Instance.new.
local function onRenderStep(dt: number)
	local now = os.clock()
	pulseAccumulator += dt
	local writePulse = pulseAccumulator >= PULSE_WRITE_INTERVAL
	if writePulse then
		pulseAccumulator = 0
	end
	for model, state in states do
		-- Escala-base: so muda durante o "pop" de nivel (1 -> 1.12 com easing Back).
		local base = state.currentBase
		if state.growing then
			state.growTime += dt
			if state.growTime >= GROW_DURATION then
				state.growing = false
				base = state.baseScale
			elseif state.growTime >= 0 then
				local eased = TweenService:GetValue(
					state.growTime / GROW_DURATION,
					Enum.EasingStyle.Back,
					Enum.EasingDirection.Out
				)
				base = state.baseFrom + (state.baseScale - state.baseFrom) * eased
			else
				base = state.baseFrom -- ainda na antecipacao
			end
			state.currentBase = base
		end

		-- Fator relativo a base: pop-in e pulso multiplicam, nunca substituem.
		local factor = 1

		-- Pop-in com easing Back (calculado na mao, sem criar Tween).
		if state.popTime >= 0 then
			state.popTime += dt
			local alpha = state.popTime / POP_DURATION
			if alpha >= 1 then
				state.popTime = -1
			else
				local eased =
					TweenService:GetValue(alpha, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				factor = POP_START_SCALE + (1 - POP_START_SCALE) * eased
			end
		end

		-- Pulso de ataque: seno de 0 a pi = sobe e desce uma vez.
		if state.pulseTime >= 0 then
			state.pulseTime += dt
			if state.pulseTime >= PULSE_DURATION then
				state.pulseTime = -1
			else
				factor *= 1 + PULSE_STRENGTH * math.sin(math.pi * state.pulseTime / PULSE_DURATION)
			end
		end

		local scale = base * factor

		-- So chama ScaleTo se a escala mudou de verdade (ScaleTo mexe em todas as partes).
		if math.abs(scale - state.appliedScale) > 0.001 then
			model:ScaleTo(scale)
			state.appliedScale = scale
		end

		-- Brilho neon pulsando.
		if writePulse then
			local wave = 0.5 + 0.5 * math.sin(now * PULSE_SPEED + state.phase)
			local parts = state.parts
			local bases = state.baseTransparency
			for i = 1, state.partCount do
				parts[i].Transparency = bases[i] + PULSE_DEPTH * wave * (1 - bases[i])
			end

			-- Aura do Lv4: os pedacinhos giram em volta do pedestal (mesmo loop, sem loop novo).
			local aura = state.aura
			if aura and state.evolved then
				local spin = now * AURA_SPIN_SPEED + state.phase
				local center = CFrame.new(state.footPosition + Vector3.new(0, AURA_LIFT, 0))
				local radius = AURA_RADIUS * state.currentBase
				for i, segment in aura do
					local angle = spin + (i - 1) * (2 * math.pi / AURA_SEGMENTS)
					-- Gira em volta do centro e vira o pedacinho para ficar "deitado" na curva.
					segment.CFrame = center
						* CFrame.Angles(0, angle, 0)
						* CFrame.new(radius, 0, 0)
						* CFrame.Angles(0, math.pi / 2, 0)
				end
			end
		end

		-- Orb flutuando: mexe so no offset da junta (o ScaleTo ja escalou o C0, entao recalculamos).
		local weld = state.orbWeld
		if weld then
			local orbBase = state.orbBaseC0
			local bob = math.sin(now * BOB_SPEED + state.phase) * BOB_HEIGHT * state.appliedScale
			weld.C0 = CFrame.new(orbBase.Position * state.appliedScale + state.upLocal * bob)
				* orbBase.Rotation
		end
	end
end

function UnitFxController.init() end

function UnitFxController.start()
	local unitsFolder = workspace:WaitForChild("Units", 30)
	if not unitsFolder then
		warn("UnitFxController: workspace.Units nao apareceu")
		return
	end

	-- Pasta local dos efeitos de nivel (fora de workspace.Units, so este jogador ve).
	local folder = Instance.new("Folder")
	folder.Name = "ClientUnitFx"
	folder.Parent = workspace
	fxFolder = folder

	-- Unidades que ja existem quando entramos: sem pop (so as novas ganham o efeito).
	for _, child in unitsFolder:GetChildren() do
		onChildAdded(child, false)
	end
	table.insert(
		connections,
		unitsFolder.ChildAdded:Connect(function(child)
			onChildAdded(child, true)
		end)
	)
	table.insert(
		connections,
		unitsFolder.ChildRemoved:Connect(function(child)
			if child:IsA("Model") then
				unregister(child) -- libera a unidade da tabela (senao vazaria memoria)
			end
		end)
	)
	table.insert(connections, Net.event("UnitAttacked").OnClientEvent:Connect(onUnitAttacked))

	renderConnection = RunService.RenderStepped:Connect(onRenderStep)
end

-- Limpeza explicita (nao usada no jogo normal).
function UnitFxController.destroy()
	local loop = renderConnection
	if loop then
		loop:Disconnect()
		renderConnection = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for model in states do
		unregister(model) -- destroi as pecas locais de cada unidade
	end
	table.clear(states)
	table.clear(statesById)
	local folder = fxFolder
	if folder then
		folder:Destroy()
		fxFolder = nil
	end
end

return UnitFxController
