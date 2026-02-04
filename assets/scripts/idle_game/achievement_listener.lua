-- Achievement listener with save debouncing
local achievement_listener = {}

local achievements = require("idle_game.achievements")
local signal_group = require("core.signal_group")

-- Internal state
local _initialized = false
local _toast_queue = nil
local _handlers = nil  -- signal_group instance

-- Save debounce state - implements the requirement:
-- "Set pending_save flag, save when debounce >= 1.0s"
local _pending_save = false
local _save_debounce_timer = 0.0
local _save_debounce_threshold = 1.0  -- 1.0 second debounce as specified

-- Initialize the achievement listener
function achievement_listener.init(toast_queue)
    if _initialized then
        -- Prevent double initialization (deduplication)
        return
    end

    _toast_queue = toast_queue
    _initialized = true
    _pending_save = false
    _save_debounce_timer = 0.0

    -- Create signal group for scoped handler registration
    _handlers = signal_group.new("achievement_listener")

    -- Register signal handlers for achievement evaluation
    register_achievement_handlers()

    -- Evaluate all achievements against current game state at startup
    achievement_listener.refresh_and_evaluate()

    print("Achievement listener initialized")
end

-- Shutdown the achievement listener
function achievement_listener.shutdown()
    if not _initialized then
        return
    end

    -- Unregister all signal handlers using signal group cleanup
    if _handlers then
        _handlers:cleanup()
        _handlers = nil
    end

    _initialized = false
    _toast_queue = nil
    _pending_save = false
    _save_debounce_timer = 0.0

    print("Achievement listener shutdown")
end

-- Check if the listener is initialized
function achievement_listener.is_initialized()
    return _initialized
end

-- Get handler count for testing deduplication
function achievement_listener.get_handler_count()
    if not _handlers then
        return 0
    end
    return _handlers:count()
end

-- Update function called each frame - implements save debounce logic
function achievement_listener.update(dt)
    if not _initialized or not dt or dt <= 0 then
        return
    end

    achievements.update(dt)

    local defs = achievements.get_all and achievements.get_all() or nil
    if defs and achievements.get_game_time and achievements.unlock then
        local game_time = achievements.get_game_time() or 0
        local unlocked_any = false

        if defs.time_5min and achievements.unlock("time_5min", game_time) then
            unlocked_any = true
        end
        if defs.time_15min and achievements.unlock("time_15min", game_time) then
            unlocked_any = true
        end

        if unlocked_any then
            achievement_listener.request_save()
        end
    end

    -- Evaluate upgrade achievements
    if evaluate_upgrade_achievements() then
        achievement_listener.request_save()
    end

    -- CORE REQUIREMENT: Save debounce implementation
    -- Set pending_save flag, save when debounce >= 1.0s
    if _pending_save then
        _save_debounce_timer = _save_debounce_timer + dt

        -- Trigger save when debounce threshold is reached
        if _save_debounce_timer >= _save_debounce_threshold then
            trigger_save()
        end
    end
end

-- Mark that a save is needed (sets pending_save flag)
function achievement_listener.request_save()
    if not _initialized then
        return
    end

    _pending_save = true
    _save_debounce_timer = 0.0  -- Reset debounce timer
end

-- Force immediate save (bypasses debounce)
function achievement_listener.force_save()
    if not _initialized then
        return
    end

    trigger_save()
end

-- Internal function to trigger actual save
function trigger_save()
    if not _pending_save then
        return
    end

    -- TODO: Implement actual save functionality when SaveManager is available
    print("Achievement listener: triggering save (debounced)")

    -- Reset save debounce state
    _pending_save = false
    _save_debounce_timer = 0.0
end

-- Register achievement-related signal handlers
function register_achievement_handlers()
    if not _handlers then
        print("Achievement listener: no signal group available for handler registration")
        return
    end

    -- Register for resource change events to evaluate resource-based achievements
    _handlers:on("idle.resource_total", function(resource_key, new_total)
        achievement_listener._evaluate_resource_achievements(resource_key, new_total)
    end)

    -- Register for resource addition events (for cumulative achievements)
    _handlers:on("idle.resource_added", function(resource_type, new_value, delta)
        if delta > 0 then
            achievement_listener._evaluate_cumulative_achievements(resource_type, delta)
        end
    end)

    -- Register for creature count changes to evaluate population-based achievements
    _handlers:on("idle.creature_counts", function(counts)
        achievement_listener._evaluate_population_achievements(counts)
    end)

    print(string.format("Achievement signal handlers registered: %d handlers", _handlers:count()))
