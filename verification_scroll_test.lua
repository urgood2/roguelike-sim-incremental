--[[
Upgrade Panel Scroll Behavior Verification Test
===============================================

Manual test to verify that upgrade panel scrolling reaches all upgrades correctly.

Test Setup:
- 12 upgrades are defined in the upgrades module
- Upgrade panel window size: 240x500 pixels
- Uses ImGui BeginChild with scrolling enabled

Test Procedure:
1. Launch the incremental flag game
2. Open the upgrade panel (should be visible by default)
3. Count the visible upgrades without scrolling
4. Scroll down to the bottom of the list
5. Verify that all 12 upgrades are accessible

Expected Upgrades (in order):
1. click_wood - "Stronger Axe"
2. click_stone - "Better Pickaxe"
3. passive_gold - "Gold Mine"
4. creature_speed - "Creature Training"
5. forage_amount - "Better Basket"
6. forage_speed - "Efficient Foraging"
7. tree_regrowth - "Tree Sapling Farming"
8. rock_regrowth - "Rock Formation"
9. max_creatures - "Better Housing"
10. starting_wood - "Initial Resources I"
11. starting_stone - "Initial Resources II"
12. click_range - "Extended Reach"

Pass Criteria:
✓ All 12 upgrades are visible when scrolling through the list
✓ Scrolling reaches the bottom item ("Extended Reach")
✓ Scrolling returns to the top item ("Stronger Axe")
✓ No upgrades are missing or duplicated
✓ Each upgrade shows: name, level, cost, button state, description

Test Results:
[ ] Initial view shows first N upgrades clearly
[ ] Scroll down reveals remaining upgrades
[ ] Bottom upgrade ("Extended Reach") is fully visible when scrolled to bottom
[ ] All 12 upgrades were accessible
[ ] Scroll back to top works correctly
[ ] No visual issues (text cutoff, overlapping, etc.)

Notes:
- Upgrade panel uses ImGui.BeginChild("upgrade_list", 0, 0, true) for scrollable content
- Panel window size is set to 240x500 pixels with FirstUseEver condition
- Each upgrade entry includes: title, cost, button, description, separator
- Window should be draggable due to FirstUseEver positioning

Implementation Details:
- File: assets/scripts/idle_game/ui/upgrade_panel.lua
- Scroll container: ImGui.BeginChild("upgrade_list")
- Upgrade source: assets/scripts/idle_game/upgrades.lua (UPGRADES table)
- Total upgrades: 12 entries
]]