# Incremental Game ASCII UI & Content Expansion (PLAN v5 — Implementation-Ready)

## TL;DR

Replace the idle game’s ImGui-only gameplay UI with **grid-aligned ASCII panels** rendered via `command_buffer` (CP437/dungeon-style sprite atlas), add **4 specialist creature types** (Miner, Lumberjack, Collector, Builder), and implement a **persisted achievement system** with **toast notifications**.

**Primary Deliverables**
- ASCII border component (9-slice via sprite atlas)
- ASCII resource panel (top-left, grid-aligned, click-blocking)
- ASCII upgrade panel (right sidebar, scroll + clickable buy, click-blocking)
- Toast notifications (queue + auto-dismiss; achievement-driven)
- Achievements (12 total; persisted)
- Creatures: Miner, Lumberjack, Collector, Builder (spawned at start)
- Collector ground-item system (transient, non-persisted)
- Builder decorative structures system (persisted)

**Critical Path**
1) Lock layout + input contract (screen/world spaces + sidebar reservation)
2) Border → panels → input routing (no world-click bleedthrough)
3) Achievements core → signals/listener → toasts → persistence
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
- Signals + listeners strictly namespaced to idle-game

**Out of scope**
- Refactoring the general UI DSL system
- Reworking idle_game legacy gameplay (`assets/scripts/idle_game/legacy/gameplay.lua`)
- Full game-wide achievements system (idle-game only)
- Balance rework beyond specified multipliers/costs

---

## Definitions (Authoritative)

### Coordinate spaces
- **Screen space**: UI coordinates in `globals.screenWidth()/globals.screenHeight()` (virtual screen coords used for UI).
- **World space**: camera-relative world rendering / world interaction.

### Key values
- `TILE_SIZE` = `require("idle_game.config").TILE_SIZE` (**must be used everywhere; never hardcode `20`**)
- `IDLE_WORLD_W/H` = `config.VIRTUAL_WIDTH/config.VIRTUAL_HEIGHT` (expected 600×400 virtual)
- `ENGINE_SCREEN_W/H` = `globals.screenWidth()/globals.screenHeight()`
- **UI sidebar width**: `UI_SIDEBAR_W = 10 * TILE_SIZE` (200px when TILE_SIZE=20)

### Resource keys (used in signals, UI, achievements)
- `food`, `wood`, `stone`, `gold`

### Layout rules (hard requirements)
1) ASCII UI draws in **Screen space** (verified identifiers recorded in “Reference Index”).
2) Idle world draws in **World space**.
3) All UI rectangles must be aligned to tile grid: `x,y,w,h` multiples of `TILE_SIZE`.
4) A click inside any UI panel rectangle must **never** trigger world harvesting/selection.
5) Mouse wheel scrolling affects the upgrade panel **only** when hovered inside the upgrade panel rect.

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
- `assets/scripts/tests/test_idle_upgrade_panel_model.lua`
- `assets/scripts/tests/test_idle_achievement_listener_dedup.lua`
- `assets/scripts/tests/test_idle_achievement_listener_unlocks.lua`
- `assets/scripts/tests/test_idle_structures_persistence.lua`
- `assets/scripts/tests/test_save_manager_register_distributes.lua`
- `assets/scripts/tests/test_idle_resources_try_spend.lua` (only if 0.4 finds no existing spend helper)

---

## Parallelization Plan (Explicit Dependencies + File-Conflict Notes)

**Wave 0 (Gating; must land first)**
- 0.1 Verify engine bindings + draw/input APIs (documentation-only unless mismatch)
- 0.2 Implement world viewport (sidebar reservation) — touches `sim_scene.lua`
- 0.3 Fix SaveManager collector late-registration distribution — touches `save_manager.lua`
- 0.4 Verify idle_game module contracts (resources/upgrades/spawner/terrain) — documentation-only unless mismatch
- 0.5 Verify AI integration points for new entity types (spawner + AI file naming) — documentation-only

**Wave 1 (Shared foundation; parallel after 0.1/0.4/0.5 findings)**
- 1.1 Confirm sprite filenames (atlas) + add `ascii_sprites.lua` — new file
- 1.2 ASCII border component (+ tests) — new files, low conflict
- 1.3 Toast queue (headless) (+ tests) — new files, low conflict
- 1.4 Achievements core (headless) (+ tests) — new files, low conflict

**Wave 2 (UI; depends on Wave 0 + 1.1 + 1.2)**
- 2.1 Resource panel renderer — new file; integrates into `sim_scene.lua`
- 2.2 Upgrade panel model (+ tests) + renderer — new files; integrates into `sim_scene.lua`
- 2.3 Toast renderer + wiring — new file; integrates into `sim_scene.lua`

