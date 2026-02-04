--[[
================================================================================
TEST: Idle Game ASCII Resource Panel Rendering
================================================================================
Verifies the ASCII resource panel renders expected text and updates rates.

Run with: lua assets/scripts/tests/test_idle_resource_panel_render.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function setup_panel()
    package.loaded["idle_game.ui.ascii_resource_panel"] = nil

    local resource_values = { food = 10, wood = 5, stone = 2, gold = 1 }
    local resources_stub = {
        FOOD = "food",
        WOOD = "wood",
        STONE = "stone",
        GOLD = "gold",
        get = function(resource_type)
            return resource_values[resource_type] or 0
        end
    }

    package.loaded["idle_game.resources"] = resources_stub
    package.loaded["idle_game.spawner"] = {
        getForagerCount = function()
            return 3
        end
    }
    package.loaded["idle_game.ui.ascii_sprites"] = {
        ICONS = { food = "F", wood = "W", stone = "S", gold = "G" }
    }

    local draw_calls = { rectangles = {}, texts = {} }
    package.loaded["core.draw"] = {
        rectangle = function(layer, params)
            table.insert(draw_calls.rectangles, { layer = layer, params = params })
        end,
        textPro = function(layer, params)
            table.insert(draw_calls.texts, { layer = layer, params = params })
        end
    }

    _G.layers = { ui = "ui_layer" }
    _G.WHITE = { r = 255, g = 255, b = 255, a = 255 }
    _G.GRAY = { r = 128, g = 128, b = 128, a = 255 }

    local panel = require("idle_game.ui.ascii_resource_panel")
    panel.init(10, 200, 100)

    return panel, resources_stub, resource_values, draw_calls
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("ASCII Resource Panel", function()

    t.it("updates rates after one second", function()
        local panel, resources_stub = setup_panel()

        panel.update(1.0, resources_stub)
        local rates = panel.get_rates()

        t.expect(rates.food).to_equal(10)
        t.expect(rates.wood).to_equal(5)
        t.expect(rates.stone).to_equal(2)
        t.expect(rates.gold).to_equal(1)
    end)

    t.it("renders header, resources, and foragers", function()
        local panel, resources_stub, _, draw_calls = setup_panel()

        panel.update(1.0, resources_stub)
        panel.draw()

        t.expect(#draw_calls.rectangles).to_equal(4)
        t.expect(#draw_calls.texts >= 6).to_be_truthy()

        local text_lines = {}
        for _, call in ipairs(draw_calls.texts) do
            table.insert(text_lines, call.params.text or "")
        end
        local joined = table.concat(text_lines, " | ")

        t.expect(joined:find("Resources")).to_be_truthy()
        t.expect(joined:find("Food: 10")).to_be_truthy()
        t.expect(joined:find("%(%+10%.0/s%)")).to_be_truthy()
        t.expect(joined:find("Foragers: 3")).to_be_truthy()
    end)
end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
