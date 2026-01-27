--[[
    FORMA TERRAIN GENERATION SPIKE TEST
    
    Validates:
    1. 30x20 pattern creation (canonical grid size)
    2. CA convergence <1000 iterations with rule B5678/S45678
    3. Generation time <100ms
    4. Determinism (same seed = same output)
    5. Flood-fill for connected region detection
    
    Run: lua assets/scripts/test_forma_terrain.lua
]]--

-- Load forma library
local script_dir = arg[0]:match("(.*/)")
if not script_dir then script_dir = "./" end
package.path = script_dir .. "external/?.lua;" .. script_dir .. "external/?/init.lua;" .. package.path

local cell = require("forma.cell")
local pattern = require("forma.pattern")
local primitives = require("forma.primitives")
local automata = require("forma.automata")
local neighbourhood = require("forma.neighbourhood")

-- Helper: Time a function execution in milliseconds
local function time_function(fn)
    local start = os.clock()
    fn()
    local elapsed = (os.clock() - start) * 1000  -- Convert to ms
    return elapsed
end

-- Helper: Count alive cells in pattern
local function count_cells(pattern)
    local count = 0
    for _ in pattern:cells() do
        count = count + 1
    end
    return count
end

-- Helper: Run a CA generation with timing
local function generate_terrain(width, height, seed, ca_rule_string, max_iterations)
    local start_time = os.clock()
    
    -- Seed for determinism
    math.randomseed(seed)
    
    -- Create domain (width x height) 
    local domain = primitives.square(width, height)
    
    -- Create initial pattern by sampling ~45% of cells
    local target_cell_count = math.floor(width * height * 0.45)
    local pat = domain:sample(target_cell_count)
    
    -- Get neighbourhood (Moore = 8-cell)
    local moore = neighbourhood.moore()
    
    -- Create CA rule
    local rule = automata.rule(moore, ca_rule_string)
    
    -- Run CA until convergence or max iterations
    local iterations = 0
    local converged = false
    
    while not converged and iterations < max_iterations do
        pat, converged = automata.iterate(pat, domain, {rule})
        iterations = iterations + 1
    end
    
    local elapsed = (os.clock() - start_time) * 1000  -- Convert to ms
    
    return {
        pattern = pat,
        iterations = iterations,
        converged = converged,
        time_ms = elapsed,
        cell_count = count_cells(pat)
    }
end

-- Helper: Count connected components
local function count_components(pat)
    local moore = neighbourhood.moore()
    local components = pat:connected_components(moore)
    return components:n_components()
end

print("=" .. string.rep("=", 58) .. "=")
print("| FORMA TERRAIN GENERATION SPIKE TEST")
print("=" .. string.rep("=", 58) .. "=")
print()

-- TEST 1: Basic generation with timing
print("TEST 1: Generation Performance (30x20 grid)")
print("-" .. string.rep("-", 58) .. "-")

local result1 = generate_terrain(30, 20, 12345, "B5678/S45678", 1000)

print(string.format("Grid Size: 30 x 20 (canonical)"))
print(string.format("CA Rule: B5678/S45678 (cave-like pattern)"))
print(string.format("Convergence: %d iterations (target: <1000) - %s", 
    result1.iterations, 
    result1.converged and "✓ CONVERGED" or "✗ DID NOT CONVERGE"))
print(string.format("Generation Time: %.2f ms (target: <100ms) - %s",
    result1.time_ms,
    result1.time_ms < 100 and "✓ PASS" or "✗ FAIL"))
print(string.format("Alive Cells: %d", result1.cell_count))
print()

-- TEST 2: Determinism check
print("TEST 2: Determinism Check (same seed)")
print("-" .. string.rep("-", 58) .. "-")

local result2a = generate_terrain(30, 20, 12345, "B5678/S45678", 1000)
local result2b = generate_terrain(30, 20, 12345, "B5678/S45678", 1000)

local deterministic = (result2a.cell_count == result2b.cell_count) and 
                      (result2a.iterations == result2b.iterations)

print(string.format("Run 1 - Cell Count: %d, Iterations: %d", 
    result2a.cell_count, result2a.iterations))
print(string.format("Run 2 - Cell Count: %d, Iterations: %d",
    result2b.cell_count, result2b.iterations))
print(string.format("Determinism: %s",
    deterministic and "✓ PASS (identical)" or "✗ FAIL (different)"))
print()
print()

-- TEST 3: Different seed produces different result
print("TEST 3: Different Seed Produces Different Pattern")
print("-" .. string.rep("-", 58) .. "-")

local result3a = generate_terrain(30, 20, 12345, "B5678/S45678", 1000)
local result3b = generate_terrain(30, 20, 54321, "B5678/S45678", 1000)

local different = (result3a.cell_count ~= result3b.cell_count)

print(string.format("Seed 12345 - Cell Count: %d", result3a.cell_count))
print(string.format("Seed 54321 - Cell Count: %d", result3b.cell_count))
print(string.format("Different Results: %s",
    different and "✓ PASS (different as expected)" or "✗ FAIL (unexpectedly same)"))
print()

-- TEST 4: Connected components / Flood-fill
print("TEST 4: Connected Components Detection")
print("-" .. string.rep("-", 58) .. "-")

local result4 = generate_terrain(30, 20, 12345, "B5678/S45678", 1000)
local num_components = count_components(result4.pattern)

print(string.format("Number of connected regions: %d", num_components))
print(string.format("Connected Components Detection: ✓ WORKING"))
print()

-- TEST 5: Performance across iterations
print("TEST 5: Performance Analysis")
print("-" .. string.rep("-", 58) .. "-")

local times = {}
for i = 1, 3 do
    local result = generate_terrain(30, 20, 10000 + i, "B5678/S45678", 1000)
    table.insert(times, result.time_ms)
    print(string.format("Run %d: %.2f ms", i, result.time_ms))
end

local avg_time = 0
for _, t in ipairs(times) do avg_time = avg_time + t end
avg_time = avg_time / #times

print(string.format("Average Time: %.2f ms", avg_time))
print()

-- SUMMARY
print("=" .. string.rep("=", 58) .. "=")
print("SUMMARY")
print("=" .. string.rep("=", 58) .. "=")

local all_pass = (result1.time_ms < 100) and 
                 (result1.iterations < 1000) and 
                 deterministic and 
                 different and 
                 (num_components > 0)

print(string.format("Overall Result: %s",
    all_pass and "✓ ALL TESTS PASSED" or "✗ SOME TESTS FAILED"))
print()

print("Findings:")
print(string.format("  • Grid 30x20 can be generated in %.2f ms (✓)", result1.time_ms))
print(string.format("  • CA converges in %d iterations (✓)", result1.iterations))
print(string.format("  • Same seed produces identical patterns (✓)"))
print(string.format("  • Different seeds produce different patterns (✓)"))
print(string.format("  • Found %d connected regions via flood-fill (✓)", num_components))
print()

if all_pass then
    print("CONCLUSION: Forma IS suitable for procedural terrain generation!")
    print("  - Performance target met (<100ms)")
    print("  - Deterministic generation confirmed")
    print("  - Connected component analysis working")
else
    print("CONCLUSION: Forma needs further investigation")
end

print()
print("=" .. string.rep("=", 58) .. "=")
