-- Minimal idle game scene
local sim_scene = {}

local terrain = require("idle_game.terrain")
local terrain_renderer = require("idle_game.terrain_renderer")
local config = require("idle_game.config")
local spawner = require("idle_game.spawner")
local resource_panel = require("idle_game.ui.resource_panel")
local input_module = require("idle_game.input")
local resources = require("idle_game.resources")
local selection = require("idle_game.selection")
local debug_panel = require("idle_game.ui.debug_panel")

-- Store generated terrain
local terrainGrid = nil

function sim_scene.init()
    print("sim_scene.init() called")
    
    -- Generate terrain with fixed seed
    terrainGrid = terrain.generate(12345, config.GRID_WIDTH, config.GRID_HEIGHT)
    terrain.setCurrentGrid(terrainGrid)
    print(string.format("Terrain generated: %dx%d", terrainGrid.width, terrainGrid.height))
    
    -- Initialize resources
    resources.init()
    
    -- Set input context
    input_module.set_context("sim_game")
    
    spawner.spawnForagers(5)
end

function sim_scene.update(dt)
    resources.update(dt, {gold=0})
    
    local tileX, tileY = input_module.handleClick(config)
    if tileX and tileY then
        local tile = terrain.get(tileX, tileY)
        
        if tile == terrain.TREE then
            resources.add("wood", 1)
            terrain._currentGrid:set(tileX, tileY, terrain.GRASS)
        elseif tile == terrain.ROCK then
            resources.add("stone", 1)
            terrain._currentGrid:set(tileX, tileY, terrain.GRASS)
        end
    end
    
    selection.update()
end

function sim_scene.draw()
    -- Draw terrain grid
    if terrainGrid then
        terrain_renderer.draw(terrainGrid)
    end
    
    resource_panel.draw()
    debug_panel.draw()
end

return sim_scene
