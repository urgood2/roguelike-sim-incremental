# Bulk Bead Import for Incremental ASCII UI Plan

<!-- Phase 0: Gating Tasks -->

## [task] 0.1.1 Identify UI layer lookup API
Research and document the exact API for acquiring UI layer handle for Screen space rendering.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.1.2 Verify command_buffer sprite draw API
Document exact function signature for drawing sprites via command_buffer in Screen space.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.1.3 Verify command_buffer text draw API
Document exact function signature for drawing text via command_buffer in Screen space.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.1.4 Document mouse position API
Research mouse position return type, units, and coordinate system.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.1.5 Document mouse wheel API
Research mouse wheel API name and sign convention.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.1.6 Document mouse click API
Research left-click pressed API and button enum/value.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.1.7 Document world-mouse conversion API
Research and document world-mouse conversion API and whether it uses screen mouse coordinates.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.1.8 Fill Reference Index: Engine Bindings
Consolidate all 0.1 findings into the Reference Index section with verified identifiers.

Labels: phase-0, gating, documentation
Priority: P0

---

## [task] 0.2.1 Calculate aligned screen dimensions
Implement SCREEN_W/SCREEN_H calculation using floor(engine_dim/TILE_SIZE)*TILE_SIZE.

Labels: phase-0, gating, implementation
Priority: P0

---

## [task] 0.2.2 Store viewport state in sim_scene
Add _screen_w, _screen_h, _world_view_w, _ui_sidebar_w, _tile_size to sim_scene.

Labels: phase-0, gating, implementation
Priority: P0

---

## [task] 0.2.3 Update camera zoom calculation
Implement sidebar reservation: zoomX = WORLD_VIEW_W / config.VIRTUAL_WIDTH, etc.

Labels: phase-0, gating, implementation
Priority: P0

---

## [task] 0.2.4 Center camera within left region
Set cam offset to WORLD_VIEW_W/2, SCREEN_H/2.

Labels: phase-0, gating, implementation
Priority: P0

---

## [task] 0.2.5 Implement margin input gating
Block input when mx >= SCREEN_W or my >= SCREEN_H.

Labels: phase-0, gating, implementation
Priority: P0

---

## [task] 0.2.6 Verify viewport at 600x400 window
Manual test: verify sidebar is reserved, world centered at 600x400.

Labels: phase-0, gating, verification
Priority: P0

---

## [task] 0.2.7 Verify viewport at 800x600 window
Manual test: verify sidebar is reserved, world centered at 800x600.

Labels: phase-0, gating, verification
Priority: P0

---

## [task] 0.3.1 Analyze SaveManager.register flow
Understand current registration and distribution logic.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.3.2 Implement late-registration distribution
In SaveManager.register, call collector.distribute(cache[key]) if cache contains key.

Labels: phase-0, gating, implementation
Priority: P0

---

## [task] 0.3.3 Add pcall guard for distribute call
Wrap distribute call in pcall to handle errors gracefully.

Labels: phase-0, gating, implementation
Priority: P0

---

## [task] 0.3.4 Create test_save_manager_register_distributes.lua
Test that late-registered collectors receive cached data.

Labels: phase-0, gating, testing
Priority: P0

---

## [task] 0.4.1 Document resources.lua read totals API
Identify exact function/shape for reading resource totals.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.4.2 Document resources.lua add delta API
Identify exact function for adding deltas, check negative support.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.4.3 Check for existing spend/afford helper
Determine if resources module has can_afford/try_spend helpers.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.4.4 Document upgrades list/definitions API
Identify upgrade IDs, titles, and definition source.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.4.5 Document upgrades purchase API
Identify purchase attempt API and return shape.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.4.6 Document upgrades level query API
Identify level query and max level query functions.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.4.7 Document spawner creature tracking
Understand foragers table keying and count access.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.4.8 Document terrain tile conventions
Understand tileX/tileY conventions and walkable/occupied checks.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.4.9 Fill Reference Index: Module Contracts
Consolidate all 0.4 findings into the Reference Index section.

Labels: phase-0, gating, documentation
Priority: P0

---

## [task] 0.5.1 Analyze entity_types directory patterns
Document current entity type patterns in ai/entity_types/.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.5.2 Analyze goal_selectors directory patterns
Document current goal selector patterns in ai/goal_selectors/.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.5.3 Analyze blackboard_init directory patterns
Document current blackboard init patterns in ai/blackboard_init/.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.5.4 Document spawner entity type assignment
Identify exact field/mechanism for entity type in spawner.

