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
config.SPRITE_GRASS = "d437_044_period"  -- period
config.SPRITE_TREE = "d437_005_spade"     -- club
config.SPRITE_ROCK = "d437_033_hash"      -- hash

return config
