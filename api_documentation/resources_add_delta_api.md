# Resources Add Delta API Documentation

## Overview
The resources system provides functions for adding and subtracting resource amounts with automatic bounds checking, validation, and event emission. This document specifies the exact function for adding deltas and confirms comprehensive support for negative resource changes.

## Primary Delta Function

### 1. `resources.add(resource_type, amount)`
**Location**: `assets/scripts/idle_game/resources.lua:41-68`

**Purpose**: Add or subtract a delta amount to a specific resource type

**Parameters**:
- `resource_type` (string): Resource identifier using resource constants
- `amount` (number): Delta to add (positive) or subtract (negative)

**Returns**:
- `number`: New total resource amount after clamping and validation

**Resource Type Constants**:
```lua
resources.FOOD  = "food"   -- Food resource
resources.WOOD  = "wood"   -- Wood resource
resources.STONE = "stone"  -- Stone resource
resources.GOLD  = "gold"   -- Gold resource
```

**Example Usage**:
```lua
local resources = require("idle_game.resources")

-- Add resources (positive deltas)
resources.add(resources.FOOD, 5)    -- Add 5 food
resources.add(resources.WOOD, 10)   -- Add 10 wood
resources.add(resources.STONE, 1)   -- Add 1 stone

-- Subtract resources (negative deltas)
resources.add(resources.FOOD, -3)   -- Remove 3 food
resources.add(resources.GOLD, -50)  -- Remove 50 gold

-- Using strings directly (also valid)
resources.add("wood", 15)           -- Add 15 wood
resources.add("stone", -2)          -- Remove 2 stone
```

## Negative Resource Support

### Full Negative Delta Support
**✅ CONFIRMED**: The system fully supports negative resource changes.

**Evidence from Implementation**:
```lua
function resources.add(resource_type, amount)
    local previous_value = _resources[resource_type]
    local new_value = previous_value + amount  -- Direct addition (supports negative)
    new_value = math.max(0, math.min(new_value, RESOURCE_CAP))  -- Clamp [0, 9999]
    _resources[resource_type] = new_value

    return new_value
end
```

**Key Features**:
- Accepts any numeric `amount` parameter (positive, negative, or zero)
- Automatically clamps final result to valid range [0, 9999]
- Used internally by `try_spend()` with explicit negative amounts
- Safe from underflow/overflow through bounds checking

### Validation and Safety Checks

#### 1. **Bounds Clamping**
```lua
new_value = math.max(0, math.min(new_value, RESOURCE_CAP))
```
- **Lower bound**: Resources cannot go below 0
- **Upper bound**: Resources cannot exceed 9999 (`RESOURCE_CAP`)
- **Behavior**: Input deltas are accepted, but results are clamped to valid range

#### 2. **Resource Type Validation**
```lua
if not _resources[resource_type] then
    error("Unknown resource type: " .. tostring(resource_type))
end
```
- Throws error for unknown resource types
- Prevents typos and invalid resource identifiers
- Only accepts: "food", "wood", "stone", "gold"

#### 3. **Event System Integration**
```lua
local delta = new_value - previous_value

if new_value ~= previous_value then
    signal.emit("idle.resource_total", resource_type, new_value)
    if delta > 0 then
        signal.emit("idle.resource_added", resource_type, new_value, delta)
    end
end
```
- Emits `"idle.resource_total"` signal for all changes
- Emits `"idle.resource_added"` signal only for positive net gains
- Provides event system integration for UI updates

#### 4. **Income Tracking**
```lua
-- Track positive income for rate display
if amount > 0 then
    _income_tracker.current_window[resource_type] =
        (_income_tracker.current_window[resource_type] or 0) + amount
end
```
- Only tracks positive amounts for income rate calculations
- Negative amounts (spending) don't affect income rate display
- Used by `get_rate()` function for per-second rate display

## Atomic Spending Function

### 2. `resources.try_spend(costs)`
**Location**: `assets/scripts/idle_game/resources.lua:134-148`

**Purpose**: Atomically spend multiple resources or fail without partial spending

**Parameters**:
- `costs` (table): Resource requirements `{food = amount, wood = amount, ...}`

**Returns**:
- `boolean`: `true` if successful, `false` if insufficient resources

**Implementation Pattern**:
```lua
function resources.try_spend(costs)
    if not costs then return true end

    -- First pass: validate all costs
    if not resources.can_afford(costs) then
        return false
    end

    -- Second pass: spend atomically using negative deltas
    for resource_type, cost in pairs(costs) do
        resources.add(resource_type, -cost)  -- Uses negative amounts
    end

    return true
end
```

**Example Usage**:
```lua
-- Define costs for a building
local building_cost = {
    wood = 25,
    stone = 10,
    food = 5
}

-- Attempt to spend resources atomically
if resources.try_spend(building_cost) then
    print("Building purchased successfully!")
    -- All resources were deducted
else
    print("Insufficient resources for building")
    -- No resources were spent
end
```

## Usage Patterns and Examples

### Passive Resource Generation
**From**: `assets/scripts/idle_game/resources.lua:89`

```lua
function resources.update(dt, upgrade_levels)
    -- Calculate upgrade-modified rates
    local gold_level = upgrade_levels.gold or 0
    local gold_rate = gold_base * (1 + gold_level * 0.25)  -- 25% per upgrade level

    -- Add fractional amounts per frame
    resources.add("gold", gold_rate * dt)
end
```

