--[[
ASCII Upgrade Panel Module

Displays upgrade information in ASCII/text format, showing available upgrades,
current levels, costs, and affordability status.
]]

local ascii_upgrade_panel = {}
local panel_model = require("idle_game.ui.ascii_upgrade_panel_model")

-- Panel state
local _tile_size = 20
local _screen_w = 0
local _screen_h = 0
local _initialized = false

-- Panel layout configuration
local _panel_x = 0
local _panel_y = 0
local _panel_w = 0
local _panel_h = 0

-- Upgrade display state
local _scroll_offset = 0
local _max_visible_upgrades = 8
local _selected_upgrade = nil
local _upgrade_list = {}

-- Initialize the upgrade panel with screen dimensions
function ascii_upgrade_panel.init(tile_size, screen_w, screen_h)
    if not tile_size or not screen_w or not screen_h then
        error("ascii_upgrade_panel.init: all parameters required")
    end

    _tile_size = tile_size
    _screen_w = screen_w
    _screen_h = screen_h
    _initialized = true

    -- Calculate panel dimensions and position
    -- Position as right sidebar: x=SCREEN_W-UI_SIDEBAR_W, y=0, w=UI_SIDEBAR_W, h=SCREEN_H
    local UI_SIDEBAR_W = _tile_size * 12  -- Match sim_scene sidebar width
    _panel_x = _screen_w - UI_SIDEBAR_W
    _panel_y = 0
    _panel_w = UI_SIDEBAR_W
    _panel_h = _screen_h

    -- Reset state
    _scroll_offset = 0
    _selected_upgrade = nil
    _upgrade_list = {}

    print(string.format("[ASCII Upgrade Panel] Initialized: %dx%d at (%d,%d), tile_size=%d",
          _panel_w, _panel_h, _panel_x, _panel_y, tile_size))
end

-- Get the panel rectangle
function ascii_upgrade_panel.get_rect()
    if not _initialized then
        error("ascii_upgrade_panel not initialized")
    end

    return {
        x = _panel_x,
        y = _panel_y,
        w = _panel_w,
        h = _panel_h
    }
end

-- Update panel state with current upgrade data
function ascii_upgrade_panel.update(dt, upgrades_module, resources_module)
    if not _initialized then return end
    if not upgrades_module then return end

    -- Build current upgrade list with affordability status
    _upgrade_list = {}

    local all_upgrades = upgrades_module.get_all()
    for upgrade_id, upgrade_def in pairs(all_upgrades) do
        local current_level = upgrades_module.get_level(upgrade_id)
        local cost = upgrades_module.get_cost(upgrade_id)
        local can_afford = false

        if resources_module and current_level < upgrade_def.max_level then
            can_afford = upgrades_module.can_afford(upgrade_id, resources_module)
        end

        local upgrade_info = {
            id = upgrade_id,
            name = upgrade_def.name,
            description = upgrade_def.description,
            current_level = current_level,
            max_level = upgrade_def.max_level,
            cost = cost,
            can_afford = can_afford,
            is_maxed = (current_level >= upgrade_def.max_level)
        }

        table.insert(_upgrade_list, upgrade_info)
    end

    -- Sort upgrades by affordability, then by name
    table.sort(_upgrade_list, function(a, b)
        if a.can_afford ~= b.can_afford then
            return a.can_afford and not b.can_afford
        end
        return a.name < b.name
    end)
end

-- Draw the upgrade panel (ASCII/text based)
function ascii_upgrade_panel.draw()
    if not _initialized then return end

    local draw = require("core.draw")

    -- Get panel rectangle
    local rect = ascii_upgrade_panel.get_rect()

    -- Get layer for drawing (try multiple fallbacks)
    local layer_handle = layers and layers.ui
    if not layer_handle then
        layer_handle = _G.layers and _G.layers.ui
        if not layer_handle then
            return
        end
    end

    -- Colors (fallback if not defined globally)
    local white = WHITE or (Col and Col(255, 255, 255, 255)) or { r = 255, g = 255, b = 255, a = 255 }
    local gray = GRAY or (Col and Col(128, 128, 128, 255)) or { r = 128, g = 128, b = 128, a = 255 }
    local green = GREEN or (Col and Col(0, 255, 0, 255)) or { r = 0, g = 255, b = 0, a = 255 }
    local red = RED or (Col and Col(255, 0, 0, 255)) or { r = 255, g = 0, b = 0, a = 255 }

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
        text = "Upgrades",
        x = rect.x + _tile_size * 0.2,
        y = header_y,
        fontSize = 14,
        color = white
    })

    -- Get visible upgrades for current scroll position
    local visible_upgrades = ascii_upgrade_panel.get_visible_upgrades()

    -- Draw upgrade rows
    local row_y = header_y + _tile_size * 0.6
    local row_height = _tile_size * 2  -- Each upgrade takes 2 tiles height

    for i, upgrade in ipairs(visible_upgrades) do
        local y_pos = row_y + (i - 1) * row_height

        -- Upgrade name and level
        local level_text = ""
        if upgrade.is_maxed then
            level_text = " (MAX)"
        else
            level_text = string.format(" (Lv %d/%d)", upgrade.current_level, upgrade.max_level)
        end

        local name_text = upgrade.name .. level_text
        draw.textPro(layer_handle, {
            text = name_text,
            x = rect.x + _tile_size * 0.2,
            y = y_pos,
            fontSize = 12,
            color = white
        })

        -- Cost and button (on second line)
        local button_y = y_pos + _tile_size * 0.5

        if upgrade.is_maxed then
            -- Show [MAX] for maxed upgrades
            draw.textPro(layer_handle, {
                text = "[MAX]",
                x = rect.x + _tile_size * 0.2,
                y = button_y,
                fontSize = 11,
                color = gray
            })
        else
            -- Format cost text
            local cost_parts = {}
            for resource, amount in pairs(upgrade.cost) do
                table.insert(cost_parts, string.format("%d %s", amount, resource))
            end
            local cost_text = "Cost: " .. table.concat(cost_parts, ", ")

            -- Show cost
            draw.textPro(layer_handle, {
                text = cost_text,
                x = rect.x + _tile_size * 0.2,
                y = button_y,
                fontSize = 10,
                color = gray
            })

            -- Show button state
            local button_text = ""
            local button_color = white
            if upgrade.can_afford then
                button_text = "[BUY]"
                button_color = green
            else
                button_text = "[—]"
                button_color = red
            end

            draw.textPro(layer_handle, {
                text = button_text,
                x = rect.x + rect.w - _tile_size * 1.5,
                y = button_y,
                fontSize = 11,
                color = button_color
            })
        end
    end

    -- Draw scroll indicators if needed
    local scroll_info = ascii_upgrade_panel.get_scroll_info()
    if scroll_info.total_upgrades > scroll_info.visible_upgrades then
        local indicator_x = rect.x + rect.w - _tile_size * 0.5

        -- Up arrow if can scroll up
        if scroll_info.can_scroll_up then
            draw.textPro(layer_handle, {
                text = "↑",
                x = indicator_x,
                y = header_y + _tile_size * 0.5,
                fontSize = 12,
                color = white
            })
        end

        -- Down arrow if can scroll down
        if scroll_info.can_scroll_down then
            draw.textPro(layer_handle, {
                text = "↓",
                x = indicator_x,
                y = rect.y + rect.h - _tile_size,
                fontSize = 12,
                color = white
            })
        end
    end