**Wave 3 (Signals + listener; depends on Wave 1.3 + 1.4, and Wave 0.4 contract findings)**
- 3.1 Emit signals — modifies `resources.lua`, `upgrades.lua`, `spawner.lua`
- 3.2 Achievement listener (dedup-safe, unlock eval) (+ tests) — new file; integrates into `sim_scene.lua`
- 3.3 Toasts on unlock — mostly wiring

**Wave 4 (Specialists + terrain; can proceed after Wave 0.4 + 0.5; independent of UI)**
- 4.0 Gate forager sensing; remove hardcoded TILE_SIZE — modifies `worldstate_updaters.lua`
- 4.1 Miner — modifies `spawner.lua` + new AI files
- 4.2 Lumberjack — modifies `spawner.lua` + new AI files
- 4.3 Collector + ground items (+ tests) — modifies `terrain.lua`, `worldstate_updaters.lua`
- 4.4 Builder + structures (+ persistence) — modifies `terrain.lua`, `terrain_renderer.lua`, `spawner.lua` + new persistence file (+ test)

**Wave 5 (Persistence + integration; depends on Waves 2–4)**
- 5.1 Achievement persistence (SaveManager collector) — new file + wiring
- 5.2 Optional window size defaults (separate bead; only if requested)
- 5.3 Integration verification pass — manual + CI commands

---

## Phase 0: Gating Tasks

### 0.1 Verify engine bindings + rendering/input APIs (no code changes unless mismatch found)
**Goal**: ensure plan’s draw and input calls match real bindings before any renderer work.

**Checks (must produce concrete findings)**
- Confirm which API draws sprites and text in Screen space (exact function names on `command_buffer`).
- Confirm how to acquire a UI layer handle for Screen space rendering (exact layer name / lookup call).
- Confirm mouse position API and coordinate system:
  - mouse pos return type and units
  - mouse wheel API name and sign convention
  - left-click pressed API and button enum/value
- Confirm world-mouse conversion API and whether it uses screen mouse coordinates.

**Output**
- Fill “Reference Index” verified identifiers for:
  - UI layer lookup
  - `command_buffer` sprite draw
  - `command_buffer` text draw
  - mouse pos / wheel delta / mouse pressed
  - mouse world conversion

**Acceptance**
- “Reference Index” contains verified, copy/paste-ready identifiers for the implementation.

---

### 0.2 Reserve world viewport for sidebar (required)
**File**: `assets/scripts/idle_game/scenes/sim_scene.lua`

**Change**
- Update camera zoom/offset math to reserve `UI_SIDEBAR_W = 10 * TILE_SIZE` on the right.
- Store:
  - `sim_scene._world_view_w` (pixels)
  - `sim_scene._ui_sidebar_w` (pixels)
  - `sim_scene._tile_size` (from config)

**Authoritative math**
- `WORLD_VIEW_W = globals.screenWidth() - UI_SIDEBAR_W`
- `zoomX = WORLD_VIEW_W / config.VIRTUAL_WIDTH`
- `zoomY = globals.screenHeight() / config.VIRTUAL_HEIGHT`
- `zoom = math.min(zoomX, zoomY)`
- Center camera within left region:
  - `cam:SetActualOffset(WORLD_VIEW_W / 2, globals.screenHeight() / 2)`

**Acceptance (in-engine manual)**
- Rightmost `UI_SIDEBAR_W` pixels contain no world tiles at any zoom.
- At **physical** window sizes 600×400 and 800×600:
  - world is centered within the left region
  - world content is fully visible (no unintended crop beyond existing behavior)

**Commit**: YES (run `just build-debug`)

---

### 0.3 SaveManager: distribute cached data to late-registered collectors (required)
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
  - asserts `distribute` called exactly once with `{x=1}`

**Acceptance**
- Test passes via `lua assets/scripts/tests/test_runner.lua --filter save_manager assets/scripts/tests`.

**Commit**: YES (run `just build-debug`)

---

### 0.4 Verify idle_game module contracts (resources/upgrades/spawner/terrain) (documentation-only unless mismatch found)
**Goal**: remove ambiguity about resource spend semantics, upgrade purchase API, and max-level lookup before UI + AI changes.

**Files to inspect**
- `assets/scripts/idle_game/resources.lua`
- `assets/scripts/idle_game/upgrades.lua`
- `assets/scripts/idle_game/spawner.lua`
- `assets/scripts/idle_game/terrain.lua`

