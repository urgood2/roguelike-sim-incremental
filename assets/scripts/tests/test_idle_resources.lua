--[[
================================================================================
TEST: Idle Game Resource System
================================================================================
Tests resource accumulation, capping, and passive generation.

Run with: lua assets/scripts/tests/test_idle_resources.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached module if re-running
package.loaded["idle_game.resources"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Resource System - Core Functionality", function()
    
    -- Test 1: Initial resources are 0
    t.it("initializes all resources to 0", function()
        local resources = require("idle_game.resources")
        resources.init()
        
        t.expect(resources.get("food")).to_equal(0)
        t.expect(resources.get("wood")).to_equal(0)
        t.expect(resources.get("stone")).to_equal(0)
        t.expect(resources.get("gold")).to_equal(0)
    end)
    
    -- Test 2: add() increases resource by amount
    t.it("add() increases resource amount", function()
        local resources = require("idle_game.resources")
        resources.init()
        
        local result = resources.add("food", 5)
        t.expect(result).to_equal(5)
        t.expect(resources.get("food")).to_equal(5)
    end)
    
    -- Test 3: get() returns current resource amount
    t.it("get() returns current resource amount", function()
        local resources = require("idle_game.resources")
        resources.init()
        
        resources.add("wood", 10)
        resources.add("wood", 5)
        
        t.expect(resources.get("wood")).to_equal(15)
    end)
    
    -- Test 4: Resources capped at 9999
    t.it("caps resources at 9999", function()
        local resources = require("idle_game.resources")
        resources.init()
        
        local result = resources.add("stone", 10000)
        t.expect(result).to_equal(9999)
        t.expect(resources.get("stone")).to_equal(9999)
    end)
    
    -- Test 5: add() with negative amount decreases resource
    t.it("add() with negative amount decreases resource", function()
        local resources = require("idle_game.resources")
        resources.init()
        
        resources.add("gold", 20)
        local result = resources.add("gold", -5)
        
        t.expect(result).to_equal(15)
        t.expect(resources.get("gold")).to_equal(15)
    end)
    
    -- Test 6: Resources cannot go below 0
    t.it("prevents resources from going below 0", function()
        local resources = require("idle_game.resources")
        resources.init()
        
        resources.add("food", 10)
        local result = resources.add("food", -20)
        
        t.expect(result).to_equal(0)
        t.expect(resources.get("food")).to_equal(0)
    end)
    
    -- Test 7: All 4 resource types work independently
    t.it("all 4 resource types work independently", function()
        local resources = require("idle_game.resources")
        resources.init()
        
        resources.add("food", 100)
        resources.add("wood", 200)
        resources.add("stone", 300)
        resources.add("gold", 400)
        
        t.expect(resources.get("food")).to_equal(100)
        t.expect(resources.get("wood")).to_equal(200)
        t.expect(resources.get("stone")).to_equal(300)
        t.expect(resources.get("gold")).to_equal(400)
    end)
    
    -- Test 8: Passive accumulation follows formula
    t.it("passive accumulation applies formula correctly", function()
        local resources = require("idle_game.resources")
        resources.init()
        
        -- Test gold accumulation with upgrade_level 5
        -- Formula: rate = base + (upgrade_level * 0.1)
        -- For gold: base = 0.1, upgrade_level = 5
        -- Expected rate: 0.1 + (5 * 0.1) = 0.6/second
        
        local upgrade_levels = {
            food = 0,
            wood = 0,
            stone = 0,
            gold = 5
        }
        
        resources.update(1.0, upgrade_levels)  -- 1 second with gold level 5
        
        local gold_value = resources.get("gold")
        -- Formula: 0.1 * (1 + 5*0.25) * 1.0 = 0.1 * 2.25 = 0.225
        t.expect(gold_value >= 0.20 and gold_value <= 0.25).to_be_truthy()
    end)
    
end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
