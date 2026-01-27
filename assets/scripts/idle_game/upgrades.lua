local upgrades = {}

-- Upgrade definitions (12 total upgrades covering diverse mechanics)
local UPGRADES = {
    click_wood = {
        name = "Stronger Axe",
        description = "Increase wood per click",
        base_cost = {wood = 10},
        max_level = 10,
        effect = {type = "click_multiplier", resource = "wood", amount = 1}
    },
    click_stone = {
        name = "Better Pickaxe",
        description = "Increase stone per click",
        base_cost = {stone = 10},
        max_level = 10,
        effect = {type = "click_multiplier", resource = "stone", amount = 1}
    },
    passive_gold = {
        name = "Gold Mine",
        description = "Increase passive gold rate",
        base_cost = {gold = 20},
        max_level = 10,
        effect = {type = "passive_rate", resource = "gold", amount = 0.1}
    },
    creature_speed = {
        name = "Creature Training",
        description = "Increase forager movement speed",
        base_cost = {food = 15},
        max_level = 10,
        effect = {type = "stat_multiplier", stat = "speed", amount = 0.1}
    },
    forage_amount = {
        name = "Better Basket",
        description = "Increase food per forage",
        base_cost = {wood = 20},
        max_level = 10,
        effect = {type = "harvest_amount", resource = "food", amount = 1}
    },
    forage_speed = {
        name = "Efficient Foraging",
        description = "Reduce forage time",
        base_cost = {stone = 25},
        max_level = 10,
        effect = {type = "action_duration", action = "forage", amount = -0.1}
    },
    tree_regrowth = {
        name = "Tree Sapling Farming",
        description = "Increase tree regrowth chance",
        base_cost = {gold = 50},
        max_level = 10,
        effect = {type = "regrowth_chance", tile = "tree", amount = 0.05}
    },
    rock_regrowth = {
        name = "Rock Formation",
        description = "Increase rock regrowth chance",
        base_cost = {gold = 50},
        max_level = 10,
        effect = {type = "regrowth_chance", tile = "rock", amount = 0.05}
    },
    max_creatures = {
        name = "Better Housing",
        description = "Increase max foragers",
        base_cost = {wood = 30},
        max_level = 10,
        effect = {type = "capacity", entity = "forager", amount = 1}
    },
    starting_wood = {
        name = "Initial Resources I",
        description = "Start new game with more wood",
        base_cost = {stone = 40},
        max_level = 10,
        effect = {type = "starting_resource", resource = "wood", amount = 10}
    },
    starting_stone = {
        name = "Initial Resources II",
        description = "Start new game with more stone",
        base_cost = {stone = 40},
        max_level = 10,
        effect = {type = "starting_resource", resource = "stone", amount = 10}
    },
    click_range = {
        name = "Extended Reach",
        description = "Increase click area radius",
        base_cost = {gold = 100},
        max_level = 10,
        effect = {type = "area_radius", amount = 0.5}
    },
}

-- Upgrade levels storage (persisted)
upgrades._levels = {}

-- Get current level of upgrade (0 if not purchased)
function upgrades.get_level(upgrade_id)
    return upgrades._levels[upgrade_id] or 0
end

-- Get cost for next level
-- Formula: base_cost * (1.5 ^ current_level)
function upgrades.get_cost(upgrade_id)
    local upgrade = UPGRADES[upgrade_id]
    if not upgrade then
        error("Unknown upgrade: " .. tostring(upgrade_id))
    end
    
    local level = upgrades.get_level(upgrade_id)
    local cost = {}
    
    for resource, base_amount in pairs(upgrade.base_cost) do
        cost[resource] = math.floor(base_amount * (1.5 ^ level))
    end
    
    return cost
end

-- Check if player can afford next level
-- Returns false if already at max level or insufficient resources
function upgrades.can_afford(upgrade_id, resources_module)
    local upgrade = UPGRADES[upgrade_id]
    if not upgrade then
        error("Unknown upgrade: " .. tostring(upgrade_id))
    end
    
    local level = upgrades.get_level(upgrade_id)
    
    -- Can't purchase if already at max level
    if level >= upgrade.max_level then
        return false
    end
    
    -- Check if player has enough resources
    local cost = upgrades.get_cost(upgrade_id)
    for resource, amount in pairs(cost) do
        if resources_module.get(resource) < amount then
            return false
        end
    end
    
    return true
end

-- Purchase upgrade (deduct cost, increment level)
-- Returns true on success, false if can't afford or at max level
function upgrades.purchase(upgrade_id, resources_module)
    if not upgrades.can_afford(upgrade_id, resources_module) then
        return false
    end
    
    local cost = upgrades.get_cost(upgrade_id)
    for resource, amount in pairs(cost) do
        resources_module.add(resource, -amount)
    end
    
    upgrades._levels[upgrade_id] = upgrades.get_level(upgrade_id) + 1
    return true
end

-- Get all upgrade definitions
function upgrades.get_all()
    return UPGRADES
end

-- Reset all upgrade levels (for testing)
function upgrades.reset()
    upgrades._levels = {}
end

return upgrades
