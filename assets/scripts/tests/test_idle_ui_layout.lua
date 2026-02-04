--[[
================================================================================
TEST: Idle Game UI Layout
================================================================================
Tests that layout functions return grid-aligned rectangles.

Run with: lua assets/scripts/tests/test_idle_ui_layout.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached module if re-running
package.loaded["idle_game.ui.ui_layout"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function is_aligned(value, tile_size)
    return (value % tile_size) == 0
end

local function assert_rect_aligned(rect, tile_size)
    t.expect(is_aligned(rect.x, tile_size)).to_be_truthy()
    t.expect(is_aligned(rect.y, tile_size)).to_be_truthy()
    t.expect(is_aligned(rect.w, tile_size)).to_be_truthy()
    t.expect(is_aligned(rect.h, tile_size)).to_be_truthy()
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("UI Layout - Grid Alignment", function()

    t.it("aligned_screen snaps to tile grid", function()
        local ui_layout = require("idle_game.ui.ui_layout")
        local aligned = ui_layout.aligned_screen(20, 1287, 805)

        t.expect(aligned.width).to_equal(1280)
        t.expect(aligned.height).to_equal(800)
        t.expect(is_aligned(aligned.width, 20)).to_be_truthy()
        t.expect(is_aligned(aligned.height, 20)).to_be_truthy()
    end)

    t.it("resource_panel_rect returns grid-aligned rectangle", function()
        local ui_layout = require("idle_game.ui.ui_layout")
        local rect = ui_layout.resource_panel_rect(20, 1280, 800)
        assert_rect_aligned(rect, 20)
    end)

    t.it("sidebar_rect returns grid-aligned rectangle", function()
        local ui_layout = require("idle_game.ui.ui_layout")
        local rect = ui_layout.sidebar_rect(20, 1280, 800)
        assert_rect_aligned(rect, 20)
    end)

    t.it("toast_rects returns grid-aligned rectangles", function()
        local ui_layout = require("idle_game.ui.ui_layout")
        local rects = ui_layout.toast_rects(20, 1280, 800, 3)

        t.expect(#rects).to_equal(3)
        for _, rect in ipairs(rects) do
            assert_rect_aligned(rect, 20)
        end
    end)

    t.it("game_area_rect returns grid-aligned rectangle", function()
        local ui_layout = require("idle_game.ui.ui_layout")
        local rect = ui_layout.game_area_rect(20, 1280, 800)
        assert_rect_aligned(rect, 20)
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
