--[[
================================================================================
TEST: Creature Achievement Evaluation
================================================================================
Tests that creature achievements (crt_total_25, crt_specialists_10, crt_builder_exists)
are correctly evaluated when creature counts change.

Run with: lua test_creature_achievement_evaluation.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached modules if re-running
package.loaded["idle_game.achievements"] = nil
package.loaded["idle_game.achievement_listener"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Mock Toast Queue
--------------------------------------------------------------------------------

local MockToastQueue = {}
function MockToastQueue.new()
    local self = {
        messages = {}
    }

    function self.add(message, duration)
        table.insert(self.messages, { message = message, duration = duration })
    end

    function self.get_messages()
        return self.messages
    end

    function self.clear()
        self.messages = {}
    end

    return self
end

--------------------------------------------------------------------------------
-- Mock Spawner Module
--------------------------------------------------------------------------------

local MockSpawner = {}
function MockSpawner.new()
    local self = {
        forager_count = 0,
        lumberjack_count = 0,
        collector_count = 0,
        builder_count = 0,
        miner_count = 0
    }

    function self.getForagerCount()
        return self.forager_count
    end

    function self.getLumberjackCount()
        return self.lumberjack_count
    end

    function self.getCollectorCount()
        return self.collector_count
    end

    function self.getBuilderCount()
        return self.builder_count
    end

    function self.getMinerCount()
        return self.miner_count
    end

    function self.set_counts(foragers, lumberjacks, collectors, builders, miners)
        self.forager_count = foragers or 0
        self.lumberjack_count = lumberjacks or 0
        self.collector_count = collectors or 0
        self.builder_count = builders or 0
        self.miner_count = miners or 0
    end

    return self
end

--------------------------------------------------------------------------------
-- Test Utilities
--------------------------------------------------------------------------------

local function setup_test_environment()
    local mock_toast = MockToastQueue.new()
    local mock_spawner = MockSpawner.new()

    -- Replace modules with mocks
    package.loaded["idle_game.spawner"] = mock_spawner
    _G.idle_game_spawner_mock = mock_spawner  -- Keep reference

    return mock_toast, mock_spawner
end

local function cleanup_test_environment()
    package.loaded["idle_game.spawner"] = nil
    _G.idle_game_spawner_mock = nil
end

local function simulate_creature_counts_signal(counts)
    local signal = require("external.hump.signal")
    signal.emit("idle.creature_counts", counts)
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Creature Achievement Evaluation", function()

    local achievements = nil
    local achievement_listener = nil
    local mock_toast = nil
    local mock_spawner = nil

    t.before_each(function()
        mock_toast, mock_spawner = setup_test_environment()
        achievements = require("idle_game.achievements")
        achievements.init()
        achievement_listener = require("idle_game.achievement_listener")
        achievement_listener.init(mock_toast)
    end)

    t.after_each(function()
        if achievement_listener and achievement_listener.shutdown then
            achievement_listener.shutdown()
        end
        cleanup_test_environment()
    end)

    -- Test 1: crt_total_25 achievement unlocks with 25 total creatures
    t.it("unlocks crt_total_25 achievement with 25 total creatures", function()
        mock_toast.clear()

        -- Simulate 25 total creatures (15 foragers + 10 specialists)
        local counts = {
            foragers = 15,
            lumberjacks = 5,
            collectors = 3,
            builders = 1,
            miners = 1
        }

        simulate_creature_counts_signal(counts)

        -- Verify achievement unlocked
        t.expect(achievements.is_unlocked("crt_total_25")).to_be_truthy()

        -- Check for toast notification
        local messages = mock_toast.get_messages()
        local found_toast = false
        for _, msg in ipairs(messages) do
            if string.find(msg.message, "Growing Crew") then
                found_toast = true
                break
            end
        end
        t.expect(found_toast).to_be_truthy()
    end)

    -- Test 2: crt_specialists_10 achievement unlocks with 10 specialist creatures
    t.it("unlocks crt_specialists_10 achievement with 10 specialist creatures", function()
        mock_toast.clear()

        -- Simulate exactly 10 specialists (no foragers to keep total under 25)
        local counts = {
            foragers = 5,  -- Keep total under 25 to isolate this achievement
            lumberjacks = 4,
            collectors = 3,
            builders = 2,
            miners = 1
        }

        simulate_creature_counts_signal(counts)

        -- Verify achievement unlocked
        t.expect(achievements.is_unlocked("crt_specialists_10")).to_be_truthy()

        -- Check for toast notification
        local messages = mock_toast.get_messages()
        local found_toast = false
        for _, msg in ipairs(messages) do
            if string.find(msg.message, "Specialist Force") then
                found_toast = true
                break
            end
        end
        t.expect(found_toast).to_be_truthy()
    end)

    -- Test 3: crt_builder_exists achievement unlocks with 1 builder
    t.it("unlocks crt_builder_exists achievement with 1 builder", function()
        mock_toast.clear()

        -- Simulate having exactly 1 builder
        local counts = {
            foragers = 5,
            lumberjacks = 2,
            collectors = 1,
            builders = 1,  -- This should trigger the achievement
            miners = 0
        }

        simulate_creature_counts_signal(counts)

        -- Verify achievement unlocked
        t.expect(achievements.is_unlocked("crt_builder_exists")).to_be_truthy()

        -- Check for toast notification
        local messages = mock_toast.get_messages()
        local found_toast = false
        for _, msg in ipairs(messages) do
            if string.find(msg.message, "Master Builder") then
                found_toast = true
                break
            end
        end
        t.expect(found_toast).to_be_truthy()
    end)

    -- Test 4: Achievements don't unlock prematurely
    t.it("does not unlock achievements when thresholds not met", function()
        mock_toast.clear()

        -- Simulate counts below all thresholds
        local counts = {
            foragers = 10,    -- Total: 15 (< 25)
            lumberjacks = 3,  -- Specialists: 5 (< 10)
            collectors = 2,
            builders = 0,     -- No builder
            miners = 0
        }

        simulate_creature_counts_signal(counts)

        -- Verify achievements NOT unlocked
        t.expect(achievements.is_unlocked("crt_total_25")).to_be_falsy()
        t.expect(achievements.is_unlocked("crt_specialists_10")).to_be_falsy()
        t.expect(achievements.is_unlocked("crt_builder_exists")).to_be_falsy()

        -- No toast notifications should be generated
        local messages = mock_toast.get_messages()
        t.expect(#messages).to_equal(0)
    end)

    -- Test 5: Multiple achievements can unlock simultaneously
    t.it("unlocks multiple achievements when multiple thresholds met", function()
        mock_toast.clear()

        -- Simulate counts that meet all three achievement thresholds
        local counts = {
            foragers = 5,     -- Total: 25 (>= 25) ✓
            lumberjacks = 8,  -- Specialists: 20 (>= 10) ✓
            collectors = 7,
            builders = 3,     -- Builders: 3 (>= 1) ✓
            miners = 2
        }

        simulate_creature_counts_signal(counts)

        -- Verify all achievements unlocked
        t.expect(achievements.is_unlocked("crt_total_25")).to_be_truthy()
        t.expect(achievements.is_unlocked("crt_specialists_10")).to_be_truthy()
        t.expect(achievements.is_unlocked("crt_builder_exists")).to_be_truthy()

        -- Check that multiple toast notifications were generated
        local messages = mock_toast.get_messages()
        t.expect(#messages >= 3).to_be_truthy()
    end)

    -- Test 6: Boundary conditions - exactly at thresholds
    t.it("unlocks achievements at exact threshold values", function()
        mock_toast.clear()

        -- Test crt_total_25 at exact boundary
        local counts = {
            foragers = 15,
            lumberjacks = 10,  -- Total exactly 25
            collectors = 0,
            builders = 0,
            miners = 0
        }

        simulate_creature_counts_signal(counts)
        t.expect(achievements.is_unlocked("crt_total_25")).to_be_truthy()

        -- Reset and test crt_specialists_10 at exact boundary
        achievements.init()  -- Reset achievements
        mock_toast.clear()

        counts = {
            foragers = 5,
            lumberjacks = 10,  -- Exactly 10 specialists
            collectors = 0,
            builders = 0,
            miners = 0
        }

        simulate_creature_counts_signal(counts)
        t.expect(achievements.is_unlocked("crt_specialists_10")).to_be_truthy()
    end)

    -- Test 7: Refresh and evaluate functionality
    t.it("evaluates achievements on refresh_and_evaluate", function()
        -- Setup spawner mock with counts that should unlock achievements
        mock_spawner.set_counts(5, 8, 7, 3, 2)  -- Total: 25, Specialists: 20, Builders: 3

        achievement_listener.refresh_and_evaluate()

        -- All achievements should be unlocked
        t.expect(achievements.is_unlocked("crt_total_25")).to_be_truthy()
        t.expect(achievements.is_unlocked("crt_specialists_10")).to_be_truthy()
        t.expect(achievements.is_unlocked("crt_builder_exists")).to_be_truthy()
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()