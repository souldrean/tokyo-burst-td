# Tokyo Burst TD — Week 4 spec: UPGRADE (4 levels + evolution) and SELL

Read docs/SPEC-SEMANA3.md, SPEC-SEMANA2.md and SPEC-SEMANA1.md first (context, style, existing
contracts — all still valid unless changed here). Same rules: --!strict, tabs, English
identifiers, comments in simple Brazilian Portuguese for a beginner, init() (no yield) /
start() modules, no _G, task library, server-authoritative, never trust the client.
Run `selene src` before finishing: 0 warnings (unused params -> prefix with `_`).

Week 4 goal: the player taps one of THEIR units to open a panel, upgrades it up to level 4,
and sells it. Levels 2 and 3 boost stats and add a stronger glow. Level 4 is an EVOLUTION:
the unit gets a new name, new colors, and a unique ABILITY (different for each unit,
original — not copied from any game). Every upgrade/sell explodes with juice.

Design decisions (from João):
- 4 levels. Level 1 = just placed. Upgrades go 1->2, 2->3, 3->4 (4 = evolution).
- Every level has a visibly different glow. Evolution changes the ability.
- Sell refund: 100% of everything spent on the unit during "Intermission",
  60% during "Wave". Selling not allowed in other states.
- NEW pause between waves: when a wave is fully CLEARED (aliveCount == 0, base alive, not
  the last wave), MatchService enters "Intermission" for Config.WAVE_BREAK_SECONDS = 5
  (MatchState EndsAt set, so the HUD countdown works as it does today) before the next
  wave. If a wave ends by WAVE_TIMEOUT with enemies alive, there is NO break.
- Approved evolutions: see the table below (João said "Aprovo assim").

## Data (src/shared/Types.luau + src/shared/Config.luau)

Types (add, keep existing):
```luau
export type AbilityKind = "MultiShot" | "Crit" | "Slow"
export type UnitAbility = {
	kind: AbilityKind,
	description: string,     -- short English text for the panel, e.g. "Throws 3 shurikens at once"
	targets: number?,        -- MultiShot: how many different enemies per attack
	every: number?,          -- Crit: every Nth attack is a crit
	multiplier: number?,     -- Crit: damage multiplier
	factor: number?,         -- Slow: speed multiplier while slowed (0.6 = 40% slower)
	duration: number?,       -- Slow: seconds
}
export type UnitEvolution = {
	displayName: string,     -- new name at level 4
	accentColor: Color3,     -- new neon color at level 4
	ability: UnitAbility,
}
export type UnitLevel = {    -- stats of ONE level (absolute values, not deltas)
	cost: number,            -- price to upgrade INTO this level
	damage: number,
	range: number,
	cooldown: number,
	splashRadius: number,
	evolution: UnitEvolution?, -- only on the level-4 entry
}
```
`UnitDef` gains `upgrades: { UnitLevel }` — exactly 3 entries: upgrades[1] = level 2,
upgrades[2] = level 3, upgrades[3] = level 4 (has `evolution`). Level 1 stats stay in the
existing UnitDef fields (cost/damage/range/cooldown/splashRadius).

Evolutions and abilities (names are original):
| Unit | Evolution name | Ability | Rule |
|---|---|---|---|
| Ninja | "Shadow Ninja" | MultiShot | each attack hits up to `targets` = 3 DIFFERENT enemies in range (the 3 most advanced), full damage each |
| Samurai | "Storm Samurai" | Crit | every `every` = 3rd attack deals damage × `multiplier` = 3 |
| Mage | "Frost Archmage" | Slow | every enemy hit (target + splash) is slowed to `factor` = 0.6 of its speed for `duration` = 2 s. Boss kinds (Config.BOSS_KINDS) use factor 0.8 instead. Slows do NOT stack: a new slow only refreshes the timer |

Starting numbers (the SERVER executor tunes them with sim_match.py — see Balance):
| Unit | Lv2 cost/dmg/rng/cd/splash | Lv3 | Lv4 (evolution) |
|---|---|---|---|
| Ninja (Lv1: 50, 8, 28, 0.5, 0) | 60, 11, 30, 0.5, 0 | 90, 15, 31, 0.45, 0 | 160, 18, 33, 0.4, 0 |
| Samurai (Lv1: 160, 30, 18, 1.4, 0) | 120, 42, 19, 1.4, 0 | 170, 58, 20, 1.3, 0 | 300, 70, 21, 1.2, 0 |
| Mage (Lv1: 260, 13, 24, 1.4, 9) | 180, 18, 24, 1.4, 10 | 240, 24, 26, 1.35, 11 | 400, 30, 27, 1.3, 12 |
Evolution accent colors: Shadow Ninja RGB(170, 80, 255) (violet), Storm Samurai
RGB(120, 200, 255) (electric blue), Frost Archmage RGB(170, 240, 255) (ice).

