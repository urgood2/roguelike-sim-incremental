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

-- Income tracking (for display purposes)
local _income_tracker = {
    window = 5.0,  -- Track income over 5 seconds
    time_accumulator = 0,
    current_window = { food = 0, wood = 0, stone = 0, gold = 0 },
    rates = { food = 0, wood = 0, stone = 0, gold = 0 }  -- Per-second rates
}

-- Initialize all resources to 0
function resources.init()
    _resources.food = 0
    _resources.wood = 0
    _resources.stone = 0
    _resources.gold = 0
    _income_tracker.time_accumulator = 0
    _income_tracker.current_window = { food = 0, wood = 0, stone = 0, gold = 0 }
    _income_tracker.rates = { food = 0, wood = 0, stone = 0, gold = 0 }
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

    -- Track positive income for rate display
    if amount > 0 then
        _income_tracker.current_window[resource_type] =
            (_income_tracker.current_window[resource_type] or 0) + amount
    end

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

    -- Update income rate tracking
    _income_tracker.time_accumulator = _income_tracker.time_accumulator + dt
    if _income_tracker.time_accumulator >= _income_tracker.window then
        -- Calculate per-second rates from accumulated income
        local elapsed = _income_tracker.time_accumulator
        for resource, amount in pairs(_income_tracker.current_window) do
            _income_tracker.rates[resource] = amount / elapsed
        end
        -- Reset for next window
        _income_tracker.time_accumulator = 0
        _income_tracker.current_window = { food = 0, wood = 0, stone = 0, gold = 0 }
    end
end

-- Get income rate per second for a resource
function resources.get_rate(resource_type)
    return _income_tracker.rates[resource_type] or 0
end

-- Get all income rates
function resources.get_all_rates()
    return _income_tracker.rates
end

return resources
