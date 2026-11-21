--!strict
-- PathMath: matematica PURA de caminhos (nao usa nenhum servico do Roblox).
-- Por ser pura, e facil de testar: mesma entrada, sempre a mesma saida.
-- Ideia: o caminho e uma linha quebrada (polilinha). Dada uma distancia
-- percorrida, descobrimos em que reta estamos e onde exatamente.

local Types = require(script.Parent.Parent.Types)

local PathMath = {}

-- Calcula o tamanho de cada reta e o total UMA vez.
-- Depois, consultar posicoes fica barato (bom para rodar todo frame).
function PathMath.build(points: { Vector3 }): Types.PathData
	local lengths: { number } = {}
	local total = 0
	for i = 1, #points - 1 do
		local len = (points[i + 1] - points[i]).Magnitude
		lengths[i] = len
		total += len
	end
	return { points = table.clone(points), lengths = lengths, total = total }
end

function PathMath.totalLength(points: { Vector3 }): number
	return PathMath.build(points).total
end

-- Descobre em qual reta (indice) a distancia cai e a fracao t (0 a 1) dentro dela.
-- Casos de borda: distancia negativa/NaN vira 0; maior que o total vira o fim;
-- retas de tamanho zero sao puladas (evita divisao por zero).
function PathMath.segmentAt(data: Types.PathData, distance: number): (number, number)
	local segmentCount = #data.lengths
	if segmentCount == 0 then
		return 1, 0
	end

	local d = distance
	if d ~= d or d < 0 then -- "d ~= d" so e verdade para NaN
		d = 0
	elseif d > data.total then
		d = data.total
	end

	for i = 1, segmentCount do
		local len = data.lengths[i]
		if len > 0 then
			if d <= len then
				return i, d / len
			end
			d -= len
		end
	end

	-- Sobrou por erro de arredondamento (ou tudo tem tamanho zero): fim da ultima reta.
	return segmentCount, 1
end

-- Posicao no mundo depois de andar "distance" studs desde o primeiro ponto.
function PathMath.positionAt(data: Types.PathData, distance: number): Vector3
	local pointCount = #data.points
	assert(pointCount >= 1, "PathMath.positionAt: caminho sem pontos")
	if pointCount == 1 then
		return data.points[1]
	end

	local index, t = PathMath.segmentAt(data, distance)
	return data.points[index]:Lerp(data.points[index + 1], t)
end

-- Direcao (vetor unitario no plano XZ) da reta onde a distancia cai.
-- Serve para o inimigo "olhar" para onde esta andando. Se nao der para calcular
-- (sem retas, ou reta so vertical), devolve Vector3.zAxis como valor seguro.
function PathMath.directionAt(data: Types.PathData, distance: number): Vector3
	if #data.points < 2 then
		return Vector3.zAxis
	end

	local index = PathMath.segmentAt(data, distance)
	local delta = data.points[index + 1] - data.points[index]
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < 1e-4 then
		return Vector3.zAxis
	end
	return flat.Unit
end

return PathMath
