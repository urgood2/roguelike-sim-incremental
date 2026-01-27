package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local script_dir = arg[0]:match("(.*/)")
if not script_dir then script_dir = "./" end
package.path = script_dir .. "../external/?.lua;" .. script_dir .. "../external/?/init.lua;" .. package.path

local pattern_module = require("external.forma.pattern")
local primitives = require("external.forma.primitives")
local automata = require("external.forma.automata")
local neighbourhood = require("external.forma.neighbourhood")

math.randomseed(12345)

local domain = primitives.square(30, 20)

local target_cell_count = math.floor(30 * 20 * 0.40)
print("Target cells: " .. target_cell_count)

local pat = domain:sample(target_cell_count)

local initial_size = pat:size()
print("Initial pattern size: " .. initial_size)

local moore = neighbourhood.moore()

local rule = automata.rule(moore, "B5678/S45678")

local iterations = 0
local converged = false

while not converged and iterations < 100 do
    local before = pat:size()
    pat, converged = automata.iterate(pat, domain, {rule})
    local after = pat:size()
    iterations = iterations + 1
    if iterations <= 5 or iterations % 10 == 0 then
        print(string.format("Iter %2d: %3d → %3d cells, converged=%s", iterations, before, after, tostring(converged)))
    end
end

print("Final size: " .. pat:size())
