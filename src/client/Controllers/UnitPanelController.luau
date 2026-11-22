--!strict
-- UnitPanelController: toca numa unidade -> abre o painel de upgrade/venda (embaixo, acima da hotbar).
-- REGRA DE OURO (igual ao PlacementController): o cliente so PEDE (UpgradeUnit / SellUnit).
-- Quem muda nivel e dinheiro e o servidor; aqui a gente so redesenha quando os atributos mudam.
-- Mobile primeiro: tudo em Scale, alvos de toque grandes, texto com limite minimo de 12.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local UnitMath = require(Shared:WaitForChild("Util"):WaitForChild("UnitMath"))
-- Direcao da dependencia: o painel conhece o Placement, nunca o contrario (evita require ciclico).
local PlacementController = require(script.Parent:WaitForChild("PlacementController"))

type ActionButton = {
	button: TextButton,
	scale: UIScale,
	stroke: UIStroke,
	dim: Frame,
	enabled: boolean,
	dimTarget: number,
	scaleTween: Tween?,
	dimTween: Tween?,
}

local DARK = Color3.fromRGB(20, 12, 40)
local PINK = Color3.fromRGB(255, 51, 153)
local CYAN = Color3.fromRGB(0, 240, 255)
local YELLOW = Color3.fromRGB(255, 225, 60)
local RED = Color3.fromRGB(255, 50, 70)
local WHITE = Color3.new(1, 1, 1)
local PIP_EMPTY = Color3.fromRGB(60, 50, 90)
local MUTED = Color3.fromRGB(170, 160, 210)

-- Vocabulario de animacao (criado uma vez so, reaproveitado).
local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local OPEN_POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local GLOW = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local BTN_PRESSED = 0.92
local DIM_AMOUNT = 0.55
local PANEL_START_SCALE = 0.6
local PANEL_BUMP_SCALE = 0.94
local TAP_MAX_MOVE = 14 -- pixels: mais que isso o toque virou arrasto de camera, nao clique
local TAP_MAX_TIME = 0.35
local SELL_CONFIRM_TIME = 1.5 -- segundos para apertar Backspace de novo e confirmar a venda
local RAY_LENGTH = 2000
local RING_THICKNESS = 0.2
local RING_TRANSPARENCY = 0.75
local RING_LIFT = 0.15 -- levanta o anel um tiquinho para nao brigar (z-fighting) com o chao
local EVOLVE_FROM_LEVEL = Config.MAX_UNIT_LEVEL - 1

local UnitPanelController = {}

local connections: { RBXScriptConnection } = {}
local selectionConnections: { RBXScriptConnection } = {} -- so da unidade selecionada agora
local gui: ScreenGui? = nil
local ringFolder: Folder? = nil
local removePlacingListener: (() -> ())? = nil

---------------------------------------------------------------------------
-- Funcoes puras (formatacao)
---------------------------------------------------------------------------
local function formatNumber(value: number): string
	return string.format("%g", math.round(value * 100) / 100)
end

-- "DMG 11" ou "DMG 11 -> 15" (a parte da seta so aparece se existe upgrade).
local function statLine(name: string, current: number, nextValue: number?, suffix: string): string
	local text = name .. " " .. formatNumber(current) .. suffix
	if nextValue then
		text ..= ' <font color="#00F0FF">→ ' .. formatNumber(nextValue) .. suffix .. "</font>"
	end
	return text
end