**Contract findings to record in “Reference Index” (exact identifiers + return shapes)**
- Resources:
  - read totals (exact function / shape)
  - add delta (supports negative? return bool? exact)
  - spend/afford helper (if exists) and its return shape
  - if no spend helper exists, record the minimal safe contract to implement:
    - `resources.can_afford(costs_table) -> bool`
    - `resources.try_spend(costs_table) -> bool` (atomic; no partial spending)
- Upgrades:
  - list/definitions source (IDs, titles)
  - purchase attempt API + return shape
  - level query API
  - max level query (field or function)
- Spawner:
  - how current creatures are tracked (foragers table keying), how to spawn mixed initial set
  - how to get current counts and (if needed) max foragers
- Terrain:
  - tile coordinate conventions used by current harvesting logic (`tileX/tileY` ints vs world coords)
  - walkable / occupied checks usable by builder placement

**If mismatches found**
- Update plan sections that name APIs to match reality.
- Only add new helpers if required; add headless tests if logic is non-trivial.

**Acceptance**
- “Reference Index” includes verified, copy/paste-ready identifiers for:
  - resource totals + add + spend/afford (existing or newly defined)
  - upgrade list + purchase + level + max
  - spawner spawn mixed set + count access points
  - terrain validation helpers for structure placement

---

### 0.5 Verify AI integration points (documentation-only unless mismatch found)
**Goal**: remove ambiguity about where to add new entity types and how spawner selects AI behaviors.

**Files to inspect**
- `assets/scripts/ai/entity_types/` (current patterns)
- `assets/scripts/ai/goal_selectors/` (current patterns)
- `assets/scripts/ai/blackboard_init/` (current patterns)
- `assets/scripts/idle_game/spawner.lua` (how entities are created / typed)

**Output**
- Fill “Reference Index” with:
  - the exact “entity type id/name” field that spawner sets
  - the exact file naming convention used for entity types/goal selectors/blackboard init
  - the exact mechanism that links an entity to its AI modules

**Acceptance**
- “Reference Index” contains copy/paste-ready guidance for adding 4 new types without guesswork.

---

## Phase 1: Foundation

### 1.1 Verify sprite filenames (atlas mapping)
**File**: `assets/graphics/sprites-0.json`

**Goal**
- Identify exact sprite filenames for:
  - border corners/edges/center fill (9-slice)
  - (optional) resource icons (food/wood/stone/gold)
  - structure sprites (decorative; minimum 3)

**Output**
- Add `assets/scripts/idle_game/ui/ascii_sprites.lua` exporting:
  - `BORDER = { tl=..., t=..., tr=..., l=..., c=..., r=..., bl=..., b=..., br=... }`
  - `ICONS = { food=..., wood=..., stone=..., gold=... }` (omit missing keys)
  - `STRUCTURES = { s1=..., s2=..., s3=... }` (keys stable; values are filenames)
  - `STRUCTURE_CYCLE = { STRUCTURES.s1, STRUCTURES.s2, STRUCTURES.s3 }` (skip nils; preserve this order)

**Acceptance**
- Each referenced `filename` exists in `sprites-0.json` exactly once.
- If `ICONS` missing any resource, UI renders text-only without errors.

**Commit**: YES (run `just build-debug`)

---

### 1.2 ASCII border component
**Files**
- add: `assets/scripts/idle_game/ui/ascii_border.lua`
- add test: `assets/scripts/tests/test_idle_ascii_border.lua`

**Contract**
- `ascii_border.layout({x, y, w, h, tile_size}) -> { tiles, pixels, interior }`
  - `x,y,w,h` are pixels and must be multiples of `tile_size`
  - `w >= 3*tile_size`, `h >= 3*tile_size`
  - returns:
    - `tiles.w`, `tiles.h` (tile counts)
    - `pixels = {x,y,w,h}`
    - `interior = {x = x+tile, y = y+tile, w = w-2*tile, h = h-2*tile}`
- `ascii_border.draw(opts)`:
  - opts includes `layer_handle`, `space`, `z`, `sprites`, `rect={x,y,w,h}`, optional tints
  - headless-safe: no-op if required engine globals are unavailable

**Test (headless)**
- Validates:
  - rejects non-aligned rects
  - rejects too-small rects
  - computes correct interior rect
  - returns correct tile counts for a known size (e.g., 5×4 tiles)

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

**Behavior**
- Visible toasts are FIFO from the buffer.
- At most `max_visible` returned.
- Buffer cap: if `max_buffer` exceeded, drop oldest buffered entries first.
- Deterministic ordering (no `pairs()` ordering dependencies).
- `update(dt)` ignores negative `dt`.

