# Terrain Tile Conventions API Documentation

## Overview
The terrain system uses a grid-based tile coordinate system with specific conventions for tileX/tileY coordinates, walkability checks, and collision detection. This document specifies the exact coordinate conventions, tile type definitions, and methods for terrain interaction.

## Core Coordinate System

### Tile Coordinate Conventions
**Grid Origin**: Top-left corner (0, 0)
**X-axis**: Extends rightward (0 to width-1)
**Y-axis**: Extends downward (0 to height-1)
**Indexing**: 0-based for all coordinates

**Coordinate Space Diagram**:
```
(0,0) ────────► X-axis (rightward)
  │
  │  [0][1][2][3]...
  │  [width-1]
  ▼
Y-axis (downward)
```

**Linear Array Indexing**:
```lua
-- Convert 2D coordinates to linear array index
index = y * grid_width + x

-- Convert linear index back to 2D coordinates
x = index % grid_width
y = math.floor(index / grid_width)
```

### Three Coordinate Spaces

#### 1. Grid Coordinates (Tile Space)
- **Units**: Tile units (integers)
- **Range**: X: [0, width-1], Y: [0, height-1]
- **Usage**: Pathfinding, game logic, tile queries

#### 2. Layer-Space Pixels
- **Units**: Pixels relative to layer origin
- **Conversion**: `pixel = grid * cell_size + layer_offset`
- **Usage**: Rendering, local positioning

#### 3. World-Space Pixels
- **Units**: Pixels in global world space
- **Conversion**: `world = layer_pixel + level_position`
- **Usage**: Entity positioning, camera, physics

### Coordinate Conversion Formulas

```lua
-- Grid to Pixel (Layer-space)
function gridToPixel(gridX, gridY, cell_size, layer_offset)
    local pixelX = gridX * cell_size + layer_offset.x
    local pixelY = gridY * cell_size + layer_offset.y
    return pixelX, pixelY
end

-- Pixel to Grid (Layer-space)
function pixelToGrid(pixelX, pixelY, cell_size, layer_offset)
    local gridX = math.floor((pixelX - layer_offset.x) / cell_size)
    local gridY = math.floor((pixelY - layer_offset.y) / cell_size)
    return gridX, gridY
end

-- Grid to World (Global space)
function gridToWorld(gridX, gridY, cell_size, layer_offset, level_position)
    local layerX, layerY = gridToPixel(gridX, gridY, cell_size, layer_offset)
    local worldX = layerX + level_position.x
    local worldY = layerY + level_position.y
    return worldX, worldY
end
```

## Walkability and Tile Types

### IntGrid System (Primary Collision Detection)
**Location**: Core terrain collision system
**Data Type**: `uint16_t` values (0-65535)

**Walkability Rules**:
```lua
-- Core walkability convention
function isWalkable(intgrid_value)
    return intgrid_value == 0  -- Only value 0 is walkable
end

function isOccupied(intgrid_value)
    return intgrid_value ~= 0  -- Any non-zero value is occupied/solid
end
```

### Standard IntGrid Value Conventions

| Value | Type | Walkable | Physics | Common Usage |
|-------|------|----------|---------|--------------|
| **0** | Empty | ✅ Yes | No collision | Open space, paths |
| **1** | Floor | ❌ No | Collision | Ground tiles, platforms |
| **2** | Wall | ❌ No | Collision | Walls, barriers |
| **3** | Water | 🔄 Special | Special | Water tiles, may have special rules |
| **4+** | Custom | ❌ No | Collision | Designer-defined terrain types |

### Tile Type Constants
**From Game Implementation**:

```lua
-- Standard tile type identifiers
TERRAIN_TYPES = {
    EMPTY = 0,    -- Walkable space
    GRASS = 1,    -- Standard ground
    TREE = 2,     -- Tree obstacle (harvestable)
    ROCK = 3,     -- Rock obstacle (harvestable)
    WATER = 4,    -- Water terrain
    WALL = 5      -- Solid wall
}
```

**Example Terrain Configuration**:
```lua
-- From idle_game.terrain implementation
terrain.GRASS = "GRASS"  -- Ground tiles
terrain.TREE = "TREE"    -- Harvestable trees
terrain.ROCK = "ROCK"    -- Harvestable rocks
```

## Data Storage and Access

### Memory Layout
**Storage Format**: Linear array with row-major ordering
**Access Pattern**: `data[y * width + x]`

**Implementation Example**:
```lua
-- Terrain grid access
function terrain.get(x, y)
    if x < 0 or x >= grid_width or y < 0 or y >= grid_height then
        return nil  -- Out of bounds
    end
    local index = y * grid_width + x
    return grid_data[index]
end

function terrain.set(x, y, value)
    if x >= 0 and x < grid_width and y >= 0 and y < grid_height then
        local index = y * grid_width + x
        grid_data[index] = value
        return true
    end
    return false  -- Out of bounds
end
```

### Bounds Checking Patterns

```lua
-- Standard bounds validation
function isValidTile(x, y, width, height)
    return x >= 0 and x < width and y >= 0 and y < height
end

-- Safe tile access with default
function getTerrainSafe(x, y, default_value)
    if isValidTile(x, y, grid_width, grid_height) then
        return terrain.get(x, y)
    else
        return default_value or 0  -- Return default for out-of-bounds
    end
end
```

