--[[
ASCII Resource Panel Module

Displays resource information (wood, stone, gold, food) in ASCII/text format
at the top of the game screen.
]]

local ascii_resource_panel = {}

-- Panel state
local _tile_size = 20
local _screen_w = 0
local _screen_h = 0
local _initialized = false

-- Resource display tracking
local _prev_totals = { food = 0, wood = 0, stone = 0, gold = 0 }
local _accum_dt = 0
local _rates = { food = 0, wood = 0, stone = 0, gold = 0 }

-- Initialize the resource panel with screen dimensions
function ascii_resource_panel.init(tile_size, screen_w, screen_h)
    if not tile_size or not screen_w or not screen_h then
        error("ascii_resource_panel.init: all parameters required")
    end

    _tile_size = tile_size
    _screen_w = screen_w
    _screen_h = screen_h
    _initialized = true

    -- Reset tracking state
    _prev_totals = { food = 0, wood = 0, stone = 0, gold = 0 }
    _accum_dt = 0
    _rates = { food = 0, wood = 0, stone = 0, gold = 0 }

    print(string.format("[ASCII Resource Panel] Initialized: %dx%d, tile_size=%d",
          screen_w, screen_h, tile_size))
end

-- Get the panel rectangle (fixed position at top of screen)
function ascii_resource_panel.get_rect()
    if not _initialized then
        error("ascii_resource_panel not initialized")
    end

    -- Fixed rect: x=0, y=0, w=10*TILE_SIZE, h=6*TILE_SIZE
    return {
        x = 0,
        y = 0,
        w = 10 * _tile_size,
        h = 6 * _tile_size
    }
end

-- Update panel state and calculate resource rates
function ascii_resource_panel.update(dt, resources_module)
    if not _initialized then return end
    if not dt or not resources_module then return end

    _accum_dt = _accum_dt + dt

    -- Calculate rates every second
    if _accum_dt >= 1.0 then
        for resource_type, prev_total in pairs(_prev_totals) do
            local current_total = resources_module.get(resource_type)
            _rates[resource_type] = (current_total - prev_total) / _accum_dt
            _prev_totals[resource_type] = current_total
        end
        _accum_dt = 0
    end
end

-- Draw the resource panel (ASCII/text based)
function ascii_resource_panel.draw()
    if not _initialized then return end

    local draw = require("core.draw")
    local resources = require("idle_game.resources")
    local spawner = require("idle_game.spawner")

    -- Try to get ASCII sprites for icons, fallback to text-only
    local icons = {}
    local success, ascii_sprites = pcall(require, "idle_game.ui.ascii_sprites")
    if success and ascii_sprites.ICONS then
        icons = {
            food = ascii_sprites.ICONS.food,
            wood = ascii_sprites.ICONS.wood,
            stone = ascii_sprites.ICONS.stone,
            gold = ascii_sprites.ICONS.gold
        }
    else
        -- Text-only fallback
        icons = {
            food = "F",
            wood = "W",
            stone = "S",
            gold = "G"
        }
    end

    -- Get panel rectangle
    local rect = ascii_resource_panel.get_rect()

    -- Get layer for drawing (try multiple fallbacks)
    local layer_handle = layers and layers.ui
    if not layer_handle then
        -- Try alternative layer access patterns
        layer_handle = _G.layers and _G.layers.ui
        if not layer_handle then
            -- If no UI layer available, skip drawing
            return
        end
    end

    -- Colors (fallback if not defined globally)
    local white = WHITE or (Col and Col(255, 255, 255, 255)) or { r = 255, g = 255, b = 255, a = 255 }
    local gray = GRAY or (Col and Col(128, 128, 128, 255)) or { r = 128, g = 128, b = 128, a = 255 }

    -- Draw border
    local border_thickness = 2
    -- Top border
    draw.rectangle(layer_handle, {
        x = rect.x,
        y = rect.y,
        width = rect.w,
        height = border_thickness,
        color = white
    })
    -- Bottom border
    draw.rectangle(layer_handle, {
        x = rect.x,
        y = rect.y + rect.h - border_thickness,
        width = rect.w,
        height = border_thickness,
        color = white
    })
    -- Left border
    draw.rectangle(layer_handle, {
        x = rect.x,
        y = rect.y,
        width = border_thickness,
        height = rect.h,
        color = white
    })
    -- Right border
    draw.rectangle(layer_handle, {
        x = rect.x + rect.w - border_thickness,
        y = rect.y,
        width = border_thickness,
        height = rect.h,
        color = white
    })

    -- Header text
    local header_y = rect.y + _tile_size * 0.3
    draw.textPro(layer_handle, {
        text = "Resources",
        x = rect.x + _tile_size * 0.2,
        y = header_y,
        fontSize = 14,
        color = white
    })

    -- Resource rows
    local resources_list = {
        { type = resources.FOOD, name = "Food", icon = icons.food },
        { type = resources.WOOD, name = "Wood", icon = icons.wood },
        { type = resources.STONE, name = "Stone", icon = icons.stone },
        { type = resources.GOLD, name = "Gold", icon = icons.gold }
    }

    local row_y = header_y + _tile_size * 0.6
    local row_height = _tile_size * 0.4

    for i, resource_info in ipairs(resources_list) do
        local amount = resources.get(resource_info.type)
        local rate = _rates[resource_info.type] or 0

        -- Format rate display
        local rate_text = ""
        if rate > 0 then
            rate_text = string.format(" (+%.1f/s)", rate)
        end

        -- Resource text with icon: "♦ Food: 45 (+0.5/s)"
        local resource_text = string.format("%s %s: %d%s", resource_info.icon or "", resource_info.name, amount, rate_text)

        draw.textPro(layer_handle, {
            text = resource_text,
            x = rect.x + _tile_size * 0.2,
            y = row_y + (i - 1) * row_height,
            fontSize = 12,
            color = white
        })
    end

    -- Foragers count
    local forager_count = spawner.getForagerCount()
    local forager_y = row_y + #resources_list * row_height + _tile_size * 0.1

    draw.textPro(layer_handle, {
        text = string.format("Foragers: %d", forager_count),
        x = rect.x + _tile_size * 0.2,
        y = forager_y,
        fontSize = 12,
        color = gray
    })
end

-- Test if a point hits the resource panel
-- @return table: {consumed=boolean} - consumed=true for clicks inside panel rect
function ascii_resource_panel.hit_test(x, y)
    if not _initialized then
        return {consumed = false}
    end
    if not x or not y then
        return {consumed = false}
    end

    local rect = ascii_resource_panel.get_rect()
    local inside_panel = x >= rect.x and x < rect.x + rect.w and
                        y >= rect.y and y < rect.y + rect.h

    return {consumed = inside_panel}
end

-- Get current resource rates for external use
function ascii_resource_panel.get_rates()
    return _rates
end

-- Check if the panel is initialized
function ascii_resource_panel.is_initialized()
    return _initialized
end

return ascii_resource_panel