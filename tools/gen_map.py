#!/usr/bin/env python3
"""Gerador do mapa da Semana 1 do Tokyo Burst TD.

O que este script faz (explicacao simples):
  - Le os 8 pontos do caminho dos inimigos (waypoints) que estao aqui embaixo.
  - Cria o chao, a estrada, os predios, o ponto de nascimento do jogador e os
    "slots" (lugares onde as unidades serao colocadas na semana 3).
  - Escreve tudo no arquivo src/workspace/Map.model.json, que o Rojo
    transforma em Workspace.Map dentro do Roblox Studio.
  - Usa um "seed" fixo: toda vez que voce roda, o resultado e IGUAL.
  - Confere (assert) se nada se sobrepoe. Se algo estiver errado, o script
    para com uma mensagem de erro.

Como rodar (na pasta raiz do projeto):
    python3 -I tools/gen_map.py

Nao edite o Map.model.json na mao: mude este script e rode de novo.
"""
import json
import math
import os
import random
import sys

SEED = 20240611
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "src", "workspace", "Map.model.json")

WAYPOINTS = [(-90, -80), (40, -80), (40, -30), (-60, -30),
             (-60, 20), (60, 20), (60, 70), (-80, 70)]
ROAD_W = 12
GROUND = 220
HALF = GROUND / 2
EPS = 1e-6


def r2(v):
    return round(v, 2) + 0.0


def r3(v):
    return round(v, 3) + 0.0


# Retangulo = (cx, cz, sx, sz) no plano XZ
def gaps(a, b):
    dx = max(0.0, abs(a[0] - b[0]) - (a[2] + b[2]) / 2)
    dz = max(0.0, abs(a[1] - b[1]) - (a[3] + b[3]) / 2)
    return dx, dz


def clear(a, b, margin):
    """True se a e b estao separados por pelo menos `margin` (AABB expandido)."""
    dx, dz = gaps(a, b)
    return dx >= margin - EPS or dz >= margin - EPS


def dist(a, b):
    dx, dz = gaps(a, b)
    return math.hypot(dx, dz)


def inside_ground(a, margin=0.0):
    return (abs(a[0]) + a[2] / 2 <= HALF - margin + EPS and
            abs(a[1]) + a[3] / 2 <= HALF - margin + EPS)


# ---------------------------------------------------------------- instancias
def part(name, cls, size, pos, color, material, anchored=True, props=None, attrs=None):
    p = {
        "Size": [r2(s) for s in size],
        "CFrame": {"position": [r2(v) for v in pos],
                   "orientation": [[1, 0, 0], [0, 1, 0], [0, 0, 1]]},
        "Color": [r3(c) for c in color],
        "Material": material,
        "Anchored": anchored,
    }
    if props:
        p.update(props)
    node = {"Name": name, "ClassName": cls, "Properties": p, "Children": []}
    if attrs:
        node["Attributes"] = attrs
    return node


def folder(name, children):
    return {"Name": name, "ClassName": "Folder", "Children": children}