## Collision Detection and Physics

### Run-Length Encoding Optimization
**Purpose**: Convert tile grid to efficient physics colliders

**Algorithm**:
1. **Scan**: Process grid row by row
2. **Compress**: Merge consecutive non-zero tiles into rectangles
3. **Generate**: Create single collider per rectangle
4. **Result**: Fewer physics bodies for better performance

**Example**:
```
Original Grid:        Compressed Colliders:
[0][1][1][1][0]  →   Rectangle(x=1, y=0, width=3, height=1)
[0][0][1][0][0]  →   Rectangle(x=2, y=1, width=1, height=1)
```

### Physics Integration
**Coordinate Space**: World-space pixels (converted at load time)
**Physics Engine**: Chipmunk physics bodies
**Collider Types**: Static rectangles for terrain

```lua
-- Example collision detection
function createTerrainColliders(intgrid, cell_size, level_position)
    local colliders = {}

    -- Convert non-zero IntGrid cells to rectangles
    for rect in runLengthEncode(intgrid) do
        local world_x = rect.x * cell_size + level_position.x
        local world_y = rect.y * cell_size + level_position.y
        local collider = createStaticRectangle(world_x, world_y,
                                              rect.width * cell_size,
                                              rect.height * cell_size)
        table.insert(colliders, collider)
    end

    return colliders
end
```

## Pathfinding Integration

### Navmesh Generation
**Source**: IntGrid collision data
**Method**: Generate walkable areas from non-collision tiles

**Walkability Query**:
```lua
function isNavigable(x, y)
    local terrain_type = terrain.get(x, y)
    return terrain_type == 0  -- Only empty tiles are navigable
end

-- A* pathfinding with terrain awareness
function findPath(startX, startY, goalX, goalY)
    -- Use IntGrid values for collision checking
    -- Only traverse tiles with value 0 (empty/walkable)
end
```

### Vision and Line-of-Sight
**Integration**: Uses same navmesh for cone-of-vision queries
**Method**: Ray-casting through walkable tiles

```lua
function hasLineOfSight(fromX, fromY, toX, toY)
    -- Bresenham line algorithm with terrain checking
    for x, y in bresenhamLine(fromX, fromY, toX, toY) do
        if not isNavigable(x, y) then
            return false  -- Blocked by terrain
        end
    end
    return true  -- Clear line of sight
end
```

## Terrain Modification Operations

### Basic Operations

#### 1. **Clear Area**
```lua
function clearArea(startX, startY, width, height, clear_value)
    clear_value = clear_value or 0  -- Default to walkable

    for y = startY, startY + height - 1 do
        for x = startX, startX + width - 1 do
            terrain.set(x, y, clear_value)
        end
    end
end
```

#### 2. **Fill Rectangle**
```lua
function fillRectangle(startX, startY, width, height, fill_value)
    for y = startY, startY + height - 1 do
        for x = startX, startX + width - 1 do
            terrain.set(x, y, fill_value)
        end
    end
end
```

#### 3. **Flood Fill**
```lua
function floodFill(startX, startY, new_value, target_value)
    target_value = target_value or terrain.get(startX, startY)

    if target_value == new_value then return end

    local queue = {{x = startX, y = startY}}
    local visited = {}

    while #queue > 0 do
        local current = table.remove(queue, 1)
        local key = current.y * grid_width + current.x

        if visited[key] or terrain.get(current.x, current.y) ~= target_value then
            goto continue
        end

        visited[key] = true
        terrain.set(current.x, current.y, new_value)

        -- Add 4-connected neighbors
        local neighbors = {
            {x = current.x + 1, y = current.y},
            {x = current.x - 1, y = current.y},
            {x = current.x, y = current.y + 1},
            {x = current.x, y = current.y - 1}
        }

        for _, neighbor in ipairs(neighbors) do
            if isValidTile(neighbor.x, neighbor.y, grid_width, grid_height) then
                table.insert(queue, neighbor)
            end
        end

        ::continue::
    end
end
```

### Procedural Generation

#### Auto-Rules System
**Purpose**: Automatically generate TileGrid visuals from IntGrid data
**Implementation**: LDtk auto-rules with Lua integration

```lua
-- Example auto-rule application
function applyTerrainRules(intgrid_layer)
    -- Apply visual tile rules based on IntGrid patterns
    -- Convert collision data to appropriate visual tiles
    local tile_layer = ldtk.generateTileLayer(intgrid_layer, auto_rules)
    return tile_layer
end
```

## Coordinate System Integration Examples

### Entity-Terrain Interaction
```lua
-- Convert entity world position to tile coordinates
function getEntityTile(entity)
    local transform = component_cache.get(entity, Transform)
    local worldX, worldY = transform.actualX, transform.actualY

    -- Convert world to tile coordinates
    local tileX = math.floor(worldX / TILE_SIZE)
    local tileY = math.floor(worldY / TILE_SIZE)

    return tileX, tileY
end

-- Check if entity can move to position
function canMoveTo(entity, worldX, worldY)
    local tileX = math.floor(worldX / TILE_SIZE)
    local tileY = math.floor(worldY / TILE_SIZE)

    local terrain_type = terrain.get(tileX, tileY)
    return terrain_type == terrain.GRASS  -- Only grass tiles walkable
end
```

