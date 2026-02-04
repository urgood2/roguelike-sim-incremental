# Incremental Game ASCII UI & Content Expansion (PLAN v2)

## TL;DR

Replace the idle game’s ImGui-only gameplay UI with **grid-aligned ASCII panels** rendered via `command_buffer` + CP437/dungeon sprites, add **4 specialist creature types** (Miner, Lumberjack, Collector, Builder), and implement a **persisted achievement system** with **toast notifications**.

**Primary Deliverables**
- ASCII border component (9-slice via CP437/dungeon sprites)
- ASCII resource panel (top-left, grid-aligned)
- ASCII upgrade panel (right sidebar, scroll + clickable buy)
- Toast notifications (queue + auto-dismiss; achievement-driven)
- Achievements (12 total; persisted)
- Creatures: Miner, Lumberjack, Collector, Builder (spawned at start)
- Collector ground-item system (transient, non-persisted)
- Builder decorative structures system (persisted)

**Critical Path**
1) Lock layout contract: **world viewport leaves a fixed 200px sidebar**
2) Build border → panels → input routing (no world-click bleedthrough)
3) Achievements core + hooks → toasts → persistence
4) Specialists + terrain extensions → persistence → integration verification

---

## Repo Workflow (Must Follow)

- **Agent Mail**: reserve files (exclusive) before edits; release after merge/TTL.
- **Beads (bd)**: triage → claim bead (in_progress) → implement + tests → close bead → notify.
- **UBS**: run UI baseline verification before committing any UI changes (`just ui-verify`).

---

## Scope / Non-goals

**In scope**
- Idle-game scene only (`assets/scripts/idle_game/scenes/sim_scene.lua`)
- ASCII panels for resources + upgrades only (debug stays ImGui)
- New creature roles + supporting terrain state

**Out of scope**
- Refactoring the general UI DSL system
- Reworking idle_game legacy gameplay (`assets/scripts/idle_game/legacy/gameplay.lua`)
- Full game-wide achievements system (idle-game only)

---

## Coordinate Spaces & Layout Contracts (Authoritative)

### Key values
- `TILE_SIZE` = `require("idle_game.config").TILE_SIZE` (expected **20**)
- `IDLE_WORLD_W/H` = `config.VIRTUAL_WIDTH/config.VIRTUAL_HEIGHT` (expected **600×400**)
- `ENGINE_SCREEN_W/H` = `globals.screenWidth()/globals.screenHeight()` (window-scaled virtual coords)
- **UI sidebar width**: `UI_SIDEBAR_W = 10 * TILE_SIZE` (**200px**)

### Rules
1) ASCII UI draws in **Screen space**: `layer.DrawCommandSpace.Screen`.
2) Idle world draws in **World space**: `layer.DrawCommandSpace.World` (camera-relative).
3) All UI rectangles must be aligned to the tile grid: `x,y,w,h` multiples of `TILE_SIZE`.
4) A click inside the UI sidebar must never trigger world harvesting/selection.

### World viewport reservation (non-negotiable)
In `assets/scripts/idle_game/scenes/sim_scene.lua:sim_scene.init()` compute zoom using:
- `WORLD_VIEW_W = globals.screenWidth() - UI_SIDEBAR_W`
- `zoomX = WORLD_VIEW_W / config.VIRTUAL_WIDTH`
- `zoomY = globals.screenHeight() / config.VIRTUAL_HEIGHT`
- `zoom = math.min(zoomX, zoomY)`
And center the camera within the **left** region:
- `cam:SetActualOffset(WORLD_VIEW_W / 2, globals.screenHeight() / 2)`

---

## Testing Strategy (Mandatory)

### What to run
- C++ build sanity: `just build-debug`
- UI baseline verification (before commits touching UI): `just ui-verify`
- Lua unit tests (headless): `lua assets/scripts/tests/test_runner.lua --filter idle_game assets/scripts/tests`

