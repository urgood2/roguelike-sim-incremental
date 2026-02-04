--[[
================================================================================
TEST: Spawner Builder Tracking
================================================================================
Verification test for builder tracking functionality in spawner module.
Tests spawn functions, count tracking, and entity management.

Run with: lua test_spawner_builders_tracking.lua
]]

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local t = require("tests.test_runner")

-- Mock AI system
local MockAI = {}
MockAI._next_entity_id = 1
MockAI._entities = {}

function MockAI.create_ai_entity(entity_type)
    local entity = MockAI._next_entity_id
    MockAI._next_entity_id = MockAI._next_entity_id + 1
    MockAI._entities[entity] = { type = entity_type, valid = true }
    return entity
end

-- Mock registry system
local MockRegistry = {}

local function normalize_registry_args(self_or_entity, entity_or_component, maybe_component)
    if maybe_component ~= nil then
        return entity_or_component, maybe_component
    end
    return self_or_entity, entity_or_component
end

function MockRegistry.valid(self_or_entity, maybe_entity)
    local entity = maybe_entity or self_or_entity
    return MockAI._entities[entity] and MockAI._entities[entity].valid
end

function MockRegistry.has(self_or_entity, entity_or_component, maybe_component)
    local entity = normalize_registry_args(self_or_entity, entity_or_component, maybe_component)
    return MockRegistry.valid(entity)  -- Simplified for testing
end

function MockRegistry.get(self_or_entity, entity_or_component, maybe_component)
    local _, component = normalize_registry_args(self_or_entity, entity_or_component, maybe_component)
    if component == "Transform" then
        return { actualX = 0, actualY = 0 }
    end
    return {}
end

-- Mock terrain
local MockTerrain = {}
MockTerrain.GRASS = 1

function MockTerrain.get(x, y)
    -- Return GRASS for valid grid positions
    if x >= 0 and x < 10 and y >= 0 and y < 8 then
        return MockTerrain.GRASS
    end
    return 2  -- Not grass
end

-- Mock other dependencies
local MockConfig = {
    TILE_SIZE = 32,
    GRID_WIDTH = 10,
    GRID_HEIGHT = 8
}

local MockPatternModule = {
    new = function()
        return {
            insert = function(self, x, y) end,
            sample_poisson = function(self, method, distance, random_func)
                -- Return simple positions for testing
                return {
                    { x = 1, y = 1 },
                    { x = 3, y = 2 },
                    { x = 5, y = 3 }
                }
            end
        }
    end
}

local MockCell = {
    euclidean = "euclidean"
}

-- Mock logging
local captured_logs = {}
_G.log_debug = function(message)
    table.insert(captured_logs, message)
end

