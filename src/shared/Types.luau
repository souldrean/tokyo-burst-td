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

return {}
