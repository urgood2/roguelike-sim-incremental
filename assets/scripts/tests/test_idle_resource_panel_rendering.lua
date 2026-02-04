-- assets/scripts/tests/test_idle_resource_panel_rendering.lua
-- Integration coverage for ascii_resource_panel rendering and rate updates.

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/tests/?.lua"

require("tests.mocks.engine_mock")

local draw_calls = { rectangles = {}, texts = {} }

package.preload["core.draw"] = function()
    return {
        rectangle = function(layer, props)
            table.insert(draw_calls.rectangles, { layer = layer, props = props })
        end,
        textPro = function(layer, props)
            table.insert(draw_calls.texts, { layer = layer, props = props })
        end,
    }
end

local resource_values = { food = 5, wood = 10, stone = 0, gold = 1 }

local resources_stub = {
    FOOD = "food",
    WOOD = "wood",
    STONE = "stone",
    GOLD = "gold",
    get = function(resource_type)
        return resource_values[resource_type] or 0
    end,
}

package.preload["idle_game.resources"] = function()
    return resources_stub
end

package.preload["idle_game.spawner"] = function()
    return {
        getForagerCount = function()
            return 3
        end,
    }
end

package.loaded["idle_game.ui.ascii_resource_panel"] = nil
package.loaded["core.draw"] = nil
package.loaded["idle_game.resources"] = nil
package.loaded["idle_game.spawner"] = nil

local t = require("tests.test_runner")
local ascii_resource_panel = require("idle_game.ui.ascii_resource_panel")

local function reset_draw_calls()
    draw_calls.rectangles = {}
    draw_calls.texts = {}
end

t.describe("ASCII resource panel rendering", function()
    t.before_each(function()
        reset_draw_calls()
        ascii_resource_panel.init(10, 800, 600)
    end)

    t.it("updates rates after 1 second", function()
        ascii_resource_panel.update(1.0, resources_stub)
        local rates = ascii_resource_panel.get_rates()
        t.expect(rates.food).to_be(5)
        t.expect(rates.wood).to_be(10)
        t.expect(rates.stone).to_be(0)
        t.expect(rates.gold).to_be(1)
    end)

    t.it("draws header, resource rows, and forager count", function()
        ascii_resource_panel.update(1.0, resources_stub)
        ascii_resource_panel.draw()

        t.expect(#draw_calls.rectangles).to_be(4)
        t.expect(#draw_calls.texts).to_be(6)

        local combined = {}
        for _, call in ipairs(draw_calls.texts) do
            table.insert(combined, call.props.text)
        end
        local text_blob = table.concat(combined, "\n")

        t.expect(text_blob).to_contain("Resources")
        t.expect(text_blob).to_contain("Food: 5 (+5.0/s)")
        t.expect(text_blob).to_contain("Wood: 10 (+10.0/s)")
        t.expect(text_blob).to_contain("Stone: 0")
        t.expect(text_blob).to_contain("Gold: 1 (+1.0/s)")
        t.expect(text_blob).to_contain("Foragers: 3")
    end)
end)

t.run()
