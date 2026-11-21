--!strict
-- EnemyMath: matematica PURA do movimento dos inimigos.
-- O servidor nao move inimigos todo frame: guarda so (BaseDistance, BaseTime, Speed).
-- Servidor e clientes usam esta MESMA formula, entao todo mundo ve o inimigo no mesmo lugar.

local EnemyMath = {}

-- distancia(agora) = BaseDistance + Speed * (agora - BaseTime)
-- Nunca devolve negativo (se o relogio do cliente estiver um pouco atrasado).
function EnemyMath.distanceAt(baseDistance: number, baseTime: number, speed: number, now: number): number
	local d = baseDistance + speed * (now - baseTime)
	if d ~= d or d < 0 then -- "d ~= d" so e verdade para NaN
		return 0
	end
	return d
end

return EnemyMath
