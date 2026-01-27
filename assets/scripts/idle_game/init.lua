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
        local hasFood = ai.get_worldstate(e, "hasFood")
        return hasFood and 0.9 or 0.0
    end,
    on_apply = function(e)
        ai.set_goal(e, { hungry = false })
    end
}

ai.goals.IDLE_WANDER = {
    band = "IDLE",
    persist = 0.05,
    desire = function(e, S)
        return 0.2
    end,
    on_apply = function(e)
        ai.patch_worldstate(e, "wander", false)
        ai.set_goal(e, { wander = true })
    end
}

return idle_game
