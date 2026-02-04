# Incremental Game ASCII UI & Content Expansion (PLAN v2 — Improved)

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
1) Lock layout/input contract (screen/world spaces + sidebar reservation)
2) Border → panels → input routing (no world-click bleedthrough)
3) Achievements core → hooks → toasts → persistence
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
- New creature roles + supporting terrain state (ground items, structures)

**Out of scope**
- Refactoring the general UI DSL system
- Reworking idle_game legacy gameplay (`assets/scripts/idle_game/legacy/gameplay.lua`)
- Full game-wide achievements system (idle-game only)

---

## Coordinate Spaces & Layout Contracts (Authoritative)

### Key values
- `TILE_SIZE` = `require("idle_game.config").TILE_SIZE` (**must be used everywhere**; never hardcode `20`)
- `IDLE_WORLD_W/H` = `config.VIRTUAL_WIDTH/config.VIRTUAL_HEIGHT` (expected 600×400 virtual)
- `ENGINE_SCREEN_W/H` = `globals.screenWidth()/globals.screenHeight()` (virtual screen coords used for UI)
- **UI sidebar width**: `UI_SIDEBAR_W = 10 * TILE_SIZE` (200px when TILE_SIZE=20)

### Rules
1) ASCII UI draws in **Screen space**: `layer.DrawCommandSpace.Screen`.
2) Idle world draws in **World space**: `layer.DrawCommandSpace.World` (camera-relative).
3) All UI rectangles must be aligned to the tile grid: `x,y,w,h` multiples of `TILE_SIZE`.
4) A click inside any UI panel rectangle must never trigger world harvesting/selection.

### World viewport reservation (non-negotiable)
In `assets/scripts/idle_game/scenes/sim_scene.lua:sim_scene.init()` compute zoom using:
- `WORLD_VIEW_W = globals.screenWidth() - UI_SIDEBAR_W`
- `zoomX = WORLD_VIEW_W / config.VIRTUAL_WIDTH`
- `zoomY = globals.screenHeight() / config.VIRTUAL_HEIGHT`
- `zoom = math.min(zoomX, zoomY)`
Then center camera within the left region:
- `cam:SetActualOffset(WORLD_VIEW_W / 2, globals.screenHeight() / 2)`

---

## Testing Strategy (Mandatory)

### What to run
- C++ build sanity: `just build-debug`
- UI baseline verification (before commits touching UI): `just ui-verify`
- Lua unit tests (headless): `lua assets/scripts/tests/test_runner.lua --filter idle_game assets/scripts/tests`

### Headless-safe module rule
Any module used by headless tests must **not** touch engine globals at require-time (`registry`, `command_buffer`, `layers`, `animation_system`, etc.). Engine-only work must happen inside functions, guarded by availability checks, or in dedicated renderer modules that are not required by headless tests.

### Required new tests (Lua, using `tests.test_runner`)
- `assets/scripts/tests/test_idle_ascii_border.lua`
- `assets/scripts/tests/test_idle_achievements.lua`
- `assets/scripts/tests/test_idle_toast_queue.lua`
- `assets/scripts/tests/test_idle_ground_items.lua`
- `assets/scripts/tests/test_idle_upgrade_panel_model.lua` (deterministic ordering + click mapping + scroll bounds)
- `assets/scripts/tests/test_idle_achievement_listener_dedup.lua` (init twice → one handler set)
- `assets/scripts/tests/test_save_manager_register_distributes.lua`

---

## Parallelization Plan (Explicit Dependencies)

**Wave 0 (Gating; must land first)**
- 0.1 Verify engine bindings + draw/input APIs
- 0.2 Implement world viewport (sidebar reservation)
- 0.3 Fix SaveManager collector late-registration distribution

**Wave 1 (Shared foundation)**
- 1.1 Confirm sprite filenames (atlas) + publish `ascii_sprites.lua`
- 1.2 ASCII border component (+ tests)
- 1.3 Toast queue (headless) (+ tests)
- 1.4 Achievements core (headless) (+ tests)

