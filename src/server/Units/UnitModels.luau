--!strict
-- Modelos chibi low-poly dos personagens (docs/DESIGN-PERSONAGENS.md).
--
-- Contrato (o cliente depende disto, nao quebre):
--   * model.Name = id; PrimaryPart = "Root" (pedestal neon ancorado).
--   * "Hitbox" e a UNICA peca com CanQuery (o painel faz raycast nela).
--   * Frente = -Z do baseCFrame (o servidor ja vira o baseCFrame para a estrada).
--   * Pecas de destaque usam Material.Neon com a cor de acento do Config:
--     o UnitFxController acha essas pecas e muda a cor delas por nivel.
--   * A bola magica do Mage se chama "Orb" e usa Weld (nao WeldConstraint):
--     o cliente anima o C0 dela para ela flutuar.
--   * Pecas de EVOLUCAO ja vem no modelo, invisiveis (atributo EvoPart).
--     setLevel(model, 4) mostra elas.
-- Cada personagem tem no maximo ~20 pecas e nenhuma luz (podem existir 24 na tela).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local UnitModels = {}

local PEDESTAL_HEIGHT = 0.3
local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- cilindro "deitado" vira disco em pe no Y
local SKIN = Color3.fromRGB(255, 221, 196)
local EYE = Color3.fromRGB(28, 26, 40)

-- Tudo que o visual precisa de um personagem.
export type Look = {
	height: number,
	body: Color3, -- roupa principal (cor MEDIA/CLARA: o mundo e noturno)
	secondary: Color3, -- detalhe da roupa (chapeu, armadura, cabelo)
	accent: Color3, -- neon (o cliente procura essa cor)
	evoAccent: Color3, -- neon da evolucao (nivel 4)
}

-- Visual de cada personagem. Os 3 iniciais pegam altura e neon do Config (lookFor).
-- Os 4 novos (gacha da S7) ainda nao estao no Config, entao tudo vem daqui.
UnitModels.LOOKS = {
	Ninja = { height = 5, body = Color3.fromRGB(70, 88, 150), secondary = Color3.fromRGB(40, 48, 84), accent = Color3.fromRGB(60, 220, 255), evoAccent = Color3.fromRGB(170, 80, 255) },
	Samurai = { height = 5.6, body = Color3.fromRGB(205, 60, 64), secondary = Color3.fromRGB(226, 192, 122), accent = Color3.fromRGB(255, 200, 60), evoAccent = Color3.fromRGB(120, 200, 255) },
	Mage = { height = 5.4, body = Color3.fromRGB(150, 112, 214), secondary = Color3.fromRGB(96, 66, 168), accent = Color3.fromRGB(230, 90, 255), evoAccent = Color3.fromRGB(170, 240, 255) },
	Archer = { height = 5.2, body = Color3.fromRGB(232, 232, 242), secondary = Color3.fromRGB(70, 80, 110), accent = Color3.fromRGB(255, 220, 50), evoAccent = Color3.fromRGB(255, 140, 60) },
	Brawler = { height = 5.2, body = Color3.fromRGB(240, 136, 52), secondary = Color3.fromRGB(60, 50, 50), accent = Color3.fromRGB(170, 255, 60), evoAccent = Color3.fromRGB(255, 245, 120) },
	Fox = { height = 5, body = Color3.fromRGB(246, 240, 246), secondary = Color3.fromRGB(255, 196, 150), accent = Color3.fromRGB(255, 110, 180), evoAccent = Color3.fromRGB(140, 200, 255) },
	Mecha = { height = 6.5, body = Color3.fromRGB(150, 156, 172), secondary = Color3.fromRGB(80, 86, 102), accent = Color3.fromRGB(40, 230, 255), evoAccent = Color3.fromRGB(255, 80, 120) },
} :: { [string]: Look }

-- Nome proprio de cada personagem (aparece como "Nome • Classe").
UnitModels.NAMES = {
	Ninja = "Sumi",
	Samurai = "Tetsu",
	Mage = "Mirai",
	Archer = "Hoshi",
	Brawler = "Jiro",
	Fox = "Kohana",
	Mecha = "Volt",
} :: { [string]: string }

