--!strict
-- Types: tipos compartilhados entre servidor e cliente.
-- Tipos so existem para o verificador de codigo (nao rodam no jogo).
-- Um ModuleScript precisa devolver um valor, entao devolvemos uma tabela vazia
-- (devolver "nil" puro da erro no Roblox).

-- Dados pre-calculados de um caminho feito de pontos ligados por retas.
export type PathData = {
	points: { Vector3 }, -- os waypoints, em ordem
	lengths: { number }, -- lengths[i] = distancia do ponto i ate o ponto i+1
	total: number, -- comprimento total do caminho
}

-- Nomes dos RemoteEvents (a lista fica aqui para cliente e servidor concordarem).
export type RemoteName =
	"EnemyDied"
	| "BaseHit"
	| "WaveStarted"
	| "MatchEnded"
	| "DebugHitEnemy"
	| "PlaceUnit"
	| "UnitPlaced"
	| "UnitAttacked"
	| "Notify"
	| "UpgradeUnit"
	| "SellUnit"
	| "UnitUpgraded"
	| "UnitSold"
	| "DebugGiveCash"

-- Por que um inimigo saiu do jogo: morto por nos ou chegou no fim (vazou).
export type DeathReason = "Killed" | "Leaked"

export type MatchResult = "Victory" | "Defeat"

-- Estados da partida (atributo State em ReplicatedStorage.MatchState).
export type MatchStateName = "Waiting" | "Intermission" | "Wave" | "Victory" | "Defeat"

-- Payloads (ordem dos argumentos de cada RemoteEvent, servidor -> clientes):
--   EnemyDied(id: string, reason: DeathReason, position: Vector3, reward: number)
--   BaseHit(damage: number, healthLeft: number)
--   WaveStarted(wave: number, waveCount: number, isBoss: boolean)
--   MatchEnded(result: MatchResult)
--   DebugHitEnemy(id: string)   <- cliente -> servidor (so no Studio)
--   (semana 3)
--   PlaceUnit(kind: string, slotName: string)        <- cliente -> servidor
--   UnitPlaced(id: string, kind: string, position: Vector3, ownerUserId: number)   <- todos
--   UnitAttacked(id: string, kind: string, from: Vector3, to: Vector3, special: string?) <- todos
--       special = "Crit" (golpe critico), "Slow" (Mago congelou), nil = normal
--   (semana 4)
--   UpgradeUnit(id: string)                           <- cliente -> servidor
--   SellUnit(id: string)                              <- cliente -> servidor
--   DebugGiveCash()                                   <- cliente -> servidor (so no Studio)
--   UnitUpgraded(id: string, level: number, position: Vector3)                     <- todos
--   UnitSold(id: string, position: Vector3, refund: number, ownerUserId: number)   <- todos
--   Notify(text: string)                              <- servidor -> UM cliente
export type EnemyDiedPayload = {
	id: string,
	reason: DeathReason,
	position: Vector3,
	reward: number,
}

-- Dados de um tipo de inimigo (vem do Config.ENEMIES).
export type EnemyDef = {
	health: number,
	speed: number,
	baseDamage: number,
	reward: number,
	size: Vector3,
	color: Color3,
	eyeColor: Color3,
	horns: boolean,
}

-- Como a unidade ataca (so muda o visual do ataque no cliente).
export type AttackStyle = "Shuriken" | "Slash" | "Orb"

-- Habilidades do nivel 4 (evolucao).
export type AbilityKind = "MultiShot" | "Crit" | "Slow"
export type UnitAbility = {
	kind: AbilityKind,
	description: string, -- texto curto em ingles para o painel
	targets: number?, -- MultiShot: quantos inimigos diferentes por ataque
	every: number?, -- Crit: a cada N ataques
	multiplier: number?, -- Crit: multiplicador de dano
	factor: number?, -- Slow: multiplicador de velocidade (0.6 = 40% mais lento)
	duration: number?, -- Slow: segundos
}
export type UnitEvolution = {
	displayName: string, -- nome novo no nivel 4
	accentColor: Color3, -- cor neon nova no nivel 4
	ability: UnitAbility,
}
-- Status de UM nivel (valores absolutos, nao diferencas).
export type UnitLevel = {
	cost: number, -- preco para subir PARA este nivel
	damage: number,
	range: number,
	cooldown: number,
	splashRadius: number,
	evolution: UnitEvolution?, -- so na entrada do nivel 4
}

-- Dados de um tipo de unidade/torre (vem do Config.UNITS).
export type UnitDef = {
	displayName: string,
	cost: number,
	range: number, -- studs, distancia no plano XZ
	damage: number,
	cooldown: number, -- segundos entre ataques
	splashRadius: number, -- 0 = dano em um alvo so
	color: Color3, -- corpo
	accentColor: Color3, -- partes neon e projetil
	height: number,
	attackStyle: AttackStyle,
	upgrades: { UnitLevel }, -- exatamente 3: upgrades[1] = nivel 2, [2] = nivel 3, [3] = nivel 4
}

-- Uma linha do "retrato" dos inimigos vivos (EnemyService.snapshot).
export type SnapshotEntry = {
	id: string,
	distance: number, -- studs andados no caminho
	position: Vector3, -- centro do inimigo no mundo
	kind: string, -- tipo (Grunt, Oni...) usado pelo Slow para chefes
}

-- Um grupo de inimigos do mesmo tipo dentro de uma onda.
export type WaveGroup = {
	kind: string,
	count: number,
	interval: number, -- segundos entre cada spawn
}

export type WaveDef = {
	groups: { WaveGroup },
	boss: boolean?,
}

return {}
