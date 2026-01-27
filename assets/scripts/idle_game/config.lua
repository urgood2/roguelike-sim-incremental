-- Configuration constants for idle game
local config = {}

-- Grid configuration (canonical size)
config.GRID_WIDTH = 30
config.GRID_HEIGHT = 20
config.TILE_SIZE = 20  -- 20x20 pixels per tile

-- Virtual resolution (matches grid perfectly)
config.VIRTUAL_WIDTH = 600   -- 30 * 20
config.VIRTUAL_HEIGHT = 400  -- 20 * 20

-- Sprite names (from dungeon_437 tileset)
-- These are UUIDs from sprites-0.json, not filenames
config.SPRITE_GRASS = "044_44_d437_symbol"  -- d437_044_symbol_44.png
config.SPRITE_TREE = "005_club_d437"         -- d437_005_club.png
config.SPRITE_ROCK = "033_33_d437_symbol"    -- d437_033_symbol_33.png

return config
