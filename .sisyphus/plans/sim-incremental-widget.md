# Sim Incremental Desktop Widget

## Context

### Original Request
Design a side project sim game that uses the existing GOAP AI system with ASCII sprites. Set up pixelation & color palette shaders, use RNG systems to generate environments. Have actors moving around doing their thing (foraging for now). Need a way to easily debug GOAP AI for individual entities. Interesting background environment necessary. Goal is an incremental game that can sit on the side of the desktop without window bar.

### Interview Summary
**Key Discussions**:
- **Sim Type**: Colony sim + creature sim hybrid with incremental game loop
- **Player Role**: Idle/incremental clicks (click to generate resources, purchase upgrades)
- **Resources**: Multiple (food, wood, stone, gold) - classic colony sim approach
- **World Size**: Single fixed screen fits in window (perfect for widget)
- **Actors**: Mix of creature types with GOAP-driven autonomous behavior
- **Setting**: Forest/nature biome, generated procedurally
- **Visual Style**: Earthy/natural palette (8-16 colors), pixelated
- **Debug**: Click entity → ImGui panel shows GOAP trace, world state, goal
- **Window**: Borderless, resizable, flexible sizing
- **Scope**: Full vertical slice for MVP
- **Testing**: TDD for core systems (procgen, resources)
- **Engine Approach**: Keep AI, sprites, shaders, RNG; remove game-specific code

**Research Findings**:
- GOAP system complete with `AITraceBuffer` (100 events), 9 working action examples
- forma library ready: cellular automata, Perlin noise, BSP, flood-fill, Poisson-disc
- procgen.lua provides seeded RNG, loot tables, layout DSL
- Shaders available: `pixelate_image` (ID), `palette_quantize` (ID) - registered in `assets/shaders/shaders.json`
- Borderless: `FLAG_WINDOW_UNDECORATED` (1-line change)
- ASCII: CP437 tileset (256 chars, 20x20px)

### Metis Review
**Identified Gaps** (addressed):
- Added Phase 0 Technical Spike to validate borderless/ImGui/GOAP assumptions
- Defined explicit resource formula defaults
- Set strict scope guardrails (15 upgrades max, 3 GOAP actions, 4 resources)
- Added edge case defaults (resource caps, respawn, window behavior)
- Created detailed per-phase acceptance criteria

**Key Recommendations Incorporated**:
- Create `assets/scripts/idle_game/` folder (don't modify existing combat/)
- Use existing `PatternBuilder` and `spawner` patterns
- Follow `gold_digger.lua` for creature definition
- Phase 1 cleanup: surgical removal with frequent builds

---

## Work Objectives

### Core Objective
Build an incremental/idle sim game as a borderless desktop widget, featuring procedurally generated forest terrain, GOAP-driven creatures that forage autonomously, and a click-based resource collection system with upgrades.

### Concrete Deliverables
- Borderless, resizable window (400x300 min, default 600x400)
- Procedurally generated **30x20 tile** forest (grass, trees, rocks) - fits 600x400 at 20px tiles
- 2-3 creature types with GOAP behaviors (Wander, Forage, Idle)
- 4 resources (food, wood, stone, gold) with accumulation UI
- Click-to-collect mechanic for trees/rocks
- 10-15 flat upgrades (click power, creature speed, passive rates)
- Click-to-select entity → ImGui GOAP debug panel
- Earthy 8-color palette + pixelation post-processing

**CANONICAL GRID SIZE: 30x20 tiles at 20px = 600x400 pixels** (used consistently throughout plan)

---

## Coordinate Spaces & Resolution Strategy

### Virtual vs Window Resolution

The engine uses a virtual resolution that is scaled/letterboxed to the actual window:

- **Default Virtual Resolution**: 1280x800 (defined in `src/core/globals.cpp:167-168`)
- **Widget Target Window**: 600x400 (borderless, resizable)

**DECISION: Change virtual resolution to 600x400 for this project**

To make the 30x20 tile grid fill the entire widget window with no letterboxing or unused space:

1. **Modify `src/core/globals.cpp`** (lines 167-168):
   ```cpp
   const int VIRTUAL_WIDTH = 600;   // Was: 1280
   const int VIRTUAL_HEIGHT = 400;  // Was: 800
   ```

2. **Also update screenWidth/screenHeight defaults** (line 282):
   ```cpp
   int screenWidth{600}, screenHeight{400};  // Was: 1280, 800
   ```

**EXPECTED ON-SCREEN RESULT**:
- The 30×20 tile terrain occupies the **entire widget area** with no margins or letterboxing
- Window at 600×400 shows 1:1 virtual-to-window pixels
- If window is resized larger, content scales up proportionally (handled by engine)
- TILE_SIZE=20 means each tile is exactly 20 window pixels at default size

### Coordinate Space Reference

| Space | Range | Usage |
|-------|-------|-------|
| **Virtual** | 0-600 x 0-400 | All rendering, transforms, tile positions |
| **Window** | 0-windowW x 0-windowH | Resize handling (may differ from virtual) |
| **Tile** | 0-29 x 0-19 | Terrain grid indexing |

### Mouse Input (ALREADY HANDLED BY ENGINE)

**VERIFIED**: `input.getMousePos()` already returns virtual/letterbox-corrected coordinates.
- See: `src/systems/input/input_lua_bindings.cpp:412` binds to `globals::getScaledMousePositionCached`
- This applies letterbox/scale correction automatically
- **No manual conversion needed** - just use `input.getMousePos()` directly

```lua
-- Mouse position is already in virtual space, conversion not needed
local mouse = input.getMousePos()
local tileX = math.floor(mouse.x / TILE_SIZE)
local tileY = math.floor(mouse.y / TILE_SIZE)
```

### TILE_SIZE Clarification

**TILE_SIZE = 20** is in **virtual pixels** (which equals window pixels at default 600×400):
- Terrain grid: 30 tiles × 20px = 600 virtual pixels wide
- Terrain grid: 20 tiles × 20px = 400 virtual pixels tall
- Click-to-tile: `tileX = math.floor(mouseX / 20)`, `tileY = math.floor(mouseY / 20)`

---

### Definition of Done
- [ ] Widget runs borderless, draggable, resizable
- [ ] Forest generates deterministically from seed
- [ ] Creatures wander and forage autonomously
- [ ] Resources accumulate from clicks and creature actions
- [ ] Upgrades purchasable, effects visible
- [ ] GOAP debug panel shows real-time state
- [ ] Visual polish applied (palette + pixelation)
- [ ] `just build-debug` passes with no errors

### Must Have
- Single fixed screen (no scrolling/panning)
- Deterministic procgen (same seed = same world)
- GOAP AI for all creature behavior
- TDD for resource system and procgen

### Must NOT Have (Guardrails)
- Multiple biomes (forest only)
- Weather/time cycle/seasons
- Sound/music system
- Creature death/reproduction
- Combat between creatures
- Achievements/quests/tutorials
- Cloud saves or multiple save slots
- Networking/multiplayer
- Custom shader development (use existing)
- More than 15 upgrades
- More than 3 GOAP actions per creature
- Tech tree (flat upgrade list only)

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (GoogleTest for C++, Lua test files)
- **User wants tests**: TDD for core Lua systems
- **Framework**: GoogleTest (C++) + Lua test files

### TDD Structure
Core Lua systems follow RED-GREEN-REFACTOR:
1. **RED**: Write failing test in `assets/scripts/tests/`
2. **GREEN**: Implement minimum code to pass
3. **REFACTOR**: Clean up while keeping green

### Lua Test File Boilerplate (MANDATORY)

All new Lua test files MUST use this template (from `assets/scripts/tests/test_procgen.lua`):

```lua
--[[
================================================================================
TEST: [Module Name]
================================================================================
Description of what's being tested.

Run with: lua assets/scripts/tests/test_idle_[name].lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached module if re-running
package.loaded["idle_game.module_name"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Module Name - Feature", function()
    
    t.it("does something", function()
        local module = require("idle_game.module_name")
        t.expect(module).to_be_truthy()
    end)
    
end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
```

**CRITICAL**: 
- `package.path` extension is required for modules to be found
- `t.run()` at the end is required to execute tests and produce output
- Run from repo root: `lua assets/scripts/tests/test_idle_*.lua`

### Test Commands (CRITICAL DISTINCTION)

**C++ Tests** (engine code):
```bash
just test              # Runs GoogleTest C++ tests only (tests/)
```

**Lua Tests** (game logic):
```bash
# Run individual Lua test files directly
lua assets/scripts/tests/test_idle_terrain.lua
lua assets/scripts/tests/test_idle_resources.lua
lua assets/scripts/tests/test_idle_upgrades.lua

# Or run all idle game tests
for f in assets/scripts/tests/test_idle_*.lua; do lua "$f"; done
```

**IMPORTANT**: `just test` does NOT run Lua tests. Each Lua TDD task must explicitly run `lua assets/scripts/tests/test_idle_*.lua`.

### Manual Verification
Visual/UX elements verified via manual play-testing (this is a native desktop Raylib app, not web):
- Window behavior (borderless, drag, resize) - run app and test manually
- Creature movement smoothness - visual observation
- UI responsiveness - click and observe
- Shader effects appearance - visual inspection

---

## Task Flow

```
Phase 0 (Spike)
     ↓
Phase 1 (Cleanup) → Phase 2 (Terrain) → Phase 3 (Creatures)
                                              ↓
Phase 7 (Polish) ← Phase 6 (Upgrades) ← Phase 5 (Debug) ← Phase 4 (Resources)
```

## Parallelization

| Group | Tasks | Reason |
|-------|-------|--------|
| A | 2.1, 2.2 | Terrain gen and rendering independent |
| B | 4.1, 4.2 | Resource data and UI independent |
| C | 6.1, 6.2, 6.3 | Upgrade data, UI, effects independent |

---

## TODOs

### Phase 0: Technical Spike

- [x] 0.0. Import dungeon tileset assets (MANDATORY)

  **What to do**:
  
  **OPTION A (Preferred): Check if already present in repo/worktree**
  - Check if `assets/graphics/pre-packing-files_globbed/dungeon_437/` already exists
  - If yes, verify 256 PNG files present (d437_000_null.png to d437_255_*.png)
  - Check other worktrees: `~/Projects/TheGameJamTemplate/TheGameJamTemplate/assets/images/dungeon_tiles/`
  
  **OPTION B: Create minimal tileset from existing CP437**
  - The repo already has CP437 sprites at `assets/graphics/cp437_20x20_sprites.png`
  - Extract needed characters programmatically or manually:
    - GRASS (`.`) = position (12, 2) in 16x16 grid → pixel offset (240, 40)
    - TREE (`♠`) = position (5, 0) → pixel offset (100, 0)
    - ROCK (`#`) = position (1, 2) → pixel offset (20, 40)
  - Save as individual 20x20 PNGs in `assets/graphics/pre-packing-files_globbed/dungeon_437/`
  - Naming: `d437_044_period.png`, `d437_005_spade.png`, `d437_033_hash.png`
  
  **OPTION C: Download Dwarf Fortress tileset (MIT/CC0 licensed)**
  - Dwarf Fortress tilesets are freely available and use CP437 layout
  - Example source: https://dwarffortresswiki.org/Tileset_repository
  - Download any 20x20 or scale to 20x20
  - Split into 256 individual PNGs following naming convention
  
  **After obtaining assets**:
  - Copy to `assets/graphics/pre-packing-files_globbed/dungeon_437/`
  
  **IMPORTANT - TexturePacker project inclusion (CRITICAL)**:
  - `assets/graphics/sprites_texturepacker.tps` contains an explicit list of input files.
  - Adding PNGs to a folder on disk is NOT guaranteed to include them in the atlas unless the `.tps` project is updated and saved.

  **Do this**:
  1) Place the PNGs at:
     - `assets/graphics/pre-packing-files_globbed/dungeon_437/`

  2) Update the TexturePacker project so the files are included:
     - Open `assets/graphics/sprites_texturepacker.tps` in the TexturePacker GUI
     - Add the `pre-packing-files_globbed/dungeon_437/` files/folder as inputs
     - SAVE the `.tps`

  3) Rebuild atlas using the project:
     ```bash
     TexturePacker assets/graphics/sprites_texturepacker.tps
     ```

  **Minimum viable success (3 sprites)**:
  - The following 3 files exist as 20x20 PNGs in the dungeon_437 folder:
    - `d437_044_period.png`
    - `d437_005_spade.png`
    - `d437_033_hash.png`

  - After running TexturePacker, verify the atlas metadata includes them:
    - `assets/graphics/sprites-0.json` contains entries with filenames matching the 3 `d437_...png` names

  - **TexturePacker Installation**: If not installed, download from https://www.codeandweb.com/texturepacker
    - Free version supports basic atlas packing
    - CLI available on all platforms

  **Must NOT do**:
  - Modify existing sprites
  - Change atlas configuration (padding, format, etc.)

  **Parallelizable**: NO (must complete before any rendering work)

  **References**:
  - `assets/graphics/sprites_texturepacker.tps` - TexturePacker project file
  - `assets/graphics/pre-packing-files_globbed/` - Source folder for atlas packing
  - `assets/graphics/sprites-0.json` - Generated atlas metadata

  **Acceptance Criteria** (MINIMUM VIABLE - 3 tiles required):
  - [ ] At least 3 PNG files exist in `assets/graphics/pre-packing-files_globbed/dungeon_437/`:
    - `d437_044_period.png` (grass) - 20×20 pixels
    - `d437_005_spade.png` (tree) - 20×20 pixels
    - `d437_033_hash.png` (rock) - 20×20 pixels
  - [ ] TexturePacker runs without error: `TexturePacker assets/graphics/sprites_texturepacker.tps`
  - [ ] Atlas regenerated: `assets/graphics/sprites-*.json` updated
  - [ ] Search sprites JSON for "d437_" entries: `grep "d437_" assets/graphics/sprites-*.json` returns matches
  
  **OPTIONAL (Full tileset)**: Import all 256 tiles if available, but only 3 are strictly required for Phase 2.2.
  
  **dungeon_mode/ is NOT required** for this project (only dungeon_437 is used for terrain).
  
  **If source tiles not found**:
  - Check other worktrees: `~/Projects/TheGameJamTemplate/TheGameJamTemplate/`
  - Or create the 3 minimal tiles manually (see OPTION B in "What to do" section above)

  **Commit**: YES
  - Message: `assets(sprites): add dungeon_437 tileset`
  - Files: `assets/graphics/pre-packing-files_globbed/dungeon_437/*` (3 minimum required), `assets/graphics/sprites-*.json`, `assets/graphics/sprites_atlas-*.png`

