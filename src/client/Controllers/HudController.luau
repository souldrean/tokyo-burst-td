--!strict
-- HudController: o HUD (interface) do jogo: titulo, onda, estado/contagem e vida da base.
-- Tudo em Scale (porcentagem da tela) para funcionar em celular e PC.
-- O HUD so MOSTRA o que o servidor diz (atributos da pasta MatchState). Ele nunca decide nada.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PINK = Color3.fromRGB(255, 51, 153)
local CYAN = Color3.fromRGB(0, 240, 255)
local YELLOW = Color3.fromRGB(255, 225, 60)
local LIME = Color3.fromRGB(120, 255, 90)
local RED = Color3.fromRGB(255, 50, 70)
local DARK = Color3.fromRGB(20, 12, 40)

-- Animacoes reaproveitadas (criar TweenInfo uma vez so).
local POP_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FILL_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- A contagem regressiva so precisa atualizar 10 vezes por segundo.
local COUNTDOWN_INTERVAL = 0.1
-- Abaixo dessa fracao de vida a barra fica vermelha.
local LOW_HEALTH_RATIO = 0.3

local HudController = {}

local connections: { RBXScriptConnection } = {}
local popTweens: { [UIScale]: Tween } = {}

-- Le um atributo numero com valor padrao (atributo pode ainda nao existir).
local function getNumber(inst: Instance, name: string, default: number): number
	local value = inst:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end
	return default
end

-- "Pop": o elemento comeca maior e volta ao normal com easing Back (efeito elastico).
local function popScale(uiScale: UIScale, from: number)
	local old = popTweens[uiScale]
	if old then
		old:Cancel() -- evita dois tweens brigando pela mesma propriedade
	end
	uiScale.Scale = from
	local tween = TweenService:Create(uiScale, POP_INFO, { Scale = 1 })
	popTweens[uiScale] = tween
	tween:Play()
end

