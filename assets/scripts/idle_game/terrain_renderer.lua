-- Terrain renderer using dungeon_437 ASCII sprites
local terrain_renderer = {}

-- Import terrain constants
local terrain = require("idle_game.terrain")
local config = require("idle_game.config")

-- Tile size from config (20x20 pixels)
local TILE_SIZE = config.TILE_SIZE

-- Sprite names from dungeon_437 tileset (imported in Phase 0.0)
-- These match the UUIDs in sprites-*.json after TexturePacker processing
local TILE_SPRITES = {
    [terrain.GRASS] = config.SPRITE_GRASS,  -- "044_44_d437_symbol"
    [terrain.TREE] = config.SPRITE_TREE,     -- "005_club_d437"
    [terrain.ROCK] = config.SPRITE_ROCK,     -- "033_33_d437_symbol"
}

-- Tile colors for tinting (must be Color userdata, not tables)
local TILE_COLORS = nil

local function initColors()
    if not TILE_COLORS then
        TILE_COLORS = {
            [terrain.GRASS] = util.getColor("FOREST GREEN"),
            [terrain.TREE] = util.getColor("DARK GREEN"),
            [terrain.ROCK] = util.getColor("GRAY"),
        }
    end
end

local _debug_logged = false

function terrain_renderer.draw(terrainGrid)
    initColors()
    
    if not terrainGrid then
        print("[terrain_renderer] ERROR: terrainGrid is nil!")
        return
    end
    
    if not _debug_logged then
        print(string.format("[terrain_renderer] Drawing grid %dx%d", terrainGrid.width, terrainGrid.height))
        _debug_logged = true
    end
    
    if not command_buffer then
        print("[terrain_renderer] ERROR: command_buffer is nil!")
        return
    end
    
    if not layers or not layers.sprites then
        print("[terrain_renderer] ERROR: layers.sprites is nil!")
        return
    end
    
    for y = 0, terrainGrid.height - 1 do
        for x = 0, terrainGrid.width - 1 do
            local tileType = terrainGrid:get(x, y)
            local spriteName = TILE_SPRITES[tileType]
            local color = TILE_COLORS[tileType]
            
            if spriteName and command_buffer then
                command_buffer.queueDrawSpriteTopLeft(
                    layers.sprites,
                    function(c)
                        c.spriteName = spriteName
                        c.x = x * TILE_SIZE
                        c.y = y * TILE_SIZE
                        c.dstW = TILE_SIZE
                        c.dstH = TILE_SIZE
                        c.tint = color
                    end,
                    0,
                    layer.DrawCommandSpace.World
                )
            end
        end
    end
end

return terrain_renderer
