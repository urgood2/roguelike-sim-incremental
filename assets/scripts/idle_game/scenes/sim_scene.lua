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
local upgrade_panel = require("idle_game.ui.upgrade_panel")
local upgrades = require("idle_game.upgrades")

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
    local passive_gold_level = upgrades.get_level("passive_gold")
    resources.update(dt, {gold=passive_gold_level})
    
    local tileX, tileY = input_module.handleClick(config)
    if tileX and tileY then
        local tile = terrain.get(tileX, tileY)
        
        if tile == terrain.TREE then
            local level = upgrades.get_level("click_wood")
            local yield = 1 * (1 + level)
            resources.add("wood", yield)
            terrain._currentGrid:set(tileX, tileY, terrain.GRASS)
        elseif tile == terrain.ROCK then
            local level = upgrades.get_level("click_stone")
            local yield = 1 * (1 + level)
            resources.add("stone", yield)
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
    upgrade_panel.draw()
end

return sim_scene
