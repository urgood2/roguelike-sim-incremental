--[[
================================================================================
TEST: Idle Game Achievement Listener - Creature Evaluation
================================================================================
Integration test: crt_total_25, crt_specialists_10, crt_builder_exists.

Run with: lua assets/scripts/tests/test_idle_achievement_listener_creatures.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached modules if re-running
package.loaded["idle_game.achievement_listener"] = nil
package.loaded["idle_game.achievements"] = nil
package.loaded["idle_game.resources"] = nil
package.loaded["idle_game.spawner"] = nil
package.loaded["idle_game.upgrades"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Achievement Listener - Creature Evaluation", function()

    t.it("unlocks creature achievements on creature_counts signal", function()
        local achievements = require("idle_game.achievements")
        achievements.init()

        -- Stub modules used during listener init
        package.loaded["idle_game.resources"] = {
            get = function() return 0 end
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

        local signal = require("external.hump.signal")
        signal.clear("idle.creature_counts")

        local listener = require("idle_game.achievement_listener")
        listener.init({ push = function() end })

        local counts = {
            foragers = 10,
            lumberjacks = 5,
            collectors = 3,
            builders = 1,
            miners = 6
        }

        signal.emit("idle.creature_counts", counts)

        t.expect(achievements.is_unlocked("crt_total_25")).to_be_truthy()
        t.expect(achievements.is_unlocked("crt_specialists_10")).to_be_truthy()
        t.expect(achievements.is_unlocked("crt_builder_exists")).to_be_truthy()

        listener.shutdown()
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
