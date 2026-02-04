-- Builder entity type definition
-- Seeks empty tiles and places decorative structures
return {
    initial = {
        nearEmptyTile = false,
        canAffordBuild = false,
        hasBuiltMax = false,
        wander = false
    },
    goal = {
        hasBuiltMax = false
    }
}
