--[[
UI Layout Module

Provides grid-aligned screen dimensions and panel rectangle calculations
for ASCII UI rendering. Headless-safe module.
]]

local ui_layout = {}

-- Minimum size validation - reject rects smaller than 3*tile_size in any dimension
local function validate_rect_size(rect, tile_size)
    local min_size = 3 * tile_size
    if rect.w < min_size or rect.h < min_size then
        error(string.format("Rectangle size validation failed: %dx%d is smaller than minimum %dx%d",
              rect.w, rect.h, min_size, min_size))
    end
    return rect
end

-- Calculate aligned screen dimensions based on tile size and engine dimensions
-- tile_size: size of a single tile/character in pixels
-- engine_w, engine_h: raw engine/window dimensions in pixels
-- Returns: {width = screen_w, height = screen_h} aligned to tile grid
function ui_layout.aligned_screen(tile_size, engine_w, engine_h)
    if not tile_size or tile_size <= 0 then
        error("tile_size must be positive")
    end
    if not engine_w or not engine_h then
        error("engine dimensions required")
    end

    -- Align screen dimensions to tile boundaries
    local screen_w = math.floor(engine_w / tile_size) * tile_size
    local screen_h = math.floor(engine_h / tile_size) * tile_size

    return {
        width = screen_w,
        height = screen_h
    }
end

-- Calculate resource panel rectangle position and size
-- Returns: {x = x, y = y, w = width, h = height}
function ui_layout.resource_panel_rect(tile_size, screen_w, screen_h)
    if not tile_size or not screen_w or not screen_h then
        error("All parameters required: tile_size, screen_w, screen_h")
    end

    -- Resource panel at top of screen
    local panel_height = tile_size * 3  -- 3 tiles high
    local panel_width = screen_w        -- Full width

    local rect = {
        x = 0,
        y = 0,
        w = panel_width,
        h = panel_height
    }

    return validate_rect_size(rect, tile_size)
end

-- Calculate sidebar rectangle position and size
-- Returns: {x = x, y = y, w = width, h = height}
function ui_layout.sidebar_rect(tile_size, screen_w, screen_h)
    if not tile_size or not screen_w or not screen_h then
        error("All parameters required: tile_size, screen_w, screen_h")
    end

    local resource_panel_h = tile_size * 3  -- Resource panel height
    local sidebar_width = tile_size * 12    -- 12 tiles wide
    local sidebar_height = screen_h - resource_panel_h  -- Remaining height

    local rect = {
        x = screen_w - sidebar_width,
        y = resource_panel_h,
        w = sidebar_width,
        h = sidebar_height
    }

    return validate_rect_size(rect, tile_size)
end

-- Calculate toast notification rectangles
-- Returns array of {x, y, w, h} rectangles for toast positioning
function ui_layout.toast_rects(tile_size, screen_w, screen_h, toast_count)
    if not tile_size or not screen_w or not screen_h then
        error("All parameters required: tile_size, screen_w, screen_h")
    end

    toast_count = toast_count or 3  -- Default to 3 toast slots
    local toasts = {}

    local toast_width = tile_size * 15   -- 15 tiles wide
    local toast_height = tile_size * 3   -- 3 tiles high (minimum size requirement)
    local spacing = tile_size            -- 1 tile spacing between toasts

    -- Position toasts in upper right, below resource panel
    local resource_panel_h = tile_size * 3
    local start_x = screen_w - toast_width - tile_size  -- 1 tile margin from edge
    local start_y = resource_panel_h + tile_size        -- 1 tile below resource panel

    for i = 1, toast_count do
        local toast_rect = {
            x = start_x,
            y = start_y + (i - 1) * (toast_height + spacing),
            w = toast_width,
            h = toast_height
        }
        table.insert(toasts, validate_rect_size(toast_rect, tile_size))
    end

    return toasts
end

-- Get the game area rectangle (area not occupied by UI panels)
-- Returns: {x = x, y = y, w = width, h = height}
function ui_layout.game_area_rect(tile_size, screen_w, screen_h)
    if not tile_size or not screen_w or not screen_h then
        error("All parameters required: tile_size, screen_w, screen_h")
    end

    local resource_panel_h = tile_size * 3
    local sidebar_w = tile_size * 12

    local rect = {
        x = 0,
        y = resource_panel_h,
        w = screen_w - sidebar_w,
        h = screen_h - resource_panel_h
    }

    return validate_rect_size(rect, tile_size)
end

return ui_layout