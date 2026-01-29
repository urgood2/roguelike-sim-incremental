-- Forager creature entity type
-- Auto-loaded by ai/init.lua:36

return {
    -- Initial worldstate atoms
    initial = {
        -- Resource sensing
        nearTree = false,
        nearRock = false,

        -- Food/eating cycle
        hungry = false,      -- true when hunger < 40
        starving = false,    -- true when hunger < 15 (urgent!)
        hasFood = false,

        -- Energy/rest cycle
        tired = false,       -- true when energy < 30
        exhausted = false,   -- true when energy < 10 (can't work!)

        -- Reproduction
        readyToReproduce = false,  -- true when hunger > 80 AND energy > 60

        -- Work tracking
        didWork = false,
        wander = false
    },

    -- Default goal (not used with custom goal selector, but required)
    goal = {
        hungry = false
    }
}