Config additions:
```luau
MAX_UNIT_LEVEL = 4,
SELL_REFUND = { Intermission = 1, Wave = 0.6 } :: { [string]: number }, -- state -> rate; missing state = cannot sell
UPGRADE_ALLOWED_STATES = { Intermission = true, Wave = true } :: { [string]: boolean },
BOSS_KINDS = { Oni = true } :: { [string]: boolean },
BOSS_SLOW_FACTOR = 0.8,
WAVE_BREAK_SECONDS = 5, -- pausa depois de limpar uma onda (sim_match.py tem copia)
DEBUG_GIVE_CASH = 500, -- Studio only (DebugService)
```

## Shared helper: src/shared/Util/UnitMath.luau (new, pure functions, both sides use it)
```luau
export type UnitStats = {
	level: number, displayName: string, accentColor: Color3,
	damage: number, range: number, cooldown: number, splashRadius: number,
	ability: Types.UnitAbility?,   -- nil before level 4
}
UnitMath.statsAt(def: Types.UnitDef, level: number): UnitStats      -- level clamped to 1..4
UnitMath.upgradeCost(def: Types.UnitDef, level: number): number?   -- cost to go level -> level+1; nil at max
UnitMath.refundFor(spent: number, stateName: string?): number?      -- math.floor(spent * rate); nil if selling not allowed in that state
```
The client uses UnitMath only to DISPLAY numbers. The server uses it as the authority.

## Instance contract changes (workspace.Units, built by the server)
- New unit model attributes (set BEFORE parenting, updated on upgrade):
  `Level: number` (1..4), `Spent: number` (total cash spent on this unit: placement + upgrades).
  Existing Id/Kind/Owner/Slot unchanged.
- New child Part "Hitbox": Transparency 1, Anchored false, Massless, CanCollide false,
  CanTouch false, **CanQuery true**, size (3.2, def.height + 0.6, 3.2), centered over the
  pedestal, welded to Root. This is what the client raycasts to select a unit
  (all other unit parts keep CanQuery false).
- The server does NOT change unit visuals on upgrade. All level glow is client-side,
  driven by the `Level` attribute (so late joiners see the right level too).

## Remotes (add to Types.RemoteName and to the payload comment block)
CLIENT -> SERVER
  UpgradeUnit(id: string)
  SellUnit(id: string)
  DebugGiveCash()          -- Studio only, like DebugHitEnemy
Server validation for Upgrade/Sell, in order (on fail: Notify that player and return,
except where "silent"):
  1. rate limit 4/s per player PER REMOTE (refactor UnitService.allow(player, key)) — silent
  2. typeof(id) == "string", #id <= 16 — silent
  3. unit exists in the server `units` table — silent
  4. unit.owner == player — Notify "Not your unit"
  5. Upgrade: MatchState.State in UPGRADE_ALLOWED_STATES else "Wait for the next round".
     Sell: UnitMath.refundFor(...) ~= nil else "Can't sell right now".
  6. Upgrade only: level < MAX_UNIT_LEVEL else "Max level!"
  7. Upgrade only: EconomyService.trySpend(player, cost) else "Not enough cash!"
  Then:
  - Upgrade: level += 1, apply UnitMath.statsAt to the server Unit (damage/range/cooldown/
    splash/ability), unit.spent += cost, set attributes Level and Spent, fire UnitUpgraded.
    Keep unit.nextAttack as is (no free instant attack).
  - Sell: refund = refundFor(unit.spent, state); removeUnit(unit) (frees slot + count);
    EconomyService.add(player, refund); fire UnitSold.
SERVER -> ALL CLIENTS
  UnitUpgraded(id: string, level: number, position: Vector3)          -- position = unit feet
  UnitSold(id: string, position: Vector3, refund: number, ownerUserId: number)
  UnitAttacked(id: string, kind: string, from: Vector3, to: Vector3, special: string?)
    -- CHANGED: 5th arg appended (old handlers ignore it). special = "Crit" on a crit hit,
    -- "Slow" when a Frost Archmage attack applies slow, nil otherwise.
    -- MultiShot fires ONE UnitAttacked PER target (up to 3 events in the same tick).

