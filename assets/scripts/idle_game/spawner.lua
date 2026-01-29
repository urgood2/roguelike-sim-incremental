-- Spawner for forager creatures
local spawner = {}

local terrain = require("idle_game.terrain")
local config = require("idle_game.config")
local pattern_module = require("external.forma.pattern")
local cell = require("external.forma.cell")

-- Track living foragers
spawner._foragers = {}
spawner._forager_count = 0

-- Track corpses for rendering
spawner._corpses = {}

-- Deferred destruction queue (entities destroyed during AI updates)
spawner._pending_destroy = {}

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
        
        -- Set position at tile origin (top-left of tile, not center)
        -- This ensures grid-aligned rendering
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
        spawner._foragers[entity] = true
        spawner._forager_count = spawner._forager_count + 1
        log_debug(string.format("[SPAWNER] Spawned forager #%d at tile (%d, %d) -> pixel (%d, %d)", i, pos.x, pos.y, pos.x * config.TILE_SIZE, pos.y * config.TILE_SIZE))
    end

    log_debug(string.format("[SPAWNER] Successfully spawned %d foragers", #spawned))
    return spawned
end

--- Spawn a single forager at a specific pixel position (for reproduction)
--- @param x number Pixel X coordinate
--- @param y number Pixel Y coordinate
--- @return entity The spawned entity
function spawner.spawnForagerAt(x, y)
    local entity = create_ai_entity("forager")

    local transform = component_cache.get(entity, Transform)
    transform.actualX = x
    transform.actualY = y

    animation_system.setupAnimatedObjectOnEntity(
        entity,
        "d437_011_male.png",
        true,
        nil,
        false
    )

    animation_system.resizeAnimationObjectsInEntityToFit(
        entity,
        config.TILE_SIZE,
        config.TILE_SIZE
    )

    spawner._foragers[entity] = true
    spawner._forager_count = spawner._forager_count + 1

    log_debug(string.format("[SPAWNER] Birth: forager at (%.0f, %.0f), total=%d", x, y, spawner._forager_count))
    return entity
end

--- Get current forager count (updates by checking valid entities)
--- @return number Current number of living foragers
function spawner.getForagerCount()
    -- Clean up dead foragers and recount
    local count = 0
    for entity, _ in pairs(spawner._foragers) do
        if registry:valid(entity) then
            count = count + 1
        else
            spawner._foragers[entity] = nil
        end
    end
    spawner._forager_count = count
    return count
end

--- Get all living forager entities
--- @return table List of valid forager entities
function spawner.getForagers()
    local result = {}
    for entity, _ in pairs(spawner._foragers) do
        if registry:valid(entity) then
            table.insert(result, entity)
        else
            spawner._foragers[entity] = nil
        end
    end
    return result
end

--- Spawn a corpse at a position (gray on pink background)
--- @param x number Pixel X coordinate
--- @param y number Pixel Y coordinate
function spawner.spawnCorpseAt(x, y)
    table.insert(spawner._corpses, { x = x, y = y })
    log_debug(string.format("[SPAWNER] Corpse spawned at (%.0f, %.0f), total corpses=%d", x, y, #spawner._corpses))
end

--- Draw all corpses (called each frame from terrain renderer or scene)
function spawner.drawCorpses()
    if not command_buffer or not layers then return end

    local TILE_SIZE = config.TILE_SIZE
    local pinkColor = util.getColor("HOTPINK") or util.getColor("PINK")
    local grayColor = util.getColor("DARKGRAY") or util.getColor("GRAY")

    for _, corpse in ipairs(spawner._corpses) do
        -- Draw pink background square
        command_buffer.queueDrawSpriteTopLeft(
            layers.sprites,
            function(c)
                c.spriteName = config.SPRITE_GRASS  -- Use grass tile as base
                c.x = corpse.x
                c.y = corpse.y
                c.dstW = TILE_SIZE
                c.dstH = TILE_SIZE
                c.tint = pinkColor
            end,
            1,  -- z-order above terrain
            layer.DrawCommandSpace.World
        )

        -- Draw gray forager sprite on top
        command_buffer.queueDrawSpriteTopLeft(
            layers.sprites,
            function(c)
                c.spriteName = "d437_011_male.png"  -- Forager sprite
                c.x = corpse.x
                c.y = corpse.y
                c.dstW = TILE_SIZE
                c.dstH = TILE_SIZE
                c.tint = grayColor
            end,
            2,  -- z-order above pink background
            layer.DrawCommandSpace.World
        )
    end
end

--- Get corpse count
--- @return number Number of corpses
function spawner.getCorpseCount()
    return #spawner._corpses
end

--- Queue an entity for deferred destruction (safe to call during AI updates)
--- @param entity number Entity to destroy
function spawner.queueDestroy(entity)
    table.insert(spawner._pending_destroy, entity)
end

--- Process pending destructions (call from scene update, after AI tick completes)
function spawner.processPendingDestructions()
    for _, entity in ipairs(spawner._pending_destroy) do
        if registry:valid(entity) then
            registry:destroy(entity)
        end
        -- Also remove from forager tracking
        spawner._foragers[entity] = nil
    end
    spawner._pending_destroy = {}
end

return spawner
