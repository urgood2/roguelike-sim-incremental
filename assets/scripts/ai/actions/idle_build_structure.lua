--[[
Builder action: Build a structure on an empty tile.
Spends wood (50) and stone (25) to place a structure deterministically cycling through types.
]]
return {
    name = "idle_build_structure",
    cost = 5,
    pre = { canAttemptBuild = true },  -- Must be ready to build (timer + resources + empty tile)
    post = { didWork = true },  -- Sets didWork flag to track productivity
    watch = { canAttemptBuild = true },

    start = function(e)
        log_debug("idle_build_structure: start for entity " .. tostring(e))
        setBlackboardFloat(e, "build_timer", 0)
    end,

    update = function(e, dt)
        local timer = getBlackboardFloat(e, "build_timer") or 0
        timer = timer + dt

        -- Building takes 2.0 seconds
        if timer >= 2.0 then
            return ActionResult.SUCCESS
        end

        setBlackboardFloat(e, "build_timer", timer)
        return ActionResult.RUNNING
    end,

    finish = function(e)
        log_debug("idle_build_structure: finish for entity " .. tostring(e))
        local config = require("idle_game.config")
        local terrain = require("idle_game.terrain")
        local resources = require("idle_game.resources")
        local spawner = require("idle_game.spawner")
        local popup = require("core.popup")
        local component_cache = require("core.component_cache")

        -- Get builder position
        local transformComp = component_cache.get(e, Transform)
        if not transformComp then
            log_debug("idle_build_structure: no transform component for entity " .. tostring(e))
            return
        end

        local entityTileX = math.floor((transformComp.actualX or 0) / config.TILE_SIZE)
        local entityTileY = math.floor((transformComp.actualY or 0) / config.TILE_SIZE)

        -- Find nearest empty tile within Manhattan distance 10
        local bestTile = nil
        local bestDistance = math.huge

        for dist = 1, 10 do
            for dy = -dist, dist do
                for dx = -dist, dist do
                    if math.abs(dx) + math.abs(dy) == dist then  -- Manhattan distance
                        local tileX = entityTileX + dx
                        local tileY = entityTileY + dy

                        -- Check if tile is valid and empty (grass)
                        if terrain.get(tileX, tileY) == terrain.GRASS then
                            -- Check if position is not occupied by existing structure
                            local structures = terrain.get_structures()
                            local occupied = false
                            for _, structure in pairs(structures) do
                                if structure.x == tileX and structure.y == tileY then
                                    occupied = true
                                    break
                                end
                            end

                            if not occupied then
                                bestTile = { x = tileX, y = tileY }
                                bestDistance = dist
                                break
                            end
                        end
                    end
                end
                if bestTile then break end
            end
            if bestTile then break end
        end

        if not bestTile then
            log_debug(string.format("idle_build_structure: entity %s found no valid empty tile within distance 10", tostring(e)))
            return
        end

        -- Check resources one more time before spending
        local current_wood = resources.get("wood")
        local current_stone = resources.get("stone")
        if current_wood < 50 or current_stone < 25 then
            log_debug(string.format("idle_build_structure: entity %s insufficient resources (wood=%d/50, stone=%d/25)",
                tostring(e), current_wood, current_stone))
            return
        end

        -- Determine structure type deterministically by cycling through valid types
        -- Use a global build counter to ensure deterministic cycling
        local build_counter = ai.bb.get("global", "build_counter", 0) + 1
        ai.bb.set("global", "build_counter", build_counter)

        local structure_types = { "farm", "house", "mine", "workshop", "storage" }
        local structure_index = ((build_counter - 1) % #structure_types) + 1
        local structure_type = structure_types[structure_index]

        -- Spend resources
        resources.add("wood", -50)
        resources.add("stone", -25)

        -- Place structure
        local success, structure_id = terrain.place_structure(bestTile.x, bestTile.y, structure_type)
        if success then
            -- Visual feedback
            local worldX = bestTile.x * config.TILE_SIZE + config.TILE_SIZE / 2
            local worldY = bestTile.y * config.TILE_SIZE + config.TILE_SIZE / 2
            popup.at(worldX, worldY, structure_type:upper(), { color = "green" })

            log_debug(string.format("idle_build_structure: entity %s built %s (#%d) at (%d,%d) using counter %d",
                tostring(e), structure_type, structure_id or 0, bestTile.x, bestTile.y, build_counter))
        else
            log_debug(string.format("idle_build_structure: entity %s failed to place structure: %s",
                tostring(e), tostring(structure_id)))
        end
    end,

    abort = function(e, reason)
        log_debug("idle_build_structure: aborted - " .. tostring(reason))
    end
}