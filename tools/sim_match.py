#!/usr/bin/env python3
"""sim_match.py - estima a duracao de uma partida do Tokyo Burst TD.

ATENCAO: os numeros de ENEMIES, WAVES e as constantes abaixo sao uma COPIA de
src/shared/Config.luau. Se mudar um, mude o outro (mantenha os dois em sincronia).

Rode com:  python3 -I tools/sim_match.py

Cenarios:
  (a) todo inimigo morre quando chega a 40% do caminho (torres boas);
  (b) ninguem morre (quanto tempo ate a base sem defesa cair?);
  (c) UM jogador competente: ganha dinheiro com os kills, compra unidades com a
      regra "melhor valor primeiro" e vemos se a base sobrevive (semana 3).

ATENCAO (semana 3): UNITS, START_CASH, MAX_UNITS_PER_PLAYER e os campos health/reward
de ENEMIES tambem sao copia de src/shared/Config.luau.

Semana 4: UPGRADES (niveis 2-4 de cada unidade), WAVE_BREAK_SECONDS, BOSS_SLOW_FACTOR e as
habilidades da evolucao tambem sao copia de Config.luau. O cenario (c) agora tambem compra
upgrades (melhor "poder extra por dinheiro") e pode ECONOMIZAR para uma evolucao.
"""

PATH_LENGTH = 640.0  # studs (caminho do mapa, aprox.)
INTERMISSION_SECONDS = 6
WAVE_BREAK_SECONDS = 5  # pausa depois de limpar uma onda que nao e a ultima (copia do Config)
BASE_MAX_HEALTH = 100
WAVE_TIMEOUT_SECONDS = 15
KILL_FRACTION = 0.4

# kind -> (speed, baseDamage, health, reward)
ENEMIES = {
    "Grunt": (20, 5, 20, 5),
    "Runner": (32, 4, 12, 4),
    "Tank": (14, 12, 90, 15),
    "Oni": (12, 40, 600, 100),
}

# --- Semana 3: unidades (copia de Config.UNITS) ---
START_CASH = 60
MAX_UNITS_PER_PLAYER = 6
# kind -> (cost, range, damage, cooldown, splashRadius)
UNITS = {
    "Ninja": (50, 28, 8, 0.5, 0),
    "Samurai": (160, 18, 30, 1.4, 0),
    "Mage": (260, 24, 13, 1.4, 9),
}
UNIT_ORDER = ["Ninja", "Samurai", "Mage"]

# kind -> [nivel 2, nivel 3, nivel 4(evolucao)], cada um = (cost, damage, range, cooldown, splashRadius)
# (copia de Config.UNITS[kind].upgrades)
UPGRADES = {
    "Ninja": [(60, 10, 29, 0.5, 0), (90, 12, 30, 0.5, 0), (150, 15, 31, 0.45, 0)],
    "Samurai": [(120, 42, 19, 1.4, 0), (170, 58, 20, 1.3, 0), (300, 70, 21, 1.2, 0)],
    "Mage": [(180, 18, 24, 1.4, 10), (240, 24, 26, 1.35, 11), (400, 30, 27, 1.3, 12)],
}
# Habilidade do nivel 4 -> multiplicador de DPS efetivo (aproximacao, nao existe no Config):
#   MultiShot ~ x2 em ondas cheias; Crit = 1 + (mult-1)/every; Slow = x1.25 para o TIME todo.
CRIT_EVERY = 3
CRIT_MULT = 3
EVO_MULT = {"Ninja": 2.0, "Samurai": 1 + (CRIT_MULT - 1) / CRIT_EVERY, "Mage": 1.0}
SLOW_TEAM_MULT = 1.25
BOSS_SLOW_FACTOR = 0.8
MAX_LEVEL = 4

# Aproximacoes do cenario (c) (nao existem no Config):
SPLASH_MULT = 1.6  # um tiro de area acerta em media 1.6 inimigos
MAX_SAME_KIND = 2  # jogador competente diversifica: no maximo 2 unidades iguais
PATIENCE = 2  # quantas ondas o jogador aceita economizar para um item melhor
OVERKILL_EFF = 0.65  # parte do dano que nao e desperdicada em inimigos ja quase mortos

# Cada onda = lista de grupos (kind, count, interval). Grupos saem em sequencia.
WAVES = [
    [("Grunt", 5, 1.2)],
    [("Grunt", 8, 1.0)],
    [("Grunt", 6, 1.0), ("Runner", 4, 0.8)],
    [("Grunt", 8, 0.8), ("Tank", 2, 2.0)],
    [("Runner", 10, 0.6), ("Grunt", 6, 0.8)],
    [("Tank", 3, 2.0), ("Grunt", 10, 0.7)],
    [("Runner", 12, 0.5), ("Tank", 3, 1.5)],
    [("Grunt", 15, 0.5), ("Tank", 4, 1.5), ("Runner", 6, 0.5)],
    [("Tank", 6, 1.0), ("Runner", 14, 0.4), ("Grunt", 10, 0.5)],
    [("Grunt", 8, 0.6), ("Tank", 4, 1.2), ("Oni", 1, 1.0)],
]


