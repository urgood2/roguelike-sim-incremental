--[[
Lumberjack Behavior Verification Test
====================================

Integration test to verify that lumberjacks target trees and provide bonus wood gain.

Test Components:
1. Lumberjack spawning and tracking
2. Tree targeting behavior (HARVEST_WOOD goal)
3. Bonus wood gain vs manual clicking
4. AI goal selection and action execution

Test Setup:
- Terrain with trees available for harvesting
- Spawned lumberjacks using spawner.spawnLumberjacks(count)
- Resource tracking to measure wood gain
- Time-based observation of lumberjack behavior

Expected Behavior:
1. Lumberjacks spawn on grass tiles using Poisson-disc sampling
2. Lumberjacks have HARVEST_WOOD goal (from lumberjack goal selector)
3. Lumberjacks target only trees, not rocks or other resources
4. Lumberjacks provide automated wood gathering (passive income)

Test Procedure:
=================

SETUP PHASE:
1. Initialize game with fresh terrain (trees + grass)
2. Record initial wood count: wood_initial = resources.get("wood")
3. Count initial trees: tree_count_initial = count_terrain_tiles(terrain.TREE)
4. Spawn lumberjacks: spawner.spawnLumberjacks(3)
5. Verify lumberjack count: assert(spawner.getLumberjackCount() == 3)

BEHAVIOR OBSERVATION (30 seconds):
6. Monitor lumberjacks moving toward trees
7. Observe trees being harvested (terrain changes from TREE to GRASS)
8. Monitor wood resource increasing
9. Verify lumberjacks ignore rocks/other resources

MEASUREMENTS:
10. Record final wood count: wood_final = resources.get("wood")
11. Count final trees: tree_count_final = count_terrain_tiles(terrain.TREE)
12. Calculate wood gained: wood_gained = wood_final - wood_initial
13. Calculate trees harvested: trees_harvested = tree_count_initial - tree_count_final

VALIDATION CRITERIA:
✓ Lumberjacks spawn successfully (count matches requested)
✓ Lumberjacks target trees (visible movement toward tree tiles)
✓ Trees are harvested (tree count decreases)
✓ Wood resources increase (passive income from lumberjack work)
✓ Lumberjacks ignore non-tree resources
✓ Wood gain > 0 (lumberjacks provide bonus beyond manual clicking)

Implementation Details to Verify:
==================================

1. Goal Selector (assets/scripts/ai/goal_selectors/lumberjack.lua):
   - HARVEST_WOOD goal present
   - No HARVEST_STONE goal (trees only)
   - Survival goals: REST, CONSUME, FORAGE
   - Fallback: WANDER

2. Spawning (assets/scripts/idle_game/spawner.lua):
   - spawnLumberjacks() function creates entities
   - Uses Poisson-disc sampling on grass tiles
   - Tracks lumberjacks in spawner._lumberjacks table
   - getLumberjackCount() returns accurate count

3. AI Integration:
   - Lumberjacks use "lumberjack" entity type
   - Goal selector applied via ai.get_entity_ai_def()
   - GOAP system executes HARVEST_WOOD actions
   - Actions result in resource gain and terrain changes

Expected Resource Flow:
======================
Manual clicking: 1 wood per tree (base) + upgrades
Lumberjack harvesting: 1+ wood per tree (automated) + any bonuses
Net effect: Passive wood income without player interaction

Test Results Template:
=====================
[ ] Lumberjacks spawned successfully: X/3
[ ] Lumberjacks observed moving to trees: Y/Y observed
[ ] Trees harvested by lumberjacks: Z trees
[ ] Wood gained from lumberjack activity: W wood
[ ] No targeting of non-tree resources observed: ✓/✗
[ ] Passive wood income confirmed: ✓/✗

Performance Expectations:
========================
- 3 lumberjacks should harvest multiple trees within 30 seconds
- Wood income should be visible in resource display
- No errors or AI failures during operation
- Smooth interaction with terrain and resource systems

Files Involved:
==============
- assets/scripts/ai/goal_selectors/lumberjack.lua (targeting)
- assets/scripts/idle_game/spawner.lua (spawning/tracking)
- assets/scripts/idle_game/terrain.lua (tree tiles)
- assets/scripts/idle_game/resources.lua (wood tracking)
- assets/scripts/idle_game/scenes/sim_scene.lua (integration)

Edge Cases to Test:
==================
- No trees available (lumberjacks should wander)
- All lumberjacks at max fatigue (should rest)
- Lumberjacks hungry (should forage for food)
- Mixed terrain with trees and rocks (should prefer trees)
]]