
-- Update function returns ActionResult.SUCCESS, ActionResult.RUNNING or ActionResult.FAILURE
-- Each action should have a start, update and finish function. Start is called once, update is called each frame and finish is called once.
-- The update function should return ActionResult.SUCCESS when the action is complete, ActionResult.RUNNING when the action is still running and ActionResult.FAILURE when the action has failed. It can also use functions like wait() to wait for a certain amount of time, but it must return one of the three values eventually.

return {
    name = "wander",
    cost = 5, -- make less desirable
    pre = { wander = false },
    post = { wander = true },

    start = function(e)
        log_debug("Entity", e, "is wandering.")
    end,

    update = function(e, dt) -- update can be coroutine
        log_debug("Entity", e, "wander update.")
        wait(1.0)
        
        --TODO: find random location on the map, activate movement towards that location, continue wandering until the entity reaches that location, turn off walk timer
        
        local config = require("idle_game.config")
        local maxX = config.GRID_WIDTH * config.TILE_SIZE
        local maxY = config.GRID_HEIGHT * config.TILE_SIZE
        local goalLoc = Vec2(random_utils.random_float(0, maxX), random_utils.random_float(0, maxY))
        
        -- save in blackboard
    
        -- setBlackboardVector2(e, "wander_target", goalLoc)
        
        -- start a timer that will rotate the entity regularly to simulate walking
        -- add a walk-timer that bounces rotation ±5° every half-second
        startEntityWalkMotion(e)
        
        -- while the entity is not at the target location, continue wandering
        while true do
            if moveEntityTowardGoalOneIncrement(e, goalLoc, dt) == false then
                log_debug("Entity", e, "has reached the wander target location.")
                break -- exit the loop when the entity reaches the target location
            end
        end
        
        return ActionResult.SUCCESS
    end,

    finish = function(e)
        log_debug("Done wandering: entity", e)
    end
}


-- previous versio for reference:


-- wander = {}

-- function wander.start(entity)
--     log_debug(entity, "Wander action started");
--     setBlackboardFloat(entity, "time_spent_wandering", 0.0);  -- Store a custom variable
-- end

-- function wander.update(entity, deltaTime)
    
--     local timeSpent = getBlackboardFloat(entity, "time_spent_wandering");
--     timeSpent = timeSpent + deltaTime;
--     setBlackboardFloat(entity, "time_spent_wandering", timeSpent);
    
--     if timeSpent >= 10.0 then
--         log_debug(entity, "Wander action completed");
--         return ActionResult.SUCCESS;  -- Return true to indicate the action has completed
--     else 
--         log_debug(entity, "Wandering... " .. timeSpent .. " seconds passed.");
--         return ActionResult.RUNNING;  -- Return false to indicate the action is still running
--     end
    
--     --[[ alternatively, use yield() or one of the wait functions
    
--         while timeSpent < 10.0 do
--             coroutine.yield(); -- Yield until the next frame
--             timeSpent = getBlackboardFloat(entity, "time_spent_wandering");
--             timeSpent = timeSpent + deltaTime;
--             setBlackboardFloat(entity, "time_spent_wandering", timeSpent);
--         end
        
--     ]]
-- end

-- -- postconditions are updated automatically, no need to define them here
-- function wander.finish(entity)
--     log_debug(entity, "Wander action ended");
-- end