Labels: phase-0, gating, research
Priority: P0

---

## [task] 0.5.5 Fill Reference Index: AI Integration
Consolidate all 0.5 findings into the Reference Index section.

Labels: phase-0, gating, documentation
Priority: P0

---

<!-- Phase 1: Foundation -->

## [task] 1.0.1 Create ui_layout.lua module
Create assets/scripts/idle_game/ui/ui_layout.lua as headless-safe module.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.0.2 Implement aligned_screen function
layout.aligned_screen(tile_size, engine_w, engine_h) -> {screen_w, screen_h}

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.0.3 Implement resource_panel_rect function
layout.resource_panel_rect(tile_size, screen_w, screen_h) -> {x,y,w,h}

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.0.4 Implement sidebar_rect function
layout.sidebar_rect(tile_size, screen_w, screen_h) -> {x,y,w,h}

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.0.5 Implement toast_rects function
layout.toast_rects(tile_size, screen_w, screen_h, max_visible) -> list of rects

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.0.6 Create test_idle_ui_layout.lua
Test all layout functions return grid-aligned rects.

Labels: phase-1, foundation, testing
Priority: P1

---

## [task] 1.1.1 Parse sprites-0.json for border sprites
Identify exact filenames for 9-slice border (tl, t, tr, l, c, r, bl, b, br).

Labels: phase-1, foundation, research
Priority: P1

---

## [task] 1.1.2 Parse sprites-0.json for resource icons
Identify filenames for food/wood/stone/gold icons if available.

Labels: phase-1, foundation, research
Priority: P1

---

## [task] 1.1.3 Parse sprites-0.json for structure sprites
Identify at least 3 structure sprite filenames.

Labels: phase-1, foundation, research
Priority: P1

---

## [task] 1.1.4 Create ascii_sprites.lua module
Export BORDER, ICONS, STRUCTURES, STRUCTURE_CYCLE tables.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.2.1 Create ascii_border.lua module
Create assets/scripts/idle_game/ui/ascii_border.lua.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.2.2 Implement border.layout function
Return tiles, pixels, interior from rect specification.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.2.3 Implement rect alignment validation
Reject rects where x,y,w,h are not multiples of tile_size.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.2.4 Implement minimum size validation
Reject rects smaller than 3*tile_size in any dimension.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.2.5 Implement border.draw function
Draw 9-slice border using sprite tiles, headless-safe no-op.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.2.6 Create test_idle_ascii_border.lua
Test alignment, size validation, interior calculation, tile counts.

Labels: phase-1, foundation, testing
Priority: P1

---

## [task] 1.3.1 Create toast_queue.lua module
Create assets/scripts/idle_game/ui/toast_queue.lua as headless-safe.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.3.2 Implement queue.init function
Initialize with max_visible, default_duration, max_buffer.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.3.3 Implement queue.push function
Add toast with text and optional duration.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.3.4 Implement queue.update function
Update ages, auto-dismiss expired toasts.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.3.5 Implement buffer cap in push
Drop oldest entries when max_buffer exceeded.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.3.6 Implement queue.get_visible function
Return newest-first list up to max_visible.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.3.7 Create test_idle_toast_queue.lua
Test auto-dismiss, buffer cap, get_visible ordering.

Labels: phase-1, foundation, testing
Priority: P1

---

## [task] 1.4.1 Create achievements.lua module
Create assets/scripts/idle_game/achievements.lua as headless-safe.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.4.2 Define 4 resource achievements
res_wood_100, res_stone_100, res_gold_25, res_total_500.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.4.3 Define 3 upgrade achievements
upg_first_purchase, upg_any_level_5, upg_any_maxed.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.4.4 Define 3 creature achievements
crt_total_25, crt_specialists_10, crt_builder_exists.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.4.5 Define 2 time achievements
time_5min, time_15min.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.4.6 Implement achievements.update(dt)
Increment playtime, ignore negative dt.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.4.7 Implement achievements.unlock function
Return bool for newly_unlocked status.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.4.8 Implement achievements.is_unlocked function
Return boolean for given achievement id.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.4.9 Implement achievements.get_unlocked_ids function
Return sorted list of unlocked achievement IDs.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.4.10 Implement achievements.get_title function
Return title for given achievement id or nil.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.4.11 Implement achievements.serialize function
Return table with unlocked ids and playtime.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.4.12 Implement achievements.deserialize function
Restore state from serialized table, ignore unknown ids.

