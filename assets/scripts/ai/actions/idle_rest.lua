--[[
Forager action: Rest to recover energy.
Stays still for a few seconds and restores energy.
]]
return {
    name = "idle_rest",
    cost = 2,
    pre = { tired = true },  -- Must be tired to rest
    post = { tired = false },
    watch = { tired = true },

    start = function(e)
        log_debug("idle_rest: start for entity " .. tostring(e))
        setBlackboardFloat(e, "rest_timer", 0)
        stopEntityWalkMotion(e)  -- Stop moving while resting
    end,

    update = function(e, dt)
        local timer = getBlackboardFloat(e, "rest_timer") or 0
        timer = timer + dt

        -- Restore energy while resting (faster than decay)
        local energy = ai.bb.get(e, "energy", 0)
        energy = energy + dt * 15  -- Restore 15 energy per second
        if energy > 100 then energy = 100 end
        ai.bb.set(e, "energy", energy)

        -- Rest for 3 seconds or until energy is restored
        if timer >= 3.0 or energy >= 80 then
            ai.set_worldstate(e, "tired", false)
            ai.set_worldstate(e, "exhausted", false)
            return ActionResult.SUCCESS
        end

        setBlackboardFloat(e, "rest_timer", timer)
        return ActionResult.RUNNING
    end,

    finish = function(e)
        log_debug(string.format("idle_rest: entity %s finished resting, energy=%.0f",
            tostring(e), ai.bb.get(e, "energy", 0)))
    end,

    abort = function(e, reason)
        log_debug("idle_rest: aborted - " .. tostring(reason))
    end
}
