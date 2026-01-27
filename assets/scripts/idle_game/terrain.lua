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

function terrain.setCurrentGrid(grid)
    terrain._currentGrid = grid
end

function terrain.get(tileX, tileY)
    if not terrain._currentGrid then return nil end
    if tileX < 0 or tileX >= terrain._currentGrid.width then return nil end
    if tileY < 0 or tileY >= terrain._currentGrid.height then return nil end
    return terrain._currentGrid:get(tileX, tileY)
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
