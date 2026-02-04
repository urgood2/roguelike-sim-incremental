--[[
Forager action: Harvest wood from nearby tree.
Adds wood to player resources and converts tree tile to grass.
]]
return {
    name = "idle_harvest_wood",
    cost = 3,
    pre = { nearTree = true },  -- Must be near a tree
    post = { didWork = true },  -- Sets didWork flag to track productivity
    watch = { nearTree = true },

    start = function(e)
        log_debug("idle_harvest_wood: start for entity " .. tostring(e))
        setBlackboardFloat(e, "harvest_timer", 0)
    end,

    update = function(e, dt)
        local timer = getBlackboardFloat(e, "harvest_timer") or 0
        timer = timer + dt

        -- Harvest takes 1.5 seconds
        if timer >= 1.5 then
            return ActionResult.SUCCESS
        end

        setBlackboardFloat(e, "harvest_timer", timer)
        return ActionResult.RUNNING
    end,

    finish = function(e)
        log_debug("idle_harvest_wood: finish for entity " .. tostring(e))
        local config = require("idle_game.config")
        local terrain = require("idle_game.terrain")
        local resources = require("idle_game.resources")
        local upgrades = require("idle_game.upgrades")
        local spawner = require("idle_game.spawner")
        local popup = require("core.popup")
        local component_cache = require("core.component_cache")

        -- Find and harvest the nearest tree
        local transformComp = component_cache.get(e, Transform)
        if not transformComp then return end

        local entityTileX = math.floor((transformComp.actualX or 0) / config.TILE_SIZE)
        local entityTileY = math.floor((transformComp.actualY or 0) / config.TILE_SIZE)

        -- Search in a 2-tile radius for a tree
        for dy = -2, 2 do
            for dx = -2, 2 do
                local tileX = entityTileX + dx
                local tileY = entityTileY + dy
                if terrain.get(tileX, tileY) == terrain.TREE then
                    -- Harvest this tree!
                    local level = upgrades.get_level("forage_amount")
                    local base_yield = 1 + math.floor(level * 0.5)  -- 1 base + 0.5 per upgrade level
                    local is_lumberjack = spawner._lumberjacks and spawner._lumberjacks[e]
                    local yield = is_lumberjack and math.floor(base_yield * 1.5) or base_yield
                    resources.add("wood", yield)
                    terrain.set(tileX, tileY, terrain.GRASS)
                    if is_lumberjack then
                        local drop_amount = math.max(1, math.floor(yield * 0.25))
                        terrain.drop_item(tileX, tileY, "wood", drop_amount)
                    end

                    -- Visual feedback
                    local worldX = tileX * config.TILE_SIZE + config.TILE_SIZE / 2
                    local worldY = tileY * config.TILE_SIZE + config.TILE_SIZE / 2
                    popup.at(worldX, worldY, "+" .. yield, { color = "gold" })

                    log_debug(string.format("idle_harvest_wood: entity %s harvested tree at (%d,%d) +%d wood",
                        tostring(e), tileX, tileY, yield))
                    return
                end
            end
        end

        log_debug("idle_harvest_wood: no tree found near entity " .. tostring(e))
    end,

    abort = function(e, reason)
        log_debug("idle_harvest_wood: aborted - " .. tostring(reason))
    end
}
