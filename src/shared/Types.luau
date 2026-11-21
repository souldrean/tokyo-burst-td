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
export type RemoteName = "EnemyDied" | "BaseHit" | "WaveStarted" | "MatchEnded" | "DebugHitEnemy"

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
