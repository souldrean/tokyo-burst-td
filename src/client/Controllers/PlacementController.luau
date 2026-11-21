--!strict
-- PlacementController: hotbar de unidades (embaixo) + modo de colocacao + avisos (toasts).
-- REGRA DE OURO: o cliente NUNCA decide nada. Ele so manda PlaceUnit(kind, slotName)
-- e desenha o que o servidor responde (atributo Cash, atributo Occupied, UnitPlaced, Notify).
-- Mobile primeiro: tudo em Scale, alvos de toque grandes, texto com limite minimo de 12.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))

local Types = require(Shared:WaitForChild("Types"))

type UnitDef = Types.UnitDef

type Card = {
	kind: string,
	cost: number,
	button: TextButton,
	scale: UIScale,
	stroke: UIStroke,
	dim: Frame,
	costLabel: TextLabel,
	accent: Color3,
	scaleTween: Tween?,
	glowTween: Tween?,
	dimTween: Tween?,
	affordable: boolean,
}

type SlotLook = {
	color: Color3,
	transparency: number,
}

type Toast = {
	group: CanvasGroup,
	moveTween: Tween?,
	fadeTween: Tween?,
	thread: thread?,
	dead: boolean,
}

local DARK = Color3.fromRGB(20, 12, 40)
local PINK = Color3.fromRGB(255, 51, 153)
local CYAN = Color3.fromRGB(0, 240, 255)
local YELLOW = Color3.fromRGB(255, 225, 60)
local RED = Color3.fromRGB(255, 50, 70)
local WHITE = Color3.new(1, 1, 1)

-- Vocabulario de animacao (criado uma vez so, reaproveitado).
local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local GLOW = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local SLOT_PULSE = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local TOAST_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TOAST_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local CARD_REST = 1
local CARD_SELECTED = 1.08
local CARD_PRESSED = 0.92
local DIM_AMOUNT = 0.55
local MAX_TOASTS = 3
local TOAST_SECONDS = 2
local TOAST_STEP = 0.36 -- distancia vertical (escala do container) entre toasts empilhados
local TAP_MAX_MOVE = 14 -- pixels: mais que isso o toque virou arrasto de camera, nao clique
local TAP_MAX_TIME = 0.35
local RAY_LENGTH = 2000

-- Atalhos de teclado: a posicao na lista vira a tecla (1, 2, 3...).
local NUMBER_KEYS: { Enum.KeyCode } = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
}

local PlacementController = {}

local connections: { RBXScriptConnection } = {}

function PlacementController.init() end