def spawn_offsets(wave):
    """Lista (kind, tempo_de_spawn_relativo). O intervalo vem depois de cada spawn."""
    out = []
    t = 0.0
    for kind, count, interval in wave:
        for _ in range(count):
            out.append((kind, t))
            t += interval
    return out, t  # t = duracao total do spawn (inclui o ultimo intervalo)


def walk_time(kind, fraction=1.0):
    return PATH_LENGTH * fraction / ENEMIES[kind][0]


def scenario_a():
    now = float(INTERMISSION_SECONDS)
    rows = []
    for i, wave in enumerate(WAVES):
        offs, spawn_dur = spawn_offsets(wave)
        clear = max(o + walk_time(k, KILL_FRACTION) for k, o in offs)
        if i == len(WAVES) - 1:
            length = max(spawn_dur, clear)  # ultima onda: espera limpar tudo
        else:
            length = max(spawn_dur, min(clear, WAVE_TIMEOUT_SECONDS))
            if clear <= WAVE_TIMEOUT_SECONDS:  # onda limpa a tempo -> tem pausa
                length += WAVE_BREAK_SECONDS
        slowest = max(walk_time(k) for k, _ in offs)
        rows.append((i + 1, spawn_dur, slowest, length))
        now += length
    return rows, now


def scenario_b():
    now = float(INTERMISSION_SECONDS)
    leaks = []  # (tempo, dano)
    starts = []  # inicio de cada onda
    for wave in WAVES:
        offs, spawn_dur = spawn_offsets(wave)
        starts.append(now)
        for k, o in offs:
            leaks.append((now + o + walk_time(k), ENEMIES[k][1]))
        clear = max(o + walk_time(k) for k, o in offs)
        now += max(spawn_dur, min(clear, WAVE_TIMEOUT_SECONDS))
    hp = BASE_MAX_HEALTH
    for t, dmg in sorted(leaks):
        hp -= dmg
        if hp <= 0:
            wave = max(i + 1 for i, st in enumerate(starts) if st <= t)
            return t, wave
    return None, None


def stats(unit):
    """(cost_de_compra, range, damage, cooldown, splash) do nivel atual da unidade."""
    kind, level = unit
    cost, rng, dmg, cd, splash = UNITS[kind]
    if level == 1:
        return (cost, rng, dmg, cd, splash)
    ucost, udmg, urng, ucd, usplash = UPGRADES[kind][level - 2]
    return (ucost, urng, udmg, ucd, usplash)


def unit_dps(unit):
    """Dano por segundo efetivo (splash e habilidade da evolucao contam)."""
    kind, level = unit
    _, _, dmg, cd, splash = stats(unit)
    mult = SPLASH_MULT if splash > 0 else 1.0
    if level == MAX_LEVEL:
        mult *= EVO_MULT[kind]
    return dmg / cd * mult


def team_mult(owned):
    """Slow do Mago evoluido ajuda o time inteiro (inimigos ficam mais tempo no alcance)."""
    return SLOW_TEAM_MULT if ("Mage", MAX_LEVEL) in owned else 1.0


def total_power(owned):
    """Poder bruto do time = soma de dps*alcance, vezes o bonus de equipe."""
    return sum(unit_dps(u) * stats(u)[1] for u in owned) * team_mult(owned)


def options(owned):
    """Lista de (valor_por_dinheiro, custo, nova_lista) de tudo que da para fazer."""
    out = []
    base = total_power(owned)
    if len(owned) < MAX_UNITS_PER_PLAYER:
        for kind in UNIT_ORDER:
            if sum(1 for k, _ in owned if k == kind) >= MAX_SAME_KIND:
                continue
            new = owned + [(kind, 1)]
            out.append(((total_power(new) - base) / UNITS[kind][0], UNITS[kind][0], new))
    for i, (kind, level) in enumerate(owned):
        if level < MAX_LEVEL:
            cost = UPGRADES[kind][level - 1][0]
            new = owned[:i] + [(kind, level + 1)] + owned[i + 1:]
            out.append(((total_power(new) - base) / cost, cost, new))
    return out


def has_evo(owned):
    return any(lv == MAX_LEVEL for _, lv in owned)


def buy_greedy(cash, owned, waited):
    """Jogador competente: compra o item com melhor "poder extra por dinheiro". Se o melhor
    ainda nao cabe no bolso, ECONOMIZA por ate PATIENCE ondas (como uma pessoa faria)
    antes de aceitar o melhor item que ja cabe.
    Devolve (cash, owned, waited, comprou_evolucao_agora)."""
    evolved = False
    while True:
        opts = sorted(options(owned), key=lambda o: -o[0])
        if not opts:
            break
        best = opts[0]
        if best[1] <= cash:
            pick = best
        else:
            if waited < PATIENCE:
                waited += 1
                break
            affordable = [o for o in opts if o[1] <= cash]
            if not affordable:
                break
            pick = affordable[0]
        cash -= pick[1]
        if has_evo(pick[2]) and not has_evo(owned):
            evolved = True
        owned = pick[2]
        waited = 0
    return cash, owned, waited, evolved


