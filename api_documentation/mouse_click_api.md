# Mouse Click API Documentation

## Overview
The input system provides comprehensive mouse click functionality through direct polling, event handling, and GameObject callback mechanisms. This document specifies the exact API names, button enums, and usage patterns for mouse click input.

## Mouse Button Constants

### Button Enum Values
**Location**: Lua binding in `src/systems/input/input_lua_bindings.cpp:284-291`

The Raylib `MouseButton` enum is exposed to Lua:

```lua
MouseButton.MOUSE_BUTTON_LEFT     -- 0 (Primary/Left click)
MouseButton.MOUSE_BUTTON_RIGHT    -- 1 (Secondary/Right click)
MouseButton.MOUSE_BUTTON_MIDDLE   -- 2 (Wheel/Middle click)
MouseButton.MOUSE_BUTTON_SIDE     -- 3 (Side button)
MouseButton.MOUSE_BUTTON_EXTRA    -- 4 (Extra button)
MouseButton.MOUSE_BUTTON_FORWARD  -- 5 (Forward navigation)
MouseButton.MOUSE_BUTTON_BACK     -- 6 (Back navigation)
```

**C++ Constants**:
- `MOUSE_LEFT_BUTTON = 0` - Left click (standard selection)
- `MOUSE_RIGHT_BUTTON = 1` - Right click (context menus)
- `MOUSE_MIDDLE_BUTTON = 2` - Middle click (scroll wheel press)

## Mouse Click Functions

### 1. `input.isMousePressed(button)`
**Location**: Lua binding in `src/systems/input/input_lua_bindings.cpp:410`
**C++ Implementation**: Wraps Raylib `IsMouseButtonPressed()`

**Purpose**: Check if mouse button was pressed this frame (first frame only)

**Parameters**:
- `button` (number): Button constant from MouseButton enum

**Returns**:
- `boolean`: `true` if button was pressed this frame, `false` otherwise

**Example Usage**:
```lua
-- Check for left click this frame
if input.isMousePressed(MouseButton.MOUSE_BUTTON_LEFT) then
    print("Left mouse button pressed!")
    local mouse = input.getMousePos()
    print("Click position: " .. mouse.x .. ", " .. mouse.y)
end

-- Check for right click
if input.isMousePressed(MouseButton.MOUSE_BUTTON_RIGHT) then
    print("Right click detected - show context menu")
end
```

### 2. `input.isMouseDown(button)`
**Location**: Lua binding in `src/systems/input/input_lua_bindings.cpp:409`
**C++ Implementation**: Wraps Raylib `IsMouseButtonDown()`

**Purpose**: Check if mouse button is currently held down

**Parameters**:
- `button` (number): Button constant from MouseButton enum

**Returns**:
- `boolean`: `true` if button is currently held, `false` otherwise

**Example Usage**:
```lua
-- Check if left button is held (for dragging)
if input.isMouseDown(MouseButton.MOUSE_BUTTON_LEFT) then
    -- Handle drag operation
    handle_drag()
end
```

### 3. `input.isMouseReleased(button)`
**Location**: Lua binding in `src/systems/input/input_lua_bindings.cpp:411`
**C++ Implementation**: Wraps Raylib `IsMouseButtonReleased()`

**Purpose**: Check if mouse button was released this frame

**Parameters**:
- `button` (number): Button constant from MouseButton enum

**Returns**:
- `boolean`: `true` if button was released this frame, `false` otherwise

**Example Usage**:
```lua
-- Handle drag release
if input.isMouseReleased(MouseButton.MOUSE_BUTTON_LEFT) then
    finish_drag_operation()
end
```

### 4. `input.getMousePos()`
**Location**: Lua binding in `src/systems/input/input_lua_bindings.cpp:412`

**Purpose**: Get current mouse position

**Parameters**: None

**Returns**:
- `table`: Mouse position with `x` and `y` fields
  - `x` (number): Horizontal screen coordinate
  - `y` (number): Vertical screen coordinate

**Example Usage**:
```lua
local mouse = input.getMousePos()
print("Mouse at: " .. mouse.x .. ", " .. mouse.y)

-- Convert to world/tile coordinates
local worldX = mouse.x + camera.offsetX
local worldY = mouse.y + camera.offsetY
local tileX = math.floor(worldX / TILE_SIZE)
local tileY = math.floor(worldY / TILE_SIZE)
```

## Complete Click Handling Example

**From**: `assets/scripts/idle_game/input.lua:15-81`

```lua
function sim_input.handleClick(config)
    -- Check for left click press
    local leftButton = MouseButton.MOUSE_BUTTON_LEFT
    local mousePressed = input.isMousePressed(leftButton)

    if not mousePressed then
        return nil
    end

    -- Get mouse position
    local mouse = input.getMousePos()
    local mouseX = mouse.x
    local mouseY = mouse.y

    -- Convert screen coordinates to world coordinates
    local camera = require("idle_game.camera")
    local worldX = mouseX - camera.offsetX
    local worldY = mouseY - camera.offsetY

    -- Convert to tile coordinates
    local tileX = math.floor(worldX / config.TILE_SIZE)
    local tileY = math.floor(worldY / config.TILE_SIZE)

    print(string.format("Clicked tile (%d, %d) at world (%.1f, %.1f)",
        tileX, tileY, worldX, worldY))

    return tileX, tileY
end
```

## Event System Integration

### Mouse Click Events
**Location**: Event structure in `src/core/events.hpp:23-31`

