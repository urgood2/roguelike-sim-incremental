--[[
================================================================================
TEST: Idle Game Upgrade System
================================================================================
Tests upgrade definitions, cost calculations, affordability, and purchases.

Run with: lua assets/scripts/tests/test_idle_upgrades.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached modules if re-running
package.loaded["idle_game.upgrades"] = nil
package.loaded["idle_game.resources"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Upgrade System - Core Functionality", function()
    
    -- Test 1: All upgrades have required properties
    t.it("defines 10+ upgrades with name, description, and base_cost", function()
        local upgrades = require("idle_game.upgrades")
        upgrades.reset()
        
        local all_upgrades = upgrades.get_all()
        
        -- Check we have at least 10 upgrades
        local count = 0
        for _ in pairs(all_upgrades) do
            count = count + 1
        end
        t.expect(count >= 10).to_be_truthy()
        
        -- Check each upgrade has required properties
        for id, upgrade in pairs(all_upgrades) do
            t.expect(upgrade.name).to_be_type("string")
            t.expect(upgrade.description).to_be_type("string")
            t.expect(upgrade.base_cost).to_be_type("table")
            t.expect(upgrade.max_level).to_be_type("number")
            t.expect(upgrade.max_level).to_equal(10)
        end
    end)
    
    -- Test 2: get_level() returns 0 initially
    t.it("get_level() returns 0 for unpurchased upgrade", function()
        local upgrades = require("idle_game.upgrades")
        upgrades.reset()
        
        local level = upgrades.get_level("click_wood")
        t.expect(level).to_equal(0)
    end)
    
    -- Test 3: get_cost() uses formula base_cost * (1.5 ^ level)
    t.it("get_cost() applies exponential formula correctly", function()
        local upgrades = require("idle_game.upgrades")
        upgrades.reset()
        
        local resources = require("idle_game.resources")
        resources.init()
        resources.add("wood", 1000)
        
        -- Level 0: base_cost * 1.5^0 = base_cost
        local cost_0 = upgrades.get_cost("click_wood")
        t.expect(cost_0.wood).to_equal(10)  -- base_cost = 10
        
        -- Level 1: base_cost * 1.5^1 = 15
        upgrades.purchase("click_wood", resources)
        local cost_1 = upgrades.get_cost("click_wood")
        t.expect(cost_1.wood).to_equal(15)  -- 10 * 1.5
        
        -- Level 2: base_cost * 1.5^2 = 22.5 → floor = 22
        upgrades.purchase("click_wood", resources)
        local cost_2 = upgrades.get_cost("click_wood")
        t.expect(cost_2.wood).to_equal(22)  -- 10 * 2.25 = 22.5 → 22
    end)
    
    -- Test 4: can_afford() checks if player has enough resources
    t.it("can_afford() returns true when resources sufficient", function()
        local upgrades = require("idle_game.upgrades")
        upgrades.reset()
        
        local resources = require("idle_game.resources")
        resources.init()
        resources.add("wood", 100)
        
        local can_afford = upgrades.can_afford("click_wood", resources)
        t.expect(can_afford).to_be_truthy()
    end)
    
    -- Test 5: can_afford() returns false when resources insufficient
    t.it("can_afford() returns false when resources insufficient", function()
        local upgrades = require("idle_game.upgrades")
        upgrades.reset()
        
        local resources = require("idle_game.resources")
        resources.init()
        resources.add("wood", 5)  -- Less than base_cost (10)
        
        local can_afford = upgrades.can_afford("click_wood", resources)
        t.expect(can_afford).to_be_falsy()
    end)
    
    -- Test 6: purchase() increments level and deducts cost
    t.it("purchase() deducts cost and increments level", function()
        local upgrades = require("idle_game.upgrades")
        upgrades.reset()
        
        local resources = require("idle_game.resources")
        resources.init()
        resources.add("wood", 100)
        
        local success = upgrades.purchase("click_wood", resources)
        t.expect(success).to_be_truthy()
        t.expect(upgrades.get_level("click_wood")).to_equal(1)
        t.expect(resources.get("wood")).to_equal(90)  -- 100 - 10
    end)
    
    -- Test 7: purchase() returns false when can't afford
    t.it("purchase() returns false when insufficient resources", function()
        local upgrades = require("idle_game.upgrades")
        upgrades.reset()
        
        local resources = require("idle_game.resources")
        resources.init()
        resources.add("wood", 5)
        
        local success = upgrades.purchase("click_wood", resources)
        t.expect(success).to_be_falsy()
        t.expect(upgrades.get_level("click_wood")).to_equal(0)
        t.expect(resources.get("wood")).to_equal(5)  -- Unchanged
    end)
    
    -- Test 8: max level 10 enforced (purchase returns false at max)
    t.it("purchase() returns false when upgrade at max level", function()
        local upgrades = require("idle_game.upgrades")
        upgrades.reset()
        
        local resources = require("idle_game.resources")
        resources.init()
        resources.add("wood", 10000)
        
        -- Purchase 10 times to reach max level
        for i = 1, 10 do
            local success = upgrades.purchase("click_wood", resources)
            t.expect(success).to_be_truthy()
        end
        
        -- Try to purchase at level 10 (should fail)
        local success = upgrades.purchase("click_wood", resources)
        t.expect(success).to_be_falsy()
        t.expect(upgrades.get_level("click_wood")).to_equal(10)
    end)
    
    -- Test 9: Multiple upgrades work independently
    t.it("multiple upgrades track levels independently", function()
        local upgrades = require("idle_game.upgrades")
        upgrades.reset()
        
        local resources = require("idle_game.resources")
        resources.init()
        resources.add("wood", 100)
        resources.add("stone", 100)
        
        upgrades.purchase("click_wood", resources)
        upgrades.purchase("click_stone", resources)
        upgrades.purchase("click_stone", resources)
        
        t.expect(upgrades.get_level("click_wood")).to_equal(1)
        t.expect(upgrades.get_level("click_stone")).to_equal(2)
    end)
    
    -- Test 10: Cost increases exponentially with level
    t.it("cost increases exponentially across multiple levels", function()
        local upgrades = require("idle_game.upgrades")
        upgrades.reset()
        
        local costs = {}
        local level = 0
        
        for i = 0, 5 do
            costs[i] = upgrades.get_cost("click_wood").wood
            level = upgrades.get_level("click_wood")
            if level < 10 then
                -- Artificial level increment for testing (using resources with huge amount)
                local resources = require("idle_game.resources")
                if i == 0 then resources.init() end
                resources.add("wood", 10000)
                upgrades.purchase("click_wood", resources)
            end
        end
        
        -- Verify each level is 1.5x higher than previous
        -- Level 0: 10
        -- Level 1: 15 (10 * 1.5)
        -- Level 2: 22 (10 * 2.25)
        -- Level 3: 33 (10 * 3.375)
        -- Level 4: 50 (10 * 5.0625)
        -- Level 5: 75 (10 * 7.59375)
        
        t.expect(costs[0]).to_equal(10)
        t.expect(costs[1]).to_equal(15)
        t.expect(costs[2]).to_equal(22)
        t.expect(costs[3] >= 30 and costs[3] <= 35).to_be_truthy()  -- ~33
    end)
    
    -- Test 11: Level persists between function calls
    t.it("upgrade level persists across multiple calls", function()
        local upgrades = require("idle_game.upgrades")
        upgrades.reset()
        
        local resources = require("idle_game.resources")
        resources.init()
        resources.add("wood", 1000)
        
        upgrades.purchase("click_wood", resources)
        upgrades.purchase("click_wood", resources)
        
        -- Simulate time passing, then check level still 2
        local level = upgrades.get_level("click_wood")
        t.expect(level).to_equal(2)
        
        -- Purchase once more
        upgrades.purchase("click_wood", resources)
        level = upgrades.get_level("click_wood")
        t.expect(level).to_equal(3)
    end)
    
end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
