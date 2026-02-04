# Incremental Game ASCII UI & Content Expansion

## TL;DR

> **Quick Summary**: Overhaul the idle game UI from ImGui to grid-aligned ASCII-styled panels using CP437/dungeon sprites, add 4 new creature types (Miner, Lumberjack, Collector, Builder), and implement an achievement system with toast notifications.
> 
> **Deliverables**:
> - ASCII border system (assembled 9-tile borders from CP437/dungeon sprites)
> - ASCII resource panel (top-left, icons + text)
> - ASCII upgrade panel (right sidebar, scrollable list)
> - 4 new creature types (specializations: Miner, Lumberjack, Collector, Builder)
> - Achievement system (4 categories, persistence, toast queue)
> 
> **Estimated Effort**: Large
> **Parallel Execution**: YES - 4 waves
> **Critical Path**: Border System → UI Panels → (Creatures || Achievements)

---

## COORDINATE SYSTEM TRUTH TABLE (AUTHORITATIVE)

> **This is THE single source of truth for all coordinate systems in this plan.**
> All other sections reference this table. DO NOT contradict it.

| System | Current Value | Source File | Lua Access | Returns |
|--------|---------------|-------------|------------|---------|
| **Physical window** | 600×400 (→ 800×600 after Task 4.2) | `assets/config.json` render_data.screen | N/A (not exposed) | N/A |
| **Engine virtual resolution** | 1280×800 | `src/core/globals.cpp` VIRTUAL_WIDTH/HEIGHT | `globals.screenWidth()` | **1280** |
| **Idle game world** | 600×400 pixels (30×20 tiles) | `assets/scripts/idle_game/config.lua` | `config.VIRTUAL_WIDTH` | **600** |
| **ASCII UI positioning** | Uses 1280×800 virtual | (calculated from engine virtual) | `globals.screenWidth()` | **1280** |

**Key Rules:**
1. ASCII UI always uses engine virtual coords (1280×800) via `globals.screenWidth()/Height()`
2. Game world/camera uses `config.VIRTUAL_WIDTH` (600×400) 
3. `input.getMousePos()` returns virtual coords (same as Screen space) - no conversion needed
4. Task 4.2 changes ONLY physical window (600×400 → 800×600), NOT virtual resolution

**CRITICAL CLARIFICATION about sim_scene.init() comment:**
The code comment in `sim_scene.init()` says "Get actual window size" but is MISLEADING:
```lua
local screenW = globals.screenWidth()  -- Returns VIRTUAL_WIDTH (1280), NOT window size!
```
`globals.screenWidth()` returns `VIRTUAL_WIDTH` (1280), NOT physical window pixels.
The zoom calculation uses virtual resolution, not actual window size.

**UI Math (in VIRTUAL pixels):**
- Resource panel: x=0, y=0
- Upgrade panel: x=1080 (1280 - 200), y=0
- Toast: x=(1280 - toast_width)/2 (centered)

---

## Context

### Original Request
Create ASCII-styled incremental game UI that conforms to the game's 20x20 tile grid aesthetic. Use existing UI system but adapt it visually with ASCII sprites. Add new creature types and achievements.

### Interview Summary
**Key Discussions**:
- **UI Approach**: Coexist - Keep ImGui for debug, add ASCII UI for gameplay
- **Border Style**: Single-line CP437 box (┌─┐│└┘) using assembled 9-tile approach, configurable
- **Layout**: Overlay with transparent background, strictly grid-aligned (20px multiples)
- **Resource Panel**: Top-left corner, ASCII icons + text, earthy color scheme
- **Upgrade Panel**: Right sidebar, scrollable list
- **Creatures**: 4 new types as specializations (faster at their resource)
- **Achievements**: 4 categories with toast queue notifications
- **Persistence**: Use existing save_file_io system
- **Test Strategy**: TDD for data systems, manual for visual

**Research Findings**:
- Native UI system uses `UIElementTemplateNode` builder pattern
- CP437 sprites: 256 chars @ 20x20px in `assets/graphics/cp437_mappings.json`
- Box drawing chars: ┌(216), ─(194), ┐(189), │(177), └(190), ┘(215)
- Dungeon sprites: `d437_*` files in atlas for terrain (same 20x20 dimensions)
- Existing forager pattern: entity_types/, goal_selectors/, blackboard_init/, worldstate_updaters.lua
- Signal system available: `require("external.hump.signal")` for achievement events

### Metis Review
**Identified Gaps** (addressed):
- Border implementation approach - Resolved: Assembled 9-tile sprites (not nine-patch)
- Creature role clarification - Resolved: Specializations (faster at one resource)
- Collector behavior - Resolved: Picks up dropped resources on ground (simple ground-item tracking)
- Builder behavior - Resolved: Places decorative sprites in `terrain._structures` table
- Achievement persistence - Resolved: Use existing SaveManager collector pattern
- Toast behavior - Resolved: Queue (stack multiple)
- Sprite lookup risk - Added verification task in Phase 1

**Guardrails Applied**:
- All UI positions MUST be grid-aligned (`math.floor(x/20)*20`)
- **Forager modification rule** (consolidated):
  - FORBIDDEN: Changing forager GOAP goals, survival thresholds, movement patterns, reproduction logic
  - ALLOWED: Adding signal emissions on existing events (no logic change)
  - ALLOWED: Adding item drop side-effects in passive harvesting block (line ~187-193 of worldstate_updaters.lua)
  - Rationale: Item drops are a non-invasive addition to existing harvest success code path
- Do NOT remove ImGui until ASCII versions verified
- Use EXACT dungeon_437 sprite filenames from atlas (NO wildcards like `d437_*`)
- All ASCII UI uses `layer.DrawCommandSpace.Screen` for screen-fixed positioning
- World terrain uses `layer.DrawCommandSpace.World` (camera-relative)
- **SaveManager collector timing** (NOTE): SaveManager caches loaded data in `SaveManager.cache`.
  Collectors registered AFTER `SaveManager.init()` miss the automatic `distribute_all()` call
  during init. While `SaveManager.peek(key)` exists for manual data retrieval, this plan 
  **does not use that pattern** to avoid complexity.
  
  **AUTHORITATIVE DECISION: Use option (a) - pre-require before SaveManager.init()**
  
  This plan uses option (a): require idle game collector modules BEFORE `SaveManager.init()` so 
  their collectors are registered and receive data during the normal `distribute_all()` flow.
  This is the simpler approach that doesn't require manual peek/distribute handling.
  
  **Required change to main.lua** (inside `main.init()` function):
  ```lua
  -- CURRENT order in main.init():
  -- line 983: (end of telemetry block)
  -- line 985: SaveManager.init()
  -- line 988-991: Statistics, GridInventorySave requires
  
  -- REQUIRED NEW order (add before SaveManager.init):
  -- line 983: (end of telemetry block)
  -- NEW: pcall(function() require("idle_game.achievements") end)   -- Task 4.1
  -- NEW: pcall(function() require("idle_game.terrain") end)        -- Task 3.4
  -- line 985: SaveManager.init()                                   -- UNCHANGED
  -- line 988-991: Statistics, GridInventorySave requires           -- UNCHANGED
  ```
  
  This is a behavior change to main.lua's initialization order. The `pcall` wrapper ensures
  failure is silent if idle_game modules aren't present.

---

## Work Objectives

### Core Objective
Create a cohesive ASCII-styled UI system for the incremental game that matches the grid-based visual aesthetic, while expanding gameplay with specialized creature types and an achievement system.

### Concrete Deliverables
- `assets/scripts/idle_game/ui/ascii_border.lua` - Reusable border component
- `assets/scripts/idle_game/ui/ascii_resource_panel.lua` - Resource display panel
- `assets/scripts/idle_game/ui/ascii_upgrade_panel.lua` - Upgrade list panel
- `assets/scripts/ai/entity_types/{miner,lumberjack,collector,builder}.lua` - 4 creature types
- `assets/scripts/ai/goal_selectors/{miner,lumberjack,collector,builder}.lua` - Goal selectors
- `assets/scripts/idle_game/achievements.lua` - Achievement data/tracking
- `assets/scripts/idle_game/ui/toast_notification.lua` - Toast queue system

### Integration Points (sim_scene.lua modifications)

**Current draw order** (`sim_scene.draw()` at line 126-138):
```lua
function sim_scene.draw()
    -- Draw terrain grid (World space)
    terrain_renderer.draw(terrainGrid)
    
    -- Draw corpses (World space)
    spawner.drawCorpses()

    -- ImGui panels (Screen space, handled by ImGui)
    resource_panel.draw()
    debug_panel.draw()
    upgrade_panel.draw()
end
```

**After implementation** (add ASCII panels before ImGui):
```lua
function sim_scene.draw()
    -- Draw terrain grid (World space)
    terrain_renderer.draw(terrainGrid)
    
    -- Draw structures (World space, Task 3.4)
    -- (handled inside terrain_renderer after Task 3.4)
    
    -- Draw corpses (World space)
    spawner.drawCorpses()

    -- === ASCII UI (Screen space, z=100+) ===
    ascii_resource_panel.draw()   -- Top-left (Task 2.1)
    ascii_upgrade_panel.draw()    -- Right sidebar (Task 2.2)
    toast_notification.draw()     -- Top-center (Task 2.3)

    -- === ImGui Debug Panels (keep for debug) ===
    resource_panel.draw()         -- Existing ImGui version
    debug_panel.draw()
    upgrade_panel.draw()          -- Existing ImGui version
end
```

**Update loop addition** (`sim_scene.update()`):
```lua
-- Add after existing update logic:
ascii_upgrade_panel.update(dt)  -- Handle scroll input
toast_notification.update(dt)   -- Handle fade/slide animations (NOT auto-dismiss - timer system handles that)
achievement_listener.update(dt) -- Track playtime, check conditions
```

### Definition of Done
- [ ] ASCII UI panels render using CP437/dungeon sprites
- [ ] All UI elements grid-aligned to 20px multiples
- [ ] 4 creature types spawn at game start and behave correctly
- [ ] Achievements unlock and persist across sessions
- [ ] Toast notifications display in queue
- [ ] `just build-debug` passes with no errors
- [ ] ImGui panels still work (debug mode)

### Creature Spawn Integration (How New Creatures Appear in Gameplay)

**CRITICAL**: This section specifies how new creatures become player-visible.

**Chosen Approach**: Spawn initial mix at game start (in `sim_scene.init()`)

**Modify `sim_scene.init()`** (after terrain generation, around line 67):
```lua
-- Current: spawner.spawnForagers(20)
-- Replace with initial creature mix:
spawner.spawnForagers(10)     -- Reduced from 20
spawner.spawnMiners(3)        -- New: 3 stone specialists
spawner.spawnLumberjacks(3)   -- New: 3 wood specialists  
spawner.spawnCollectors(2)    -- New: 2 resource gatherers
spawner.spawnBuilders(2)      -- New: 2 structure builders
```

**Why this approach**:
- Immediate player visibility (no upgrades required to see new creatures)
- Allows testing all creature types from game start
- Total creatures: 20 (same as before, just mixed)

**Fallback search token**: Find `spawner.spawnForagers(20)` in `sim_scene.lua`

**Future enhancement (OUT OF SCOPE for this plan)**:
- Upgrades that spawn additional specialists
- Creature reproduction for specialists

### Must Have
- Grid-aligned UI (20px multiples)
- Assembled sprite borders (9-tile pattern)
- Earthy color scheme (browns, greens, gold)
- TDD for achievement and creature data logic
- Resource panel with icons
- Scrollable upgrade list

### Must NOT Have (Guardrails)
- Double-line borders or Unicode beyond CP437
- Creature breeding, evolution, or genetics
- Achievement trees, prestige, or unlockable perks
- Drag-and-drop UI, resizing, or windowing
- Removal of ImGui panels (keep for debug)
- Hardcoded sprite indices (use mapping lookup)
- Modification of existing forager behavior
- Sound effects for achievements (defer)

### Headless-Safe Module Design (GLOBAL RULE)

**Applies to ALL modules that have headless Lua tests in this plan.**

**REQUIRE-TIME SAFETY RULE**: A module is headless-safe if `require("module.path")` succeeds 
in plain Lua CLI without engine globals (`command_buffer`, `layers`, `util`, `Col`, `save_io`, etc.).

**Modules with headless tests (must follow this rule)**:
| Module | Headless Test | Engine Globals Guard |
|--------|---------------|---------------------|
| `idle_game.achievements` | `test_idle_achievements.lua` | NO globals at require-time; lazy-load deps in functions |
| `idle_game.ui.ascii_border` | `test_idle_ascii_border.lua` | NO `command_buffer`/`layers` at require; guard in `create()`/`draw()` |

**Required pattern**:
```lua
-- GOOD: Engine globals guarded inside functions, not at module level
local M = {}
function M.draw()
    if not command_buffer then return end  -- Guard for headless
    -- ... draw logic ...
end
return M

-- BAD: Module fails to load in headless Lua
local cmd_buffer = command_buffer  -- CRASH: command_buffer is nil in headless
```

**Test verification**: Before committing a module with a headless test, verify:
```bash
# NOTE: Set package.path to find idle_game modules
lua -e "package.path='assets/scripts/?.lua;'..package.path; require('idle_game.achievements'); print('OK')"
# Must print "OK" without error
```

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (Lua test framework in `assets/scripts/tests/`)
- **User wants tests**: TDD for data systems, manual for visual
- **Framework**: Lua test files with `test_runner.lua`

### TDD Structure for Data Systems
Achievement and creature logic follow RED-GREEN-REFACTOR:
1. **RED**: Write failing test in `assets/scripts/tests/test_idle_*.lua`
2. **GREEN**: Implement minimum code to pass
3. **REFACTOR**: Clean up while keeping green

### TEST EXECUTION MATRIX (CRITICAL - which tests run where)

Each task's acceptance criteria falls into one of three categories:

| Category | Environment | How to Run | Example |
|----------|-------------|------------|---------|
| **Headless Lua** | Plain Lua interpreter | `lua assets/scripts/tests/test_*.lua` | achievements.lua, terrain grid tests |
| **In-Engine** | Running game with engine globals | Dev console or scene init hook | spawner tests, render verification |
| **Manual** | Human observation | Launch game, visual check | UI rendering, click behavior |

**Headless-safe requirements** (for Lua CLI tests):
- Module must NOT require engine globals (`command_buffer`, `layers`, `registry`, `Transform`, etc.)
- Dependencies should be lazy-loaded or mockable via `package.loaded[]`
- Tests use standard `assert()` and `print()` for output

**In-engine test execution** (when engine globals needed):
- Wrap test code in a function called from scene init or debug hotkey
- Use `log_debug()` for output verification
- These CANNOT run via `lua` CLI

### Automated Verification

**For headless-safe modules** (using Bash lua):
```bash
lua assets/scripts/tests/test_idle_achievements.lua
# Assert: "All tests passed"
```

**For in-engine tests** (added to sim_scene or dev console):
```lua
-- In sim_scene.init() or debug hotkey:
local spawner_tests = require("idle_game.tests.spawner_tests")
spawner_tests.run()  -- Uses engine globals, prints results
```

**For visual UI** (manual verification):
- Run game: `./build/raylib-cpp-cmake-template`
- Observe UI renders correctly
- Screenshot evidence saved to `.sisyphus/evidence/`

### UI Coordinate Space Specification (CRITICAL)

**Two coordinate spaces exist in the engine:**

| Space | Usage | Example |
|-------|-------|---------|
| `layer.DrawCommandSpace.World` | Terrain, creatures, world objects | Terrain tiles at (0,0) to (600,400) move with camera |
| `layer.DrawCommandSpace.Screen` | UI panels, toasts, HUD elements | Resource panel at (0,0) stays fixed on screen |

**All ASCII UI panels MUST use:**
```lua
command_buffer.queueDrawSpriteTopLeft(
    layers.sprites,       -- draw layer (same as terrain)
    function(c) ... end,  -- config callback
    z_order,              -- higher = on top (use 100+ for UI)
    layer.DrawCommandSpace.Screen  -- ← CRITICAL: fixed to screen
)
```

**Existing pattern reference:** `assets/scripts/idle_game/terrain_renderer.lua:64-76` uses `.World`

**Integration point in sim_scene.lua:**
The draw order in `sim_scene.draw()` (line 126-138) is:
1. `terrain_renderer.draw()` - World space, z=0 (command_buffer sprites)
2. `spawner.drawCorpses()` - World space (command_buffer sprites)
3. `resource_panel.draw()` - **ImGui** (not command_buffer, no z-order concept)
4. `debug_panel.draw()` - **ImGui**
5. `upgrade_panel.draw()` - **ImGui**

**Note**: Current UI panels use ImGui, which has its own rendering pipeline separate from 
command_buffer. New ASCII UI panels will use command_buffer with Screen space and z-order.

**ASCII panels will be inserted AFTER terrain, BEFORE ImGui debug panels.**

### Render Layer & Z-Order Contract (CRITICAL for ASCII UI)

**Verified rendering pattern** (from `terrain_renderer.lua:64-76`):
```lua
command_buffer.queueDrawSpriteTopLeft(
    layers.sprites,                    -- Draw layer
    function(c) ... end,               -- Config callback
    z_order,                           -- Z-order (higher = on top)
    layer.DrawCommandSpace.World       -- Coordinate space
)
```

**Z-Order convention for idle game**:
| Z-Order | What | Coordinate Space |
|---------|------|------------------|
| 0 | Terrain tiles | World |
| 1 | Structures (builder output) | World |
| 2-10 | Creatures/corpses | World |
| 100+ | ASCII UI panels | **Screen** |

**COORDINATE SPACE CONTRACT (authoritative for idle game UI)**:

| Space | Unit | Origin | Used By |
|-------|------|--------|---------|
| `DrawCommandSpace.Screen` | Virtual pixels | Top-left (0,0) | ASCII UI panels |
| `DrawCommandSpace.World` | World pixels | Depends on camera | Terrain, creatures |
| `input.getMousePos()` | Virtual pixels | Top-left (0,0) | Mouse position for UI hit testing |

**Virtual pixels vs window pixels**: The engine uses virtual resolution (1280×800 by default).
`input.getMousePos()` returns coordinates in this virtual space, NOT raw window pixels.
`DrawCommandSpace.Screen` also uses virtual pixels.

**For idle game (800×600 window)**:
- Window default is set to 800×600, but virtual resolution constants remain 1280×800
- The game world is 600×400 pixels (30×20 tiles × 20px)
- Camera zoom in `sim_scene.init()` auto-scales the world to fit the window
- ASCII UI panels using Screen space appear at fixed virtual-pixel positions

**AUTHORITATIVE DECISION: ASCII UI uses VIRTUAL coordinates (1280×800)**:
- ALL ASCII UI panels position themselves relative to 1280×800 virtual resolution
- `globals.screenWidth()` returns 1280 (VIRTUAL_WIDTH), NOT window width
- `globals.screenHeight()` returns 800 (VIRTUAL_HEIGHT), NOT window height
- The rendering system scales virtual coords to fit the actual window
- This is verified in `src/systems/scripting/scripting_functions.cpp` (line ~468):
  ```cpp
  lua["globals"]["screenWidth"] = []() { return globals::VIRTUAL_WIDTH; };
  ```

**UI Placement Math (VIRTUAL space)**:
- Resource panel (top-left): x=0, y=0 (virtual pixels)
- Upgrade panel (right side): x=VIRTUAL_WIDTH - panel_width = 1280 - 200 = 1080 (virtual pixels)
- Toast notifications (top-center): x=(VIRTUAL_WIDTH - toast_width)/2 (virtual pixels)
- The engine's scaling system maps these to actual window pixels automatically

**IMPORTANT: Two "VIRTUAL" constants exist - DO NOT confuse them**:

