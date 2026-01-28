local sim_input = {}

-- Set input context for the sim game
function sim_input.set_context(context)
    -- TODO: This might need to route to C++ input system if context switching is needed
    -- For now, just track context for debugging
    sim_input._context = context
end

-- Handle click input for the sim game
-- Returns: tile_x, tile_y if valid click, or nil if out of bounds
function sim_input.handleClick(config)
    -- Use global IsMouseButtonPressed (Raylib) or fallback
    local mousePressed = false
    if IsMouseButtonPressed then
        mousePressed = IsMouseButtonPressed(0)  -- 0 = left mouse button
    end
    
    if not mousePressed then
        return nil
    end

    -- Use global input module's getMousePos
    if not input or not input.getMousePos then
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

return sim_input
