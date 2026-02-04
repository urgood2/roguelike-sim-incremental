# Goal Selector Patterns Analysis

**Analysis of ai/goal_selectors/ directory patterns**

## Overview

The `ai/goal_selectors/` directory contains entity-specific goal selection logic for the GOAP (Goal-Oriented Action Planning) AI system. Three distinct patterns have been identified across the current goal selectors.

## Pattern 1: Modern Idle Game Selectors

**Files:** `forager.lua`, `lumberjack.lua`, `builder.lua`

**Characteristics:**
- Uses `ai.goal_selector_engine` for goal selection
- Explicit goal definitions with clear categorization
- Standard survival + work + idle structure
- Detailed comments explaining purpose

**Structure:**
```lua
local selector = require("ai.goal_selector_engine")

return function(e)
    local def = ai.get_entity_ai_def(e)
    def.policy = def.policy or ai.policy
    def.goals = {
        -- Survival (highest priority)
        REST = ai.goals.REST,
        CONSUME = ai.goals.CONSUME,
        FORAGE = ai.goals.FORAGE,

        -- Work goals (entity-specific)
        HARVEST_WOOD = ai.goals.HARVEST_WOOD,
        -- ... other work goals

        -- Fallback
        WANDER = ai.goals.WANDER,
    }
    selector.select_and_apply(e)
end
```

**Goal Categories:**
1. **Survival Goals** (highest priority)
   - `REST` - Rest when tired/exhausted
   - `CONSUME` - Eat when has food
   - `FORAGE` - Get food when hungry

2. **Work Goals** (entity-specific specialization)
   - Forager: `HARVEST_WOOD`, `HARVEST_STONE` (general gathering)
   - Lumberjack: `HARVEST_WOOD` only (specialized)
   - Builder: `HARVEST_WOOD`, `HARVEST_STONE` (construction materials)

3. **Fallback Goals**
   - `WANDER` - Idle wandering behavior

**Specialization Patterns:**
- **Forager**: General resource gathering (wood + stone)
- **Lumberjack**: Specialized wood harvesting only
- **Builder**: Resource gathering for construction + future building goals

## Pattern 2: Generic Shared Selector

**Files:** `gold_digger.lua`

**Characteristics:**
- Uses default shared policy and goals from `ai.policy` and `ai.goals`
- Minimal customization with optional per-type tweaks
- Uses `ai.goal_selector_engine` but delegates to shared definitions
- Includes debug logging

**Structure:**
```lua
local selector = require("ai.goal_selector_engine")

return function(e)
  local def = ai.get_entity_ai_def(e)

  -- Use shared policy/goals by default
  def.policy = def.policy or ai.policy
  def.goals  = def.goals  or ai.goals

  -- (Optional) Per-type tweaks commented out

  selector.select_and_apply(e)
end
```

**Use Case:**
- Entities that use the complete shared goal set (includes DIG_FOR_GOLD, HARVEST, etc.)
- Suitable for entities that don't need specialized goal filtering
- Allows optional per-type parameter tuning (persistence, priorities)

## Pattern 3: Legacy Manual Selector

**Files:** `kobold.lua`

**Characteristics:**
- Direct goal setting without goal_selector_engine
- Manual conditional logic for goal selection
- Legacy/experimental implementation
- Hardcoded behavior trees

**Structure:**
```lua
return function(entity)
    if (ai.get_worldstate(entity, "duplicator_available")) then
        ai.set_goal(entity, { duplicator_available = false })
    else if (getBlackboardFloat(entity, "hunger")) > 0.3 then
        ai.set_worldstate(entity, "wander", false)
        ai.set_goal(entity, { wander = true })
    else
        ai.set_goal(entity, { hungry = false })
    end
end
```

**Characteristics:**
- Manual if/else goal selection
- Direct blackboard access
- No use of goal_selector_engine
- Hardcoded thresholds and logic

## Import Patterns

**Engine Import:**
- Modern selectors: `require("ai.goal_selector_engine")`
- Some also import: `require("ai.init")` for ai table access

**Differences:**
- Forager: Only imports `goal_selector_engine`
- Lumberjack/Builder: Import both `ai.init` and `goal_selector_engine`
- Gold Digger: Only imports `goal_selector_engine`
- Kobold: No imports (legacy)

## Common Elements

**Function Signature:**
All selectors return a function that takes an entity parameter: `function(e)` or `function(entity)`

**AI Definition Access:**
Modern selectors get entity AI definition: `local def = ai.get_entity_ai_def(e)`

**Policy Setting:**
Modern selectors set policy: `def.policy = def.policy or ai.policy`

**Engine Usage:**
Modern selectors call: `selector.select_and_apply(e)`

## Recommendations

**Preferred Pattern:** Modern Idle Game Selectors (Pattern 1)
- Clear goal categorization (survival, work, idle)
- Explicit goal filtering for entity specialization
- Good documentation and comments
- Consistent structure across entity types

**Migration Path:**
- Legacy selectors (kobold) should be migrated to Pattern 1
- Generic selectors can be specialized using Pattern 1 when needed

**Naming Conventions:**
- File names match entity types: `{entity_type}.lua`
- Clear comments explaining specialization
- Consistent goal organization (survival → work → idle)