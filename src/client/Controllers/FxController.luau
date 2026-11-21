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

local Net = require(ReplicatedStorage.Shared.Net)

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

-- Animacoes reaproveitadas.
local POP_IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local NUMBER_POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local NUMBER_RISE = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local NUMBER_FADE = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.5)
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

local FxController = {}

local connections: { RBXScriptConnection } = {}

local fxFolder: Folder? = nil
local burstSlots: { BurstSlot } = {}
local leakSlots: { BurstSlot } = {}
local numberSlots: { NumberSlot } = {}
local nextBurst = 1
local nextLeak = 1
local nextNumber = 1

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

local function makeBurstSlot(folder: Folder, colors: { Color3 }, speedMax: number, sizeMax: number): BurstSlot
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

local function burst(slots: { BurstSlot }, index: number, position: Vector3, perColor: number, lightColor: Color3)
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

	return { part = part, gui = gui, label = label, scale = scale, stroke = stroke, token = 0, tweens = {} }
end

local function showNumber(position: Vector3, text: string)
	local slot = numberSlots[nextNumber]
	nextNumber = nextNumber % #numberSlots + 1 -- se todos estao em uso, reaproveita o mais antigo

	slot.token += 1
	local myToken = slot.token
	cancelAll(slot.tweens)

	slot.part.Position = position + Vector3.new((math.random() - 0.5) * 3, 1, (math.random() - 0.5) * 3)
	slot.gui.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	slot.label.Text = text
	slot.label.TextColor3 = randomColor()
	slot.label.TextTransparency = 0
	slot.stroke.Transparency = 0
	slot.scale.Scale = 0.2
	slot.gui.Enabled = true

	local pop = TweenService:Create(slot.scale, NUMBER_POP, { Scale = 1.2 })
	local rise = TweenService:Create(slot.gui, NUMBER_RISE, { StudsOffsetWorldSpace = Vector3.new(0, 6, 0) })
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
		RunService:BindToRenderStep(SHAKE_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, onShakeStep)
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
		local info = TweenInfo.new(2.2 + math.random() * 1.8, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, math.random() * 0.9)
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
	local tween = TweenService:Create(effect, GRADE_INFO, { Saturation = saturation, Brightness = brightness })
	gradeTween = tween
	tween:Play()
end

-- ---------------------------------------------------------------------------
-- Eventos do servidor
-- ---------------------------------------------------------------------------

local function onEnemyDied(id: string, reason: string, position: Vector3, reward: number)
	if typeof(position) ~= "Vector3" then
		return
	end
	if reason == "Killed" then
		burst(burstSlots, nextBurst, position, CONFETTI_PER_COLOR, PALETTE[math.random(1, #PALETTE)])
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
end

-- Limpeza explicita (nao usada no jogo normal): desliga tudo e solta a camera.
function FxController.destroy()
	stopShake()
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