def main():
    rng = random.Random(SEED)

    # ---- estrada (retangulos no plano XZ)
    road_rects = []
    road_parts = []
    ROAD_COLOR = (0.18, 0.18, 0.22)
    for i in range(len(WAYPOINTS) - 1):
        (x1, z1), (x2, z2) = WAYPOINTS[i], WAYPOINTS[i + 1]
        assert x1 == x2 or z1 == z2, "segmento nao e alinhado aos eixos"
        cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
        sx = abs(x2 - x1) if x1 != x2 else ROAD_W
        sz = abs(z2 - z1) if z1 != z2 else ROAD_W
        road_rects.append((cx, cz, sx, sz))
        road_parts.append(part("Segment_%d_%d" % (i + 1, i + 2), "Part",
                               (sx, 0.2, sz), (cx, 0, cz), ROAD_COLOR, "Asphalt"))
    for i, (x, z) in enumerate(WAYPOINTS):
        road_rects.append((x, z, ROAD_W, ROAD_W))
        road_parts.append(part("Joint_%d" % (i + 1), "Part", (ROAD_W, 0.2, ROAD_W),
                               (x, 0, z), ROAD_COLOR, "Asphalt"))

    # ---- waypoints
    wp_parts = []
    for i, (x, z) in enumerate(WAYPOINTS):
        wp_parts.append(part(str(i + 1), "Part", (1, 1, 1), (x, 1, z), (1, 1, 1),
                             "Plastic",
                             props={"Transparency": 1, "CanCollide": False,
                                    "CanQuery": False, "CanTouch": False},
                             attrs={"Index": i + 1}))

    # ---- spawn inimigo e base
    ex, ez = WAYPOINTS[0]
    bx, bz = WAYPOINTS[-1]
    enemy_rect = (ex, ez, 10, 10)
    base_rect = (bx, bz, 14, 14)
    enemy_part = part("EnemySpawn", "Part", (10, 0.4, 10), (ex, 0.3, ez),
                      (1, 0.2, 0.35), "Neon", props={"CanCollide": False})
    base_part = part("PlayerBase", "Part", (14, 8, 14), (bx, 4, bz),
                     (0.2, 0.75, 1), "Neon", attrs={"MaxHealth": 100})

    # ---- PlayerSpawn: perto do centro, fora da estrada
    spawn_rect = None
    for _ in range(500):
        c = (r2(rng.uniform(-25, 25)), r2(rng.uniform(-8, 8)), 12, 12)
        if all(clear(c, rr, 6) for rr in road_rects) and inside_ground(c, 4):
            spawn_rect = c
            break
    assert spawn_rect, "nao achei lugar seguro para o PlayerSpawn"
    spawn_part = part("PlayerSpawn", "SpawnLocation", (12, 1, 12),
                      (spawn_rect[0], 0.5, spawn_rect[1]), (0.35, 0.35, 0.4),
                      "SmoothPlastic", props={"Neutral": True, "Duration": 0})

    # ---- slots: espalhados ao longo do caminho, 2-4 studs da borda da estrada
    seg_len = [abs(WAYPOINTS[i + 1][0] - WAYPOINTS[i][0]) +
               abs(WAYPOINTS[i + 1][1] - WAYPOINTS[i][1])
               for i in range(len(WAYPOINTS) - 1)]
    total = sum(seg_len)
    N_SLOTS = 10
    SLOT = 8
    slot_rects = []
    others = [enemy_rect, base_rect, spawn_rect]
    for k in range(N_SLOTS):
        target = (k + 0.5) / N_SLOTS * total
        placed = None
        for _ in range(2000):
            s = target + rng.uniform(-10, 10)
            s = min(max(s, 0.0), total - 1e-6)
            idx, acc = 0, 0.0
            while acc + seg_len[idx] < s:
                acc += seg_len[idx]
                idx += 1
            t = s - acc
            (x1, z1), (x2, z2) = WAYPOINTS[idx], WAYPOINTS[idx + 1]
            side = rng.choice((-1, 1))
            gap = rng.uniform(2.3, 3.7)
            off = ROAD_W / 2 + gap + SLOT / 2
            if x1 == x2:
                z = z1 + t * (1 if z2 > z1 else -1)
                c = (r2(x1 + side * off), r2(z), SLOT, SLOT)
            else:
                x = x1 + t * (1 if x2 > x1 else -1)
                c = (r2(x), r2(z1 + side * off), SLOT, SLOT)
            if not inside_ground(c, 3):
                continue
            d = min(dist(c, rr) for rr in road_rects)
            if not (2.0 - EPS <= d <= 4.0 + EPS):
                continue
            if not all(clear(c, o, 3) for o in others + slot_rects):
                continue
            placed = c
            break
        assert placed, "nao consegui posicionar Slot_%02d" % (k + 1)
        slot_rects.append(placed)

    # ---- predios
    n_build = rng.randint(14, 20)
    build_rects, build_parts = [], []
    attempts = 0
    while len(build_rects) < n_build and attempts < 20000:
        attempts += 1
        w, d = rng.randint(10, 18), rng.randint(10, 18)
        c = (r2(rng.uniform(-HALF + 6, HALF - 6)), r2(rng.uniform(-HALF + 6, HALF - 6)), w, d)
        if not inside_ground(c, 3):
            continue
        if not all(clear(c, rr, 6) for rr in road_rects):
            continue
        if not all(clear(c, o, 6) for o in (enemy_rect, base_rect, spawn_rect)):
            continue
        if not all(clear(c, o, 3) for o in slot_rects + build_rects):
            continue
        build_rects.append(c)
        h = rng.randint(12, 60)
        g = rng.uniform(0.42, 0.72)
        col = (g, g + rng.uniform(0.0, 0.03), g + rng.uniform(0.02, 0.09))
        build_parts.append(part("Building_%02d" % len(build_rects), "Part", (w, h, d),
                                (c[0], h / 2, c[1]), col, "SmoothPlastic"))
    assert len(build_rects) >= 14, "poucos predios cabem: %d" % len(build_rects)

    # ---- slots como instancias
    slot_parts = [part("Slot_%02d" % (i + 1), "Part", (SLOT, 0.2, SLOT), (c[0], 0.1, c[1]),
                       (1, 0.85, 0.2), "Neon",
                       props={"Transparency": 0.6, "CanCollide": False})
                  for i, c in enumerate(slot_rects)]

    ground = part("Ground", "Part", (GROUND, 1, GROUND), (0, -0.5, 0),
                  (0.62, 0.62, 0.66), "Concrete")

    # ---- ASSERTS finais (usam os valores ja arredondados)
    for b in build_rects:
        assert inside_ground(b), "predio fora do chao"
        for rr in road_rects:
            assert clear(b, rr, 6), "predio perto demais da estrada"
        for o in (enemy_rect, base_rect, spawn_rect):
            assert clear(b, o, 6), "predio perto de spawn/base"
    for i, a in enumerate(build_rects):
        for b in build_rects[i + 1:]:
            assert clear(a, b, 3), "predios sobrepostos"
    assert inside_ground(spawn_rect)
    for rr in road_rects:
        assert clear(spawn_rect, rr, 6), "PlayerSpawn na estrada"
    for i, s in enumerate(slot_rects):
        assert inside_ground(s)
        d = min(dist(s, rr) for rr in road_rects)
        assert 2.0 - EPS <= d <= 4.0 + EPS, "slot fora de 2-4 studs: %.2f" % d
        for rr in road_rects:
            assert clear(s, rr, 2), "slot na estrada"
        for b in build_rects + [spawn_rect, base_rect, enemy_rect]:
            assert clear(s, b, 2), "slot sobrepondo algo"
        for o in slot_rects[i + 1:]:
            assert clear(s, o, 2), "slots sobrepostos"
    assert clear(spawn_rect, base_rect, 4) and clear(spawn_rect, enemy_rect, 4)
    print("Asserts OK (predios, spawn, slots).")

    model = {"ClassName": "Model", "Children": [
        ground,
        folder("Road", road_parts),
        folder("Waypoints", wp_parts),
        enemy_part,
        base_part,
        folder("Buildings", build_parts),
        spawn_part,
        folder("Placement", slot_parts),
    ]}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(model, f, indent=2)
        f.write("\n")
    print("Escrito:", OUT)

    # ---- resumo
    print("Resumo: Road=%d (segmentos=%d, juntas=%d) Waypoints=%d Buildings=%d "
          "Placement=%d + Ground, EnemySpawn, PlayerBase, PlayerSpawn" %
          (len(road_parts), len(WAYPOINTS) - 1, len(WAYPOINTS), len(wp_parts),
           len(build_parts), len(slot_parts)))

    # ---- grade ASCII 44x44 (5 studs por celula; linhas = Z, colunas = X)
    N = 44
    cell = GROUND / N
    layers = [("R", road_rects), ("B", build_rects), ("S", slot_rects),
              ("P", [spawn_rect]), ("E", [enemy_rect]), ("H", [base_rect])]
    print("Grade (R estrada, B predio, S slot, P spawn jogador, E spawn inimigo, H base):")
    for row in range(N):
        z = -HALF + (row + 0.5) * cell
        line = ""
        for col in range(N):
            x = -HALF + (col + 0.5) * cell
            ch = "."
            for sym, rects in layers:
                if any(abs(x - q[0]) <= q[2] / 2 and abs(z - q[1]) <= q[3] / 2 for q in rects):
                    ch = sym
            line += ch
        print(line)


if __name__ == "__main__":
    sys.exit(main())