### Headless-safe module rule
Any module with headless tests must **not** touch engine globals at require-time (`registry`, `command_buffer`, `layers`, `animation_system`, etc.). Only use those inside functions guarded by availability checks.

### Required new tests (Lua, using `tests.test_runner`)
- `assets/scripts/tests/test_idle_ascii_border.lua`
- `assets/scripts/tests/test_idle_achievements.lua`
- `assets/scripts/tests/test_idle_toast_queue.lua`
- `assets/scripts/tests/test_idle_ground_items.lua`
- `assets/scripts/tests/test_save_manager_register_distributes.lua` (see Phase 0.3)

---

## Parallelization Plan

**Wave 0 (Gating)**
- 0.1 Verify coordinate + input assumptions
- 0.2 Implement world viewport (sidebar reservation)
- 0.3 Fix SaveManager collector late-registration distribution

**Wave 1 (Foundation)**
- 1.1 Verify sprite filenames (atlas)
- 1.2 ASCII border component (+ tests)
- 1.3 Achievements core (+ tests)

**Wave 2 (UI)**
- 2.1 ASCII resource panel
- 2.2 ASCII upgrade panel (scroll + click + deterministic ordering)
- 2.3 Toast queue + renderer (+ tests)
- 2.4 Achievement listener + event hooks (hot-reload safe)

**Wave 3 (Specialists + Terrain)**
- 3.0 Gate forager-only sensing and remove hardcoded TILE_SIZE
- 3.1 Miner
- 3.2 Lumberjack
- 3.3 Collector + transient ground items (+ tests)
- 3.4 Builder + persisted structures

**Wave 4 (Integration + Persistence)**
- 4.1 Achievement persistence
- 4.2 Optional window defaults
- 4.3 Integration verification pass

---

## Phase 0: Gating Tasks

### 0.1 Verify engine bindings (no code changes unless mismatch found)
**Goal**: confirm assumptions so UI input/layout is correct.

**Checks**
- `globals.screenWidth()`/`globals.screenHeight()` correspond to Screen-space pixel coordinates used by UI draw calls.
- `input.getMousePos()` returns Screen-space coordinates consistent with `layer.DrawCommandSpace.Screen`.
- `camera.Get("world_camera"):GetMouseWorld()` maps `input.getMousePos()` to world coordinates.

**Acceptance**
- Reference Index updated with verified file paths + tokens confirming:
  - screen size source
  - mouse position source
  - world mouse conversion

---

### 0.2 Reserve world viewport for sidebar (required)
**File**: `assets/scripts/idle_game/scenes/sim_scene.lua`

**Change**
- Update camera zoom/offset math to reserve `UI_SIDEBAR_W = 200px` on the right.
- Store `sim_scene._world_view_w` and `sim_scene._ui_sidebar_w` for UI modules.

**Acceptance (in-engine)**
- Placing the upgrade panel at `x = globals.screenWidth() - 200` never overlaps world tiles.
- World is fully visible within left region at common window sizes (600×400 and 800×600 physical).

**Commit**: YES (run `just build-debug`)

---

### 0.3 SaveManager: distribute cached data to late-registered collectors (required for persistence)
**File**: `assets/scripts/core/save_manager.lua`

**Problem**
- `SaveManager.init()` loads and distributes only to collectors registered at that moment; collectors registered later never receive loaded data.

**Change**
- In `SaveManager.register(key, collector)`:
  - After `SaveManager.collectors[key] = collector`, if `SaveManager.cache` already contains `SaveManager.cache[key]`, immediately call `collector.distribute(SaveManager.cache[key])` (pcall-guarded).

**Test (headless)**
- `assets/scripts/tests/test_save_manager_register_distributes.lua` sets `SaveManager.cache = { foo = { x = 1 } }`, registers collector `foo`, and asserts `distribute` applied.

**Acceptance**
- Test passes via `lua assets/scripts/tests/test_runner.lua --filter save_manager assets/scripts/tests`.