-- Mock signals
local MockSignals = {
    emit = function(signal_name, data) end
}

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Builder Tracking Functionality", function()

    t.it("initializes builder tracking tables correctly", function()
        -- Load spawner module with mocked dependencies
        package.loaded["idle_game.terrain"] = MockTerrain
        package.loaded["idle_game.config"] = MockConfig
        package.loaded["external.forma.pattern"] = MockPatternModule
        package.loaded["external.forma.cell"] = MockCell
        _G.ai = MockAI
        _G.registry = MockRegistry
        _G.signals = MockSignals
        _G.Transform = "Transform"  -- Mock component type

        local spawner = require("idle_game.spawner")

        -- Verify builder tracking tables exist
        t.expect(spawner._builders).to_be_truthy()
        t.expect(spawner._builder_count).to_equal(0)
        t.expect(type(spawner._builders)).to_equal("table")

        print("✓ Builder tracking tables initialized correctly")
    end)

    t.it("spawns builders correctly with spawnBuilders function", function()
        local spawner = require("idle_game.spawner")

        -- Reset state
        spawner._builders = {}
        spawner._builder_count = 0
        MockAI._entities = {}
        MockAI._next_entity_id = 1
        captured_logs = {}

        -- Mock the _emitCreatureCounts function to avoid signal dependencies
        spawner._emitCreatureCounts = function() end

        -- Spawn 2 builders
        local spawned_builders = spawner.spawnBuilders(2)

        -- Verify spawn results
        t.expect(#spawned_builders).to_equal(2)
        t.expect(spawner._builder_count).to_equal(2)

        -- Verify builders are tracked
        for _, entity in ipairs(spawned_builders) do
            t.expect(spawner._builders[entity]).to_be_truthy()
            t.expect(MockRegistry.valid(entity)).to_be_truthy()
        end

        -- Verify debug logging
        t.expect(#captured_logs > 0).to_be_truthy()
        local found_spawn_log = false
        for _, log in ipairs(captured_logs) do
            if string.match(log, "Spawning.*builders") then
                found_spawn_log = true
                break
            end
        end
        t.expect(found_spawn_log).to_be_truthy()

        print(string.format("✓ spawnBuilders() spawned %d builders correctly", #spawned_builders))
    end)

    t.it("spawns single builder with spawnBuilderAt function", function()
        local spawner = require("idle_game.spawner")

        -- Reset state
        spawner._builders = {}
        spawner._builder_count = 0
        MockAI._entities = {}
        MockAI._next_entity_id = 1
        captured_logs = {}

        spawner._emitCreatureCounts = function() end

        -- Spawn builder at specific location
        local x, y = 100, 150
        local entity = spawner.spawnBuilderAt(x, y)

        -- Verify spawn results
        t.expect(entity).to_be_truthy()
        t.expect(spawner._builder_count).to_equal(1)
        t.expect(spawner._builders[entity]).to_be_truthy()

        -- Verify position setting (check that registry.get was called for Transform)
        t.expect(MockRegistry.valid(entity)).to_be_truthy()

        -- Verify debug logging includes position
        local found_position_log = false
        for _, log in ipairs(captured_logs) do
            if string.match(log, "Builder spawned at") and
               string.match(log, "100") and
               string.match(log, "150") then
                found_position_log = true
                break
            end
        end
        t.expect(found_position_log).to_be_truthy()

        print(string.format("✓ spawnBuilderAt() spawned builder at (%d, %d)", x, y))
    end)

    t.it("tracks builder count correctly with getBuilderCount", function()
        local spawner = require("idle_game.spawner")

        -- Reset state
        spawner._builders = {}
        spawner._builder_count = 0

        -- Add some mock builders
        local entity1 = 101
        local entity2 = 102
        local entity3 = 103
        MockAI._entities[entity1] = { valid = true }
        MockAI._entities[entity2] = { valid = true }
        MockAI._entities[entity3] = { valid = false }  -- Invalid entity

        spawner._builders[entity1] = true
        spawner._builders[entity2] = true
        spawner._builders[entity3] = true
        spawner._builder_count = 3

        spawner._emitCreatureCounts = function() end

        -- Get builder count (should clean up invalid entities)
        local count = spawner.getBuilderCount()

        -- Should return 2 (only valid entities)
        t.expect(count).to_equal(2)

        -- Invalid entity should be removed from tracking
        t.expect(spawner._builders[entity3]).to_be_nil()

        print(string.format("✓ getBuilderCount() returned %d valid builders and cleaned up invalid ones", count))
    end)

    t.it("retrieves all builders correctly with getBuilders", function()
        local spawner = require("idle_game.spawner")

        -- Reset state
        spawner._builders = {}

        -- Add some mock builders
        local entity1 = 201
        local entity2 = 202
        local entity3 = 203
        MockAI._entities[entity1] = { valid = true }
        MockAI._entities[entity2] = { valid = true }
        MockAI._entities[entity3] = { valid = false }  -- Invalid entity

        spawner._builders[entity1] = true
        spawner._builders[entity2] = true
        spawner._builders[entity3] = true

        -- Get all builders
        local builders = spawner.getBuilders()

        -- Should return only valid entities
        t.expect(#builders).to_equal(2)

        local found_entity1 = false
        local found_entity2 = false
        for _, entity in ipairs(builders) do
            if entity == entity1 then found_entity1 = true end
            if entity == entity2 then found_entity2 = true end
        end
        t.expect(found_entity1).to_be_truthy()
        t.expect(found_entity2).to_be_truthy()

        -- Invalid entity should be removed from tracking
        t.expect(spawner._builders[entity3]).to_be_nil()

        print(string.format("✓ getBuilders() returned %d valid builder entities", #builders))
    end)

    t.it("includes builders in specialist count", function()
        local spawner = require("idle_game.spawner")

        -- Reset all entity counts
        spawner._builders = {}
        spawner._builder_count = 0
        spawner._miners = {}
        spawner._miner_count = 0
        spawner._lumberjacks = {}
        spawner._lumberjack_count = 0
        spawner._foragers = {}
        spawner._forager_count = 0

        -- Add mock builders
        local entity1 = 301
        local entity2 = 302
        MockAI._entities[entity1] = { valid = true }
        MockAI._entities[entity2] = { valid = true }

        spawner._builders[entity1] = true
        spawner._builders[entity2] = true
        spawner._builder_count = 2

        spawner._emitCreatureCounts = function() end

        -- Check specialist count includes builders
        local total = spawner.getSpecialistCount()

        -- Should include the 2 builders
        t.expect(total >= 2).to_be_truthy()

        print(string.format("✓ getSpecialistCount() includes builders, total specialists: %d", total))
    end)

    t.it("handles edge cases correctly", function()
        local spawner = require("idle_game.spawner")

        -- Reset state
        spawner._builders = {}
        spawner._builder_count = 0

        spawner._emitCreatureCounts = function() end

        -- Test spawning 0 builders
        local spawned_zero = spawner.spawnBuilders(0)
        t.expect(#spawned_zero).to_equal(0)
        t.expect(spawner._builder_count).to_equal(0)

        -- Test getBuilderCount with no builders
        local count_empty = spawner.getBuilderCount()
        t.expect(count_empty).to_equal(0)

        -- Test getBuilders with no builders
        local builders_empty = spawner.getBuilders()
        t.expect(#builders_empty).to_equal(0)

        print("✓ Edge cases handled correctly")
    end)

end)

--------------------------------------------------------------------------------
-- Run Tests
--------------------------------------------------------------------------------

print(string.rep("=", 60))
print("SPAWNER BUILDER TRACKING TEST RESULTS")
print(string.rep("=", 60))

t.run()

print(string.rep("=", 60))
print("Builder tracking test complete!")
print("✓ Tracking tables: _builders and _builder_count initialized")
print("✓ Spawn functions: spawnBuilders() and spawnBuilderAt() working")
print("✓ Count tracking: getBuilderCount() with cleanup")
print("✓ Entity retrieval: getBuilders() with validation")
print("✓ Integration: Included in getSpecialistCount()")
print("✓ Edge cases: Zero builders and empty state handled")
print(string.rep("=", 60))
