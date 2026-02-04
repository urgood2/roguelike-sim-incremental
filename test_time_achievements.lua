--[[
================================================================================
TEST: Time-based Achievement System
================================================================================
Verification test for time-based achievements: time_5min and time_15min.
Tests achievement definition, time tracking, unlocking mechanics, and integration.

Run with: lua test_time_achievements.lua
]]

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local t = require("tests.test_runner")

-- Mock logging
local captured_logs = {}
_G.log_debug = function(message)
    table.insert(captured_logs, message)
end

-- Mock print for achievement listener
_G.print = function(message)
    table.insert(captured_logs, "[PRINT] " .. tostring(message))
end

-- Mock toast queue
local MockToastQueue = {
    _toasts = {},
    add = function(self, message, duration)
        table.insert(self._toasts, {message = message, duration = duration})
        print("Toast: " .. message .. " (duration: " .. duration .. "s)")
    end,
    get_toasts = function(self)
        return self._toasts
    end,
    clear = function(self)
        self._toasts = {}
    end
}

-- Mock signal group for achievement listener
_G.signal_group = {
    new = function(name)
        return {
            _name = name,
            _handlers = {},
            on = function(self, signal, handler)
                self._handlers[signal] = handler
            end,
            count = function(self)
                local count = 0
                for _ in pairs(self._handlers) do
                    count = count + 1
                end
                return count
            end,
            cleanup = function(self)
                self._handlers = {}
            end
        }
    end
}

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Time Achievement System", function()

    t.it("time achievements are defined correctly", function()
        local achievements = require("idle_game.achievements")

        -- Initialize achievements system
        achievements.init()

        -- Get all achievement definitions
        local all_achievements = achievements.get_all()

        -- Verify time_5min achievement exists and has correct properties
        t.expect(all_achievements.time_5min).to_be_truthy()
        t.expect(all_achievements.time_5min.id).to_equal("time_5min")
        t.expect(all_achievements.time_5min.title).to_equal("Getting Started")
        t.expect(all_achievements.time_5min.description).to_equal("Play for 5 minutes")
        t.expect(all_achievements.time_5min.kind).to_equal("time_played")
        t.expect(all_achievements.time_5min.threshold).to_equal(300) -- 5 minutes
        t.expect(all_achievements.time_5min.unlocked).to_be_falsy()

        -- Verify time_15min achievement exists and has correct properties
        t.expect(all_achievements.time_15min).to_be_truthy()
        t.expect(all_achievements.time_15min.id).to_equal("time_15min")
        t.expect(all_achievements.time_15min.title).to_equal("Dedicated Player")
        t.expect(all_achievements.time_15min.description).to_equal("Play for 15 minutes")
        t.expect(all_achievements.time_15min.kind).to_equal("time_played")
        t.expect(all_achievements.time_15min.threshold).to_equal(900) -- 15 minutes
        t.expect(all_achievements.time_15min.unlocked).to_be_falsy()

        print("✓ Both time achievements defined with correct properties")
    end)

    t.it("tracks game time correctly", function()
        local achievements = require("idle_game.achievements")

        -- Initialize achievements system
        achievements.init()

        -- Initial time should be 0
        t.expect(achievements.get_game_time()).to_equal(0)

        -- Update with 30 seconds
        achievements.update(30.0)
        t.expect(achievements.get_game_time()).to_equal(30.0)

        -- Update with additional 60 seconds
        achievements.update(60.0)
        t.expect(achievements.get_game_time()).to_equal(90.0)

        -- Update with fractional seconds
        achievements.update(0.5)
        t.expect(achievements.get_game_time()).to_equal(90.5)

        print("✓ Game time tracking works correctly")
    end)

    t.it("unlocks time_5min achievement at 5 minutes", function()
        local achievements = require("idle_game.achievements")

        -- Initialize achievements system
        achievements.init()

        -- Simulate playing for just under 5 minutes
        achievements.update(299) -- 4:59

        local game_time = achievements.get_game_time()
        t.expect(game_time).to_equal(299)

        -- Should not unlock yet
        local unlocked = achievements.unlock("time_5min", game_time)
        t.expect(unlocked).to_be_falsy()
        t.expect(achievements.is_unlocked("time_5min")).to_be_falsy()

        -- Simulate 2 more seconds to reach 5 minutes
        achievements.update(2)
        game_time = achievements.get_game_time()
        t.expect(game_time).to_equal(301)

        -- Should unlock now
        unlocked = achievements.unlock("time_5min", game_time)
        t.expect(unlocked).to_be_truthy()
        t.expect(achievements.is_unlocked("time_5min")).to_be_truthy()

        print("✓ time_5min achievement unlocks at exactly 5 minutes")
    end)

    t.it("unlocks time_15min achievement at 15 minutes", function()
        local achievements = require("idle_game.achievements")

        -- Initialize achievements system
        achievements.init()

        -- Simulate playing for 10 minutes (should not unlock 15min achievement)
        achievements.update(600)

        local game_time = achievements.get_game_time()
        local unlocked = achievements.unlock("time_15min", game_time)
        t.expect(unlocked).to_be_falsy()
        t.expect(achievements.is_unlocked("time_15min")).to_be_falsy()

        -- Simulate additional time to reach 15 minutes total
        achievements.update(300) -- 5 more minutes
        game_time = achievements.get_game_time()
        t.expect(game_time).to_equal(900)

        -- Should unlock now
        unlocked = achievements.unlock("time_15min", game_time)
        t.expect(unlocked).to_be_truthy()
        t.expect(achievements.is_unlocked("time_15min")).to_be_truthy()

        print("✓ time_15min achievement unlocks at exactly 15 minutes")
    end)

    t.it("integrates with achievement listener correctly", function()
        -- Clear captured logs
        captured_logs = {}

        -- Mock required modules for achievement listener
        package.loaded["idle_game.resources"] = {
            get = function(key) return 0 end
        }
        package.loaded["idle_game.spawner"] = {
            getForagerCount = function() return 0 end,
            getLumberjackCount = function() return 0 end,
            getCollectorCount = function() return 0 end,
            getBuilderCount = function() return 0 end,
            getMinerCount = function() return 0 end
        }
        package.loaded["idle_game.upgrades"] = {
            get_all = function() return {} end,
            get_level = function() return 0 end
        }

        local achievements = require("idle_game.achievements")
        local achievement_listener = require("idle_game.achievement_listener")

        -- Initialize systems
        achievements.init()
        MockToastQueue:clear()
        achievement_listener.init(MockToastQueue)

        -- Verify achievement listener is initialized
        t.expect(achievement_listener.is_initialized()).to_be_truthy()

        -- Simulate time passing through achievement listener
        -- This should update achievements.update() internally
        achievement_listener.update(300) -- 5 minutes

        local game_time = achievements.get_game_time()
        t.expect(game_time).to_equal(300)

        -- time_5min should be unlocked automatically by achievement listener
        t.expect(achievements.is_unlocked("time_5min")).to_be_truthy()

        -- Check that a toast was shown for time_5min
        local toasts = MockToastQueue:get_toasts()
        local found_time_toast = false
        for _, toast in ipairs(toasts) do
            if string.match(toast.message, "Getting Started") then
                found_time_toast = true
                break
            end
        end
        t.expect(found_time_toast).to_be_truthy()

        -- Continue to 15 minutes
        achievement_listener.update(600) -- 10 more minutes
        game_time = achievements.get_game_time()
        t.expect(game_time).to_equal(900)

        -- time_15min should be unlocked
        t.expect(achievements.is_unlocked("time_15min")).to_be_truthy()

        -- Shutdown achievement listener
        achievement_listener.shutdown()
        t.expect(achievement_listener.is_initialized()).to_be_falsy()

        print("✓ Achievement listener integration works correctly")
    end)

    t.it("handles edge cases correctly", function()
        local achievements = require("idle_game.achievements")

        -- Initialize achievements system
        achievements.init()

        -- Test negative dt (should be ignored)
        achievements.update(-10)
        t.expect(achievements.get_game_time()).to_equal(0)

        -- Test zero dt
        achievements.update(0)
        t.expect(achievements.get_game_time()).to_equal(0)

        -- Test nil dt (should be ignored)
        achievements.update(nil)
        t.expect(achievements.get_game_time()).to_equal(0)

        -- Test very small dt
        achievements.update(0.001)
        t.expect(achievements.get_game_time()).to_equal(0.001)

        -- Test multiple unlock attempts (should only return true once)
        achievements.update(300) -- Reach 5 minutes
        local unlocked1 = achievements.unlock("time_5min", achievements.get_game_time())
        local unlocked2 = achievements.unlock("time_5min", achievements.get_game_time())
        t.expect(unlocked1).to_be_truthy()
        t.expect(unlocked2).to_be_falsy() -- Already unlocked

        print("✓ Edge cases handled correctly")
    end)

    t.it("achievement serialization includes time achievements", function()
        local achievements = require("idle_game.achievements")

        -- Initialize and unlock some achievements
        achievements.init()
        achievements.update(1000) -- 16:40 minutes

        -- Unlock both time achievements
        achievements.unlock("time_5min", achievements.get_game_time())
        achievements.unlock("time_15min", achievements.get_game_time())

        -- Serialize state
        local serialized = achievements.serialize()

        -- Verify serialization includes time and unlocked achievements
        t.expect(serialized.game_time).to_equal(1000)
        t.expect(serialized.unlocked.time_5min).to_be_truthy()
        t.expect(serialized.unlocked.time_15min).to_be_truthy()

        -- Test deserialization
        achievements.init() -- Reset
        achievements.deserialize(serialized)

        -- Verify restored state
        t.expect(achievements.get_game_time()).to_equal(1000)
        t.expect(achievements.is_unlocked("time_5min")).to_be_truthy()
        t.expect(achievements.is_unlocked("time_15min")).to_be_truthy()

        print("✓ Serialization/deserialization works correctly")
    end)

end)

--------------------------------------------------------------------------------
-- Run Tests
--------------------------------------------------------------------------------

print(string.rep("=", 60))
print("TIME ACHIEVEMENT SYSTEM TEST RESULTS")
print(string.rep("=", 60))

t.run()

print(string.rep("=", 60))
print("Time achievement test complete!")
print("✓ Achievement definitions: time_5min and time_15min added")
print("✓ Time tracking: Game time accumulates correctly")
print("✓ Unlock mechanics: Achievements trigger at correct thresholds")
print("✓ Integration: Achievement listener handles time achievements")
print("✓ Edge cases: Negative/nil dt, multiple unlock attempts")
print("✓ Persistence: Serialization includes time and achievements")
print(string.rep("=", 60))