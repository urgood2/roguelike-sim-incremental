-- These will run every frame per ai entity.
local config = require("idle_game.config")

return {
    -- Reset wander state so foragers continuously wander
    wander_reset = function(entity, dt)
        if not registry:valid(entity) then return end
        -- Only reset if wander is currently true (just completed wandering)
        if ai.get_worldstate(entity, "wander") == true then
            ai.set_worldstate(entity, "wander", false)
        end
    end,

    hunger_check = function(entity, dt)
        if not registry:valid(entity) then return end
        -- TODO: Implement hunger check logic
        local ok, bb = pcall(ai.get_blackboard, entity)
        if not ok or not bb then return end
        local has_hunger, contains = pcall(function() return bb:contains("hunger") end)
        if not has_hunger or not contains then
            return
        end
        local hunger = bb:get_float("hunger")
        bb:set_float("hunger", hunger - dt * 0.01) -- decrement hunger over time
        log_debug("hunger_check: Hunger level for entity " .. tostring(entity) .. ": " .. tostring(hunger))
        
        if hunger < 0 then
            hunger = 0 -- ensure hunger does not go below 0
        end
        
        if hunger < 0.3 then
            ai.set_worldstate(entity, "hungry", hunger < 0.3) -- set world state based on hunger level
            
            -- check if worldstate has been set correctly
            if ai.get_worldstate(entity, "hungry") then
                log_debug("hunger_check: Entity " .. tostring(entity) .. " is set to hungry.")
            else
                log_error("hunger_check: Entity " .. tostring(entity) .. " is not set to hungry.")
            end
            
            log_debug("Entity " .. tostring(entity) .. " is hungry.")
        end
        
        
        -- bb.hunger = bb.hunger + dt * 0.01
        -- ai.set_worldstate(entity, "hungry", bb.hunger > 0.7)
    end,

    enemy_sight = function(entity, dt)
        if not registry:valid(entity) then return end
        -- TODO: Implement enemy sight check logic
        -- local visible = check_if_enemy_visible(entity)
        -- ai.set_worldstate(entity, "enemyvisible", visible)
        -- local bb = get_blackboard(entity)
        -- bb.enemy_visible = visible
    end,
    
    can_heal_other = function(entity, dt)
        if not registry:valid(entity) then return end
        -- when's the last time the healer healed?
        if (blackboardContains(entity, "last_heal_time") == false) then
            return
        end
        local heal_time = getBlackboardFloat(entity, "last_heal_time")
        local heal_cooldown = findInTable(globals.creature_defs, "id", "healer").heal_cooldown_seconds or 10 -- default to 10 seconds if not found
        if (GetTime() - heal_time) < heal_cooldown then
            -- if the last heal time is less than 10 seconds ago, then we cannot heal
            ai.set_worldstate(entity, "canhealother", false)
            log_debug("can_heal_other: Entity " .. tostring(entity) .. " cannot heal yet.")
        else
            ai.set_worldstate(entity, "canhealother", true)
            log_debug("can_heal_other: Entity " .. tostring(entity) .. " can heal now.")
        end
    end,
    
    can_dig_for_gold = function(entity, dt)
        if not registry:valid(entity) then return end
        -- when's the last time the gold digger dug for gold?
        if (blackboardContains(entity, "last_dig_time") == false) then
            return
        end
        local dig_time =  getBlackboardFloat(entity, "last_dig_time")
        local dig_cooldown = findInTable(globals.creature_defs, "id", "gold_digger").dig_cooldown_seconds or 10 -- default to 10 seconds if not found
        if (GetTime() - dig_time) < dig_cooldown then
            -- if the last dig time is less than 5 seconds ago, then we cannot dig for gold
            ai.set_worldstate(entity, "candigforgold", false)
            log_debug("can_dig_for_gold: Entity " .. tostring(entity) .. " cannot dig for gold yet.")
        else
            ai.set_worldstate(entity, "candigforgold", true)
            log_debug("can_dig_for_gold: Entity " .. tostring(entity) .. " can dig for gold now.")
        end
    end,
    
    avilable_duplicator = function(entity, dt)
        -- Early exit if entity was destroyed (e.g., by forager_sensing death)
        if not registry:valid(entity) then return end

        -- Check if the duplicator table is not empty, and there is one with taken flag not set
        local duplicatorAvailable = false
        if #globals.structures.duplicators > 0 then
            for _, duplicatorEntry in ipairs(globals.structures.duplicators) do
                if not duplicatorEntry.taken then
                    -- If we find a duplicator that is not taken, set the world state
                    ai.set_worldstate(entity, "duplicator_available", true)
                    log_debug("avilable_duplicator: Found an available duplicator for entity " .. tostring(entity))
                    -- save in blackboard
                    setBlackboardInt(entity, "duplicator_available", duplicatorEntry.entity)
                    duplicatorEntry.taken = true -- mark it as taken
                    
                    duplicatorAvailable = true
                    break
                end
            end
        end
        
        if not duplicatorAvailable then
            
            -- if we previously found one, then don't touch world state
            if blackboardContains(entity, "duplicator_available") and
               getBlackboardInt(entity, "duplicator_available") ~= -1 then
                log_debug("avilable_duplicator: one still available for entity ", tostring(entity))
                return
            end
            -- If no duplicator is available, set the world state to false
            ai.set_worldstate(entity, "duplicator_available", false)
            log_debug("avilable_duplicator: No available duplicators for entity " .. tostring(entity))
            -- save in blackboard
            setBlackboardInt(entity, "duplicator_available", -1) -- -1 indicates no duplicator available
        end
    end,

    perception_tick = function(entity, dt)
        if not registry:valid(entity) then return end
        if ai.perception and ai.perception.tick then
            ai.perception.tick(entity, dt)
        end
    end,
    
    forager_sensing = function(entity, dt)
        -- GATE: Only run for foragers, not specialists
        local spawner = require("idle_game.spawner")
        if not spawner._foragers[entity] then return end

        local transform = registry:get(entity, Transform)
        if not transform then return end

        local tile_size = config.TILE_SIZE
        local tileX = math.floor(transform.actualX / tile_size)
        local tileY = math.floor(transform.actualY / tile_size)

        local terrain = require("idle_game.terrain")

        -- Debug: Log every 5 seconds to confirm updater is running
        local debug_timer = ai.bb.get(entity, "sensing_debug_timer", 0) + dt
        if debug_timer > 5.0 then
            local hunger = ai.bb.get(entity, "hunger", -1)
            local energy = ai.bb.get(entity, "energy", -1)
            log_debug(string.format("[SENSING] entity=%s hunger=%.0f energy=%.0f tile=(%d,%d)",
                tostring(entity), hunger, energy, tileX, tileY))
            debug_timer = 0
        end
        ai.bb.set(entity, "sensing_debug_timer", debug_timer)

        -- Sense nearby trees and rocks for harvesting
        local nearTree = terrain.isNearTileType(tileX, tileY, terrain.TREE, 2)
        local nearRock = terrain.isNearTileType(tileX, tileY, terrain.ROCK, 2)
        ai.set_worldstate(entity, "nearTree", nearTree)
        ai.set_worldstate(entity, "nearRock", nearRock)

        -- Reset didWork flag so foragers can work again
        if ai.get_worldstate(entity, "didWork") == true then
            ai.set_worldstate(entity, "didWork", false)
        end

        -- PASSIVE INCOME: Foragers automatically gather resources while near them
        -- This runs every frame and provides steady income regardless of GOAP goal selection
        local resources = require("idle_game.resources")
        local upgrades = require("idle_game.upgrades")
        local popup = require("core.popup")

        local harvest_timer = ai.bb.get(entity, "auto_harvest_timer", 0) + dt
        local harvest_interval = 3.0  -- Harvest every 3 seconds when near resources

        if harvest_timer >= harvest_interval then
            harvest_timer = 0
            local level = upgrades.get_level("forage_amount")
            local yield = 1 + math.floor(level * 0.3)

            if nearTree then
                -- 30% chance to harvest wood when near tree
                if math.random() < 0.3 then
                    resources.add("wood", yield)
                    popup.at(transform.actualX, transform.actualY - 10, "+" .. yield, { color = "gold" })
                    -- Small chance to consume the tree
                    if math.random() < 0.1 then
                        terrain.set(tileX, tileY, terrain.GRASS)
                    end
                end
            end

            if nearRock then
                -- 20% chance to harvest stone when near rock
                if math.random() < 0.2 then
                    resources.add("stone", yield)
                    popup.at(transform.actualX, transform.actualY - 10, "+" .. yield, { color = "white" })

                    -- Drop stone ground item for miners
                    local terrain = require("idle_game.terrain")
                    terrain.drop_item(tileX, tileY, "stone", yield)
                    -- Small chance to consume the rock
                    if math.random() < 0.1 then
                        terrain.set(tileX, tileY, terrain.GRASS)
                    end
                end
            end
        end
        ai.bb.set(entity, "auto_harvest_timer", harvest_timer)
    end,

    -- Lumberjack sensing - targets trees specifically, not rocks or bushes
    lumberjack_sensing = function(entity, dt)
        -- GATE: Only run for lumberjacks
        local spawner = require("idle_game.spawner")
        if not spawner._lumberjacks or not spawner._lumberjacks[entity] then return end

        local transform = registry:get(entity, Transform)
        if not transform then return end

        local tile_size = config.TILE_SIZE
        local tileX = math.floor(transform.actualX / tile_size)
        local tileY = math.floor(transform.actualY / tile_size)

        local terrain = require("idle_game.terrain")

        -- Only sense trees, NOT rocks (lumberjack targets trees specifically)
        local nearTree = terrain.isNearTileType(tileX, tileY, terrain.TREE, 2)
        ai.set_worldstate(entity, "nearTree", nearTree)

        -- Reset didWork flag so lumberjacks can work again
        if ai.get_worldstate(entity, "didWork") == true then
            ai.set_worldstate(entity, "didWork", false)
        end

        -- LUMBERJACK PASSIVE INCOME: Harvest wood at 1.5x rate when near trees
        local resources = require("idle_game.resources")
        local upgrades = require("idle_game.upgrades")
        local popup = require("core.popup")

        local harvest_timer = ai.bb.get(entity, "auto_harvest_timer", 0) + dt
        local harvest_interval = 3.0  -- Same interval as foragers

        if harvest_timer >= harvest_interval then
            harvest_timer = 0
            local level = upgrades.get_level("forage_amount")
            local base_yield = 1 + math.floor(level * 0.3)
            local yield = math.floor(base_yield * 1.5)  -- Lumberjack 1.5x multiplier

            if nearTree then
                -- 30% chance to harvest wood when near tree
                if math.random() < 0.3 then
                    -- Drop wood as ground item instead of directly adding to resources
                    terrain.drop_item(tileX, tileY, "wood", yield)
                    popup.at(transform.actualX, transform.actualY - 10, "+" .. yield .. " Wood", { color = "brown" })

                    -- Small chance to consume the tree
                    if math.random() < 0.1 then
                        terrain.set(tileX, tileY, terrain.GRASS)
                    end
                end
            end
        end
        ai.bb.set(entity, "auto_harvest_timer", harvest_timer)

        -- ═══════════════════════════════════════════════════════════════
        -- SURVIVAL SYSTEM: Hunger, Energy, Age, Death, Reproduction
        -- ═══════════════════════════════════════════════════════════════

        local spawner = require("idle_game.spawner")

        -- Get current survival stats from blackboard
        local hunger = ai.bb.get(entity, "hunger", 50)
        local energy = ai.bb.get(entity, "energy", 50)
        local age = ai.bb.get(entity, "age", 0)

        -- HUNGER DECAY: Loses ~5 hunger per second (starves in ~20 seconds if not eating)
        hunger = hunger - dt * 5
        if hunger < 0 then hunger = 0 end

        -- ENERGY DECAY: Loses ~2 energy per second while working (near resources)
        if nearTree or nearRock then
            energy = energy - dt * 3  -- Working is tiring
        else
            energy = energy - dt * 1  -- Wandering is less tiring
        end
        if energy < 0 then energy = 0 end

        -- AGE: Ticks up slowly
        age = age + dt

        -- Store updated values
        ai.bb.set(entity, "hunger", hunger)
        ai.bb.set(entity, "energy", energy)
        ai.bb.set(entity, "age", age)

        -- UPDATE WORLDSTATE BOOLEANS based on numeric values
        ai.set_worldstate(entity, "hungry", hunger < 40)
        ai.set_worldstate(entity, "starving", hunger < 15)
        ai.set_worldstate(entity, "tired", energy < 30)
        ai.set_worldstate(entity, "exhausted", energy < 10)
        ai.set_worldstate(entity, "readyToReproduce", hunger > 80 and energy > 60)

        -- DEATH CHECK: Forager dies if hunger reaches 0
        if hunger <= 0 then
            log_debug(string.format("[DEATH] Forager %s starved to death! age=%.0f", tostring(entity), age))
            popup.at(transform.actualX, transform.actualY - 20, "STARVED!", { color = "red" })

            -- Drop some food for other foragers
            resources.add("food", 2)

            -- Spawn corpse at death location (gray on pink background)
            spawner.spawnCorpseAt(transform.actualX, transform.actualY)

            -- Queue for deferred destruction (safe during AI updates)
            -- Don't destroy immediately to avoid entt assertion failures
            spawner.queueDestroy(entity)
            return  -- Exit early, entity is marked for death
        end

        -- REPRODUCTION CHECK: Well-fed and rested foragers can reproduce
        local repro_cooldown = ai.bb.get(entity, "repro_cooldown", 0)
        if repro_cooldown > 0 then
            ai.bb.set(entity, "repro_cooldown", repro_cooldown - dt)
        elseif hunger > 80 and energy > 60 then
            local max_foragers = 20 + upgrades.get_level("max_creatures") * 2
            local current_count = spawner.getForagerCount and spawner.getForagerCount() or 20

            if current_count < max_foragers then
                -- Reproduce! Costs hunger and energy
                hunger = hunger - 30
                energy = energy - 20
                ai.bb.set(entity, "hunger", hunger)
                ai.bb.set(entity, "energy", energy)
                ai.bb.set(entity, "repro_cooldown", 15.0)  -- Can't reproduce for 15 seconds

                -- Spawn new forager near parent
                local newX = transform.actualX + (math.random() - 0.5) * 40
                local newY = transform.actualY + (math.random() - 0.5) * 40
                spawner.spawnForagerAt(newX, newY)

                popup.at(transform.actualX, transform.actualY - 20, "BIRTH!", { color = "green" })
                log_debug(string.format("[BIRTH] Forager %s reproduced! population=%d/%d",
                    tostring(entity), current_count + 1, max_foragers))
            end
        end
    end,

    -- Miner sensing - targets rocks specifically, not trees or bushes
    miner_sensing = function(entity, dt)
        -- GATE: Only run for miners
        local spawner = require("idle_game.spawner")
        if not spawner._miners or not spawner._miners[entity] then return end

        local transform = registry:get(entity, Transform)
        if not transform then return end

        local tile_size = config.TILE_SIZE
        local tileX = math.floor(transform.actualX / tile_size)
        local tileY = math.floor(transform.actualY / tile_size)

        local terrain = require("idle_game.terrain")

        -- Only sense rocks, NOT trees (miner targets rocks specifically)
        local nearRock = terrain.isNearTileType(tileX, tileY, terrain.ROCK, 2)
        ai.set_worldstate(entity, "nearRock", nearRock)

        -- Reset didWork flag so miners can work again
        if ai.get_worldstate(entity, "didWork") == true then
            ai.set_worldstate(entity, "didWork", false)
        end

        -- MINER PASSIVE INCOME: Harvest stone at 1.5x rate when near rocks
        local resources = require("idle_game.resources")
        local upgrades = require("idle_game.upgrades")
        local popup = require("core.popup")

        local harvest_timer = ai.bb.get(entity, "auto_harvest_timer", 0) + dt
        local harvest_interval = 3.0  -- Same interval as foragers

        if harvest_timer >= harvest_interval then
            harvest_timer = 0
            local level = upgrades.get_level("forage_amount")
            local base_yield = 1 + math.floor(level * 0.3)
            local yield = math.floor(base_yield * 1.5)  -- Miner 1.5x multiplier

            if nearRock then
                -- 20% chance to harvest stone when near rock (same as foragers)
                if math.random() < 0.2 then
                    -- Drop stone as ground item instead of directly adding to resources
                    terrain.drop_item(tileX, tileY, "stone", yield)
                    popup.at(transform.actualX, transform.actualY - 10, "+" .. yield .. " Stone", { color = "gray" })

                    -- Small chance to consume the rock
                    if math.random() < 0.1 then
                        terrain.set(tileX, tileY, terrain.GRASS)
                    end
                end
            end
        end
        ai.bb.set(entity, "auto_harvest_timer", harvest_timer)
    end,

    -- Collector sensing - targets ground items for pickup
    collector_sensing = function(entity, dt)
        -- GATE: Only run for collectors
        local spawner = require("idle_game.spawner")
        if not spawner._collectors or not spawner._collectors[entity] then return end

        local transform = registry:get(entity, Transform)
        if not transform then return end

        local tile_size = config.TILE_SIZE
        local tileX = math.floor(transform.actualX / tile_size)
        local tileY = math.floor(transform.actualY / tile_size)

        local terrain = require("idle_game.terrain")

        -- Check for ground items in nearby area (2-tile radius)
        local nearGroundItem = false
        local ground_items = terrain.get_ground_items()

        for _, item in pairs(ground_items) do
            local item_tileX = math.floor(item.x / tile_size)
            local item_tileY = math.floor(item.y / tile_size)
            local distance = math.abs(tileX - item_tileX) + math.abs(tileY - item_tileY)

            if distance <= 2 then
                nearGroundItem = true
                break
            end
        end

        ai.set_worldstate(entity, "nearGroundItem", nearGroundItem)

        -- Reset didWork flag so collectors can work again
        if ai.get_worldstate(entity, "didWork") == true then
            ai.set_worldstate(entity, "didWork", false)
        end

        -- COLLECTOR PASSIVE COLLECTION: Pick up nearby ground items
        local resources = require("idle_game.resources")
        local popup = require("core.popup")

        local collection_timer = ai.bb.get(entity, "auto_collection_timer", 0) + dt
        local collection_interval = 2.0  -- Check for items every 2 seconds

        if collection_timer >= collection_interval then
            collection_timer = 0

            if nearGroundItem then
                -- 50% chance to collect item when near ground items
                if math.random() < 0.5 then
                    -- Find closest ground item and collect it
                    local closest_item = nil
                    local closest_distance = math.huge

                    for id, item in pairs(ground_items) do
                        local item_tileX = math.floor(item.x / tile_size)
                        local item_tileY = math.floor(item.y / tile_size)
                        local distance = math.abs(tileX - item_tileX) + math.abs(tileY - item_tileY)

                        if distance <= 2 and distance < closest_distance then
                            closest_item = item
                            closest_distance = distance
                        end
                    end

                    if closest_item then
                        -- Collect the item (add to resources and remove from ground)
                        resources.add(closest_item.kind, closest_item.amount)
                        popup.at(transform.actualX, transform.actualY - 10,
                                "+" .. closest_item.amount .. " " .. string.upper(closest_item.kind),
                                { color = "green" })

                        -- Remove from ground items
                        terrain._ground_items[closest_item.id] = nil

                        log_debug(string.format("Collector %s collected %d %s at (%.0f, %.0f)",
                            tostring(entity), closest_item.amount, closest_item.kind,
                            closest_item.x, closest_item.y))
                    end
                end
            end
        end
        ai.bb.set(entity, "auto_collection_timer", collection_timer)
    end,

    builder_sensing = function(entity, dt)
        -- GATE: Only run for builders
        local spawner = require("idle_game.spawner")
        if not spawner._builders or not spawner._builders[entity] then return end

        local transform = component_cache.get(entity, Transform)
        if not transform then return end

        local tileX = math.floor(transform.actualX / config.TILE_SIZE)
        local tileY = math.floor(transform.actualY / config.TILE_SIZE)

        -- Find nearest empty tile within Manhattan radius 10
        local emptyX, emptyY = terrain.findNearestEmptyTile(tileX, tileY, 10)
        local nearEmptyTile = (emptyX ~= nil and emptyY ~= nil)

        ai.set_worldstate(entity, "nearEmptyTile", nearEmptyTile)

        -- Store the target empty tile coordinates for building actions
        if nearEmptyTile then
            ai.bb.set(entity, "target_empty_x", emptyX)
            ai.bb.set(entity, "target_empty_y", emptyY)

            log_debug(string.format("Builder %s found empty tile at (%d, %d), distance: %d",
                tostring(entity), emptyX, emptyY,
                math.abs(tileX - emptyX) + math.abs(tileY - emptyY)))
        else
            -- Clear target coordinates if no empty tile found
            ai.bb.set(entity, "target_empty_x", nil)
            ai.bb.set(entity, "target_empty_y", nil)
        end

        -- Reset didWork flag so builders can work again
        if ai.get_worldstate(entity, "didWork") == true then
            ai.set_worldstate(entity, "didWork", false)
        end

        -- RESOURCE CHECK: Check wood >= 50, stone >= 25 before building
        local resources = require("idle_game.resources")
        local current_wood = resources.get("wood")
        local current_stone = resources.get("stone")
        local canAffordBuild = (current_wood >= 50 and current_stone >= 25)

        ai.set_worldstate(entity, "canAffordBuild", canAffordBuild)

        if canAffordBuild then
            log_debug(string.format("Builder %s can afford to build (wood=%d/50, stone=%d/25)",
                tostring(entity), current_wood, current_stone))
        else
            log_debug(string.format("Builder %s CANNOT afford to build (wood=%d/50, stone=%d/25)",
                tostring(entity), current_wood, current_stone))
        end

        -- BUILD INTERVAL TIMER: Track 20-second build intervals
        local build_timer = ai.bb.get(entity, "build_timer", 0) + dt
        local BUILD_INTERVAL = 20.0  -- 20 seconds between build attempts

        if build_timer >= BUILD_INTERVAL then
            build_timer = 0  -- Reset timer

            -- Check all conditions for building: affordability, empty tile, not max built
            -- This integrates the resource check with the building logic
            if nearEmptyTile and canAffordBuild then
                log_debug(string.format("Builder %s build timer triggered at (%d, %d) - CAN BUILD (wood=%d/50, stone=%d/25)",
                    tostring(entity), emptyX or -1, emptyY or -1, current_wood, current_stone))

                -- Mark that builder can attempt to build (for future BUILD_STRUCTURE actions)
                ai.set_worldstate(entity, "canAttemptBuild", true)
            else
                local reason = {}
                if not nearEmptyTile then table.insert(reason, "no empty tile") end
                if not canAffordBuild then table.insert(reason, "insufficient resources") end

                log_debug(string.format("Builder %s CANNOT build: %s (wood=%d/50, stone=%d/25)",
                    tostring(entity), table.concat(reason, ", "), current_wood, current_stone))

                ai.set_worldstate(entity, "canAttemptBuild", false)
            end
        else
            ai.set_worldstate(entity, "canAttemptBuild", false)
        end

        ai.bb.set(entity, "build_timer", build_timer)
    end
}
