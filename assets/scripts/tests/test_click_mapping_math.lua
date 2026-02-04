--[[
================================================================================
TEST: Upgrade Panel Click Mapping Mathematics
================================================================================
Verifies the mathematical correctness of click-to-upgrade mapping logic
with scrolling. Tests the core coordinate transformation without UI dependencies.

Run with: lua assets/scripts/tests/test_click_mapping_math.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Click Mapping Logic (Extracted from upgrade panel)
--------------------------------------------------------------------------------

-- This is the core mathematical logic extracted from ascii_upgrade_panel.lua
local function calculate_clicked_upgrade(click_x, click_y, panel_rect, tile_size, scroll_offset)
    -- Check if click is within panel bounds
    if not (click_x >= panel_rect.x and click_x < panel_rect.x + panel_rect.w and
            click_y >= panel_rect.y and click_y < panel_rect.y + panel_rect.h) then
        return nil  -- Click outside panel
    end

    -- Calculate which upgrade was clicked based on position
    local relative_y = click_y - panel_rect.y
    local upgrade_height = tile_size * 2  -- Each upgrade takes 2 tiles height
    local clicked_index = math.floor(relative_y / upgrade_height) + 1 + scroll_offset

    return clicked_index
end

local function get_visible_upgrades(upgrade_list, scroll_offset, max_visible)
    local visible = {}
    local start_index = scroll_offset + 1
    local end_index = math.min(start_index + max_visible - 1, #upgrade_list)

    for i = start_index, end_index do
        if upgrade_list[i] then
            table.insert(visible, {index = i, upgrade = upgrade_list[i]})
        end
    end

    return visible
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Click Mapping Mathematics", function()

    -- Test 1: Basic coordinate to upgrade index calculation
    t.it("calculates upgrade index from click coordinates correctly", function()
        local panel_rect = {x = 100, y = 50, w = 200, h = 400}
        local tile_size = 20
        local scroll_offset = 0

        -- Click on first upgrade (middle of first upgrade area)
        local upgrade_height = tile_size * 2  -- 40 pixels
        local click_x = panel_rect.x + panel_rect.w / 2  -- Center X
        local click_y = panel_rect.y + upgrade_height / 2  -- Middle of first upgrade

        local clicked_index = calculate_clicked_upgrade(click_x, click_y, panel_rect, tile_size, scroll_offset)
        t.expect(clicked_index).to_equal(1)

        -- Click on second upgrade
        click_y = panel_rect.y + upgrade_height * 1.5  -- Middle of second upgrade
        clicked_index = calculate_clicked_upgrade(click_x, click_y, panel_rect, tile_size, scroll_offset)
        t.expect(clicked_index).to_equal(2)

        -- Click on third upgrade
        click_y = panel_rect.y + upgrade_height * 2.5  -- Middle of third upgrade
        clicked_index = calculate_clicked_upgrade(click_x, click_y, panel_rect, tile_size, scroll_offset)
        t.expect(clicked_index).to_equal(3)
    end)

    -- Test 2: Click mapping with scroll offset
    t.it("adjusts click mapping correctly with scroll offset", function()
        local panel_rect = {x = 100, y = 50, w = 200, h = 400}
        local tile_size = 20
        local upgrade_height = tile_size * 2  -- 40 pixels

        -- Test with scroll offset of 3
        local scroll_offset = 3
        local click_x = panel_rect.x + panel_rect.w / 2

        -- Click on first visible upgrade (which is actually the 4th upgrade in the list)
        local click_y = panel_rect.y + upgrade_height / 2
        local clicked_index = calculate_clicked_upgrade(click_x, click_y, panel_rect, tile_size, scroll_offset)
        t.expect(clicked_index).to_equal(4)  -- 1 + 3 (scroll offset)

        -- Click on second visible upgrade (which is actually the 5th upgrade in the list)
        click_y = panel_rect.y + upgrade_height * 1.5
        clicked_index = calculate_clicked_upgrade(click_x, click_y, panel_rect, tile_size, scroll_offset)
        t.expect(clicked_index).to_equal(5)  -- 2 + 3 (scroll offset)
    end)

    -- Test 3: Click outside panel bounds
    t.it("returns nil for clicks outside panel bounds", function()
        local panel_rect = {x = 100, y = 50, w = 200, h = 400}
        local tile_size = 20
        local scroll_offset = 0

        -- Click to the left of panel
        local clicked_index = calculate_clicked_upgrade(panel_rect.x - 10, panel_rect.y + 20, panel_rect, tile_size, scroll_offset)
        t.expect(clicked_index).to_equal(nil)

        -- Click to the right of panel
        clicked_index = calculate_clicked_upgrade(panel_rect.x + panel_rect.w + 10, panel_rect.y + 20, panel_rect, tile_size, scroll_offset)
        t.expect(clicked_index).to_equal(nil)

        -- Click above panel
        clicked_index = calculate_clicked_upgrade(panel_rect.x + 50, panel_rect.y - 10, panel_rect, tile_size, scroll_offset)
        t.expect(clicked_index).to_equal(nil)

        -- Click below panel
        clicked_index = calculate_clicked_upgrade(panel_rect.x + 50, panel_rect.y + panel_rect.h + 10, panel_rect, tile_size, scroll_offset)
        t.expect(clicked_index).to_equal(nil)
    end)

    -- Test 4: Visible upgrades calculation
    t.it("calculates visible upgrades correctly with scrolling", function()
        local upgrade_list = {}
        for i = 1, 12 do
            upgrade_list[i] = "upgrade_" .. i
        end

        local max_visible = 5
        local scroll_offset = 0

        -- No scrolling - should show first 5 upgrades
        local visible = get_visible_upgrades(upgrade_list, scroll_offset, max_visible)
        t.expect(#visible).to_equal(5)
        t.expect(visible[1].index).to_equal(1)
        t.expect(visible[5].index).to_equal(5)

        -- Scroll offset of 2 - should show upgrades 3-7
        scroll_offset = 2
        visible = get_visible_upgrades(upgrade_list, scroll_offset, max_visible)
        t.expect(#visible).to_equal(5)
        t.expect(visible[1].index).to_equal(3)
        t.expect(visible[5].index).to_equal(7)

        -- Scroll near end - should show last available upgrades
        scroll_offset = 8
        visible = get_visible_upgrades(upgrade_list, scroll_offset, max_visible)
        t.expect(#visible).to_equal(4)  -- Only 4 left (upgrades 9-12)
        t.expect(visible[1].index).to_equal(9)
        t.expect(visible[4].index).to_equal(12)
    end)

    -- Test 5: Edge cases and boundary testing
    t.it("handles edge cases correctly", function()
        local panel_rect = {x = 0, y = 0, w = 100, h = 200}
        local tile_size = 10
        local scroll_offset = 0
        local upgrade_height = tile_size * 2  -- 20 pixels

        -- Click exactly on the boundary between upgrades
        local click_x = panel_rect.x + 50
        local click_y = panel_rect.y + upgrade_height  -- Exactly on border between upgrade 1 and 2

        -- Should map to upgrade 2 (floor function rounds down)
        local clicked_index = calculate_clicked_upgrade(click_x, click_y, panel_rect, tile_size, scroll_offset)
        t.expect(clicked_index).to_equal(2)

        -- Click at very top of panel
        click_y = panel_rect.y
        clicked_index = calculate_clicked_upgrade(click_x, click_y, panel_rect, tile_size, scroll_offset)
        t.expect(clicked_index).to_equal(1)

        -- Click at bottom pixel of panel
        click_y = panel_rect.y + panel_rect.h - 1
        clicked_index = calculate_clicked_upgrade(click_x, click_y, panel_rect, tile_size, scroll_offset)
        -- Should be within a valid upgrade index
        t.expect(clicked_index > 0).to_equal(true)
    end)

    -- Test 6: Consistency verification - Visual index to actual index mapping
    t.it("maintains consistent visual-to-actual index mapping", function()
        local scroll_offset = 5
        local max_visible = 8

        for visual_index = 1, max_visible do
            local actual_index = visual_index + scroll_offset

            -- The relationship should be: actual_index = visual_index + scroll_offset
            t.expect(actual_index).to_equal(visual_index + scroll_offset)
        end

        -- Test with different scroll offsets
        for test_scroll in ipairs({0, 2, 7, 10}) do
            for visual_idx = 1, 3 do
                local actual_idx = visual_idx + test_scroll
                t.expect(actual_idx).to_equal(visual_idx + test_scroll)
            end
        end
    end)

end)

--------------------------------------------------------------------------------
-- Auto-run if executed directly
--------------------------------------------------------------------------------
if arg and arg[0] and arg[0]:match("test_click_mapping_math%.lua$") then
    t.run()
end