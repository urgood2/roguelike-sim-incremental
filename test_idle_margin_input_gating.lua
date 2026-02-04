--[[
================================================================================
INTEGRATION TEST: Margin Input Gating
================================================================================
Verifies that clicks in margin areas (outside screen bounds) have no effect
on the game state, while clicks within valid bounds work correctly.

Run with: lua test_idle_margin_input_gating.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached modules if re-running
package.loaded["idle_game.input"] = nil
package.loaded["idle_game.config"] = nil
package.loaded["idle_game.resources"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Mock Dependencies
--------------------------------------------------------------------------------

-- Mock input system for testing
local MockInput = {}
function MockInput.new()
    local self = {
        mouse_pressed = false,
        mouse_x = 0,
        mouse_y = 0
    }

    function self.setMousePressed(pressed)
        self.mouse_pressed = pressed
    end

    function self.setMousePos(x, y)
        self.mouse_x = x
        self.mouse_y = y
    end

    -- Mock the global input functions
    function self.install()
        _G.input = {
            isMousePressed = function(button)
                return self.mouse_pressed
            end,
            getMousePos = function()
                return { x = self.mouse_x, y = self.mouse_y }
            end
        }

        -- Mock mouse button constants
        _G.MouseButton = {
            MOUSE_BUTTON_LEFT = 0
        }

        -- Mock globals for screen dimensions
        _G.globals = {
            screenWidth = function() return 1280 end,
            screenHeight = function() return 800 end
        }

        -- Mock camera system (for coordinate conversion)
        _G.camera = {
            Exists = function(name) return name == "world_camera" end,
            Get = function(name)
                if name == "world_camera" then
                    return {
                        GetMouseWorld = function()
                            -- Simple 1:1 mapping for testing (no zoom/offset)
                            return { x = self.mouse_x, y = self.mouse_y }
                        end
                    }
                end
                return nil
            end
        }
    end

    function self.cleanup()
        _G.input = nil
        _G.MouseButton = nil
        _G.globals = nil
        _G.camera = nil
    end

    return self
end

-- Mock log_debug function to prevent undefined function errors
_G.log_debug = function(msg)
    -- Optionally uncomment for debugging:
    -- print("[DEBUG] " .. msg)
end

--------------------------------------------------------------------------------
-- Test Utilities
--------------------------------------------------------------------------------

local function simulate_click(mock_input, x, y)
    mock_input.setMousePos(x, y)
    mock_input.setMousePressed(true)

    local input_module = require("idle_game.input")
    local config = require("idle_game.config")

    local tile_x, tile_y = input_module.handleClick(config)

    mock_input.setMousePressed(false)

    return tile_x, tile_y
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Margin Input Gating - Integration Tests", function()

    local mock_input = nil

    t.before_each(function()
        mock_input = MockInput.new()
        mock_input.install()
    end)

    t.after_each(function()
        if mock_input then
            mock_input.cleanup()
        end
    end)

    -- Test 1: Clicks with negative X coordinates are blocked
    t.it("blocks clicks with negative X coordinates", function()
        local tile_x, tile_y = simulate_click(mock_input, -10, 400)
        t.expect(tile_x).to_be_nil()
        t.expect(tile_y).to_be_nil()
    end)

    -- Test 2: Clicks with negative Y coordinates are blocked
    t.it("blocks clicks with negative Y coordinates", function()
        local tile_x, tile_y = simulate_click(mock_input, 640, -5)
        t.expect(tile_x).to_be_nil()
        t.expect(tile_y).to_be_nil()
    end)

    -- Test 3: Clicks at or beyond right edge are blocked
    t.it("blocks clicks at or beyond right edge (X >= screen_width)", function()
        -- At exact boundary
        local tile_x, tile_y = simulate_click(mock_input, 1280, 400)
        t.expect(tile_x).to_be_nil()
        t.expect(tile_y).to_be_nil()

        -- Beyond boundary
        tile_x, tile_y = simulate_click(mock_input, 1300, 400)
        t.expect(tile_x).to_be_nil()
        t.expect(tile_y).to_be_nil()
    end)

    -- Test 4: Clicks at or beyond bottom edge are blocked
    t.it("blocks clicks at or beyond bottom edge (Y >= screen_height)", function()
        -- At exact boundary
        local tile_x, tile_y = simulate_click(mock_input, 640, 800)
        t.expect(tile_x).to_be_nil()
        t.expect(tile_y).to_be_nil()

        -- Beyond boundary
        tile_x, tile_y = simulate_click(mock_input, 640, 850)
        t.expect(tile_x).to_be_nil()
        t.expect(tile_y).to_be_nil()
    end)

    -- Test 5: Clicks in all four corner margins are blocked
    t.it("blocks clicks in all four corner margin areas", function()
        -- Top-left corner (negative coordinates)
        local tile_x, tile_y = simulate_click(mock_input, -1, -1)
        t.expect(tile_x).to_be_nil()
        t.expect(tile_y).to_be_nil()

        -- Top-right corner
        tile_x, tile_y = simulate_click(mock_input, 1281, -1)
        t.expect(tile_x).to_be_nil()
        t.expect(tile_y).to_be_nil()

        -- Bottom-left corner
        tile_x, tile_y = simulate_click(mock_input, -1, 801)
        t.expect(tile_x).to_be_nil()
        t.expect(tile_y).to_be_nil()

        -- Bottom-right corner
        tile_x, tile_y = simulate_click(mock_input, 1281, 801)
        t.expect(tile_x).to_be_nil()
        t.expect(tile_y).to_be_nil()
    end)

    -- Test 6: Valid clicks within bounds work correctly (control test)
    t.it("allows valid clicks within screen bounds", function()
        -- Click within game grid bounds (300px = 300/20 = tile 15, 200px = 200/20 = tile 10)
        local tile_x, tile_y = simulate_click(mock_input, 300, 200)

        -- Should return valid tile coordinates (not nil)
        t.expect(tile_x).to_be_type("number")
        t.expect(tile_y).to_be_type("number")

        -- Tile coordinates should be within valid range
        local config = require("idle_game.config")
        t.expect(tile_x >= 0 and tile_x < config.GRID_WIDTH).to_be_truthy()
        t.expect(tile_y >= 0 and tile_y < config.GRID_HEIGHT).to_be_truthy()
    end)

    -- Test 7: Edge coordinates just inside bounds work correctly
    t.it("allows clicks just inside screen bounds", function()
        -- Just inside top-left corner of game grid (10px = tile 0, 10px = tile 0)
        local tile_x, tile_y = simulate_click(mock_input, 10, 10)
        t.expect(tile_x).to_be_type("number")
        t.expect(tile_y).to_be_type("number")

        -- Just inside bottom-right corner of game grid (580px = tile 29, 380px = tile 19)
        tile_x, tile_y = simulate_click(mock_input, 580, 380)
        t.expect(tile_x).to_be_type("number")
        t.expect(tile_y).to_be_type("number")
    end)

    -- Test 8: No click input (mouse not pressed) returns nil
    t.it("returns nil when mouse is not pressed", function()
        mock_input.setMousePos(640, 400)  -- Valid position
        mock_input.setMousePressed(false) -- But not pressed

        local input_module = require("idle_game.input")
        local config = require("idle_game.config")

        local tile_x, tile_y = input_module.handleClick(config)
        t.expect(tile_x).to_be_nil()
        t.expect(tile_y).to_be_nil()
    end)

    -- Test 9: Click out of tile grid bounds returns nil (even if within screen)
    t.it("returns nil for clicks outside tile grid bounds", function()
        -- This test verifies that clicks within screen bounds but outside
        -- the game's tile grid are properly handled

        -- Mock a larger screen but keep the same tile grid size
        _G.globals = {
            screenWidth = function() return 2000 end,   -- Much larger than grid
            screenHeight = function() return 1500 end
        }

        -- Click within screen but way outside tile grid
        local tile_x, tile_y = simulate_click(mock_input, 1500, 1200)

        -- Should pass margin gating but fail tile bounds check
        t.expect(tile_x).to_be_nil()
        t.expect(tile_y).to_be_nil()
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()