local function readNumber(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end
	return fallback
end

local function currentMatchState(): string?
	local matchState = ReplicatedStorage:FindFirstChild("MatchState")
	if not matchState then
		return nil
	end
	local state = matchState:GetAttribute("State")
	if typeof(state) == "string" then
		return state
	end
	return nil
end

---------------------------------------------------------------------------
-- Construtores de UI
---------------------------------------------------------------------------
local function addCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = parent
end

local function makeLabel(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	maxText: number,
	color: Color3,
	alignment: Enum.TextXAlignment
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextXAlignment = alignment
	label.TextColor3 = color
	label.Text = ""
	label.Parent = parent
	local limit = Instance.new("UITextSizeConstraint") -- texto nunca fica ilegivel nem gigante
	limit.MinTextSize = 12
	limit.MaxTextSize = maxText
	limit.Parent = label
	return label
end

function UnitPanelController.init() end

function UnitPanelController.start()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local upgradeRemote = Net.event("UpgradeUnit")
	local sellRemote = Net.event("SellUnit")

	local screen = Instance.new("ScreenGui")
	screen.Name = "UnitPanel"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 6 -- acima do Placement (5)
	screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- mesma area da hotbar: alinha certinho
	screen.Parent = playerGui
	gui = screen

	-- Pasta LOCAL (so na nossa tela) para o anel de alcance; fora de workspace.Units de proposito.
	local folder = Instance.new("Folder")
	folder.Name = "UnitPanelLocal"
	folder.Parent = workspace
	ringFolder = folder

	local ring = Instance.new("Part")
	ring.Name = "RangeRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false -- o raio de selecao nunca acerta o anel
	ring.CastShadow = false
	ring.Transparency = RING_TRANSPARENCY
	ring.Size = Vector3.new(RING_THICKNESS, 1, 1)

	---------------------------------------------------------------------------
	-- Estado
	---------------------------------------------------------------------------
	local selectedModel: Model? = nil
	local isOpen = false
	local ownerView = false -- true se a unidade e nossa (so o dono ve os botoes)
	local ringLevel = 0
	local ringTween: Tween? = nil
	local pulseTween: Tween? = nil
	local pulseActive = false
	local scaleTween: Tween? = nil
	local fadeTween: Tween? = nil
	local touchInput: InputObject? = nil
	local touchStart = Vector2.zero
	local touchTime = 0
	local touchWasPlacing = false
	local sellArmedAt = 0 -- Backspace precisa de 2 toques seguidos para vender (evita venda sem querer)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include

	---------------------------------------------------------------------------
	-- Painel (CanvasGroup: GroupTransparency apaga tudo junto no fade)
	---------------------------------------------------------------------------
	local panel = Instance.new("CanvasGroup")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	-- A hotbar ocupa de 0.78 a 0.98 da tela; o painel termina em 0.76, logo acima, sem encostar.
	panel.Position = UDim2.fromScale(0.5, 0.76)
	panel.Size = UDim2.fromScale(0.62, 0.48)
	panel.BackgroundColor3 = DARK
	panel.GroupTransparency = 1
	panel.Active = true -- engole o toque: tocar no painel nao conta como "tocar no mundo vazio"
	panel.Visible = false
	panel.Parent = screen
	addCorner(panel, 0.08)

	local panelAspect = Instance.new("UIAspectRatioConstraint") -- mesma proporcao em qualquer tela
	panelAspect.AspectRatio = 1.9
	panelAspect.AspectType = Enum.AspectType.FitWithinMaxSize
	panelAspect.Parent = panel
	local panelLimit = Instance.new("UISizeConstraint") -- no PC nao vira um outdoor
	panelLimit.MaxSize = Vector2.new(520, 275)
	panelLimit.Parent = panel
	local panelScale = Instance.new("UIScale")
	panelScale.Scale = PANEL_START_SCALE
	panelScale.Parent = panel
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Thickness = 3
	panelStroke.Color = CYAN
	panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	panelStroke.Parent = panel

	local title = makeLabel(
		panel,
		"Title",
		UDim2.fromScale(0.04, 0.03),
		UDim2.fromScale(0.68, 0.15),
		26,
		WHITE,
		Enum.TextXAlignment.Left
	)

	-- Bolinhas de nivel: preenchida = nivel ja alcancado.
	local pipHolder = Instance.new("Frame")
	pipHolder.Name = "Pips"
	pipHolder.Position = UDim2.fromScale(0.04, 0.21)
	pipHolder.Size = UDim2.fromScale(0.3, 0.08)
	pipHolder.BackgroundTransparency = 1
	pipHolder.Parent = panel
	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.Padding = UDim.new(0.06, 0)
	pipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pipLayout.Parent = pipHolder
	local pips: { Frame } = {}
	for index = 1, Config.MAX_UNIT_LEVEL do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. index
		pip.LayoutOrder = index
		pip.Size = UDim2.fromScale(1, 1)
		pip.BackgroundColor3 = PIP_EMPTY
		pip.BorderSizePixel = 0
		pip.Parent = pipHolder
		addCorner(pip, 0.5)
		local pipAspect = Instance.new("UIAspectRatioConstraint") -- sempre redonda
		pipAspect.AspectRatio = 1
		pipAspect.DominantAxis = Enum.DominantAxis.Height
		pipAspect.Parent = pip
		table.insert(pips, pip)
	end

	local statLabels: { TextLabel } = {}
	for index, statName in { "Damage", "Range", "Speed" } do
		local label = makeLabel(
			panel,
			statName,
			UDim2.fromScale(0.04, 0.32 + (index - 1) * 0.12),
			UDim2.fromScale(0.52, 0.11),
			20,
			WHITE,
			Enum.TextXAlignment.Left
		)
		label.RichText = true -- a seta fica ciano, o numero atual fica branco
		table.insert(statLabels, label)
	end

	-- Caixa da evolucao / habilidade (lado direito).
	local abilityBox = Instance.new("Frame")
	abilityBox.Name = "AbilityBox"
	abilityBox.Position = UDim2.fromScale(0.58, 0.26)
	abilityBox.Size = UDim2.fromScale(0.38, 0.42)
	abilityBox.BackgroundColor3 = Color3.fromRGB(38, 26, 70)
	abilityBox.BorderSizePixel = 0
	abilityBox.Parent = panel
	addCorner(abilityBox, 0.12)
	local abilityStroke = Instance.new("UIStroke")
	abilityStroke.Thickness = 1
	abilityStroke.Color = MUTED
	abilityStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	abilityStroke.Parent = abilityBox
	local abilityHeader = makeLabel(
		abilityBox,
		"Header",
		UDim2.fromScale(0.06, 0.04),
		UDim2.fromScale(0.88, 0.26),
		16,
		MUTED,
		Enum.TextXAlignment.Left
	)
	local abilityBody = makeLabel(
		abilityBox,
		"Body",
		UDim2.fromScale(0.06, 0.32),
		UDim2.fromScale(0.88, 0.62),
		18,
		WHITE,
		Enum.TextXAlignment.Left
	)
	abilityBody.Font = Enum.Font.GothamBold
	abilityBody.TextWrapped = true
	abilityBody.TextYAlignment = Enum.TextYAlignment.Top

	-- Quando a unidade e de outro jogador: so mostra o nome do dono no lugar dos botoes.
	local ownerLabel = makeLabel(
		panel,
		"Owner",
		UDim2.fromScale(0.04, 0.72),
		UDim2.fromScale(0.92, 0.24),
		22,
		MUTED,
		Enum.TextXAlignment.Center
	)
	ownerLabel.Visible = false

	---------------------------------------------------------------------------
	-- Botoes (pop ao apertar, camada escura quando desligado/sem dinheiro)
	---------------------------------------------------------------------------
	local function tweenButtonScale(action: ActionButton, target: number, info: TweenInfo)
		local old = action.scaleTween
		if old then
			old:Cancel()
		end
		local tween = TweenService:Create(action.scale, info, { Scale = target })
		action.scaleTween = tween
		tween:Play()
	end

	local function setDim(action: ActionButton, amount: number)
		if action.dimTarget == amount then
			return -- ja esta assim: nao cria tween toda vez que o Cash muda
		end
		action.dimTarget = amount
		local old = action.dimTween
		if old then
			old:Cancel()
		end
		local tween = TweenService:Create(action.dim, FAST, { BackgroundTransparency = amount })
		action.dimTween = tween
		tween:Play()
	end

	local function makeButton(
		name: string,
		position: UDim2,
		size: UDim2,
		color: Color3,
		textColor: Color3,
		onActivate: () -> ()
	): ActionButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.Position = position
		button.Size = size
		button.BackgroundColor3 = color
		button.AutoButtonColor = false -- o feedback e o nosso (pop), nao o padrao
		button.Font = Enum.Font.GothamBlack
		button.TextScaled = true
		button.TextColor3 = textColor
		button.Text = ""
		button.Parent = panel
		addCorner(button, 0.25)
		local limit = Instance.new("UITextSizeConstraint")
		limit.MinTextSize = 12
		limit.MaxTextSize = 24
		limit.Parent = button
		local sizeLimit = Instance.new("UISizeConstraint") -- alvo de toque nunca fica pequeno demais
		sizeLimit.MinSize = Vector2.new(80, 40)
		sizeLimit.Parent = button
		local uiScale = Instance.new("UIScale")
		uiScale.Parent = button
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = WHITE
		stroke.Transparency = 0.4
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button

		-- Camada escura por cima. Active = false para nao roubar o clique do botao.
		local dim = Instance.new("Frame")
		dim.Name = "Dim"
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 1
		dim.BorderSizePixel = 0
		dim.Active = false
		dim.ZIndex = 5
		dim.Parent = button
		addCorner(dim, 0.25)

		local action: ActionButton = {
			button = button,
			scale = uiScale,
			stroke = stroke,
			dim = dim,
			enabled = true,
			dimTarget = 1,
			scaleTween = nil,
			dimTween = nil,
		}

		table.insert(
			connections,
			button.MouseButton1Down:Connect(function()
				tweenButtonScale(action, BTN_PRESSED, FAST)
			end)
		)
		table.insert(
			connections,
			button.MouseButton1Up:Connect(function()
				tweenButtonScale(action, 1, POP)
			end)
		)
		table.insert(
			connections,
			button.MouseLeave:Connect(function()
				tweenButtonScale(action, 1, POP)
			end)
		)
		table.insert(
			connections,
			button.Activated:Connect(function()
				tweenButtonScale(action, 1, POP)
				if action.enabled then
					onActivate()
				end
			end)
		)
		return action
	end

	-- Fecha o painel (declarada aqui, definida mais abaixo) e pedidos ao servidor.
	local closePanel: () -> ()

	local function requestUpgrade()
		local model = selectedModel
		if not model or not ownerView then
			return
		end
		local id = model:GetAttribute("Id")
		if typeof(id) == "string" then
			-- Mandamos o nivel que estamos vendo: se dois cliques chegarem juntos, o servidor
			-- ignora o segundo (o nivel real ja mudou) e nao cobra upgrade duplo.
			local level = model:GetAttribute("Level")
			if typeof(level) ~= "number" then
				return
			end
			-- So pedimos. Se faltar dinheiro, o servidor responde com Notify (toast do Placement).
			upgradeRemote:FireServer(id, level)
		end
	end

	local function requestSell()
		local model = selectedModel
		if not model or not ownerView then
			return
		end
		local id = model:GetAttribute("Id")
		if typeof(id) == "string" then
			sellRemote:FireServer(id)
		end
	end

	local upgradeButton = makeButton(
		"Upgrade",
		UDim2.fromScale(0.04, 0.72),
		UDim2.fromScale(0.54, 0.24),
		CYAN,
		DARK,
		requestUpgrade
	)
	local sellButton = makeButton(
		"Sell",
		UDim2.fromScale(0.62, 0.72),
		UDim2.fromScale(0.34, 0.24),
		YELLOW,
		DARK,
		requestSell
	)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.fromScale(0.97, 0.03)
	closeButton.Size = UDim2.fromScale(0.1, 0.16)
	closeButton.BackgroundColor3 = RED
	closeButton.AutoButtonColor = false
	closeButton.Font = Enum.Font.GothamBlack
	closeButton.TextScaled = true
	closeButton.TextColor3 = WHITE
	closeButton.Text = "X"
	closeButton.Parent = panel
	addCorner(closeButton, 0.3)
	local closeLimit = Instance.new("UITextSizeConstraint")
	closeLimit.MinTextSize = 12
	closeLimit.MaxTextSize = 24
	closeLimit.Parent = closeButton
	local closeSizeLimit = Instance.new("UISizeConstraint")
	closeSizeLimit.MinSize = Vector2.new(36, 36)
	closeSizeLimit.Parent = closeButton
	local closeScale = Instance.new("UIScale")
	closeScale.Parent = closeButton
	local closeTween: Tween? = nil
	local function tweenClose(target: number, info: TweenInfo)
		local old = closeTween
		if old then
			old:Cancel()
		end
		local tween = TweenService:Create(closeScale, info, { Scale = target })
		closeTween = tween
		tween:Play()
	end
	table.insert(
		connections,
		closeButton.MouseButton1Down:Connect(function()
			tweenClose(BTN_PRESSED, FAST)
		end)
	)
	table.insert(
		connections,
		closeButton.MouseLeave:Connect(function()
			tweenClose(1, POP)
		end)
	)
	table.insert(
		connections,
		closeButton.Activated:Connect(function()
			tweenClose(1, POP)
			closePanel()
		end)
	)

	---------------------------------------------------------------------------
	-- Pulso do botao EVOLVE
	---------------------------------------------------------------------------
	local function setPulse(active: boolean)
		if pulseActive == active then
			return -- nao reinicia o tween a cada render
		end
		pulseActive = active
		local old = pulseTween
		if old then
			old:Cancel()
			pulseTween = nil
		end
		if active then
			local tween =
				TweenService:Create(upgradeButton.stroke, GLOW, { Thickness = 9, Transparency = 0 })
			pulseTween = tween
			tween:Play()
		else
			upgradeButton.stroke.Thickness = 3
			upgradeButton.stroke.Transparency = 0.4
		end
	end

	---------------------------------------------------------------------------
	-- Anel de alcance (local)
	---------------------------------------------------------------------------
	local function updateRing(model: Model, range: number, color: Color3)
		local hitbox = model:FindFirstChild("Hitbox")
		local feet = model:GetPivot().Position
		if hitbox and hitbox:IsA("BasePart") then
			-- Base da hitbox = pe da unidade.
			feet = hitbox.Position - Vector3.new(0, hitbox.Size.Y / 2, 0)
		end
		ring.Color = color
		ring.CFrame = CFrame.new(feet + Vector3.new(0, RING_LIFT, 0))
			* CFrame.Angles(0, 0, math.rad(90)) -- deita o cilindro
		ring.Parent = ringFolder
		local diameter = range * 2
		ring.Size = Vector3.new(RING_THICKNESS, 0.1, 0.1)
		local old = ringTween
		if old then
			old:Cancel()
		end
		local tween = TweenService:Create(
			ring,
			POP,
			{ Size = Vector3.new(RING_THICKNESS, diameter, diameter) }
		)
		ringTween = tween
		tween:Play()
	end

	---------------------------------------------------------------------------
	-- Desenha o painel a partir dos atributos (chamada a cada mudanca)
	---------------------------------------------------------------------------
	local function renderAbilityBox(
		level: number,
		nextStats: UnitMath.UnitStats?,
		stats: UnitMath.UnitStats
	)
		local ability = stats.ability
		if level >= Config.MAX_UNIT_LEVEL and ability then
			abilityHeader.Text = "ABILITY"
			abilityHeader.TextColor3 = stats.accentColor
			abilityBody.Text = ability.description
			abilityStroke.Color = stats.accentColor
			abilityStroke.Thickness = 2
		elseif level == EVOLVE_FROM_LEVEL and nextStats and nextStats.ability then
			-- Nivel 3: destaque forte mostrando o que a evolucao vai dar.
			abilityHeader.Text = "EVOLVE: " .. nextStats.displayName
			abilityHeader.TextColor3 = nextStats.accentColor
			abilityBody.Text = nextStats.ability.description
			abilityStroke.Color = nextStats.accentColor
			abilityStroke.Thickness = 3
		else
			abilityHeader.Text = "EVOLUTION"
			abilityHeader.TextColor3 = MUTED
			abilityBody.Text = "Reach Lv " .. Config.MAX_UNIT_LEVEL .. " to evolve"
			abilityStroke.Color = MUTED
			abilityStroke.Thickness = 1
		end
	end

	local function renderButtons(
		level: number,
		spent: number,
		nextStats: UnitMath.UnitStats?,
		cost: number?
	)
		local cash = readNumber(localPlayer, "Cash", 0)
		local state = currentMatchState()
		-- Fora de Intermission/Wave o servidor recusa o upgrade, entao ja apagamos o botao.
		local upgradeAllowed = state ~= nil and Config.UPGRADE_ALLOWED_STATES[state] == true
		if cost and nextStats then
			local evolving = level == EVOLVE_FROM_LEVEL
			upgradeButton.button.Text = if upgradeAllowed
				then (if evolving then "EVOLVE $" else "UPGRADE $") .. math.floor(cost)
				else "Can't upgrade"
			upgradeButton.button.BackgroundColor3 = if evolving then PINK else CYAN
			upgradeButton.button.TextColor3 = if evolving then WHITE else DARK
			upgradeButton.enabled = upgradeAllowed
			setDim(upgradeButton, if upgradeAllowed and cash >= cost then 1 else DIM_AMOUNT)
			setPulse(evolving and upgradeAllowed)
		else
			upgradeButton.button.Text = "MAX"
			upgradeButton.button.BackgroundColor3 = CYAN
			upgradeButton.button.TextColor3 = DARK
			upgradeButton.enabled = false
			setDim(upgradeButton, DIM_AMOUNT)
			setPulse(false)
		end

		local refund = UnitMath.refundFor(spent, state)
		if refund then
			local suffix = if state == "Intermission" then " (100%)" else ""
			sellButton.button.Text = "Sell $" .. math.floor(refund) .. suffix
			sellButton.enabled = true
			setDim(sellButton, 1)
		else
			sellButton.button.Text = "Can't sell"
			sellButton.enabled = false
			setDim(sellButton, DIM_AMOUNT)
		end
	end

	local function render()
		local model = selectedModel
		if not model then
			return
		end
		local kind = model:GetAttribute("Kind")
		local def = if typeof(kind) == "string" then Config.UNITS[kind] else nil
		if not def then
			closePanel() -- unidade que nao existe na Config: nada para mostrar
			return
		end

		local maxLevel = Config.MAX_UNIT_LEVEL
		local level = math.clamp(math.floor(readNumber(model, "Level", 1)), 1, maxLevel)
		local spent = readNumber(model, "Spent", def.cost)
		local stats = UnitMath.statsAt(def, level)
		local cost = UnitMath.upgradeCost(def, level)
		local nextStats = if cost then UnitMath.statsAt(def, level + 1) else nil

		title.Text = stats.displayName .. "  Lv " .. level
		title.TextColor3 = stats.accentColor
		panelStroke.Color = stats.accentColor
		for index, pip in pips do
			pip.BackgroundColor3 = if index <= level then stats.accentColor else PIP_EMPTY
		end

		statLabels[1].Text =
			statLine("DMG", stats.damage, if nextStats then nextStats.damage else nil, "")
		statLabels[2].Text =
			statLine("RANGE", stats.range, if nextStats then nextStats.range else nil, "")
		statLabels[3].Text =
			statLine("SPEED", stats.cooldown, if nextStats then nextStats.cooldown else nil, "s")
		renderAbilityBox(level, nextStats, stats)

		-- So o dono ve os botoes; os outros veem o nome do dono.
		local owner = model:GetAttribute("Owner")
		ownerView = owner == localPlayer.UserId
		upgradeButton.button.Visible = ownerView
		sellButton.button.Visible = ownerView
		ownerLabel.Visible = not ownerView
		if not ownerView then
			local ownerPlayer = if typeof(owner) == "number"
				then Players:GetPlayerByUserId(owner)
				else nil
			ownerLabel.Text = "Owner: "
				.. (if ownerPlayer then ownerPlayer.DisplayName else "Player")
			setPulse(false)
		else
			renderButtons(level, spent, nextStats, cost)
		end

		if ringLevel ~= level then
			local firstShow = ringLevel == 0
			ringLevel = level
			updateRing(model, stats.range, stats.accentColor)
			if not firstShow then
				-- Subiu de nivel com o painel aberto: um "tum" para chamar atencao.
				panelScale.Scale = PANEL_BUMP_SCALE
				local old = scaleTween
				if old then
					old:Cancel()
				end
				local tween = TweenService:Create(panelScale, OPEN_POP, { Scale = 1 })
				scaleTween = tween
				tween:Play()
			end
		end
	end

	---------------------------------------------------------------------------
	-- Abrir / fechar
	---------------------------------------------------------------------------
	local function clearSelection()
		-- Solta TUDO que pertencia a unidade selecionada (conexoes, anel, pulso).
		for _, connection in selectionConnections do
			connection:Disconnect()
		end
		table.clear(selectionConnections)
		sellArmedAt = 0
		local oldRing = ringTween
		if oldRing then
			oldRing:Cancel()
			ringTween = nil
		end
		ring.Parent = nil
		setPulse(false)
		selectedModel = nil
		ringLevel = 0
	end

	closePanel = function()
		if not isOpen then
			return
		end
		isOpen = false
		clearSelection()
		local oldFade = fadeTween
		if oldFade then
			oldFade:Cancel()
		end
		local fade = TweenService:Create(panel, FADE_OUT, { GroupTransparency = 1 })
		fadeTween = fade
		fade.Completed:Once(function()
			-- Se o jogador abriu outra unidade durante o fade, nao esconde.
			if not isOpen then
				panel.Visible = false
			end
		end)
		fade:Play()
	end

	local function openPanel()
		local oldFade = fadeTween
		if oldFade then
			oldFade:Cancel()
		end
		local oldScale = scaleTween
		if oldScale then
			oldScale:Cancel()
		end
		panel.Visible = true
		-- Ja aberto (trocou de unidade): so um "tum" pequeno. Fechado: pop de abrir (Back 0.25 s).
		panelScale.Scale = if isOpen then PANEL_BUMP_SCALE else PANEL_START_SCALE
		isOpen = true
		local scale = TweenService:Create(panelScale, OPEN_POP, { Scale = 1 })
		scaleTween = scale
		scale:Play()
		local fade = TweenService:Create(panel, FAST, { GroupTransparency = 0 })
		fadeTween = fade
		fade:Play()
	end

	local function selectModel(model: Model)
		if selectedModel == model and isOpen then
			render()
			return
		end
		clearSelection()
		selectedModel = model
		table.insert(
			selectionConnections,
			model.AttributeChanged:Connect(function(name: string)
				if name == "Level" or name == "Spent" or name == "Owner" then
					render()
				end
			end)
		)
		table.insert(
			selectionConnections,
			model.AncestryChanged:Connect(function()
				-- Vendida/destruida: tira da workspace -> fecha o painel.
				if not model:IsDescendantOf(workspace) then
					closePanel()
				end
			end)
		)
		openPanel()
		render()
	end

	---------------------------------------------------------------------------
	-- Toque/clique no mundo 3D
	---------------------------------------------------------------------------
	local function handleWorldTap(screenPos: Vector2)
		if PlacementController.isPlacing() then
			return
		end
		local camera = workspace.CurrentCamera
		local unitsFolder = workspace:FindFirstChild("Units")
		if not camera or not unitsFolder then
			return
		end
		-- ScreenPointToRay ja considera a barra superior do Roblox (inset).
		local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
		raycastParams.FilterDescendantsInstances = { unitsFolder }
		local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, raycastParams)
		if result and result.Instance.Name == "Hitbox" then
			-- So o Hitbox tem CanQuery ligado; o dono dele e o modelo da unidade.
			local model = result.Instance.Parent
			if model and model:IsA("Model") and typeof(model:GetAttribute("Id")) == "string" then
				selectModel(model)
				return
			end
		end
		closePanel() -- tocou no vazio
	end

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			-- Escape fecha mesmo se o Roblox ja "usou" a tecla (menu), mas so com o painel aberto.
			if isOpen and input.KeyCode == Enum.KeyCode.Escape then
				closePanel()
				return
			end
			if gameProcessed then
				return -- um botao/UI ja usou este clique
			end
			local inputType = input.UserInputType
			if inputType == Enum.UserInputType.MouseButton1 then
				-- Le ANTES: um clique que termina a colocacao nao pode tambem selecionar unidade.
				local wasPlacing = PlacementController.isPlacing()
				if not wasPlacing then
					handleWorldTap(Vector2.new(input.Position.X, input.Position.Y))
				end
			elseif inputType == Enum.UserInputType.Touch then
				-- Toque: so conta como "clique" se soltar perto e rapido (senao e arrastar a camera).
				touchInput = input
				touchStart = Vector2.new(input.Position.X, input.Position.Y)
				touchTime = os.clock()
				touchWasPlacing = PlacementController.isPlacing()
			elseif inputType == Enum.UserInputType.Keyboard and isOpen then
				local key = input.KeyCode
				if key == Enum.KeyCode.Q then
					closePanel()
				elseif key == Enum.KeyCode.E then
					requestUpgrade()
				elseif key == Enum.KeyCode.Backspace and sellButton.enabled then
					if os.clock() - sellArmedAt <= SELL_CONFIRM_TIME then
						sellArmedAt = 0
						requestSell()
					else
						sellArmedAt = os.clock()
						sellButton.button.Text = "Press again"
						task.delay(SELL_CONFIRM_TIME, function()
							-- Acabou o tempo: volta o texto normal do botao.
							if isOpen then
								render()
							end
						end)
					end
				end
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
			if input ~= touchInput then
				return
			end
			touchInput = nil
			if touchWasPlacing then
				return -- o toque era para colocar unidade, nao para selecionar
			end
			local endPos = Vector2.new(input.Position.X, input.Position.Y)
			if
				(endPos - touchStart).Magnitude <= TAP_MAX_MOVE
				and os.clock() - touchTime <= TAP_MAX_TIME
			then
				handleWorldTap(endPos)
			end
		end)
	)

	-- Comecou a colocar uma unidade nova -> fecha o painel.
	removePlacingListener = PlacementController.onPlacingChanged(function(placing: boolean)
		if placing then
			closePanel()
		end
	end)

	-- Dinheiro mudou -> escurece/acende o botao de upgrade.
	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("Cash"):Connect(function()
			if isOpen then
				render()
			end
		end)
	)

	-- Estado da partida mudou (Intermission/Wave...) -> muda o reembolso do botao Sell.
	task.spawn(function()
		local matchState = ReplicatedStorage:WaitForChild("MatchState", 30)
		if not matchState then
			return
		end
		table.insert(
			connections,
			matchState:GetAttributeChangedSignal("State"):Connect(function()
				local state = currentMatchState()
				if state == "Waiting" or state == "Victory" or state == "Defeat" then
					closePanel() -- partida acabou/reiniciou: nao ha o que mostrar
				elseif isOpen then
					render()
				end
			end)
		)
	end)
end

-- Desliga tudo (mesmo padrao dos outros controllers).
function UnitPanelController.destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, connection in selectionConnections do
		connection:Disconnect()
	end
	table.clear(selectionConnections)
	local removeListener = removePlacingListener
	if removeListener then
		removeListener()
		removePlacingListener = nil
	end
	local screen = gui
	if screen then
		screen:Destroy()
		gui = nil
	end
	local folder = ringFolder
	if folder then
		folder:Destroy()
		ringFolder = nil
	end
end

return UnitPanelController
