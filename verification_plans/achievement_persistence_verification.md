# Achievement Persistence Verification Plan

## Task: bd-142c - Verify achievement persistence
**Objective**: Manual test to verify achievements persist across game restarts

## Prerequisites
- [ ] achievements.lua module implemented (bd-3qj)
- [ ] achievement_listener.lua module implemented (bd-20u)
- [ ] achievements_persistence.lua module implemented (bd-246r)
- [ ] Achievement collector registered in SaveManager (bd-1k58)
- [ ] Game builds and runs successfully

## Manual Verification Steps

### Setup
1. Start the game in debug/test mode
2. Ensure save system is enabled
3. Note initial achievement state (should be empty for new save)

### Test Procedure

#### Step 1: Unlock Achievement
1. Perform an action that should unlock an achievement
   - Collect enough resources (resource achievement)
   - Purchase upgrades (upgrade achievement)
   - Wait for time-based achievement
   - Spawn enough creatures (creature achievement)
2. Verify achievement notification appears (toast/popup)
3. Check achievement is listed in unlocked achievements
4. Note which achievement(s) were unlocked

#### Step 2: Save and Exit
1. Trigger save (manual save or wait for auto-save)
2. Properly exit the game
3. Verify save file contains achievement data

#### Step 3: Restart and Verify
1. Restart the game completely
2. Load the save file
3. Check that previously unlocked achievement(s) are still unlocked
4. Verify achievement count matches pre-restart state
5. Verify achievement titles/descriptions are correct

### Expected Results
- ✅ Achievement unlocked in step 1 should remain unlocked after restart
- ✅ Achievement data should persist in save file
- ✅ No achievements should be lost
- ✅ No duplicate achievements should appear

### Failure Conditions
- ❌ Achievement shows as locked after restart
- ❌ Achievement data missing from save file
- ❌ Game crashes during save/load
- ❌ Achievement state corruption

### Additional Tests
1. **Multiple Restart Test**: Verify persistence across multiple restart cycles
2. **Mixed Achievement Types**: Unlock different types and verify all persist
3. **Save File Integrity**: Manually inspect save file for achievement data

## Automated Test Recommendation
Consider creating an automated version of this test using:
- Mock save/load operations
- Simulated game state
- Automated verification of persistence methods

## Documentation
Document results including:
- Achievement types tested
- Save file structure observed
- Any issues or edge cases found
- Performance impact of persistence system