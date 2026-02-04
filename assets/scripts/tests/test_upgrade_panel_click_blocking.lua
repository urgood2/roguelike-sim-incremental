--[[
================================================================================
TEST: Upgrade Panel Click Blocking Integration Test
================================================================================
Verifies that clicks inside the upgrade panel sidebar don't affect the world.

Run with: lua assets/scripts/tests/test_upgrade_panel_click_blocking.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

package.loaded["idle_game.ui.ascii_upgrade_panel"] = nil

local t = require("tests.test_runner")

-- Mock upgrades module for panel update
local function make_upgrades_stub()
    return {
        get_all = function()
            return {
                upg_alpha = { name = "Alpha", description = "A", base_cost = { wood = 1 }, max_level = 2 }
            }
        end,
        get_level = function()
            return 0
        end,
        get_cost = function()
            return { wood = 1 }
        end,
        can_afford = function()
            return true
        end,
        purchase = function()
            return true
        end
    }
end

--------------------------------------------------------------------------------
-- Click Blocking Logic (Extracted from sim_scene.lua)
--------------------------------------------------------------------------------

local function simulate_click_processing(click_x, click_y, panel)
    local click_consumed = false

    if panel.hit_test(click_x, click_y) then
        click_consumed = true
        panel.handle_click(click_x, click_y, make_upgrades_stub(), {})
    end

    local world_interaction_allowed = not click_consumed

    return {
        click_consumed = click_consumed,
        world_interaction_allowed = world_interaction_allowed
    }
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Upgrade Panel Click Blocking Integration", function()

    t.it("consumes clicks inside the upgrade panel area", function()
        local panel = require("idle_game.ui.ascii_upgrade_panel")
        panel.init(20, 800, 600)
        panel.update(0, make_upgrades_stub(), {})

        local rect = panel.get_rect()
        local click_x = rect.x + rect.w / 2
        local click_y = rect.y + rect.h / 2

        local result = simulate_click_processing(click_x, click_y, panel)

        t.expect(result.click_consumed).to_equal(true)
        t.expect(result.world_interaction_allowed).to_equal(false)
    end)

    t.it("allows clicks outside the upgrade panel to pass through", function()
        local panel = require("idle_game.ui.ascii_upgrade_panel")
        panel.init(20, 800, 600)
        panel.update(0, make_upgrades_stub(), {})

        local rect = panel.get_rect()
        local click_x = rect.x - 50
        local click_y = rect.y + rect.h / 2

        local result = simulate_click_processing(click_x, click_y, panel)

        t.expect(result.click_consumed).to_equal(false)
        t.expect(result.world_interaction_allowed).to_equal(true)
    end)

    t.it("handles boundary conditions around panel edges", function()
        local panel = require("idle_game.ui.ascii_upgrade_panel")
        panel.init(20, 800, 600)
        panel.update(0, make_upgrades_stub(), {})

        local rect = panel.get_rect()

        local test_positions = {
            {x = rect.x + 10, y = rect.y + 10, should_consume = true},
            {x = rect.x + rect.w - 10, y = rect.y + rect.h - 10, should_consume = true},
            {x = rect.x - 1, y = rect.y + 10, should_consume = false},
            {x = rect.x + rect.w, y = rect.y + 10, should_consume = false},
            {x = rect.x + 10, y = rect.y - 1, should_consume = false},
            {x = rect.x + 10, y = rect.y + rect.h, should_consume = false}
        }

        for _, pos in ipairs(test_positions) do
            local result = simulate_click_processing(pos.x, pos.y, panel)
            t.expect(result.click_consumed).to_equal(pos.should_consume)
            t.expect(result.world_interaction_allowed).to_equal(not pos.should_consume)
        end
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
