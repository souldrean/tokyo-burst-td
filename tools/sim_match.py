#!/usr/bin/env python3
"""sim_match.py - estima a duracao de uma partida do Tokyo Burst TD.

ATENCAO: os numeros de ENEMIES, WAVES e as constantes abaixo sao uma COPIA de
src/shared/Config.luau. Se mudar um, mude o outro (mantenha os dois em sincronia).

Rode com:  python3 -I tools/sim_match.py

Cenarios:
  (a) todo inimigo morre quando chega a 40% do caminho (torres boas);
  (b) ninguem morre (quanto tempo ate a base sem defesa cair?).
"""

PATH_LENGTH = 640.0  # studs (caminho do mapa, aprox.)
INTERMISSION_SECONDS = 6
BASE_MAX_HEALTH = 100
WAVE_TIMEOUT_SECONDS = 15
KILL_FRACTION = 0.4

# kind -> (speed, baseDamage)  (health/reward nao importam para o tempo)
ENEMIES = {
    "Grunt": (20, 5),
    "Runner": (32, 4),
    "Tank": (14, 12),
    "Oni": (12, 40),
}

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


main()
