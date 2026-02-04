# Idle Game Resources API

Module: `idle_game.resources`

This module tracks idle-game resource totals and exposes helpers for reading totals.

## Read Totals API

`resources.get(resource_id) -> number`

- Returns the current total for the given resource id.
- Valid resource ids are exposed as constants on the module: `resources.FOOD`, `resources.WOOD`, `resources.STONE`, `resources.GOLD`.
- Throws an error if an unknown resource id is provided.

## Example

```lua
local resources = require("idle_game.resources")

local wood_total = resources.get(resources.WOOD)
print("Wood:", wood_total)
```
