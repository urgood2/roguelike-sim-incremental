local selector = require("ai.goal_selector_engine")

return function(e)
    local def = ai.get_entity_ai_def(e)
    def.policy = def.policy or ai.policy
    def.goals = {
        IDLE_WANDER = ai.goals.IDLE_WANDER,
        FORAGE = ai.goals.FORAGE,
        CONSUME = ai.goals.CONSUME,
    }
    selector.select_and_apply(e)
end
