-- Lumberjack entity type definition
-- Targets trees specifically, not rocks or bushes
return {
    initial = {
        nearTree = false,      -- Only trees, NOT nearRock
        hungry = false,
        starving = false,
        hasFood = false,
        tired = false,
        exhausted = false,
        readyToReproduce = false,
        didWork = false,
        wander = false
    },
    goal = { hungry = false }
}