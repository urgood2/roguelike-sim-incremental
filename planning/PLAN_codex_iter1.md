# Incremental Game ASCII UI & Content Expansion (PLAN v1)

## TL;DR

Overhaul the idle game’s gameplay UI from ImGui-only to **grid-aligned ASCII-styled panels** drawn with existing CP437/dungeon sprites, add **4 specialist creature types** (Miner, Lumberjack, Collector, Builder), and implement a **persisted achievement system** with **toast notifications**.

**Deliverables**
- ASCII border component (9-tile assembled CP437/dungeon sprites)
- ASCII resource panel (top-left)
- ASCII upgrade panel (right sidebar, scroll + clickable buy)
- Toast notification system (queue + auto-dismiss)
- Achievements (12 total, 4 categories, persisted)
- Creatures: Miner, Lumberjack, Collector, Builder (spawned at start)
- Collector ground-item system (transient)
- Builder decorative structures system (persisted)

**Critical Path**
1) Reserve stable screen-space layout + world viewport (sidebar space)  
2) Border → Panels → Input routing  
3) Achievements data + hooks → Toast  
4) Creature types + terrain systems → Persistence → Integration test

---

## Repo Workflow (Must Follow)

- **Agent Mail**: reserve files (exclusive) before edits; release after merge/TTL.
- **Beads (bd)**: triage → claim bead (in_progress) → implement + tests → close bead → notify.

---

## Coordinate Spaces & Layout Contracts (Authoritative)

### Constants
- `ENGINE_VIRTUAL_W/H` = `globals.screenWidth()/globals.screenHeight()` (**virtual pixels**, expected **1280×800**)
- `IDLE_WORLD_W/H` = `config.VIRTUAL_WIDTH/config.VIRTUAL_HEIGHT` (**world pixels**, expected **600×400**)
- `TILE_SIZE` = `config.TILE_SIZE` (**20**)
- **UI sidebar width**: `UI_SIDEBAR_W = 200` (10 tiles)
- **World viewport width in virtual space**: `WORLD_VIEW_W = ENGINE_VIRTUAL_W - UI_SIDEBAR_W` (target **1080**)

### Rules
1) **All ASCII UI draws in** `layer.DrawCommandSpace.Screen` (virtual pixels).
2) **Idle world draws in** `layer.DrawCommandSpace.World` (camera-relative).
3) **Mouse**: `input.getMousePos()` must match Screen-space virtual coords (verify in Task 0.1).
4) **Grid alignment**: all UI origins/sizes must be multiples of `TILE_SIZE` (20).

### Non-negotiable Layout Requirement (Prevents UI overlap)
The idle world must be zoomed/offset so the rendered world fits inside the **left** `WORLD_VIEW_W × ENGINE_VIRTUAL_H` region, leaving a guaranteed **200px** right sidebar in virtual space for the upgrade panel.

**Implementation requirement** (in `sim_scene.init()`):
- Compute zoom using `WORLD_VIEW_W`, not full virtual width:
  - `zoomX = WORLD_VIEW_W / IDLE_WORLD_W`
  - `zoomY = ENGINE_VIRTUAL_H / IDLE_WORLD_H`
  - `zoom = math.min(zoomX, zoomY)`
- Center the camera within the **world viewport region**, not the full screen (so the world occupies the left region).

---

## Testing Strategy (Mandatory)

### Execution Matrix
| Category | Runs In | Use For |
|---|---|---|
| Headless Lua | `lua` CLI | pure data/state modules (achievements logic, border geometry, ground items, structures table ops) |
| In-engine | game runtime | rendering, input routing, spawner/AI, SaveManager |
| Manual | human | visual correctness, feel, screenshots |

### Headless-safe rule
Any module with headless tests must succeed on:
```bash
lua -e "package.path='assets/scripts/?.lua;assets/scripts/?/init.lua;'..package.path; require('idle_game.achievements'); print('OK')"
```
No engine globals at require-time.

---

## Parallelization Plan

**Wave 0 (Gating / must finish first)**
- 0.1 Verify coordinate + input bindings
- 0.2 Implement world viewport (sidebar space) in `sim_scene.init()`