---

- [x] 0.1. Validate borderless window with ImGui

  **What to do**:
  
  **Modify `src/core/init.cpp`** (line 853):
  ```cpp
  // BEFORE:
  SetConfigFlags(FLAG_WINDOW_RESIZABLE);
  
  // AFTER (combine flags with bitwise OR):
  SetConfigFlags(FLAG_WINDOW_RESIZABLE | FLAG_WINDOW_UNDECORATED);
  ```
  
  - Test window opens without title bar
  - Test ImGui renders correctly in borderless mode
  - Test window resizing still works (both flags active)
  - Document any macOS-specific quirks
  
  **Window Drag Implementation (CONCRETE)**:
  
  Since Raylib's `SetWindowPosition()` is not exposed to Lua, implement window dragging in C++.
  
  **EXACT INSERTION POINT** in `src/main.cpp`:
  
  The main game loop is in `void RunGameLoop()` (lines 237-onward in `src/main.cpp`).
  The frame loop structure is:
  ```
  while (!WindowShouldClose()) {    // line ~253
      BeginDrawing();                // line ~258
      rlImGuiBegin();                // line ~263 (ImGui frame starts here)
      ... keyboard handlers ...
      ... game update/render calls ...
      rlImGuiEnd();
      EndDrawing();
  }
  ```
  
  **INSERT THE DRAG HANDLER** immediately after `BeginDrawing()` and BEFORE `rlImGuiBegin()`:
  
  ```cpp
  // In src/main.cpp, inside RunGameLoop(), after line 258 (BeginDrawing()):
  
  // === BORDERLESS WINDOW DRAGGING ===
  // Must run BEFORE rlImGuiBegin() so we can check WantCaptureMouse from previous frame
  {
      static bool isDragging = false;
      
      // Get ImGui state from previous frame (rlImGuiBegin hasn't been called yet)
      ImGuiIO& io = ImGui::GetIO();
      
      // Only drag if ImGui doesn't want the mouse
      if (!io.WantCaptureMouse) {
          Vector2 mousePos = GetMousePosition();
          int screenW = GetScreenWidth();
          int screenH = GetScreenHeight();
          int edgeMargin = 10;  // resize zone width
          
          // Check if in drag area (not near edges, reserved for resize)
          bool inDragArea = mousePos.x > edgeMargin && mousePos.x < screenW - edgeMargin &&
                           mousePos.y > edgeMargin && mousePos.y < screenH - edgeMargin;
          
          if (IsMouseButtonPressed(MOUSE_LEFT_BUTTON) && inDragArea) {
              isDragging = true;
          }
          
          if (IsMouseButtonReleased(MOUSE_LEFT_BUTTON)) {
              isDragging = false;
          }
          
          if (isDragging && IsMouseButtonDown(MOUSE_LEFT_BUTTON)) {
              Vector2 mouseDelta = GetMouseDelta();
              Vector2 windowPos = GetWindowPosition();
              SetWindowPosition((int)(windowPos.x + mouseDelta.x), 
                               (int)(windowPos.y + mouseDelta.y));
          }
      } else {
          // ImGui wants mouse - cancel any drag
          isDragging = false;
      }
  }
  // === END BORDERLESS WINDOW DRAGGING ===
  ```
  
  **WHY THIS LOCATION**:
  - After `BeginDrawing()`: Raylib is in drawing state, GetMouseDelta() works
  - Before `rlImGuiBegin()`: We use `io.WantCaptureMouse` from *previous* frame (ImGui state persists)
  - Before any game logic: Drag happens first, so window position is updated for this frame
  
  **Drag area definition**: 
  - Entire window EXCEPT 10px edges (reserved for resize handles)
  - When ImGui panels/buttons capture mouse (`WantCaptureMouse`), drag is disabled

  **Must NOT do**:
  - Build full UI - just verify the mechanism works
  - Implement actual game logic

  **Parallelizable**: NO (foundation for all other work)

  **References**:
  - `src/core/init.cpp:850-860` - Window creation with SetConfigFlags
  - `src/main.cpp:262-263` - ImGui frame setup (rlImGuiBegin/End)
  - `src/third_party/rlImGui/rlImGui.cpp` - ImGui backend

  **Minimum Window Size Enforcement**:
  
  Add to the drag handler block in `src/main.cpp` (or near window flag setup in `init.cpp`):
  ```cpp
  // Enforce minimum window size
  SetWindowMinSize(400, 300);  // Raylib API
  ```
  
  Alternatively, clamp in resize handler:
  ```cpp
  if (IsWindowResized()) {
      int w = GetScreenWidth();
      int h = GetScreenHeight();
      if (w < 400 || h < 300) {
          SetWindowSize(std::max(w, 400), std::max(h, 300));
      }
  }
  ```

  **Acceptance Criteria**:
  - [ ] Window opens without title bar (`FLAG_WINDOW_UNDECORATED` set in init.cpp)
  - [ ] Window can be moved by dragging (drag handler in main.cpp, BEFORE rlImGuiBegin)
  - [ ] Window can be resized by dragging edges (`FLAG_WINDOW_RESIZABLE` set)
  - [ ] ImGui panel renders without artifacts
  - [ ] Minimum size enforced (400x300) via `SetWindowMinSize()` or clamp
  - [ ] Manual: visually confirm on macOS

  **Commit**: YES
  - Message: `feat(window): add borderless widget mode with drag support`
  - Files: `src/core/init.cpp`, `src/main.cpp`

---

- [ ] 0.2. Validate GOAP suitability for idle game

  **What to do**:
  - Create minimal creature with Wander action only
  - Verify GOAP planning overhead is acceptable (<1ms per plan)
  - Verify `AITraceBuffer` captures events correctly
  - Test 20 simultaneous GOAP entities for performance
  
  **Instrumentation (EXACT LOCATION)**:
  - Measure GOAP planning time inside the replanning function:
    - `src/systems/ai/ai_system.cpp`
    - Function: `replan(entt::entity entity)`
    - Wrap ONLY the planner call:
      - `goapStruct.planCost = astar_plan(...)`
      - This call is currently at approximately `src/systems/ai/ai_system.cpp:2218-2220` (search for `astar_plan(&goapStruct.ap`)

  **Measurement method**:
  - Add a Tracy zone (preferred if available in this file) around the `astar_plan(...)` call, named e.g. `GOAP astar_plan`.
  - If Tracy macros are not available in this translation unit, use a `std::chrono` timer around `astar_plan(...)` and log the result (ms) with `SPDLOG_INFO` for the spike.

  **Must NOT do**:
  - Build full creature system - just validate approach
  - Create permanent game files yet

  **Parallelizable**: YES (with 0.1 after window works)

  **References**:
  - `assets/scripts/ai/entity_types/kobold.lua` - Existing entity type pattern
  - `src/systems/ai/goap_utils.hpp` - AITraceBuffer definition
  - `assets/scripts/ai/actions/wander.lua` - Existing wander action
  - `src/systems/ai/ai_system.cpp` - `replan()` function with `astar_plan()` call

  **Acceptance Criteria (performance)**:
  - [ ] Single entity: measured `astar_plan` time < 1ms in the profiler/logs
  - [ ] 20 entities: stable 60fps (manual) AND no sustained spikes above 1ms per plan on typical replans
  - [ ] AITraceBuffer shows GOAL_SELECTED, ACTION_START events

  **Commit**: YES
  - Message: `spike(ai): validate GOAP performance for idle game`
  - Files: temp spike files (can be removed after validation)

---