-- Junta o visual daqui com os numeros oficiais do Config (altura e neon).
function UnitModels.lookFor(kind: string, def: Types.UnitDef?): Look
	local base = UnitModels.LOOKS[kind] or UnitModels.LOOKS.Ninja
	if not def then
		return base
	end
	local evo = base.evoAccent
	local last = def.upgrades[#def.upgrades]
	if last and last.evolution then
		evo = last.evolution.accentColor
	end
	return {
		height = def.height,
		body = base.body,
		secondary = base.secondary,
		accent = def.accentColor,
		evoAccent = evo,
	}
end

-- ---------------------------------------------------------------------------
-- Montagem
-- ---------------------------------------------------------------------------

type Ctx = {
	model: Model,
	root: BasePart,
	base: CFrame,
	look: Look,
	-- medidas do corpo (calculadas em buildBody)
	torsoY: number,
	torsoH: number,
	torsoW: number,
	headY: number,
	headD: number,
	headTop: number,
	handY: number,
	armX: number,
}

type AddOptions = {
	neon: boolean?,
	evo: boolean?, -- peca de evolucao: comeca invisivel
	material: Enum.Material?,
	shadow: boolean?,
	realWeld: boolean?, -- Weld com C0 (so o Orb)
	transparency: number?,
}

-- Cria uma peca soldada ao Root. offset e relativo ao chao do personagem (baseCFrame).
local function add(ctx: Ctx, name: string, shape: Enum.PartType, size: Vector3, offset: CFrame, color: Color3, options: AddOptions?): Part
	local opts: AddOptions = options or {}
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = if opts.neon then Enum.Material.Neon else (opts.material or Enum.Material.SmoothPlastic)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = opts.shadow == true
	local visible = opts.transparency or 0
	if opts.evo then
		-- Peca de evolucao nasce invisivel e SEM neon. Motivo: o UnitFxController guarda a
		-- transparencia das pecas neon quando a unidade aparece e reaplica isso todo frame
		-- (o brilho pulsando). Se ela nascesse neon e invisivel, ficaria invisivel para sempre.
		-- O setLevel liga o neon e a transparencia juntos.
		part:SetAttribute("EvoPart", true)
		part:SetAttribute("EvoTransparency", visible)
		part:SetAttribute("EvoNeon", opts.neon == true)
		part.Material = opts.material or Enum.Material.SmoothPlastic
		part.Transparency = 1
	else
		part.Transparency = visible
	end
	part.CFrame = ctx.base * offset
	part.Parent = ctx.model
	if opts.realWeld then
		local weld = Instance.new("Weld")
		weld.Part0 = ctx.root
		weld.Part1 = part
		weld.C0 = ctx.root.CFrame:ToObjectSpace(part.CFrame)
		weld.Parent = part
	else
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = ctx.root
		weld.Part1 = part
		weld.Parent = part
	end
	return part
end

local BLOCK = Enum.PartType.Block
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local WEDGE = Enum.PartType.Wedge

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Corpo chibi comum: 2 pernas, tronco, 2 bracos, cabeca grande, 2 olhos (7 pecas + Root/Hitbox).
-- legs = false troca as pernas por uma saia/manto (Mage).
local function buildBody(ctx: Ctx, legs: boolean)
	local h = ctx.look.height
	local legH = h * 0.17
	local torsoH = h * 0.26
	local torsoW = 1.4
	local headD = h * 0.42
	local torsoY = PEDESTAL_HEIGHT + legH + torsoH / 2
	local headY = PEDESTAL_HEIGHT + legH + torsoH + headD * 0.42
	ctx.torsoY, ctx.torsoH, ctx.torsoW = torsoY, torsoH, torsoW
	ctx.headY, ctx.headD, ctx.headTop = headY, headD, headY + headD / 2
	ctx.armX = torsoW / 2 + 0.24
	ctx.handY = torsoY - torsoH * 0.45

	local look = ctx.look
	if legs then
		for _, side in { -1, 1 } do
			add(ctx, if side < 0 then "LegL" else "LegR", BLOCK, Vector3.new(0.5, legH, 0.55), at(side * 0.32, PEDESTAL_HEIGHT + legH / 2, 0), look.secondary)
		end
	else
		add(ctx, "Robe", BLOCK, Vector3.new(1.7, legH + 0.1, 1.2), at(0, PEDESTAL_HEIGHT + legH / 2 + 0.05, 0), look.secondary)
	end
	add(ctx, "Body", BLOCK, Vector3.new(torsoW, torsoH, 0.95), at(0, torsoY, 0), look.body, { shadow = true })
	for _, side in { -1, 1 } do
		add(ctx, if side < 0 then "ArmL" else "ArmR", BLOCK, Vector3.new(0.42, torsoH * 0.95, 0.45), at(side * ctx.armX, torsoY - 0.05, 0), look.body)
	end
	add(ctx, "Head", BALL, Vector3.new(headD, headD, headD), at(0, headY, 0), SKIN, { shadow = true })
	for _, side in { -1, 1 } do
		add(ctx, if side < 0 then "EyeL" else "EyeR", BLOCK, Vector3.new(0.18, 0.3, 0.08), at(side * headD * 0.18, headY + headD * 0.02, -headD * 0.47), EYE)
	end
end

-- ---------------------------------------------------------------------------
-- Personagens
-- ---------------------------------------------------------------------------

-- Sumi • Ninja: mascara, faixa e cachecol neon com ponta voando, shurikens nas costas.
local function ninja(ctx: Ctx)
	buildBody(ctx, true)
	local l, d, y = ctx.look, ctx.headD, ctx.headY
	add(ctx, "Mask", BLOCK, Vector3.new(d * 0.86, d * 0.26, d * 0.5), at(0, y - d * 0.2, -d * 0.22), l.secondary)
	add(ctx, "Headband", BLOCK, Vector3.new(d * 1.04, 0.22, d * 1.04), at(0, y + d * 0.16, 0), l.accent, { neon = true })
	local neck = ctx.torsoY + ctx.torsoH / 2
	add(ctx, "Scarf", BLOCK, Vector3.new(1.6, 0.32, 1.15), at(0, neck, 0), l.accent, { neon = true })
	add(ctx, "ScarfTail1", BLOCK, Vector3.new(0.4, 0.18, 1.3), at(0.4, neck - 0.05, 1.05) * CFrame.Angles(0.35, 0.2, 0), l.accent, { neon = true })
	add(ctx, "ScarfTail2", BLOCK, Vector3.new(0.34, 0.16, 1.1), at(0.6, neck - 0.35, 2.0) * CFrame.Angles(0.6, 0.35, 0.1), l.accent, { neon = true })
	for i, x in { -0.35, 0.35 } do
		add(ctx, `Shuriken{i}`, BLOCK, Vector3.new(0.5, 0.5, 0.08), at(x, ctx.torsoY + 0.15, 0.52) * CFrame.Angles(0, 0, math.rad(45)), l.secondary, { material = Enum.Material.Metal })
	end
	-- Evolucao (Shadow Ninja): capa rasgada + segunda lamina na mao.
	add(ctx, "EvoCape", WEDGE, Vector3.new(1.5, ctx.torsoH + 0.9, 0.35), at(0, ctx.torsoY - 0.35, 0.62) * CFrame.Angles(0, math.pi, 0), l.evoAccent:Lerp(Color3.new(0, 0, 0), 0.55), { evo = true })
	add(ctx, "EvoBlade", BLOCK, Vector3.new(0.14, 0.14, 1.8), at(ctx.armX, ctx.handY, -0.7), l.evoAccent, { evo = true, neon = true })
end

-- Tetsu • Samurai: chapeu largo de palha, ombreiras, katana neon na cintura.
local function samurai(ctx: Ctx)
	buildBody(ctx, true)
	local l, d = ctx.look, ctx.headD
	add(ctx, "HatBrim", CYL, Vector3.new(0.22, d * 2.1, d * 2.1), at(0, ctx.headTop - 0.12, 0) * FLAT, l.secondary, { shadow = true })
	add(ctx, "HatTop", CYL, Vector3.new(0.4, d * 0.9, d * 0.9), at(0, ctx.headTop + 0.15, 0) * FLAT, l.secondary)
	local shoulderY = ctx.torsoY + ctx.torsoH * 0.38
	for _, side in { -1, 1 } do
		add(ctx, if side < 0 then "PadL" else "PadR", BLOCK, Vector3.new(0.75, 0.32, 0.85), at(side * (ctx.armX + 0.08), shoulderY, 0) * CFrame.Angles(0, 0, -side * 0.3), l.body:Lerp(Color3.new(0, 0, 0), 0.25))
	end
	add(ctx, "Belt", BLOCK, Vector3.new(ctx.torsoW + 0.05, 0.22, 1.0), at(0, ctx.torsoY - ctx.torsoH * 0.3, 0), l.secondary)
	add(ctx, "Katana", BLOCK, Vector3.new(0.14, 0.14, 2.6), at(-0.85, ctx.torsoY - ctx.torsoH * 0.3, 0.2) * CFrame.Angles(0.35, 0, 0), l.accent, { neon = true })
	add(ctx, "Hilt", BLOCK, Vector3.new(0.18, 0.18, 0.6), at(-0.85, ctx.torsoY - ctx.torsoH * 0.3 + 0.55, -1.25) * CFrame.Angles(0.35, 0, 0), Color3.fromRGB(40, 30, 30))
	-- Evolucao (Storm Samurai): chifres de raio no chapeu + segunda katana nas costas.
	for _, side in { -1, 1 } do
		add(ctx, if side < 0 then "EvoHornL" else "EvoHornR", WEDGE, Vector3.new(0.2, 1.1, 0.5), at(side * 0.45, ctx.headTop + 0.75, -0.2) * CFrame.Angles(0, 0, -side * 0.35), l.evoAccent, { evo = true, neon = true })
	end
	add(ctx, "EvoKatana", BLOCK, Vector3.new(0.14, 2.6, 0.14), at(0.3, ctx.torsoY + 0.3, 0.58) * CFrame.Angles(0, 0, 0.6), l.evoAccent, { evo = true, neon = true })
end

-- Mirai • Mage: manto, chapeu conico torto, cajado com Orb (o cliente faz o Orb flutuar).
local function mage(ctx: Ctx)
	buildBody(ctx, false)
	local l, d = ctx.look, ctx.headD
	local widths = { d * 1.9, d * 1.25, d * 0.7 }
	for i, width in widths do
		local tilt = CFrame.Angles(0, 0, (i - 1) * -0.12)
		add(ctx, `Hat{i}`, CYL, Vector3.new(0.5, width, width), at((i - 1) * 0.12, ctx.headTop - 0.1 + (i - 1) * 0.5, 0) * tilt * FLAT, l.secondary)
	end
	add(ctx, "HatBand", CYL, Vector3.new(0.14, d * 1.3, d * 1.3), at(0, ctx.headTop + 0.18, 0) * FLAT, l.accent, { neon = true })
	local staffX = ctx.armX + 0.25
	add(ctx, "Staff", BLOCK, Vector3.new(0.18, 4.2, 0.18), at(staffX, PEDESTAL_HEIGHT + 2.1, -0.35), Color3.fromRGB(110, 70, 50), { material = Enum.Material.Wood })
	add(ctx, "Orb", BALL, Vector3.new(1, 1, 1), at(staffX, PEDESTAL_HEIGHT + 4.7, -0.35), l.accent, { neon = true, realWeld = true })
	-- Evolucao (Frost Archmage): coroa de 3 cristais + cristal em volta do orb.
	for i = 1, 3 do
		local angle = (i - 2) * 0.6
		add(ctx, `EvoCrown{i}`, BLOCK, Vector3.new(0.3, 0.8, 0.3), at(math.sin(angle) * d * 0.5, ctx.headTop + 0.25, -math.cos(angle) * d * 0.5) * CFrame.Angles(0, 0, math.rad(45)), l.evoAccent, { evo = true, neon = true })
	end
	add(ctx, "EvoCrystal", BLOCK, Vector3.new(0.9, 0.9, 0.9), at(staffX, PEDESTAL_HEIGHT + 4.7, -0.35) * CFrame.Angles(math.rad(45), 0, math.rad(45)), l.evoAccent, { evo = true, neon = true, transparency = 0.45 })
end

-- Hoshi • Neon Archer: visor neon, rabo de cavalo alto, arco grande neon, aljava.
local function archer(ctx: Ctx)
	buildBody(ctx, true)
	local l, d, y = ctx.look, ctx.headD, ctx.headY
	add(ctx, "Hair", BALL, Vector3.new(d * 1.04, d * 0.7, d * 1.04), at(0, y + d * 0.2, 0.05), l.secondary)
	add(ctx, "Ponytail", BLOCK, Vector3.new(0.45, 1.3, 0.45), at(0, ctx.headTop + 0.1, d * 0.45) * CFrame.Angles(-0.7, 0, 0), l.secondary)
	add(ctx, "Visor", BLOCK, Vector3.new(d * 0.9, 0.25, 0.12), at(0, y + d * 0.04, -d * 0.48), l.accent, { neon = true })
	-- Arco: 3 barras formando um arco na mao esquerda.
	local bx = -(ctx.armX + 0.35)
	local cy = ctx.torsoY
	add(ctx, "BowMid", BLOCK, Vector3.new(0.16, 1.4, 0.16), at(bx, cy, -0.55), l.accent, { neon = true })
	add(ctx, "BowTop", BLOCK, Vector3.new(0.16, 1.2, 0.16), at(bx, cy + 1.15, -0.3) * CFrame.Angles(0.5, 0, 0), l.accent, { neon = true })
	add(ctx, "BowLow", BLOCK, Vector3.new(0.16, 1.2, 0.16), at(bx, cy - 1.15, -0.3) * CFrame.Angles(-0.5, 0, 0), l.accent, { neon = true })
	add(ctx, "Quiver", CYL, Vector3.new(1.4, 0.5, 0.5), at(0.3, ctx.torsoY + 0.2, 0.55) * CFrame.Angles(0, 0, math.rad(70)), l.secondary)
	-- Evolucao (Starfall Archer): estrela na testa + capa curta.
	add(ctx, "EvoStar1", BLOCK, Vector3.new(0.55, 0.55, 0.1), at(0, ctx.headTop + 0.3, -d * 0.2), l.evoAccent, { evo = true, neon = true })
	add(ctx, "EvoStar2", BLOCK, Vector3.new(0.55, 0.55, 0.1), at(0, ctx.headTop + 0.3, -d * 0.2) * CFrame.Angles(0, 0, math.rad(45)), l.evoAccent, { evo = true, neon = true })
	add(ctx, "EvoCape", BLOCK, Vector3.new(1.3, ctx.torsoH + 0.4, 0.15), at(0, ctx.torsoY - 0.2, 0.55), l.evoAccent:Lerp(Color3.new(1, 1, 1), 0.3), { evo = true })
end

-- Jiro • Street Brawler: cabelo espetado, gola da jaqueta, luvas gigantes neon.
local function brawler(ctx: Ctx)
	buildBody(ctx, true)
	local l, d = ctx.look, ctx.headD
	for i, x in { -0.35, 0, 0.35 } do
		add(ctx, `Spike{i}`, WEDGE, Vector3.new(0.4, 0.9, 0.7), at(x, ctx.headTop - 0.05, 0.1) * CFrame.Angles(0, math.pi, -x * 0.8), l.secondary)
	end
	add(ctx, "Collar", BLOCK, Vector3.new(ctx.torsoW + 0.2, 0.35, 1.05), at(0, ctx.torsoY + ctx.torsoH / 2, 0), l.body:Lerp(Color3.new(1, 1, 1), 0.2))
	add(ctx, "Shirt", BLOCK, Vector3.new(0.5, ctx.torsoH * 0.9, 0.1), at(0, ctx.torsoY, -0.48), Color3.fromRGB(240, 240, 240))
	for _, side in { -1, 1 } do
		add(ctx, if side < 0 then "GloveL" else "GloveR", BLOCK, Vector3.new(0.9, 0.9, 0.9), at(side * ctx.armX, ctx.handY - 0.2, -0.1), l.accent, { neon = true })
	end
	add(ctx, "Bandage", BLOCK, Vector3.new(d * 1.03, 0.2, d * 1.03), at(0, ctx.headY + d * 0.22, 0), Color3.fromRGB(240, 240, 240))
	-- Evolucao (Thunder Brawler): raios saindo dos ombros.
	for _, side in { -1, 1 } do
		add(ctx, if side < 0 then "EvoBoltL" else "EvoBoltR", WEDGE, Vector3.new(0.25, 1.3, 0.6), at(side * (ctx.armX + 0.2), ctx.torsoY + ctx.torsoH * 0.7, 0.1) * CFrame.Angles(0, 0, -side * 0.6), l.evoAccent, { evo = true, neon = true })
	end
end

-- Kohana • Fox Spirit: orelhas de raposa, 3 caudas, mascara de festival na lateral.
local function fox(ctx: Ctx)
	buildBody(ctx, true)
	local l, d, y = ctx.look, ctx.headD, ctx.headY
	for _, side in { -1, 1 } do
		add(ctx, if side < 0 then "EarL" else "EarR", WEDGE, Vector3.new(0.25, 0.9, 0.6), at(side * d * 0.3, ctx.headTop + 0.15, 0), l.body)
		add(ctx, if side < 0 then "EarTipL" else "EarTipR", WEDGE, Vector3.new(0.27, 0.35, 0.3), at(side * d * 0.3, ctx.headTop + 0.48, -0.08), l.accent, { neon = true })
	end
	add(ctx, "Hair", BALL, Vector3.new(d * 1.04, d * 0.6, d * 1.04), at(0, y + d * 0.24, 0.05), l.secondary)
	add(ctx, "FestivalMask", BALL, Vector3.new(0.75, 0.75, 0.3), at(d * 0.46, y + d * 0.1, -0.1) * CFrame.Angles(0, -1.2, 0), Color3.fromRGB(255, 255, 255))
	add(ctx, "MaskStripe", BLOCK, Vector3.new(0.5, 0.12, 0.12), at(d * 0.5, y + d * 0.1, -0.2) * CFrame.Angles(0, -1.2, 0), l.accent, { neon = true })
	for i, yaw in { -0.6, 0, 0.6 } do
		add(ctx, `Tail{i}`, BALL, Vector3.new(0.7, 0.7, 2.2), at(math.sin(yaw) * 0.9, ctx.torsoY - 0.2 + math.abs(yaw) * 0.3, 0.6 + math.cos(yaw) * 0.8) * CFrame.Angles(0.5, yaw, 0), l.body)
	end
	-- Evolucao (Moonfire Fox): 3 fogos-fatuos em volta.
	for i = 1, 3 do
		local angle = i * math.pi * 2 / 3
		add(ctx, `EvoFire{i}`, BALL, Vector3.new(0.6, 0.6, 0.6), at(math.cos(angle) * 1.6, ctx.headY, math.sin(angle) * 1.6), l.evoAccent, { evo = true, neon = true })
	end
end

-- Volt • Mecha Pilot: mini-mecha (sem o corpo chibi): pernas grossas, cabine de vidro com o
-- piloto dentro e canhoes nos ombros.
local function mecha(ctx: Ctx)
	local l, h = ctx.look, ctx.look.height
	local legH = h * 0.25
	local bodyH = h * 0.38
	local bodyY = PEDESTAL_HEIGHT + legH + bodyH / 2
	ctx.torsoY, ctx.torsoH, ctx.torsoW = bodyY, bodyH, 2.6
	ctx.headD = 1.3
	ctx.headY = bodyY + bodyH / 2 + 0.55
	ctx.headTop = ctx.headY + 0.65
	for _, side in { -1, 1 } do
		add(ctx, if side < 0 then "LegL" else "LegR", BLOCK, Vector3.new(0.8, legH, 1.1), at(side * 0.75, PEDESTAL_HEIGHT + legH / 2, 0), l.secondary, { material = Enum.Material.Metal })
		add(ctx, if side < 0 then "FootL" else "FootR", BLOCK, Vector3.new(1, 0.35, 1.5), at(side * 0.75, PEDESTAL_HEIGHT + 0.17, -0.15), l.secondary, { material = Enum.Material.Metal })
	end
	add(ctx, "Body", BLOCK, Vector3.new(2.6, bodyH, 1.9), at(0, bodyY, 0), l.body, { material = Enum.Material.Metal, shadow = true })
	add(ctx, "Cockpit", BLOCK, Vector3.new(1.5, 1.3, 0.2), at(0, bodyY + 0.15, -0.95), Color3.fromRGB(120, 200, 255), { material = Enum.Material.Glass, transparency = 0.35 })
	add(ctx, "Head", BALL, Vector3.new(1.1, 1.1, 1.1), at(0, bodyY + 0.2, -0.5), SKIN)
	add(ctx, "PilotHelmet", BLOCK, Vector3.new(1.15, 0.3, 1.15), at(0, bodyY + 0.65, -0.5), l.accent, { neon = true })
	add(ctx, "Antenna", BLOCK, Vector3.new(0.1, 0.9, 0.1), at(0.8, bodyY + bodyH / 2 + 0.45, 0.4), l.secondary)
	for _, side in { -1, 1 } do
		add(ctx, if side < 0 then "CannonL" else "CannonR", CYL, Vector3.new(1.9, 0.55, 0.55), at(side * 1.55, bodyY + bodyH / 2 + 0.2, -0.3) * CFrame.Angles(0, math.pi / 2, 0), l.secondary, { material = Enum.Material.Metal })
		add(ctx, if side < 0 then "MuzzleL" else "MuzzleR", CYL, Vector3.new(0.2, 0.6, 0.6), at(side * 1.55, bodyY + bodyH / 2 + 0.2, -1.25) * CFrame.Angles(0, math.pi / 2, 0), l.accent, { neon = true })
	end
	-- Evolucao (Giga Mech): casulos de missil nas costas.
	for _, side in { -1, 1 } do
		add(ctx, if side < 0 then "EvoPodL" else "EvoPodR", BLOCK, Vector3.new(0.8, 1.2, 0.9), at(side * 0.6, bodyY + bodyH / 2 + 0.5, 0.75), l.evoAccent, { evo = true, neon = true })
	end
end

local BUILDERS: { [string]: (Ctx) -> () } = {
	Ninja = ninja,
	Samurai = samurai,
	Mage = mage,
	Archer = archer,
	Brawler = brawler,
	Fox = fox,
	Mecha = mecha,
}

-- Monta o modelo. baseCFrame fica no chao (topo do slot), olhando para a estrada.
function UnitModels.build(id: string, kind: string, look: Look, baseCFrame: CFrame): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Shape = CYL
	root.Size = Vector3.new(PEDESTAL_HEIGHT, 3.2, 3.2)
	root.Color = look.accent
	root.Material = Enum.Material.Neon
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = baseCFrame * CFrame.new(0, PEDESTAL_HEIGHT / 2, 0) * FLAT
	root.Parent = model
	model.PrimaryPart = root

	-- Hitbox invisivel: a UNICA peca com CanQuery (o cliente faz raycast nela).
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(3.2, look.height + 0.6, 3.2)
	hitbox.Transparency = 1
	hitbox.Anchored = false
	hitbox.Massless = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.CFrame = baseCFrame * CFrame.new(0, (look.height + 0.6) / 2, 0)
	hitbox.Parent = model
	local hitboxWeld = Instance.new("WeldConstraint")
	hitboxWeld.Part0 = root
	hitboxWeld.Part1 = hitbox
	hitboxWeld.Parent = hitbox

	local ctx: Ctx = {
		model = model,
		root = root,
		base = baseCFrame,
		look = look,
		torsoY = 0,
		torsoH = 0,
		torsoW = 0,
		headY = 0,
		headD = 0,
		headTop = 0,
		handY = 0,
		armX = 0,
	}
	local builder = BUILDERS[kind] or ninja
	builder(ctx)
	return model, root
end

-- Mostra (nivel maximo) ou esconde as pecas de evolucao.
function UnitModels.setLevel(model: Model, level: number, maxLevel: number)
	local evolved = level >= maxLevel
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("EvoPart") == true then
			local visible = part:GetAttribute("EvoTransparency")
			part.Transparency = if evolved and typeof(visible) == "number" then visible else 1
			if part:GetAttribute("EvoNeon") == true then
				part.Material = if evolved then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end
	end
end

return UnitModels
