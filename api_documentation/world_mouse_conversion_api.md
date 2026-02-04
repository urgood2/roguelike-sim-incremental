# World-Mouse Conversion API Documentation

## Overview
The coordinate conversion system provides functions to transform between screen mouse coordinates and world coordinates, accounting for camera transformations including zoom, rotation, and translation. This document specifies the exact API names, function signatures, and usage patterns for coordinate conversion.

## Core Conversion Functions

### 1. `GetScreenToWorld2D(position, camera)`
**Location**: Raylib function exposed to Lua in `src/systems/scripting/scripting_functions.cpp:603-642`
**C++ Implementation**: Native Raylib function

**Purpose**: Convert screen coordinates to world coordinates using camera transformation

**Parameters**:
- `position` (Vector2): Screen position with `x` and `y` fields
- `camera` (Camera2D): Camera object with zoom, rotation, and target properties

**Returns**:
- `Vector2`: World coordinates with `x` and `y` fields

**Example Usage**:
```lua
-- Convert screen mouse position to world coordinates
local mouse_screen = input.getMousePos()  -- Screen coordinates (1280x800 virtual space)
local camera = get_current_camera()       -- Get active camera
local world_pos = GetScreenToWorld2D(mouse_screen, camera)

print("Screen: " .. mouse_screen.x .. ", " .. mouse_screen.y)
print("World: " .. world_pos.x .. ", " .. world_pos.y)

-- Convert to tile coordinates
local tile_x = math.floor(world_pos.x / TILE_SIZE)
local tile_y = math.floor(world_pos.y / TILE_SIZE)
```

### 2. `GetWorldToScreen2D(position, camera)`
**Location**: Raylib function exposed to Lua in `src/systems/scripting/scripting_functions.cpp:603-642`
**C++ Implementation**: Native Raylib function

**Purpose**: Convert world coordinates to screen coordinates using camera transformation

**Parameters**:
- `position` (Vector2): World position with `x` and `y` fields
- `camera` (Camera2D): Camera object with zoom, rotation, and target properties

**Returns**:
- `Vector2`: Screen coordinates with `x` and `y` fields

**Example Usage**:
```lua
-- Convert world position to screen position for UI overlay
local world_entity_pos = {x = 100, y = 50}  -- Entity position in world
local camera = get_current_camera()
local screen_pos = GetWorldToScreen2D(world_entity_pos, camera)

-- Draw UI element at screen position
draw_health_bar(screen_pos.x, screen_pos.y, entity_health)
```

## High-Level Camera Methods

### 3. `camera:GetMouseWorld()`
**Location**: C++ method in `src/systems/camera/custom_camera.hpp:345-347`
**Lua Binding**: Available on camera instances

**Purpose**: Get world-space mouse position for the current camera instance

**Parameters**: None (uses current mouse position internally)

**Returns**:
- `Vector2`: Current mouse position in world coordinates

**Implementation**:
```cpp
Vector2 GetMouseWorld() const {
    return GetScreenToWorld2D(globals::GetScaledMousePosition(), cam);
}
```

**Example Usage**:
```lua
-- Get world mouse position from camera instance
if camera and camera.Exists("world_camera") then
    local cam = camera.Get("world_camera")
    local world_mouse = cam:GetMouseWorld()

    print("Mouse in world: " .. world_mouse.x .. ", " .. world_mouse.y)

    -- Use for interaction detection
    local clicked_tile_x = math.floor(world_mouse.x / TILE_SIZE)
    local clicked_tile_y = math.floor(world_mouse.y / TILE_SIZE)
end
```

### 4. `camera:worldCoords(x, y, ox, oy)`
**Location**: Hump camera library in `assets/scripts/external/hump/camera.lua:118-123`

**Purpose**: Convert screen coordinates to world coordinates with optional offset

**Parameters**:
- `x` (number): Screen x coordinate
- `y` (number): Screen y coordinate
- `ox` (number, optional): X offset (default 0)
- `oy` (number, optional): Y offset (default 0)