**Wave 2 (UI; depends on Wave 0 + 1.2)**
- 2.1 Resource panel (renderer + minimal model)
- 2.2 Upgrade panel (split model from renderer) (+ model tests)
- 2.3 Toast renderer (engine) + wiring to queue

**Wave 3 (Signals + listeners; depends on Wave 1.3 + 1.4)**
- 3.1 Emit signals (resources/upgrades/spawner)
- 3.2 Achievement listener (dedup-safe) (+ tests)
- 3.3 Wire toasts on unlock

**Wave 4 (Specialists + terrain; can proceed after Wave 0.3, independent of UI)**
- 4.0 Gate forager-only sensing; remove hardcoded TILE_SIZE
- 4.1 Miner
- 4.2 Lumberjack
- 4.3 Collector + ground items (+ tests)
- 4.4 Builder + structures (+ persistence)

**Wave 5 (Persistence + integration; depends on Waves 2–4)**
- 5.1 Achievement persistence (SaveManager collector) (+ smoke test)
- 5.2 Structure persistence verification
- 5.3 Integration verification pass

---

## Phase 0: Gating Tasks

### 0.1 Verify engine bindings + rendering/input APIs (no code changes unless mismatch found)
**Goal**: ensure plan’s draw and input calls match real bindings.

**Checks (must produce concrete findings)**
- Confirm which API draws sprites and text in Screen space (exact function names on `command_buffer`).
- Confirm mouse position API and coordinate system:
  - `input.getMousePos()` return type and units
  - mouse wheel API name and sign convention
  - left-click pressed API and button enum/value
- Confirm world-mouse conversion:
  - `camera.Get("world_camera"):GetMouseWorld()` or equivalent, and whether it uses `input.getMousePos()`.

**Acceptance**
- Update the “Reference Index” with exact function identifiers and the verified binding names to use in implementation.

---

### 0.2 Reserve world viewport for sidebar (required)
**File**: `assets/scripts/idle_game/scenes/sim_scene.lua`

**Change**
- Update camera zoom/offset math to reserve `UI_SIDEBAR_W = 10 * TILE_SIZE` on the right.
- Store `sim_scene._world_view_w` and `sim_scene._ui_sidebar_w` for UI layout.
- Store `sim_scene._tile_size` (from config) for shared grid alignment.

**Acceptance (in-engine)**
- Rightmost `UI_SIDEBAR_W` pixels contain no world tiles at any zoom.
- At 600×400 and 800×600 physical window sizes: world is centered within the left region and fully visible.

**Commit**: YES (run `just build-debug`)

---

### 0.3 SaveManager: distribute cached data to late-registered collectors (required for persistence)
**File**: `assets/scripts/core/save_manager.lua`

**Problem**
- `SaveManager.init()` loads and distributes only to collectors registered at that moment; collectors registered later never receive loaded data.

**Change**
- In `SaveManager.register(key, collector)`:
  - After storing `collector`, if `SaveManager.cache` contains `cache[key]`, immediately call `collector.distribute(cache[key])` (pcall-guarded).
  - Ensure this does not trigger `collect()` or `save()` implicitly.

**Test (headless)**
- `assets/scripts/tests/test_save_manager_register_distributes.lua`:
  - sets `SaveManager.cache = { foo = { x = 1 } }`
  - registers collector `foo` with a `distribute` spy
  - asserts `distribute` called once with `{x=1}`

**Acceptance**
- Test passes via `lua assets/scripts/tests/test_runner.lua --filter save_manager assets/scripts/tests`.

**Commit**: YES (run `just build-debug`)

---

## Phase 1: Foundation

### 1.1 Verify sprite filenames (research task)
**File**: `assets/graphics/sprites-0.json`

**Goal**
- Identify exact sprite filenames for:
  - border corners/edges/center fill (9-slice)
  - (optional) resource icons (food/wood/stone/gold)
  - structure sprites (decorative)

