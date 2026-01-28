print("idle_game loaded")

local idle_game = {}

-- Register GOAP goals for forager creatures
ai.goals.FORAGE = {
    band = "WORK",
    persist = 0.08,
    desire = function(e, S)
        local hungry = ai.get_worldstate(e, "hungry")
        local nearTree = ai.get_worldstate(e, "nearTree")
        return (hungry and nearTree) and 1.0 or 0.0
    end,
    on_apply = function(e)
        ai.set_goal(e, { hasFood = true })
    end
}

ai.goals.CONSUME = {
    band = "SURVIVAL",
    persist = 0.1,
    desire = function(e, S)
        -- Must be BOTH hungry AND have food to want to consume
        -- Without hungry check, this activates after foraging even if not hungry anymore
        local hungry = ai.get_worldstate(e, "hungry")
        local hasFood = ai.get_worldstate(e, "hasFood")
        return (hungry and hasFood) and 0.9 or 0.0
    end,
    on_apply = function(e)
        ai.set_goal(e, { hungry = false })
    end
}

ai.goals.IDLE_WANDER = {
    band = "IDLE",
    persist = 0.0,  -- No persistence - re-evaluate every frame
    desire = function(e, S)
        -- Always want to wander
        return 0.5
    end,
    on_apply = function(e)
        -- Always reset wander to false so GOAP can plan
        ai.set_worldstate(e, "wander", false)
        ai.set_goal(e, { wander = true })
    end
}

return idle_game
