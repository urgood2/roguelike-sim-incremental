--[[
ASCII Border Module

Provides border layout calculations and drawing functions for ASCII UI panels.
Core function: border.layout - returns tiles, pixels, interior from rect specification.
]]

local ascii_border = {}

-- Border style configuration  
local BORDER_STYLES = {
    simple = {
        top_left = "+", top = "-", top_right = "+",
        left = "|", right = "|", 
        bottom_left = "+", bottom = "-", bottom_right = "+"
    },
    double = {
        top_left = "╔", top = "═", top_right = "╗",
        left = "║", right = "║",
        bottom_left = "╚", bottom = "═", bottom_right = "╝"
    }
}

-- Default configuration
local DEFAULT_STYLE = "simple"
local DEFAULT_THICKNESS = 1

-- CORE FUNCTION: Border layout calculation  
-- Returns tiles, pixels, interior from rect specification
function ascii_border.layout(rect_spec, tile_size, border_config)
    if not rect_spec or not tile_size then
        error("ascii_border.layout: rect_spec and tile_size required")
    end

    -- Handle optional border configuration
    border_config = border_config or {}
    local thickness = border_config.thickness or DEFAULT_THICKNESS

    -- Validate input rectangle specification
    if not rect_spec.x or not rect_spec.y or not rect_spec.w or not rect_spec.h then
        error("ascii_border.layout: rect_spec must have x, y, w, h fields")
    end

    -- Calculate border dimensions in tiles
    local border_tiles = {
        thickness = thickness,
        total_w = math.ceil(rect_spec.w / tile_size),
        total_h = math.ceil(rect_spec.h / tile_size),
        left = thickness,
        right = thickness, 
        top = thickness,
        bottom = thickness
    }

    -- Calculate border dimensions in pixels
    local border_pixels = {
        thickness = thickness * tile_size,
        total_w = border_tiles.total_w * tile_size,
        total_h = border_tiles.total_h * tile_size,
        left = thickness * tile_size,
        right = thickness * tile_size,
        top = thickness * tile_size,
        bottom = thickness * tile_size
    }

    -- Calculate interior rectangle (content area after border)
    local interior = {
        x = rect_spec.x + border_pixels.left,
        y = rect_spec.y + border_pixels.top,
        w = rect_spec.w - border_pixels.left - border_pixels.right,
        h = rect_spec.h - border_pixels.top - border_pixels.bottom
    }

    -- Ensure interior has positive dimensions
    interior.w = math.max(0, interior.w)
    interior.h = math.max(0, interior.h)

    -- Interior dimensions in tiles
    interior.tiles_w = math.floor(interior.w / tile_size)
    interior.tiles_h = math.floor(interior.h / tile_size)

    return {
        tiles = border_tiles,
        pixels = border_pixels, 
        interior = interior,
        style = border_config.style or DEFAULT_STYLE,
        original_rect = rect_spec
    }
end

-- Validate rectangle alignment with borders
function ascii_border.validate_alignment(rect_spec, tile_size, border_config)
    if not rect_spec or not tile_size or tile_size <= 0 then
        return false
    end

    if rect_spec.x == nil or rect_spec.y == nil or rect_spec.w == nil or rect_spec.h == nil then
        return false
    end

    border_config = border_config or {}
    local thickness = border_config.thickness or DEFAULT_THICKNESS
    local min_border_pixels = thickness * 2 * tile_size

    -- Check if rectangle is large enough for border
    if rect_spec.w < min_border_pixels or rect_spec.h < min_border_pixels then
        return false
    end

    -- Require alignment to tile grid
    local function is_multiple(value)
        return value % tile_size == 0
    end

    return is_multiple(rect_spec.x)
        and is_multiple(rect_spec.y)
        and is_multiple(rect_spec.w)
        and is_multiple(rect_spec.h)
end

-- Check minimum size requirements
function ascii_border.validate_minimum_size(rect_spec, tile_size, border_config)
    local layout = ascii_border.layout(rect_spec, tile_size, border_config)

    -- Minimum content area: 1x1 tile
    return layout.interior.w >= tile_size and layout.interior.h >= tile_size
