-- Collector entity type definition
-- Specializes in collecting dropped ground items
return {
    initial = {
        -- Ground item sensing
        nearGroundItem = false,    -- true when near collectible ground items
        hasInventorySpace = true,  -- true when can carry more items

        -- Survival states (same as other entity types)
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
    goal = { hungry = false }
}