**Wave 1**
- 1.1 Verify sprite filenames in atlas
- 1.2 ASCII border component (+ headless test)
- 1.3 Achievements data module (+ headless tests)

**Wave 2**
- 2.1 ASCII resource panel
- 2.2 ASCII upgrade panel (scroll + deterministic ordering + click)
- 2.3 Toast notification system (+ headless test for queue/timing)
- 2.4 Achievement event hooks + listener (hot-reload safe)

**Wave 3**
- 3.0 Gate `forager_sensing` to foragers only (prereq)
- 3.1 Miner
- 3.2 Lumberjack
- 3.3 Collector + ground items (transient)
- 3.4 Builder + structures (persisted)

**Wave 4**
- 4.1 Achievement persistence
- 4.2 Window resize defaults (optional usability; not required for sidebar space)
- 4.3 Integration test pass

---

## Phase 0: Gating Tasks

### 0.1 Verify engine bindings (no code changes unless mismatch found)
**Goal**: confirm assumptions so UI input/layout is correct.

**Checks**
- `globals.screenWidth()` returns engine virtual width (expected 1280).
- `input.getMousePos()` returns Screen-space virtual coords.
- Confirm current `sim_scene.init()` camera/zoom logic and how to bias it into the left region.

**Acceptance**
- A short note added to the plan’s “Reference Index” section listing:
  - verified file + search token proving each assumption

---

### 0.2 Reserve world viewport for sidebar (required)
**Goal**: guarantee a 200px right sidebar in virtual space without UI/world overlap.

**Change**
- Update idle scene camera setup to use `WORLD_VIEW_W = globals.screenWidth() - UI_SIDEBAR_W` for zoom/offset math.

**Acceptance (in-engine)**
- Upgrade panel at `x = globals.screenWidth() - 200` does **not** overlap any world tiles (visually).
- World fully visible inside left region at common window sizes (600×400 and 800×600 physical).

---

## Phase 1: Foundation

### 1.1 Verify sprite filenames (research task)
- Confirm exact sprite filenames exist in `assets/graphics/sprites-0.json`.
- Record verified filenames for:
  - border corners + edges
  - resource icons
  - structure sprites

**Acceptance**
- `grep -c "<filename>" assets/graphics/sprites-0.json` returns `1` for each referenced sprite.

**Commit**: NO

---

### 1.2 ASCII border component
**File**: `assets/scripts/idle_game/ui/ascii_border.lua`

**Contract**
- `create({x,y,width,height,z_order,fill_color})` where `x,y,width,height` are **tiles**
- Stores computed pixel geometry (`pixel_x/y/width/height`) = tiles × 20
- `draw(panel)` queues border sprites in Screen space; must guard headless (`if not command_buffer then return end`)

**Tests (headless)**
- `assets/scripts/tests/test_idle_ascii_border.lua` validates geometry math and headless require.

**Acceptance**
- `lua assets/scripts/tests/test_idle_ascii_border.lua` passes.

**Commit**: YES

---

### 1.3 Achievements data module (TDD)
**File**: `assets/scripts/idle_game/achievements.lua`  
**Test**: `assets/scripts/tests/test_idle_achievements.lua`

**Requirements**
- Exactly **12 achievements** (resource/upgrade/creatures/time).
- State:
  - `_definitions` map
  - `_unlocked` set map
  - `_playtime` seconds
- `unlock(id)` is idempotent.
- Threshold comparisons use `>=`; floor float inputs before compare.

**Headless constraints**
- No engine globals at require-time.
- Any dependency (`resources`, `upgrades`, `spawner`) must be lazy-loaded inside check functions or mockable.

**Acceptance**
- `lua assets/scripts/tests/test_idle_achievements.lua` passes.

**Commit**: YES

---

## Phase 2: UI Panels

### 2.1 ASCII resource panel
**File**: `assets/scripts/idle_game/ui/ascii_resource_panel.lua`

**Layout**
- Screen-space at (0,0), grid-aligned, uses `ascii_border`.
- Renders icons + labels + amounts.

