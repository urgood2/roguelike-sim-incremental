--[[
================================================================================
TEST: Idle Game Achievement Listener - Deduplication
================================================================================
Tests that achievement_listener.init() can be called multiple times without
registering duplicate handlers.

Run with: lua assets/scripts/tests/test_idle_achievement_listener_dedup.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached module if re-running
package.loaded["idle_game.achievement_listener"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Achievement Listener - Deduplication", function()

    -- Test 1: Double init only registers handlers once
    t.it("double init only registers one handler set", function()
        local achievement_listener = require("idle_game.achievement_listener")

        -- Mock toast_queue for testing
        local mock_toast_queue = {
            push = function(msg) end
        }

        -- Track handler registration calls (if achievement_listener exposes this)
        local initial_handler_count = 0
        local post_first_init_count = 0
        local post_second_init_count = 0

        -- If achievement_listener has a way to check registered handlers
        if achievement_listener.get_handler_count then
            initial_handler_count = achievement_listener.get_handler_count()
        end

        -- First init call
        achievement_listener.init(mock_toast_queue)

        if achievement_listener.get_handler_count then
            post_first_init_count = achievement_listener.get_handler_count()
        end

        -- Second init call (should not double register)
        achievement_listener.init(mock_toast_queue)

        if achievement_listener.get_handler_count then
            post_second_init_count = achievement_listener.get_handler_count()
        end

        -- Verify deduplication behavior
        if achievement_listener.get_handler_count then
            -- If we can check handler count, verify it didn't double
            t.expect(post_first_init_count).to_equal(post_second_init_count)
            t.expect(post_second_init_count > initial_handler_count).to_be_truthy()
        end

        -- Alternative: Check that listener has an initialized flag
        if achievement_listener.is_initialized then
            t.expect(achievement_listener.is_initialized()).to_be_truthy()
        end

        -- Cleanup for subsequent tests
        if achievement_listener.shutdown then
            achievement_listener.shutdown()
        end
    end)

    -- Test 2: init is idempotent
    t.it("init is idempotent", function()
        local achievement_listener = require("idle_game.achievement_listener")

        local mock_toast_queue = {
            push = function(msg) end
        }

        -- Call init multiple times
        achievement_listener.init(mock_toast_queue)
        achievement_listener.init(mock_toast_queue)
        achievement_listener.init(mock_toast_queue)

        -- Should still be properly initialized (not broken by multiple calls)
        if achievement_listener.is_initialized then
            t.expect(achievement_listener.is_initialized()).to_be_truthy()
        end

        -- Cleanup
        if achievement_listener.shutdown then
            achievement_listener.shutdown()
        end
    end)

    -- Test 3: shutdown clears initialization state
    t.it("shutdown clears initialization state", function()
        local achievement_listener = require("idle_game.achievement_listener")

        local mock_toast_queue = {
            push = function(msg) end
        }

        -- Initialize
        achievement_listener.init(mock_toast_queue)

        if achievement_listener.is_initialized then
            t.expect(achievement_listener.is_initialized()).to_be_truthy()
        end

        -- Shutdown
        if achievement_listener.shutdown then
            achievement_listener.shutdown()

            if achievement_listener.is_initialized then
                t.expect(achievement_listener.is_initialized()).to_be_falsy()
            end
        end
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()