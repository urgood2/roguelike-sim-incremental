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
local ui_layout = require("idle_game.ui.ui_layout")
local ascii_resource_panel = require("idle_game.ui.ascii_resource_panel")
local ascii_upgrade_panel = require("idle_game.ui.ascii_upgrade_panel")
local toast_renderer = require("idle_game.ui.toast_renderer")
local toast_queue = require("idle_game.ui.toast_queue")
local upgrades = require("idle_game.upgrades")
local popup = require("core.popup")
local achievements = require("idle_game.achievements")

-- Persistence module imports
local achievements_persistence = require("idle_game.achievements_persistence")
local terrain_persistence = require("idle_game.terrain_persistence")

-- Achievement system imports
local achievement_listener = require("idle_game.achievement_listener")

-- Store generated terrain
local terrainGrid = nil

function sim_scene.init()
    print("sim_scene.init() called")
    
    terrainGrid = terrain.generate(12345, config.GRID_WIDTH, config.GRID_HEIGHT)
    terrain.setCurrentGrid(terrainGrid)
    print(string.format("Terrain generated: %dx%d", terrainGrid.width, terrainGrid.height))
    
    resources.init()

    -- Initialize aligned screen dimensions
    local screenW = globals.screenWidth()
    local screenH = globals.screenHeight()
    local aligned = ui_layout.aligned_screen(config.TILE_SIZE, screenW, screenH)
    sim_scene.SCREEN_W = aligned.width
    sim_scene.SCREEN_H = aligned.height
    sim_scene._screen_w = aligned.width
    sim_scene._screen_h = aligned.height
    sim_scene._tile_size = config.TILE_SIZE

    -- Initialize UI panels
    ascii_resource_panel.init(config.TILE_SIZE, sim_scene.SCREEN_W, sim_scene.SCREEN_H)
    ascii_upgrade_panel.init(config.TILE_SIZE, sim_scene.SCREEN_W, sim_scene.SCREEN_H)

    -- Initialize toast queue
    toast_queue.init()

    -- Initialize achievement listener
    achievement_listener.init(toast_queue)

    -- Note: We use input.isMousePressed directly in input.lua
    -- This bypasses the context system and is more reliable
    input_module.set_context("sim_game")
    
    local gridPixelW = config.GRID_WIDTH * config.TILE_SIZE   -- 600
    local gridPixelH = config.GRID_HEIGHT * config.TILE_SIZE  -- 400

    -- Get actual window size and calculate zoom to fit grid with sidebar reservation
    local screenW = globals.screenWidth()
    local screenH = globals.screenHeight()
    local sidebar_w = config.TILE_SIZE * 12  -- UI sidebar width
    local world_view_w = screenW - sidebar_w
    local zoomX = world_view_w / config.VIRTUAL_WIDTH  -- Reserve space for sidebar
    local zoomY = screenH / config.VIRTUAL_HEIGHT
    local zoom = math.min(zoomX, zoomY)  -- Fit grid to world view area

    -- Store zoom for coordinate conversion
    sim_scene._zoom = zoom
    sim_scene._gridPixelW = gridPixelW
    sim_scene._gridPixelH = gridPixelH
    sim_scene._ui_sidebar_w = sidebar_w
    sim_scene._world_view_w = world_view_w

    local ok, err = pcall(function()
        if camera and camera.Exists and camera.Exists("world_camera") then
            local cam = camera.Get("world_camera")
            if cam.SetActualZoom then cam:SetActualZoom(zoom) end
            if cam.SetVisualZoom then cam:SetVisualZoom(zoom) end
            -- Center camera on grid center
            if cam.SetActualTarget then cam:SetActualTarget(gridPixelW / 2, gridPixelH / 2) end
            -- Offset to center within left region (world view area)
            local sidebar_w = config.TILE_SIZE * 12  -- UI sidebar width
            local world_view_w = sim_scene.SCREEN_W - sidebar_w
            if cam.SetActualOffset then cam:SetActualOffset(world_view_w / 2, sim_scene.SCREEN_H / 2) end
            print(string.format("Camera: zoom=%.2f (fit grid %dx%d to window %dx%d)", zoom, gridPixelW, gridPixelH, screenW, screenH))
        elseif camera and camera.Create then
            camera.Create("world_camera", gridPixelW / 2, gridPixelH / 2, zoom, 0)
            print(string.format("Created world_camera: zoom=%.2f, center=(%d,%d)", zoom, gridPixelW/2, gridPixelH/2))
        end
    end)
    if not ok then
        print("Camera setup failed: " .. tostring(err))
    end
    
    -- Mixed spawn: 12 foragers, 3 miners, 3 lumberjacks, 1 collector, 1 builder (total: 20)
    spawner.spawnForagers(12)
    spawner.spawnLumberjacks(3)
    -- TODO: Add spawner.spawnMiners(3) when miners are implemented
    -- TODO: Add spawner.spawnCollectors(1) when collectors are implemented
    -- TODO: Add spawner.spawnBuilders(1) when builders are implemented
    print("Mixed spawn: 12 foragers + 3 lumberjacks (miners/collectors/builders pending implementation)")