**Commit**: YES (run `just build-debug`)

---

## Phase 1: Foundation

### 1.1 Verify sprite filenames (research task)
**File**: `assets/graphics/sprites-0.json`

**Goal**
- Identify exact sprite filenames for:
  - border corners/edges/center fill
  - resource icons (food/wood/stone/gold) (if present; otherwise use text-only)
  - structure sprites (decorative)

**Output**
- Create `assets/scripts/idle_game/ui/ascii_sprites.lua` with a single table:
  - `BORDER = { tl=..., t=..., tr=..., l=..., c=..., r=..., bl=..., b=..., br=... }`
  - `ICONS = { food=..., wood=..., stone=..., gold=... }` (optional if icons exist)
  - `STRUCTURES = { ... }` (builder placement uses these keys)

**Acceptance**
- Each referenced sprite filename appears exactly once in `sprites-0.json`.

**Commit**: NO

---

### 1.2 ASCII border component
**Files**
- add: `assets/scripts/idle_game/ui/ascii_border.lua`
- add test: `assets/scripts/tests/test_idle_ascii_border.lua`

**Contract**
- `ascii_border.layout({x, y, w, h, tile_size}) -> { tiles, pixels, interior }`
  - `x,y,w,h` are pixels (must be multiples of `tile_size`)
  - returns computed 9-slice sprite placements (pixel coords)
- `ascii_border.draw(opts)`:
  - opts includes `layer_handle`, `space`, `z`, `sprites=BORDER`, `rect`, optional `fill_tint`, `border_tint`
  - no-op if `not command_buffer` or `not layers` in-engine globals

**Test (headless)**
- Validates grid-aligned geometry math and returned placements.

**Acceptance**
- `lua assets/scripts/tests/test_runner.lua --filter ascii_border assets/scripts/tests` passes.

**Commit**: YES (run `just build-debug`)

---

### 1.3 Achievements core (TDD)
**Files**
- add: `assets/scripts/idle_game/achievements.lua`
- add test: `assets/scripts/tests/test_idle_achievements.lua`

**Requirements**
- Exactly **12 achievements**, IDs stable strings.
- State:
  - `_definitions` (id → definition)
  - `_unlocked` (id → true)
  - `_playtime_seconds`
- Public API:
  - `init()` (optional)
  - `update(dt)` (increments playtime)
  - `is_unlocked(id)`
  - `unlock(id) -> bool newly_unlocked`
  - `get_unlocked_ids() -> {id,...}` (deterministic sorted)
  - `serialize() -> table` and `deserialize(t)`
- Comparisons use `>=` and convert numeric totals with `math.floor` before comparing.

**Achievement list (12)**
- **Resources (4)**
  - `res_wood_100` (wood >= 100)
  - `res_stone_100` (stone >= 100)
  - `res_gold_25` (gold >= 25)
  - `res_total_500` (food+wood+stone+floor(gold) >= 500)
- **Upgrades (3)**
  - `upg_first_purchase` (any upgrade reaches level 1)
  - `upg_any_level_5` (any upgrade reaches level 5)
  - `upg_any_maxed` (any upgrade reaches max_level)
- **Creatures (3)**
  - `crt_total_25` (total living creatures >= 25)
  - `crt_specialists_10` (miners+lumberjacks+collectors+builders >= 10)
  - `crt_builder_exists` (builders >= 1)
- **Time (2)**
  - `time_5min` (playtime >= 300)
  - `time_15min` (playtime >= 900)

**Acceptance**
- Headless tests pass.

**Commit**: YES (run `just build-debug`)

---

## Phase 2: UI Panels

### 2.1 ASCII resource panel
**File**
- add: `assets/scripts/idle_game/ui/ascii_resource_panel.lua`

**Rendering**
- Uses `ascii_border` + (optional) icons from `ascii_sprites.ICONS`.
- Draws in Screen space on `layers.ui` (or another UI-capable layer used elsewhere).
- Position: `(0, 0)`; size: grid-aligned and fixed (e.g. `10 tiles wide × 6 tiles high`).