function PlacementController.start()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local units = Config.UNITS
	local order = Config.UNIT_ORDER :: { string }

	local placeRemote = Net.event("PlaceUnit")
	local placedRemote = Net.event("UnitPlaced")
	local notifyRemote = Net.event("Notify")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Placement"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- nao fica embaixo do notch/home bar
	gui.Parent = playerGui

	---------------------------------------------------------------------------
	-- Estado
	---------------------------------------------------------------------------
	local cards: { Card } = {}
	local selected: Card? = nil
	local slotFolder: Instance? = nil
	local slotOriginals: { [BasePart]: SlotLook } = {}
	local slotTweens: { [BasePart]: Tween } = {}
	local slotConnections: { RBXScriptConnection } = {}
	local toasts: { Toast } = {} -- indice 1 = mais novo
	local touchInput: InputObject? = nil
	local touchStart = Vector2.zero
	local touchTime = 0

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include

	---------------------------------------------------------------------------
	-- Ajudantes de tween
	---------------------------------------------------------------------------
	-- Cada elemento guarda o seu tween atual: cancelamos antes de criar outro,
	-- senao dois tweens brigam pela mesma propriedade.
	local function tweenCardScale(card: Card, target: number, info: TweenInfo)
		local old = card.scaleTween
		if old then
			old:Cancel()
		end
		local tween = TweenService:Create(card.scale, info, { Scale = target })
		card.scaleTween = tween
		tween:Play()
	end

	local function restScale(card: Card): number
		if selected == card then
			return CARD_SELECTED
		end
		return CARD_REST
	end

	---------------------------------------------------------------------------
	-- Toasts (avisos no topo)
	---------------------------------------------------------------------------
	local toastHolder = Instance.new("Frame")
	toastHolder.Name = "Toasts"
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Position = UDim2.fromScale(0.5, 0.2)
	toastHolder.Size = UDim2.fromScale(0.42, 0.22)
	toastHolder.BackgroundTransparency = 1
	toastHolder.Parent = gui

	local function toastPosition(index: number): UDim2
		return UDim2.fromScale(0.5, (index - 1) * TOAST_STEP)
	end

	local function layoutToasts()
		for index, toast in toasts do
			local old = toast.moveTween
			if old then
				old:Cancel()
			end
			local tween = TweenService:Create(toast.group, TOAST_IN, { Position = toastPosition(index) })
			toast.moveTween = tween
			tween:Play()
		end
	end

	local function dismissToast(toast: Toast)
		if toast.dead then
			return
		end
		toast.dead = true
		local index = table.find(toasts, toast)
		if index then
			table.remove(toasts, index)
		end
		local thread = toast.thread
		if thread and thread ~= coroutine.running() then
			task.cancel(thread) -- nao deixa o timer de 2s rodando a toa
		end
		toast.thread = nil
		local fade = TweenService:Create(toast.group, TOAST_OUT, { GroupTransparency = 1 })
		toast.fadeTween = fade
		fade.Completed:Once(function()
			toast.group:Destroy()
		end)
		fade:Play()
		layoutToasts()
	end

	local function showToast(text: string)
		-- Limite de 3 empilhados: o mais velho (final da lista) sai.
		while #toasts >= MAX_TOASTS do
			dismissToast(toasts[#toasts])
		end

		local group = Instance.new("CanvasGroup") -- 1 propriedade (GroupTransparency) apaga tudo junto
		group.Name = "Toast"
		group.AnchorPoint = Vector2.new(0.5, 0)
		group.Size = UDim2.fromScale(1, 0.3)
		group.Position = UDim2.fromScale(0.5, -0.5) -- comeca acima e escorrega para dentro
		group.BackgroundColor3 = DARK
		group.GroupTransparency = 1
		group.Parent = toastHolder

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = group

		local bar = Instance.new("Frame") -- barrinha rosa na esquerda: deixa o aviso com cara de anime
		bar.Size = UDim2.fromScale(0.025, 1)
		bar.BackgroundColor3 = PINK
		bar.BorderSizePixel = 0
		bar.Parent = group

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.92, 0.7)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.53, 0.5)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = WHITE
		label.Text = string.sub(text, 1, 60)
		label.Parent = group

		local limit = Instance.new("UITextSizeConstraint")
		limit.MinTextSize = 12
		limit.MaxTextSize = 28
		limit.Parent = label

		local toast: Toast = { group = group, moveTween = nil, fadeTween = nil, thread = nil, dead = false }
		table.insert(toasts, 1, toast)
		layoutToasts()
		TweenService:Create(group, FAST, { GroupTransparency = 0 }):Play()

		toast.thread = task.delay(TOAST_SECONDS, function()
			toast.thread = nil
			dismissToast(toast)
		end)
	end

	---------------------------------------------------------------------------
	-- Slots: destaque LOCAL (so na nossa tela) enquanto estamos colocando
	---------------------------------------------------------------------------
	local function restoreSlot(slot: BasePart)
		local tween = slotTweens[slot]
		if tween then
			tween:Cancel()
			slotTweens[slot] = nil
		end
		local look = slotOriginals[slot]
		if look then
			slot.Color = look.color
			slot.Transparency = look.transparency
		end
	end

	local function pulseSlot(slot: BasePart)
		local look = slotOriginals[slot]
		if not look then
			return
		end
		local tween = TweenService:Create(slot, SLOT_PULSE, {
			Color = CYAN,
			Transparency = math.max(0, look.transparency - 0.35),
		})
		slotTweens[slot] = tween
		tween:Play()
	end

	local function endSlotHighlight()
		-- Devolve o visual original de TODOS os slots (por isso guardamos os originais).
		for _, conn in slotConnections do
			conn:Disconnect()
		end
		table.clear(slotConnections)
		for slot in slotOriginals do
			restoreSlot(slot)
		end
		table.clear(slotOriginals)
	end

	local function beginSlotHighlight()
		local folder = slotFolder
		if not folder then
			return
		end
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				local slot: BasePart = child
				slotOriginals[slot] = { color = slot.Color, transparency = slot.Transparency }
				if slot:GetAttribute("Occupied") ~= true then
					pulseSlot(slot) -- livre: pulsa forte
				end -- ocupado: continua apagado (visual original)

				-- Se o servidor ocupar o slot enquanto olhamos, ele para de pulsar.
				table.insert(
					slotConnections,
					slot:GetAttributeChangedSignal("Occupied"):Connect(function()
						if slot:GetAttribute("Occupied") == true then
							restoreSlot(slot)
						elseif not slotTweens[slot] then
							pulseSlot(slot)
						end
					end)
				)
			end
		end
	end

	---------------------------------------------------------------------------
	-- Hotbar
	---------------------------------------------------------------------------
	local hotbar = Instance.new("Frame")
	hotbar.Name = "Hotbar"
	hotbar.AnchorPoint = Vector2.new(0.5, 1)
	hotbar.Position = UDim2.fromScale(0.5, 0.98)
	hotbar.Size = UDim2.fromScale(0.62, 0.2)
	hotbar.BackgroundTransparency = 1
	hotbar.Parent = gui

	local hotbarLimit = Instance.new("UISizeConstraint") -- no PC nao vira uma faixa gigante
	hotbarLimit.MaxSize = Vector2.new(760, 170)
	hotbarLimit.Parent = hotbar

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.02, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = hotbar

	-- Dica + botao X, aparecem so no modo de colocacao.
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	-- Acima do Cancel; o offset cobre o tamanho minimo (40 px) do botao em telas pequenas.
	hint.Position = UDim2.new(0.5, 0, 0.71, -20)
	hint.Size = UDim2.fromScale(0.34, 0.05)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBlack
	hint.TextScaled = true
	hint.TextColor3 = CYAN
	hint.Text = "Tap a glowing slot"
	hint.Visible = false
	hint.Parent = gui
	local hintLimit = Instance.new("UITextSizeConstraint")
	hintLimit.MinTextSize = 12
	hintLimit.MaxTextSize = 24
	hintLimit.Parent = hint
	local hintStroke = Instance.new("UIStroke")
	hintStroke.Color = DARK
	hintStroke.Thickness = 2
	hintStroke.Parent = hint

	local cancelButton = Instance.new("TextButton")
	cancelButton.Name = "Cancel"
	cancelButton.AnchorPoint = Vector2.new(0.5, 1)
	-- Base do botao logo acima da borda de cima da hotbar (0.98 - 0.2 = 0.78), nunca em cima dela.
	cancelButton.Position = UDim2.fromScale(0.5, 0.77)
	cancelButton.Size = UDim2.fromScale(0.16, 0.06)
	cancelButton.BackgroundColor3 = RED
	cancelButton.AutoButtonColor = false
	cancelButton.Font = Enum.Font.GothamBlack
	cancelButton.TextScaled = true
	cancelButton.TextColor3 = WHITE
	cancelButton.Text = "X  CANCEL"
	cancelButton.Visible = false
	cancelButton.Parent = gui
	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0.5, 0)
	cancelCorner.Parent = cancelButton
	local cancelLimit = Instance.new("UITextSizeConstraint")
	cancelLimit.MinTextSize = 12
	cancelLimit.MaxTextSize = 24
	cancelLimit.Parent = cancelButton
	local cancelSizeLimit = Instance.new("UISizeConstraint") -- alvo de toque nunca fica pequeno demais
	cancelSizeLimit.MinSize = Vector2.new(110, 40)
	cancelSizeLimit.Parent = cancelButton
	local cancelScale = Instance.new("UIScale")
	cancelScale.Parent = cancelButton
	local cancelPop: Tween? = nil

	local function popCancel()
		local old = cancelPop
		if old then
			old:Cancel()
		end
		cancelScale.Scale = 0.6
		local tween = TweenService:Create(cancelScale, POP, { Scale = 1 })
		cancelPop = tween
		tween:Play()
	end

	-- Visual de um card: selecionado = brilho pulsando + maior; normal = quieto.
	local function renderCard(card: Card)
		local isSelected = selected == card
		local oldGlow = card.glowTween
		if oldGlow then
			oldGlow:Cancel()
			card.glowTween = nil
		end
		if isSelected then
			card.stroke.Color = WHITE
			local glow = TweenService:Create(card.stroke, GLOW, { Thickness = 8, Color = card.accent })
			card.glowTween = glow
			glow:Play()
		else
			card.stroke.Thickness = 3
			card.stroke.Color = card.accent
		end
		tweenCardScale(card, restScale(card), POP)
	end

	local function setSelected(card: Card?)
		local previous = selected
		if previous == card then
			return
		end
		local wasActive = previous ~= nil
		selected = card
		if previous then
			renderCard(previous)
		end
		if card then
			renderCard(card)
		end

		local active = card ~= nil
		hint.Visible = active
		cancelButton.Visible = active
		if active and not wasActive then
			popCancel()
			beginSlotHighlight()
		elseif not active then
			endSlotHighlight() -- volta o visual original dos slots
		end
	end

	local function exitPlacement()
		setSelected(nil)
	end

	-- Se o Cash ainda nao replicou ao entrar, o primeiro valor nao anima (fallback de 10 s).
	local cashReady = localPlayer:GetAttribute("Cash") ~= nil
	if not cashReady then
		task.delay(10, function()
			cashReady = true
		end)
	end

	local function updateAffordability(playPop: boolean)
		local cash = 0
		local value = localPlayer:GetAttribute("Cash")
		if typeof(value) == "number" then
			cash = value
		end
		for _, card in cards do
			local affordable = cash >= card.cost
			if affordable ~= card.affordable then
				card.affordable = affordable
				local oldDim = card.dimTween
				if oldDim then
					oldDim:Cancel()
				end
				local dimTween = TweenService:Create(card.dim, FAST, {
					BackgroundTransparency = if affordable then 1 else DIM_AMOUNT,
				})
				card.dimTween = dimTween
				dimTween:Play()
				card.costLabel.TextColor3 = if affordable then YELLOW else RED
				if affordable and playPop then
					-- Acabou de ficar acessivel: chama atencao com um pop.
					card.scale.Scale = restScale(card) * 1.15
					tweenCardScale(card, restScale(card), POP)
				end
			end
		end
	end

	local function makeCard(kind: string, def: UnitDef, index: number, count: number)
		local button = Instance.new("TextButton")
		button.Name = "Card_" .. kind
		button.LayoutOrder = index
		-- Largura reparte o espaco da hotbar igualmente (Scale, funciona em qualquer tela).
		button.Size = UDim2.fromScale((1 - 0.02 * (count - 1)) / count, 0.92)
		button.BackgroundColor3 = DARK
		button.AutoButtonColor = false -- o feedback e o nosso (squash), nao o padrao
		button.Text = ""
		button.Parent = hotbar

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.14, 0)
		corner.Parent = button

		local stroke = Instance.new("UIStroke")
		stroke.Color = def.accentColor
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button

		local uiScale = Instance.new("UIScale")
		uiScale.Parent = button

		-- "Retrato": quadrado colorido (cor da unidade) com borda neon (cor de destaque).
		local portrait = Instance.new("Frame")
		portrait.Name = "Portrait"
		portrait.AnchorPoint = Vector2.new(0, 0.5)
		portrait.Position = UDim2.fromScale(0.06, 0.5)
		portrait.Size = UDim2.fromScale(0.3, 0.7)
		-- Clareia um pouco a cor: o Ninja (azul bem escuro) sumia no fundo escuro do card.
		portrait.BackgroundColor3 = def.color:Lerp(Color3.new(1, 1, 1), 0.25)
		portrait.BorderSizePixel = 0
		portrait.Parent = button
		local portraitAspect = Instance.new("UIAspectRatioConstraint") -- sempre quadrado
		portraitAspect.AspectRatio = 1
		portraitAspect.AspectType = Enum.AspectType.FitWithinMaxSize
		portraitAspect.Parent = portrait
		local portraitCorner = Instance.new("UICorner")
		portraitCorner.CornerRadius = UDim.new(0.2, 0)
		portraitCorner.Parent = portrait
		local portraitStroke = Instance.new("UIStroke")
		portraitStroke.Color = def.accentColor
		portraitStroke.Thickness = 3
		portraitStroke.Parent = portrait

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.Position = UDim2.fromScale(0.42, 0.1)
		nameLabel.Size = UDim2.fromScale(0.54, 0.4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBlack
		nameLabel.TextScaled = true
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = WHITE
		nameLabel.Text = def.displayName
		nameLabel.Parent = button
		local nameLimit = Instance.new("UITextSizeConstraint")
		nameLimit.MinTextSize = 12
		nameLimit.MaxTextSize = 26
		nameLimit.Parent = nameLabel

		local costLabel = Instance.new("TextLabel")
		costLabel.Name = "Cost"
		costLabel.Position = UDim2.fromScale(0.42, 0.52)
		costLabel.Size = UDim2.fromScale(0.54, 0.36)
		costLabel.BackgroundTransparency = 1
		costLabel.Font = Enum.Font.GothamBlack
		costLabel.TextScaled = true
		costLabel.TextXAlignment = Enum.TextXAlignment.Left
		costLabel.TextColor3 = YELLOW
		costLabel.Text = "$" .. math.floor(def.cost)
		costLabel.Parent = button
		local costLimit = Instance.new("UITextSizeConstraint")
		costLimit.MinTextSize = 12
		costLimit.MaxTextSize = 24
		costLimit.Parent = costLabel

		-- Numero do atalho (so serve no PC, mas e pequeno e nao atrapalha).
		if index <= #NUMBER_KEYS and not UserInputService.TouchEnabled then
			local keyLabel = Instance.new("TextLabel")
			keyLabel.Name = "Key"
			keyLabel.Position = UDim2.fromScale(0.03, 0.03)
			keyLabel.Size = UDim2.fromScale(0.12, 0.22)
			keyLabel.BackgroundTransparency = 1
			keyLabel.Font = Enum.Font.GothamBold
			keyLabel.TextScaled = true
			keyLabel.TextColor3 = Color3.fromRGB(200, 215, 255)
			keyLabel.Text = tostring(index)
			keyLabel.Parent = button
			local keyLimit = Instance.new("UITextSizeConstraint")
			keyLimit.MinTextSize = 12
			keyLimit.MaxTextSize = 18
			keyLimit.Parent = keyLabel
		end

		-- Camada escura por cima: dimmed (sem dinheiro) = camada visivel.
		-- Active = false para nao roubar o clique do botao.
		local dim = Instance.new("Frame")
		dim.Name = "Dim"
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 1
		dim.BorderSizePixel = 0
		dim.Active = false
		dim.ZIndex = 5
		dim.Parent = button
		local dimCorner = Instance.new("UICorner")
		dimCorner.CornerRadius = UDim.new(0.14, 0)
		dimCorner.Parent = dim

		local card: Card = {
			kind = kind,
			cost = def.cost,
			button = button,
			scale = uiScale,
			stroke = stroke,
			dim = dim,
			costLabel = costLabel,
			accent = def.accentColor,
			scaleTween = nil,
			glowTween = nil,
			dimTween = nil,
			affordable = true,
		}
		table.insert(cards, card)

		-- Aperta: encolhe rapido ("squash"). Solta: volta com Back (pop).
		table.insert(
			connections,
			button.MouseButton1Down:Connect(function()
				tweenCardScale(card, CARD_PRESSED, FAST)
			end)
		)
		table.insert(
			connections,
			button.MouseLeave:Connect(function()
				tweenCardScale(card, restScale(card), POP)
			end)
		)
		table.insert(
			connections,
			button.Activated:Connect(function()
				if not card.affordable and selected ~= card then
					-- So um aviso local de UX; quem decide de verdade e o servidor.
					showToast("Not enough cash!")
					tweenCardScale(card, restScale(card), POP)
					return
				end
				if selected == card then
					exitPlacement() -- tocar de novo cancela
				else
					setSelected(card)
				end
				tweenCardScale(card, restScale(card), POP)
			end)
		)
	end

	for index, kind in order do
		local def = units[kind]
		if def then
			makeCard(kind, def, index, #order)
		else
			warn("[PlacementController] Config.UNITS sem a unidade: " .. kind)
		end
	end

	---------------------------------------------------------------------------
	-- Colocar: raycast no mundo 3D so contra os slots
	---------------------------------------------------------------------------
	local function tryPlaceAt(screenPos: Vector2)
		local card = selected
		local folder = slotFolder
		local camera = workspace.CurrentCamera
		if not card or not folder or not camera then
			return
		end
		-- ScreenPointToRay ja considera a barra superior do Roblox (inset).
		local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
		raycastParams.FilterDescendantsInstances = { folder }
		local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, raycastParams)
		if not result then
			return -- clicou no vazio: continua no modo
		end
		local slot = result.Instance
		if slot.Parent ~= folder then
			return
		end
		if slot:GetAttribute("Occupied") == true then
			showToast("Slot taken")
			return
		end
		-- So pedimos. Servidor valida tudo (estado, slot, limite, dinheiro) e responde.
		placeRemote:FireServer(card.kind, slot.Name)
		exitPlacement()
	end

	-- Cancelar
	table.insert(
		connections,
		cancelButton.Activated:Connect(function()
			exitPlacement()
		end)
	)

	-- Entrada: gameProcessed = true quer dizer que um botao/UI ja usou o clique.
	-- Sem isso, tocar num card tambem colocaria a unidade "atras" dele.
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then
				return
			end
			local inputType = input.UserInputType
			if inputType == Enum.UserInputType.MouseButton1 then
				if selected then
					tryPlaceAt(Vector2.new(input.Position.X, input.Position.Y))
				end
			elseif inputType == Enum.UserInputType.Touch then
				-- Toque: so conta como "clique" se soltar perto e rapido (senao e arrastar a camera).
				touchInput = input
				touchStart = Vector2.new(input.Position.X, input.Position.Y)
				touchTime = os.clock()
			elseif inputType == Enum.UserInputType.Keyboard then
				local key = input.KeyCode
				if key == Enum.KeyCode.Q or key == Enum.KeyCode.Escape then
					exitPlacement()
					return
				end
				local index = table.find(NUMBER_KEYS, key)
				if index then
					local card = cards[index]
					if card then
						if not card.affordable and selected ~= card then
							showToast("Not enough cash!")
						elseif selected == card then
							exitPlacement()
						else
							setSelected(card)
						end
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
			if not selected then
				return
			end
			local endPos = Vector2.new(input.Position.X, input.Position.Y)
			if (endPos - touchStart).Magnitude <= TAP_MAX_MOVE and os.clock() - touchTime <= TAP_MAX_TIME then
				tryPlaceAt(endPos)
			end
		end)
	)

	---------------------------------------------------------------------------
	-- Respostas do servidor
	---------------------------------------------------------------------------
	table.insert(
		connections,
		notifyRemote.OnClientEvent:Connect(function(text: unknown)
			if typeof(text) == "string" then
				showToast(text)
			end
		end)
	)

	-- Se a nossa unidade foi criada e ainda estamos no modo, sai dele.
	table.insert(
		connections,
		placedRemote.OnClientEvent:Connect(function(_id: unknown, _kind: unknown, _position: unknown, ownerUserId: unknown)
			if ownerUserId == localPlayer.UserId and selected then
				exitPlacement()
			end
		end)
	)

	-- Dinheiro mudou -> atualiza cards escurecidos.
	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("Cash"):Connect(function()
			-- Primeiro valor pos-join nao e "ganho": atualiza sem o pop.
			local playPop = cashReady
			cashReady = true
			updateAffordability(playPop)
		end)
	)
	updateAffordability(false)

	-- Acha a pasta de slots (pode demorar a replicar). Sem ela o modo so nao destaca nada.
	local map = workspace:WaitForChild("Map", 30)
	if map then
		local placement = map:WaitForChild("Placement", 30)
		if placement then
			slotFolder = placement
		end
	end
	if not slotFolder then
		warn("[PlacementController] workspace.Map.Placement nao apareceu; colocacao desativada.")
	end

	-- Se a partida entrar em estado onde nao pode colocar (ex.: Derrota), sai do modo.
	task.spawn(function()
		local matchState = ReplicatedStorage:WaitForChild("MatchState", 30)
		if not matchState then
			return
		end
		local allowed = Config.PLACE_ALLOWED_STATES
		table.insert(
			connections,
			matchState:GetAttributeChangedSignal("State"):Connect(function()
				local state = matchState:GetAttribute("State")
				if selected and not (typeof(state) == "string" and allowed[state]) then
					exitPlacement()
				end
			end)
		)
	end)
end

-- Desliga todas as conexoes (mesmo padrao dos outros controllers).
function PlacementController.destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return PlacementController
