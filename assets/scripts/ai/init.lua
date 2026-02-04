
ai = ai or {}  -- preserve C++ bindings if they exist

ai.actions = ai.actions or {} -- Actions are named functions that can be executed by entities
ai.goal_selectors = ai.goal_selectors or {} -- Goal selectors are functions that set the goal state dynamically per entity
ai.blackboard_init = ai.blackboard_init or {} -- Blackboard initialization functions for each entity type
ai.entity_types = ai.entity_types or {} -- Entity types are presets for worldstate, e.g. kobold, goblin, etc.
ai.worldstate_updaters = ai.worldstate_updaters or {} -- Worldstate updaters are functions that update worldstate from blackboard/sensory data
ai.bb = ai.bb or {}

require("ai.bb_compat")
ai.sense = require("ai.sense")
ai.memory = require("ai.memory")
ai.perception = require("ai.perception")
ai.nav = require("ai.nav")
ai.debug = require("ai.debug")
ai.action = require("ai.action")
ai.thresholds = require("ai.thresholds")
ai.stuck = require("ai.stuck")

local function load_directory(dir, outTable, assignByReturnName)
    local list_fn = ai.list_lua_files
    for _, name in ipairs(list_fn(dir)) do
        local mod = require(dir .. "." .. name)
        if assignByReturnName and mod.name then
            outTable[mod.name] = mod
        else
            outTable[name] = mod
        end
    end
end

load_directory("ai.actions", ai.actions, true)
load_directory("ai.goal_selectors", ai.goal_selectors, false)
load_directory("ai.blackboard_init", ai.blackboard_init, false)
load_directory("ai.entity_types", ai.entity_types, false)
ai.worldstate_updaters = require("ai.worldstate_updaters")


-- ---- Policy & Goals (shared defaults) ----
local selector = require("ai.goal_selector_engine")

ai.policy = ai.policy or {
  band_rank = { COMBAT=4, SURVIVAL=3, WORK=2, IDLE=1 }
}

