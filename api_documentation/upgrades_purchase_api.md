# Upgrades Purchase API Documentation

## Overview
The upgrades system provides functions for purchasing upgrades, checking affordability, and calculating costs. This document identifies the purchase attempt API and return shapes.

## Purchase Attempt Functions

### 1. `upgrades.purchase(upgrade_id, resources_module)`
**Location**: `assets/scripts/idle_game/upgrades.lua:145-157`

**Purpose**: Attempt to purchase the next level of an upgrade

**Parameters**:
- `upgrade_id` (string): The unique identifier of the upgrade (e.g., "click_wood", "passive_gold")
- `resources_module` (table): The resources module instance with `get()` and `add()` functions

**Returns**:
- `boolean`: `true` on successful purchase, `false` if cannot afford or already at max level

**Behavior**:
1. Checks if upgrade can be afforded using `upgrades.can_afford()`
2. If affordable, deducts cost from resources using `resources_module.add(resource, -amount)`
3. Increments upgrade level by 1
4. Returns purchase success status

**Example Usage**:
```lua
local resources = require("idle_game.resources")
local upgrades = require("idle_game.upgrades")

-- Attempt to purchase next level of "click_wood" upgrade
local success = upgrades.purchase("click_wood", resources)

if success then
    print("Upgrade purchased successfully!")
else
    print("Cannot afford upgrade or already at max level")
end
```

**Implementation**:
```lua
function upgrades.purchase(upgrade_id, resources_module)
    if not upgrades.can_afford(upgrade_id, resources_module) then
        return false
    end

    local cost = upgrades.get_cost(upgrade_id)
    for resource, amount in pairs(cost) do
        resources_module.add(resource, -amount)
    end

    upgrades._levels[upgrade_id] = upgrades.get_level(upgrade_id) + 1
    return true
end
```

### 2. `upgrades.can_afford(upgrade_id, resources_module)`
**Location**: `assets/scripts/idle_game/upgrades.lua:119-141`

**Purpose**: Check if player can afford the next level of an upgrade

**Parameters**:
- `upgrade_id` (string): The unique identifier of the upgrade
- `resources_module` (table): The resources module instance with `get()` function

**Returns**:
- `boolean`: `true` if upgrade can be afforded and not at max level, `false` otherwise

**Conditions for `false`**:
1. Upgrade is already at maximum level (`level >= max_level`)
2. Player has insufficient resources for any required resource type

**Example Usage**:
```lua
local can_buy = upgrades.can_afford("passive_gold", resources)
if can_buy then
    print("Can purchase passive gold upgrade")
    local cost = upgrades.get_cost("passive_gold")
    -- Display cost to player
end
```

**Implementation**:
```lua
function upgrades.can_afford(upgrade_id, resources_module)
    local upgrade = UPGRADES[upgrade_id]
    if not upgrade then
        error("Unknown upgrade: " .. tostring(upgrade_id))
    end

    local level = upgrades.get_level(upgrade_id)

    -- Can't purchase if already at max level
    if level >= upgrade.max_level then
        return false
    end

    -- Check if player has enough resources
    local cost = upgrades.get_cost(upgrade_id)
    for resource, amount in pairs(cost) do
        if resources_module.get(resource) < amount then
            return false
        end
    end

    return true
end
```

### 3. `upgrades.get_cost(upgrade_id)`
**Location**: `assets/scripts/idle_game/upgrades.lua:101-115`

**Purpose**: Calculate the cost for the next level of an upgrade

**Parameters**:
- `upgrade_id` (string): The unique identifier of the upgrade

**Returns**:
- `table`: Resource cost table with resource types as keys and amounts as values

**Cost Formula**: `base_cost * (1.5 ^ current_level)`

**Return Shape**:
```lua
{
    wood = 15,    -- Amount of wood required
    stone = 22,   -- Amount of stone required
    gold = 30,    -- Amount of gold required
    food = 18     -- Amount of food required
}
-- Note: Only resources defined in upgrade's base_cost are included
```

**Example Usage**:
```lua
local cost = upgrades.get_cost("click_wood")
-- Returns: {wood = 10} for level 0, {wood = 15} for level 1, etc.

print("Wood cost: " .. cost.wood)

-- Check specific resource cost
if cost.gold then
    print("Gold required: " .. cost.gold)
end
```

