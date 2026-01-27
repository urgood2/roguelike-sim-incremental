local resources = {}

-- Resource types (exactly 4)
resources.FOOD = "food"
resources.WOOD = "wood"
resources.STONE = "stone"
resources.GOLD = "gold"

-- Resource cap
local RESOURCE_CAP = 9999

-- Current resource amounts
local _resources = {
    food = 0,
    wood = 0,
    stone = 0,
    gold = 0
}

-- Initialize all resources to 0
function resources.init()
    _resources.food = 0
    _resources.wood = 0
    _resources.stone = 0
    _resources.gold = 0
end

-- Add/subtract resource amount, clamped to [0, RESOURCE_CAP]
-- Returns new total
function resources.add(resource_type, amount)
    if not _resources[resource_type] then
        error("Unknown resource type: " .. tostring(resource_type))
    end
    
    local new_value = _resources[resource_type] + amount
    new_value = math.max(0, math.min(new_value, RESOURCE_CAP))
    _resources[resource_type] = new_value
    
    return new_value
end

-- Get current resource amount
function resources.get(resource_type)
    if not _resources[resource_type] then
        error("Unknown resource type: " .. tostring(resource_type))
    end
    
    return _resources[resource_type]
end

-- Passive accumulation: applies per-second generation based on upgrade levels
-- Formula: rate = base_rate * (1 + upgrade_level * 0.25)
-- upgrade_levels: {gold=0, wood=0, stone=0, gold=0}
function resources.update(dt, upgrade_levels)
    if not dt or not upgrade_levels then return end
    
    -- Gold base rate: 0.1/second, multiplied by passive_gold upgrade (25% per level)
    local gold_base = 0.1
    local gold_level = upgrade_levels.gold or 0
    local gold_rate = gold_base * (1 + gold_level * 0.25)
    resources.add("gold", gold_rate * dt)
end

return resources
