
-- Update function returns ActionResult.SUCCESS, ActionResult.RUNNING or ActionResult.FAILURE
-- Each action should have a start, update and finish function. Start is called once, update is called each frame and finish is called once.
-- The update function should return ActionResult.SUCCESS when the action is complete, ActionResult.RUNNING when the action is still running and ActionResult.FAILURE when the action has failed. It can also use functions like wait() to wait for a certain amount of time, but it must return one of the three values eventually.

-- NOTE: This action is deprecated - use idle_consume.lua instead
-- Keeping this file to avoid "action not found" errors but with high cost
return {
    name = "eat",
    cost = 999,  -- High cost to ensure idle_consume is preferred
    pre = { hungry = true, _deprecated = true },  -- Impossible precondition
    post = { hungry = false },

    start = function(e)
        log_debug("eat.lua (deprecated): started for", e)
    end,

    update = function(e, dt)
        -- Immediately succeed since this is deprecated
        return ActionResult.SUCCESS
    end,

    finish = function(e)
        log_debug("eat.lua (deprecated): finished for", e)
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