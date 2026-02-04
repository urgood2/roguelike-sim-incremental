# Resources Read Totals API Documentation

## Overview
The resources system provides functions for reading current resource amounts, income rates, and checking affordability. This document identifies the exact functions and return shapes for accessing resource data.

## Read Resource Totals Functions

### 1. `resources.get(resource_type)`
**Location**: `assets/scripts/idle_game/resources.lua:71-77`

**Purpose**: Get the current amount of a specific resource type

**Parameters**:
- `resource_type` (string): The resource type identifier (use resource constants)

**Returns**:
- `number`: Current amount of the specified resource (0 to 9999)

**Resource Type Constants**:
- `resources.FOOD` = "food"
- `resources.WOOD` = "wood"
- `resources.STONE` = "stone"
- `resources.GOLD` = "gold"

**Example Usage**:
```lua
local resources = require("idle_game.resources")

-- Get current amounts using constants (recommended)
local food_amount = resources.get(resources.FOOD)
local wood_amount = resources.get(resources.WOOD)
local stone_amount = resources.get(resources.STONE)
local gold_amount = resources.get(resources.GOLD)

-- Get current amounts using strings (also valid)
local food_amount = resources.get("food")

print("Current wood: " .. wood_amount)
```

**Implementation**:
```lua
function resources.get(resource_type)
    if not _resources[resource_type] then
        error("Unknown resource type: " .. tostring(resource_type))
    end

    return _resources[resource_type]
end
```

**Error Handling**:
- Throws Lua error if `resource_type` is unknown/invalid
- Valid resource types: "food", "wood", "stone", "gold"

### 2. `resources.get_rate(resource_type)`
**Location**: `assets/scripts/idle_game/resources.lua:106-108`

**Purpose**: Get the current income rate per second for a specific resource

**Parameters**:
- `resource_type` (string): The resource type identifier

**Returns**:
- `number`: Income rate in resources per second (can be 0 if no income)

**Example Usage**:
```lua
-- Get current income rates
local gold_rate = resources.get_rate(resources.GOLD)
local wood_rate = resources.get_rate(resources.WOOD)

print(string.format("Gold income: %.2f/sec", gold_rate))
print(string.format("Wood income: %.2f/sec", wood_rate))
```

**Implementation**:
```lua
function resources.get_rate(resource_type)
    return _income_tracker.rates[resource_type] or 0
end
```

**Rate Calculation**:
- Rates are calculated over a 5-second window
- Only positive income (additions) are tracked for rates
- Rates are updated every 5 seconds with accumulated income

### 3. `resources.get_all_rates()`
**Location**: `assets/scripts/idle_game/resources.lua:111-113`

**Purpose**: Get income rates for all resource types in a single call

**Parameters**: None

**Returns**:
- `table`: Income rates table with resource types as keys and rates as values

**Return Shape**:
```lua
{
    food = 0.5,    -- Food income per second
    wood = 1.2,    -- Wood income per second
    stone = 0.8,   -- Stone income per second
    gold = 0.35    -- Gold income per second
}
```

**Example Usage**:
```lua
local all_rates = resources.get_all_rates()

-- Display all rates
for resource_type, rate in pairs(all_rates) do
    print(string.format("%s: %.2f/sec", resource_type, rate))
end

-- Access specific rates from returned table
local gold_rate = all_rates.gold or 0
```

**Implementation**:
```lua
function resources.get_all_rates()
    return _income_tracker.rates
end
```

## Resource Affordability Functions

### 4. `resources.can_afford(costs)`
**Location**: `assets/scripts/idle_game/resources.lua:116-129`

**Purpose**: Check if player has enough resources to afford a cost table

**Parameters**:
- `costs` (table): Cost table with resource types as keys and amounts as values

**Returns**:
- `boolean`: `true` if all costs can be afforded, `false` otherwise

**Cost Table Format**:
```lua
{
    food = 10,    -- Requires 10 food
    wood = 25,    -- Requires 25 wood
    stone = 5     -- Requires 5 stone
    -- gold not specified, so 0 gold required
}
```

**Example Usage**:
```lua
-- Check if player can afford an upgrade
local upgrade_cost = {
    wood = 50,
    stone = 25
}

if resources.can_afford(upgrade_cost) then
    print("Player can afford the upgrade")
    -- Proceed with purchase logic
else
    print("Insufficient resources")
    -- Show what's needed
end

-- Check multiple different costs
local costs = {
    building = {wood = 100, stone = 50},
    upgrade = {gold = 25},
    food_purchase = {gold = 10}
}

for item_name, cost in pairs(costs) do
    local affordable = resources.can_afford(cost)
    print(item_name .. ": " .. (affordable and "YES" or "NO"))
end
```