ai.goals  = ai.goals  or {
  -- WORK: dig whenever worldstate says we can
  DIG_FOR_GOLD = {
    band    = "WORK",
    persist = 0.08, -- hysteresis to avoid immediate bounce back to wander
    desire  = function(e, S)
      return ai.get_worldstate(e, "candigforgold") and 1.0 or 0.0
    end,
    -- No veto: your worldstate_updater already sets candigforgold true/false
    on_apply = function(e)
      -- Target state: make candigforgold false (planner picks action with pre=true, post=false)
      ai.set_goal(e, { candigforgold = false })
    end
  },

  -- WORK: Harvest wood when near trees (foragers gather resources for player)
  HARVEST_WOOD = {
    band    = "WORK",
    persist = 0.1,
    desire  = function(e, S)
      local nearTree = ai.get_worldstate(e, "nearTree")
      return nearTree == true and 0.8 or 0.0
    end,
    on_apply = function(e)
      ai.set_goal(e, { didWork = true })
    end
  },

  -- WORK: Harvest stone when near rocks
  HARVEST_STONE = {
    band    = "WORK",
    persist = 0.1,
    desire  = function(e, S)
      local nearRock = ai.get_worldstate(e, "nearRock")
      return nearRock == true and 0.75 or 0.0
    end,
    on_apply = function(e)
      ai.set_goal(e, { didWork = true })
    end
  },

  -- WORK: Collect ground items when available and has inventory space
  COLLECT_ITEM = {
    band    = "WORK",
    persist = 0.12,
    desire  = function(e, S)
      local hasInventorySpace = ai.get_worldstate(e, "hasInventorySpace")
      local nearGroundItem = ai.get_worldstate(e, "nearGroundItem")

      -- Only collect distant items when not near items (passive collection handles nearby)
      -- and when there's inventory space
      if hasInventorySpace == true and nearGroundItem == false then
        -- Check if there are any ground items available on the map
        local terrain = require("idle_game.terrain")
        local ground_items = terrain.get_ground_items()

        -- Count available ground items
        local item_count = 0
        for _ in pairs(ground_items) do
          item_count = item_count + 1
          if item_count > 0 then break end  -- Early exit if any found
        end

        return item_count > 0 and 0.7 or 0.0
      end

      return 0.0
    end,
    on_apply = function(e)
      ai.set_goal(e, { didWork = true })
    end
  },

  -- SURVIVAL: Forage food when hungry and near tree
  FORAGE = {
    band    = "SURVIVAL",
    persist = 0.12,
    desire  = function(e, S)
      local hungry = ai.get_worldstate(e, "hungry")
      local nearTree = ai.get_worldstate(e, "nearTree")
      return (hungry == true and nearTree == true) and 0.9 or 0.0
    end,
    on_apply = function(e)
      ai.set_goal(e, { hasFood = true })
    end
  },

  -- SURVIVAL: Consume food when has food
  CONSUME = {
    band    = "SURVIVAL",
    persist = 0.1,
    desire  = function(e, S)
      local hasFood = ai.get_worldstate(e, "hasFood")
      return hasFood == true and 0.95 or 0.0
    end,
    on_apply = function(e)
      ai.set_goal(e, { hungry = false })
    end
  },

  -- SURVIVAL: Rest when tired
  REST = {
    band    = "SURVIVAL",
    persist = 0.15,
    desire  = function(e, S)
      local tired = ai.get_worldstate(e, "tired")
      local exhausted = ai.get_worldstate(e, "exhausted")
      -- Higher priority when exhausted
      if exhausted == true then return 1.0 end
      if tired == true then return 0.7 end
      return 0.0
    end,
    on_apply = function(e)
      ai.set_goal(e, { tired = false })
    end
  },

  -- IDLE fallback
  WANDER = {
    band    = "IDLE",
    persist = 0.05,
    desire  = function(e, S) return 0.2 end,
    veto    = function(e, S)
      -- Optional guard; keep if your code sometimes latches wander=false
    --   local v = ai.get_worldstate(e, "wander")
    --   return v == false
    end,
    on_apply = function(e)
      ai.patch_worldstate(e, "wander", false) -- clear sticky toggle, optional
      ai.set_goal(e, { wander = true })
    end
  },

  -- WORK: Build structures when resources are available and timer allows
  BUILD_STRUCTURE = {
    band    = "WORK",
    persist = 0.15,
    desire  = function(e, S)
      local canAttemptBuild = ai.get_worldstate(e, "canAttemptBuild")
      return canAttemptBuild == true and 0.8 or 0.0
    end,
    on_apply = function(e)
      ai.set_goal(e, { didWork = true })
    end
  },

  -- ============================================================================
  -- DEMO BOT GOALS - For GOAP AI System Demo
  -- ============================================================================

  -- COMBAT band: Highest priority - respond to threats
  DEMO_ALERT = {
    band    = "COMBAT",
    persist = 0.15, -- Strong hysteresis to complete alert
    desire  = function(e, S)
      return ai.get_worldstate(e, "threat_detected") and 1.0 or 0.0
    end,
    on_apply = function(e)
      ai.set_goal(e, { threat_detected = false, alert_complete = true })
    end
  },

  -- SURVIVAL band: Rest when tired
  DEMO_REST = {
    band    = "SURVIVAL",
    persist = 0.1,
    desire  = function(e, S)
      return ai.get_worldstate(e, "tired") and 0.9 or 0.0
    end,
    on_apply = function(e)
      ai.set_goal(e, { tired = false, rested = true })
    end
  },

  -- WORK band: Patrol duty (continuous wandering for idle sim)
  DEMO_PATROL = {
    band    = "WORK",
    persist = 0.08,
    desire  = function(e, S)
      -- Always desire patrol for continuous wandering behavior
      return 0.7
    end,
    on_apply = function(e)
      -- Reset patrolling to false so GOAP will plan a new patrol action
      ai.set_worldstate(e, "patrolling", false)
      ai.set_goal(e, { patrolling = true })
    end
  },

  -- IDLE band: Fallback when nothing else to do
  DEMO_IDLE = {
    band    = "IDLE",
    persist = 0.05,
    desire  = function(e, S) return 0.2 end, -- Always slightly desires idle
    on_apply = function(e)
      ai.set_goal(e, { idle = true })
    end
  },
}

-- Default per-type selector → uses the generic selector and the shared goals/policy
ai.goal_selectors.Default = function(e)
  -- def is the per-entity deep-copied table your C++ side created
  local def = ai.get_entity_ai_def(e)
  def.policy = def.policy or ai.policy
  def.goals  = def.goals  or ai.goals
  selector.select_and_apply(e)
end