end

-- Refresh and evaluate all achievements (called on init)
function achievement_listener.refresh_and_evaluate()
    if not _initialized then
        return
    end

    local unlocked_any = false

    -- Get all current game state using module getters
    local resources = require("idle_game.resources")
    local spawner = require("idle_game.spawner")
    local upgrades = require("idle_game.upgrades")

    -- 1. Evaluate resource achievements
    local wood_total = resources.get("wood") or 0
    local stone_total = resources.get("stone") or 0
    local gold_total = resources.get("gold") or 0
    local food_total = resources.get("food") or 0
    local resource_sum = wood_total + stone_total + gold_total + food_total

    if wood_total >= 100 and achievements.unlock("res_wood_100", wood_total) then
        show_achievement_toast("res_wood_100")
        unlocked_any = true
    end

    if stone_total >= 100 and achievements.unlock("res_stone_100", stone_total) then
        show_achievement_toast("res_stone_100")
        unlocked_any = true
    end

    if gold_total >= 25 and achievements.unlock("res_gold_25", gold_total) then
        show_achievement_toast("res_gold_25")
        unlocked_any = true
    end

    if resource_sum >= 500 and achievements.unlock("res_total_500", resource_sum) then
        show_achievement_toast("res_total_500")
        unlocked_any = true
    end

    -- 2. Evaluate population achievements
    local forager_count = spawner.getForagerCount and spawner.getForagerCount() or 0
    local lumberjack_count = spawner.getLumberjackCount and spawner.getLumberjackCount() or 0
    local collector_count = spawner.getCollectorCount and spawner.getCollectorCount() or 0
    local builder_count = spawner.getBuilderCount and spawner.getBuilderCount() or 0
    local miner_count = spawner.getMinerCount and spawner.getMinerCount() or 0

    local total_creatures = forager_count + lumberjack_count + collector_count + builder_count + miner_count
    local specialist_count = lumberjack_count + collector_count + builder_count + miner_count

    -- Evaluate creature achievements with correct IDs
    if total_creatures >= 25 and achievements.unlock("crt_total_25", total_creatures) then
        show_achievement_toast("crt_total_25")
        unlocked_any = true
    end

    if specialist_count >= 10 and achievements.unlock("crt_specialists_10", specialist_count) then
        show_achievement_toast("crt_specialists_10")
        unlocked_any = true
    end

    if builder_count >= 1 and achievements.unlock("crt_builder_exists", builder_count) then
        show_achievement_toast("crt_builder_exists")
        unlocked_any = true
    end

    -- 3. Evaluate upgrade achievements
    if evaluate_upgrade_achievements() then
        unlocked_any = true
    end

    -- 4. Evaluate time achievements
    if achievements.get_game_time and achievements.unlock then
        local game_time = achievements.get_game_time() or 0
        local defs = achievements.get_all and achievements.get_all() or {}

        if defs.time_5min and achievements.unlock("time_5min", game_time) then
            show_achievement_toast("time_5min")
            unlocked_any = true
        end

        if defs.time_15min and achievements.unlock("time_15min", game_time) then
            show_achievement_toast("time_15min")
            unlocked_any = true
        end
    end

    -- Save if any achievements were newly unlocked
    if unlocked_any then
        achievement_listener.request_save()
    end

    print(string.format("Achievement refresh complete - %s new unlocks", unlocked_any and "found" or "no"))
end

