local Selection = {
    selected_entity = nil,
    _previous_entity = nil
}

local config = require("idle_game.config")

function Selection.update()
    local mousePressed = IsMouseButtonPressed and IsMouseButtonPressed(0)
    if not mousePressed then
        return
    end
    
    local mouse = input.getMousePos()
    local worldX, worldY = mouse.x, mouse.y
    
    if camera and camera.Exists and camera.Exists("world_camera") then
        local cam = camera.Get("world_camera")
        if cam and cam.GetMouseWorld then
            local worldMouse = cam:GetMouseWorld()
            if worldMouse then
                worldX, worldY = worldMouse.x, worldMouse.y
            end
        end
    end
    
    local clicked = Selection.findEntityAtPosition(worldX, worldY)
    
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
    if not ai or not ai.list_goap_entities then
        return nil
    end
    local goap_entities = ai.list_goap_entities() or {}

    for _, entity in ipairs(goap_entities) do
        if registry:valid(entity) and registry:has(entity, Transform) then
            local t = registry:get(entity, Transform)
            local halfSize = config.TILE_SIZE / 2
            
            local entityX = t.actualX or t.visualX or 0
            local entityY = t.actualY or t.visualY or 0
            if x >= entityX - halfSize and x <= entityX + halfSize and
               y >= entityY - halfSize and y <= entityY + halfSize then
                return entity
            end
        end
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