| Constant | Value | Purpose | Used By |
|----------|-------|---------|---------|
| `globals.screenWidth()` | 1280 | Engine virtual resolution | **ASCII UI positioning** |
| `globals.screenHeight()` | 800 | Engine virtual resolution | **ASCII UI positioning** |
| `idle_game/config.VIRTUAL_WIDTH` | 600 | Game world pixel size (30 tiles × 20px) | World/camera calculations |
| `idle_game/config.VIRTUAL_HEIGHT` | 400 | Game world pixel size (20 tiles × 20px) | World/camera calculations |

**Rule**: ASCII UI uses `globals.screenWidth()/Height()` (1280×800). Game world uses `config.VIRTUAL_*`.

**Grid alignment rule**: "20px multiples" refers to **tile units** (TILE_SIZE = 20 virtual pixels).
UI positions should be `tile * 20` to align with the game grid visually.

**Click hit testing**: Both `input.getMousePos()` and Screen space use the same coordinate 
system, so no conversion is needed. The plan's input routing approach works correctly.

**Available render layers** (from `assets/scripts/core/render_layers.lua`):
- `layers.background` - Background elements
- `layers.sprites` - Main sprite layer (terrain, creatures)
- `layers.ui` - UI layer (exists and is used elsewhere in the codebase)
- `layers.final` - Final compositing layer

**Layer choice for ASCII UI: `layers.sprites` (intentional)**:
- `layers.ui` DOES exist and is used in other parts of the codebase (e.g., `currency_display.lua`)
- However, the idle game terrain uses `layers.sprites`, and we want ASCII UI to render 
  in the same layer to avoid potential z-ordering issues across layers
- `DrawCommandSpace.Screen` handles screen-fixed positioning regardless of which layer is used
- Z-order within the layer ensures UI appears above terrain (z=100 vs z=0)

**Existing Screen-space usage** (reference implementations):
- `assets/scripts/ui/currency_display.lua` - Uses `layers.ui` + `DrawCommandSpace.Screen`
- Screen-space rendering with `command_buffer` is proven to work in this codebase

**If layering issues occur**:
- Can switch ASCII UI to `layers.ui` if `layers.sprites` z-ordering is insufficient
- The `DrawCommandSpace.Screen` pattern will work the same way on either layer

### Text Rendering Contract (REQUIRED for ASCII UI panels)

ASCII UI panels need text for labels, numbers, costs, headers, and buttons. Use `command_buffer.queueDrawText`.

**Reference implementation**: `assets/scripts/ui/currency_display.lua:166-173` (verify line numbers during implementation)

```lua
-- Text rendering pattern for Screen-space ASCII UI
local localization = require("systems.localization")

function ascii_panel.draw_text(text, x, y, options)
    options = options or {}
    local space = layer.DrawCommandSpace.Screen
    local font = localization.getFont()
    local z_order = options.z_order or 100
    local fontSize = options.fontSize or 14
    local color = options.color or util.getColor("WHITE")
    
    command_buffer.queueDrawText(layers.ui, function(c)
        c.text = text
        c.font = font
        c.x = x
        c.y = y
        c.color = color
        c.fontSize = fontSize
    end, z_order, space)
end

-- To measure text width (for alignment):
-- Signature: (text, fontSize, spacing) - 3 args required
-- Reference: assets/scripts/ui/currency_display.lua:148 (verify during implementation)
local width = localization.getTextWidthWithCurrentFont(text, fontSize, 1)  -- spacing=1 is standard
```

**Key APIs** (from `assets/scripts/ui/currency_display.lua`):
- `command_buffer.queueDrawText(layer, config_fn, z_order, space)` - Draw text
- `localization.getFont()` - Get current font
- `localization.getTextWidthWithCurrentFont(text, size, spacing)` - Measure text width (3rd arg = spacing, use 1)

**Layer choice for text**: Use `layers.ui` for text (matches currency_display pattern).
Sprite borders can use `layers.sprites`; text uses `layers.ui` for best results.

### Input Routing Strategy (CRITICAL for clickable ASCII UI)

**Problem**: `sim_scene.update()` calls `input_module.handleClick(config)` which processes world clicks (tree/rock harvesting). ASCII upgrade panel needs clickable BUY buttons in screen space.

**Solution**: Check ASCII UI hit areas BEFORE calling `input_module.handleClick()`.

**Implementation in sim_scene.update()**:

**CLARIFICATION: Input reading behavior**

The `input.isMousePressed(button)` function may behave as **edge-triggered** (returns true 
only on the first check per frame) or **level-triggered** (returns true for entire frame).

**Verified in codebase**: The current `idle_game/input.lua:21` calls `input.isMousePressed()` 
directly without any state caching, suggesting it queries the engine each time. The exact 
behavior depends on C++ binding implementation.

**CHOSEN APPROACH: Add UI check BEFORE existing `input_module.handleClick()`**

**Why pre-check instead of bypass**:
- `input_module.handleClick()` already works correctly for world tile clicking
- We only need to intercept clicks that hit UI panels
- Simpler change: add early return if UI consumes click
- No need to duplicate camera conversion logic

**Click routing modification** (add IMMEDIATELY BEFORE `input_module.handleClick`):
```lua
-- Add IMMEDIATELY BEFORE line 88 (`input_module.handleClick`), 
-- AFTER terrain.update, spawner.processPendingDestructions (don't skip those)
local leftButton = MouseButton and MouseButton.MOUSE_BUTTON_LEFT or 0
if input.isMousePressed(leftButton) then
    local mouse = input.getMousePos()
    
    -- UI panels consume clicks first (highest to lowest priority)
    if ascii_upgrade_panel.handle_click(mouse.x, mouse.y) then
        return  -- click consumed by upgrade panel, skip world interaction
    end
end

-- EXISTING CODE UNCHANGED (input_module.handleClick handles world clicks):
local tileX, tileY = input_module.handleClick(config)
if tileX and tileY then
    -- existing tile harvest logic stays here unchanged
end
```

**Exact changes to sim_scene.lua**:
1. **ADD**: `local ascii_upgrade_panel = require("idle_game.ui.ascii_upgrade_panel")` at top
2. **ADD**: The UI check block IMMEDIATELY BEFORE `input_module.handleClick(config)` call
3. **KEEP**: The `input_module.handleClick(config)` call and all subsequent tile handling UNCHANGED

**Fallback search token**: Find `input_module.handleClick(config)` in sim_scene.lua

**RELATIONSHIP WITH idle_game/input.lua (SOURCE OF TRUTH)**:

The existing `idle_game/input.lua` module is NOT modified. We only add a pre-check in `sim_scene.lua`.

| File | Role | Change |
|------|------|--------|
| `idle_game/input.lua` | Utility module for click→tile conversion | **NO CHANGE** - kept as utility |
| `sim_scene.lua` line 88 | Calls `input_module.handleClick(config)` | **UNCHANGED** - kept as-is |
| `sim_scene.lua` | New UI click pre-check | **ADDED** - early return if UI consumes click |

**Why pre-check instead of bypass `input.lua`**:
1. `input_module.handleClick()` already works correctly for world tile clicking
2. We only need to intercept clicks that hit UI panels  
3. Simpler change: add early return BEFORE calling handleClick
4. No need to duplicate camera conversion logic

**What is NEW in sim_scene (adds to existing flow)**:
- `ascii_upgrade_panel.handle_click(x, y)` call BEFORE `input_module.handleClick`
- Early `return` if UI consumes the click (prevents world interaction)

**INPUT SAFETY NOTE**: Raylib's `IsMouseButtonPressed` (which `input.isMousePressed` wraps) 
returns the same value when called multiple times per frame. The UI pre-check reads it once, 
and if it doesn't consume the click, `input_module.handleClick` can safely read it again.

**Future extensibility**: If other ASCII panels need click handling, add them to the UI check chain:
```lua
if input.isMousePressed(leftButton) then
    local mouse = input.getMousePos()
    if ascii_upgrade_panel.handle_click(mouse.x, mouse.y) then return end
    -- Future: if ascii_inventory_panel.handle_click(mouse.x, mouse.y) then return end
end
-- Falls through to existing input_module.handleClick(config)
```

**Acceptance criteria for input routing**:
- Click on BUY button in upgrade panel → triggers `upgrades.purchase()` → NO tile behind it is harvested
- Click on world tile NOT covered by UI → harvests tree/rock as before
- **NEW**: Click outside UI area while UI panel is visible → still registers as world click

**ascii_upgrade_panel.handle_click(x, y)** function:
```lua
function ascii_upgrade_panel.handle_click(x, y)
    -- Panel bounds (VIRTUAL screen space 1280×800, grid-aligned)
    -- NOTE: globals.screenWidth() = 1280 (VIRTUAL_WIDTH, not window)
    -- These should be module-level constants or calculated in init():
    local VIRTUAL_WIDTH = 1280
    local PANEL_WIDTH = 200   -- 10 tiles × 20px
    local PANEL_HEIGHT = 600  -- ~30 tiles (flexible, adjust as needed)
    local raw_x = VIRTUAL_WIDTH - PANEL_WIDTH  -- 1280 - 200 = 1080
    local panel_x = math.floor(raw_x / 20) * 20   -- Round down to 20px grid (1080 already aligned)
    local panel_y = 0  -- Top edge, already grid-aligned
    
    -- Check if click is within panel
    if x < panel_x or x > panel_x + PANEL_WIDTH then return false end
    if y < panel_y or y > panel_y + PANEL_HEIGHT then return false end
    
    -- Determine which upgrade slot was clicked
    local slot_height = 80  -- pixels per upgrade entry
    local clicked_slot = math.floor((y - panel_y + panel.scroll_offset) / slot_height)
    
    -- Check if BUY button area was clicked within that slot
    local buy_button_y = clicked_slot * slot_height + 60  -- BUY button at bottom of slot
    if y >= buy_button_y and y <= buy_button_y + 20 then
        local upgrade_id = panel.visible_upgrades[clicked_slot + 1]
        if upgrade_id then
            -- CORRECT API: upgrades.purchase(id, resources_module)
            local resources = require("idle_game.resources")
            upgrades.purchase(upgrade_id, resources)
            return true  -- Click consumed
        end
    end
    
    return false  -- Click not consumed
end
```

**Input API Reference (AUTHORITATIVE - use these exact patterns)**:

**Mouse input**:
- `input.getMousePos()` → returns `{x=number, y=number}` (virtual screen coordinates, matches Screen space)
- `input.isMousePressed(leftButton)` → boolean, where leftButton is:
  ```lua
  -- CANONICAL PATTERN (with fallback for safety):
  local leftButton = MouseButton and MouseButton.MOUSE_BUTTON_LEFT or 0
  local mouse_pressed = input.isMousePressed(leftButton)
  ```
  NOTE: Two different APIs exist - both are VALID in their contexts:
  - `input.isMousePressed(MouseButton.MOUSE_BUTTON_LEFT)` - Direct mouse state query
  - `input.bind("action", MouseButton.BUTTON_LEFT)` - Input mapping system (different API)
  Always use `MOUSE_BUTTON_LEFT` with the `or 0` fallback for `isMousePressed()` calls.

- `input.getMouseWheel()` → number (positive = scroll up, negative = scroll down)

**Keyboard input**:
- `_G.isKeyPressed(key_string)` → boolean
  ```lua
  -- CANONICAL PATTERN (with safety guard):
  local isKeyPressed = _G.isKeyPressed
  if isKeyPressed and isKeyPressed("KEY_DOWN") then
      -- handle key
  end
  ```
  Valid key strings: `"KEY_UP"`, `"KEY_DOWN"`, `"KEY_LEFT"`, `"KEY_RIGHT"`, `"KEY_W"`, `"KEY_S"`, 
  `"KEY_E"`, `"KEY_I"`, `"KEY_ESCAPE"`, `"KEY_ENTER"`, `"KEY_SPACE"`, etc.
  
  NOTE: `_G.isKeyPressed` is a global function exposed by the engine (defined in C++ bindings,
  documented in `chugget_code_definitions.lua:450`). Always guard with `if isKeyPressed and ...`.

**World coordinates** (for tile conversion):
- `camera.Get("world_camera"):GetMouseWorld()` → `{x=, y=}` world coordinates

**Key constraint**: Resource panel (top-left) is display-only, no click handling needed.

**Acceptance criteria for input routing**:
- Click on BUY button in upgrade panel → triggers `upgrades.purchase()` → NO tile behind it is harvested
- Click on world tile NOT covered by UI → harvests tree/rock as before
- Arrow keys (UP/DOWN or W/S) scroll the upgrade panel when mouse cursor is inside panel bounds (hover-based focus, no explicit focus state required)
- Mouse wheel scrolling IS supported - `input.getMouseWheel()` is exposed to Lua (see `src/systems/input/input_lua_bindings.cpp` - verify API during implementation)

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
├── Task 1.1: Verify CP437/dungeon sprite availability
├── Task 1.2: Create ASCII border component
└── Task 1.3: TDD: Achievement data module

Wave 2 (After Wave 1):
├── Task 2.1: ASCII resource panel (depends: 1.2)
├── Task 2.2: ASCII upgrade panel (depends: 1.2)
├── Task 2.3: Toast notification UI (depends: 1.2, 1.3)
└── Task 2.4: Achievement event hooks (depends: 1.3)

Wave 3 (After Wave 2):
├── Task 3.1: Miner creature type (no dependencies from Wave 2)
├── Task 3.2: Lumberjack creature type
├── Task 3.3: Collector creature type
└── Task 3.4: Builder creature type

Wave 4 (Final Integration):
├── Task 4.1: Achievement persistence
├── Task 4.2: Window resize for UI
└── Task 4.3: Integration testing

Critical Path: 1.2 → 2.1/2.2 → 4.2
Parallel Speedup: ~50% faster than sequential
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1.1 | None | 1.2 | 1.3 |
| 1.2 | 1.1 | 2.1, 2.2, 2.3 | 1.3 |
| 1.3 | None | 2.3, 2.4, 4.1 | 1.1, 1.2 |
| 2.1 | 1.2 | 4.2 | 2.2, 2.3, 2.4 |
| 2.2 | 1.2 | 4.2 | 2.1, 2.3, 2.4 |
| 2.3 | 1.2, 1.3 | None | 2.1, 2.2, 2.4 |
| 2.4 | 1.3 | 4.1 | 2.1, 2.2, 2.3 |
| 3.1-3.4 | None | 4.3 | Each other, Wave 2 |
| 4.1 | 1.3, 2.4 | 4.3 | 4.2 |
| 4.2 | 2.1, 2.2 | 4.3 | 4.1 |
| 4.3 | All above | None | None (final) |

---

## TODOs

### Phase 1: Foundation

- [ ] 1.1. Verify dungeon_437 sprite availability for borders

  **What to do**:
  - Confirm box drawing sprites exist in atlas (`sprites-0.json`)
  - Record exact sprite filenames from atlas (NOT wildcards)
  - Create lookup table in `idle_game/config.lua` for border sprites
  
  **Sprite filenames** (see VERIFIED REFERENCE INDEX at end of plan for verification):
  ```lua
  -- In config.lua, add:
  BORDER_SPRITES = {
      TOP_LEFT = "d437_218_box_down_r.png",       -- ┌ corner
      TOP = "d437_196_box_horiz.png",             -- ─ horizontal
      TOP_RIGHT = "d437_191_box_down_l.png",      -- ┐ corner
      LEFT = "d437_179_box_vert.png",             -- │ vertical
      RIGHT = "d437_179_box_vert.png",            -- │ vertical (same)
      BOTTOM_LEFT = "d437_217_box_up_l.png",      -- └ corner
      BOTTOM = "d437_196_box_horiz.png",          -- ─ horizontal (same as TOP)
      BOTTOM_RIGHT = "d437_192_box_up_r.png"      -- ┘ corner
  }
  -- NOTE: All sprite names verified via `grep -c "filename" assets/graphics/sprites-0.json`
  ```
  
  **SPRITE NAMING CONVENTION** (dungeon_437 atlas):
  - Corner sprites use `up/down` + `l/r` to indicate which direction the lines extend
  - `down_r` = lines extend down and right (top-left corner ┌)
  - `down_l` = lines extend down and left (top-right corner ┐)
  - `up_l` = lines extend up and left (bottom-left corner └)
  - `up_r` = lines extend up and right (bottom-right corner ┘)

  **Must NOT do**:
  - Use wildcard sprite names (e.g., `d437_216_*`)
  - Assume CP437 naming exists (atlas uses dungeon_437 naming)

  **OTHER SPRITE FILENAMES USED IN THIS PLAN** (verify during implementation):
  
  Task 1.1 verifies border sprites. The following sprites are also used and should be 
  verified via `grep -c "filename" assets/graphics/sprites-0.json`:
  
  | Sprite | Usage | Verified? |
  |--------|-------|-----------|
  | `d437_005_club.png` | Wood icon (resource panel) | Verify during Task 2.1 |
  | `d437_033_symbol_33.png` | Stone icon (config.SPRITE_ROCK) | Verify during Task 2.1 |
  | `d437_003_heart.png` | Food icon | Verify during Task 2.1 |
  | `d437_004_diamond.png` | Gold icon, marker structure | Verify during Task 2.1/3.4 |
  | `d437_015_sun.png` | Campfire structure | Verify during Task 3.4 |
  | `d437_186_box_vert_d.png` | Fence structure | Verify during Task 3.4 |
  
  **Pattern**: Before using any sprite filename, grep for it in `sprites-0.json` first.

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None needed (file inspection)

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with 1.3)
  - **Blocks**: 1.2
  - **Blocked By**: None

  **References**:
  - `assets/graphics/cp437_mappings.json` - CP437 character to index mapping (reference only)
  - `assets/graphics/sprites-0.json` - Sprite atlas metadata (authoritative source for filenames)
  - `assets/scripts/idle_game/config.lua` - Config location for sprite lookup

  **Acceptance Criteria**:
  ```bash
  # Verify EXACT border sprite filenames (as declared in BORDER_SPRITES above) exist in atlas
  # These MUST match the sprite names in BORDER_SPRITES config
  
  # Corners
  grep -c "d437_218_box_down_r.png" assets/graphics/sprites-0.json
  # Assert: Output is 1 (TOP_LEFT corner ┌)
  
  grep -c "d437_191_box_down_l.png" assets/graphics/sprites-0.json
  # Assert: Output is 1 (TOP_RIGHT corner ┐)
  
  grep -c "d437_217_box_up_l.png" assets/graphics/sprites-0.json
  # Assert: Output is 1 (BOTTOM_LEFT corner └)
  
  grep -c "d437_192_box_up_r.png" assets/graphics/sprites-0.json
  # Assert: Output is 1 (BOTTOM_RIGHT corner ┘)
  
  # Lines
  grep -c "d437_196_box_horiz.png" assets/graphics/sprites-0.json
  # Assert: Output is 1 (horizontal line ─)
  
  grep -c "d437_179_box_vert.png" assets/graphics/sprites-0.json
  # Assert: Output is 1 (vertical line │)
  ```

  **Commit**: NO (research task)

---

