# Mouse Wheel API Documentation

## Overview
The input system provides mouse wheel functionality through both direct polling and action binding mechanisms. This document specifies the exact API names, function signatures, and sign conventions for mouse wheel input.

## Mouse Wheel Functions

### 1. `input.getMouseWheel()`
**Location**: Lua binding in `src/systems/input/input_lua_bindings.cpp:413`
**C++ Implementation**: `src/systems/input/input_polling.cpp:207-218`

**Purpose**: Get the current frame's mouse wheel movement delta

**Parameters**: None

**Returns**:
- `number`: Mouse wheel movement delta for the current frame
  - **Positive value**: Scrolling UP (wheel rolled forward/away from user)
  - **Negative value**: Scrolling DOWN (wheel rolled backward/toward user)
  - **Zero**: No wheel movement this frame

**Sign Convention Summary**:
- `+1.0`: One "tick" scroll up
- `-1.0`: One "tick" scroll down
- `0.0`: No wheel movement

**Example Usage**:
```lua
-- Basic per-frame wheel polling
local wheel_delta = input.getMouseWheel()
if wheel_delta ~= 0 then
    print("Wheel moved: " .. wheel_delta)
    if wheel_delta > 0 then
        print("Scrolling UP")
    else
        print("Scrolling DOWN")
    end
end

-- Scroll panel example
function scroll_panel(wheel_delta)
    if wheel_delta ~= 0 then
        -- Apply wheel movement to scroll offset
        scroll_offset = scroll_offset + wheel_delta
        scroll_offset = math.max(0, math.min(scroll_offset, max_scroll))
    end
end
```

**Practical Usage Pattern** (from `assets/scripts/idle_game/ui/ascii_upgrade_panel.lua:287-295`):
```lua
function ascii_upgrade_panel.scroll_by_wheel(wheel_delta)
    if not _initialized then return end

    local max_offset = math.max(0, #_upgrade_list - _max_visible_upgrades)

    -- Scroll up (negative delta) or down (positive delta)
    _scroll_offset = _scroll_offset + wheel_delta
    _scroll_offset = math.max(0, math.min(_scroll_offset, max_offset))
end
```

## Action Binding Support

### Mouse Wheel as Axis Input
**Axis Constant**: `AXIS_MOUSE_WHEEL_Y = 1001` (defined in `src/systems/input/input_function_data.hpp:25`)

The mouse wheel can be bound to game actions using the axis binding system:

```lua
-- Bind zoom actions to mouse wheel directions
input.bind("ZoomIn",  { device = "gamepad_axis", axis = AXIS_MOUSE_WHEEL_Y, trigger = "AxisPos", threshold = 0.2 })
input.bind("ZoomOut", { device = "gamepad_axis", axis = AXIS_MOUSE_WHEEL_Y, trigger = "AxisNeg", threshold = 0.2 })

-- Check bound actions
if input.action_down("ZoomIn") then
    camera.zoom = camera.zoom * 1.1
elseif input.action_down("ZoomOut") then
    camera.zoom = camera.zoom * 0.9
end
```

**Trigger Types**:
- `"AxisPos"`: Triggers on positive wheel movement (scroll up)
- `"AxisNeg"`: Triggers on negative wheel movement (scroll down)
- `threshold`: Minimum wheel delta to trigger the action

## Implementation Details

### C++ Level Architecture

**Input Provider Interface** (`src/systems/input/input_polling.hpp:32,58`):
```cpp
virtual float get_mouse_wheel_move() const = 0;
float get_mouse_wheel_move() const override;  // Wraps Raylib GetMouseWheelMove()
```

**Frame Polling** (`src/systems/input/input_polling.cpp:207-218`):
```cpp
// ----------------
// Mouse Wheel
// ----------------
float wheelMove = provider.get_mouse_wheel_move();
if (wheelMove != 0.0f) {
    hid::reconfigure_device_info(reg, state, InputDeviceInputCategory::MOUSE);
    // Dispatch as axis input (using special AXIS_MOUSE_WHEEL_Y code)
    input::DispatchRaw(state,
        InputDeviceInputCategory::GAMEPAD_AXIS, // intentionally using gamepad axis category
        AXIS_MOUSE_WHEEL_Y,
        /*down*/ true,
        /*value*/ wheelMove);
}
```

### Scroll System Integration

**Scroll Speed Configuration** (`src/systems/input/input_constants.hpp:37-41`):
```cpp
// ========================================================================
// Scroll Settings
// ========================================================================

// Scroll speed multiplier for mouse wheel scrolling
constexpr float SCROLL_SPEED = 10.0f;
```

**Active Scroll Pane Tracking** (`src/systems/input/input_function_data.hpp:176`):
```cpp
entt::entity activeScrollPane = entt::null; // Currently active scroll pane, if any
```

The input system automatically detects which UI scroll pane is under the cursor and routes wheel input accordingly.

## Data Flow Summary

1. **Raylib**: `GetMouseWheelMove()` → raw float delta
2. **Input Provider**: Abstracts Raylib call for testing
3. **Input Polling**: Dispatches wheel as axis event with `AXIS_MOUSE_WHEEL_Y`
4. **Lua Binding**: `input.getMouseWheel()` returns delta to scripts
5. **UI Components**: Handle wheel input for scrolling/zooming

## Testing & Validation

The mouse wheel API can be tested using the input provider abstraction:

```cpp
// Mock for unit tests
class MockInputProvider : public InputProvider {
    float get_mouse_wheel_move() const override {
        return mock_wheel_delta;
    }
    // ...
};
```

## Related Documentation

- Input Action Binding: `/data/projects/incremental-flag/src/systems/input/input_action_binding_usage.md`
- UI System: `/data/projects/incremental-flag/.sisyphus/plans/incremental-ascii-ui.md` (lines 650, 676, 1578-1591, 3659)
- Scroll Pane Implementation: `assets/scripts/idle_game/ui/ascii_upgrade_panel.lua`