--[[
Achievements Persistence Module

Registers with SaveManager using the collector pattern.
Bridges achievements.lua with the save system.
]]

local AchievementsPersistence = {}

-- Load the achievements system
local achievements = require("idle_game.achievements")
local SaveManager = require("core.save_manager")

-- Debug logging helper
local function log_debug(msg)
    if log_debug then
        log_debug("[AchievementsPersistence] " .. msg)
    else
        print("[AchievementsPersistence] " .. msg)
    end
end

-- Collect achievements state for saving
-- Called by SaveManager when creating a save file
local function collect()
    log_debug("Collecting achievements state for save")

    local state = achievements.serialize()

    log_debug("Collected achievements: " .. #(achievements.get_unlocked_ids()) .. " unlocked")

    return state
end

-- Distribute (restore) achievements state from save data
-- Called by SaveManager when loading a save file
local function distribute(data)
    log_debug("Distributing achievements state from save data")

    if not data then
        log_debug("No achievements save data found, initializing fresh")
        achievements.init()
        return
    end

    achievements.deserialize(data)

    local unlocked_count = #(achievements.get_unlocked_ids())
    log_debug("Restored " .. unlocked_count .. " unlocked achievements")

    -- Log specific unlocked achievements for debugging
    local unlocked_ids = achievements.get_unlocked_ids()
    if #unlocked_ids > 0 then
        log_debug("Unlocked achievements: " .. table.concat(unlocked_ids, ", "))
    end
end

-- Register with SaveManager
SaveManager.register("achievements", {
    collect = collect,
    distribute = distribute,
})

log_debug("Registered with SaveManager")

return AchievementsPersistence