- [ ] 1.2. Create ASCII border component

  **What to do**:
  - Create `assets/scripts/idle_game/ui/ascii_border.lua`
  - Implement 9-tile assembled border rendering
  - Accept width/height in tiles (not pixels)
  - Render using `command_buffer.queueDrawSpriteTopLeft`
  - Support configurable sprite set (swap border styles)
  - All positions grid-aligned to 20px
  
  **API Design**:
  ```lua
  local ascii_border = require("idle_game.ui.ascii_border")
  
  -- Create a bordered panel at tile position (1, 0) with size 6x8 tiles
  local panel = ascii_border.create({
      x = 1,            -- tile X (multiplied by 20 internally)
      y = 0,            -- tile Y
      width = 6,        -- width in tiles
      height = 8,       -- height in tiles
      -- NOTE: Only "single_line" border style is supported per guardrails
      -- border_set parameter is reserved for future but defaults to single_line
      fill_color = Col(30, 30, 30, 200), -- optional background (Color userdata, NOT table)
      z_order = 100     -- render layer
  })
  
  -- Draw the border (call in scene draw loop)
  ascii_border.draw(panel)
  
  -- Cleanup
  ascii_border.destroy(panel)
  ```
  
  **Implementation approach**:
  - Store 9 sprite positions in `_borders` table
  - In `draw()`, queue 9 sprites:
    - 4 corners (fixed positions)
    - 4 edges (tiled/repeated as needed)
    - 1 center fill (optional colored rect via `command_buffer.queueDrawRectangle()`)
  - Grid alignment: all x,y positions = tile * TILE_SIZE (20)
  
  **Fill rendering (if fill_color provided)**:
  
  **Reference pattern**: `assets/scripts/ui/wand_resource_bar_ui.lua:270-276` (verify line numbers)
  
  ```lua
  -- Render semi-transparent background fill BEFORE border sprites
  -- c.color MUST be a Color userdata, NOT a Lua table
  if panel.fill_color then
      command_buffer.queueDrawRectangle(layers.sprites, function(c)
          c.x = panel.pixel_x
          c.y = panel.pixel_y
          c.width = panel.pixel_width
          c.height = panel.pixel_height
          c.color = panel.fill_color  -- Color userdata (created via Col() constructor)
      end, panel.z_order - 1, layer.DrawCommandSpace.Screen)
  end
  ```
  
  **CRITICAL: Color userdata construction**:
  - The engine exposes `Col(r, g, b, a)` constructor for creating Color userdata
  - `util.getColor(name)` returns Color userdata for named colors
  - DO NOT pass Lua tables `{r=, g=, b=, a=}` to `c.color` - it must be userdata
  
  **Creating semi-transparent dark background**:
  ```lua
  -- Option 1: Use global Col constructor (verified in: assets/scripts/idle_game/legacy/gameplay.lua:6961)
  local bg_color = Col(30, 30, 30, 200)
  
  -- Option 2: Modify existing color's alpha
  local bg_color = util.getColor("DARKGRAY"):setAlpha(200)
  ```

  **Must NOT do**:
  - Use nine-patch texture system
  - Support non-grid-aligned positions
  - Make border interactive (just visual)

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: `frontend-ui-ux`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with 1.1, 1.3)
  - **Blocks**: 2.1, 2.2, 2.3
  - **Blocked By**: 1.1 (sprite verification)

  **References**:

  **Pattern References** (existing code to follow):
  - `assets/scripts/idle_game/terrain_renderer.lua:57-80` - Sprite rendering pattern (shows exact `queueDrawSpriteTopLeft` usage with `layer.DrawCommandSpace.World`)

  **API/Type References** (contracts to implement against):
  - `assets/scripts/chugget_code_definitions.lua:8661` - `queueDrawSpriteTopLeft` function signature
  - `assets/scripts/idle_game/config.lua` - TILE_SIZE constant (20)

  **Integration Reference**:
  - `assets/scripts/idle_game/scenes/sim_scene.lua:126-138` - Where to integrate ASCII panel draw calls (after terrain, before ImGui)

  **WHY Each Reference Matters**:
  - `terrain_renderer.lua:57-80`: Copy this exact pattern but change `DrawCommandSpace.World` → `DrawCommandSpace.Screen` for UI
  - `sim_scene.lua:126-138`: Shows draw order - ASCII panels slot between terrain and ImGui panels

  **Acceptance Criteria**:
  
  **Automated test** (create file: `assets/scripts/tests/test_idle_ascii_border.lua`):
  ```lua
  -- test_idle_ascii_border.lua
  -- Run: lua assets/scripts/tests/test_idle_ascii_border.lua
  
  -- Path setup (copy from test_idle_terrain.lua:14-24)
  local script_dir = arg[0]:match("(.*/)")
  if not script_dir then script_dir = "./" end
  package.path = script_dir .. "../external/?.lua;" .. script_dir .. "../external/?/init.lua;" .. package.path
  package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"
  
  local ascii_border = require("idle_game.ui.ascii_border")
  local panel = ascii_border.create({x=1, y=0, width=6, height=4})
  
  -- Verify grid alignment
  assert(panel.pixel_x == 20, "X not grid-aligned")
  assert(panel.pixel_y == 0, "Y not grid-aligned")
  assert(panel.pixel_width == 120, "Width not correct (6 * 20)")
  assert(panel.pixel_height == 80, "Height not correct (4 * 20)")
  
  print("Border component test passed")
  ```
  
  **Run command**: `lua assets/scripts/tests/test_idle_ascii_border.lua`
  
  **Manual Verification**:
  - Launch game
  - Observe bordered panel renders at top-left
  - Border corners and edges align perfectly to grid
  - Screenshot: `.sisyphus/evidence/task-1.2-border.png`

  **Commit**: YES
  - Message: `feat(idle-ui): add ASCII border component with 9-tile assembly`
  - Files: `assets/scripts/idle_game/ui/ascii_border.lua`
  - Pre-commit: `just build-debug`

---

- [ ] 1.3. TDD: Achievement data module

  **What to do**:
  - Write tests in `assets/scripts/tests/test_idle_achievements.lua`
  - Create `assets/scripts/idle_game/achievements.lua`
  
  **UNIFIED ACHIEVEMENT MODULE API CONTRACT** (authoritative):
  
  ```lua
  -- achievements.lua public API
  
  -- Registration (called at module load time)
  achievements.define(id, {name, description, condition, icon})  -- Register achievement definition
  
  -- Query
  achievements.get(id) -> definition or nil               -- Get single achievement definition
  achievements.get_all() -> {[id] = definition}           -- Get all definitions
  achievements.get_unlocked() -> {id, id, ...}            -- List of unlocked achievement IDs
  achievements.is_unlocked(id) -> boolean                 -- Check if specific achievement unlocked
  
  -- State mutation
  achievements.unlock(id)                                 -- Mark achievement as unlocked (idempotent)
  achievements.add_playtime(dt)                           -- Increment playtime counter (for time achievements)
  
  -- Condition checking (returns list of NEWLY unlocked achievements)
  achievements.check_resource_achievements(resource, amount) -> {definition, ...}
  achievements.check_upgrade_achievements(upgrade_id, level) -> {definition, ...}
  achievements.check_creature_achievements() -> {definition, ...}  -- Queries spawner.getTotalCreatureCount() internally
  achievements.check_time_achievements() -> {definition, ...}
  achievements.check_all() -> {definition, ...}           -- Check ALL condition types
  
  -- NOTE: check_creature_achievements() takes NO parameters. It always queries 
  -- spawner.getTotalCreatureCount() internally. This simplifies the listener code
  -- and ensures consistency (no risk of passing stale count).
  
  -- Internal state (for SaveManager collector)
  achievements._unlocked = {}        -- SET: {[id] = true}
  achievements._playtime = 0         -- Seconds of playtime
  ```
  
  **NUMERIC/ROUNDING POLICY** (for threshold comparisons):
  
  | Value Type | Storage | Threshold Comparison | UI Display |
  |------------|---------|---------------------|------------|
  | Resources (wood, stone, food) | Integer | Exact: `>=` against integer threshold | Integer |
  | Gold | Float (from `gold_rate * dt`) | Floor before compare: `math.floor(gold) >= threshold` | Floored integer |
  | Playtime | Float (seconds) | Floor before compare: `math.floor(seconds) >= threshold` | Formatted as "Xm Ys" |
  | Creature count | Integer | Exact: `>=` against integer threshold | Integer |
  
  **Implementation rule**: All achievement threshold comparisons use `>=` operator.
  For float values (gold, playtime), **floor before comparison** to avoid edge cases like
  9.9999 triggering a threshold of 10.
  
  ```lua
  -- Example: gold achievement check
  function achievements.check_resource_achievements(resource, amount)
      local compare_amount = (resource == "gold") and math.floor(amount) or amount
      for id, def in pairs(definitions) do
          if def.condition.resource == resource and compare_amount >= def.condition.amount then
              -- Check unlocked, etc.
          end
      end
  end
  ```
  
  **Test cases (RED phase)**:
  1. `achievements.define()` registers achievement with id, name, description, condition
  2. `achievements.get(id)` returns definition or nil
  3. `achievements.unlock(id)` marks achievement as unlocked (idempotent, second call is no-op)
  4. `achievements.is_unlocked(id)` returns unlock status
  5. `achievements.get_all()` returns all achievement definitions
  6. `achievements.get_unlocked()` returns list of unlocked achievement IDs
  7. `achievements.add_playtime(dt)` accumulates playtime, `achievements._playtime` reflects total
  8. `achievements.check_resource_achievements()` returns NEWLY unlocked (empty if already unlocked)
  9. `achievements.check_all()` calls all check_*_achievements and returns combined list
  10. Achievement conditions work for 4 categories:
      - Resource thresholds: `{type="resource", resource="wood", amount=100}`
      - Upgrade milestones: `{type="upgrade", upgrade="click_wood", level=5}`
      - Creature population: `{type="creatures", count=10}` - **DEFERRED to Wave 3**
      - Time-based: `{type="time", seconds=300}`
  
  **NOTE on creature count achievements**: The `{type="creatures"}` condition depends on 
  `spawner.getTotalCreatureCount()` which is added in Wave 3. Task 1.3 tests should MOCK
  this function or SKIP creature-count tests until Wave 3 is complete.
  
  **Recommended approach for Task 1.3 TDD**:
  ```lua
  -- In test_idle_achievements.lua, mock spawner for creature tests
  t.describe("Creature achievements (requires Wave 3)", function()
      local original_spawner = package.loaded["idle_game.spawner"]
      
      t.before_each(function()
          -- Mock spawner with getTotalCreatureCount
          package.loaded["idle_game.spawner"] = {
              getTotalCreatureCount = function() return 15 end  -- Mock value
          }
      end)
      
      t.after_each(function()
          package.loaded["idle_game.spawner"] = original_spawner
      end)
      
      t.it("unlocks creature achievement when count threshold met", function()
          -- Test with mocked spawner
      end)
  end)
  ```
  
  **Creature count semantics** (for `{type="creatures", count=N}` achievements):
  - Count = **total living creatures across ALL types** (forager + miner + lumberjack + collector + builder)
  - Source: Query `spawner.getTotalCreatureCount()` (new function to add)
  
  **CURRENT spawner.lua tracking tables** (verify by grepping spawner.lua during implementation):
  - `spawner._foragers` = {} - exists (search: `_foragers = {}`)
  - `spawner._corpses` = {} - exists (search: `_corpses = {}`)
  - `spawner._pending_destroy` = {} - exists (search: `_pending_destroy = {}`)
  - `spawner._miners`, `_lumberjacks`, `_collectors`, `_builders` = **DO NOT EXIST YET** - must add
  
  **Required additions to spawner.lua** (Tasks 3.1-3.4):
  ```lua
  -- ADD these tracking tables at module level
  spawner._miners = {}
  spawner._lumberjacks = {}
  spawner._collectors = {}
  spawner._builders = {}
  
  -- ADD count functions (follow getForagerCount pattern - cleans invalid entities)
  function spawner.getMinerCount()
      local count = 0
      for e, _ in pairs(spawner._miners) do
          if registry:valid(e) then count = count + 1
          else spawner._miners[e] = nil end  -- Clean up invalid
      end
      return count
  end
  -- (repeat pattern for lumberjack, collector, builder)
  
  -- ADD spawn functions (naming convention matches existing spawnForagerAt/spawnForagers)
  function spawner.spawnMinerAt(px, py) ... end   -- single spawn at pixel coords
  function spawner.spawnMiners(count) ... end     -- batch spawn at random positions
  function spawner.spawnLumberjackAt(px, py) ... end
  function spawner.spawnLumberjacks(count) ... end
  function spawner.spawnCollectorAt(px, py) ... end
  function spawner.spawnCollectors(count) ... end
  function spawner.spawnBuilderAt(px, py) ... end
  function spawner.spawnBuilders(count) ... end
  
  -- ADD total count function
  function spawner.getTotalCreatureCount()
      return spawner.getForagerCount() 
           + spawner.getMinerCount() 
           + spawner.getLumberjackCount()
           + spawner.getCollectorCount()
           + spawner.getBuilderCount()
  end
  ```
  
  **"Living creatures" definition**: Entities in tracking tables that pass `registry:valid(e)`.
  Corpses (`spawner._corpses`) are NOT counted.
  
  **AUTHORITATIVE ACHIEVEMENT LIST** (exactly 12 achievements to implement):
  
  > This is the complete list. Implement ALL 12. Do NOT add or remove achievements.
  
  | ID | Name | Description | Condition | Icon |
  |----|------|-------------|-----------|------|
  | `first_wood` | First Harvest | Collect 10 wood | `{type="resource", resource="wood", amount=10}` | `d437_005_club.png` |
  | `wood_hoarder` | Wood Hoarder | Collect 100 wood | `{type="resource", resource="wood", amount=100}` | `d437_005_club.png` |
  | `stone_age` | Stone Age | Collect 50 stone | `{type="resource", resource="stone", amount=50}` | `d437_033_symbol_33.png` |
  | `first_meal` | First Meal | Collect 20 food | `{type="resource", resource="food", amount=20}` | `d437_003_heart.png` |
  | `wealthy` | Wealthy | Collect 500 gold | `{type="resource", resource="gold", amount=500}` | `d437_004_diamond.png` |
  | `upgrade_novice` | Upgrade Novice | Purchase any upgrade | `{type="upgrade", any=true, level=1}` | `d437_024_up_arrow.png` |
  | `upgrade_master` | Upgrade Master | Max out any upgrade | `{type="upgrade", any=true, level=10}` | `d437_024_up_arrow.png` |
  | `growing_tribe` | Growing Tribe | Have 10 creatures | `{type="creatures", count=10}` | `d437_001_face.png` |
  | `full_house` | Full House | Have 20 creatures | `{type="creatures", count=20}` | `d437_001_face.png` |
  | `getting_started` | Getting Started | Play for 1 minute | `{type="time", seconds=60}` | `d437_015_sun.png` |
  | `dedicated` | Dedicated | Play for 10 minutes | `{type="time", seconds=600}` | `d437_015_sun.png` |
  | `veteran` | Veteran | Play for 30 minutes | `{type="time", seconds=1800}` | `d437_015_sun.png` |
  
  **Achievement check semantics**:
  - `any=true` for upgrades: Triggers when ANY upgrade reaches the specified level
  - The checker scans all upgrades and returns true if any meets the condition
  - Example: `{type="upgrade", any=true, level=10}` triggers when click_wood=10 OR click_stone=10 OR etc.
  
  **Code implementation** (in achievements.lua module init):
  ```lua
  -- Register all 12 achievements at module load
  local ACHIEVEMENT_DEFS = {
      {id = "first_wood", name = "First Harvest", desc = "Collect 10 wood", 
       condition = {type = "resource", resource = "wood", amount = 10}, icon = "d437_005_club.png"},
      {id = "wood_hoarder", name = "Wood Hoarder", desc = "Collect 100 wood", 
       condition = {type = "resource", resource = "wood", amount = 100}, icon = "d437_005_club.png"},
      {id = "stone_age", name = "Stone Age", desc = "Collect 50 stone", 
       condition = {type = "resource", resource = "stone", amount = 50}, icon = "d437_033_symbol_33.png"},
      {id = "first_meal", name = "First Meal", desc = "Collect 20 food", 
       condition = {type = "resource", resource = "food", amount = 20}, icon = "d437_003_heart.png"},
      {id = "wealthy", name = "Wealthy", desc = "Collect 500 gold", 
       condition = {type = "resource", resource = "gold", amount = 500}, icon = "d437_004_diamond.png"},
      {id = "upgrade_novice", name = "Upgrade Novice", desc = "Purchase any upgrade", 
       condition = {type = "upgrade", any = true, level = 1}, icon = "d437_024_up_arrow.png"},
      {id = "upgrade_master", name = "Upgrade Master", desc = "Max out any upgrade", 
       condition = {type = "upgrade", any = true, level = 10}, icon = "d437_024_up_arrow.png"},
      {id = "growing_tribe", name = "Growing Tribe", desc = "Have 10 creatures", 
       condition = {type = "creatures", count = 10}, icon = "d437_001_face.png"},
      {id = "full_house", name = "Full House", desc = "Have 20 creatures", 
       condition = {type = "creatures", count = 20}, icon = "d437_001_face.png"},
      {id = "getting_started", name = "Getting Started", desc = "Play for 1 minute", 
       condition = {type = "time", seconds = 60}, icon = "d437_015_sun.png"},
      {id = "dedicated", name = "Dedicated", desc = "Play for 10 minutes", 
       condition = {type = "time", seconds = 600}, icon = "d437_015_sun.png"},
      {id = "veteran", name = "Veteran", desc = "Play for 30 minutes", 
       condition = {type = "time", seconds = 1800}, icon = "d437_015_sun.png"},
  }
  
  for _, def in ipairs(ACHIEVEMENT_DEFS) do
      achievements.define(def.id, {
          name = def.name,
          description = def.desc,
          condition = def.condition,
          icon = def.icon
      })
  end
  ```

  **Must NOT do**:
  - Implement UI yet (data module only)
  - Add persistence yet (Wave 4)
  - Create more than 12 achievements total

  **HEADLESS-TEST BOUNDARY REQUIREMENTS** (CRITICAL for TDD):
  
  The achievements module is a pure data module and MUST be fully testable in headless Lua:
  
  **Required design**:
  - NO engine globals (`command_buffer`, `layers`, `util`, `Col`, etc.) at require-time
  - Dependencies on other idle_game modules (resources, upgrades, spawner) should be 
    lazy-loaded inside check functions, NOT at module load time
  - Tests can mock these dependencies via `package.loaded[]` manipulation
  
  ```lua
  -- achievements.lua - HEADLESS-SAFE pattern
  local achievements = {}
  achievements._definitions = {}
  achievements._unlocked = {}
  achievements._playtime = 0
  
  function achievements.check_resource_achievements(resource, amount)
      -- Lazy-load resources only when needed (allows test mocking)
      local resources = require("idle_game.resources")
      -- ... check logic ...
  end
  
  -- SaveManager registration happens at module level but is guarded:
  local function register_save_collector()
      local ok, SaveManager = pcall(require, "core.save_manager")
      if ok and SaveManager and SaveManager.register then
          SaveManager.register("achievements", { ... })
      end
  end
  register_save_collector()
  
  return achievements
  ```
  
  **Test mocking pattern**:
  ```lua
  -- In test file, mock resources before requiring achievements
  package.loaded["idle_game.resources"] = {
      get = function(type) return 100 end  -- Mock: always has 100 of everything
  }
  local achievements = require("idle_game.achievements")
  ```

  **TEST ISOLATION STRATEGY (MANDATORY for test_idle_achievements.lua)**:
  
  Tests MUST reset achievement module state between test cases to prevent cross-test contamination.
  
  **Reset mechanism** (add to test file):
  ```lua
  -- test_idle_achievements.lua
  local t = require("tests.test_runner")
  
  -- Helper to reset achievements module to clean state
  local function reset_achievements()
      -- Clear cached module to force fresh require
      package.loaded["idle_game.achievements"] = nil
      
      -- Re-require gets fresh module with empty state:
      -- _definitions = {}
      -- _unlocked = {}  
      -- _playtime = 0
      local achievements = require("idle_game.achievements")
      return achievements
  end
  
  t.describe("Achievement System", function()
      t.before_each(function()
          -- Fresh achievements module for each test
          _G._test_achievements = reset_achievements()
      end)
      
      t.it("defines achievement with id and condition", function()
          local achievements = _G._test_achievements
          achievements.define("test_ach", { name = "Test", condition = { type = "resource", resource = "wood", amount = 10 } })
          assert(achievements.get("test_ach") ~= nil)
      end)
      
      t.it("unlock is idempotent", function()
          local achievements = _G._test_achievements
          achievements.define("test_ach", { name = "Test", condition = {} })
          achievements.unlock("test_ach")
          achievements.unlock("test_ach")  -- Second call should be no-op
          assert(achievements.is_unlocked("test_ach") == true)
      end)
      
      -- ... more tests using _G._test_achievements ...
  end)
  ```
  
  **Why `package.loaded[] = nil` works**:
  - Lua's `require()` caches modules in `package.loaded`
  - Setting to `nil` clears the cache, forcing next `require()` to re-execute module file
  - Module re-execution resets all module-level state (`_definitions = {}`, etc.)
  
  **Alternative (explicit reset function)**:
  If module reload is too slow, add an explicit reset function to achievements.lua:
  ```lua
  -- In achievements.lua (for testing only)
  function achievements._reset_for_testing()
      achievements._definitions = {}
      achievements._unlocked = {}
      achievements._playtime = 0
  end
  ```
  Then call `achievements._reset_for_testing()` in `before_each()`.

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with 1.1, 1.2)
  - **Blocks**: 2.3, 2.4, 4.1
  - **Blocked By**: None

  **References**:
  - `assets/scripts/idle_game/upgrades.lua:1-170` - Similar data module pattern
  - `assets/scripts/idle_game/resources.lua:1-105` - Resource tracking pattern
  - `assets/scripts/tests/test_idle_terrain.lua` - Test file pattern

  **Acceptance Criteria**:
  
  Test file MUST follow the existing test pattern from `test_idle_terrain.lua`:
  ```lua
  -- test_idle_achievements.lua (follows standard test structure)
  -- Setup path (copy from test_idle_terrain.lua:14-24)
  local script_dir = arg[0]:match("(.*/)")
  if not script_dir then script_dir = "./" end
  package.path = script_dir .. "../external/?.lua;" .. script_dir .. "../external/?/init.lua;" .. package.path
  package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"
  
  local t = require("tests.test_runner")
  
  t.describe("Achievement System", function()
      t.it("defines achievement with id and condition", function()
          local achievements = require("idle_game.achievements")
          -- test implementation
      end)
      -- ... 6 more tests
  end)
  
  t.run()
  ```
  
  Run test:
  ```bash
  lua assets/scripts/tests/test_idle_achievements.lua
  # Assert: Output contains "passed" and no "FAILED"
  ```

  **Commit**: YES
  - Message: `feat(idle): add TDD achievement data module`
  - Files: `assets/scripts/idle_game/achievements.lua`, `assets/scripts/tests/test_idle_achievements.lua`
  - Pre-commit: `lua assets/scripts/tests/test_idle_achievements.lua`

