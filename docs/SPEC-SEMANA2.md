# Tokyo Burst TD — Week 2 spec (source of truth for all executors)

Read docs/SPEC-SEMANA1.md for project context and code style. Same rules: every Luau
file starts with --!strict, tabs, English identifiers, comments in simple Brazilian
Portuguese (owner is a beginner), two-phase init()/start() modules, no _G.

Week 2 goal: a full match loop WITHOUT towers yet:
intermission -> 10 waves of enemies walking the path -> enemies that reach the end
damage the base -> Victory (all waves cleared) or Defeat (base HP 0) -> restart.
Plus the first "juice": confetti on kill, floating reward numbers, wave banners,
screen shake when the base is hit, victory confetti. In Studio only, the developer
can click enemies to damage them (gated debug remote) so kills/juice are testable.

## Core movement model (IMPORTANT — do not deviate)
The server NEVER moves enemies every frame. Each enemy stores:
  BaseDistance (studs along path), BaseTime (workspace:GetServerTimeNow()), Speed (studs/s)
distance(now) = BaseDistance + Speed * (now - BaseTime)
- Server evaluates this at 10 Hz for game logic (reached end? later: tower range).
- Every client evaluates it every frame (RenderStepped) and moves its LOCAL copy of the
  enemy model with PivotTo. The server sets the pivot only once at spawn.
- If speed ever changes (slows, later weeks): server "rebases": BaseDistance = current
  distance, BaseTime = now, then sets the new Speed. Provide EnemyService.setSpeed for this.

## Instance contracts

### ReplicatedStorage.PathPoints (Folder) — created by server PathService.init()
Vector3Value children named "1".."N" (Value = waypoint position with Y = 0, i.e. ground level).
Clients build their path from this (never from workspace, which may stream out).

### ReplicatedStorage.MatchState (Folder) — created by server MatchService.init()
Attributes (replicate automatically, no remotes needed):
  State: string       "Waiting" | "Intermission" | "Wave" | "Victory" | "Defeat"
  Wave: number        current wave (0 before first)
  WaveCount: number   total waves (10)
  BaseHealth: number
  BaseMaxHealth: number
  StateEndsAt: number server time (GetServerTimeNow) when the current timed state ends,
                      0 if not timed (client shows countdown = StateEndsAt - now)
  EnemiesAlive: number

### workspace.Enemies (Folder) — created by server EnemyService.init()
Each enemy is a Model named by its Id (e.g. "E17"), PrimaryPart = "Root".
Model attributes:
  Id: string, Kind: string, Health: number, MaxHealth: number,
  Speed: number, BaseDistance: number, BaseTime: number,
  HeightOffset: number   (Y of the Root center above ground; client adds it)
Root: Part, Anchored, CanCollide false, CanTouch false, CanQuery true (clickable).
Decorations (eyes, horns...) are Parts welded to Root (WeldConstraint), Anchored false,
Massless true, CanCollide false, CanTouch false, CanQuery false.
Visuals are built by the SERVER at spawn from Config.ENEMIES[kind] (low-poly "demons":
block body in the kind color + 2 small Neon eyes + optional horns for Tank/Boss).

### Remotes — shared/Net.luau
Net.event(name: RemoteName): RemoteEvent
  - On the server: returns ReplicatedStorage.Remotes[name], CREATING the folder/event
    lazily if missing (so init order between systems never matters).
  - On the client: WaitForChild on ReplicatedStorage.Remotes then the event (timeout 30s,
    error with clear message).
RemoteName = "EnemyDied" | "BaseHit" | "WaveStarted" | "MatchEnded" | "DebugHitEnemy"
Payloads (server -> all clients unless noted):
  EnemyDied(id: string, reason: "Killed" | "Leaked", position: Vector3, reward: number)
  BaseHit(damage: number, healthLeft: number)
  WaveStarted(wave: number, waveCount: number, isBoss: boolean)
  MatchEnded(result: "Victory" | "Defeat")
  DebugHitEnemy(id: string)   CLIENT -> SERVER. Server connects the handler ONLY if
                              RunService:IsStudio(). Validate: typeof(id)=="string",
                              #id <= 16, rate limit 10/s per player, enemy exists.
                              Effect: EnemyService.damage(id, Config.DEBUG_HIT_DAMAGE).
Put payload types in shared/Types.luau.

## Config (shared/Config.luau) — keys both sides rely on
PATH_PREVIEW_ENABLED = false (keep the week-1 preview code, just off)
INTERMISSION_SECONDS = 6
RESTART_DELAY_SECONDS = 8
BASE_MAX_HEALTH = 100
SERVER_TICK_RATE = 10
DEBUG_HIT_DAMAGE = 5
MAX_ENEMIES_ALIVE = 60 (safety cap)
ENEMIES = { [kind] = { health, speed, baseDamage, reward, size: Vector3, color: Color3,
            eyeColor: Color3, horns: boolean } }
  kinds: "Grunt", "Runner", "Tank", "Oni" (boss). Tune numbers (see Timing).
WAVES = array of 10 waves; each wave = { groups = { { kind, count, interval } }, boss: boolean? }
  groups inside a wave spawn sequentially; interval = seconds between spawns.
  Wave 10 is the boss wave (Oni + escorts). Next wave starts when the current wave
  finished spawning AND (all its enemies are gone OR WAVE_TIMEOUT_SECONDS elapsed).
WAVE_TIMEOUT_SECONDS = tune (so the match stays ~3 minutes)
Path length is ~640 studs.

