# Upgrades Definitions and List API Documentation

## Overview
The upgrades system provides access to upgrade definitions including IDs, titles, descriptions, and effect data. This document identifies the API for accessing upgrade definitions and lists.

## Definition Source
**Location**: `assets/scripts/idle_game/upgrades.lua:6-91`

All upgrade definitions are stored in the internal `UPGRADES` table within the upgrades module. This table contains 12 upgrade definitions covering diverse game mechanics.

## List Access Function

### `upgrades.get_all()`
**Location**: `assets/scripts/idle_game/upgrades.lua:169-171`

**Purpose**: Get all upgrade definitions for iteration or lookup

**Parameters**: None

**Returns**:
- `table`: Complete UPGRADES table containing all upgrade definitions

**Return Structure**:
```lua
{
    upgrade_id = {
        name = "Display Title",
        description = "Detailed description text",
        base_cost = {resource_type = amount, ...},
        max_level = number,
        effect = {type = "effect_type", ...}
    },
    -- ... more upgrades
}
```

**Example Usage**:
```lua
local all_upgrades = upgrades.get_all()

-- Iterate through all upgrades
for upgrade_id, upgrade_def in pairs(all_upgrades) do
    print(upgrade_id .. ": " .. upgrade_def.name)
end

-- Access specific upgrade definition
local wood_click_def = all_upgrades["click_wood"]
print(wood_click_def.description)  -- "Increase wood per click"
```

**Implementation**:
```lua
function upgrades.get_all()
    return UPGRADES
end
```

## Complete Upgrade Definitions List

### Available Upgrade IDs
There are 12 upgrade IDs available in the system:

| Upgrade ID | Name | Description | Base Cost |
|------------|------|-------------|-----------|
| `click_wood` | Stronger Axe | Increase wood per click | {wood = 10} |
| `click_stone` | Better Pickaxe | Increase stone per click | {stone = 10} |
| `passive_gold` | Gold Mine | Increase passive gold rate | {gold = 20} |
| `creature_speed` | Creature Training | Increase forager movement speed | {food = 15} |
| `forage_amount` | Better Basket | Increase food per forage | {wood = 20} |
| `forage_speed` | Efficient Foraging | Reduce forage time | {stone = 25} |
| `tree_regrowth` | Tree Sapling Farming | Increase tree regrowth chance | {gold = 50} |
| `rock_regrowth` | Rock Formation | Increase rock regrowth chance | {gold = 50} |
| `max_creatures` | Better Housing | Increase max foragers | {wood = 30} |
| `starting_wood` | Initial Resources I | Start new game with more wood | {stone = 40} |
| `starting_stone` | Initial Resources II | Start new game with more stone | {stone = 40} |
| `click_range` | Extended Reach | Increase click area radius | {gold = 100} |

### Upgrade Categories by Effect Type

**Click Enhancement**:
- `click_wood` - Wood per click multiplier
- `click_stone` - Stone per click multiplier
- `click_range` - Click area radius expansion

**Resource Generation**:
- `passive_gold` - Passive gold rate increase
- `forage_amount` - Food per forage amount increase
- `forage_speed` - Forage time reduction

**Creature/Population**:
- `creature_speed` - Forager movement speed
- `max_creatures` - Maximum forager capacity

**World Mechanics**:
- `tree_regrowth` - Tree regrowth chance increase
- `rock_regrowth` - Rock regrowth chance increase

**Starting Bonuses**:
- `starting_wood` - Initial wood bonus for new games
- `starting_stone` - Initial stone bonus for new games

## Definition Field Structure

### Required Fields
Every upgrade definition contains these fields:

```lua
{
    name = "string",           -- Display title (e.g., "Stronger Axe")
    description = "string",    -- Detailed description (e.g., "Increase wood per click")
    base_cost = {             -- Resource costs for level 1
        resource_name = amount,  -- e.g., wood = 10
        -- ... additional resources
    },
    max_level = number,        -- Maximum upgrade level (always 10)
    effect = {                 -- Effect configuration
        type = "effect_type",    -- Effect category
        -- ... type-specific fields
    }
}
```

### Effect Types and Structures

**Click Multipliers**:
```lua
effect = {
    type = "click_multiplier",
    resource = "resource_name",  -- "wood" or "stone"
    amount = number             -- Multiplier per level
}
```

**Passive Rates**:
```lua
effect = {
    type = "passive_rate",
    resource = "resource_name",  -- "gold"
    amount = number             -- Rate increase per level
}
```

**Stat Multipliers**:
```lua
effect = {
    type = "stat_multiplier",
    stat = "stat_name",         -- "speed"
    amount = number             -- Multiplier per level
}
```

**Harvest Amounts**:
```lua
effect = {
    type = "harvest_amount",
    resource = "resource_name",  -- "food"
    amount = number             -- Amount increase per level
}
```

**Action Duration**:
```lua
effect = {
    type = "action_duration",
    action = "action_name",     -- "forage"
    amount = number             -- Duration change per level (negative = faster)
}
```

**Regrowth Chances**:
```lua
effect = {
    type = "regrowth_chance",
    tile = "tile_type",         -- "tree" or "rock"
    amount = number             -- Chance increase per level
}
```

**Capacity Changes**:
```lua
effect = {
    type = "capacity",
    entity = "entity_type",     -- "forager"
    amount = number             -- Capacity increase per level
}
```

**Starting Resources**:
```lua
effect = {
    type = "starting_resource",
    resource = "resource_name",  -- "wood" or "stone"
    amount = number             -- Starting amount increase per level
}
```

