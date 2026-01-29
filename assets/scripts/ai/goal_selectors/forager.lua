local selector = require("ai.goal_selector_engine")

return function(e)
    local def = ai.get_entity_ai_def(e)
    def.policy = def.policy or ai.policy
    def.goals = {
        -- Survival (highest priority)
        REST = ai.goals.REST,           -- Rest when tired/exhausted
        CONSUME = ai.goals.CONSUME,     -- Eat when has food
        FORAGE = ai.goals.FORAGE,       -- Get food when hungry

        -- Resource gathering (work)
        HARVEST_WOOD = ai.goals.HARVEST_WOOD,
        HARVEST_STONE = ai.goals.HARVEST_STONE,

        -- Fallback idle behavior
        WANDER = ai.goals.WANDER,
    }
    selector.select_and_apply(e)
end