## Timing target
A full match (intermission + 10 waves) should last about 3 minutes (170-200 s) assuming
enemies are killed quickly once towers exist. Write tools/sim_match.py (Python stdlib)
that reads nothing from Luau — duplicate the WAVES/ENEMIES numbers in Python — and prints
per-wave spawn duration, the time for the slowest enemy to walk the full path, and the
total estimated match time for two scenarios: (a) every enemy killed 40% along the path,
(b) nobody killed (how fast does an undefended base die?). Keep Python numbers in sync
with Config and say so in a comment at the top of both files.

## Server systems (src/server/Systems/)
- PathService (exists): also publish ReplicatedStorage.PathPoints in init().
  Add getPathData(): Types.PathData (built once with PathMath.build, cached).
- EnemyService: init() creates workspace.Enemies. API:
    spawn(kind: string): string?   (returns id; nil if MAX_ENEMIES_ALIVE reached)
    damage(id: string, amount: number): ()  -> Health down; at <=0 fire EnemyDied Killed,
                                              destroy, signal to MatchService
    setSpeed(id, speed): ()          (rebase as described)
    getDistance(id): number?
    clearAll(): ()                   (no events fired)
    aliveCount(): number
    onEnemyRemoved: a tiny signal/callback list (Killed or Leaked) MatchService subscribes to
  start(): 10 Hz loop (task.wait(1/SERVER_TICK_RATE) loop or accumulating Heartbeat) that
    leaks enemies whose distance >= path total: fire EnemyDied Leaked, call
    BaseService.damage(baseDamage), destroy.
  Keep enemies in a server table keyed by id (do not scan workspace each tick).
- BaseService: health state; damage(amount) clamps at 0, updates MatchState.BaseHealth,
  fires BaseHit; reset(); isDead().
- MatchService: owns MatchState folder + the match loop in start():
    Waiting (until >= 1 player in game) -> Intermission (StateEndsAt) -> for each wave:
    set Wave, fire WaveStarted, spawn groups, wait for clear/timeout -> if base dead at any
    point: State Defeat, fire MatchEnded("Defeat"), EnemyService.clearAll() ->
    after last wave cleared: Victory -> RESTART_DELAY then reset (BaseService.reset,
    Wave 0) and loop again. Keep EnemiesAlive attribute updated.
- DebugService: Studio-only DebugHitEnemy handler as specified.
- Use task library only. No yields inside init().

## Shared utils
- Util/PathMath (exists): ADD directionAt(data, distance): Vector3 (unit XZ direction of
  the segment at that distance; fallback Vector3.zAxis). Keep it pure.
- Util/EnemyMath (new, pure): distanceAt(baseDistance, baseTime, speed, now): number.

## Client controllers (src/client/Controllers/)
- EnemyRenderer: builds PathData from ReplicatedStorage.PathPoints. Tracks children of
  workspace.Enemies (ChildAdded/ChildRemoved + existing). Every RenderStepped: for each
  tracked enemy compute distance with EnemyMath and workspace:GetServerTimeNow(),
  position = PathMath.positionAt + Vector3.yAxis * HeightOffset, face directionAt,
  model:PivotTo(CFrame.lookAt(pos, pos + dir)). Add a small bob (sin) for life.
  Health bar: BillboardGui above each enemy (size in studs scale), fill tweened on
  Health attribute change; brief white Highlight flash on damage. Clean up all
  connections when an enemy is removed. No per-frame table allocations.
- HudController (exists, extend): keep the title (smaller, top-left or top-center), add:
  wave label "WAVE 3/10", state/countdown label ("Next wave in 4", "BOSS WAVE"...),
  base health bar with numbers (tween fill, turns red under 30%). Mobile-friendly
  (Scale units, TextScaled + UITextSizeConstraint min 12). Remove the "Week 1 build" tag
  or change it to "Week 2 build".
- FxController (new) — the juice:
    EnemyDied Killed: confetti burst at position (pooled Part+Attachment+ParticleEmitter
      with a multicolor ColorSequence, :Emit(n)), plus a floating "+<reward>" BillboardGui
      that tweens up and fades. Leaked: small red burst at the position.
    BaseHit: camera shake (short, decaying, apply as an offset in RenderStepped bound with
      BindToRenderStep after camera priority, never fight the camera permanently) + a red
      full-screen flash Frame tween.
    WaveStarted: big center banner "WAVE n" (or "BOSS WAVE!" in red/gold) that pops in
      (UIScale tween with Back easing) and fades out.
    MatchEnded Victory: screen-wide UI confetti (40-60 small colored Frames falling with
      rotation via tweens, then destroyed) + "VICTORY!" banner. Defeat: "DEFEAT" banner,
      desaturated.
    Sounds: OPTIONAL. If used, only "rbxasset://sounds/electronicpingshort.wav", volume low.
    Cap simultaneous effects (pooling; max ~20 floating numbers at once).
- DebugController (new): only if RunService:IsStudio(). On mouse click / touch tap,
  raycast from the camera (workspace:Raycast with params including only workspace.Enemies)
  and if hit belongs to an enemy Model, fire DebugHitEnemy(model.Name). Show a tiny
  "DEBUG: click enemies" label in a corner.

## Ownership (parallel executors — do not edit the other side's files)
Executor SERVER owns: src/shared/** and src/server/** and tools/sim_match.py.
Executor CLIENT owns: src/client/** only. It must code against the contracts above
  (Net.event, Config keys, PathMath.positionAt/directionAt/build, EnemyMath.distanceAt,
  Types) exactly as specified, even if the shared files are not written yet.