**Returns**:
- `number, number`: World x and y coordinates

**Example Usage**:
```lua
-- Hump camera conversion
local hump_camera = require("external.hump.camera")
local cam = hump_camera()

local mouse = input.getMousePos()
local world_x, world_y = cam:worldCoords(mouse.x, mouse.y)
print("World position: " .. world_x .. ", " .. world_y)
```

### 5. `camera:cameraCoords(x, y, ox, oy, w, h)`
**Location**: Hump camera library in `assets/scripts/external/hump/camera.lua:109-115`

**Purpose**: Convert world coordinates to screen coordinates with optional dimensions

**Parameters**:
- `x` (number): World x coordinate
- `y` (number): World y coordinate
- `ox` (number, optional): X offset (default 0)
- `oy` (number, optional): Y offset (default 0)
- `w` (number, optional): Width (default 0)
- `h` (number, optional): Height (default 0)

**Returns**:
- `number, number`: Screen x and y coordinates

### 6. `camera:mousePosition(ox, oy)`
**Location**: Hump camera library in `assets/scripts/external/hump/camera.lua:126-132`

**Purpose**: Get mouse position in world coordinates using Hump camera

**Parameters**:
- `ox` (number, optional): X offset (default 0)
- `oy` (number, optional): Y offset (default 0)

**Returns**:
- `number, number`: Mouse x and y in world coordinates

## Input System Functions

### 7. `input.getMousePos()`
**Location**: Lua binding in `src/systems/input/input_lua_bindings.cpp:412`
**C++ Implementation**: `globals::getScaledMousePositionCached`

**Purpose**: Get current mouse position in scaled screen coordinates

**Parameters**: None

**Returns**:
- `table`: Screen coordinates with `x` and `y` fields
  - Coordinates are in virtual resolution space (1280x800)
  - Accounts for window scaling and letterboxing

**Example Usage**:
```lua
-- Get screen coordinates (input for world conversion)
local screen_mouse = input.getMousePos()
print("Screen mouse: " .. screen_mouse.x .. ", " .. screen_mouse.y)

-- Convert to world using camera transformation
local camera = get_active_camera()
local world_mouse = GetScreenToWorld2D(screen_mouse, camera)
```

## Coordinate System Details

### Screen Coordinate System
- **Origin**: Top-left corner (0, 0)
- **Virtual Resolution**: 1280x800 pixels
- **Scaling**: Automatically handles window scaling and letterboxing
- **Range**: X: [0, 1280], Y: [0, 800]

### World Coordinate System
- **Origin**: Camera-dependent (typically centered on camera target)
- **Units**: Game world units (often tiles × TILE_SIZE)
- **Transformations**: Affected by camera zoom, rotation, and target position
- **Range**: Unlimited (depends on world size)

### Camera Transformation Pipeline

**From Screen to World** (`GetScreenToWorld2D`):
1. **Input**: Screen coordinates (0-1280, 0-800 virtual space)
2. **Center**: Translate to camera center relative coordinates
3. **Zoom**: Divide by camera zoom factor
4. **Rotation**: Apply inverse camera rotation matrix
5. **Translation**: Add camera target position
6. **Output**: World coordinates

**From World to Screen** (`GetWorldToScreen2D`):
1. **Input**: World coordinates
2. **Translation**: Subtract camera target position
3. **Rotation**: Apply camera rotation matrix
4. **Zoom**: Multiply by camera zoom factor
5. **Center**: Translate from camera center to screen space
6. **Output**: Screen coordinates

## Implementation Details

### C++ Global Functions
**Location**: `src/core/globals.cpp`

#### `GetScaledMousePosition()` (Lines 136-158)
```cpp
Vector2 GetScaledMousePosition() {
    Vector2 mouse = GetMousePosition();  // Raw Raylib position

    // Remove letterbox offset and scale to virtual resolution
    mouse.x = (mouse.x - letterboxOffset.x) / renderScale;
    mouse.y = (mouse.y - letterboxOffset.y) / renderScale;

    return mouse;  // Returns 1280x800 virtual coordinates
}
```