---

### Phase 2: UI Panels

- [ ] 2.1. ASCII resource panel

  **What to do**:
  - Create `assets/scripts/idle_game/ui/ascii_resource_panel.lua`
  - Position: top-left corner, starting at tile (0, 0)
  - Size: ~8 tiles wide, 6 tiles tall (160x120 pixels)
  - Display 4 resources with:
    - ASCII icon sprite (tree for wood, rock for stone, etc.)
    - Resource name
    - Current amount
    - Per-second rate (if > 0)
  - Use ascii_border component for panel frame
  - Earthy color scheme: browns, greens, gold text
  - Semi-transparent background (game visible behind)
  
  **Layout (tile-based)**:
  ```
  ┌──────────────┐  <- Tile (0,0) to (7,0)
  │ 🌲 Wood: 150 │  <- Icon + text
  │ 🪨 Stone: 42 │
  │ 🍎 Food: 88  │
  │ 🪙 Gold: 5.2 │
  │  +0.5/s      │  <- Rate display
  └──────────────┘
  ```
  
  **Icon sprites** (use exact filenames from `idle_game/config.lua` and atlas):
  - Wood: `d437_005_club.png` (♣ tree/club - matches config.SPRITE_TREE)
  - Stone: `d437_033_symbol_33.png` (#  - matches config.SPRITE_ROCK)
  - Food: `d437_003_heart.png` (♥ heart - use for food/life)
  - Gold: `d437_004_diamond.png` (♦ diamond - use for gold/currency)
  
  **API**:
  ```lua
  local resource_panel = require("idle_game.ui.ascii_resource_panel")
  resource_panel.init()  -- Call once
  resource_panel.draw()  -- Call each frame
  ```

  **Must NOT do**:
  - Remove existing ImGui resource_panel.lua
  - Make panel draggable
  - Add click interactions to panel

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: `frontend-ui-ux`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with 2.2, 2.3, 2.4)
  - **Blocks**: 4.2
  - **Blocked By**: 1.2 (border component)

  **References**:
  - `assets/scripts/idle_game/ui/resource_panel.lua:1-67` - Current ImGui version (data access pattern)
  - `assets/scripts/idle_game/ui/ascii_border.lua` - Border component (Task 1.2)
  - `assets/scripts/idle_game/resources.lua` - Resource API

  **Acceptance Criteria** (**IN-ENGINE test** - panel.init() may touch engine globals):
  
  Run via sim_scene init hook or dev console (NOT headless `lua`):
  ```lua
  -- Grid alignment verification
  local panel = require("idle_game.ui.ascii_resource_panel")
  panel.init()
  
  -- Check panel position is grid-aligned
  assert(panel.x % 20 == 0, "Panel X not grid-aligned")
  assert(panel.y % 20 == 0, "Panel Y not grid-aligned")
  assert(panel.width % 20 == 0, "Panel width not grid-aligned")
  assert(panel.height % 20 == 0, "Panel height not grid-aligned")
  
  print("Resource panel grid alignment passed")
  ```
  
  **Manual Verification** (visual confirmation):
  - Launch game
  - Resource panel visible at top-left with ASCII border
  - Shows all 4 resources with icons
  - Numbers update as resources change
  - Screenshot: `.sisyphus/evidence/task-2.1-resource-panel.png`

  **Commit**: YES
  - Message: `feat(idle-ui): add ASCII resource panel with icons`
  - Files: `assets/scripts/idle_game/ui/ascii_resource_panel.lua`

---

- [ ] 2.2. ASCII upgrade panel

  **What to do**:
  - Create `assets/scripts/idle_game/ui/ascii_upgrade_panel.lua`
  - Position: right side of screen (sidebar) in VIRTUAL coordinates
    - x = 1280 - 200 = 1080 (VIRTUAL_WIDTH - panel_width)
    - y = 0
  - Size: ~10 tiles wide, full height (200px wide = 10 tiles × 20px, flexible height)
  - Display all 12 upgrades in scrollable list
  - Each upgrade shows:
    - Name (text)
    - Current level / max level
    - Cost (resource icons + amounts)
    - Buy button (clickable area)
  - Use ascii_border component for panel frame
  - Scroll support for overflow
  
  **Layout**:
  ```
  ┌─────────────────┐  <- Right edge of screen
  │ UPGRADES        │
  ├─────────────────┤
  │ Stronger Axe    │
  │ Lv. 2/10        │
  │ Cost: 🪵15      │
  │ [BUY]           │  <- Clickable
  ├─────────────────┤
  │ Better Pickaxe  │
  │ ...             │
  └─────────────────┘
  ```
  
  **UPGRADE ORDERING CONTRACT (AUTHORITATIVE)**:
  
  > This is critical for deterministic slot→upgrade mapping. The executor MUST follow this exactly.
  
  `upgrades.get_all()` returns a Lua table iterated via `pairs()` which has **non-deterministic order**.
  The upgrade panel MUST impose a deterministic ordering.
  
  **REQUIRED: Sort upgrades by ID alphabetically**
  
  ```lua
  -- In ascii_upgrade_panel.lua
  function ascii_upgrade_panel._get_ordered_upgrades()
      local all = upgrades.get_all()
      local ordered = {}
      for id, def in pairs(all) do
          table.insert(ordered, {id = id, def = def})
      end
      -- Sort alphabetically by ID for deterministic order
      table.sort(ordered, function(a, b) return a.id < b.id end)
      return ordered
  end
  
  -- This ordered list is used for BOTH:
  -- 1. Rendering (slot 0 = first in ordered list)
  -- 2. Click handling (clicked_slot → ordered[clicked_slot + 1].id)
  ```
  
  **Resulting order** (alphabetical by upgrade ID):
  | Slot | Upgrade ID | Display Name |
  |------|------------|--------------|
  | 0 | `auto_harvest` | Auto Harvest |
  | 1 | `build_speed` | Build Speed |
  | 2 | `click_food` | Food Efficiency |
  | 3 | `click_gold` | Gold Rush |
  | 4 | `click_stone` | Mining Strength |
  | 5 | `click_wood` | Woodcutting |
  | 6 | `collector_speed` | Collector Speed |
  | 7 | `creature_spawn` | Population Growth |
  | 8 | `forager_efficiency` | Forager Efficiency |
  | 9 | `lumberjack_speed` | Lumberjack Speed |
  | 10 | `miner_speed` | Miner Speed |
  | 11 | `passive_income` | Passive Income |
  
  > Note: These upgrade IDs are examples based on typical incremental game patterns.
  > Verify the actual upgrade IDs by inspecting `idle_game/upgrades.lua` during implementation.
  > The SORTING RULE (alphabetical by ID) is authoritative; the specific IDs may differ.
  
  **Click-to-purchase mapping**:
  ```lua
  function ascii_upgrade_panel.handle_click(x, y)
      -- ... hit testing to get clicked_slot (0-indexed from top of visible area)
      
      -- Map slot to upgrade ID using the SAME ordered list used for rendering
      local ordered = ascii_upgrade_panel._get_ordered_upgrades()
      local visible_start = panel.scroll_offset  -- First visible slot index
      local actual_index = visible_start + clicked_slot + 1  -- Lua 1-indexed
      
      if ordered[actual_index] then
          local upgrade_id = ordered[actual_index].id
          upgrades.purchase(upgrade_id)
          return true  -- Consumed click
      end
      return false  -- Click not handled
  end
  ```
  
  **Scroll implementation**:
  - Track scroll offset in tiles
  - Render only visible upgrades
  - Arrow key scrolling AND mouse wheel scrolling (both supported)
  
  **Scroll input APIs** (reference patterns from codebase):
  ```lua
  -- Arrow key detection using global isKeyPressed function
  -- Reference: assets/scripts/ui/wand_panel.lua:1706-1720, assets/scripts/ui/player_inventory.lua:1044-1045
  local isKeyPressed = _G.isKeyPressed
  
  function ascii_upgrade_panel.update(dt)
      -- KEY_UP / KEY_DOWN for scrolling (string keys, not KeyboardKey enum)
      if isKeyPressed and isKeyPressed("KEY_UP") then
          panel.scroll_offset = math.max(0, panel.scroll_offset - 1)
      elseif isKeyPressed and isKeyPressed("KEY_DOWN") then
          panel.scroll_offset = math.min(panel.max_scroll, panel.scroll_offset + 1)
      end
      
      -- W/S as alternatives (common game pattern)
      if isKeyPressed and isKeyPressed("KEY_W") then
          panel.scroll_offset = math.max(0, panel.scroll_offset - 1)
      elseif isKeyPressed and isKeyPressed("KEY_S") then
          panel.scroll_offset = math.min(panel.max_scroll, panel.scroll_offset + 1)
      end
  end
  ```
  
  **Mouse wheel scrolling** (CORRECTED - IS available):
  - `input.getMouseWheel()` IS exposed to Lua (bound to `GetMouseWheelMove()` in 
    `src/systems/input/input_lua_bindings.cpp:~413`)
  - Upgrade panel should support BOTH keyboard (arrow keys, W/S) AND mouse wheel scrolling
  
  **Complete scrolling implementation** (inside `ascii_upgrade_panel.update(dt)`):
  ```lua
  function ascii_upgrade_panel.update(dt)
      -- Hover detection for keyboard focus
      local mouse = input.getMousePos()
      local is_hovered = panel.contains_point(mouse.x, mouse.y)
      
      -- Mouse wheel scrolling (works when hovered)
      if is_hovered then
          local wheel = input.getMouseWheel and input.getMouseWheel() or 0
          if wheel ~= 0 then
              panel.scroll_offset = panel.scroll_offset - wheel  -- Negative wheel = scroll down
              panel.scroll_offset = math.max(0, math.min(panel.max_scroll, panel.scroll_offset))
          end
          
          -- Keyboard scrolling (only when hovered - no explicit focus state needed)
          local isKeyPressed = _G.isKeyPressed
          if isKeyPressed then
              if isKeyPressed("KEY_UP") or isKeyPressed("KEY_W") then
                  panel.scroll_offset = math.max(0, panel.scroll_offset - 1)
              elseif isKeyPressed("KEY_DOWN") or isKeyPressed("KEY_S") then
                  panel.scroll_offset = math.min(panel.max_scroll, panel.scroll_offset + 1)
              end
          end
      end
  end
  
  -- Helper function for bounds checking
  function ascii_upgrade_panel.contains_point(x, y)
      return x >= panel.x and x < panel.x + panel.width
         and y >= panel.y and y < panel.y + panel.height
  end
  ```
  
  **SCROLLING OWNERSHIP**: This module handles ALL scrolling. `sim_scene.update(dt)` only calls 
  `ascii_upgrade_panel.update(dt)` - no additional scrolling logic in sim_scene.
  
  **API**:
  ```lua
  local upgrade_panel = require("idle_game.ui.ascii_upgrade_panel")
  upgrade_panel.init()
  upgrade_panel.update(dt)  -- Handle input
  upgrade_panel.draw()
  ```

  **Must NOT do**:
  - Remove existing ImGui upgrade_panel.lua
  - Implement drag-to-reorder
  - Add category tabs (keep single list)

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: `frontend-ui-ux`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with 2.1, 2.3, 2.4)
  - **Blocks**: 4.2
  - **Blocked By**: 1.2 (border component)

  **References**:
  - `assets/scripts/idle_game/ui/upgrade_panel.lua:1-49` - Current ImGui version
  - `assets/scripts/idle_game/upgrades.lua` - Upgrade API
  - `assets/scripts/idle_game/ui/ascii_border.lua` - Border component

  **Acceptance Criteria** (**IN-ENGINE test** - panel.init() touches engine globals):
  
  Run via sim_scene init hook or dev console (NOT headless `lua`):
  ```lua
  -- Verify all 12 upgrades accessible
  local upgrades = require("idle_game.upgrades")
  local all = upgrades.get_all()
  local count = 0
  for _ in pairs(all) do count = count + 1 end
  assert(count == 12, "Expected 12 upgrades, got " .. count)
  
  -- Verify panel scrolling via update() with simulated key press
  local panel = require("idle_game.ui.ascii_upgrade_panel")
  panel.init()
  
  -- Store initial offset
  local initial_offset = panel._scroll_offset or 0
  
  -- Simulate DOWN key press (mock isKeyPressed for test)
  local old_isKeyPressed = _G.isKeyPressed
  _G.isKeyPressed = function(key) return key == "KEY_DOWN" end
  panel.update(0.016)  -- One frame
  _G.isKeyPressed = old_isKeyPressed  -- Restore
  
  -- Verify scroll changed (if there's content to scroll)
  -- Note: scroll may not change if panel fits all 12 upgrades
  print("Upgrade panel scroll test completed (manual visual verification recommended)")
  ```
  
  **STANDARDIZED TEST INTERFACE (applies to all ASCII UI modules)**:
  
  Each ASCII UI module (`ascii_resource_panel`, `ascii_upgrade_panel`, `toast_notification`) 
  MUST expose these fields for in-engine testing:
  
  | Field | Type | Purpose |
  |-------|------|---------|
  | `module.x` | number | Panel x position (virtual pixels) |
  | `module.y` | number | Panel y position (virtual pixels) |
  | `module.width` | number | Panel width (virtual pixels) |
  | `module.height` | number | Panel height (virtual pixels) |
  | `module._scroll_offset` | number | (upgrade panel only) Current scroll offset |
  | `module._queue` | table | (toast only) Current toast queue |
  
  These fields are prefixed with `_` to indicate "internal but test-accessible".
  Production code should use public APIs (`init()`, `update(dt)`, `draw()`).
  
  **Manual Verification** (visual confirmation):
  - Launch game
  - Upgrade panel visible on right side
  - Can scroll through all 12 upgrades
  - Click buy button successfully purchases upgrade
  - Screenshot: `.sisyphus/evidence/task-2.2-upgrade-panel.png`

  **Commit**: YES
  - Message: `feat(idle-ui): add ASCII upgrade panel with scrolling`
  - Files: `assets/scripts/idle_game/ui/ascii_upgrade_panel.lua`

---

