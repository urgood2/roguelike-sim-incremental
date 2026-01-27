return {
    name = "idle_wander",
    cost = 1,
    pre = {},
    post = { wander = true },
    watch = {},
    
    start = function(e)
        log_debug("idle_wander: start for entity " .. tostring(e))
        local goalLoc = Vec2(
            random_utils.random_float(0, globals.screenWidth()), 
            random_utils.random_float(0, globals.screenHeight())
        )
        setBlackboardVector2(e, "wander_target", goalLoc)
        startEntityWalkMotion(e)
    end,
    
    update = function(e, dt)
        local goalLoc = getBlackboardVector2(e, "wander_target")
        if not goalLoc then
            return ActionResult.SUCCESS
        end
        
        if moveEntityTowardGoalOneIncrement(e, goalLoc, dt) == false then
            return ActionResult.SUCCESS
        end
        
        return ActionResult.RUNNING
    end,
    
    finish = function(e)
        log_debug("idle_wander: finish for entity " .. tostring(e))
        stopEntityWalkMotion(e)
    end,
    
    abort = function(e, reason)
        log_debug("idle_wander: aborted - " .. tostring(reason))
        stopEntityWalkMotion(e)
    end
}