**Output**
- Create `assets/scripts/idle_game/ui/ascii_sprites.lua`:
  - `BORDER = { tl=..., t=..., tr=..., l=..., c=..., r=..., bl=..., b=..., br=... }`
  - `ICONS = { food=..., wood=..., stone=..., gold=... }` (omit keys that do not exist)
  - `STRUCTURES = { banner=..., statue=..., ... }` (minimum 3)

**Acceptance**
- Each referenced `filename` exists in `sprites-0.json` exactly once.
- If icons do not exist, panels must render text-only without errors.

**Commit**: NO

---

### 1.2 ASCII border component
**Files**
- add: `assets/scripts/idle_game/ui/ascii_border.lua`
- add test: `assets/scripts/tests/test_idle_ascii_border.lua`

**Contract**
- `ascii_border.layout({x, y, w, h, tile_size}) -> { tiles, pixels, interior }`
  - `x,y,w,h` are pixels and must be multiples of `tile_size`
  - `w >= 3*tile_size`, `h >= 3*tile_size` (to support corners + interior)
  - returns:
    - `tiles.w`, `tiles.h`
    - `pixels = {x,y,w,h}`
    - `interior = {x = x+tile, y = y+tile, w = w-2*tile, h = h-2*tile}`
- `ascii_border.draw(opts)`:
  - opts includes `layer_handle`, `space`, `z`, `sprites=BORDER`, `rect={x,y,w,h}`, optional tints
  - no-op if engine globals are unavailable (headless-safe)

**Test (headless)**
- Validates:
  - rejects non-aligned rects
  - rejects too-small rects
  - computes correct interior rect
  - returns correct number of edge/corner placements for a known size (e.g., 5×4 tiles)

**Acceptance**
- `lua assets/scripts/tests/test_runner.lua --filter ascii_border assets/scripts/tests` passes.

**Commit**: YES (run `just build-debug`)

---

### 1.3 Toast queue (headless-safe)
**Files**
- add: `assets/scripts/idle_game/ui/toast_queue.lua`
- add test: `assets/scripts/tests/test_idle_toast_queue.lua`

**API**
- `queue.init({max_visible=3, default_duration=3.0, max_buffer=32})`
- `queue.push(text, {duration=?})`
- `queue.update(dt)`
- `queue.get_visible() -> { {text, age, duration}, ... }`
- Behavior:
  - visible toasts are FIFO from the buffer
  - max `max_visible` returned
  - `max_buffer` drops oldest when exceeded
  - deterministic ordering

**Test (headless)**
- Simulates time progression and asserts:
  - auto-dismiss after duration
  - FIFO order preserved
  - buffer cap behavior

**Commit**: YES (run `just build-debug`)

---

### 1.4 Achievements core (TDD; headless-safe)
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
  - `update(dt)` (increments playtime; ignore negative dt)
  - `is_unlocked(id)`
  - `unlock(id) -> bool newly_unlocked`
  - `get_unlocked_ids() -> {id,...}` (sorted)
  - `serialize() -> table` and `deserialize(t)` (idempotent)
- Comparisons use `>=` and convert numeric totals with `math.floor` before comparing.

**Achievement list (12)**
- **Resources (4)**: `res_wood_100`, `res_stone_100`, `res_gold_25`, `res_total_500`
- **Upgrades (3)**: `upg_first_purchase`, `upg_any_level_5`, `upg_any_maxed`
- **Creatures (3)**: `crt_total_25`, `crt_specialists_10`, `crt_builder_exists`
- **Time (2)**: `time_5min`, `time_15min`

**Test (headless)**
- Covers:
  - unlocking returns true once
  - deterministic `get_unlocked_ids`
  - serialize/deserialize roundtrip
  - playtime thresholds (exact boundary)

**Commit**: YES (run `just build-debug`)

---

## Phase 2: UI Panels

### 2.1 ASCII resource panel
**Files**
- add: `assets/scripts/idle_game/ui/ascii_resource_panel.lua` (engine renderer; keep require-time headless-safe if imported elsewhere)

