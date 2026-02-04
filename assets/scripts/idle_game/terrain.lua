local terrain = {}

local pattern_module = require("external.forma.pattern")
local primitives = require("external.forma.primitives")
local automata = require("external.forma.automata")
local neighbourhood = require("external.forma.neighbourhood")

terrain.GRASS = "GRASS"
terrain.TREE = "TREE"
terrain.ROCK = "ROCK"

local Grid = {}
Grid.__index = Grid

function Grid.new(width, height)
    local self = setmetatable({}, Grid)
    self.width = width
    self.height = height
    self.cells = {}
    
    for y = 0, height - 1 do
        self.cells[y] = {}
        for x = 0, width - 1 do
            self.cells[y][x] = terrain.GRASS
        end
    end
    
    return self
end

function Grid:get(x, y)
    return self.cells[y][x]
end

function Grid:set(x, y, value)
    self.cells[y][x] = value
end

function terrain.generate(seed, width, height)
    local grid = Grid.new(width, height)
    
    math.randomseed(seed)
    
    local domain = primitives.square(width, height)
    
    local target_cell_count = math.floor(width * height * 0.50)
    local pat = domain:sample(target_cell_count)
    
    local moore = neighbourhood.moore()
    
    local rule = automata.rule(moore, "B5678/S45678")
    
    local iterations = 0
    local converged = false
    
    while not converged and iterations < 100 do
        pat, converged = automata.iterate(pat, domain, {rule})
        iterations = iterations + 1
    end
    
    math.randomseed(seed)
    
    for cell in pat:cells() do
        local x, y = cell.x, cell.y
        if math.random() < 0.40 then
            grid:set(x, y, terrain.ROCK)
        else
            grid:set(x, y, terrain.TREE)
        end
    end
    
    return grid
end

terrain._currentGrid = nil

-- Regeneration tracking
terrain._regenAccumulator = 0
terrain._stats = {
    trees_regrown = 0,
    rocks_regrown = 0,
    total_trees = 0,
    total_rocks = 0,
    total_grass = 0
}

function terrain.setCurrentGrid(grid)
    terrain._currentGrid = grid
    terrain._regenAccumulator = 0
    terrain.updateStats()
end

-- Count current tile types
function terrain.updateStats()
    if not terrain._currentGrid then return end

    local trees, rocks, grass = 0, 0, 0
    for y = 0, terrain._currentGrid.height - 1 do
        for x = 0, terrain._currentGrid.width - 1 do
            local tile = terrain._currentGrid:get(x, y)
            if tile == terrain.TREE then trees = trees + 1
            elseif tile == terrain.ROCK then rocks = rocks + 1
            else grass = grass + 1 end
        end
    end

    terrain._stats.total_trees = trees
    terrain._stats.total_rocks = rocks
    terrain._stats.total_grass = grass
end

function terrain.getStats()
    return terrain._stats
end

-- Regeneration update - call every frame
-- base_tree_chance and base_rock_chance are per-second probabilities for each grass tile
function terrain.update(dt, tree_regen_bonus, rock_regen_bonus)
    if not terrain._currentGrid then return end

    tree_regen_bonus = tree_regen_bonus or 0
    rock_regen_bonus = rock_regen_bonus or 0

    -- Base regen: 0.5% per second per grass tile, boosted by upgrades
    local base_tree_chance = 0.005 * (1 + tree_regen_bonus)
    local base_rock_chance = 0.003 * (1 + rock_regen_bonus)

    -- Accumulate time and process in chunks to avoid too many random calls
    terrain._regenAccumulator = terrain._regenAccumulator + dt

    -- Process every 0.5 seconds for efficiency
    if terrain._regenAccumulator < 0.5 then return end

    local elapsed = terrain._regenAccumulator
    terrain._regenAccumulator = 0

    local trees_regrown = 0
    local rocks_regrown = 0

    for y = 0, terrain._currentGrid.height - 1 do
        for x = 0, terrain._currentGrid.width - 1 do
            if terrain._currentGrid:get(x, y) == terrain.GRASS then
                -- Tree regrowth - more likely near existing trees
                local near_tree = terrain.isNearTileType(x, y, terrain.TREE, 2)
                local tree_chance = base_tree_chance * elapsed * (near_tree and 3 or 1)

                if math.random() < tree_chance then
                    terrain._currentGrid:set(x, y, terrain.TREE)
                    trees_regrown = trees_regrown + 1
                elseif math.random() < base_rock_chance * elapsed then
                    -- Rock regrowth - less common
                    terrain._currentGrid:set(x, y, terrain.ROCK)
                    rocks_regrown = rocks_regrown + 1
                end
            end
        end
    end

    if trees_regrown > 0 or rocks_regrown > 0 then
        terrain._stats.trees_regrown = terrain._stats.trees_regrown + trees_regrown
        terrain._stats.rocks_regrown = terrain._stats.rocks_regrown + rocks_regrown
        terrain.updateStats()
    end
