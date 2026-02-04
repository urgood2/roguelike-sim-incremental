--[[
================================================================================
TEST: Debug Panel Integration Test
================================================================================
Verifies that the ImGui debug panel is still functional after recent changes.
Tests both summary and detail panels for proper functionality.

Run with: lua assets/scripts/tests/test_debug_panel_integration.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached modules if re-running
package.loaded["idle_game.ui.debug_panel"] = nil
package.loaded["idle_game.selection"] = nil

local t = require("tests.test_runner")

-- Mock ImGui module for headless testing
local function createImGuiMock()
    return {
        SetNextWindowPos = function() end,
        SetNextWindowSize = function() end,
        SetNextWindowBgAlpha = function() end,
        Begin = function(title, open, flags) return true, true end,
        End = function() end,
        Text = function(text) end,
        TextColored = function(r, g, b, a, text) end,
        TextWrapped = function(text) end,
        Separator = function() end,
        SameLine = function() end,
        BeginChild = function(name, w, h, border) return true end,
        EndChild = function() end
    }
end

-- Mock AI module
local function createAiMock()
    return {
        list_goap_entities = function()
            return {1001, 1002, 1003}  -- Mock entity IDs
        end,
        get_goap_state = function(entity)
            return {
                current_goal = "HARVEST_WOOD",
                current_action = "MOVE_TO_TREE",
                atoms = {
                    {name = "nearTree", current = true, goal = true},
                    {name = "hasWood", current = false, goal = "dontcare"},
                    {name = "canWork", current = true, goal = true}
                }
            }
        end,
        get_trace_events = function(entity, limit)
            return {
                {type = "goal_started", message = "Started HARVEST_WOOD goal"},
                {type = "action_changed", message = "Action: MOVE_TO_TREE"},
                {type = "worldstate_updated", message = "Updated nearTree: true"}
            }
        end
    }
end

-- Mock selection module
local function createSelectionMock()
    return {
        selected_entity = nil,  -- Initially no entity selected
        selectEntity = function(entity)
            package.loaded["idle_game.selection"].selected_entity = entity
        end
    }
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Debug Panel Integration Tests", function()

    -- Test 1: Module loads without errors
    t.it("loads debug panel module without errors", function()
        local success, debug_panel = pcall(require, "idle_game.ui.debug_panel")
        t.expect(success).to_equal(true)
        t.expect(debug_panel ~= nil).to_equal(true)
        t.expect(type(debug_panel.draw)).to_equal("function")
        t.expect(type(debug_panel.drawSummary)).to_equal("function")
        t.expect(type(debug_panel.drawDetails)).to_equal("function")
    end)

    -- Test 2: Summary panel handles missing dependencies gracefully
    t.it("handles missing ImGui gracefully in summary panel", function()
        -- Setup mocks
        _G.ImGui = nil
        _G.ai = createAiMock()
        package.loaded["idle_game.selection"] = createSelectionMock()

        local debug_panel = require("idle_game.ui.debug_panel")

        -- Should not crash when ImGui is not available
        local success = pcall(debug_panel.drawSummary)
        t.expect(success).to_equal(true)
    end)

    -- Test 3: Summary panel handles missing AI gracefully
    t.it("handles missing AI module gracefully in summary panel", function()
        -- Setup mocks
        _G.ImGui = createImGuiMock()
        _G.ai = nil
        package.loaded["idle_game.selection"] = createSelectionMock()

        local debug_panel = require("idle_game.ui.debug_panel")

        -- Should not crash when AI is not available
        local success = pcall(debug_panel.drawSummary)
        t.expect(success).to_equal(true)
    end)

    -- Test 4: Summary panel works with full dependencies
    t.it("displays summary panel correctly with full dependencies", function()
        -- Setup full mocks
        _G.ImGui = createImGuiMock()
        _G.ai = createAiMock()
        _G.ImGuiWindowFlags = {NoResize = 1, NoCollapse = 2}
        _G.ImGuiCond = {FirstUseEver = 2}
        package.loaded["idle_game.selection"] = createSelectionMock()

        local debug_panel = require("idle_game.ui.debug_panel")

        -- Should work without errors
        local success = pcall(debug_panel.drawSummary)
        t.expect(success).to_equal(true)
    end)

    -- Test 5: Details panel handles no selection gracefully
    t.it("handles no selected entity gracefully in details panel", function()
        -- Setup mocks
        _G.ImGui = createImGuiMock()
        _G.ai = createAiMock()
        package.loaded["idle_game.selection"] = createSelectionMock()
        -- Keep selected_entity as nil

        local debug_panel = require("idle_game.ui.debug_panel")

        -- Should return early when no entity selected
        local success = pcall(debug_panel.drawDetails)
        t.expect(success).to_equal(true)
    end)

    -- Test 6: Details panel works with selected entity
    t.it("displays entity details correctly with selection", function()
        -- Setup mocks
        _G.ImGui = createImGuiMock()
        _G.ai = createAiMock()
        package.loaded["idle_game.selection"] = createSelectionMock()

        local debug_panel = require("idle_game.ui.debug_panel")

        -- Select an entity
        local selection = require("idle_game.selection")
        selection.selected_entity = 1001

        -- Should work without errors
        local success = pcall(debug_panel.drawDetails)
        t.expect(success).to_equal(true)
    end)

    -- Test 7: Main draw function integrates both panels
    t.it("integrates both summary and details panels in main draw", function()
        -- Setup full mocks
        _G.ImGui = createImGuiMock()
        _G.ai = createAiMock()
        package.loaded["idle_game.selection"] = createSelectionMock()

        local debug_panel = require("idle_game.ui.debug_panel")

        -- Test main draw function
        local success = pcall(debug_panel.draw)
        t.expect(success).to_equal(true)
    end)

    -- Test 8: Panel configuration values are accessible
    t.it("has accessible configuration values", function()
        local debug_panel = require("idle_game.ui.debug_panel")

        t.expect(type(debug_panel.panel_width)).to_equal("number")
        t.expect(type(debug_panel.panel_height)).to_equal("number")
        t.expect(type(debug_panel.panel_x)).to_equal("number")
        t.expect(type(debug_panel.panel_y)).to_equal("number")

        t.expect(debug_panel.panel_width).to_equal(280)
        t.expect(debug_panel.panel_height).to_equal(400)
    end)

end)

--------------------------------------------------------------------------------
-- Cleanup and auto-run
--------------------------------------------------------------------------------

-- Clean up global mocks after tests
local function cleanup()
    _G.ImGui = nil
    _G.ai = nil
    _G.ImGuiWindowFlags = nil
    _G.ImGuiCond = nil
    package.loaded["idle_game.ui.debug_panel"] = nil
    package.loaded["idle_game.selection"] = nil
end

-- Auto-run if executed directly
if arg and arg[0] and arg[0]:match("test_debug_panel_integration%.lua$") then
    t.run()
    cleanup()
end