--[[
Layout Module - Simplified UI Layout API

Provides a simplified API for UI layout calculations.
This module wraps the more detailed ui_layout functions with the
planned API interface from the planning documents.
]]

local layout = {}

local ui_layout = require("idle_game.ui.ui_layout")

-- Calculate sidebar rectangle position and size
-- Returns: {x = x, y = y, w = width, h = height}
function layout.sidebar_rect(tile_size, screen_w, screen_h)
    return ui_layout.sidebar_rect(tile_size, screen_w, screen_h)
end

-- Calculate aligned screen dimensions
-- Returns: {width = screen_w, height = screen_h}
function layout.aligned_screen(tile_size, engine_w, engine_h)
    return ui_layout.aligned_screen(tile_size, engine_w, engine_h)
end

-- Calculate resource panel rectangle position and size
-- Returns: {x = x, y = y, w = width, h = height}
function layout.resource_panel_rect(tile_size, screen_w, screen_h)
    return ui_layout.resource_panel_rect(tile_size, screen_w, screen_h)
end

-- Calculate toast notification rectangles
-- Returns: array of {x, y, w, h} rectangles
function layout.toast_rects(tile_size, screen_w, screen_h, max_visible)
    return ui_layout.toast_rects(tile_size, screen_w, screen_h, max_visible)
end

return layout