end

function terrain.get(tileX, tileY)
    if not terrain._currentGrid then return nil end
    if tileX < 0 or tileX >= terrain._currentGrid.width then return nil end
    if tileY < 0 or tileY >= terrain._currentGrid.height then return nil end
    return terrain._currentGrid:get(tileX, tileY)
end

function terrain.set(tileX, tileY, value)
    if not terrain._currentGrid then return false end
    if tileX < 0 or tileX >= terrain._currentGrid.width then return false end
    if tileY < 0 or tileY >= terrain._currentGrid.height then return false end
    terrain._currentGrid:set(tileX, tileY, value)
    return true
end

function terrain.isNearTileType(tileX, tileY, tileType, radius)
    for dy = -radius, radius do
        for dx = -radius, radius do
            local tile = terrain.get(tileX + dx, tileY + dy)
            if tile == tileType then
                return true
            end
        end
    end
    return false
end

-- Find nearest empty tile (GRASS) within Manhattan radius
-- Returns coordinates of nearest empty tile or nil if none found
function terrain.findNearestEmptyTile(tileX, tileY, maxRadius)
    if not tileX or not tileY then
        return nil
    end

    maxRadius = maxRadius or 10  -- Default radius 10 as specified in task

    -- Search in expanding Manhattan distance rings
    for manhattanDist = 0, maxRadius do
        -- Check all positions at exactly this Manhattan distance
        for dy = -manhattanDist, manhattanDist do
            local remainingDist = manhattanDist - math.abs(dy)

            -- For this dy, dx can be -remainingDist or +remainingDist
            local positions = {}
            if remainingDist == 0 then
                -- Only one position: dx = 0
                table.insert(positions, {dx = 0, dy = dy})
            else
                -- Two positions: dx = -remainingDist and dx = +remainingDist
                table.insert(positions, {dx = -remainingDist, dy = dy})
                table.insert(positions, {dx = remainingDist, dy = dy})
            end

            -- Check each position at this Manhattan distance
            for _, pos in ipairs(positions) do
                local checkX = tileX + pos.dx
                local checkY = tileY + pos.dy

                -- Verify this position is actually at the correct Manhattan distance
                local actualDist = math.abs(pos.dx) + math.abs(pos.dy)
                if actualDist == manhattanDist then
                    local tile = terrain.get(checkX, checkY)
                    if tile == terrain.GRASS then
                        return checkX, checkY  -- Found nearest empty tile
                    end
                end
            end
        end
    end

    return nil  -- No empty tile found within radius
end

-- Ground items system
terrain._ground_items = {}
terrain._next_item_id = 1

-- Valid item kinds for validation
local VALID_ITEM_KINDS = {
    wood = true,
    stone = true,
    food = true,
    gold = true
}

-- Drop item function - add ground item with monotonic id, validate kind/amount
function terrain.drop_item(x, y, kind, amount)
    -- Validate parameters
    if not x or not y or not kind or not amount then
        error("terrain.drop_item: x, y, kind, amount required")
    end

    -- Validate coordinates
    if not terrain._currentGrid then
        error("terrain.drop_item: no current grid set")
    end

    if x < 0 or x >= terrain._currentGrid.width or y < 0 or y >= terrain._currentGrid.height then
        return nil, "Invalid coordinates"
    end

    -- Validate item kind
    if not VALID_ITEM_KINDS[kind] then
        return nil, "Invalid item kind: " .. tostring(kind)
    end

    -- Validate amount
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return nil, "Invalid amount: must be positive number"
    end

    -- Create ground item with monotonic ID
    local item = {
        id = terrain._next_item_id,
        x = x,
        y = y,
        kind = kind,
        amount = amount,
        created_at = os.time()
    }

    -- Increment monotonic ID counter
    terrain._next_item_id = terrain._next_item_id + 1

    -- Add to ground items table
    terrain._ground_items[item.id] = item

    print(string.format("[TERRAIN] Dropped item #%d: %s x%d at (%d,%d)",
          item.id, kind, amount, x, y))

    return item.id
end

-- Get all ground items
function terrain.get_ground_items()
    return terrain._ground_items
end

-- Get ground items at specific location
function terrain.get_items_at(x, y)
    local items_at_position = {}

    for id, item in pairs(terrain._ground_items) do
        if item.x == x and item.y == y then
            table.insert(items_at_position, item)
        end
    end

    return items_at_position
end

-- Find nearest ground item by Manhattan distance; optional kind filter
-- Ties are broken by lowest item id
function terrain.find_nearest_item(x, y, kind)
    if x == nil or y == nil then
        return nil
    end

    local nearest_item = nil
    local nearest_distance = math.huge
    local nearest_id = math.huge

    for id, item in pairs(terrain._ground_items) do
        if not kind or item.kind == kind then
            local distance = math.abs(item.x - x) + math.abs(item.y - y)
            local item_id = item.id or id
            if distance < nearest_distance or (distance == nearest_distance and item_id < nearest_id) then
                nearest_distance = distance
                nearest_id = item_id
                nearest_item = item
            end
        end
    end

    if not nearest_item then
        return nil
    end

    return nearest_item, nearest_distance
