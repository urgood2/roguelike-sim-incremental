-- Idle game achievements persistence (SaveManager collector)

local achievements_persistence = {}

local achievements = require("idle_game.achievements")
local SaveManager = require("core.save_manager")

local function collect()
    return achievements.serialize()
end

local function distribute(data)
    achievements.deserialize(data)
end

SaveManager.register("idle_achievements", {
    collect = collect,
    distribute = distribute,
})

return achievements_persistence