**Edge Cases**:
- `costs = nil` or `costs = {}` returns `true` (nothing to afford)
- Unknown resource type in costs throws error
- Costs with 0 or negative amounts are treated as free

## Resource Constants

### Available Resource Types
```lua
resources.FOOD = "food"     -- Food resource
resources.WOOD = "wood"     -- Wood resource
resources.STONE = "stone"   -- Stone resource
resources.GOLD = "gold"     -- Gold resource
```

**Usage Pattern**:
```lua
-- Recommended: Use constants for type safety
local current_food = resources.get(resources.FOOD)

-- Also valid: Use strings directly
local current_food = resources.get("food")

-- Constants help avoid typos
local wrong = resources.get("foo")  -- Would cause error
local right = resources.get(resources.FOOD)  -- Safe
```

## Resource Limits

### Resource Cap
- **Maximum per resource**: 9999
- **Minimum per resource**: 0
- Values are automatically clamped to this range when modified

### Rate Tracking
- **Rate window**: 5 seconds
- **Rate precision**: Per-second averages
- **Rate scope**: Only positive income is tracked (not spending)

## Complete Resource Status Pattern

### Get Full Resource State
```lua
function get_complete_resource_status()
    local status = {}

    -- Get current amounts
    status.amounts = {
        food = resources.get(resources.FOOD),
        wood = resources.get(resources.WOOD),
        stone = resources.get(resources.STONE),
        gold = resources.get(resources.GOLD)
    }

    -- Get all income rates
    status.rates = resources.get_all_rates()

    -- Calculate total wealth
    status.total_value = status.amounts.food + status.amounts.wood +
                        status.amounts.stone + status.amounts.gold

    return status
end

-- Usage
local status = get_complete_resource_status()
print("Total resources: " .. status.total_value)
print("Gold income: " .. status.rates.gold .. "/sec")
```

### UI Display Pattern
```lua
function display_resource_ui()
    local resource_types = {"food", "wood", "stone", "gold"}
    local rates = resources.get_all_rates()

    for _, resource_type in ipairs(resource_types) do
        local amount = resources.get(resource_type)
        local rate = rates[resource_type] or 0
        local display_rate = rate > 0 and string.format(" (+%.1f/s)", rate) or ""

        print(string.format("%s: %d%s", resource_type:upper(), amount, display_rate))
    end
end

-- Output example:
-- FOOD: 45 (+0.5/s)
-- WOOD: 123 (+2.1/s)
-- STONE: 67
-- GOLD: 234 (+0.3/s)
```

## Error Handling Summary

| Function | Error Condition | Error Type |
|----------|----------------|------------|
| `get()` | Unknown resource type | Lua error (throws) |
| `get_rate()` | Unknown resource type | Returns 0 (safe) |
| `get_all_rates()` | None | Always succeeds |
| `can_afford()` | Unknown resource type in costs | Lua error (throws) |

## Performance Notes

- **`get()`**: O(1) - direct table lookup
- **`get_rate()`**: O(1) - direct table lookup with default
- **`get_all_rates()`**: O(1) - returns reference to internal table
- **`can_afford()`**: O(n) where n = number of resource types in cost table

## Integration Examples

### With Upgrades System
```lua
local upgrades = require("idle_game.upgrades")
local resources = require("idle_game.resources")

function display_upgrade_affordability(upgrade_id)
    local cost = upgrades.get_cost(upgrade_id)
    local can_buy = resources.can_afford(cost)

    print("Upgrade: " .. upgrade_id)
    print("Affordable: " .. (can_buy and "YES" or "NO"))

    for resource_type, cost_amount in pairs(cost) do
        local current = resources.get(resource_type)
        local status = current >= cost_amount and "✓" or "✗"
        print(string.format("  %s: %d/%d %s", resource_type, current, cost_amount, status))
    end
end
```

### With Save System
```lua
function serialize_resource_state()
    return {
        amounts = {
            food = resources.get(resources.FOOD),
            wood = resources.get(resources.WOOD),
            stone = resources.get(resources.STONE),
            gold = resources.get(resources.GOLD)
        },
        rates = resources.get_all_rates(),
        timestamp = os.time()
    }
end
```

## Return Value Summary

| Function | Return Type | Example Value |
|----------|-------------|---------------|
| `get()` | `number` | `123` |
| `get_rate()` | `number` | `2.5` |
| `get_all_rates()` | `table` | `{food=0.5, wood=1.2, stone=0, gold=0.3}` |
| `can_afford()` | `boolean` | `true` or `false` |

This API provides complete access to resource totals, income rates, and affordability checking for the incremental game's resource management system.