-- Evaluate upgrade achievements and unlock if conditions are met
-- Returns true if any achievements were newly unlocked
function evaluate_upgrade_achievements()
    local upgrades = require("idle_game.upgrades")
    if not upgrades or not upgrades.get_all or not upgrades.get_level then
        return false
    end

    local unlocked_any = false

    -- Get all upgrades
    local all_upgrades = upgrades.get_all()

    -- Track total purchases and max level for evaluation
    local total_purchases = 0
    local max_level = 0
    local any_maxed = false

    for upgrade_id, upgrade in pairs(all_upgrades) do
        local level = upgrades.get_level(upgrade_id)
        if level > 0 then
            total_purchases = total_purchases + 1
        end
        if level > max_level then
            max_level = level
        end
        if level >= upgrade.max_level then
            any_maxed = true
        end
    end

    -- Evaluate upgrade achievements

    -- 1. upg_first_purchase: Purchase your first upgrade
    if total_purchases >= 1 and achievements.unlock("upg_first_purchase", total_purchases) then
        show_achievement_toast("upg_first_purchase")
        unlocked_any = true
    end

    -- 2. upg_any_level_5: Get any upgrade to level 5
    if max_level >= 5 and achievements.unlock("upg_any_level_5", max_level) then
        show_achievement_toast("upg_any_level_5")
        unlocked_any = true
    end

    -- 3. upg_any_maxed: Max out any upgrade
    if any_maxed and achievements.unlock("upg_any_maxed", 1) then
        show_achievement_toast("upg_any_maxed")
        unlocked_any = true
    end

    return unlocked_any
end

-- Show achievement unlock toast notification
function show_achievement_toast(achievement_id)
    if not _toast_queue then
        return
    end

    local title = achievements.get_title(achievement_id) or tostring(achievement_id)
    local message = "ACHIEVEMENT: " .. title

    if _toast_queue.push then
        _toast_queue.push(message, { duration = 3.0 })
    elseif _toast_queue.add then
        _toast_queue.add(message, 3.0)
    end
end

-- Evaluate resource-based achievements when resources change
function achievement_listener._evaluate_resource_achievements(resource_key, new_total)
    if not _initialized then
        return
    end

    local unlocked_any = false

    -- Check resource milestone achievements
    if resource_key == "wood" and new_total >= 100 and achievements.unlock("res_wood_100", new_total) then
        show_achievement_toast("res_wood_100")
        unlocked_any = true
    end

    if resource_key == "stone" and new_total >= 100 and achievements.unlock("res_stone_100", new_total) then
        show_achievement_toast("res_stone_100")
        unlocked_any = true
    end

    if resource_key == "gold" and new_total >= 25 and achievements.unlock("res_gold_25", new_total) then
        show_achievement_toast("res_gold_25")
        unlocked_any = true
    end

    -- Check total resource sum achievement when any resource changes
    if resource_key == "wood" or resource_key == "stone" or resource_key == "gold" or resource_key == "food" then
        local resources = require("idle_game.resources")
        local total_resources = (resources.get("wood") or 0) + (resources.get("stone") or 0) +
                               (resources.get("gold") or 0) + (resources.get("food") or 0)

        if total_resources >= 500 and achievements.unlock("res_total_500", total_resources) then
            show_achievement_toast("res_total_500")
            unlocked_any = true
        end
    end

    if unlocked_any then
        achievement_listener.request_save()
    end
end

-- Evaluate cumulative achievements when resources are gained
function achievement_listener._evaluate_cumulative_achievements(resource_type, delta)
    if not _initialized then
        return
    end

    -- TODO: Track cumulative resource gains for "total harvested" achievements
    -- This would require persistent tracking across game sessions
end

-- Evaluate population-based achievements when creature counts change
function achievement_listener._evaluate_population_achievements(counts)
    if not _initialized then
        return
    end

    local unlocked_any = false

    -- Calculate totals - include miners if available
    local total_creatures = (counts.foragers or 0) + (counts.lumberjacks or 0) +
                          (counts.collectors or 0) + (counts.builders or 0) + (counts.miners or 0)

    -- Calculate specialists (non-forager creatures)
    local specialist_count = (counts.lumberjacks or 0) + (counts.collectors or 0) +
                           (counts.builders or 0) + (counts.miners or 0)

    -- Evaluate creature achievements
    if total_creatures >= 25 and achievements.unlock("crt_total_25", total_creatures) then
        show_achievement_toast("crt_total_25")
        unlocked_any = true
    end

    if specialist_count >= 10 and achievements.unlock("crt_specialists_10", specialist_count) then
        show_achievement_toast("crt_specialists_10")
        unlocked_any = true
    end

    if (counts.builders or 0) >= 1 and achievements.unlock("crt_builder_exists", counts.builders or 0) then
        show_achievement_toast("crt_builder_exists")
        unlocked_any = true
    end

    if unlocked_any then
        achievement_listener.request_save()
    end
end

return achievement_listener