- [ ] 2.3. Toast notification UI

  **What to do**:
  - Create `assets/scripts/idle_game/ui/toast_notification.lua`
  - Position: top-center of screen (above resource panel)
  - Queue system: multiple toasts stack vertically
  - Each toast shows:
    - Achievement icon
    - Achievement name
    - Brief description
  - Auto-dismiss after 3 seconds
  - Use ascii_border for toast frame
  - Fade-in/fade-out animation
  
  **Layout**:
  ```
         ┌────────────────────┐
         │ 🏆 First Harvest   │
         │ Collect 10 wood    │
         └────────────────────┘
                  ↓ (next toast slides up)
  ```
  
  **API**:
  ```lua
  local toast = require("idle_game.ui.toast_notification")
  
  toast.show({
      icon = "d437_015_sun.png",  -- ☼ sun symbol (verify exists in sprites-0.json)
      title = "First Harvest",
      description = "Collect 10 wood",
      duration = 3.0
  })
  
  toast.update(dt)  -- Handle fade/slide animations ONLY (auto-dismiss via timer.after)
  toast.draw()
  ```

  **Must NOT do**:
  - Play sound effects (defer)
  - Allow clicking to dismiss
  - Show more than 3 toasts simultaneously

  **HEADLESS-TEST BOUNDARY REQUIREMENTS** (CRITICAL for TDD):
  
  Toast module MUST be structured so that `show()`, `update()`, `_dismiss()` can run 
  in headless Lua (test runner) WITHOUT engine globals.
  
  **Required separation**:
  ```lua
  -- toast_notification.lua
  
  -- Initialization (idempotent, safe to call multiple times):
  function toast.init()
      toast._queue = toast._queue or {}  -- Only init if not already done
      toast._next_id = toast._next_id or 1
  end
  
  -- These functions are ENGINE-INDEPENDENT (can run in tests):
  function toast.show(opts)         -- Adds to queue, schedules timer
  function toast.update(dt)         -- Updates animation state (fade progress)
  function toast._dismiss(id)       -- Removes from queue
  function toast._get_queue()       -- Returns queue for test inspection
  
  -- This function REQUIRES ENGINE (guards nil globals):
  function toast.draw()
      -- Guard for headless testing
      if not command_buffer or not layers then return end
      
      -- Actual rendering with command_buffer.queueDrawSpriteTopLeft, etc.
  end
  ```
  
  **toast.init() contract**:
  - Idempotent: safe to call multiple times
  - Headless-safe: no engine globals
  - Purpose: initializes internal queue if not already done
  - Required: YES (must be called in sim_scene.init() before first show())
  
  **Test safety rules**:
  - `show()` must NOT call any `command_buffer.*` or `layers.*` functions
  - `show()` must guard `timer.after()` with `if timer and timer.after then ... end`
  - `update()` must only update local animation state (fade_alpha, slide_y)
  - Tests can verify queue state without rendering

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: `frontend-ui-ux`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with 2.1, 2.2, 2.4)
  - **Blocks**: None (used by achievement system)
  - **Blocked By**: 1.2 (border), 1.3 (achievement data)

  **References**:

  **Pattern References** (existing code to follow):
  - `assets/scripts/idle_game/ui/ascii_border.lua` - Border component (Task 1.2 output)

  **API/Type References** (contracts to implement against):
  - `assets/scripts/core/timer.lua:88-105` - `timer.after(delay, action, tag)` for auto-dismiss
  - `assets/scripts/core/timer.lua:131-154` - `timer.every(delay, action, times)` for animation ticks

  **WHY Each Reference Matters**:
  - `timer.after`: Use for auto-dismiss after 3 seconds - `timer.after(3.0, function() dismiss_toast(id) end, "toast_" .. id)`
  - Timer system is centralized in `assets/scripts/core/timer.lua`

  **Timer Integration Details**:
  
  Toast auto-dismiss uses the centralized timer system, NOT a local `update(dt)`:
  ```lua
  -- Toast module state (at module level)
  toast._queue = {}
  toast._next_id = 1  -- Monotonic counter, never resets
  
  -- In toast.show():
  local timer = require("core.timer")
  local toast_id = toast._next_id
  toast._next_id = toast._next_id + 1  -- Increment for next toast
  
  -- Store toast in queue
  toast._queue[#toast._queue + 1] = { id = toast_id, title = ..., ... }
  
  -- Use timer.after for auto-dismiss (unique tag via monotonic ID)
  timer.after(duration or 3.0, function()
      toast._dismiss(toast_id)
  end, "toast_dismiss_" .. toast_id)
  ```
  
  **Why monotonic ID**: Using `#queue + 1` can collide after toasts are dismissed.
  A monotonic counter (`_next_id`) ensures unique timer tags even after queue churn.
  
  **toast.update(dt)** handles:
  - Fade-in/fade-out animation progress (local state, not timer-based)
  - Toast position animation (slide-in effect)
  
  It does NOT handle auto-dismiss timing (that's the timer system's job).
  
  **Timer update loop location** (verify line during implementation):
  The global `timer.update(dt)` is already called in the engine's main loop:
  - **File**: `assets/scripts/core/main.lua`
  - **Line**: ~1194 (search token: `timer.update(dt`)
  - **Code**: `timer.update(dt, isRenderFrame)`
  
  This runs every frame for ALL scenes, so toast auto-dismiss will work automatically.
  No additional integration needed in `sim_scene.update()`.

  **Acceptance Criteria**:
  ```lua
  local toast = require("idle_game.ui.toast_notification")
  local timer = require("core.timer")
  
  -- Show a test toast with short duration
  toast.show({title = "Test", description = "Test toast", duration = 0.1})
  
  -- Verify queue
  assert(#toast._queue == 1, "Queue should have 1 toast")
  
  -- Simulate time passage via timer system (how it actually works)
  for i = 1, 10 do
      timer.update(0.02)  -- 10 * 0.02 = 0.2 seconds > 0.1 duration
  end
  
  -- Toast should be dismissed by timer callback
  assert(#toast._queue == 0, "Queue should be empty after timer fires")
  
  print("Toast notification test passed")
  ```

  **Commit**: YES
  - Message: `feat(idle-ui): add toast notification queue system`
  - Files: `assets/scripts/idle_game/ui/toast_notification.lua`

---

- [ ] 2.4. Achievement event hooks

  **What to do**:
  - Modify `assets/scripts/idle_game/resources.lua` to emit signals on resource add
  - Modify `assets/scripts/idle_game/upgrades.lua` to emit signals on purchase
  - Modify `assets/scripts/idle_game/spawner.lua` to emit signals on creature spawn
  - Create `assets/scripts/idle_game/achievement_listener.lua` to:
    - Listen for resource/upgrade/spawn signals
    - Check achievement conditions
    - Trigger toast notifications on unlock
  - Track playtime for time-based achievements
  
  **SIGNAL CONTRACT (authoritative)**:
  
  | Signal Name | Emitter | Payload | Emission Rule |
  |-------------|---------|---------|---------------|
  | `resource_changed` | `resources.add()` | `(resource_type, new_total)` | Emit ONLY when `amount > 0` (not on spend) |
  | `upgrade_purchased` | `upgrades.purchase()` | `(upgrade_id, new_level)` | Emit ONLY on successful purchase (return true) |
  | `creature_spawned` | `spawner.spawnXAt()` AND inside `spawner.spawnXs()` batch loops | `(creature_type, entity)` | Emit for ALL spawns (initial, reproduction, specialists). NOTE: `spawnForagers(count)` loops internally and does NOT call `spawnForagerAt()` - signal must be emitted inside the loop. Same pattern applies to new `spawnMiners()`, etc. |
  
  **Signal emission example** (resources.lua:add):
  ```lua
  -- In resources.lua:add()
  local signal = require("external.hump.signal")
  
  function resources.add(resource_type, amount)
      -- existing add logic...
      
      -- Emit signal ONLY on positive adds (not on spend)
      if amount > 0 then
          signal.emit("resource_changed", resource_type, resources.get(resource_type))
      end
  end
  ```
  
  **Handler example** (achievement_listener.lua):
  ```lua
  signal.register("resource_changed", function(resource_type, new_total)
      local newly_unlocked = achievements.check_resource_achievements(resource_type, new_total)
      -- ...
  end)
  ```

  **CRITICAL: Signal/Timer Lifecycle Management**
  
  **Problem**: `signal.register()` adds handlers to a global table. If the module is `require()`d multiple times (e.g., during development hot-reload), handlers duplicate.
  
  **HOT-RELOAD ASSUMPTION (CRITICAL)**:
  
  **Note**: The engine's hot-reload mechanism (`assets/scripts/core/hot_reload.lua`) clears 
  `package.loaded` for reloaded modules. This means the `_initialized` guard alone is NOT sufficient.
  (Verify hot-reload behavior by checking `assets/scripts/core/hot_reload.lua` during implementation)
  
  **Problem with naive approach:**
  - Hot-reload clears `package.loaded["idle_game.achievement_listener"]`
  - Module is re-required, `_initialized` resets to `false`
  - `init()` is called again, registers signal handlers AGAIN
  - But old handlers still exist in signal's global registry → duplicates!
  
  **REQUIRED: Cleanup-aware initialization pattern**:
  ```lua
  -- achievement_listener.lua (hot-reload safe version)
  local achievement_listener = {}
  local signal = require("external.hump.signal")
  
  -- Store handler references so we can remove them on shutdown
  achievement_listener._handlers = {}
  
  function achievement_listener.init()
      -- Clean up any existing handlers first (idempotent)
      achievement_listener.shutdown()
      
      -- Register new handlers and store references
      achievement_listener._handlers.resource = function(resource, amount)
          -- ... handler logic ...
      end
      signal.register("resource_changed", achievement_listener._handlers.resource)
      
      -- Repeat for other signals...
  end
  
  function achievement_listener.shutdown()
      -- Remove all registered handlers
      for signal_name, handler in pairs(achievement_listener._handlers) do
          signal.remove(signal_name, handler)  -- Uses hump.signal's remove API
      end
      achievement_listener._handlers = {}
  end
  
  return achievement_listener
  ```
  
  **Integration requirement**: Scene shutdown should call `achievement_listener.shutdown()` before
  hot-reload, OR init should always clean up first (as shown above - the REQUIRED approach).
  
  **AUTHORITATIVE PATTERN (use this, not _initialized guard)**:
  The cleanup-aware init pattern shown above is MANDATORY. Do NOT use a simple `_initialized` guard 
  because it will fail under hot-reload (the guard resets but old handlers remain in signal registry).
  
  **Complete achievement_listener.lua implementation**:
  ```lua
  -- achievement_listener.lua (HOT-RELOAD SAFE - use this exact pattern)
  local achievement_listener = {}
  local signal = require("external.hump.signal")
  local achievements = require("idle_game.achievements")
  local toast = require("idle_game.ui.toast_notification")
  
  -- Store handler references for cleanup (REQUIRED for hot-reload safety)
  achievement_listener._handlers = {}
  
  function achievement_listener.init()
      -- ALWAYS clean up first (handles hot-reload case)
      achievement_listener.shutdown()
      
      -- Create and register handlers, storing references
      achievement_listener._handlers.resource_changed = function(resource, amount)
          local newly_unlocked = achievements.check_resource_achievements(resource, amount)
          for _, ach in ipairs(newly_unlocked) do
              toast.show({ title = ach.name, description = ach.description })
          end
      end
      signal.register("resource_changed", achievement_listener._handlers.resource_changed)
      
      achievement_listener._handlers.upgrade_purchased = function(upgrade_id, level)
          local newly_unlocked = achievements.check_upgrade_achievements(upgrade_id, level)
          for _, ach in ipairs(newly_unlocked) do
              toast.show({ title = ach.name, description = ach.description })
          end
      end
      signal.register("upgrade_purchased", achievement_listener._handlers.upgrade_purchased)
      
      achievement_listener._handlers.creature_spawned = function(creature_type, entity)
          local newly_unlocked = achievements.check_creature_achievements()  -- Queries spawner internally
          for _, ach in ipairs(newly_unlocked) do
              toast.show({ title = ach.name, description = ach.description })
          end
      end
      signal.register("creature_spawned", achievement_listener._handlers.creature_spawned)
      
      print("[achievement_listener] Initialized signal handlers (hot-reload safe)")
  end
  
  function achievement_listener.shutdown()
      -- Remove all registered handlers from signal system
      if achievement_listener._handlers.resource_changed then
          signal.remove("resource_changed", achievement_listener._handlers.resource_changed)
      end
      if achievement_listener._handlers.upgrade_purchased then
          signal.remove("upgrade_purchased", achievement_listener._handlers.upgrade_purchased)
      end
      if achievement_listener._handlers.creature_spawned then
          signal.remove("creature_spawned", achievement_listener._handlers.creature_spawned)
      end
      achievement_listener._handlers = {}
  end
  
  -- Playtime tracking (called from sim_scene.update)
  function achievement_listener.update(dt)
      achievements.add_playtime(dt)
      local time_unlocked = achievements.check_time_achievements()
      for _, ach in ipairs(time_unlocked) do
          toast.show({ title = ach.name, description = ach.description })
      end
  end
  
  return achievement_listener
  ```
  
  **Integration in sim_scene.lua**:
  ```lua
  -- In sim_scene.init() - ONE TIME:
  local achievement_listener = require("idle_game.achievement_listener")
  achievement_listener.init()  -- Safe to call multiple times (cleans up first)
  
  -- In sim_scene.update(dt) - EVERY FRAME:
  achievement_listener.update(dt)  -- Tracks playtime
  ```
  
  **Timer integration for toast auto-dismiss**:
  The toast module uses `timer.after()` which is updated by the global timer system.
  Ensure `timer.update(dt)` is called somewhere in the game loop.
  
  **Verification**: Check if timer is already being updated:
  ```lua
  -- In main game loop or scene update, one of these should exist:
  timer.update(dt)
  -- OR it's called by the engine automatically
  ```
  
  If timer is NOT being updated in idle scene, add to `sim_scene.update()`:
  ```lua
  local timer = require("core.timer")
  timer.update(dt)  -- Advances all timers including toast auto-dismiss
  ```

  **Must NOT do**:
  - Create circular dependencies
  - Check achievements every frame (only on events, except playtime)
  - Modify existing logic beyond signal emission
  - Register handlers outside of `init()` function

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with 2.1, 2.2, 2.3)
  - **Blocks**: 4.1
  - **Blocked By**: 1.3 (achievement data)

  **References**:

  **Pattern References** (existing code to follow):
  - `assets/scripts/external/hump/signal.lua` - Signal library (`register`, `emit`, `remove`)
  - `assets/scripts/core/timer.lua:556-723` - `timer.update()` loop that advances all timers

  **API/Type References** (contracts to implement against):
  - `assets/scripts/idle_game/resources.lua:41-57` - Resource add function (add signal.emit here)
  - `assets/scripts/idle_game/upgrades.lua:145-157` - Purchase function (add signal.emit here)

  **WHY Each Reference Matters**:
  - `signal.lua`: Use `signal.register(name, fn)` and `signal.emit(name, args...)` - NOT `signal.new()`
  - `timer.lua:556-723`: Toast auto-dismiss depends on `timer.update()` being called; verify it's in the update loop

  **Acceptance Criteria**:
  ```lua
  local signal = require("external.hump.signal")
  local resources = require("idle_game.resources")
  local achievement_listener = require("idle_game.achievement_listener")
  
  -- Initialize (idempotent)
  achievement_listener.init()
  achievement_listener.init()  -- Call twice to verify no duplicate handlers
  
  -- Track signal emission
  local call_count = 0
  signal.register("resource_changed", function()
      call_count = call_count + 1
  end)
  
  -- Add resource
  resources.add("wood", 10)
  
  -- Verify signal emitted exactly once (not duplicated)
  assert(call_count == 1, "Signal should be emitted exactly once, got: " .. call_count)
  
  print("Achievement hooks test passed")
  ```

  **Commit**: YES
  - Message: `feat(idle): add achievement event hooks via signal system`
  - Files: `assets/scripts/idle_game/resources.lua`, `assets/scripts/idle_game/upgrades.lua`, `assets/scripts/idle_game/spawner.lua`, `assets/scripts/idle_game/achievement_listener.lua`

---

### Phase 3: New Creatures

**WORLDSTATE UPDATER WIRING (applies to ALL creature types)**:

This section explains how worldstate updaters actually run for idle game AI entities.

**How updaters are registered and called** (verify file paths/line numbers during implementation):

1. **Updater definitions**: All updaters are defined in `assets/scripts/ai/worldstate_updaters.lua` as a 
   table of functions:
   ```lua
   -- worldstate_updaters.lua
   return {
       forager_sensing = function(entity, dt) ... end,
       -- Add new ones here:
       miner_sensing = function(entity, dt) ... end,
       lumberjack_sensing = function(entity, dt) ... end,
   }
   ```

2. **Registration**: The updaters table is loaded into `ai.worldstate_updaters` during AI init
   (`assets/scripts/ai/init.lua:37`):
   ```lua
   ai.worldstate_updaters = require("ai.worldstate_updaters")
   ```

3. **Entity def contains ALL updaters**: When `create_ai_entity("forager")` is called, the C++ 
   function `initGOAPComponent()` (in `src/systems/ai/ai_system.cpp:563-617`) does:
   ```cpp
   // Line 580: deep copy the entire ai table (including worldstate_updaters)
   sol::function dc = masterStateLua["deep_copy"];
   sol::table def_instance = dc(aiTable);  // Contains ai.worldstate_updaters
   
   // Line 594: store the copy as the entity's def
   goap.def = def_instance;
   ```
   
   This means EVERY AI entity's `goap.def["worldstate_updaters"]` contains ALL updater functions
   (forager_sensing, miner_sensing, etc.), regardless of entity type.

4. **Execution**: The C++ AI system calls `runWorldStateUpdaters()` each AI tick 
   (`src/systems/ai/ai_system.cpp:2144-2158`):
   ```cpp
   void runWorldStateUpdaters(GOAPComponent &comp, entt::entity &entity) {
       sol::table updaters = comp.def["worldstate_updaters"];  // ALL updaters
       for (auto &[k, v] : updaters) {
           // Calls EVERY updater function with (entity, dt)
           sol::protected_function f = v;
           f(entity, aiUpdateTickInSeconds);
       }
   }
   ```

5. **Per-type filtering**: Since ALL updaters run for ALL entities, each updater MUST early-return 
   if the entity isn't the correct type (using `spawner._miners[entity]` check, etc.).

**CRITICAL: EXISTING forager_sensing MUST BE GATED (Task 3.0 - PREREQUISITE)**:

The current `forager_sensing` function in `worldstate_updaters.lua` has NO entity-type gate. 
Once new creature types exist, `forager_sensing` will run on miners/lumberjacks/collectors/builders,
applying forager-specific logic (hunger, energy decay, reproduction, passive harvesting, death) 
to non-forager creatures.

**REQUIRED CHANGE to worldstate_updaters.lua** (must be done BEFORE Tasks 3.1-3.4):
```lua
-- At the START of forager_sensing function, add:
forager_sensing = function(entity, dt)
    -- GATE: Only run for foragers
    local spawner = require("idle_game.spawner")
    if not spawner._foragers or not spawner._foragers[entity] then
        return  -- Not a forager, skip
    end
    
    -- ... rest of existing forager_sensing logic unchanged ...
end,
```

**Why this doesn't violate "no forager behavior change" guardrail:**
- This change does NOT modify forager behavior - foragers still run the exact same code
- It's a containment change that prevents NEW creature types from inheriting forager logic
- Without this gate, the new creature tasks are broken by design

**Why this architecture exists**: The idle game GOAP entities are simpler than full GOAP - they 
don't dynamically select actions. Instead, worldstate updaters handle behavior directly (passive 
harvesting, sensing). This is intentional for idle game simplicity.

**To add a new creature type's updater**:
1. Add function to `worldstate_updaters.lua` (e.g., `miner_sensing`)
2. Include entity-type gate at start of function (check `spawner._miners[entity]`)
3. No additional registration needed - it's automatically included via the deep copy of `ai` table

---

- [ ] 3.0. Gate forager_sensing (PREREQUISITE - must complete before 3.1-3.4)

  **What to do**:
  - Add entity-type gate to `forager_sensing` in `assets/scripts/ai/worldstate_updaters.lua`
  - This prevents forager survival/reproduction/death logic from running on new creature types
  
  **EXACT CHANGE** (MUST be FIRST lines after function signature, BEFORE any `registry:get`):
  ```lua
  forager_sensing = function(entity, dt)
      -- GATE: Only run for foragers (prevents cross-type contamination)
      -- CRITICAL: This MUST be BEFORE line 139's `registry:get(entity, Transform)`
      local spawner = require("idle_game.spawner")
      if not spawner._foragers or not spawner._foragers[entity] then
          return  -- Not a forager, skip this updater entirely
      end
      
      -- EXISTING LINE 139 STAYS (now protected by gate above):
      local transform = registry:get(entity, Transform)
      -- ... rest of existing forager_sensing logic UNCHANGED ...
  end,
  ```
  
  **CRITICAL PLACEMENT NOTE**: The current code at line 139 is `registry:get(entity, Transform)`.
  The gate MUST be inserted BEFORE this line, not after. Calling `registry:get` on an invalid 
  entity could cause errors.
  
  **Fallback search token** (if line numbers drift): Find `forager_sensing = function(entity, dt)` 
  in `worldstate_updaters.lua` and add the gate IMMEDIATELY after the function signature, BEFORE
  any `registry:get` or `registry:try_get` calls.

  **Must NOT do**:
  - Modify any other forager logic (hunger thresholds, reproduction, death)
  - Change the gate to anything except spawner._foragers membership check
  - Skip this task (Tasks 3.1-3.4 will be BROKEN without it)

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: None (must complete first)
  - **Blocks**: 3.1, 3.2, 3.3, 3.4
  - **Blocked By**: None

  **References**:
  - `assets/scripts/ai/worldstate_updaters.lua` - File to modify (forager_sensing function)
  - `assets/scripts/idle_game/spawner.lua` - Source of `_foragers` tracking table

  **Acceptance Criteria** (structural verification - PREFERRED):
  
  ```bash
  # Verify gate code exists BEFORE registry:get in forager_sensing
  grep -A8 "forager_sensing = function" assets/scripts/ai/worldstate_updaters.lua
  # Assert: Output shows "spawner._foragers" check BEFORE "registry:get"
  ```
  
  **Expected output after fix**:
  ```
  forager_sensing = function(entity, dt)
      -- GATE: Only run for foragers
      local spawner = require("idle_game.spawner")
      if not spawner._foragers or not spawner._foragers[entity] then
          return
      end
      
      local transform = registry:get(entity, Transform)
  ```
  
  **Alternative IN-ENGINE test** (if structural check passes):
  ```lua
  -- Test that non-forager valid entity doesn't crash
  local worldstate_updaters = require("ai.worldstate_updaters")
  local spawner = require("idle_game.spawner")
  
  -- Find a valid entity that is NOT a forager (e.g., a miner if Task 3.1 is done)
  -- Or use any valid entity ID that exists but isn't registered as a forager
  for entity, _ in pairs(spawner._miners or {}) do
      worldstate_updaters.forager_sensing(entity, 0.016)
      print("Gate works: miner entity " .. entity .. " did not crash forager_sensing")
      break
  end
  ```
  
  **NOTE**: The invalid-entity test (99999) would still work after the gate is added because
  the `spawner._foragers[99999]` check returns nil before `registry:get` is called.

  **Commit**: YES
  - Message: `fix(ai): gate forager_sensing to only run for forager entities`
  - Files: `assets/scripts/ai/worldstate_updaters.lua`