**Content (minimum)**
- Food, Wood, Stone, Gold (with rates from `resources.get_rate`)
- Foragers count and max (keep existing formula)
- Optional: deaths, trees/rocks totals (if space)

**Acceptance (in-engine)**
- Values update live; no Lua errors.

**Commit**: YES (run `just ui-verify` before commit)

---

### 2.2 ASCII upgrade panel (scroll + click)
**File**
- add: `assets/scripts/idle_game/ui/ascii_upgrade_panel.lua`

**Layout**
- `x = globals.screenWidth() - UI_SIDEBAR_W`, `y = 0`, `w = UI_SIDEBAR_W`, `h = globals.screenHeight()`.
- All internal rects grid-aligned.

**Ordering**
- Deterministic: sort upgrade IDs alphabetically (never rely on `pairs()`).

**Input**
- Scroll:
  - Mouse wheel via `input.getMouseWheel()` when hovered
  - Keyboard: UP/DOWN or W/S when hovered
- Click:
  - Uses `input.isMousePressed(MouseButton.MOUSE_BUTTON_LEFT)` and `input.getMousePos()`
  - Must return `consumed=true` when click is inside panel bounds (even if click is on empty space) to prevent world click-through.
- Purchasing:
  - Single authoritative render model: the exact same ordered list + scroll offset used for draw and click mapping.
  - Calls `upgrades.purchase(id, resources)` only if afford + not max.

**Acceptance (in-engine)**
- Clicking inside sidebar never harvests/selects world tiles.
- Buying works; scroll reaches all upgrades.

**Commit**: YES (run `just ui-verify` before commit)

---

### 2.3 Toast notifications (queue + auto-dismiss)
**Files**
- add: `assets/scripts/idle_game/ui/toast_queue.lua` (headless-safe)
- add: `assets/scripts/idle_game/ui/toast_renderer.lua` (engine rendering; ASCII border optional)
- add test: `assets/scripts/tests/test_idle_toast_queue.lua`

**Toast queue API (headless-safe)**
- `queue.init({max_visible=3, default_duration=3.0})`
- `queue.push(text, {duration=?})`
- `queue.update(dt)`
- `queue.get_visible() -> { {text, age, duration}, ... }` (deterministic)
- No engine globals.

**Renderer**
- Anchored bottom-right (or top-right under upgrade panel header), Screen space.
- Draws 1–3 toasts using ASCII border and `command_buffer.queueDrawText`.

**Acceptance**
- Queue unit test simulates time and asserts auto-dismiss.
- In-engine: unlocking an achievement produces a toast.

**Commit**: YES (run `just ui-verify` before commit)

---

### 2.4 Achievement event hooks + listener (hot-reload safe)
**Files**
- modify: `assets/scripts/idle_game/resources.lua`
- modify: `assets/scripts/idle_game/upgrades.lua`
- modify: `assets/scripts/idle_game/spawner.lua`
- add: `assets/scripts/idle_game/achievement_listener.lua`

**Event mechanism**
- Use `local signal = require("external.hump.signal")`.
- Use `core.signal_group` in the listener to register/unregister handlers safely.

**Signals (namespaced)**
- `signal.emit("idle.resource_added", resource, new_total, delta)` (delta > 0 only)
- `signal.emit("idle.upgrade_purchased", id, new_level)`
- `signal.emit("idle.creature_spawned", type, entity)`
- Listener drives:
  - achievements checks/unlocks
  - toast enqueue on newly unlocked

**Hot-reload safety**
- `achievement_listener.init()` may be called multiple times; must not duplicate handlers.
- `achievement_listener.shutdown()` removes handlers.

**Acceptance (in-engine)**
- Calling `achievement_listener.init()` twice results in exactly one unlock + one toast per achievement.

