# Tokyo Burst TD — Week 3 spec: UNITS (towers) + match cash

Read docs/SPEC-SEMANA2.md and SPEC-SEMANA1.md first (context, style, existing contracts —
all still valid). Same rules: --!strict, tabs, English identifiers, comments in simple
Brazilian Portuguese for a beginner, init()/start() modules, no _G, task library,
server-authoritative, never trust the client.

Week 3 goal: players earn cash from kills, buy units from a bottom hotbar, place them on the
yellow Placement slots, and units attack enemies automatically. Every action explodes with
juice (placement = light explosion + pop, every attack = neon projectile/slash + spark,
cash gain = counter pop). Upgrade/sell come in week 4 (do NOT build them now).

## Units (original anime archetypes — not copies of any existing character)
Config.UNITS[kind] = {
  displayName: string, cost: number, range: number (studs, XZ distance),
  damage: number, cooldown: number (s between attacks), splashRadius: number (0 = single),
  color: Color3 (body), accentColor: Color3 (neon parts / projectile), height: number,
  attackStyle: "Shuriken" | "Slash" | "Orb",
}
Kinds (exact keys, also the order of the hotbar = Config.UNIT_ORDER = {"Ninja","Samurai","Mage"}):
  Ninja   cheap, long-ish range, fast single target   attackStyle "Shuriken"
  Samurai mid cost, SHORT range, big single hits      attackStyle "Slash"
  Mage    expensive, splash damage                    attackStyle "Orb"
Tune numbers with tools/sim_match.py (see Balance).
Config.START_CASH (per player per match), Config.MAX_UNITS_PER_PLAYER = 6,
Config.PLACE_ALLOWED_STATES = {"Intermission","Wave"} (store as a set-like table
{ Intermission = true, Wave = true }).

## Economy (server)
- Each player has match cash. Server stores it in a table AND mirrors it to the Player
  attribute "Cash" (number) so the HUD can read it. Only the server writes it.
- Co-op rule: when an enemy is Killed, EVERY player in the server receives its reward.
- Cash resets to START_CASH for everyone when a match (re)starts (when MatchService resets),
  and a player joining mid-match gets START_CASH.

## Placement slots (already in the map)
workspace.Map.Placement has Parts "Slot_01".."Slot_10" (8x0.2x8, CanQuery true).
Server marks a used slot with attribute Occupied = true (false/nil = free) and clears it
when units are cleared. Clients read Occupied to show which slots are free.

## Instance contract: workspace.Units (Folder, created by server UnitService.init())
Each unit = Model named by Id ("U1", "U2"...), PrimaryPart "Root" (anchored, CanCollide
false, CanQuery false, CanTouch false). Model attributes (set BEFORE parenting):
  Id: string, Kind: string, Owner: number (UserId), Slot: string (slot name)
Visuals built by the SERVER from Config.UNITS (low-poly: body block/cylinder in color,
head ball, archetype accessory — Ninja: neon headband + scarf; Samurai: wide hat +
katana part; Mage: cone hat + floating neon orb). Decorations welded to Root,
unanchored, massless, no collision/query/touch. Unit stands on the slot center, facing
the nearest road point (server computes facing at spawn). Units never move.

## Remotes (add to Types.RemoteName and use Net.event)
CLIENT -> SERVER
  PlaceUnit(kind: string, slotName: string)
    Server validation, in order (on fail send Notify to that player and return):
    rate limit 4/s per player; typeof checks; #strings <= 16; Config.UNITS[kind] exists;
    MatchState.State in PLACE_ALLOWED_STATES; slot exists in workspace.Map.Placement and is
    a BasePart and not Occupied; player's unit count < MAX_UNITS_PER_PLAYER;
    cash >= cost. Then: deduct cash, mark slot, create unit, fire UnitPlaced.
SERVER -> ALL CLIENTS
  UnitPlaced(id: string, kind: string, position: Vector3, ownerUserId: number)
  UnitAttacked(id: string, kind: string, from: Vector3, to: Vector3)
     from = unit's "muzzle" point (Root position + up*height*0.7), to = target position.
     Fired once per attack (splash too — one event, client draws the area burst).
SERVER -> ONE CLIENT
  Notify(text: string)   short English message, e.g. "Not enough cash!", "Slot taken",
                         "Unit limit reached", "Wait for the next round".
Existing EnemyDied(... reward) stays; the client shows coin gain from the Cash attribute.

## Server systems (src/server/Systems/)
- EconomyService (new): init: table by player; PlayerAdded/Removing; API
  get(player), add(player, n), trySpend(player, n): boolean, addAll(n), resetAll().
  Subscribes to EnemyService.onEnemyRemoved: on "Killed" -> addAll(reward).
  (If onEnemyRemoved does not pass the reward/reason, extend EnemyService so it does —
  keep existing subscribers working.)
