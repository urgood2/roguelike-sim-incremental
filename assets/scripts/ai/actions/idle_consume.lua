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
            -- Restore hunger when eating
            local hunger = ai.bb.get(e, "hunger", 50)
            hunger = hunger + 40  -- Eating restores 40 hunger
            if hunger > 100 then hunger = 100 end
            ai.bb.set(e, "hunger", hunger)

            ai.set_worldstate(e, "hungry", hunger < 40)
            ai.set_worldstate(e, "starving", hunger < 15)
            ai.set_worldstate(e, "hasFood", false)
            return ActionResult.SUCCESS
        end

        setBlackboardFloat(e, "consume_timer", timer)
        return ActionResult.RUNNING
    end,

    finish = function(e)
        log_debug(string.format("idle_consume: entity %s ate food, hunger=%.0f",
            tostring(e), ai.bb.get(e, "hunger", 0)))
    end,

    abort = function(e, reason)
        log_debug("idle_consume: aborted - " .. tostring(reason))
    end
}
