# Unified Lua API Reference

> Auto-generated from binding definitions and api.lua module

**Last updated:** 2025-12-19


## Core API (from api.lua)

See `assets/scripts/core/api.lua` for the authoritative documentation table.

Key modules:
- `registry` - ECS entity management
- `component_cache` - Cached component access
- `physics` - Physics world and collision
- `timer` - Timer and sequence API
- `signal` - Event pub/sub system
- `draw` - Drawing commands

## Builder APIs

### EntityBuilder

```lua
local EntityBuilder = require('core.entity_builder')

-- Full options
local entity, script = EntityBuilder.create({
    sprite = 'kobold',
    position = { x = 100, y = 200 },
    size = { 64, 64 },
    shadow = true,
    data = { health = 100 },
})

-- Simple creation
local entity = EntityBuilder.simple('sprite', x, y, w, h)

-- Validated (prevents data-after-attach bug)
local script = EntityBuilder.validated(MyScript, entity, { health = 100 })
```

### PhysicsBuilder

```lua
local PhysicsBuilder = require('core.physics_builder')

PhysicsBuilder.for_entity(entity)
    :circle()
    :tag('projectile')
    :bullet()
    :collideWith({ 'enemy', 'WORLD' })
    :apply()
```

### ShaderBuilder

```lua
local ShaderBuilder = require('core.shader_builder')

ShaderBuilder.for_entity(entity)
    :add('3d_skew_holo', { sheen_strength = 1.5 })
    :add('dissolve', { dissolve = 0.5 })
    :apply()
```


## Quick Helpers (Q.lua)

```lua
local Q = require('core.Q')

Q.move(entity, x, y)       -- Move to absolute position
Q.offset(entity, dx, dy)   -- Move relative
local cx, cy = Q.center(entity)  -- Get center point
```


## Timer API

```lua
local timer = require('core.timer')

-- One-shot
timer.after(2.0, function() print('done') end, 'my_tag')

-- Repeating
timer.every(0.5, function() print('tick') end, 'heartbeat')

-- Sequence
timer.sequence('anim')
    :wait(0.5)
    :do_now(function() print('start') end)
    :wait(0.3)
    :do_now(function() print('end') end)
    :start()

-- Cancel
timer.cancel('my_tag')
```


## Event System (Signal)

```lua
local signal = require('external.hump.signal')

-- Emit event
signal.emit('player_damaged', player_entity, { damage = 25, type = 'fire' })

-- Register handler
signal.register('player_damaged', function(entity, data)
    log_debug('Player took', data.damage, data.type, 'damage')
end)
```


## Common Patterns

### Safe Entity Access

```lua
if ensure_entity(eid) then
    local script = safe_script_get(eid)
    local health = script_field(eid, 'health', 100)  -- with default
end
```

### Component Cache

```lua
local transform = component_cache.get(entity, Transform)
if transform then
    transform.actualX = 100
end
```


## Performance Settings

```lua
-- Enable shader/texture batching (reduces GPU state changes)
set_shader_texture_batching(true)

-- Check current state
local enabled = get_shader_texture_batching()
```


## Command Buffer Sprite Drawing

The `command_buffer` module provides queued sprite drawing functions for both World and Screen coordinate spaces. These are the primary APIs for rendering sprites in the game.

### queueDrawSpriteTopLeft

**Signature:**
```lua
command_buffer.queueDrawSpriteTopLeft(layer, config_fn, z_order, coordinate_space)
```

**Parameters:**
- `layer` (Layer) - The draw layer to queue the command on (typically `layers.sprites`)
- `config_fn` (function) - Configuration callback that receives a command object `c`
- `z_order` (integer) - Z-order for depth sorting (higher = on top)
- `coordinate_space` (layer.DrawCommandSpace, optional) - `World` or `Screen` space

**Config function fields:**
- `c.spriteName` (string) - Sprite name/UUID to render
- `c.x`, `c.y` (number) - Top-left position coordinates
- `c.dstW`, `c.dstH` (number, optional) - Destination width/height (defaults to sprite size)
- `c.tint` (color, optional) - Color tint to apply to sprite

**Example (World space terrain):**
```lua
command_buffer.queueDrawSpriteTopLeft(
    layers.sprites,
    function(c)
        c.spriteName = "d437_grass.png"
        c.x = tile_x * TILE_SIZE
        c.y = tile_y * TILE_SIZE
        c.dstW = TILE_SIZE
        c.dstH = TILE_SIZE
        c.tint = util.getColor("GREEN")
    end,
    0, -- z-order
    layer.DrawCommandSpace.World
)
```

