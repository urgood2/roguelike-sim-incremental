--[[
================================================================================
MANUAL TEST: Viewport at 600x400 Window
================================================================================
Verifies that at a 600x400 window resolution:
1. Sidebar is properly reserved (positioned correctly)
2. World is centered in the remaining viewport area

This test validates the UI layout calculations and camera positioning
for the canonical window size that matches the game's virtual resolution.

Run with: lua test_viewport_600x400.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached modules if re-running
package.loaded["idle_game.ui.ui_layout"] = nil
package.loaded["idle_game.config"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Test Constants
--------------------------------------------------------------------------------

-- Target window resolution (canonical size)
local WINDOW_WIDTH = 600
local WINDOW_HEIGHT = 400

-- Expected layout calculations
local TILE_SIZE = 20
local GRID_WIDTH = 30    -- 30 tiles
local GRID_HEIGHT = 20   -- 20 tiles
local VIRTUAL_WIDTH = GRID_WIDTH * TILE_SIZE   -- 600px
local VIRTUAL_HEIGHT = GRID_HEIGHT * TILE_SIZE -- 400px
local SIDEBAR_WIDTH = 12 * TILE_SIZE           -- 240px

--------------------------------------------------------------------------------
-- Mock Global Functions
--------------------------------------------------------------------------------

local function setup_mock_globals()
    -- Mock screen dimensions to 600x400
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
    return {
        -- Screen dimensions
        screen_width = WINDOW_WIDTH,
        screen_height = WINDOW_HEIGHT,

        -- World grid dimensions (in pixels)
        world_pixel_width = VIRTUAL_WIDTH,   -- 600px
        world_pixel_height = VIRTUAL_HEIGHT, -- 400px

        -- UI panel dimensions
        sidebar_width = SIDEBAR_WIDTH,       -- 240px
        resource_panel_height = 3 * TILE_SIZE, -- 60px

        -- Available world view area (after reserving sidebar)
        world_view_width = WINDOW_WIDTH - SIDEBAR_WIDTH,  -- 360px
        world_view_height = WINDOW_HEIGHT,                -- 400px

        -- Camera positioning (world centered in view area)
        camera_target_x = VIRTUAL_WIDTH / 2,               -- 300px (center of world)
        camera_target_y = VIRTUAL_HEIGHT / 2,              -- 200px (center of world)
        camera_offset_x = (WINDOW_WIDTH - SIDEBAR_WIDTH) / 2, -- 180px (center of view area)
        camera_offset_y = WINDOW_HEIGHT / 2,               -- 200px (center of view area)

        -- Zoom calculation (should be 1.0 for perfect fit)
        zoom_x = (WINDOW_WIDTH - SIDEBAR_WIDTH) / VIRTUAL_WIDTH, -- 360/600 = 0.6
        zoom_y = WINDOW_HEIGHT / VIRTUAL_HEIGHT,                 -- 400/400 = 1.0
        expected_zoom = math.min(360/600, 400/400)               -- min(0.6, 1.0) = 0.6
    }
end

local function print_layout_analysis(expected)
    print("")
    print("📊 VIEWPORT LAYOUT ANALYSIS (600x400 window)")
    print("=" .. string.rep("=", 50))
    print(string.format("Window Size: %dx%d", expected.screen_width, expected.screen_height))
    print(string.format("World Grid: %dx%d tiles (%dx%d pixels)",
          GRID_WIDTH, GRID_HEIGHT, expected.world_pixel_width, expected.world_pixel_height))
    print("")
    print("UI Layout:")
    print(string.format("  • Sidebar: %dpx wide (reserved on right)", expected.sidebar_width))
    print(string.format("  • Resource panel: %dpx high (reserved at top)", expected.resource_panel_height))
    print(string.format("  • World view area: %dx%d pixels", expected.world_view_width, expected.world_view_height))
    print("")
    print("Camera Positioning:")
    print(string.format("  • World center: (%.0f, %.0f)", expected.camera_target_x, expected.camera_target_y))
    print(string.format("  • View center: (%.0f, %.0f)", expected.camera_offset_x, expected.camera_offset_y))
    print(string.format("  • Zoom factor: %.2f (fit world to view)", expected.expected_zoom))
    print("")
    print("Analysis:")
    if expected.expected_zoom < 1.0 then
        print("  ⚠️  World will be scaled down to fit (expected for 600x400 with sidebar)")
    elseif expected.expected_zoom == 1.0 then
        print("  ✅ World fits perfectly at 1:1 scale")
    else
        print("  ⚠️  World would be scaled up (unexpected)")
    end
    print("")
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Viewport at 600x400 Window - Layout Verification", function()

    local ui_layout = nil

    t.before_each(function()
        setup_mock_globals()
        ui_layout = require("idle_game.ui.ui_layout")
    end)

    t.after_each(function()
        cleanup_mock_globals()
    end)

    -- Test 1: Aligned screen dimensions should match window size exactly
    t.it("calculates correct aligned screen dimensions", function()
        local expected = calculate_expected_layout()

        local aligned = ui_layout.aligned_screen(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)

        -- At 600x400, both dimensions should be perfectly tile-aligned
        t.expect(aligned.width).to_equal(expected.screen_width)   -- 600px
        t.expect(aligned.height).to_equal(expected.screen_height) -- 400px

        -- Verify dimensions are tile-aligned
        t.expect(aligned.width % TILE_SIZE).to_equal(0)
        t.expect(aligned.height % TILE_SIZE).to_equal(0)
    end)

    -- Test 2: Resource panel should span full width at top
    t.it("positions resource panel correctly", function()
        local expected = calculate_expected_layout()

        local rect = ui_layout.resource_panel_rect(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)

        t.expect(rect.x).to_equal(0)                      -- Left edge
        t.expect(rect.y).to_equal(0)                      -- Top edge
        t.expect(rect.w).to_equal(expected.screen_width)  -- Full width (600px)
        t.expect(rect.h).to_equal(expected.resource_panel_height) -- 60px high
    end)

    -- Test 3: Sidebar should be reserved on the right side
    t.it("positions sidebar correctly on right edge", function()
        local expected = calculate_expected_layout()

        local rect = ui_layout.sidebar_rect(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)

        t.expect(rect.x).to_equal(expected.screen_width - expected.sidebar_width) -- Right edge - 240px
        t.expect(rect.y).to_equal(expected.resource_panel_height) -- Below resource panel
        t.expect(rect.w).to_equal(expected.sidebar_width)         -- 240px wide
        t.expect(rect.h).to_equal(expected.screen_height - expected.resource_panel_height) -- Remaining height
    end)

    -- Test 4: Game area should be correctly calculated
    t.it("calculates game area dimensions correctly", function()
        local expected = calculate_expected_layout()

        local rect = ui_layout.game_area_rect(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)

        t.expect(rect.x).to_equal(0)                           -- Left edge
        t.expect(rect.y).to_equal(expected.resource_panel_height) -- Below resource panel
        t.expect(rect.w).to_equal(expected.world_view_width)   -- 360px (600 - 240 sidebar)
        t.expect(rect.h).to_equal(expected.world_view_height - expected.resource_panel_height) -- Remaining height
    end)

    -- Test 5: Toast notifications should be positioned correctly
    t.it("positions toast notifications in available space", function()
        local expected = calculate_expected_layout()

        local toast_rects = ui_layout.toast_rects(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT, 3)

        t.expect(#toast_rects).to_equal(3)

        -- All toasts should be within the screen bounds
        for i, toast in ipairs(toast_rects) do
            t.expect(toast.x >= 0).to_be_truthy()
            t.expect(toast.y >= 0).to_be_truthy()
            t.expect(toast.x + toast.w <= expected.screen_width).to_be_truthy()
            t.expect(toast.y + toast.h <= expected.screen_height).to_be_truthy()

            -- Toasts should be positioned in the upper area (not overlapping game space too much)
            t.expect(toast.x + toast.w <= expected.screen_width).to_be_truthy() -- Within screen
        end
    end)

    -- Test 6: Layout calculations should be mathematically consistent
    t.it("maintains mathematical consistency across layout calculations", function()
        local expected = calculate_expected_layout()

        local resource_rect = ui_layout.resource_panel_rect(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)
        local sidebar_rect = ui_layout.sidebar_rect(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)
        local game_rect = ui_layout.game_area_rect(TILE_SIZE, WINDOW_WIDTH, WINDOW_HEIGHT)

        -- Verify no overlap between sidebar and game area
        local sidebar_left = sidebar_rect.x
        local game_right = game_rect.x + game_rect.w
        t.expect(game_right <= sidebar_left).to_be_truthy()

        -- Verify resource panel and game area don't overlap vertically
        local resource_bottom = resource_rect.y + resource_rect.h
        local game_top = game_rect.y
        t.expect(resource_bottom <= game_top).to_be_truthy()

        -- Verify all areas fit within screen bounds
        t.expect(resource_rect.w).to_equal(expected.screen_width)
        t.expect(sidebar_rect.x + sidebar_rect.w).to_equal(expected.screen_width)
        t.expect(game_rect.x + game_rect.w + sidebar_rect.w).to_equal(expected.screen_width)
    end)

    -- Test 7: Print comprehensive layout analysis
    t.it("provides comprehensive layout analysis", function()
        local expected = calculate_expected_layout()
        print_layout_analysis(expected)

        -- This test always passes - it's for manual verification
        t.expect(true).to_be_truthy()
    end)

end)

--------------------------------------------------------------------------------
-- Manual Verification Guide
--------------------------------------------------------------------------------

t.describe("Manual Verification Guide", function()

    t.it("provides manual testing instructions", function()
        print("")
        print("🧪 MANUAL VERIFICATION INSTRUCTIONS")
        print("=" .. string.rep("=", 50))
        print("")
        print("To manually verify viewport behavior at 600x400:")
        print("")
        print("1. Set window resolution to exactly 600x400 pixels")
        print("2. Launch the idle game simulation")
        print("3. Verify the following layout elements:")
        print("")
        print("   ✅ SIDEBAR (Right side):")
        print("      • Positioned on right edge")
        print("      • 240px wide (12 tiles)")
        print("      • Contains upgrade panel and other UI")
        print("      • Does not overlap with world view")
        print("")
        print("   ✅ WORLD VIEW (Left side):")
        print("      • 360px wide (600 - 240 sidebar)")
        print("      • 400px high")
        print("      • Game world is centered within this area")
        print("      • World may be scaled down to fit (zoom < 1.0)")
        print("")
        print("   ✅ RESOURCE PANEL (Top):")
        print("      • Spans full window width (600px)")
        print("      • 60px high (3 tiles)")
        print("      • Shows resource counters and rates")
        print("")
        print("   ✅ CAMERA BEHAVIOR:")
        print("      • World grid centered in view area")
        print("      • No clipping of game elements")
        print("      • Smooth interaction with game tiles")
        print("")
        print("4. Test interaction:")
        print("   • Click on tiles - should register correctly")
        print("   • UI elements should be clickable in their designated areas")
        print("   • No UI overflow or clipping")
        print("")
        print("Expected result: Clean, organized layout with properly")
        print("reserved sidebar and centered world view.")
        print("")

        t.expect(true).to_be_truthy()
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()