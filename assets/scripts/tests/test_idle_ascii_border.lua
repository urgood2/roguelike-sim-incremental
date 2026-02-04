--[[
================================================================================
TEST: Idle Game ASCII Border
================================================================================
Tests border layout, alignment checks, minimum size validation, and tile counts.

Run with: lua assets/scripts/tests/test_idle_ascii_border.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached module if re-running
package.loaded["idle_game.ui.ascii_border"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("ASCII Border - Layout and Validation", function()

    t.it("layout computes tile and interior sizes", function()
        local border = require("idle_game.ui.ascii_border")
        local rect = { x = 10, y = 20, w = 80, h = 60 }
        local layout = border.layout(rect, 20)

        t.expect(layout.tiles.total_w).to_equal(4)
        t.expect(layout.tiles.total_h).to_equal(3)
        t.expect(layout.pixels.total_w).to_equal(80)
        t.expect(layout.pixels.total_h).to_equal(60)

        t.expect(layout.interior.x).to_equal(30)
        t.expect(layout.interior.y).to_equal(40)
        t.expect(layout.interior.w).to_equal(40)
        t.expect(layout.interior.h).to_equal(20)
        t.expect(layout.interior.tiles_w).to_equal(2)
        t.expect(layout.interior.tiles_h).to_equal(1)
    end)

    t.it("layout uses ceil for total tile counts", function()
        local border = require("idle_game.ui.ascii_border")
        local rect = { x = 0, y = 0, w = 41, h = 39 }
        local layout = border.layout(rect, 20)

        t.expect(layout.tiles.total_w).to_equal(3)
        t.expect(layout.tiles.total_h).to_equal(2)
    end)

    t.it("validate_alignment enforces minimum border size", function()
        local border = require("idle_game.ui.ascii_border")
        local rect_small = { x = 0, y = 0, w = 30, h = 50 }
        local rect_ok = { x = 0, y = 0, w = 40, h = 40 }

        t.expect(border.validate_alignment(rect_small, 20)).to_be_falsy()
        t.expect(border.validate_alignment(rect_ok, 20)).to_be_truthy()
    end)

    t.it("validate_alignment requires tile-aligned rects", function()
        local border = require("idle_game.ui.ascii_border")
        local rect_ok = { x = 0, y = 20, w = 40, h = 60 }
        local rect_bad_x = { x = 5, y = 20, w = 40, h = 60 }
        local rect_bad_w = { x = 0, y = 20, w = 45, h = 60 }

        t.expect(border.validate_alignment(rect_ok, 10)).to_be_truthy()
        t.expect(border.validate_alignment(rect_bad_x, 10)).to_be_falsy()
        t.expect(border.validate_alignment(rect_bad_w, 10)).to_be_falsy()
    end)

    t.it("validate_minimum_size requires at least 1x1 interior tile", function()
        local border = require("idle_game.ui.ascii_border")
        local rect_ok = { x = 0, y = 0, w = 60, h = 60 }
        local rect_bad = { x = 0, y = 0, w = 50, h = 60 }

        t.expect(border.validate_minimum_size(rect_ok, 20)).to_be_truthy()
        t.expect(border.validate_minimum_size(rect_bad, 20)).to_be_falsy()
    end)

    t.it("validate_alignment honors border thickness", function()
        local border = require("idle_game.ui.ascii_border")
        local rect = { x = 0, y = 0, w = 40, h = 40 }
        local cfg = { thickness = 2 }

        t.expect(border.validate_alignment(rect, 10, cfg)).to_be_truthy()
        t.expect(border.validate_alignment(rect, 20, cfg)).to_be_falsy()
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