**Test (headless)**
- Simulates time progression and asserts:
  - auto-dismiss after duration boundary (exactly at `>= duration`)
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
- Definition schema (authoritative):
  - `definition = { id, title, kind, threshold? }`
  - `kind` in: `resource_total`, `resource_sum`, `upgrade_purchase`, `upgrade_level`, `upgrade_maxed`, `creature_total`, `creature_specialists`, `creature_builder`, `time`
- State:
  - `_definitions` (id → definition)
  - `_unlocked` (id → true)
  - `_playtime_seconds`
- Public API:
  - `update(dt)` (increments playtime; ignore negative dt)
  - `is_unlocked(id)`
  - `unlock(id) -> bool newly_unlocked`
  - `get_unlocked_ids() -> {id,...}` (sorted)
  - `get_title(id) -> title_or_nil`
  - `serialize() -> table` and `deserialize(t)`:
    - serialize includes unlocked ids and playtime seconds
    - deserialize is idempotent; unknown ids ignored
- Numeric comparisons:
  - when comparing thresholds, coerce inputs with `math.floor` before `>=` comparisons

**Achievement list (12)**
- **Resources (4)**:
  - `res_wood_100` title `Wood Hoarder` (wood total >= 100)
  - `res_stone_100` title `Stone Stockpile` (stone total >= 100)
  - `res_gold_25` title `Shiny Things` (gold total >= 25)
  - `res_total_500` title `Full Pantry` (sum `food+wood+stone+gold` totals >= 500)
- **Upgrades (3)**
  - `upg_first_purchase` title `First Upgrade` (any upgrade purchased at least once)
  - `upg_any_level_5` title `Level Five` (any single upgrade level >= 5)
  - `upg_any_maxed` title `Maxed Out` (any single upgrade at max level; “max” per 0.4)
- **Creatures (3)**
  - `crt_total_25` title `Growing Crew` (total creatures >= 25)
  - `crt_specialists_10` title `Specialized` (miners+lumberjacks+collectors+builders >= 10)
  - `crt_builder_exists` title `Architect` (builder count >= 1)
- **Time (2)**
  - `time_5min` title `Five Minutes` (playtime >= 300s)
  - `time_15min` title `Quarter Hour` (playtime >= 900s)

**Test (headless)**
- Covers:
  - unlocking returns true once
  - deterministic `get_unlocked_ids` sorting
  - serialize/deserialize roundtrip (includes playtime)
  - playtime thresholds (exact boundary)
  - `res_total_500` uses defined sum semantics
  - `get_title` returns expected title

**Commit**: YES (run `just build-debug`)

---

## Phase 2: UI Panels (ASCII)

### Common panel input contract (required)
**Rule**
- Every interactive UI module must expose:
  - `get_rect(tile_size) -> {x,y,w,h}` (screen-space pixels, grid-aligned)
  - `hit_test(mx, my, opts) -> {consumed, action?, id?}` where:
    - `consumed=true` for any click inside the module’s rect
    - `action/id` only when a meaningful action occurs (e.g., buy)

**Acceptance**
- `sim_scene.update(dt)` can block world clicks using only these return values (no duplicated rect math in multiple places).

---

### 2.1 ASCII resource panel (renderer)
**Files**
- add: `assets/scripts/idle_game/ui/ascii_resource_panel.lua` (engine renderer; headless-safe at require-time)

**Layout (fixed; grid-aligned)**
- `x=0`, `y=0`, `w=10*TILE_SIZE`, `h=6*TILE_SIZE`

**API**
- `get_rect(tile_size)`
- `update(dt, totals)` (pure logic; totals from resources)
- `draw(opts)` (engine-only draw; safe no-op if engine missing)
- `hit_test(mx, my, tile_size) -> {consumed=true/false}` (always consumes inside rect; no actions)

**Rates (authoritative; no new global dependencies)**
- Maintain `prev_totals[key]` and `accum_dt`.
- Each update:
  - `accum_dt += max(dt, 0)`
  - when `accum_dt >= 1.0`, compute `rate[key] = (totals[key] - prev_totals[key]) / accum_dt`, then reset `prev_totals=totals` and `accum_dt=0`
- Display format: `+X.Y/s` (one decimal). Clamp `-0.0` to `0.0`.

**Content grid**
- Row 1: header `RESOURCES`
- Rows 2–5: `Food/Wood/Stone/Gold` + total + rate
- Row 6: `FORAGERS N/MAX` (from spawner state per 0.4)

