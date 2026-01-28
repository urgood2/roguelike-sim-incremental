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
    
    terrainGrid = terrain.generate(12345, config.GRID_WIDTH, config.GRID_HEIGHT)
    terrain.setCurrentGrid(terrainGrid)
    print(string.format("Terrain generated: %dx%d", terrainGrid.width, terrainGrid.height))
    
    resources.init()
    input_module.set_context("sim_game")
    
    local screenW = globals.screenWidth()
    local screenH = globals.screenHeight()
    local gridPixelW = config.GRID_WIDTH * config.TILE_SIZE
    local gridPixelH = config.GRID_HEIGHT * config.TILE_SIZE
    
    local zoomX = screenW / gridPixelW
    local zoomY = screenH / gridPixelH
    local zoom = math.min(zoomX, zoomY)
    
    local ok, err = pcall(function()
        if camera and camera.Exists and camera.Exists("world_camera") then
            local cam = camera.Get("world_camera")
            if cam.SetActualZoom then cam:SetActualZoom(zoom) end
            if cam.SetVisualZoom then cam:SetVisualZoom(zoom) end
            if cam.SetActualTarget then cam:SetActualTarget(gridPixelW / 2, gridPixelH / 2) end
            if cam.SetActualOffset then cam:SetActualOffset(screenW / 2, screenH / 2) end
            print(string.format("Camera zoom set to %.2f", zoom))
        elseif camera and camera.Create then
            camera.Create("world_camera", gridPixelW / 2, gridPixelH / 2, zoom, 0)
            print(string.format("Created world_camera with zoom %.2f", zoom))
        end
    end)
    if not ok then
        print("Camera setup failed: " .. tostring(err))
    end
    
    spawner.spawnForagers(20)
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
            terrain.set(tileX, tileY, terrain.GRASS)
        elseif tile == terrain.ROCK then
            local level = upgrades.get_level("click_stone")
            local yield = 1 * (1 + level)
            resources.add("stone", yield)
            terrain.set(tileX, tileY, terrain.GRASS)
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
