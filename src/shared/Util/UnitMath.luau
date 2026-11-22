--!strict
-- UnitMath: matematica PURA dos niveis das unidades.
-- O servidor usa como autoridade; o cliente so usa para MOSTRAR os numeros no painel.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

export type UnitStats = {
	level: number,
	displayName: string,
	accentColor: Color3,
	damage: number,
	range: number,
	cooldown: number,
	splashRadius: number,
	ability: Types.UnitAbility?, -- nil antes do nivel 4
}

local UnitMath = {}

-- Status da unidade no nivel pedido (o nivel e preso entre 1 e MAX_UNIT_LEVEL).
function UnitMath.statsAt(def: Types.UnitDef, level: number): UnitStats
	local clamped = math.clamp(math.floor(level), 1, Config.MAX_UNIT_LEVEL)
	if clamped == 1 then
		return {
			level = 1,
			displayName = def.displayName,
			accentColor = def.accentColor,
			damage = def.damage,
			range = def.range,
			cooldown = def.cooldown,
			splashRadius = def.splashRadius,
			ability = nil,
		}
	end
	local data = def.upgrades[clamped - 1]
	if not data then
		-- Erro de Config: falha logo e com nome, em vez de quebrar longe daqui.
		error(`UnitMath.statsAt: {def.displayName} has no upgrades[{clamped - 1}] (Config bug)`)
	end
	local evolution = data.evolution
	return {
		level = clamped,
		displayName = if evolution then evolution.displayName else def.displayName,
		accentColor = if evolution then evolution.accentColor else def.accentColor,
		damage = data.damage,
		range = data.range,
		cooldown = data.cooldown,
		splashRadius = data.splashRadius,
		ability = if evolution then evolution.ability else nil,
	}
end

-- Preco para ir de "level" para "level + 1". nil se ja esta no maximo.
function UnitMath.upgradeCost(def: Types.UnitDef, level: number): number?
	if level >= Config.MAX_UNIT_LEVEL then
		return nil
	end
	local data = def.upgrades[math.max(1, math.floor(level))]
	return if data then data.cost else nil
end

-- Quanto volta ao vender. nil = nao pode vender nesse estado da partida.
function UnitMath.refundFor(spent: number, stateName: string?): number?
	if stateName == nil then
		return nil
	end
	local rate = Config.SELL_REFUND[stateName]
	if rate == nil then
		return nil
	end
	return math.floor(spent * rate)
end

return UnitMath