Labels: phase-1, foundation, implementation
Priority: P1

---

## [task] 1.4.13 Create test_idle_achievements.lua
Test unlock, serialize/deserialize, playtime, sorting.

Labels: phase-1, foundation, testing
Priority: P1

---

<!-- Phase 2: UI Panels -->

## [task] 2.1.1 Create ascii_resource_panel.lua module
Create assets/scripts/idle_game/ui/ascii_resource_panel.lua.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.1.2 Implement resource panel get_rect
Return fixed rect: x=0, y=0, w=10*TILE_SIZE, h=6*TILE_SIZE.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.1.3 Implement resource panel rate calculation
Track prev_totals, accum_dt, compute rate per second.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.1.4 Implement resource panel update function
Update rates when accum_dt >= 1.0.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.1.5 Implement resource panel draw function
Draw border, header, resource rows, foragers count.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.1.6 Implement resource panel hit_test
Return consumed=true for clicks inside panel rect.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.1.7 Integrate resource icons in panel
Display icons if available, text-only fallback.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.1.8 Verify resource panel at 600x400
Manual test: panel renders correctly at 600x400.

Labels: phase-2, ui, verification
Priority: P2

---

## [task] 2.1.9 Verify resource panel at 800x600
Manual test: panel renders correctly at 800x600.

Labels: phase-2, ui, verification
Priority: P2

---

## [task] 2.2.1 Create ascii_upgrade_panel_model.lua
Create headless-safe model module.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.2.2 Implement model.sorted_ids function
Return alphabetically sorted upgrade IDs.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.2.3 Implement model.view_rows function
Calculate visible rows from list height and row height.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.2.4 Implement model.scroll function
Scroll with clamping at top/bottom.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.2.5 Implement model.row_at function
Map click position to absolute row index.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.2.6 Implement model.hit_test function
Return consumed, action, id from click position.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.2.7 Create test_idle_upgrade_panel_model.lua
Test sorting, scroll clamping, hit-test mapping.

Labels: phase-2, ui, testing
Priority: P2

---

## [task] 2.2.8 Create ascii_upgrade_panel.lua renderer
Create engine renderer module.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.2.9 Implement upgrade panel get_rect
Return rect: x=SCREEN_W-UI_SIDEBAR_W, y=0, w=UI_SIDEBAR_W, h=SCREEN_H.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.2.10 Implement upgrade panel scroll_by_wheel
Handle wheel input when hovered.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.2.11 Implement upgrade panel draw function
Draw header, scrollable upgrade rows, buy buttons.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.2.12 Implement buy button states
Show [BUY], [MAX], or [—] based on upgrade state.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.2.13 Wire upgrade panel to purchase API
Call upgrades purchase API on buy action.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.2.14 Verify upgrade panel scroll behavior
Manual test: scroll reaches all upgrades correctly.

Labels: phase-2, ui, verification
Priority: P2

---

## [task] 2.2.15 Verify upgrade panel click mapping
Manual test: buy clicks map correctly after scrolling.

Labels: phase-2, ui, verification
Priority: P2

---

## [task] 2.3.1 Create toast_renderer.lua module
Create assets/scripts/idle_game/ui/toast_renderer.lua.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.3.2 Implement toast layout calculation
Compute toast positions anchored in sidebar with padding.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.3.3 Implement toast draw function
Draw visible toasts with borders and text.

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.3.4 Implement toast text formatting
Format achievement toasts as "ACHIEVEMENT: <Title>".

Labels: phase-2, ui, implementation
Priority: P2

---

## [task] 2.3.5 Verify toast stacking behavior
Manual test: newest toast at bottom, stack upward.

Labels: phase-2, ui, verification
Priority: P2

---

<!-- Phase 3: Achievement Hooks -->

## [task] 3.1.1 Add idle.resource_total signal
Emit on any resource total change.

Labels: phase-3, signals, implementation
Priority: P2

---

## [task] 3.1.2 Add idle.resource_added signal
Emit only when delta > 0.

Labels: phase-3, signals, implementation
Priority: P2

---

## [task] 3.1.3 Add idle.upgrade_purchased signal
Emit with upgrade_id and new_level.

Labels: phase-3, signals, implementation
Priority: P2

---

## [task] 3.1.4 Add idle.creature_counts signal
Emit counts table after spawn/despawn maintenance.

Labels: phase-3, signals, implementation
Priority: P2

---

