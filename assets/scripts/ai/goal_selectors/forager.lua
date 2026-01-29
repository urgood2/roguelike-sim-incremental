local selector = require("ai.goal_selector_engine")

return function(e)
    local def = ai.get_entity_ai_def(e)
    def.policy = def.policy or ai.policy
    def.goals = {
        -- Resource gathering (priority work)
        HARVEST_WOOD = ai.goals.HARVEST_WOOD,
        HARVEST_STONE = ai.goals.HARVEST_STONE,
        -- Survival (foraging for food)
        FORAGE = ai.goals.FORAGE,
        CONSUME = ai.goals.CONSUME,
        -- Fallback idle behavior
        WANDER = ai.goals.WANDER,
    }
    selector.select_and_apply(e)
end
