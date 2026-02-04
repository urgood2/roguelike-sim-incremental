--[[
================================================================================
TEST: Idle Game Achievement Listener - Time Evaluation
================================================================================
Ensures listener.update evaluates time-based achievements.

Run with: lua assets/scripts/tests/test_idle_achievement_listener_time.lua
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

t.describe("Achievement Listener - Time Evaluation", function()

    t.it("unlocks time achievements when thresholds are met", function()
        local achievements_stub = {
            _time = 0,
            _unlocked = {}
        }

        function achievements_stub.update(dt)
            achievements_stub._time = achievements_stub._time + dt
        end

        function achievements_stub.get_game_time()
            return achievements_stub._time
        end

        function achievements_stub.get_all()
            return {
                time_5min = { id = "time_5min" },
                time_15min = { id = "time_15min" }
            }
        end

        function achievements_stub.unlock(id, current_value)
            if achievements_stub._unlocked[id] then
                return false
            end
            local thresholds = { time_5min = 300, time_15min = 900 }
            if current_value >= thresholds[id] then
                achievements_stub._unlocked[id] = true
                return true
            end
            return false
        end

        package.loaded["idle_game.achievements"] = achievements_stub
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

        local listener = require("idle_game.achievement_listener")
        listener.init({})

        listener.update(299)
        t.expect(achievements_stub._unlocked.time_5min).to_be_falsy()
        t.expect(achievements_stub._unlocked.time_15min).to_be_falsy()

        listener.update(1)
        t.expect(achievements_stub._unlocked.time_5min).to_be_truthy()
        t.expect(achievements_stub._unlocked.time_15min).to_be_falsy()

        listener.update(600)
        t.expect(achievements_stub._unlocked.time_15min).to_be_truthy()

        listener.shutdown()
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