- UnitService (new): owns workspace.Units, slots' Occupied, PlaceUnit handler with the
  validation above, unit visuals, per-player unit counts, clearAll() (destroy units, free
  slots, reset counts; no events), and the COMBAT loop in start():
  10 Hz (Config.SERVER_TICK_RATE). Each tick: get the current enemy list ONCE from
  EnemyService (add EnemyService.snapshot(): returns a REUSED array of
  { id, distance, position } with live count — no per-tick allocations beyond what is
  unavoidable), then for each unit whose cooldown is ready: choose target = enemy in range
  with the GREATEST distance along the path ("first"); deal damage via
  EnemyService.damage(id, damage); for splashRadius > 0 also damage every other enemy within
  splashRadius (XZ) of the target position; set cooldown; fire UnitAttacked.
  Enemy position on the server = PathMath.positionAt(pathData, distance) + up*HeightOffset
  (EnemyService already knows how to compute distance; put the position in the snapshot).
- MatchService: on match reset (restart after Victory/Defeat) call UnitService.clearAll()
  and EconomyService.resetAll(). Avoid require cycles (MatchService may require
  UnitService/EconomyService; they must NOT require MatchService — read
  ReplicatedStorage.MatchState.State attribute directly for the allowed-state check).
- DebugService stays as is.

## Balance (tools/sim_match.py — extend, keep in sync with Config, say so in comments)
Add a scenario (c): one player, starting with START_CASH, earning every kill reward,
greedily buying the best-value unit (damage/cooldown/cost) as soon as affordable, units
placed with ~50% of the path inside their range on average (approximate: each unit gets
(range*2 / enemySpeed) seconds of shooting per enemy pass). Print per wave: cash, units
owned, estimated DPS vs required DPS, and whether the base survives. Tune so:
  - one competent player WINS but is pressured on waves 8-10 (base ends ~30-70% hp),
  - undefended base still dies around wave 5 (unchanged),
  - first unit affordable at match start (START_CASH >= Ninja cost), second around wave 2.
Report the tuned table.

## Client (src/client/Controllers/)
Two executors split the client. Do not edit the other's files.

### Executor CLIENT-UI owns: HudController.luau (extend), PlacementController.luau (new)
- HUD: add a cash counter (top-right or near the health bar): coin-yellow text "$150",
  reads LocalPlayer "Cash" attribute; on increase: number counts up (tween a NumberValue)
  + scale pop; on decrease: quick red flash. Keep everything else from week 2.
- PlacementController: bottom-center hotbar with one card per Config.UNIT_ORDER
  (name, cost, a colored square "portrait" in the unit color with accent stroke). Cards the
  player can't afford are dimmed (update when Cash changes). Big touch targets (mobile).
  Tap a card -> placement mode (card glows, others normal; tap again or "X" button cancels).
  In placement mode: free slots (Occupied ~= true) pulse brighter (client-side local tween
  of Transparency/Color of the slot Part — local only); occupied slots stay dim. A click/tap
  on the 3D world (ignore if gameProcessedEvent) raycasts with Include filter =
  workspace.Map.Placement; if it hits a free slot -> fire PlaceUnit(kind, slot.Name) and
  exit placement mode. Show a range ring preview? -> YES on PC hover only (optional; skip if
  complex). Notify: show a toast (top-center, slides in, fades after 2s, max 3 stacked).
  Also listen to UnitPlaced for local-player placements to exit placement mode if still in it.
  Keyboard shortcuts on PC: 1/2/3 select cards, Q/Escape cancel.
  Must not break DebugController (Studio enemy click) — both may receive the same click;
  that's OK.

### Executor CLIENT-FX owns: FxController.luau (extend), UnitFxController.luau (new)
- UnitPlaced: "light explosion" at position: a Neon sphere that expands (Size tween) and
  fades (Transparency), a vertical light pillar, PointLight flash, confetti burst (reuse
  the existing confetti pool), and the unit model pops in: local Model:ScaleTo animation
  from 0.2 to 1 with Back easing (drive a NumberValue tween and call ScaleTo in its
  Changed handler, or step it in a short RenderStepped loop) — find the model by id in
  workspace.Units (WaitForChild with short timeout).
- UnitAttacked by attackStyle (look up Config.UNITS[kind].attackStyle):
    Shuriken: small spinning neon star/part flies from->to fast (0.12-0.2 s), spark at hit.
    Slash: neon crescent/flat part arc swept near target, white flash, short.
    Orb: glowing ball arcs/flies to target then expanding ring burst (area = splashRadius).
  Pool projectiles (no Instance.new per attack after warmup), cap simultaneous (e.g. 40).
  Also make the attacking unit "lunge"/recoil: brief local tween of its Root CFrame?
  NO — units are anchored server parts; instead tween a local Highlight or scale pulse
  (ScaleTo 1 -> 1.08 -> 1). Keep it cheap.
- UnitFxController: idle life for units: neon accent parts gently pulse, Mage orb bobs,
  using ONE RenderStepped loop over tracked units (ChildAdded/Removed on workspace.Units),
  no per-frame allocations, cleanup on removal.
- Respect mobile performance: pools, caps, cleanup, no per-frame Instance creation.

## Ownership summary (parallel executors)
SERVER: src/shared/**, src/server/**, tools/sim_match.py
CLIENT-UI: src/client/Controllers/HudController.luau, PlacementController.luau
CLIENT-FX: src/client/Controllers/FxController.luau, UnitFxController.luau
Client executors code against this spec even if shared files are not updated yet:
Config.UNITS fields above, Config.UNIT_ORDER, Net.event names above, Types.
