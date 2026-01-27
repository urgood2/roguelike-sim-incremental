--[[
================================================================================
TEST: Idle Game Terrain Generator
================================================================================
Tests forma-based terrain generation with CA rules.

Run with: lua assets/scripts/tests/test_idle_terrain.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Setup forma path (MUST be done before any forma modules are required)
local script_dir = arg[0]:match("(.*/)")
if not script_dir then script_dir = "./" end
package.path = script_dir .. "../external/?.lua;" .. script_dir .. "../external/?/init.lua;" .. package.path

-- Standard test path setup  
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached module if re-running
package.loaded["idle_game.terrain"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Terrain Generator - Basic Functionality", function()
    
    t.it("generates a grid of correct size", function()
        local terrain = require("idle_game.terrain")
        local grid = terrain.generate(12345, 30, 20)
        
        t.expect(grid).to_be_truthy()
        t.expect(grid.width).to_equal(30)
        t.expect(grid.height).to_equal(20)
    end)
    
    t.it("produces identical grids for same seed", function()
        local terrain = require("idle_game.terrain")
        local grid1 = terrain.generate(12345, 30, 20)
        local grid2 = terrain.generate(12345, 30, 20)
        
        -- Count tiles in each grid
        local count1 = {GRASS=0, TREE=0, ROCK=0}
        local count2 = {GRASS=0, TREE=0, ROCK=0}
        
        for y = 0, 19 do
            for x = 0, 29 do
                local tile1 = grid1:get(x, y)
                local tile2 = grid2:get(x, y)
                count1[tile1] = count1[tile1] + 1
                count2[tile2] = count2[tile2] + 1
            end
        end
        
        t.expect(count1.GRASS).to_equal(count2.GRASS)
        t.expect(count1.TREE).to_equal(count2.TREE)
        t.expect(count1.ROCK).to_equal(count2.ROCK)
    end)
    
    t.it("contains only valid tile types", function()
        local terrain = require("idle_game.terrain")
        local grid = terrain.generate(12345, 30, 20)
        
        local validTypes = {GRASS=true, TREE=true, ROCK=true}
        
        for y = 0, 19 do
            for x = 0, 29 do
                local tile = grid:get(x, y)
                t.expect(validTypes[tile]).to_be_truthy()
            end
        end
    end)
    
    t.it("has reasonable tile distribution", function()
        local terrain = require("idle_game.terrain")
        local grid = terrain.generate(12345, 30, 20)
        
        local counts = {GRASS=0, TREE=0, ROCK=0}
        local total = 30 * 20
        
        for y = 0, 19 do
            for x = 0, 29 do
                local tile = grid:get(x, y)
                counts[tile] = counts[tile] + 1
            end
        end
        
        local grassPct = (counts.GRASS / total) * 100
        local treePct = (counts.TREE / total) * 100
        local rockPct = (counts.ROCK / total) * 100
        
        -- Trees: 15-25%
        t.expect(treePct >= 15 and treePct <= 25).to_be_truthy()
        -- Rocks: 5-15%
        t.expect(rockPct >= 5 and rockPct <= 15).to_be_truthy()
        -- Grass: 60-80%
        t.expect(grassPct >= 60 and grassPct <= 80).to_be_truthy()
    end)
    
    t.it("generates in under 100ms", function()
        local terrain = require("idle_game.terrain")
        
        local start = os.clock()
        local grid = terrain.generate(12345, 30, 20)
        local elapsed = (os.clock() - start) * 1000  -- ms
        
        t.expect(elapsed < 100).to_be_truthy()
    end)
    
end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
