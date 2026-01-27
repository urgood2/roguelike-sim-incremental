package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local script_dir = arg[0]:match("(.*/)")
if not script_dir then script_dir = "./" end
package.path = script_dir .. "../external/?.lua;" .. script_dir .. "../external/?/init.lua;" .. package.path

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

print("Actual distribution:")
print(string.format("GRASS: %d (%.1f%%)", counts.GRASS, grassPct))
print(string.format("TREE:  %d (%.1f%%)", counts.TREE, treePct))
print(string.format("ROCK:  %d (%.1f%%)", counts.ROCK, rockPct))
print()
print("Target ranges:")
print("TREE:  15-25%")
print("ROCK:  5-15%")
print("GRASS: 60-80%")
