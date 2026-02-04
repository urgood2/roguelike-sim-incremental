# Spawner Creature Tracking API Documentation

## Overview
The spawner system manages entity tracking for all creature types in the game through boolean-set tables indexed by entity IDs. This document details the foragers table keying mechanism, count access methods, and comprehensive tracking patterns used across all creature types.

## Core Tracking Architecture

### Entity ID Keying System
**Location**: `assets/scripts/idle_game/spawner.lua:9-30`

**Table Structure Pattern**:
```lua
spawner._foragers = {}        -- Entity ID → boolean set
spawner._forager_count = 0    -- Cached count for performance

-- All creature types use identical pattern
spawner._lumberjacks = {}
spawner._miners = {}
spawner._collectors = {}
spawner._builders = {}
```

**Keying Mechanism**:
- **Key Type**: Entity ID (numeric, assigned by ECS registry)
- **Value Type**: Boolean `true` (simple existence flag)
- **Purpose**: Fast O(1) lookup and existence checking

**Example Usage**:
```lua
-- Add entity to tracking
local entity = ai.create_ai_entity("forager")
spawner._foragers[entity] = true
spawner._forager_count = spawner._forager_count + 1

-- Check if entity is tracked
if spawner._foragers[entity] then
    print("Entity " .. entity .. " is a forager")
end

-- Remove entity from tracking
spawner._foragers[entity] = nil
spawner._forager_count = spawner._forager_count - 1
```

## Count Access Methods

### Universal Count Pattern
**Implementation**: All creature types follow identical count validation pattern

```lua
function spawner.getCreatureTypeCount()
    local count = 0
    local cleaned_any = false

    -- Validate all tracked entities
    for entity, _ in pairs(spawner._creature_type_table) do
        if registry:valid(entity) then
            count = count + 1
        else
            -- Remove dead entities
            spawner._creature_type_table[entity] = nil
            spawner._creature_type_count = spawner._creature_type_count - 1
            cleaned_any = true
        end
    end

    -- Emit signal only if cleanup occurred
    if cleaned_any then
        spawner._emitCreatureCounts()
    end

    return count
end
```

### Available Count Methods

#### 1. `spawner.getForagerCount()`
**Location**: `assets/scripts/idle_game/spawner.lua:162-182`

**Purpose**: Get current number of valid forager entities

**Returns**:
- `number`: Count of valid foragers (after cleanup)

**Example**:
```lua
local forager_count = spawner.getForagerCount()
print("Active foragers: " .. forager_count)
```

#### 2. `spawner.getLumberjackCount()`
**Location**: `assets/scripts/idle_game/spawner.lua:277-296`

**Purpose**: Get current number of valid lumberjack entities

**Returns**:
- `number`: Count of valid lumberjacks (after cleanup)

#### 3. `spawner.getMinerCount()`
**Location**: `assets/scripts/idle_game/spawner.lua:398-417`

**Purpose**: Get current number of valid miner entities

**Returns**:
- `number`: Count of valid miners (after cleanup)

#### 4. `spawner.getCollectorCount()`
**Location**: `assets/scripts/idle_game/spawner.lua:300-319`

**Purpose**: Get current number of valid collector entities

**Returns**:
- `number`: Count of valid collectors (after cleanup)

**Note**: ⚠️ Spawn methods not yet implemented for collectors

#### 5. `spawner.getBuilderCount()`
**Location**: `assets/scripts/idle_game/spawner.lua:512-531`

**Purpose**: Get current number of valid builder entities

**Returns**:
- `number`: Count of valid builders (after cleanup)

#### 6. `spawner.getCorpseCount()`
**Location**: `assets/scripts/idle_game/spawner.lua:636-638`

**Purpose**: Get current number of corpse markers

**Returns**:
- `number`: Count of corpse positions

**Implementation**:
```lua
function spawner.getCorpseCount()
    return #spawner._corpses  -- Simple array length
end
```

**Note**: Corpses use array-based tracking, not entity ID sets

## Creature Types and Tracking Tables

### Tracked Creature Types

| Type | Tracking Table | Count Cache | Spawn Methods | Implementation Status |
|------|-----------------|-------------|---------------|----------------------|
| **Foragers** | `_foragers` | `_forager_count` | ✅ Both batch/individual | Complete |
| **Lumberjacks** | `_lumberjacks` | `_lumberjack_count` | ✅ Both batch/individual | Complete |
| **Miners** | `_miners` | `_miner_count` | ✅ Both batch/individual | Complete |
| **Collectors** | `_collectors` | `_collector_count` | ❌ Missing (TODO) | Partial |
| **Builders** | `_builders` | `_builder_count` | ✅ Both batch/individual | Complete |
| **Corpses** | `_corpses` | N/A | Manual placement | Array-based |

### Creature Specializations

#### Foragers (Generalist)
- **Behavior**: Forage trees and rocks
- **Harvest Multiplier**: 1.0x (baseline)
- **Survival System**: ✅ Hunger, energy, age, reproduction
- **Passive Income**: ✅ Auto-harvest nearby resources

