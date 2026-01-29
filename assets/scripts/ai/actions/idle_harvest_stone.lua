--[[
Forager action: Mine stone from nearby rock.
Adds stone to player resources and converts rock tile to grass.
]]
return {
    name = "idle_harvest_stone",
    cost = 4,  -- Slightly higher cost than wood (stone is more valuable)
    pre = { nearRock = true },  -- Must be near a rock
    post = { didWork = true },  -- Sets didWork flag to track productivity
    watch = { nearRock = true },

    start = function(e)
        log_debug("idle_harvest_stone: start for entity " .. tostring(e))
        setBlackboardFloat(e, "harvest_timer", 0)
    end,

    update = function(e, dt)
        local timer = getBlackboardFloat(e, "harvest_timer") or 0
        timer = timer + dt

        -- Mining takes 2 seconds (longer than wood)
        if timer >= 2.0 then
            return ActionResult.SUCCESS
        end

        setBlackboardFloat(e, "harvest_timer", timer)
        return ActionResult.RUNNING
    end,

    finish = function(e)
        log_debug("idle_harvest_stone: finish for entity " .. tostring(e))
        local config = require("idle_game.config")
        local terrain = require("idle_game.terrain")
        local resources = require("idle_game.resources")
        local upgrades = require("idle_game.upgrades")
        local popup = require("core.popup")
        local component_cache = require("core.component_cache")

        -- Find and mine the nearest rock
        local transformComp = component_cache.get(e, Transform)
        if not transformComp then return end

        local entityTileX = math.floor((transformComp.actualX or 0) / config.TILE_SIZE)
        local entityTileY = math.floor((transformComp.actualY or 0) / config.TILE_SIZE)

        -- Search in a 2-tile radius for a rock
        for dy = -2, 2 do
            for dx = -2, 2 do
                local tileX = entityTileX + dx
                local tileY = entityTileY + dy
                if terrain.get(tileX, tileY) == terrain.ROCK then
                    -- Mine this rock!
                    local level = upgrades.get_level("forage_amount")
                    local yield = 1 + math.floor(level * 0.5)  -- 1 base + 0.5 per upgrade level
                    resources.add("stone", yield)
                    terrain.set(tileX, tileY, terrain.GRASS)

                    -- Visual feedback
                    local worldX = tileX * config.TILE_SIZE + config.TILE_SIZE / 2
                    local worldY = tileY * config.TILE_SIZE + config.TILE_SIZE / 2
                    popup.at(worldX, worldY, "+" .. yield, { color = "white" })

                    log_debug(string.format("idle_harvest_stone: entity %s mined rock at (%d,%d) +%d stone",
                        tostring(e), tileX, tileY, yield))
                    return
                end
            end
        end

        log_debug("idle_harvest_stone: no rock found near entity " .. tostring(e))
    end,

    abort = function(e, reason)
        log_debug("idle_harvest_stone: aborted - " .. tostring(reason))
    end
}
