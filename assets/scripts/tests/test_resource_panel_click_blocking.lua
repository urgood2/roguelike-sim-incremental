--[[
================================================================================
TEST: Resource Panel Click Blocking Integration Test
================================================================================
Verifies that clicks inside the resource panel don't affect the world.
Tests the UI click consumption mechanism to ensure proper separation between
UI interactions and world interactions.

Run with: lua assets/scripts/tests/test_resource_panel_click_blocking.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached modules if re-running
package.loaded["idle_game.ui.ascii_resource_panel"] = nil

local t = require("tests.test_runner")

-- Mock spawner for resource panel
package.loaded["idle_game.spawner"] = {
    getForagerCount = function() return 5 end
}

-- Mock draw module
package.loaded["core.draw"] = {
    rectangle = function() end,
    textPro = function() end
}

-- Mock resources module
package.loaded["idle_game.resources"] = {
    FOOD = "food",
    WOOD = "wood",
    STONE = "stone",
    GOLD = "gold",
    get = function(type) return 100 end
}

-- Mock globals for layer access
_G.layers = { ui = {} }

--------------------------------------------------------------------------------
-- Click Blocking Logic (Extracted from sim_scene.lua)
--------------------------------------------------------------------------------

-- This simulates the click blocking logic from sim_scene.lua
local function simulate_click_processing(click_x, click_y, resource_panel)
    -- Initialize click state
    local click_consumed = false

    -- Test resource panel hit (from sim_scene.lua lines 218-222)
    local resource_hit = resource_panel.hit_test(click_x, click_y)
    if resource_hit and resource_hit.consumed then
        click_consumed = true
        print(string.format("[sim_scene] Click consumed by resource panel at (%d, %d)", click_x, click_y))
    end

    -- Only process terrain clicks if UI didn't consume the click (from sim_scene.lua line 237)
    local world_interaction_allowed = not click_consumed

    return {
        click_consumed = click_consumed,
        world_interaction_allowed = world_interaction_allowed,
        resource_hit = resource_hit
    }
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Resource Panel Click Blocking Integration", function()

    -- Test 1: Clicks inside resource panel are consumed
    t.it("consumes clicks inside the resource panel area", function()
        local panel = require("idle_game.ui.ascii_resource_panel")

        -- Initialize panel
        local tile_size = 20
        local screen_w = 800
        local screen_h = 600
        panel.init(tile_size, screen_w, screen_h)

        -- Get panel rectangle
        local rect = panel.get_rect()

        -- Click inside the panel area
        local click_x = rect.x + rect.w / 2  -- Center X of panel
        local click_y = rect.y + rect.h / 2  -- Center Y of panel

        local result = simulate_click_processing(click_x, click_y, panel)

        -- Click should be consumed by resource panel
        t.expect(result.click_consumed).to_equal(true)
        t.expect(result.world_interaction_allowed).to_equal(false)
        t.expect(result.resource_hit.consumed).to_equal(true)
    end)

    -- Test 2: Clicks outside resource panel are not consumed
    t.it("allows clicks outside the resource panel to pass through", function()
        local panel = require("idle_game.ui.ascii_resource_panel")

        -- Initialize panel
        panel.init(20, 800, 600)

        -- Get panel rectangle
        local rect = panel.get_rect()

        -- Click outside the panel area (to the left)
        local click_x = rect.x - 50  -- Left of panel
        local click_y = rect.y + rect.h / 2  -- Same Y level

        local result = simulate_click_processing(click_x, click_y, panel)

        -- Click should NOT be consumed by resource panel
        t.expect(result.click_consumed).to_equal(false)
        t.expect(result.world_interaction_allowed).to_equal(true)
        t.expect(result.resource_hit.consumed).to_equal(false)
    end)

    -- Test 3: Test multiple positions around panel boundaries
    t.it("correctly handles boundary conditions around panel edges", function()
        local panel = require("idle_game.ui.ascii_resource_panel")
        panel.init(20, 800, 600)

        local rect = panel.get_rect()

        -- Test positions around the panel
        local test_positions = {
            -- Inside panel
            {x = rect.x + 10, y = rect.y + 10, should_consume = true, desc = "top-left inside"},
            {x = rect.x + rect.w - 10, y = rect.y + rect.h - 10, should_consume = true, desc = "bottom-right inside"},
            {x = rect.x + rect.w / 2, y = rect.y + rect.h / 2, should_consume = true, desc = "center"},

            -- Outside panel
            {x = rect.x - 1, y = rect.y + 10, should_consume = false, desc = "just left of panel"},
            {x = rect.x + rect.w, y = rect.y + 10, should_consume = false, desc = "just right of panel"},
            {x = rect.x + 10, y = rect.y - 1, should_consume = false, desc = "just above panel"},
            {x = rect.x + 10, y = rect.y + rect.h, should_consume = false, desc = "just below panel"},
        }

        for _, pos in ipairs(test_positions) do
            local result = simulate_click_processing(pos.x, pos.y, panel)

            t.expect(result.click_consumed).to_equal(pos.should_consume)
            t.expect(result.world_interaction_allowed).to_equal(not pos.should_consume)

            -- Additional verification of hit_test logic
            local hit_result = panel.hit_test(pos.x, pos.y)
            t.expect(hit_result.consumed).to_equal(pos.should_consume)
        end
    end)

    -- Test 4: Panel initialization state affects click blocking
    t.it("handles uninitialized panel state gracefully", function()
        -- Clear the cached module to ensure truly uninitialized state
        package.loaded["idle_game.ui.ascii_resource_panel"] = nil
        local panel = require("idle_game.ui.ascii_resource_panel")

        -- Don't initialize the panel
        -- Test click on arbitrary position
        local click_x, click_y = 100, 100

        local result = simulate_click_processing(click_x, click_y, panel)

        -- Uninitialized panel should not consume clicks
        t.expect(result.click_consumed).to_equal(false)
        t.expect(result.world_interaction_allowed).to_equal(true)
        t.expect(result.resource_hit.consumed).to_equal(false)
    end)

    -- Test 5: Invalid coordinates are handled properly
    t.it("handles invalid click coordinates gracefully", function()
        local panel = require("idle_game.ui.ascii_resource_panel")
        panel.init(20, 800, 600)

        -- Test with nil coordinates
        local result1 = simulate_click_processing(nil, 100, panel)
        t.expect(result1.click_consumed).to_equal(false)
        t.expect(result1.world_interaction_allowed).to_equal(true)

        local result2 = simulate_click_processing(100, nil, panel)
        t.expect(result2.click_consumed).to_equal(false)
        t.expect(result2.world_interaction_allowed).to_equal(true)

        local result3 = simulate_click_processing(nil, nil, panel)
        t.expect(result3.click_consumed).to_equal(false)
        t.expect(result3.world_interaction_allowed).to_equal(true)
    end)

    -- Test 6: Panel rectangle calculation is correct
    t.it("calculates panel rectangle correctly for different screen sizes", function()
        local panel = require("idle_game.ui.ascii_resource_panel")

        -- Test different screen configurations
        local configs = {
            {tile_size = 20, w = 800, h = 600},
            {tile_size = 16, w = 1024, h = 768},
            {tile_size = 24, w = 640, h = 480}
        }

        for _, config in ipairs(configs) do
            panel.init(config.tile_size, config.w, config.h)

            local rect = panel.get_rect()

            -- Verify rectangle has valid dimensions
            t.expect(rect.w).to_equal(10 * config.tile_size)  -- Fixed width: 10 tiles
            t.expect(rect.h).to_equal(6 * config.tile_size)   -- Fixed height: 6 tiles
            t.expect(rect.x).to_equal(0)  -- Fixed position: top-left
            t.expect(rect.y).to_equal(0)

            -- Verify click inside this rectangle is consumed
            local center_x = rect.x + rect.w / 2
            local center_y = rect.y + rect.h / 2

            local hit_result = panel.hit_test(center_x, center_y)
            t.expect(hit_result.consumed).to_equal(true)
        end
    end)

end)

--------------------------------------------------------------------------------
-- Auto-run if executed directly
--------------------------------------------------------------------------------
if arg and arg[0] and arg[0]:match("test_resource_panel_click_blocking%.lua$") then
    t.run()
end