#### Lumberjacks (Wood Specialist)
- **Behavior**: Target trees only (no rocks)
- **Harvest Multiplier**: 1.5x wood yield
- **Survival System**: ✅ Full survival mechanics
- **Passive Income**: ✅ Auto-harvest trees

#### Miners (Stone Specialist)
- **Behavior**: Target rocks only (no trees)
- **Harvest Multiplier**: 1.5x stone yield
- **Survival System**: ❌ Not yet implemented
- **Passive Income**: ✅ Auto-harvest rocks

#### Collectors (Item Specialist)
- **Behavior**: Pick up ground items
- **Harvest Multiplier**: N/A
- **Survival System**: ❌ Not implemented
- **Passive Income**: 🔄 Partial (sensing exists, spawn missing)

#### Builders (Construction)
- **Behavior**: Construction tasks
- **Harvest Multiplier**: N/A
- **Survival System**: ❌ Not implemented
- **Passive Income**: ❌ No implementation yet

## Entity Lifecycle Management

### Addition (Spawn Process)
**Pattern for all creature types**:

```lua
function spawner.spawnCreatureTypeAt(x, y)
    -- 1. Create AI entity
    local entity = ai.create_ai_entity("creature_type")

    -- 2. Set position
    local transform = component_cache.get(entity, Transform)
    transform.actualX = x
    transform.actualY = y

    -- 3. Setup visuals
    animation_system.setupAnimatedObjectOnEntity(entity, sprite_config)

    -- 4. Track entity
    spawner._creature_type_table[entity] = true
    spawner._creature_type_count = spawner._creature_type_count + 1

    -- 5. Emit signal
    spawner._emitCreatureCounts()

    return entity
end
```

### Removal (3 Methods)

#### Method 1: Automatic Cleanup (Lazy)
**Location**: Count methods (e.g., `getForagerCount()`)

```lua
-- Cleanup during count validation
for entity, _ in pairs(spawner._foragers) do
    if not registry:valid(entity) then
        spawner._foragers[entity] = nil
        spawner._forager_count = spawner._forager_count - 1
        cleaned_any = true
    end
end
```

#### Method 2: Deferred Destruction Queue (Safe)
**Location**: `assets/scripts/idle_game/spawner.lua:640-667`

```lua
-- Queue for destruction (safe during AI updates)
function spawner.queueDestroy(entity)
    table.insert(spawner._pending_destroy, entity)
end

-- Process after AI frame completes
function spawner.processPendingDestructions()
    for _, entity in ipairs(spawner._pending_destroy) do
        if registry:valid(entity) then
            registry:destroy(entity)
        end
        -- Remove from ALL tracking tables
        spawner._foragers[entity] = nil
        spawner._lumberjacks[entity] = nil
        spawner._collectors[entity] = nil
        spawner._miners[entity] = nil
        spawner._builders[entity] = nil
    end

    spawner._pending_destroy = {}
    if destroyed_any then
        spawner._emitCreatureCounts()
    end
end
```

#### Method 3: Manual Removal (Immediate)
```lua
-- Direct removal without validation
spawner._foragers[entity] = nil
spawner._forager_count = spawner._forager_count - 1
```

## Signal System Integration

### Creature Count Signal
**Signal Name**: `"idle.creature_counts"`
**Location**: `assets/scripts/idle_game/spawner.lua:690-718`

**Payload Structure**:
```lua
{
    foragers = number,     -- Current forager count
    lumberjacks = number,  -- Current lumberjack count
    collectors = number,   -- Current collector count
    miners = number,       -- Current miner count
    builders = number,     -- Current builder count
    corpses = number       -- Current corpse count
}
```

**Emission Implementation**:
```lua
function spawner._emitCreatureCounts()
    -- Prevent re-entrant calls
    if spawner._emitting_signal then
        return
    end

    local signals = require("idle_game.signals")
    if signals and signals.emit then
        spawner._emitting_signal = true

        -- Gather all counts (triggers cleanup)
        local counts = {
            foragers = spawner.getForagerCount(),
            lumberjacks = spawner.getLumberjackCount(),
            collectors = spawner.getCollectorCount(),
            miners = spawner.getMinerCount(),
            builders = spawner.getBuilderCount(),
            corpses = spawner.getCorpseCount()
        }

        signals.emit("idle.creature_counts", counts)
        spawner._emitting_signal = false
    end
end
```

**Signal Emission Triggers**:
- After any spawn operation
- During count cleanup (when dead entities found)
- After processing pending destructions
- Manual triggering via `_emitCreatureCounts()`

### Signal Listeners

#### Achievement System
**Location**: `assets/scripts/idle_game/achievement_listener.lua:170`

```lua
-- Population-based achievement evaluation
signal.register("idle.creature_counts", function(counts)
    -- Check population milestones
    if counts.foragers >= 10 then
        achievements.unlock("forager_colony")
    end

    local total_specialists = counts.lumberjacks + counts.miners + counts.builders
    if total_specialists >= 5 then
        achievements.unlock("specialist_workforce")
    end
end)
```