---

- [ ] 3.1. Miner creature type

  **What to do**:
  - Create `assets/scripts/ai/entity_types/miner.lua`
  - Create `assets/scripts/ai/goal_selectors/miner.lua`
  - Create `assets/scripts/ai/blackboard_init/miner.lua`
  - Add miner-specific worldstate updater to `worldstate_updaters.lua`
  - Add spawning function to `spawner.lua`
  
  **Miner behavior** (specialization):
  - Only targets rocks (not trees or food)
  - 50% faster mining than forager
  - Gathers 2x stone per action
  - Uses existing `harvest_rock` action (or create similar)
  
  **Entity type definition**:
  ```lua
  -- entity_types/miner.lua
  return {
      initial = {
          hungry = false,
          hasStone = false,
          nearRock = false,
          wander = false
      },
      goal = {
          hasStone = true
      }
  }
  ```
  
  **Goal selector** (simplified for passive harvesting specialists):
  
  **CRITICAL: GOAP Goal Conflict Prevention**:
  
  The global `ai.goals` table includes `HARVEST_WOOD` and `HARVEST_STONE` desires that trigger on 
  `nearTree=true` and `nearRock=true` (see `ai/init.lua:63-86` - verify during implementation). Since specialist updaters 
  WILL set these atoms, we MUST prevent specialists from triggering these forager-intended goals.
  
  **CHOSEN SOLUTION: Specialists use EMPTY goal tables**
  
  ```lua
  -- goal_selectors/miner.lua
  -- Miner uses EMPTY goals table to prevent HARVEST_STONE from triggering
  local selector = require("ai.goal_selector_engine")
  
  -- Specialist-specific empty goals (no HARVEST_*, no SURVIVAL goals)
  local SPECIALIST_GOALS = {}  -- Empty: no active goals, always WANDER
  
  return function(e)
      local def = ai.get_entity_ai_def(e)
      def.policy = def.policy or ai.policy
      def.goals = SPECIALIST_GOALS  -- Override with empty goals
      selector.select_and_apply(e)  -- Will always return WANDER (no goals to select)
  end
  ```
  
  **Why this works**:
  - Global `ai.goals.HARVEST_STONE` has desire check: `nearRock == true and 0.75 or 0.0`
  - If miner used global goals AND set `nearRock=true`, HARVEST_STONE would activate (BAD)
  - By using `SPECIALIST_GOALS = {}`, no goals are evaluated, planner returns WANDER
  - Actual harvesting comes from `miner_sensing` updater (passive harvesting pattern)
  
  **Alternative rejected: Adding type-check to goal desires**
  - Would require modifying global `ai.goals` (violates "no forager behavior change" guardrail)
  - More invasive and error-prone
  
  **Blackboard init**:
  ```lua
  -- blackboard_init/miner.lua
  return function(entity)
      ai.bb.set(entity, "move_speed", 60)  -- Faster than forager
      ai.bb.set(entity, "harvest_multiplier", 2.0)
      ai.bb.set(entity, "target_resource", "stone")
  end
  ```

  **Must NOT do**:
  - Modify existing forager behavior
  - Add combat capabilities
  - Create complex new GOAP actions (use passive harvesting pattern instead)

  **CLARIFICATION on "reuse existing pattern"**:
  The miner does NOT use discrete GOAP actions like `harvest_rock`. Instead, it uses the 
  **passive harvesting pattern** from `forager_sensing` worldstate updater (line 170-208).
  This pattern runs every frame when near resources and has a chance-based harvest.
  
  **Miner variation**:
  - Only triggers on `nearRock` (ignores `nearTree`)
  - Higher harvest chance: 40% vs forager's 20%
  - Higher yield: `2 + level * 0.5` vs forager's `1 + level * 0.3`

  **CRITICAL: Worldstate Updater Entity-Type Gating (applies to ALL new creature types)**:
  
  The worldstate_updaters.lua file runs ALL updaters for ALL AI entities every frame.
  New creature-specific updaters MUST early-return if the entity is not the correct type.
  
  **Gating mechanism**: Check spawner tracking table membership.
  
  ```lua
  -- In worldstate_updaters.lua, new miner_sensing function:
  miner_sensing = function(entity, dt)
      -- CRITICAL: Gate by entity type using spawner tracking table
      local spawner = require("idle_game.spawner")
      if not spawner._miners or not spawner._miners[entity] then 
          return  -- Not a miner, skip this updater
      end
      
      -- ... miner-specific sensing/harvesting logic ...
  end,
  ```
  
  **Why this works**:
  - `spawner.spawnMinerAt()` adds entity to `spawner._miners[entity] = true`
  - Checking `spawner._miners[entity]` is O(1) hash lookup
  - Foragers have `spawner._foragers`, miners have `spawner._miners`, etc.
  - Each updater only runs logic for its type, preventing cross-type side effects
  
  **MUST apply this pattern to ALL new updaters**:
  - `miner_sensing` → checks `spawner._miners`
  - `lumberjack_sensing` → checks `spawner._lumberjacks`
  - `collector_sensing` → checks `spawner._collectors`
  - `builder_sensing` → checks `spawner._builders`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: `codebase-teacher`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with 3.2, 3.3, 3.4)
  - **Blocks**: 4.3
  - **Blocked By**: None

  **References**:

  **Pattern References** (existing code to follow):
  - `assets/scripts/ai/entity_types/forager.lua` - Entity type definition structure
  - `assets/scripts/ai/goal_selectors/forager.lua` - Goal selector pattern
  - `assets/scripts/ai/blackboard_init/forager.lua` - Blackboard initialization pattern
  - `assets/scripts/ai/worldstate_updaters.lua:138-291` - `forager_sensing` updater - **THE KEY PATTERN**
  - `assets/scripts/ai/worldstate_updaters.lua:170-208` - Passive harvesting logic to copy/modify

  **AI Auto-Loading Mechanism** (CRITICAL for new creature types):
  - Location: `assets/scripts/ai/init.lua:33-36`
  - How it works:
    ```lua
    load_directory("ai.entity_types", ai.entity_types, false)
    load_directory("ai.goal_selectors", ai.goal_selectors, false)
    load_directory("ai.blackboard_init", ai.blackboard_init, false)
    ```
  - `load_directory` scans the directory and `require()`s each `.lua` file
  - **Naming convention**: filename becomes the type ID
    - `ai/entity_types/miner.lua` → `ai.entity_types.miner`
    - `ai/goal_selectors/miner.lua` → `ai.goal_selectors.miner`
  - New creature types are auto-discovered; no manual registration needed

  **Integration Reference**:
  - `assets/scripts/idle_game/spawner.lua:63-98` - Spawning pattern to follow

  **WHY Each Reference Matters**:
  - `worldstate_updaters.lua:170-208`: This is the passive income system. Miner copies this but only for rocks, with boosted rates.
  - Miner does NOT need new GOAP actions - passive harvesting happens automatically via worldstate updater

  **Acceptance Criteria** (**IN-ENGINE test** - requires `ai`, `registry`, `create_ai_entity` globals):
  
  Run via sim_scene init hook or dev console (NOT headless `lua`):
  ```lua
  -- Verify miner entity type loads
  local miner_type = ai.entity_types.miner
  assert(miner_type ~= nil, "Miner entity type not loaded")
  assert(miner_type.initial.nearRock ~= nil, "Missing nearRock atom")
  
  -- Verify goal selector is function
  assert(type(ai.goal_selectors.miner) == "function", "Goal selector not a function")
  
  -- Spawn a miner
  local spawner = require("idle_game.spawner")
  local miner = spawner.spawnMinerAt(100, 100)  -- pixel coords for single spawn
  assert(miner ~= nil, "Failed to spawn miner")
  
  print("Miner creature test passed")
  ```

  **Commit**: YES
  - Message: `feat(idle): add Miner creature type (stone specialist)`
  - Files: `assets/scripts/ai/entity_types/miner.lua`, `assets/scripts/ai/goal_selectors/miner.lua`, `assets/scripts/ai/blackboard_init/miner.lua`, `assets/scripts/ai/worldstate_updaters.lua`, `assets/scripts/idle_game/spawner.lua`

---

- [ ] 3.2. Lumberjack creature type

  **What to do**:
  - Create `assets/scripts/ai/entity_types/lumberjack.lua`
  - Create `assets/scripts/ai/goal_selectors/lumberjack.lua`
  - Create `assets/scripts/ai/blackboard_init/lumberjack.lua`
  - Add lumberjack-specific worldstate updater to `worldstate_updaters.lua`
  - Add spawning function to `spawner.lua`
  
  **Lumberjack behavior** (uses passive harvesting pattern like miner):
  - Only triggers on `nearTree` (ignores `nearRock`)
  - Higher harvest chance: 50% vs forager's 30%
  - Higher yield: `2 + level * 0.5` vs forager's `1 + level * 0.3`
  - Same movement speed as forager (60)
  
  **Worldstate atoms**:
  ```lua
  return {
      initial = {
          hungry = false,
          hasWood = false,
          nearTree = false,
          wander = false
      },
      goal = {
          hasWood = true
      }
  }
  ```

  **Must NOT do**:
  - Duplicate code from miner (extract shared helper `specialist_harvest` if needed)
  - Create new GOAP actions (use passive harvesting pattern)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: `codebase-teacher`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3
  - **Blocks**: 4.3
  - **Blocked By**: None

  **References**:

  **Pattern References** (existing code to follow):
  - Same as Task 3.1 (miner pattern)
  - `assets/scripts/ai/worldstate_updaters.lua:184-193` - Tree harvesting logic in forager_sensing

  **Acceptance Criteria** (**IN-ENGINE test** - requires engine globals):
  
  Run via sim_scene init hook (NOT headless `lua`):
  ```lua
  assert(ai.entity_types.lumberjack ~= nil, "Lumberjack not loaded")
  assert(type(ai.goal_selectors.lumberjack) == "function", "Goal selector not function")
  
  local spawner = require("idle_game.spawner")
  local lj = spawner.spawnLumberjackAt(100, 100)  -- pixel coords for single spawn
  assert(lj ~= nil, "Failed to spawn lumberjack")
  
  print("Lumberjack creature test passed")
  ```

  **Commit**: YES
  - Message: `feat(idle): add Lumberjack creature type (wood specialist)`
  - Files: Similar to miner

---

- [ ] 3.3. Collector creature type

  **What to do**:
  - Create `assets/scripts/ai/entity_types/collector.lua`
  - Create `assets/scripts/ai/goal_selectors/collector.lua`
  - Create `assets/scripts/ai/blackboard_init/collector.lua`
  - Add collector-specific worldstate updater to `worldstate_updaters.lua`
  - Implement simple ground-item tracking in `terrain.lua`
  - Add spawning function to `spawner.lua`
  
  **LOCKED BEHAVIOR (no alternatives - Momus rejected ambiguity)**:
  
  **Ground Item System**:
  ```lua
  -- In terrain.lua (add these functions)
  terrain._ground_items = {}  -- {[tileKey] = {resource="wood", amount=1}}
  
  function terrain.drop_item(tileX, tileY, resource, amount)
      local key = tileX .. "," .. tileY
      terrain._ground_items[key] = terrain._ground_items[key] or {}
      local item = terrain._ground_items[key]
      item.resource = resource
      item.amount = (item.amount or 0) + amount
  end
  
  function terrain.pickup_item(tileX, tileY)
      local key = tileX .. "," .. tileY
      local item = terrain._ground_items[key]
      if item then
          terrain._ground_items[key] = nil
          return item.resource, item.amount
      end
      return nil, 0
  end
  
  function terrain.find_nearest_ground_item(tileX, tileY, searchRadius)
      -- Returns tileX, tileY of nearest ground item, or nil
  end
  ```
  
  **Ground Item Lifecycle (CRITICAL for correctness)**:
  
  | Event | `_ground_items` Behavior |
  |-------|--------------------------|
  | Game startup | Initialized to `{}` (empty) at module load |
  | `terrain.setCurrentGrid(grid)` | **CLEAR**: `terrain._ground_items = {}` |
  | New game / regenerate | Cleared by `setCurrentGrid` |
  | Save/Load | **NOT PERSISTED** (ground items are transient) |
  | Forager drops item | Added via `terrain.drop_item()` |
  | Collector picks up | Removed via `terrain.pickup_item()` |
  
  **terrain.lua structure** (verify field names by grepping `terrain.lua` during implementation):
  - `terrain._currentGrid` - The grid object (NOT `_grid`) - search: `_currentGrid`
  - `terrain._regenAccumulator` - A **number** (NOT a table), reset to `0` - search: `_regenAccumulator`
  - `terrain._stats` - Stats table for tracking tree/rock counts - search: `_stats`
  
  **TO ADD (does NOT exist yet)**:
  - `terrain._ground_items` - Ground item tracking table - **NEW, added by this task**
  
  **Implementation in `terrain.setCurrentGrid()`** (EXACT patch):
  ```lua
  -- File: assets/scripts/idle_game/terrain.lua
  -- Location: Line 87-91 (existing function)
  -- PATCH: Add _ground_items reset
  
  function terrain.setCurrentGrid(grid)
      terrain._currentGrid = grid       -- existing (NOT _grid)
      terrain._regenAccumulator = 0     -- existing (number, NOT table)
      terrain._ground_items = {}        -- ADD: Clear ground items on new grid
      terrain.updateStats()             -- existing
  end
  ```
  
  **Module-level initialization** (add near line 75-78):
  ```lua
  terrain._currentGrid = nil           -- existing line 75
  terrain._regenAccumulator = 0        -- existing line 78
  terrain._ground_items = {}           -- ADD: Initialize ground items table
  ```
  
  **Rationale**: Ground items are transient gameplay artifacts from creature drops. They 
  should NOT persist across save/load or regeneration. Starting fresh each session is simpler 
  and avoids stale item bugs.
  
  **Collector behavior**:
  - 50% faster movement than forager (move_speed = 90 vs 60)
  - NO harvesting ability (cannot harvest trees/rocks)
  - Seeks nearest ground item within 5 tile radius
  - Picks up ground item and adds to player resources
  - When no ground items nearby, wanders randomly
  
  **Worldstate atoms**:
  ```lua
  return {
      initial = {
          nearGroundItem = false,
          hasItem = false,
          wander = false
      },
      goal = {
          hasItem = true  -- Will seek ground items to satisfy this
      }
  }
  ```
  
  **Integration with other creatures**:
  - Modify forager/miner/lumberjack worldstate updaters to occasionally drop items:
  ```lua
  -- In forager_sensing (line ~187), after successful harvest:
  if math.random() < 0.2 then  -- 20% chance to drop excess
      terrain.drop_item(tileX, tileY, "wood", 1)
  end
  ```

  **Must NOT do**:
  - Implement passive aura collection (rejected alternative)
  - Allow collector to harvest directly from tiles
  - Create complex item stacking/inventory for ground items

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: `codebase-teacher`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3
  - **Blocks**: 4.3
  - **Blocked By**: None

  **References**:

  **Pattern References** (existing code to follow):
  - `assets/scripts/ai/entity_types/forager.lua` - Entity type structure
  - `assets/scripts/ai/worldstate_updaters.lua:138-291` - `forager_sensing` updater pattern
  - `assets/scripts/idle_game/terrain.lua` - Where to add ground item functions

  **WHY Each Reference Matters**:
  - `forager_sensing` (line 138-291): Copy this pattern but replace tree/rock sensing with ground-item sensing
  - `terrain.lua`: Ground items stored alongside tile data in this module

  **Acceptance Criteria** (MIXED: ground items **HEADLESS**, spawning **IN-ENGINE**):
  
  **Part 1: Ground item system** (HEADLESS test - create `test_idle_ground_items.lua`):
  ```lua
  -- Run: lua assets/scripts/tests/test_idle_ground_items.lua
  local terrain = require("idle_game.terrain")
  terrain._ground_items = {}  -- Reset for test
  terrain.drop_item(5, 5, "wood", 3)
  local res, amt = terrain.pickup_item(5, 5)
  assert(res == "wood", "Ground item resource mismatch")
  assert(amt == 3, "Ground item amount mismatch")
  assert(terrain.pickup_item(5, 5) == nil, "Item should be removed after pickup")
  print("Ground item system test passed")
  ```
  
  **Part 2: Entity spawning** (IN-ENGINE test via sim_scene hook):
  ```lua
  assert(ai.entity_types.collector ~= nil, "Collector entity type not loaded")
  assert(type(ai.goal_selectors.collector) == "function", "Goal selector not a function")
  local spawner = require("idle_game.spawner")
  local coll = spawner.spawnCollectorAt(100, 100)
  assert(coll ~= nil, "Failed to spawn collector")
  print("Collector creature test passed")
  ```

  **Commit**: YES
  - Message: `feat(idle): add Collector creature type with ground-item system`
  - Files: `assets/scripts/ai/entity_types/collector.lua`, `assets/scripts/ai/goal_selectors/collector.lua`, `assets/scripts/ai/blackboard_init/collector.lua`, `assets/scripts/ai/worldstate_updaters.lua`, `assets/scripts/idle_game/terrain.lua`, `assets/scripts/idle_game/spawner.lua`

---