end

-- Pick up item by ID - remove and return item data
function terrain.pickup_item(item_id)
    -- Validate parameters
    if not item_id then
        return nil, "Item ID required"
    end

    -- Find the item
    local item = terrain._ground_items[item_id]
    if not item then
        return nil, "Item not found"
    end

    -- Remove from ground items table
    terrain._ground_items[item_id] = nil

    print(string.format("[TERRAIN] Picked up item #%d: %s x%d from (%d,%d)",
          item.id, item.kind, item.amount, item.x, item.y))

    -- Return the item data
    return item
end

-- Clear all ground items (called on setCurrentGrid)
function terrain.clear_ground_items()
    local count = 0
    for _ in pairs(terrain._ground_items) do
        count = count + 1
    end

    terrain._ground_items = {}
    terrain._next_item_id = 1

    if count > 0 then
        print(string.format("[TERRAIN] Cleared %d ground items", count))
    end
end

-- Update setCurrentGrid to clear ground items
local original_setCurrentGrid = terrain.setCurrentGrid
function terrain.setCurrentGrid(grid)
    original_setCurrentGrid(grid)
    terrain.clear_ground_items()
    terrain.clear_structures()
end

-- Structures system
terrain._structures = {}
terrain._next_structure_id = 1

-- Valid structure types for validation
local VALID_STRUCTURE_TYPES = {
    farm = true,
    mine = true,
    house = true,
    workshop = true,
    storage = true
}

-- Place structure function - validate placement and add to structures list
function terrain.place_structure(x, y, structure_type)
    -- Use the dedicated validation function
    local valid, error_message = terrain.validate_structure_placement(x, y, structure_type)
    if not valid then
        return false, error_message
    end

    -- Create structure with unique ID
    local structure = {
        id = terrain._next_structure_id,
        x = x,
        y = y,
        type = structure_type,
        created_at = os.time()
    }

    -- Increment ID counter
    terrain._next_structure_id = terrain._next_structure_id + 1

    -- Add to structures table
    terrain._structures[structure.id] = structure

    print(string.format("[TERRAIN] Placed structure #%d: %s at (%d,%d)",
          structure.id, structure_type, x, y))

    return true, structure.id
end

-- Get all structures
function terrain.get_structures()
    local copy = {}
    for id, structure in pairs(terrain._structures) do
        copy[id] = {
            id = structure.id,
            x = structure.x,
            y = structure.y,
            type = structure.type,
            created_at = structure.created_at
        }
    end
    return copy
end

-- Get structure at specific location
function terrain.get_structure_at(x, y)
    for _, structure in pairs(terrain._structures) do
        if structure.x == x and structure.y == y then
            return structure
        end
    end
    return nil
end

-- Remove structure by ID
function terrain.remove_structure(structure_id)
    if terrain._structures[structure_id] then
        local structure = terrain._structures[structure_id]
        terrain._structures[structure_id] = nil
        print(string.format("[TERRAIN] Removed structure #%d: %s at (%d,%d)",
              structure.id, structure.type, structure.x, structure.y))
        return true
    end
    return false, "Structure not found"
end

-- Clear all structures (called on setCurrentGrid)
function terrain.clear_structures()
    local count = 0
    for _ in pairs(terrain._structures) do
        count = count + 1
    end

    terrain._structures = {}
    terrain._next_structure_id = 1

    if count > 0 then
        print(string.format("[TERRAIN] Cleared %d structures", count))
    end
end

-- Validate structure placement without actually placing
-- Returns true, nil if valid; false, error_message if invalid
function terrain.validate_structure_placement(x, y, structure_type)
    -- Validate parameters
    if not x or not y or not structure_type then
        return false, "x, y, and structure_type required"
    end

    -- Validate coordinates
    if not terrain._currentGrid then
        return false, "No current grid set"
    end

    -- Check within bounds
    if x < 0 or x >= terrain._currentGrid.width or y < 0 or y >= terrain._currentGrid.height then
        return false, "Invalid coordinates: out of bounds"
    end

    -- Validate structure type (valid sprite)
    if not VALID_STRUCTURE_TYPES[structure_type] then
        return false, "Invalid structure type: " .. tostring(structure_type)
    end

    -- Check if position is empty (not occupied by existing structure)
    for _, structure in pairs(terrain._structures) do
        if structure.x == x and structure.y == y then
            return false, "Position already occupied by structure"
        end
    end

    -- Check if terrain is walkable (grass only for structures)
    local tile = terrain.get(x, y)
    if tile ~= terrain.GRASS then
        return false, "Structures can only be placed on grass terrain (walkable)"
    end

    return true, nil
end

return terrain
