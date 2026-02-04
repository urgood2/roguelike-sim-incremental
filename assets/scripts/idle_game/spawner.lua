-- Spawner for forager creatures
local spawner = {}

local terrain = require("idle_game.terrain")
local config = require("idle_game.config")
local pattern_module = require("external.forma.pattern")
local cell = require("external.forma.cell")

-- Track living foragers
spawner._foragers = {}
spawner._forager_count = 0

-- Track living lumberjacks
spawner._lumberjacks = {}
spawner._lumberjack_count = 0

-- Track living collectors
spawner._collectors = {}
spawner._collector_count = 0

-- Track living miners
spawner._miners = {}
spawner._miner_count = 0

-- Track living builders
spawner._builders = {}
spawner._builder_count = 0

-- Track corpses for rendering
spawner._corpses = {}

-- Deferred destruction queue (entities destroyed during AI updates)
spawner._pending_destroy = {}

-- Flag to prevent re-entrant signal emissions
spawner._emitting_signal = false

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

    -- Emit creature counts signal after spawning
    spawner._emitCreatureCounts()

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

    -- Emit creature counts signal after spawning
    spawner._emitCreatureCounts()

    return entity
end

--- Get current forager count (updates by checking valid entities)
--- @return number Current number of living foragers
function spawner.getForagerCount()
    -- Clean up dead foragers and recount
    local count = 0
    local cleaned_any = false
    for entity, _ in pairs(spawner._foragers) do
        if registry:valid(entity) then
            count = count + 1
        else
            spawner._foragers[entity] = nil
            cleaned_any = true
        end
    end
    spawner._forager_count = count

    -- Emit creature counts signal after maintenance cleanup
    if cleaned_any then
        spawner._emitCreatureCounts()
    end

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