- [ ] 3.4. Builder creature type

  **What to do**:
  - Create `assets/scripts/ai/entity_types/builder.lua`
  - Create `assets/scripts/ai/goal_selectors/builder.lua`
  - Create `assets/scripts/ai/blackboard_init/builder.lua`
  - Add builder-specific worldstate updater to `worldstate_updaters.lua`
  - Implement structure storage in `terrain._structures` table
  - Add spawning function to `spawner.lua`
  - Render structures in `terrain_renderer.lua`
  
  **LOCKED BEHAVIOR (no alternatives - Momus rejected ambiguity)**:
  
  **Structure Storage System**:
  ```lua
  -- In terrain.lua (add these)
  terrain._structures = {}  -- {[tileKey] = {type="fence", sprite="d437_186_*"}}
  
  -- EXACT filenames from sprites-0.json (NO wildcards allowed per guardrails)
  terrain.STRUCTURE_TYPES = {
      fence = { sprite = "d437_186_box_vert_d.png", cost = {wood = 2} },    -- ║ double vertical
      campfire = { sprite = "d437_015_sun.png", cost = {wood = 3} },        -- ☼ sun/fire symbol
      marker = { sprite = "d437_004_diamond.png", cost = {stone = 1} }      -- ♦ diamond
  }
  
  function terrain.place_structure(tileX, tileY, structure_type)
      if terrain.get(tileX, tileY) ~= terrain.GRASS then return false end
      if terrain.has_structure(tileX, tileY) then return false end
      
      local key = tileX .. "," .. tileY
      local struct_def = terrain.STRUCTURE_TYPES[structure_type]
      if not struct_def then return false end
      
      terrain._structures[key] = {
          type = structure_type,
          sprite = struct_def.sprite,
          x = tileX,
          y = tileY
      }
      return true
  end
  
  function terrain.has_structure(tileX, tileY)
      return terrain._structures[tileX .. "," .. tileY] ~= nil
  end
  
  function terrain.get_structures()
      return terrain._structures
  end
  ```
  
  **Structure Lifecycle (CRITICAL for correctness)**:
  
  | Event | `_structures` Behavior |
  |-------|------------------------|
  | Game startup | Initialized to `{}` at module load |
  | `terrain.setCurrentGrid(grid)` | **DO NOT CLEAR** - structures persist across regen |
  | New game via SaveManager | Cleared by `distribute()` with empty data |
  | Save | **PERSISTED** via SaveManager collector |
  | Load | Restored from save data via `distribute()` |
  | Builder places structure | Added via `terrain.place_structure()` |
  
  **Module-level initialization** (add near line 75-78):
  ```lua
  terrain._currentGrid = nil           -- existing line 75
  terrain._regenAccumulator = 0        -- existing line 78
  terrain._ground_items = {}           -- ADD (Task 3.3)
  terrain._structures = {}             -- ADD (Task 3.4)
  ```
  
  **SaveManager Integration - COLLECTOR REGISTRATION**:
  
  **CRITICAL: Collector registration timing problem (same as achievements)**
  
  SaveManager loads at startup (`SaveManager.init()` at main.lua:985). If terrain.lua
  is only required later (when entering idle game), the collector registers AFTER load,
  so structures won't be restored.
  
  **Solution: Add early require in main.lua** (same pattern as achievements):
  
  **EXACT INSERTION LOCATION** (inside `main.init()` function):
  - File: `assets/scripts/core/main.lua`
  - Function: `main.init()` (starts at line 973)
  - Insert AFTER line 983 (end of telemetry block, blank line)
  - Insert BEFORE line 985 (`SaveManager.init()`)
  
  ```lua
  -- assets/scripts/core/main.lua, inside main.init(), after line 983:
  
  -- Pre-register idle game save collectors (must happen before SaveManager.init)
  -- These modules register SaveManager collectors on require, so order matters
  pcall(function() require("idle_game.achievements") end)  -- Task 4.1: achievement persistence
  pcall(function() require("idle_game.terrain") end)       -- Task 3.4: structure persistence
  
  -- Initialize save system early (existing line 985)
  SaveManager.init()
  ```
  
  **Why inside main.init() and not at file top-level:**
  - `main.init()` is called once during game startup
  - Modules are loaded in dependency order inside this function
  - Top-level requires would execute before `main.init()` context is ready
  
  **Collector registration in terrain.lua** (at end of file):
  ```lua
  -- At end of terrain.lua (after all function definitions)
  -- This runs when module is first required
  local function register_save_collector()
      local ok, SaveManager = pcall(require, "core.save_manager")
      if ok and SaveManager and SaveManager.register then
          SaveManager.register("terrain_structures", {
              collect = function()
                  return { structures = terrain._structures }
              end,
              distribute = function(data)
                  terrain._structures = data.structures or {}
              end
          })
      end
  end
  register_save_collector()
  ```
  
  **Why structures persist but ground_items don't**:
  - Structures: Player invested resources to build them; losing them on save/load is frustrating
  - Ground items: Transient, auto-generated by creature drops; ephemeral by design
  
  **Implementation in `terrain.setCurrentGrid()` - structures NOT cleared**:
  ```lua
  -- File: assets/scripts/idle_game/terrain.lua, Line 87-91
  function terrain.setCurrentGrid(grid)
      terrain._currentGrid = grid       -- existing (correct field name)
      terrain._regenAccumulator = 0     -- existing (number, not table)
      terrain._ground_items = {}        -- CLEAR ground items
      -- NOTE: terrain._structures is NOT cleared here
      -- Structures persist and are managed by SaveManager
      terrain.updateStats()             -- existing
  end
  ```
  
  **Builder behavior**:
  - Slower movement than forager (move_speed = 40 vs 60)
  - Seeks empty grass tiles (no tree, rock, or existing structure)
  - Consumes resources to build (deducted from player resources)
  - Places random structure type from available types
  - Build cooldown: 5 seconds between builds
  - Max structures per builder: 5 (tracked in blackboard)
  
  **Worldstate atoms**:
  ```lua
  return {
      initial = {
          nearEmptyTile = false,
          canAffordBuild = false,
          hasBuiltMax = false,
          wander = false
      },
      goal = {
          -- Builder's satisfaction comes from building
          -- When nearEmptyTile and canAffordBuild, will build
      }
  }
  ```
  
  **Rendering structures** (add to terrain_renderer.lua):
  ```lua
  -- After drawing terrain tiles, draw structures
  for key, struct in pairs(terrain.get_structures()) do
      command_buffer.queueDrawSpriteTopLeft(
          layers.sprites,
          function(c)
              c.spriteName = struct.sprite
              c.x = struct.x * TILE_SIZE
              c.y = struct.y * TILE_SIZE
              c.dstW = TILE_SIZE
              c.dstH = TILE_SIZE
              c.tint = util.getColor("SADDLE BROWN")
          end,
          1,  -- z_order above terrain
          layer.DrawCommandSpace.World
      )
  end
  ```

  **Must NOT do**:
  - Make structures functional (just decorative)
  - Add destruction mechanics
  - Create structure upgrades
  - Allow structures on non-grass tiles

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: `codebase-teacher`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3
  - **Blocks**: 4.3
  - **Blocked By**: None

  **References**:

  **Pattern References** (existing code to follow):
  - `assets/scripts/ai/entity_types/forager.lua` - Entity type structure
  - `assets/scripts/ai/worldstate_updaters.lua:138-291` - Worldstate updater pattern
  - `assets/scripts/idle_game/terrain_renderer.lua:57-80` - Sprite rendering for structures

  **API/Type References** (contracts to implement against):
  - `assets/scripts/idle_game/terrain.lua` - Add `_structures`, `STRUCTURE_TYPES`, `place_structure()`, `has_structure()`, `get_structures()`
  - `assets/scripts/idle_game/resources.lua` - Use `resources.get(type)` to check affordability, `resources.add(type, -amount)` to spend
  
  **Resource spending pattern** (NO `can_afford`/`spend` exists - use this pattern):
  ```lua
  local resources = require("idle_game.resources")
  local cost = terrain.STRUCTURE_TYPES[structure_type].cost
  
  -- Check affordability manually
  local can_afford = true
  for resource, amount in pairs(cost) do
      if resources.get(resource) < amount then
          can_afford = false
          break
      end
  end
  
  if can_afford then
      -- Spend resources using add() with negative amount
      for resource, amount in pairs(cost) do
          resources.add(resource, -amount)
      end
      terrain.place_structure(tileX, tileY, structure_type)
  end
  ```

  **WHY Each Reference Matters**:
  - `terrain_renderer.lua:57-80`: Copy this pattern to render structures on top of terrain tiles
  - `terrain.lua`: Store structures in same module as terrain data for consistency

  **Acceptance Criteria** (MIXED: structure API **HEADLESS**, spawning **IN-ENGINE**):
  
  **Part 1: Entity spawning** (IN-ENGINE test via sim_scene hook):
  ```lua
  assert(ai.entity_types.builder ~= nil, "Builder entity type not loaded")
  assert(type(ai.goal_selectors.builder) == "function", "Goal selector not a function")
  local spawner = require("idle_game.spawner")
  local builder = spawner.spawnBuilderAt(100, 100)
  assert(builder ~= nil, "Failed to spawn builder")
  
  -- Verify structure placement API
  local terrain = require("idle_game.terrain")
  
  -- Place on grass (should succeed)
  terrain.setCurrentGrid(terrain.generate(12345, 30, 20))  -- Ensure terrain exists
  local grassTile = nil
  for y = 0, 19 do
      for x = 0, 29 do
          if terrain.get(x, y) == terrain.GRASS and not terrain.has_structure(x, y) then
              grassTile = {x = x, y = y}
              break
          end
      end
      if grassTile then break end
  end
  assert(grassTile, "No grass tile found for test")
  
  local placed = terrain.place_structure(grassTile.x, grassTile.y, "fence")
  assert(placed, "Structure placement failed")
  assert(terrain.has_structure(grassTile.x, grassTile.y), "has_structure returned false")
  
  -- Verify can't double-place
  local placed2 = terrain.place_structure(grassTile.x, grassTile.y, "campfire")
  assert(not placed2, "Should not allow double placement")
  
  -- Verify get_structures returns our structure
  local structs = terrain.get_structures()
  local found = false
  for _, s in pairs(structs) do
      if s.x == grassTile.x and s.y == grassTile.y then found = true end
  end
  assert(found, "Structure not in get_structures()")
  
  print("Builder creature test passed")
  ```

  **Commit**: YES
  - Message: `feat(idle): add Builder creature type with decorative structures`
  - Files: `assets/scripts/ai/entity_types/builder.lua`, `assets/scripts/ai/goal_selectors/builder.lua`, `assets/scripts/ai/blackboard_init/builder.lua`, `assets/scripts/ai/worldstate_updaters.lua`, `assets/scripts/idle_game/terrain.lua`, `assets/scripts/idle_game/terrain_renderer.lua`, `assets/scripts/idle_game/spawner.lua`

---

### Phase 4: Integration

- [ ] 4.1. Achievement persistence

  **What to do**:
  - Integrate achievements with existing SaveManager collector pattern
  - Register an `achievements` collector with SaveManager
  - Collector saves/loads unlocked achievement IDs and playtime
  - Handle missing/corrupted save data gracefully via SaveManager's built-in migration
  
  **SaveManager collector pattern** (MUST use pcall for headless test compatibility):
  ```lua
  -- In achievements.lua (add at end of file, with pcall guard)
  local function register_save_collector()
      local ok, SaveManager = pcall(require, "core.save_manager")
      if ok and SaveManager and SaveManager.register then
          SaveManager.register("achievements", {
              collect = function()
                  return {
                      unlocked = achievements._unlocked,  -- table of unlocked achievement IDs
                      playtime_seconds = achievements._playtime or 0
                  }
              end,
              distribute = function(data)
                  achievements._unlocked = data.unlocked or {}
                  achievements._playtime = data.playtime_seconds or 0
              end
          })
      end
  end
  register_save_collector()
  ```
  
  **Integration flow**:
  1. On achievement unlock → `achievements.unlock()` marks it unlocked → calls `SaveManager.save()`
  2. On game load → `SaveManager.load()` → `distribute()` restores state
  
  **CRITICAL: SaveManager.save() trigger** (must be guarded for headless-safe):
  ```lua
  -- In achievements.lua
  function achievements.unlock(id)
      if achievements._unlocked[id] then return end  -- Already unlocked
      
      achievements._unlocked[id] = true
      
      -- Trigger save immediately when achievement unlocks
      -- DOUBLE-GUARDED: 
      -- 1) pcall require in case SaveManager module fails
      -- 2) pcall save() in case save_io isn't available (headless tests)
      local ok, SaveManager = pcall(require, "core.save_manager")
      if ok and SaveManager and SaveManager.save then
          pcall(SaveManager.save)  -- Wrap save() in pcall - fails silently in headless
      end
  end
  ```
  
  **HEADLESS-SAFE RECONCILIATION**:
  - Task 1.3 requires achievements.lua be headless-testable
  - `unlock()` must work in both contexts (engine + headless CLI)
  - **CRITICAL FIX**: `SaveManager.save()` internally calls `save_io.save_file_async()` which 
    crashes in headless (no C++ bindings). The outer pcall protects against require failure, 
    but the inner `pcall(SaveManager.save)` protects against runtime failure during save.
  - Headless tests: `unlock()` records state in memory, save silently fails
  - Engine runtime: `unlock()` records state AND triggers save successfully
  
  **SaveManager.load() location** (verify line numbers during implementation):
  - `SaveManager.init()` is called in `assets/scripts/core/main.lua` (search: `SaveManager.init()`)
  - `SaveManager.init()` internally calls `SaveManager.load()` (check save_manager.lua)
  - This happens on game startup, BEFORE any scene is loaded
  
  **CRITICAL: Collector registration timing problem and solution**
  
  The achievements collector must be registered BEFORE `SaveManager.load()` runs.
  But `idle_game/achievements.lua` is not currently required at startup.
  
  **Solution: Add early require in main.lua** (Task 4.1 addition):
  
  **EXACT INSERTION LOCATION** (inside `main.init()` function):
  - File: `assets/scripts/core/main.lua`
  - Function: `main.init()` (starts at line 973)
  - Insert AFTER line 983 (end of telemetry block, blank line)
  - Insert BEFORE line 985 (`SaveManager.init()`)
  
  **Fallback search token** (if line numbers drift):
  Find `SaveManager.init()` inside `function main.init()` and insert the pcall block 
  IMMEDIATELY BEFORE it.
  
  ```lua
  -- assets/scripts/core/main.lua, inside main.init(), before SaveManager.init():
  
  -- Pre-register idle game save collectors (must happen before SaveManager.init)
  pcall(function() require("idle_game.achievements") end)  -- Registers its SaveManager collector
  
  -- Initialize save system early (existing)
  SaveManager.init()
  ```
  
  **Why pcall**: If idle game modules aren't available (e.g., different game mode), 
  the require fails silently. The collector registration happens inside achievements.lua
  at module load time.
  
  **Why inside main.init() and not at file top-level:**
  - `main.init()` is called once during game startup
  - Modules are loaded in dependency order inside this function
  - Top-level requires would execute before `main.init()` context is ready
  
  **Collector registration in achievements.lua** (at module level, end of file):
  
  **IMPORTANT: Must use pcall guard to keep achievements.lua headless-testable**
  (This matches the pattern in Task 1.3's HEADLESS-TEST BOUNDARY REQUIREMENTS)
  
  ```lua
  -- At the END of achievements.lua (runs on first require)
  -- GUARDED with pcall for headless test compatibility
  local function register_save_collector()
      local ok, SaveManager = pcall(require, "core.save_manager")
      if ok and SaveManager and SaveManager.register then
          SaveManager.register("achievements", {
              collect = function()
                  return {
                      unlocked = achievements._unlocked,
                      playtime_seconds = achievements._playtime or 0
                  }
              end,
              distribute = function(data)
                  achievements._unlocked = data.unlocked or {}
                  achievements._playtime = data.playtime_seconds or 0
              end
          })
      end
  end
  register_save_collector()
  ```
  
  **Why pcall guard is REQUIRED**:
  - Headless CLI tests (`lua assets/scripts/tests/test_idle_achievements.lua`) cannot load SaveManager
  - SaveManager depends on engine globals (`save_io` C++ bindings)
  - Without pcall, requiring achievements.lua in tests would fail
  - With pcall, tests skip SaveManager registration gracefully
  
  **Flow verification**:
  1. main.lua line ~980: `require("idle_game.achievements")` → collector registered
  2. main.lua line ~985: `SaveManager.init()` → calls `SaveManager.load()`
  3. SaveManager.load() → calls `distribute_all()` → achievements collector receives saved data
  
  **Chosen approach**: Save on unlock (immediate persistence, achievements are rare events)

  **Must NOT do**:
  - Create separate save file (use SaveManager's `saves/profile.json`)
  - Add `achievements.reset()` (Momus flagged this as contradictory)
  - Bypass SaveManager with direct `save_io` calls

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with 4.2)
  - **Blocks**: 4.3
  - **Blocked By**: 1.3, 2.4

  **References**:

  **Pattern References** (existing code to follow):
  - `assets/scripts/core/save_manager.lua:34-40` - `SaveManager.register(key, collector)` API
  - `assets/scripts/core/save_manager.lua:44-59` - `collect_all()` shows how collectors are called
  - `assets/scripts/core/save_manager.lua:64-74` - `distribute_all()` shows how data is restored

  **API/Type References** (contracts to implement against):
  - `assets/scripts/core/save_manager.lua:27-30` - Collector interface: `{collect: fun(): table, distribute: fun(data: table)}`

  **Integration Reference**:
  - `src/systems/save/save_file_io.cpp` - C++ backend for `save_io` global (async file I/O)

  **WHY Each Reference Matters**:
  - `save_manager.lua:34-40`: Use this exact registration pattern - `SaveManager.register("achievements", {collect=..., distribute=...})`
  - Don't call `save_io` directly - SaveManager wraps it with JSON encoding, migrations, and async handling

  **Achievement data structure** (required for collector):
  ```lua
  -- achievements._unlocked is a SET (map with id=true), NOT an array
  achievements._unlocked = {
      ["first_wood"] = true,
      ["upgrade_master"] = true,
      -- ...
  }
  ```

  **Acceptance Criteria** (**IN-ENGINE test** - SaveManager requires engine context):
  
  Run via sim_scene init hook or dev console (NOT headless `lua`):
  ```lua
  local achievements = require("idle_game.achievements")
  local SaveManager = require("core.save_manager")
  
  -- Verify collector is registered
  assert(SaveManager.collectors["achievements"] ~= nil, "Achievements collector not registered")
  
  -- Unlock an achievement
  achievements.unlock("first_wood")
  
  -- Verify unlock was tracked
  assert(achievements.is_unlocked("first_wood"), "Achievement not tracked in memory")
  
  -- Collect data (simulates what SaveManager does)
  local data = SaveManager.collectors["achievements"].collect()
  -- _unlocked is a SET (map), so check for key presence directly
  assert(data.unlocked["first_wood"] == true, "Achievement not in collected data")
  
  -- Simulate load by distributing empty state then restoring
  SaveManager.collectors["achievements"].distribute({ unlocked = {}, playtime_seconds = 0 })
  assert(not achievements.is_unlocked("first_wood"), "Achievement should be cleared")
  
  -- Restore from saved data
  SaveManager.collectors["achievements"].distribute(data)
  assert(achievements.is_unlocked("first_wood"), "Achievement not restored from save data")
  
  print("Achievement persistence test passed")
  ```

  **Commit**: YES
  - Message: `feat(idle): add achievement persistence`
  - Files: `assets/scripts/idle_game/achievements.lua`

---

- [ ] 4.2. Window resize for UI

  **What to do**:
  - Modify `src/core/globals.cpp` to set new default **window size** (NOT virtual resolution)
  - Keep VIRTUAL_WIDTH/HEIGHT unchanged (currently 1280x800 globally)
  - The idle game already handles its own zoom calculation in `sim_scene.init()` based on grid size
  
  **CRITICAL CLARIFICATION on virtual vs window resolution:**
  
  | Setting | Current Value | Change? | Lua Access | Returns |
  |---------|---------------|---------|------------|---------|
  | `VIRTUAL_WIDTH/HEIGHT` | 1280x800 | **NO CHANGE** | `globals.screenWidth()` | **1280** (always) |
  | `screenWidth/screenHeight` defaults | ~1280x800 | **YES → 800x600** | **NOT directly exposed** | N/A |
  
  **IMPORTANT: globals.screenWidth() returns VIRTUAL_WIDTH (1280), NOT window size**
  - Verified in `src/systems/scripting/scripting_functions.cpp`:
    `lua["globals"]["screenWidth"] = []() { return globals::VIRTUAL_WIDTH; };`
  - Changing C++ `screenWidth` defaults does NOT change what Lua sees
  - Lua always sees 1280×800 virtual coordinates
  
  **Why NOT change VIRTUAL resolution:**
  - `VIRTUAL_WIDTH/HEIGHT` affects the entire rendering pipeline and all scenes
  - Changing it would break other game modes and camera systems
  - The idle game calculates its own zoom in `sim_scene.init()` based on grid pixel size vs actual window
  
  **Implementation approach**:
  - Change `screenWidth` and `screenHeight` defaults in `globals.cpp` (around line 282)
  - **ALSO** change `assets/config.json` render_data.screen values (CRITICAL - config overrides defaults!)
  - New values: `screenWidth = 800`, `screenHeight = 600`
  - This creates a smaller physical window that the engine scales virtual coords into
  
  **CONFIG OVERRIDE WARNING**:
  - `src/core/init.cpp:1072` loads window size from `assets/config.json` render_data.screen
  - Current config has `width: 600, height: 400` which OVERRIDES globals.cpp defaults
  - You MUST update BOTH `globals.cpp` (fallback) AND `config.json` (active value)
  
  **How sim_scene zoom ACTUALLY works** (CLARIFIED):
  
  The current `sim_scene.init()` code (lines 36-41):
  ```lua
  -- Comment says "Get actual window size" but this is MISLEADING:
  local screenW = globals.screenWidth()  -- Returns VIRTUAL_WIDTH (1280), NOT window size!
  local screenH = globals.screenHeight() -- Returns VIRTUAL_HEIGHT (800), NOT window size!
  local zoomX = screenW / gridPixelW     -- 1280 / 600 = ~2.13
  local zoomY = screenH / gridPixelH     -- 800 / 400 = 2.0
  local zoom = math.min(zoomX, zoomY)    -- 2.0
  ```
  
  **KEY INSIGHT**: Despite the misleading comment, `sim_scene.init()` uses VIRTUAL resolution 
  (1280×800), not actual window size. The zoom calculation is FIXED regardless of window size.
  
  **ACTUAL effect of changing window defaults to 800×600:**
  - Physical window becomes 800×600 pixels
  - Virtual resolution remains 1280×800 (unchanged - same 2.0 zoom calculation)
  - Engine scales the 1280×800 virtual canvas to fit the 800×600 physical window
  - The game world and UI render at the same positions in virtual space
  - Visual result: everything APPEARS smaller because window is smaller
  
  **This is a WINDOW SIZE change, not a virtual resolution change.**
  The idle game layout (resource panel at x=0, upgrade panel at x=1080) uses virtual coordinates 
  and will automatically scale to fit the smaller window.
  
  **UI layout remains in VIRTUAL space (unchanged from Tasks 2.1/2.2):**
  - Resource panel: x=0, y=0 (virtual pixels)
  - Upgrade panel: x=1080 (VIRTUAL_WIDTH - 200), y=0 (virtual pixels)
  - The engine's scaling handles mapping to physical window pixels

  **Must NOT do**:
  - Change `VIRTUAL_WIDTH` or `VIRTUAL_HEIGHT` (global engine constants)
  - Change tile grid size (keep 30x20)
  - Modify camera zoom logic (already adaptive)

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: None

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with 4.1)
  - **Blocks**: 4.3
  - **Blocked By**: 2.1, 2.2

  **References**:

  **Pattern References** (existing code to follow):
  - `assets/scripts/idle_game/scenes/sim_scene.lua:33-46` - Zoom calculation based on VIRTUAL resolution (1280×800), NOT physical window size

  **Window creation path** (verify line numbers during implementation):
  - Window created at `src/core/init.cpp`: `InitWindow(globals::getScreenWidth(), globals::getScreenHeight(), "Game")` - search: `InitWindow(`
  - Default values at `src/core/globals.cpp`: `int screenWidth{VIRTUAL_WIDTH}, screenHeight{VIRTUAL_HEIGHT};` - search: `int screenWidth{`
  - Config can override via `src/core/init.cpp` (loads from config.json if present)
  - Changing `globals.cpp` screenWidth/screenHeight defaults WILL affect actual window size at startup

  **API/Type References** (contracts to implement against):
  - `src/core/globals.cpp:167-168` - `VIRTUAL_WIDTH/HEIGHT` (DO NOT CHANGE)
  - `src/core/globals.cpp:281-282` - `screenWidth/screenHeight` defaults (CHANGE THESE)
  - **Fallback search token**: Find `int screenWidth{` in `src/core/globals.cpp`

  **Acceptance Criteria**:
  ```bash
  # Verify ONLY window defaults changed, NOT virtual resolution
  grep -A1 "VIRTUAL_WIDTH" src/core/globals.cpp
  # Assert: Still shows 1280 (or original value, not 600)
  
  grep -A1 "screenWidth" src/core/globals.cpp | head -4
  # Assert: Shows 800 (new default)
  
  # Build and run
  just build-debug
  ./build/raylib-cpp-cmake-template &
  sleep 3
  
  # Manual verification (no xdotool needed):
  # - Window should be 800x600 pixels (can verify in window title bar on most OS)
  # - Game grid (30x20 tiles) renders with extra space on right for UI panel
  ```
  
  **Manual Verification**:
  - Launch game
  - Window size is 800x600 (check window manager or title bar)
  - Game world (30x20 tiles) renders, camera auto-zooms to fit
  - Upgrade panel has space on right side
  - Other engine scenes (if any) still work correctly
  - Screenshot: `.sisyphus/evidence/task-4.2-window-resize.png`

  **Commit**: YES
  - Message: `feat(window): resize default window to 800x600 for UI sidebar`
  - Files: `src/core/globals.cpp`, `assets/config.json`

