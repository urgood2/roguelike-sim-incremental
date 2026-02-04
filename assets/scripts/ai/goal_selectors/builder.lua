-- Builder goal selector
-- Specializes in construction and structure placement
local ai = require("ai.init")
local selector = require("ai.goal_selector_engine")

return function(e)
    local def = ai.get_entity_ai_def(e)
    def.policy = def.policy or ai.policy

    -- Builder-specific goals: survival + construction work
    def.goals = {
        -- Survival (highest priority)
        REST = ai.goals.REST,           -- Rest when tired/exhausted
        CONSUME = ai.goals.CONSUME,     -- Eat when has food
        FORAGE = ai.goals.FORAGE,       -- Get food when hungry

        -- Construction work (builder specialty)
        BUILD_STRUCTURE = ai.goals.BUILD_STRUCTURE,     -- Build structures when ready

        -- Resource gathering (for construction materials)
        HARVEST_WOOD = ai.goals.HARVEST_WOOD,      -- Wood for building
        HARVEST_STONE = ai.goals.HARVEST_STONE,    -- Stone for building

        -- Fallback idle behavior
        WANDER = ai.goals.WANDER,
    }

    selector.select_and_apply(e)
end