**Layout (fixed)**
- `x=0`, `y=0`, `w=10*TILE_SIZE`, `h=6*TILE_SIZE`
- Grid:
  - Row 1: header `RESOURCES`
  - Rows 2–5: Food/Wood/Stone/Gold + rate (e.g., `+1.2/s`)
  - Row 6: Foragers `N/MAX`

**Rendering**
- Uses `ascii_border`.
- Text draws in Screen space on UI layer (confirm layer name during 0.1).
- If icons exist, draw icon at col 1 and text at col 3; otherwise text-only.

**Acceptance (in-engine)**
- Panel is fully within world-left region; no overlap with sidebar.
- Values update live; no Lua errors.

**Commit**: YES (run `just ui-verify` before commit)

---

### 2.2 ASCII upgrade panel (scroll + click) — split model from renderer
**Files**
- add: `assets/scripts/idle_game/ui/ascii_upgrade_panel_model.lua` (headless-safe)
- add: `assets/scripts/idle_game/ui/ascii_upgrade_panel.lua` (engine renderer + input glue)
- add test: `assets/scripts/tests/test_idle_upgrade_panel_model.lua`

**Panel rect (authoritative)**
- `x = globals.screenWidth() - UI_SIDEBAR_W`, `y = 0`, `w = UI_SIDEBAR_W`, `h = globals.screenHeight()`
- Inside:
  - header height: `2*TILE_SIZE`
  - row height: `1*TILE_SIZE`
  - list rect: remaining height

**Ordering**
- Deterministic: sort upgrade IDs alphabetically (never rely on `pairs()`).

**Model API (headless-safe)**
- `model.build(upgrades_state) -> { ids_sorted, rows = {...} }`
- `model.scroll(state, delta_rows, view_rows, total_rows) -> new_scroll_row`
- `model.hit_test(click_x, click_y, rect, header_h, row_h, scroll_row, ids_sorted) -> {consumed, id?}`

**Input (engine)**
- Scroll changes `scroll_row` only when hovered.
- Click inside panel bounds always returns `consumed=true`.
- If click hits a row’s buy region and upgrade is purchasable, calls purchase.

**Acceptance (in-engine)**
- Clicking anywhere in sidebar never triggers world harvest/selection.
- Scroll reaches all upgrades and mapping is correct after scrolling.
- Purchase uses the same ordered list + scroll offset as rendering.

**Commit**: YES (run `just ui-verify` before commit)

---

### 2.3 Toast renderer (engine)
**Files**
- add: `assets/scripts/idle_game/ui/toast_renderer.lua` (engine only; depends on verified draw APIs)

**Rendering**
- Screen space; anchor bottom-right inside sidebar:
  - `x = globals.screenWidth() - UI_SIDEBAR_W`
  - `y = globals.screenHeight() - (max_visible * toast_h)`
- Toast size fixed: `UI_SIDEBAR_W × (2*TILE_SIZE)` each.
- Draw 1–3 toasts using `ascii_border` + text.

**Acceptance (in-engine)**
- Toasts appear, stack, and disappear without layout jitter.

**Commit**: YES (run `just ui-verify` before commit)

---

## Phase 3: Achievement Hooks + Listener (Hot-reload safe)

### 3.1 Emit gameplay signals (namespaced)
**Files**
- modify: `assets/scripts/idle_game/resources.lua`
- modify: `assets/scripts/idle_game/upgrades.lua`
- modify: `assets/scripts/idle_game/spawner.lua`

**Signals**
- `signal.emit("idle.resource_total", resource, new_total)` (emit on any total change)
- `signal.emit("idle.resource_added", resource, new_total, delta)` (delta > 0 only)
- `signal.emit("idle.upgrade_purchased", id, new_level)`
- `signal.emit("idle.creature_counts", counts_table)` (emit after spawn/despawn tick; includes specialists + total)

