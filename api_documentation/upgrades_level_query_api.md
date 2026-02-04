# Upgrades Level Query API Documentation

## Overview
The upgrades system provides functions for querying upgrade levels and related information. This document identifies the current API and notes missing functionality.

## Current Level Query Functions

### 1. `upgrades.get_level(upgrade_id)`
**Location**: `assets/scripts/idle_game/upgrades.lua:95-97`

**Purpose**: Get the current level of an upgrade

**Parameters**:
- `upgrade_id` (string): The unique identifier of the upgrade (e.g., "click_wood", "passive_gold")

**Returns**:
- `number`: Current level of the upgrade (0 if not purchased)

**Example Usage**:
```lua
local wood_click_level = upgrades.get_level("click_wood")  -- Returns 0-10
local passive_gold_level = upgrades.get_level("passive_gold")  -- Returns 0-10
```

**Implementation**:
```lua
function upgrades.get_level(upgrade_id)
    return upgrades._levels[upgrade_id] or 0
end
```

## Missing Max Level Query Function

### **IDENTIFIED NEED**: `upgrades.get_max_level(upgrade_id)`
**Status**: Not implemented (missing from API)

**Purpose**: Get the maximum level for an upgrade

**Current Workaround**: Max level information is stored in upgrade definitions but not exposed via API

**Data Location**: Each upgrade definition contains `max_level` field:
```lua
click_wood = {
    name = "Stronger Axe",
    description = "Increase wood per click",
    base_cost = {wood = 10},
    max_level = 10,  -- <-- This data exists but no API to access it
    effect = {type = "click_multiplier", resource = "wood", amount = 1}
}
```

**Recommended Implementation**:
```lua
function upgrades.get_max_level(upgrade_id)
    local upgrade = UPGRADES[upgrade_id]
    if not upgrade then
        error("Unknown upgrade: " .. tostring(upgrade_id))
    end
    return upgrade.max_level
end
```

## Related Query Functions

### 2. `upgrades.can_afford(upgrade_id, resources_module)`
**Location**: `assets/scripts/idle_game/upgrades.lua:119-141`

**Purpose**: Check if player can afford the next level (includes max level check)

**Returns**: `boolean` - false if at max level or insufficient resources

**Note**: This function internally checks max level but doesn't expose the max level value

### 3. `upgrades.get_all()`
**Location**: `assets/scripts/idle_game/upgrades.lua:160-162`

**Purpose**: Get all upgrade definitions (includes max_level data)

**Returns**: Table containing all upgrade definitions

**Note**: Provides access to max level data but requires table traversal

## Upgrade Definitions Summary

All upgrades have `max_level = 10`:

| Upgrade ID | Name | Max Level |
|------------|------|-----------|
| click_wood | Stronger Axe | 10 |
| click_stone | Better Pickaxe | 10 |
| passive_gold | Gold Mine | 10 |
| creature_speed | Creature Training | 10 |
| forage_amount | Better Basket | 10 |
| forage_speed | Efficient Foraging | 10 |
| tree_regrowth | Tree Sapling Farming | 10 |
| rock_regrowth | Rock Formation | 10 |
| max_creatures | Better Housing | 10 |
| starting_wood | Initial Resources I | 10 |
| starting_stone | Initial Resources II | 10 |
| click_range | Extended Reach | 10 |

## API Usage Patterns

### Check Current vs Max Level
```lua
local current = upgrades.get_level("click_wood")
-- Currently requires manual reference to definitions:
local max = 10  -- Hard-coded knowledge

-- Better approach (requires missing API):
-- local max = upgrades.get_max_level("click_wood")

local is_maxed = (current >= max)
```

### Progress Calculation
```lua
local current = upgrades.get_level("passive_gold")
-- local max = upgrades.get_max_level("passive_gold")  -- Missing API
local progress = current / max  -- Requires max level API
```

## Recommendations

### 1. Implement Missing API
Add `upgrades.get_max_level(upgrade_id)` function to provide clean access to max level information.

### 2. Consider Additional Helpers
- `upgrades.is_maxed(upgrade_id)` - Check if upgrade is at max level
- `upgrades.get_progress(upgrade_id)` - Get level progress as fraction (current/max)
- `upgrades.get_remaining_levels(upgrade_id)` - Get how many levels can still be purchased

### 3. API Consistency
Ensure all upgrade query functions follow similar patterns for error handling and parameter validation.

## Implementation Priority
The missing `get_max_level` function is needed for UI display logic and progression systems.