## [task] 3.1.5 Check for existing signal_group utility
Determine if core.signal_group exists for hot-reload safety.

Labels: phase-3, signals, research
Priority: P2

---

## [task] 3.1.6 Create signal_group.lua if needed
Add idle_game/signal_group.lua if no core utility exists.

Labels: phase-3, signals, implementation
Priority: P2

---

## [task] 3.1.7 Implement resources.can_afford if missing
Add atomic affordability check to resources.lua.

Labels: phase-3, signals, implementation
Priority: P2

---

## [task] 3.1.8 Implement resources.try_spend if missing
Add atomic spend helper to resources.lua.

Labels: phase-3, signals, implementation
Priority: P2

---

## [task] 3.1.9 Create test_idle_resources_try_spend.lua
Test try_spend atomicity and signal emission.

Labels: phase-3, signals, testing
Priority: P2

---

## [task] 3.2.1 Create achievement_listener.lua module
Create assets/scripts/idle_game/achievement_listener.lua.

Labels: phase-3, listener, implementation
Priority: P2

---

## [task] 3.2.2 Implement listener.init function
Register signal handlers idempotently.

Labels: phase-3, listener, implementation
Priority: P2

---

## [task] 3.2.3 Implement listener.shutdown function
Unregister all signal handlers.

Labels: phase-3, listener, implementation
Priority: P2

---

## [task] 3.2.4 Implement resource achievement evaluation
Evaluate res_wood_100, res_stone_100, res_gold_25, res_total_500.

Labels: phase-3, listener, implementation
Priority: P2

---

## [task] 3.2.5 Implement upgrade achievement evaluation
Evaluate upg_first_purchase, upg_any_level_5, upg_any_maxed.

Labels: phase-3, listener, implementation
Priority: P2

---

## [task] 3.2.6 Implement creature achievement evaluation
Evaluate crt_total_25, crt_specialists_10, crt_builder_exists.

Labels: phase-3, listener, implementation
Priority: P2

---

## [task] 3.2.7 Implement time achievement evaluation
Evaluate time_5min, time_15min in listener.update.

Labels: phase-3, listener, implementation
Priority: P2

---

## [task] 3.2.8 Wire toast queue to listener
Push "ACHIEVEMENT: <Title>" on unlock.

Labels: phase-3, listener, implementation
Priority: P2

---

## [task] 3.2.9 Implement save debounce in listener
Set pending_save flag, save when debounce >= 1.0s.

Labels: phase-3, listener, implementation
Priority: P2

---

## [task] 3.2.10 Implement refresh_and_evaluate on init
Evaluate achievements at startup using module getters.

Labels: phase-3, listener, implementation
Priority: P2

---

## [task] 3.2.11 Create test_idle_achievement_listener_dedup.lua
Test double-init registers only one handler set.

Labels: phase-3, listener, testing
Priority: P2

---

## [task] 3.2.12 Create test_idle_achievement_listener_unlocks.lua
Test signal events trigger correct unlocks and toasts.

Labels: phase-3, listener, testing
Priority: P2

---

<!-- Phase 4: Creatures -->

## [task] 4.0.1 Gate forager_sensing by entity type
Early-return unless entity is classified as forager.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.0.2 Remove hardcoded TILE_SIZE in worldstate_updaters
Replace hardcoded 20 with config.TILE_SIZE.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.1.1 Add _miners tracking table to spawner
Create miners tracking similar to foragers.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.1.2 Implement spawner.getMinerCount
Return count of active miners.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.1.3 Create miner entity type file
Add ai/entity_types file for miner following 0.5 pattern.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.1.4 Create miner goal selector
Add ai/goal_selectors file for miner.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.1.5 Create miner blackboard init
Add ai/blackboard_init file for miner.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.1.6 Implement miner rock targeting
Target rocks specifically, not trees or bushes.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.1.7 Implement miner harvest multiplier
STONE_DELTA = floor(base_forager_delta * 1.5).

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.1.8 Implement miner ground item drop
Drop stone ground item on harvest.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.2.1 Add _lumberjacks tracking table to spawner
Create lumberjacks tracking similar to foragers.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.2.2 Implement spawner.getLumberjackCount
Return count of active lumberjacks.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.2.3 Create lumberjack entity type file
Add ai/entity_types file for lumberjack.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.2.4 Create lumberjack goal selector
Add ai/goal_selectors file for lumberjack.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.2.5 Create lumberjack blackboard init
Add ai/blackboard_init file for lumberjack.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.2.6 Implement lumberjack tree targeting
Target trees specifically, not rocks or bushes.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.2.7 Implement lumberjack harvest multiplier
WOOD_DELTA = floor(base_forager_delta * 1.5).

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.2.8 Implement lumberjack ground item drop
Drop wood ground item on harvest.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.3.1 Add _ground_items table to terrain
Create internal array for ground items.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.3.2 Implement terrain.drop_item function
Add ground item with monotonic id, validate kind/amount.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.3.3 Implement terrain.pickup_item function
Remove and return item by id.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.3.4 Implement terrain.find_nearest_item function
Manhattan distance search with tie-breaking.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.3.5 Clear ground items on setCurrentGrid
Reset _ground_items when grid changes.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.3.6 Create test_idle_ground_items.lua
Test drop, pickup, find_nearest, grid clear.

