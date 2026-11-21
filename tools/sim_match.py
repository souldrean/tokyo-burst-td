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
"""

PATH_LENGTH = 640.0  # studs (caminho do mapa, aprox.)
INTERMISSION_SECONDS = 6
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

# Aproximacoes do cenario (c) (nao existem no Config):
SPLASH_MULT = 1.6  # um tiro de area acerta em media 1.6 inimigos
BUILD_ORDER = ["Ninja", "Ninja", "Samurai", "Mage", "Samurai", "Mage"]  # ordem de compra do jogador
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


def unit_value(kind):
    """Valor = dano por segundo * alcance (mais alcance = mais tempo atirando) / custo."""
    cost, rng, dmg, cd, splash = UNITS[kind]
    mult = SPLASH_MULT if splash > 0 else 1.0
    return dmg / cd * mult * rng / cost


def unit_power(kind):
    """Poder bruto = dano por segundo * alcance (dps com splash conta mais)."""
    _, rng, dmg, cd, splash = UNITS[kind]
    return dmg / cd * (SPLASH_MULT if splash > 0 else 1.0) * rng


def buy_greedy(cash, owned):
    """Jogador competente: segue uma ordem de compra fixa e compra o proximo item
    assim que o dinheiro der (nao ha venda na semana 3, entao nao desperdica slot)."""
    while len(owned) < MAX_UNITS_PER_PLAYER:
        nxt = BUILD_ORDER[len(owned)]
        if UNITS[nxt][0] > cash:
            break
        cash -= UNITS[nxt][0]
        owned.append(nxt)
    return cash


def wave_capacity(wave, owned):
    """Dano total que as unidades conseguem causar nesta onda (estimativa)."""
    offs, spawn_dur = spawn_offsets(wave)
    total = 0.0
    for u in owned:
        _, rng, dmg, cd, splash = UNITS[u]
        dps = dmg / cd * (SPLASH_MULT if splash > 0 else 1.0)
        # Tempo em que ha inimigo no alcance: cada passagem dura range*2/velocidade
        # (~50% do alcance dentro do caminho), mas a unidade so atira em um por vez.
        windows = sum(rng * 2 / ENEMIES[k][0] for k, _ in offs)
        max_win = max(rng * 2 / ENEMIES[k][0] for k, _ in offs)
        active = min(windows, spawn_dur + max_win)
        total += dps * active * OVERKILL_EFF
    return total


def scenario_c():
    cash = START_CASH
    owned = []
    cash = buy_greedy(cash, owned)
    first_buy = UNITS[owned[0]][0] if owned else None
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
        # DPS "necessario" = vida total / duracao da onda (spawn + passagem).
        need = hp_total / (spawn_dur + max(UNITS[owned[0]][1] * 2 / ENEMIES[k][0] for k, _ in offs) if owned else spawn_dur)
        have = cap / (spawn_dur + 1e-9)
        rows.append((i + 1, round(cash), len(owned), have, need, frac, max(base, 0.0)))
        if base <= 0:
            break
        cash = buy_greedy(cash, owned)
    return rows, base, owned


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

    rows, base, owned = scenario_c()
    print()
    print("Cenario (c): 1 jogador, START_CASH=%d, segue a ordem de compra (limite %d unidades)"
          % (START_CASH, MAX_UNITS_PER_PLAYER))
    print("Onda | cash antes de comprar | unidades | DPS efetivo | DPS necessario | mortos | base hp")
    for n, c, u, have, need, frac, hp in rows:
        print("%4d | %21d | %8d | %11.1f | %14.1f | %5.0f%% | %7.1f" % (n, c, u, have, need, frac * 100, hp))
    if base > 0:
        print("Cenario (c): base SOBREVIVE com %.0f%% de vida. Unidades: %s" % (base, ", ".join(owned)))
    else:
        print("Cenario (c): base CAI na onda %d. (ajuste os numeros!)" % rows[-1][0])


main()
