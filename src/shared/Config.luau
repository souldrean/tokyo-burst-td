--!strict
-- Config: todos os numeros "ajustaveis" do jogo ficam aqui.
-- Assim, para mudar a velocidade de um inimigo, voce mexe em UM lugar so.
-- table.freeze deixa a tabela somente leitura: ninguem muda um valor por engano.
-- ATENCAO: ENEMIES, WAVES, WAVE_TIMEOUT_SECONDS, INTERMISSION_SECONDS, UNITS (inclusive upgrades),
-- START_CASH, MAX_UNITS_PER_PLAYER, WAVE_BREAK_SECONDS, SELL_REFUND e BOSS_SLOW_FACTOR tem uma copia em tools/sim_match.py. Se mudar aqui, mude la tambem (mantenha em sincronia).

local Types = require(script.Parent.Types)

local ENEMIES: { [string]: Types.EnemyDef } = {
	Grunt = {
		health = 20,
		speed = 20,
		baseDamage = 5,
		reward = 5,
		size = Vector3.new(2.4, 2.8, 2.4),
		color = Color3.fromRGB(170, 40, 60),
		eyeColor = Color3.fromRGB(255, 240, 80),
		horns = false,
	},
	Runner = {
		health = 12,
		speed = 32,
		baseDamage = 4,
		reward = 4,
		size = Vector3.new(1.8, 2.2, 1.8),
		color = Color3.fromRGB(255, 120, 30),
		eyeColor = Color3.fromRGB(255, 255, 255),
		horns = false,
	},
	Tank = {
		health = 90,
		speed = 14,
		baseDamage = 12,
		reward = 15,
		size = Vector3.new(4, 4.4, 4),
		color = Color3.fromRGB(90, 40, 140),
		eyeColor = Color3.fromRGB(255, 60, 60),
		horns = true,
	},
	Oni = {
		health = 600,
		speed = 12,
		baseDamage = 40,
		reward = 100,
		size = Vector3.new(6.5, 7.5, 6.5),
		color = Color3.fromRGB(200, 20, 20),
		eyeColor = Color3.fromRGB(255, 220, 0),
		horns = true,
	},
}

local WAVES: { Types.WaveDef } = {
	{ groups = { { kind = "Grunt", count = 5, interval = 1.2 } } },
	{ groups = { { kind = "Grunt", count = 8, interval = 1.0 } } },
	{ groups = { { kind = "Grunt", count = 6, interval = 1.0 }, { kind = "Runner", count = 4, interval = 0.8 } } },
	{ groups = { { kind = "Grunt", count = 8, interval = 0.8 }, { kind = "Tank", count = 2, interval = 2.0 } } },
	{ groups = { { kind = "Runner", count = 10, interval = 0.6 }, { kind = "Grunt", count = 6, interval = 0.8 } } },
	{ groups = { { kind = "Tank", count = 3, interval = 2.0 }, { kind = "Grunt", count = 10, interval = 0.7 } } },
	{ groups = { { kind = "Runner", count = 12, interval = 0.5 }, { kind = "Tank", count = 3, interval = 1.5 } } },
	{
		groups = {
			{ kind = "Grunt", count = 15, interval = 0.5 },
			{ kind = "Tank", count = 4, interval = 1.5 },
			{ kind = "Runner", count = 6, interval = 0.5 },
		},
	},
	{
		groups = {
			{ kind = "Tank", count = 6, interval = 1.0 },
			{ kind = "Runner", count = 14, interval = 0.4 },
			{ kind = "Grunt", count = 10, interval = 0.5 },
		},
	},
	{
		groups = {
			{ kind = "Grunt", count = 8, interval = 0.6 },
			{ kind = "Tank", count = 4, interval = 1.2 },
			{ kind = "Oni", count = 1, interval = 1.0 },
		},
		boss = true,
	},
}