#### UI Updates
**Resource Panel**: Displays creature counts in sidebar
**Statistics Panel**: Shows population trends and growth rates

## Specialized Access Methods

### 1. `spawner.getForagers()`
**Purpose**: Get list of all forager entity IDs

**Returns**: `table` - Array of entity IDs

**Implementation**:
```lua
function spawner.getForagers()
    local foragers = {}
    for entity, _ in pairs(spawner._foragers) do
        if registry:valid(entity) then
            table.insert(foragers, entity)
        end
    end
    return foragers
end
```

### 2. `spawner.getSpecialistCount()`
**Purpose**: Get combined count of all specialist creatures (non-foragers)

**Returns**: `number` - Total specialist count

**Implementation**:
```lua
function spawner.getSpecialistCount()
    return spawner.getLumberjackCount() +
           spawner.getMinerCount() +
           spawner.getCollectorCount() +
           spawner.getBuilderCount()
end
```

## Usage Examples

### Basic Spawning and Tracking
```lua
-- Spawn foragers at specific location
local forager = spawner.spawnForagerAt(100, 100)
print("Spawned forager: " .. forager)

-- Check if entity is tracked as forager
if spawner._foragers[forager] then
    print("Entity is tracked as forager")
end

-- Get current counts
local counts = {
    foragers = spawner.getForagerCount(),
    lumberjacks = spawner.getLumberjackCount(),
    miners = spawner.getMinerCount()
}
print("Population - Foragers: " .. counts.foragers ..
      ", Lumberjacks: " .. counts.lumberjacks ..
      ", Miners: " .. counts.miners)
```

### Batch Operations
```lua
-- Spawn multiple creatures using Poisson distribution
spawner.spawnForagers(5)     -- Spawn 5 foragers randomly placed
spawner.spawnLumberjacks(3)  -- Spawn 3 lumberjacks randomly placed
spawner.spawnMiners(2)       -- Spawn 2 miners randomly placed

-- Check total population
local total = spawner.getForagerCount() +
              spawner.getLumberjackCount() +
              spawner.getMinerCount()
print("Total population: " .. total)
```

### Signal-Based Population Management
```lua
-- Listen for population changes
local signals = require("idle_game.signals")

signals.register("idle.creature_counts", function(counts)
    local total_population = counts.foragers + counts.lumberjacks +
                            counts.miners + counts.builders

    if total_population > 20 then
        print("Population is getting large: " .. total_population)
    end

    if counts.corpses > 5 then
        print("High mortality detected: " .. counts.corpses .. " corpses")
    end
end)
```

### Entity Validation and Cleanup
```lua
-- Manual validation and cleanup
local dead_foragers = {}
for entity, _ in pairs(spawner._foragers) do
    if not registry:valid(entity) then
        table.insert(dead_foragers, entity)
    end
end

-- Clean up dead entities
for _, entity in ipairs(dead_foragers) do
    spawner._foragers[entity] = nil
    spawner._forager_count = spawner._forager_count - 1
end

if #dead_foragers > 0 then
    print("Cleaned up " .. #dead_foragers .. " dead foragers")
    spawner._emitCreatureCounts()
end
```

### Safe Destruction During AI Updates
```lua
-- Queue entities for destruction (safe during AI processing)
function killUnhealthyCreatures()
    for entity, _ in pairs(spawner._foragers) do
        local bb = ai.get_blackboard(entity)
        if bb and bb:get_float("hunger", 0) < 10 then
            spawner.queueDestroy(entity)  -- Safe queuing
        end
    end
end

-- Process destruction queue after AI frame
spawner.processPendingDestructions()
```

## Implementation Status Summary

### Complete Implementation (4/5 types)
- ✅ **Foragers**: Full spawn, track, sense, survive, reproduce
- ✅ **Lumberjacks**: Full spawn, track, sense, survive (wood specialist)
- ✅ **Miners**: Full spawn, track, sense (stone specialist)
- ✅ **Builders**: Full spawn, track (construction role)

### Partial Implementation (1/5 types)
- 🔄 **Collectors**: Tracking table exists, no spawn methods yet
  - TODO: `spawnCollectors(count)` and `spawnCollectorAt(x, y)`
  - Sensing partially implemented in `worldstate_updaters.lua`
  - Ground item pickup behavior exists but untestable

### Development Status
- **Current Priority**: Complete collectors implementation
- **Next Phase**: Add builder behavior and construction mechanics
- **Future Work**: Advanced population dynamics and resource pressure

## Related Documentation

- Spawner Implementation: `/assets/scripts/idle_game/spawner.lua`
- AI Worldstate Updates: `/assets/scripts/ai/worldstate_updaters.lua`
- Achievement Integration: `/assets/scripts/idle_game/achievement_listener.lua`
- Signal System: `/assets/scripts/idle_game/signals.lua`
- Resource System: `/api_documentation/resources_add_delta_api.md`