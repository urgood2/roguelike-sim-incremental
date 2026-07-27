-- Lumberjack goal selector
-- Targets trees only - excludes HARVEST_STONE goal
local ai = _G.ai
local selector = require("ai.goal_selector_engine")

return function(e)
    local def = ai.get_entity_ai_def(e)
    def.policy = def.policy or ai.policy

    -- Only wood harvesting goals - NO HARVEST_STONE
    def.goals = {
        REST = ai.goals.REST,
        CONSUME = ai.goals.CONSUME,
        FORAGE = ai.goals.FORAGE,
        HARVEST_WOOD = ai.goals.HARVEST_WOOD,  -- Trees only
        WANDER = ai.goals.WANDER,
    }

    selector.select_and_apply(e)
end