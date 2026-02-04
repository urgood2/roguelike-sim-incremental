--[[
================================================================================
TEST: Idle Game Structures Persistence
================================================================================
Validates that structure persistence drops invalid entries and preserves valid ones.

Run with: lua assets/scripts/tests/test_idle_structures_persistence.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua;./assets/scripts/external/?.lua;./assets/scripts/external/?/init.lua"

-- Clear cached modules if re-running
package.loaded["core.save_manager"] = nil
package.loaded["idle_game.terrain"] = nil
package.loaded["idle_game.terrain_persistence"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function normalize_structure(structure)
    local x = structure.x or structure.tileX
    local y = structure.y or structure.tileY
    local kind = structure.type or structure.sprite
    return x, y, kind
end

local function count_structures(structures)
    local count = 0
    for _ in pairs(structures) do
        count = count + 1
    end
    return count
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Idle Structures Persistence", function()

    t.it("distribute drops invalid entries and preserves valid ones", function()
        local SaveManager = require("core.save_manager")
        SaveManager.collectors = {}
        SaveManager.cache = {}

        local terrain = require("idle_game.terrain")
        local grid = terrain.generate(1, 5, 5)
        grid:set(1, 1, terrain.GRASS)
        grid:set(2, 2, terrain.GRASS)
        terrain.setCurrentGrid(grid)

        local ok, _ = pcall(require, "idle_game.terrain_persistence")
        t.expect(ok).to_be_truthy()
        if not ok then
            return
        end

        local collector = SaveManager.collectors["idle_structures"]
        t.expect(collector).to_be_truthy()

        local input = {
            { x = 1, y = 1, tileX = 1, tileY = 1, type = "farm", sprite = "farm" },
            { x = 10, y = 0, tileX = 10, tileY = 0, type = "mine", sprite = "mine" },
            { x = 2, y = 2, tileX = 2, tileY = 2, type = "invalid", sprite = "invalid" },
        }

        -- Wrap distribute call in pcall to handle errors gracefully
        local success, err = pcall(function()
            collector.distribute(input)
        end)

        if not success then
            print("Warning: distribute call failed: " .. tostring(err))
        end

        local structures = terrain.get_structures()
        local total = count_structures(structures)
        local found_valid = false
        for _, structure in pairs(structures) do
            local sx, sy, sk = normalize_structure(structure)
            if sx == 1 and sy == 1 and sk == "farm" then
                found_valid = true
            end
        end

        t.expect(total).to_equal(1)
        t.expect(found_valid).to_be_truthy()
    end)

    t.it("collect returns serializable structure entries", function()
        local SaveManager = require("core.save_manager")
        local terrain = require("idle_game.terrain")

        local grid = terrain.generate(2, 4, 4)
        grid:set(1, 1, terrain.GRASS)
        terrain.setCurrentGrid(grid)

        local ok, _ = pcall(require, "idle_game.terrain_persistence")
        t.expect(ok).to_be_truthy()
        if not ok then
            return
        end

        local collector = SaveManager.collectors["idle_structures"]
        t.expect(collector).to_be_truthy()

        terrain.place_structure(1, 1, "farm")

        local data = collector.collect()
        t.expect(type(data)).to_equal("table")

        local entries = 0
        for _, structure in pairs(data) do
            entries = entries + 1
            local sx, sy, sk = normalize_structure(structure)
            t.expect(type(sx)).to_equal("number")
            t.expect(type(sy)).to_equal("number")
            t.expect(type(sk)).to_equal("string")
        end

        t.expect(entries > 0).to_be_truthy()
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
