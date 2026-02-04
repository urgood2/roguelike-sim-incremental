--[[
Navigate to nearest ground item and collect it.
This action handles active collection of distant ground items (beyond 2-tile passive range).

Behavior:
1. Find nearest ground item on the map
2. Navigate tile-by-tile toward the item
3. When within collection range, pick up the item
4. Add collected item to player resources
]]

return {
    name = "idle_collect_item",
    cost = 3,  -- Higher cost than passive collection - only when no closer options
    pre = { nearGroundItem = false, hasInventorySpace = true },  -- Only when not passively collecting
    post = { didWork = true },  -- Mark that collector worked
    watch = { nearGroundItem = true, hasInventorySpace = true },  -- Watch for changes

    start = function(e)
        log_debug("idle_collect_item: start for entity " .. tostring(e))
        local config = require("idle_game.config")
        local terrain = require("idle_game.terrain")
        local component_cache = require("core.component_cache")

        -- Get current tile position
        local transformComp = component_cache.get(e, Transform)
        if not transformComp then return end

        local currentTileX = math.floor((transformComp.actualX or 0) / config.TILE_SIZE)
        local currentTileY = math.floor((transformComp.actualY or 0) / config.TILE_SIZE)

        -- Find nearest ground item
        local ground_items = terrain.get_ground_items()
        local nearest_item = nil
        local nearest_distance = math.huge

        for id, item in pairs(ground_items) do
            local item_tileX = math.floor(item.x / config.TILE_SIZE)
            local item_tileY = math.floor(item.y / config.TILE_SIZE)
            local distance = math.abs(currentTileX - item_tileX) + math.abs(currentTileY - item_tileY)

            if distance < nearest_distance then
                nearest_item = item
                nearest_distance = distance
            end
        end

        if not nearest_item then
            -- No ground items available
            log_debug("idle_collect_item: no ground items found")
            return
        end

        -- Store target item and tile coords
        setBlackboardInt(e, "collect_target_item_id", nearest_item.id)
        setBlackboardInt(e, "collect_target_tile_x", math.floor(nearest_item.x / config.TILE_SIZE))
        setBlackboardInt(e, "collect_target_tile_y", math.floor(nearest_item.y / config.TILE_SIZE))
        setBlackboardInt(e, "collect_current_tile_x", currentTileX)
        setBlackboardInt(e, "collect_current_tile_y", currentTileY)
        setBlackboardFloat(e, "collect_tween_progress", 1.0)  -- Ready for first step
        setBlackboardInt(e, "collect_initialized", 0)  -- Will re-sync position on first update

        log_debug(string.format("idle_collect_item[%s]: navigating from (%d,%d) to item at (%d,%d)",
            tostring(e), currentTileX, currentTileY,
            math.floor(nearest_item.x / config.TILE_SIZE),
            math.floor(nearest_item.y / config.TILE_SIZE)))

        startEntityWalkMotion(e)
    end,

    update = function(e, dt)
        local config = require("idle_game.config")
        local terrain = require("idle_game.terrain")
        local component_cache = require("core.component_cache")
        local upgrades = require("idle_game.upgrades")
        local resources = require("idle_game.resources")
        local popup = require("core.popup")

        local transformComp = component_cache.get(e, Transform)
        if not transformComp then
            return ActionResult.FAILURE
        end

        -- Verify target item still exists
        local target_item_id = getBlackboardInt(e, "collect_target_item_id")
        local ground_items = terrain.get_ground_items()
        local target_item = ground_items[target_item_id]

        if not target_item then
            -- Target item was collected by someone else or disappeared
            log_debug("idle_collect_item: target item no longer exists")
            return ActionResult.FAILURE
        end

        -- First update: re-sync position from Transform
        local initialized = getBlackboardInt(e, "collect_initialized") or 0
        if initialized == 0 then
            local actualTileX = math.floor((transformComp.actualX or 0) / config.TILE_SIZE)
            local actualTileY = math.floor((transformComp.actualY or 0) / config.TILE_SIZE)
            setBlackboardInt(e, "collect_current_tile_x", actualTileX)
            setBlackboardInt(e, "collect_current_tile_y", actualTileY)
            setBlackboardInt(e, "collect_prev_tile_x", actualTileX)
            setBlackboardInt(e, "collect_prev_tile_y", actualTileY)
            setBlackboardInt(e, "collect_initialized", 1)
        end

        local targetTileX = getBlackboardInt(e, "collect_target_tile_x") or 0
        local targetTileY = getBlackboardInt(e, "collect_target_tile_y") or 0
        local currentTileX = getBlackboardInt(e, "collect_current_tile_x") or 0
        local currentTileY = getBlackboardInt(e, "collect_current_tile_y") or 0
        local tweenProgress = getBlackboardFloat(e, "collect_tween_progress") or 1.0

        -- Check if we're within collection range (2 tiles)
        local distance = math.abs(currentTileX - targetTileX) + math.abs(currentTileY - targetTileY)
        if distance <= 2 then
            -- Within collection range - collect the item
            log_debug(string.format("idle_collect_item[%s]: collecting item %d (%s x%d)",
                tostring(e), target_item.id, target_item.kind, target_item.amount))

            -- Add to resources
            resources.add(target_item.kind, target_item.amount)

            -- Show collection popup
            popup.at(transformComp.actualX, transformComp.actualY - 10,
                    "+" .. target_item.amount .. " " .. string.upper(target_item.kind),
                    { color = "green" })

            -- Remove from ground items
            terrain._ground_items[target_item.id] = nil

            -- Mark that work was done
            ai.set_worldstate(e, "didWork", true)

            log_debug(string.format("Collector %s collected %d %s at (%.0f, %.0f)",
                tostring(e), target_item.amount, target_item.kind,
                target_item.x, target_item.y))

            return ActionResult.SUCCESS
        end

        -- Speed: tiles per second (base 2, upgradeable like wander)
        local speedLevel = upgrades.get_level("creature_speed") or 0
        local tilesPerSecond = 2 * (1 + speedLevel * 0.2)

        -- If tween is complete, move to next tile
        if tweenProgress >= 1.0 then
            -- Pick next tile (move one step toward target item)
            local nextTileX = currentTileX
            local nextTileY = currentTileY

            local dx = targetTileX - currentTileX
            local dy = targetTileY - currentTileY

            -- Move one tile at a time (prefer X then Y, or random)
            if dx ~= 0 and dy ~= 0 then
                -- Both directions needed - pick randomly
                if math.random() < 0.5 then
                    nextTileX = currentTileX + (dx > 0 and 1 or -1)
                else
                    nextTileY = currentTileY + (dy > 0 and 1 or -1)
                end
            elseif dx ~= 0 then
                nextTileX = currentTileX + (dx > 0 and 1 or -1)
            elseif dy ~= 0 then
                nextTileY = currentTileY + (dy > 0 and 1 or -1)
            end

            -- Store previous tile for tweening
            setBlackboardInt(e, "collect_prev_tile_x", currentTileX)
            setBlackboardInt(e, "collect_prev_tile_y", currentTileY)
            setBlackboardInt(e, "collect_current_tile_x", nextTileX)
            setBlackboardInt(e, "collect_current_tile_y", nextTileY)
            setBlackboardFloat(e, "collect_tween_progress", 0.0)
            tweenProgress = 0.0
            currentTileX = nextTileX
            currentTileY = nextTileY
        end

        -- Smooth tile-to-tile tweening
        local prevTileX = getBlackboardInt(e, "collect_prev_tile_x") or currentTileX
        local prevTileY = getBlackboardInt(e, "collect_prev_tile_y") or currentTileY

        tweenProgress = tweenProgress + tilesPerSecond * dt
        if tweenProgress > 1.0 then tweenProgress = 1.0 end
        setBlackboardFloat(e, "collect_tween_progress", tweenProgress)

        -- Smooth interpolation between tiles
        local fromX = prevTileX * config.TILE_SIZE
        local fromY = prevTileY * config.TILE_SIZE
        local toX = currentTileX * config.TILE_SIZE
        local toY = currentTileY * config.TILE_SIZE

        transformComp.actualX = fromX + (toX - fromX) * tweenProgress
        transformComp.actualY = fromY + (toY - fromY) * tweenProgress

        return ActionResult.RUNNING
    end,

    finish = function(e)
        log_debug("idle_collect_item: finish for entity " .. tostring(e))
        local config = require("idle_game.config")
        local component_cache = require("core.component_cache")

        -- Snap to exact tile position on finish
        local transformComp = component_cache.get(e, Transform)
        if transformComp then
            local tileX = getBlackboardInt(e, "collect_current_tile_x") or 0
            local tileY = getBlackboardInt(e, "collect_current_tile_y") or 0
            transformComp.actualX = tileX * config.TILE_SIZE
            transformComp.actualY = tileY * config.TILE_SIZE
        end

        stopEntityWalkMotion(e)
    end,

    abort = function(e, reason)
        log_debug("idle_collect_item: aborted - " .. tostring(reason))
        stopEntityWalkMotion(e)
    end
}