-- Miner goal selector
-- Targets rocks only - excludes HARVEST_WOOD goal
local ai = _G.ai
local selector = require("ai.goal_selector_engine")

return function(e)
    local def = ai.get_entity_ai_def(e)
    def.policy = def.policy or ai.policy

    -- Only stone harvesting goals - NO HARVEST_WOOD
    def.goals = {
        -- Survival (highest priority)
        REST = ai.goals.REST,           -- Rest when tired/exhausted
        CONSUME = ai.goals.CONSUME,     -- Eat when has food
        FORAGE = ai.goals.FORAGE,       -- Get food when hungry

        -- Mining work (miner specialty)
        HARVEST_STONE = ai.goals.HARVEST_STONE,    -- Rocks only

        -- Fallback idle behavior
        WANDER = ai.goals.WANDER,
    }

    selector.select_and_apply(e)
end