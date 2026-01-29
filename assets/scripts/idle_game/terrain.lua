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

return terrain
