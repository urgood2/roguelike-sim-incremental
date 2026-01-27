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
        
        local component_cache = require("core.component_cache")
        local upgrades = require("idle_game.upgrades")
        
        local transformComp = component_cache.get(e, Transform)
        local absYDiff = math.abs(transformComp.actualY - goalLoc.y)
        local absXDiff = math.abs(transformComp.actualX - goalLoc.x)
        
        -- Apply creature_speed upgrade multiplier (base 30 px/s, +10% per level)
        local speedLevel = upgrades.get_level("creature_speed")
        local speed = 30 * (1 + speedLevel * 0.1)
        
        if absYDiff < speed and absXDiff < speed then
            log_debug("idle_wander: entity " .. tostring(e) .. " reached target")
            return ActionResult.SUCCESS
        else
            local direction = Vec2(goalLoc.x - transformComp.actualX, goalLoc.y - transformComp.actualY)
            local length = math.sqrt(direction.x * direction.x + direction.y * direction.y)
            if length > 0 then
                direction.x = direction.x / length
                direction.y = direction.y / length
            end
            transformComp.actualX = transformComp.actualX + direction.x * speed * dt
            transformComp.actualY = transformComp.actualY + direction.y * speed * dt
            return ActionResult.RUNNING
        end
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
