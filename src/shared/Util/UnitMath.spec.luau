--!strict
-- Testes simples da UnitMath (sem TestEZ). Testam so funcoes puras.
-- Para rodar no Studio (execute_luau, no Client ou no Server):
--   require(game.ReplicatedStorage.Shared.Util["UnitMath.spec"]).run()
-- Ele imprime o resumo e devolve: quantos passaram, quantos falharam, e a lista de falhas.

local UnitMath = require(script.Parent.UnitMath)
local Config = require(script.Parent.Parent.Config)

-- Tipo de uma unidade (pegamos do proprio Config, assim nao precisamos importar Types).
type UnitDef = typeof(Config.UNITS.Ninja)

type Report = {
	passed: number,
	failed: number,
	failures: { string },
}

-- Compara o valor recebido com o esperado e guarda o resultado no relatorio.
-- "==" compara valores (numeros, texto, nil e Color3 funcionam direto).
local function expectEqual(report: Report, label: string, got: any, expected: any)
	if got == expected then
		report.passed += 1
	else
		report.failed += 1
		table.insert(
			report.failures,
			`{label}: recebeu {tostring(got)}, esperado {tostring(expected)}`
		)
	end
end

-- Nivel e "preso" entre 1 e 4. Numero quebrado vira o inteiro de baixo (2.7 -> 2).
local function testLevelClamping(report: Report)
	local def = Config.UNITS.Ninja
	expectEqual(report, "clamp: nivel 0 vira 1", UnitMath.statsAt(def, 0).level, 1)
	expectEqual(report, "clamp: nivel 1 fica 1", UnitMath.statsAt(def, 1).level, 1)
	expectEqual(report, "clamp: nivel 4 fica 4", UnitMath.statsAt(def, 4).level, 4)
	expectEqual(report, "clamp: nivel 99 vira 4", UnitMath.statsAt(def, 99).level, 4)
	expectEqual(report, "clamp: nivel 2.7 vira 2", UnitMath.statsAt(def, 2.7).level, 2)
end

-- Para um nivel, os status devem bater com o Config (nivel 1 usa os campos da unidade,
-- niveis 2-4 usam upgrades[nivel - 1]).
local function checkStatsAtLevel(report: Report, name: string, def: UnitDef, level: number)
	local label = `{name} Lv{level}`
	local stats = UnitMath.statsAt(def, level)
	local expected = if level == 1 then def else def.upgrades[level - 1]

	expectEqual(report, `{label} level`, stats.level, level)
	expectEqual(report, `{label} damage`, stats.damage, expected.damage)
	expectEqual(report, `{label} range`, stats.range, expected.range)
	expectEqual(report, `{label} cooldown`, stats.cooldown, expected.cooldown)
	expectEqual(report, `{label} splashRadius`, stats.splashRadius, expected.splashRadius)

	-- So o Lv4 tem evolucao: nome e cor mudam. Antes disso, sao os da unidade.
	local evolution = if level == 4 then def.upgrades[3].evolution else nil
	local expectedName = if evolution then evolution.displayName else def.displayName
	local expectedAccent = if evolution then evolution.accentColor else def.accentColor
	expectEqual(report, `{label} displayName`, stats.displayName, expectedName)
	expectEqual(report, `{label} accentColor`, stats.accentColor, expectedAccent)
end

-- Todos os status de todas as unidades, em todos os niveis 1..4.
local function testStatsMatchConfig(report: Report)
	for _, name in Config.UNIT_ORDER do
		local def = Config.UNITS[name]
		for level = 1, Config.MAX_UNIT_LEVEL do
			checkStatsAtLevel(report, name, def, level)
		end
	end
end

-- Habilidade (ability) so existe no Lv4, e e a habilidade da evolucao.
local function testAbilityOnlyAtLevel4(report: Report)
	for _, name in Config.UNIT_ORDER do
		local def = Config.UNITS[name]
		local evolution = def.upgrades[3].evolution

		expectEqual(report, `{name} upgrade 1 sem evolucao`, def.upgrades[1].evolution, nil)
		expectEqual(report, `{name} upgrade 2 sem evolucao`, def.upgrades[2].evolution, nil)
		expectEqual(report, `{name} Config tem evolucao no Lv4`, evolution ~= nil, true)

		for level = 1, 3 do
			expectEqual(
				report,
				`{name} Lv{level} sem habilidade`,
				UnitMath.statsAt(def, level).ability,
				nil
			)
		end

		local ability = UnitMath.statsAt(def, 4).ability
		expectEqual(report, `{name} Lv4 tem habilidade`, ability ~= nil, true)
		if evolution and ability then
			expectEqual(
				report,
				`{name} Lv4 tipo da habilidade`,
				ability.kind,
				evolution.ability.kind
			)
		end
	end
