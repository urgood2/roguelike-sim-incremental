--[[
Idle Game Signal Emitters

Provides convenience functions for emitting game-related signals using the hump.signal system.
Handles common idle game events like resource changes, creature counts, etc.
]]

local signals = {}

local signal = require("external.hump.signal")

-- Emit signal for creature count changes
-- @param counts table containing creature counts (e.g., { foragers = 5, lumberjacks = 3 })
function signals.emit(signal_name, data)
    signal.emit(signal_name, data)
end

return signals