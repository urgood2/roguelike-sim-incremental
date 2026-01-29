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
local popup = require("core.popup")

-- Store generated terrain
local terrainGrid = nil

function sim_scene.init()
    print("sim_scene.init() called")
    
    terrainGrid = terrain.generate(12345, config.GRID_WIDTH, config.GRID_HEIGHT)
    terrain.setCurrentGrid(terrainGrid)
    print(string.format("Terrain generated: %dx%d", terrainGrid.width, terrainGrid.height))
    
    resources.init()

    -- Note: We use input.isMousePressed directly in input.lua
    -- This bypasses the context system and is more reliable
    input_module.set_context("sim_game")
    
    local gridPixelW = config.GRID_WIDTH * config.TILE_SIZE   -- 600
    local gridPixelH = config.GRID_HEIGHT * config.TILE_SIZE  -- 400

    -- Get actual window size and calculate zoom to fit grid
    local screenW = globals.screenWidth()
    local screenH = globals.screenHeight()
    local zoomX = screenW / gridPixelW
    local zoomY = screenH / gridPixelH
    local zoom = math.min(zoomX, zoomY)  -- Fit grid to window

    -- Store zoom for coordinate conversion
    sim_scene._zoom = zoom
    sim_scene._gridPixelW = gridPixelW
    sim_scene._gridPixelH = gridPixelH

    local ok, err = pcall(function()
        if camera and camera.Exists and camera.Exists("world_camera") then
            local cam = camera.Get("world_camera")
            if cam.SetActualZoom then cam:SetActualZoom(zoom) end
            if cam.SetVisualZoom then cam:SetVisualZoom(zoom) end
            -- Center camera on grid center
            if cam.SetActualTarget then cam:SetActualTarget(gridPixelW / 2, gridPixelH / 2) end
            -- Offset to screen center
            if cam.SetActualOffset then cam:SetActualOffset(screenW / 2, screenH / 2) end
            print(string.format("Camera: zoom=%.2f (fit grid %dx%d to window %dx%d)", zoom, gridPixelW, gridPixelH, screenW, screenH))
        elseif camera and camera.Create then
            camera.Create("world_camera", gridPixelW / 2, gridPixelH / 2, zoom, 0)
            print(string.format("Created world_camera: zoom=%.2f, center=(%d,%d)", zoom, gridPixelW/2, gridPixelH/2))
        end
    end)
    if not ok then
        print("Camera setup failed: " .. tostring(err))
    end
    
    spawner.spawnForagers(20)
end

-- Frame counter for throttled debug logging
local _update_frame = 0

function sim_scene.update(dt)
    _update_frame = _update_frame + 1

    -- Passive resource generation based on upgrades
    local passive_gold_level = upgrades.get_level("passive_gold")
    resources.update(dt, {gold=passive_gold_level})

    -- Terrain regeneration (trees and rocks regrow over time)
    local tree_regen_bonus = upgrades.get_level("tree_regrowth") * 0.2  -- 20% per level
    local rock_regen_bonus = upgrades.get_level("rock_regrowth") * 0.2
    terrain.update(dt, tree_regen_bonus, rock_regen_bonus)

    -- Process deferred entity destructions (after AI tick completes)
    spawner.processPendingDestructions()

    local tileX, tileY = input_module.handleClick(config)
    if tileX and tileY then
        log_debug(string.format("[sim_scene] Click at tile (%d, %d)", tileX, tileY))
        local tile = terrain.get(tileX, tileY)
        local worldX = tileX * config.TILE_SIZE + config.TILE_SIZE / 2
        local worldY = tileY * config.TILE_SIZE + config.TILE_SIZE / 2
        log_debug(string.format("[sim_scene] World pos: (%.1f, %.1f), tile type: %s", worldX, worldY, tostring(tile)))

        -- First, check if there's an entity at this position (regardless of tile type)
        local entity = selection.findEntityAtPosition(worldX, worldY)
        if entity then
            log_debug("[sim_scene] Found entity: " .. tostring(entity))
            selection.selectEntity(entity)
        elseif tile == terrain.TREE then
            -- No entity - harvest tree
            local level = upgrades.get_level("click_wood")
            local yield = 1 * (1 + level)
            resources.add("wood", yield)
            terrain.set(tileX, tileY, terrain.GRASS)
            popup.at(worldX, worldY, "+" .. yield .. " Wood", { color = "gold" })
            if playSoundEffect then playSoundEffect("effects", "button-click") end
            selection.selectEntity(nil)
        elseif tile == terrain.ROCK then
            -- No entity - harvest rock
            local level = upgrades.get_level("click_stone")
            local yield = 1 * (1 + level)
            resources.add("stone", yield)
            terrain.set(tileX, tileY, terrain.GRASS)
            popup.at(worldX, worldY, "+" .. yield .. " Stone", { color = "white" })
            if playSoundEffect then playSoundEffect("effects", "button-click") end
            selection.selectEntity(nil)
        else
            -- Clicked on grass with no entity
            selection.selectEntity(nil)
        end
    end
end

function sim_scene.draw()
    -- Draw terrain grid
    if terrainGrid then
        terrain_renderer.draw(terrainGrid)
    end

    -- Draw corpses (gray on pink, above terrain)
    spawner.drawCorpses()

    resource_panel.draw()
    debug_panel.draw()
    upgrade_panel.draw()
end

return sim_scene
