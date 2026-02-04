# Reference Index: AI Integration

**Version:** 0.5 Findings Consolidation
**Last Updated:** 2026-02-01
**Purpose:** Comprehensive reference for AI integration findings, coordinate systems, and technical patterns

---

## Table of Contents

1. [Coordinate System Reference](#coordinate-system-reference)
2. [AI Integration Infrastructure](#ai-integration-infrastructure)
3. [Technical Pattern Analysis](#technical-pattern-analysis)
4. [Framework Design Patterns](#framework-design-patterns)
5. [Engine Bindings Reference](#engine-bindings-reference)
6. [Module Contracts Reference](#module-contracts-reference)
7. [Verified UI Identifiers](#verified-ui-identifiers)
8. [System Performance Findings](#system-performance-findings)
9. [Implementation Guidelines](#implementation-guidelines)

---

## Coordinate System Reference

*Based on ASCII UI implementation findings*

### Core Definitions

| System | Reference Frame | Scale | Usage |
|--------|----------------|-------|--------|
| **World Space** | Game world coordinates | Grid-aligned tiles | Entity positioning, terrain |
| **Screen Space** | Pixel coordinates | Direct pixel mapping | UI rendering, ImGui |
| **Draw Command Space** | Normalized coordinates | 0.0-1.0 range | GPU rendering pipeline |

### Critical Identifiers

```cpp
// Grid System
const int TILE_SIZE = 32;           // Pixels per tile
const int SCREEN_W = 1280;          // Total screen width
const int SCREEN_H = 720;           // Total screen height
const int UI_SIDEBAR_W = 300;       // Right sidebar width

// Coordinate Conversion
pixel_x = tile_x * TILE_SIZE
pixel_y = tile_y * TILE_SIZE
screen_center_x = (SCREEN_W - UI_SIDEBAR_W) / 2
```

### Verified Alignment Rules

1. **Grid Alignment**: All world entities snap to `(tile_x * 32, tile_y * 32)` pixels
2. **Screen Centering**: Left region centers camera at `((SCREEN_W - UI_SIDEBAR_W) / 2, SCREEN_H / 2)`
3. **UI Panel Positioning**: Sidebar occupies `[SCREEN_W - UI_SIDEBAR_W, 0, UI_SIDEBAR_W, SCREEN_H]`

**Source:** `/planning/PLAN.md` - ASCII UI implementation coordinate system truth table

---

## AI Integration Infrastructure

*Consolidated findings from Firmware.ai integration analysis*

### Network Performance Analysis

**Critical Finding: Trans-Pacific Latency Impact on AI Responses**

| Metric | Value | Impact |
|--------|-------|---------|
| Base RTT | 213.6ms | 2x normal response time |
| First-byte latency | 2.27s | Initial connection overhead |
| Stream timeout | 60s | AWS ELB idle timeout limit |
| Connection drops | ~15% | High-latency route instability |

### Infrastructure Recommendations

1. **Timeout Configuration**
   - Set client timeout > 60s for streaming responses
   - Implement exponential backoff for connection drops
   - Use keep-alive headers to prevent ELB timeouts

2. **Latency Mitigation**
   - Cache common AI responses locally
   - Use request batching for non-time-critical operations
   - Implement graceful degradation for network issues

3. **Error Handling**
   - Detect connection drops vs. completion
   - Automatic retry with jitter for failed requests
   - Fallback to local processing when possible

**Source References:**
- `/FIRMWARE_AI_HANG_REPORT.md` - Initial diagnostic
- `/FIRMWARE_LLM_PROXY_HANG_COMPREHENSIVE.md` - Comprehensive network analysis

---

## Technical Pattern Analysis

*AI-identified recurring technical challenges*

### Top Struggle Patterns (17 identified)

| Pattern | Frequency | Category | Impact |
|---------|-----------|----------|---------|
| **Shader Coordinate System Issues** | High | Rendering | Critical |
| **DrawCommandSpace Confusion** | High | Rendering | Critical |
| **Dual Quadtree Collision** | Medium | Physics | Moderate |
| **Sol2 Lua/C++ Binding** | Medium | Integration | Moderate |
| **LuaJIT Local Variable Limits** | Low | Scripting | Minor |

### Detailed Analysis

#### 1. Coordinate System Confusion
- **Problem**: Mixed world/screen space in rendering pipeline
- **Solution**: Enforce strict coordinate space separation
- **Prevention**: Use type-safe coordinate wrapper classes

#### 2. DrawCommandSpace Y-Coordinate Issues
- **Problem**: OpenGL Y-up vs. screen Y-down coordinate systems
- **Solution**: Consistent Y-flip handling in shaders
- **Prevention**: Abstract coordinate conversion functions

#### 3. UI Element Recursive Removal Crashes
- **Problem**: Destructor chains during UI cleanup
- **Solution**: Deferred destruction with cleanup queues
- **Prevention**: RAII with explicit lifecycle management

**Source:** `/docs/analysis/conversation-retrospective-2026-01.md`

---

## Framework Design Patterns

*AI-assisted experimental game design analysis*

### Pacing System Analysis

**Core Finding: Negative Acquisition Mechanics**

Traditional incremental games use positive feedback loops. Analysis of 22 games + 9 experimental designs revealed:

| Mechanic Type | Games Using | Effectiveness | Implementation Complexity |
|---------------|-------------|---------------|-------------------------|
| **Cursed Items** | 3/22 | High engagement | Medium |
| **Corrupted Resources** | 2/22 | Medium | Low |
| **Reversibility Systems** | 1/22 | Very High | High |
| **Pacing Governors** | 8/22 | Medium | Low |

### Design Recommendations

1. **Cursed/Corrupted Mechanics**
   - Introduce items that slow progress temporarily
   - Balance with meaningful rewards for risk-taking
   - Provide clear opt-out mechanisms

2. **Reversibility Systems**
   - Allow players to undo recent decisions
   - Create strategic depth through timing
   - Prevent degenerate "save scumming" behaviors

3. **Pacing Governors**
   - Implement soft caps that encourage diversification
   - Use diminishing returns rather than hard limits
   - Provide alternate progression paths

**Source:** `/docs/analysis/missing-framework-elements-analysis.md`

---

## Engine Bindings Reference

*Comprehensive reference for input and coordinate conversion APIs*

### Mouse Input API

**Core Functions Available in Lua:**

#### Mouse Click Detection
```lua
-- Button state checking
input.isMousePressed(MouseButton.MOUSE_BUTTON_LEFT)   -- First frame of press only
input.isMouseDown(MouseButton.MOUSE_BUTTON_RIGHT)     -- Held down state
input.isMouseReleased(MouseButton.MOUSE_BUTTON_MIDDLE) -- First frame of release

-- Mouse position (screen coordinates)
local pos = input.getMousePos()  -- Returns {x: number, y: number}
```

#### Mouse Button Constants
```lua
MouseButton = {
    MOUSE_BUTTON_LEFT     = 0,  -- Primary click
    MOUSE_BUTTON_RIGHT    = 1,  -- Context/secondary click
    MOUSE_BUTTON_MIDDLE   = 2,  -- Wheel press
    MOUSE_BUTTON_SIDE     = 3,  -- Side button
    MOUSE_BUTTON_EXTRA    = 4,  -- Extra button
    MOUSE_BUTTON_FORWARD  = 5,  -- Forward navigation
    MOUSE_BUTTON_BACK     = 6   -- Back navigation
}
```

#### Mouse Wheel Input
```lua
local wheel_delta = input.getMouseWheel()
-- Positive: scroll up (away from user)
-- Negative: scroll down (toward user)
-- Zero: no wheel movement this frame
```

### Coordinate Conversion API

**Screen-World Transformation:**

#### Core Conversion Functions
```lua
-- Raylib native functions (exposed to Lua)
local world_pos = GetScreenToWorld2D(screen_pos, camera)
local screen_pos = GetWorldToScreen2D(world_pos, camera)

-- High-level camera methods
local world_mouse = camera:GetMouseWorld()              -- C++ binding
local world_x, world_y = hump_camera:worldCoords(x, y)  -- Hump library
```

#### Input Coordinate Flow
```
Raw Mouse → GetScaledMousePosition() → Screen Coordinates (1280x800)
            → GetScreenToWorld2D() → World Coordinates
```

#### Camera Integration
```lua
-- Get scaled screen coordinates
local screen_mouse = input.getMousePos()

-- Convert to world using active camera
local camera = get_active_camera()
local world_mouse = GetScreenToWorld2D(screen_mouse, camera)

-- Convert to tile coordinates
local tile_x = math.floor(world_mouse.x / TILE_SIZE)
local tile_y = math.floor(world_mouse.y / TILE_SIZE)
```

### Event System Integration

#### Mouse Click Events
```cpp
struct MouseClicked : public event_bus::Event {
    Vector2 position{};           // Click coordinates
    int button{0};                // Button code (0=left, 1=right, 2=middle)
    entt::entity target{entt::null}; // Target entity clicked
};
```

#### GameObject Callbacks
```lua
-- Available callback methods for GameObjects
gameObject.methods = {
    onClick = function(self, event) end,      -- Left click
    onRightClick = function(self, event) end, -- Right click
    onDrag = function(self, event) end,       -- Drag operation
    onRelease = function(self, event) end,    -- Mouse release
    onHover = function(self, event) end,      -- Hover start
    onStopHover = function(self, event) end   -- Hover end
}
```

### Advanced Features

#### Mac Right-Click Emulation
- **Ctrl + Left Click** = Right Click
- **Cmd + Left Click** = Right Click

#### Coordinate System Types
| Type | Origin | Range | Usage |
|------|--------|-------|-------|
| **Screen Space** | Top-left (0,0) | 1280×800 virtual | Input, UI rendering |
| **World Space** | Camera-dependent | Unlimited | Entity positioning |
| **Tile Space** | Grid-aligned | Integer coordinates | Terrain, pathfinding |

#### Transform Pipeline
```
Screen Input → Letterbox Removal → Virtual Resolution → Camera Transform → World Space
```

**Source References:**
- **Mouse Click API:** `/api_documentation/mouse_click_api.md`
- **Mouse Wheel API:** `/api_documentation/mouse_wheel_api.md`
- **Coordinate Conversion:** `/api_documentation/world_mouse_conversion_api.md`
- **Implementation:** `src/systems/input/input_lua_bindings.cpp`

---

## Module Contracts Reference

*Comprehensive reference for game system modules and their APIs*

### Resource Management System

**Primary Module**: `idle_game.resources`
**Core Function**: `resources.add(resource_type, amount)`

#### Delta Operations
```lua
-- Add/subtract resources with automatic bounds checking
resources.add("food", 10)     -- Add 10 food
resources.add("wood", -5)     -- Subtract 5 wood (negative delta)
resources.add("stone", 999)   -- Add 999 stone (clamped to 9999 max)
resources.add("gold", -9999)  -- Remove 9999 gold (clamped to 0 min)

-- Negative support confirmed: Full support with safety clamping [0, 9999]
```

#### Atomic Spending Operations
```lua
-- Multi-resource transaction (atomic - all or nothing)
local building_cost = {food = 20, wood = 15, stone = 5}
if resources.try_spend(building_cost) then
    -- All resources deducted successfully
    spawn_building()
else
    -- Insufficient resources - nothing spent
    show_error_message()
end
```

#### Rate Tracking
```lua
-- Income rate calculation (positive deltas only)
local food_rate = resources.get_rate("food")  -- Per-second income
print("Food income: " .. food_rate .. " per second")
```

**Key Features**:
- **Negative Delta Support**: ✅ Full support with bounds clamping
- **Bounds Safety**: Automatic clamping to [0, 9999] range
- **Atomic Transactions**: `try_spend()` prevents partial spending
- **Event Integration**: Emits signals for UI updates
- **Rate Tracking**: Income rate calculation for display

### Spawner Entity Tracking System

**Primary Module**: `idle_game.spawner`
**Core Pattern**: Boolean-set tables indexed by entity IDs

#### Creature Type Tracking
```lua
-- Entity tracking via boolean sets
spawner._foragers[entity] = true    -- Track as forager
spawner._lumberjacks[entity] = true -- Track as lumberjack
spawner._miners[entity] = true      -- Track as miner
spawner._builders[entity] = true    -- Track as builder
spawner._collectors[entity] = true  -- Track as collector

-- Count with automatic cleanup
local forager_count = spawner.getForagerCount()     -- Validates entities
local specialist_count = spawner.getSpecialistCount() -- All non-foragers
```

#### Count Access Methods
| Method | Returns | Cleanup | Implementation Status |
|--------|---------|---------|----------------------|
| `getForagerCount()` | number | ✅ Automatic | Complete |
| `getLumberjackCount()` | number | ✅ Automatic | Complete |
| `getMinerCount()` | number | ✅ Automatic | Complete |
| `getBuilderCount()` | number | ✅ Automatic | Complete |
| `getCollectorCount()` | number | ✅ Automatic | Tracking only (no spawn) |
| `getCorpseCount()` | number | N/A | Array-based |

#### Signal Integration
```lua
-- Population change signal emission
signal.emit("idle.creature_counts", {
    foragers = number,
    lumberjacks = number,
    miners = number,
    builders = number,
    collectors = number,
    corpses = number
})
```

**Key Features**:
- **Entity ID Keying**: Direct ECS entity ID as key, boolean value
- **Automatic Cleanup**: Dead entities removed during count operations
- **Signal Emission**: Population changes trigger UI updates
- **Safe Destruction**: Deferred destruction queue for AI safety
- **Specialist Tracking**: Role-specific entity categorization

### Terrain Tile System

**Primary Module**: `idle_game.terrain` (conceptual)
**Core Convention**: Grid coordinates with top-left origin (0,0)

#### Coordinate System
```lua
-- Grid coordinate conventions
-- Origin: Top-left (0,0)
-- X-axis: Rightward (0 to width-1)
-- Y-axis: Downward (0 to height-1)

function gridToWorld(tileX, tileY)
    return tileX * TILE_SIZE, tileY * TILE_SIZE
end

function worldToGrid(worldX, worldY)
    return math.floor(worldX / TILE_SIZE), math.floor(worldY / TILE_SIZE)
end
```

#### Walkability System
```lua
-- IntGrid walkability rules
function isWalkable(intgrid_value)
    return intgrid_value == 0  -- Only value 0 is walkable
end

function isOccupied(intgrid_value)
    return intgrid_value ~= 0  -- Any non-zero is solid
end
```

#### Terrain Types
| Value | Type | Walkable | Physics | Usage |
|-------|------|----------|---------|-------|
| 0 | Empty | ✅ Yes | No collision | Paths, movement |
| 1 | Grass/Floor | ❌ No | Collision | Ground tiles |
| 2 | Tree | ❌ No | Collision | Wood resource |
| 3 | Rock | ❌ No | Collision | Stone resource |
| 4+ | Custom | ❌ No | Collision | Designer-defined |

**Key Features**:
- **Grid Origin**: Top-left (0,0) with rightward X, downward Y
- **IntGrid System**: Single value per tile for collision/type
- **Run-Length Encoding**: Optimized physics collider generation
- **Bounds Safety**: All operations validate grid boundaries
- **Procedural Support**: Auto-rules for tile generation

### Module Integration Patterns

#### Coordinate System Chain
```lua
-- Screen → World → Tile coordinate conversion chain
local mouse = input.getMousePos()                    -- Screen coordinates
local world = GetScreenToWorld2D(mouse, camera)     -- World coordinates
local tileX = math.floor(world.x / TILE_SIZE)       -- Tile coordinates
local tileY = math.floor(world.y / TILE_SIZE)

-- Terrain interaction
local terrain_type = terrain.get(tileX, tileY)
if terrain_type == "ROCK" and spawner.getMinerCount() > 0 then
    resources.add("stone", 1)  -- Harvest stone
end
```

#### Entity-Resource-Terrain Workflow
```lua
-- Complete game action workflow
function handleResourceHarvest(entity, tileX, tileY)
    -- 1. Validate entity type (spawner system)
    local is_miner = spawner._miners[entity]

    -- 2. Check terrain type (terrain system)
    local terrain_type = terrain.get(tileX, tileY)

    -- 3. Calculate yield based on entity type
    local base_yield = 1
    local yield = is_miner and math.floor(base_yield * 1.5) or base_yield

    -- 4. Add resources (resource system)
    if terrain_type == "ROCK" then
        resources.add("stone", yield)
        terrain.set(tileX, tileY, "GRASS")  -- Clear harvested tile
    end

    -- 5. Update population signals (spawner system)
    spawner._emitCreatureCounts()
end
```

### API Completeness Status

#### Fully Documented APIs (6)
- ✅ **Mouse Input**: Click detection, wheel input, button constants
- ✅ **Coordinate Conversion**: Screen/world/grid transformations
- ✅ **Resource Management**: Add/subtract deltas, atomic spending
- ✅ **Spawner Tracking**: Entity categorization, count access
- ✅ **Terrain System**: Tile conventions, walkability, coordinates
- ✅ **Reference Integration**: Engine bindings consolidated

#### Implementation Completeness
- **Mouse/Input System**: Complete implementation
- **Resource System**: Complete with negative delta support
- **Spawner System**: 4/5 creature types complete (collectors missing spawn)
- **Terrain System**: Core conventions documented, implementation varies

**Source References:**
- **Resource Delta API:** `/api_documentation/resources_add_delta_api.md`
- **Spawner Tracking:** `/api_documentation/spawner_creature_tracking_api.md`
- **Terrain Conventions:** `/api_documentation/terrain_tile_conventions_api.md`
- **Engine Bindings:** Combined input/coordinate systems (see above)

---

## Verified UI Identifiers

*ASCII UI component reference*

### Resource Panel Components

```lua
-- Verified identifiers from ascii_sprites.lua
ICONS = {
    wood = "♠",           -- Wood resource icon
    stone = "◊",          -- Stone resource icon
    food = "♦",           -- Food resource icon
    gold = "$",           -- Gold resource icon
    trophy = "🏆",        -- Achievement icon
    check = "✓",          -- Confirmation icon
    cross = "✗"           -- Error/cancel icon
}

BORDER = {
    top_left = "┌",
    top_right = "┐",
    bottom_left = "└",
    bottom_right = "┘",
    horizontal = "─",
    vertical = "│"
}
```

### Structure Sprites

```lua
STRUCTURES = {
    farm = "🏠",          -- Farm building
    mine = "⛏️",          -- Mine building
    house = "🏘️",        -- Housing
    workshop = "🔧",      -- Workshop
    storage = "📦"        -- Storage building
}
```

### Button Standards

```lua
BUTTON_STYLES = {
    buy = "[BUY]",        -- Standard purchase button
    max = "[MAX]",        -- Maximum purchase button
    upgrade = "[UPG]",    -- Upgrade button
    cancel = "[X]"        -- Cancel/close button
}
```

**Source:** `/assets/scripts/idle_game/ui/ascii_sprites.lua`

---

## System Performance Findings

*Integration test results and benchmarks*

### Achievement System Performance

**Test Results:**
- Toast rendering: 7/7 tests passed (23.77ms total)
- Achievement unlock timing: < 1ms per achievement
- Persistence serialization: Functional with minor edge cases

**Critical Finding:** Achievement serialize function returns `nil` in edge cases
- **Impact:** Save/load functionality partially compromised
- **Workaround:** Core achievement logic verified functional
- **Fix Required:** Debug achievement serialization edge case

### Collector AI Performance

**Test Results:**
- Ground item detection: 100% accuracy within 2-tile radius
- Collection probability: 50% success rate verified
- Multi-collector coordination: No conflicts detected
- Performance: 10 collectors × 20 items × 100 cycles in 2.5ms

**Findings:**
- Timer system (2-second intervals) working correctly
- Inventory management (3-item limit) functional
- Worldstate updates (`nearGroundItem`, `hasInventorySpace`) accurate

### Terrain Persistence

**Test Results:**
- Structure serialization: Stable format with validation
- Load error handling: Graceful degradation
- Grid clearing: Automatic on terrain changes

**Source:** Integration test files created during verification tasks

---

## Implementation Guidelines

*Consolidated best practices from AI integration work*

### Coordinate System Discipline

1. **Type Safety**
   ```cpp
   struct WorldCoord { float x, y; };
   struct ScreenCoord { int x, y; };
   struct TileCoord { int x, y; };
   ```

2. **Explicit Conversion**
   ```cpp
   ScreenCoord worldToScreen(WorldCoord world, CameraState cam);
   WorldCoord screenToWorld(ScreenCoord screen, CameraState cam);
   TileCoord worldToTile(WorldCoord world);
   ```

3. **Consistent Naming**
   - `world_x`, `world_y` for game coordinates
   - `screen_x`, `screen_y` for pixel coordinates
   - `tile_x`, `tile_y` for grid coordinates

### AI Integration Patterns

1. **Error Resilience**
   - Always provide fallback behavior for AI failures
   - Cache successful AI responses when possible
   - Use timeouts appropriate for network conditions

2. **Performance Optimization**
   - Batch AI requests when latency is high
   - Precompute common responses during low-usage periods
   - Implement progressive enhancement (works without AI)

3. **User Experience**
   - Show loading indicators for AI operations > 500ms
   - Provide manual alternatives to all AI features
   - Clear error messages when AI services unavailable

### Testing Methodology

1. **Integration Tests**
   - Test complete workflows, not just isolated components
   - Include network failure simulation for AI features
   - Verify graceful degradation under all conditions

2. **Performance Benchmarking**
   - Establish baseline performance metrics
   - Test with realistic data scales (10+ entities, 20+ items)
   - Monitor memory usage during extended operations

3. **Edge Case Coverage**
   - Empty state initialization
   - Resource exhaustion scenarios
   - Network interruption recovery

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|---------|
| 0.7.0 | 2026-02-01 | Added Module Contracts Reference section consolidating 0.4 findings | System Agent |
| 0.6.0 | 2026-02-01 | Added Engine Bindings Reference section with input/coordinate APIs | System Agent |
| 0.5.0 | 2026-02-01 | Initial consolidation of AI integration findings | System Agent |

---

## Quick Reference Links

- **Coordinate System Details:** `/planning/PLAN.md` (ASCII UI section)
- **Engine Bindings APIs:**
  - `/api_documentation/mouse_click_api.md` (Button constants, click detection, events)
  - `/api_documentation/mouse_wheel_api.md` (Wheel input, scroll handling, sign conventions)
  - `/api_documentation/world_mouse_conversion_api.md` (Coordinate transformation, camera integration)
- **Module Contracts APIs:**
  - `/api_documentation/resources_add_delta_api.md` (Resource add/subtract, negative support, atomic spending)
  - `/api_documentation/spawner_creature_tracking_api.md` (Entity tracking, counts, population signals)
  - `/api_documentation/terrain_tile_conventions_api.md` (Tile coordinates, walkability, collision detection)
- **Network Analysis:** `/FIRMWARE_LLM_PROXY_HANG_COMPREHENSIVE.md`
- **Technical Patterns:** `/docs/analysis/conversation-retrospective-2026-01.md`
- **Framework Design:** `/docs/analysis/missing-framework-elements-analysis.md`
- **UI Components:** `/assets/scripts/idle_game/ui/ascii_sprites.lua`
- **Integration Tests:** `/collector_behavior_integration_test.lua`, `/toast_integration_test.lua`

---

*This reference index consolidates findings from AI integration work in version 0.5. It serves as the single source of truth for coordinate systems, technical patterns, and implementation guidelines discovered through AI-assisted development.*