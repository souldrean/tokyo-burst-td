--!strict
-- Config: todos os numeros "ajustaveis" do jogo ficam aqui.
-- Assim, para mudar a velocidade de um inimigo, voce mexe em UM lugar so.
-- table.freeze deixa a tabela somente leitura: ninguem muda um valor por engano.
-- ATENCAO: ENEMIES, WAVES, WAVE_TIMEOUT_SECONDS, INTERMISSION_SECONDS, UNITS, START_CASH
-- e MAX_UNITS_PER_PLAYER tem uma copia em tools/sim_match.py. Se mudar aqui, mude la tambem (mantenha em sincronia).

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
		displayName = "Ninja",
		cost = 50,
		range = 28,
		damage = 8,
		cooldown = 0.5,
		splashRadius = 0,
		color = Color3.fromRGB(40, 44, 70),
		accentColor = Color3.fromRGB(60, 220, 255),
		height = 5,
		attackStyle = "Shuriken",
	},
	Samurai = {
		displayName = "Samurai",
		cost = 160,
		range = 18,
		damage = 30,
		cooldown = 1.4,
		splashRadius = 0,
		color = Color3.fromRGB(190, 40, 50),
		accentColor = Color3.fromRGB(255, 200, 60),
		height = 5.6,
		attackStyle = "Slash",
	},
	Mage = {
		displayName = "Mage",
		cost = 260,
		range = 24,
		damage = 13,
		cooldown = 1.4,
		splashRadius = 9,
		color = Color3.fromRGB(90, 60, 170),
		accentColor = Color3.fromRGB(230, 90, 255),
		height = 5.4,
		attackStyle = "Orb",
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

	-- Debug (so no Studio)
	DEBUG_HIT_DAMAGE = 5,

	ENEMIES = ENEMIES,
	WAVES = WAVES,
	UNITS = UNITS,
}

return table.freeze(Config)