#### `updateGlobalVariables()` (Lines 719-748)
```cpp
// Updates cached world mouse position each frame
void updateGlobalVariables() {
    Vector2 mouse = GetMousePosition();

    // Transform to world space with camera calculations
    float centerX = 640.0f, centerY = 400.0f;  // Virtual center
    mouse.x = (mouse.x - centerX) / camera2D.zoom;
    mouse.y = (mouse.y - centerY) / camera2D.zoom;

    // Apply camera rotation
    float angleRad = -camera2D.rotation * DEG2RAD;
    float cosAngle = cosf(angleRad);
    float sinAngle = sinf(angleRad);

    globals::worldMousePosition = {
        mouse.x * cosAngle - mouse.y * sinAngle + camera2D.target.x,
        mouse.x * sinAngle + mouse.y * cosAngle + camera2D.target.y
    };
}
```

#### `getWorldMousePosition()` (Lines 752-757)
```cpp
Vector2 getWorldMousePosition() {
    // Returns cached world mouse position
    if (engine_ctx && engine_ctx->isValid()) {
        return engine_ctx->worldMousePosition;
    }
    return globals::worldMousePosition;
}
```

## Complete Usage Pattern

**From**: `assets/scripts/idle_game/input.lua:15-81`

```lua
function sim_input.handleClick(config)
    -- Step 1: Get screen mouse coordinates
    local screen_mouse = input.getMousePos()

    -- Step 2: Convert to world coordinates
    local camera = require("idle_game.camera")
    local world_x = screen_mouse.x - camera.offsetX  -- Simple offset method
    local world_y = screen_mouse.y - camera.offsetY

    -- Alternative: Use camera transformation
    -- local camera_instance = get_active_camera()
    -- local world_pos = GetScreenToWorld2D(screen_mouse, camera_instance)
    -- local world_x, world_y = world_pos.x, world_pos.y

    -- Step 3: Convert to tile coordinates
    local tile_x = math.floor(world_x / config.TILE_SIZE)
    local tile_y = math.floor(world_y / config.TILE_SIZE)

    return tile_x, tile_y
end
```

## API Comparison Table

| Function | Input Type | Output Type | Camera Required | Use Case |
|----------|------------|-------------|-----------------|----------|
| `GetScreenToWorld2D()` | Screen coords | World coords | Yes | General conversion |
| `GetWorldToScreen2D()` | World coords | Screen coords | Yes | UI positioning |
| `camera:GetMouseWorld()` | None (auto) | World coords | Implicit | Quick mouse world pos |
| `camera:worldCoords()` | Screen coords | World coords | Yes (Hump) | Hump camera system |
| `camera:mousePosition()` | None (auto) | World coords | Yes (Hump) | Hump mouse world pos |
| `input.getMousePos()` | None | Screen coords | No | Get input coordinates |

## Testing Support

**Mock Implementation Example**:
```lua
-- Mock camera for testing coordinate conversion
local mock_camera = {
    target = {x = 0, y = 0},
    zoom = 1.0,
    rotation = 0.0
}

-- Test conversion
local screen_pos = {x = 640, y = 400}  -- Screen center
local world_pos = GetScreenToWorld2D(screen_pos, mock_camera)
-- Should return world center coordinates
```

## Related Documentation

- Mouse Click API: `/data/projects/incremental-flag/api_documentation/mouse_click_api.md`
- Mouse Wheel API: `/data/projects/incremental-flag/api_documentation/mouse_wheel_api.md`
- Camera System: `/data/projects/incremental-flag/src/systems/camera/custom_camera.hpp`
- Input System: `/data/projects/incremental-flag/assets/scripts/idle_game/input.lua`
- Hump Camera: `/data/projects/incremental-flag/assets/scripts/external/hump/camera.lua`