**Acceptance**
- No signal emission at require-time; only during gameplay updates.

**Commit**: YES (run `just build-debug`)

---

### 3.2 Achievement listener (dedup safe) + toast wiring
**Files**
- add: `assets/scripts/idle_game/achievement_listener.lua`
- add test: `assets/scripts/tests/test_idle_achievement_listener_dedup.lua`

**Mechanism**
- `local signal = require("external.hump.signal")`
- Use `core.signal_group` (or equivalent verified in 0.1) to register/unregister handlers.

**API**
- `init(toast_queue)` registers handlers once
- `shutdown()` unregisters handlers
- `update(dt)` forwards to `achievements.update(dt)` (or call achievements update from scene)

**Behavior**
- On each relevant signal, evaluate only the affected achievement subset (avoid O(N) on every tick).
- On newly unlocked achievement, enqueue toast text and return the unlock list (optional for persistence triggers).

**Acceptance**
- Calling `init()` twice results in exactly one set of handlers and one toast per unlock.
- Headless dedup test passes (mock signal group + emit events twice).

**Commit**: YES (run `just build-debug`)

---

## Phase 4: New Creatures + Terrain Extensions

### 4.0 Gate forager sensing + remove hardcoded TILE_SIZE (required)
**File**: `assets/scripts/ai/worldstate_updaters.lua`

**Changes**
- `forager_sensing`: early-return unless `require("idle_game.spawner")._foragers[entity] == true`.
- Replace any hardcoded `TILE_SIZE = 20` with `require("idle_game.config").TILE_SIZE`.

**Acceptance**
- Specialists do not run forager survival/harvest logic.
- No hardcoded tile size remains in touched files.

**Commit**: YES

---

### Common creature requirements (4.1–4.4)
**Files**
- modify: `assets/scripts/idle_game/spawner.lua`
- add AI files per type under:
  - `assets/scripts/ai/entity_types/`
  - `assets/scripts/ai/goal_selectors/`
  - `assets/scripts/ai/blackboard_init/`

**Spawner**
- Add tracking tables: `_miners`, `_lumberjacks`, `_collectors`, `_builders`
- Add count helpers:
  - `getMinerCount()`, `getLumberjackCount()`, `getCollectorCount()`, `getBuilderCount()`
  - `getTotalCreatureCount()`
  - `getSpecialistCount()`
- Emit `idle.creature_counts` after spawn/despawn maintenance.

**Updaters**
- Any per-type updater must early-return unless entity is in its tracking table.

---

### 4.1 Miner
**Behavior (specific)**
- Target rocks; on successful harvest, call the same resource add path as foragers but with multiplier:
  - `STONE_DELTA = base_forager_delta * 1.5` (rounded/floored consistently with resources)
- Harvest cadence: same tick rate as forager harvesting (do not introduce new timers unless required).

**Acceptance (in-engine)**
- With miners present and rocks on map: stone increases measurably faster than with equal number of foragers over 60 seconds.

**Commit**: YES

---

### 4.2 Lumberjack
**Behavior (specific)**
- Target trees; `WOOD_DELTA = base_forager_delta * 1.5` (rounded/floored consistently).

**Acceptance (in-engine)**
- With lumberjacks present and trees on map: wood increases measurably faster than with equal number of foragers over 60 seconds.

**Commit**: YES

---

### 4.3 Collector + ground items (transient)
**Files**
- modify: `assets/scripts/idle_game/terrain.lua` (add `_ground_items` + API)
- modify: `assets/scripts/ai/worldstate_updaters.lua` (collector sensing)
- add collector AI files + spawner integration
- add test: `assets/scripts/tests/test_idle_ground_items.lua`

**Ground item model**
- `_ground_items` is an array of `{id, tileX, tileY, kind, amount}`
- `id` is monotonically increasing per session (start at 1)

