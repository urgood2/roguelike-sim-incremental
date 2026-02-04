--[[
================================================================================
TEST: Save Manager Late Registration Distribution
================================================================================
Tests that late-registered collectors receive cached data automatically.

This verifies the SaveManager's ability to distribute previously loaded data
to collectors that register after the data has been loaded into cache.

Run with: lua assets/scripts/tests/test_save_manager_register_distributes.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached modules if re-running
package.loaded["core.save_manager"] = nil

local t = require("tests.test_runner")

-- Mock save_io module since we're testing in isolation
package.loaded["core.save_io"] = {
    init_filesystem = function() end,
    save_file_async = function(path, content, callback) callback(true) end,
    load_file = function() return nil end,
    file_exists = function() return false end,
    delete_file = function() end
}

-- Mock save_migrations module
package.loaded["core.save_migrations"] = {}

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("SaveManager Late Registration Distribution", function()

    -- Test 1: Late registration distributes cached data
    t.it("distributes cached data to late-registered collectors", function()
        local SaveManager = require("core.save_manager")

        -- Reset SaveManager state for clean test
        SaveManager.collectors = {}
        SaveManager.cache = {}
        SaveManager.save_in_progress = false
        SaveManager.pending_save = nil

        -- Set up cache with test data (simulating loaded save file)
        local test_data = {
            version = 2,
            saved_at = "2026-02-01T00:00:00Z",
            player_stats = { level = 5, xp = 1500 },
            inventory = { wood = 100, stone = 50 }
        }
        SaveManager.cache = test_data

        -- Track what data was distributed
        local distributed_data = {}

        -- Create mock collectors
        local player_collector = {
            collect = function() return { level = 5, xp = 1500 } end,
            distribute = function(data)
                distributed_data.player_stats = data
            end
        }

        local inventory_collector = {
            collect = function() return { wood = 100, stone = 50 } end,
            distribute = function(data)
                distributed_data.inventory = data
            end
        }

        -- Register collectors AFTER cache has been populated (late registration)
        SaveManager.register("player_stats", player_collector)
        SaveManager.register("inventory", inventory_collector)

        -- Verify that cached data was distributed to late-registered collectors
        t.expect(distributed_data.player_stats).to_equal({ level = 5, xp = 1500 })
        t.expect(distributed_data.inventory).to_equal({ wood = 100, stone = 50 })
    end)

    -- Test 2: Late registration handles missing cache data gracefully
    t.it("handles missing cache data for late-registered collectors", function()
        local SaveManager = require("core.save_manager")

        -- Reset SaveManager state
        SaveManager.collectors = {}
        SaveManager.cache = { version = 2, saved_at = "2026-02-01T00:00:00Z" }

        local distribute_called = false
        local collector = {
            collect = function() return { test = true } end,
            distribute = function(data)
                distribute_called = true
            end
        }

        -- Register collector for key not in cache
        SaveManager.register("missing_key", collector)

        -- distribute should not be called if no cache data for this key
        t.expect(distribute_called).to_equal(false)
    end)

    -- Test 3: Early registration doesn't get duplicate distribution
    t.it("doesn't duplicate distribute to early-registered collectors", function()
        local SaveManager = require("core.save_manager")

        -- Reset SaveManager state
        SaveManager.collectors = {}
        SaveManager.cache = {}

        local distribute_count = 0
        local collector = {
            collect = function() return { early = true } end,
            distribute = function(data)
                distribute_count = distribute_count + 1
            end
        }

        -- Register BEFORE cache is populated (early registration)
        SaveManager.register("early_test", collector)

        -- Now populate cache and distribute all
        local test_data = { version = 2, early_test = { early = true } }
        SaveManager.distribute_all(test_data)

        -- Should only be called once (from distribute_all, not from register)
        t.expect(distribute_count).to_equal(1)
    end)

    -- Test 4: Late registration handles distributor errors gracefully
    t.it("handles distributor errors during late registration", function()
        local SaveManager = require("core.save_manager")

        -- Reset SaveManager state
        SaveManager.collectors = {}
        SaveManager.cache = { version = 2, error_test = { data = "test" } }

        local error_collector = {
            collect = function() return { data = "test" } end,
            distribute = function(data)
                error("Distribution failed!")
            end
        }

        -- This should not crash even though distribute() throws an error
        local success = pcall(function()
            SaveManager.register("error_test", error_collector)
        end)

        -- Registration should succeed despite distributor error
        t.expect(success).to_equal(true)

        -- Collector should still be registered
        t.expect(SaveManager.collectors.error_test).to_equal(error_collector)
    end)

    -- Test 5: Multiple late registrations work correctly
    t.it("handles multiple late registrations correctly", function()
        local SaveManager = require("core.save_manager")

        -- Reset SaveManager state
        SaveManager.collectors = {}
        SaveManager.cache = {
            version = 2,
            stats = { strength = 10 },
            items = { sword = 1, shield = 1 },
            settings = { sound = true, music = false }
        }

        local distributed = {}

        local collectors = {
            stats = {
                collect = function() return { strength = 10 } end,
                distribute = function(data) distributed.stats = data end
            },
            items = {
                collect = function() return { sword = 1, shield = 1 } end,
                distribute = function(data) distributed.items = data end
            },
            settings = {
                collect = function() return { sound = true, music = false } end,
                distribute = function(data) distributed.settings = data end
            }
        }

        -- Register all collectors late
        for key, collector in pairs(collectors) do
            SaveManager.register(key, collector)
        end

        -- All should receive their cached data
        t.expect(distributed.stats).to_equal({ strength = 10 })
        t.expect(distributed.items).to_equal({ sword = 1, shield = 1 })
        t.expect(distributed.settings).to_equal({ sound = true, music = false })
    end)

end)

--------------------------------------------------------------------------------
-- Auto-run if executed directly
--------------------------------------------------------------------------------
if arg and arg[0] and arg[0]:match("test_save_manager_register_distributes%.lua$") then
    t.run()
end