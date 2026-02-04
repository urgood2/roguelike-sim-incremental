--[[
================================================================================
TEST: Idle Game ASCII Upgrade Panel Integration
================================================================================
Integration test: scroll works, buy triggers purchases.

Run with: lua assets/scripts/tests/test_idle_upgrade_panel_integration.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Stub signals to avoid external side effects
package.loaded["idle_game.signals"] = { emit = function() end }

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function make_resources_stub(initial)
    local store = {
        food = initial.food or 0,
        wood = initial.wood or 0,
        stone = initial.stone or 0,
        gold = initial.gold or 0
    }

    return {
        get = function(resource)
            return store[resource] or 0
        end,
        add = function(resource, amount)
            store[resource] = (store[resource] or 0) + amount
        end,
        snapshot = function()
            return {
                food = store.food,
                wood = store.wood,
                stone = store.stone,
                gold = store.gold
            }
        end
    }
end

local function get_visible_ids(panel)
    local ids = {}
    for _, upgrade in ipairs(panel.get_visible_upgrades()) do
        table.insert(ids, upgrade.id)
    end
    return ids
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("ASCII Upgrade Panel - Integration", function()

    t.it("scroll changes visible upgrades", function()
        package.loaded["idle_game.ui.ascii_upgrade_panel"] = nil
        package.loaded["idle_game.upgrades"] = nil

        local panel = require("idle_game.ui.ascii_upgrade_panel")
        local upgrades = require("idle_game.upgrades")
        local resources = make_resources_stub({ food = 1000, wood = 1000, stone = 1000, gold = 1000 })

        upgrades.reset()
        panel.init(10, 300, 300)
        panel.update(0, upgrades, resources)

        local before_ids = get_visible_ids(panel)
        panel.scroll_by_wheel(1)
        local after_ids = get_visible_ids(panel)
        local info = panel.get_scroll_info()

        t.expect(info.offset > 0).to_be_truthy()
        t.expect(#before_ids).to_equal(#after_ids)
        t.expect(before_ids[1] ~= after_ids[1]).to_be_truthy()
    end)

    t.it("buy triggers purchase and deducts resources", function()
        package.loaded["idle_game.ui.ascii_upgrade_panel"] = nil
        package.loaded["idle_game.upgrades"] = nil

        local panel = require("idle_game.ui.ascii_upgrade_panel")
        local upgrades = require("idle_game.upgrades")
        local resources = make_resources_stub({ food = 1000, wood = 1000, stone = 1000, gold = 1000 })

        upgrades.reset()
        panel.init(10, 300, 300)
        panel.update(0, upgrades, resources)

        local visible = panel.get_visible_upgrades()
        t.expect(#visible > 0).to_be_truthy()

        local target = visible[1]
        local before_level = upgrades.get_level(target.id)
        local cost = upgrades.get_cost(target.id)
        local before_resources = resources.snapshot()

        local rect = panel.get_rect()
        local buy_x = rect.x + rect.w - 1
        local consumed = panel.handle_click(buy_x, rect.y + 1, upgrades, resources)

        t.expect(consumed).to_be_truthy()
        t.expect(upgrades.get_level(target.id)).to_equal(before_level + 1)

        for resource, amount in pairs(cost) do
            local expected = (before_resources[resource] or 0) - amount
            t.expect(resources.get(resource)).to_equal(expected)
        end
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