-- Cria um texto padrao do HUD: escala com a tela, com limites e contorno para ler bem.
local function makeLabel(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	text: string,
	color: Color3,
	minSize: number,
	maxSize: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true -- o texto se ajusta ao tamanho da caixa
	label.TextColor3 = color
	label.Parent = parent

	-- Limites: o texto nao fica minusculo no celular nem gigante no PC.
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = minSize
	limit.MaxTextSize = maxSize
	limit.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = DARK
	stroke.Thickness = 2
	stroke.Parent = label

	return label
end

function HudController.init() end

function HudController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false -- nao some quando o personagem morre
	gui.IgnoreGuiInset = false -- respeita a barra superior do Roblox
	gui.Parent = playerGui

	-- Titulo pequeno no canto superior esquerdo (o centro fica para a onda e a vida).
	local title = makeLabel(
		gui,
		"Title",
		UDim2.fromScale(0.01, 0.01),
		UDim2.fromScale(0.2, 0.04),
		"TOKYO BURST TD",
		CYAN,
		12,
		26
	)
	title.AnchorPoint = Vector2.new(0, 0)
	local titleStroke = title:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Color = PINK
		-- Pulso: um Tween so, repetindo para sempre. Bem mais leve do que mexer a cada frame.
		local pulseInfo = TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		TweenService:Create(titleStroke, pulseInfo, { Thickness = 3, Color = CYAN }):Play()
		TweenService:Create(title, pulseInfo, { TextColor3 = PINK }):Play()
	end

	local tag = makeLabel(
		gui,
		"BuildTag",
		UDim2.fromScale(0.01, 0.05),
		UDim2.fromScale(0.12, 0.03),
		"Week 2 build",
		Color3.fromRGB(200, 215, 255),
		12,
		16
	)
	tag.AnchorPoint = Vector2.new(0, 0)
	tag.Font = Enum.Font.GothamBold
	tag.TextTransparency = 0.2

	-- Etiqueta da onda, topo centro.
	local waveLabel = makeLabel(
		gui,
		"WaveLabel",
		UDim2.fromScale(0.5, 0.01),
		UDim2.fromScale(0.3, 0.06),
		"WAVE 0/10",
		YELLOW,
		14,
		44
	)
	local waveScale = Instance.new("UIScale")
	waveScale.Parent = waveLabel

	-- Etiqueta de estado/contagem, logo abaixo da onda.
	local stateLabel = makeLabel(
		gui,
		"StateLabel",
		UDim2.fromScale(0.5, 0.07),
		UDim2.fromScale(0.3, 0.045),
		"",
		CYAN,
		12,
		30
	)

	-- Barra de vida da base.
	local barFrame = Instance.new("Frame")
	barFrame.Name = "BaseHealthBar"
	barFrame.AnchorPoint = Vector2.new(0.5, 0)
	barFrame.Position = UDim2.fromScale(0.5, 0.12)
	barFrame.Size = UDim2.fromScale(0.36, 0.04)
	barFrame.BackgroundColor3 = DARK
	barFrame.BorderSizePixel = 0
	barFrame.Parent = gui

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0.5, 0)
	barCorner.Parent = barFrame

	local barStroke = Instance.new("UIStroke")
	barStroke.Color = CYAN
	barStroke.Thickness = 2
	barStroke.Parent = barFrame

	local barScale = Instance.new("UIScale")
	barScale.Parent = barFrame

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = LIME
	fill.BorderSizePixel = 0
	fill.Parent = barFrame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	local healthText = Instance.new("TextLabel")
	healthText.Name = "HealthText"
	healthText.AnchorPoint = Vector2.new(0.5, 0.5)
	healthText.Position = UDim2.fromScale(0.5, 0.5)
	healthText.Size = UDim2.fromScale(0.6, 0.8)
	healthText.BackgroundTransparency = 1
	healthText.Font = Enum.Font.GothamBlack
	healthText.TextScaled = true
	healthText.TextColor3 = Color3.new(1, 1, 1)
	healthText.Text = ""
	healthText.ZIndex = 2 -- fica por cima da barra colorida
	healthText.Parent = barFrame

	local healthLimit = Instance.new("UITextSizeConstraint")
	healthLimit.MinTextSize = 12
	healthLimit.MaxTextSize = 26
	healthLimit.Parent = healthText

	local healthStroke = Instance.new("UIStroke")
	healthStroke.Color = DARK
	healthStroke.Thickness = 2
	healthStroke.Parent = healthText

	-- A pasta MatchState e criada pelo servidor; esperamos com tempo limite.
	local matchStateInst = ReplicatedStorage:WaitForChild("MatchState", 30)
	if not matchStateInst then
		warn("[HudController] MatchState nao apareceu em 30s; HUD fica parado.")
		return
	end
	local matchState: Instance = matchStateInst

	-- Valores antigos guardados para so mexer na interface quando algo MUDA
	-- (evita criar texto e tween a toa).
	local lastWave = -1
	local lastWaveCount = -1
	local lastHealth = -1
	local lastMaxHealth = -1
	local lastState = ""
	local lastSeconds = -1
	local lastAlive = -1
	local lastStateWave = -1
	local fillTween: Tween? = nil

	local function updateWave()
		local wave = getNumber(matchState, "Wave", 0)
		local waveCount = getNumber(matchState, "WaveCount", 10)
		if wave == lastWave and waveCount == lastWaveCount then
			return
		end
		if wave ~= lastWave and wave > 0 then
			popScale(waveScale, 1.5) -- pop quando entra uma onda nova
		end
		lastWave = wave
		lastWaveCount = waveCount
		waveLabel.Text = "WAVE " .. wave .. "/" .. waveCount
	end

	local function updateState()
		local stateValue = matchState:GetAttribute("State")
		local state = if typeof(stateValue) == "string" then stateValue else "Waiting"
		local endsAt = getNumber(matchState, "StateEndsAt", 0)
		local seconds = 0
		if endsAt > 0 then
			seconds = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
		end
		local alive = getNumber(matchState, "EnemiesAlive", 0)
		local wave = getNumber(matchState, "Wave", 0)
		local waveCount = getNumber(matchState, "WaveCount", 10)

		if state == lastState and seconds == lastSeconds and alive == lastAlive and wave == lastStateWave then
			return
		end
		lastState = state
		lastSeconds = seconds
		lastAlive = alive
		lastStateWave = wave

		local text = ""
		local color = CYAN
		if state == "Waiting" then
			text = "Waiting for players..."
		elseif state == "Intermission" then
			text = "Next wave in " .. seconds
			color = CYAN
		elseif state == "Wave" then
			if wave >= waveCount and waveCount > 0 then
				text = "BOSS WAVE"
				color = RED
			else
				text = "Enemies: " .. alive
				color = YELLOW
			end
		elseif state == "Victory" then
			text = "VICTORY!"
			color = LIME
			if seconds > 0 then
				text ..= "  Restart in " .. seconds
			end
		elseif state == "Defeat" then
			text = "DEFEAT"
			color = RED
			if seconds > 0 then
				text ..= "  Restart in " .. seconds
			end
		end
		stateLabel.Text = text
		stateLabel.TextColor3 = color
	end

	local function updateHealth()
		local health = getNumber(matchState, "BaseHealth", 100)
		local maxHealth = math.max(1, getNumber(matchState, "BaseMaxHealth", 100))
		if health == lastHealth and maxHealth == lastMaxHealth then
			return
		end
		if lastHealth >= 0 and health < lastHealth then
			popScale(barScale, 1.15) -- a barra "treme" quando a base leva dano
		end
		lastHealth = health
		lastMaxHealth = maxHealth

		local ratio = math.clamp(health / maxHealth, 0, 1)
		local color = LIME
		if ratio < LOW_HEALTH_RATIO then
			color = RED
		end

		local old = fillTween
		if old then
			old:Cancel()
		end
		local tween = TweenService:Create(fill, FILL_INFO, {
			Size = UDim2.fromScale(ratio, 1),
			BackgroundColor3 = color,
		})
		fillTween = tween
		tween:Play()

		healthText.Text = math.ceil(health) .. "/" .. math.ceil(maxHealth)
	end

	local function refreshAll()
		updateWave()
		updateState()
		updateHealth()
	end

	refreshAll()

	-- Atributos replicam sozinhos; basta ouvir a mudanca (sem remotes).
	table.insert(connections, matchState.AttributeChanged:Connect(refreshAll))

	-- Contagem regressiva: Heartbeat com acumulador (10 vezes por segundo).
	local accumulator = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt: number)
			accumulator += dt
			if accumulator < COUNTDOWN_INTERVAL then
				return
			end
			accumulator = 0
			updateState()
		end)
	)
end

return HudController