### Resource Harvesting Integration
```lua
-- Find harvestable terrain near position
function findHarvestableNear(centerX, centerY, radius, resource_type)
    local target_terrain = (resource_type == "wood") and terrain.TREE or terrain.ROCK

    for dy = -radius, radius do
        for dx = -radius, radius do
            local checkX = centerX + dx
            local checkY = centerY + dy

            if terrain.get(checkX, checkY) == target_terrain then
                return checkX, checkY  -- Found harvestable tile
            end
        end
    end

    return nil  -- No harvestable terrain found
end
```

### Click-to-Tile Conversion
```lua
-- Convert screen click to tile coordinates
function screenClickToTile(mouseX, mouseY, camera)
    -- Convert screen to world coordinates
    local worldPos = GetScreenToWorld2D({x = mouseX, y = mouseY}, camera)

    -- Convert world to tile coordinates
    local tileX = math.floor(worldPos.x / TILE_SIZE)
    local tileY = math.floor(worldPos.y / TILE_SIZE)

    -- Validate tile bounds
    if isValidTile(tileX, tileY, GRID_WIDTH, GRID_HEIGHT) then
        return tileX, tileY
    else
        return nil  -- Click outside valid terrain
    end
end
```

## Configuration Constants

### Standard Grid Configuration
```lua
-- Common grid size constants
TILE_SIZE = 20          -- Pixels per tile
GRID_WIDTH = 20         -- Tiles horizontally
GRID_HEIGHT = 15        -- Tiles vertically

-- Derived values
WORLD_WIDTH = GRID_WIDTH * TILE_SIZE   -- 400 pixels
WORLD_HEIGHT = GRID_HEIGHT * TILE_SIZE  -- 300 pixels
```

### Bounds Checking Constants
```lua
-- Validation helpers
MAX_X = GRID_WIDTH - 1   -- 19 (0-based)
MAX_Y = GRID_HEIGHT - 1  -- 14 (0-based)

function isInBounds(x, y)
    return x >= 0 and x <= MAX_X and y >= 0 and y <= MAX_Y
end
```

## Error Handling Patterns

### Safe Terrain Access
```lua
-- Bounds-safe terrain queries
function getTerrainSafe(x, y, default_type)
    if x < 0 or x >= GRID_WIDTH or y < 0 or y >= GRID_HEIGHT then
        return default_type or terrain.GRASS  -- Safe default
    end
    return terrain.get(x, y)
end

-- Safe terrain modification
function setTerrainSafe(x, y, terrain_type)
    if x >= 0 and x < GRID_WIDTH and y >= 0 and y < GRID_HEIGHT then
        terrain.set(x, y, terrain_type)
        return true  -- Success
    else
        return false  -- Out of bounds
    end
end
```

### Validation Helpers
```lua
-- Input validation for tile operations
function validateTileCoordinates(x, y, operation_name)
    if type(x) ~= "number" or type(y) ~= "number" then
        error(operation_name .. ": coordinates must be numbers")
    end

    if x ~= math.floor(x) or y ~= math.floor(y) then
        error(operation_name .. ": coordinates must be integers")
    end

    if x < 0 or x >= GRID_WIDTH or y < 0 or y >= GRID_HEIGHT then
        error(operation_name .. ": coordinates out of bounds")
    end

    return true
end
```

## Performance Considerations

### Memory Layout Optimization
- **Row-major ordering**: Cache-friendly sequential access
- **Single allocation**: Contiguous memory for entire grid
- **Minimal indirection**: Direct array indexing

### Collision Optimization
- **Run-length encoding**: Reduces physics body count
- **Static bodies**: No dynamic collision updates needed
- **Spatial partitioning**: Consider quad-tree for large grids

### Access Patterns
```lua
-- Efficient: Row-major access (cache-friendly)
for y = 0, GRID_HEIGHT - 1 do
    for x = 0, GRID_WIDTH - 1 do
        process_tile(terrain.get(x, y))
    end
end

-- Inefficient: Column-major access (cache-unfriendly)
for x = 0, GRID_WIDTH - 1 do
    for y = 0, GRID_HEIGHT - 1 do
        process_tile(terrain.get(x, y))  -- Scattered memory access
    end
end
```

## Related Documentation

- World-Mouse Conversion API: `/api_documentation/world_mouse_conversion_api.md`
- Spawner Creature Tracking: `/api_documentation/spawner_creature_tracking_api.md`
- Coordinate System Reference: `/docs/REFERENCE_INDEX.md` (Section 1)
- LDtk Integration: Level editor data loading and auto-rules
- Physics System: Chipmunk physics integration
- Implementation Files:
  - Terrain Module: `/assets/scripts/idle_game/terrain.lua`
  - Physics Integration: Level loading and collider generation
  - Pathfinding: Navigation mesh and A* implementation