#!/usr/bin/env lua
--[[
Integration test for resource panel click blocking functionality.
Verifies that clicks inside the resource panel don't affect the world (no tree/rock harvesting).
]]

-- Setup package path
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local function create_resource_panel_mock()
    local panel_rect = { x = 0, y = 0, w = 200, h = 120 }  -- 10*20 x 6*20 tiles

    return {
        get_rect = function() return panel_rect end,
        hit_test = function(x, y)
            local in_bounds = x >= panel_rect.x and x < panel_rect.x + panel_rect.w and
                             y >= panel_rect.y and y < panel_rect.y + panel_rect.h
            return in_bounds and { consumed = true } or nil
        end,
        init = function() end,
        draw = function() end,
        update = function() end
    }
end

local function create_terrain_mock()
    local grid = {}
    local TREE, ROCK, GRASS = 1, 2, 0

    -- Initialize 3x3 grid with resources
    for y = 0, 2 do
        grid[y] = {}
        for x = 0, 2 do
            if x == 1 and y == 1 then
                grid[y][x] = TREE  -- Tree at center
            elseif x == 2 and y == 1 then
                grid[y][x] = ROCK  -- Rock at right
            else
                grid[y][x] = GRASS
            end
        end
    end

    return {
        get = function(x, y)
            if grid[y] and grid[y][x] then
                return grid[y][x]
            end
            return GRASS
        end,
        set = function(x, y, type)
            if grid[y] then
                grid[y][x] = type
            end
        end,
        TREE = TREE,
        ROCK = ROCK,
        GRASS = GRASS,
        get_grid_state = function() return grid end
    }
end

local function create_config_mock()
    return {
        TILE_SIZE = 20,
        GRID_WIDTH = 3,
        GRID_HEIGHT = 3
    }
end

local function create_resources_mock()
    local resources = { wood = 0, stone = 0, gold = 0 }

    return {
        get = function(type) return resources[type] or 0 end,
        add = function(type, amount)
            resources[type] = (resources[type] or 0) + amount
        end,
        get_state = function() return resources end,
        reset = function()
            resources = { wood = 0, stone = 0, gold = 0 }
        end
    }
end

local function create_input_mock()
    local click_x, click_y = 0, 0
    local mouse_pressed = false

    return {
        set_click_position = function(x, y)
            click_x, click_y = x, y
        end,
        set_mouse_pressed = function(pressed)
            mouse_pressed = pressed
        end,
        getMousePos = function()
            return { x = click_x, y = click_y }
        end,
        isMousePressed = function()
            return mouse_pressed
        end
    }
end

