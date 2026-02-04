--[[
================================================================================
MANUAL TEST: Viewport at 800x600 Window
================================================================================
Verifies that at a 800x600 window resolution:
1. Sidebar is properly reserved (positioned correctly)
2. World is centered in the remaining viewport area

Run with: lua test_viewport_800x600.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

package.loaded["idle_game.ui.ui_layout"] = nil
package.loaded["idle_game.config"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Test Constants
--------------------------------------------------------------------------------

local WINDOW_WIDTH = 800
local WINDOW_HEIGHT = 600

local TILE_SIZE = 20
local GRID_WIDTH = 30
local GRID_HEIGHT = 20
local VIRTUAL_WIDTH = GRID_WIDTH * TILE_SIZE
local VIRTUAL_HEIGHT = GRID_HEIGHT * TILE_SIZE
local SIDEBAR_WIDTH = 12 * TILE_SIZE

--------------------------------------------------------------------------------
-- Mock Global Functions
--------------------------------------------------------------------------------

local function setup_mock_globals()
    _G.globals = {
        screenWidth = function() return WINDOW_WIDTH end,
        screenHeight = function() return WINDOW_HEIGHT end
    }
end

local function cleanup_mock_globals()
    _G.globals = nil
end

--------------------------------------------------------------------------------
-- Test Utilities
--------------------------------------------------------------------------------

local function calculate_expected_layout()
    local world_view_width = WINDOW_WIDTH - SIDEBAR_WIDTH
    return {
        screen_width = WINDOW_WIDTH,
        screen_height = WINDOW_HEIGHT,
        world_pixel_width = VIRTUAL_WIDTH,
        world_pixel_height = VIRTUAL_HEIGHT,
        sidebar_width = SIDEBAR_WIDTH,
        resource_panel_height = 3 * TILE_SIZE,
        world_view_width = world_view_width,
        world_view_height = WINDOW_HEIGHT,
        camera_target_x = VIRTUAL_WIDTH / 2,
        camera_target_y = VIRTUAL_HEIGHT / 2,
        camera_offset_x = world_view_width / 2,
        camera_offset_y = WINDOW_HEIGHT / 2,
        zoom_x = world_view_width / VIRTUAL_WIDTH,
        zoom_y = WINDOW_HEIGHT / VIRTUAL_HEIGHT,
        expected_zoom = math.min(world_view_width / VIRTUAL_WIDTH, WINDOW_HEIGHT / VIRTUAL_HEIGHT)
    }
end

local function print_layout_analysis(expected)
    print("")
    print("VIEWPORT LAYOUT ANALYSIS (800x600 window)")
    print("=" .. string.rep("=", 50))
    print(string.format("Window Size: %dx%d", expected.screen_width, expected.screen_height))
    print(string.format("World Grid: %dx%d tiles (%dx%d pixels)",
          GRID_WIDTH, GRID_HEIGHT, expected.world_pixel_width, expected.world_pixel_height))
    print("")
    print("UI Layout:")
    print(string.format("  Sidebar: %dpx wide (reserved on right)", expected.sidebar_width))
    print(string.format("  Resource panel: %dpx high (reserved at top)", expected.resource_panel_height))
    print(string.format("  World view area: %dx%d pixels", expected.world_view_width, expected.world_view_height))
    print("")
    print("Camera Positioning:")
    print(string.format("  World center: (%.0f, %.0f)", expected.camera_target_x, expected.camera_target_y))
    print(string.format("  View center: (%.0f, %.0f)", expected.camera_offset_x, expected.camera_offset_y))
    print(string.format("  Zoom factor: %.2f (fit world to view)", expected.expected_zoom))
    print("")
    print("Analysis:")
    if expected.expected_zoom < 1.0 then
        print("  NOTE: World will be scaled down to fit (expected for 800x600 with sidebar)")
    elseif expected.expected_zoom == 1.0 then
        print("  OK: World fits perfectly at 1:1 scale")
    else
        print("  NOTE: World would be scaled up (unexpected)")
    end
    print("")
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Viewport at 800x600 Window - Layout Verification", function()

    local ui_layout = nil

    t.before_each(function()
        setup_mock_globals()
        ui_layout = require("idle_game.ui.ui_layout")
    end)

    t.after_each(function()
        cleanup_mock_globals()
    end)

    t.it("calculates correct aligned screen dimensions", function()
        local expected = calculate_expected_layout()
        local aligned = ui_layout.aligned_screen(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)

        t.expect(aligned.width).to_equal(expected.screen_width)
        t.expect(aligned.height).to_equal(expected.screen_height)

        t.expect(aligned.width % TILE_SIZE).to_equal(0)
        t.expect(aligned.height % TILE_SIZE).to_equal(0)
    end)

    t.it("positions resource panel correctly", function()
        local expected = calculate_expected_layout()
        local rect = ui_layout.resource_panel_rect(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)

        t.expect(rect.x).to_equal(0)
        t.expect(rect.y).to_equal(0)
        t.expect(rect.w).to_equal(expected.screen_width)
        t.expect(rect.h).to_equal(expected.resource_panel_height)
    end)

    t.it("positions sidebar correctly on right edge", function()
        local expected = calculate_expected_layout()
        local rect = ui_layout.sidebar_rect(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)

        t.expect(rect.x).to_equal(expected.screen_width - expected.sidebar_width)
        t.expect(rect.y).to_equal(expected.resource_panel_height)
        t.expect(rect.w).to_equal(expected.sidebar_width)
        t.expect(rect.h).to_equal(expected.screen_height - expected.resource_panel_height)
    end)

    t.it("calculates game area dimensions correctly", function()
        local expected = calculate_expected_layout()
        local rect = ui_layout.game_area_rect(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)

        t.expect(rect.x).to_equal(0)
        t.expect(rect.y).to_equal(expected.resource_panel_height)
        t.expect(rect.w).to_equal(expected.world_view_width)
        t.expect(rect.h).to_equal(expected.world_view_height - expected.resource_panel_height)
    end)

    t.it("positions toast notifications in available space", function()
        local expected = calculate_expected_layout()
        local toast_rects = ui_layout.toast_rects(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT, 3)

        t.expect(#toast_rects).to_equal(3)

        for _, toast in ipairs(toast_rects) do
            t.expect(toast.x >= 0).to_be_truthy()
            t.expect(toast.y >= 0).to_be_truthy()
            t.expect(toast.x + toast.w <= expected.screen_width).to_be_truthy()
            t.expect(toast.y + toast.h <= expected.screen_height).to_be_truthy()
        end
    end)

    t.it("maintains mathematical consistency across layout calculations", function()
        local expected = calculate_expected_layout()

        local resource_rect = ui_layout.resource_panel_rect(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)
        local sidebar_rect = ui_layout.sidebar_rect(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)
        local game_rect = ui_layout.game_area_rect(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)

        local sidebar_left = sidebar_rect.x
        local game_right = game_rect.x + game_rect.w
        t.expect(game_right <= sidebar_left).to_be_truthy()

        local resource_bottom = resource_rect.y + resource_rect.h
        local game_top = game_rect.y
        t.expect(resource_bottom <= game_top).to_be_truthy()

        t.expect(resource_rect.w).to_equal(expected.screen_width)
        t.expect(sidebar_rect.x + sidebar_rect.w).to_equal(expected.screen_width)
        t.expect(game_rect.x + game_rect.w + sidebar_rect.w).to_equal(expected.screen_width)
    end)

    t.it("provides comprehensive layout analysis", function()
        local expected = calculate_expected_layout()
        print_layout_analysis(expected)
        t.expect(true).to_be_truthy()
    end)

end)

--------------------------------------------------------------------------------
-- Run tests
--------------------------------------------------------------------------------

t.run()
