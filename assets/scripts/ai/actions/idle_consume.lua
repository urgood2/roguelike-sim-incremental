return {
    name = "idle_consume",
    cost = 1,
    pre = { hasFood = true },
    post = { hungry = false, hasFood = false },
    watch = {},
    
    start = function(e)
        log_debug("idle_consume: start for entity " .. tostring(e))
        setBlackboardFloat(e, "consume_timer", 0)
    end,
    
    update = function(e, dt)
        local timer = getBlackboardFloat(e, "consume_timer") or 0
        timer = timer + dt
        
        if timer >= 1.0 then
            ai.set_worldstate(e, "hungry", false)
            ai.set_worldstate(e, "hasFood", false)
            ai.bb.set(e, "hunger_timer", 0)
            return ActionResult.SUCCESS
        end
        
        setBlackboardFloat(e, "consume_timer", timer)
        return ActionResult.RUNNING
    end,
    
    finish = function(e)
        log_debug("idle_consume: finish for entity " .. tostring(e))
    end,
    
    abort = function(e, reason)
        log_debug("idle_consume: aborted - " .. tostring(reason))
    end
}
