-- ASCII Upgrade Panel Model
-- Headless-safe model module for upgrade panel logic
-- Provides deterministic sorting, scroll handling, and hit-test calculations

local model = {}

-- Returns upgrade IDs sorted alphabetically for deterministic ordering
-- @param upgrades_state_or_defs table: upgrade definitions or state object with get_all() method
-- @return table: array of upgrade IDs sorted alphabetically
function model.sorted_ids(upgrades_state_or_defs)
    if not upgrades_state_or_defs then
        return {}
    end

    -- Handle both upgrade state objects and raw definitions
    local upgrades_data = upgrades_state_or_defs
    if type(upgrades_state_or_defs.get_all) == "function" then
        upgrades_data = upgrades_state_or_defs.get_all()
    end

    if not upgrades_data then
        return {}
    end

    -- Collect all upgrade IDs
    local ids = {}
    for upgrade_id, _ in pairs(upgrades_data) do
        table.insert(ids, upgrade_id)
    end

    -- Sort alphabetically for deterministic ordering (never rely on pairs() order)
    table.sort(ids)

    return ids
end

-- Calculates how many rows fit in the given view height
-- @param list_h number: height of the list area in pixels
-- @param row_h number: height of each row in pixels
-- @return number: number of rows that fit (floor division)
function model.view_rows(list_h, row_h)
    if not list_h or not row_h or row_h <= 0 then
        return 0
    end

    return math.floor(list_h / row_h)
end

-- Clamps scroll position to valid range
-- @param scroll_row number: current scroll position
-- @param delta_rows number: scroll delta (positive = down, negative = up)
-- @param view_rows number: number of visible rows
-- @param total_rows number: total number of rows in list
-- @return number: new clamped scroll position
function model.scroll(scroll_row, delta_rows, view_rows, total_rows)
    if not scroll_row or not delta_rows or not view_rows or not total_rows then
        return 0
    end

    local new_scroll = scroll_row + delta_rows
    local max_offset = math.max(0, total_rows - view_rows)

    return math.max(0, math.min(new_scroll, max_offset))
end

-- Determines which row a click landed in
-- @param click_x number: x coordinate of click
-- @param click_y number: y coordinate of click
-- @param rect table: panel rect {x, y, w, h}
-- @param header_h number: height of header area
-- @param row_h number: height of each row
-- @param scroll_row number: current scroll offset
-- @param total_rows number: total number of rows
-- @return table: {in_list=boolean, row_index=number?} where row_index is absolute index (not scrolled)
function model.row_at(click_x, click_y, rect, header_h, row_h, scroll_row, total_rows)
    if not click_x or not click_y or not rect or not header_h or not row_h then
        return {in_list = false}
    end

    -- Check if click is within panel bounds
    if click_x < rect.x or click_x >= rect.x + rect.w or
       click_y < rect.y or click_y >= rect.y + rect.h then
        return {in_list = false}
    end

    -- Check if click is in list area (below header)
    local list_start_y = rect.y + header_h
    if click_y < list_start_y then
        return {in_list = false}
    end

    -- Calculate which row was clicked (relative to list area)
    local relative_y = click_y - list_start_y
    local clicked_row_index = math.floor(relative_y / row_h)

    -- Convert to absolute index accounting for scroll
    local absolute_index = clicked_row_index + scroll_row + 1  -- +1 for 1-based indexing

    -- Validate row exists
    if absolute_index < 1 or absolute_index > total_rows then
        return {in_list = true, row_index = nil}
    end

    return {in_list = true, row_index = absolute_index}
end

-- Complete hit-test returning action information
-- @param click_x number: x coordinate of click
-- @param click_y number: y coordinate of click
-- @param rect table: panel rect {x, y, w, h}
-- @param header_h number: height of header area
-- @param row_h number: height of each row
-- @param buy_w number: width of buy button region (from right edge)
-- @param scroll_row number: current scroll offset
-- @param ids_sorted table: sorted array of upgrade IDs
-- @return table: {consumed=boolean, id=string?, action=string?}
function model.hit_test(click_x, click_y, rect, header_h, row_h, buy_w, scroll_row, ids_sorted)
    if not click_x or not click_y or not rect then
        return {consumed = false}
    end

    -- Check if click is within panel bounds at all
    if click_x < rect.x or click_x >= rect.x + rect.w or
       click_y < rect.y or click_y >= rect.y + rect.h then
        return {consumed = false}
    end

    -- Click is within panel bounds, so it's consumed
    local result = {consumed = true}

    -- Use row_at to determine which row was clicked
    local row_info = model.row_at(click_x, click_y, rect, header_h, row_h, scroll_row, #ids_sorted)

    if not row_info.in_list or not row_info.row_index then
        -- Click was in panel but not in a valid row (e.g., header area)
        return result
    end

    -- Get the upgrade ID for this row
    local upgrade_id = ids_sorted[row_info.row_index]
    if not upgrade_id then
        return result
    end

    result.id = upgrade_id

    -- Check if click was in buy region (rightmost buy_w pixels)
    local buy_region_start = rect.x + rect.w - buy_w
    if buy_w and click_x >= buy_region_start then
        result.action = "buy"
    end

    return result
end

return model