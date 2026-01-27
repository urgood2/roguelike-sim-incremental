-- scripts/ai/goal_selectors/forager.lua
-- Forager goal selector: returns a function that selects goals for forager entities
local selector = require("ai.goal_selector_engine")

return function(e)
    local def = ai.get_entity_ai_def(e)
    
    -- Use shared policy/goals
    def.policy = def.policy or ai.policy
    def.goals = def.goals or ai.goals
    
    log_debug("Forager Goal Selector for entity " .. tostring(e))
    
    selector.select_and_apply(e)
end
