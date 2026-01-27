-- Minimal idle game scene
local sim_scene = {}

local terrain = require("idle_game.terrain")
local terrain_renderer = require("idle_game.terrain_renderer")
local config = require("idle_game.config")
local spawner = require("idle_game.spawner")

-- Store generated terrain
local terrainGrid = nil

function sim_scene.init()
    print("sim_scene.init() called")
    
    -- Generate terrain with fixed seed
    terrainGrid = terrain.generate(12345, config.GRID_WIDTH, config.GRID_HEIGHT)
    terrain.setCurrentGrid(terrainGrid)
    print(string.format("Terrain generated: %dx%d", terrainGrid.width, terrainGrid.height))
    
    spawner.spawnForagers(5)
end

function sim_scene.update(dt)
    -- Will add entity updates here later
end

function sim_scene.draw()
    -- Draw terrain grid
    if terrainGrid then
        terrain_renderer.draw(terrainGrid)
    end
end

return sim_scene
