local input = {}

-- Set input context for the sim game
function input.set_context(context)
    -- TODO: This might need to route to C++ input system if context switching is needed
    -- For now, just track context for debugging
    input._context = context
end

-- Handle click input for the sim game
-- Returns: tile_x, tile_y if valid click, or nil if out of bounds
function input.handleClick(config)
    if not input.isMousePressed(MouseButton.MOUSE_BUTTON_LEFT) then
        return nil
    end
    
    local mouse = input.getMousePos()
    local mouseX = mouse.x
    local mouseY = mouse.y
    
    -- Convert screen coords to tile coords
    local tileX = math.floor(mouseX / config.TILE_SIZE)
    local tileY = math.floor(mouseY / config.TILE_SIZE)
    
    -- Bounds check
    if tileX >= 0 and tileX < config.GRID_WIDTH and
       tileY >= 0 and tileY < config.GRID_HEIGHT then
        return tileX, tileY
    end
    
    return nil
end

return input