**Rendering**
- Uses `ascii_border` and `ascii_sprites` (icons optional).
- Text draws in Screen space on UI layer (layer identifier from 0.1).
- If icon exists for a resource:
  - icon at column 1
  - text begins at column 3
- Else: text begins at column 1

**Acceptance (in-engine manual)**
- Panel renders without errors at 600×400 and 800×600.
- Values update live while sim runs.
- Rates change over time and are stable (no NaN/inf).
- Clicking inside the resource panel never triggers world harvest/selection.

**Commit**: YES (run `just ui-verify` before commit)

---

### 2.2 ASCII upgrade panel (scroll + click) — split model from renderer
**Files**
- add: `assets/scripts/idle_game/ui/ascii_upgrade_panel_model.lua` (headless-safe)
- add: `assets/scripts/idle_game/ui/ascii_upgrade_panel.lua` (engine renderer + input glue; headless-safe at require-time)
- add test: `assets/scripts/tests/test_idle_upgrade_panel_model.lua`

**Panel rect (authoritative)**
- `x = globals.screenWidth() - UI_SIDEBAR_W`, `y = 0`, `w = UI_SIDEBAR_W`, `h = globals.screenHeight()`
- Inside:
  - `header_h = 2*TILE_SIZE`
  - `row_h = 1*TILE_SIZE`
  - `buy_w = 3*TILE_SIZE` (rightmost 3 tiles are the buy button region)
  - `list_rect = { x, y+header_h, w, h-header_h }`

**Ordering**
- Deterministic: sort upgrade IDs alphabetically (never rely on `pairs()`).

**Row format (authoritative, to support deterministic hit-testing)**
- For each visible row:
  - left area: upgrade name + level text (renderer-defined)
  - right area (`buy_w`): `[BUY]` if purchasable, `[MAX]` if maxed, `[—]` otherwise

**Model API (headless-safe)**
- `model.sorted_ids(upgrades_state_or_defs) -> {id,...}` (alphabetical; per 0.4 discovery)
- `model.view_rows(list_h, row_h) -> n_view_rows` (floor)
- `model.scroll(scroll_row, delta_rows, view_rows, total_rows) -> new_scroll_row` (clamped)
- `model.row_at(click_x, click_y, rect, header_h, row_h, scroll_row, total_rows) -> {in_list, row_index?}` (row_index is absolute index in ids list)
- `model.hit_test(click_x, click_y, rect, header_h, row_h, buy_w, scroll_row, ids_sorted) -> {consumed, id?, action?}`
  - `consumed=true` for any click inside `rect`
  - `action` is `"buy"` only when click lands inside buy region and the row exists; else nil

**Renderer/API**
- `get_rect(tile_size)`
- `update_hover(mx,my)` (optional)
- `scroll_by_wheel(wheel_delta)` only when hovered (per Layout rules)
- `hit_test(mx,my) -> {consumed, action?, id?}` (calls model)
- `draw(opts)` draws rows using the same `ids_sorted + scroll_row` used for hit-testing.

**Input (engine)**
- On `{action="buy", id=...}`: attempt purchase via upgrades purchase API verified in 0.4.

**Test (headless)**
- Validates:
  - stable alphabetical ordering
  - scroll clamp at top/bottom
  - hit-test maps clicks to correct `id` before/after scrolling
  - buy-region detection via `buy_w`

**Acceptance (in-engine manual)**
- Clicking anywhere in sidebar never triggers world harvest/selection.
- Scroll reaches all upgrades and click mapping remains correct after scrolling.
- Buy button triggers only when clicking in rightmost `buy_w`.

**Commit**: YES (run `just ui-verify` before commit)

---

### 2.3 Toast renderer (engine)
**Files**
- add: `assets/scripts/idle_game/ui/toast_renderer.lua` (engine only; depends on 0.1 verified draw APIs)

**Layout**
- Screen space; anchored inside sidebar with 1-tile padding:
  - `pad = TILE_SIZE`
  - `toast_w = UI_SIDEBAR_W - 2*pad`
  - `toast_h = 2*TILE_SIZE`
  - `x = globals.screenWidth() - UI_SIDEBAR_W + pad`
  - `y_base = globals.screenHeight() - pad`
- For `i=1..max_visible`: toast `i` draws with bottom alignment:
  - `y = y_base - i*toast_h`

**Text format (authoritative)**
- Achievement unlock toast: `ACHIEVEMENT: <Title>` (Title from `achievements.get_title(id)`; fallback to id)

**Acceptance (in-engine manual)**
- Toasts stack up to `max_visible`, appear/disappear without jitter, and never overlap outside sidebar.

