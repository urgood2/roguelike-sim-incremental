--[[
================================================================================
TEST: Idle Game Achievement Listener - Resource Evaluation
================================================================================
Integration test: res_wood_100, res_stone_100, res_gold_25, res_total_500.

Run with: lua assets/scripts/tests/test_idle_achievement_listener_resources.lua
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

t.describe("Achievement Listener - Resource Evaluation", function()

    t.it("unlocks all resource achievements", function()
        local achievements_stub = {
            _unlocked = {}
        }

        function achievements_stub.unlock(id, current_value)
            if achievements_stub._unlocked[id] then
                return false
            end
            local thresholds = {
                res_wood_100 = 100,
                res_stone_100 = 100,
                res_gold_25 = 25,
                res_total_500 = 500
            }
            if current_value >= thresholds[id] then
                achievements_stub._unlocked[id] = true
                return true
            end
            return false
        end

        function achievements_stub.get_title(id)
            return id
        end

        package.loaded["idle_game.achievements"] = achievements_stub
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

        local resource_values = { wood = 0, stone = 0, gold = 0, food = 0 }
        package.loaded["idle_game.resources"] = {
            get = function(resource)
                return resource_values[resource] or 0
            end
        }

        local listener = require("idle_game.achievement_listener")
        listener.init({ push = function() end })

        resource_values.wood = 100
        listener._evaluate_resource_achievements("wood", 100)
        t.expect(achievements_stub._unlocked.res_wood_100).to_be_truthy()

        resource_values.stone = 100
        listener._evaluate_resource_achievements("stone", 100)
        t.expect(achievements_stub._unlocked.res_stone_100).to_be_truthy()

        resource_values.gold = 25
        listener._evaluate_resource_achievements("gold", 25)
        t.expect(achievements_stub._unlocked.res_gold_25).to_be_truthy()

        resource_values.food = 200
        resource_values.wood = 150
        resource_values.stone = 100
        resource_values.gold = 50
        listener._evaluate_resource_achievements("food", 200)
        t.expect(achievements_stub._unlocked.res_total_500).to_be_truthy()

        listener.shutdown()
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