def wave_capacity(wave, owned):
    """Dano total que as unidades conseguem causar nesta onda (estimativa)."""
    offs, spawn_dur = spawn_offsets(wave)
    total = 0.0
    for u in owned:
        rng = stats(u)[1]
        dps = unit_dps(u)
        # Tempo em que ha inimigo no alcance: cada passagem dura range*2/velocidade
        # (~50% do alcance dentro do caminho), mas a unidade so atira em um por vez.
        windows = sum(rng * 2 / ENEMIES[k][0] for k, _ in offs)
        max_win = max(rng * 2 / ENEMIES[k][0] for k, _ in offs)
        active = min(windows, spawn_dur + max_win)
        total += dps * active * OVERKILL_EFF
    return total * team_mult(owned)


def scenario_c():
    cash = START_CASH
    owned = []
    waited = 0
    cash, owned, waited, _ = buy_greedy(cash, owned, waited)
    first_evo_wave = None
    first_evo_affordable = None
    cheapest_evo = min(UPGRADES[k][2][0] for k in UPGRADES)
    base = float(BASE_MAX_HEALTH)
    rows = []
    for i, wave in enumerate(WAVES):
        offs, spawn_dur = spawn_offsets(wave)
        hp_total = sum(ENEMIES[k][2] for k, _ in offs)
        reward_total = sum(ENEMIES[k][3] for k, _ in offs)
        dmg_total = sum(ENEMIES[k][1] for k, _ in offs)
        cap = wave_capacity(wave, owned)
        frac = min(1.0, cap / hp_total)
        base -= (1 - frac) * dmg_total
        cash += frac * reward_total
        have = cap / (spawn_dur + 1e-9)
        need = hp_total / (spawn_dur + max(stats(owned[0])[1] * 2 / ENEMIES[k][0] for k, _ in offs)) if owned else 0.0
        rows.append((i + 1, round(cash), len(owned), have, need, frac, max(base, 0.0)))
        if base <= 0:
            break
        # "Evolucao ao alcance": ja deu dinheiro para a evolucao mais barata?
        if first_evo_affordable is None and cash >= cheapest_evo:
            first_evo_affordable = i + 1
        cash, owned, waited, evolved = buy_greedy(cash, owned, waited)
        if evolved and first_evo_wave is None:
            first_evo_wave = i + 1
    return rows, base, owned, first_evo_wave, first_evo_affordable


def main():
    rows, total = scenario_a()
    print("Cenario (a): inimigos morrem a %d%% do caminho" % int(KILL_FRACTION * 100))
    print("Onda | spawn(s) | mais lento andando tudo (s) | duracao da onda (s)")
    for n, sd, slow, length in rows:
        print("%4d | %8.1f | %27.1f | %19.1f" % (n, sd, slow, length))
    print("Total estimado (com intervalo inicial de %ds): %.1f s" % (INTERMISSION_SECONDS, total))
    t, wave = scenario_b()
    print()
    if t is None:
        print("Cenario (b): a base sobreviveu sem defesa (ajuste os numeros!)")
    else:
        print("Cenario (b): sem defesa, a base morre aos %.1f s, na onda %d" % (t, wave))

    rows, base, owned, evo_wave, evo_afford = scenario_c()
    print()
    print("Cenario (c): 1 jogador, START_CASH=%d, compra/upgrade por valor (limite %d unidades)"
          % (START_CASH, MAX_UNITS_PER_PLAYER))
    print("Onda | cash antes de comprar | unidades | DPS efetivo | DPS necessario | mortos | base hp")
    for n, c, u, have, need, frac, hp in rows:
        print("%4d | %21d | %8d | %11.1f | %14.1f | %5.0f%% | %7.1f" % (n, c, u, have, need, frac * 100, hp))
    if base > 0:
        print("Cenario (c): base SOBREVIVE com %.0f%% de vida. Unidades: %s"
              % (base, ", ".join("%s Lv%d" % u for u in owned)))
        print("Cenario (c): primeira evolucao COMPRADA na onda %s; dinheiro para a mais barata na onda %s"
              % (evo_wave, evo_afford))
    else:
        print("Cenario (c): base CAI na onda %d. (ajuste os numeros!)" % rows[-1][0])
    print()
    print("Tabela final (nivel: custo / dano / alcance / cooldown / splash):")
    for kind in UNIT_ORDER:
        c, r, d, cd, sp = UNITS[kind]
        print("  %-8s Lv1 %3d / %3d / %2d / %.2f / %2d" % (kind, c, d, r, cd, sp))
        for n, (uc, ud, ur, ucd, usp) in enumerate(UPGRADES[kind], start=2):
            print("  %-8s Lv%d %3d / %3d / %2d / %.2f / %2d" % ("", n, uc, ud, ur, ucd, usp))


if __name__ == "__main__":
    main()