end

-- Handle scroll input for upgrade list
function ascii_upgrade_panel.scroll_by_wheel(wheel_delta)
    if not _initialized then return end

    local max_offset = math.max(0, #_upgrade_list - _max_visible_upgrades)

    -- Scroll up (negative delta) or down (positive delta)
    _scroll_offset = _scroll_offset + wheel_delta
    _scroll_offset = math.max(0, math.min(_scroll_offset, max_offset))
end

-- Test if a point hits the upgrade panel
function ascii_upgrade_panel.hit_test(x, y)
    if not _initialized then return false end
    if not x or not y then return false end

    local rect = ascii_upgrade_panel.get_rect()
    return x >= rect.x and x < rect.x + rect.w and
           y >= rect.y and y < rect.y + rect.h
end

-- Handle click input to select/purchase upgrades
function ascii_upgrade_panel.handle_click(x, y, upgrades_module, resources_module)
    if not ascii_upgrade_panel.hit_test(x, y) then
        return false
    end

    if not _initialized or not upgrades_module or not resources_module then
        return false
    end

    -- Map click to upgrade/action using the shared model
    local rect = ascii_upgrade_panel.get_rect()
    local row_height = _tile_size * 2  -- Each upgrade takes 2 tiles height
    local buy_w = _tile_size * 3  -- Rightmost buy region width
    local ids_sorted = {}
    for _, upgrade in ipairs(_upgrade_list) do
        table.insert(ids_sorted, upgrade.id)
    end

    local hit = panel_model.hit_test(x, y, rect, 0, row_height, buy_w, _scroll_offset, ids_sorted)
    if hit.action == "buy" and hit.id then
        local target = nil
        for _, upgrade in ipairs(_upgrade_list) do
            if upgrade.id == hit.id then
                target = upgrade
                break
            end
        end

        -- Attempt to purchase the upgrade only when clicking the buy region
        if target and target.can_afford and not target.is_maxed then
            local success = upgrades_module.purchase(hit.id, resources_module)
            if success then
                print(string.format("[ASCII Upgrade Panel] Purchased: %s (Level %d)",
                      target.name, target.current_level + 1))
                return true
            end
        end
    end

    return false
end

-- Get visible upgrade count for rendering
function ascii_upgrade_panel.get_visible_upgrades()
    if not _initialized then return {} end

    local visible = {}
    local start_index = _scroll_offset + 1
    local end_index = math.min(start_index + _max_visible_upgrades - 1, #_upgrade_list)

    for i = start_index, end_index do
        table.insert(visible, _upgrade_list[i])
    end

    return visible
end

-- Get current scroll position info
function ascii_upgrade_panel.get_scroll_info()
    return {
        offset = _scroll_offset,
        total_upgrades = #_upgrade_list,
        visible_upgrades = _max_visible_upgrades,
        can_scroll_up = _scroll_offset > 0,
        can_scroll_down = _scroll_offset < (#_upgrade_list - _max_visible_upgrades)
    }
end

-- Check if the panel is initialized
function ascii_upgrade_panel.is_initialized()
    return _initialized
end

-- Get panel configuration for testing
function ascii_upgrade_panel.get_config()
    return {
        tile_size = _tile_size,
        screen_w = _screen_w,
        screen_h = _screen_h,
        panel_rect = ascii_upgrade_panel.get_rect(),
        max_visible = _max_visible_upgrades
    }
end

return ascii_upgrade_panel
