-- Terrain persistence (SaveManager collector for structures)
-- Handles serialization/deserialization of placed structures

local terrain_persistence = {}

local terrain = require("idle_game.terrain")
local SaveManager = require("core.save_manager")

-- Valid structure types for validation during loading
local VALID_STRUCTURE_TYPES = {
    farm = true,
    mine = true,
    house = true,
    workshop = true,
    storage = true
}

-- Normalize structure format (handle legacy format)
local function normalize_structure(structure)
    local x = structure.x or structure.tileX
    local y = structure.y or structure.tileY
    local structure_type = structure.type or structure.sprite
    return x, y, structure_type
end

-- Collect function - serialize current structures for saving
local function collect()
    local structures = terrain.get_structures()
    local serializable_structures = {}

    -- Convert structure table to array with stable ordering
    for id, structure in pairs(structures) do
        table.insert(serializable_structures, {
            id = structure.id,
            x = structure.x,
            y = structure.y,
            type = structure.type,
            created_at = structure.created_at
        })
    end

    return serializable_structures
end

-- Distribute function - load and validate structures from save data
local function distribute(data)
    if not data or type(data) ~= "table" then
        return
    end

    -- Clear existing structures
    terrain.clear_structures()

    local placed_count = 0
    local skipped_count = 0

    for _, structure_data in ipairs(data) do
        if type(structure_data) == "table" then
            local x, y, structure_type = normalize_structure(structure_data)

            -- Validate structure data
            if x and y and structure_type and
               type(x) == "number" and type(y) == "number" and
               type(structure_type) == "string" and
               VALID_STRUCTURE_TYPES[structure_type] then

                -- Attempt to place structure (this validates terrain and bounds)
                local success, structure_id = terrain.place_structure(x, y, structure_type)

                if success then
                    placed_count = placed_count + 1
                else
                    skipped_count = skipped_count + 1
                end
            else
                skipped_count = skipped_count + 1
            end
        end
    end

    if placed_count > 0 or skipped_count > 0 then
        print(string.format("[TERRAIN_PERSISTENCE] Loaded structures: %d placed, %d skipped",
              placed_count, skipped_count))
    end
end

-- Register with SaveManager
SaveManager.register("idle_structures", {
    collect = collect,
    distribute = distribute,
})

return terrain_persistence