## Server (owner: SERVER executor) — src/shared/**, src/server/**, tools/sim_match.py
- Types, Config, Util/UnitMath as above.
- UnitService:
  - Unit record gains: level, spent, stats (UnitStats from UnitMath), attackCount (for Crit).
  - Combat uses unit.stats (not def) for damage/range/cooldown/splash.
  - MultiShot: pick the N enemies in range with the greatest distance (reuse a small array —
    no allocation per tick), damage each, one UnitAttacked per target.
  - Crit: attackCount += 1; if attackCount % every == 0 -> damage × multiplier, special "Crit".
  - Slow: after damaging target and splash victims, call EnemyService.slow(id, factor, duration)
    for each (BOSS_SLOW_FACTOR for Config.BOSS_KINDS); special "Slow".
    EnemyService.snapshot entries may need `kind` — add `kind: string` to SnapshotEntry.
  - Upgrade/Sell handlers with the validation above. Placement sets Level=1, Spent=def.cost,
    builds the Hitbox part.
- EnemyService: add `EnemyService.slow(id: string, factor: number, duration: number)`.
  Use the existing setSpeed so distance stays continuous. Base speed = the enemy def speed;
  slowed speed = base * factor; one slow per enemy (refresh the end time, never stack);
  restore base speed when it ends (skip if the enemy is gone). Do NOT create one
  task.delay per hit: store `slowUntil` per enemy and restore in the existing server loop.
  Clean up on removal.
- DebugService: Studio-only `DebugGiveCash` remote: rate limit 2/s, gives
  Config.DEBUG_GIVE_CASH via EconomyService.add. Not created outside Studio. No client UI
  sends it: the orchestrator fires it from the MCP (execute_luau on the Client) for tests.
- MatchService: the between-wave break described in "Design decisions" (setState
  "Intermission" with EndsAt = now + WAVE_BREAK_SECONDS, wait, then the next wave).
  Keep everything else (timeout, last wave waits for all, Victory/Defeat) unchanged.
- Balance (tools/sim_match.py, keep in sync with Config and say so in comments): extend
  scenario (c) so the greedy player also considers upgrades (pick the best
  "extra DPS per cash" among: buy a new unit, or upgrade an owned one; evolutions count
  their ability: MultiShot ≈ ×2 effective DPS on crowded waves, Crit ≈ ×(1 + (mult-1)/every),
  Slow ≈ ×1.25 for the whole team while a Mage evo exists). Targets (same as week 3,
  plus): one competent player WINS with the base ending ~30-70% hp; undefended base still
  dies ~wave 5; at least one evolution is affordable by ~wave 7 for a solo player.
  Model the WAVE_BREAK_SECONDS break (only after cleared waves) in the timeline.
  Print the tuned table and copy the final numbers into Config.

## Client UI (owner: CLIENT-UI executor)
Files: src/client/Controllers/PlacementController.luau (small change),
src/client/Controllers/UnitPanelController.luau (NEW). Do not edit other files.
- Dependency direction (avoid a require cycle): UnitPanelController requires
  PlacementController, never the opposite.
- PlacementController: export `PlacementController.isPlacing(): boolean` (true while a card
  is selected) and `PlacementController.onPlacingChanged(callback: (boolean) -> ()): () -> ()`
  (returns a disconnect function). Today `selected` is a local INSIDE start(): keep a
  MODULE-LEVEL `placing: boolean` + callback list, updated wherever selection changes, so
  isPlacing/onPlacingChanged work no matter which controller starts first. Nothing else changes.
