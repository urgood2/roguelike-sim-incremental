--[[
Queue Module - Simplified Toast Notification API

Provides a simplified API for toast notifications.
This module wraps the more detailed toast_queue functions with the
planned API interface from the planning documents.
]]

local queue = {}

local toast_queue = require("idle_game.ui.toast_queue")

-- Add toast with text and optional duration
-- @param text string Toast message text
-- @param options table Optional configuration: {duration=number}
function queue.push(text, options)
    return toast_queue.push(text, options)
end

-- Initialize the queue with optional configuration
-- @param config table Optional configuration for toast_queue
function queue.init(config)
    return toast_queue.init(config)
end

-- Update queue processing (removes expired toasts)
-- @param dt number Delta time in seconds
function queue.update(dt)
    return toast_queue.update(dt)
end

-- Get visible toasts for rendering
-- @return table Array of visible toasts
function queue.get_visible()
    return toast_queue.get_visible()
end

-- Get total number of queued toasts
-- @return number Total toast count
function queue.get_count()
    return toast_queue.get_count()
end

-- Clear all toasts
function queue.clear()
    return toast_queue.clear()
end

-- Calculate layout for visible toasts
-- @param sidebar_config table Sidebar configuration: {x, y, w, h}
-- @param toast_config table Toast configuration: {w, h, padding}
-- @param visible_toasts table Array of visible toasts
-- @return table Array of positioned toasts
function queue.calculate_layout(sidebar_config, toast_config, visible_toasts)
    return toast_queue.calculate_layout(sidebar_config, toast_config, visible_toasts)
end

-- Draw positioned toasts
-- @param positioned_toasts table Array of positioned toasts
-- @param layer_handle table Layer handle for drawing
function queue.draw(positioned_toasts, layer_handle)
    return toast_queue.draw(positioned_toasts, layer_handle)
end

return queue