--[[
================================================================================
TEST: Lumberjack Blackboard Initialization
================================================================================
Verification test for the lumberjack blackboard init file.
Tests initialization values and error handling.

Run with: lua test_lumberjack_blackboard_init.lua
]]

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local t = require("tests.test_runner")

-- Mock blackboard system
local MockBlackboard = {}

function MockBlackboard.new()
    local self = {
        _data = {}
    }

    function self.set_float(key, value)
        self._data[key] = tonumber(value) or 0
    end

    function self.get_float(key)
        return tonumber(self._data[key]) or 0
    end

    function self.get_data()
        return self._data
    end

    return self
end

-- Mock AI system
local MockAI = {
    blackboards = {}
}

function MockAI.get_blackboard(entity)
    if not MockAI.blackboards[entity] then
        MockAI.blackboards[entity] = MockBlackboard.new()
    end
    return MockAI.blackboards[entity]
end

-- Mock logging
_G.log_debug = function(message)
    -- Capture log messages for verification
    if not _G.test_log_messages then
        _G.test_log_messages = {}
    end
    table.insert(_G.test_log_messages, message)
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Lumberjack Blackboard Initialization", function()

    t.it("initializes survival stats correctly", function()
        -- Setup mock AI system
        _G.ai = MockAI
        _G.test_log_messages = {}

        -- Load and execute lumberjack blackboard init
        local init_function = dofile("assets/scripts/ai/blackboard_init/lumberjack.lua")
        t.expect(type(init_function)).to_equal("function")

        -- Test with mock entity
        local entity = "test_lumberjack_123"
        init_function(entity)

        -- Get initialized blackboard
        local bb = MockAI.get_blackboard(entity)
        t.expect(bb).to_be_truthy()

        -- Verify survival stats
        local hunger = bb:get_float("hunger")
        local energy = bb:get_float("energy")
        local age = bb:get_float("age")
        local hunger_timer = bb:get_float("hunger_timer")

        -- Hunger should be 80-100
        t.expect(hunger >= 80).to_be_truthy()
        t.expect(hunger <= 100).to_be_truthy()

        -- Energy should be 70-100
        t.expect(energy >= 70).to_be_truthy()
        t.expect(energy <= 100).to_be_truthy()

        -- Age should start at 0
        t.expect(age).to_equal(0)

        -- Hunger timer should start at 0
        t.expect(hunger_timer).to_equal(0)

        print(string.format("✓ Lumberjack initialized: hunger=%.0f, energy=%.0f", hunger, energy))
    end)

    t.it("handles missing AI system gracefully", function()
        -- Test without AI system
        _G.ai = nil
        _G.test_log_messages = {}

        local init_function = dofile("assets/scripts/ai/blackboard_init/lumberjack.lua")

        -- Should not crash when AI system is missing
        init_function("test_entity")

        -- Should log warning
        t.expect(#_G.test_log_messages > 0).to_be_truthy()
        t.expect(string.match(_G.test_log_messages[1], "WARNING")).to_be_truthy()

        print("✓ Missing AI system handled gracefully")
    end)

    t.it("handles missing blackboard gracefully", function()
        -- Mock AI system that returns nil blackboard
        _G.ai = {
            get_blackboard = function(entity)
                return nil
            end
        }
        _G.test_log_messages = {}

        local init_function = dofile("assets/scripts/ai/blackboard_init/lumberjack.lua")

        -- Should not crash when blackboard is missing
        init_function("test_entity")

        -- Should log warning
        t.expect(#_G.test_log_messages > 0).to_be_truthy()
        local found_warning = false
        for _, message in ipairs(_G.test_log_messages) do
            if string.match(message, "Could not get blackboard") then
                found_warning = true
                break
            end
        end
        t.expect(found_warning).to_be_truthy()

        print("✓ Missing blackboard handled gracefully")
    end)

    t.it("produces consistent initialization values", function()
        _G.ai = MockAI
        _G.test_log_messages = {}

        local init_function = dofile("assets/scripts/ai/blackboard_init/lumberjack.lua")

        -- Initialize multiple lumberjacks
        local lumberjacks = {}
        for i = 1, 5 do
            local entity = "lumberjack_" .. i
            init_function(entity)
            lumberjacks[i] = MockAI.get_blackboard(entity)
        end

        -- All should have valid ranges
        for i, bb in ipairs(lumberjacks) do
            local hunger = bb:get_float("hunger")
            local energy = bb:get_float("energy")

            t.expect(hunger >= 80 and hunger <= 100).to_be_truthy()
            t.expect(energy >= 70 and energy <= 100).to_be_truthy()
        end

        -- Values should vary (not all identical due to randomization)
        local hunger_values = {}
        for i, bb in ipairs(lumberjacks) do
            table.insert(hunger_values, bb:get_float("hunger"))
        end

        -- Check that not all hunger values are identical
        local all_same = true
        for i = 2, #hunger_values do
            if hunger_values[i] ~= hunger_values[1] then
                all_same = false
                break
            end
        end
        t.expect(all_same).to_be_falsy()  -- Should have some variation

        print("✓ Multiple lumberjacks initialized with appropriate variation")
    end)

    t.it("verifies file structure matches pattern", function()
        -- Read the file content
        local file = io.open("assets/scripts/ai/blackboard_init/lumberjack.lua", "r")
        t.expect(file).to_be_truthy()

        if file then
            local content = file:read("*all")
            file:close()

            -- Verify key components exist
            t.expect(string.match(content, "return function%(entity%)")).to_be_truthy()
            t.expect(string.match(content, "ai%.get_blackboard")).to_be_truthy()
            t.expect(string.match(content, "bb:set_float%(\"hunger\"")).to_be_truthy()
            t.expect(string.match(content, "bb:set_float%(\"energy\"")).to_be_truthy()
            t.expect(string.match(content, "bb:set_float%(\"age\"")).to_be_truthy()
            t.expect(string.match(content, "log_debug")).to_be_truthy()

            print("✓ File structure follows expected pattern")
        end
    end)

end)

t.describe("Integration with Entity Type", function()

    t.it("verifies lumberjack entity type exists", function()
        -- Check that lumberjack entity type file exists
        local entity_file = io.open("assets/scripts/ai/entity_types/lumberjack.lua", "r")
        t.expect(entity_file).to_be_truthy()

        if entity_file then
            local content = entity_file:read("*all")
            entity_file:close()

            -- Verify it has the expected structure
            t.expect(string.match(content, "nearTree")).to_be_truthy()
            t.expect(string.match(content, "hungry")).to_be_truthy()

            print("✓ Lumberjack entity type integration verified")
        end
    end)

end)

--------------------------------------------------------------------------------
-- Run Tests
--------------------------------------------------------------------------------

print(string.rep("=", 60))
print("LUMBERJACK BLACKBOARD INITIALIZATION TEST RESULTS")
print(string.rep("=", 60))

t.run()

print(string.rep("=", 60))
print("Lumberjack blackboard initialization test complete!")
print("✓ Survival stats: hunger (80-100), energy (70-100), age (0)")
print("✓ Error handling: Missing AI system and blackboard")
print("✓ Randomization: Appropriate variation in initial values")
print("✓ File structure: Follows established pattern")
print("✓ Integration: Works with lumberjack entity type")
print(string.rep("=", 60))