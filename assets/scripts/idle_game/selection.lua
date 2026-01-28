local Selection = {
    selected_entity = nil,
    _previous_entity = nil
}

local config = require("idle_game.config")

--- Select an entity (or nil to deselect)
function Selection.selectEntity(entity)
    if Selection._previous_entity and Selection._previous_entity ~= entity then
        Selection._removeOutline(Selection._previous_entity)
    end

    Selection.selected_entity = entity
    Selection._previous_entity = entity

    if entity then
        Selection._addOutline(entity)
        log_debug("[Selection] Entity selected: " .. tostring(entity))
    else
        log_debug("[Selection] Selection cleared")
    end
end

function Selection.update()
    -- Note: This function is NOT called from sim_scene - click handling is done directly in sim_scene.update()
    -- If you want to use this standalone, use input.action_down instead of IsMouseButtonPressed
    -- (IsMouseButtonPressed is NOT exposed to Lua)

    if not input or not input.action_down then
        return
    end

    local mousePressed = input.action_down("mouse_click")
    if not mousePressed then
        return
    end

    log_debug("[Selection] Mouse button pressed detected via input.action_down!")

    if not input or not input.getMousePos then
        log_debug("[Selection] ERROR: input.getMousePos not available")
        return
    end

    -- Get screen mouse position
    local mouse = input.getMousePos()
    local screenX, screenY = mouse.x, mouse.y

    -- Convert screen coords to world coords using camera
    local worldX, worldY = screenX, screenY
    if camera and camera.Exists and camera.Exists("world_camera") then
        local cam = camera.Get("world_camera")
        if cam and cam.GetMouseWorld then
            local worldMouse = cam:GetMouseWorld()
            if worldMouse then
                worldX, worldY = worldMouse.x, worldMouse.y
            end
        end
    end

    log_debug(string.format("[Selection] Screen: (%.1f, %.1f) -> World: (%.1f, %.1f)", screenX, screenY, worldX, worldY))

    local clicked = Selection.findEntityAtPosition(worldX, worldY)
    if clicked then
        log_debug("[Selection] Selected entity: " .. tostring(clicked))
    else
        log_debug("[Selection] No entity at click position")
    end

    if Selection._previous_entity and Selection._previous_entity ~= clicked then
        Selection._removeOutline(Selection._previous_entity)
    end

    Selection.selected_entity = clicked
    Selection._previous_entity = clicked

    if clicked then
        Selection._addOutline(clicked)
    end
end

function Selection.findEntityAtPosition(x, y)
    if not ai then
        log_debug("[Selection] ERROR: ai module not available")
        return nil
    end
    if not ai.list_goap_entities then
        log_debug("[Selection] ERROR: ai.list_goap_entities not available")
        return nil
    end
    local goap_entities = ai.list_goap_entities() or {}
    log_debug(string.format("[Selection] Searching %d GOAP entities near click (%.1f, %.1f)", #goap_entities, x, y))

    local closest_entity = nil
    local closest_dist = math.huge

    for i, entity in ipairs(goap_entities) do
        if registry:valid(entity) and registry:has(entity, Transform) then
            local t = registry:get(entity, Transform)
            local entityX = t.actualX or t.visualX or 0
            local entityY = t.actualY or t.visualY or 0
            local dist = math.sqrt((x - entityX)^2 + (y - entityY)^2)

            -- Log first few entities for debugging
            if i <= 3 then
                log_debug(string.format("[Selection] Entity %d: %s at (%.0f, %.0f), dist=%.1f",
                    i, tostring(entity), entityX, entityY, dist))
            end

            if dist < closest_dist then
                closest_dist = dist
                closest_entity = entity
            end
        end
    end

    -- Use a generous hitbox - 1.5x tile size
    local hitRadius = config.TILE_SIZE * 1.5
    if closest_entity and closest_dist < hitRadius then
        log_debug(string.format("[Selection] MATCH: entity %s, dist=%.1f < %.1f",
            tostring(closest_entity), closest_dist, hitRadius))
        return closest_entity
    else
        log_debug(string.format("[Selection] NO MATCH: closest dist=%.1f, hitRadius=%.1f",
            closest_dist, hitRadius))
    end

    return nil
end

function Selection._addOutline(entity)
    if not registry:has(entity, shader_pipeline.ShaderPipelineComponent) then
        registry:emplace(entity, shader_pipeline.ShaderPipelineComponent)
    end
    local pipeline = registry:get(entity, shader_pipeline.ShaderPipelineComponent)
    pipeline:addPass("efficient_pixel_outline")
    
    if not registry:has(entity, shaders.ShaderUniformComponent) then
        registry:emplace(entity, shaders.ShaderUniformComponent)
    end
    local uniforms = registry:get(entity, shaders.ShaderUniformComponent)
    
    uniforms:set("efficient_pixel_outline", "outlineColor", Color(255, 255, 0, 255))
    uniforms:set("efficient_pixel_outline", "thickness", 2.0)
    uniforms:set("efficient_pixel_outline", "outlineType", 2)
end

function Selection._removeOutline(entity)
    if not registry:valid(entity) then return end
    if not registry:has(entity, shader_pipeline.ShaderPipelineComponent) then return end
    
    local pipeline = registry:get(entity, shader_pipeline.ShaderPipelineComponent)
    pipeline:removePass("efficient_pixel_outline")
end

return Selection