**Commit**: YES (run `just ui-verify` before commit)

---

## Phase 3: Achievement Hooks + Listener (Hot-reload safe)

### 3.1 Emit gameplay signals (namespaced)
**Files**
- modify: `assets/scripts/idle_game/resources.lua`
- modify: `assets/scripts/idle_game/upgrades.lua`
- modify: `assets/scripts/idle_game/spawner.lua`

**Signals (authoritative payloads)**
- Use `local signal = require("external.hump.signal")` inside emitters (no globals).
- `signal.emit("idle.resource_total", resource_key, new_total_int)`
  - emit on any total change (including from ground-item conversion)
- `signal.emit("idle.resource_added", resource_key, new_total_int, delta_int)`
  - emit only when `delta_int > 0`
- `signal.emit("idle.upgrade_purchased", upgrade_id, new_level_int)`
- `signal.emit("idle.creature_counts", counts_table)`
  - `counts_table = { total=..., foragers=..., miners=..., lumberjacks=..., collectors=..., builders=..., specialists=... }`
  - emit after spawn/despawn maintenance tick and after initial spawn mix is complete

**If needed (per 0.4)**
- If no safe spend helper exists, add:
  - `resources.can_afford(costs) -> bool`
  - `resources.try_spend(costs) -> bool` (atomic; emits `idle.resource_total` for any changed resource)
- Add headless test `assets/scripts/tests/test_idle_resources_try_spend.lua`.

**Acceptance**
- No signal emission at require-time; only during gameplay updates.
- Payload shapes match above exactly.

**Commit**: YES (run `just build-debug`)

---

### 3.2 Achievement listener (dedup safe) + toast wiring + unlock evaluation
**Files**
- add: `assets/scripts/idle_game/achievement_listener.lua`
- add test: `assets/scripts/tests/test_idle_achievement_listener_dedup.lua`
- add test: `assets/scripts/tests/test_idle_achievement_listener_unlocks.lua`

**Mechanism**
- `local signal = require("external.hump.signal")`
- Use an explicit “group” abstraction to ensure hot-reload safe unregister:
  - Prefer existing `core.signal_group` if verified in 0.1/0.4.
  - If missing, add `assets/scripts/idle_game/signal_group.lua` and use that (headless-safe).

**API (authoritative; no ambiguity)**
- `init(toast_queue)` registers handlers once (idempotent) and performs an initial `refresh_and_evaluate()` using module getters (resources/upgrades/spawner) so achievements can unlock immediately even if no signals fire at startup.
- `shutdown()` unregisters handlers
- `update(dt)` calls `achievements.update(dt)` exactly once per frame and evaluates time achievements

**Evaluation rules (performance + determinism)**
- Maintain minimal counters/state in listener for:
  - resource totals (per key)
  - any-upgrade-purchased flag
  - per-upgrade levels + max levels (max-level source per 0.4)
  - creature counts snapshot
- On each relevant signal, evaluate only the achievements that depend on that signal type.
- On newly unlocked achievement:
  - enqueue toast via `toast_queue.push("ACHIEVEMENT: <Title>", {duration=?})`
  - mark a `pending_save=true` flag for persistence debounce

**Persistence debounce integration point**
- Listener maintains `save_debounce_dt` and calls `SaveManager.save()` only when `pending_save==true` and `save_debounce_dt >= 1.0` (dt-accumulated; no absolute clock dependency).

**Tests (headless)**
- Dedup test:
  - calling `init()` twice registers only one effective handler set; emitting events twice yields one toast per unlock.
- Unlock test:
  - simulate signal events crossing thresholds and assert corresponding achievement IDs unlock and toast text is queued exactly once.

**Commit**: YES (run `just build-debug`)

---

## Phase 4: New Creatures + Terrain Extensions

### 4.0 Gate forager sensing + remove hardcoded TILE_SIZE (required)
**File**: `assets/scripts/ai/worldstate_updaters.lua`

**Changes**
- `forager_sensing`: early-return unless the entity is classified as a forager using the spawner’s verified tracking mechanism (per 0.4; `_foragers[entity]==true` only if that is confirmed correct).
- Replace any hardcoded `TILE_SIZE = 20` with `require("idle_game.config").TILE_SIZE`.

**Acceptance**
- Specialists do not run forager survival/harvest logic.
- No hardcoded tile size remains in touched files.

**Commit**: YES (run `just build-debug`)

---

### Common creature requirements (4.1–4.4)
**Files**
- modify: `assets/scripts/idle_game/spawner.lua`
- add AI files per type under (per 0.5 verified naming):
  - `assets/scripts/ai/entity_types/`
  - `assets/scripts/ai/goal_selectors/`
  - `assets/scripts/ai/blackboard_init/`

