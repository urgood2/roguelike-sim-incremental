-- Toast queue - headless-safe notification system
-- Manages temporary UI notifications with automatic expiration
local toast_queue = {}

-- Toast queue state
local _queue = {}               -- All toasts (buffer)
local _max_visible = 3          -- Max toasts shown at once
local _default_duration = 3.0   -- Default display time (seconds)
local _max_buffer = 32          -- Max total toasts in buffer
local _next_id = 1              -- Unique ID counter for toasts

-- Toast structure:
-- {
--   id = unique_number,
--   text = "message",
--   duration = seconds_to_show,
--   age = current_age_seconds,
--   created_at = os.time()
-- }

--- Initialize toast queue with configuration
--- @param config table Configuration: {max_visible=3, default_duration=3.0, max_buffer=32}
function toast_queue.init(config)
    config = config or {}

    _max_visible = config.max_visible or 3
    _default_duration = config.default_duration or 3.0
    _max_buffer = config.max_buffer or 32

    -- Clear any existing toasts
    _queue = {}
    _next_id = 1

    print(string.format("[TOAST_QUEUE] Initialized: max_visible=%d, default_duration=%.1f, max_buffer=%d",
        _max_visible, _default_duration, _max_buffer))
end

--- Add a new toast to the queue
--- @param text string Toast message text
--- @param options table Optional: {duration=number} or legacy number duration
function toast_queue.push(text, options)
    if not text or text == "" then
        return nil
    end

    -- Support both new {duration=...} and legacy duration number for compatibility
    local duration
    if type(options) == "table" then
        duration = options.duration or _default_duration
    elseif type(options) == "number" then
        duration = options  -- Legacy compatibility
    else
        duration = _default_duration
    end

    -- Buffer cap management: drop oldest entries when max_buffer exceeded
    if #_queue >= _max_buffer then
        -- Remove oldest toast (first in queue)
        table.remove(_queue, 1)
        print(string.format("[TOAST_QUEUE] Buffer cap exceeded, dropped oldest toast"))
    end

    local toast = {
        id = _next_id,
        text = tostring(text),
        duration = duration,
        age = 0,
        created_at = os.time()
    }

    table.insert(_queue, toast)
    _next_id = _next_id + 1

    print(string.format("[TOAST_QUEUE] Added toast #%d: '%s' (duration=%.1f)",
        toast.id, toast.text, toast.duration))

    return toast.id
end