**Acceptance (in-engine)**
- Visual: correct values update live; screenshot captured.
- Structural: exported `module.x/y/width/height` are multiples of 20.

**Commit**: YES

---

### 2.2 ASCII upgrade panel (scroll + click)
**File**: `assets/scripts/idle_game/ui/ascii_upgrade_panel.lua`

**Requirements**
- Screen-space `x = globals.screenWidth() - 200`, `y=0`, width=200.
- Deterministic ordering: **sort upgrade IDs alphabetically** (do not rely on `pairs()` order).
- Scroll via mouse wheel + (UP/DOWN, W/S) when hovered.
- Click handling consumes clicks inside BUY button regions and calls `upgrades.purchase(id, resources)` (verify exact signature at implementation time; define wrapper if needed).

**Single authoritative click mapping**
- Render and click must use the **same ordered list** and the same scroll offset semantics.

**Acceptance (in-engine)**
- Click BUY does not harvest tiles behind it.
- Scroll reaches all upgrades (count verified against `upgrades.get_all()`).

**Commit**: YES

---

### 2.3 Toast notifications
**File**: `assets/scripts/idle_game/ui/toast_notification.lua`

**Requirements**
- Queue max 3 visible.
- Auto-dismiss after default 3s.
- Headless-safe queue/timing logic:
  - If `core.timer` is available, use it.
  - If not available (headless), fall back to per-toast `remaining` decremented by `update(dt)` so tests still validate auto-dismiss.

**Acceptance (headless)**
- A test shows a toast with duration 0.1s and asserts the queue becomes empty after simulated time.

**Commit**: YES

---

### 2.4 Achievement event hooks + listener
**Files**
- modify: `assets/scripts/idle_game/resources.lua`, `assets/scripts/idle_game/upgrades.lua`, `assets/scripts/idle_game/spawner.lua`
- add: `assets/scripts/idle_game/achievement_listener.lua`

**Signals**
- `resource_changed(resource, new_total)` emitted on positive adds only.
- `upgrade_purchased(id, new_level)` emitted only on successful purchase.
- `creature_spawned(type, entity)` emitted for all creature spawns (including batch spawns).

**Hot-reload safety**
- Listener must support `init()` + `shutdown()` and must remove old handlers before re-registering.

**Acceptance (in-engine)**
- Calling `achievement_listener.init()` twice does not duplicate unlock/toast behavior.
- Unlocking an achievement emits exactly one toast.

**Commit**: YES

---

## Phase 3: New Creatures

### 3.0 Gate `forager_sensing` (required)
**File**: `assets/scripts/ai/worldstate_updaters.lua`

**Change**
- Early-return unless entity is in `spawner._foragers`.

**Acceptance**
- Structural grep confirms the gate exists before any `registry:get(...)` in `forager_sensing`.

**Commit**: YES

---

### Common creature requirements (3.1–3.4)
- Add tracking tables in `spawner.lua`: `_miners/_lumberjacks/_collectors/_builders`
- Add per-type count functions + `getTotalCreatureCount()` (used by achievements).
- Each creature’s updater must be gated by its tracking table membership.
- Specialists must not accidentally activate global forager goals; goal selectors must avoid global goal table (use empty goals or a dedicated safe goals table).

---

### 3.1 Miner
**Files**
- `assets/scripts/ai/entity_types/miner.lua`
- `assets/scripts/ai/goal_selectors/miner.lua`
- `assets/scripts/ai/blackboard_init/miner.lua`
- `assets/scripts/ai/worldstate_updaters.lua` (add `miner_sensing`)
- `assets/scripts/idle_game/spawner.lua` (spawn + tracking + signal)

**Behavior**
- Passive stone harvesting near rocks, faster yield/chance than forager.

**Acceptance (in-engine)**
- Miner spawns; miner increases stone resource over time near rocks.

**Commit**: YES

---

### 3.2 Lumberjack
Same structure as Miner, but targets trees / wood.

**Acceptance (in-engine)**
- Lumberjack spawns; increases wood near trees.

**Commit**: YES

---