end

-- Draw border using 9-slice sprite tiles
-- Headless-safe: returns early if drawing system is unavailable
function ascii_border.draw(layout_result)
    if not layout_result or not layout_result.original_rect or not layout_result.tiles then
        return false
    end

    -- Headless-safe checks: return early if drawing system unavailable
    if not command_buffer or not layers or not layers.sprites then
        return true  -- Success (no-op in headless environment)
    end

    local config = require("idle_game.config")
    local tile_size = config.TILE_SIZE or 20

    -- Get border style and sprites
    local style = ascii_border.get_style(layout_result.style)
    if not style then
        return false
    end

    -- Simple sprite mapping for dungeon_437 tileset border characters
    -- Using available symbols that represent border elements
    local BORDER_SPRITES = {
        ["+"] = "d437_043_symbol_43.png",   -- Plus symbol for corners
        ["-"] = "d437_045_symbol_45.png",   -- Minus/dash for horizontal borders
        ["|"] = "d437_124_pipe.png",        -- Pipe symbol for vertical borders
        ["╔"] = "d437_043_symbol_43.png",   -- Corner (fallback to +)
        ["═"] = "d437_045_symbol_45.png",   -- Double horizontal (fallback to -)
        ["╗"] = "d437_043_symbol_43.png",   -- Corner (fallback to +)
        ["║"] = "d437_124_pipe.png",        -- Double vertical (fallback to |)
        ["╚"] = "d437_043_symbol_43.png",   -- Corner (fallback to +)
        ["╝"] = "d437_043_symbol_43.png"    -- Corner (fallback to +)
    }

    local rect = layout_result.original_rect
    local thickness = layout_result.tiles.thickness

    -- 9-slice border positions
    local positions = {
        -- Corners
        {char = style.top_left, x = rect.x, y = rect.y},
        {char = style.top_right, x = rect.x + rect.w - tile_size, y = rect.y},
        {char = style.bottom_left, x = rect.x, y = rect.y + rect.h - tile_size},
        {char = style.bottom_right, x = rect.x + rect.w - tile_size, y = rect.y + rect.h - tile_size}
    }

    -- Top and bottom edges
    for i = 1, math.floor(rect.w / tile_size) - 2 do
        table.insert(positions, {
            char = style.top,
            x = rect.x + i * tile_size,
            y = rect.y
        })
        table.insert(positions, {
            char = style.bottom,
            x = rect.x + i * tile_size,
            y = rect.y + rect.h - tile_size
        })
    end

    -- Left and right edges
    for i = 1, math.floor(rect.h / tile_size) - 2 do
        table.insert(positions, {
            char = style.left,
            x = rect.x,
            y = rect.y + i * tile_size
        })
        table.insert(positions, {
            char = style.right,
            x = rect.x + rect.w - tile_size,
            y = rect.y + i * tile_size
        })
    end

    -- Default colors
    local white = WHITE or { r = 255, g = 255, b = 255, a = 255 }
    local default_color = type(white) == "table" and white
                         or { r = 255, g = 255, b = 255, a = 255 }

    -- Draw each border segment
    for _, pos in ipairs(positions) do
        local sprite_name = BORDER_SPRITES[pos.char]
        if sprite_name then
            command_buffer.queueDrawSpriteTopLeft(
                layers.sprites,
                function(c)
                    c.spriteName = sprite_name
                    c.x = pos.x
                    c.y = pos.y
                    c.dstW = tile_size
                    c.dstH = tile_size
                    c.tint = default_color
                end,
                1,  -- Layer 1: UI border above terrain
                layer.DrawCommandSpace and layer.DrawCommandSpace.World or 0
            )
        end
    end

    return true
end

-- Get available border styles
function ascii_border.get_styles()
    local styles = {}
    for style_name, _ in pairs(BORDER_STYLES) do
        table.insert(styles, style_name)
    end
    return styles
end

-- Get style definition  
function ascii_border.get_style(style_name)
    return BORDER_STYLES[style_name or DEFAULT_STYLE]
end

return ascii_border