--- Update toast ages and auto-dismiss expired toasts
--- @param dt number Delta time in seconds
function toast_queue.update(dt)
    if not dt or dt <= 0 then
        return
    end

    local removed_count = 0
    local i = 1

    -- Update ages and remove expired toasts
    while i <= #_queue do
        local toast = _queue[i]
        toast.age = toast.age + dt

        -- Check if toast has expired
        if toast.age >= toast.duration then
            print(string.format("[TOAST_QUEUE] Expired toast #%d: '%s' (age=%.1f)",
                toast.id, toast.text, toast.age))
            table.remove(_queue, i)
            removed_count = removed_count + 1
        else
            i = i + 1
        end
    end

    -- Debug log if toasts were removed
    if removed_count > 0 then
        print(string.format("[TOAST_QUEUE] Removed %d expired toasts, %d remaining",
            removed_count, #_queue))
    end
end

--- Get visible toasts for rendering (newest-first)
--- Returns newest-first ordering: visible[1] = newest toast (rendered at bottom)
--- @return table List of visible toasts, newest at index 1
function toast_queue.get_visible()
    local visible = {}
    local count = math.min(#_queue, _max_visible)

    -- Return newest toasts first (from end of queue)
    -- This ensures visible[1] is the newest toast (rendered at bottom)
    for i = 1, count do
        local toast_index = #_queue - i + 1
        local toast = _queue[toast_index]

        -- Create visible toast with progress information
        local visible_toast = {
            id = toast.id,
            text = toast.text,
            age = toast.age,
            duration = toast.duration,
            progress = toast.age / toast.duration  -- 0.0 to 1.0
        }
        table.insert(visible, visible_toast)
    end

    return visible
end

--- Get total number of toasts in buffer (debug/testing)
--- @return number Total toast count
function toast_queue.get_count()
    return #_queue
end

--- Clear all toasts (debug/testing)
function toast_queue.clear()
    local count = #_queue
    _queue = {}
    print(string.format("[TOAST_QUEUE] Cleared %d toasts", count))
end

--- Remove specific toast by ID (debug/testing)
--- @param toast_id number Toast ID to remove
--- @return boolean True if toast was found and removed
function toast_queue.remove(toast_id)
    for i, toast in ipairs(_queue) do
        if toast.id == toast_id then
            table.remove(_queue, i)
            return true
        end
    end
    return false
end

--- Get configuration (debug/testing)
--- @return table Current configuration
function toast_queue.get_config()
    return {
        max_visible = _max_visible,
        default_duration = _default_duration,
        max_buffer = _max_buffer
    }
end

--- Calculate toast layout positions anchored in sidebar with padding
--- @param sidebar_config table Sidebar configuration: {x, y, w, h}
--- @param toast_config table Toast configuration: {w, h, padding}
--- @param visible_toasts table Array of visible toasts
--- @return table Array of positioned toasts with {x, y, w, h, ...toast_data}
function toast_queue.calculate_layout(sidebar_config, toast_config, visible_toasts)
    if not sidebar_config or not toast_config or not visible_toasts then
        return {}
    end

    -- Validate sidebar configuration
    if not sidebar_config.x or not sidebar_config.y or not sidebar_config.w or not sidebar_config.h then
        error("toast_queue.calculate_layout: sidebar_config must have x, y, w, h")
    end

    -- Validate toast configuration
    if not toast_config.w or not toast_config.h then
        error("toast_queue.calculate_layout: toast_config must have w, h")
    end

    local padding = toast_config.padding or 8

    -- Calculate anchor position (top-right of sidebar)
    local anchor_x = sidebar_config.x + sidebar_config.w + padding
    local anchor_y = sidebar_config.y + padding

    local positioned_toasts = {}

    -- Position each visible toast vertically downward from anchor
    for i, toast in ipairs(visible_toasts) do
        local toast_y = anchor_y + (i - 1) * (toast_config.h + padding)

        local positioned_toast = {
            -- Position and size
            x = anchor_x,
            y = toast_y,
            w = toast_config.w,
            h = toast_config.h,

            -- Toast data
            id = toast.id,
            text = toast.text,
            age = toast.age,
            duration = toast.duration,
            progress = toast.progress
        }

        table.insert(positioned_toasts, positioned_toast)
    end

    return positioned_toasts
end

--- Draw positioned toasts with borders and text
--- @param positioned_toasts table Array of positioned toasts with {x, y, w, h, text, progress}
--- @param layer_handle table Layer handle for drawing commands
function toast_queue.draw(positioned_toasts, layer_handle)
    if not positioned_toasts or #positioned_toasts == 0 then
        return
    end

    if not layer_handle then
        -- Try to get UI layer from global context
        layer_handle = (_G.layers and _G.layers.ui) or (layers and layers.ui)
        if not layer_handle then
            -- No layer available for drawing
            return
        end
    end

    -- Color definitions with fallbacks
    local white = WHITE or (Col and Col(255, 255, 255, 255)) or { r = 255, g = 255, b = 255, a = 255 }
    local dark_gray = DARKGRAY or (Col and Col(80, 80, 80, 255)) or { r = 80, g = 80, b = 80, a = 255 }
    local light_gray = LIGHTGRAY or (Col and Col(200, 200, 200, 255)) or { r = 200, g = 200, b = 200, a = 255 }

    for _, toast in ipairs(positioned_toasts) do
        -- Draw background with slight transparency based on progress
        local alpha = math.max(50, 200 - (toast.progress * 150))  -- Fade out as toast expires
        local bg_color = { r = dark_gray.r, g = dark_gray.g, b = dark_gray.b, a = alpha }

        draw.rectangle(layer_handle, {
            x = toast.x,
            y = toast.y,
            width = toast.w,
            height = toast.h,
            color = bg_color
        })

        -- Draw border
        local border_thickness = 1
        draw.rectangle(layer_handle, {
            x = toast.x,
            y = toast.y,
            width = toast.w,
            height = border_thickness,
            color = light_gray
        })
        draw.rectangle(layer_handle, {
            x = toast.x,
            y = toast.y + toast.h - border_thickness,
            width = toast.w,
            height = border_thickness,
            color = light_gray
        })
        draw.rectangle(layer_handle, {
            x = toast.x,
            y = toast.y,
            width = border_thickness,
            height = toast.h,
            color = light_gray
        })
        draw.rectangle(layer_handle, {
            x = toast.x + toast.w - border_thickness,
            y = toast.y,
            width = border_thickness,
            height = toast.h,
            color = light_gray
        })

        -- Draw text centered in toast
        local text_padding = 4
        local text_alpha = math.max(100, 255 - (toast.progress * 155))  -- Fade text as toast expires
        local text_color = { r = white.r, g = white.g, b = white.b, a = text_alpha }

        draw.textPro(layer_handle, {
            text = toast.text,
            x = toast.x + text_padding,
            y = toast.y + (toast.h / 2) - 6,  -- Rough vertical centering
            fontSize = 12,
            color = text_color
        })

        -- Optional: Draw progress bar at bottom
        if toast.progress > 0 then
            local progress_height = 2
            local progress_width = math.floor(toast.w * toast.progress)
            local progress_color = { r = 255, g = 215, b = 0, a = 150 }  -- Gold color

            draw.rectangle(layer_handle, {
                x = toast.x,
                y = toast.y + toast.h - progress_height,
                width = progress_width,
                height = progress_height,
                color = progress_color
            })
        end
    end
end

return toast_queue