Labels: phase-4, creatures, testing
Priority: P2

---

## [task] 4.3.7 Add _collectors tracking table to spawner
Create collectors tracking similar to foragers.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.3.8 Implement spawner.getCollectorCount
Return count of active collectors.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.3.9 Create collector entity type file
Add ai/entity_types file for collector.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.3.10 Create collector goal selector
Add ai/goal_selectors file for collector.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.3.11 Create collector blackboard init
Add ai/blackboard_init file for collector.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.3.12 Implement collector sensing updater
Add collector-specific updater in worldstate_updaters.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.3.13 Implement collector item pickup behavior
Navigate to nearest item, pickup, add to resources.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.1 Add _structures table to terrain
Create internal list for structures.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.2 Implement terrain.place_structure function
Validate placement, add to structures list.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.3 Implement terrain.get_structures function
Return read-only or copied structures list.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.4 Implement structure placement validation
Check walkable, empty, within bounds, valid sprite.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.5 Add _builders tracking table to spawner
Create builders tracking similar to foragers.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.6 Implement spawner.getBuilderCount
Return count of active builders.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.7 Create builder entity type file
Add ai/entity_types file for builder.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.8 Create builder goal selector
Add ai/goal_selectors file for builder.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.9 Create builder blackboard init
Add ai/blackboard_init file for builder.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.10 Implement builder build interval timer
Track 20-second BUILD_INTERVAL.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.11 Implement builder resource check
Check wood >= 50, stone >= 25 before building.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.12 Implement builder tile selection
Find nearest valid empty tile within Manhattan radius 10.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.13 Implement builder sprite cycling
Cycle through STRUCTURE_CYCLE deterministically.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.14 Render structures in terrain_renderer
Draw structures after terrain, before corpses.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.15 Create terrain_persistence.lua
Register SaveManager collector for structures.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.16 Implement structures collect function
Return serializable structure list.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.17 Implement structures distribute function
Restore structures with validation.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.18 Create test_idle_structures_persistence.lua
Test serialize/deserialize with validation.

Labels: phase-4, creatures, testing
Priority: P2

---

## [task] 4.4.19 Implement spawner.getTotalCreatureCount
Sum all creature types.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.20 Implement spawner.getSpecialistCount
Sum miners + lumberjacks + collectors + builders.

Labels: phase-4, creatures, implementation
Priority: P2

---

## [task] 4.4.21 Update spawner to emit creature_counts signal
Emit after spawn/despawn maintenance.

Labels: phase-4, creatures, implementation
Priority: P2

---

<!-- Phase 5: Persistence + Integration -->

## [task] 5.1.1 Create achievements_persistence.lua
Create assets/scripts/idle_game/achievements_persistence.lua.

Labels: phase-5, persistence, implementation
Priority: P3

---

## [task] 5.1.2 Implement achievements collector
Wrap achievements.serialize/deserialize for SaveManager.

Labels: phase-5, persistence, implementation
Priority: P3

---

## [task] 5.1.3 Register achievements collector in SaveManager
Call SaveManager.register("idle_achievements", collector).

Labels: phase-5, persistence, implementation
Priority: P3

---

## [task] 5.1.4 Verify achievement persistence
Manual test: unlock, restart, verify still unlocked.

Labels: phase-5, persistence, verification
Priority: P3

---

## [task] 5.2.1 Update config.json window defaults
Set default window size to 800x600.

Labels: phase-5, optional, implementation
Priority: P4

---

## [task] 5.2.2 Update globals.cpp for window defaults
Apply config defaults when unset.

Labels: phase-5, optional, implementation
Priority: P4

---

