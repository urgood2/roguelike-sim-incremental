#!/usr/bin/env lua
--[[
Integration test to verify terrain.place_structure works with the new validation function.
]]

-- Setup package path for modules
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Mock the forma dependency
local forma_mock = {
    pattern = {
        square = function(w, h) return { sample = function(self, count) return { cells = function() return function() end end } end } end,
        primitives = { square = function(w, h) return { sample = function(self, count) return { cells = function() return function() end end } end } end },
        automata = {
            rule = function(n, r) return {} end,
            iterate = function(p, d, r) return p, true end
        },
        neighbourhood = { moore = function() return {} end }
    }
}

package.loaded["external.forma.pattern"] = forma_mock.pattern
package.loaded["external.forma.primitives"] = forma_mock.pattern
package.loaded["external.forma.automata"] = forma_mock.automata
package.loaded["external.forma.neighbourhood"] = forma_mock.neighbourhood

local function run_integration_test()
    print("Testing terrain.place_structure integration with validation...")

    -- Create minimal terrain module for testing
    local terrain = {
        GRASS = "GRASS",
        TREE = "TREE",
        ROCK = "ROCK",
        _currentGrid = nil,
        _structures = {},
        _next_structure_id = 1
    }

    -- Simple grid implementation
    local Grid = {}
    Grid.__index = Grid

    function Grid.new(width, height)
        local self = setmetatable({}, Grid)
        self.width = width
        self.height = height
        self.cells = {}
        for y = 0, height - 1 do
            self.cells[y] = {}
            for x = 0, width - 1 do
                self.cells[y][x] = terrain.GRASS
            end
        end
        return self
    end

    function Grid:get(x, y)
        if not self.cells[y] then return nil end
        return self.cells[y][x]
    end

    function terrain.get(tileX, tileY)
        if not terrain._currentGrid then return nil end
        if tileX < 0 or tileX >= terrain._currentGrid.width then return nil end
        if tileY < 0 or tileY >= terrain._currentGrid.height then return nil end
        return terrain._currentGrid:get(tileX, tileY)
    end

    function terrain.setCurrentGrid(grid)
        terrain._currentGrid = grid
    end

    -- Valid structure types
    local VALID_STRUCTURE_TYPES = {
        farm = true,
        mine = true,
        house = true,
        workshop = true,
        storage = true
    }

    -- Validation function
    function terrain.validate_structure_placement(x, y, structure_type)
        if not x or not y or not structure_type then
            return false, "x, y, and structure_type required"
        end

        if not terrain._currentGrid then
            return false, "No current grid set"
        end

        if x < 0 or x >= terrain._currentGrid.width or y < 0 or y >= terrain._currentGrid.height then
            return false, "Invalid coordinates: out of bounds"
        end

        if not VALID_STRUCTURE_TYPES[structure_type] then
            return false, "Invalid structure type: " .. tostring(structure_type)
        end

        for _, structure in pairs(terrain._structures) do
            if structure.x == x and structure.y == y then
                return false, "Position already occupied by structure"
            end
        end

        local tile = terrain.get(x, y)
        if tile ~= terrain.GRASS then
            return false, "Structures can only be placed on grass terrain (walkable)"
        end

        return true, nil
    end

    -- Place structure function using validation
    function terrain.place_structure(x, y, structure_type)
        -- Use the dedicated validation function
        local valid, error_message = terrain.validate_structure_placement(x, y, structure_type)
        if not valid then
            return false, error_message
        end

        -- Create structure with unique ID
        local structure = {
            id = terrain._next_structure_id,
            x = x,
            y = y,
            type = structure_type,
            created_at = os.time()
        }

        terrain._next_structure_id = terrain._next_structure_id + 1
        terrain._structures[structure.id] = structure

        print(string.format("[TERRAIN] Placed structure #%d: %s at (%d,%d)",
              structure.id, structure_type, x, y))

        return true, structure.id
    end

    function terrain.get_structures()
        return terrain._structures
    end

    -- Set up test grid
    local grid = Grid.new(5, 5)
    terrain.setCurrentGrid(grid)

    print("\n=== Testing place_structure with validation integration ===")

    -- Test 1: Valid placement should succeed
    print("\nTest 1: Valid placement")
    local success1, result1 = terrain.place_structure(1, 1, "farm")
    if success1 then
        print("✅ PASS: Structure placed successfully, ID:", result1)
    else
        print("❌ FAIL: Valid placement failed:", result1)
        return false
    end

    -- Test 2: Invalid placement should fail with proper error message
    print("\nTest 2: Invalid placement (out of bounds)")
    local success2, result2 = terrain.place_structure(10, 10, "house")
    if not success2 and result2:find("out of bounds") then
        print("✅ PASS: Invalid placement properly rejected:", result2)
    else
        print("❌ FAIL: Invalid placement not properly handled:", success2, result2)
        return false
    end

    -- Test 3: Duplicate placement should fail
    print("\nTest 3: Duplicate placement")
    local success3, result3 = terrain.place_structure(1, 1, "mine")
    if not success3 and result3:find("already occupied") then
        print("✅ PASS: Duplicate placement properly rejected:", result3)
    else
        print("❌ FAIL: Duplicate placement not properly handled:", success3, result3)
        return false
    end

    -- Verify structures were placed correctly
    local structures = terrain.get_structures()
    local structure_count = 0
    for _ in pairs(structures) do structure_count = structure_count + 1 end

    print("\nFinal verification:")
    print("  Structures placed:", structure_count, "(expected: 1)")

    if structure_count == 1 then
        print("✅ PASS: Correct number of structures placed")
    else
        print("❌ FAIL: Incorrect number of structures")
        return false
    end

    print("\n🎉 Integration test passed! terrain.place_structure works correctly with validation.")
    return true
end

-- Run the integration test
return run_integration_test()