**Spawner**
- Add tracking tables: `_miners`, `_lumberjacks`, `_collectors`, `_builders`
- Add count helpers:
  - `getMinerCount()`, `getLumberjackCount()`, `getCollectorCount()`, `getBuilderCount()`
  - `getTotalCreatureCount()`, `getSpecialistCount()`
- Emit `idle.creature_counts` after spawn/despawn maintenance and after initial spawn mix.

**Updaters**
- Any per-type updater must early-return unless entity is in its tracking table.

---

### 4.1 Miner
**Behavior (specific)**
- Targets rocks; on successful harvest:
  - add stone via resources add API verified in 0.4, multiplier:
    - `STONE_DELTA = math.floor(base_forager_delta * 1.5)`
  - additionally drop a ground item for collectors:
    - `terrain.drop_item(tileX, tileY, "stone", math.max(1, math.floor(STONE_DELTA * 0.25)))`
- `base_forager_delta` must be sourced from the same value/path the forager harvesting uses (identified in 0.4); do not duplicate constants.

**Acceptance (in-engine manual)**
- With miners present and at least one rock on the map:
  - per-harvest stone gain from miner is >= per-harvest stone gain from a forager (by the multiplier rule above)
  - collector picks up dropped stone items and increases stone totals further

**Commit**: YES (run `just build-debug`)

---

### 4.2 Lumberjack
**Behavior (specific)**
- Targets trees; on successful harvest:
  - `WOOD_DELTA = math.floor(base_forager_delta * 1.5)`
  - drop ground item:
    - `terrain.drop_item(tileX, tileY, "wood", math.max(1, math.floor(WOOD_DELTA * 0.25)))`
- `base_forager_delta` must be sourced from the same value/path the forager harvesting uses (identified in 0.4).

**Acceptance (in-engine manual)**
- With lumberjacks present and at least one tree on the map:
  - per-harvest wood gain from lumberjack is >= per-harvest wood gain from a forager
  - collector picks up dropped wood items and increases wood totals further

**Commit**: YES (run `just build-debug`)

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
- `tileX/tileY` are integer tiles (floor any inputs on drop)
- `kind` must be one of `food/wood/stone/gold` (invalid kinds rejected)

**Terrain API**
- `drop_item(tileX, tileY, kind, amount) -> id_or_nil`
  - rejects non-positive amount; returns nil on invalid
- `pickup_item(id) -> item_or_nil` (remove by id)
- `find_nearest_item(tileX, tileY, kind?) -> item_or_nil`
  - Manhattan distance; ties: lowest distance, then lowest id
- Clear `_ground_items` inside `terrain.setCurrentGrid(grid)` (non-persisted).
- Do **not** clear `_structures` in `setCurrentGrid` (structures are persisted).

**Collector behavior**
- Prefer nearest item (any kind); on pickup:
  - convert to resources via resources add API verified in 0.4 (delta = item.amount)
  - no direct resource gain without pickup (ground items are the source of truth for the dropped portion)

**Test (headless)**
- Validates:
  - drop assigns increasing ids
  - find_nearest tie-break by id
  - pickup removes item
  - clearing on `setCurrentGrid`

**Acceptance (in-engine manual)**
- Items dropped by miners/lumberjacks exist in terrain state and are collected over time; totals increase when collected.

**Commit**: YES (run `just build-debug`)

---

### 4.4 Builder + structures (persisted)
**Files**
- modify: `assets/scripts/idle_game/terrain.lua` (add `_structures` + placement API)
- modify: `assets/scripts/idle_game/terrain_renderer.lua` (render structures above terrain)
- modify: `assets/scripts/idle_game/spawner.lua` (spawn + tracking + signal)
- add builder AI files
- add: `assets/scripts/idle_game/terrain_persistence.lua` (register SaveManager collector)
- add test: `assets/scripts/tests/test_idle_structures_persistence.lua`

**Structure model**
- `_structures` list of `{tileX, tileY, sprite, tint?}`
- Placement rules:
  - only on walkable, empty tiles (no overlap with existing structure) using terrain helpers verified in 0.4
  - within world bounds
  - sprite must be one of `ascii_sprites.STRUCTURE_CYCLE`; invalid rejected

**Terrain API**
- `place_structure(tileX, tileY, sprite, tint?) -> bool` (validates + inserts exactly once)
- `get_structures() -> list` (read-only or copy; used by renderer/persistence)