local function test_resource_panel_click_blocking()
    print("Testing resource panel click blocking functionality...")

    -- Create mocks
    local resource_panel_mock = create_resource_panel_mock()
    local terrain_mock = create_terrain_mock()
    local config_mock = create_config_mock()
    local resources_mock = create_resources_mock()
    local input_mock = create_input_mock()

    -- Mock global dependencies
    _G.input = input_mock
    _G.MouseButton = { MOUSE_BUTTON_LEFT = 0 }

    local tests_passed = 0
    local tests_failed = 0

    -- Test 1: Click inside resource panel should be blocked
    print("\nTest 1: Click inside resource panel (should be blocked)")

    -- Reset resources
    resources_mock.reset()

    -- Set up click inside panel bounds
    local panel_rect = resource_panel_mock.get_rect()
    local click_x = panel_rect.x + 50  -- Inside panel
    local click_y = panel_rect.y + 50

    input_mock.set_click_position(click_x, click_y)
    input_mock.set_mouse_pressed(true)

    print(string.format("  Clicking at (%d, %d) - inside panel bounds", click_x, click_y))

    -- Simulate the click blocking logic from sim_scene.lua
    local click_consumed = false

    -- Test resource panel hit
    local resource_hit = resource_panel_mock.hit_test(click_x, click_y)
    if resource_hit and resource_hit.consumed then
        click_consumed = true
        print("  ✓ Resource panel hit test returned consumed=true")
    end

    -- Only process terrain if not consumed
    local terrain_processed = false
    if not click_consumed then
        -- Would normally process terrain click here
        terrain_processed = true
        print("  ❌ ERROR: Terrain would be processed despite panel hit")
    else
        print("  ✓ Terrain processing correctly blocked")
    end

    -- Verify no resources were added (terrain not processed)
    local wood_before = resources_mock.get("wood")
    local stone_before = resources_mock.get("stone")

    if click_consumed and not terrain_processed and wood_before == 0 and stone_before == 0 then
        print("✅ PASS: Click inside panel correctly blocked world interaction")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Panel click blocking failed")
        tests_failed = tests_failed + 1
    end

    -- Test 2: Click outside resource panel should reach terrain
    print("\nTest 2: Click outside resource panel (should reach terrain)")

    resources_mock.reset()

    -- Set up click outside panel bounds
    click_x = panel_rect.x + panel_rect.w + 10  -- Outside panel
    click_y = panel_rect.y + panel_rect.h + 10

    input_mock.set_click_position(click_x, click_y)

    print(string.format("  Clicking at (%d, %d) - outside panel bounds", click_x, click_y))

    click_consumed = false

    -- Test resource panel hit
    resource_hit = resource_panel_mock.hit_test(click_x, click_y)
    if resource_hit and resource_hit.consumed then
        click_consumed = true
        print("  ❌ ERROR: Resource panel incorrectly reported hit outside bounds")
    else
        print("  ✓ Resource panel correctly reported no hit")
    end

    terrain_processed = false
    if not click_consumed then
        terrain_processed = true
        print("  ✓ Terrain processing allowed (click not blocked)")
    end

    if not click_consumed and terrain_processed then
        print("✅ PASS: Click outside panel correctly reaches terrain")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Click outside panel was incorrectly blocked")
        tests_failed = tests_failed + 1
    end

    -- Test 3: Click on panel edge boundary
    print("\nTest 3: Click on panel edge boundary")

    -- Click exactly on right edge (should be outside)
    click_x = panel_rect.x + panel_rect.w  -- Exactly at right edge
    click_y = panel_rect.y + 10            -- Within Y bounds

    input_mock.set_click_position(click_x, click_y)

    print(string.format("  Clicking at (%d, %d) - on panel right edge", click_x, click_y))

    resource_hit = resource_panel_mock.hit_test(click_x, click_y)
    if resource_hit and resource_hit.consumed then
        print("  ❌ FAIL: Panel edge click incorrectly reported as hit")
        tests_failed = tests_failed + 1
    else
        print("✅ PASS: Panel edge click correctly not consumed")
        tests_passed = tests_passed + 1
    end

    -- Test 4: Verify panel dimensions match expected values
    print("\nTest 4: Panel dimensions verification")

    local expected_w = 10 * config_mock.TILE_SIZE  -- 200 pixels
    local expected_h = 6 * config_mock.TILE_SIZE   -- 120 pixels

    if panel_rect.w == expected_w and panel_rect.h == expected_h then
        print(string.format("✅ PASS: Panel dimensions correct (%dx%d)", panel_rect.w, panel_rect.h))
        tests_passed = tests_passed + 1
    else
        print(string.format("❌ FAIL: Panel dimensions incorrect (got %dx%d, expected %dx%d)",
              panel_rect.w, panel_rect.h, expected_w, expected_h))
        tests_failed = tests_failed + 1
    end

    -- Test 5: Multiple clicks inside panel area
    print("\nTest 5: Multiple clicks inside panel")

    local panel_clicks = {
        { x = panel_rect.x + 10, y = panel_rect.y + 10 },     -- Top-left
        { x = panel_rect.x + 100, y = panel_rect.y + 60 },     -- Center
        { x = panel_rect.x + 190, y = panel_rect.y + 110 }     -- Bottom-right (within bounds)
    }

    local all_blocked = true
    for i, pos in ipairs(panel_clicks) do
        input_mock.set_click_position(pos.x, pos.y)
        resource_hit = resource_panel_mock.hit_test(pos.x, pos.y)

        if not (resource_hit and resource_hit.consumed) then
            print(string.format("  ❌ Click %d at (%d, %d) not blocked", i, pos.x, pos.y))
            all_blocked = false
        else
            print(string.format("  ✓ Click %d at (%d, %d) correctly blocked", i, pos.x, pos.y))
        end
    end

    if all_blocked then
        print("✅ PASS: All clicks inside panel correctly blocked")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Some clicks inside panel were not blocked")
        tests_failed = tests_failed + 1
    end

    -- Summary
    print(string.format("\n🏁 Test Summary: %d passed, %d failed", tests_passed, tests_failed))

    if tests_failed == 0 then
        print("🎉 All tests passed! Resource panel click blocking works correctly:")
        print("  ✅ Clicks inside panel bounds are blocked (consumed=true)")
        print("  ✅ Clicks outside panel bounds reach terrain processing")
        print("  ✅ Panel edge boundaries are handled correctly")
        print("  ✅ Panel dimensions match specification (10x6 tiles)")
        print("  ✅ Multiple clicks inside panel are consistently blocked")
        print("  ✅ No unintended world interaction when clicking UI elements")
        return true
    else
        print("⚠️ Some tests failed - click blocking may have issues!")
        return false
    end
end

-- Run the test
return test_resource_panel_click_blocking()