### 3.3 Collector + ground items (transient)
**Files**
- modify: `assets/scripts/idle_game/terrain.lua` (add `_ground_items`, drop/pickup/find-nearest)
- modify: `assets/scripts/ai/worldstate_updaters.lua` (collector sensing + optional drop logic for other harvesters)
- add AI + spawner pieces for Collector

**Lifecycle**
- `_ground_items` cleared on `terrain.setCurrentGrid(grid)`
- not persisted

**Acceptance**
- Headless test validates `drop_item/pickup_item` semantics.
- In-engine: collector picks up dropped items and resources increase.

**Commit**: YES

---

### 3.4 Builder + structures (persisted)
**Files**
- modify: `assets/scripts/idle_game/terrain.lua` (add `_structures`, placement API, SaveManager collector registration)
- modify: `assets/scripts/idle_game/terrain_renderer.lua` (render structures at z>terrain)
- add AI + spawner pieces for Builder
- modify: `assets/scripts/core/main.lua` (early `pcall(require("idle_game.terrain"))` before `SaveManager.init()`)

**Persistence**
- Structures persist via SaveManager collector.
- `_structures` is not cleared in `setCurrentGrid`.

**Acceptance (in-engine)**
- Builder places decorative structures.
- Save/load restores structures.

**Commit**: YES

---

## Phase 4: Integration

### 4.1 Achievement persistence
**Files**
- `assets/scripts/idle_game/achievements.lua` (SaveManager collector + guarded `SaveManager.save()` on unlock)
- `assets/scripts/core/main.lua` (early require before `SaveManager.init()`)

**Acceptance (in-engine)**
- Achievements unlocked, restart game, achievements remain unlocked.

**Commit**: YES

---

### 4.2 Window size defaults (optional usability)
**Goal**: improve physical window defaults (does not affect virtual sidebar math).

**Files**
- `assets/config.json` (render_data.screen width/height → 800×600)
- `src/core/globals.cpp` (fallback defaults to match)

**Acceptance**
- Window opens at 800×600 (manual).

**Commit**: YES

---

### 4.3 Integration test pass (final)
**Checklist**
- ASCII resource panel renders and updates
- Upgrade panel: scroll + buy works; click doesn’t harvest world
- Toast queue works; no spam/dup handlers
- All 4 creatures spawn at game start and behave
- Achievements unlock (resource/upgrade/time/creature count)
- Persistence: achievements + structures survive restart
- ImGui debug panels still render

**Acceptance**
- `just build-debug` passes
- No Lua errors during 5–10 minutes of play

**Commit**: NO

---

## sim_scene.lua Integration (Single Source of Truth)

### Imports
Add requires for:
- `idle_game.ui.ascii_resource_panel`
- `idle_game.ui.ascii_upgrade_panel`
- `idle_game.ui.toast_notification`
- `idle_game.achievement_listener`

### init()
- Initialize panels + toast + listener.
- Spawn initial creature mix (20 total), replacing `spawnForagers(20)` with a mixed set.

### update(dt)
Order:
1) terrain + spawner maintenance (existing)
2) `ascii_upgrade_panel.update(dt)`
3) `toast_notification.update(dt)`
4) `achievement_listener.update(dt)`
5) UI click pre-check → early return if consumed
6) existing `input_module.handleClick(config)` path unchanged

### draw()
Order:
1) world (terrain, corpses, structures)
2) ASCII UI (Screen space, z high)
3) ImGui debug panels last

---

## Commit Strategy (Atomic)
- One feature per commit matching task boundaries (border, achievements, each panel, hooks, each creature, persistence, window defaults).

---

## Reference Index (Search Tokens)
- `sim_scene.lua`: `function sim_scene.init()`, `function sim_scene.update(dt)`, `function sim_scene.draw()`
- `worldstate_updaters.lua`: `forager_sensing = function(entity, dt)`
- `spawner.lua`: `_foragers`, `spawnForagers`, `processPendingDestructions`
- `terrain.lua`: `function terrain.setCurrentGrid(grid)`
- `core/main.lua`: `function main.init()`, `SaveManager.init()`
- `scripting_functions.cpp`: `lua["globals"]["screenWidth"]`
- `assets/graphics/sprites-0.json`: sprite filename strings