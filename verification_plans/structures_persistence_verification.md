# Structures Persistence Verification Plan

## Task: bd-198y - Verify structures persistence
**Objective**: Integration test to verify structures survive save/restart cycles

## Prerequisites
- [ ] terrain._structures table implemented (bd-2rj)
- [ ] terrain.place_structure function implemented (bd-1i5)
- [ ] terrain.get_structures function implemented (bd-zm7)
- [ ] Structure placement validation implemented (bd-3qn)
- [ ] Structures collect/distribute functions implemented (bd-3to7, bd-ffjc)
- [ ] test_idle_structures_persistence.lua created (bd-1s20)
- [ ] Game builds and runs successfully with structures system

## Integration Test Procedure

### Setup
1. Start fresh game instance
2. Ensure structures system is enabled
3. Verify terrain supports structure placement
4. Note initial game state (empty terrain)

### Test Procedure

#### Phase 1: Structure Placement
1. **Place Multiple Structures**
   - Place at least 3 different structure types
   - Place structures at various terrain locations
   - Verify visual confirmation of placement
   - Record structure positions and types

2. **Verify Structure Functionality**
   - Test structure collection functionality (if applicable)
   - Test structure distribution functionality (if applicable)
   - Confirm structures are integrated with game systems

3. **Record Initial State**
   - Note exact structure locations (x, y coordinates)
   - Record structure types and any state data
   - Verify structures appear in terrain.get_structures()

#### Phase 2: Save and Exit
1. **Trigger Save Operation**
   - Manual save or wait for auto-save
   - Verify save process completes successfully
   - Check save file contains structure data

2. **Clean Exit**
   - Properly exit game
   - Ensure all data is flushed to disk

#### Phase 3: Restart and Verification
1. **Restart Game**
   - Launch game completely fresh
   - Load the save file with structures

2. **Verify Structure Persistence**
   - Check all previously placed structures are present
   - Verify structures are at correct positions
   - Confirm structure types match original placement
   - Test structure functionality still works

3. **Verify Structure State**
   - Any structure-specific state should be preserved
   - Structure interactions should work normally
   - No duplicated or missing structures

### Expected Results
- ✅ All placed structures present after restart
- ✅ Structure positions exactly match pre-restart state
- ✅ Structure types and properties preserved
- ✅ Structure functionality works normally
- ✅ No corruption or data loss in structure data

### Failure Conditions
- ❌ Any structures missing after restart
- ❌ Structures in wrong positions
- ❌ Structure type/property corruption
- ❌ Structure functionality broken after restart
- ❌ Save file missing structure data

### Test Scenarios

#### Scenario 1: Basic Persistence
- Place 3-5 simple structures
- Save, restart, verify all present

#### Scenario 2: Complex Layout
- Place many structures in specific pattern
- Verify pattern integrity after restart

#### Scenario 3: Structure State Persistence
- Place structures with specific states/properties
- Verify state preserved after restart

#### Scenario 4: Multiple Save/Load Cycles
- Verify persistence across multiple restart cycles
- Test for cumulative data corruption

#### Scenario 5: Edge Cases
- Structures near terrain boundaries
- Maximum number of structures
- Structures with special properties

### Performance Considerations
- Monitor save file size with many structures
- Verify load time performance
- Check memory usage with structure data

### Error Recovery Testing
- Test behavior with corrupted structure data
- Verify graceful handling of invalid structure references
- Test structure cleanup on data inconsistencies

## Automated Test Recommendations

While this is a manual integration test, consider creating automated versions:

```lua
-- Example automated test structure
function test_structure_persistence()
    -- Place test structures
    local structures = {
        {x=10, y=10, type="farm"},
        {x=15, y=20, type="mine"},
        {x=25, y=15, type="house"}
    }

    for _, structure in ipairs(structures) do
        terrain.place_structure(structure.x, structure.y, structure.type)
    end

    -- Simulate save/load
    local save_data = save_manager.serialize()
    save_manager.deserialize(save_data)

    -- Verify structures
    local loaded_structures = terrain.get_structures()
    assert_structures_match(structures, loaded_structures)
end
```

## Documentation Requirements
Document results including:
- Structure types tested
- Number of structures in test
- Save file structure analysis
- Load time measurements
- Any issues or edge cases discovered

## Success Criteria
Test passes when:
1. All placed structures survive save/restart
2. Structure positions and types are preserved
3. Structure functionality works after restart
4. No performance degradation
5. Save file integrity maintained

This verification confirms the structures system meets persistence requirements for production use.