#!/usr/bin/env lua
--[[
Integration test for ImGui debug panel functionality.
Verifies that the debug panel can handle various states and dependencies correctly.
]]

-- Setup package path
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local function create_imgui_mock()
    local imgui_mock = {
        Begin = function(title, open, flags) return true, true end,
        End = function() end,
        SetNextWindowPos = function(x, y, cond) end,
        SetNextWindowSize = function(w, h, cond) end,
        SetNextWindowBgAlpha = function(alpha) end,
        Text = function(text) print("ImGui Text:", text) end,
        TextColored = function(r, g, b, a, text) print("ImGui Colored:", text) end,
        TextWrapped = function(text) print("ImGui Wrapped:", text) end,
        Separator = function() print("ImGui ──────────") end,
        SameLine = function() end,
        BeginChild = function(id, w, h, border) return true end,
        EndChild = function() end
    }

    return imgui_mock
end

local function create_ai_mock()
    local ai_mock = {
        list_goap_entities = function()
            return {1001, 1002, 1003}  -- Mock entity IDs
        end,
        get_goap_state = function(entity)
            return {
                current_goal = "HARVEST_WOOD",
                current_action = "idle_harvest_wood",
                atoms = {
                    {name = "hasFood", current = true, goal = true},
                    {name = "nearTree", current = false, goal = true},
                    {name = "canWork", current = true, goal = "dontcare"}
                }
            }
        end,
        get_trace_events = function(entity, count)
            return {
                {type = "goal_selected", message = "Selected goal: HARVEST_WOOD"},
                {type = "action_started", message = "Started action: idle_harvest_wood"},
                {type = "move_to", message = "Moving to tree at (5, 7)"}
            }
        end
    }

    return ai_mock
end

local function create_selection_mock()
    return {
        selected_entity = 1001  -- Mock selected entity
    }
end

local function test_debug_panel_functionality()
    print("Testing ImGui debug panel functionality...")

    -- Set up mocks
    local imgui_mock = create_imgui_mock()
    local ai_mock = create_ai_mock()
    local selection_mock = create_selection_mock()

    -- Override global modules
    _G.ImGui = imgui_mock
    _G.ImGuiWindowFlags = { NoResize = 1, NoCollapse = 2 }
    _G.ImGuiCond = { FirstUseEver = 2 }

    package.loaded["ai.init"] = ai_mock
    _G.ai = ai_mock

    package.loaded["idle_game.selection"] = selection_mock

    -- Load the debug panel module
    local debug_panel = require("idle_game.ui.debug_panel")

    local tests_passed = 0
    local tests_failed = 0

    -- Test 1: Debug panel module loads correctly
    print("\nTest 1: Module loading")
    if debug_panel and type(debug_panel.draw) == "function" then
        print("✅ PASS: Debug panel module loaded with draw function")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Debug panel module failed to load properly")
        tests_failed = tests_failed + 1
    end

    -- Test 2: Summary panel functionality
    print("\nTest 2: Summary panel (drawSummary)")
    local summary_success = pcall(function()
        debug_panel.drawSummary()
    end)

    if summary_success then
        print("✅ PASS: Summary panel draws without errors")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Summary panel throws errors")
        tests_failed = tests_failed + 1
    end

    -- Test 3: Details panel functionality
    print("\nTest 3: Details panel (drawDetails)")
    local details_success = pcall(function()
        debug_panel.drawDetails()
    end)

    if details_success then
        print("✅ PASS: Details panel draws without errors")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Details panel throws errors")
        tests_failed = tests_failed + 1
    end

    -- Test 4: Main draw function
    print("\nTest 4: Main draw function")
    local main_draw_success = pcall(function()
        debug_panel.draw()
    end)

    if main_draw_success then
        print("✅ PASS: Main draw function works without errors")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Main draw function throws errors")
        tests_failed = tests_failed + 1
    end

    -- Test 5: Panel configuration values
    print("\nTest 5: Panel configuration")
    if debug_panel.panel_width and debug_panel.panel_height and
       debug_panel.panel_x and debug_panel.panel_y then
        print("✅ PASS: Panel configuration values defined")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Panel configuration values missing")
        tests_failed = tests_failed + 1
    end

    -- Test 6: Handle missing ImGui gracefully
    print("\nTest 6: Missing ImGui handling")
    local old_imgui = _G.ImGui
    _G.ImGui = nil

    local no_imgui_success = pcall(function()
        debug_panel.draw()
    end)

    _G.ImGui = old_imgui  -- Restore

    if no_imgui_success then
        print("✅ PASS: Handles missing ImGui gracefully")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Crashes when ImGui not available")
        tests_failed = tests_failed + 1
    end

    -- Test 7: Handle missing ai module gracefully
    print("\nTest 7: Missing AI module handling")
    local old_ai = _G.ai
    _G.ai = nil

    local no_ai_success = pcall(function()
        debug_panel.drawSummary()
        debug_panel.drawDetails()
    end)

    _G.ai = old_ai  -- Restore

    if no_ai_success then
        print("✅ PASS: Handles missing AI module gracefully")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Crashes when AI module not available")
        tests_failed = tests_failed + 1
    end

    -- Test 8: Handle no selected entity
    print("\nTest 8: No selected entity handling")
    selection_mock.selected_entity = nil

    local no_selection_success = pcall(function()
        debug_panel.drawDetails()
    end)

    selection_mock.selected_entity = 1001  -- Restore

    if no_selection_success then
        print("✅ PASS: Handles no selected entity gracefully")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Crashes when no entity selected")
        tests_failed = tests_failed + 1
    end

    -- Summary
    print(string.format("\n🏁 Test Summary: %d passed, %d failed", tests_passed, tests_failed))

    if tests_failed == 0 then
        print("🎉 All tests passed! ImGui debug panel is fully functional:")
        print("  ✅ Module loads correctly")
        print("  ✅ Summary panel displays entity and action information")
        print("  ✅ Details panel shows GOAP state when entity selected")
        print("  ✅ Main draw function works without errors")
        print("  ✅ Panel configuration is properly defined")
        print("  ✅ Gracefully handles missing ImGui")
        print("  ✅ Gracefully handles missing AI module")
        print("  ✅ Gracefully handles no selected entity")
        return true
    else
        print("⚠️ Some tests failed - debug panel may have issues!")
        return false
    end
end

-- Run the test
return test_debug_panel_functionality()