## [task] 5.3.1 Verify sidebar reservation
Integration test: rightmost UI_SIDEBAR_W pixels contain no world tiles.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.2 Verify margin input gating
Integration test: clicks in margin have no effect.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.3 Verify resource panel rendering
Integration test: panel renders and updates correctly.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.4 Verify resource panel click blocking
Integration test: clicks inside panel don't affect world.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.5 Verify upgrade panel scroll and buy
Integration test: scroll works, buy triggers purchases.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.6 Verify upgrade panel click blocking
Integration test: sidebar clicks don't affect world.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.7 Verify toast rendering and dismiss
Integration test: toasts show, auto-dismiss, stack correctly.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.8 Verify miner behavior
Integration test: miner targets rocks, bonus stone gain.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.9 Verify lumberjack behavior
Integration test: lumberjack targets trees, bonus wood gain.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.10 Verify collector behavior
Integration test: collector picks up ground items.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.11 Verify builder behavior
Integration test: builder places structures periodically.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.12 Verify resource achievements
Integration test: all 4 resource achievements unlock correctly.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.13 Verify upgrade achievements
Integration test: all 3 upgrade achievements unlock correctly.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.14 Verify creature achievements
Integration test: all 3 creature achievements unlock correctly.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.15 Verify time achievements
Integration test: time_5min and time_15min unlock correctly.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.16 Verify structures persistence
Integration test: structures survive save/restart.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.17 Verify ImGui debug panel
Integration test: debug panel still functional.

Labels: phase-5, integration, verification
Priority: P3

---

## [task] 5.3.18 Run 10-minute stability test
Play SIM_GAME for 10 minutes, verify no Lua errors.

Labels: phase-5, integration, verification
Priority: P3

---

<!-- sim_scene.lua Integration -->

## [task] INT.1 Add UI module imports to sim_scene
Import ui_layout, ascii_resource_panel, ascii_upgrade_panel, toast_renderer, toast_queue.

Labels: integration, sim-scene, implementation
Priority: P2

---

## [task] INT.2 Add persistence imports to sim_scene
Import achievements_persistence, terrain_persistence.

Labels: integration, sim-scene, implementation
Priority: P2

---

## [task] INT.3 Initialize aligned screen dimensions
Compute SCREEN_W/SCREEN_H in sim_scene.init().

Labels: integration, sim-scene, implementation
Priority: P2

---

## [task] INT.4 Initialize toast queue in sim_scene
Call toast_queue.init() in sim_scene.init().

Labels: integration, sim-scene, implementation
Priority: P2

---

## [task] INT.5 Initialize panels in sim_scene
Set up resource and upgrade panels in sim_scene.init().

Labels: integration, sim-scene, implementation
Priority: P2

---

## [task] INT.6 Initialize achievement listener
Call achievement_listener.init(toast_queue) in sim_scene.init().

Labels: integration, sim-scene, implementation
Priority: P2

---

## [task] INT.7 Replace spawnForagers with mixed spawn
Replace spawner.spawnForagers(20) with 12 foragers, 3 miners, 3 lumberjacks, 1 collector, 1 builder.

Labels: integration, sim-scene, implementation
Priority: P2

---

## [task] INT.8 Implement resize detection in update
Recompute ENGINE_SCREEN_W/H and camera values on resize.

Labels: integration, sim-scene, implementation
Priority: P2

---

## [task] INT.9 Add UI state updates to sim_scene.update
Update resource panel, upgrade panel hover/scroll, toast queue, achievement listener.

Labels: integration, sim-scene, implementation
Priority: P2

---

## [task] INT.10 Implement margin gating in update
Block all input when mx >= SCREEN_W or my >= SCREEN_H.

Labels: integration, sim-scene, implementation
Priority: P2

---

## [task] INT.11 Implement UI click handling in update
Test hit_test on resource and upgrade panels, consume if inside.

Labels: integration, sim-scene, implementation
Priority: P2

---

## [task] INT.12 Wire upgrade purchase action
Call upgrades purchase API on {action="buy", id=...}.

Labels: integration, sim-scene, implementation
Priority: P2

---

## [task] INT.13 Update sim_scene.draw for ASCII UI
Draw resource panel, upgrade panel, toasts in Screen space.

Labels: integration, sim-scene, implementation
Priority: P2

---

## [task] INT.14 Ensure correct draw order
World -> structures -> corpses -> ASCII UI -> ImGui debug.

Labels: integration, sim-scene, implementation
Priority: P2

---
