--[[
================================================================================
TEST: Idle Game ASCII Upgrade Panel Model
================================================================================
Tests sorting, scroll clamping, and hit-test mapping for the ASCII upgrade panel.

Run with: lua assets/scripts/tests/test_idle_upgrade_panel_model.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"
package.loaded["idle_game.ui.ascii_upgrade_panel"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function make_upgrades_stub(defs, levels, affordables, purchase_hook)
    local levels_map = levels or {}
    local afford_map = affordables or {}

    return {
        get_all = function()
            return defs
        end,
        get_level = function(id)
            return levels_map[id] or 0
        end,
        get_cost = function(id)
            local def = defs[id]
            return def and def.base_cost or { wood = 1 }
        end,
        can_afford = function(id, resources)
            return afford_map[id] == true
        end,
        purchase = function(id, resources)
            if purchase_hook then
                purchase_hook(id)
            end
            return true
        end
    }
end

local function make_defs_from_names(names)
    local defs = {}
    for _, name in ipairs(names) do
        local id = "upg_" .. string.lower(name)
        defs[id] = {
            name = name,
            description = name .. " desc",
            base_cost = { wood = 1 },
            max_level = 3
        }
    end
    return defs
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("ASCII Upgrade Panel - Model Behavior", function()

    t.it("sorts upgrades by affordability then name", function()
        local panel = require("idle_game.ui.ascii_upgrade_panel")
        panel.init(10, 300, 300)

        local defs = {
            upg_alpha = { name = "Alpha", description = "A", base_cost = { wood = 1 }, max_level = 2 },
            upg_bravo = { name = "Bravo", description = "B", base_cost = { wood = 1 }, max_level = 2 },
            upg_charlie = { name = "Charlie", description = "C", base_cost = { wood = 1 }, max_level = 2 },
        }

        local affordables = {
            upg_alpha = true,
            upg_bravo = true,
            upg_charlie = false,
        }

        local upgrades = make_upgrades_stub(defs, {}, affordables)
        panel.update(0, upgrades, {})

        local visible = panel.get_visible_upgrades()
        t.expect(visible[1].id).to_equal("upg_alpha")
        t.expect(visible[2].id).to_equal("upg_bravo")
        t.expect(visible[3].id).to_equal("upg_charlie")
    end)

    t.it("clamps scroll offset to valid range", function()
        local panel = require("idle_game.ui.ascii_upgrade_panel")
        panel.init(10, 300, 300)

        local defs = make_defs_from_names({
            "Alpha", "Bravo", "Charlie", "Delta", "Echo",
            "Foxtrot", "Golf", "Hotel", "India", "Juliet"
        })

        local affordables = {}
        for id, _ in pairs(defs) do
            affordables[id] = true
        end

        local upgrades = make_upgrades_stub(defs, {}, affordables)
        panel.update(0, upgrades, {})

        panel.scroll_by_wheel(100)
        local info = panel.get_scroll_info()
        local max_offset = info.total_upgrades - info.visible_upgrades
        t.expect(info.offset).to_equal(max_offset)

        panel.scroll_by_wheel(-100)
        info = panel.get_scroll_info()
        t.expect(info.offset).to_equal(0)
    end)

    t.it("maps hit-test clicks to the correct upgrade with scroll offset", function()
        local panel = require("idle_game.ui.ascii_upgrade_panel")
        panel.init(10, 300, 300)

        local defs = make_defs_from_names({
            "Alpha", "Bravo", "Charlie", "Delta", "Echo",
            "Foxtrot", "Golf", "Hotel", "India", "Juliet"
        })

        local affordables = {}
        for id, _ in pairs(defs) do
            affordables[id] = true
        end

        local last_purchased = nil
        local upgrades = make_upgrades_stub(defs, {}, affordables, function(id)
            last_purchased = id
        end)

        panel.update(0, upgrades, {})

        -- Scroll down by one to offset the list
        panel.scroll_by_wheel(1)

        local rect = panel.get_rect()
        local click_x = rect.x + rect.w - 1
        local click_y = rect.y + 1

        local consumed = panel.handle_click(click_x, click_y, upgrades, {})
        t.expect(consumed).to_be_truthy()
        t.expect(last_purchased).to_equal("upg_bravo")
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