```cpp
struct MouseClicked : public event_bus::Event {
    Vector2 position{};           // Click coordinates
    int button{0};                // Button code (0=left, 1=right, 2=middle)
    entt::entity target{entt::null}; // Target entity that was clicked
};
```

**Event Publishing** (from `src/systems/input/input_polling.cpp:157-196`):
```cpp
// Left click detection and event publishing
if (mouseDetectDownFirstFrameLeft) {
    Vector2 mousePos = globals::getScaledMousePositionCached();
    cursor_events::enqueue_left_press(state, mousePos.x, mousePos.y);
    bus.publish(events::MouseClicked{mousePos, MOUSE_LEFT_BUTTON});
}

// Right click detection
if (mouseDetectDownFirstFrameRight) {
    Vector2 mousePos = globals::getScaledMousePositionCached();
    cursor_events::enqueue_right_press(state, mousePos.x, mousePos.y);
    bus.publish(events::MouseClicked{mousePos, MOUSE_RIGHT_BUTTON});
}
```

### GameObject Click Callbacks

GameObjects can implement these callback methods for click handling:

**Available Callbacks**:
- `onClick` - Called when entity is left-clicked
- `onRightClick` - Called when entity is right-clicked
- `onDrag` - Called while dragging from this entity
- `onRelease` - Called when mouse is released
- `onHover` - Called when hover starts
- `onStopHover` - Called when hover ends

**Example Implementation**:
```lua
-- GameObject with click handling
local myGameObject = {
    methods = {
        onClick = function(self, event)
            print("Entity " .. self.id .. " was clicked!")
            print("Click position: " .. event.position.x .. ", " .. event.position.y)
            print("Button: " .. event.button)
        end,

        onRightClick = function(self, event)
            print("Right-clicked entity " .. self.id)
            -- Show context menu
            show_context_menu(event.position)
        end
    }
}
```

## Advanced Features

### Mac Right-Click Emulation
**Location**: `src/systems/input/input_polling.cpp`

The system automatically handles Mac-style right-click emulation:
- `Ctrl + Left Click` = Right Click
- `Cmd + Left Click` = Right Click

```cpp
bool ctrlDown = provider.is_key_down(KEY_LEFT_CONTROL) || provider.is_key_down(KEY_RIGHT_CONTROL);
bool cmdDown = provider.is_key_down(KEY_LEFT_SUPER) || provider.is_key_down(KEY_RIGHT_SUPER);
bool macRightClickEmulation = (ctrlDown || cmdDown) && mouseLeftDownCurrentFrame;
bool effectiveRightDown = mouseRightDownCurrentFrame || macRightClickEmulation;
```

### UI Button Activation
**Location**: Event structure in `src/core/events.hpp:91-97`

```cpp
struct UIButtonActivated : public event_bus::Event {
    entt::entity element{entt::null}; // Button entity
    int button{MOUSE_LEFT_BUTTON};    // Which mouse button activated it
};
```

### Drag and Drop Support

The input system tracks complete drag operations:

**Input State Tracking** (from InputState):
- `cursor_down_target` - Entity where mouse was pressed
- `cursor_up_target` - Entity where mouse was released
- `cursor_down_position` - Initial click position
- `cursor_up_position` - Release position
- `cursor_down_time` / `cursor_up_time` - Timing information
- `cursor_released_on_target` - Drop target validation

**Drag Event Propagation**:
```cpp
// From src/systems/input/input_cursor_events.hpp
void propagate_drag(entt::registry& registry, InputState& state);
void propagate_release(InputState& state, entt::registry& registry);
```

## Usage Patterns

### Basic Click Detection
```lua
-- Simple click handling
function handle_input()
    if input.isMousePressed(MouseButton.MOUSE_BUTTON_LEFT) then
        local pos = input.getMousePos()
        on_left_click(pos.x, pos.y)
    end

    if input.isMousePressed(MouseButton.MOUSE_BUTTON_RIGHT) then
        local pos = input.getMousePos()
        show_context_menu(pos.x, pos.y)
    end
end
```

### Drag Operations
```lua
-- Drag handling with state tracking
local dragging = false
local drag_start_pos = nil

function handle_drag()
    if input.isMousePressed(MouseButton.MOUSE_BUTTON_LEFT) then
        dragging = true
        drag_start_pos = input.getMousePos()
    end

    if dragging and input.isMouseDown(MouseButton.MOUSE_BUTTON_LEFT) then
        local current_pos = input.getMousePos()
        update_drag_visual(drag_start_pos, current_pos)
    end

    if input.isMouseReleased(MouseButton.MOUSE_BUTTON_LEFT) then
        if dragging then
            local end_pos = input.getMousePos()
            complete_drag_operation(drag_start_pos, end_pos)
            dragging = false
        end
    end
end
```

## Testing Support

**Mock Input Provider** (for unit tests):
```cpp
class MockInputProvider : public InputProvider {
public:
    bool is_mouse_button_down(int button) const override {
        return mock_button_states[button];
    }

    bool is_mouse_button_pressed(int button) const override {
        return mock_button_pressed[button];
    }

    Vector2 get_mouse_position() const override {
        return mock_mouse_position;
    }
};
```

## Related Documentation

- Mouse Wheel API: `/data/projects/incremental-flag/api_documentation/mouse_wheel_api.md`
- Input Event System: `/data/projects/incremental-flag/src/core/events.hpp`
- GameObject Callbacks: `/data/projects/incremental-flag/src/systems/input/input_cursor_events.cpp`
- UI Click Testing: `/data/projects/incremental-flag/test_ui_click_handling.lua`