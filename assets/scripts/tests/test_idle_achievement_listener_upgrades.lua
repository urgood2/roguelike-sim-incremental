--[[
================================================================================
TEST: Idle Game Achievement Listener - Upgrade Evaluation
================================================================================
Integration test: upg_first_purchase, upg_any_level_5, upg_any_maxed.

Run with: lua assets/scripts/tests/test_idle_achievement_listener_upgrades.lua
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

t.describe("Achievement Listener - Upgrade Evaluation", function()

    t.it("unlocks upgrade achievements when thresholds are met", function()
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
            get_all = function()
                return {
                    upg_alpha = { max_level = 3 },
                    upg_beta = { max_level = 5 }
                }
            end,
            get_level = function(id)
                if id == "upg_alpha" then
                    return 1
                end
                if id == "upg_beta" then
                    return 5
                end
                return 0
            end
        }

        local listener = require("idle_game.achievement_listener")
        listener.init({ push = function() end })

        -- Trigger update-driven evaluation
        listener.update(0.1)

        t.expect(achievements.is_unlocked("upg_first_purchase")).to_be_truthy()
        t.expect(achievements.is_unlocked("upg_any_level_5")).to_be_truthy()
        t.expect(achievements.is_unlocked("upg_any_maxed")).to_be_truthy()

        listener.shutdown()
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
