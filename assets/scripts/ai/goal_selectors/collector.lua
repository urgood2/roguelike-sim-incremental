-- Collector goal selector
-- Specializes in collecting ground items and providing resource gathering backup
local ai = require("ai.init")
local selector = require("ai.goal_selector_engine")

return function(e)
    local def = ai.get_entity_ai_def(e)
    def.policy = def.policy or ai.policy

    -- Collector-specific goals: survival + collection work + resource backup
    def.goals = {
        -- Survival (highest priority)
        REST = ai.goals.REST,           -- Rest when tired/exhausted
        CONSUME = ai.goals.CONSUME,     -- Eat when has food
        FORAGE = ai.goals.FORAGE,       -- Get food when hungry

        -- Collection work (collector specialty)
        COLLECT_ITEM = ai.goals.COLLECT_ITEM,    -- Collect distant ground items

        -- Resource gathering backup (when no items to collect)
        HARVEST_WOOD = ai.goals.HARVEST_WOOD,      -- Trees for backup work
        HARVEST_STONE = ai.goals.HARVEST_STONE,    -- Rocks for backup work

        -- Fallback idle behavior
        WANDER = ai.goals.WANDER,
    }

    selector.select_and_apply(e)
end