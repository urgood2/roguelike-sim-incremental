# Idle Game Upgrades API

Module: `idle_game.upgrades`

This module tracks upgrade levels, costs, affordability, and purchases for the idle game.

## Purchase Attempt API

`upgrades.purchase(upgrade_id, resources_module) -> boolean`

- Returns `true` when the upgrade is purchased.
- Returns `false` when the upgrade is at max level or the player cannot afford it.
- On success, it deducts resources via `resources_module.add(resource, -amount)` and increments the upgrade level by 1.

`resources_module` must expose:
- `get(resource_id) -> number`
- `add(resource_id, delta) -> number`

## Related Helpers

`upgrades.get_cost(upgrade_id) -> table`
- Returns a cost table keyed by resource id (for example: `{ wood = 15 }`).

`upgrades.can_afford(upgrade_id, resources_module) -> boolean`
- Returns `false` when the upgrade is maxed or the resources are insufficient.

`upgrades.get_level(upgrade_id) -> number`
- Returns the current level (0 when unpurchased).

## Example

```lua
local upgrades = require("idle_game.upgrades")
local resources = require("idle_game.resources")

if upgrades.can_afford("click_wood", resources) then
    local success = upgrades.purchase("click_wood", resources)
    if success then
        print("Upgrade purchased!")
    end
end
```
