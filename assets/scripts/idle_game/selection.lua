local Selection = {
    selected_entity = nil,
    _previous_entity = nil
}

local config = require("idle_game.config")

function Selection.update()
    if not input.isMousePressed(MouseButton.MOUSE_BUTTON_LEFT) then
        return
    end
    
    local mouse = input.getMousePos()
    local clicked = Selection.findEntityAtPosition(mouse.x, mouse.y)
    
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
    local goap_entities = ai.list_goap_entities()
    
    for _, entity in ipairs(goap_entities) do
        if registry:valid(entity) and registry:has(entity, Transform) then
            local t = registry:get(entity, Transform)
            local halfSize = config.TILE_SIZE / 2
            
            if x >= t.visualX - halfSize and x <= t.visualX + halfSize and
               y >= t.visualY - halfSize and y <= t.visualY + halfSize then
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
