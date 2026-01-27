-- Spawner for forager creatures
local spawner = {}

local terrain = require("idle_game.terrain")
local config = require("idle_game.config")
local pattern_module = require("external.forma.pattern")
local cell = require("external.forma.cell")

--- Spawns forager creatures on grass tiles using Poisson-disc sampling
--- @param count number Number of creatures to spawn
--- @return table List of spawned entity IDs
function spawner.spawnForagers(count)
    print(string.format("Spawning %d foragers...", count))
    
    -- Build list of all grass tile coordinates
    local grass_cells = {}
    for y = 0, config.GRID_HEIGHT - 1 do
        for x = 0, config.GRID_WIDTH - 1 do
            if terrain.get(x, y) == terrain.GRASS then
                table.insert(grass_cells, {x = x, y = y})
            end
        end
    end
    
    print(string.format("Found %d grass tiles", #grass_cells))
    
    if #grass_cells < count then
        print(string.format("WARNING: Only %d grass tiles available for %d creatures", #grass_cells, count))
    end
    
    -- Convert grass cells to forma pattern
    local grass_pattern = pattern_module.new()
    for _, pos in ipairs(grass_cells) do
        grass_pattern:add(pos.x, pos.y)
    end
    
    -- Sample using Poisson-disc distribution
    -- distance = 3 tiles minimum separation, radius = 10 search radius
    local spawn_positions = grass_pattern:sample_poisson(cell.euclidean, 3, math.random)
    
    -- Convert pattern to list and limit to requested count
    local positions = {}
    for pos_cell in spawn_positions:cells() do
        table.insert(positions, {x = pos_cell.x, y = pos_cell.y})
        if #positions >= count then
            break
        end
    end
    
    print(string.format("Poisson sampling generated %d positions", #positions))
    
    -- Spawn entities
    local spawned = {}
    for i, pos in ipairs(positions) do
        -- Create entity with Transform and Sprite
        local entity = registry:create()
        
        -- Set position (convert tile coords to world coords)
        local transform = registry:emplace(entity, Transform)
        transform.actualX = pos.x * config.TILE_SIZE
        transform.actualY = pos.y * config.TILE_SIZE
        transform.actualW = config.TILE_SIZE
        transform.actualH = config.TILE_SIZE
        
        -- Add sprite component (using '@' ASCII character for forager)
        local sprite = registry:emplace(entity, Sprite)
        sprite.sprite_id = "011_d437_male"
        sprite.visible = true
        
        -- Create GOAP entity of type "forager"
        -- This attaches GOAPComponent and initializes worldstate from ai/entity_types/forager.lua
        local ai_entity = ai:create_ai_entity("forager", {})
        
        -- Copy GOAP component from ai_entity to our entity
        -- (ai:create_ai_entity creates a new entity, we need to transfer the component)
        if component_cache.has(ai_entity, GOAPComponent) then
            local goap = component_cache.get(ai_entity, GOAPComponent)
            registry:emplace(entity, GOAPComponent, goap)
            registry:destroy(ai_entity)  -- Clean up temporary entity
        end
        
        table.insert(spawned, entity)
        print(string.format("Spawned forager #%d at tile (%d, %d)", i, pos.x, pos.y))
    end
    
    print(string.format("Successfully spawned %d foragers", #spawned))
    return spawned
end

return spawner
