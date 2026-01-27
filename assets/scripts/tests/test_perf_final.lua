package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local script_dir = arg[0]:match("(.*/)")
if not script_dir then script_dir = "./" end
package.path = script_dir .. "../external/?.lua;" .. script_dir .. "../external/?/init.lua;" .. package.path

local terrain = require("idle_game.terrain")

-- Measure performance
local start = os.clock()
local grid = terrain.generate(12345, 30, 20)
local elapsed = (os.clock() - start) * 1000

-- Count distribution
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

print(string.format("Performance: %.2fms", elapsed))
print(string.format("GRASS: %.1f%%, TREE: %.1f%%, ROCK: %.1f%%", grassPct, treePct, rockPct))