**Builder behavior (specific + deterministic)**
- Every `BUILD_INTERVAL = 20` seconds:
  - if `wood >= 50` and `stone >= 25`, spend using the resources spend path verified in 0.4 (must be atomic)
  - place exactly one structure on the nearest valid empty tile within Manhattan radius 10 of builder
    - ties: lowest distance, then lowest `tileY`, then lowest `tileX`
  - structure sprite chosen deterministically by cycling through `ascii_sprites.STRUCTURE_CYCLE`
- Builder does not place if no valid tile found or insufficient resources.

**Rendering**
- draw after terrain and before corpses (or explicitly specify z ordering) so structures are visible and stable.

**Persistence**
- `SaveManager.register("idle_structures", collector)` in `terrain_persistence.lua`
- Collector:
  - `collect()` returns a serializable structure list (no function values)
  - `distribute(data)` replaces `_structures` with validated list (invalid entries dropped)

**Test (headless)**
- Ensures distribute drops invalid entries (out of bounds, invalid sprite) and preserves valid ones.

**Acceptance (in-engine manual)**
- Builder places structures periodically once resources available.
- Save/reload restores structures exactly (tile positions + sprite + tint).

**Commit**: YES (run `just build-debug`)

---

## Phase 5: Persistence + Integration

### 5.1 Achievement persistence
**Files**
- add: `assets/scripts/idle_game/achievements_persistence.lua` (SaveManager collector)
- modify (if needed): `assets/scripts/idle_game/achievements.lua`
- wiring expected in: `assets/scripts/idle_game/scenes/sim_scene.lua`

**Behavior**
- `SaveManager.register("idle_achievements", collector)`
- Collector:
  - `collect()` returns `achievements.serialize()`
  - `distribute(data)` calls `achievements.deserialize(data)`
- Saves are triggered by the achievement listener debounce (Phase 3.2); no additional timers.

**Acceptance (in-engine manual)**
- Unlock achievement → restart → still unlocked.
- No save spam while unlocking multiple achievements rapidly.

**Commit**: YES (run `just build-debug`)

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
- Resource panel renders and updates; clicking inside consumes
- Upgrade panel scroll + buy works; no world click-through; wheel only when hovered
- Toasts show and auto-dismiss; no duplicate handlers; text format matches spec
- 4 specialists spawn and behave distinctly (miner/lj faster harvest; collector picks ground items; builder places structures)
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
- plus persistence modules to ensure collectors register:
  - `idle_game.achievements_persistence`
  - `idle_game.terrain_persistence`

### init()
- Initialize toast queue, panels, and listener (listener receives toast queue).
- Replace `spawner.spawnForagers(20)` with fixed mixed initial set (20 total):
  - 12 foragers, 3 miners, 3 lumberjacks, 1 collector, 1 builder
- Ensure `idle.creature_counts` emits after initialization completes (explicit maintenance tick if required).

### update(dt) (authoritative order)
1) world sim updates (existing)
2) spawner maintenance (existing; emits creature counts)
3) UI state updates:
   - resource panel `update(dt, totals)`
   - upgrade panel hover/scroll state
   - toast queue update
   - achievement listener update (includes `achievements.update(dt)`)
4) UI click handling:
   - compute mouse pos once (screen space)
   - if click inside resource panel `hit_test` OR upgrade panel `hit_test`, consume and do not forward
   - if upgrade panel returns `{action="buy", id=...}`, attempt purchase
5) world click handling:
   - call `input_module.handleClick(config)` only if not consumed

### draw() (authoritative order)
1) world: terrain → structures → corpses (confirm desired layering)
2) ASCII UI: resource panel → upgrade panel → toasts (Screen space, high z)
3) ImGui debug panel last

---

## Commit Strategy (Atomic)

- One feature per commit (viewport, SaveManager fix, sprites mapping, border, toast queue, achievements, each panel, signals/listener, each creature, ground items, structures + persistence, achievements persistence).
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

**(Fill during 0.1)** Verified identifiers:
- UI layer lookup:
- `command_buffer` sprite draw:
- `command_buffer` text draw:
- mouse pos:
- wheel delta:
- mouse pressed:
- mouse world:

**(Fill during 0.4)** Verified identifiers:
- resource totals read:
- resource add:
- resource spend/afford (if any):
- upgrades list/defs:
- upgrades purchase:
- upgrades level read:
- upgrades max level read:
- spawner spawn mixed set:
- spawner counts read:
- terrain walkable check:
- terrain occupied/structure check:

**(Fill during 0.5)** Verified identifiers:
- entity type naming/id field:
- entity type file naming convention:
- goal selector wiring:
- blackboard init wiring: