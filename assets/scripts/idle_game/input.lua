local sim_input = {}

-- Set input context for the sim game
function sim_input.set_context(context)
    -- TODO: This might need to route to C++ input system if context switching is needed
    -- For now, just track context for debugging
    sim_input._context = context
end

-- Frame counter for throttled debug logging
local _handleClick_frame = 0

-- Handle click input for the sim game
-- Returns: tile_x, tile_y if valid click, or nil if out of bounds
function sim_input.handleClick(config)
    _handleClick_frame = _handleClick_frame + 1

    -- Use input.isMousePressed directly - bypasses context system and always works
    -- This is the pattern used by inventory_grid_init.lua and other UI code
    local leftButton = MouseButton and MouseButton.MOUSE_BUTTON_LEFT or 0
    local mousePressed = input and input.isMousePressed and input.isMousePressed(leftButton)

    -- Debug: log periodically to show input state
    if _handleClick_frame % 180 == 1 then
        log_debug(string.format("[input] handleClick frame=%d, mousePressed=%s, hasIsMousePressed=%s",
            _handleClick_frame, tostring(mousePressed), tostring(input and input.isMousePressed ~= nil)))
    end

    if not mousePressed then
        return nil
    end

    log_debug("[input] Click detected via input.isMousePressed!")

    -- Use global input module's getMousePos
    if not input or not input.getMousePos then
        log_debug("[input] ERROR: input.getMousePos not available")
        return nil
    end
    local mouse = input.getMousePos()
    local mouseX = mouse.x
    local mouseY = mouse.y

    -- Convert screen coords to world coords using camera
    local worldX, worldY = mouseX, mouseY
    if camera and camera.Exists and camera.Exists("world_camera") then
        local cam = camera.Get("world_camera")
        if cam and cam.GetMouseWorld then
            local worldMouse = cam:GetMouseWorld()
            if worldMouse then
                worldX, worldY = worldMouse.x, worldMouse.y
            end
        end
    end

    log_debug(string.format("[input] Screen (%.0f,%.0f) -> World (%.0f,%.0f)", mouseX, mouseY, worldX, worldY))

    -- Convert world coords to tile coords
    local tileX = math.floor(worldX / config.TILE_SIZE)
    local tileY = math.floor(worldY / config.TILE_SIZE)

    log_debug(string.format("[input] Tile (%d,%d)", tileX, tileY))

    -- Bounds check
    if tileX >= 0 and tileX < config.GRID_WIDTH and
       tileY >= 0 and tileY < config.GRID_HEIGHT then
        return tileX, tileY
    end

    log_debug("[input] Click out of bounds")
    return nil
end

return sim_input
