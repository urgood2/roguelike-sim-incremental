-- assets/scripts/tests/test_idle_upgrade_panel_interaction.lua
-- Integration test for upgrade panel scroll and buy behavior.

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/tests/?.lua"

local t = require("tests.test_runner")
local ascii_upgrade_panel = require("idle_game.ui.ascii_upgrade_panel")

local function make_upgrades(count)
    local defs = {}
    local levels = {}
    local purchase_calls = {}

    for i = 1, count do
        local id = string.format("upgrade_%02d", i)
        defs[id] = {
            name = string.format("Upgrade %02d", i),
            description = string.format("Desc %02d", i),
            max_level = 5,
        }
        levels[id] = 0
    end

    local upgrades = {}
    upgrades.get_all = function()
        return defs
    end
    upgrades.get_level = function(id)
        return levels[id] or 0
    end
    upgrades.get_cost = function(id)
        return { wood = 1 }
    end
    upgrades.can_afford = function(id, resources)
        return true
    end
    upgrades.purchase = function(id, resources)
        table.insert(purchase_calls, id)
        levels[id] = (levels[id] or 0) + 1
        return true
    end
    upgrades._purchase_calls = purchase_calls

    return upgrades
end

local resources_stub = {
    get = function(resource_type)
        return 999
    end,
}

t.describe("ASCII upgrade panel interactions", function()
    t.it("scroll_by_wheel updates scroll offset", function()
        local upgrades = make_upgrades(10)
        ascii_upgrade_panel.init(10, 800, 600)
        ascii_upgrade_panel.update(0, upgrades, resources_stub)

        local info = ascii_upgrade_panel.get_scroll_info()
        t.expect(info.total_upgrades).to_be(10)
        t.expect(info.offset).to_be(0)

        ascii_upgrade_panel.scroll_by_wheel(2)
        info = ascii_upgrade_panel.get_scroll_info()
        t.expect(info.offset).to_be(2)

        ascii_upgrade_panel.scroll_by_wheel(-1)
        info = ascii_upgrade_panel.get_scroll_info()
        t.expect(info.offset).to_be(1)
    end)

    t.it("handle_click triggers purchase for visible upgrade", function()
        local upgrades = make_upgrades(8)
        ascii_upgrade_panel.init(10, 800, 600)
        ascii_upgrade_panel.update(0, upgrades, resources_stub)

        local rect = ascii_upgrade_panel.get_rect()
        local buy_x = rect.x + rect.w - 1
        local clicked = ascii_upgrade_panel.handle_click(buy_x, rect.y + 1, upgrades, resources_stub)

        t.expect(clicked).to_be_truthy()
        t.expect(upgrades._purchase_calls[1]).to_be("upgrade_01")
    end)
end)

t.run()
