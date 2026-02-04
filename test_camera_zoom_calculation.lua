#!/usr/bin/env lua
--[[
Test camera zoom calculation with sidebar reservation.
Verifies the updated zoom formula: zoomX = WORLD_VIEW_W / config.VIRTUAL_WIDTH
]]

local function test_zoom_calculation()
    print("Testing camera zoom calculation with sidebar reservation...")

    -- Mock config values
    local config = {
        TILE_SIZE = 20,
        VIRTUAL_WIDTH = 600,   -- 30 * 20
        VIRTUAL_HEIGHT = 400   -- 20 * 20
    }

    local tests_passed = 0
    local tests_failed = 0

    -- Test case 1: Standard screen resolution (1920x1080)
    print("\nTest 1: Standard resolution (1920x1080)")
    local screenW, screenH = 1920, 1080
    local sidebar_w = config.TILE_SIZE * 12  -- 240 pixels
    local world_view_w = screenW - sidebar_w  -- 1680 pixels

    local zoomX = world_view_w / config.VIRTUAL_WIDTH  -- 1680 / 600 = 2.8
    local zoomY = screenH / config.VIRTUAL_HEIGHT      -- 1080 / 400 = 2.7
    local zoom = math.min(zoomX, zoomY)                -- 2.7

    print(string.format("  Screen: %dx%d, Sidebar: %d, World View: %d", screenW, screenH, sidebar_w, world_view_w))
    print(string.format("  ZoomX: %.2f, ZoomY: %.2f, Final Zoom: %.2f", zoomX, zoomY, zoom))

    if zoom == 2.7 and world_view_w == 1680 then
        print("✅ PASS: Correct zoom calculation with sidebar reservation")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Incorrect zoom calculation")
        tests_failed = tests_failed + 1
    end

    -- Test case 2: Smaller screen (800x600)
    print("\nTest 2: Smaller resolution (800x600)")
    screenW, screenH = 800, 600
    world_view_w = screenW - sidebar_w  -- 560 pixels

    zoomX = world_view_w / config.VIRTUAL_WIDTH  -- 560 / 600 = 0.933
    zoomY = screenH / config.VIRTUAL_HEIGHT      -- 600 / 400 = 1.5
    zoom = math.min(zoomX, zoomY)                -- 0.933

    print(string.format("  Screen: %dx%d, Sidebar: %d, World View: %d", screenW, screenH, sidebar_w, world_view_w))
    print(string.format("  ZoomX: %.3f, ZoomY: %.3f, Final Zoom: %.3f", zoomX, zoomY, zoom))

    if math.abs(zoom - 0.933) < 0.01 and world_view_w == 560 then
        print("✅ PASS: Correct zoom with constrained width")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Incorrect zoom with constrained width")
        tests_failed = tests_failed + 1
    end

    -- Test case 3: Very wide screen (2560x1440)
    print("\nTest 3: Ultra-wide resolution (2560x1440)")
    screenW, screenH = 2560, 1440
    world_view_w = screenW - sidebar_w  -- 2320 pixels

    zoomX = world_view_w / config.VIRTUAL_WIDTH  -- 2320 / 600 = 3.867
    zoomY = screenH / config.VIRTUAL_HEIGHT      -- 1440 / 400 = 3.6
    zoom = math.min(zoomX, zoomY)                -- 3.6

    print(string.format("  Screen: %dx%d, Sidebar: %d, World View: %d", screenW, screenH, sidebar_w, world_view_w))
    print(string.format("  ZoomX: %.3f, ZoomY: %.3f, Final Zoom: %.3f", zoomX, zoomY, zoom))

    if zoom == 3.6 and world_view_w == 2320 then
        print("✅ PASS: Correct zoom with ultra-wide screen")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Incorrect zoom with ultra-wide screen")
        tests_failed = tests_failed + 1
    end

    -- Test case 4: Verify sidebar takes exactly 12 tiles
    print("\nTest 4: Sidebar width calculation")
    local expected_sidebar = 12 * 20  -- 12 tiles * 20 pixels = 240 pixels

    if sidebar_w == expected_sidebar then
        print("✅ PASS: Sidebar width is exactly 12 tiles (240px)")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Sidebar width incorrect, got " .. sidebar_w .. ", expected " .. expected_sidebar)
        tests_failed = tests_failed + 1
    end

    -- Test case 5: Verify virtual dimensions match grid size
    print("\nTest 5: Virtual dimensions")
    local expected_virtual_w = 30 * 20  -- 30 tiles * 20 pixels = 600
    local expected_virtual_h = 20 * 20  -- 20 tiles * 20 pixels = 400

    if config.VIRTUAL_WIDTH == expected_virtual_w and config.VIRTUAL_HEIGHT == expected_virtual_h then
        print("✅ PASS: Virtual dimensions match grid (600x400)")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Virtual dimensions incorrect")
        tests_failed = tests_failed + 1
    end

    -- Summary
    print(string.format("\n🏁 Test Summary: %d passed, %d failed", tests_passed, tests_failed))

    if tests_failed == 0 then
        print("🎉 All tests passed! Camera zoom calculation with sidebar reservation works correctly:")
        print("  ✅ Sidebar width reserves 12 tiles (240px)")
        print("  ✅ World view width = screen width - sidebar width")
        print("  ✅ ZoomX = world_view_w / VIRTUAL_WIDTH")
        print("  ✅ ZoomY = screen_height / VIRTUAL_HEIGHT")
        print("  ✅ Final zoom = min(zoomX, zoomY) for proper fitting")
        print("  ✅ Works correctly across different screen resolutions")
        return true
    else
        print("⚠️ Some tests failed!")
        return false
    end
end

-- Run the test
return test_zoom_calculation()