**Commit**: YES (run `just build-debug`)

---

## Phase 3: New Creatures + Terrain Extensions

### 3.0 Gate forager sensing + remove hardcoded TILE_SIZE (required)
**File**: `assets/scripts/ai/worldstate_updaters.lua`

**Changes**
- `forager_sensing`: early-return unless `require("idle_game.spawner")._foragers[entity] == true`.
- Replace any hardcoded `TILE_SIZE = 20` with `require("idle_game.config").TILE_SIZE`.

**Acceptance**
- Specialists do not run survival/harvest logic intended for foragers.

**Commit**: YES

---

### Common creature requirements (3.1–3.4)
**Files**
- modify: `assets/scripts/idle_game/spawner.lua`
- add AI files per type under:
  - `assets/scripts/ai/entity_types/`
  - `assets/scripts/ai/goal_selectors/`
  - `assets/scripts/ai/blackboard_init/`

**Spawner**
- Add tracking tables:
  - `_miners`, `_lumberjacks`, `_collectors`, `_builders`
- Add count helpers:
  - `getMinerCount()`, `getLumberjackCount()`, `getCollectorCount()`, `getBuilderCount()`
  - `getTotalCreatureCount()`

**Updaters**
- Any per-type updater must early-return unless the entity is in its tracking table.

---

### 3.1 Miner
**Files**
- add: `assets/scripts/ai/entity_types/miner.lua`
- add: `assets/scripts/ai/goal_selectors/miner.lua`
- add: `assets/scripts/ai/blackboard_init/miner.lua`
- modify: `assets/scripts/ai/worldstate_updaters.lua` (miner sensing/harvest)
- modify: `assets/scripts/idle_game/spawner.lua` (spawn + tracking + signal)

**Behavior**
- Prefer rocks; harvest stone at higher rate/chance than foragers.

**Acceptance (in-engine)**
- Miner spawns and increases stone near rocks.

**Commit**: YES

---

### 3.2 Lumberjack
Same as Miner but targets trees and produces wood.

**Acceptance (in-engine)**
- Lumberjack spawns and increases wood near trees.

**Commit**: YES

---

### 3.3 Collector + ground items (transient)
**Files**
- modify: `assets/scripts/idle_game/terrain.lua` (add `_ground_items` + API)
- modify: `assets/scripts/ai/worldstate_updaters.lua` (collector sensing)
- add collector AI files + spawner integration

**Terrain API**
- `drop_item(tileX, tileY, kind, amount)` (adds ground item)
- `pickup_item(index_or_id)` (removes; returns item)
- `find_nearest_item(tileX, tileY, kind?)`
- Clear `_ground_items` inside `terrain.setCurrentGrid(grid)` (non-persisted).

**Test (headless)**
- `assets/scripts/tests/test_idle_ground_items.lua` validates drop/pickup/find semantics.

**Acceptance (in-engine)**
- Collector picks up items and resources increase accordingly.

**Commit**: YES

---

### 3.4 Builder + structures (persisted)
**Files**
- modify: `assets/scripts/idle_game/terrain.lua` (add `_structures` + placement API)
- modify: `assets/scripts/idle_game/terrain_renderer.lua` (render structures above terrain)
- modify: `assets/scripts/idle_game/spawner.lua` (spawn + tracking + signal)
- add builder AI files
- add: `assets/scripts/idle_game/terrain_persistence.lua` (register SaveManager collector)

**Structure model**
- `_structures` stored as a list of `{tileX, tileY, sprite}` (and optional tint).
- Not cleared in `setCurrentGrid`.

**Persistence**
- Register `SaveManager.register("idle_structures", collector)` in `terrain_persistence.lua`.
- With Phase 0.3, registration order relative to `SaveManager.init()` is no longer a blocker.

**Acceptance (in-engine)**
- Builder places decorative structures.
- Save/load restores structures.

**Commit**: YES

---

## Phase 4: Integration + Persistence