- [ ] 0.3. Validate forma terrain generation

  **What to do**:
  - Test forma cellular automata with "B5678/S45678" rule
  - Generate **30x20** pattern from seed 12345 (canonical grid size)
  - Verify identical output on repeated runs
  - Measure generation time (<100ms target)
  - Test flood-fill for connected region finding

  **Must NOT do**:
  - Create final terrain rendering - just validate data generation

  **Parallelizable**: YES (with 0.1, 0.2)

  **References**:
  - `assets/scripts/external/forma/automata.lua` - CA implementation
  - `assets/scripts/external/forma/primitives.lua` - Shape primitives
  - `assets/scripts/external/forma/pattern.lua` - Pattern class
  - `docs/external/forma_README.md` - Library documentation

  **Acceptance Criteria**:
  - [ ] `forma.primitives.square(30, 20)` creates domain (canonical size)
  - [ ] CA converges within 1000 iterations
  - [ ] Same seed produces identical pattern (compare cell count)
  - [ ] Generation completes in <100ms
  - [ ] Connected components found via flood-fill

  **Commit**: YES
  - Message: `spike(procgen): validate forma terrain generation`
  - Files: temp spike files

---

### Phase 1: Code Cleanup & Scene Setup

- [ ] 1.1. Create idle_game script folder structure and integrate loading

  **What to do**:
  - Create `assets/scripts/idle_game/` directory
  - Create `assets/scripts/idle_game/init.lua` (entry point)
  - Create `assets/scripts/idle_game/config.lua` (constants)
  - Create `assets/scripts/idle_game/scenes/` for scene files
  
  - **CRITICAL - Script loading model (DO NOT ASSUME main.lua is the only entry)**:
    - The engine does NOT only run `assets/scripts/core/main.lua`.
    - It enumerates directories from `assets/scripts/scripting_config.json` and `script_file()` loads **every .lua file** it finds in those directories at startup.
    - Verified loader loop: `src/systems/scripting/scripting_functions.cpp:401-427`
    - Directory enumeration (core/tutorial/monobehavior/task/ai): `src/systems/ai/ai_system.cpp:729-746`

  - **Integration approach for idle_game**:
    - We still add `require("idle_game.init")` in `assets/scripts/core/main.lua` so our module is reachable from the `main` table flow,
      BUT we must also ensure any auto-loaded files that hard-require combat/wand are neutralized before deleting those directories (see Task 1.3.0).

  **Must NOT do**:
  - Remove any existing code yet
  - Implement game logic yet
  - Modify `scripting_config.json` (use require from main.lua instead)

  **Parallelizable**: NO (sets up structure for all later work)

  **References**:
  - `assets/scripts/core/main.lua:1-40` - Lua entry point with existing requires (add `require("idle_game.init")` here)
  - `assets/scripts/scripting_config.json` - Script loading config (shows `coreDirectory: "core"` is the entry)
  - `assets/scripts/init/default.lua` - Existing init script pattern (NOT `init/init.lua` which doesn't exist)
  - `src/systems/scripting/scripting_functions.cpp` - initLuaMasterState loads scripts from configured directories

  **Acceptance Criteria**:
  - [ ] Directory structure exists: `assets/scripts/idle_game/{init.lua, config.lua, scenes/}`
  - [ ] `require("idle_game.init")` added to `assets/scripts/core/main.lua`
  - [ ] Game launches without Lua errors
  - [ ] `print("idle_game loaded")` in init.lua appears in console

  **Commit**: YES
  - Message: `feat(idle): create idle_game script folder structure`
  - Files: `assets/scripts/idle_game/*`, `assets/scripts/core/main.lua`

---

- [ ] 1.2. Create minimal game scene with Lua-level scene switching

  **What to do**:
  - Create `assets/scripts/idle_game/scenes/sim_scene.lua` with `init()`, `update(dt)`, `draw()` functions
  - **CRITICAL**: Game execution is driven by Lua's `main.init/update/draw` (see `src/core/game.cpp` calling `masterStateLua["main"]["init/update/draw"]`)
  
  **DECISION: Use new SIM_GAME state (not AUTO_START_MAIN_GAME)**
  - Reason: We want a completely separate scene, not repurposing existing IN_GAME which has combat/card dependencies
  
  **Implementation steps** (complete end-to-end):
  
  1. **Add new state** in `assets/scripts/core/main.lua:47`:
     ```lua
     GAMESTATE = {
         MAIN_MENU = 0,
         IN_GAME = 1,
         SIM_GAME = 2  -- ADD THIS
     }
     ```
  
  2. **Update `changeGameState()` function** at line 938-953 to handle SIM_GAME:
     ```lua
     elseif newState == GAMESTATE.SIM_GAME then
         sim_scene.init()
     ```
  
  3. **CRITICAL: Fix `main.init()` to start in SIM_GAME directly**
     At `assets/scripts/core/main.lua:1137`:
     ```lua
     -- BEFORE:
     changeGameState(GAMESTATE.MAIN_MENU)
     
     -- AFTER:
     changeGameState(GAMESTATE.SIM_GAME)  -- Launch directly into sim scene
     ```
  
  4. **CRITICAL: Disable autoStartMainGameEnv**
     At `assets/scripts/core/main.lua:1139-1148`, wrap in guard:
     ```lua
     -- BEFORE:
     if autoStartMainGameEnv then
         timer.after(0.25, function() ... end, "auto_start_main_game")
     end
     
     -- AFTER:
     if autoStartMainGameEnv and currentGameState ~= GAMESTATE.SIM_GAME then
         timer.after(0.25, function() ... end, "auto_start_main_game")
     end
     ```
  
  5. **Add sim_scene routing to `main.update()`** (PRECISE LOCATION):
      
      The current `main.update()` structure (line 1160-1235):
      - Lines 1176-1189: Timer/cache updates (run always)
      - Line 1191: `isPaused` check based on `gamePaused` or `MAIN_MENU`
      - Lines 1193-1196: `Node.update_all(dt)` if not paused
      - Lines 1202-1220: `MAIN_MENU` specific updates
      - Lines 1222-1225: Early return if paused
      - Lines 1227-1229: ProjectileSystemTest update
      
      **Insert at line ~1201** (after Node.update, before MAIN_MENU check):
      ```lua
      -- SIM_GAME update - runs when not paused
      if currentGameState == GAMESTATE.SIM_GAME and not isPaused then
          sim_scene.update(dt)
      end
      ```
      
      **Alternatively**, add after the MAIN_MENU block (line 1221):
      ```lua
      elseif currentGameState == GAMESTATE.SIM_GAME then
          sim_scene.update(dt)
      ```
  
  6. **Add sim_scene routing to `main.draw()`** (PRECISE LOCATION):
      
      `main.draw(dt)` is currently nearly empty (lines 1237-1240).
      Simply add:
      ```lua
      function main.draw(dt)
          if currentGameState == GAMESTATE.SIM_GAME then
              sim_scene.draw()
          end
      end
      ```
      
      **CRITICAL**: sim_scene should queue draw commands via `command_buffer.queueDrawSpriteTopLeft()` 
      and similar APIs (not immediate-mode drawing). These commands are processed by the C++ render loop.
  
  7. **Require sim_scene in main.lua** (near top with other requires):
     ```lua
     local sim_scene = require("idle_game.scenes.sim_scene")
     ```

  **Must NOT do**:
  - Modify C++ GameState enum (keep changes in Lua layer)
  - Implement actual game logic
  - Add UI elements yet

  **Parallelizable**: NO (depends on 1.1)

  **References**:
  - `src/core/game.cpp` - C++ calls `masterStateLua["main"]["init"]`, `["update"]`, `["draw"]`
  - `assets/scripts/core/main.lua:44-52` - GAMESTATE enum and currentGameState
  - `assets/scripts/core/main.lua:938-953` - `changeGameState()` function
  - `assets/scripts/core/main.lua:1137` - **main.init() calls changeGameState(MAIN_MENU) - MUST CHANGE**
  - `assets/scripts/core/main.lua:1139-1148` - **autoStartMainGameEnv auto-switches to IN_GAME - MUST GUARD**

  **Acceptance Criteria**:
  - [ ] `assets/scripts/idle_game/scenes/sim_scene.lua` exists with init/update/draw
  - [ ] `GAMESTATE.SIM_GAME = 2` added to main.lua:47
  - [ ] `changeGameState()` handles SIM_GAME at main.lua:938-953
  - [ ] main.init() calls `changeGameState(GAMESTATE.SIM_GAME)` at line 1137
  - [ ] autoStartMainGameEnv guarded to not override SIM_GAME
  - [ ] Game launches directly into sim scene (no menu, no auto-switch to IN_GAME)
  - [ ] Window is borderless and resizable
  - [ ] Empty scene renders (colored background visible)
  - [ ] `just build-debug` passes
  - [ ] No Lua errors in console

  **Commit**: YES
  - Message: `feat(idle): create minimal sim scene with direct launch`
  - Files: `assets/scripts/idle_game/scenes/sim_scene.lua`, `assets/scripts/core/main.lua`

---

- [ ] 1.3.0. Pre-cleanup: neutralize auto-loaded Lua files that require combat/wand

  **Why this exists (CRITICAL)**:
  - The engine auto-loads and executes *all* `.lua` files in configured directories at startup.
  - If any auto-loaded file contains `require("combat...")` or `require("wand...")`, deleting those directories will cause boot-time Lua errors.

  **What to do**:
  1. Identify "auto-loaded" directories (these are enumerated at boot):
     - From `assets/scripts/scripting_config.json`
       and `src/systems/ai/ai_system.cpp:729-746`
     - Directories include: `assets/scripts/core/`, `assets/scripts/tutorial/`, `assets/scripts/monobehavior/`, `assets/scripts/task/`, `assets/scripts/ai/`

  2. Scan auto-loaded files for hard dependencies:
     - Search patterns: `require("combat` and `require("wand`
     - Also search for known entry modules that pull these in indirectly (combat system, wand executor, etc.)

  3. For each offending auto-loaded file, choose ONE of the following solutions (keep behavior minimal):
     - **Option A (preferred): Move file out of an auto-loaded directory** into a non-auto-loaded folder so it won't be executed at boot.
     - **Option B: Wrap the dependency in `pcall(require, ...)` and gate usage** so missing combat/wand doesn't crash boot.
     - **Option C: Remove the file entirely** if it is purely game-specific and not required for the sim widget.

  **Hard guardrail**:
  - Do NOT delete `assets/scripts/tutorial/` directory itself (engine enumerates it at boot). Keep directory present; it can be empty or have a placeholder.

  **References (verified example of the problem)**:
  - `assets/scripts/core/gameplay.lua:13-26` hard-requires `combat.*` and `wand.*` (must be neutralized before deleting those directories).

  **Acceptance Criteria**:
  - [ ] No auto-loaded `.lua` file hard-requires `combat.*` or `wand.*` (directly or indirectly).
  - [ ] After neutralization (but before deleting directories), the game boots with no Lua require errors.
  - [ ] `just build-debug` passes.

  **Commit**: YES
  - Message: `chore(cleanup): neutralize auto-loaded files with combat/wand dependencies`
  - Files: Various (core/*.lua, etc.)

---

- [ ] 1.3. Remove unused game code (surgical)

  **What to do**:
  - **PREREQ**: Task 1.3.0 must be completed first (neutralize auto-loaded `require("combat")` / `require("wand")`).
  - Create git branch `phase-1-cleanup`
  - Remove `assets/scripts/combat/` directory
  - Remove `assets/scripts/wand/` directory
  - **KEEP `assets/scripts/tutorial/` directory** (see CRITICAL note below)
  - Search for and remove remaining `require("combat")` etc. from any non-auto-loaded files
  - Remove game-specific UI in `assets/scripts/ui/` (keep core UI helpers)
  - Build after each removal to catch breaks immediately
  - Document any unexpected dependencies
  
  **CRITICAL: Tutorial Directory Handling**
  - `assets/scripts/scripting_config.json` specifies `"tutorialDirectory": "tutorial"`
  - `src/systems/ai/ai_system.cpp:737-742` calls `getLuaFilesFromDirectory(tutorialDir, luaFiles)`
  - **If directory is deleted, engine init will fail** during directory enumeration
  - **Solution**: Keep `assets/scripts/tutorial/` directory but **empty its contents** (or keep one minimal placeholder file)
  - Alternatively, remove "tutorialDirectory" from scripting_config.json (but this requires C++ recompile to avoid null access)

  **Must NOT do**:
  - Remove `src/systems/` (engine code)
  - Remove `assets/scripts/core/` (engine Lua)
  - Remove `assets/scripts/external/` (libraries)
  - Remove `assets/scripts/ai/` (keep GOAP system)
  - Remove test files
  - **Delete tutorial/ directory entirely** (keep empty or placeholder)

  **Parallelizable**: NO (must be done carefully, sequentially)

  **References**:
  - Use `ast_grep_search` pattern `require("combat")` to find usages
  - Use `grep` for `wand` to find card system references
  - `assets/scripts/core/main.lua:13` - Has `require("combat.combat_system")` that must be removed
  - `assets/scripts/init/default.lua` - Init scripts (NOT `init/init.lua` which doesn't exist)
  - `assets/scripts/scripting_config.json` - Script loader config (tutorialDirectory: "tutorial")
  - `src/systems/ai/ai_system.cpp:737-742` - Tutorial directory enumeration (will fail if dir missing)

  **Acceptance Criteria**:
  - [ ] `just build-debug` passes after all removals
  - [ ] No `require("combat")` in any loaded file
  - [ ] No `require("wand")` in any loaded file
  - [ ] `assets/scripts/combat/` directory gone
  - [ ] `assets/scripts/wand/` directory gone
  - [ ] `assets/scripts/tutorial/` directory **EXISTS** (empty or placeholder)
  - [ ] Game launches without errors

  **Commit**: YES (multiple small commits during removal)
  - Message: `chore(cleanup): remove combat system`, `chore(cleanup): remove wand system`, etc.
  - Files: Various

---

### Phase 2: Terrain Generation

- [ ] 2.1. TDD: Terrain generator module

  **What to do**:
  - Write tests in `assets/scripts/tests/test_idle_terrain.lua`
  - Test: `terrain.generate(seed, width, height)` returns grid
  - Test: Same seed produces identical grid
  - Test: Grid contains GRASS, TREE, ROCK tile types
  - Test: Tile distribution within acceptable ranges (15-25% trees, 5-15% rocks, 60-80% grass)
  - Implement `assets/scripts/idle_game/terrain.lua` to pass tests

  **Must NOT do**:
  - Add rendering yet (data only)
  - Add more than 3 tile types

  **Parallelizable**: YES (with 2.2 after interface defined)

  **References**:
  - `assets/scripts/external/forma/automata.lua` - CA rules
  - `assets/scripts/external/forma/primitives.lua` - Domain creation
  - `assets/scripts/tests/test_procgen_terrain.lua` - Existing test pattern

  **Acceptance Criteria**:
  - [ ] Test file exists with 5+ test cases
  - [ ] All Lua tests pass: `lua assets/scripts/tests/test_idle_terrain.lua` → "All tests passed"
  - [ ] Seed 12345 produces consistent output
  - [ ] Generation <100ms for 30x20 grid (canonical size)
  - [ ] Tile distribution within tolerance: trees 15-25%, rocks 5-15%, grass 60-80%

  **Commit**: YES
  - Message: `feat(idle): add TDD terrain generator with forma CA`
  - Files: `assets/scripts/idle_game/terrain.lua`, `assets/scripts/tests/test_idle_terrain.lua`
  - Pre-commit: `lua assets/scripts/tests/test_idle_terrain.lua` (Lua tests) + `just build-debug` (build check)

---

- [ ] 2.2. Render terrain with ASCII sprites

  **What to do**:
  - Create `assets/scripts/idle_game/terrain_renderer.lua`
  - Map tile types to sprite names (GRASS, TREE, ROCK)
  
  **RENDERING APPROACH: Use imported dungeon_437 sprites with queueDrawSpriteTopLeft**
  
  This is the ONLY supported rendering approach. Phase 0.0 MUST be completed first.
  
  **Why this approach**:
  - `drawSpriteComponentASCII` - **DO NOT USE**: Has tile visibility check that returns false (`src/core/graphics.cpp:91-96`)
  - `queueTexturePro` with raw CP437 - **DO NOT USE**: Requires texture handle not readily available in Lua
  - `queueDrawSpriteTopLeft` with imported atlas sprites - **USE THIS**: Simple, proven, sprites in atlas after Phase 0.0
  
  **DEPENDENCY: Phase 0.0 must complete first**
  - Phase 0.0 imports dungeon_437 tiles into `assets/graphics/pre-packing-files_globbed/dungeon_437/`
  - TexturePacker adds them to the main sprite atlas
  - This task uses those atlas sprites via `queueDrawSpriteTopLeft`
  
  **Sprite names** (verify in `assets/graphics/sprites-*.json` after Phase 0.0):
  - Naming convention: `d437_{sprite_number}_{description}.png`
  - GRASS: `d437_044_period.png` (the '.' character, sprite_number 44)
  - TREE: `d437_005_spade.png` (the '♠' character, sprite_number 5)
  - ROCK: `d437_033_hash.png` (the '#' character, sprite_number 33)
  
  **Implementation**:
  ```lua
  -- In terrain_renderer.lua
  local TILE_SIZE = 20
  
  -- Sprite names from dungeon_437 import
  -- Verify these names exist in sprites-*.json after Phase 0.0
  local TILE_SPRITES = {
      GRASS = "d437_044_period.png",
      TREE = "d437_005_spade.png",
      ROCK = "d437_033_hash.png",
  }
  
  local TILE_COLORS = {
      GRASS = Color(34, 139, 34, 255),   -- Forest green
      TREE = Color(139, 69, 19, 255),    -- Saddle brown
      ROCK = Color(128, 128, 128, 255),  -- Gray
  }
  
  function TerrainRenderer.draw(terrainGrid)
      for y = 0, terrainGrid.height - 1 do
          for x = 0, terrainGrid.width - 1 do
              local tileType = terrainGrid:get(x, y)
              command_buffer.queueDrawSpriteTopLeft(layers.sprites, function(c)
                  c.spriteName = TILE_SPRITES[tileType]
                  c.x = x * TILE_SIZE
                  c.y = y * TILE_SIZE
                  c.dstW = TILE_SIZE
                  c.dstH = TILE_SIZE
                  c.tint = TILE_COLORS[tileType]
              end, 0, layer.DrawCommandSpace.World)
          end
      end
  end
  ```
  
  **Tile Size**: **20x20 pixels**
  - 30x20 grid at 20px = 600x400 world space (good for widget)

  **Must NOT do**:
  - Add animation to terrain
  - Add more visual variants yet
  - Use `drawSpriteComponentASCII` (visibility check will block rendering)

  **Parallelizable**: YES (with 2.1 after terrain data available)

  **References**:
  - `assets/scripts/chugget_code_definitions.lua:7865-7869` - `queueTexturePro` API
  - `assets/graphics/cp437_20x20_sprites.png` - CP437 tileset (16x16 grid of 20x20 tiles)
  - `assets/graphics/cp437_mappings.json` - sprite_number to character mapping
  - `assets/scripts/core/gameplay.lua:6687-6757` - Working sprite queue pattern (for reference)
  - `src/core/graphics.cpp:91-96` - isTileVisible returns false (explains WHY to avoid drawSpriteComponentASCII)

  **Acceptance Criteria**:
  - [ ] Terrain grid visible in window (30x20 at 20px = 600x400)
  - [ ] Trees appear as ASCII character in brown/green
  - [ ] Rocks appear as '#' in gray
  - [ ] Grass appears as '.' in green
  - [ ] Tiles render via `command_buffer.queueDrawSpriteTopLeft` using atlas sprite names from the `dungeon_437` import (Phase 0.0)
  - [ ] Stable 60fps with terrain rendered

  **Commit**: YES
  - Message: `feat(idle): render terrain with ASCII sprites`
  - Files: `assets/scripts/idle_game/terrain_renderer.lua`

---

### Phase 3: Creature System

- [ ] 3.1. Define creature entity types, goal selectors, and worldstate updaters

  **What to do**:
  
  **PART A: Entity Type Definition**
  - Create `assets/scripts/ai/entity_types/forager.lua` (auto-loaded by ai/init.lua:36)
  - Entity type table structure:
    ```lua
    return {
        initial = { hungry = true, hasFood = false, nearTree = false, wander = false },
        goal = { hungry = false }
    }
    ```

  **PART B: Goal Selector (REQUIRED for GOAP to work)**
  - **CRITICAL**: Goal selectors MUST be **functions**, not tables. The engine calls `goap.def["goal_selectors"][type](entity)`.
  - Create `assets/scripts/ai/goal_selectors/forager.lua` (auto-loaded by ai/init.lua:34)
  - **CORRECT Goal selector structure** (see `assets/scripts/ai/goal_selectors/gold_digger.lua` for working example):
    ```lua
    -- assets/scripts/ai/goal_selectors/forager.lua
    local selector = require("ai.goal_selector_engine")
    
    return function(e)
        local def = ai.get_entity_ai_def(e)
        
        -- Use shared policy/goals by default
        def.policy = def.policy or ai.policy
        def.goals  = def.goals  or ai.goals
        
        log_debug("Forager Goal Selector for entity " .. tostring(e))
        
        selector.select_and_apply(e)
    end
    ```
  
  **GOAP ATOM SCHEMA AND LOOP (CRITICAL for coherent behavior)**
  
  The entity type's `initial` and `goal` states define the atom schema.
  Goals and actions must work together to create a repeatable behavior loop.
  
  **Intended behavior loop**:
  ```
  hungry=true → (wants FORAGE) → nearTree? → forage action → hasFood=true
             → (wants CONSUME) → consume action → hungry=false
             → (idle) → wander → hungry becomes true again via worldstate updater
  ```
  
  - **Register forager goals** in `ai.goals` table (in `assets/scripts/idle_game/init.lua`):
    ```lua
    -- FORAGE: When hungry and near a tree, forage for food
    ai.goals.FORAGE = {
        band = "WORK",
        persist = 0.08,
        desire = function(e, S)
            -- Want to forage when hungry AND near a tree
            local hungry = ai.get_worldstate(e, "hungry")
            local nearTree = ai.get_worldstate(e, "nearTree")
            return (hungry and nearTree) and 1.0 or 0.0
        end,
        on_apply = function(e)
            ai.set_goal(e, { hasFood = true })  -- Planner finds forage action
        end
    }
    
    -- CONSUME: When have food, eat it to satisfy hunger
    ai.goals.CONSUME = {
        band = "SURVIVAL",
        persist = 0.1,
        desire = function(e, S)
            local hasFood = ai.get_worldstate(e, "hasFood")
            return hasFood and 0.9 or 0.0
        end,
        on_apply = function(e)
            ai.set_goal(e, { hungry = false })  -- Planner finds consume action
        end
    }
    
    -- IDLE_WANDER: Default fallback when nothing else to do
    ai.goals.IDLE_WANDER = {
        band = "IDLE",
        persist = 0.05,
        desire = function(e, S) return 0.2 end,
        on_apply = function(e)
            ai.patch_worldstate(e, "wander", false)  -- Clear sticky toggle (see init.lua:73)
            ai.set_goal(e, { wander = true })
        end
    }
    ```

  **PART C: Worldstate Updaters (REQUIRED for preconditions)**
  - **CRITICAL**: Atoms like `nearTree` won't become true unless a worldstate updater sets them
  
  **MODULE STRUCTURE** (see actual file: `assets/scripts/ai/worldstate_updaters.lua`):
  - The file returns a table: `return { updater_name = function(entity, dt) ... end, ... }`
  - Add new updaters as additional keys in this returned table
  - Updaters are invoked per-entity per-frame by the AI system (see `src/systems/ai/ai_system.cpp`)
  
  **HOW TO ADD**: Edit `assets/scripts/ai/worldstate_updaters.lua` to include:
  ```lua
  return {
      -- ... existing updaters (hunger_check, enemy_sight, etc.) ...
      
      -- ADD THIS NEW ENTRY:
      forager_sensing = function(entity, dt)
          -- ... implementation below ...
      end,
  }
  ```
  
  **FULL IMPLEMENTATION** (add as entry in returned table, NOT as assignment):
  
  Edit `assets/scripts/ai/worldstate_updaters.lua` to add this entry inside the `return { ... }` block:
  ```lua
  -- In assets/scripts/ai/worldstate_updaters.lua, add inside the return { ... }:
  
  forager_sensing = function(entity, dt)
      -- Get entity position from Transform component
      -- Transform is exposed to Lua via registry:get(entity, Transform)
      -- See: assets/scripts/chugget_code_definitions.lua:3539-3561 (Transform fields)
      -- IMPORTANT: Transform fields are actualX/actualY (logical) and visualX/visualY (interpolated)
      -- Use actualX/actualY for game logic (sensing), visualX/visualY for rendering/hit tests
      local transform = registry:get(entity, Transform)
      if not transform then return end
      
      -- Creature positions are in WORLD/PIXEL coordinates
      -- Convert to TILE coordinates for terrain queries
      -- Use actualX/actualY for logical position (sensing)
      local TILE_SIZE = 20  -- Must match terrain_renderer.lua
      local tileX = math.floor(transform.actualX / TILE_SIZE)
      local tileY = math.floor(transform.actualY / TILE_SIZE)
      
      -- Query terrain module singleton (created in idle_game/terrain.lua)
      -- terrain module must expose: terrain.get(x,y) and terrain.isNearTileType(tileX, tileY, type, radius)
      local terrain = require("idle_game.terrain")
      local nearTree = terrain.isNearTileType(tileX, tileY, "TREE", 2)  -- within 2 tiles
      ai.set_worldstate(entity, "nearTree", nearTree)
      
      -- HUNGER REGENERATION: Over time, creature becomes hungry again
      -- This closes the behavior loop so foraging repeats
      local hungry = ai.get_worldstate(entity, "hungry")
      if not hungry then
          -- Use blackboard to track time since last meal
          -- Blackboard API: ai.bb.get(entity, key, default) / ai.bb.set(entity, key, value)
          -- See: src/systems/ai/ai_system.cpp:1164+ for binding
          local hunger_timer = ai.bb.get(entity, "hunger_timer", 0) + dt
          if hunger_timer > 10.0 then  -- Get hungry every 10 seconds
              ai.set_worldstate(entity, "hungry", true)
              ai.bb.set(entity, "hunger_timer", 0)
          else
              ai.bb.set(entity, "hunger_timer", hunger_timer)
          end
      end
  end,  -- Note the trailing comma!
  ```
  
  **The file structure should look like**:
  ```lua
  -- assets/scripts/ai/worldstate_updaters.lua
  return {
      hunger_check = function(entity, dt) ... end,
      enemy_sight = function(entity, dt) ... end,
      -- ... other existing updaters ...
      
      forager_sensing = function(entity, dt)
          -- implementation above
      end,
  }
  ```
  
  **TERRAIN MODULE API REQUIREMENTS** (must be implemented in Task 2.1):
  
  The terrain module at `assets/scripts/idle_game/terrain.lua` must expose:
  ```lua
  local M = {}
  M._grid = nil  -- 2D grid storage: M._grid[y][x] = "GRASS"|"TREE"|"ROCK"
  M.width = 30   -- Grid width in tiles
  M.height = 20  -- Grid height in tiles
  
  -- Get tile type at tile coordinates
  function M.get(tileX, tileY)
      if tileX < 0 or tileX >= M.width or tileY < 0 or tileY >= M.height then
          return nil
      end
      return M._grid[tileY][tileX]
  end
  
  -- Check if any tile of given type is within radius (in tiles)
  function M.isNearTileType(tileX, tileY, tileType, radius)
      for dy = -radius, radius do
          for dx = -radius, radius do
              local tile = M.get(tileX + dx, tileY + dy)
              if tile == tileType then
                  return true
              end
          end
      end
      return false
  end
  
  return M
  ```
  
  **COORDINATE SPACES**:
  - **World/Pixel**: Used by Transform, rendering, input (0-600 x 0-400 for default window)
  - **Tile**: Used by terrain grid (0-29 x 0-19 for 30x20 grid)
  - **Conversion**: `tileX = math.floor(worldX / TILE_SIZE)`, `tileY = math.floor(worldY / TILE_SIZE)`
  - **TILE_SIZE = 20** (must be consistent across terrain.lua, terrain_renderer.lua, and worldstate_updaters.lua)
  
  **TRANSFORM FIELDS** (see `assets/scripts/chugget_code_definitions.lua:3539-3561`):
  - `actualX`, `actualY`: Logical position (use for game logic, sensing, pathfinding)
  - `visualX`, `visualY`: Spring-interpolated position (use for rendering, hit tests, UI)
  - `actualW`, `actualH`, `visualW`, `visualH`: Width/height
  - `rotation`, `scale`: Rotation in degrees, scale multiplier

  **Must NOT do**:
  - Add more than 1 creature type initially
  - Add death/reproduction

  **Parallelizable**: NO (foundational for 3.2)

  **References**:
  - `assets/scripts/ai/goal_selectors/gold_digger.lua` - **WORKING goal selector pattern** (returns a function, uses selector.select_and_apply)
  - `assets/scripts/ai/goal_selector_engine.lua` - Engine that evaluates goals and applies highest-desire
  - `assets/scripts/ai/entity_types/kobold.lua` - Entity type structure (`initial` and `goal` tables)
  - `assets/scripts/ai/init.lua:33-37` - `load_directory` loads goal_selectors (NOT assignByReturnName, so filename becomes key)
  - `assets/scripts/ai/init.lua:47-129` - `ai.goals` table where goal definitions live (DIG_FOR_GOLD, WANDER, DEMO_* examples)
  - `assets/scripts/ai/init.lua:132-138` - Default goal selector pattern
  - `assets/scripts/ai/worldstate_updaters.lua` - Sensor functions that update world state

  **Acceptance Criteria**:
  - [ ] `ai.entity_types.forager` accessible from Lua: `print(ai.entity_types.forager ~= nil)` → true
  - [ ] `ai.goal_selectors.forager` is a **function**: `print(type(ai.goal_selectors.forager))` → "function"
  - [ ] `ai.goals.FORAGE` and `ai.goals.IDLE_WANDER` registered
  - [ ] Worldstate updater for `nearTree` exists in `ai.worldstate_updaters`
  - [ ] Test spawn with `initGOAPComponent(registry, entity, "forager")` → no "No goal selector found" log

  **Commit**: YES
  - Message: `feat(idle): define forager entity type with goal selector and worldstate updater`
  - Files: `assets/scripts/ai/entity_types/forager.lua`, `assets/scripts/ai/goal_selectors/forager.lua`, `assets/scripts/ai/worldstate_updaters.lua`, `assets/scripts/idle_game/init.lua`

---

- [ ] 3.2. Implement GOAP actions (Wander, Forage, Idle) and register with AI system

  **What to do**:
  - **CRITICAL INTEGRATION**: Actions are loaded via `assets/scripts/ai/init.lua:33`:
    ```lua
    load_directory("ai.actions", ai.actions, true)  -- 'true' means use mod.name as key
    ```
    This loads from `assets/scripts/ai/actions/` and indexes by the action's `name` field.
  - **Required action table structure** (from `dig_for_gold.lua`):
    ```lua
    return {
        name = "idle_wander",  -- MUST match planner's action ID exactly
        cost = 1,
        pre = {},              -- Preconditions: {atom_name = bool_value}
        post = {},             -- Postconditions: {atom_name = bool_value}
        watch = {},            -- Atoms that trigger interrupt if changed
        start = function(e) end,
        update = function(e, dt)
            -- CRITICAL: Must return ActionResult enum, NOT strings!
            -- ActionResult.SUCCESS - action completed successfully
            -- ActionResult.RUNNING - action still in progress
            -- ActionResult.FAILURE - action failed
            return ActionResult.SUCCESS
        end,
        finish = function(e) end,
        abort = function(e, reason) end  -- Optional
    }
    ```
  - Create actions in `assets/scripts/ai/actions/` (auto-loaded):
    - `idle_wander.lua`: cost=1, pre={}, post={wander=true}, move randomly
    - `idle_forage.lua`: cost=2, pre={nearTree=true, hungry=true}, post={hasFood=true}, harvest tree
    - `idle_consume.lua`: cost=1, pre={hasFood=true}, post={hungry=false, hasFood=false}, consume food
  
  **Actions must close the loop** - consume clears both `hasFood` and `hungry`, allowing hunger to return
  
  - **Example idle_wander action** (adapted from existing `wander.lua`):
    ```lua
    -- assets/scripts/ai/actions/idle_wander.lua
    -- Update function returns ActionResult.SUCCESS, ActionResult.RUNNING or ActionResult.FAILURE
    
    return {
        name = "idle_wander",
        cost = 1,
        pre = {},
        post = { wander = true },
        watch = {},
        
        start = function(e)
            log_debug("idle_wander: start for entity " .. tostring(e))
        end,
        
        update = function(e, dt)
            -- Simple wander: pick random direction, move for a bit
            -- TODO: Implement actual movement
            return ActionResult.SUCCESS  -- NOT "SUCCESS" string!
        end,
        
        finish = function(e)
            log_debug("idle_wander: finish for entity " .. tostring(e))
        end,
        
        abort = function(e, reason)
            log_debug("idle_wander: aborted - " .. tostring(reason))
        end
    }
    ```

  **Must NOT do**:
  - Add more than 3 actions
  - Add combat actions
  - Return string literals like `"SUCCESS"` - MUST use `ActionResult.SUCCESS`

  **Parallelizable**: NO (depends on 3.1)

  **References**:
  - `assets/scripts/ai/actions/wander.lua` - Existing wander pattern, line 40 shows `return ActionResult.SUCCESS`
  - `assets/scripts/ai/actions/dig_for_gold.lua` - Full action lifecycle example, lines 36,148 show ActionResult usage
  - `assets/scripts/ai/actions/demo_rest.lua` - Shows SUCCESS/RUNNING/FAILURE patterns at lines 26,54,58
  - `assets/scripts/ai/action.lua` - Action helper factory (`A.instant()`, `A.timed()`)
  - `assets/scripts/ai/init.lua:33` - How actions are loaded (`load_directory` with `assignByReturnName=true`)

  **Acceptance Criteria**:
  - [ ] `ai.actions["idle_wander"]` accessible from Lua
  - [ ] Each action has: name, cost, pre, post, start, update, finish
  - [ ] Action `update` returns `ActionResult.SUCCESS`, NOT string `"SUCCESS"`
  - [ ] Verify: `print(type(ActionResult.SUCCESS))` → "userdata" or "number" (NOT "string")
  - [ ] Test: creature with forager type successfully plans with these actions

  **Commit**: YES
  - Message: `feat(idle): implement Wander, Forage, Idle GOAP actions`
  - Files: `assets/scripts/ai/actions/idle_*.lua` OR `assets/scripts/idle_game/actions/*.lua` + registration

---

- [ ] 3.3. Spawn creatures with GOAP

  **What to do**:
  - Create `assets/scripts/idle_game/spawner.lua`
  - Use Poisson-disc sampling for natural distribution
  - Spawn 5 forager creatures on grass tiles only
  - Attach GOAPComponent to each
  - Verify creatures begin executing plans

  **Must NOT do**:
  - Spawn on invalid tiles (trees, rocks)
  - Spawn more than 20 creatures

  **Parallelizable**: NO (depends on 3.2)

  **References**:
  - `assets/scripts/external/forma/pattern.lua:762-766` - Poisson-disc sampling via `pattern:sample_poisson(distance, radius, rng)` (NOT in utils/random.lua)
  - `assets/scripts/ai/init.lua` - GOAP attachment pattern
  - `src/systems/ai/ai_system.cpp` - initGOAPComponent API

  **Acceptance Criteria**:
  - [ ] 5 creatures spawn on grass tiles
  - [ ] Creatures visible with ASCII sprite
  - [ ] Creatures move (wander action executing)
  - [ ] GOAP plans visible in console log
  - [ ] 60fps maintained with 5 creatures

  **Commit**: YES
  - Message: `feat(idle): spawn forager creatures with GOAP AI`
  - Files: `assets/scripts/idle_game/spawner.lua`

---

### Phase 4: Resource System

- [ ] 4.1. TDD: Resource accumulation module

  **What to do**:
  - Write tests in `assets/scripts/tests/test_idle_resources.lua`
  - Test: Initial resources are 0
  - Test: `resources.add("food", 5)` increases food by 5
  - Test: `resources.get("food")` returns current amount
  - Test: Resources capped at 9999
  - Test: Passive accumulation formula: `base + (upgrade_level * 0.1)`
  - Implement `assets/scripts/idle_game/resources.lua`

  **Must NOT do**:
  - Add more than 4 resource types
  - Add complex resource interactions

  **Parallelizable**: YES (with 4.2)

  **References**:
  - `assets/scripts/core/procgen.lua` - Similar DSL pattern
  - `assets/scripts/tests/test_procgen.lua` - Test file pattern

  **Acceptance Criteria**:
  - [ ] Test file with 8+ test cases
  - [ ] All Lua tests pass: `lua assets/scripts/tests/test_idle_resources.lua` → "All tests passed"
  - [ ] Resources: food, wood, stone, gold
  - [ ] Cap enforced at 9999

  **Commit**: YES
  - Message: `feat(idle): TDD resource accumulation system`
  - Files: `assets/scripts/idle_game/resources.lua`, `assets/scripts/tests/test_idle_resources.lua`
  - Pre-commit: `lua assets/scripts/tests/test_idle_resources.lua` (Lua tests) + `just build-debug` (build check)

---

- [ ] 4.2. Resource UI display

  **What to do**:
  - Create `assets/scripts/idle_game/ui/resource_panel.lua`
  - Display 4 resources in corner (top-right)
  - Use ASCII icons: food='*', wood='=', stone='o', gold='$'
  - Update every frame from resource module
  - Use ImGui for simple display

  **Must NOT do**:
  - Build custom UI framework
  - Add animations to UI

  **Parallelizable**: YES (with 4.1 after interface defined)

  **References**:
  - `src/third_party/rlImGui/rlImGui.cpp` - ImGui integration
  - ImGui documentation for window creation

  **Acceptance Criteria**:
  - [ ] Panel visible in top-right corner
  - [ ] All 4 resources displayed with values
  - [ ] Values update in real-time
  - [ ] Panel doesn't obstruct game view

  **Commit**: YES
  - Message: `feat(idle): resource UI panel with ImGui`
  - Files: `assets/scripts/idle_game/ui/resource_panel.lua`

---

- [ ] 4.3. Click-to-collect mechanic

  **What to do**:
  - Implement click detection on terrain tiles
  - Click tree: +1 wood, tree becomes grass
  - Click rock: +1 stone, rock becomes grass
  - Click grass: no effect
  - Creature forage: +1 food (automatic from GOAP)
  - Passive: +0.1 gold/second
  
  **INPUT SYSTEM (Lua bindings exist)**:
  
  **Mouse Position** (verified):
  ```lua
  -- Use input.getMousePos() - this is the ONLY mouse position API
  -- Binding: src/systems/input/input_lua_bindings.cpp:412
  -- Returns virtual/letterbox-corrected coordinates (already scaled)
  local mouse = input.getMousePos()
  local mouseX, mouseY = mouse.x, mouse.y
  ```
  
  **Mouse Click Detection** (two options, both verified):
  ```lua
  -- Option A: Direct check (verified at gameplay.lua:536)
  local leftClick = input.isMousePressed(MouseButton.MOUSE_BUTTON_LEFT)
  
  -- Option B: Action binding (verified at main.lua:1003)
  -- In sim_scene.init():
  input.bind("sim_click", { device="mouse", key=MouseButton.BUTTON_LEFT, trigger="Pressed", context="sim_game" })
  input.set_context("sim_game")  -- CRITICAL: Set context in scene init!
  
  -- In sim_scene.update():
  if input.action_pressed("sim_click") then ... end
  ```
  
  **INPUT CONTEXT (CRITICAL)**:
  - Set input context in sim_scene.init(): `input.set_context("sim_game")`
  - This ensures action bindings with `context="sim_game"` will fire
  - See `assets/scripts/core/gameplay.lua:8134` for context switching pattern
  
  **World-to-tile conversion**:
  ```lua
  local function screenToTile(screenX, screenY)
      local tileX = math.floor(screenX / TILE_SIZE)
      local tileY = math.floor(screenY / TILE_SIZE)
      return tileX, tileY
  end
  ```

  **Must NOT do**:
  - Add particle effects for collection
  - Add sound effects

  **Parallelizable**: NO (depends on 4.1)

  **References**:
  - `assets/scripts/ui/hover_registry.lua:12-29` - **Verified `input.getMousePos()` fallback pattern**
  - `assets/scripts/core/gameplay.lua:536-537` - `input.isMousePressed(MouseButton.MOUSE_BUTTON_LEFT)` usage
  - `assets/scripts/core/gameplay.lua:8134` - `input.set_context("gameplay")` example
  - `assets/scripts/core/main.lua:1003` - Mouse binding example with context

  **Acceptance Criteria**:
  - [ ] `input.set_context("sim_game")` called in sim_scene.init()
  - [ ] Click tree → wood count increases
  - [ ] Clicked tree disappears (becomes grass)
  - [ ] Click rock → stone count increases
  - [ ] Gold increases over time
  - [ ] Food increases when creatures forage
  - [ ] Mouse position correctly converts to tile coordinates

  **Commit**: YES
  - Message: `feat(idle): click-to-collect resource mechanic`
  - Files: `assets/scripts/idle_game/input.lua`, `assets/scripts/idle_game/scenes/sim_scene.lua`

---

### Phase 5: Debug UI

- [ ] 5.1. Click-to-select entity

  **What to do**:
  - Implement entity selection on click
  - Store selected entity ID in scene state
  - Visual indicator on selected entity (highlight/outline)
  - Click elsewhere to deselect
  
  **Implementation approach**:
  ```lua
  -- In selection.lua
  local Selection = {
      selected_entity = nil,
      _previous_entity = nil  -- Track for cleanup
  }
  
  function Selection.update()
      if input.isMousePressed(MouseButton.MOUSE_BUTTON_LEFT) then
          local mouse = input.getMousePos()
          local clicked_entity = Selection.findEntityAtPosition(mouse.x, mouse.y)
          
          -- Clean up previous selection
          if Selection._previous_entity and Selection._previous_entity ~= clicked_entity then
              Selection._removeOutline(Selection._previous_entity)
          end
          
          -- Apply new selection
          Selection.selected_entity = clicked_entity
          Selection._previous_entity = clicked_entity
          
          if clicked_entity then
              Selection._addOutline(clicked_entity)
          end
      end
  end
  
  function Selection.findEntityAtPosition(x, y)
      -- Use ai.list_goap_entities() to get all GOAP-controlled creatures
      -- CRITICAL: Use DOT notation (ai.list_goap_entities), NOT colon (ai:list_goap_entities)
      -- The binding takes zero arguments; colon call would pass 'self' causing error
      -- See: assets/scripts/ui/ai_inspector.lua for working usage pattern
      -- See: src/systems/ai/ai_system.cpp for binding definition
      local goap_entities = ai.list_goap_entities()
      
      for _, entity in ipairs(goap_entities) do
          if registry:valid(entity) and registry:has(entity, Transform) then
              local t = registry:get(entity, Transform)
              -- Use visualX/visualY for hit testing (where entity appears on screen)
              -- Transform fields: actualX/actualY (logical), visualX/visualY (interpolated display)
              -- See: assets/scripts/chugget_code_definitions.lua:3539-3561
              local halfSize = TILE_SIZE / 2
              if x >= t.visualX - halfSize and x <= t.visualX + halfSize and
                 y >= t.visualY - halfSize and y <= t.visualY + halfSize then
                  return entity
              end
          end
      end
      return nil
  end
  
  -- NOTE: ai.list_goap_entities() (DOT notation!) is the preferred way to iterate over creatures.
  -- All forager entities have GOAPComponent attached via initGOAPComponent().
  ```
  
  **Visual indicator: Shader pass API** (verified from `assets/scripts/core/hitfx.lua:43-69`):
  ```lua
  function Selection._addOutline(entity)
      -- Ensure ShaderPipelineComponent exists
      if not registry:has(entity, shader_pipeline.ShaderPipelineComponent) then
          registry:emplace(entity, shader_pipeline.ShaderPipelineComponent)
      end
      local pipeline = registry:get(entity, shader_pipeline.ShaderPipelineComponent)
      
      -- Add pass by NAME (string), NOT by object
      pipeline:addPass("efficient_pixel_outline")
      
      -- Set uniforms via ShaderUniformComponent
      -- API: uniforms:set(shaderName, uniformName, value)
      -- NOT: uniforms:setFloat() / uniforms:setColor() (those don't exist)
      if not registry:has(entity, shaders.ShaderUniformComponent) then
          registry:emplace(entity, shaders.ShaderUniformComponent)
      end
      local uniforms = registry:get(entity, shaders.ShaderUniformComponent)
      
      -- Uniform names from assets/shaders/efficient_pixel_outline_fragment.fs:10-14
      -- outlineType: 0=none, 1=4-way, 2=8-way  (MUST be 1 or 2 or you will see no outline)
      -- CORRECT uniform names: outlineColor, thickness, outlineType
      uniforms:set("efficient_pixel_outline", "outlineColor", Color(255, 255, 0, 255))  -- yellow
      uniforms:set("efficient_pixel_outline", "thickness", 2.0)  -- NOT "outlineThickness"
      uniforms:set("efficient_pixel_outline", "outlineType", 2)  -- 0=none, 1=4-way, 2=8-way (use 2 for visible outline)
  end
  
  function Selection._removeOutline(entity)
      if not registry:valid(entity) then return end
      if not registry:has(entity, shader_pipeline.ShaderPipelineComponent) then return end
      
      local pipeline = registry:get(entity, shader_pipeline.ShaderPipelineComponent)
      pipeline:removePass("efficient_pixel_outline")
  end
  ```

  **Must NOT do**:
  - Multi-select
  - Keyboard selection

  **Parallelizable**: NO (foundational for 5.2)

  **References**:
  - `assets/scripts/core/hitfx.lua:43-60` - **Verified pattern: `pipeline:addPass("flash")`** (string name, not object)
  - `assets/scripts/chugget_code_definitions.lua:11715-11728` - `addPass(name)`, `removePass(name)` API
  - `assets/scripts/ui/hover_registry.lua:69-80` - Mouse position and hit testing pattern
  - `assets/scripts/core/gameplay.lua:536` - `input.isMousePressed()` usage
  - `assets/shaders/efficient_pixel_outline_fragment.fs` - Outline shader (check uniform names)

  **Acceptance Criteria**:
  - [ ] Click creature → becomes selected
  - [ ] `pipeline:addPass("efficient_pixel_outline")` called (string name)
  - [ ] Selected creature has visual indicator (outline visible)
  - [ ] Click ground → deselects, `pipeline:removePass()` called
  - [ ] Only one entity selected at a time

  **Commit**: YES
  - Message: `feat(idle): click-to-select entity system`
  - Files: `assets/scripts/idle_game/selection.lua`

---

- [ ] 5.2. ImGui GOAP debug panel

  **What to do**:
  - Create `assets/scripts/idle_game/ui/debug_panel.lua`
  - Show when entity selected:
    - Current goal
    - Current action
    - World state atoms (all true/false)
    - Action queue
    - Recent trace events (last 10)
  - Update in real-time
  - Panel on left side of screen
  
  **GOAP INSPECTION APIS** (use these, NOT direct AITraceBuffer access):
  
  ```lua
  local entity = Selection.selected_entity
  if entity then
      -- Get full GOAP state (goal, action, worldstate, etc.)
      -- Returns nil if entity has no GOAPComponent
      local goap_state = ai.get_goap_state(entity)
      
      -- Get trace events (type, message, timestamp per event)
      -- See: src/systems/ai/ai_system.cpp for binding
      local trace_events = ai.get_trace_events(entity, 10)  -- last 10 events
      
      -- Or use the debug helper which wraps both
      -- See: assets/scripts/ai/debug.lua
      local debug_info = ai.debug.inspect(entity, { trace_count = 10 })
  end
  ```
  
  **REFERENCE IMPLEMENTATION**: See `assets/scripts/ui/ai_inspector.lua` for a complete
  working GOAP inspector panel that shows all this information. Use it as a pattern.

  **Must NOT do**:
  - Build custom panel framework
  - Add editing capabilities

  **Parallelizable**: NO (depends on 5.1)

  **References**:
  - `assets/scripts/ui/ai_inspector.lua` - **WORKING GOAP inspector panel** (use as template!)
  - `src/systems/ai/ai_system.cpp` - `get_goap_state()`, `get_trace_events()` bindings
  - `assets/scripts/ai/debug.lua` - `ai.debug.inspect(e, opts)` wrapper

  **Acceptance Criteria**:
  - [ ] Panel appears when entity selected
  - [ ] Shows current goal name (from `ai.get_goap_state(e)`)
  - [ ] Shows current action name
  - [ ] Shows world state atoms as checkboxes (read-only)
  - [ ] Shows last 10 trace events (via `ai.get_trace_events(e, 10)`)
  - [ ] Updates every frame
  - [ ] Panel dismisses on deselect

  **Commit**: YES
  - Message: `feat(idle): ImGui GOAP debug panel for selected entity`
  - Files: `assets/scripts/idle_game/ui/debug_panel.lua`

---

### Phase 6: Upgrade System

- [ ] 6.1. TDD: Upgrade data module

  **What to do**:
  - Write tests in `assets/scripts/tests/test_idle_upgrades.lua`
  - Test: All upgrades defined with name, cost, effect
  - Test: `upgrades.can_afford(id)` checks resources
  - Test: `upgrades.purchase(id)` deducts cost, increments level
  - Test: Max 10 levels per upgrade
  - Define 10-15 upgrades:
    - Click Power (wood per click)
    - Stone Power (stone per click)
    - Passive Gold Rate
    - Creature Speed
    - Forage Amount
    - etc.
  - Implement `assets/scripts/idle_game/upgrades.lua`

  **Must NOT do**:
  - Tech tree dependencies
  - More than 15 upgrades
  - Prestige system

  **Parallelizable**: YES (with 6.2, 6.3)

  **References**:
  - `assets/scripts/core/procgen.lua` - Cost curve pattern

  **Acceptance Criteria**:
  - [ ] Test file with 10+ test cases
  - [ ] All Lua tests pass: `lua assets/scripts/tests/test_idle_upgrades.lua` → "All tests passed"
  - [ ] 10-15 upgrades defined
  - [ ] Cost formula: `base_cost * (1.5 ^ level)`
  - [ ] Max level enforced

  **Commit**: YES
  - Message: `feat(idle): TDD upgrade data system`
  - Files: `assets/scripts/idle_game/upgrades.lua`, `assets/scripts/tests/test_idle_upgrades.lua`
  - Pre-commit: `lua assets/scripts/tests/test_idle_upgrades.lua` (Lua tests) + `just build-debug` (build check)

---

- [ ] 6.2. Upgrade UI panel

  **What to do**:
  - Create `assets/scripts/idle_game/ui/upgrade_panel.lua`
  - Show all upgrades in scrollable ImGui panel
  - Each upgrade: name, current level, cost, buy button
  - Disable button if can't afford
  - Show effect description
  
  **ImGui Panel Pattern** (use as template):
  ```lua
  -- Reference: assets/scripts/ui/ai_inspector.lua for working ImGui panel in this codebase
  
  local UpgradePanel = {}
  
  function UpgradePanel.draw()
      if imgui.Begin("Upgrades", nil, imgui.WindowFlags_None) then
          -- Scrollable region
          if imgui.BeginChild("upgrade_list", 0, 0, true) then
              local upgrades = require("idle_game.upgrades")
              for _, upgrade in ipairs(upgrades.list()) do
                  imgui.Text(upgrade.name .. " (Lv." .. upgrade.level .. ")")
                  imgui.SameLine()
                  
                  -- Disable button if can't afford
                  local canAfford = upgrades.can_afford(upgrade.id)
                  if not canAfford then imgui.BeginDisabled() end
                  
                  if imgui.Button("Buy##" .. upgrade.id) then
                      upgrades.purchase(upgrade.id)
                  end
                  
                  if not canAfford then imgui.EndDisabled() end
                  imgui.Text("Cost: " .. upgrade.cost)
                  imgui.Separator()
              end
              imgui.EndChild()
          end
      end
      imgui.End()
  end
  
  return UpgradePanel
  ```

  **Must NOT do**:
  - Custom button styling
  - Animations

  **Parallelizable**: YES (with 6.1 after interface defined)

  **References**:
  - `assets/scripts/ui/ai_inspector.lua` - **WORKING ImGui panel pattern** in this codebase
  - ImGui scrollable child regions: `imgui.BeginChild()` / `imgui.EndChild()`
  - ImGui disabled state: `imgui.BeginDisabled()` / `imgui.EndDisabled()`

  **Acceptance Criteria**:
  - [ ] All upgrades visible in panel
  - [ ] Buy button works when affordable
  - [ ] Buy button disabled when not affordable
  - [ ] Level updates after purchase
  - [ ] Cost updates after purchase

  **Commit**: YES
  - Message: `feat(idle): upgrade purchase UI panel`
  - Files: `assets/scripts/idle_game/ui/upgrade_panel.lua`

---

- [ ] 6.3. Apply upgrade effects

  **What to do**:
  - Wire upgrade levels to game systems:
    - Click Power → multiply click yield
    - Creature Speed → multiply movement speed
    - Passive Gold → multiply gold per second
    - etc.
  - Update effects immediately on purchase
  
  **INTEGRATION POINTS** (data flow for each effect):
  
  1. **Click Power** (source → transform → sink):
     - Source: `upgrades.get_level("click_power")` returns current level
     - Transform: `base_yield * (1 + level * 0.2)` (20% bonus per level)
     - Sink: Call in `assets/scripts/idle_game/input.lua` click handler when harvesting tree/rock
     ```lua
     local function getClickYield(baseYield)
         local upgrades = require("idle_game.upgrades")
         local level = upgrades.get_level("click_power") or 0
         return baseYield * (1 + level * 0.2)
     end
     ```
  
  2. **Creature Speed** (modify GOAP action movement):
     - Source: `upgrades.get_level("creature_speed")`
     - Transform: In wander/forage actions, multiply move speed: `base_speed * (1 + level * 0.1)`
     - Sink: `assets/scripts/ai/actions/idle_wander.lua` in `update()` function
     ```lua
     -- In idle_wander.lua update():
     local upgrades = require("idle_game.upgrades")
     local speedMult = 1 + (upgrades.get_level("creature_speed") or 0) * 0.1
     local moveSpeed = BASE_SPEED * speedMult
     ```
  
  3. **Passive Gold Rate**:
     - Source: `upgrades.get_level("passive_gold")`
     - Transform: `base_rate * (1 + level * 0.25)` (25% bonus per level)
     - Sink: `assets/scripts/idle_game/scenes/sim_scene.lua` in `update(dt)`
     ```lua
     -- In sim_scene.update():
     local function tickPassiveGold(dt)
         local upgrades = require("idle_game.upgrades")
         local baseRate = 0.1  -- 0.1 gold per second
         local level = upgrades.get_level("passive_gold") or 0
         local rate = baseRate * (1 + level * 0.25)
         resources.add("gold", rate * dt)
     end
     ```

  **Must NOT do**:
  - Add upgrade visual effects
  - Add achievement popups

  **Parallelizable**: NO (depends on 6.1)

  **References**:
  - `assets/scripts/idle_game/upgrades.lua` - `get_level(id)` function (implement in 6.1)
  - `assets/scripts/idle_game/resources.lua` - `add(type, amount)` function (Task 4.1)
  - `assets/scripts/ai/actions/idle_wander.lua` - Creature movement (Task 3.2)
  - `assets/scripts/idle_game/scenes/sim_scene.lua` - Game loop (Task 1.2)

  **Acceptance Criteria**:
  - [ ] Click Power upgrade → more wood per click (verify: click tree, compare yield before/after upgrade)
  - [ ] Creature Speed → creatures move faster (verify: observe wander speed before/after)
  - [ ] Passive Gold → gold rate increases (verify: watch gold counter rate before/after)
  - [ ] Effects apply immediately after purchase (no restart required)

  **Commit**: YES
  - Message: `feat(idle): apply upgrade effects to game systems`
  - Files: `assets/scripts/idle_game/upgrade_effects.lua`

---

### Phase 7: Visual Polish

- [ ] 7.1. Apply earthy color palette

  **What to do**:
  - Create palette texture: 8-16 earthy colors
    - Greens (grass, trees)
    - Browns (wood, dirt)
    - Grays (rock, stone)
    - Gold/yellow (currency)
  - Apply `palette_quantize.fs` as **layer post-process shader**
  
  **POST-PROCESS SHADER ATTACHMENT (Layer System)**:
  The layer system supports post-process shaders via Lua bindings:
  ```lua
  -- In sim_scene.lua init or after scene setup:
  
  -- Get the sprites layer (or whichever layer renders your game)
  local spriteLayer = layers.sprites
  
  -- Add post-process shader to the layer
  -- Method: layer:addPostProcessShader(shader_name)
  -- Binding at: src/systems/layer/layer_lua_bindings.cpp:236
  spriteLayer:addPostProcessShader("palette_quantize")
  ```
  
  **Shader registration**: Ensure "palette_quantize" is in `assets/shaders/shaders.json`
  (Already exists - verified: `assets/shaders/palette_quantize_fragment.fs` and `assets/shaders/palette_quantize_vertex.vs`)
  
  **PALETTE TEXTURE BINDING (CRITICAL)**:
  
  The `palette_quantize` shader requires a palette texture bound to TEXTURE1.
  Use the existing `setPaletteTexture()` global function:
  
  ```lua
  -- In sim_scene.lua init, AFTER adding the shader:
  
  -- Bind palette texture using the existing pattern
  -- See: assets/scripts/core/shader_uniforms.lua:123-126
  -- setPaletteTexture(shaderName, texturePath) - global function
  setPaletteTexture("palette_quantize", "graphics/palettes/earthy.png")
  ```
  
  **Palette texture format**: 
  - 1D horizontal strip PNG (e.g., 8x1 or 16x1 pixels)
  - Each pixel represents one palette color
  - Example reference: `assets/graphics/palettes/resurrect-64-1x.png`

  **Must NOT do**:
  - Create new shaders
  - Add palette cycling/animation

  **Parallelizable**: YES (with 7.2)

  **References**:
  - `src/systems/layer/layer_lua_bindings.cpp:235-236` - `addPostProcessShader` Lua binding
  - `src/systems/layer/layer.hpp:252-268` - Layer post-process shader methods
  - `assets/shaders/palette_quantize_fragment.fs` - Shader code
  - `assets/shaders/shaders.json` - Shader registry (palette_quantize exists)
  - `assets/scripts/core/shader_uniforms.lua` - How to set shader uniforms
  - `assets/graphics/palettes/` - Existing palette textures (reference for format)

  **Acceptance Criteria**:
  - [ ] Palette texture created (8-16 colors) at `assets/graphics/palettes/earthy.png`
  - [ ] `spriteLayer:addPostProcessShader("palette_quantize")` called in sim_scene init
  - [ ] All game colors quantized to palette
  - [ ] Visual consistency across terrain and creatures

  **Commit**: YES
  - Message: `feat(idle): apply earthy color palette shader`
  - Files: `assets/graphics/palettes/earthy.png`, `assets/scripts/idle_game/scenes/sim_scene.lua`

---

- [ ] 7.2. Apply pixelation effect

  **What to do**:
  - Apply `pixelate_image.fs` as post-process via layer system
  - Configure `pixelRatio` uniform (suggest 0.5 for 2x pixels)
  - Ensure pixelation applies after palette quantization
  - Verify effect looks good at various window sizes
  
  **Implementation**:
  ```lua
  -- In sim_scene.lua, AFTER adding palette_quantize:
  
  -- Add pixelation as second post-process (order matters!)
  local spriteLayer = layers.sprites
  spriteLayer:addPostProcessShader("pixelate_image")
  
  -- Post-process shaders execute in order added:
  -- 1. palette_quantize (added in 7.1)
  -- 2. pixelate_image (added here)
  
  -- Set pixelation uniforms via globalShaderUniforms (C++ binding, global variable)
  -- See working usage: assets/scripts/core/lighting.lua:875-954
  globalShaderUniforms:set("pixelate_image", "pixelRatio", 0.5)  -- 2x pixel size
  
  -- texSize uniform (texture dimensions) - set once at init
  local VW, VH = globals.screenWidth(), globals.screenHeight()
  globalShaderUniforms:set("pixelate_image", "texSize", Vector2{ x = VW, y = VH })
  ```
  
  **Window Resize Handling**:
  If window is resizable, `texSize` uniform must be updated when size changes.
  Add to sim_scene.update():
  ```lua
  -- Check if window size changed and update shader uniform
  local newW, newH = globals.screenWidth(), globals.screenHeight()
  if newW ~= lastW or newH ~= lastH then
      globalShaderUniforms:set("pixelate_image", "texSize", Vector2{ x = newW, y = newH })
      lastW, lastH = newW, newH
  end
  ```

  **Must NOT do**:
  - Create new shader
  - Add multiple pixelation levels

  **Parallelizable**: YES (with 7.1)

  **References**:
  - `src/systems/layer/layer_lua_bindings.cpp:235-236` - `addPostProcessShader` binding
  - `assets/shaders/pixelate_image_fragment.fs` - Shader code
  - `assets/shaders/shaders.json` - Shader registry (pixelate_image exists)
  - `assets/scripts/core/shader_uniforms.lua` - Uniform configuration patterns

  **Acceptance Criteria**:
  - [ ] Pixelation visible (chunky pixels)
  - [ ] Consistent across window sizes
  - [ ] Ordered correctly: render → palette → pixelate (verify via visual inspection)
  - [ ] Readable ASCII characters (not too pixelated)

  **Commit**: YES
  - Message: `feat(idle): apply pixelation post-process shader`
  - Files: `assets/scripts/idle_game/scenes/sim_scene.lua`

---

- [ ] 7.3. Final integration and polish

  **What to do**:
  - Set default window size: 600x400
  - Ensure all systems work together
  - Performance profiling (target 60fps)
  - Final visual review
  
  **NOTE**: Window position memory (save/restore) is OUT OF SCOPE for MVP.
  Persistence system would require SaveManager integration which is not part of this vertical slice.

  **Must NOT do**:
  - Add new features
  - Major refactoring

  **Parallelizable**: NO (final integration)

  **References**:
  - All previous tasks

  **Acceptance Criteria**:
  - [ ] Game launches at 600x400 borderless
  - [ ] All features working together
  - [ ] Stable 60fps with 20 creatures
  - [ ] Visual style cohesive (palette + pixelation)
  - [ ] GOAP debug panel functional
  - [ ] Upgrades affect gameplay

  **Commit**: YES
  - Message: `feat(idle): final polish and integration`
  - Files: Various

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 0.1 | `feat(window): borderless widget mode` | init.cpp | Manual: window test |
| 0.2 | `spike(ai): validate GOAP performance` | temp files | Tracy: <1ms plan |
| 0.3 | `spike(procgen): validate forma terrain` | temp files | Test: determinism |
| 1.1 | `feat(idle): script folder structure` | idle_game/* | require works |
| 1.2 | `feat(idle): minimal sim scene` | scene, globals | builds, launches |
| 1.3 | `chore(cleanup): remove unused code` | multiple | just build-debug |
| 2.1 | `feat(idle): TDD terrain generator` | terrain.lua, tests | lua assets/scripts/tests/test_idle_terrain.lua |
| 2.2 | `feat(idle): render terrain` | terrain_renderer.lua | visual check |
| 3.1 | `feat(idle): forager entity type` | creatures/forager.lua | GOAP registered |
| 3.2 | `feat(idle): GOAP actions` | actions/*.lua | plans execute |
| 3.3 | `feat(idle): spawn creatures` | spawner.lua | 5 creatures visible |
| 4.1 | `feat(idle): TDD resources` | resources.lua, tests | lua assets/scripts/tests/test_idle_resources.lua |
| 4.2 | `feat(idle): resource UI` | ui/resource_panel.lua | UI visible |
| 4.3 | `feat(idle): click-to-collect` | input.lua | clicks work |
| 5.1 | `feat(idle): entity selection` | selection.lua | select works |
| 5.2 | `feat(idle): GOAP debug panel` | ui/debug_panel.lua | panel shows state |
| 6.1 | `feat(idle): TDD upgrades` | upgrades.lua, tests | lua assets/scripts/tests/test_idle_upgrades.lua |
| 6.2 | `feat(idle): upgrade UI` | ui/upgrade_panel.lua | purchases work |
| 6.3 | `feat(idle): upgrade effects` | upgrade_effects.lua | effects applied |
| 7.1 | `feat(idle): color palette` | palette, config | palette applied |
| 7.2 | `feat(idle): pixelation` | config | pixels visible |
| 7.3 | `feat(idle): final polish` | various | 60fps, cohesive |

---

## Success Criteria

### Verification Commands
```bash
# Build verification
just build-debug          # Expected: SUCCESS, no errors

# C++ tests (engine code)
just test                 # Expected: All C++ tests pass

# Lua tests (game logic) - run each idle game test
lua assets/scripts/tests/test_idle_terrain.lua    # Expected: All tests passed
lua assets/scripts/tests/test_idle_resources.lua  # Expected: All tests passed
lua assets/scripts/tests/test_idle_upgrades.lua   # Expected: All tests passed

# Manual verification
./build/raylib-cpp-cmake-template  # Expected: Game launches into sim scene
```

### Final Checklist
- [ ] Borderless widget window working
- [ ] Forest terrain generated from seed
- [ ] 5+ creatures wandering/foraging
- [ ] 4 resources accumulating
- [ ] Click-to-collect working
- [ ] 10+ upgrades purchasable
- [ ] GOAP debug panel functional
- [ ] Earthy palette applied
- [ ] Pixelation effect applied
- [ ] Stable 60fps with 20 creatures
- [ ] All "Must NOT Have" items absent