**Area Radius**:
```lua
effect = {
    type = "area_radius",
    amount = number             -- Radius increase per level
}
```

## Title and Description Access

### Direct Field Access
```lua
local all_upgrades = upgrades.get_all()

-- Get title (name field)
local title = all_upgrades["click_wood"].name  -- "Stronger Axe"

-- Get description
local desc = all_upgrades["click_wood"].description  -- "Increase wood per click"
```

### Helper Function Pattern
```lua
-- Utility function to get upgrade title by ID
function get_upgrade_title(upgrade_id)
    local all_upgrades = upgrades.get_all()
    local upgrade = all_upgrades[upgrade_id]
    return upgrade and upgrade.name or "Unknown Upgrade"
end

-- Utility function to get upgrade description by ID
function get_upgrade_description(upgrade_id)
    local all_upgrades = upgrades.get_all()
    local upgrade = all_upgrades[upgrade_id]
    return upgrade and upgrade.description or "No description available"
end
```

### UI Display Pattern
```lua
function populate_upgrades_list()
    local all_upgrades = upgrades.get_all()

    for upgrade_id, upgrade_def in pairs(all_upgrades) do
        local current_level = upgrades.get_level(upgrade_id)
        local cost = upgrades.get_cost(upgrade_id)

        -- Create UI element with definition data
        ui.create_upgrade_button({
            id = upgrade_id,
            title = upgrade_def.name,
            description = upgrade_def.description,
            level = current_level,
            max_level = upgrade_def.max_level,
            cost = cost,
            can_afford = upgrades.can_afford(upgrade_id, resources)
        })
    end
end
```

## Upgrade Validation

### Check if Upgrade ID Exists
```lua
function is_valid_upgrade(upgrade_id)
    local all_upgrades = upgrades.get_all()
    return all_upgrades[upgrade_id] ~= nil
end

-- Usage
if is_valid_upgrade("click_wood") then
    print("Valid upgrade ID")
end
```

### Get All Upgrade IDs
```lua
function get_all_upgrade_ids()
    local all_upgrades = upgrades.get_all()
    local ids = {}

    for upgrade_id, _ in pairs(all_upgrades) do
        table.insert(ids, upgrade_id)
    end

    table.sort(ids)  -- Optional: sort alphabetically
    return ids
end

-- Usage
local upgrade_ids = get_all_upgrade_ids()
-- Returns: {"click_range", "click_stone", "click_wood", "creature_speed", ...}
```

## Definition Metadata

### Universal Properties
- **Total Upgrades**: 12
- **Max Level**: All upgrades have `max_level = 10`
- **Cost Formula**: All use `base_cost * (1.5 ^ level)`
- **Effect Types**: 9 different effect types available
- **Resource Types**: 4 resource types used in costs (wood, stone, gold, food)

### Resource Cost Distribution
- **Wood costs**: 3 upgrades (click_wood, forage_amount, max_creatures)
- **Stone costs**: 4 upgrades (click_stone, forage_speed, starting_wood, starting_stone)
- **Gold costs**: 4 upgrades (passive_gold, tree_regrowth, rock_regrowth, click_range)
- **Food costs**: 1 upgrade (creature_speed)

## Integration with Other APIs

### Combined with Level Queries
```lua
function get_upgrade_summary(upgrade_id)
    local all_upgrades = upgrades.get_all()
    local upgrade_def = all_upgrades[upgrade_id]

    if not upgrade_def then
        return nil, "Unknown upgrade ID"
    end

    return {
        id = upgrade_id,
        name = upgrade_def.name,
        description = upgrade_def.description,
        current_level = upgrades.get_level(upgrade_id),
        max_level = upgrade_def.max_level,
        current_cost = upgrades.get_cost(upgrade_id),
        can_afford = upgrades.can_afford(upgrade_id, resources),
        effect = upgrade_def.effect
    }
end
```

### Combined with Purchase API
```lua
function create_full_upgrade_info(upgrade_id, resources_module)
    local all_upgrades = upgrades.get_all()
    local upgrade_def = all_upgrades[upgrade_id]

    return {
        -- Definition data
        id = upgrade_id,
        name = upgrade_def.name,
        description = upgrade_def.description,
        effect = upgrade_def.effect,
        max_level = upgrade_def.max_level,

        -- Current state
        current_level = upgrades.get_level(upgrade_id),
        next_cost = upgrades.get_cost(upgrade_id),
        can_purchase = upgrades.can_afford(upgrade_id, resources_module),
        is_maxed = upgrades.get_level(upgrade_id) >= upgrade_def.max_level
    }
end
```

## Error Handling

### Missing Upgrade ID
The `get_all()` function always returns the complete table, so individual upgrade lookups should be validated:

```lua
local all_upgrades = upgrades.get_all()
local upgrade = all_upgrades["invalid_id"]

if not upgrade then
    print("Upgrade ID not found")
    return
end

-- Safe to use upgrade.name, upgrade.description, etc.
```

### Defensive Access Pattern
```lua
function safe_get_upgrade_name(upgrade_id)
    local all_upgrades = upgrades.get_all()
    local upgrade = all_upgrades[upgrade_id]
    return upgrade and upgrade.name or ("Unknown: " .. tostring(upgrade_id))
end
```

## Notes

- The `get_all()` function returns a direct reference to the internal UPGRADES table
- Modifying the returned table would affect the internal definitions (not recommended)
- All upgrade definitions are loaded at module initialization time
- The definitions table is static and does not change during gameplay
- For safe iteration, consider copying the table if modifications are needed