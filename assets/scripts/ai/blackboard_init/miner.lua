return function(entity)
    if not ai or not ai.get_blackboard then
        log_debug("WARNING: ai.get_blackboard not available for miner entity: " .. tostring(entity))
        return
    end
    local bb = ai.get_blackboard(entity)
    if not bb then
        log_debug("WARNING: Could not get blackboard for miner entity: " .. tostring(entity))
        return
    end

    -- Survival stats (0-100 scale)
    bb:set_float("hunger", 80 + math.random() * 20)  -- Start 80-100 (well-fed)
    bb:set_float("energy", 70 + math.random() * 30)  -- Start 70-100 (rested)
    bb:set_float("age", 0)  -- Ticks up over time

    -- Legacy timer
    bb:set_float("hunger_timer", 0)

    log_debug(string.format("Miner %s initialized: hunger=%.0f, energy=%.0f",
        tostring(entity), bb:get_float("hunger"), bb:get_float("energy")))
end
