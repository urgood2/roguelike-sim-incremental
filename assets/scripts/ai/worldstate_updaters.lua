-- These will run every frame per ai entity.

return {
    -- Reset wander state so foragers continuously wander
    wander_reset = function(entity, dt)
        -- Only reset if wander is currently true (just completed wandering)
        if ai.get_worldstate(entity, "wander") == true then
            ai.set_worldstate(entity, "wander", false)
        end
    end,

    hunger_check = function(entity, dt)
        -- TODO: Implement hunger check logic
        local bb = ai.get_blackboard(entity)
        if (bb:contains("hunger")) == false then
            log_debug("Hunger key not found in blackboard for entity: " .. tostring(entity))
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
        -- TODO: Implement enemy sight check logic
        -- local visible = check_if_enemy_visible(entity)
        -- ai.set_worldstate(entity, "enemyvisible", visible)
        -- local bb = get_blackboard(entity)
        -- bb.enemy_visible = visible
    end,
    
    can_heal_other = function(entity, dt)
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
        if ai.perception and ai.perception.tick then
            ai.perception.tick(entity, dt)
        end
    end,
    
    forager_sensing = function(entity, dt)
        local transform = registry:get(entity, Transform)
        if not transform then return end

        local TILE_SIZE = 20
        local tileX = math.floor(transform.actualX / TILE_SIZE)
        local tileY = math.floor(transform.actualY / TILE_SIZE)

        local terrain = require("idle_game.terrain")

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
                    -- Small chance to consume the rock
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

            -- Destroy the entity
            if registry:valid(entity) then
                registry:destroy(entity)
            end
            return  -- Exit early, entity is dead
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
    end
}