**Example (Screen space UI):**
```lua
command_buffer.queueDrawSpriteTopLeft(
    layers.sprites,
    function(c)
        c.spriteName = sprite_name
        c.x = panel_x + icon_x
        c.y = panel_y + icon_y
        c.dstW = icon_size
        c.dstH = icon_size
    end,
    100, -- UI z-order (above world)
    layer.DrawCommandSpace.Screen
)
```

### queueDrawSpriteCentered

**Signature:**
```lua
command_buffer.queueDrawSpriteCentered(layer, config_fn, z_order, coordinate_space)
```

Similar to `queueDrawSpriteTopLeft` but positions sprites by their center point instead of top-left corner.

**Config function differences:**
- `c.x`, `c.y` represent the center position of the sprite

**Example:**
```lua
command_buffer.queueDrawSpriteCentered(
    layers.sprites,
    function(c)
        c.spriteName = "player.png"
        c.x = player_center_x
        c.y = player_center_y
        c.dstW = 32
        c.dstH = 32
    end,
    1,
    layer.DrawCommandSpace.World
)
```

### Common Patterns

**UI panels (Screen space):**
```lua
-- Always use Screen space for UI elements
command_buffer.queueDrawSpriteTopLeft(
    layers.sprites,
    function(c) ... end,
    100, -- High z-order for UI
    layer.DrawCommandSpace.Screen
)
```

**Terrain/World objects:**
```lua
-- Use World space for game objects
command_buffer.queueDrawSpriteTopLeft(
    layers.sprites,
    function(c) ... end,
    0, -- Base z-order
    layer.DrawCommandSpace.World
)
```

**Safety checks:**
```lua
if not command_buffer or not layers then return end
-- Proceed with drawing commands
```

## Mouse Input API

The mouse input system provides access to cursor position in both screen and world coordinate spaces.

### Screen Space Mouse Position

**Primary API:**
```lua
input.getMousePos() -> table
```

**Return value:**
- Type: `table` with numeric fields
- Fields: `x`, `y` (number) - pixel coordinates
- Units: Pixels in screen space
- Coordinate system: Top-left origin (0,0 at screen top-left)
- Range: 0 to screen width/height

**Example:**
```lua
if input and input.getMousePos then
    local mouse = input.getMousePos()
    local screenX, screenY = mouse.x, mouse.y
    print(string.format("Mouse at screen (%d, %d)", screenX, screenY))
end
```

### Alternative Mouse Functions

**Individual coordinate access:**
```lua
GetMouseX() -> number  -- Screen X position in pixels
GetMouseY() -> number  -- Screen Y position in pixels
```

Note: These are Raylib functions with optional availability checks:
```lua
local mx = GetMouseX and GetMouseX() or 0
local my = GetMouseY and GetMouseY() or 0
```

### World Space Mouse Position

**Camera-based conversion:**
```lua
camera.Get("world_camera"):GetMouseWorld() -> Vector2
```

Converts screen mouse position to world coordinates through the active camera.

**Example:**
```lua
if camera and camera.Exists and camera.Exists("world_camera") then
    local cam = camera.Get("world_camera")
    if cam and cam.GetMouseWorld then
        local worldMouse = cam:GetMouseWorld()
        if worldMouse then
            local worldX, worldY = worldMouse.x, worldMouse.y
            -- Use world coordinates for game logic
        end
    end
end
```

### Common Usage Patterns

**UI hit testing:**
```lua
local function checkMouseInRect(rect)
    if not input or not input.getMousePos then return false end
    local mouse = input.getMousePos()
    return mouse.x >= rect.x and mouse.x < rect.x + rect.w and
           mouse.y >= rect.y and mouse.y < rect.y + rect.h
end
```

**Fallback chain for mouse position:**
```lua
local function getMousePosition()
    if input and input.getMousePos then
        return input.getMousePos()
    elseif GetMouseX and GetMouseY then
        return { x = GetMouseX(), y = GetMouseY() }
    end
    return { x = 0, y = 0 }  -- Default fallback
end
```

**Converting to tile coordinates:**
```lua
local mouse = input.getMousePos()
local tileX = math.floor(worldX / TILE_SIZE)
local tileY = math.floor(worldY / TILE_SIZE)
```

## See Also

- `CLAUDE.md` - Quick reference and patterns
- `docs/api/` - Individual API documentation files
- `docs/content-creation/` - Content creation guides
- `assets/scripts/core/api.lua` - Full API documentation table
