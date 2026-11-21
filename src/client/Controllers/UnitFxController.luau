--!strict
-- UnitFxController: "vida" das unidades (so no cliente, so visual).
-- Faz 3 coisas com UM unico loop de RenderStepped:
--   1) pop-in: unidade nova cresce de 0.2 ate 1 com efeito "Back" (passa um pouco e volta);
--   2) pulso: o ataque faz a unidade dar uma "inchada" rapida (1 -> 1.08 -> 1);
--   3) idle: partes neon pulsam de leve e o orb do Mage flutua (se der para mexer nele).
-- Para ficar leve no celular: listas de partes sao criadas UMA vez por unidade (no registro),
-- e o loop nao cria tabelas nem Instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local POP_START_SCALE = 0.2
local POP_DURATION = 0.45
local PULSE_DURATION = 0.18
local PULSE_STRENGTH = 0.08
local PULSE_SPEED = 3 -- velocidade do brilho neon
local PULSE_DEPTH = 0.3 -- o quanto o neon fica transparente no ponto mais fraco
local BOB_HEIGHT = 0.35 -- studs que o orb sobe e desce
local BOB_SPEED = 2.2
local PULSE_WRITE_INTERVAL = 1 / 30 -- neon nao precisa de 60 Hz; economiza escritas de propriedade

type UnitState = {
	model: Model,
	parts: { BasePart }, -- partes neon (menos o Root)
	baseTransparency: { number },
	partCount: number,
	phase: number, -- cada unidade pulsa em um ritmo diferente
	popTime: number, -- segundos desde o inicio do pop; negativo = sem pop
	pulseTime: number, -- segundos desde o ataque; negativo = sem pulso
	appliedScale: number,
	orbWeld: Weld?, -- junta que prende o orb ao corpo (se o servidor usou Weld)
	orbBaseC0: CFrame,
	upLocal: Vector3, -- "cima" do mundo no espaco do Root (o Root e cilindro deitado)
}

local UnitFxController = {}

local connections: { RBXScriptConnection } = {}
local renderConnection: RBXScriptConnection? = nil
local pulseAccumulator = 0
local states: { [Model]: UnitState } = {}
local statesById: { [string]: UnitState } = {}

-- Procura o Weld que prende o orb. WeldConstraint nao tem offset editavel, entao so Weld serve.
local function findOrbWeld(model: Model, orb: BasePart): Weld?
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Weld") and descendant.Part1 == orb then
			return descendant
		end
	end
	return nil
end

local function register(model: Model, withPop: boolean)
	if states[model] then
		return
	end
	local root = model:FindFirstChild("Root")
	if not root or not root:IsA("BasePart") then
		return
	end

	local parts: { BasePart } = {}
	local bases: { number } = {}
	local orb: BasePart? = nil
	local kind = model:GetAttribute("Kind")
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root and descendant.Material == Enum.Material.Neon then
			table.insert(parts, descendant)
			table.insert(bases, descendant.Transparency)
			local isOrbName = string.find(string.lower(descendant.Name), "orb", 1, true) ~= nil
			if orb == nil and (isOrbName or (kind == "Mage" and descendant:IsA("Part") and descendant.Shape == Enum.PartType.Ball)) then
				orb = descendant
			end
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

	local state: UnitState = {
		model = model,
		parts = parts,
		baseTransparency = bases,
		partCount = #parts,
		phase = math.random() * math.pi * 2,
		popTime = if withPop then 0 else -1,
		pulseTime = -1,
		appliedScale = 1,
		orbWeld = weld,
		orbBaseC0 = baseC0,
		upLocal = root.CFrame:VectorToObjectSpace(Vector3.yAxis),
	}
	states[model] = state
	local id = model:GetAttribute("Id")
	if typeof(id) == "string" then
		statesById[id] = state
	end

	if withPop then
		-- Ja nasce pequena para nao piscar no tamanho cheio antes do primeiro frame do loop.
		model:ScaleTo(POP_START_SCALE)
		state.appliedScale = POP_START_SCALE
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
		local scale = 1

		-- Pop-in com easing Back (calculado na mao, sem criar Tween).
		if state.popTime >= 0 then
			state.popTime += dt
			local alpha = state.popTime / POP_DURATION
			if alpha >= 1 then
				state.popTime = -1
			else
				local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				scale = POP_START_SCALE + (1 - POP_START_SCALE) * eased
			end
		end

		-- Pulso de ataque: seno de 0 a pi = sobe e desce uma vez.
		if state.pulseTime >= 0 then
			state.pulseTime += dt
			if state.pulseTime >= PULSE_DURATION then
				state.pulseTime = -1
			else
				scale *= 1 + PULSE_STRENGTH * math.sin(math.pi * state.pulseTime / PULSE_DURATION)
			end
		end

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
		end

		-- Orb flutuando: mexe so no offset da junta (o ScaleTo ja escalou o C0, entao recalculamos).
		local weld = state.orbWeld
		if weld then
			local base = state.orbBaseC0
			local bob = math.sin(now * BOB_SPEED + state.phase) * BOB_HEIGHT * state.appliedScale
			weld.C0 = CFrame.new(base.Position * state.appliedScale + state.upLocal * bob) * base.Rotation
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
	table.clear(states)
	table.clear(statesById)
end

return UnitFxController
