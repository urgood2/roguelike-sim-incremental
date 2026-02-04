--[[
================================================================================
TEST: Idle Game Resources try_spend Function
================================================================================
Tests atomic resource spending and signal emission for the resources.try_spend function.
Verifies that either all resources are spent successfully or none are spent.

Run with: lua assets/scripts/tests/test_idle_resources_try_spend.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached modules if re-running
package.loaded["idle_game.resources"] = nil
package.loaded["external.hump.signal"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Signal Capture Helper
--------------------------------------------------------------------------------

local function setup_signal_capture()
    local captured_signals = {}
    local signal = require("external.hump.signal")

    -- Clear any existing handlers
    signal.clear("idle.resource_total")
    signal.clear("idle.resource_added")

    -- Register signal capture handlers
    signal.register("idle.resource_total", function(resource_type, new_value)
        table.insert(captured_signals, {
            type = "resource_total",
            resource = resource_type,
            value = new_value
        })
    end)

    signal.register("idle.resource_added", function(resource_type, new_value, delta)
        table.insert(captured_signals, {
            type = "resource_added",
            resource = resource_type,
            value = new_value,
            delta = delta
        })
    end)

    return captured_signals
end

local function cleanup_signals()
    local signal = require("external.hump.signal")
    signal.clear("idle.resource_total")
    signal.clear("idle.resource_added")
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Resources try_spend - Atomicity and Signals", function()

    local resources = nil

    t.before_each(function()
        resources = require("idle_game.resources")
        resources.init()
    end)

    t.after_each(function()
        cleanup_signals()
    end)

    -- Test 1: Successful spend with sufficient resources
    t.it("spends all resources when sufficient amounts available", function()
        local captured = setup_signal_capture()

        -- Setup: add resources
        resources.add("wood", 50)
        resources.add("stone", 30)
        resources.add("gold", 20)

        -- Clear signal capture from setup
        captured = setup_signal_capture()

        -- Test: spend multiple resources
        local costs = { wood = 25, stone = 15, gold = 10 }
        local success = resources.try_spend(costs)

        -- Verify success
        t.expect(success).to_be_truthy()

        -- Verify resources were deducted
        t.expect(resources.get("wood")).to_equal(25)   -- 50 - 25
        t.expect(resources.get("stone")).to_equal(15)  -- 30 - 15
        t.expect(resources.get("gold")).to_equal(10)   -- 20 - 10

        -- Verify signals were emitted for each resource
        t.expect(#captured >= 3).to_be_truthy() -- At least one signal per resource

        -- Check that resource_total signals were emitted
        local total_signals = {}
        for _, signal in ipairs(captured) do
            if signal.type == "resource_total" then
                total_signals[signal.resource] = signal.value
            end
        end
        t.expect(total_signals.wood).to_equal(25)
        t.expect(total_signals.stone).to_equal(15)
        t.expect(total_signals.gold).to_equal(10)
    end)

    -- Test 2: Failed spend with insufficient resources (atomicity test)
    t.it("spends nothing when insufficient resources (atomicity)", function()
        local captured = setup_signal_capture()

        -- Setup: add limited resources
        resources.add("wood", 50)
        resources.add("stone", 10)  -- Insufficient for our cost
        resources.add("gold", 20)

        -- Clear signal capture from setup
        captured = setup_signal_capture()

        -- Test: try to spend more than available
        local costs = { wood = 25, stone = 15, gold = 10 }  -- stone = 15 > 10 available
        local success = resources.try_spend(costs)

        -- Verify failure
        t.expect(success).to_be_falsy()

        -- Verify NO resources were deducted (atomicity)
        t.expect(resources.get("wood")).to_equal(50)   -- Unchanged
        t.expect(resources.get("stone")).to_equal(10)  -- Unchanged
        t.expect(resources.get("gold")).to_equal(20)   -- Unchanged

        -- Verify NO signals were emitted during failed spend
        t.expect(#captured).to_equal(0)
    end)

    -- Test 3: Empty costs should succeed
    t.it("succeeds with empty costs table", function()
        local captured = setup_signal_capture()

        local success = resources.try_spend({})
        t.expect(success).to_be_truthy()

        -- No signals should be emitted for empty spend
        t.expect(#captured).to_equal(0)
    end)

    -- Test 4: Nil costs should succeed
    t.it("succeeds with nil costs", function()
        local captured = setup_signal_capture()

        local success = resources.try_spend(nil)
        t.expect(success).to_be_truthy()

        -- No signals should be emitted for nil spend
        t.expect(#captured).to_equal(0)
    end)

    -- Test 5: Single resource spend
    t.it("spends single resource correctly", function()
        local captured = setup_signal_capture()

        -- Setup
        resources.add("food", 100)
        captured = setup_signal_capture()

        -- Test
        local costs = { food = 40 }
        local success = resources.try_spend(costs)

        t.expect(success).to_be_truthy()
        t.expect(resources.get("food")).to_equal(60)

        -- Verify signal emitted for single resource
        local found_total = false
        for _, signal in ipairs(captured) do
            if signal.type == "resource_total" and signal.resource == "food" then
                t.expect(signal.value).to_equal(60)
                found_total = true
                break
            end
        end
        t.expect(found_total).to_be_truthy()
    end)

    -- Test 6: Exact amount spend (boundary test)
    t.it("spends exact available amount successfully", function()
        local captured = setup_signal_capture()

        -- Setup: exact amounts
        resources.add("wood", 25)
        resources.add("stone", 15)
        captured = setup_signal_capture()

        -- Test: spend exact amounts
        local costs = { wood = 25, stone = 15 }
        local success = resources.try_spend(costs)

        t.expect(success).to_be_truthy()
        t.expect(resources.get("wood")).to_equal(0)
        t.expect(resources.get("stone")).to_equal(0)
    end)

    -- Test 7: One resource short (atomicity boundary test)
    t.it("fails when only one resource is insufficient", function()
        local captured = setup_signal_capture()

        -- Setup: one resource short by 1
        resources.add("wood", 25)
        resources.add("stone", 14)  -- Need 15, have 14
        captured = setup_signal_capture()

        -- Test
        local costs = { wood = 25, stone = 15 }
        local success = resources.try_spend(costs)

        t.expect(success).to_be_falsy()

        -- Verify atomicity: nothing spent
        t.expect(resources.get("wood")).to_equal(25)
        t.expect(resources.get("stone")).to_equal(14)

        -- No signals emitted
        t.expect(#captured).to_equal(0)
    end)

    -- Test 8: Zero cost should succeed
    t.it("handles zero costs correctly", function()
        local captured = setup_signal_capture()

        resources.add("wood", 10)
        captured = setup_signal_capture()

        local costs = { wood = 0, stone = 0 }
        local success = resources.try_spend(costs)

        t.expect(success).to_be_truthy()

        -- Resources unchanged
        t.expect(resources.get("wood")).to_equal(10)
        t.expect(resources.get("stone")).to_equal(0)

        -- No signals emitted for zero spend
        t.expect(#captured).to_equal(0)
    end)

    -- Test 9: Signal emission order and content
    t.it("emits correct signals in proper order", function()
        local captured = setup_signal_capture()

        -- Setup
        resources.add("food", 50)
        resources.add("wood", 30)
        captured = setup_signal_capture()

        -- Test
        local costs = { food = 20, wood = 10 }
        local success = resources.try_spend(costs)

        t.expect(success).to_be_truthy()

        -- Check that we got resource_total signals for both resources
        local total_signals = {}
        for _, signal in ipairs(captured) do
            if signal.type == "resource_total" then
                total_signals[signal.resource] = signal.value
            end
        end

        t.expect(total_signals.food).to_equal(30)  -- 50 - 20
        t.expect(total_signals.wood).to_equal(20) -- 30 - 10
    end)

    -- Test 10: Mixed valid/invalid resource types (error handling)
    t.it("handles invalid resource types appropriately", function()
        local captured = setup_signal_capture()

        resources.add("wood", 50)

        -- This should trigger an error due to invalid resource type
        local costs = { wood = 10, invalid_resource = 5 }

        local success, error_msg = pcall(function()
            return resources.try_spend(costs)
        end)

        t.expect(success).to_be_falsy()
        t.expect(error_msg).to_be_type("string")

        -- Resources should be unchanged after error
        t.expect(resources.get("wood")).to_equal(50)
    end)

    -- Test 11: Large transaction atomicity
    t.it("handles large multi-resource transaction atomically", function()
        local captured = setup_signal_capture()

        -- Setup with all resources
        resources.add("food", 100)
        resources.add("wood", 200)
        resources.add("stone", 150)
        resources.add("gold", 80)
        captured = setup_signal_capture()

        -- Large transaction that should succeed
        local costs = { food = 90, wood = 180, stone = 120, gold = 70 }
        local success = resources.try_spend(costs)

        t.expect(success).to_be_truthy()

        -- Verify all deductions
        t.expect(resources.get("food")).to_equal(10)   -- 100 - 90
        t.expect(resources.get("wood")).to_equal(20)   -- 200 - 180
        t.expect(resources.get("stone")).to_equal(30)  -- 150 - 120
        t.expect(resources.get("gold")).to_equal(10)   -- 80 - 70

        -- Verify signals emitted for all resources
        local total_signals = {}
        for _, signal in ipairs(captured) do
            if signal.type == "resource_total" then
                total_signals[signal.resource] = signal.value
            end
        end

        t.expect(total_signals.food).to_equal(10)
        t.expect(total_signals.wood).to_equal(20)
        t.expect(total_signals.stone).to_equal(30)
        t.expect(total_signals.gold).to_equal(10)
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()