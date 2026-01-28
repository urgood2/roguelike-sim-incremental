return function(entity)
    if not ai or not ai.get_blackboard then
        log_debug("WARNING: ai.get_blackboard not available for forager entity: " .. tostring(entity))
        return
    end
    local bb = ai.get_blackboard(entity)
    if not bb then
        log_debug("WARNING: Could not get blackboard for forager entity: " .. tostring(entity))
        return
    end
    bb:set_float("hunger_timer", 0)
    log_debug("Blackboard initialized for forager entity: " .. tostring(entity))
end
