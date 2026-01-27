return {
    name = "idle_forage",
    cost = 2,
    pre = { nearTree = true, hungry = true },
    post = { hasFood = true },
    watch = { nearTree = true },
    
    start = function(e)
        log_debug("idle_forage: start for entity " .. tostring(e))
        setBlackboardFloat(e, "forage_timer", 0)
    end,
    
    update = function(e, dt)
        local timer = getBlackboardFloat(e, "forage_timer") or 0
        timer = timer + dt
        
        if timer >= 2.0 then
            ai.set_worldstate(e, "hasFood", true)
            ai.set_worldstate(e, "hungry", false)
            return ActionResult.SUCCESS
        end
        
        setBlackboardFloat(e, "forage_timer", timer)
        return ActionResult.RUNNING
    end,
    
    finish = function(e)
        log_debug("idle_forage: finish for entity " .. tostring(e))
    end,
    
    abort = function(e, reason)
        log_debug("idle_forage: aborted - " .. tostring(reason))
    end
}
