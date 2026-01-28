return {
    name = "idle_wander",
    cost = 1,
    pre = {},
    post = { wander = true },
    watch = {},
    
    start = function(e)
        log_debug("idle_wander: start for entity " .. tostring(e))
        -- Constrain wander to game grid bounds (not full screen)
        local config = require("idle_game.config")
        local maxX = config.GRID_WIDTH * config.TILE_SIZE
        local maxY = config.GRID_HEIGHT * config.TILE_SIZE
        local goalLoc = Vec2(
            random_utils.random_float(0, maxX), 
            random_utils.random_float(0, maxY)
        )
        setBlackboardVector2(e, "wander_target", goalLoc)
        startEntityWalkMotion(e)
    end,
    
    update = function(e, dt)
        local goalLoc = getBlackboardVector2(e, "wander_target")
        if not goalLoc then
            log_debug("idle_wander: NO GOAL for entity " .. tostring(e))
            return ActionResult.SUCCESS
        end
        
        local component_cache = require("core.component_cache")
        local upgrades = require("idle_game.upgrades")
        
        local transformComp = component_cache.get(e, Transform)
        if not transformComp then
            log_debug("idle_wander: NO TRANSFORM for entity " .. tostring(e))
            return ActionResult.FAILURE
        end
        
        local posX = transformComp.actualX or 0
        local posY = transformComp.actualY or 0
        local goalX = goalLoc.x or 0
        local goalY = goalLoc.y or 0
        
        log_debug(string.format("idle_wander[%s]: pos=(%.1f,%.1f) goal=(%.1f,%.1f)", tostring(e), posX, posY, goalX, goalY))
        
        local absYDiff = math.abs(posY - goalY)
        local absXDiff = math.abs(posX - goalX)
        
        local speedLevel = upgrades.get_level("creature_speed")
        local speed = 30 * (1 + speedLevel * 0.1)
        
        if absYDiff < speed and absXDiff < speed then
            log_debug("idle_wander: entity " .. tostring(e) .. " reached target")
            return ActionResult.SUCCESS
        else
            local dirX = goalX - posX
            local dirY = goalY - posY
            local length = math.sqrt(dirX * dirX + dirY * dirY)
            if length > 0 then
                dirX = dirX / length
                dirY = dirY / length
            end
            transformComp.actualX = posX + dirX * speed * dt
            transformComp.actualY = posY + dirY * speed * dt
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