---

- [ ] 4.3. Integration testing

  **What to do**:
  - Full playthrough test of all features
  - Verify:
    - Resource panel shows correct values
    - Upgrade panel scrolls and purchases work
    - All 4 creature types spawn and behave
    - Achievements unlock and toast shows
    - Achievements persist across restart
  - Document any visual issues for polish pass
  
  **Test checklist**:
  - [ ] ASCII borders render correctly
  - [ ] Resource icons display
  - [ ] All 12 upgrades visible via scroll
  - [ ] Miner gathers stone
  - [ ] Lumberjack gathers wood
  - [ ] Collector picks up items
  - [ ] Builder places structures
  - [ ] Resource threshold achievement triggers
  - [ ] Toast notification appears
  - [ ] Save/load preserves achievements
  - [ ] ImGui debug panels still work

  **Must NOT do**:
  - Add new features during integration testing
  - Skip any test case

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: None (manual verification - native game, not browser)

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (final)
  - **Blocks**: None
  - **Blocked By**: All previous tasks

  **References**:
  - All previous task files

  **Acceptance Criteria**:
  ```bash
  # Run game and verify no Lua errors
  ./build/raylib-cpp-cmake-template 2>&1 | tee /tmp/game_output.log &
  sleep 30
  kill $!
  
  # Check for errors
  grep -i "error\|exception\|failed" /tmp/game_output.log
  # Assert: No critical errors
  
  # Manual verification of all test checklist items
  ```

  **Commit**: NO (verification only, no tracked files to commit)
  
  **Why no commit**: This task is verification/QA - it produces no new code or tracked artifacts.
  All code changes were committed in prior tasks.

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1.2 | `feat(idle-ui): add ASCII border component` | ascii_border.lua | `just build-debug` |
| 1.3 | `feat(idle): add TDD achievement module` | achievements.lua, test file | `lua test_idle_achievements.lua` |
| 2.1 | `feat(idle-ui): add ASCII resource panel` | ascii_resource_panel.lua | Manual visual |
| 2.2 | `feat(idle-ui): add ASCII upgrade panel` | ascii_upgrade_panel.lua | Manual visual |
| 2.3 | `feat(idle-ui): add toast notifications` | toast_notification.lua | Lua test |
| 2.4 | `feat(idle): add achievement event hooks` | Multiple .lua | Lua test |
| 3.1-3.4 | `feat(idle): add [creature] creature type` | AI files, spawner.lua | Spawn test |
| 4.1 | `feat(idle): add achievement persistence` | achievements.lua | Save/load test |
| 4.2 | `feat(window): resize for UI panels` | globals.cpp | Manual visual |
| 4.3 | `test(idle): integration testing` | None | Full playthrough |

---

## Success Criteria

### Verification Commands
```bash
# Build check
just build-debug

# Lua tests
lua assets/scripts/tests/test_idle_achievements.lua

# Run game for visual verification
./build/raylib-cpp-cmake-template
```

### Final Checklist
- [ ] ASCII UI panels render with grid-aligned borders
- [ ] All 4 resources display with icons
- [ ] All 12 upgrades accessible via scrolling
- [ ] 4 new creature types spawn and behave correctly
- [ ] Achievements unlock based on conditions
- [ ] Toast notifications display in queue
- [ ] Achievements persist across sessions
- [ ] ImGui debug panels still functional (see verification below)
- [ ] No Lua errors during gameplay
- [ ] `just build-debug` passes

**How to verify ImGui panels still work**:
- The existing `resource_panel.draw()`, `debug_panel.draw()`, and `upgrade_panel.draw()` calls
  remain in `sim_scene.draw()` (lines 135-137 after ASCII panel additions)
- ImGui panels render after command_buffer content, so they appear on top
- Visual verification: Both ImGui upgrade list AND ASCII upgrade panel should be visible
  (redundant during testing, ImGui removed in later polish pass if desired)

---

## SIM_SCENE.LUA FINAL INTEGRATION CHECKLIST

> **AUTHORITATIVE**: This section consolidates ALL integration changes to `sim_scene.lua`.
> Do NOT rely on scattered snippets elsewhere in this plan - this is the single source of truth.

### 1. Imports to Add (at top of file, after existing requires)

```lua
-- Add after existing requires (around line 10-20)
local ascii_border = require("idle_game.ui.ascii_border")
local ascii_resource_panel = require("idle_game.ui.ascii_resource_panel")
local ascii_upgrade_panel = require("idle_game.ui.ascii_upgrade_panel")
local toast_notification = require("idle_game.ui.toast_notification")
local achievement_listener = require("idle_game.achievement_listener")
```

**Fallback search token**: Find `local resources = require` in `sim_scene.lua` - add new requires nearby.

### 2. Initialization in sim_scene.init()

```lua
-- Add at end of init() function, after camera setup
ascii_resource_panel.init()
ascii_upgrade_panel.init()
toast_notification.init()
achievement_listener.init()
```

**Fallback search token**: Find `function sim_scene.init()` and add before its closing `end`.

### 3. Update Loop Additions in sim_scene.update(dt)

**ORDERING CRITICAL** to avoid early-return trap:

```lua
function sim_scene.update(dt)
    -- EXISTING: terrain updates, spawner cleanup (keep unchanged)
    terrain.update(dt, ...)
    spawner.processPendingDestructions()
    
    -- NEW: Add these updates BEFORE click routing (so early return doesn't skip them)
    ascii_upgrade_panel.update(dt)   -- handles scroll, hover state
    toast_notification.update(dt)    -- handles fade/slide animations
    achievement_listener.update(dt)  -- checks achievement conditions (tracks playtime)
    
    -- NEW: Click routing with early return (section 5 below)
    -- if UI consumes click, returns early here - BUT updates above already ran
    
    -- EXISTING: input_module.handleClick and tile handling (keep unchanged)
end
```

**WHY THIS ORDER**: The click routing may `return` early if UI consumes the click. If updates 
were placed AFTER click routing, they would be skipped on UI clicks. Place updates BEFORE 
click routing to ensure they always run.

**Fallback search token**: Find `spawner.processPendingDestructions()` in `sim_scene.update(dt)` - 
add the three update calls IMMEDIATELY AFTER this line.

### 4. Draw Order (CRITICAL - must be exact)

**CURRENT sim_scene.draw()** (lines 126-138):
```lua
function sim_scene.draw()
    terrain_renderer.draw(terrainGrid)  -- Draw terrain grid
    spawner.drawCorpses()               -- Draw corpses
    resource_panel.draw()               -- ImGui panel
    debug_panel.draw()                  -- ImGui panel  
    upgrade_panel.draw()                -- ImGui panel
end
```

**MODIFICATION** - Add ASCII panel draws BEFORE ImGui:
```lua
function sim_scene.draw()
    -- 1. Terrain and entities (existing)
    terrain_renderer.draw(terrainGrid)
    spawner.drawCorpses()
    
    -- 2. ASCII panels (queue draw commands - engine flushes automatically)
    ascii_resource_panel.draw()  -- top-left, z_index=1000
    ascii_upgrade_panel.draw()   -- right side, z_index=1000
    toast_notification.draw()    -- top-center, z_index=1100
    
    -- 3. ImGui panels (render on top of everything)
    resource_panel.draw()        -- existing ImGui (keep for debug)
    debug_panel.draw()           -- existing ImGui
    upgrade_panel.draw()         -- existing ImGui (keep for debug)
end
```

**RENDER PIPELINE CLARIFICATION**:
- This project uses a command_buffer pattern where Lua queues draw commands
- The engine automatically flushes all queued commands at frame end
- `sim_scene.draw()` does NOT call flush - the C++ game loop handles it
- ImGui renders last (after command_buffer flush) so it appears on top
- Z-index values control order WITHIN command_buffer (higher = on top)

**Fallback search token**: Find `function sim_scene.draw()` in sim_scene.lua.

### 5. Click Routing Modification

**CURRENT CODE** in `sim_scene.update(dt)` (lines 88-123):
```lua
local tileX, tileY = input_module.handleClick(config)
if tileX and tileY then
    -- tile harvest logic...
end
```

**MODIFICATION** - Add UI check IMMEDIATELY BEFORE `input_module.handleClick`:
```lua
-- Add IMMEDIATELY BEFORE line 88 (`input_module.handleClick`), NOT at function start
-- (don't interrupt earlier update logic like terrain.update, spawner.processPendingDestructions)
local leftButton = MouseButton and MouseButton.MOUSE_BUTTON_LEFT or 0
if input.isMousePressed(leftButton) then
    local mouse = input.getMousePos()
    
    -- UI panels consume clicks first (highest to lowest priority)
    if ascii_upgrade_panel.handle_click(mouse.x, mouse.y) then
        return  -- click consumed by upgrade panel, skip world interaction
    end
end

-- EXISTING CODE UNCHANGED (input_module.handleClick handles world clicks):
local tileX, tileY = input_module.handleClick(config)
if tileX and tileY then
    -- existing tile harvest logic stays here unchanged
end
```

**KEY INSIGHT**: The current `input_module.handleClick(config)` already handles converting mouse 
position to tile coordinates. We ONLY need to add a UI click check BEFORE it - NOT replace it.

**Fallback search token**: Find `input_module.handleClick` in `sim_scene.lua` - add UI check before this line.

### 6. Keyboard/Wheel Scrolling (Handled Inside Panel Module)

**SCROLLING OWNERSHIP**: `ascii_upgrade_panel.update(dt)` handles ALL scrolling internally.

There is NO scrolling code in `sim_scene.update(dt)`. The panel module:
- Reads `input.getMouseWheel()` for mouse wheel scrolling
- Reads `_G.isKeyPressed("KEY_UP/DOWN/W/S")` for keyboard scrolling
- Internally checks if mouse is over panel before processing keyboard input
- Updates `scroll_offset` state internally

**sim_scene.update(dt) only calls**:
```lua
ascii_upgrade_panel.update(dt)  -- Panel handles all scrolling internally
```

**No additional scrolling code in sim_scene is needed or allowed.**

See Task 2.2 for the complete scrolling implementation inside `ascii_upgrade_panel.update(dt)`.

---

## REFERENCE INDEX (Verify During Implementation)

> **Critical references with search tokens** - use these when line numbers are stale.
> All references should be verified by the executor during implementation using the search tokens provided.

### Core Files (Must-Reference)

| File | Search Token | What It Contains |
|------|--------------|------------------|
| `sim_scene.lua` | `function sim_scene.init()` | Scene initialization, integration point |
| `sim_scene.lua` | `function sim_scene.update(dt)` | Update loop, click routing |
| `sim_scene.lua` | `function sim_scene.draw()` | Draw order (engine auto-flushes) |
| `resources.lua` | `function resources.get(type)` | Resource getter API |
| `resources.lua` | `function resources.add(type, amount)` | Resource modification API |
| `upgrades.lua` | `function upgrades.get_all()` | Get upgrade definitions |
| `upgrades.lua` | `function upgrades.purchase(id)` | Purchase upgrade API |
| `config.lua` | `VIRTUAL_WIDTH =` | Game world virtual size (600) |
| `config.lua` | `TILE_SIZE =` | Tile pixel size (20) |

### C++ References (Must-Verify)

| File | Search Token | What It Contains |
|------|--------------|------------------|
| `globals.cpp` | `int screenWidth{` | Window size defaults |
| `globals.cpp` | `constexpr int VIRTUAL_WIDTH` | Engine virtual resolution |
| `init.cpp` | `InitWindow(` | Window creation call |
| `scripting_functions.cpp` | `lua["globals"]["screenWidth"]` | Lua binding for screen size |

### Sprite References (Verified in sprites-0.json)

| Sprite Name | CP437 Code | Usage |
|-------------|-----------|-------|
| `d437_216_box_cross_h.png` | ┼ | Border intersection |
| `d437_194_box_down_h.png` | ┬ | T-junction down |
| `d437_179_box_vert.png` | │ | Vertical border |
| `d437_196_box_horiz.png` | ─ | Horizontal border |
| `d437_218_box_down_r.png` | ┌ | Top-left corner |
| `d437_191_box_down_l.png` | ┐ | Top-right corner |
| `d437_217_box_up_l.png` | └ | Bottom-left corner |
| `d437_192_box_up_r.png` | ┘ | Bottom-right corner |
| `d437_005_club.png` | ♣ | Wood icon |
| `d437_033_symbol_33.png` | ! | Stone icon |
| `d437_003_heart.png` | ♥ | Food icon |
| `d437_004_diamond.png` | ♦ | Gold icon |

> **NOTE**: Corner sprite naming follows the CP437 dungeon set convention where `up/down` + `l/r` 
> indicates the direction of the corner lines. Verified in `assets/graphics/sprites-0.json`.

### API Patterns (Copy-Paste Safe)

**Sprite drawing (queueDrawSpriteTopLeft pattern)**:
```lua
-- Search token: "queueDrawSpriteTopLeft" in terrain_renderer.lua, spawner.lua
-- Uses FIELD ASSIGNMENT (c.fieldName), not method calls
command_buffer.queueDrawSpriteTopLeft(layers.sprites, function(c)
    c.spriteName = sprite_name
    c.x = x
    c.y = y
    c.dstW = width     -- optional: destination width
    c.dstH = height    -- optional: destination height
    c.tint = color     -- optional: tint color
end, z_index, DrawCommandSpace.Screen)
```

**Text drawing**:
```lua
-- Search token: "queueDrawText" in currency_display.lua, cast_feed_ui.lua
-- Uses FIELD ASSIGNMENT (c.fieldName), not method calls
command_buffer.queueDrawText(layers.ui, function(c)
    c.text = text
    c.font = font      -- optional: font handle
    c.fontSize = font_size
    c.x = x
    c.y = y
    c.color = color
end, z_index, DrawCommandSpace.Screen)
```

**Mouse input with fallback**:
```lua
-- Search token: "MouseButton.MOUSE_BUTTON_LEFT" 
local leftButton = MouseButton and MouseButton.MOUSE_BUTTON_LEFT or 0
if input.isMousePressed(leftButton) then ... end
```

**Keyboard input with guard**:
```lua
-- Search token: "_G.isKeyPressed"
local isKeyPressed = _G.isKeyPressed
if isKeyPressed and isKeyPressed("KEY_DOWN") then ... end
```

**Signal subscription with cleanup (hump.signal)**:
```lua
-- Search token: "signal.register" in idle_game files
-- NOTE: Uses hump.signal library (signal.register/emit/remove)
local function my_handler(data) 
    -- handle event
end
signal.register("event_name", my_handler)

-- For cleanup (e.g., in hot reload): 
signal.remove("event_name", my_handler)  -- pass signal name AND handler function
```
