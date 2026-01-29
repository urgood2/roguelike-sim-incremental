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

        -- Debug logging (every 3 seconds per entity via frame counting)
        local sense_frame = ai.bb.get(entity, "sense_log_frame", 0) + 1
        ai.bb.set(entity, "sense_log_frame", sense_frame)
        if sense_frame % 180 == 1 and (nearTree or nearRock) then
            log_debug(string.format("[forager_sensing] entity=%s tile=(%d,%d) nearTree=%s nearRock=%s",
                tostring(entity), tileX, tileY, tostring(nearTree), tostring(nearRock)))
        end

        -- Reset didWork flag so foragers can work again
        if ai.get_worldstate(entity, "didWork") == true then
            ai.set_worldstate(entity, "didWork", false)
        end

        -- Hunger system (foragers get hungry over time)
        local hungry = ai.get_worldstate(entity, "hungry")
        if not hungry then
            local hunger_timer = ai.bb.get(entity, "hunger_timer", 0) + dt
            if hunger_timer > 10.0 then
                ai.set_worldstate(entity, "hungry", true)
                ai.bb.set(entity, "hunger_timer", 0)
            else
                ai.bb.set(entity, "hunger_timer", hunger_timer)
            end
        end
    end
}