**Terrain API**
- `drop_item(tileX, tileY, kind, amount) -> id`
- `pickup_item(id) -> item_or_nil` (remove by id)
- `find_nearest_item(tileX, tileY, kind?) -> item_or_nil` (Manhattan distance; ties lowest id)
- Clear `_ground_items` inside `terrain.setCurrentGrid(grid)` (non-persisted).

**Collector behavior**
- Prefer nearest item; on pickup, convert to resources via the standard resource add path.

**Acceptance (in-engine)**
- Dropped items appear (optional render) and are collected; resources increase accordingly.

**Commit**: YES

---

### 4.4 Builder + structures (persisted)
**Files**
- modify: `assets/scripts/idle_game/terrain.lua` (add `_structures` + placement API)
- modify: `assets/scripts/idle_game/terrain_renderer.lua` (render structures above terrain)
- modify: `assets/scripts/idle_game/spawner.lua` (spawn + tracking + signal)
- add builder AI files
- add: `assets/scripts/idle_game/terrain_persistence.lua` (register SaveManager collector)

**Structure model**
- `_structures` list of `{tileX, tileY, sprite, tint?}`
- Placement rules:
  - only on walkable, empty tiles (no overlap with existing structure)
  - must be within world bounds
- Rendering:
  - draw after terrain and before corpses (or explicitly specify z ordering) so structures are visible and stable.

**Persistence**
- `SaveManager.register("idle_structures", collector)` in `terrain_persistence.lua`
- Collector:
  - `collect()` returns `_structures`
  - `distribute(data)` replaces `_structures` with validated list

**Acceptance (in-engine)**
- Builder places structures; save/reload restores them exactly.

**Commit**: YES

---

## Phase 5: Persistence + Integration

### 5.1 Achievement persistence
**Files**
- add: `assets/scripts/idle_game/achievements_persistence.lua` (SaveManager collector)
- modify (if needed): `assets/scripts/idle_game/achievements.lua` (ensure serialize/deserialize sufficient)

**Behavior**
- `SaveManager.register("idle_achievements", collector)`
- On new unlock: call `SaveManager.save()` with a simple debounce (e.g., only once per second) to avoid thrash.

**Acceptance (in-engine)**
- Unlock achievement → restart → still unlocked.

**Commit**: YES

---

### 5.2 Optional window size defaults (separate bead; only if requested)
**Files**
- modify: `assets/config.json`
- modify: `src/core/globals.cpp`

**Rules**
- Do not override user-provided window size CLI/config if present; only set defaults when unset.

**Acceptance**
- Fresh run opens at 800×600 by default.

**Commit**: YES

---

### 5.3 Integration verification pass (final)
**Checklist**
- Sidebar reserved; no overlap; UI rects are grid-aligned
- Resource panel renders and updates
- Upgrade panel scroll + buy works; no world click-through
- Toasts show and auto-dismiss; no duplicate handlers
- 4 specialists spawn and behave distinctly
- Achievements unlock across resource/upgrade/creature/time categories
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
- `idle_game.ui.toast_queue`
- `idle_game.achievement_listener`

### init()
- Initialize toast queue, panels, and listener.
- Replace `spawner.spawnForagers(20)` with fixed mixed initial set (20 total):
  - 12 foragers, 3 miners, 3 lumberjacks, 1 collector, 1 builder

### update(dt) (authoritative order)
1) world sim updates (existing)
2) spawner maintenance (existing; emits creature counts)
3) UI state updates:
   - upgrade panel scroll state
   - toast queue update
   - achievement listener update (playtime)
4) UI click handling:
   - if click inside any UI panel rect, consume and do not forward
5) world click handling:
   - call `input_module.handleClick(config)` only if not consumed

### draw() (authoritative order)
1) world: terrain → structures → corpses (confirm desired layering)
2) ASCII UI: resource panel → upgrade panel → toasts (Screen space, high z)
3) ImGui debug panel last

---

## Commit Strategy (Atomic)

- One feature per commit (viewport, SaveManager fix, border, toast queue, achievements, each panel, signals/listener, each creature, ground items, structures, persistence).
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