end

-- Custo para subir de nivel: upgradeCost(nivel) = custo do upgrades[nivel].
-- No nivel maximo nao existe proximo custo, entao devolve nil.
local function testUpgradeCost(report: Report)
	for _, name in Config.UNIT_ORDER do
		local def = Config.UNITS[name]
		for level = 1, 3 do
			expectEqual(
				report,
				`{name} custo para subir do Lv{level}`,
				UnitMath.upgradeCost(def, level),
				def.upgrades[level].cost
			)
		end
		expectEqual(report, `{name} Lv4 sem proximo custo`, UnitMath.upgradeCost(def, 4), nil)
		expectEqual(report, `{name} nivel 99 sem proximo custo`, UnitMath.upgradeCost(def, 99), nil)
	end
end

-- Somando o preco base com todos os upgrades (usando so upgradeCost) chega no
-- mesmo total que somar o Config na mao, e a unidade chega no Lv4.
local function testTotalSpent(report: Report)
	for _, name in Config.UNIT_ORDER do
		local def = Config.UNITS[name]
		local spent = def.cost
		local level = 1
		local cost = UnitMath.upgradeCost(def, level)
		while cost ~= nil do
			spent += cost
			level += 1
			cost = UnitMath.upgradeCost(def, level)
		end

		local expectedTotal = def.cost
			+ def.upgrades[1].cost
			+ def.upgrades[2].cost
			+ def.upgrades[3].cost
		expectEqual(report, `{name} gasto total ate Lv4`, spent, expectedTotal)
		expectEqual(report, `{name} chega no Lv4 gastando tudo`, level, 4)
	end
end

-- Venda: Intermission devolve 100%, Wave devolve 60% arredondado para BAIXO (math.floor).
-- Estados sem regra de venda (ou nil) devolvem nil.
local function testSellRefund(report: Report)
	expectEqual(
		report,
		"venda Intermission 100%: 100 -> 100",
		UnitMath.refundFor(100, "Intermission"),
		100
	)
	expectEqual(report, "venda Wave 60%: 100 -> 60", UnitMath.refundFor(100, "Wave"), 60)
	expectEqual(
		report,
		"venda Wave arredonda para baixo: 101 -> 60",
		UnitMath.refundFor(101, "Wave"),
		60
	)
	expectEqual(report, "venda Wave: 160 -> 96", UnitMath.refundFor(160, "Wave"), 96)
	expectEqual(report, "venda Wave: 1 -> 0", UnitMath.refundFor(1, "Wave"), 0)
	expectEqual(report, "venda Wave: total Ninja 350 -> 210", UnitMath.refundFor(350, "Wave"), 210)
	expectEqual(
		report,
		"venda Wave: total Samurai 750 -> 450",
		UnitMath.refundFor(750, "Wave"),
		450
	)
	expectEqual(report, "venda Wave: total Mage 1080 -> 648", UnitMath.refundFor(1080, "Wave"), 648)
	expectEqual(report, "venda Waiting nao pode: nil", UnitMath.refundFor(100, "Waiting"), nil)
	expectEqual(report, "venda Victory nao pode: nil", UnitMath.refundFor(100, "Victory"), nil)
	expectEqual(report, "venda sem estado: nil", UnitMath.refundFor(100, nil), nil)
end

local function run(): (number, number, { string })
	local report: Report = { passed = 0, failed = 0, failures = {} }

	testLevelClamping(report)
	testStatsMatchConfig(report)
	testAbilityOnlyAtLevel4(report)
	testUpgradeCost(report)
	testTotalSpent(report)
	testSellRefund(report)

	print(`UnitMath.spec: {report.passed} passaram, {report.failed} falharam`)
	for _, message in report.failures do
		warn(message)
	end
	return report.passed, report.failed, report.failures
end

return { run = run }