-- Unidades (semana 3). Numeros calibrados com tools/sim_match.py (cenario c).
-- Os slots ficam a ~12-14 studs do centro da estrada, por isso os alcances sao altos.
local UNITS: { [string]: Types.UnitDef } = {
	Ninja = {
		displayName = "Sumi • Ninja",
		cost = 50,
		range = 28,
		damage = 8,
		cooldown = 0.5,
		splashRadius = 0,
		color = Color3.fromRGB(40, 44, 70),
		accentColor = Color3.fromRGB(60, 220, 255),
		height = 5,
		attackStyle = "Shuriken",
		upgrades = {
			{ cost = 60, damage = 10, range = 29, cooldown = 0.5, splashRadius = 0 },
			{ cost = 90, damage = 12, range = 30, cooldown = 0.5, splashRadius = 0 },
			{
				cost = 150,
				damage = 15,
				range = 31,
				cooldown = 0.45,
				splashRadius = 0,
				evolution = {
					displayName = "Sumi • Shadow Ninja",
					accentColor = Color3.fromRGB(170, 80, 255),
					ability = { kind = "MultiShot", description = "Throws 3 shurikens at once", targets = 3 },
				},
			},
		},
	},
	Samurai = {
		displayName = "Tetsu • Samurai",
		cost = 160,
		range = 18,
		damage = 30,
		cooldown = 1.4,
		splashRadius = 0,
		color = Color3.fromRGB(190, 40, 50),
		accentColor = Color3.fromRGB(255, 200, 60),
		height = 5.6,
		attackStyle = "Slash",
		upgrades = {
			{ cost = 120, damage = 42, range = 19, cooldown = 1.4, splashRadius = 0 },
			{ cost = 170, damage = 58, range = 20, cooldown = 1.3, splashRadius = 0 },
			{
				cost = 300,
				damage = 70,
				range = 21,
				cooldown = 1.2,
				splashRadius = 0,
				evolution = {
					displayName = "Tetsu • Storm Samurai",
					accentColor = Color3.fromRGB(120, 200, 255),
					ability = { kind = "Crit", description = "Every 3rd slash hits 3x harder", every = 3, multiplier = 3 },
				},
			},
		},
	},
	Mage = {
		displayName = "Mirai • Mage",
		cost = 260,
		range = 24,
		damage = 13,
		cooldown = 1.4,
		splashRadius = 9,
		color = Color3.fromRGB(90, 60, 170),
		accentColor = Color3.fromRGB(230, 90, 255),
		height = 5.4,
		attackStyle = "Orb",
		upgrades = {
			{ cost = 180, damage = 18, range = 24, cooldown = 1.4, splashRadius = 10 },
			{ cost = 240, damage = 24, range = 26, cooldown = 1.35, splashRadius = 11 },
			{
				cost = 400,
				damage = 30,
				range = 27,
				cooldown = 1.3,
				splashRadius = 12,
				evolution = {
					displayName = "Mirai • Frost Archmage",
					accentColor = Color3.fromRGB(170, 240, 255),
					ability = { kind = "Slow", description = "Hits slow enemies by 40% for 2s", factor = 0.6, duration = 2 },
				},
			},
		},
	},
}

local Config = {
	-- Cubo de teste da semana 1 (codigo mantido, mas desligado).
	PATH_PREVIEW_ENABLED = false,
	PATH_PREVIEW_SPEED = 20,
	PATH_PREVIEW_CUBE_SIZE = 3,
	PATH_PREVIEW_HEIGHT = 2,

	-- Partida
	INTERMISSION_SECONDS = 6, -- pausa antes da primeira onda
	RESTART_DELAY_SECONDS = 8, -- tempo na tela de Vitoria/Derrota antes de recomecar
	BASE_MAX_HEALTH = 100,
	WAVE_TIMEOUT_SECONDS = 15, -- depois disto a proxima onda comeca mesmo com inimigos vivos

	-- Servidor
	SERVER_TICK_RATE = 10, -- vezes por segundo que o servidor confere se inimigos chegaram ao fim
	MAX_ENEMIES_ALIVE = 60, -- limite de seguranca

	-- Unidades e dinheiro (semana 3)
	START_CASH = 60, -- dinheiro de cada jogador no inicio da partida
	MAX_UNITS_PER_PLAYER = 6,
	-- Estados em que pode colocar unidade (conjunto: chave = estado, valor = true).
	PLACE_ALLOWED_STATES = { Intermission = true, Wave = true } :: { [string]: boolean },
	UNIT_ORDER = { "Ninja", "Samurai", "Mage" } :: { string }, -- ordem da hotbar

	-- Upgrades e venda (semana 4)
	MAX_UNIT_LEVEL = 4,
	-- estado da partida -> parte do dinheiro devolvida; estado ausente = nao pode vender.
	SELL_REFUND = { Intermission = 1, Wave = 0.6 } :: { [string]: number },
	-- Folga (s) depois que a pausa acaba em que a venda ainda paga a taxa da pausa:
	-- o botao mostra 100% no fim da pausa, e o pedido chega um pouco depois (latencia).
	SELL_GRACE_SECONDS = 0.5,
	UPGRADE_ALLOWED_STATES = { Intermission = true, Wave = true } :: { [string]: boolean },
	BOSS_KINDS = { Oni = true } :: { [string]: boolean }, -- chefes sao menos afetados pelo Slow
	BOSS_SLOW_FACTOR = 0.8,
	WAVE_BREAK_SECONDS = 5, -- pausa depois de limpar uma onda (sim_match.py tem copia)

	-- Debug (so no Studio)
	DEBUG_GIVE_CASH = 500,
	DEBUG_HIT_DAMAGE = 5,

	ENEMIES = ENEMIES,
	WAVES = WAVES,
	UNITS = UNITS,
}

return table.freeze(Config)
