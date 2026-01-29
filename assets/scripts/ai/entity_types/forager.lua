-- Forager creature entity type
-- Auto-loaded by ai/init.lua:36

return {
    -- Initial worldstate atoms
    initial = {
        hungry = true,
        hasFood = false,
        nearTree = false,
        nearRock = false,
        didWork = false,
        wander = false
    },

    -- Default goal (not used with custom goal selector, but required)
    goal = {
        hungry = false
    }
}
