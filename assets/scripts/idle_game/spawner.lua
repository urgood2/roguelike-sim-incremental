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
    log_debug(string.format("[SPAWNER] Spawning %d foragers...", count))
    
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
        grass_pattern:insert(pos.x, pos.y)
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
        -- Create GOAP entity of type "forager"
        -- This creates entity with Transform and GOAPComponent already configured
        local entity = create_ai_entity("forager")
        
        -- Set position (convert tile coords to world coords)
        local transform = component_cache.get(entity, Transform)
        transform.actualX = pos.x * config.TILE_SIZE
        transform.actualY = pos.y * config.TILE_SIZE
        
        -- Set up visual using animation system with a static sprite
        animation_system.setupAnimatedObjectOnEntity(
            entity,
            "d437_011_male.png",
            true,
            nil,
            false
        )
        
        -- Resize to fit tile size
        animation_system.resizeAnimationObjectsInEntityToFit(
            entity,
            config.TILE_SIZE,
            config.TILE_SIZE
        )
        
        table.insert(spawned, entity)
        log_debug(string.format("[SPAWNER] Spawned forager #%d at tile (%d, %d) -> pixel (%d, %d)", i, pos.x, pos.y, pos.x * config.TILE_SIZE, pos.y * config.TILE_SIZE))
    end
    
    log_debug(string.format("[SPAWNER] Successfully spawned %d foragers", #spawned))
    return spawned
end

return spawner
