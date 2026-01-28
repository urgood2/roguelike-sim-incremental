--[[
Discrete tile-based wandering (roguelike/pico8 style).
Entities pick a random target TILE and move tile-by-tile.
Visual movement is smooth via tweening, but positions snap to grid.
]]
return {
    name = "idle_wander",
    cost = 1,
    pre = {},  -- No preconditions - always plannable
    post = { wander = true },  -- Sets wander=true when complete
    watch = {},

    start = function(e)
        log_debug("idle_wander: start for entity " .. tostring(e))
        local config = require("idle_game.config")
        local component_cache = require("core.component_cache")

        -- Get current tile position
        local transformComp = component_cache.get(e, Transform)
        if not transformComp then return end

        local currentTileX = math.floor((transformComp.actualX or 0) / config.TILE_SIZE)
        local currentTileY = math.floor((transformComp.actualY or 0) / config.TILE_SIZE)

        -- Pick a random target TILE (discrete, not pixel)
        local targetTileX = math.random(0, config.GRID_WIDTH - 1)
        local targetTileY = math.random(0, config.GRID_HEIGHT - 1)

        -- Store target tile coords (current tile will be re-synced on first update)
        setBlackboardInt(e, "wander_target_tile_x", targetTileX)
        setBlackboardInt(e, "wander_target_tile_y", targetTileY)
        setBlackboardInt(e, "wander_current_tile_x", currentTileX)
        setBlackboardInt(e, "wander_current_tile_y", currentTileY)
        setBlackboardFloat(e, "wander_tween_progress", 1.0)  -- Start at 1.0 = ready for next step
        setBlackboardInt(e, "wander_initialized", 0)  -- Will re-sync position on first update

        log_debug(string.format("idle_wander[%s]: tile (%d,%d) -> (%d,%d)",
            tostring(e), currentTileX, currentTileY, targetTileX, targetTileY))

        startEntityWalkMotion(e)
    end,

    update = function(e, dt)
        local config = require("idle_game.config")
        local component_cache = require("core.component_cache")
        local upgrades = require("idle_game.upgrades")

        local transformComp = component_cache.get(e, Transform)
        if not transformComp then
            return ActionResult.FAILURE
        end

        -- First update: re-sync position from Transform (fixes race with spawner)
        local initialized = getBlackboardInt(e, "wander_initialized") or 0
        if initialized == 0 then
            local actualTileX = math.floor((transformComp.actualX or 0) / config.TILE_SIZE)
            local actualTileY = math.floor((transformComp.actualY or 0) / config.TILE_SIZE)
            setBlackboardInt(e, "wander_current_tile_x", actualTileX)
            setBlackboardInt(e, "wander_current_tile_y", actualTileY)
            setBlackboardInt(e, "wander_prev_tile_x", actualTileX)
            setBlackboardInt(e, "wander_prev_tile_y", actualTileY)
            setBlackboardInt(e, "wander_initialized", 1)
            log_debug(string.format("idle_wander[%s]: synced to actual tile (%d,%d)",
                tostring(e), actualTileX, actualTileY))
        end

        local targetTileX = getBlackboardInt(e, "wander_target_tile_x") or 0
        local targetTileY = getBlackboardInt(e, "wander_target_tile_y") or 0
        local currentTileX = getBlackboardInt(e, "wander_current_tile_x") or 0
        local currentTileY = getBlackboardInt(e, "wander_current_tile_y") or 0
        local tweenProgress = getBlackboardFloat(e, "wander_tween_progress") or 1.0

        -- Speed: tiles per second (base 2, upgradeable)
        local speedLevel = upgrades.get_level("creature_speed")
        local tilesPerSecond = 2 * (1 + speedLevel * 0.2)

        -- If tween is complete, move to next tile
        if tweenProgress >= 1.0 then
            -- Check if we've reached target tile
            if currentTileX == targetTileX and currentTileY == targetTileY then
                -- Snap to exact tile position
                transformComp.actualX = currentTileX * config.TILE_SIZE
                transformComp.actualY = currentTileY * config.TILE_SIZE
                log_debug("idle_wander: entity " .. tostring(e) .. " reached target tile")
                return ActionResult.SUCCESS
            end

            -- Pick next tile (move one step toward target)
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
            setBlackboardInt(e, "wander_prev_tile_x", currentTileX)
            setBlackboardInt(e, "wander_prev_tile_y", currentTileY)
            setBlackboardInt(e, "wander_current_tile_x", nextTileX)
            setBlackboardInt(e, "wander_current_tile_y", nextTileY)
            setBlackboardFloat(e, "wander_tween_progress", 0.0)
            tweenProgress = 0.0
            currentTileX = nextTileX
            currentTileY = nextTileY
        end

        -- Tween toward current tile
        local prevTileX = getBlackboardInt(e, "wander_prev_tile_x") or currentTileX
        local prevTileY = getBlackboardInt(e, "wander_prev_tile_y") or currentTileY

        tweenProgress = tweenProgress + tilesPerSecond * dt
        if tweenProgress > 1.0 then tweenProgress = 1.0 end
        setBlackboardFloat(e, "wander_tween_progress", tweenProgress)

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
        log_debug("idle_wander: finish for entity " .. tostring(e))
        local config = require("idle_game.config")
        local component_cache = require("core.component_cache")

        -- Snap to exact tile position on finish
        local transformComp = component_cache.get(e, Transform)
        if transformComp then
            local tileX = getBlackboardInt(e, "wander_current_tile_x") or 0
            local tileY = getBlackboardInt(e, "wander_current_tile_y") or 0
            transformComp.actualX = tileX * config.TILE_SIZE
            transformComp.actualY = tileY * config.TILE_SIZE
        end

        stopEntityWalkMotion(e)
    end,

    abort = function(e, reason)
        log_debug("idle_wander: aborted - " .. tostring(reason))
        stopEntityWalkMotion(e)
    end
}