### 4.1 Achievement persistence
**Files**
- modify: `assets/scripts/idle_game/achievements.lua` (serialize/deserialize)
- add: `assets/scripts/idle_game/achievements_persistence.lua` (SaveManager collector)

**Behavior**
- Register `SaveManager.register("idle_achievements", collector)`.
- On new unlock: trigger `SaveManager.save()` (debounce optional; correctness first).

**Acceptance (in-engine)**
- Unlock achievement → restart → still unlocked.

**Commit**: YES

---

### 4.2 Optional window size defaults (usability)
**Files**
- modify: `assets/config.json` (default physical size 800×600)
- modify: `src/core/globals.cpp` (fallback defaults)

**Acceptance**
- Window opens at 800×600 by default.

**Commit**: YES

---

### 4.3 Integration verification pass (final)
**Checklist**
- Sidebar reserved; no overlap
- Resource panel renders and updates
- Upgrade panel scroll + buy works; no world click-through
- Toasts show and auto-dismiss; no duplicate handlers
- 4 specialists spawn and behave
- Achievements unlock across categories
- Persistence: achievements + structures survive restart
- ImGui debug panel still works

**Acceptance**
- `just build-debug` passes
- `just ui-verify` passes
- No Lua errors during 10 minutes of SIM_GAME play

**Commit**: NO

---

## sim_scene.lua Integration (Single Source of Truth)

**File**: `assets/scripts/idle_game/scenes/sim_scene.lua`

### Imports
Replace ImGui panels with:
- `idle_game.ui.ascii_resource_panel`
- `idle_game.ui.ascii_upgrade_panel`
- `idle_game.ui.toast_renderer`
- `idle_game.achievement_listener`

### init()
- Initialize panels, toasts, and listener.
- Replace `spawner.spawnForagers(20)` with a mixed initial set (20 total), e.g.:
  - 12 foragers, 3 miners, 3 lumberjacks, 1 collector, 1 builder

### update(dt)
Order:
1) resources/terrain updates (existing)
2) spawner maintenance (existing)
3) UI updates:
   - upgrade panel scroll state
   - toast queue update
   - achievements update (playtime)
4) UI click handling:
   - if click is inside UI sidebar (or any UI panel), consume and return
5) world click handling:
   - call `input_module.handleClick(config)` only if not consumed

### draw()
Order:
1) world: terrain → corpses → structures
2) ASCII UI: resource panel → upgrade panel → toasts (Screen space, high z)
3) ImGui debug panel last

---

## Commit Strategy (Atomic)

- One feature per commit (viewport, SaveManager fix, border, achievements, each panel, hooks, each creature, ground items, structures, persistence).
- For any commit touching UI rendering/input: run `just ui-verify` before committing.

---

## Reference Index (File Paths + Search Tokens)

- `assets/scripts/idle_game/scenes/sim_scene.lua`: `function sim_scene.init()`, `function sim_scene.update(dt)`, `function sim_scene.draw()`
- `assets/scripts/idle_game/input.lua`: `function sim_input.handleClick(config)`
- `assets/scripts/core/main.lua`: `SaveManager.init()`, `sim_scene.init()`, `sim_scene.update(dt)`, `sim_scene.draw()`
- `assets/scripts/core/save_manager.lua`: `function SaveManager.register(key, collector)`
- `assets/scripts/ai/worldstate_updaters.lua`: `forager_sensing = function(entity, dt)`
- `assets/scripts/idle_game/spawner.lua`: `_foragers`, `spawnForagers`, `processPendingDestructions`
- `assets/scripts/idle_game/terrain.lua`: `function terrain.setCurrentGrid(grid)`
- `assets/scripts/idle_game/terrain_renderer.lua`: `function terrain_renderer.draw(terrainGrid)`
- `assets/scripts/tests/test_runner.lua`: `describe`, `it`, `expect`, `run`
- `assets/graphics/sprites-0.json`: sprite `filename` strings