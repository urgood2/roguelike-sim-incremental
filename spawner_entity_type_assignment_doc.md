# Spawner Entity Type Assignment Documentation

## Overview
This document identifies the exact field/mechanism for entity type assignment in the spawner system.

## Entity Type Assignment Mechanism

### Core Function: `create_ai_entity(type_string)`

Entity types are assigned by passing a **string parameter** to the `create_ai_entity()` function when spawning entities.

**Function Signature:**
```lua
local entity = create_ai_entity("entity_type_name")
```

### Implementation Details

**Location:** `assets/scripts/idle_game/spawner.lua`

**Method:** Entity type is specified as the **first parameter** to `create_ai_entity()` function calls.

### Current Entity Type Assignments

| Entity Type | Spawner Function | Assignment Call | Line Reference |
|-------------|------------------|----------------|----------------|
| **forager** | `spawnForagers()` | `create_ai_entity("forager")` | Line 86 |
| **forager** | `spawnForagerAt()` | `create_ai_entity("forager")` | Line 129 |
| **lumberjack** | `spawnLumberjackAt()` | `ai.create_ai_entity("lumberjack")` | Line 255 |

### String-to-Type Mapping

The entity type assignment uses **literal string values** that correspond to:

1. **AI Entity Type Files**: `assets/scripts/ai/entity_types/[type_name].lua`
   - `"forager"` → `forager.lua`
   - `"lumberjack"` → `lumberjack.lua`
   - `"collector"` → `collector.lua`
   - `"builder"` → `builder.lua`
   - etc.

2. **Goal Selectors**: `assets/scripts/ai/goal_selectors/[type_name].lua`
   - Entity type string determines which goal selector is applied

3. **Blackboard Initialization**: `assets/scripts/ai/blackboard_init/[type_name].lua`
   - Entity type string determines initial AI state setup

### Key Observations

1. **No Entity Component Field**: Entity type is NOT stored as a component field on the entity
2. **Function Parameter Only**: Type assignment happens **only** through the create function parameter
3. **String-Based Lookup**: AI system uses the type string to load appropriate:
   - Initial worldstate atoms
   - Goal selectors
   - Blackboard initialization

### Implementation Examples

#### Forager Spawning
```lua
-- In spawnForagers() and spawnForagerAt()
local entity = create_ai_entity("forager")
```

#### Lumberjack Spawning
```lua
-- In spawnLumberjackAt()
local entity = ai.create_ai_entity("lumberjack")
```

### Tracking After Creation

After entity creation, type-specific tracking is maintained through:

1. **Spawner Tables**:
   - `spawner._foragers[entity] = true`
   - `spawner._lumberjacks[entity] = true`
   - etc.

2. **Count Variables**:
   - `spawner._forager_count`
   - `spawner._lumberjack_count`
   - etc.

## AI System Integration

The entity type string passed to `create_ai_entity()` is used by the AI system to:

1. **Load Entity Type Definition**: From `ai/entity_types/[type].lua`
2. **Apply Goal Selector**: From `ai/goal_selectors/[type].lua`
3. **Initialize Blackboard**: From `ai/blackboard_init/[type].lua`
4. **Set Worldstate Atoms**: Based on entity type initial state

## Future Entity Types

To add new entity types, the spawner would use:

```lua
-- For miners (planned)
local entity = create_ai_entity("miner")

-- For builders (planned)
local entity = create_ai_entity("builder")

-- For collectors (planned)
local entity = create_ai_entity("collector")
```

## Summary

**Entity type assignment mechanism:** String parameter passed to `create_ai_entity(type_string)` function.

**Exact field/location:** First parameter of `create_ai_entity()` calls in spawner functions.

**No persistent storage:** Entity type is not stored as a component field after creation; type identity is maintained through spawner tracking tables and AI system configuration.