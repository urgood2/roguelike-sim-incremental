local achievements = {}

-- Achievement definitions (4 resource + 3 upgrade + 3 creature + 2 time = 12 total)
local ACHIEVEMENTS = {
    -- 4 resource achievements
    res_wood_100 = {
        id = "res_wood_100",
        title = "Wood Hoarder",
        description = "Reach 100 total wood",
        kind = "resource_total",
        threshold = 100,
        unlocked = false
    },
    res_stone_100 = {
        id = "res_stone_100",
        title = "Stone Stockpile",
        description = "Reach 100 total stone",
        kind = "resource_total",
        threshold = 100,
        unlocked = false
    },
    res_gold_25 = {
        id = "res_gold_25",
        title = "Shiny Things",
        description = "Reach 25 total gold",
        kind = "resource_total",
        threshold = 25,
        unlocked = false
    },
    res_total_500 = {
        id = "res_total_500",
        title = "Full Pantry",
        description = "Reach 500 total resources",
        kind = "resource_sum",
        threshold = 500,
        unlocked = false
    },
    -- 3 creature achievements
    crt_total_25 = {
        id = "crt_total_25",
        title = "Growing Crew",
        description = "Have 25 or more total creatures",
        kind = "creature_total",
        threshold = 25,
        unlocked = false
    },
    crt_specialists_10 = {
        id = "crt_specialists_10",
        title = "Specialist Force",
        description = "Have 10 or more specialist creatures",
        kind = "creature_specialists",
        threshold = 10,
        unlocked = false
    },
    crt_builder_exists = {
        id = "crt_builder_exists",
        title = "Master Builder",
        description = "Recruit your first Builder",
        kind = "creature_builder",
        threshold = 1,
        unlocked = false
    },
    -- 3 upgrade achievements
    upg_first_purchase = {
        id = "upg_first_purchase",
        title = "Stepping Up",
        description = "Purchase your first upgrade",
        kind = "upgrade_first",
        threshold = 1,
        unlocked = false
    },
    upg_any_level_5 = {
        id = "upg_any_level_5",
        title = "Dedicated Upgrader",
        description = "Get any upgrade to level 5",
        kind = "upgrade_level",
        threshold = 5,
        unlocked = false
    },
    upg_any_maxed = {
        id = "upg_any_maxed",
        title = "Perfectionist",
        description = "Max out any upgrade",
        kind = "upgrade_maxed",
        threshold = 1,
        unlocked = false
    },
    -- 2 time achievements
    time_5min = {
        id = "time_5min",
        title = "Getting Started",
        description = "Play for 5 minutes",
        kind = "time_played",
        threshold = 300, -- 5 minutes in seconds
        unlocked = false
    },
    time_15min = {
        id = "time_15min",
        title = "Dedicated Player",
        description = "Play for 15 minutes",
        kind = "time_played",
        threshold = 900, -- 15 minutes in seconds
        unlocked = false
    }
}

-- Unlocked achievements storage
local _unlocked = {}

-- Game time tracking for time achievements
local _game_time = 0

-- Initialize achievements system
function achievements.init()
    _unlocked = {}
    _game_time = 0
    -- Mark all achievements as locked initially
    for id, achievement in pairs(ACHIEVEMENTS) do
        achievement.unlocked = false
    end
end

-- Update achievements system (called each frame with dt)
function achievements.update(dt)
    if not dt or dt < 0 then return end

    -- Track game time for time achievements
    _game_time = _game_time + dt
end

-- Check and unlock an achievement if conditions are met
-- Returns true if newly unlocked, false if already unlocked or conditions not met
function achievements.unlock(achievement_id, current_value)
    local achievement = ACHIEVEMENTS[achievement_id]
    if not achievement then
        error("Unknown achievement: " .. tostring(achievement_id))
    end

    -- Already unlocked
    if achievement.unlocked or _unlocked[achievement_id] then
        return false
    end

    -- Check if threshold is met
    if current_value >= achievement.threshold then
        achievement.unlocked = true
        _unlocked[achievement_id] = true
        return true
    end

    return false
end

-- Check if an achievement is unlocked
function achievements.is_unlocked(achievement_id)
    local achievement = ACHIEVEMENTS[achievement_id]
    if not achievement then
        error("Unknown achievement: " .. tostring(achievement_id))
    end

    return achievement.unlocked or (_unlocked[achievement_id] == true)
end

-- Get list of all unlocked achievement IDs
function achievements.get_unlocked_ids()
    local unlocked_ids = {}
    for id, achievement in pairs(ACHIEVEMENTS) do
        if achievement.unlocked or _unlocked[id] then
            table.insert(unlocked_ids, id)
        end
    end
    table.sort(unlocked_ids)
    return unlocked_ids
end

-- Get achievement title
function achievements.get_title(achievement_id)
    local achievement = ACHIEVEMENTS[achievement_id]
    if not achievement then
        return nil  -- Return nil for unknown achievement IDs
    end

    return achievement.title
end

-- Serialize achievements state for persistence
function achievements.serialize()
    local state = {
        unlocked = {},
        game_time = _game_time
    }

    for id, achievement in pairs(ACHIEVEMENTS) do
        if achievement.unlocked or _unlocked[id] then
            state.unlocked[id] = true
        end
    end

    return state
end

-- Deserialize achievements state from persistence
-- Restores state from serialized table, ignoring unknown achievement IDs
function achievements.deserialize(state)
    if not state then
        achievements.init()
        return
    end

    -- Initialize clean state
    _unlocked = {}
    _game_time = state.game_time or 0

    -- Only restore known achievement IDs, ignore unknown/obsolete ones
    local source_unlocked = state.unlocked or {}
    for achievement_id, is_unlocked in pairs(source_unlocked) do
        if ACHIEVEMENTS[achievement_id] then
            -- Only include known achievement IDs
            _unlocked[achievement_id] = is_unlocked == true
        end
        -- Unknown IDs are silently ignored as per requirement
    end

    -- Update achievement objects with filtered unlocked state
    for id, achievement in pairs(ACHIEVEMENTS) do
        achievement.unlocked = _unlocked[id] == true
    end
end

-- Get all achievement definitions
function achievements.get_all()
    return ACHIEVEMENTS
end

-- Get current game time
function achievements.get_game_time()
    return _game_time
end

return achievements