- UnitPanelController:
  - Tap/click on the 3D world (ignore gameProcessed, ignore while isPlacing(), same
    tap-vs-drag rule as PlacementController: TAP_MAX_MOVE 14 px, TAP_MAX_TIME 0.35 s)
    raycasts with Include = { workspace.Units } (only Hitbox parts are queryable). Hit ->
    select the unit (model = hitbox.Parent). Miss -> close panel.
  - Selected unit: a local range ring (Neon flat cylinder, Transparency ~0.75, accent color,
    diameter = stats.range*2, CanQuery/CanTouch/CanCollide false, Anchored, in a local folder
    that is NOT inside workspace.Units). Update when Level changes. Remove on close.
  - Panel (bottom-center, ABOVE the hotbar, Scale sizes + UIAspectRatioConstraint, big
    touch targets, opens with a 0.25 s Back pop, closes with a quick fade):
    title "Ninja  Lv 2" (evolution name at Lv 4), 4 pips showing the level (filled = reached),
    stat lines "DMG 11 → 15", "RANGE 30 → 31", "SPEED 0.5s → 0.45s" (arrow part only when an
    upgrade exists), and at level 3 a highlighted EVOLUTION box: evolution name + ability
    description. At level 4 show the ability description permanently.
  - Buttons (only if Owner == LocalPlayer.UserId; otherwise show "Owner: <DisplayName>"):
    UPGRADE "$cost" — "EVOLVE $cost" with a pulsing glow at level 3, "MAX" + disabled at
    level 4, dimmed when Cash < cost (update on Cash change).
    SELL — refund from UnitMath.refundFor(Spent, MatchState.State): "Sell $X (100%)" in
    Intermission, "Sell $X" in Wave, disabled "Can't sell" when nil. Update on State and
    Spent change. Close "X" button. Press = scale pop (0.92 -> 1).
  - Fire UpgradeUnit(id)/SellUnit(id) — only REQUEST; never change cash/level locally.
    Re-render from attributes when Level/Spent change (AttributeChanged on the model).
  - Close when: model removed, X, tap empty world, placement starts, Escape/Q on PC.
    PC shortcuts while open: E = upgrade, Backspace = sell.
  - Server Notify toasts are already shown by PlacementController; do not listen to Notify.

## Client FX (owner: CLIENT-FX executor)
Files: src/client/Controllers/FxController.luau, src/client/Controllers/UnitFxController.luau.
Do not edit other files.
- UnitFxController — level glow driven by the model's `Level` attribute (initial value +
  GetAttributeChangedSignal("Level")), for every unit in workspace.Units:
  - Lv1: as today.
  - Lv2: neon accent parts brighter (lighter color) + a thin neon "rank ring" disk on the
    pedestal (local Part, positioned once — units never move).
  - Lv3: Lv2 + a PointLight (accent, Range ~8, Brightness ~1.5) + a small ParticleEmitter of
    rising sparks (Rate <= 6, LightEmission 1, Lifetime <= 1 s).
  - Lv4 (evolved): accent parts recolored to the evolution accentColor (local only), rank
    ring becomes a slowly spinning aura ring (driven by the EXISTING single RenderStepped
    loop — no new loop), PointLight and sparks in the evo color, and the model scaled to
    1.12 with ScaleTo (pop from 1 to 1.12).
  - SCALE RULE: keep a per-unit `baseScale` (1 for Lv1-3, 1.12 for Lv4). Every existing
    scale effect (placement pop-in, attack pulse 1 -> 1.08 -> 1) must become RELATIVE:
    baseScale * factor. Nothing may ScaleTo(1) an evolved unit.
  - Do NOT use Highlight instances (Roblox renders max 31 at once; 4 players × 6 units).
  - BillboardGui over each unit with level stars (MaxDistance 120, small). Cleanup
    everything on unregister.
- FxController:
  - UnitUpgraded(id, level, position): Lv2/Lv3 = upward neon ring burst + spark burst in the
    accent color + sound ping + floating text "LV 2!". Level 4 = EVOLUTION: bigger moment —
    0.25 s anticipation glow, white flash pillar, double ring, confetti burst, small short
    camera shake, floating text "EVOLVED!" in the evo color.
  - UnitSold(id, position, refund, ownerUserId): implode effect (ring shrinking to the
    center), coin-yellow spark burst, floating "+$refund" only for the owner.
  - UnitAttacked 5th arg `special`: "Crit" -> bigger hit spark + floating "CRIT!" text
    (pooled labels), "Slow" -> pale-blue ring at `to` (diameter = Lv4 splashRadius*2).
    MultiShot needs nothing special (3 events).
  - Projectiles/explosions use the evolution accent when the unit's Level is 4 (look the
    model up by id in workspace.Units; fall back to Config accent).
  - Pools and caps as in week 3; no per-attack Instance.new after warmup.

## Ownership summary (parallel executors)
SERVER: src/shared/**, src/server/**, tools/sim_match.py
CLIENT-UI: src/client/Controllers/PlacementController.luau, UnitPanelController.luau (new)
CLIENT-FX: src/client/Controllers/FxController.luau, UnitFxController.luau
Client executors code against this spec even if shared files are not updated yet
(UnitMath API, Types, Config keys, remote names above). Nobody touches HudController,
EnemyRenderer, DebugController, init files, the map, or build/.