end

-- Frame counter for throttled debug logging
local _update_frame = 0

function sim_scene.update(dt)
    _update_frame = _update_frame + 1

    -- Update achievement listener (handles achievements.update and achievement evaluation)
    achievement_listener.update(dt)

    -- Resize detection: recompute screen dimensions and camera if window size changed
    local currentW = globals.screenWidth()
    local currentH = globals.screenHeight()
    if currentW ~= sim_scene.SCREEN_W or currentH ~= sim_scene.SCREEN_H then
        print(string.format("[sim_scene] Screen resize detected: %dx%d -> %dx%d",
              sim_scene.SCREEN_W or 0, sim_scene.SCREEN_H or 0, currentW, currentH))

        -- Recompute aligned screen dimensions
        local aligned = ui_layout.aligned_screen(config.TILE_SIZE, currentW, currentH)
        sim_scene.SCREEN_W = aligned.width
        sim_scene.SCREEN_H = aligned.height
        sim_scene._screen_w = aligned.width
        sim_scene._screen_h = aligned.height
        sim_scene._tile_size = config.TILE_SIZE

        -- Reinitialize UI panels with new dimensions
        ascii_resource_panel.init(config.TILE_SIZE, sim_scene.SCREEN_W, sim_scene.SCREEN_H)
        ascii_upgrade_panel.init(config.TILE_SIZE, sim_scene.SCREEN_W, sim_scene.SCREEN_H)

        -- Recalculate camera zoom and positioning for grid fitting with sidebar reservation
        local gridPixelW = config.GRID_WIDTH * config.TILE_SIZE
        local gridPixelH = config.GRID_HEIGHT * config.TILE_SIZE
        local sidebar_w = config.TILE_SIZE * 12  -- UI sidebar width
        local world_view_w = sim_scene.SCREEN_W - sidebar_w
        local zoomX = world_view_w / config.VIRTUAL_WIDTH  -- Reserve space for sidebar
        local zoomY = sim_scene.SCREEN_H / config.VIRTUAL_HEIGHT
        local zoom = math.min(zoomX, zoomY)

        sim_scene._zoom = zoom
        sim_scene._gridPixelW = gridPixelW
        sim_scene._gridPixelH = gridPixelH
        sim_scene._ui_sidebar_w = sidebar_w
        sim_scene._world_view_w = world_view_w

        -- Update camera with new zoom and positioning
        local ok, err = pcall(function()
            if camera and camera.Exists and camera.Exists("world_camera") then
                local cam = camera.Get("world_camera")
                if cam.SetActualZoom then cam:SetActualZoom(zoom) end
                if cam.SetVisualZoom then cam:SetVisualZoom(zoom) end
                if cam.SetActualTarget then cam:SetActualTarget(gridPixelW / 2, gridPixelH / 2) end
                -- Offset to center within left region (world view area)
                local sidebar_w = config.TILE_SIZE * 12  -- UI sidebar width
                local world_view_w = sim_scene.SCREEN_W - sidebar_w
                if cam.SetActualOffset then cam:SetActualOffset(world_view_w / 2, sim_scene.SCREEN_H / 2) end
            end
        end)
        if not ok then
            print("Camera resize update failed: " .. tostring(err))
        end
    end

    -- Passive resource generation based on upgrades
    local passive_gold_level = upgrades.get_level("passive_gold")
    resources.update(dt, {gold=passive_gold_level})

    -- Update resource panel rate calculation
    ascii_resource_panel.update(dt, resources)

    -- Update upgrade panel state with current upgrade data and resources
    ascii_upgrade_panel.update(dt, upgrades, resources)

    -- Update toast queue (auto-dismiss expired toasts)
    toast_queue.update(dt)

    -- Update toast renderer (handles toast timing and animations)
    toast_renderer.update(dt)

    -- Terrain regeneration (trees and rocks regrow over time)
    local tree_regen_bonus = upgrades.get_level("tree_regrowth") * 0.2  -- 20% per level
    local rock_regen_bonus = upgrades.get_level("rock_regrowth") * 0.2
    terrain.update(dt, tree_regen_bonus, rock_regen_bonus)

    -- Process deferred entity destructions (after AI tick completes)
    spawner.processPendingDestructions()

    -- Handle UI input first - clicks and wheel scrolling on panels
    local click_consumed = false

    -- Handle mouse wheel input for scrolling
    if input and input.getMouseWheel and input.getMousePos then
        local wheel_delta = input.getMouseWheel()
        if wheel_delta ~= 0 then
            local mouse = input.getMousePos()
            local mouse_x, mouse_y = mouse.x, mouse.y

            -- Check if mouse is over upgrade panel for wheel scrolling
            if ascii_upgrade_panel.hit_test(mouse_x, mouse_y) then
                ascii_upgrade_panel.scroll_by_wheel(wheel_delta)
                log_debug(string.format("[sim_scene] Wheel scroll (%.1f) handled by upgrade panel at (%d, %d)",
                          wheel_delta, mouse_x, mouse_y))
            end
        end
    end

    -- Check for mouse click using same pattern as input_module
    local leftButton = MouseButton and MouseButton.MOUSE_BUTTON_LEFT or 0
    local mousePressed = input and input.isMousePressed and input.isMousePressed(leftButton)

    if mousePressed and input and input.getMousePos then
        local mouse = input.getMousePos()
        local click_x, click_y = mouse.x, mouse.y

        -- Test resource panel hit
        local resource_hit = ascii_resource_panel.hit_test(click_x, click_y)
        if resource_hit and resource_hit.consumed then
            click_consumed = true
            log_debug(string.format("[sim_scene] Click consumed by resource panel at (%d, %d)", click_x, click_y))
        end

        -- Test upgrade panel hit (only if not already consumed)
        if not click_consumed and ascii_upgrade_panel.hit_test(click_x, click_y) then
            click_consumed = true

            -- Handle upgrade panel click (purchase if applicable)
            local handled = ascii_upgrade_panel.handle_click(click_x, click_y, upgrades, resources)
            if handled then
                log_debug(string.format("[sim_scene] Click consumed by upgrade panel at (%d, %d)", click_x, click_y))
            end
        end
    end

    -- Only process terrain clicks if UI didn't consume the click
    local tileX, tileY = nil, nil
    if not click_consumed then
        tileX, tileY = input_module.handleClick(config)
    end

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

    ascii_resource_panel.draw()
    ascii_upgrade_panel.draw()  -- ASCII upgrade panel with purchase API
    toast_renderer.draw()  -- Toast notifications
    debug_panel.draw()
end

return sim_scene
