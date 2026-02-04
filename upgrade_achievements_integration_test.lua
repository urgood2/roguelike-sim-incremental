--[[
================================================================================
INTEGRATION TEST: Upgrade Achievement Verification
================================================================================
Comprehensive integration test to verify all 3 upgrade achievements unlock correctly:
1. upg_first_purchase: "Stepping Up" - Purchase your first upgrade
2. upg_any_level_5: "Dedicated Upgrader" - Get any upgrade to level 5
3. upg_any_maxed: "Perfectionist" - Max out any upgrade

Run with: lua upgrade_achievements_integration_test.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua;./assets/scripts/external/?.lua;./assets/scripts/external/?/init.lua"

-- Clear cached modules for clean testing
package.loaded["idle_game.achievements"] = nil
package.loaded["idle_game.achievement_listener"] = nil
package.loaded["idle_game.upgrades"] = nil
package.loaded["idle_game.resources"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Mock Setup for Testing
--------------------------------------------------------------------------------

-- Create simple mock toast queue
local mock_toast_queue = {
    toasts = {}
}

local function normalize_toast_args(first, second, third)
    if type(first) == "table" then
        return second, third
    end
    return first, second
end

function mock_toast_queue.add(first, second, third)
    local text, duration = normalize_toast_args(first, second, third)
    table.insert(mock_toast_queue.toasts, {text = text, duration = duration or 3.0})
    print(string.format("[MOCK_TOAST] Added: '%s'", text))
end

function mock_toast_queue.push(first, second, third)
    local text, opts = normalize_toast_args(first, second, third)
    local duration = 3.0
    if type(opts) == "table" and type(opts.duration) == "number" then
        duration = opts.duration
    end
    table.insert(mock_toast_queue.toasts, {text = text, duration = duration})
    print(string.format("[MOCK_TOAST] Added: '%s'", text))
end

function mock_toast_queue.get_toasts(self)
    return self.toasts
end

function mock_toast_queue.clear(self)
    self.toasts = {}
end

-- Mock signal system (achievements use signals)
local mock_signals = {}
_G.signal = {
    register = function(event_name, handler) end,
    remove = function(event_name, handler) end
}

--------------------------------------------------------------------------------
-- Integration Tests
--------------------------------------------------------------------------------

t.describe("Upgrade Achievement Integration Tests", function()

    t.it("verifies upg_first_purchase achievement", function()
        -- Initialize systems
        local achievements = require("idle_game.achievements")
        local achievement_listener = require("idle_game.achievement_listener")
        local upgrades = require("idle_game.upgrades")
        local resources = require("idle_game.resources")
        local upgrade_id = "click_wood"

        -- Reset state
        achievements.init()
        upgrades.reset()
        resources.init()
        mock_toast_queue:clear()

        achievement_listener.init(mock_toast_queue)

        -- Verify achievement starts locked
        t.expect(achievements.is_unlocked("upg_first_purchase")).to_be_falsy()

        -- Give player resources to buy an upgrade
        resources.add("wood", 100)
        resources.add("gold", 50)

        -- Purchase first upgrade (should trigger achievement)
        local upgrade_success = upgrades.purchase(upgrade_id, resources)
        t.expect(upgrade_success).to_be_truthy()

        -- Manually trigger achievement evaluation (since we're not running full game loop)
        local achievement_listener_module = require("idle_game.achievement_listener")
        if achievement_listener_module.refresh_and_evaluate then
            achievement_listener_module.refresh_and_evaluate()
        end

        -- Verify achievement was unlocked
        t.expect(achievements.is_unlocked("upg_first_purchase")).to_be_truthy()

        -- Verify toast notification was shown
        local toasts = mock_toast_queue:get_toasts()
        local found_achievement_toast = false
        for _, toast in ipairs(toasts) do
            if string.match(toast.text, "Stepping Up") then
                found_achievement_toast = true
                break
            end
        end
        t.expect(found_achievement_toast).to_be_truthy()

        print("✓ upg_first_purchase achievement verified")
    end)

    t.it("verifies upg_any_level_5 achievement", function()
        -- Initialize systems
        local achievements = require("idle_game.achievements")
        local achievement_listener = require("idle_game.achievement_listener")
        local upgrades = require("idle_game.upgrades")
        local resources = require("idle_game.resources")
        local upgrade_id = "click_wood"

        -- Reset state
        achievements.init()
        upgrades.reset()
        resources.init()
        mock_toast_queue:clear()

        achievement_listener.init(mock_toast_queue)

        -- Verify achievement starts locked
        t.expect(achievements.is_unlocked("upg_any_level_5")).to_be_falsy()

        -- Give player plenty of resources
        resources.add("wood", 10000)
        resources.add("gold", 10000)

        -- Purchase same upgrade multiple times to reach level 5
        for i = 1, 5 do
            local success = upgrades.purchase(upgrade_id, resources)
            t.expect(success).to_be_truthy()
        end

        -- Verify upgrade reached level 5
        t.expect(upgrades.get_level(upgrade_id)).to_equal(5)

        -- Trigger achievement evaluation
        local achievement_listener_module = require("idle_game.achievement_listener")
        if achievement_listener_module.refresh_and_evaluate then
            achievement_listener_module.refresh_and_evaluate()
        end

        -- Verify achievement was unlocked
        t.expect(achievements.is_unlocked("upg_any_level_5")).to_be_truthy()

        -- Verify toast notification
        local toasts = mock_toast_queue:get_toasts()
        local found_achievement_toast = false
        for _, toast in ipairs(toasts) do
            if string.match(toast.text, "Dedicated Upgrader") then
                found_achievement_toast = true
                break
            end
        end
        t.expect(found_achievement_toast).to_be_truthy()

        print("✓ upg_any_level_5 achievement verified")
    end)

    t.it("verifies upg_any_maxed achievement", function()
        -- Initialize systems
        local achievements = require("idle_game.achievements")
        local achievement_listener = require("idle_game.achievement_listener")
        local upgrades = require("idle_game.upgrades")
        local resources = require("idle_game.resources")

        -- Reset state
        achievements.init()
        upgrades.reset()
        resources.init()
        mock_toast_queue:clear()

        achievement_listener.init(mock_toast_queue)

        -- Verify achievement starts locked
        t.expect(achievements.is_unlocked("upg_any_maxed")).to_be_falsy()

        -- Give player massive resources
        resources.add("wood", 100000)
        resources.add("stone", 100000)
        resources.add("gold", 100000)
        resources.add("food", 100000)

        -- Use a known upgrade with affordable maxing costs within resource cap
        local all_upgrades = upgrades.get_all()
        local target_upgrade = "click_wood"
        local target_def = all_upgrades[target_upgrade]

        t.expect(target_def).to_be_truthy()
        local max_level = target_def.max_level or 0
        t.expect(max_level > 0).to_be_truthy()

        -- Purchase upgrade to max level
        for i = 1, max_level do
            local success = upgrades.purchase(target_upgrade, resources)
            if not success then
                print(string.format("Failed to purchase %s level %d", target_upgrade, i))
                break
            end
        end

        -- Verify upgrade reached max level
        t.expect(upgrades.get_level(target_upgrade)).to_equal(max_level)

        -- Trigger achievement evaluation
        local achievement_listener_module = require("idle_game.achievement_listener")
        if achievement_listener_module.refresh_and_evaluate then
            achievement_listener_module.refresh_and_evaluate()
        end

        -- Verify achievement was unlocked
        t.expect(achievements.is_unlocked("upg_any_maxed")).to_be_truthy()

        -- Verify toast notification
        local toasts = mock_toast_queue:get_toasts()
        local found_achievement_toast = false
        for _, toast in ipairs(toasts) do
            if string.match(toast.text, "Perfectionist") then
                found_achievement_toast = true
                break
            end
        end
        t.expect(found_achievement_toast).to_be_truthy()

        print("✓ upg_any_maxed achievement verified")
    end)

    t.it("verifies achievements don't unlock prematurely", function()
        -- Initialize systems with fresh state
        local achievements = require("idle_game.achievements")
        local achievement_listener = require("idle_game.achievement_listener")
        local upgrades = require("idle_game.upgrades")
        local resources = require("idle_game.resources")

        achievements.init()
        upgrades.reset()
        resources.init()
        mock_toast_queue:clear()

        achievement_listener.init(mock_toast_queue)

        -- All achievements should start locked
        t.expect(achievements.is_unlocked("upg_first_purchase")).to_be_falsy()
        t.expect(achievements.is_unlocked("upg_any_level_5")).to_be_falsy()
        t.expect(achievements.is_unlocked("upg_any_maxed")).to_be_falsy()

        -- Trigger evaluation without meeting conditions
        local achievement_listener_module = require("idle_game.achievement_listener")
        if achievement_listener_module.refresh_and_evaluate then
            achievement_listener_module.refresh_and_evaluate()
        end

        -- Achievements should still be locked
        t.expect(achievements.is_unlocked("upg_first_purchase")).to_be_falsy()
        t.expect(achievements.is_unlocked("upg_any_level_5")).to_be_falsy()
        t.expect(achievements.is_unlocked("upg_any_maxed")).to_be_falsy()

        -- No toast notifications should have been shown
        local toasts = mock_toast_queue:get_toasts()
        t.expect(#toasts).to_equal(0)

        print("✓ Achievements don't unlock prematurely")
    end)

end)

--------------------------------------------------------------------------------
-- Stress Test
--------------------------------------------------------------------------------

t.describe("Upgrade Achievement Stress Tests", function()

    t.it("handles multiple rapid upgrade purchases correctly", function()
        local achievements = require("idle_game.achievements")
        local achievement_listener = require("idle_game.achievement_listener")
        local upgrades = require("idle_game.upgrades")
        local resources = require("idle_game.resources")

        -- Reset state
        achievements.init()
        upgrades.reset()
        resources.init()
        mock_toast_queue:clear()

        achievement_listener.init(mock_toast_queue)

        -- Give massive resources
        resources.add("wood", 1000000)
        resources.add("stone", 1000000)
        resources.add("gold", 1000000)
        resources.add("food", 1000000)

        -- Rapidly purchase multiple different upgrades
        local all_upgrades = upgrades.get_all()
        local purchase_count = 0

        for upgrade_id, _ in pairs(all_upgrades) do
            for level = 1, 3 do  -- Buy first 3 levels of each upgrade
                if upgrades.purchase(upgrade_id, resources) then
                    purchase_count = purchase_count + 1
                end
            end
        end

        t.expect(purchase_count > 3).to_be_truthy()

        -- Trigger achievement evaluation
        local achievement_listener_module = require("idle_game.achievement_listener")
        if achievement_listener_module.refresh_and_evaluate then
            achievement_listener_module.refresh_and_evaluate()
        end

        -- First purchase achievement should be unlocked
        t.expect(achievements.is_unlocked("upg_first_purchase")).to_be_truthy()

        print("✓ Handles multiple rapid purchases correctly")
    end)

end)

--------------------------------------------------------------------------------
-- Run All Tests
--------------------------------------------------------------------------------

print("\n" .. string.rep("=", 60))
print("UPGRADE ACHIEVEMENT INTEGRATION TEST RESULTS")
print(string.rep("=", 60))

t.run()

print("\n" .. string.rep("=", 60))
print("Upgrade achievement integration test complete!")
print("✓ upg_first_purchase: Verified first purchase unlocks achievement")
print("✓ upg_any_level_5: Verified level 5 upgrade unlocks achievement")
print("✓ upg_any_maxed: Verified maxed upgrade unlocks achievement")
print("✓ Premature unlock prevention: Verified achievements don't unlock early")
print("✓ Stress testing: Verified system handles rapid purchases")
print(string.rep("=", 60))
