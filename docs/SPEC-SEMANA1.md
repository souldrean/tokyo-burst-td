# Tokyo Burst TD — Week 1 spec (source of truth for all executors)

Game: anime tower defense, co-op up to 4, 3-minute matches, low-poly + neon juice,
modern anime city theme (Tokyo-like). Audience 10-18, mobile+PC, English UI.
Week 1 goal: project skeleton + grey-box city map with an enemy path that is
PROVEN to work (a preview cube walks the path in a loop).

## Coordinates (studs). Ground top surface is at Y = 0.
Waypoints (enemy path, in order). Y for waypoint parts = 1.
  1: (-90, -80)   <- EnemySpawn here
  2: ( 40, -80)
  3: ( 40, -30)
  4: (-60, -30)
  5: (-60,  20)
  6: ( 60,  20)
  7: ( 60,  70)
  8: (-80,  70)   <- PlayerBase here
(pairs are X, Z)
Road width: 12 studs. Ground: 220 x 220.

## Instance tree (Workspace.Map, a Model)
- Ground        Part  Size (220,1,220), CFrame pos (0,-0.5,0), Material Concrete, Color (0.62,0.62,0.66), Anchored
- Road          Folder; one Part per segment between consecutive waypoints, plus a square
                "joint" Part (12x0.2x12) at each waypoint so corners look clean.
                Height 0.2, top at Y=0.1 (center Y=0). Material Asphalt, Color (0.18,0.18,0.22), Anchored.
                Names: "Segment_1_2", "Joint_3", etc.
- Waypoints     Folder; Parts named "1".."8", Size (1,1,1), pos (x,1,z), Transparency 1,
                CanCollide false, CanQuery false, CanTouch false, Anchored. Attribute Index = n (number).
- EnemySpawn    Part Size (10,0.4,10) at waypoint 1, top slightly above road (center Y=0.3),
                Material Neon, Color (1,0.2,0.35), Anchored, CanCollide false.
- PlayerBase    Part Size (14,8,14) at waypoint 8, resting on ground (center Y=4),
                Material Neon, Color (0.2,0.75,1), Anchored. Attribute MaxHealth = 100.
- Buildings     Folder; 14-20 grey block Parts as placeholder city buildings, varying heights
                (12-60), Material SmoothPlastic, greys/slight blue-greys, Anchored, resting on
                ground. Must NOT overlap any road rectangle (keep >= 6 studs margin) and must be
                inside the ground. Names "Building_01".. Deterministic (fixed seed).
- PlayerSpawn   SpawnLocation Size (12,1,12) at (0, 0.5, -5)?? -> MUST be off-road; generator
                picks a safe spot near the center and asserts no overlap. Neutral = true,
                Duration (ForceField) 0, Anchored.
- Placement     Folder; 10 flat Parts "Slot_01".. Size (8,0.2,8), Material Neon,
                Color (1,0.85,0.2), Transparency 0.6, CanCollide false, Anchored, center Y=0.1,
                placed beside the road (2-4 studs from road edge, not on road, not on buildings,
                not overlapping each other). These are where units will be placed in week 3.

## Model file format (src/workspace/Map.model.json) — Rojo 7 style
{ "ClassName": "Model", "Children": [ { "Name": "...", "ClassName": "Part",
  "Properties": { "Size": [x,y,z], "CFrame": {"position":[x,y,z],
  "orientation":[[1,0,0],[0,1,0],[0,0,1]]}, "Color": [r,g,b] (0..1 floats),
  "Material": "Concrete", "Anchored": true, "Transparency": 1, "CanCollide": false },
  "Attributes": { "Index": 1 }, "Children": [] } ] }
Supported property value kinds ONLY: Vector3 array (Size), CFrame object, Color array
(property name "Color"), Material enum string, booleans, numbers (Transparency),
strings. SpawnLocation extra: "Neutral": true, "Duration": 0.
Attributes: numbers, booleans, strings only.

## Code layout (Luau, every file starts with --!strict, tabs, English identifiers,
## comments in simple Brazilian Portuguese because the owner is a beginner learning)
src/shared/Config.luau          frozen table of tunables (PREVIEW_SPEED etc.)
src/shared/Types.luau           shared types (PathData etc.), return nil
src/shared/Util/PathMath.luau   PURE functions: total path length, position at distance
                                along polyline (lerp), segment lookup. No Roblox services.
src/server/init.server.luau     two-phase bootstrap (init all, then start all)
src/server/Systems/PathService.luau  init(): reads Workspace.Map.Waypoints, sorts by
                                Index attribute, validates (>=2, sequential), caches
                                Vector3 list; getWaypoints(): {Vector3}; errors clearly
                                if map missing.
src/server/Systems/PathPreview.luau  start(): spawns a small anchored neon cube that walks
                                the path continuously (Heartbeat, using PathMath with
                                distance += speed*dt), loops at end. Controlled by
                                Config.PATH_PREVIEW_ENABLED. Clean up connection pattern.
src/client/init.client.luau     two-phase bootstrap for Controllers
src/client/Controllers/HudController.luau  creates a simple ScreenGui with a title label
                                "TOKYO BURST TD" (top center, scaled with UIScale/Scale
                                units, mobile-friendly, TextScaled + UITextSizeConstraint)
                                and a small "Week 1 build" tag. Fun neon-ish colors, a
                                subtle looping tween pulse on the title (TweenService).
No RemoteEvents yet (none needed in week 1).
