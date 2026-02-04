--[[
Toast Renderer Module

Provides a unified interface for displaying toast notifications.
Uses toast_queue for queue management and implements rendering integration.
]]

local toast_renderer = {}

-- Dependencies
local toast_queue = require("idle_game.ui.toast_queue")
local ui_layout = require("idle_game.ui.ui_layout")

-- Toast rendering configuration
local TOAST_CONFIG = {
    w = 200,              -- Toast width in pixels
    h = 32,               -- Toast height in pixels
    padding = 8,          -- Padding between toasts and around text
    max_visible = 3,      -- Maximum visible toasts
    default_duration = 3.0 -- Default display duration in seconds
}

-- Internal state
local _initialized = false
local _screen_width = 0
local _screen_height = 0
local _tile_size = 20

-- Initialize the toast renderer
function toast_renderer.init(tile_size, screen_width, screen_height)
    if not tile_size or not screen_width or not screen_height then
        error("toast_renderer.init: all parameters required")
    end

    _tile_size = tile_size
    _screen_width = screen_width
    _screen_height = screen_height
    _initialized = true

    -- Initialize the underlying toast queue
    toast_queue.init({
        max_visible = TOAST_CONFIG.max_visible,
        default_duration = TOAST_CONFIG.default_duration,
        max_buffer = 32
    })

    print(string.format("[TOAST_RENDERER] Initialized: %dx%d, tile_size=%d",
          screen_width, screen_height, tile_size))
end

-- Add a new toast (compatible with achievement listener interface)
function toast_renderer.add(message, duration)
    if not _initialized then
        print("[TOAST_RENDERER] Warning: not initialized, ignoring toast")
        return
    end

    if not message or message == "" then
        return
    end

    -- Use toast_queue's push method with the expected interface
    local toast_id = toast_queue.push(message, duration)
    return toast_id
end

-- Update toast states (should be called each frame)
function toast_renderer.update(dt)
    if not _initialized then
        return
    end

    toast_queue.update(dt)
end

-- Draw all visible toasts
function toast_renderer.draw()
    if not _initialized then
        return
    end

    -- Get visible toasts from queue
    local visible_toasts = toast_queue.get_visible()
    if #visible_toasts == 0 then
        return
    end

    -- Get sidebar configuration for positioning
    local sidebar_rect = ui_layout.resource_panel_rect(_tile_size, _screen_width, _screen_height)
    if not sidebar_rect then
        -- Fallback positioning if no sidebar
        sidebar_rect = {
            x = _screen_width - 240,
            y = 0,
            w = 240,
            h = _screen_height
        }
    end

    -- Calculate toast positions
    local positioned_toasts = toast_queue.calculate_layout(
        sidebar_rect,
        TOAST_CONFIG,
        visible_toasts
    )

    -- Get layer for drawing
    local layer_handle = layers and layers.ui
    if not layer_handle then
        layer_handle = _G.layers and _G.layers.ui
        if not layer_handle then
            return -- No UI layer available
        end
    end

    -- Draw the positioned toasts
    toast_queue.draw(positioned_toasts, layer_handle)
end

-- Get number of active toasts (for debugging/testing)
function toast_renderer.get_count()
    if not _initialized then
        return 0
    end
    return toast_queue.get_count()
end

-- Clear all toasts (for debugging/testing)
function toast_renderer.clear()
    if not _initialized then
        return
    end
    toast_queue.clear()
end

-- Check if renderer is initialized
function toast_renderer.is_initialized()
    return _initialized
end

-- Get current configuration (for debugging/testing)
function toast_renderer.get_config()
    return {
        toast_config = TOAST_CONFIG,
        screen_width = _screen_width,
        screen_height = _screen_height,
        tile_size = _tile_size,
        initialized = _initialized
    }
end

-- Reinitialize on screen resize
function toast_renderer.on_resize(tile_size, screen_width, screen_height)
    if _initialized then
        toast_renderer.init(tile_size, screen_width, screen_height)
    end
end

return toast_renderer