### AI Entity Resource Collection
**From**: `assets/scripts/ai/actions/idle_harvest_wood.lua:58`

```lua
-- Calculate yield with entity bonuses
local base_yield = 1 + math.floor(upgrade_level * 0.5)
local is_lumberjack = spawner._lumberjacks and spawner._lumberjacks[entity_id]
local yield = is_lumberjack and math.floor(base_yield * 1.5) or base_yield

-- Add resources with bonus multiplier
resources.add("wood", yield)  -- Could be 1, 2, 3+ depending on upgrades/bonuses
```

### Mining with Entity Specialization
**From**: `assets/scripts/ai/actions/idle_harvest_stone.lua:61`

```lua
local spawner = require("idle_game.spawner")
local is_miner = spawner._miners and spawner._miners[entity_id]
local yield = is_miner and math.floor(base_yield * 1.5) or base_yield

resources.add("stone", yield)  -- 1.5x bonus for miner entities
```

### Error Recovery with Bounds Safety
```lua
-- Safe to use extreme values - system handles clamping
resources.add("food", 99999)    -- Result: clamped to 9999
resources.add("wood", -99999)   -- Result: clamped to 0

-- Multiple operations are safe
resources.add("gold", 5000)     -- Current: 5000
resources.add("gold", 5000)     -- Current: 9999 (clamped to cap)
resources.add("gold", -10000)   -- Current: 0 (clamped to minimum)
```

## Rate Calculation Support

### 3. `resources.get_rate(resource_type)`
**Location**: `assets/scripts/idle_game/resources.lua:99-120`

**Purpose**: Get income rate per second for a resource type

**Parameters**:
- `resource_type` (string): Resource identifier

**Returns**:
- `number`: Resource gain per second (averaged over recent window)

**Rate Calculation Details**:
```lua
-- Income tracking (only positive amounts count toward rates)
if amount > 0 then  -- from resources.add()
    _income_tracker.current_window[resource_type] =
        (_income_tracker.current_window[resource_type] or 0) + amount
end

-- Rate calculation (smoothed over time windows)
function resources.get_rate(resource_type)
    local windows = _income_tracker.windows
    if #windows == 0 then return 0 end

    local total = 0
    local count = 0
    for _, window in ipairs(windows) do
        total = total + (window[resource_type] or 0)
        count = count + 1
    end

    return count > 0 and (total / count) or 0
end
```

## Integration with Other Systems

### Signal Emission for UI Updates
```lua
-- Emitted when any resource total changes
signal.emit("idle.resource_total", resource_type, new_value)

-- Emitted only when resources increase (positive delta)
if delta > 0 then
    signal.emit("idle.resource_added", resource_type, new_value, delta)
end
```

### Upgrade System Integration
**From**: `assets/scripts/idle_game/resources.lua:75-95`

```lua
-- Passive gold generation based on upgrade levels
function resources.update(dt, upgrade_levels)
    local gold_level = upgrade_levels.gold or 0
    local gold_base = 0.1  -- Base rate: 0.1 gold per second
    local gold_rate = gold_base * (1 + gold_level * 0.25)  -- +25% per level

    resources.add("gold", gold_rate * dt)
end
```

### Entity Spawning Cost Validation
```lua
-- Example: Check if player can afford entity spawn
local spawn_cost = {food = 10, wood = 5}

if resources.can_afford(spawn_cost) then
    if resources.try_spend(spawn_cost) then
        spawner.spawnForagerAt(click_x, click_y)
        print("Forager spawned!")
    end
else
    print("Need " .. spawn_cost.food .. " food and " .. spawn_cost.wood .. " wood")
end
```

## API Reference Summary

| Function | Input | Output | Supports Negatives | Bounds Checking | Event Emission |
|----------|-------|--------|-------------------|-----------------|----------------|
| `resources.add(type, amount)` | Any number | Clamped result | ✅ Yes | ✅ [0, 9999] | ✅ Yes |
| `resources.try_spend(costs)` | Cost table | Boolean success | ✅ Uses negative add() | ✅ Pre-validated | ✅ Yes |
| `resources.can_afford(costs)` | Cost table | Boolean | N/A (read-only) | N/A | ❌ No |
| `resources.get(type)` | Type string | Current amount | N/A (read-only) | N/A | ❌ No |
| `resources.get_rate(type)` | Type string | Rate per second | N/A (derived) | N/A | ❌ No |

## Testing Examples

```lua
-- Test negative delta support
local initial_food = resources.get("food")  -- e.g., 50
resources.add("food", -30)
local result = resources.get("food")        -- Should be 20

-- Test bounds clamping
resources.add("wood", 99999)
local capped = resources.get("wood")        -- Should be 9999 (capped)

-- Test underflow protection
resources.add("stone", -99999)
local protected = resources.get("stone")    -- Should be 0 (protected)

-- Test atomic spending
local success = resources.try_spend({food = 100, wood = 200})  -- Should fail if insufficient
assert(success == false or (resources.get("food") >= 0 and resources.get("wood") >= 0))
```

## Related Documentation

- Resources Read Totals API: `/api_documentation/resources_read_totals_api.md`
- Upgrades Purchase API: `/api_documentation/upgrades_purchase_api.md`
- Implementation: `/assets/scripts/idle_game/resources.lua`
- Usage Examples: `/assets/scripts/ai/actions/idle_*.lua`