--- Spawns lumberjack creatures on grass tiles using Poisson-disc sampling
--- @param count number Number of lumberjacks to spawn
--- @return table List of spawned entity IDs
function spawner.spawnLumberjacks(count)
    log_debug(string.format("[SPAWNER] Spawning %d lumberjacks...", count))

    -- Build list of all grass tile coordinates
    local grass_cells = {}
    for y = 0, config.GRID_HEIGHT - 1 do
        for x = 0, config.GRID_WIDTH - 1 do
            if terrain.get(x, y) == terrain.GRASS then
                table.insert(grass_cells, {x = x, y = y})
            end
        end
    end

    if #grass_cells < count then
        print(string.format("WARNING: Only %d grass tiles available for %d lumberjacks", #grass_cells, count))
    end

    -- Convert grass cells to forma pattern
    local grass_pattern = pattern_module.new()
    for _, pos in ipairs(grass_cells) do
        grass_pattern:insert(pos.x, pos.y)
    end

    -- Sample using Poisson-disc distribution
    local spawn_positions = grass_pattern:sample_poisson(cell.euclidean, 3, math.random)

    if #spawn_positions > count then
        -- Shuffle and trim to exact count
        for i = #spawn_positions, 2, -1 do
            local j = math.random(i)
            spawn_positions[i], spawn_positions[j] = spawn_positions[j], spawn_positions[i]
        end
        for i = #spawn_positions, count + 1, -1 do
            spawn_positions[i] = nil
        end
    end

    local spawned = {}
    for _, pos in ipairs(spawn_positions) do
        local entity = spawner.spawnLumberjackAt(pos.x * config.TILE_SIZE, pos.y * config.TILE_SIZE)
        table.insert(spawned, entity)
    end

    -- Emit creature counts signal after spawning
    spawner._emitCreatureCounts()

    return spawned
end

--- Spawns a single lumberjack at specific world coordinates
--- @param x number World X position (pixels)
--- @param y number World Y position (pixels)
--- @return Entity Spawned lumberjack entity ID
function spawner.spawnLumberjackAt(x, y)
    local entity = ai.create_ai_entity("lumberjack")
    spawner._lumberjacks[entity] = true
    spawner._lumberjack_count = spawner._lumberjack_count + 1

    -- Set world position
    if registry:has(entity, Transform) then
        local transform = registry:get(entity, Transform)
        transform.actualX = x
        transform.actualY = y
    end

    log_debug(string.format("[SPAWNER] Lumberjack spawned at (%.0f, %.0f), total=%d",
        x, y, spawner._lumberjack_count))

    -- Emit creature counts signal after spawning
    spawner._emitCreatureCounts()

    return entity
end

--- Get count of living lumberjacks (with cleanup)
--- @return number Valid lumberjack count
function spawner.getLumberjackCount()
    local count = 0
    local cleaned_any = false
    for entity, _ in pairs(spawner._lumberjacks) do
        if registry:valid(entity) then
            count = count + 1
        else
            spawner._lumberjacks[entity] = nil
            spawner._lumberjack_count = spawner._lumberjack_count - 1
            cleaned_any = true
        end
    end

    -- Emit creature counts signal after maintenance cleanup
    if cleaned_any then
        spawner._emitCreatureCounts()
    end

    return count
end

--- Get count of living collectors (with cleanup)
--- @return number Valid collector count
function spawner.getCollectorCount()
    local count = 0
    local cleaned_any = false
    for entity, _ in pairs(spawner._collectors) do
        if registry:valid(entity) then
            count = count + 1
        else
            spawner._collectors[entity] = nil
            spawner._collector_count = spawner._collector_count - 1
            cleaned_any = true
        end
    end

    -- Emit creature counts signal after maintenance cleanup
    if cleaned_any then
        spawner._emitCreatureCounts()
    end

    return count
end

--- Spawns collector creatures on grass tiles using Poisson-disc sampling
--- @param count number Number of creatures to spawn
--- @return table List of spawned entity IDs
function spawner.spawnCollectors(count)
    log_debug(string.format("[SPAWNER] Spawning %d collectors...", count))

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
        -- Create GOAP entity of type "collector"
        -- This creates entity with Transform and GOAPComponent already configured
        local entity = create_ai_entity("collector")

        -- Set position at tile origin (top-left of tile, not center)
        -- This ensures grid-aligned rendering
        local transform = component_cache.get(entity, Transform)
        transform.actualX = pos.x * config.TILE_SIZE
        transform.actualY = pos.y * config.TILE_SIZE

        -- Set up visual using animation system with a static sprite
        -- Use female sprite to distinguish collectors from foragers
        animation_system.setupAnimatedObjectOnEntity(
            entity,
            "d437_012_female.png",
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
        spawner._collectors[entity] = true
        spawner._collector_count = spawner._collector_count + 1
        log_debug(string.format("[SPAWNER] Spawned collector #%d at tile (%d, %d) -> pixel (%d, %d)", i, pos.x, pos.y, pos.x * config.TILE_SIZE, pos.y * config.TILE_SIZE))
    end

    log_debug(string.format("[SPAWNER] Successfully spawned %d collectors", #spawned))

    -- Emit creature counts signal after spawning
    spawner._emitCreatureCounts()

    return spawned
end

--- Spawn a single collector at a specific pixel position (for reproduction)
--- @param x number Pixel X coordinate
--- @param y number Pixel Y coordinate
--- @return entity The spawned entity
function spawner.spawnCollectorAt(x, y)
    local entity = create_ai_entity("collector")

    local transform = component_cache.get(entity, Transform)
    transform.actualX = x
    transform.actualY = y

    animation_system.setupAnimatedObjectOnEntity(
        entity,
        "d437_012_female.png",
        true,
        nil,
        false
    )

    animation_system.resizeAnimationObjectsInEntityToFit(
        entity,
        config.TILE_SIZE,
        config.TILE_SIZE
    )

    spawner._collectors[entity] = true
    spawner._collector_count = spawner._collector_count + 1

    log_debug(string.format("[SPAWNER] Birth: collector at (%.0f, %.0f), total=%d", x, y, spawner._collector_count))

    -- Emit creature counts signal after spawning
    spawner._emitCreatureCounts()

    return entity
end

--- Spawns miner creatures on grass tiles using Poisson-disc sampling
--- @param count number Number of miners to spawn
--- @return table List of spawned entity IDs
function spawner.spawnMiners(count)
    log_debug(string.format("[SPAWNER] Spawning %d miners...", count))

    -- Build list of all grass tile coordinates
    local grass_cells = {}
    for y = 0, config.GRID_HEIGHT - 1 do
        for x = 0, config.GRID_WIDTH - 1 do
            if terrain.get(x, y) == terrain.GRASS then
                table.insert(grass_cells, {x = x, y = y})
            end
        end
    end

    if #grass_cells < count then
        print(string.format("WARNING: Only %d grass tiles available for %d miners", #grass_cells, count))
    end

    -- Convert grass cells to forma pattern
    local grass_pattern = pattern_module.new()
    for _, pos in ipairs(grass_cells) do
        grass_pattern:insert(pos.x, pos.y)
    end

    -- Sample using Poisson-disc distribution
    local spawn_positions = grass_pattern:sample_poisson(cell.euclidean, 3, math.random)

    -- Convert pattern to list and limit to requested count
    local positions = {}
    for pos_cell in spawn_positions:cells() do
        table.insert(positions, {x = pos_cell.x, y = pos_cell.y})
        if #positions >= count then
            break
        end
    end

    local spawned = {}
    for _, pos in ipairs(positions) do
        local entity = spawner.spawnMinerAt(pos.x * config.TILE_SIZE, pos.y * config.TILE_SIZE)
        table.insert(spawned, entity)
    end

    -- Emit creature counts signal after spawning
    spawner._emitCreatureCounts()

    return spawned
end

--- Spawns a single miner at specific world coordinates
--- @param x number World X position (pixels)
--- @param y number World Y position (pixels)
--- @return Entity Spawned miner entity ID
function spawner.spawnMinerAt(x, y)
    local entity = ai.create_ai_entity("miner")
    spawner._miners[entity] = true
    spawner._miner_count = spawner._miner_count + 1

    -- Set world position
    if registry:has(entity, Transform) then
        local transform = registry:get(entity, Transform)
        transform.actualX = x
        transform.actualY = y
    end

    log_debug(string.format("[SPAWNER] Miner spawned at (%.0f, %.0f), total=%d",
        x, y, spawner._miner_count))

    -- Emit creature counts signal after spawning
    spawner._emitCreatureCounts()

    return entity
end

--- Get count of living miners (with cleanup)
--- @return number Valid miner count
function spawner.getMinerCount()
    local count = 0
    local cleaned_any = false
    for entity, _ in pairs(spawner._miners) do
        if registry:valid(entity) then
            count = count + 1
        else
            spawner._miners[entity] = nil
            spawner._miner_count = spawner._miner_count - 1
            cleaned_any = true
        end
    end

    -- Emit creature counts signal after maintenance cleanup
    if cleaned_any then
        spawner._emitCreatureCounts()
    end

    return count
end

--- Get all living miner entities
--- @return table List of valid miner entities
function spawner.getMiners()
    local result = {}
    for entity, _ in pairs(spawner._miners) do
        if registry:valid(entity) then
            table.insert(result, entity)
        else
            spawner._miners[entity] = nil
        end
    end
    return result
end

--- Spawns builder creatures on grass tiles using Poisson-disc sampling
--- @param count number Number of builders to spawn
--- @return table List of spawned entity IDs
function spawner.spawnBuilders(count)
    log_debug(string.format("[SPAWNER] Spawning %d builders...", count))

    -- Build list of all grass tile coordinates
    local grass_cells = {}
    for y = 0, config.GRID_HEIGHT - 1 do
        for x = 0, config.GRID_WIDTH - 1 do
            if terrain.get(x, y) == terrain.GRASS then
                table.insert(grass_cells, {x = x, y = y})
            end
        end
    end

    if #grass_cells < count then
        print(string.format("WARNING: Only %d grass tiles available for %d builders", #grass_cells, count))
    end

    -- Convert grass cells to forma pattern
    local grass_pattern = pattern_module.new()
    for _, pos in ipairs(grass_cells) do
        grass_pattern:insert(pos.x, pos.y)
    end

    -- Sample using Poisson-disc distribution
    local spawn_positions = grass_pattern:sample_poisson(cell.euclidean, 3, math.random)

    if #spawn_positions > count then
        -- Shuffle and trim to exact count
        for i = #spawn_positions, 2, -1 do
            local j = math.random(i)
            spawn_positions[i], spawn_positions[j] = spawn_positions[j], spawn_positions[i]
        end
        for i = #spawn_positions, count + 1, -1 do
            spawn_positions[i] = nil
        end
    end

    local spawned = {}
    for _, pos in ipairs(spawn_positions) do
        local entity = spawner.spawnBuilderAt(pos.x * config.TILE_SIZE, pos.y * config.TILE_SIZE)
        table.insert(spawned, entity)
    end

    -- Emit creature counts signal after spawning
    spawner._emitCreatureCounts()

    return spawned
end

--- Spawns a single builder at specific world coordinates
--- @param x number World X position (pixels)
--- @param y number World Y position (pixels)
--- @return Entity Spawned builder entity ID
function spawner.spawnBuilderAt(x, y)
    local entity = ai.create_ai_entity("builder")
    spawner._builders[entity] = true
    spawner._builder_count = spawner._builder_count + 1

    -- Set world position
    if registry:has(entity, Transform) then
        local transform = registry:get(entity, Transform)
        transform.actualX = x
        transform.actualY = y
    end

    log_debug(string.format("[SPAWNER] Builder spawned at (%.0f, %.0f), total=%d",
        x, y, spawner._builder_count))

    -- Emit creature counts signal after spawning
    spawner._emitCreatureCounts()

    return entity
end

--- Get count of living builders (with cleanup)
--- @return number Valid builder count
function spawner.getBuilderCount()
    local count = 0
    local cleaned_any = false
    for entity, _ in pairs(spawner._builders) do
        if registry:valid(entity) then
            count = count + 1
        else
            spawner._builders[entity] = nil
            spawner._builder_count = spawner._builder_count - 1
            cleaned_any = true
        end
    end

    -- Emit creature counts signal after maintenance cleanup
    if cleaned_any then
        spawner._emitCreatureCounts()
    end

    return count
end

--- Get all living builder entities
--- @return table List of valid builder entities
function spawner.getBuilders()
    local result = {}
    for entity, _ in pairs(spawner._builders) do
        if registry:valid(entity) then
            table.insert(result, entity)
        else
            spawner._builders[entity] = nil
        end
    end
    return result
end

--- Get count of specialist creatures (miners + lumberjacks + collectors + builders)
--- @return number Total specialist count
function spawner.getSpecialistCount()
    local miners = spawner.getMinerCount and spawner.getMinerCount() or 0
    local lumberjacks = spawner.getLumberjackCount and spawner.getLumberjackCount() or 0
    local collectors = spawner.getCollectorCount and spawner.getCollectorCount() or 0
    local builders = spawner.getBuilderCount and spawner.getBuilderCount() or 0
    return miners + lumberjacks + collectors + builders
end

--- Get all living lumberjack entities
--- @return table List of valid lumberjack entities
function spawner.getLumberjacks()
    local result = {}
    for entity, _ in pairs(spawner._lumberjacks) do
        if registry:valid(entity) then
            table.insert(result, entity)
        else
            spawner._lumberjacks[entity] = nil
        end
    end
    return result
end

--- Get all living collector entities
--- @return table List of valid collector entities
function spawner.getCollectors()
    local result = {}
    for entity, _ in pairs(spawner._collectors) do
        if registry:valid(entity) then
            table.insert(result, entity)
        else
            spawner._collectors[entity] = nil
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
            2,  -- Layer 2: Corpses (after structures on layer 1)
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
            2,  -- Layer 2: Corpses (with pink background)
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
    local destroyed_any = false
    for _, entity in ipairs(spawner._pending_destroy) do
        if registry:valid(entity) then
            registry:destroy(entity)
            destroyed_any = true
        end
        -- Also remove from all tracking tables
        spawner._foragers[entity] = nil
        spawner._lumberjacks[entity] = nil
        spawner._collectors[entity] = nil
        spawner._miners[entity] = nil
        spawner._builders[entity] = nil
    end
    spawner._pending_destroy = {}

    -- Emit creature counts signal after destruction maintenance
    if destroyed_any then
        spawner._emitCreatureCounts()
    end
end

--- Get total count of all specialist workers (miners + lumberjacks + collectors + builders)
--- @return number Total specialist count
function spawner.getSpecialistCount()
    local total = 0

    -- Lumberjacks (implemented)
    total = total + spawner.getLumberjackCount()

    -- Miners (implemented)
    total = total + spawner.getMinerCount()

    -- Collectors (treating foragers as collectors for now)
    total = total + spawner.getForagerCount()

    -- Builders (implemented)
    total = total + spawner.getBuilderCount()

    log_debug(string.format("[SPAWNER] Total specialists: %d (lumberjacks + miners + foragers + builders)", total))
    return total
end

--- Get total count of all living creatures (all types combined)
--- @return number Total creature count across all types
function spawner.getTotalCreatureCount()
    local total = 0

    -- Sum all creature types
    total = total + spawner.getForagerCount()
    total = total + spawner.getLumberjackCount()
    total = total + spawner.getCollectorCount()
    total = total + spawner.getMinerCount()
    total = total + spawner.getBuilderCount()

    log_debug(string.format("[SPAWNER] Total creatures: %d (foragers + lumberjacks + collectors + miners + builders)", total))
    return total
end

--- Internal helper to emit creature counts signal
--- Called after spawn/despawn maintenance operations
function spawner._emitCreatureCounts()
    -- Prevent re-entrant calls
    if spawner._emitting_signal then
        return
    end

    local signals = require("idle_game.signals")
    if signals and signals.emit then
        spawner._emitting_signal = true

        -- Get current counts (these may trigger cleanup, but won't re-emit due to flag)
        local counts = {
            foragers = spawner.getForagerCount(),
            lumberjacks = spawner.getLumberjackCount(),
            collectors = spawner.getCollectorCount(),
            miners = spawner.getMinerCount(),
            builders = spawner.getBuilderCount(),
            corpses = spawner.getCorpseCount()
        }

        signals.emit("idle.creature_counts", counts)
        log_debug(string.format("[SPAWNER] Emitted creature_counts signal: foragers=%d, lumberjacks=%d, collectors=%d, miners=%d, builders=%d, corpses=%d",
            counts.foragers, counts.lumberjacks, counts.collectors, counts.miners, counts.builders, counts.corpses))

        spawner._emitting_signal = false
    end
end

return spawner