**Implementation**:
```lua
function upgrades.get_cost(upgrade_id)
    local upgrade = UPGRADES[upgrade_id]
    if not upgrade then
        error("Unknown upgrade: " .. tostring(upgrade_id))
    end

    local level = upgrades.get_level(upgrade_id)
    local cost = {}

    for resource, base_amount in pairs(upgrade.base_cost) do
        cost[resource] = math.floor(base_amount * (1.5 ^ level))
    end

    return cost
end
```

## Purchase Workflow Pattern

### Complete Purchase Attempt Flow
```lua
local resources = require("idle_game.resources")
local upgrades = require("idle_game.upgrades")

function attempt_purchase(upgrade_id)
    -- Step 1: Check if purchase is possible
    if not upgrades.can_afford(upgrade_id, resources) then
        local level = upgrades.get_level(upgrade_id)
        local max_level = 10  -- All upgrades have max_level = 10

        if level >= max_level then
            return false, "Upgrade is already at maximum level"
        else
            return false, "Insufficient resources"
        end
    end

    -- Step 2: Get cost for display (optional)
    local cost = upgrades.get_cost(upgrade_id)

    -- Step 3: Attempt purchase
    local success = upgrades.purchase(upgrade_id, resources)

    if success then
        local new_level = upgrades.get_level(upgrade_id)
        return true, "Upgrade purchased! Now at level " .. new_level
    else
        return false, "Purchase failed unexpectedly"
    end
end
```

### UI Integration Pattern
```lua
function update_upgrade_ui(upgrade_id)
    local level = upgrades.get_level(upgrade_id)
    local can_afford = upgrades.can_afford(upgrade_id, resources)
    local cost = upgrades.get_cost(upgrade_id)

    -- Update UI elements
    ui.set_level_text(upgrade_id, "Level: " .. level .. "/10")
    ui.set_cost_text(upgrade_id, format_cost(cost))
    ui.set_button_enabled(upgrade_id, can_afford)

    if level >= 10 then
        ui.set_button_text(upgrade_id, "MAXED")
    else
        ui.set_button_text(upgrade_id, "UPGRADE")
    end
end
```

## Error Handling

### Invalid Upgrade ID
All functions will raise a Lua error if provided with an unknown upgrade_id:
```lua
-- This will error: "Unknown upgrade: invalid_upgrade"
upgrades.purchase("invalid_upgrade", resources)
```

### Missing Resources Module
Functions requiring `resources_module` parameter will error if module doesn't have required methods:
- `resources_module.get(resource_type)` - Required by `can_afford()`
- `resources_module.add(resource_type, amount)` - Required by `purchase()`

## Available Upgrade Types

All upgrades support the purchase API. Current upgrade IDs:

| Upgrade ID | Base Cost | Effect |
|------------|-----------|--------|
| click_wood | {wood = 10} | Increase wood per click |
| click_stone | {stone = 10} | Increase stone per click |
| passive_gold | {gold = 20} | Increase passive gold rate |
| creature_speed | {food = 15} | Increase forager movement speed |
| forage_amount | {wood = 20} | Increase food per forage |
| forage_speed | {stone = 25} | Reduce forage time |
| tree_regrowth | {gold = 50} | Increase tree regrowth chance |
| rock_regrowth | {gold = 50} | Increase rock regrowth chance |
| max_creatures | {wood = 30} | Increase max foragers |
| starting_wood | {stone = 40} | Start new game with more wood |
| starting_stone | {stone = 40} | Start new game with more stone |
| click_range | {gold = 100} | Increase click area radius |

## Return Value Summary

| Function | Success Return | Failure Return | Error Conditions |
|----------|---------------|---------------|------------------|
| `purchase()` | `true` | `false` | Throws on invalid upgrade_id |
| `can_afford()` | `true` | `false` | Throws on invalid upgrade_id |
| `get_cost()` | `{resource=amount, ...}` | N/A | Throws on invalid upgrade_id |

## Notes

- All upgrades have `max_level = 10`
- Cost increases exponentially: `base_cost * (1.5 ^ level)`
- Purchase automatically deducts resources and increments level
- Functions are atomic - either purchase succeeds completely or fails completely
- Resources module integration allows for different resource management systems