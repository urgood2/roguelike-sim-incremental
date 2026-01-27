-- contains code limited to gameplay logic for organizational purposes

-- CRITICAL: Must be declared BEFORE any requires that might load enemy_factory.lua
-- enemy_factory checks _G.enemyHealthUiState to register spawned enemies
_G.enemyHealthUiState = _G.enemyHealthUiState or {}
_G.combatActorToEntity = _G.combatActorToEntity or setmetatable({}, { __mode = "k" })

local z_orders = require("core.z_orders")
local Node = require("monobehavior.behavior_script_v2") -- the new monobehavior script
local palette = require("color.palette")
local TimerChain = require("core.timer_chain")
local Easing = require("util.easing")
local CombatSystem = require("combat.combat_system")
local WaveTestInit = require("combat.wave_test_init")  -- Wave system test integration
local ShopSystem = require("core.shop_system")
local CardMetadata = require("core.card_metadata")
local CardRarityTags = require("core.add_card_rarity_tags")
require("core.card_eval_order_test")
local WandEngine = require("core.card_eval_order_test")
local WandExecutor = require("wand.wand_executor")
local WandTriggers = require("wand.wand_triggers")
-- NOTE: wandAdapter accessed via _G to avoid local variable limit (Lua 200 local max)
_G.wandAdapter = require("ui.wand_grid_adapter")
local TagEvaluator = require("wand.tag_evaluator")
local AvatarSystem = require("wand.avatar_system")
local JokerSystem = require("wand.joker_system")
local signal = require("external.hump.signal")
local timer = require("core.timer")
local component_cache = require("core.component_cache")
local entity_cache = require("core.entity_cache")
require("ui.ui_definition_helper")
local dsl = require("ui.ui_syntax_sugar")

-- UI modules consolidated to stay under Lua's 200 local variable limit
local ui_modules = {
    CastExecutionGraphUI = require("ui.cast_execution_graph_ui"),
    CastBlockFlashUI = require("ui.cast_block_flash_ui"),
    WandCooldownUI = require("ui.wand_cooldown_ui"),
    SubcastDebugUI = require("ui.subcast_debug_ui"),
    MessageQueueUI = require("ui.message_queue_ui"),
    CurrencyDisplay = require("ui.currency_display"),
    TagSynergyPanel = require("ui.tag_synergy_panel"),
    AvatarJokerStrip = require("ui.avatar_joker_strip"),
    TriggerStripUI = require("ui.trigger_strip_ui"),
    LevelUpScreen = require("ui.level_up_screen"),
    HoverRegistry = require("ui.hover_registry"),
    ContentDebugPanel = require("ui.content_debug_panel"),
    CombatDebugPanel = require("ui.combat_debug_panel"),
    UIOverlayToggles = require("ui.ui_overlay_toggles"),
    EntityInspector = require("ui.entity_inspector"),
    AIInspector = require("ui.ai_inspector"),
    WandResourceBar = require("ui.wand_resource_bar_ui"),
    TooltipV2 = require("ui.tooltip_v2"),
}
wandResourceBar = ui_modules.WandResourceBar -- global alias for compatibility
TooltipV2 = ui_modules.TooltipV2 -- global alias for compatibility

local tooltip_registry = require("core.tooltip_registry")
local StatusIndicatorSystem = require("systems.status_indicator_system")
local MarkSystem = require("systems.mark_system")
local C = require("core.constants")
local CardsData = require("data.cards")

USE_TOOLTIP_V2 = true

local function L(key, fallback)
    if localization and localization.get then
        local result = localization.get(key)
        if result and result ~= key then return result end
    end
    return fallback or key
end

-- Consolidated config/state to stay under Lua's 200 local variable limit
local gameplay_cfg = {
    -- Signal handler management (prevents memory leaks on game restart)
    signal_group = require("core.signal_group"),
    handlers = nil,  -- Will be set to signal_group.new() when handlers are registered

    -- Required runtime state (DO NOT REMOVE)
    LEVEL_UP_MODAL_DELAY = 0.5,
    ENABLE_SURVIVOR_MASK = false,
    messageQueueHooksRegistered = false,
    avatarTestEventsFired = false,
    DEBUG_AVATAR_TEST_EVENTS = rawget(_G, "DEBUG_AVATAR_TEST_EVENTS") or (os.getenv("ENABLE_AVATAR_DEBUG_EVENTS") == "1"),
    DEBUG_AUTO_EQUIP_AVATAR = "conduit",
    cardW = 80,
    cardH = 112,
    isPlayerDying = false,
    DeathScreen = nil,
    debugQuickAccessState = { lastMessage = nil },
    planningPeekEntities = {},
    TESTED_CARD_IDS = {},
    playerFootStepSounds = {
        "walk_1", "walk_2", "walk_3", "walk_4", "walk_5",
        "walk_6", "walk_7", "walk_8", "walk_9", "walk_10"
    },

    -- Feature flags
    -- USE_GRID_INVENTORY: Toggle between new grid-based inventory and legacy board system
    -- When true: Uses PlayerInventory (screen-space grid) + WandLoadoutUI for card management
    -- When false: Uses legacy board_sets with inventory_board for card management
    USE_GRID_INVENTORY = true,  -- Set to false to use legacy board-based inventory

    enable_subcast_debug_ui = true,
    enable_wave_test_init = false,
    enable_joker_debug_panel = false,
    enable_cast_debug_panel = false,
    enable_entity_inspector = true,
    enable_ai_inspector = true,
    enable_content_debug_panel = true,
    enable_tag_synergy_panel = true,
    enable_combat_debug_panel = true,
    enable_trigger_strip = true,
    enable_cast_block_flash_ui = true,
    enable_cast_feed_ui = true,
    enable_message_queue_ui = false,
    enable_planning_board_ui = true,
    enable_mouse_cursor = true,
    enable_inventory_ui = true,
    enable_avatar_strip_ui = true,
    enable_status_indicator_ui = true,
    enable_mark_system = true,
    enable_shop_ui = true,
    enable_shop_pack_ui = true,
    enable_shop_stats_ui = true,
    enable_shop_hint_ui = true,
    enable_shop_interest_ui = true,
    enable_shop_pack_rewards = true,
    enable_shop_card_rewards = true,
    enable_shop_stat_rolls = true,
    enable_shop_modifier_rolls = true,
    enable_shop_stat_modifiers = true,
    enable_shop_stat_modifiers_ui = true,
    enable_shop_modifier_preview = true,
    enable_planning_phase_manabar = true,
    enable_trigger_simulator = true,
    enable_card_spawner_debug_ui = true,
    enable_shop_debug_ui = true,
    enable_wave_debug_ui = true,
    enable_wave_visuals = true,
    enable_wave_system = true,
    enable_tag_evaluator = true,
    enable_card_database = true,
    enable_card_evaluator = true,
    enable_card_modifier_system = true,
    enable_card_modifier_database = true,
    enable_card_modifier_evaluator = true,
    enable_card_modifier_ui = true,
    enable_card_modifier_tooltips = true,
    enable_card_modifier_tooltips_ui = true,
    enable_card_modifier_tooltips_debug_ui = true,
    enable_card_modifier_tooltips_debug_ui_buttons = true,
    enable_card_modifier_tooltips_debug_ui_labels = true,
    enable_card_modifier_tooltips_debug_ui_data = true,
    enable_card_modifier_tooltips_debug_ui_data_labels = true,
    enable_card_modifier_tooltips_debug_ui_data_values = true,
    enable_card_modifier_tooltips_debug_ui_data_tables = true,
    enable_card_modifier_tooltips_debug_ui_data_tables_labels = true,
    enable_card_modifier_tooltips_debug_ui_data_tables_values = true,
    enable_card_modifier_tooltips_debug_ui_data_tables_rows = true,
    enable_card_modifier_tooltips_debug_ui_data_tables_columns = true,
    enable_card_modifier_tooltips_debug_ui_data_tables_headers = true,
    enable_card_modifier_tooltips_debug_ui_data_tables_cells = true,
    auto_action_env = (os.getenv and os.getenv("AUTO_ACTION_PHASE") == "1") or false,
}

gameplay_cfg.auto_action_state = gameplay_cfg.auto_action_state or {}
if os.getenv then
    gameplay_cfg.auto_action_state.env_raw = os.getenv("AUTO_ACTION_PHASE")
end

gameplay_cfg.debugQuickAccessState = gameplay_cfg.debugQuickAccessState or {}
if gameplay_cfg.auto_action_state.env_raw then
    gameplay_cfg.auto_action_state.env_normalized = string.lower(tostring(gameplay_cfg.auto_action_state.env_raw))
    if gameplay_cfg.auto_action_state.env_normalized == "1"
        or gameplay_cfg.auto_action_state.env_normalized == "true"
        or gameplay_cfg.auto_action_state.env_normalized == "yes" then
        gameplay_cfg.auto_action_env = true
    else
        gameplay_cfg.auto_action_env = false
    end
    if not gameplay_cfg.auto_action_state.reported_env_raw then
        print(string.format("[DEBUG ACTION] AUTO_ACTION_PHASE env detected raw=%s normalized=%s enabled=%s",
            tostring(gameplay_cfg.auto_action_state.env_raw),
            tostring(gameplay_cfg.auto_action_state.env_normalized),
            tostring(gameplay_cfg.auto_action_env)))
        gameplay_cfg.auto_action_state.reported_env_raw = true
    end
else
    if not gameplay_cfg.auto_action_state.reported_env_absent then
        print("[DEBUG ACTION] AUTO_ACTION_PHASE env not set; export AUTO_ACTION_PHASE=1 to enable auto action testing")
        gameplay_cfg.auto_action_state.reported_env_absent = true
    end
end


function gameplay_cfg.getDeathScreen()
    if not gameplay_cfg.DeathScreen then
        gameplay_cfg.DeathScreen = require("ui.death_screen")
    end
    return gameplay_cfg.DeathScreen
end

function gameplay_cfg.getDemoFooterUI()
    if not gameplay_cfg.DemoFooterUI then
        gameplay_cfg.DemoFooterUI = require("ui.demo_footer_ui")
    end
    return gameplay_cfg.DemoFooterUI
end

function gameplay_cfg.getStatsPanel()
    if not gameplay_cfg.StatsPanel then
        gameplay_cfg.StatsPanel = require("ui.stats_panel_v2")
    end
    return gameplay_cfg.StatsPanel
end

function gameplay_cfg.getManualTriggerPromptUI()
    if not gameplay_cfg.ManualTriggerPromptUI then
        gameplay_cfg.ManualTriggerPromptUI = require("ui.manual_trigger_prompt_ui")
    end
    return gameplay_cfg.ManualTriggerPromptUI
end

function gameplay_cfg.getShopPackUI()
    if not gameplay_cfg.ShopPackUI then
        gameplay_cfg.ShopPackUI = require("ui.shop_pack_ui")
    end
    return gameplay_cfg.ShopPackUI
end

--- Check if new grid inventory system is enabled
-- @return boolean True if using new grid inventory, false for legacy boards
function gameplay_cfg.isGridInventoryEnabled()
    return gameplay_cfg.USE_GRID_INVENTORY == true
end

-- Expose flag globally for other modules to check without requiring gameplay.lua
_G.USE_GRID_INVENTORY = gameplay_cfg.USE_GRID_INVENTORY

require("core.type_defs") -- for Node customizations
local BaseCreateExecutionContext = WandExecutor.createExecutionContext

-- Cleanup signal handlers to prevent memory leaks on game restart
-- IMPORTANT: Call this BEFORE timer.kill_group() in resetGameToStart()
local function cleanupGameplayHandlers()
    if gameplay_cfg.handlers then
        gameplay_cfg.handlers:cleanup()
        gameplay_cfg.handlers = nil
    end
    -- Reset registration flags so handlers re-register on next init
    gameplay_cfg.messageQueueHooksRegistered = false
    gameplay_cfg.deathFlowHandlersRegistered = false
    gameplay_cfg.bumpEnemyHandlerRegistered = false
    gameplay_cfg.pickupHandlersRegistered = false
    if stats_tooltip then
        stats_tooltip.signalRegistered = false
    end
end

-- Initialize gameplay signal handler group
local function initGameplayHandlers()
    if gameplay_cfg.handlers then return gameplay_cfg.handlers end
    gameplay_cfg.handlers = gameplay_cfg.signal_group.new("gameplay_main")
    return gameplay_cfg.handlers
end

local function ensureMessageQueueHooks()
    if gameplay_cfg.messageQueueHooksRegistered then return end
    gameplay_cfg.messageQueueHooksRegistered = true

    local handlers = initGameplayHandlers()

    local function ensureMQ()
        if not ui_modules.MessageQueueUI.isActive then
            ui_modules.MessageQueueUI.init()
        end
    end

    handlers:on("avatar_unlocked", function(data)
        ensureMQ()
        local avatarId = (data and data.avatar_id) or "Unknown Avatar"
        ui_modules.MessageQueueUI.enqueue(string.format("Avatar unlocked: %s", avatarId))
    end)

    handlers:on("tag_threshold_discovered", function(data)
        ensureMQ()
        local tag = (data and data.tag) or "Tag"
        local threshold = (data and data.threshold) or "?"
        ui_modules.MessageQueueUI.enqueue(string.format("Discovery: %s x%s", tag, threshold))
    end)

    handlers:on("spell_type_discovered", function(data)
        ensureMQ()
        local spell = (data and data.spell_type) or "Spell"
        ui_modules.MessageQueueUI.enqueue(string.format("New spell type: %s", spell))
    end)

    handlers:on("deck_changed", function(data)
        -- Re-evaluate tag thresholds when deck changes (shop purchases, loot, etc.)
        if reevaluateDeckTags then
            reevaluateDeckTags()
        end
        -- Update wand resource bar prediction
        if updateWandResourceBar then
            updateWandResourceBar()
        end
    end)

    handlers:on("wand_trigger_changed", function()
        if reevaluateDeckTags then
            reevaluateDeckTags()
        end
        if updateWandResourceBar then
            updateWandResourceBar()
        end
    end)

    handlers:on("wand_action_changed", function()
        if reevaluateDeckTags then
            reevaluateDeckTags()
        end
        if updateWandResourceBar then
            updateWandResourceBar()
        end
    end)

    handlers:on("wand_selected", function(newIndex)
        if type(newIndex) ~= "number" then return end

        if board_sets and #board_sets > 0 then
            local clamped = math.max(1, math.min(#board_sets, newIndex))
            if clamped ~= current_board_set_index then
                current_board_set_index = clamped
                -- Keep all board sets hidden (only wand selector buttons visible)
                for index, boardSet in ipairs(board_sets) do
                    toggleBoardSetVisibility(boardSet, false)
                end
            end
        else
            current_board_set_index = newIndex
        end

        if reevaluateDeckTags then
            reevaluateDeckTags()
        end
        if updateWandResourceBar then
            updateWandResourceBar()
        end
    end)

    handlers:on("trigger_activated", function(wandId, triggerType)
        if ui_modules.TriggerStripUI and ui_modules.TriggerStripUI.onTriggerActivated then
            ui_modules.TriggerStripUI.onTriggerActivated(wandId, triggerType)
        end
    end)
end

local function fireAvatarDebugEvents()
    if gameplay_cfg.avatarTestEventsFired or not gameplay_cfg.DEBUG_AVATAR_TEST_EVENTS then return end
    gameplay_cfg.avatarTestEventsFired = true

    local testPlayer = {}
    local cards = {}
    for _ = 1, 7 do
        table.insert(cards, { tags = { "Fire" } })
    end

    -- Emits tag discovery + wildfire unlock signals
    TagEvaluator.evaluate_and_apply(testPlayer, { cards = cards })

    -- Unlocks citadel via metric path
    AvatarSystem.record_progress(testPlayer, "damage_blocked", 5000)

    -- Exercise spell discovery hook
    signal.emit("spell_type_discovered", { spell_type = "Twin Cast" })
end



--  let's make some card data
local action_card_defs = {
    {
        id = "fire_basic_bolt", -- at target, or in direction if no target
    },
    {
        id = "leave_spike_hazard",
    },
    {
        id = "temporary_strength_bonus"
    }

}

local trigger_card_defs = {
    {
        id = "every_N_seconds"
    },
    {
        id = "on_pickup"
    },
    {
        id = "on_distance_moved"
    },
    {
        id = "on_bump_enemy"
    },
    {
        id = "on_dash"
    },

}
local modifier_card_defs = {
    {
        id = "double_effect"
    },
    {
        id = "summon_minion_wandering"
    },
    {
        id = "projectile_pierces_twice"
    }
}

-- card sizes: see gameplay_cfg.cardW and gameplay_cfg.cardH


-- save game state strings
REWARD_OPENING_STATE = "REWARD_OPENING"
PLANNING_STATE = "PLANNING"
ACTION_STATE = "SURVIVORS"
SHOP_STATE = "SHOP"
WAND_TOOLTIP_STATE = "WAND_TOOLTIP_STATE" -- we use this to show wand tooltips and hide them when needed.
CARD_TOOLTIP_STATE = "CARD_TOOLTIP_STATE" -- we use this to show card tooltips and hide them when needed.
PLAYER_STATS_TOOLTIP_STATE = "PLAYER_STATS_TOOLTIP_STATE"
DETAILED_STATS_TOOLTIP_STATE = "DETAILED_STATS_TOOLTIP_STATE"
STATS_PANEL_STATE = "STATS_PANEL_STATE"

-- combat context, to be used with the combat system.
combat_context = nil

-- some entities

survivorEntity = nil
survivorMaskEntity = nil
boards = {}
cards = {}
-- NOTE: inventory_board_id and trigger_inventory_board_id removed (Phase 5 cleanup)
-- The new grid inventory system uses PlayerInventory and WandLoadoutUI modules
trigger_board_id_to_action_board_id = {} -- map trigger boards to action boards
trigger_board_id = nil
action_board_id = nil
mouseAimAngle = mouseAimAngle or 0
if globals then globals.mouseAimAngle = globals.mouseAimAngle or mouseAimAngle end

-- ui tooltip cache
wand_tooltip_cache = {}
card_tooltip_cache = {}
card_tooltip_disabled_cache = {}
previously_hovered_tooltip = nil
-- Alt-preview state: show hovered card at top Z while Alt is held
-- Consolidated into a table to stay under Lua's 200 local variable limit
local card_ui_state = {
    alt_entity = nil,       -- Currently previewing entity
    alt_original_z = nil,   -- Original Z to restore
    hovered_card = nil,     -- Currently hovered card for alt/right-click
}

-- Alt-preview and right-click transfer helper functions (using card_ui_state)
local function isAltHeld()
    return input.isKeyDown(KeyboardKey.KEY_LEFT_ALT) or input.isKeyDown(KeyboardKey.KEY_RIGHT_ALT)
end

local function isCtrlHeld()
    return input.isKeyDown(KeyboardKey.KEY_LEFT_CONTROL) or input.isKeyDown(KeyboardKey.KEY_RIGHT_CONTROL)
end

local function isCmdHeld()
    return input.isKeyDown(KeyboardKey.KEY_LEFT_SUPER) or input.isKeyDown(KeyboardKey.KEY_RIGHT_SUPER)
end

local function beginAltPreview(entity)
    if card_ui_state.alt_entity == entity then return end
    if card_ui_state.alt_entity then
        local prevLayerOrder = component_cache.get(card_ui_state.alt_entity, layer.LayerOrderComponent)
        if prevLayerOrder and card_ui_state.alt_original_z then
            prevLayerOrder.zIndex = card_ui_state.alt_original_z
        end
    end
    local layerOrder = component_cache.get(entity, layer.LayerOrderComponent)
    if layerOrder then
        card_ui_state.alt_original_z = layerOrder.zIndex
        layerOrder.zIndex = z_orders.top_card
    end
    card_ui_state.alt_entity = entity
end

local function endAltPreview()
    if not card_ui_state.alt_entity then return end
    local layerOrder = component_cache.get(card_ui_state.alt_entity, layer.LayerOrderComponent)
    if layerOrder and card_ui_state.alt_original_z then
        layerOrder.zIndex = card_ui_state.alt_original_z
    end
    card_ui_state.alt_entity = nil
    card_ui_state.alt_original_z = nil
end

local function updateAltPreview()
    local altHeld = isAltHeld()
    if card_ui_state.alt_entity and not altHeld then
        endAltPreview()
        return
    end
    if altHeld and card_ui_state.hovered_card and not card_ui_state.alt_entity then
        if entity_cache.valid(card_ui_state.hovered_card) then
            beginAltPreview(card_ui_state.hovered_card)
        end
    end
    -- Re-apply z-index every frame while alt-previewing (to counter any overrides)
    if card_ui_state.alt_entity and altHeld and entity_cache.valid(card_ui_state.alt_entity) then
        layer_order_system.assignZIndexToEntity(card_ui_state.alt_entity, z_orders.top_card)
    end
end

-- Forward declaration for transferCardViaRightClick (defined later in file)
local transferCardViaRightClick

local function updateRightClickTransfer()
    if not card_ui_state.hovered_card then return end
    if not entity_cache.valid(card_ui_state.hovered_card) then
        card_ui_state.hovered_card = nil
        return
    end
    -- Right-click or modifier+left-click triggers transfer (ctrl/cmd helps mac)
    local leftClick = input.isMousePressed(MouseButton.MOUSE_BUTTON_LEFT)
    local rightClick = input.isMousePressed(MouseButton.MOUSE_BUTTON_RIGHT)
    local altClick = isAltHeld() and leftClick
    local ctrlClick = isCtrlHeld() and leftClick
    local cmdClick = isCmdHeld() and leftClick
    if rightClick or altClick or ctrlClick or cmdClick then
        log_debug("[Transfer] Click detected (right:", rightClick, "altClick:", altClick, "ctrlClick:", ctrlClick, "cmdClick:", cmdClick, ") on card:", card_ui_state.hovered_card)
        local cardScript = getScriptTableFromEntityID(card_ui_state.hovered_card)
        if cardScript then
            log_debug("[Transfer] Card script found, currentBoard:", cardScript.currentBoardEntity)
            transferCardViaRightClick(card_ui_state.hovered_card, cardScript)
        else
            log_debug("[Transfer] No card script found!")
        end
    end
end

-- Helper to determine inventory tab category from card type
-- Maps card type to PlayerInventory tab category
local function getInventoryCategoryForCard(cardEntity)
    local script = getScriptTableFromEntityID(cardEntity)
    if not script then return "equipment" end

    -- Check explicit type/category fields
    local cardType = script.type or script.category or script.cardType
    if cardType == "trigger" or cardType == "triggers" then
        return "triggers"
    elseif cardType == "action" or cardType == "actions" then
        return "actions"
    elseif cardType == "modifier" or cardType == "modifiers" then
        return "modifiers"
    end

    -- Check isTrigger flag
    if script.isTrigger then
        return "triggers"
    end

    -- Check against WandEngine definitions as fallback
    local cardID = script.cardID or script.id or script.card_id
    if cardID and WandEngine then
        if WandEngine.trigger_card_defs and WandEngine.trigger_card_defs[cardID] then
            return "triggers"
        end
        if WandEngine.card_defs and WandEngine.card_defs[cardID] then
            local def = WandEngine.card_defs[cardID]
            if def.type == "modifier" then
                return "modifiers"
            end
            return "actions"  -- Default for action cards
        end
    end

    return "equipment"  -- default fallback
end

local function hideCardTooltip(entity)
    if not entity or not entity_cache.valid(entity) then
        return
    end
    if USE_TOOLTIP_V2 then
        TooltipV2.hide(entity)
    else
        clear_state_tags(entity)
        ui.box.ClearStateTagsFromUIBox(entity)
    end
end
-- Player stats tooltip state (consolidated to save local slots)
local stats_tooltip = {
    entity = nil,
    detailedEntity = nil,
    version = 0,
    detailedVersion = 0,
    signalRegistered = false,
    makeTooltip = nil,  -- forward declaration
    testStickerInfo = nil,
}

local function make_rect(x, y, w, h)
    if Rectangle and Rectangle.new then
        return Rectangle.new(x, y, w, h)
    end
    return { x = x, y = y, width = w, height = h }
end

-- Safely extract rect components from either sol userdata (Vector4) or plain tables.
local function unpack_rect_like(rectLike, fallbackTable)
    if not rectLike then
        if type(fallbackTable) == "table" then
            return fallbackTable.x or fallbackTable[1] or 0,
                fallbackTable.y or fallbackTable[2] or 0,
                fallbackTable.width or fallbackTable[3] or 32,
                fallbackTable.height or fallbackTable[4] or 32
        end
        return 0, 0, 32, 32
    end

    local x, y, w, h
    if type(rectLike) == "table" then
        x = rectLike.x or rectLike[1] or 0
        y = rectLike.y or rectLike[2] or 0
        w = rectLike.z or rectLike[3] or rectLike.width or 32
        h = rectLike.w or rectLike[4] or rectLike.height or 32
    else
        local ok, rx, ry, rw, rh = pcall(function()
            return rectLike.x, rectLike.y, rectLike.z or rectLike.width, rectLike.w or rectLike.height
        end)
        if ok and rx ~= nil and ry ~= nil and rw ~= nil and rh ~= nil then
            x, y, w, h = rx, ry, rw, rh
        else
            ok, rx, ry, rw, rh = pcall(function()
                return rectLike[1], rectLike[2], rectLike[3], rectLike[4]
            end)
            if ok and rx ~= nil and ry ~= nil and rw ~= nil and rh ~= nil then
                x, y, w, h = rx, ry, rw, rh
            end
        end
    end

    if not (x and y and w and h) and type(fallbackTable) == "table" then
        return fallbackTable.x or fallbackTable[1] or 0,
            fallbackTable.y or fallbackTable[2] or 0,
            fallbackTable.width or fallbackTable[3] or 32,
            fallbackTable.height or fallbackTable[4] or 32
    end

    return x or 0, y or 0, w or 32, h or 32
end

local tooltipStyle = {
    -- COMPACT FONT SIZES (reduced from 22)
    fontSize = 16,              -- Base text size (was 22)
    titleFontSize = 18,         -- Title/header size
    labelFontSize = 14,         -- Label text size
    valueFontSize = 14,         -- Value text size
    
    -- COLORS
    labelBg = "black",
    idBg = "gold",
    idTextColor = "black",
    labelColor = "apricot_cream",
    valueColor = "white",
    
    -- COMPACT PADDING (reduced from original)
    innerPadding = 4,           -- Was 6
    rowPadding = 1,             -- Was 2
    textPadding = 1,            -- Was 2
    pillPadding = 3,            -- Was 4
    outerPadding = 6,           -- Was 10
    
    -- COMPACT COLUMN WIDTHS
    labelColumnMinWidth = 100,  -- Was 140
    valueColumnMinWidth = 60,   -- Was 80
    maxWidth = 280,             -- Max tooltip width
    
    -- BACKGROUND COLORS
    bgColor = Col(18, 22, 32, 255),       -- Fully opaque
    innerColor = Col(28, 32, 44, 255),    -- Fully opaque
    outlineColor = (util.getColor and util.getColor("apricot_cream")) or Col(255, 214, 170, 255),
    
    -- TITLE TEXT EFFECTS (dynamic text from C++ text system)
    -- Available effects: pop, slide, bounce, pulse, float, wiggle, shake, rainbow, fade, highlight
    titleEffects = {
        default = "pop=0.15,0.03,in",                    -- Subtle pop entrance
        card = "slide=0.2,0.02,in,l",                    -- Slide from left
        trigger = "bounce=500,-10,0.35,0.02",            -- Bouncy entrance
        joker = "pop=0.2,0.04,in;float=1.5,2,0.15",      -- Pop + gentle float
        wand = "slide=0.18,0.02,in,r",                   -- Slide from right
        stats = "pop=0.12,0.02,in",                      -- Very subtle pop
    },
    
    -- Named font for tooltip text (loaded below)
    fontName = "tooltip"
}
local TOOLTIP_FONT_VERSION = 2

-- Tooltip font is now configured in fonts.json under namedFonts.tooltip
-- The C++ localization system loads it automatically at startup.
-- This function reloads it when language changes (for language-specific fonts)
local function reloadTooltipFontForLanguage()
    if not (localization and localization.loadFontData) then
        return
    end
    -- Reload fonts.json to pick up the correct language variant
    localization.loadFontData(util.getRawAssetPathNoUUID("localization/fonts.json"))
    TOOLTIP_FONT_VERSION = TOOLTIP_FONT_VERSION + 1
end

-- Register language change callback to reload tooltip font and clear caches
-- This ensures tooltips are rebuilt with the new language's text and font
if localization and localization.onLanguageChanged then
    localization.onLanguageChanged(function(newLang)
        -- Reload fonts.json for new language (picks correct named font variants)
        reloadTooltipFontForLanguage()

        -- Clear all tooltip caches so they get rebuilt with new language
        for id, entity in pairs(card_tooltip_cache or {}) do
            if entity and entity_cache and entity_cache.valid(entity) and registry and registry:valid(entity) then
                registry:destroy(entity)
            end
        end
        for id, entity in pairs(card_tooltip_disabled_cache or {}) do
            if entity and entity_cache and entity_cache.valid(entity) and registry and registry:valid(entity) then
                registry:destroy(entity)
            end
        end
        for id, entity in pairs(wand_tooltip_cache or {}) do
            if entity and entity_cache and entity_cache.valid(entity) and registry and registry:valid(entity) then
                registry:destroy(entity)
            end
        end
        card_tooltip_cache = {}
        card_tooltip_disabled_cache = {}
        wand_tooltip_cache = {}
        previously_hovered_tooltip = nil
        
        if TooltipV2 and TooltipV2.clearCache then
            TooltipV2.clearCache()
        end
    end)
end

-- Helper to get the tooltip font (with fallback)
local function getTooltipFont()
    if localization and localization.hasNamedFont and localization.hasNamedFont(tooltipStyle.fontName) then
        return localization.getNamedFont(tooltipStyle.fontName).font
    end
    return localization and localization.getFont and localization.getFont() or nil
end

-- Build a font attribute suffix only if the tooltip font is available.
local function getTooltipFontAttr()
    if not tooltipStyle.fontName then
        return ""
    end
    if localization and localization.hasNamedFont and localization.hasNamedFont(tooltipStyle.fontName) then
        return ";font=" .. tooltipStyle.fontName
    end
    return ""
end

local function makeTooltipTextDef(text, opts)
    opts = opts or {}

    if opts.coded and ui and ui.definitions then
        local fontSize = opts.fontSize or tooltipStyle.fontSize
        local fontName = opts.fontName or tooltipStyle.fontName
        local textStr = tostring(text)
        
        local dynamicEffects = {
            pop=1, slide=1, bounce=1, float=1, pulse=1, wiggle=1, shake=1, rainbow=1,
            highlight=1, fade=1, scramble=1, spin=1, fan=1, expand=1, rotate=1, bump=1
        }
        
        local function hasAnimEffects(s)
            for eff in pairs(dynamicEffects) do
                if s:find(eff .. "=") or s:find(eff .. ";") or s:find(eff .. "%)") then
                    return true
                end
            end
            return false
        end
        
        if hasAnimEffects(textStr) and ui.definitions.getNewDynamicTextEntry then
            local plainText = textStr:match("%[([^%]]+)%]") or textStr
            
            local params = textStr:match("%]%(([^)]+)%)")
            local effectParts = {}
            if params then
                for part in params:gmatch("([^;]+)") do
                    local effName = part:match("^([^=]+)")
                    if effName and dynamicEffects[effName] then
                        table.insert(effectParts, part)
                    end
                end
            end
            local effectString = #effectParts > 0 and table.concat(effectParts, ";") or nil
            
            local colorName = opts.color
            if type(colorName) ~= "string" then
                colorName = "apricot_cream"
            end
            
            local dynamicText = "[" .. plainText .. "](color=" .. colorName .. ")"
            
            -- getNewDynamicTextEntry expects a function that returns text, not a string directly
            return ui.definitions.getNewDynamicTextEntry(function() return dynamicText end, fontSize, effectString)
        end
        
        if ui.definitions.getTextFromString then
            local wrappedText = textStr:gsub("%]%(([^)]*)%)", function(params)
                local newParams = params
                if not params:find("fontSize=") then
                    newParams = newParams .. ";fontSize=" .. fontSize
                end
                if not params:find("fontName=") and fontName then
                    newParams = newParams .. ";fontName=" .. fontName
                end
                if not params:find("shadow=") then
                    newParams = newParams .. ";shadow=" .. (opts.shadow and "true" or "false")
                end
                return "](" .. newParams .. ")"
            end)

            return ui.definitions.getTextFromString(wrappedText, {
                fontSize = fontSize,
                fontName = fontName,
                color = opts.color or tooltipStyle.valueColor,
                shadow = opts.shadow or false
            })
        end
    end

    return ui.definitions.def {
        type = "TEXT",
        config = {
            text = tostring(text),
            color = opts.color or tooltipStyle.valueColor,
            fontSize = opts.fontSize or tooltipStyle.fontSize,
            fontName = opts.fontName or tooltipStyle.fontName,
            align = opts.align or bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER),
            shadow = opts.shadow or false
        }
    }
end

local function makeTooltipPill(text, opts)
    opts = opts or {}
    local cfg = {
        color = opts.background or tooltipStyle.labelBg,
        padding = opts.padding or tooltipStyle.pillPadding,
        align = opts.align or bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER)
    }
    if opts.minWidth then cfg.minWidth = opts.minWidth end
    
    local displayText = tostring(text)
    local effects = opts.effects or opts.titleEffects
    local useCoded = opts.coded or false
    
    if effects and effects ~= "" then
        local colorName = opts.color
        if type(colorName) ~= "string" then
            colorName = "apricot_cream"
        end
        displayText = "[" .. displayText .. "](" .. effects .. ";color=" .. colorName .. ")"
        useCoded = true
    end
    
    local textOpts = {
        color = opts.color or tooltipStyle.labelColor,
        fontSize = opts.fontSize or tooltipStyle.titleFontSize,
        align = opts.textAlign,
        fontName = opts.fontName or tooltipStyle.fontName,
        shadow = opts.shadow,
        coded = useCoded
    }
    return dsl.strict.hbox {
        config = cfg,
        children = { makeTooltipTextDef(displayText, textOpts) }
    }
end

local function makeTooltipValueBox(text, opts)
    opts = opts or {}
    local cfg = {
        align = opts.align or bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER),
        padding = opts.padding or tooltipStyle.textPadding
    }
    if opts.minWidth then cfg.minWidth = opts.minWidth end
    if opts.maxWidth then cfg.maxWidth = opts.maxWidth end  -- NEW: support text wrapping
    local textOpts = {
        color = opts.color or tooltipStyle.valueColor,
        fontSize = opts.fontSize,
        align = opts.textAlign or opts.align,
        fontName = opts.fontName or tooltipStyle.fontName,
        shadow = opts.shadow,
        coded = opts.coded  -- NEW: pass through coded option
    }
    return dsl.strict.hbox {
        config = cfg,
        children = { makeTooltipTextDef(text, textOpts) }
    }
end

local function makeTooltipRow(label, value, opts)
    opts = opts or {}
    if value == nil then return nil end
    return dsl.strict.hbox {
        config = {
            align = opts.align or bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER),
            padding = opts.rowPadding or tooltipStyle.rowPadding
        },
        children = {
            makeTooltipPill(label, opts.labelOpts),
            makeTooltipValueBox(value, opts.valueOpts)
        }
    }
end

local function destroyTooltipEntity(eid)
    if eid and entity_cache.valid(eid) then
        registry:destroy(eid)
    end
end

-- Forward declare shared tooltip positioning helpers (used by DSL tooltips and other UIs)
local centerTooltipAboveEntity

-- Prevent tooltip boxes from animating from size 0 by snapping visual dimensions immediately.
local function snapTooltipVisual(boxID)
    if not boxID or not entity_cache.valid(boxID) then
        return
    end
    local t = component_cache.get(boxID, Transform)
    if not t then return end
    t.visualX = t.actualX or t.visualX
    t.visualY = t.actualY or t.visualY
    t.visualW = t.actualW or t.visualW
    t.visualH = t.actualH or t.visualH
end

-- Simple tooltip for title + description (jokers, avatars, relics, buttons)
local function makeSimpleTooltip(title, body, opts)
    opts = opts or {}
    local outerPadding = opts.outerPadding or tooltipStyle.outerPadding
    local rows = {}

    local tooltipType = opts.tooltipType or "default"
    local titleEffect = opts.titleEffects
        or (tooltipStyle.titleEffects and tooltipStyle.titleEffects[tooltipType])
        or (tooltipStyle.titleEffects and tooltipStyle.titleEffects.default)

    if title and title ~= "" then
        table.insert(rows, makeTooltipPill(title, {
            background = opts.titleBg or tooltipStyle.labelBg,
            color = opts.titleColor or tooltipStyle.labelColor,
            fontName = opts.titleFont or tooltipStyle.fontName,
            fontSize = opts.titleFontSize or tooltipStyle.titleFontSize,
            effects = titleEffect,
            coded = true,
            padding = tooltipStyle.pillPadding
        }))
    end

    if body and body ~= "" then
        table.insert(rows, makeTooltipValueBox(body, {
            color = opts.bodyColor or tooltipStyle.valueColor,
            fontName = opts.bodyFont or tooltipStyle.fontName,
            fontSize = opts.bodyFontSize or tooltipStyle.valueFontSize,
            coded = opts.bodyCoded,
            maxWidth = opts.maxWidth or tooltipStyle.maxWidth,
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER),
            padding = tooltipStyle.textPadding
        }))
    end

    local innerPad = tooltipStyle.innerPadding
    local v = dsl.strict.vbox {
        config = {
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_TOP),
            color = tooltipStyle.innerColor,
            padding = innerPad,
            spacing = innerPad
        },
        children = rows
    }

    local root = dsl.strict.root {
        config = {
            color = tooltipStyle.bgColor,
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER),
            padding = innerPad,
            outlineThickness = 2,
            outlineColor = tooltipStyle.outlineColor,
            shadow = true
        },
        children = { v }
    }

    local boxID = dsl.spawn({ x = 200, y = 200 }, root)

    ui.box.set_draw_layer(boxID, "ui")
    ui.box.RenewAlignment(registry, boxID)
    snapTooltipVisual(boxID)
    ui.box.ClearStateTagsFromUIBox(boxID)

    return boxID
end

--- Create a tooltip with localized, color-coded text
--- @param key string Localization key
--- @param params table|nil Parameters for substitution (supports {value=X, color="Y"})
--- @param opts table|nil Options: title, maxWidth, titleColor
--- @return number|nil boxID The tooltip entity ID
local function makeLocalizedTooltip(key, params, opts)
    opts = opts or {}

    -- Use styled localization for color markup
    local text = localization.getStyled(key, params)

    return makeSimpleTooltip(
        opts.title or "",
        text,
        {
            bodyCoded = true,  -- Enable [text](effects) parsing
            maxWidth = opts.maxWidth or 320,
            bodyColor = opts.bodyColor,
            bodyFont = opts.bodyFont,
            bodyFontSize = opts.bodyFontSize
        }
    )
end

local function cacheFetch(cache, key)
    local entry = cache[key]
    if not entry then return nil end
    local eid = entry.eid or entry
    local version = entry.version or 0
    if (version ~= TOOLTIP_FONT_VERSION) or not entity_cache.valid(eid) then
        destroyTooltipEntity(eid)
        cache[key] = nil
        return nil
    end
    return eid
end

local function cacheStore(cache, key, eid)
    local existing = cache[key]
    if existing then
        destroyTooltipEntity(existing.eid or existing)
    end
    cache[key] = { eid = eid, version = TOOLTIP_FONT_VERSION }
    return eid
end

-- Cache for simple tooltips (keyed by string key)
local simple_tooltip_cache = {}

-- Ensure a simple tooltip exists (lazy init with caching)
local function ensureSimpleTooltip(key, title, body, opts)
    if not key then return nil end

    local cached = cacheFetch(simple_tooltip_cache, key)
    if cached then return cached end

    local tooltip = makeSimpleTooltip(title, body, opts)
    cacheStore(simple_tooltip_cache, key, tooltip)

    layer_order_system.assignZIndexToEntity(
        tooltip,
        z_orders.ui_tooltips or 1000
    )

    return tooltip
end

-- Show a simple tooltip positioned above an entity
local function showSimpleTooltipAbove(key, title, body, anchorEntity, opts)
    local tooltip = ensureSimpleTooltip(key, title, body, opts)
    if not tooltip then return nil end

    -- Add state tags so the tooltip is visible in the current game state
    -- (makeSimpleTooltip clears state tags, so we must reapply them)
    if ui and ui.box and ui.box.AddStateTagToUIBox then
        ui.box.ClearStateTagsFromUIBox(tooltip)
        if PLANNING_STATE then ui.box.AddStateTagToUIBox(tooltip, PLANNING_STATE) end
        if ACTION_STATE then ui.box.AddStateTagToUIBox(tooltip, ACTION_STATE) end
        if SHOP_STATE then ui.box.AddStateTagToUIBox(tooltip, SHOP_STATE) end
    end

    centerTooltipAboveEntity(tooltip, anchorEntity)
    return tooltip
end

-- Hide a simple tooltip (move offscreen, keep cached)
local function hideSimpleTooltip(key)
    local cached = simple_tooltip_cache[key]
    if not cached then return end
    local eid = cached.eid or cached
    if eid and entity_cache.valid(eid) then
        local t = component_cache.get(eid, Transform)
        if t then
            t.actualY = globals.screenHeight() + 100
            t.visualY = t.actualY
        end
    end
end

-- Destroy all cached simple tooltips (for cleanup)
local function destroyAllSimpleTooltips()
    for key, entry in pairs(simple_tooltip_cache) do
        local eid = entry.eid or entry
        destroyTooltipEntity(eid)
    end
    simple_tooltip_cache = {}
end

centerTooltipAboveEntity = function(tooltipEntity, targetEntity, offset)
    if not tooltipEntity or not targetEntity then return end
    if not entity_cache.valid(tooltipEntity) or not entity_cache.valid(targetEntity) then return end

    ui.box.RenewAlignment(registry, tooltipEntity)

    local tooltipTransform = component_cache.get(tooltipEntity, Transform)
    local targetTransform = component_cache.get(targetEntity, Transform)
    if not tooltipTransform or not targetTransform then return end

    local gap = offset or 12
    local screenW = globals.screenWidth() or 0
    local screenH = globals.screenHeight() or 0
    local anchorX = targetTransform.actualX or 0
    local anchorY = targetTransform.actualY or 0
    local anchorW = targetTransform.actualW or 0
    local anchorH = targetTransform.actualH or 0
    local tooltipW = tooltipTransform.actualW or 0
    local tooltipH = tooltipTransform.actualH or 0

    local x, y

    -- Helper to check if a position would overlap the anchor entity
    local function overlapsAnchor(testX, testY)
        local tooltipRight = testX + tooltipW
        local tooltipBottom = testY + tooltipH
        local anchorRight = anchorX + anchorW
        local anchorBottom = anchorY + anchorH
        -- Check for rectangle intersection
        return testX < anchorRight and tooltipRight > anchorX and
               testY < anchorBottom and tooltipBottom > anchorY
    end

    -- Try positioning ABOVE the card (preferred)
    x = anchorX + anchorW * 0.5 - tooltipW * 0.5
    y = anchorY - tooltipH - gap

    -- Clamp X to screen bounds
    if x < gap then
        x = gap
    elseif x + tooltipW > screenW - gap then
        x = math.max(gap, screenW - tooltipW - gap)
    end

    -- Check if "above" fits without overlapping
    local fitsAbove = (y >= gap) and not overlapsAnchor(x, y)

    if not fitsAbove then
        -- Try positioning BELOW the card
        local belowY = anchorY + anchorH + gap
        local fitsBelow = (belowY + tooltipH <= screenH - gap) and not overlapsAnchor(x, belowY)

        if fitsBelow then
            y = belowY
        else
            -- Try positioning to the RIGHT of the card
            local rightX = anchorX + anchorW + gap
            local rightY = anchorY + anchorH * 0.5 - tooltipH * 0.5
            -- Clamp Y for right position
            if rightY < gap then rightY = gap end
            if rightY + tooltipH > screenH - gap then rightY = math.max(gap, screenH - tooltipH - gap) end

            local fitsRight = (rightX + tooltipW <= screenW - gap) and not overlapsAnchor(rightX, rightY)

            if fitsRight then
                x = rightX
                y = rightY
            else
                -- Try positioning to the LEFT of the card
                local leftX = anchorX - tooltipW - gap
                local leftY = rightY -- same vertical centering
                local fitsLeft = (leftX >= gap) and not overlapsAnchor(leftX, leftY)

                if fitsLeft then
                    x = leftX
                    y = leftY
                else
                    -- Fallback: position below but clamp to screen (may partially overlap)
                    y = anchorY + anchorH + gap
                    if y + tooltipH > screenH - gap then
                        y = math.max(gap, screenH - tooltipH - gap)
                    end
                    -- If still overlapping, push to the side
                    if overlapsAnchor(x, y) then
                        -- Push right if there's more room on the right, else left
                        local roomRight = screenW - (anchorX + anchorW)
                        local roomLeft = anchorX
                        if roomRight >= roomLeft then
                            x = math.min(anchorX + anchorW + gap, screenW - tooltipW - gap)
                        else
                            x = math.max(gap, anchorX - tooltipW - gap)
                        end
                    end
                end
            end
        end
    end

    -- Final safety clamp to screen bounds
    x = math.max(gap, math.min(x, screenW - tooltipW - gap))
    y = math.max(gap, math.min(y, screenH - tooltipH - gap))

    tooltipTransform.actualX = x
    tooltipTransform.actualY = y
    tooltipTransform.visualX = tooltipTransform.actualX
    tooltipTransform.visualY = tooltipTransform.actualY
end

local ensureCardTooltip -- forward declaration

local function positionTooltipRightOfEntity(tooltipEntity, targetEntity, opts)
    if not tooltipEntity or not targetEntity then return end
    if not entity_cache.valid(tooltipEntity) or not entity_cache.valid(targetEntity) then return end

    ui.box.RenewAlignment(registry, tooltipEntity)

    local tooltipTransform = component_cache.get(tooltipEntity, Transform)
    local targetTransform = component_cache.get(targetEntity, Transform)
    if not tooltipTransform or not targetTransform then return end

    local gap = (opts and opts.gap) or 8
    local screenW = globals.screenWidth() or 0
    local screenH = globals.screenHeight() or 0

    local tooltipW = tooltipTransform.actualW or 0
    local tooltipH = tooltipTransform.actualH or 0
    local anchorX = targetTransform.actualX or 0
    local anchorY = targetTransform.actualY or 0
    local anchorW = targetTransform.actualW or 0
    local anchorH = targetTransform.actualH or 0

    local x, y

    -- Helper to check if a position would overlap the anchor entity
    local function overlapsAnchor(testX, testY)
        local tooltipRight = testX + tooltipW
        local tooltipBottom = testY + tooltipH
        local anchorRight = anchorX + anchorW
        local anchorBottom = anchorY + anchorH
        return testX < anchorRight and tooltipRight > anchorX and
               testY < anchorBottom and tooltipBottom > anchorY
    end

    -- Try positioning to the RIGHT (preferred for this function)
    x = anchorX + anchorW + gap
    y = anchorY + anchorH * 0.5 - tooltipH * 0.5

    -- Clamp Y to screen bounds
    if y < gap then y = gap end
    if y + tooltipH > screenH - gap then y = math.max(gap, screenH - tooltipH - gap) end

    local fitsRight = (x + tooltipW <= screenW - gap) and not overlapsAnchor(x, y)

    if not fitsRight then
        -- Try positioning to the LEFT
        local leftX = anchorX - tooltipW - gap
        local fitsLeft = (leftX >= gap) and not overlapsAnchor(leftX, y)

        if fitsLeft then
            x = leftX
        else
            -- Try positioning ABOVE
            local aboveX = anchorX + anchorW * 0.5 - tooltipW * 0.5
            local aboveY = anchorY - tooltipH - gap
            if aboveX < gap then aboveX = gap end
            if aboveX + tooltipW > screenW - gap then aboveX = math.max(gap, screenW - tooltipW - gap) end

            local fitsAbove = (aboveY >= gap) and not overlapsAnchor(aboveX, aboveY)

            if fitsAbove then
                x = aboveX
                y = aboveY
            else
                -- Try positioning BELOW
                local belowY = anchorY + anchorH + gap
                local fitsBelow = (belowY + tooltipH <= screenH - gap) and not overlapsAnchor(aboveX, belowY)

                if fitsBelow then
                    x = aboveX
                    y = belowY
                else
                    -- Fallback: clamp to screen, accept possible overlap
                    if x + tooltipW > screenW - gap then
                        x = math.max(gap, screenW - tooltipW - gap)
                    end
                end
            end
        end
    end

    -- Final safety clamp
    x = math.max(gap, math.min(x, screenW - tooltipW - gap))
    y = math.max(gap, math.min(y, screenH - tooltipH - gap))

    tooltipTransform.actualX = x
    tooltipTransform.actualY = y
    tooltipTransform.visualX = x
    tooltipTransform.visualY = y
end

-- to decide which trigger+action board set is active
board_sets = {}
current_board_set_index = 1

local reevaluateDeckTags -- forward declaration; defined after deck helpers
local relayoutBoardCardsInOrder -- forward declaration; defined at ~line 8044
-- updateWandResourceBar defined as global at line ~6642 (forward decl removed to stay under 200 local limit)

local function notifyDeckChanged(boardEntityID)
    if not boardEntityID then return end

    -- Always relayout the board when cards change
    local board = boards[boardEntityID]
    if board and relayoutBoardCardsInOrder then
        relayoutBoardCardsInOrder(board)
    end

    -- Board set-specific updates (deck tags, resource bar)
    if not board_sets or #board_sets == 0 then return end
    for _, boardSet in ipairs(board_sets) do
        if boardSet.action_board_id == boardEntityID or boardSet.trigger_board_id == boardEntityID then
            if reevaluateDeckTags then
                reevaluateDeckTags()
            end
            if updateWandResourceBar then
                updateWandResourceBar()
            end
            return
        end
    end
end

-- keep track of controller focus
controller_focused_entity = nil

-- shop system state
local shop_system_initialized = false
local shop_board_id = nil
local shop_buy_board_id = nil
local shop_card_entities = {} -- Track shop card entity IDs for cleanup
local active_shop_instance = nil
local AVATAR_PURCHASE_COST = 10
local ensureShopSystemInitialized -- forward declaration so planning init can ensure metadata before card spawn
local tryPurchaseShopCard -- forward declaration


local dash_sfx_list               = {
    "dash_1",
    "dash_2",
    "dash_3",
    "dash_4",
    "dash_5",
    "dash_6",
    "dash_7",
}

local DASH_COOLDOWN_SECONDS       = 2.0 -- how long before the next dash is available
local DASH_LENGTH_SEC             = 0.5 -- how long a single dash lasts
local DASH_BUFFER_WINDOW          = 0.15 -- grace window for queuing a dash near the end of dash/cooldown
local DASH_COYOTE_WINDOW          = 0.1  -- leniency to allow a dash slightly before cooldown fully ends
local STAMINA_TICKER_LINGER       = 1.0 -- how long the stamina bar lingers after refilling
local ENEMY_HEALTH_BAR_LINGER     = 2.0 -- how long enemy health bars stay visible after a hit
local DAMAGE_NUMBER_LIFETIME            = 1.35 -- seconds to keep a floating damage number around
local DAMAGE_NUMBER_VERTICAL_SPEED      = 60   -- initial upward velocity of a damage number
local DAMAGE_NUMBER_HORIZONTAL_JITTER   = 14   -- horizontal scatter when spawning a damage number
local DAMAGE_NUMBER_GRAVITY             = 28   -- downward accel that eases the rise of the numbers
local DAMAGE_NUMBER_FONT_SIZE           = 28
local PLAYER_PROJECTILE_RECOIL_STRENGTH = 120
local PLAYER_PROJECTILE_RECOIL_DECAY    = 0.85
local playerShotRecoil                  = { x = 0, y = 0 }
local AUTO_AIM_RADIUS                   = 1200
local autoAimEnabled                    = autoAimEnabled or (globals and globals.autoAimEnabled) or true
if globals then globals.autoAimEnabled = autoAimEnabled end
local aimSpring = { ox = 0, oy = 0, vx = 0, vy = 0 } -- spring offsets for aim indicator

local EXP_PICKUP_ANIMATION_ID = "exp_pickup.png"
local EXP_PICKUP_SOUNDS = {
    "item_appear_1",
    "item_appear_2",
    "item_appear_3",
    "item_appear_4"
}

local playerDashCooldownRemaining = 0
local playerDashTimeRemaining     = 0
local dashBufferTimer             = 0
local bufferedDashDir             = nil
local playerIsDashing             = false
local playerStaminaTickerTimer    = 0

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Use the global tables created at top of file (required for enemy_factory.lua integration)
local enemyHealthUiState          = _G.enemyHealthUiState              -- eid -> { actor=<combat actor>, visibleUntil=<time> }
local combatActorToEntity         = _G.combatActorToEntity             -- combat actor -> eid (weak keys so actors can be GCd)
local damageNumbers               = {}                                 -- active floating damage numbers
local spawnExpPickupAt            -- forward declaration

local function isLevelUpModalActive()
    return ui_modules.LevelUpScreen and ui_modules.LevelUpScreen.isActive
end

local function kickAimSpring()
    aimSpring.vx = aimSpring.vx + (math.random() * 2 - 1) * 220
    aimSpring.vy = aimSpring.vy + (math.random() * 2 - 1) * 220
end

local function updateAimSpring(dt)
    local k = 280    -- spring stiffness
    local drag = 3.5 -- damping
    aimSpring.vx = aimSpring.vx - k * aimSpring.ox * dt
    aimSpring.vy = aimSpring.vy - k * aimSpring.oy * dt
    aimSpring.vx = aimSpring.vx * math.max(0, 1 - drag * dt)
    aimSpring.vy = aimSpring.vy * math.max(0, 1 - drag * dt)
    aimSpring.ox = aimSpring.ox + aimSpring.vx * dt
    aimSpring.oy = aimSpring.oy + aimSpring.vy * dt
end

local function isEnemyEntity(eid)
    return eid and eid ~= entt_null and eid ~= survivorEntity and enemyHealthUiState[eid]
        and entity_cache.valid(eid)
end

-- Override globals stub with actual implementation
globals.isEnemyEntity = isEnemyEntity

local function findNearestEnemyPosition(px, py, maxDistance)
    local world = PhysicsManager and PhysicsManager.get_world and PhysicsManager.get_world("world")
    if not (physics and physics.GetObjectsInArea and world) then
        return nil
    end

    local radius = maxDistance or AUTO_AIM_RADIUS

    -- Use GetObjectsInArea which correctly returns entity IDs from shape userData
    -- NOTE: point_query_nearest returns shape pointers, not entities, so we can't use it directly
    local candidates = physics.GetObjectsInArea(world, px - radius, py - radius, px + radius, py + radius) or {}
    local bestPos, bestDistSq = nil, nil
    for _, eid in ipairs(candidates) do
        if isEnemyEntity(eid) then
            local t = component_cache.get(eid, Transform)
            if t then
                local ex = (t.actualX or t.visualX or 0) + (t.actualW or t.visualW or 0) * 0.5
                local ey = (t.actualY or t.visualY or 0) + (t.actualH or t.visualH or 0) * 0.5
                local dx, dy = ex - px, ey - py
                local distSq = dx * dx + dy * dy
                -- Also check within circular radius (AABB is just first pass)
                if distSq <= radius * radius and (not bestDistSq or distSq < bestDistSq) then
                    bestDistSq = distSq
                    bestPos = { x = ex, y = ey }
                end
            end
        end
    end

    return bestPos
end

local function isCardOverCapacity(cardScript, cardEntityID)
    if not cardScript then return false end

    local boardEntity = cardScript.currentBoardEntity
    if not boardEntity or not entity_cache.valid(boardEntity) then return false end

    -- NOTE: Legacy inventory_board_id check removed (Phase 5)
    -- Grid inventory handles capacity via inventory_grid.lua

    local board = boards[boardEntity]
    if not board or not board.cards then return false end

    local cardEid = cardEntityID
    if (not cardEid) and cardScript.handle then
        cardEid = cardScript:handle()
    end

    local cardIndex = nil
    for i, cardInBoard in ipairs(board.cards) do
        if cardInBoard == cardEid then
            cardIndex = i
            break
        end
    end
    if not cardIndex then return false end

    local maxCapacity = 1 -- default for trigger boards
    if board_sets then
        for _, boardSet in ipairs(board_sets) do
            if boardSet.action_board_id == boardEntity then
                if boardSet.wandDef and boardSet.wandDef.total_card_slots then
                    maxCapacity = boardSet.wandDef.total_card_slots
                end
                break
            end
        end
    end

    return cardIndex > maxCapacity
end

function addCardToBoard(cardEntityID, boardEntityID)
    if not cardEntityID or cardEntityID == entt_null or not entity_cache.valid(cardEntityID) then return end
    if not boardEntityID or boardEntityID == entt_null or not entity_cache.valid(boardEntityID) then return end
    local board = boards[boardEntityID]
    if not board then return end
    board.cards = board.cards or {}
    board.needsResort = true
    table.insert(board.cards, cardEntityID)
    log_debug("Added card", cardEntityID, "to board", boardEntityID)

    local cardScript = getScriptTableFromEntityID(cardEntityID)
    if cardScript then
        log_debug("Card", cardEntityID, "now on board", boardEntityID)
        cardScript.currentBoardEntity = boardEntityID
    end

    notifyDeckChanged(boardEntityID)
end

function removeCardFromBoard(cardEntityID, boardEntityID)
    if not cardEntityID or cardEntityID == entt_null or not entity_cache.valid(cardEntityID) then return end
    if not boardEntityID or boardEntityID == entt_null or not entity_cache.valid(boardEntityID) then return end
    local board = boards[boardEntityID]
    if not board then return end
    board.cards = board.cards or {}
    board.needsResort = true

    for i, eid in ipairs(board.cards) do
        if eid == cardEntityID then
            table.remove(board.cards, i)
            break
        end
    end

    -- add the state of whatever the current game state is to the card again
    if is_state_active(PLANNING_STATE) then
        add_state_tag(cardEntityID, PLANNING_STATE)
    end

    if is_state_active(ACTION_STATE) then
        add_state_tag(cardEntityID, ACTION_STATE)
    end

    if is_state_active(SHOP_STATE) then
        add_state_tag(cardEntityID, SHOP_STATE)
    end

    notifyDeckChanged(boardEntityID)
end

-- Get the appropriate inventory board for a card type
-- NOTE: Legacy function - returns nil since inventory_board_id removed in Phase 5
-- New grid inventory uses PlayerInventory module instead
local function getInventoryForCardType(cardScript)
    -- Legacy inventory boards no longer exist
    -- Use PlayerInventory.addCard() for grid inventory instead
    return nil
end

-- Get the appropriate active board for a card type
local function getActiveBoardForCardType(cardScript)
    local activeSet = board_sets and board_sets[current_board_set_index]
    if not activeSet then return nil end

    if cardScript.cardType == "trigger" then
        return activeSet.trigger_board_id
    else
        return activeSet.action_board_id
    end
end

-- Check if a board can accept another card
-- NOTE: Legacy inventory_board_id checks removed (Phase 5)
-- Grid inventory handles capacity via inventory_grid.lua
local function canBoardAcceptCard(boardEntityID, cardScript)
    if not boardEntityID or not entity_cache.valid(boardEntityID) then
        return false
    end

    -- Check against wand capacity
    local board = boards[boardEntityID]
    if not board then return false end

    local currentCount = board.cards and #board.cards or 0

    -- Get capacity from the board set's wand definition
    local maxCapacity = 1 -- default for trigger boards
    if board_sets then
        for _, boardSet in ipairs(board_sets) do
            if boardSet.action_board_id == boardEntityID then
                if boardSet.wandDef and boardSet.wandDef.total_card_slots then
                    maxCapacity = boardSet.wandDef.total_card_slots
                end
                break
            elseif boardSet.trigger_board_id == boardEntityID then
                -- Trigger boards: keep default capacity of 1
                break
            end
        end
    end

    return currentCount < maxCapacity
end

-- Transfer card via right-click (assigns to forward-declared local)
-- NOTE: Legacy function - inventory_board_id references removed (Phase 5)
-- Right-click equip now handled by wand_loadout_ui.lua for grid inventory
transferCardViaRightClick = function(cardEntity, cardScript)
    local currentBoard = cardScript.currentBoardEntity
    log_debug("[Transfer] currentBoard:", currentBoard)
    if not currentBoard or not entity_cache.valid(currentBoard) then
        log_debug("[Transfer] No valid current board, aborting")
        return
    end

    local targetBoard
    -- Legacy inventory boards no longer exist - cards on wand boards only
    local isFromInventory = false  -- Grid inventory cards aren't tracked here
    log_debug("[Transfer] isFromInventory:", isFromInventory)

    if isFromInventory then
        targetBoard = getActiveBoardForCardType(cardScript)
    else
        targetBoard = getInventoryForCardType(cardScript)
    end
    log_debug("[Transfer] targetBoard:", targetBoard)

    if not targetBoard or not entity_cache.valid(targetBoard) then
        log_debug("[Transfer] No valid target board, aborting")
        return
    end

    -- Check capacity
    if not canBoardAcceptCard(targetBoard, cardScript) then
        log_debug("[Transfer] Target board full, playing error")
        playSoundEffect("effects", "error_buzz", 0.8)
        return
    end

    -- Transfer
    log_debug("[Transfer] Transferring card!")
    removeCardFromBoard(cardEntity, currentBoard)
    addCardToBoard(cardEntity, targetBoard)

    -- Clear selection state
    cardScript.selected = false
    local nodeComp = component_cache.get(cardEntity, GameObject)
    if nodeComp then
        nodeComp.state.isBeingFocused = false
    end

    -- Play feedback sound
    playSoundEffect("effects", "card_put_down_1", 0.9)
end

-- Moves all selected cards from the inventory board to the current set's action board.
-- NOTE: Legacy function - inventory_board_id removed in Phase 5
-- Grid inventory uses WandLoadoutUI for card equipping
function sendSelectedInventoryCardsToActiveActionBoard()
    -- Legacy inventory board no longer exists
    -- Use WandLoadoutUI for equipping cards from grid inventory
    log_debug("[Transfer] sendSelectedInventoryCardsToActiveActionBoard: Legacy function, no-op")
    return false
end

function resetCardStackZOrder(rootCardEntityID)
    local rootCardScript = getScriptTableFromEntityID(rootCardEntityID)
    if not rootCardScript or not rootCardScript.cardStack then return end
    local baseZ = z_orders.card

    -- give root entity the base z order
    layer_order_system.assignZIndexToEntity(rootCardScript:handle(), baseZ)

    -- now for every card in the stack, give it a z order above the root
    for i, stackedCardEid in ipairs(rootCardScript.cardStack) do
        if stackedCardEid and entity_cache.valid(stackedCardEid) then
            local stackedTransform = component_cache.get(stackedCardEid, Transform)
            local zi = baseZ + (i) -- root is baseZ, first stacked card is baseZ + 1, etc
            layer_order_system.assignZIndexToEntity(stackedCardEid, zi)
        end
    end
end

function createNewBoard(x, y, w, h)
    local board = BoardType {}

    ------------------------------------------------------------
    -- Swap positions between a selected card and its neighbor
    ------------------------------------------------------------

    board.z_orders = { bottom = z_orders.card, top = z_orders.card + 1000 } -- save specific z orders for the card in the board.
    board.z_order_cache_per_card = {}                                       -- cache for z orders per card entity id.
    board.cards = {}                                                        -- no starting cards

    board:attach_ecs { create_new = true }
    transform.CreateOrEmplace(registry, globals.gameWorldContainerEntity(), x, y, w, h, board:handle())
    boards[board:handle()] = board
    -- add_state_tag(board:handle(), PLANNING_STATE)

    -- get the game object for board and make it onReleaseEnabled
    local boardGameObject = component_cache.get(board:handle(), GameObject)
    if boardGameObject then
        boardGameObject.state.hoverEnabled = true
        boardGameObject.state.triggerOnReleaseEnabled = true
        boardGameObject.state.collisionEnabled = true
    end
    -- give onRelease method to the board
    boardGameObject.methods.onRelease = function(registry, releasedOn, released)
        log_debug("Entity", released, "released on", releasedOn)

        -- when released on top of a board, add self to that board's card list

        -- is the released entity a card?
        local releasedCardScript = getScriptTableFromEntityID(released)
        if not releasedCardScript then return end

        -- check that it isn't already in this board
        for _, eid in ipairs(board.cards) do
            if eid == released then
                log_debug("released card is already in this board, not adding again")
                return
            end
        end

        -- TODO: check it isn't part of a stack. if it is, add to the board only if it's the root entity of the stack.
        if releasedCardScript.stackRootEntity and releasedCardScript.stackRootEntity ~= released then
            log_debug("released card is part of a stack, and is not the root. not adding to board")
            return
        end


        -- remove it from any existing board it may be in
        for boardEid, boardScript in pairs(boards) do
            if boardScript and boardScript.cards then
                for i, eid in ipairs(boardScript.cards) do
                    if eid == released then
                        table.remove(boardScript.cards, i)
                        notifyDeckChanged(boardEid)
                        break
                    end
                end
            end
        end

        -- add it to this board
        addCardToBoard(released, board:handle())

        -- if this card was part of a stack, reset the z-orders of the stack
        if releasedCardScript.stackRootEntity and releasedCardScript.stackRootEntity == released then
            resetCardStackZOrder(releasedCardScript:handle())
        end

        -- reset card selected state
        releasedCardScript.selected = false
    end

    return board:handle()
end

function addCardToStack(rootCardScript, cardScriptToAdd)
    if not rootCardScript or not rootCardScript.cardStack then return false end
    for _, cardEid in ipairs(rootCardScript.cardStack) do
        if cardEid == cardScriptToAdd:handle() then
            log_debug("card is already in the stack, not adding again")
            return false
        end
    end

    -- only let action mods stack on top of actions
    if rootCardScript.category == "action" and cardScriptToAdd.category ~= "modifier" then
        log_debug("can only stack modifier cards on top of action cards")
        return false
    end

    -- don't let mods stack on other mods or triggers
    if rootCardScript.category == "modifier" then
        log_debug("cannot stack on top of modifier cards")
        return false
    end

    -- don't let actions stack on other actions or triggers
    if rootCardScript.category == "trigger" then
        log_debug("cannot stack on top of trigger cards")
        return false
    end



    table.insert(rootCardScript.cardStack, cardScriptToAdd:handle())
    -- also store a reference to the root entity in self
    cardScriptToAdd.stackRootEntity = rootCardScript:handle()
    -- mark as stack child
    cardScriptToAdd.isStackChild = true
end

function removeCardFromStack(rootCardScript, cardScriptToRemove)
    if not rootCardScript or not rootCardScript.cardStack then return end

    -- is the card the root of a stack? then remove all children
    if rootCardScript.stackRootEntity == rootCardScript:handle() then
        for _, cardEid in ipairs(rootCardScript.cardStack) do
            local childCardScript = getScriptTableFromEntityID(cardEid)
            if childCardScript then
                childCardScript.stackRootEntity = nil
                childCardScript.isStackChild = false
            end
        end
        rootCardScript.cardStack = {}
        return
    end

    for i, cardEid in ipairs(rootCardScript.cardStack) do
        if cardEid == cardScriptToRemove:handle() then
            table.remove(rootCardScript.cardStack, i)
            -- also clear the reference to the root entity in self
            cardScriptToRemove.stackRootEntity = nil
            -- unmark as stack child
            cardScriptToRemove.isStackChild = false
            return
        end
    end
end

-- creates a new trigger slot card. these go in trigger boards ONLY.
function createNewTriggerSlotCard(id, x, y, gameStateToApply)
    local card = createNewCard(id, x, y, gameStateToApply)

    local cardScript = getScriptTableFromEntityID(card)
    if not cardScript then
        log_error("createNewTriggerSlotCard: Failed to get script for card entity")
        return card
    end

    WandEngine.apply_card_properties(cardScript, WandEngine.trigger_card_defs[id] or {})

    return card
end

function transitionInOutCircle(duration, messageKey, color, startPosition)
    local TransitionType = Node:extend()

    TransitionType.age = 0
    TransitionType.duration = duration or 1.0
    TransitionType.messageKey = messageKey or ""  -- Store the localization key instead of resolved text
    TransitionType.color = color or palette.getColor("gray")
    TransitionType.radius = 0
    TransitionType.x = startPosition.x or globals.getScreenWidth() * 0.5
    TransitionType.y = startPosition.y or globals.getScreenHeight() * 0.5
    TransitionType.textScale = 0
    TransitionType.fontSize = 48




    function TransitionType:init()
        -- a circle that will expand to fill the screen in duration * 0.3 (tween cubic) from startPosition

        timer.tween_fields(duration * 0.3, self,
            { radius = math.sqrt(globals.screenWidth() ^ 2 + globals.screenHeight() ^ 2) }, Easing.inOutCubic.f, nil,
            "transition_circle_expand", "ui")

        -- spawn text in center after duration * 0.1, scaling up from 0 to 1 in duration * 0.2 (tween cubic).
        timer.after(duration * 0.05, function()
            timer.tween_fields(duration * 0.2, self, { textScale = 1.0 }, Easing.inOutCubic.f, nil,
                "transition_text_scale_up", "ui")
        end, "transition_text_delay", "ui")

        -- at duration * 0.7, start shrinking circle back to center.
        timer.after(duration * 0.7, function()
            timer.tween_fields(duration * 0.3, self, { radius = 0 }, Easing.inOutCubic.f, nil, "transition_circle_shrink",
                "ui")
        end, "transition_circle_shrink_delay", "ui")

        timer.after(duration * 0.8, function()
            playSoundEffect("effects", "transition_whoosh_out", 1.0)
        end, "transition_sound_delay", "ui")

        -- at duration 0.9, scale text back down to 0.
        timer.after(duration * 0.9, function()
            timer.tween_fields(duration * 0.1, self, { textScale = 0.0 }, Easing.inOutCubic.f, nil,
                "transition_text_scale_down", "ui")
        end, "transition_text_scale_down_delay", "ui")

        playSoundEffect("effects", "transition_whoosh", 1.0)
    end

    function TransitionType:update(dt)
        self.age = self.age + dt
        -- float x, y, rx, ry;
        -- Color color = WHITE;
        -- std::optional<float> lineWidth = std::nullopt; // If set, draw outline with this width; else filled
        -- draw a filled circle with radius.
        command_buffer.queueDrawCenteredEllipse(layers.sprites, function(c)
            c.x = self.x
            c.y = self.y
            c.rx = self.radius
            c.ry = self.radius
            c.color = self.color
        end, z_orders.ui_transition, layer.DrawCommandSpace.Screen)

        -- Resolve the localized text dynamically each frame so it updates when language changes
        local message = localization.get(self.messageKey)
        local textW = localization.getTextWidthWithCurrentFont(message, self.fontSize, 1)
        -- scale text
        command_buffer.queueDrawText(layers.sprites, function(c)
            c.text = message
            c.font = localization.getFont()
            c.x = globals.screenWidth() * 0.5 - textW * 0.5 * self.textScale
            c.y = globals.screenHeight() * 0.5 - (self.fontSize * self.textScale) * 0.5
            c.color = util.getColor("white")
            c.fontSize = self.fontSize * self.textScale
        end, z_orders.ui_transition + 1, layer.DrawCommandSpace.Screen)
    end

    function TransitionType:destroy()
        -- playSoundEffect("effects", "transition_whoosh_out", 1.0)
    end

    local transition = TransitionType {}
        :attach_ecs { create_new = true }
        :addStateTag(PLANNING_STATE)
        :addStateTag(ACTION_STATE)
        :addStateTag(SHOP_STATE) -- make them function in all states
        :destroy_when(function(self, eid) return self.age >= self.duration end)
end

function transitionGoldInterest(duration, startingGold, interestEarned)
    local TransitionType = Node:extend()

    TransitionType.age = 0
    TransitionType.duration = duration or 1.35
    TransitionType.radius = 0
    TransitionType.textScale = 0
    TransitionType.centerX = globals.screenWidth() * 0.5
    TransitionType.centerY = globals.screenHeight() * 0.5
    TransitionType.color = util.getColor("black")
    TransitionType.accent = util.getColor("gold")
    TransitionType.startingGold = math.floor(startingGold or globals.currency or 0)
    TransitionType.interest = math.floor(interestEarned or 0)
    TransitionType.displayGold = TransitionType.startingGold
    TransitionType.targetGold = TransitionType.startingGold + TransitionType.interest
    TransitionType.interestPulse = 0
    TransitionType.titleKey = "ui.banked_gold_title"  -- Store localization key instead of resolved text

    function TransitionType:init()
        local maxRadius = math.sqrt(globals.screenWidth() ^ 2 + globals.screenHeight() ^ 2)

        timer.tween_fields(self.duration * 0.28, self,
            { radius = maxRadius }, Easing.outCubic.f, nil, "gold_transition_expand", "ui")

        timer.tween_fields(self.duration * 0.24, self, { textScale = 1.0 }, Easing.outBack.f, nil,
            "gold_transition_text", "ui")

        timer.tween_fields(self.duration * 0.55, self, { displayGold = self.targetGold }, Easing.inOutQuad.f, nil,
            "gold_transition_count", "ui")

        timer.after(self.duration * 0.42, function()
            self.interestPulse = 1.0
            if self.interest > 0 and playSoundEffect then
                playSoundEffect("effects", "gold-gain", 1.0)
            end
        end, "gold_transition_ping", "ui")

        timer.after(self.duration * 0.7, function()
            timer.tween_fields(self.duration * 0.26, self, { radius = 0, textScale = 0.0 }, Easing.inOutCubic.f, nil,
                "gold_transition_shrink", "ui")
        end, "gold_transition_shrink_delay", "ui")

        if playSoundEffect then
            playSoundEffect("effects", "transition_whoosh", 0.9)
        end
    end

    function TransitionType:update(dt)
        self.age = self.age + dt
        self.interestPulse = math.max(0, self.interestPulse - dt * 3.0)

        local alpha = 1.0
        if self.age > self.duration * 0.8 then
            alpha = math.max(0, 1 - (self.age - self.duration * 0.8) / (self.duration * 0.2))
        end

        command_buffer.queueDrawCenteredEllipse(layers.sprites, function(c)
            c.x = self.centerX
            c.y = self.centerY
            c.rx = self.radius
            c.ry = self.radius
            c.color = Col(self.color.r, self.color.g, self.color.b, math.floor(235 * alpha))
        end, z_orders.ui_transition, layer.DrawCommandSpace.Screen)

        local font = localization.getFont()
        local labelSize = 20 * self.textScale
        local amountSize = 46 * self.textScale
        local interestSize = (24 + self.interestPulse * 6) * self.textScale

        -- Resolve the localized text dynamically each frame so it updates when language changes
        local title = localization.get(self.titleKey)
        command_buffer.queueDrawText(layers.sprites, function(c)
            c.text = title
            c.font = font
            c.x = self.centerX - localization.getTextWidthWithCurrentFont(title, labelSize, 1) * 0.5
            c.y = self.centerY - 64 * self.textScale
            c.color = Col(self.accent.r, self.accent.g, self.accent.b, 220)
            c.fontSize = labelSize
        end, z_orders.ui_transition + 1, layer.DrawCommandSpace.Screen)

        local amountText = tostring(math.floor(self.displayGold + 0.5))
        command_buffer.queueDrawText(layers.sprites, function(c)
            c.text = amountText
            c.font = font
            c.x = self.centerX - localization.getTextWidthWithCurrentFont(amountText, amountSize, 1) * 0.5
            c.y = self.centerY - amountSize * 0.5
            c.color = self.accent
            c.fontSize = amountSize
        end, z_orders.ui_transition + 1, layer.DrawCommandSpace.Screen)

        local interestLabel = string.format("+%d interest", self.interest)
        command_buffer.queueDrawText(layers.sprites, function(c)
            c.text = interestLabel
            c.font = font
            c.x = self.centerX - localization.getTextWidthWithCurrentFont(interestLabel, interestSize, 1) * 0.5
            c.y = self.centerY + 24 * self.textScale - self.interestPulse * 6
            c.color = Col(self.accent.r, self.accent.g, self.accent.b, 220)
            c.fontSize = interestSize
        end, z_orders.ui_transition + 1, layer.DrawCommandSpace.Screen)
    end

    local transition = TransitionType {}
        :attach_ecs { create_new = true }
        :addStateTag(PLANNING_STATE)
        :addStateTag(ACTION_STATE)
        :addStateTag(SHOP_STATE)
        :destroy_when(function(self, eid) return self.age >= self.duration end)
end

function setUpCardAndWandStatDisplay()
    local STAT_FONT_SIZE = 27




    local bumper_l = "xbox_lb.png"
    local bumper_r = "xbox_rb.png"
    local trigger_l = "xbox_lt.png"
    local trigger_r = "xbox_rt.png"
    local button_a = "xbox_button_color_a.png"
    local button_b = "xbox_button_color_b.png"
    local button_x = "xbox_button_color_x.png"
    local button_y = "xbox_button_color_y.png"
    local left_stick = "xbox_stick_top_l.png"
    local right_stick = "xbox_stick_top_r.png"
    local d_pad = "xbox_dpad.png"
    local plus = "flair_plus.png"



    -- Changed from timer.run() to timer.run_every_render_frame() to fix flickering
    timer.run_every_render_frame(function()
        -- bail if not shop or planning state
        if not is_state_active(PLANNING_STATE) and not is_state_active(SHOP_STATE) then
            return
        end

        -- TODO: controller prompts

        -- get current board set
        local boardSet = board_sets[current_board_set_index]
        if not boardSet then return end

        --TODO: assign a "wand" to each board set and display stats.


        -- is the mouse covering over a card?

        local isHoveredOverCard = false


        if ensure_entity(globals.inputState.cursor_hovering_target) then
            for cardEid, cardScript in pairs(cards) do
                if cardEid == globals.inputState.cursor_hovering_target then
                    isHoveredOverCard = true
                    break
                end
            end
        end

        local hovered = globals.inputState.cursor_hovering_target

        local startY = globals.screenHeight() - globals.screenHeight() * 0.28
        local startX = globals.screenWidth() * 0.1
        local currentY = startY
        local columnWidth = 400
        local currentX = startX

        if isHoveredOverCard then
            -- if mousing over card, show card stats.
            local cardScript = getScriptTableFromEntityID(hovered)
            if not cardScript then return end

            -- draw:
            -- id = "TEST_PROJECTILE_TIMER",
            -- type = "action",
            -- max_uses = -1,
            -- mana_cost = 8,
            -- damage = 15,
            -- damage_type = "physical",
            -- radius_of_effect = 0,
            -- spread_angle = 3,
            -- projectile_speed = 400,
            -- lifetime = 3000,
            -- cast_delay = 150,
            -- recharge_time = 0,
            -- spread_modifier = 0,
            -- speed_modifier = 0,
            -- lifetime_modifier = 0,
            -- critical_hit_chance_modifier = 0,
            -- timer_ms = 1000,
            -- weight = 2,
            -- test_label = "TEST\nprojectile\ntimer",

            local statsToDraw = { "card_id", "type", "max_uses", "mana_cost", "damage", "damage_type", "radius_of_effect",
                "spread_angle", "projectile_speed", "lifetime", "cast_delay", "recharge_time", "timer_ms" }

            local lineHeight = 22

            -- if nil, don't draw.
            -- if reached bottom, reset to next column
            for _, statName in ipairs(statsToDraw) do
                local statValue = cardScript[statName]
                if statValue ~= nil then
                    command_buffer.queueDrawText(layers.sprites, function(c)
                        c.text = tostring(statName) .. ": " .. tostring(statValue)
                        c.font = localization.getFont()
                        c.x = currentX
                        c.y = currentY
                        c.color = util.getColor("YELLOW")
                        c.fontSize = STAT_FONT_SIZE
                    end, z_orders.card_text, layer.DrawCommandSpace.World)

                    currentY = currentY + lineHeight
                    if currentY > globals.screenHeight() - 50 then
                        currentY = startY
                        currentX = currentX + columnWidth
                    end
                end
            end
        else
            -- else, show wand stats.

            local currentWandDef = board_sets[current_board_set_index].wand_def

            if currentWandDef then
                local statsToDraw = {
                    "id",
                    "type",
                    "max_uses",
                    "mana_max",
                    "mana_recharge_rate",
                    "cast_block_size",
                    "cast_delay",
                    "recharge_time",
                    "spread_angle",
                    "shuffle",
                    "total_card_slots",
                    "always_cast_cards"
                }

                local lineHeight = 22

                -- if nil, don't draw.
                -- if reached bottom, reset to next column
                for _, statName in ipairs(statsToDraw) do
                    local statValue = currentWandDef[statName]

                    -- if it is a table, convert to string
                    if type(statValue) == "table" then
                        statValue = table.concat(statValue, ", ")
                    end

                    if statValue ~= nil then
                        command_buffer.queueDrawText(layers.sprites, function(c)
                            c.text = tostring(statName) .. ": " .. tostring(statValue)
                            c.font = localization.getFont()
                            c.x = currentX
                            c.y = currentY
                            c.color = util.getColor("CYAN")
                            c.fontSize = STAT_FONT_SIZE
                        end, z_orders.card_text, layer.DrawCommandSpace.World)

                        currentY = currentY + lineHeight
                        if currentY > globals.screenHeight() - 50 then
                            currentY = startY
                            currentX = currentX + columnWidth
                        end
                    end
                end

                -- Overheat Visualization
                if WandExecutor and WandExecutor.wandStates then
                    local wandState = WandExecutor.wandStates[currentWandDef.id]
                    if wandState and wandState.currentMana < 0 then
                        command_buffer.queueDrawText(layers.sprites, function(c)
                            c.text = localization.get("ui.wand_overheat")
                            c.font = localization.getFont()
                            c.x = currentX
                            c.y = currentY + lineHeight
                            c.color = util.getColor("RED")
                            c.fontSize = STAT_FONT_SIZE * 1.5
                        end, z_orders.card_text, layer.DrawCommandSpace.World)

                        -- Draw deficit
                        command_buffer.queueDrawText(layers.sprites, function(c)
                            c.text = localization.get("ui.wand_flux_deficit",
                                { amount = string.format("%.1f", math.abs(wandState.currentMana)) })
                            c.font = localization.getFont()
                            c.x = currentX
                            c.y = currentY + lineHeight * 2.5
                            c.color = util.getColor("ORANGE")
                            c.fontSize = STAT_FONT_SIZE
                        end, z_orders.card_text, layer.DrawCommandSpace.World)
                    end
                end
            end
        end


        --TODO: make these prettier with dynamic text later.
    end)
end

-- any card that goes in an action board. NOT TRIGGERS.
-- retursn the entity ID of the created card
function createNewCard(id, x, y, gameStateToApply)
    local card_def = WandEngine.card_defs[id] or WandEngine.trigger_card_defs[id] or {}
    local imageToUse = card_def.sprite or "sample_card.png"
    -- local imageToUse = "3500-TheRoguelike_1_10_alpha_293.png"
    -- local imageToUse = "b1822.png"
    -- if category == "action" then
    --     imageToUse = "action_card_placeholder.png"
    -- elseif category == "trigger" then
    --     imageToUse = "trigger_card_placeholder.png"
    -- elseif category == "modifier" then
    --     imageToUse = "mod_card_placeholder.png"
    -- else
    --     log_debug("Invalid category for createNewCard:", category)
    --     return nil
    -- end

    local card = animation_system.createAnimatedObjectWithTransform(
        imageToUse, -- animation ID
        true        -- use animation, not sprite identifier, if false
    )

    -- give card state tag
    add_state_tag(card, gameStateToApply or PLANNING_STATE)
    remove_default_state_tag(card)
    
    -- give a script table
    local CardType = Node:extend()
    local cardScript = CardType {}

    -- cardScript.isStackable = isStackable or false -- whether this card can be stacked on other cards, default true

    -- save category and id
    cardScript.category = category
    cardScript.cardID = id or "unknown"
    cardScript.selected = false
    cardScript.skewSeed = math.random() * 10000

    -- copy over card definition data if it exists
    if not id then
        log_debug("Warning: createNewCard called without id")
    else
        WandEngine.apply_card_properties(cardScript, WandEngine.card_defs[id] or {})
    end



    -- give an update table to align the card's stacks if they exist.
    -- cardScript.update = function(self, dt)
    --     local eid = self:handle()



    --     -- command_buffer.queuePushObjectTransformsToMatrix(layers.sprites, function (c)
    --     --     c.entity = eid
    --     -- end, z_orders.card_text, layer.DrawCommandSpace.World)

    --     -- draw debug label.
    --     command_buffer.queueDrawText(layers.sprites, function(c)
    --         local cardScript = getScriptTableFromEntityID(eid)
    --         local t = component_cache.get(eid, Transform)
    --         c.text = cardScript.test_label or "unknown"
    --         c.font = localization.getFont()
    --         c.x = t.visualX
    --         c.y = t.visualY
    --         c.color = util.getColor("BLACK")
    --         c.fontSize = 25.0
    --     end, z_orders.card_text, layer.DrawCommandSpace.World)

    --     -- command_buffer.queuePopMatrix(layers.sprites, function () end, z_orders.card_text, layer.DrawCommandSpace.World)

    -- end

    -- attach ecs must be called after defining the callbacks.
    cardScript:attach_ecs { create_new = false, existing_entity = card }

    -- add to cards table
    cards[cardScript:handle()] = cardScript

    -- if card update timer doens't exist, add it.
    if not timer.get_timer_and_delay("card_render_timer") then
        -- Changed from timer.run() to timer.run_every_render_frame() to fix flickering
        timer.run_every_render_frame(function()
                -- log_debug("Card Render Timer Tick")
                -- tracy.zoneBeginN("Card Render Timer Tick") -- just some default depth to avoid bugs
                -- bail if not shop or planning state
                if not is_state_active(PLANNING_STATE) and not is_state_active(SHOP_STATE) then
                    return
                end

                local dt = (GetFrameTime and GetFrameTime()) or 0.016

                -- Collect cards for batched shader rendering (reduces per-pass overhead).
                local batchedCardBuckets = {}
                local cardZCache = {}

                if command_buffer and command_buffer.queueDrawBatchedEntities and layers and layers.sprites
                    and registry and registry.valid then
                    for eid, cardScript in pairs(cards) do
                        if eid and entity_cache.valid(eid) and entity_cache.active(eid) and registry:valid(eid) then
                            local hasPipeline = shader_pipeline and shader_pipeline.ShaderPipelineComponent
                                and registry:has(eid, shader_pipeline.ShaderPipelineComponent)
                            local animComp = component_cache.get(eid, AnimationQueueComponent)
                            if animComp then
                                animComp.drawWithLegacyPipeline = true
                            end
                            if hasPipeline and animComp and not animComp.noDraw then
                                local zToUse = layer_order_system.getZIndex(eid)
                                if cardScript and cardScript.isBeingDragged then
                                    zToUse = z_orders.top_card + 2
                                end
                                cardZCache[eid] = zToUse

                                local bucket = batchedCardBuckets[zToUse]
                                if not bucket then
                                    bucket = {}
                                    batchedCardBuckets[zToUse] = bucket
                                end
                                bucket[#bucket + 1] = eid
                                animComp.drawWithLegacyPipeline = false
                            end
                        end
                    end

                    if next(batchedCardBuckets) then
                        local zKeys = {}
                        for z, entityList in pairs(batchedCardBuckets) do
                            if #entityList > 0 then
                                table.insert(zKeys, z)
                            end
                        end
                        table.sort(zKeys)

                        for _, z in ipairs(zKeys) do
                            local entityList = batchedCardBuckets[z]
                            if entityList and #entityList > 0 then
                                command_buffer.queueDrawBatchedEntities(layers.sprites, function(cmd)
                                    cmd.registry = registry
                                    cmd.entities = entityList
                                    cmd.autoOptimize = true
                                end, z, layer.DrawCommandSpace.Screen)
                            end
                        end
                    end
                end

                -- loop through cards.
                for eid, cardScript in pairs(cards) do
                    if eid and entity_cache.valid(eid) then
                        -- bail if entity not active
                        if not entity_cache.active(eid) then
                            goto continue
                        end

                        local go = component_cache.get(eid, GameObject)
                        if go then
                            go.state.isBeingFocused = cardScript.selected and true or false
                        end

                        local t = component_cache.get(eid, Transform)
                        if t then
                            local colorToUse = util.getColor("RED")
                            if cardScript.type == "trigger" then
                                colorToUse = util.getColor("PURPLE")
                            end
                            -- command_buffer.queuePushObjectTransformsToMatrix(layers.sprites, function (c)
                            --     c.entity = eid
                            -- end, z_orders.card_text, layer.DrawCommandSpace.World)


                            -- command_buffer.queuePopMatrix(layers.sprites, function () end, z_orders.card_text, layer.DrawCommandSpace.World)

                            -- this will draw in local space of the card, hopefully.
                            local zToUse = cardZCache[eid] or layer_order_system.getZIndex(eid)
                            if not cardZCache[eid] and cardScript.isBeingDragged then
                                zToUse = z_orders.top_card + 2 -- force on top if being dragged
                                log_debug("Card", eid, "is being dragged, forcing z to", zToUse, "from",
                                    layer_order_system.getZIndex(eid))
                            end

                            -- check if card is over capacity on its board
                            local isOverCapacity = isCardOverCapacity(cardScript, eid)
                            cardScript.isDisabled = isOverCapacity

                            -- only show text label and sticker for cards without custom sprites
                            if not cardScript.sprite then
                                -- inject card label into the batched shader pipeline (local space, shaded)
                                shader_draw_commands.add_local_command(
                                    registry, eid, "text_pro",
                                    function(c)
                                        c.text = cardScript.test_label or "unknown"
                                        c.font = localization.getFont()
                                        c.x = t.visualW * 0.1
                                        c.y = t.visualH * 0.1
                                        c.origin = _G.Vector2 and _G.Vector2(0, 0) or { x = 0, y = 0 }
                                        c.rotation = 0
                                        c.fontSize = 20.0
                                        c.spacing = 1.0
                                        c.color = colorToUse
                                    end,
                                    1, -- z >= 0 to draw after sprite
                                    layer.DrawCommandSpace.World, -- keep in world space with the card
                                    true -- force text pass (uses uv_passthrough in 3d_skew)
                                )

                                if not stats_tooltip.testStickerInfo then
                                    stats_tooltip.testStickerInfo = getSpriteFrameTextureInfo("b138.png")
                                end
                                if stats_tooltip.testStickerInfo then
                                    shader_draw_commands.add_local_command(
                                        registry, eid, "texture_pro",
                                        function(c)
                                            local size = (t and t.visualW or 32) * 0.22
                                            local vec = (_G.Vector2 and _G.Vector2(size, size)) or { x = size, y = size }
                                            local center = (_G.Vector2 and _G.Vector2(size * 0.5, size * 0.5)) or { x = size * 0.5, y = size * 0.5 }
                                            c.texture = stats_tooltip.testStickerInfo.atlas
                                            local x, y, w, h = unpack_rect_like(stats_tooltip.testStickerInfo.gridRect, stats_tooltip.testStickerInfo.frame)
                                            c.source = make_rect(x, y, w, h)
                                            c.offsetX = (t and t.visualW or 0) * 0.5 - size * 0.5
                                            c.offsetY = (t and t.visualH or 0) * 0.1
                                            c.size = vec
                                            c.rotationCenter = center
                                            c.rotation = 0
                                            c.color = (_G.WHITE or Col(255, 255, 255, 255))
                                        end,
                                        2, -- draw above the text label
                                        layer.DrawCommandSpace.World,
                                        false, -- text pass (leave false; we use sticker pass instead)
                                        true, -- force uv_passthrough in 3d_skew to clamp within atlas subrect
                                        true -- sticker pass: identity atlas, after overlays
                                    )
                                end
                            end

                            -- slightly above the card sprite
                            command_buffer.queueScopedTransformCompositeRender(layers.sprites, eid, function()
                                -- if over capacity, gray overlay + disabled marker
                                if isOverCapacity and not cardScript.isBeingDragged then
                                    local xSize = math.min(t.actualW, t.actualH) * 0.6
                                    local centerX = t.actualW * 0.5
                                    local centerY = t.actualH * 0.5
                                    local thickness = 8
                                    local xColor = util.getColor("red")

                                    command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                                        c.x = centerX
                                        c.y = centerY
                                        c.w = t.actualW
                                        c.h = t.actualH
                                        c.rx = 12
                                        c.ry = 12
                                        c.color = Col(18, 20, 24, 180)
                                    end, zToUse + 1, layer.DrawCommandSpace.World)

                                    -- draw diagonal line from top-left to bottom-right
                                    command_buffer.queueDrawLine(layers.sprites, function(c)
                                        c.x1 = centerX - xSize * 0.5
                                        c.y1 = centerY - xSize * 0.5
                                        c.x2 = centerX + xSize * 0.5
                                        c.y2 = centerY + xSize * 0.5
                                        c.color = xColor
                                        c.lineWidth = thickness
                                    end, zToUse + 2, layer.DrawCommandSpace.World)

                                    -- draw diagonal line from top-right to bottom-left
                                    command_buffer.queueDrawLine(layers.sprites, function(c)
                                        c.x1 = centerX + xSize * 0.5
                                        c.y1 = centerY - xSize * 0.5
                                        c.x2 = centerX - xSize * 0.5
                                        c.y2 = centerY + xSize * 0.5
                                        c.color = xColor
                                        c.lineWidth = thickness
                                    end, zToUse + 2, layer.DrawCommandSpace.World)
                                end

                                -- if it's controller_focused_entity, draw moving dashed outline
                                if eid == controller_focused_entity then
                                    local thickness = 10
                                    command_buffer.queueDrawDashedRoundedRect(layers.sprites, function(c)
                                        c.rec       = Rectangle.new(
                                            -thickness / 2,
                                            -thickness / 2,
                                            t.actualW + thickness,
                                            t.actualH + thickness
                                        )
                                        c.radius    = 10
                                        c.dashLen   = 12
                                        c.gapLen    = 8
                                        c.phase     = shapeAnimationPhase
                                        c.arcSteps  = 14
                                        c.thickness = thickness
                                        c.color     = util.getColor("green")
                                    end, zToUse + 1, layer.DrawCommandSpace.World)
                                end
                            end, zToUse, layer.DrawCommandSpace.World)

                            -- now make the most recent queued command follow the sprite render command immediately in the queue.
                            -- FIXME: not using this. doesn't seem to work anyway.
                            -- SetFollowAnchorForEntity(layers.sprites, eid)
                        end
                    end
                    ::continue::
                end
                -- tracy.zoneEnd()
            end,
            nil,                -- no onComplete
            "card_render_timer" -- tag
        )
    end

    -- -- let's give the card a label (temporary) for testing
    -- cardScript.labelEntity = ui.definitions.getNewDynamicTextEntry(
    --     function() return (cardScript.test_label or "unknown") end,  -- initial text
    --     20.0,                                 -- font size
    --     "color=red"                       -- animation spec
    -- ).config.object

    -- -- make the text world space
    -- transform.set_space(cardScript.labelEntity, "world")

    -- -- text state
    -- add_state_tag(cardScript.labelEntity, gameStateToApply or PLANNING_STATE)

    -- -- set text z order
    -- layer_order_system.assignZIndexToEntity(cardScript.labelEntity, z_orders.card_text)

    -- -- let's anchor to top of the card
    -- transform.AssignRole(registry, cardScript.labelEntity, InheritedPropertiesType.PermanentAttachment, cardScript:handle(),
    --     InheritedPropertiesSync.Strong,
    --     InheritedPropertiesSync.Weak,
    --     InheritedPropertiesSync.Strong,
    --     InheritedPropertiesSync.Weak
    --     -- Vec2(0, -10) -- offset it a bit upwards
    -- );
    -- local roleComp = component_cache.get(cardScript.labelEntity, InheritedProperties)
    -- roleComp.flags = AlignmentFlag.VERTICAL_CENTER | AlignmentFlag.HORIZONTAL_CENTER

    local shaderPipelineComp = registry:emplace(card, shader_pipeline.ShaderPipelineComponent)
    -- shaderPipelineComp:addPass("material_card_overlay")
    -- shaderPipelineComp:addPass("3d_skew_hologram")
    shaderPipelineComp:addPass("3d_skew")
    -- shaderPipelineComp:addPass("3d_skew_foil")
    -- shaderPipelineComp:addPass("3d_skew_negative_shine")
    -- shaderPipelineComp:addPass("3d_skew_negative")
    -- shaderPipelineComp:addPass("3d_skew_holo")
    -- shaderPipelineComp:addPass("3d_skew_voucher")
    -- shaderPipelineComp:addPass("3d_skew_gold_seal")
    -- shaderPipelineComp:addPass("3d_skew_polychrome")
    -- shaderPipelineComp:addPass("3d_skew_aurora")
    -- shaderPipelineComp:addPass("3d_skew_iridescent")
    -- shaderPipelineComp:addPass("3d_skew_nebula")
    -- shaderPipelineComp:addPass("3d_skew_plasma")
    -- shaderPipelineComp:addPass("3d_skew_prismatic")
    -- shaderPipelineComp:addPass("3d_skew_thermal")
    
    -- shaderPipelineComp:addPass("3d_skew_crystalline")
    -- shaderPipelineComp:addPass("3d_skew_glitch")
    -- shaderPipelineComp:addPass("3d_skew_negative_tint")
    -- shaderPipelineComp:addPass("3d_skew_oil_slick")
    -- shaderPipelineComp:addPass("3d_skew_polka_dot")
    
    do
        local passes = shaderPipelineComp.passes
        local idx = passes and #passes
        if idx and idx >= 1 then
            local pass = passes[idx]
            -- Apply unique random seed to ALL 3d_skew shader variants
            if pass and pass.shaderName and pass.shaderName:sub(1, 7) == "3d_skew" then
                local seed = cardScript.skewSeed or math.random() * 10000
                local shaderName = pass.shaderName
                pass.customPrePassFunction = function()
                    if globalShaderUniforms then
                        globalShaderUniforms:set(shaderName, "rand_seed", seed)
                    end
                end
            end
        end
    end

    -- Add outline shader pass (applied after 3d_skew transformation)
    -- Uncomment to enable card outlines:
    -- do
    --     local outlinePass = shaderPipelineComp:addPass("efficient_pixel_outline", false)
    --     outlinePass.customPrePassFunction = function()
    --         if globalShaderUniforms then
    --             globalShaderUniforms:set("efficient_pixel_outline", "outlineColor", Vector4{ x = 0.0, y = 0.0, z = 0.0, w = 1.0 })
    --             globalShaderUniforms:set("efficient_pixel_outline", "outlineType", 2)
    --             globalShaderUniforms:set("efficient_pixel_outline", "thickness", 1.0)
    --         end
    --     end
    -- end

    -- shaderPipelineComp:addPass("3d_polychrome")
    -- shaderPipelineComp:addPass("material_card_overlay_new_dissolve")


    -- make draggable and set some callbacks in the transform system
    local nodeComp = component_cache.get(card, GameObject)
    nodeComp.shadowMode = ShadowMode.SpriteBased
    local gameObjectState = nodeComp.state
    gameObjectState.hoverEnabled = true
    gameObjectState.collisionEnabled = true
    gameObjectState.clickEnabled = true
    gameObjectState.dragEnabled = true
    gameObjectState.rightClickEnabled = true

    animation_system.resizeAnimationObjectsInEntityToFit(
        card,
        gameplay_cfg.cardW, -- width
        gameplay_cfg.cardH  -- height
    )

    -- registry:emplace(card, shader_pipeline.ShaderPipelineComponent)

    -- entity.set_draw_override(card, function(w, h)
    -- -- immediate render version of the same thing.
    --     command_buffer.executeDrawGradientRectRoundedCentered(layers.sprites, function(c)
    --         local survivorT = component_cache.get(card, Transform)

    --         c.cx = 0 -- self centered
    --         c.cy = 0
    --         c.width = w
    --         c.height = h
    --         c.roundness = 0.5
    --         c.segments = 8
    --         c.topLeft = util.getColor("white")
    --         c.topRight = util.getColor("gray")
    --         -- c.bottomRight = util.getColor("green")
    --         -- c.bottomLeft = util.getColor("apricot_cream")

    --         end, z_orders.card, layer.DrawCommandSpace.World)

    --     -- layer.ExecuteScale(1.0, -1.0) -- flip y axis for text rendering
    --     -- layer.ExecuteTranslate(0, -h) -- translate down by height
    --     -- let's draw some text.
    --     --TODO: fix. text flips over for some reason.
    --     -- command_buffer.executeDrawTextPro(layers.sprites, function(t)
    --     --     local cardScript = getScriptTableFromEntityID(card)
    --     --     t.text = cardScript.test_label or "unknown"
    --     --     t.font = localization.getFont()
    --     --     t.x = 0
    --     --     t.y = 0
    --     --     t.color = util.getColor("red")
    --     --     t.fontSize = 25.0
    --     -- end)

    --     -- layer.ExecuteScale(1.0, -1.0) -- re-flip y axis
    -- end, true) -- true disables sprite rendering


    -- NOTE: onRelease is called for when mouse is released ON TOP OF this node.
    -- TODO: removing card stacking behavior for now.
    -- nodeComp.methods.onRelease = function(registry, releasedOn, released)
    --     log_debug("card", released, "released on", releasedOn)

    --     -- when released on top of a card, get the root card of the stack if there is one, and add self to that stack


    --     -- get the card script table
    --     local releasedCardScript = getScriptTableFromEntityID(released)
    --     local releasedOnCardScript = getScriptTableFromEntityID(releasedOn)
    --     if not releasedCardScript then return end
    --     if not releasedOnCardScript then return end

    --     -- check stackRootEntity in the table. Also, check that isStackable is true
    --     if not releasedCardScript.isStackable then
    --         log_debug("released card is not stackable or has no stackRootEntity")
    --         return
    --     end

    --     -- check that the released entity is not already a stack root
    --     if releasedCardScript.stackRootEntity and releasedCardScript.stackRootEntity == released and releasedCardScript.cardStack and #releasedCardScript.cardStack > 0 then
    --         log_debug("released card is already a stack root, not stacking on self")
    --         return
    --     end

    --     -- if the released card is already part of a stack, remove it first
    --     if releasedCardScript.stackRootEntity and releasedCardScript.stackRootEntity ~= releasedCardScript:handle() then
    --         local currentRootCardScript = getScriptTableFromEntityID(releasedCardScript.stackRootEntity)
    --         if currentRootCardScript then
    --             removeCardFromStack(currentRootCardScript, releasedCardScript)
    --         end
    --     end

    --     local rootCardScript = nil

    --     -- if the card released on has no root, then make it the root.
    --     if not releasedOnCardScript.stackRootEntity then
    --         rootCardScript = releasedOnCardScript
    --         releasedOnCardScript.stackRootEntity = releasedOnCardScript:handle()
    --         releasedOnCardScript.cardStack = releasedOnCardScript.cardStack or {}
    --         releasedCardScript.stackRootEntity = releasedOnCardScript:handle()
    --     else
    --         -- if it has a root, use that instead.
    --         rootCardScript = getScriptTableFromEntityID(releasedOnCardScript.stackRootEntity)
    --     end

    --     if not rootCardScript then
    --         log_debug("could not find root card script")
    --         return
    --     end

    --     -- add self to the root entity's stack, if self is not the root
    --     if rootCardScript:handle() == released then
    --         log_debug("released card is the root entity, not stacking on self")
    --         return
    --     end

    --     -- make sure neither card is already in a stack and they're being dropped onto each other by accident. It's weird, but sometimes root can be dropped on a member card.
    --     if rootCardScript.cardStack then
    --         for _, e in ipairs(rootCardScript.cardStack) do
    --             if e == released then
    --                 log_debug("released card is already in the root entity's stack, not stacking again")
    --                 return
    --             end
    --         end
    --     elseif releasedCardScript.isStackChild then
    --         log_debug("released card is already a child in another stack, not stacking again")
    --         return
    --     end
    --     local result = addCardToStack(rootCardScript, releasedCardScript)

    --     if not result then
    --         log_debug("failed to add card to stack due to validation")
    --         -- return to previous position
    --         local t = component_cache.get(released, Transform)
    --         if t and cardScript.startingPosition then
    --             t.actualX = cardScript.startingPosition.x
    --             t.actualY = cardScript.startingPosition.y
    --         else
    --             log_debug("could not snap back to starting position, missing transform or startingPosition")
    --             -- just bump it down a bit
    --             if t then
    --                 t.actualY = t.actualY + 70
    --             end
    --         end
    --         return
    --     end

    --     -- after adding to the stack, update the z-orders from bottom up.
    --     local baseZ = z_orders.card

    --     -- give root entity the base z order
    --     layer_order_system.assignZIndexToEntity(rootCardScript:handle(), baseZ)

    --     -- now for every card in the stack, give it a z order above the root
    --     for i, stackedCardEid in ipairs(rootCardScript.cardStack) do
    --         if stackedCardEid and entity_cache.valid(stackedCardEid) then
    --             local stackedTransform = component_cache.get(stackedCardEid, Transform)
    --             local zi = baseZ + (i) -- root is baseZ, first stacked card is baseZ + 1, etc
    --             layer_order_system.assignZIndexToEntity(stackedCardEid, zi)
    --         end
    --     end

    -- end

    nodeComp.methods.onClick = function(registry, clickedEntity)
        -- cardScript.selected = not cardScript.selected
        -- nodeComp.state.isBeingFocused = cardScript.selected
    end

    nodeComp.methods.onRightClick = function(registry, clickedEntity)
        transferCardViaRightClick(card, cardScript)
    end

    nodeComp.methods.onHover = function()
        log_debug("card onHover called for", card)

        -- inject dynamic motion
        transform.InjectDynamicMotion(card, 0, 1)


        -- get script
        local hoveredCardScript = getScriptTableFromEntityID(card)
        if not hoveredCardScript then return end

        local isDisabled = isCardOverCapacity(hoveredCardScript, card)
        hoveredCardScript.isDisabled = isDisabled

        local cardDef = WandEngine.card_defs[hoveredCardScript.cardID] or WandEngine.trigger_card_defs[hoveredCardScript.cardID] or hoveredCardScript
        local tooltipOpts = nil
        if isDisabled then
            tooltipOpts = { status = "disabled", statusColor = "red" }
        end

        if USE_TOOLTIP_V2 then
            if previously_hovered_tooltip and previously_hovered_tooltip ~= card then
                TooltipV2.hide(previously_hovered_tooltip)
            end
            TooltipV2.showCard(card, cardDef, tooltipOpts)
            activate_state(CARD_TOOLTIP_STATE)
            previously_hovered_tooltip = card
        else
            local tooltip = ensureCardTooltip(cardDef, tooltipOpts)
            if not tooltip then
                return
            end
            positionTooltipRightOfEntity(tooltip, card, { gap = 12 })
            if previously_hovered_tooltip and previously_hovered_tooltip ~= tooltip then
                hideCardTooltip(previously_hovered_tooltip)
            end
            add_state_tag(tooltip, CARD_TOOLTIP_STATE)
            activate_state(CARD_TOOLTIP_STATE)
            ui.box.AddStateTagToUIBox(tooltip, CARD_TOOLTIP_STATE)
            previously_hovered_tooltip = tooltip
        end

        -- Track for alt-preview
        card_ui_state.hovered_card = card

        -- If Alt is already held, begin preview
        if isAltHeld() then
            beginAltPreview(card)
        end
    end

    nodeComp.methods.onStopHover = function()
        local hoveredCardScript = getScriptTableFromEntityID(card)
        if not hoveredCardScript then return end

        if previously_hovered_tooltip then
            if USE_TOOLTIP_V2 then
                TooltipV2.hide(previously_hovered_tooltip)
            else
                hideCardTooltip(previously_hovered_tooltip)
            end
            previously_hovered_tooltip = nil
        end

        card_ui_state.hovered_card = nil
        if card_ui_state.alt_entity == card then
            endAltPreview()
        end
    end

    nodeComp.methods.onDrag = function()
        local currentBoardEid = cardScript.currentBoardEntity
        if currentBoardEid then
            local currentBoard = boards[currentBoardEid]
            if currentBoard and currentBoard.layoutMode == "grid" then
                return
            end
        end

        if card_ui_state.alt_entity == card then
            card_ui_state.alt_entity = nil
            card_ui_state.alt_original_z = nil
        end

        cardScript.isBeingDragged = true

        if not boardEntityID then
            layer_order_system.assignZIndexToEntity(card, z_orders.top_card)
            return
        end

        local board = boards[boardEntityID]
        if not board then return end

        log_debug("dragging card, bringing to top z:", z_orders.top_card)
        layer_order_system.assignZIndexToEntity(card, z_orders.top_card)
    end

    nodeComp.methods.onStopDrag = function()
        -- sound
        local putDownSounds = {
            "card_put_down_1",
            "card_put_down_2",
            "card_put_down_3",
            "card_put_down_4"
        }
        playSoundEffect("effects", lume.randomchoice(putDownSounds), 0.9 + math.random() * 0.2)


        cardScript.isBeingDragged = false

        if not boardEntityID then
            layer_order_system.assignZIndexToEntity(card, z_orders.card)
            return
        end

        local board = boards[boardEntityID]
        -- dunno why, board can be nil
        if not board then return end
        -- reset z order to cached value
        cardScript.isDragging = false
        local cachedZ = board.z_order_cache_per_card and board.z_order_cache_per_card[card1] or board.z_orders.card
        layer_order_system.assignZIndexToEntity(card, cachedZ)


        -- is it part of a stack?
        if cardScript.stackRootEntity and cardScript.stackRootEntity == card then
            resetCardStackZOrder(cardScript:handle())
        end

        -- -- make it transform authoritative again
        -- physics.set_sync_mode(registry, card, physics.PhysicsSyncMode.AuthoritativeTransform)
    end


    -- if x and y are given, set position
    if x and y then
        local t = component_cache.get(card, Transform)
        if t then
            t.actualX = x
            t.actualY = y
        end
    end

    return cardScript:handle()
end

function setUpScrollingBackgroundSprites()
    local gridSpacingX     = 700
    local gridSpacingY     = 700
    local scrollSpeedX     = 50
    local scrollSpeedY     = -40
    local spriteName       = "light_03.png"
    local scale            = 1
    local tint             = Col(255, 255, 255, 255)

    local bgSprites        = {}
    local screenW, screenH = globals.screenWidth(), globals.screenHeight()

    -- extend bounds by one screen in all directions
    local startX           = -screenW
    local endX             = screenW * 2
    local startY           = -screenH
    local endY             = screenH * 2

    for gx = startX, endX, gridSpacingX do
        for gy = startY, endY, gridSpacingY do
            table.insert(bgSprites, { x = gx, y = gy })
        end
    end

    timer.every(0.016, function()
        local dt = 0.016

        for _, s in ipairs(bgSprites) do
            s.x = s.x + scrollSpeedX * dt
            s.y = s.y + scrollSpeedY * dt

            -- wrap horizontally
            if s.x > endX + gridSpacingX * 0.5 then
                s.x = s.x - (endX - startX + gridSpacingX)
            elseif s.x < startX - gridSpacingX * 0.5 then
                s.x = s.x + (endX - startX + gridSpacingX)
            end

            -- wrap vertically
            if s.y > endY + gridSpacingY * 0.5 then
                s.y = s.y - (endY - startY + gridSpacingY)
            elseif s.y < startY - gridSpacingY * 0.5 then
                s.y = s.y + (endY - startY + gridSpacingY)
            end


            command_buffer.queueDrawSpriteCentered(layers.sprites, function(c)
                c.spriteName = spriteName
                c.x = s.x
                c.y = s.y
                c.dstW = nil
                c.dstH = nil
                c.tint = tint
            end, z_orders.background, layer.DrawCommandSpace.World)
        end
    end)
end

function addPulseEffectBehindCard(cardEntityID, startColor, endColor)
    if not cardEntityID or cardEntityID == entt_null or not entity_cache.valid(cardEntityID) then return end
    local cardTransform = component_cache.get(cardEntityID, Transform)
    if not cardTransform then return end


    -- create a new object for a pulsing rectangle that fades out in color over time, then destroys itself.
    local PulseObjectType = Node:extend()

    PulseObjectType.lifetime = 0.3
    PulseObjectType.age = 0.0
    PulseObjectType.cardEntityID = cardEntityID
    PulseObjectType.startColor = startColor
    PulseObjectType.endColor = endColor

    function PulseObjectType:update(dt)
        local addedScaleAmount = 0.3

        self.age = self.age + dt

        -- make scale & alpha based on age
        local alpha = 1.0 - Easing.outQuart.f(math.min(1.0, self.age / self.lifetime))
        local scale = 1.0 + addedScaleAmount * Easing.outQuart.f(math.min(1.0, self.age / self.lifetime))
        local e = math.min(1.0, self.age / self.lifetime)

        local fromColor = self.startColor or util.getColor("yellow")
        local toColor = self.endColor or util.getColor("black")

        -- interpolate per channel
        local r = lerp(fromColor.r, toColor.r, e)
        local g = lerp(fromColor.g, toColor.g, e)
        local b = lerp(fromColor.b, toColor.b, e)
        local a = lerp(fromColor.a or 255, 0, e)

        -- make sure they're integers
        r = math.floor(r + 0.5)
        g = math.floor(g + 0.5)
        b = math.floor(b + 0.5)
        a = math.floor(a + 0.5)

        command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
            local t = component_cache.get(self.cardEntityID, Transform)
            c.x = t.actualX + t.actualW * 0.5
            c.y = t.actualY + t.actualH * 0.5
            c.w = t.actualW * scale
            c.h = t.actualH * scale
            c.rx = 15
            c.ry = 15
            c.color = Col(r, g, b, a)
        end, z_orders.card - 1, layer.DrawCommandSpace.World)
    end

    local pulseObject = PulseObjectType {}
        :attach_ecs { create_new = true }
        :destroy_when(function(self, eid) return self.age >= self.lifetime end)

    -- add planning state tag after clearing all tags
    clear_state_tags(pulseObject:handle())
    add_state_tag(pulseObject:handle(), PLANNING_STATE)
end

function slowTime(duration, targetTimeScale)
    main_loop.data.timescale = targetTimeScale or 0.2   -- slow to 20%, then over X seconds, tween back to 1.0
    timer.tween_scalar(
        duration or 1.0,                                -- duration in seconds
        function() return main_loop.data.timescale end, -- getter
        function(v) main_loop.data.timescale = v end,   -- setter
        1.0                                             -- target value
    )
end

function killPlayer()
    -- slow time using main_loop.data.timeScale


    main_loop.data.timescale = 0.15                     -- slow to 15%, then over X seconds, tween back to 1.0
    timer.tween(
        1.0,                                            -- duration in seconds
        function() return main_loop.data.timescale end, -- getter
        function(v) main_loop.data.timescale = v end,   -- setter
        1.0                                             -- target value
    )

    -- destroy the entity, get particles flying.

    timer.after(0.01, function()
        local transform = component_cache.get(survivorEntity, Transform)

        -- create a note that draws a red circle where the player was and removes itself after 0.1 second
        local DeathCircleType = Node:extend()
        local playerX = transform.actualX + transform.actualW * 0.5
        local playerY = transform.actualY + transform.actualH * 0.5
        local playerW = transform.actualW
        local playerH = transform.actualH
        function DeathCircleType:update(dt)
            self.age = self.age + dt
            command_buffer.queueDrawCenteredEllipse(layers.sprites, function(c)
                local t = component_cache.get(survivorEntity, Transform)
                c.x = playerX
                c.y = playerY
                c.rx = playerW * 0.5 * (1.0 + self.age * 5.0)
                c.ry = playerH * 0.5 * (1.0 + self.age * 5.0)
                c.color = util.getColor("red")
            end, z_orders.player_vfx, layer.DrawCommandSpace.World)
        end

        local deathCircle = DeathCircleType {}
        deathCircle.lifetime = 0.1
        deathCircle.age = 0.0


        deathCircle:attach_ecs { create_new = true }
        deathCircle:destroy_when(function(self, eid) return self.age >= self.lifetime end)

        spawnCircularBurstParticles(
            transform.visualX + transform.actualW * 0.5,
            transform.visualY + transform.actualH * 0.5,
            8,                     -- count
            0.9,                   -- seconds
            util.getColor("blue"), -- start color
            util.getColor("red"),  -- end color
            "outCubic",            -- from util.easing
            "world"                -- screen space
        )

        registry:destroy(survivorEntity)
    end)
end

function spawnRandomBullet()
    local bulletSize = 10

    local playerTransform = component_cache.get(survivorEntity, Transform)

    local BulletType = Node:extend() -- define the type before instantiating
    function BulletType:update(dt)
        self.age = self.age + dt

        -- draw a circle
        command_buffer.queueDrawCenteredEllipse(layers.sprites, function(c)
            local t = component_cache.get(self:handle(), Transform)
            c.x = t.actualX + t.actualW * 0.5
            c.y = t.actualY + t.actualH * 0.5
            c.rx = t.actualW * 0.5
            c.ry = t.actualH * 0.5
            c.color = util.getColor("red")
        end, z_orders.projectiles, layer.DrawCommandSpace.World)
    end

    local node = BulletType {}
    node.lifetime = 2.0
    node.age = 0.0

    node:attach_ecs { create_new = true }
    node:destroy_when(function(self, eid) return self.age >= self.lifetime end)

    -- give transform
    local centerX = playerTransform.actualX + playerTransform.actualW * 0.5 - bulletSize * 0.5
    local centerY = playerTransform.actualY + playerTransform.actualH * 0.5 - bulletSize * 0.5
    transform.CreateOrEmplace(registry, globals.gameWorldContainerEntity(), centerX, centerY, bulletSize, bulletSize,
        node:handle())

    -- give physics.

    local world = PhysicsManager.get_world("world")

    local info = { shape = "circle", tag = C.CollisionTags.BULLET, sensor = false, density = 1.0, inflate_px = -4 }
    physics.create_physics_for_transform(registry,
        physics_manager_instance,                                                                     -- global instance
        node:handle(),                                                                                -- entity id
        "world",                                                                                      -- physics world identifier
        info
    )

    -- give bullet state
    add_state_tag(node:handle(), ACTION_STATE)

    -- collision mask
    physics.enable_collision_between_many(PhysicsManager.get_world("world"), C.CollisionTags.ENEMY, { C.CollisionTags.BULLET })
    physics.enable_collision_between_many(PhysicsManager.get_world("world"), C.CollisionTags.BULLET, { C.CollisionTags.ENEMY })
    physics.update_collision_masks_for(PhysicsManager.get_world("world"), C.CollisionTags.ENEMY, { C.CollisionTags.BULLET })
    physics.update_collision_masks_for(PhysicsManager.get_world("world"), C.CollisionTags.BULLET, { C.CollisionTags.ENEMY })

    -- ignore damping
    physics.SetBullet(world, node:handle(), true)

    -- Fire in the direction the player is currently moving.
    local v = physics.GetVelocity(world, survivorEntity)
    local vx = v.x
    local vy = v.y
    local speed = 300.0

    -- If the player is standing still, default to forward or random.
    if vx == 0 and vy == 0 then
        local angle = math.random() * math.pi * 2.0
        vx = math.cos(angle)
        vy = math.sin(angle)
    end

    -- Normalize
    local mag = math.sqrt(vx * vx + vy * vy)
    if mag > 0 then
        vx, vy = vx / mag * speed, vy / mag * speed
    end

    physics.SetVelocity(world, node:handle(), vx, vy)

    -- make a new node that discards after 0.1 seconds to mark bullet firing
    local FireMarkType = Node:extend()
    function FireMarkType:update(dt)
        self.age = self.age + dt
        -- draw a small flash at the bullet position
        command_buffer.queueDrawCenteredEllipse(layers.sprites, function(c)
            local t = component_cache.get(node:handle(), Transform)
            c.x = t.actualX + t.actualW * 0.5
            c.y = t.actualY + t.actualH * 0.5
            c.rx = t.actualW * 1.5
            c.ry = t.actualH * 1.5
            c.color = util.getColor("yellow")
        end, z_orders.projectiles, layer.DrawCommandSpace.World)
    end

    local fireMarkNode = FireMarkType {}
    fireMarkNode.lifetime = 0.1
    fireMarkNode.age = 0.0

    fireMarkNode:attach_ecs { create_new = true }
    fireMarkNode:destroy_when(function(self, eid) return self.age >= self.lifetime end)
end

function spawnRandomTrapHazard()
    local playerTransform = component_cache.get(survivorEntity, Transform)

    -- make animated object
    local hazard = animation_system.createAnimatedObjectWithTransform(
        "b3997.png", -- animation ID
        true         -- use animation, not sprite identifier, if false
    )

    -- give state tag
    add_state_tag(hazard, ACTION_STATE)

    -- resize
    animation_system.resizeAnimationObjectsInEntityToFit(
        hazard,
        32 * 2, -- width
        32 * 2  -- height
    )

    -- position it in front of the player, at a random offset
    local offsetDistance = 80.0
    local angle = (math.random() * 0.5 - 0.25) * math.pi -- random angle between -45 and +45 degrees
    local offsetX = math.cos(angle) * offsetDistance
    local offsetY = math.sin(angle) * offsetDistance
    local playerCenterX = playerTransform.actualX + playerTransform.actualW * 0.5
    local playerCenterY = playerTransform.actualY + playerTransform.actualH * 0.5
    local hazardX = playerCenterX + offsetX - 32 -- center the hazard
    local hazardY = playerCenterY + offsetY - 32

    -- snap visual to actual
    local hazardTransform = component_cache.get(hazard, Transform)
    hazardTransform.actualX = hazardX
    hazardTransform.actualY = hazardY
    hazardTransform.visualX = hazardX
    hazardTransform.visualY = hazardY

    -- jiggle
    hazardTransform.visualS = 1.5

    -- give physics & node
    local info = { shape = "rectangle", tag = C.CollisionTags.SPIKE_HAZARD, sensor = false, density = 1.0, inflate_px = -4 }
    physics.create_physics_for_transform(registry,
        physics_manager_instance,                                                                              -- global instance
        hazard,                                                                                                -- entity id
        "world",                                                                                               -- physics world identifier
        info
    )


    local node = Node {}
    node.lifetime = 8.0 --TODO: base lifetime on some kind of stat, maybe?
    node.age = 0.0
    node.update = function(self, dt)
        self.age = self.age + dt
    end

    node:attach_ecs { create_new = false, existing_entity = hazard }
    node:destroy_when(function(self, eid) return self.age >= self.lifetime end)
end

function applyPlayerStrengthBonus()
    playSoundEffect("effects", "strength_bonus", 0.9 + math.random() * 0.2)

    local playerTransform = component_cache.get(survivorEntity, Transform)

    -- make a node
    local node = Node {}
    node.lifetime = 1.0 -- lasts for 10 seconds
    node.age = 0.0
    node.update = function(self, dt)
        self.age = self.age + dt

        local tweenProgress = math.min(1.0, self.age / self.lifetime)

        -- draw a series of vertical lines on the player that move up and lengthen over time, cubically.

        local numlines = 5
        local baseHeight = playerTransform.actualH * 0.3
        local addedHeight = playerTransform.actualH * 0.7

        local startColor = util.getColor("white")
        local endColor = util.getColor("red")

        local t = component_cache.get(survivorEntity, Transform)
        local centerX = t.actualX + t.actualW * 0.5
        local baseY = t.actualY + t.actualH

        for i = 1, numlines do
            local lineProgress = (i - 1) / (numlines - 1)
            local x = centerX + (lineProgress - 0.5) * t.actualW * 0.8
            local h = baseHeight + addedHeight * Easing.outExpo.f(tweenProgress) * (0.5 + 0.5 * lineProgress)

            -- interpolate color
            local r = lerp(startColor.r, endColor.r, tweenProgress)
            local g = lerp(startColor.g, endColor.g, tweenProgress)
            local b = lerp(startColor.b, endColor.b, tweenProgress)
            local a = lerp(startColor.a or 255, endColor.a or 255, tweenProgress)

            -- make sure they're integers
            r = math.floor(r + 0.5)
            g = math.floor(g + 0.5)
            b = math.floor(b + 0.5)
            a = math.floor(a + 0.5)

            -- draw the lines
            command_buffer.queueDrawLine(layers.sprites, function(c)
                c.x1 = x
                c.y1 = baseY
                c.x2 = x
                c.y2 = baseY - h
                c.color = Col(r, g, b, a)
                c.lineWidth = 2
            end, z_orders.player_vfx, layer.DrawCommandSpace.World)
        end
    end
    node:attach_ecs { create_new = true }
    node:destroy_when(function(self, eid) return self.age >= self.lifetime end)
end

function fireActionCardWithModifiers(cardEntityID, executionIndex)
    if not cardEntityID or cardEntityID == entt_null or not entity_cache.valid(cardEntityID) then return end
    local cardScript = getScriptTableFromEntityID(cardEntityID)
    if not cardScript then return end

    local playerScript = getScriptTableFromEntityID(survivorEntity)
    local playerTransform = component_cache.get(survivorEntity, Transform)

    log_debug("Firing action card:", cardScript.cardID)


    local pitchIncrement = 0.1;

    -- play a sound
    playSoundEffect("effects", "card_activate", 0.9 + pitchIncrement * (executionIndex or 0))



    -- first, let's see if the card has any modifiers stacked on it, and log them

    local modsTable = {}

    if cardScript.cardStack and #cardScript.cardStack > 0 then
        log_debug("Card has", #cardScript.cardStack, "modifiers stacked on it:")
        for i, modEid in ipairs(cardScript.cardStack) do
            local modCardScript = getScriptTableFromEntityID(modEid)
            if modCardScript then
                log_debug(" - modifier", i, ":", modCardScript.cardID)
                table.insert(modsTable, modCardScript.cardID)
            end
        end
    end


    -- for now, we'll handle bolt, spike hazard, and strength bonus



    -- let's see what the card ID is and do something based on that
    if cardScript.cardID == "fire_basic_bolt" then
        -- create a basic bolt projectile in a random direction.

        -- play sound once, doesn't make sense to play multiple times
        playSoundEffect("effects", "fire_bolt", 0.9 + math.random() * 0.2)

        spawnRandomBullet()

        -- if mods contains double_effect, do it again
        if lume.find(modsTable, "double_effect") then
            spawnRandomBullet()
        end
    elseif cardScript.cardID == "leave_spike_hazard" then
        -- create a spike hazard at a random position in front of the player

        playSoundEffect("effects", "place_trap", 0.9 + math.random() * 0.2)

        spawnRandomTrapHazard()

        -- if mods contains double_effect, do it again
        if lume.find(modsTable, "double_effect") then
            spawnRandomTrapHazard()
        end
    elseif cardScript.cardID == "temporary_strength_bonus" then
        -- for now, just log it
        log_debug("Strength bonus activated! (no effect yet)")

        applyPlayerStrengthBonus()

        -- if mods contains double_effect, wait a bit, then do it again.
        if lume.find(modsTable, "double_effect") then
            timer.after(1.1, function()
                applyPlayerStrengthBonus()
            end)
        end
    else
        log_debug("Unknown action card ID:", cardScript.cardID)
    end
end

-- TODO: handle things like cooldown, modifiers that change the effect, etc
function fireActionCardsInBoard(boardEntityID)
    if not boardEntityID or boardEntityID == entt_null or not entity_cache.valid(boardEntityID) then return end
    local board = boards[boardEntityID]
    if not board or not board.cards or #board.cards == 0 then return end

    -- for now, just log the card ids in order
    local cooldownBetweenActions = 0.5 -- seconds
    local runningDelay = 0.3
    local pulseColorRampTable = palette.ramp_quantized("blue", "white", #board.cards)
    local index = 1
    for _, cardEid in ipairs(board.cards) do
        if ensure_entity(cardEid) then
            local cardScript = getScriptTableFromEntityID(cardEid)
            if cardScript then
                timer.after(
                    runningDelay,
                    function()
                        -- log_debug("Firing action card:", cardScript.cardID)

                        -- pulse and jiggle
                        local cardTransform = component_cache.get(cardEid, Transform)
                        if cardTransform then
                            cardTransform.visualS = 2.0
                            addPulseEffectBehindCard(cardEid, pulseColorRampTable[index], util.getColor("black"))
                        end

                        -- actually execute the logic of the card
                        fireActionCardWithModifiers(cardEid, index)
                    end
                )

                runningDelay = runningDelay + cooldownBetweenActions
            end
        end
        index = index + 1
    end
end

function startTriggerNSecondsTimer(trigger_board_id, action_board_id, timer_name)
    -- this timer should make the card pulse and jiggle + particles. Then it will go through the action board and execute all actions that are on it in sequence.

    -- for now, just do 3 seconds

    local outCubic = Easing.outQuart.f -- the easing function, not the derivative


    -- log_debug("startTriggerNSecondsTimer called for trigger board:", trigger_board_id, "and action board:", action_board_id)
    timer.every(
        3.0,
        function()
            -- onlly in action state
            if not is_state_active(ACTION_STATE) then return end

            -- log_debug("every N seconds trigger fired")
            -- pulse and jiggle the card
            if not trigger_board_id or trigger_board_id == entt_null or not entity_cache.valid(trigger_board_id) then return end
            local triggerBoard = boards[trigger_board_id]
            if not triggerBoard or not triggerBoard.cards or #triggerBoard.cards == 0 then return end

            local triggerCardEid = triggerBoard.cards[1]
            if not triggerCardEid or triggerCardEid == entt_null or not entity_cache.valid(triggerCardEid) then return end
            local triggerCardScript = getScriptTableFromEntityID(triggerCardEid)
            if not triggerCardScript then return end

            -- pulse animation
            local cardTransform = component_cache.get(triggerCardEid, Transform)
            cardTransform.visualS = 1.5

            -- play sound
            playSoundEffect("effects", "trigger_activate", 1.0)

            addPulseEffectBehindCard(triggerCardEid, util.getColor("yellow"), util.getColor("black"))

            -- start chain of action cards in the action board
            if not action_board_id or action_board_id == entt_null or not entity_cache.valid(action_board_id) then return end
            fireActionCardsInBoard(action_board_id)
        end,
        0,         -- infinite repetitions
        false,     -- don't start immediately
        nil,       -- no after callback
        timer_name -- name of the timer (so we can check if it exists later
    )
end

-- generic weapon def, creatures must have this to deal damage.

local basic_monster_weapon = {
    id = 'basic_monster_weapon',
    slot = 'sword1',
    -- requires = { attribute = 'cunning', value = 12, mode = 'sole' },
    mods = {
        { stat = 'weapon_min', base = 6 },
        { stat = 'weapon_max', base = 10 },
        --   { stat = 'fire_modifier_pct', add_pct = 15 },
    },
    -- conversions = { { from = 'physical', to = 'fire', pct = 25 } },
    -- procs = {
    --   {
    --     trigger = 'OnBasicAttack',
    --     chance = 70,
    --     effects = Effects.deal_damage {
    --       components = { { type = 'fire', amount = 40 } }, tags = { ability = true }
    --     },
    --   },
    -- },
    -- granted_spells = { 'Fireball' },
}
function setUpLogicTimers()
    -- handler for bumping into enemy. just get the enemy's combat script and let the enemy deal damage to the player.
    local function on_bump_enemy_handler(enemyEntityID)
        log_debug("on_bump_enemy_handler called with enemy entity:", enemyEntityID)

        if not enemyEntityID or enemyEntityID == entt_null or not entity_cache.valid(enemyEntityID) then return end

        local enemyScript = getScriptTableFromEntityID(enemyEntityID)
        if not enemyScript then return end

        -- for now just deal generic damage to the player.
        -- TODO: expand with other enemies who deal different types of damage.

        local playerScript = getScriptTableFromEntityID(survivorEntity)
        if not playerScript then return end

        local enemyCombatTable = enemyScript.combatTable
        if not enemyCombatTable then return end

        local playerCombatTable = playerScript.combatTable
        if not playerCombatTable then return end

        -- 1. Basic attack (vanilla weapon hit)
        CombatSystem.Game.Effects.deal_damage { weapon = true, scale_pct = 100 } (combat_context, enemyCombatTable,
            playerCombatTable)

        -- NOTE: player_damaged signal is emitted from combat_system.lua OnHitResolved
        -- when tgt.side == 1 (player). No need to emit here.

        -- pull player hp spring
        if hpBarScaleSpringEntity and entity_cache.valid(hpBarScaleSpringEntity) then
            local hpBarSpringRef = spring.get(registry, hpBarScaleSpringEntity)
            if hpBarSpringRef then
                hpBarSpringRef:pull(0.15, 120.0, 14.0)
            end
        end
    end

    if not gameplay_cfg.bumpEnemyHandlerRegistered then
        gameplay_cfg.bumpEnemyHandlerRegistered = true
        local handlers = initGameplayHandlers()
        handlers:on("on_bump_enemy", on_bump_enemy_handler)
    end

    -- check the trigger board
    timer.run(
        function()
            -- bail if not in action state
            if not is_state_active(PLANNING_STATE) then return end

            if gameplay_cfg.isGridInventoryEnabled()
                and wandAdapter
                and wandAdapter.getWandCount
                and wandAdapter.getLoadout
                and wandAdapter.getWandDef
                and wandAdapter.collectCardPool then
                local wandCount = wandAdapter.getWandCount()
                if wandCount and wandCount > 0 then
                    local hasTrigger = false
                    for wandIndex = 1, wandCount do
                        local loadout = wandAdapter.getLoadout(wandIndex)
                        if loadout and loadout.trigger and entity_cache.valid(loadout.trigger) then
                            hasTrigger = true
                            break
                        end
                    end

                    if hasTrigger and timer.get_delay("trigger_simul_timer") == nil then
                        timer.every(
                            1.0, -- timing may need to change if there are many cards.
                            function()
                                if not is_state_active(PLANNING_STATE) then return end

                                local wandIndex = current_board_set_index
                                local wandDef = wandAdapter.getWandDef(wandIndex)
                                if not wandDef then
                                    ui_modules.CastExecutionGraphUI.clear()
                                    return
                                end

                                local cardPool = wandAdapter.collectCardPool(wandIndex)
                                if not cardPool or #cardPool == 0 then
                                    ui_modules.CastExecutionGraphUI.clear()
                                    return
                                end

                                local simulatedResult = WandEngine.simulate_wand(wandDef, cardPool)

                                if simulatedResult and simulatedResult.blocks then
                                    ui_modules.CastExecutionGraphUI.render(simulatedResult.blocks,
                                        { wandId = wandDef.id, title = localization.get("ui.execution_preview_title") })
                                else
                                    ui_modules.CastExecutionGraphUI.clear()
                                    return
                                end
                            end,
                            0,
                            false,
                            nil,
                            "trigger_simul_timer"
                        )
                    end

                    return
                end
            end

            for triggerBoardID, actionBoardID in pairs(trigger_board_id_to_action_board_id) do
                if ensure_entity(triggerBoardID) then
                    local triggerBoard = boards[triggerBoardID]
                    -- log_debug("checking trigger board:", triggerBoardID, "contains", triggerBoard and triggerBoard.cards and #triggerBoard.cards or 0, "cards")
                    if triggerBoard and triggerBoard.cards and #triggerBoard.cards > 0 then
                        local triggerCardEid = triggerBoard.cards[1]
                        if ensure_entity(triggerCardEid) then
                            -- we have a trigger card in the board. we need to assemble a deck of action cards from the action board, and execute them based on the trigger type.

                            -- for now, just make sure that timer is running.
                            if timer.get_delay("trigger_simul_timer") == nil then
                                -- this timer will provide visual feedback for any of the cards which are active.
                                timer.every(
                                    1.0, -- timing may need to change if there are many cards.
                                    function()
                                        
                                        if not is_state_active(PLANNING_STATE) then return end
                                        
                                        -- bail if current action board has no cards
                                        local currentSet = board_sets[current_board_set_index]
                                        if not currentSet then
                                            ui_modules.CastExecutionGraphUI.clear()
                                            return
                                        end
                                        local actionBoardID = currentSet.action_board_id
                                        if not actionBoardID or actionBoardID == entt_null or not entity_cache.valid(actionBoardID) then
                                            ui_modules.CastExecutionGraphUI.clear()
                                            return
                                        end
                                        local actionBoard = boards[actionBoardID]
                                        if not actionBoard or not actionBoard.cards or #actionBoard.cards == 0 then
                                            ui_modules.CastExecutionGraphUI.clear()
                                            return
                                        end

                                        log_debug("trigger_simul_timer fired for action board:", actionBoardID)
                                        log_debug("action board has", #actionBoard.cards, "cards")
                                        log_debug("Now simulating wand", currentSet.wandDef.id) -- wand def is stored in the set
                                        
                                        
                                        -- run the simulation, then take the return value to pulse the cards that would be fired.
                                        local cardPool = collectCardPoolForBoardSet(currentSet, true)
                                        if not cardPool or #cardPool == 0 then
                                            ui_modules.CastExecutionGraphUI.clear()
                                            return
                                        end

                                        local simulatedResult = WandEngine.simulate_wand(currentSet.wandDef, cardPool)

                                        if simulatedResult and simulatedResult.blocks then
                                            ui_modules.CastExecutionGraphUI.render(simulatedResult.blocks,
                                                { wandId = currentSet.wandDef.id, title = localization.get("ui.execution_preview_title") })
                                        else
                                            ui_modules.CastExecutionGraphUI.clear()
                                            return
                                        end

                                    end,
                                    0,
                                    false,
                                    nil,
                                    "trigger_simul_timer"
                                )
                            end

                            -- if triggerCardScript and triggerCardScript.cardID == "every_N_seconds" then
                            --     local timerName = "every_N_seconds_trigger_" .. tostring(triggerBoardID)
                            --     if not timer.get_timer_and_delay(timerName) then
                            --         startTriggerNSecondsTimer(triggerBoardID, actionBoardID, timerName)
                            --     end
                            -- end

                            --

                            -- bump enemy. if signal not registered, register it.
                        end
                    end
                end
            end
        end
    )
end

-- modular creation of trigger + action board sets
function createTriggerActionBoardSet(x, y, triggerWidth, actionWidth, height, padding)
    local set                   = {}

    -- Trigger board
    local triggerBoardID        = createNewBoard(x, y, triggerWidth, height)
    local triggerBoard          = boards[triggerBoardID]
    triggerBoard.noDashedBorder = true
    triggerBoard.borderColor    = util.getColor("cyan")

    triggerBoard.textEntity     = ui.definitions.getNewDynamicTextEntry(
        function() return localization.get("ui.trigger_area") end,
        20.0, "color=cyan"
    ).config.object

    transform.set_space(triggerBoard.textEntity, "world")

    -- give state tags to boards, remove default state tags
    add_state_tag(triggerBoardID, PLANNING_STATE)
    remove_default_state_tag(triggerBoardID)
    add_state_tag(triggerBoard.textEntity, PLANNING_STATE)
    remove_default_state_tag(triggerBoard.textEntity)

    transform.AssignRole(registry, triggerBoard.textEntity,
        InheritedPropertiesType.PermanentAttachment, triggerBoard:handle(),
        InheritedPropertiesSync.Strong,
        InheritedPropertiesSync.Weak,
        InheritedPropertiesSync.Strong,
        InheritedPropertiesSync.Weak,
        Vec2(0, -10)
    )
    component_cache.get(triggerBoard.textEntity, InheritedProperties).flags = AlignmentFlag.VERTICAL_TOP

    -- Action board
    local actionBoardX                                                      = x + triggerWidth + padding
    local actionBoardID                                                     = createNewBoard(actionBoardX, y, actionWidth,
        height)
    local actionBoard                                                       = boards[actionBoardID]
    actionBoard.noDashedBorder                                              = true
    actionBoard.borderColor                                                 = util.getColor("apricot_cream")

    actionBoard.textEntity                                                  = ui.definitions.getNewDynamicTextEntry(
        function() return localization.get("ui.action_mod_area") end,
        20.0, "color=apricot_cream"
    ).config.object

    transform.set_space(actionBoard.textEntity, "world")

    -- give state tags to boards, remove default state tags
    add_state_tag(actionBoardID, PLANNING_STATE)
    remove_default_state_tag(actionBoardID)
    add_state_tag(actionBoard.textEntity, PLANNING_STATE)
    remove_default_state_tag(actionBoard.textEntity)

    transform.AssignRole(registry, actionBoard.textEntity,
        InheritedPropertiesType.PermanentAttachment, actionBoard:handle(),
        InheritedPropertiesSync.Strong,
        InheritedPropertiesSync.Weak,
        InheritedPropertiesSync.Strong,
        InheritedPropertiesSync.Weak,
        Vec2(0, -10)
    )
    component_cache.get(actionBoard.textEntity, InheritedProperties).flags = AlignmentFlag.VERTICAL_TOP

    trigger_board_id_to_action_board_id[triggerBoardID]                    = actionBoardID

    -- Store as a set
    set.trigger_board_id                                                   = triggerBoardID
    set.action_board_id                                                    = actionBoardID
    set.text_entities                                                      = { triggerBoard.textEntity, actionBoard
        .textEntity }

    -- also add to boards
    boards[triggerBoardID]                                                 = triggerBoard
    boards[actionBoardID]                                                  = actionBoard

    table.insert(board_sets, set)
    return set
end

-- takes a given entity management state tag and applies it to all boards and cards in the board set
function applyStateToBoardSet(boardSet, stateTagToApply)
    if not boardSet then return end

    -- for each board in the set, apply the state to it and its cards.

    if boardSet.trigger_board_id then
        local triggerBoard = boards[boardSet.trigger_board_id]
        if triggerBoard then
            -- apply to cards
            for _, cardEid in ipairs(triggerBoard.cards) do
                add_state_tag(cardEid, stateTagToApply)
                remove_state_tag(cardEid, PLANNING_STATE)
            end
            -- apply to board
            add_state_tag(triggerBoard:handle(), stateTagToApply)
            remove_state_tag(triggerBoard:handle(), PLANNING_STATE)

            -- apply to text entity
            add_state_tag(triggerBoard.textEntity, stateTagToApply)
            remove_state_tag(triggerBoard.textEntity, PLANNING_STATE)
        end
    end

    if boardSet.action_board_id then
        local actionBoard = boards[boardSet.action_board_id]
        if actionBoard then
            -- apply to cards
            for _, cardEid in ipairs(actionBoard.cards) do
                add_state_tag(cardEid, stateTagToApply)
                remove_state_tag(cardEid, PLANNING_STATE)
            end
            -- apply to board
            add_state_tag(actionBoard:handle(), stateTagToApply)
            remove_state_tag(actionBoard:handle(), PLANNING_STATE)
        end
    end
end

-- methods to toggle visibility of a board set
function toggleBoardSetVisibility(boardSet, visible)
    if not boardSet then return end

    -- we'll create a new state "boardSet" + id to manage visibility
    local id = "boardSet_" .. tostring(boardSet.trigger_board_id) .. "_" .. tostring(boardSet.action_board_id)

    -- we'll add it to both boards and their cards
    applyStateToBoardSet(boardSet, id)
    if visible then
        activate_state(id)
    else
        deactivate_state(id)
    end
end

function makeWandTooltip(wand_def)
    if not wand_def then
        wand_def = WandEngine.wand_defs[1]
    end

    -- Helper function to check if value should be excluded
    local function shouldExclude(value)
        if value == nil then return true end
        if value == -1 then return true end
        if type(value) == "number" and value == 0 then return true end
        if type(value) == "string" and (value == "N/A" or value == "NONE") then return true end
        return false
    end

    local rows = {}

    if wand_def.id then
        table.insert(rows, dsl.strict.hbox {
            config = { align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER),
                padding = tooltipStyle.rowPadding },
            children = {
                makeTooltipPill(L("wand.label.id_prefix", "ID: ") .. tostring(wand_def.id), {
                    background = tooltipStyle.idBg,
                    color = tooltipStyle.idTextColor or tooltipStyle.labelColor
                })
            }
        })
    end

    -- Helper function to add a line if value is not excluded
    local function addLine(label, value, valueFormatter)
        if shouldExclude(value) then return end
        local formattedValue = valueFormatter and valueFormatter(value) or tostring(value)
        local row = makeTooltipRow(label, formattedValue)
        if row then
            table.insert(rows, row)
        end
    end

    addLine(L("wand.label.type", "type"), wand_def.type)
    addLine(L("wand.label.cast_block_size", "cast block size"), wand_def.cast_block_size)
    addLine(L("wand.label.cast_delay", "cast delay"), wand_def.cast_delay)
    addLine(L("wand.label.recharge", "recharge"), wand_def.recharge_time)
    addLine(L("wand.label.spread", "spread"), wand_def.spread_angle)
    addLine(L("wand.label.shuffle", "shuffle"), wand_def.shuffle, function(v) return v and L("ui.on", "on") or L("ui.off", "off") end)
    addLine(L("wand.label.total_slots", "total slots"), wand_def.total_card_slots)

    -- Handle always_cast_cards specially
    if wand_def.always_cast_cards and #wand_def.always_cast_cards > 0 then
        addLine(L("wand.label.always_casts", "always casts"), table.concat(wand_def.always_cast_cards, ", "))
    end

    local v = dsl.strict.vbox {
        config = { align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_TOP),
            color = tooltipStyle.innerColor,
            padding = tooltipStyle.innerPadding },
        children = rows
    }

    local root = dsl.strict.root {
        config = {
            color = tooltipStyle.bgColor,
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_TOP),
            padding = tooltipStyle.innerPadding,
            outlineThickness = 2,
            outlineColor = tooltipStyle.outlineColor,
            shadow = true,
        },
        children = { v } }

    local boxID = dsl.spawn({ x = 200, y = 200 }, root)

    ui.box.RenewAlignment(registry, boxID)
    ui.box.set_draw_layer(boxID, "ui")
    snapTooltipVisual(boxID)

    ui.box.AssignStateTagsToUIBox(boxID, PLANNING_STATE)
    remove_default_state_tag(boxID)

    return boxID
end

function makeCardTooltip(card_def, opts)
    if not card_def then
        card_def = CardTemplates.ACTION_BASIC_PROJECTILE
    end

    opts = opts or {}

    local cardId = card_def.id or card_def.cardID
    local rowPadding = tooltipStyle.rowPadding
    local innerPad = tooltipStyle.innerPadding

    local tooltipType = card_def.type == "trigger" and "trigger" or "card"
    local titleEffect = tooltipStyle.titleEffects and tooltipStyle.titleEffects[tooltipType]

    local function shouldExclude(value)
        if value == nil then return true end
        if value == -1 then return true end
        if type(value) == "number" and value == 0 then return true end
        if type(value) == "string" and value == "N/A" then return true end
        return false
    end

    local function addLine(rows, label, value, labelOpts, valueOpts)
        if shouldExclude(value) then return end
        labelOpts = labelOpts or {}
        valueOpts = valueOpts or {}
        labelOpts.fontSize = labelOpts.fontSize or tooltipStyle.labelFontSize
        valueOpts.fontSize = valueOpts.fontSize or tooltipStyle.valueFontSize
        local row = makeTooltipRow(label, value, {
            rowPadding = rowPadding,
            labelOpts = labelOpts,
            valueOpts = valueOpts,
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER)
        })
        if row then
            table.insert(rows, row)
        end
    end

    local rows = {}

    if cardId then
        table.insert(rows, dsl.strict.hbox {
            config = {
                align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER),
                padding = rowPadding
            },
            children = {
                makeTooltipPill(L("card.label.id_prefix", "ID: ") .. tostring(cardId), {
                    background = tooltipStyle.idBg,
                    color = tooltipStyle.idTextColor or tooltipStyle.labelColor,
                    fontSize = tooltipStyle.titleFontSize,
                    effects = titleEffect
                })
            }
        })
    end

    if opts.status then
        addLine(rows, L("card.label.status", "status"), opts.status, { background = "dim_gray", color = "white" },
            { color = opts.statusColor or "red" })
    end

    -- Always show ID and type
    local localizedType = L("card.type." .. (card_def.type or "action"), card_def.type)
    addLine(rows, L("card.label.type", "type"), localizedType)

    -- Show description if available (important for trigger cards)
    -- For trigger cards, use localized description if available
    local descriptionText = card_def.description
    if card_def.type == "trigger" and card_def.trigger_type then
        local localizedDesc = CardsData.getLocalizedTriggerDescription and CardsData.getLocalizedTriggerDescription(card_def.trigger_type)
        if localizedDesc and localizedDesc ~= "" then
            descriptionText = localizedDesc
        end
    end
    if descriptionText and descriptionText ~= "" then
        addLine(rows, L("card.label.effect", "effect"), descriptionText)
    end

    -- For trigger cards, show trigger-specific info
    if card_def.type == "trigger" then
        if card_def.trigger_type then
            addLine(rows, L("card.label.trigger", "trigger"), card_def.trigger_type)
        end
        if card_def.trigger_interval then
            addLine(rows, L("card.label.interval", "interval"), string.format("%.1fs", card_def.trigger_interval / 1000))
        end
        if card_def.trigger_distance then
            addLine(rows, L("card.label.distance", "distance"), card_def.trigger_distance)
        end
    end

    addLine(rows, L("card.label.max_uses", "max uses"), card_def.max_uses)
    addLine(rows, L("card.label.mana_cost", "mana cost"), card_def.mana_cost)
    addLine(rows, L("card.label.damage", "damage"), card_def.damage)
    local localizedDamageType = card_def.damage_type and L("card.damage_type." .. card_def.damage_type, card_def.damage_type) or nil
    addLine(rows, L("card.label.damage_type", "damage type"), localizedDamageType)
    addLine(rows, L("card.label.radius_of_effect", "radius of effect"), card_def.radius_of_effect)
    addLine(rows, L("card.label.spread_angle", "spread angle"), card_def.spread_angle)
    addLine(rows, L("card.label.projectile_speed", "projectile speed"), card_def.projectile_speed)
    addLine(rows, L("card.label.lifetime", "lifetime"), card_def.lifetime)
    addLine(rows, L("card.label.cast_delay", "cast delay"), card_def.cast_delay)
    addLine(rows, L("card.label.recharge", "recharge"), card_def.recharge_time)
    addLine(rows, L("card.label.spread_modifier", "spread modifier"), card_def.spread_modifier)
    addLine(rows, L("card.label.speed_modifier", "speed modifier"), card_def.speed_modifier)
    addLine(rows, L("card.label.lifetime_modifier", "lifetime modifier"), card_def.lifetime_modifier)
    addLine(rows, L("card.label.crit_modifier", "crit chance mod"), card_def.critical_hit_chance_modifier)
    addLine(rows, L("card.label.weight", "weight"), card_def.weight)

    local rarityColors = {
        common = "gray",
        uncommon = "green",
        rare = "blue",
        legendary = "purple"
    }
    local tagColors = {
        brute = "red",
        tactical = "cyan",
        mobility = "orange",
        defense = "green",
        hazard = "brown",
        elemental = "blue"
    }

    local assignment = nil
    if CardRarityTags and CardRarityTags.cardAssignments then
        assignment = CardRarityTags.cardAssignments[cardId]
    end
    if not assignment and CardRarityTags and CardRarityTags.triggerAssignments then
        assignment = CardRarityTags.triggerAssignments[cardId]
    end

    if assignment then
        local pillDefs = {}
        if assignment.rarity then
            local rarity = tostring(assignment.rarity)
            local rarityBg = rarityColors[rarity] or tooltipStyle.idBg
            local localizedRarity = L("card.rarity." .. rarity, rarity)
            table.insert(pillDefs, makeTooltipPill(localizedRarity, { background = rarityBg, color = "white" }))
        end
        if assignment.tags and #assignment.tags > 0 then
            for _, tag in ipairs(assignment.tags) do
                local tagBg = tagColors[tag] or "dim_gray"
                local localizedTag = L("card.tag." .. tostring(tag), tostring(tag))
                table.insert(pillDefs, makeTooltipPill(localizedTag, { background = tagBg, color = "white" }))
            end
        end
        if #pillDefs > 0 then
            table.insert(rows, dsl.strict.hbox {
                config = {
                    align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER),
                    padding = rowPadding
                },
                children = pillDefs
            })
        end
    end

    -- Single column layout for card tooltips
    local v = dsl.strict.vbox {
        config = {
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_TOP),
            color = tooltipStyle.innerColor,
            padding = innerPad
        },
        children = rows
    }

    local root = dsl.strict.root {
        config = {
            color = tooltipStyle.bgColor,
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER),
            padding = innerPad,
            outlineThickness = 2,
            outlineColor = tooltipStyle.outlineColor,
            shadow = true
        },
        children = { v }
    }

    local boxID = dsl.spawn({ x = 200, y = 200 }, root)

    ui.box.set_draw_layer(boxID, "ui")
    ui.box.RenewAlignment(registry, boxID)
    snapTooltipVisual(boxID)
    -- ui.box.AssignStateTagsToUIBox(boxID, PLANNING_STATE)
    ui.box.ClearStateTagsFromUIBox(boxID) -- remove all state tags from sub entities and box
    -- remove_default_state_tag(boxID)

    return boxID
end

function ensureCardTooltip(card_def, opts)
    if not card_def then return nil end

    local cardId = card_def.id or card_def.cardID
    if not cardId then return nil end

    local cache = card_tooltip_cache
    if opts and opts.status then
        cache = card_tooltip_disabled_cache
    end

    local cached = cacheFetch(cache, cardId)
    if cached then return cached end

    local tooltip = makeCardTooltip(card_def, opts)
    cacheStore(cache, cardId, tooltip)

    layer_order_system.assignZIndexToEntity(
        tooltip,
        z_orders.ui_tooltips
    )

    local t = component_cache.get(tooltip, Transform)
    if t then
        t.actualY = globals.screenHeight() * 0.5 - (t.actualH * 0.5)
        t.visualY = t.actualY
    end

    clear_state_tags(tooltip)
    return tooltip
end

local function destroyPlayerStatsTooltip()
    if stats_tooltip.entity and entity_cache.valid(stats_tooltip.entity) then
        registry:destroy(stats_tooltip.entity)
    end
    stats_tooltip.entity = nil
    stats_tooltip.version = 0
end

local function collectPlayerStatsSnapshot()
    local ctx = combat_context
    if not ctx or not ctx.side1 or not ctx.side1[1] then return nil end

    local player = ctx.side1[1]
    local stats = player and player.stats
    if not player or not stats then return nil end

    local level = player.level or 1
    local xpToNext = nil
    if CombatSystem and CombatSystem.Game and CombatSystem.Game.Leveling and CombatSystem.Game.Leveling.xp_to_next then
        xpToNext = CombatSystem.Game.Leveling.xp_to_next(ctx, player, level)
    end

    local perType = {}
    if CombatSystem and CombatSystem.Core and CombatSystem.Core.DAMAGE_TYPES then
        for _, dt in ipairs(CombatSystem.Core.DAMAGE_TYPES) do
            perType[#perType + 1] = {
                type = dt,
                dmg = stats:get(dt .. "_damage"),
                mod = stats:get(dt .. "_modifier_pct"),
                resist = stats:get(dt .. "_resist_pct"),
                duration = stats:get(dt .. "_duration_pct")
            }
        end
    end

    return {
        level = level,
        xp = player.xp or 0,
        xp_to_next = xpToNext,
        hp = player.hp or stats:get('health') or 0,
        max_hp = player.max_health or stats:get('health') or 0,
        health_regen = stats:get('health_regen'),
        physique = stats:get('physique'),
        cunning = stats:get('cunning'),
        spirit = stats:get('spirit'),
        offensive_ability = stats:get('offensive_ability'),
        defensive_ability = stats:get('defensive_ability'),
        weapon_min = stats:get('weapon_min'),
        weapon_max = stats:get('weapon_max'),
        attack_speed = stats:get('attack_speed'),
        cast_speed = stats:get('cast_speed'),
        cooldown_reduction = stats:get('cooldown_reduction'),
        life_steal_pct = stats:get('life_steal_pct'),
        crit_damage_pct = stats:get('crit_damage_pct'),
        dodge_chance_pct = stats:get('dodge_chance_pct'),
        armor = stats:get('armor'),
        run_speed = stats:get('run_speed'),
        move_speed_pct = stats:get('move_speed_pct'),
        all_damage_pct = stats:get('all_damage_pct'),
        skill_energy_cost_reduction = stats:get('skill_energy_cost_reduction'),
        experience_gained_pct = stats:get('experience_gained_pct'),
        weapon_damage_pct = stats:get('weapon_damage_pct'),
        block_chance_pct = stats:get('block_chance_pct'),
        block_amount = stats:get('block_amount'),
        block_recovery_reduction_pct = stats:get('block_recovery_reduction_pct'),
        percent_absorb_pct = stats:get('percent_absorb_pct'),
        flat_absorb = stats:get('flat_absorb'),
        armor_absorption_bonus_pct = stats:get('armor_absorption_bonus_pct'),
        healing_received_pct = stats:get('healing_received_pct'),
        reflect_damage_pct = stats:get('reflect_damage_pct'),
        penetration_all_pct = stats:get('penetration_all_pct'),
        armor_penetration_pct = stats:get('armor_penetration_pct'),
        max_resist_cap_pct = stats:get('max_resist_cap_pct'),
        min_resist_cap_pct = stats:get('min_resist_cap_pct'),
        damage_taken_reduction_pct = stats:get('damage_taken_reduction_pct'),
        burn_damage_pct = stats:get('burn_damage_pct'),
        burn_tick_rate_pct = stats:get('burn_tick_rate_pct'),
        damage_vs_frozen_pct = stats:get('damage_vs_frozen_pct'),
        buff_duration_pct = stats:get('buff_duration_pct'),
        buff_effect_pct = stats:get('buff_effect_pct'),
        chain_targets = stats:get('chain_targets'),
        on_move_proc_frequency_pct = stats:get('on_move_proc_frequency_pct'),
        hazard_radius_pct = stats:get('hazard_radius_pct'),
        hazard_damage_pct = stats:get('hazard_damage_pct'),
        hazard_duration = stats:get('hazard_duration'),
        max_poison_stacks_pct = stats:get('max_poison_stacks_pct'),
        summon_hp_pct = stats:get('summon_hp_pct'),
        summon_damage_pct = stats:get('summon_damage_pct'),
        summon_persistence = stats:get('summon_persistence'),
        barrier_refresh_rate_pct = stats:get('barrier_refresh_rate_pct'),
        health_pct = stats:get('health_pct'),
        melee_damage_pct = stats:get('melee_damage_pct'),
        melee_crit_chance_pct = stats:get('melee_crit_chance_pct'),
        -- Elemental damage modifiers (derived from Spirit)
        fire_modifier_pct = stats:get('fire_modifier_pct'),
        cold_modifier_pct = stats:get('cold_modifier_pct'),
        lightning_modifier_pct = stats:get('lightning_modifier_pct'),
        acid_modifier_pct = stats:get('acid_modifier_pct'),
        vitality_modifier_pct = stats:get('vitality_modifier_pct'),
        aether_modifier_pct = stats:get('aether_modifier_pct'),
        chaos_modifier_pct = stats:get('chaos_modifier_pct'),
        -- Physical/pierce modifiers (derived from Cunning)
        physical_modifier_pct = stats:get('physical_modifier_pct'),
        pierce_modifier_pct = stats:get('pierce_modifier_pct'),
        -- DoT duration modifiers
        burn_duration_pct = stats:get('burn_duration_pct'),
        frostburn_duration_pct = stats:get('frostburn_duration_pct'),
        electrocute_duration_pct = stats:get('electrocute_duration_pct'),
        poison_duration_pct = stats:get('poison_duration_pct'),
        vitality_decay_duration_pct = stats:get('vitality_decay_duration_pct'),
        bleed_duration_pct = stats:get('bleed_duration_pct'),
        trauma_duration_pct = stats:get('trauma_duration_pct'),
        per_type = perType
    }
end


local function ensurePlayerStatsTooltip()
    if stats_tooltip.entity and entity_cache.valid(stats_tooltip.entity) and stats_tooltip.version == TOOLTIP_FONT_VERSION then
        return stats_tooltip.entity
    end

    destroyPlayerStatsTooltip()

    local tooltip = stats_tooltip.makeTooltip(collectPlayerStatsSnapshot())
    if not tooltip then return nil end

    stats_tooltip.entity = tooltip
    stats_tooltip.version = TOOLTIP_FONT_VERSION

    layer_order_system.assignZIndexToEntity(
        tooltip,
        z_orders.ui_tooltips
    )

    return tooltip
end

local function destroyDetailedStatsTooltip()
    if stats_tooltip.detailedEntity and entity_cache.valid(stats_tooltip.detailedEntity) then
        registry:destroy(stats_tooltip.detailedEntity)
    end
    stats_tooltip.detailedEntity = nil
    stats_tooltip.detailedVersion = 0
end

-- ============================================================================
-- STAT TOOLTIP SYSTEM - Declarative stat definitions and helpers
-- ============================================================================
-- All stat tooltip configuration and helpers are stored in a single table
-- to avoid hitting Lua's 200 local variable limit

StatTooltipSystem = {
    -- Format types
    FORMAT = { INT = "int", FLOAT = "float", PCT = "pct", RANGE = "range", FRACTION = "fraction" },

    -- Snapshot hash cache for lazy updates
    playerStatsHash = nil,
    detailedStatsHash = nil,

    -- Stats to show in basic tooltip
    BASIC_STATS = {
        "level", "health", "health_regen", "xp",
        "physique", "cunning", "spirit",
        "offensive_ability", "defensive_ability",
        "damage", "attack_speed", "cast_speed",
        "cooldown_reduction", "skill_energy_cost_reduction",
        "all_damage_pct", "life_steal_pct", "crit_damage_pct",
        "dodge_chance_pct", "armor",
        "run_speed", "move_speed_pct"
    },

    -- Stats to show in detailed tooltip
    DETAILED_STATS = {
        "experience_gained_pct", "weapon_damage_pct",
        "block_chance_pct", "block_amount", "block_recovery_reduction_pct",
        "percent_absorb_pct", "flat_absorb", "armor_absorption_bonus_pct",
        "healing_received_pct", "reflect_damage_pct",
        "penetration_all_pct", "armor_penetration_pct",
        "max_resist_cap_pct", "min_resist_cap_pct", "damage_taken_reduction_pct",
        "burn_damage_pct", "burn_tick_rate_pct", "damage_vs_frozen_pct",
        "buff_duration_pct", "buff_effect_pct",
        "chain_targets", "on_move_proc_frequency_pct",
        "hazard_radius_pct", "hazard_damage_pct", "hazard_duration",
        "max_poison_stacks_pct",
        "summon_hp_pct", "summon_damage_pct", "summon_persistence",
        "barrier_refresh_rate_pct", "health_pct", "melee_damage_pct", "melee_crit_chance_pct",
        -- Elemental damage modifiers
        "fire_modifier_pct", "cold_modifier_pct", "lightning_modifier_pct",
        "acid_modifier_pct", "vitality_modifier_pct", "aether_modifier_pct", "chaos_modifier_pct",
        -- Physical/pierce modifiers
        "physical_modifier_pct", "pierce_modifier_pct",
        -- DoT duration modifiers
        "burn_duration_pct", "frostburn_duration_pct", "electrocute_duration_pct",
        "poison_duration_pct", "vitality_decay_duration_pct", "bleed_duration_pct", "trauma_duration_pct"
    },

    -- Group labels
    GROUPS = {
        core = "Core", attributes = "Attributes", combat = "Combat",
        offense = "Offense", defense = "Defense", utility = "Utility",
        movement = "Movement", status = "Status", buffs = "Buffs",
        special = "Special", hazard = "Hazard", summon = "Summon", elemental = "Elemental"
    },

    -- Optional: color-code stat labels (used for debugging/layout verification).
    LABEL_GROUP_COLORS = {
        core = "gold",
        attributes = "orange",
        combat = "cyan",
        offense = "red",
        defense = "blue",
        utility = "purple",
        movement = "yellow",
        status = "fuchsia",
        buffs = "green",
        special = "pink",
        hazard = "poison",
        summon = "cyan",
        elemental = "cyan"
    },

    -- Stats where positive values are bad (inverted color)
    REVERSED_STATS = { damage_taken_reduction_pct = true }
}

-- Stat definitions (using short format refs)
local SF = StatTooltipSystem.FORMAT
StatTooltipSystem.DEFS = {
    level = { label = "stats.level", format = SF.INT, group = "core" },
    health = { label = "stats.health", format = SF.FRACTION, keys = {"hp", "max_hp"}, group = "core" },
    health_regen = { label = "stats.health_regen", format = SF.FLOAT, suffix = "/s", group = "core" },
    xp = { label = "stats.xp", format = SF.FRACTION, keys = {"xp", "xp_to_next"}, group = "core" },
    physique = { label = "stats.physique", format = SF.INT, group = "attributes" },
    cunning = { label = "stats.cunning", format = SF.INT, group = "attributes" },
    spirit = { label = "stats.spirit", format = SF.INT, group = "attributes" },
    offensive_ability = { label = "stats.offensive_ability", format = SF.INT, group = "combat" },
    defensive_ability = { label = "stats.defensive_ability", format = SF.INT, group = "combat" },
    damage = { label = "stats.damage", format = SF.RANGE, keys = {"weapon_min", "weapon_max"}, group = "combat" },
    attack_speed = { label = "stats.attack_speed", format = SF.FLOAT, suffix = "/s", group = "combat" },
    cast_speed = { label = "stats.cast_speed", format = SF.FLOAT, suffix = "/s", group = "combat" },
    all_damage_pct = { label = "stats.all_damage", format = SF.PCT, group = "offense" },
    weapon_damage_pct = { label = "stats.weapon_damage", format = SF.PCT, group = "offense" },
    crit_damage_pct = { label = "stats.crit_damage", format = SF.PCT, group = "offense" },
    life_steal_pct = { label = "stats.life_steal", format = SF.PCT, group = "offense" },
    penetration_all_pct = { label = "stats.penetration_all", format = SF.PCT, group = "offense" },
    armor_penetration_pct = { label = "stats.armor_penetration", format = SF.PCT, group = "offense" },
    armor = { label = "stats.armor", format = SF.INT, group = "defense" },
    dodge_chance_pct = { label = "stats.dodge", format = SF.PCT, group = "defense" },
    block_chance_pct = { label = "stats.block_chance", format = SF.PCT, group = "defense" },
    block_amount = { label = "stats.block_amount", format = SF.INT, group = "defense" },
    block_recovery_reduction_pct = { label = "stats.block_recovery", format = SF.PCT, group = "defense" },
    percent_absorb_pct = { label = "stats.absorb_pct", format = SF.PCT, group = "defense" },
    flat_absorb = { label = "stats.absorb_flat", format = SF.INT, group = "defense" },
    armor_absorption_bonus_pct = { label = "stats.armor_absorb_bonus", format = SF.PCT, group = "defense" },
    damage_taken_reduction_pct = { label = "stats.damage_reduction", format = SF.PCT, group = "defense" },
    reflect_damage_pct = { label = "stats.reflect_damage", format = SF.PCT, group = "defense" },
    max_resist_cap_pct = { label = "stats.max_resist_cap", format = SF.PCT, group = "defense" },
    min_resist_cap_pct = { label = "stats.min_resist_cap", format = SF.PCT, group = "defense" },
    cooldown_reduction = { label = "stats.cooldown_reduction", format = SF.PCT, group = "utility" },
    skill_energy_cost_reduction = { label = "stats.skill_cost_reduction", format = SF.PCT, group = "utility" },
    experience_gained_pct = { label = "stats.xp_gain", format = SF.PCT, group = "utility" },
    healing_received_pct = { label = "stats.healing_received", format = SF.PCT, group = "utility" },
    run_speed = { label = "stats.run_speed", format = SF.FLOAT, group = "movement" },
    move_speed_pct = { label = "stats.move_speed", format = SF.PCT, group = "movement" },
    burn_damage_pct = { label = "stats.burn_damage", format = SF.PCT, group = "status" },
    burn_tick_rate_pct = { label = "stats.burn_tick_rate", format = SF.PCT, group = "status" },
    damage_vs_frozen_pct = { label = "stats.vs_frozen_damage", format = SF.PCT, group = "status" },
    max_poison_stacks_pct = { label = "stats.max_poison_stacks", format = SF.PCT, group = "status" },
    buff_duration_pct = { label = "stats.buff_duration", format = SF.PCT, group = "buffs" },
    buff_effect_pct = { label = "stats.buff_effect", format = SF.PCT, group = "buffs" },
    chain_targets = { label = "stats.chain_targets", format = SF.INT, group = "special" },
    on_move_proc_frequency_pct = { label = "stats.on_move_proc", format = SF.PCT, group = "special" },
    hazard_radius_pct = { label = "stats.hazard_radius", format = SF.PCT, group = "hazard" },
    hazard_damage_pct = { label = "stats.hazard_damage", format = SF.PCT, group = "hazard" },
    hazard_duration = { label = "stats.hazard_duration", format = SF.INT, group = "hazard" },
    summon_hp_pct = { label = "stats.summon_hp", format = SF.PCT, group = "summon" },
    summon_damage_pct = { label = "stats.summon_damage", format = SF.PCT, group = "summon" },
    summon_persistence = { label = "stats.summon_persistence", format = SF.INT, group = "summon" },
    barrier_refresh_rate_pct = { label = "stats.barrier_refresh", format = SF.PCT, group = "defense" },
    health_pct = { label = "stats.health_bonus", format = SF.PCT, group = "core" },
    melee_damage_pct = { label = "stats.melee_damage", format = SF.PCT, group = "offense" },
    melee_crit_chance_pct = { label = "stats.melee_crit", format = SF.PCT, group = "offense" },
    -- Elemental damage modifiers (derived from Spirit)
    fire_modifier_pct = { label = "stats.fire_modifier", format = SF.PCT, group = "elemental" },
    cold_modifier_pct = { label = "stats.cold_modifier", format = SF.PCT, group = "elemental" },
    lightning_modifier_pct = { label = "stats.lightning_modifier", format = SF.PCT, group = "elemental" },
    acid_modifier_pct = { label = "stats.acid_modifier", format = SF.PCT, group = "elemental" },
    vitality_modifier_pct = { label = "stats.vitality_modifier", format = SF.PCT, group = "elemental" },
    aether_modifier_pct = { label = "stats.aether_modifier", format = SF.PCT, group = "elemental" },
    chaos_modifier_pct = { label = "stats.chaos_modifier", format = SF.PCT, group = "elemental" },
    -- Physical/pierce modifiers (derived from Cunning)
    physical_modifier_pct = { label = "stats.physical_modifier", format = SF.PCT, group = "offense" },
    pierce_modifier_pct = { label = "stats.pierce_modifier", format = SF.PCT, group = "offense" },
    -- DoT duration modifiers
    burn_duration_pct = { label = "stats.burn_duration", format = SF.PCT, group = "status" },
    frostburn_duration_pct = { label = "stats.frostburn_duration", format = SF.PCT, group = "status" },
    electrocute_duration_pct = { label = "stats.electrocute_duration", format = SF.PCT, group = "status" },
    poison_duration_pct = { label = "stats.poison_duration", format = SF.PCT, group = "status" },
    vitality_decay_duration_pct = { label = "stats.vitality_decay_duration", format = SF.PCT, group = "status" },
    bleed_duration_pct = { label = "stats.bleed_duration", format = SF.PCT, group = "status" },
    trauma_duration_pct = { label = "stats.trauma_duration", format = SF.PCT, group = "status" },
}

-- Helper functions as methods
function StatTooltipSystem.computeHash(snapshot)
    if not snapshot then return "nil" end
    local parts = {}
    for k, v in pairs(snapshot) do
        if k ~= "per_type" then parts[#parts + 1] = k .. "=" .. tostring(v) end
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

function StatTooltipSystem.getLabel(key)
    local def = StatTooltipSystem.DEFS[key]
    if def and def.label and localization then
        local loc = localization.get(def.label)
        if loc and loc ~= def.label then return loc end
    end
    return key:gsub("_pct$", ""):gsub("_", " ")
end

function StatTooltipSystem.getGroupLabel(groupId)
    if localization then
        local loc = localization.get("stats.group." .. groupId)
        if loc and loc ~= "stats.group." .. groupId then return loc end
    end
    return StatTooltipSystem.GROUPS[groupId] or groupId:gsub("^%l", string.upper)
end

function StatTooltipSystem.formatValue(key, value, snapshot, showZeros)
    local def = StatTooltipSystem.DEFS[key]
    local F = StatTooltipSystem.FORMAT

    if not def then
        return type(value) == "number" and tostring(math.floor(value + 0.5)) or tostring(value)
    end

    if def.format == F.FRACTION and def.keys then
        local v1, v2 = snapshot[def.keys[1]], snapshot[def.keys[2]]
        return (v1 and v2) and string.format("%d / %d", math.floor(v1 + 0.5), math.floor(v2 + 0.5)) or nil
    end

    if def.format == F.RANGE and def.keys then
        local v1, v2 = snapshot[def.keys[1]], snapshot[def.keys[2]]
        return (v1 and v2) and string.format("%d - %d", math.floor(v1 + 0.5), math.floor(v2 + 0.5)) or nil
    end

    -- Skip nil/zero values unless showZeros is true
    local isZero = value == nil or (type(value) == "number" and math.abs(value) < 0.0001)
    if isZero and not showZeros then return nil end

    -- Use 0 for display if value is nil
    local displayValue = value or 0

    if def.format == F.PCT then return string.format("%d%%", math.floor(displayValue + 0.5))
    elseif def.format == F.FLOAT then return string.format("%.1f%s", displayValue, def.suffix or "")
    elseif def.format == F.INT then return tostring(math.floor(displayValue + 0.5))
    end
    return tostring(displayValue)
end

function StatTooltipSystem.getValueColor(key, value)
    if type(value) ~= "number" then return tooltipStyle.valueColor or "white" end
    if value > 0 then return "green" end
    if value < 0 then return "red" end
    return tooltipStyle.valueColor or "white"
end

function StatTooltipSystem.makeRow(key, snapshot, opts)
    opts = opts or {}
    local def = StatTooltipSystem.DEFS[key]
    local value = (def and def.keys) and snapshot[def.keys[1]] or snapshot[key]

    -- Skip nil/zero values unless showZeros is true
    local isZero = value == nil or (type(value) == "number" and math.abs(value) < 0.0001)
    if isZero and not opts.showZeros then return nil end

    local formatted = StatTooltipSystem.formatValue(key, value, snapshot, opts.showZeros)
    if not formatted then return nil end

    local label = StatTooltipSystem.getLabel(key)
    local group = def and def.group or "other"
    local displayValue = value or 0
    local color = opts.colorCode and StatTooltipSystem.getValueColor(key, displayValue) or (tooltipStyle.valueColor or "white")

    -- Only enable coded parsing if the label actually contains markup
    local hasMarkup = label:find("%[") ~= nil
    if opts.labelColorCode and not hasMarkup then
        local groupColor = StatTooltipSystem.LABEL_GROUP_COLORS and StatTooltipSystem.LABEL_GROUP_COLORS[group]
        if groupColor then
            label = string.format("[%s](color=%s)", label, groupColor)
            hasMarkup = true
        end
    end

    return makeTooltipRow(label, formatted, {
        rowPadding = opts.rowPadding or tooltipStyle.rowPadding,
        labelOpts = {
            background = tooltipStyle.labelBg,
            color = tooltipStyle.labelColor,
            padding = opts.pillPadding or tooltipStyle.pillPadding,
            fontSize = opts.fontSize,
            coded = hasMarkup  -- Only enable if label has [text](effects) markup
        },
        valueOpts = {
            color = color,
            padding = opts.textPadding or tooltipStyle.textPadding,
            fontSize = opts.fontSize
        },
        align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER)
    })
end

function StatTooltipSystem.makeSectionHeader(groupId, opts)
    opts = opts or {}
    -- Don't use string.upper() as it doesn't handle UTF-8 properly
    local label = StatTooltipSystem.getGroupLabel(groupId)
    return dsl.strict.hbox {
        config = {
            color = opts.headerBg or tooltipStyle.labelBg,
            padding = opts.headerPadding or 3,
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER)
        },
        children = {
            dsl.strict.text(label, {
                fontSize = opts.headerFontSize or 10,
                color = opts.headerColor or tooltipStyle.labelColor,
                shadow = false
            })
        }
    }
end

function StatTooltipSystem.buildRows(statKeys, snapshot, opts)
    opts = opts or {}
    local rows, currentGroup = {}, nil

    for _, key in ipairs(statKeys) do
        local def = StatTooltipSystem.DEFS[key]
        local group = def and def.group or "other"

        if opts.showHeaders and group ~= currentGroup then
            -- Note: removed empty spacer hbox as it was rendering as a rectangle
            rows[#rows + 1] = StatTooltipSystem.makeSectionHeader(group, opts)
            currentGroup = group
        end

        local row = StatTooltipSystem.makeRow(key, snapshot, opts)
        if row then rows[#rows + 1] = row end
    end
    return rows
end

function StatTooltipSystem.buildElementalRows(perType, opts)
    opts = opts or {}
    local rows = {}
    if not perType or #perType == 0 then return rows end

    if opts.showHeaders then
        rows[#rows + 1] = StatTooltipSystem.makeSectionHeader("elemental", opts)
    end

    for _, entry in ipairs(perType) do
        local t = entry.type or "?"

        -- Localize damage type name
        local localizedType = L("stats.damage_type." .. t, t)

        local function addRow(suffixKey, val)
            -- Skip nil/zero values unless showZeros is true
            local isZero = not val or math.abs(val) < 0.01
            if isZero and not opts.showZeros then return end

            local displayVal = val or 0

            -- Localize suffix
            local localizedSuffix = L("stats.suffix." .. suffixKey, suffixKey)

            local fmt = suffixKey:match("pct") and string.format("%d%%", math.floor(displayVal + 0.5)) or tostring(math.floor(displayVal + 0.5))
            local clr = opts.colorCode and (displayVal > 0 and "green" or (displayVal < 0 and "red" or (tooltipStyle.valueColor or "white"))) or tooltipStyle.valueColor
            local r = makeTooltipRow(localizedType .. " " .. localizedSuffix, fmt, {
                rowPadding = opts.rowPadding or tooltipStyle.rowPadding,
                labelOpts = {
                    background = tooltipStyle.labelBg,
                    color = tooltipStyle.labelColor,
                    padding = opts.pillPadding or tooltipStyle.pillPadding,
                    fontSize = opts.fontSize
                },
                valueOpts = {
                    color = clr,
                    padding = opts.textPadding or tooltipStyle.textPadding,
                    fontSize = opts.fontSize
                },
                align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER)
            })
            if r then rows[#rows + 1] = r end
        end
        addRow("dmg", entry.dmg)
        addRow("dmg_pct", entry.mod)
        addRow("resist", entry.resist)
        addRow("dur_pct", entry.duration)
    end
    return rows
end

-- Unified N-column layout builder (single function replaces 3 old ones)
local function buildNColumnBody(rows, columnCount, opts)
    opts = opts or {}
    columnCount = columnCount or 2
    if #rows == 0 then return dsl.strict.vbox { config = { padding = 0 }, children = {} } end

    local columns = {}
    for i = 1, columnCount do columns[i] = {} end

    local rowsPerCol = math.ceil(#rows / columnCount)
    for i, row in ipairs(rows) do
        local colIdx = math.min(math.ceil(i / rowsPerCol), columnCount)
        columns[colIdx][#columns[colIdx] + 1] = row
    end

    local children = {}
    for _, col in ipairs(columns) do
        if #col > 0 then
            children[#children + 1] = dsl.strict.vbox {
                config = { align = bit.bor(AlignmentFlag.HORIZONTAL_LEFT, AlignmentFlag.VERTICAL_TOP), padding = opts.columnPadding or 0 },
                children = col
            }
        end
    end

    return dsl.strict.hbox {
        config = { align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_TOP), color = opts.innerColor, padding = opts.padding or 0 },
        children = children
    }
end

-- Compatibility aliases
local function buildTwoColumnBody(rows, opts) return buildNColumnBody(rows, 2, opts) end
local function buildFourColumnBody(rows, opts) return buildNColumnBody(rows, 4, opts) end

local function makeDetailedStatsTooltip(snapshot)
    -- Compressed styling for detailed stats
    -- Use 16px for compact text (smallest eight-bit-dragon size)
    local compactPadding = tooltipStyle.outerPadding or 10
    local compactRowPadding = 1
    local compactFontSize = 16
    local opts = {
        colorCode = true,
        labelColorCode = true,
        showHeaders = true,  -- Show section headers
        showZeros = true,
        rowPadding = compactRowPadding,
        fontSize = compactFontSize,
        pillPadding = 2,
        headerFontSize = 13,  -- Match body font for consistency
        headerPadding = 2,
        textPadding = 1
    }

    local rows = {}
    if not snapshot then
        rows[1] = makeTooltipRow("status", "Stats unavailable", {
            rowPadding = compactRowPadding,
            labelOpts = { background = tooltipStyle.labelBg, color = tooltipStyle.labelColor, padding = 2 },
            valueOpts = { color = "red", padding = 1 },
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER)
        })
    else
        -- Build main stat rows using the new system
        rows = StatTooltipSystem.buildRows(StatTooltipSystem.DETAILED_STATS, snapshot, opts)

        -- Add elemental/per-type stats in a separate section
        local elementalRows = StatTooltipSystem.buildElementalRows(snapshot.per_type, opts)
        for _, r in ipairs(elementalRows) do rows[#rows + 1] = r end
    end

    if #rows == 0 then
        rows[1] = makeTooltipRow("status", "No stats", {
            rowPadding = compactRowPadding,
            labelOpts = { background = tooltipStyle.labelBg, color = tooltipStyle.labelColor, padding = 2 },
            valueOpts = { color = "yellow", padding = 1 },
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER)
        })
    end

    -- Use 5 columns for more compact layout
    -- Note: padding only on root to prevent overflow, inner body has no extra padding
    local v = buildNColumnBody(rows, 5, { innerColor = tooltipStyle.innerColor, padding = 0, columnPadding = 2 })

    local root = dsl.strict.root {
        config = {
            color = tooltipStyle.bgColor,
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_TOP),
            padding = innerPad,
            outlineThickness = 2,
            outlineColor = tooltipStyle.outlineColor,
            shadow = true
        },
        children = { v }
    }

    local boxID = dsl.spawn({ x = 200, y = 200 }, root)
    ui.box.set_draw_layer(boxID, "ui")
    ui.box.RenewAlignment(registry, boxID)
    snapTooltipVisual(boxID)
    ui.box.ClearStateTagsFromUIBox(boxID)

    return boxID
end

local function ensureDetailedStatsTooltip()
    if stats_tooltip.detailedEntity and entity_cache.valid(stats_tooltip.detailedEntity) and stats_tooltip.detailedVersion == TOOLTIP_FONT_VERSION then
        return stats_tooltip.detailedEntity
    end

    destroyDetailedStatsTooltip()

    local tooltip = makeDetailedStatsTooltip(collectPlayerStatsSnapshot())
    if not tooltip then return nil end

    stats_tooltip.detailedEntity = tooltip
    stats_tooltip.detailedVersion = TOOLTIP_FONT_VERSION

    layer_order_system.assignZIndexToEntity(
        tooltip,
        z_orders.ui_tooltips
    )

    return tooltip
end
function stats_tooltip.makeTooltip(snapshot)
    local innerPad = tooltipStyle.outerPadding or 10  -- Increased padding for better fit
    local opts = {
        colorCode = true,
        labelColorCode = true,
        showHeaders = true,
        rowPadding = 2,
        headerFontSize = 12,
        headerPadding = 2
    }

    local rows = {}
    if not snapshot then
        rows[1] = makeTooltipRow("status", "Stats unavailable", {
            rowPadding = 2,
            labelOpts = { background = tooltipStyle.labelBg, color = tooltipStyle.labelColor },
            valueOpts = { color = "red" },
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER)
        })
    else
        -- Build stat rows using the new declarative system
        rows = StatTooltipSystem.buildRows(StatTooltipSystem.BASIC_STATS, snapshot, opts)
    end

    if #rows == 0 then
        rows[1] = makeTooltipRow("status", "No stats", {
            rowPadding = 2,
            labelOpts = { background = tooltipStyle.labelBg, color = tooltipStyle.labelColor },
            valueOpts = { color = "yellow" },
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER)
        })
    end

    -- Use 3 columns for better layout, padding only on root
    local v = buildNColumnBody(rows, 3, { innerColor = tooltipStyle.innerColor, padding = 0, columnPadding = 4 })

    local root = dsl.strict.root {
        config = {
            color = tooltipStyle.bgColor,
            align = bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER),
            padding = innerPad,
            outlineThickness = 2,
            outlineColor = tooltipStyle.outlineColor,
            shadow = true
        },
        children = { v }
    }

    local boxID = dsl.spawn({ x = 200, y = 200 }, root)
    ui.box.set_draw_layer(boxID, "ui")
    ui.box.RenewAlignment(registry, boxID)
    snapTooltipVisual(boxID)
    ui.box.ClearStateTagsFromUIBox(boxID)

    return boxID
end

local function showPlayerStatsTooltip(anchorEntity)
    local tooltip = ensurePlayerStatsTooltip()
    if not tooltip then return end

    -- Reapply state tags in case they were cleared when hidden
    ui.box.ClearStateTagsFromUIBox(tooltip)
    ui.box.AddStateTagToUIBox(tooltip, PLANNING_STATE)
    ui.box.AddStateTagToUIBox(tooltip, ACTION_STATE)
    ui.box.AddStateTagToUIBox(tooltip, SHOP_STATE)
    ui.box.AddStateTagToUIBox(tooltip, PLAYER_STATS_TOOLTIP_STATE)

    ui.box.RenewAlignment(registry, tooltip)

    if anchorEntity then
        positionTooltipRightOfEntity(tooltip, anchorEntity, { gap = 10 })
    end

    add_state_tag(tooltip, PLAYER_STATS_TOOLTIP_STATE)
    activate_state(PLAYER_STATS_TOOLTIP_STATE)
end

local function hidePlayerStatsTooltip()
    if not stats_tooltip.entity or not entity_cache.valid(stats_tooltip.entity) then return end
    deactivate_state(PLAYER_STATS_TOOLTIP_STATE)
    clear_state_tags(stats_tooltip.entity)
    ui.box.ClearStateTagsFromUIBox(stats_tooltip.entity)
end

local function showDetailedStatsTooltip(anchorEntity)
    local tooltip = ensureDetailedStatsTooltip()
    if not tooltip then return end

    ui.box.ClearStateTagsFromUIBox(tooltip)
    ui.box.AddStateTagToUIBox(tooltip, PLANNING_STATE)
    ui.box.AddStateTagToUIBox(tooltip, ACTION_STATE)
    ui.box.AddStateTagToUIBox(tooltip, SHOP_STATE)
    ui.box.AddStateTagToUIBox(tooltip, DETAILED_STATS_TOOLTIP_STATE)

    ui.box.RenewAlignment(registry, tooltip)

    if anchorEntity then
        positionTooltipRightOfEntity(tooltip, anchorEntity, { gap = 10 })
    end

    add_state_tag(tooltip, DETAILED_STATS_TOOLTIP_STATE)
    activate_state(DETAILED_STATS_TOOLTIP_STATE)
end

local function hideDetailedStatsTooltip()
    if not stats_tooltip.detailedEntity or not entity_cache.valid(stats_tooltip.detailedEntity) then return end
    deactivate_state(DETAILED_STATS_TOOLTIP_STATE)
    clear_state_tags(stats_tooltip.detailedEntity)
    ui.box.ClearStateTagsFromUIBox(stats_tooltip.detailedEntity)
end

local function refreshPlayerStatsTooltip(anchorEntity)
    if not anchorEntity or not entity_cache.valid(anchorEntity) then return end
    local wasActive = is_state_active and is_state_active(PLAYER_STATS_TOOLTIP_STATE)
    destroyPlayerStatsTooltip()
    local tooltip = ensurePlayerStatsTooltip()
    if not tooltip then return end

    positionTooltipRightOfEntity(tooltip, anchorEntity, { gap = 10 })

    if wasActive then
        add_state_tag(tooltip, PLAYER_STATS_TOOLTIP_STATE)
        activate_state(PLAYER_STATS_TOOLTIP_STATE)
    end
end

local function refreshDetailedStatsTooltip(anchorEntity)
    if not anchorEntity or not entity_cache.valid(anchorEntity) then return end
    local wasActive = is_state_active and is_state_active(DETAILED_STATS_TOOLTIP_STATE)
    destroyDetailedStatsTooltip()
    local tooltip = ensureDetailedStatsTooltip()
    if not tooltip then return end

    positionTooltipRightOfEntity(tooltip, anchorEntity, { gap = 10 })

    if wasActive then
        add_state_tag(tooltip, DETAILED_STATS_TOOLTIP_STATE)
        activate_state(DETAILED_STATS_TOOLTIP_STATE)
    end
end

-- initialize the game area for planning phase, where you combine cards and stuff.
function initPlanningPhase()
    
    ensureShopSystemInitialized() -- make sure card defs carry metadata/tags before any cards spawn

    -- Validate content definitions (runtime check)
    -- Note: Validation errors are non-blocking in dev builds to allow iteration.
    -- Errors are logged to console for debugging. In production, consider making
    -- validation failures block initialization if content integrity is critical.
    local ok, ContentValidator = pcall(require, "tools.content_validator")
    if ok and ContentValidator and ContentValidator.runtime_check then
        local validation_passed = ContentValidator.runtime_check()
        if not validation_passed then
            log_warn("[Gameplay] Content validation found errors - check console output")
        end
    end

    local CastFeedUI = require "ui.cast_feed_ui"
    CastFeedUI.init()
    ui_modules.SubcastDebugUI.init()
    ui_modules.MessageQueueUI.init()
    ensureMessageQueueHooks()
    ui_modules.CurrencyDisplay.init({ amount = globals.currency or 0 })
    ui_modules.TagSynergyPanel.init({
        breakpoints = TagEvaluator.get_breakpoints(),
        layout = { marginX = 24, marginTop = 18, panelWidth = 360 }
    })
    ui_modules.AvatarJokerStrip.init({ margin = 20 })
    ui_modules.TriggerStripUI.init()

    ui_modules.MessageQueueUI.enqueueTest()
    
    -- Changed from timer.run() to timer.run_every_render_frame() to fix flickering
    -- timer.run() executes during fixed timestep which may skip frames
    timer.run_every_render_frame(function()
        local dt = GetFrameTime()

        if CastFeedUI and is_state_active and (is_state_active(PLANNING_STATE) or is_state_active(ACTION_STATE)) then
            CastFeedUI.update(dt)
            CastFeedUI.draw()
        end

        -- if MessageQueueUI and is_state_active and (is_state_active(PLANNING_STATE) or is_state_active(ACTION_STATE)) then
            ui_modules.MessageQueueUI.update(dt)
            ui_modules.MessageQueueUI.draw()
        -- end

        if ui_modules.WandCooldownUI and is_state_active and is_state_active(ACTION_STATE) then
            ui_modules.WandCooldownUI.update(dt)
            ui_modules.WandCooldownUI.draw()
        end

        if ui_modules.CastBlockFlashUI and ui_modules.CastBlockFlashUI.isActive and is_state_active and is_state_active(ACTION_STATE) then
            ui_modules.CastBlockFlashUI.update(dt)
            ui_modules.CastBlockFlashUI.draw()
        end

        if ui_modules.CurrencyDisplay and ui_modules.CurrencyDisplay.isActive and is_state_active
            and (is_state_active(PLANNING_STATE) or is_state_active(SHOP_STATE)) then
            ui_modules.CurrencyDisplay.setAmount(globals.currency or 0)
            ui_modules.CurrencyDisplay.update(dt)
            ui_modules.CurrencyDisplay.draw()
        end

        do
            local DemoFooterUI = gameplay_cfg.getDemoFooterUI()
            if DemoFooterUI then
                DemoFooterUI.update(dt)
                DemoFooterUI.draw()
            end
        end

        if is_state_active and is_state_active(ACTION_STATE) then
            local ManualTriggerPromptUI = gameplay_cfg.getManualTriggerPromptUI()
            if ManualTriggerPromptUI then
                ManualTriggerPromptUI.update(dt)
                ManualTriggerPromptUI.draw()
            end
        end

        if is_state_active and is_state_active(SHOP_STATE) then
            local ShopPackUI = gameplay_cfg.getShopPackUI()
            if ShopPackUI then
                ShopPackUI.update(dt)
                ShopPackUI.draw()
            end
        end

        if ui_modules.TagSynergyPanel and ui_modules.TagSynergyPanel.isActive and is_state_active
            and is_state_active(PLANNING_STATE) then
            ui_modules.TagSynergyPanel.update(dt)
            ui_modules.TagSynergyPanel.draw()

            -- Update synergy panel button visual feedback based on visibility
            local synergyButton = planningUIEntities and planningUIEntities.synergy_toggle_button
            if synergyButton and entity_cache.valid(synergyButton) then
                local config = component_cache.get(synergyButton, UIConfig)
                if config then
                    local isVisible = ui_modules.TagSynergyPanel.isVisible()
                    local targetColor = isVisible and util.getColor("apricot") or util.getColor("gray")
                    config.color = targetColor
                end
            end
        end

        if wandResourceBar then
            wandResourceBar.draw()
        end

        -- Update execution graph slide animation
        if ui_modules.CastExecutionGraphUI and is_state_active and is_state_active(PLANNING_STATE) then
            ui_modules.CastExecutionGraphUI.updateSlide(dt)

            -- Update execution graph button visual feedback based on visibility
            local execGraphButton = planningUIEntities and planningUIEntities.exec_graph_toggle_button
            if execGraphButton and entity_cache.valid(execGraphButton) then
                local config = component_cache.get(execGraphButton, UIConfig)
                if config then
                    local isVisible = ui_modules.CastExecutionGraphUI.isVisible()
                    local targetColor = isVisible and util.getColor("apricot") or util.getColor("gray")
                    config.color = targetColor
                end
            end
        end

        if ui_modules.AvatarJokerStrip and ui_modules.AvatarJokerStrip.isActive and is_state_active
            and (is_state_active(PLANNING_STATE) or is_state_active(ACTION_STATE) or is_state_active(SHOP_STATE)) then
            local playerTarget = nil
            if getTagEvaluationTargets then
                -- Use second return value (playerScript with avatar_state), not first (combatTable)
                local _, playerScript = getTagEvaluationTargets()
                playerTarget = playerScript
            end
            -- Only sync if we have a valid player with avatar_state
            if playerTarget and playerTarget.avatar_state then
                ui_modules.AvatarJokerStrip.syncFrom(playerTarget)
            end
            ui_modules.AvatarJokerStrip.update(dt)
            ui_modules.AvatarJokerStrip.draw()
        end

        if ui_modules.TriggerStripUI and is_state_active and is_state_active(ACTION_STATE) then
            ui_modules.TriggerStripUI.update(dt)
            ui_modules.TriggerStripUI.draw()
        end

        if ui_modules.SubcastDebugUI and is_state_active and is_state_active(ACTION_STATE) then
            ui_modules.SubcastDebugUI.update(dt)
            ui_modules.SubcastDebugUI.draw()
        end

        if ui_modules.LevelUpScreen and ui_modules.LevelUpScreen.isActive then
            ui_modules.LevelUpScreen.update(dt)
            ui_modules.LevelUpScreen.draw()
        end

        -- Update combat systems
        if StatusIndicatorSystem then
            StatusIndicatorSystem.update(dt)
        end
        if MarkSystem then
            MarkSystem.update(dt)
        end

        -- Update StatsPanel (available in planning, action, and shop phases)
        local StatsPanel = gameplay_cfg.getStatsPanel()
        if StatsPanel then
            StatsPanel.handleInput()
            StatsPanel.update(dt)
        end

        -- Process hover regions after all UIs have registered
        ui_modules.HoverRegistry.update()
    end)

    -- let's bind d-pad input to switch between cards, and A to select.
    input.bind("controller-navigation-planning-select", {
        device = "gamepad_button",
        button = GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_DOWN, -- A button
        trigger = "Pressed",                                   -- or "Threshold" if your system uses analog triggers
        context = "planning-phase"                             -- we'll use this context for planning phase only
    })
    input.bind("controller-navigation-planning-up", {
        device = "gamepad_button",
        button = GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_UP, -- D-pad up
        trigger = "Pressed",                                -- or "Threshold" if your system uses analog triggers
        context = "planning-phase"                          -- we'll use this context for planning phase only
    })
    input.bind("controller-navigation-planning-down", {
        device = "gamepad_button",
        button = GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_DOWN, -- D-pad down
        trigger = "Pressed",                                  -- or "Threshold" if your system uses analog triggers
        context = "planning-phase"                            -- we'll use this context for planning phase only
    })
    input.bind("controller-navigation-planning-left", {
        device = "gamepad_button",
        button = GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_LEFT, -- D-pad left
        trigger = "Pressed",                                  -- or "Threshold" if your system uses analog triggers
        context = "planning-phase"                            -- we'll use this context for planning phase only
    })

    input.bind("controller-navigation-planning-right", {
        device = "gamepad_button",
        button = GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_RIGHT, -- D-pad right
        trigger = "Pressed",                                   -- or "Threshold" if your system uses analog triggers
        context = "planning-phase"                             -- we'll use this context for planning phase only
    })

    input.bind("controller-navigation-planning-right-bumper", {
        device = "gamepad_button",
        button = GamepadButton.GAMEPAD_BUTTON_RIGHT_TRIGGER_1, -- D-pad right
        trigger = "Pressed",                                   -- or "Threshold" if your system uses analog triggers
        context = "planning-phase"                             -- we'll use this context for planning phase only
    })
    input.bind("controller-navigation-planning-left-bumper", {
        device = "gamepad_button",
        button = GamepadButton.GAMEPAD_BUTTON_LEFT_TRIGGER_1, -- D-pad right
        trigger = "Pressed",                                  -- or "Threshold" if your system uses analog triggers
        context = "planning-phase"                            -- we'll use this context for planning phase only
    })
    input.bind("controller-navigation-planning-left-trigger", {
        device = "gamepad_button",
        button = GamepadButton.GAMEPAD_BUTTON_LEFT_TRIGGER_2, -- D-pad right
        trigger = "Pressed",                                  -- or "Threshold" if your system uses analog triggers
        context = "planning-phase"                            -- we'll use this context for planning phase only
    })
    input.bind("controller-navigation-planning-right-trigger", {
        device = "gamepad_button",
        button = GamepadButton.GAMEPAD_BUTTON_RIGHT_TRIGGER_2, -- D-pad right
        trigger = "Pressed",                                   -- or "Threshold" if your system uses analog triggers
        context = "planning-phase"                             -- we'll use this context for planning phase only
    })

    -- let's set up the nav group so the controller can navigate the cards.
    controller_nav.create_layer("planning-input-layer")
    controller_nav.create_group("planning-phase")
    controller_nav.add_group_to_layer("planning-input-layer", "planning-phase")

    controller_nav.set_group_callbacks("planning-phase", {
        on_focus = function(e)
            playSoundEffect("effects", "card-hover", 0.9 + math.random() * 0.2)

            -- update to move cursor to entity
            input.updateCursorFocus()

            -- jiggle
            transform.InjectDynamicMotionDefault(e)

            controller_focused_entity = e

            -- get card script, set selected
            local cardScript = getScriptTableFromEntityID(e)
            if cardScript then
                cardScript.selected = true
                local go = component_cache.get(e, GameObject)
                if go then go.state.isBeingFocused = true end
            end
        end,
        on_unfocus = function(e)
            -- unselect card
            local cardScript = getScriptTableFromEntityID(e)
            if cardScript then
                cardScript.selected = false
                local go = component_cache.get(e, GameObject)
                if go then go.state.isBeingFocused = false end
            end
        end,
        on_select = function(e)
            playSoundEffect("effects", "card_click", 0.9 + math.random() * 0.2)

            transform.InjectDynamicMotionDefault(e)

            local script = getScriptTableFromEntityID(e)
            if not script then return end

            -- first check if the card belongs to one of the boards in the current board set.
            if not board_sets or #board_sets == 0 then return end

            if not current_board_set_index then return end
            local currentSet = board_sets[current_board_set_index]
            if not currentSet then return end

            local belongsToCurrentSet = false
            -- check trigger board
            if script.currentBoardEntity == currentSet.trigger_board_id then
                belongsToCurrentSet = true
            end
            -- check action board
            if script.currentBoardEntity == currentSet.action_board_id then
                belongsToCurrentSet = true
            end


            -- is it a trigger card?

            -- NOTE: Legacy inventory_board_id references removed (Phase 5)
            -- Card toggle between wand boards and inventory now handled by WandLoadoutUI
            -- This controller nav code only handles wand board card swapping now

            if script and script.type == "trigger" then
                -- add to current trigger board, if not already on it
                if board_sets and #board_sets > 0 then
                    local currentSet = board_sets[current_board_set_index]

                    if currentSet and currentSet.trigger_board_id then
                        -- if already on trigger board, just deselect (legacy inventory removed)
                        if belongsToCurrentSet and script.currentBoardEntity == currentSet.trigger_board_id then
                            playSoundEffect("effects", "card_pick_up", 0.9 + math.random() * 0.2)
                            script.selected = false
                            return
                        end

                        -- otherwise add to trigger board
                        removeCardFromBoard(e, script.currentBoardEntity) -- remove from any board it's currently on
                        addCardToBoard(e, currentSet.trigger_board_id)
                        playSoundEffect("effects", "card_put_down_3", 0.9 + math.random() * 0.2)
                    end
                end
            else
                -- add to current action board
                if board_sets and #board_sets > 0 then
                    local currentSet = board_sets[current_board_set_index]
                    if currentSet and currentSet.action_board_id then
                        -- if already on action board, just deselect (legacy inventory removed)
                        if belongsToCurrentSet and script.currentBoardEntity == currentSet.action_board_id then
                            playSoundEffect("effects", "card_pick_up", 0.9 + math.random() * 0.2)
                            script.selected = false
                            return
                        end

                        -- otherwise add to action board up top
                        removeCardFromBoard(e, script.currentBoardEntity) -- remove from any board it's currently on
                        addCardToBoard(e, currentSet.action_board_id)
                        playSoundEffect("effects", "card_put_down_3", 0.9 + math.random() * 0.2)
                    end
                end
            end
        end,
    })
    controller_nav.set_group_mode("planning-phase", "spatial")
    controller_nav.set_wrap("planning-phase", true)
    controller_nav.ud:set_active_layer("planning-input-layer")

    -- let's set input context to planning phase when in planning state


    -- make an input timer that runs onlyi in planning phase to handle controller navigation
    timer.run(
        function()
            -- only in planning state
            if not entity_cache.state_active(PLANNING_STATE) then return end

            local leftTriggerDown = input.action_down("controller-navigation-planning-left-trigger")
            local rightTriggerDown = input.action_down("controller-navigation-planning-right-trigger")

            if input.action_down("controller-navigation-planning-up") then
                log_debug("Planning phase nav: up")
                controller_nav.navigate("planning-phase", "U")
            elseif input.action_down("controller-navigation-planning-down") then
                log_debug("Planning phase nav: down")
                controller_nav.navigate("planning-phase", "D")
            elseif input.action_down("controller-navigation-planning-left") then
                if (leftTriggerDown) then
                    log_debug("Planning phase nav: trigger L is down, swapping left")
                    -- get the board of the current focused entity
                    local selectedCardScript = getScriptTableFromEntityID(controller_focused_entity)
                    if selectedCardScript and selectedCardScript.currentBoardEntity then
                        local boardScript = getScriptTableFromEntityID(selectedCardScript.currentBoardEntity)
                        if boardScript and boardScript.swapCardWithNeighbor then
                            boardScript:swapCardWithNeighbor(controller_focused_entity, -1)
                        end
                    end
                else
                    log_debug("Planning phase nav: left")
                    controller_nav.navigate("planning-phase", "L")
                end
            elseif input.action_down("controller-navigation-planning-right") then
                if (leftTriggerDown) then
                    log_debug("Planning phase nav: trigger L is down, swapping right")

                    -- get the board of the current focused entity
                    local selectedCardScript = getScriptTableFromEntityID(controller_focused_entity)
                    if selectedCardScript and selectedCardScript.currentBoardEntity then
                        local boardScript = getScriptTableFromEntityID(selectedCardScript.currentBoardEntity)
                        if boardScript and boardScript.swapCardWithNeighbor then
                            boardScript:swapCardWithNeighbor(controller_focused_entity, 1)
                        end
                    end
                else
                    log_debug("Planning phase nav: right")
                    controller_nav.navigate("planning-phase", "R")
                end
            elseif input.action_down("controller-navigation-planning-select") then
                log_debug("Planning phase nav: select")
                controller_nav.select_current("planning-phase")
            elseif input.action_down("controller-navigation-planning-right-bumper") then
                log_debug("Planning phase nav: next board set")
                -- next board set
                cycleBoardSets(1)
            elseif input.action_down("controller-navigation-planning-left-bumper") then
                log_debug("Planning phase nav: previous board set")
                -- previous board set
                cycleBoardSets(-1)
            end
        end
    )



    -- set default card size based on screen size
    gameplay_cfg.cardW = globals.screenWidth() * 0.150
    gameplay_cfg.cardH = gameplay_cfg.cardW * (64 / 48) -- default card aspect ratio is 48:64

    -- make entire roster of cards
    local catalog = WandEngine.card_defs

    print("[gameplay] ====== INITIAL CARD SPAWN DEBUG ======")
    print("[gameplay] catalog:", catalog and "exists" or "nil")
    local catalogCount = 0
    local cardsWithSprites = 0
    for id, def in pairs(catalog or {}) do
        catalogCount = catalogCount + 1
        if def.sprite then cardsWithSprites = cardsWithSprites + 1 end
    end
    print("[gameplay] Total cards in catalog:", catalogCount, "Cards with sprites:", cardsWithSprites)

    local cardsToChange = {}

    for cardID, cardDef in pairs(catalog) do
        -- Only spawn cards with designated sprites (for testing)
        if not cardDef.sprite then
            goto continue
        end

        local card = createNewCard(cardID, 4000, 4000, PLANNING_STATE) -- offscreen for now
        print("[gameplay] Created card:", cardID, "entity:", card)

        table.insert(cardsToChange, card)

        -- add to navigation group as well.
        controller_nav.ud:add_entity("planning-phase", card)

        controller_nav.validate()          -- validate the nav system after setting up bindings and layers.
        controller_nav.debug_print_state() -- print state for debugging.
        controller_nav.focus_entity(card)  -- focus the newly created card.

        ::continue::
    end

    -- Also spawn trigger cards to inventory
    local triggerCatalog = WandEngine.trigger_card_defs
    if triggerCatalog then
        print("[gameplay] Spawning trigger cards from trigger_card_defs...")
        for cardID, cardDef in pairs(triggerCatalog) do
            -- Only spawn cards with sprites
            if not cardDef.sprite then
                goto continue_trigger
            end

            local card = createNewTriggerSlotCard(cardID, 4000, 4000, PLANNING_STATE)
            print("[gameplay] Created trigger card:", cardID, "entity:", card)

            -- Mark as trigger type for proper inventory categorization
            local script = getScriptTableFromEntityID(card)
            if script then
                script.type = "trigger"
                script.category = "trigger"
            end

            table.insert(cardsToChange, card)

            controller_nav.ud:add_entity("planning-phase", card)
            controller_nav.validate()
            controller_nav.focus_entity(card)

            ::continue_trigger::
        end
    end


    -- deal the cards out with dely & sound.
    for _, card in ipairs(cardsToChange) do
        if ensure_entity(card) then
            -- set the location of each card to an offscreen pos
            local t = component_cache.get(card, Transform)
            if t then
                t.actualX = -500
                t.actualY = -500
                t.visualX = t.actualX
                t.visualY = t.actualY
            end
        end
    end

    print("[gameplay] Cards to deal:", #cardsToChange)
    local cardDelay = 4.0 -- start X seconds after game init
    for _, card in ipairs(cardsToChange) do
        if ensure_entity(card) then
            timer.after(cardDelay, function()
                print("[gameplay] Card deal timer fired")
                playSoundEffect("effects", "card_deal", 0.7 + math.random() * 0.3)

                if gameplay_cfg.isGridInventoryEnabled() then
                    local PlayerInventory = require("ui.player_inventory")
                    local category = getInventoryCategoryForCard(card)
                    local success = PlayerInventory.addCard(card, category)
                    if not success then
                        log_warn("[gameplay] Failed to add card to PlayerInventory")
                    end
                else
                    log_debug("[gameplay] Legacy mode: card spawned (no auto-add to inventory)")
                end
                -- give physics
                -- local info = { shape = "rectangle", tag = "card", sensor = false, density = 1.0, inflate_px = 15 } -- inflate so cards will not stick to each other when dealt.
                -- physics.create_physics_for_transform(registry,
                --     physics_manager_instance, -- global instance
                --     card, -- entity id
                --     "world", -- physics world identifier
                --     info
                -- )

                -- collision mask so cards collide with each other
                -- physics.enable_collision_between_many(PhysicsManager.get_world("world"), "card", {"card"})
                -- physics.update_collision_masks_for(PhysicsManager.get_world("world"), "card", {"card"})


                -- physics.use_transform_fixed_rotation(registry, card)
            end)
            cardDelay = cardDelay + 0.1
        end
    end

    -- for _, card in ipairs(cardsToChange) do
    --     if card and card ~= entt_null and entity_cache.valid(card) then
    --         -- remove physics after a few seconds
    --         timer.after(7.0, function()
    --             if card and card ~= entt_null and entity_cache.valid(card) then
    --                 -- physics.clear_all_shapes(PhysicsManager.get_world("world"), card)


    --                 -- make transform autoritative
    --                 physics.set_sync_mode(registry, card, physics.PhysicsSyncMode.AuthoritativeTransform)

    --                 -- get card transform, set rotation to 0
    --                 local t = component_cache.get(card, Transform)
    --                 if t then
    --                     t.actualR = 0
    --                 end

    --                 -- remove phyics entirely.
    --                 physics.remove_physics(PhysicsManager.get_world("world"), card, true)
    --             end
    --         end)
    --     end
    -- end


    local screenW = globals.screenWidth()
    local screenH = globals.screenHeight()

    -- Leave space for the synergy panel on the right during planning.
    local synergyPanelReserve = 300
    if ui_modules.TagSynergyPanel and ui_modules.TagSynergyPanel.layout then
        local layout = ui_modules.TagSynergyPanel.layout
        synergyPanelReserve = math.max(synergyPanelReserve, (layout.panelWidth or 0) + (layout.marginX or 0))
    end

    boardHeight = screenH / 2.8
    local planningRegionWidth = math.max(0, screenW)
    boardPadding = planningRegionWidth * 0.1 / 3
    local actionBoardWidth = planningRegionWidth * 0.7
    local triggerBoardWidth = planningRegionWidth * 0.2

    local boardSetTotalWidth = triggerBoardWidth + actionBoardWidth + boardPadding
    local runningYValue = boardPadding
    local leftAlignValueTriggerBoardX = math.max(boardPadding, (planningRegionWidth - boardSetTotalWidth) * 0.5)
    local leftAlignValueActionBoardX = leftAlignValueTriggerBoardX + triggerBoardWidth + boardPadding
    local leftAlignValueRemoveBoardX = leftAlignValueActionBoardX + actionBoardWidth + boardPadding

    local resourceBarHeight = 52
    wandResourceBar.init(leftAlignValueActionBoardX, runningYValue)
    runningYValue = runningYValue + resourceBarHeight + 4

    -- board draw function, for all baords
    -- Changed from timer.run() to timer.run_every_render_frame() to fix flickering
    timer.run_every_render_frame(function()
        -- tracy.zoneBeginN("Planning Phase Board Draw") -- just some default depth to avoid bugs

        -- log_debug("Drawing board borders")





        for key, boardScript in pairs(boards) do
            local self = boardScript
            local eid = self:handle()
            if not (eid and entity_cache.valid(eid) and entity_cache.active(eid)) then
                goto continue
            end

            -- local draw = true
            -- if type(self.gameStates) == "table" and next(self.gameStates) ~= nil then
            --     draw = false
            --     for _, state in pairs(self.gameStates) do
            --         if is_state_active(state) then
            --             draw = true
            --             break
            --         end
            --     end
            -- else
            --     -- draw only in planning state by default
            --     if not is_state_active(PLANNING_STATE) then
            --         draw = false
            --     end
            -- end

            -- if draw then

            local area = component_cache.get(eid, Transform)



            if self.noDashedBorder then
                local baseColor = self.borderColor or util.getColor("yellow")
                local fillColor = Col(baseColor.r, baseColor.g, baseColor.b, 100)
                local borderThickness = 3
                command_buffer.queueDrawSteppedRoundedRect(layers.sprites, function(c)
                    c.x           = area.actualX + area.actualW * 0.5
                    c.y           = area.actualY + area.actualH * 0.5
                    c.w           = math.max(0, area.actualW)
                    c.h           = math.max(0, area.actualH)
                    c.fillColor   = fillColor
                    c.borderColor = baseColor
                    c.borderWidth = borderThickness
                    c.numSteps    = 4
                end, z_orders.board, layer.DrawCommandSpace.World)
                goto continue
            end
            local dashedRadius = math.max(math.max(area.actualW, area.actualH) / 60, 12)
            local baseColor = self.borderColor or util.getColor("yellow")
            local fillColor = Col(baseColor.r, baseColor.g, baseColor.b, 80)
            
            command_buffer.queueDrawSteppedRoundedRect(layers.sprites, function(c)
                c.x           = area.actualX + area.actualW * 0.5
                c.y           = area.actualY + area.actualH * 0.5
                c.w           = math.max(0, area.actualW)
                c.h           = math.max(0, area.actualH)
                c.fillColor   = fillColor
                c.borderColor = Col(0, 0, 0, 0)
                c.borderWidth = 0
                c.numSteps    = 4
            end, z_orders.board - 1, layer.DrawCommandSpace.World)
            
            command_buffer.queueDrawDashedRoundedRect(layers.sprites, function(c)
                c.rec       = Rectangle.new(
                    area.actualX,
                    area.actualY,
                    math.max(0, area.actualW),
                    math.max(0, area.actualH)
                )
                c.radius    = dashedRadius
                c.dashLen   = 12
                c.gapLen    = 8
                c.phase     = shapeAnimationPhase
                c.arcSteps  = 14
                c.thickness = 5
                c.color     = baseColor
            end, z_orders.board, layer.DrawCommandSpace.World)
            -- end

            ::continue::
        end
        -- tracy.zoneEnd()
    end)

    -- -------------------------------------------------------------------------- --
    --                   create a set of trigger + action board                   --
    -- -------------------------------------------------------------------------- -

    local set = createTriggerActionBoardSet(
        leftAlignValueTriggerBoardX,
        runningYValue,
        triggerBoardWidth,
        actionBoardWidth,
        boardHeight,
        boardPadding
    )

    -- let's make a total of 3 sets and disable the last two for now.
    local set2 = createTriggerActionBoardSet(
        leftAlignValueTriggerBoardX,
        runningYValue,
        triggerBoardWidth,
        actionBoardWidth,
        boardHeight,
        boardPadding
    )

    local set3 = createTriggerActionBoardSet(
        leftAlignValueTriggerBoardX,
        runningYValue,
        triggerBoardWidth,
        actionBoardWidth,
        boardHeight,
        boardPadding
    )

    -- Hide ALL board sets (boards and cards) - only wand selector buttons remain visible
    toggleBoardSetVisibility(set, false)
    toggleBoardSetVisibility(set2, false)
    toggleBoardSetVisibility(set3, false)

    runningYValue = runningYValue + boardHeight + boardPadding

    -- Wand resource bar is now initialized ABOVE the action board (see line ~5091)

    -- let's create a card board


    -- make a trigger card and add it to the trigger board.
    -- local triggerCard = createNewCard("TEST_TRIGGER_EVERY_N_SECONDS", 4000, 4000, PLANNING_STATE) -- offscreen for now

    -- ======================== TEST CARDS FOR DEVELOPMENT ========================
    -- Add lightning card to action board & "every N seconds" trigger to trigger board
    local testTriggerCard = createNewTriggerSlotCard("TEST_TRIGGER_EVERY_N_SECONDS", 4000, 4000, PLANNING_STATE)
    addCardToBoard(testTriggerCard, set.trigger_board_id)

    local testActionCard = createNewCard("ACTION_CHAIN_LIGHTNING", 4000, 4000, PLANNING_STATE)
    addCardToBoard(testActionCard, set.action_board_id)
    -- =============================================================================

    -- -------------------------------------------------------------------------- --
    --       GRID INVENTORY SYSTEM (Phase 5 Cleanup - Legacy Code Removed)       --
    -- -------------------------------------------------------------------------- --
    -- Grid-based inventory initializes when planning phase starts
    -- Modules self-initialize before first open for correct sizing and input
    -- Legacy inventory_board_id and trigger_inventory_board_id have been removed
    log_debug("[gameplay] Using new grid inventory system (legacy boards removed)")
    log_debug("[gameplay] PlayerInventory initializes at planning phase start")
    log_debug("[gameplay] WandLoadoutUI will initialize on E key press")

    -- for each board set, we get a corresponding index wand def to save, or if the index is out of range, we loop around.
    for index, boardSet in ipairs(board_sets) do
        local indexToUse = index
        if indexToUse > #WandEngine.wand_defs then
            indexToUse = ((indexToUse - 1) % #WandEngine.wand_defs) + 1
        end

        boardSet.wandDef = WandEngine.wand_defs[indexToUse]

        -- inject the def with the trigger board's entity id

        boardSet.wandDef = util.deep_copy(WandEngine.wand_defs[indexToUse]) -- make a copy to avoid mutating original
        boardSet.wandDef.trigger_board_entity = boardSet.trigger_board_id
        boardSet.wandDef.action_board_entity = boardSet.action_board_id
    end

    -- Initialize wand grid adapter with wand definitions for combat sync
    -- This must be done after board_sets have their wandDef assigned
    local wandDefsForAdapter = {}
    for _, boardSet in ipairs(board_sets) do
        if boardSet.wandDef then
            table.insert(wandDefsForAdapter, boardSet.wandDef)
        end
    end
    if #wandDefsForAdapter > 0 then
        wandAdapter.init(wandDefsForAdapter)
        log_debug("[gameplay] wandAdapter initialized with " .. #wandDefsForAdapter .. " wand definitions")
    end

    if gameplay_cfg.isGridInventoryEnabled() then
        local GridInventorySave = require("core.grid_inventory_save")
        local PlayerInventory = require("ui.player_inventory")
        local WandLoadoutUI = require("ui.wand_loadout_ui")

        WandLoadoutUI.setWandCount(#wandDefsForAdapter)

        GridInventorySave.setPlayerInventoryRef(PlayerInventory)
        GridInventorySave.setWandLoadoutRef(WandLoadoutUI)
        GridInventorySave.setWandAdapterRef(wandAdapter)

        -- Initialize new WandPanel (Phase 8 integration)
        log_debug("[gameplay] Attempting to load WandPanel module...")
        local WandPanel_ok, WandPanel_or_err = pcall(require, "ui.wand_panel")
        if WandPanel_ok and WandPanel_or_err then
            log_debug("[gameplay] WandPanel module loaded successfully")
            local WandPanel = WandPanel_or_err
            WandPanel.setWandDefs(wandDefsForAdapter)
            -- Initialize immediately to set up E key handler
            local init_success = WandPanel.initialize()
            if init_success then
                log_debug("[gameplay] WandPanel initialized and ready (E key enabled)")
            else
                log_debug("[gameplay] WandPanel setWandDefs succeeded but initialize deferred")
            end
        else
            log_warn("[gameplay] WandPanel module failed to load: " .. tostring(WandPanel_or_err))
        end

        -- NOTE: Skills Panel is initialized in initCombatSystem() after hero is created
        -- This ensures playerScript.combatTable (hero) has skill_points set

        GridInventorySave.setCardRecreator(function(cardId, category)
            if not cardId then return nil end

            local cardEntity
            if category == "trigger" or WandEngine.trigger_card_defs[cardId] then
                cardEntity = createNewTriggerSlotCard(cardId, -9999, -9999, PLANNING_STATE)
            else
                cardEntity = createNewCard(cardId, -9999, -9999, PLANNING_STATE)
            end

            if cardEntity and registry:valid(cardEntity) then
                if ObjectAttachedToUITag and not registry:has(cardEntity, ObjectAttachedToUITag) then
                    registry:emplace(cardEntity, ObjectAttachedToUITag)
                end
                if transform and transform.set_space then
                    transform.set_space(cardEntity, "screen")
                end
                log_debug("[GridInventorySave] Recreated card: " .. cardId)
            end

            return cardEntity
        end)

        log_debug("[gameplay] Grid inventory save/load integration configured")
    else
        log_debug("[gameplay] Grid inventory disabled - using legacy board system")
    end

    -- Card tooltips are built lazily on hover to avoid spawning hundreds of UI boxes up front.

    activate_state(WAND_TOOLTIP_STATE) -- keep activated at  all times.
    -- activate_state(CARD_TOOLTIP_STATE) -- keep activated at all times.

    -- make tooltip for each wand in WandEngine.wand_defs
    for id, wandDef in pairs(WandEngine.wand_defs) do
        local tooltip = cacheStore(wand_tooltip_cache, wandDef.id, makeWandTooltip(wandDef))

        -- z_orders
        layer_order_system.assignZIndexToEntity(
            tooltip,
            z_orders.ui_tooltips
        )

        -- disable by default
        clear_state_tags(tooltip)
    end


    setUpLogicTimers()

    -- Timer for preview updates (StatsPanel now updated in main loop)
    timer.every(0.016, function()
        updateAltPreview()
        updateRightClickTransfer()
    end)
end

local ctx = nil

function make_actor(name, defs, attach)
    -- Creates a fresh Stats instance, applies attribute derivations via `attach`,
    -- and snapshots initial HP/Energy as both current and max. The actor also
    -- carries helpers for pet creation (so PetsAndSets.spawn_pet can reuse them).
    local s = CombatSystem.Core.Stats.new(defs)
    attach(s)
    s:recompute()
    local hp = s:get('health')
    local en = s:get('energy')

    return {
        name             = name,
        stats            = s,
        hp               = hp,
        max_health       = hp,
        energy           = en,
        max_energy       = en,
        gear_conversions = {},
        tags             = {},
        timers           = {},

        -- add these so spawn_pet can reuse them
        _defs            = defs,
        _attach          = attach,
        _make_actor      = make_actor,
    }
end

local function formatDamageNumber(amount)
    if not amount then return "0" end
    if amount >= 10 then
        return string.format("%.0f", amount)
    end
    return string.format("%.1f", amount)
end

local function pickDamageColor(amount, isCrit)
    if isCrit then
        return { r = 255, g = 215, b = 0, a = 255 }
    end
    if amount and amount > 0 then
        return { r = 255, g = 70, b = 70, a = 255 }
    end
    return { r = 255, g = 255, b = 255, a = 255 }
end

local function spawnDamageNumber(targetEntity, amount, isCrit)
    if not targetEntity or not entity_cache.valid(targetEntity) then return end
    if not amount then return end

    local t = component_cache.get(targetEntity, Transform)
    if not t then return end

    local spawnX = t.actualX + t.actualW * 0.5 + (math.random() - 0.5) * DAMAGE_NUMBER_HORIZONTAL_JITTER
    local spawnY = t.actualY - 10

    damageNumbers[#damageNumbers + 1] = {
        x        = spawnX,
        y        = spawnY,
        vx       = (math.random() - 0.5) * (DAMAGE_NUMBER_HORIZONTAL_JITTER * 0.8),
        vy       = -(DAMAGE_NUMBER_VERTICAL_SPEED + math.random() * 20),
        life     = DAMAGE_NUMBER_LIFETIME,
        age      = 0,
        text     = formatDamageNumber(amount),
        crit     = isCrit or false,
        fontSize = DAMAGE_NUMBER_FONT_SIZE,
        color    = pickDamageColor(amount, isCrit),
    }
end

-- Reset hero combat actor to baseline stats (level 1, no accumulated bonuses)
local function resetHeroToBaseline(hero)
    if not hero then return end

    -- Reset level/xp/points to starting values
    local oldLevel = hero.level or 1
    hero.level = 1
    hero.xp = 0
    hero.attr_points = 0
    hero.skill_points = 10  -- Reset to 10 skill points for testing
    hero.masteries = 0

    -- Calculate and remove level-up stat bonuses (10 OA/DA per level gained)
    local levelsGained = oldLevel - 1
    if levelsGained > 0 and hero.stats then
        -- Remove the accumulated OA/DA from level-ups
        hero.stats:add_base('offensive_ability', -10 * levelsGained)
        hero.stats:add_base('defensive_ability', -10 * levelsGained)
        log_debug("[gameplay] Removed", levelsGained, "levels worth of OA/DA bonuses")
    end

    -- Recompute stats to get correct max health
    if hero.stats and hero.stats.recompute then
        hero.stats:recompute()
    end

    -- Reset HP to new max
    local maxHp = hero.max_health or (hero.stats and hero.stats:get("health")) or 100
    hero.hp = maxHp

    log_debug("[gameplay] Reset hero to level 1, HP:", maxHp)
end

-- Reset game to starting state for new run
local function resetGameToStart()
    -- CRITICAL: Cleanup signal handlers FIRST (before timer cleanup)
    -- This prevents memory leaks from accumulated handlers on restart
    cleanupGameplayHandlers()

    -- Cleanup external module signal handlers
    local ok, CastFeedUI = pcall(require, "ui.cast_feed_ui")
    if ok and CastFeedUI and CastFeedUI.unsubscribe then
        CastFeedUI.unsubscribe()
    end

    local ok2, PlayerInventory = pcall(require, "ui.player_inventory")
    if ok2 and PlayerInventory and PlayerInventory.cleanupSignalHandlers then
        PlayerInventory.cleanupSignalHandlers()
    end

    -- WaveDirector cleanup is called separately via its own cleanup() function
    -- which includes handler cleanup

    -- Reset death guard so player can die again in new run
    gameplay_cfg.isPlayerDying = false
    log_debug("[gameplay] Resetting game to start...")

    -- 1. Kill all timers (including wave timers)
    timer.kill_group("combat")
    timer.kill_group("death_animation")
    timer.kill_group("combat_state_timer")
    -- Kill wave telegraph/spawn timers
    for i = 1, 50 do
        timer.cancel("wave_telegraph_" .. i)
        timer.cancel("wave_spawn_" .. i)
        timer.cancel("telegraph_anim_" .. tostring(i))
    end
    timer.cancel("wave_spawn_complete")
    timer.cancel("wave_advance")
    timer.cancel("elite_spawn")
    timer.cancel("stage_transition")
    timer.cancel("reset_card_fly_in")

    -- 2. Reset globals to starting values
    globals.currency = 30
    if globals.shopState then
        globals.shopState.playerLevel = 1
        globals.shopState.avatarPurchases = {}
        globals.shopState.cards = {}
    else
        globals.shopState = { playerLevel = 1, avatarPurchases = {}, cards = {} }
    end
    globals.ownedRelics = {
        { id = "proto_umbrella" }
    }

    -- 3. Clear jokers and reset to defaults
    JokerSystem.clear_jokers()
    JokerSystem.add_joker("lightning_rod")  -- default starting joker

    -- 4. Clear all cards from boards
    if board_sets then
        for _, boardSet in ipairs(board_sets) do
            -- Destroy card entities
            if boardSet.cardIDs then
                for _, cardEID in ipairs(boardSet.cardIDs) do
                    if cardEID and entity_cache.valid(cardEID) then
                        registry:destroy(cardEID)
                    end
                end
                boardSet.cardIDs = {}
            end
            -- Clear card pool references
            if boardSet.cards then
                boardSet.cards = {}
            end
        end
        log_debug("[gameplay] Cleared cards from all boards")
    else
        log_debug("[gameplay] No board_sets found, skipping board clear")
    end

    -- 4b. Clear inventory boards (separate from board_sets)
    local function clearInventoryBoard(boardId, boardName)
        if boardId and entity_cache.valid(boardId) then
            local board = boards[boardId]
            if board and board.cards then
                for _, cardEID in ipairs(board.cards) do
                    if cardEID and entity_cache.valid(cardEID) then
                        registry:destroy(cardEID)
                    end
                end
                board.cards = {}
                log_debug("[gameplay] Cleared " .. boardName)
            end
        end
    end
    if gameplay_cfg.isGridInventoryEnabled() then
        local PlayerInventory = require("ui.player_inventory")
        if PlayerInventory.clearAll then
            PlayerInventory.clearAll()
            log_debug("[gameplay] Cleared PlayerInventory grid")
        end
    end

    -- 5. Reset player to baseline (level 1, full HP, no accumulated stats)
    if survivorEntity and entity_cache.valid(survivorEntity) then
        local playerScript = getScriptTableFromEntityID(survivorEntity)
        if playerScript then
            -- Reset hero combat stats to baseline
            if playerScript.combatTable then
                resetHeroToBaseline(playerScript.combatTable)
            end

            -- Clear avatar state (unequip any equipped avatar)
            if playerScript.avatar_state then
                playerScript.avatar_state = { unlocked = {}, equipped = nil }
            end
        end

        -- Remove any shaders (dissolve, etc.)
        local ok, ShaderBuilder = pcall(require, "core.shader_builder")
        if ok and ShaderBuilder then
            ShaderBuilder.for_entity(survivorEntity):clear():apply()
        end

        -- Reset position to center
        local survivorTransform = component_cache.get(survivorEntity, Transform)
        if survivorTransform then
            survivorTransform.actualX = globals.screenWidth() / 2
            survivorTransform.actualY = globals.screenHeight() / 2
            survivorTransform.visualX = survivorTransform.actualX
            survivorTransform.visualY = survivorTransform.actualY
        end
    end

    -- 5b. Re-add starting cards to boards with fly-in animation
    log_debug("[gameplay] board_sets count:", board_sets and #board_sets or 0)
    if board_sets and #board_sets > 0 then
        local set = board_sets[1]
        log_debug("[gameplay] Using board set 1, trigger_board:", set.trigger_board_id, "action_board:", set.action_board_id)
        local cardsToAnimate = {}

        -- Create trigger card
        local testTriggerCard = createNewTriggerSlotCard("TEST_TRIGGER_EVERY_N_SECONDS", 4000, 4000, PLANNING_STATE)
        log_debug("[gameplay] Created trigger card:", testTriggerCard)
        table.insert(cardsToAnimate, { card = testTriggerCard, board = set.trigger_board_id })

        -- Create action card
        local testActionCard = createNewCard("ACTION_CHAIN_LIGHTNING", 4000, 4000, PLANNING_STATE)
        log_debug("[gameplay] Created action card:", testActionCard)
        table.insert(cardsToAnimate, { card = testActionCard, board = set.action_board_id })

        -- Animate cards flying in with staggered delay
        local cardDelay = 0.3
        for _, entry in ipairs(cardsToAnimate) do
            local card = entry.card
            local boardId = entry.board

            -- Set initial position offscreen
            local t = component_cache.get(card, Transform)
            if t then
                t.actualX = -500
                t.actualY = -500
                t.visualX = t.actualX
                t.visualY = t.actualY
            end

            -- Animate in after delay
            timer.after_opts({
                delay = cardDelay,
                action = function()
                    log_debug("[gameplay] Card fly-in timer fired for card:", card)
                    if not entity_cache.valid(card) then
                        log_debug("[gameplay] Card no longer valid:", card)
                        return
                    end
                    local transform = component_cache.get(card, Transform)
                    local boardTransform = component_cache.get(boardId, Transform)
                    log_debug("[gameplay] Card transform:", transform and "valid" or "nil", "Board transform:", boardTransform and "valid" or "nil")
                    if transform and boardTransform then
                        -- Set target position
                        transform.actualX = boardTransform.actualX + boardTransform.actualW / 2
                        transform.actualY = boardTransform.actualY
                        -- Start visual position offscreen right for fly-in effect
                        transform.visualX = globals.screenWidth() * 1.2
                        transform.visualY = transform.actualY - 100
                        log_debug("[gameplay] Card positioned at actual:", transform.actualX, transform.actualY, "visual:", transform.visualX, transform.visualY)

                        -- Play card deal sound
                        playSoundEffect("effects", "card_deal", 0.7 + math.random() * 0.3)
                    end
                    addCardToBoard(card, boardId)
                    log_debug("[gameplay] Card added to board")
                end,
                tag = "reset_card_fly_in"
            })
            cardDelay = cardDelay + 0.15
        end

        log_debug("[gameplay] Re-added starting cards with fly-in animation")
    end

    if gameplay_cfg.isGridInventoryEnabled() then
        local PlayerInventory = require("ui.player_inventory")
        local catalog = WandEngine.card_defs
        local inventoryCardsToAnimate = {}

        for cardID, cardDef in pairs(catalog) do
            if cardDef.sprite then
                local card = createNewCard(cardID, 4000, 4000, PLANNING_STATE)
                table.insert(inventoryCardsToAnimate, card)

                if controller_nav and controller_nav.ud and controller_nav.ud.add_entity then
                    controller_nav.ud:add_entity("planning-phase", card)
                end
            end
        end

        local inventoryCardDelay = 0.5
        for _, card in ipairs(inventoryCardsToAnimate) do
            if entity_cache.valid(card) then
                timer.after(inventoryCardDelay, function()
                    if not entity_cache.valid(card) then return end
                    playSoundEffect("effects", "card_deal", 0.7 + math.random() * 0.3)
                    local category = getInventoryCategoryForCard(card)
                    PlayerInventory.addCard(card, category)
                end)
                inventoryCardDelay = inventoryCardDelay + 0.1
            end
        end
        log_debug("[gameplay] Re-spawned " .. #inventoryCardsToAnimate .. " inventory cards to grid")
    end

    -- 6. Cleanup wand executor (destroys projectiles and wand state)
    WandExecutor.cleanup()

    -- 6.5. Reset wave director state
    local ok, WaveDirector = pcall(require, "combat.wave_director")
    if ok and WaveDirector and WaveDirector.cleanup then
        WaveDirector.cleanup()
    end

    -- 6.6. Cleanup wave visuals (telegraphs)
    local ok2, WaveVisuals = pcall(require, "combat.wave_visuals")
    if ok2 and WaveVisuals and WaveVisuals.cleanup then
        WaveVisuals.cleanup()
    end

    -- 7. Reset UI systems
    if ui_modules.CastBlockFlashUI and ui_modules.CastBlockFlashUI.clear then
        ui_modules.CastBlockFlashUI.clear()
    end
    if ui_modules.SubcastDebugUI and ui_modules.SubcastDebugUI.clear then
        ui_modules.SubcastDebugUI.clear()
    end

    -- 8. Clear combat context (enemies and accumulated state)
    if combat_context then
        -- Destroy enemy entities
        if combat_context.side2 then
            for _, actor in ipairs(combat_context.side2) do
                local enemyEntity = combatActorToEntity and combatActorToEntity[actor]
                if enemyEntity and entity_cache.valid(enemyEntity) then
                    registry:destroy(enemyEntity)
                end
            end
            combat_context.side2 = {}
        end

        -- Reset combat time (affects DoTs, cooldowns)
        if combat_context.time and combat_context.time.reset then
            combat_context.time:reset()
        elseif combat_context.time then
            combat_context.time.elapsed = 0
        end
    end

    -- 9. Clear actor-entity mapping (keeps only player)
    -- DISABLED FOR DEBUG: Bisecting crash
    -- if combatActorToEntity then
    --     local playerActor = nil
    --     if survivorEntity and entity_cache.valid(survivorEntity) then
    --         local playerScript = getScriptTableFromEntityID(survivorEntity)
    --         if playerScript then
    --             playerActor = playerScript.combatTable
    --         end
    --     end
    --     for k in pairs(combatActorToEntity) do
    --         if k ~= playerActor then
    --             combatActorToEntity[k] = nil
    --         end
    --     end
    -- end

    -- 10. Clear damage numbers and enemy health UI
    -- DISABLED FOR DEBUG: Bisecting crash
    -- if damageNumbers then
    --     for k in pairs(damageNumbers) do damageNumbers[k] = nil end
    -- end
    -- if enemyHealthUiState then
    --     for k in pairs(enemyHealthUiState) do enemyHealthUiState[k] = nil end
    -- end

    -- 11. Reset dash state
    playerIsDashing = false
    playerDashCooldownRemaining = 0
    playerDashTimeRemaining = 0
    dashBufferTimer = 0
    bufferedDashDir = nil
    playerStaminaTickerTimer = 0

    -- 12. Start fresh planning phase
    startPlanningPhase()

    log_debug("[gameplay] Game reset complete - now in planning phase")
end

-- Player death animation with dissolve shader and blood particles
local function playPlayerDeathAnimation(playerEntity, onComplete)
    if gameplay_cfg.isPlayerDying then return end
    gameplay_cfg.isPlayerDying = true

    local Q = require("core.Q")
    local ShaderBuilder = require("core.shader_builder")
    local ok, Particles = pcall(require, "core.particles")

    -- Get player position for blood particles
    local cx, cy = Q.center(playerEntity)

    -- Blood particle burst (only if Particles loaded successfully)
    if ok and Particles then
        local blood = Particles.define()
            :shape("circle")
            :size(3, 8)
            :color(255, 0, 0)          -- red
            :velocity(50, 150)
            :gravity(300)
            :lifespan(0.6, 1.2)
            :fade()

        blood:burst(25):inCircle(cx, cy, 20):outward()
    end

    -- Apply dissolve shader to player
    ShaderBuilder.for_entity(playerEntity)
        :add("dissolve_with_burn_edge", { dissolve_value = 0.0 })
        :apply()

    -- Animate dissolve from 0 to 1 over 1.5 seconds
    local duration = 1.5
    local elapsed = 0

    timer.every_opts({
        delay = 0.016,
        action = function()
            elapsed = elapsed + 0.016
            local progress = math.min(elapsed / duration, 1.0)

            -- Update dissolve uniform
            globalShaderUniforms:set("dissolve_with_burn_edge", "dissolve_value", progress)

            if progress >= 1.0 then
                if onComplete then onComplete() end
                return false  -- stop timer
            end
            return true  -- continue
        end,
        tag = "player_death_dissolve",
        group = "death_animation"
    })
end

-- ============================================================================
-- PLAYER DEATH FLOW SIGNALS
-- ============================================================================

-- Initialize death flow handlers (called once on game init)
local function initDeathFlowHandlers()
    if gameplay_cfg.deathFlowHandlersRegistered then return end
    gameplay_cfg.deathFlowHandlersRegistered = true

    local handlers = initGameplayHandlers()

    -- Handle player death - trigger animation
    handlers:on("player_died", function(playerEntity)
        log_debug("[gameplay] Player died - starting death animation")
        playPlayerDeathAnimation(playerEntity, function()
            log_debug("[gameplay] Death animation complete")
            -- Animation complete callback - state machine handles transition to GAME_OVER
        end)
    end)

    -- Handle game over - show death screen
    handlers:on("show_death_screen", function()
        log_debug("[gameplay] Showing death screen")
        gameplay_cfg.getDeathScreen().show()
    end)

    -- Handle restart request - fade and reset
    handlers:on("restart_game", function()
        log_debug("[gameplay] Restart requested - fading to black")
        local timer = require("core.timer")

        -- Simple fade to black (if fade system exists)
        if fadeToBlack then
            fadeToBlack(0.5, function()
                resetGameToStart()
                fadeFromBlack(0.5)
            end)
        else
            -- No fade system - just reset immediately
            timer.after_opts({
                delay = 0.1,
                action = function()
                    resetGameToStart()
                end,
                tag = "restart_delay"
            })
        end
    end)
end

-- Register death flow handlers on module load
initDeathFlowHandlers()

function initCombatSystem()
    -- init combat system.

    local combatBus                    = CombatSystem.Core.EventBus.new()
    local combatTime                   = CombatSystem.Core.Time.new()
    local combatStatDefs, DAMAGE_TYPES = CombatSystem.Core.StatDef.make()
    local combatBundle                 = CombatSystem.Game.Combat.new(CombatSystem.Core.RR, DAMAGE_TYPES) -- carries RR + DAMAGE_TYPES; stored on ctx.combat



    combat_context     = {
        stat_defs    = combatStatDefs, -- definitions for stats in this combat
        DAMAGE_TYPES = DAMAGE_TYPES,   -- damage types available in this combat
        _make_actor  = make_actor,     -- Factory for creating actors
        debug        = true,           -- verbose debug prints across systems
        bus          = combatBus,      -- shared event bus for this arena
        time         = combatTime,     -- shared clock for statuses/DoTs/cooldowns
        combat       = combatBundle    -- optional bundle for RR+damage types, if needed
    }

    local ctx          = combat_context

    -- add side-aware accessors to ctx
    -- Used by targeters and AI; these close over 'ctx' (safe here).
    ctx.get_enemies_of = function(a) return a.side == 1 and ctx.side2 or ctx.side1 end
    ctx.get_allies_of  = function(a) return a.side == 1 and ctx.side1 or ctx.side2 end

    -- Bridge combat bus events to signal system (prevents disconnection bugs)
    local EventBridge = require("core.event_bridge")
    EventBridge.attach(ctx)

    --TODO: probably make separate enemy creation functions for each enemy type.

    -- Hero baseline: some OA/Cunning/Spirit, crit damage, CDR, cost reduction, and atk/cast speed.
    local hero         = make_actor('Hero', combatStatDefs, CombatSystem.Game.Content.attach_attribute_derivations)
    hero.side          = 1
    hero.level_curve   = 'fast_start'
    hero.stats:add_base('physique', 16)
    hero.stats:add_base('cunning', 18)
    hero.stats:add_base('spirit', 12)
    hero.stats:add_base('weapon_min', 18)
    hero.stats:add_base('weapon_max', 25)
    hero.stats:add_base('life_steal_pct', 10)
    hero.stats:add_base('crit_damage_pct', 50) -- +50% crit damage
    hero.stats:add_base('cooldown_reduction', 20)
    hero.stats:add_base('skill_energy_cost_reduction', 15)
    hero.stats:add_base('attack_speed', 1.0)
    hero.stats:add_base('cast_speed', 1.0)
    hero.stats:recompute()

    -- Initial progression state
    hero.level = 1
    hero.xp = 0
    hero.attr_points = 0
    hero.skill_points = 10  -- Start with 10 skill points for testing
    hero.masteries = 0

    -- Ogre: tougher target with defense layers and reactive behaviors (reflect/retaliation/block).
    local ogre = make_actor('Ogre', combatStatDefs, CombatSystem.Game.Content.attach_attribute_derivations)
    ogre.side = 2
    ogre.stats:add_base('health', 400)
    ogre.stats:add_base('defensive_ability', 95)
    ogre.stats:add_base('armor', 50)
    ogre.stats:add_base('armor_absorption_bonus_pct', 20)
    ogre.stats:add_base('fire_resist_pct', 40)
    ogre.stats:add_base('dodge_chance_pct', 10)
    -- ogre.stats:add_base('deflect_chance_pct', 8) -- (deflection not currently used)
    ogre.stats:add_base('reflect_damage_pct', 5)
    ogre.stats:add_base('retaliation_fire', 8)
    ogre.stats:add_base('retaliation_fire_modifier_pct', 25)
    ogre.stats:add_base('block_chance_pct', 30)
    ogre.stats:add_base('block_amount', 60)
    ogre.stats:add_base('block_recovery_reduction_pct', 25)
    ogre.stats:add_base('damage_taken_reduction_pct', 2000) -- stress test: massive DR → negative damage (healing)
    ogre.stats:recompute()

    ctx.side1 = { hero }
    ctx.side2 = { ogre }

    -- store in player entity for easy access later
    assert(survivorEntity and entity_cache.valid(survivorEntity), "Survivor entity is not valid in combat system init!")
    local playerScript        = getScriptTableFromEntityID(survivorEntity)
    assert(playerScript, "Failed to get script table for survivor entity in combat system init!")
    playerScript.combatTable  = hero
    combatActorToEntity[hero] = survivorEntity
    hero.entity_id            = survivorEntity  -- For combat_system.lua signal emission

    -- Initialize Skills Panel (K key toggle) now that hero has skill_points
    local SkillsPanelInput_ok, SkillsPanelInput = pcall(require, "ui.skills_panel_input")
    if SkillsPanelInput_ok and SkillsPanelInput then
        log_debug("[gameplay] SkillsPanelInput module loaded successfully")
        -- Pass hero (playerScript.combatTable) which has skill_points = 10
        SkillsPanelInput.initialize(hero)
        log_debug("[gameplay] SkillsPanelInput initialized (K key enabled)")
    else
        log_warn("[gameplay] SkillsPanelInput module failed to load: " .. tostring(SkillsPanelInput))
    end

    -- DEBUG: Auto-equip avatar for testing
    if gameplay_cfg.DEBUG_AUTO_EQUIP_AVATAR then
        local avatarId = gameplay_cfg.DEBUG_AUTO_EQUIP_AVATAR
        playerScript.avatar_state = playerScript.avatar_state or { unlocked = {}, equipped = nil }
        playerScript.avatar_state.unlocked[avatarId] = true  -- Force unlock
        local ok, err = AvatarSystem.equip(playerScript, avatarId)
        log_debug("[Avatar] Auto-equipped avatar:", avatarId, "ok=", ok, "err=", err)
        log_debug("[Avatar] avatar_state.equipped =", playerScript.avatar_state.equipped)

        -- Sync avatar strip UI (delayed to ensure strip is ready)
        -- Store reference to avoid closure issues
        local capturedPlayer = playerScript
        timer.after_opts({
            delay = 0.5,
            action = function()
                if ui_modules.AvatarJokerStrip and ui_modules.AvatarJokerStrip.isActive and ui_modules.AvatarJokerStrip.syncFrom then
                    log_debug("[Avatar] Syncing avatar strip with captured player")
                    log_debug("[Avatar] capturedPlayer.avatar_state.equipped =", capturedPlayer and capturedPlayer.avatar_state and capturedPlayer.avatar_state.equipped)
                    ui_modules.AvatarJokerStrip.syncFrom(capturedPlayer)
                else
                    log_debug("[Avatar] Avatar strip not ready: isActive=", ui_modules.AvatarJokerStrip and ui_modules.AvatarJokerStrip.isActive)
                end
            end,
            tag = "debug_avatar_sync"
        })
    end

    -- attach defs/derivations to ctx for easy access later for pets
    ctx._defs                 = combatStatDefs
    ctx._attach               = CombatSystem.Game.Content.attach_attribute_derivations
    ctx._make_actor           = make_actor

    -- subscribe to events.
    ctx.bus:on('OnLevelUp', function()
        -- send player level up signal.
        signal.emit("player_level_up")
    end)
    ctx.bus:on('OnHitResolved', function(ev)
        local targetEntity = combatActorToEntity[ev.target]
        if targetEntity and enemyHealthUiState[targetEntity] then
            enemyHealthUiState[targetEntity].visibleUntil = GetTime() + ENEMY_HEALTH_BAR_LINGER
        end
        if targetEntity then
            spawnDamageNumber(targetEntity, ev.damage or 0, ev.crit)
        end

        -- NEW: Emit on_player_attack when player deals damage to enemies
        local attackerEntity = combatActorToEntity[ev.attacker]
        if attackerEntity == survivorEntity and targetEntity and targetEntity ~= survivorEntity then
            signal.emit("on_player_attack", {
                entity = survivorEntity,
                target = targetEntity,
                damage = ev.damage or 0,
                crit = ev.crit
            })
        end

        -- NEW: Check for on_low_health when player takes damage
        if targetEntity == survivorEntity then
            local playerActor = ev.target
            if playerActor and playerActor.hp and playerActor.max_health then
                local healthPct = playerActor.hp / playerActor.max_health
                if healthPct <= 0 and not gameplay_cfg.isPlayerDying then
                    gameplay_cfg.isPlayerDying = true
                    signal.emit("player_died", survivorEntity)
                    signal.emit("show_death_screen")
                elseif healthPct < 0.3 then
                    signal.emit("on_low_health", {
                        entity = survivorEntity,
                        health_pct = healthPct
                    })
                end
            end
            -- NEW: Track damage blocked for avatar system
            local blocked = ev.blocked or 0
            if blocked > 0 then
                local playerScript = getScriptTableFromEntityID(survivorEntity)
                if playerScript then
                    AvatarSystem.record_progress(playerScript, "damage_blocked", blocked)
                end
            end
        end
    end)
    ctx.bus:on('OnDeath', function(ev)
        local actor = ev.entity
        if not actor or actor.side ~= 2 then return end

        local enemyEntity = combatActorToEntity[actor]

        -- NEW: Track kills for avatar system
        local playerScript = getScriptTableFromEntityID(survivorEntity)
        if playerScript then
            AvatarSystem.record_progress(playerScript, "kills", 1)
        end
        combatActorToEntity[actor] = nil

        if enemyEntity then
            enemyHealthUiState[enemyEntity] = nil

            local dropX, dropY = nil, nil
            if entity_cache.valid(enemyEntity) then
                local t = component_cache.get(enemyEntity, Transform)
                if t then
                    dropX = t.actualX + t.actualW * 0.5
                    dropY = t.actualY + t.actualH * 0.5
                end
            end

            local deathPosition = (dropX and dropY) and { x = dropX, y = dropY } or nil
            signal.emit("enemy_killed", enemyEntity, { 
                position = deathPosition, 
                entity = enemyEntity 
            })

            timer.after(0.01, function()
                if dropX and dropY then
                    particle.spawnExplosion(dropX, dropY, 18, 0.45, {
                        colors = { util.getColor("ORANGE"), util.getColor("YELLOW"), util.getColor("WHITE") },
                        space = "world"
                    })
                    if particle.spawnDirectionalLinesCone then
                        particle.spawnDirectionalLinesCone(Vec2(dropX, dropY), 18, 0.35, {
                            direction = Vec2(0, -1),
                            spread = 320,
                            colors = { util.getColor("WHITE"), util.getColor("YELLOW") },
                            minSpeed = 180,
                            maxSpeed = 360,
                            minLength = 18,
                            maxLength = 46,
                            space = "world",
                            z = z_orders.particle_vfx
                        })
                    end
                    spawnExpPickupAt(dropX, dropY, { positionIsCenter = true })
                end

                if entity_cache.valid(enemyEntity) then
                    registry:destroy(enemyEntity)
                end
            end, "enemy_death_cleanup_" .. tostring(enemyEntity))
        end
    end)

    -- make springs for exp bar and hp bar SCALE (for undulation effect)
    expBarScaleSpringEntity, expBarScaleSpringRef = spring.make(registry, 1.0, 120.0, 14.0, {
        target = 1.0,
        smoothingFactor = 0.9,
        preventOvershoot = false,
        maxVelocity = 10.0
    })
    hpBarScaleSpringEntity, hpBarScaleSpringRef = spring.make(registry, 1.0, 120.0, 14.0, {
        target = 1.0,
        smoothingFactor = 0.9,
        preventOvershoot = false,
        maxVelocity = 10.0
    })

    -- make springs for the main XP bar value (smooth lerping)
    expBarMainSpringEntity, expBarMainSpringRef = spring.make(registry, 0.0, 60.0, 8.0, {
        target = 0.0,
        smoothingFactor = 0.85,
        preventOvershoot = false,
        maxVelocity = 8.0
    })

    -- make springs for delayed indicator bars (white bars that catch up)
    expBarDelayedSpringEntity, expBarDelayedSpringRef = spring.make(registry, 1.0, 60.0, 8.0, {
        target = 1.0,
        smoothingFactor = 0.85,
        preventOvershoot = false,
        maxVelocity = 8.0
    })
    hpBarDelayedSpringEntity, hpBarDelayedSpringRef = spring.make(registry, 1.0, 60.0, 8.0, {
        target = 1.0,
        smoothingFactor = 0.85,
        preventOvershoot = false,
        maxVelocity = 8.0
    })

    -- Track previous values for change detection
    local prevHpPct = 1.0
    local prevXpPct = 0.0
    local movementTutorialStyle = {
        margin = 20,
        paddingX = 14,
        paddingY = 12,
        rowSpacing = 10,
        iconTextGap = 12,
        keySize = 28,
        keyGap = 4,
        spaceWidth = 80,
        spaceHeight = 24,
        stickSize = 40,
        buttonSize = 32,
        fontSize = 18,
        textColor = util.getColor("apricot_cream"),
        bgColor = Col(8, 10, 16, 170),
        outlineColor = Col(255, 255, 255, 30),
        z = z_orders.background - 1
    }

    local function measureMoveHint(isPad)
        if isPad then
            local size = movementTutorialStyle.stickSize
            return size, size
        end
        local keySize = movementTutorialStyle.keySize
        local gap = movementTutorialStyle.keyGap
        return keySize * 3 + gap * 2, keySize * 2 + gap
    end

    local function measureDashHint(isPad)
        if isPad then
            local size = movementTutorialStyle.buttonSize
            return size, size
        end
        return movementTutorialStyle.spaceWidth, movementTutorialStyle.spaceHeight
    end

    local function drawMoveHintIcons(x, y, isPad, z, renderSpace)
        renderSpace = renderSpace or layer.DrawCommandSpace.Screen
        if isPad then
            local size = movementTutorialStyle.stickSize
            command_buffer.queueDrawSpriteTopLeft(layers.sprites, function(c)
                c.spriteName = "xbox_stick_top_l.png"
                c.x = x
                c.y = y
                c.dstW = size
                c.dstH = size
            end, z, renderSpace)
            return
        end

        local keySize = movementTutorialStyle.keySize
        local gap = movementTutorialStyle.keyGap
        local rowWidth = keySize * 3 + gap * 2
        local topX = x + (rowWidth - keySize) * 0.5
        local topY = y
        local bottomY = y + keySize + gap

        command_buffer.queueDrawSpriteTopLeft(layers.sprites, function(c)
            c.spriteName = "keyboard_w.png"
            c.x = topX
            c.y = topY
            c.dstW = keySize
            c.dstH = keySize
        end, z, renderSpace)

        command_buffer.queueDrawSpriteTopLeft(layers.sprites, function(c)
            c.spriteName = "keyboard_a.png"
            c.x = x
            c.y = bottomY
            c.dstW = keySize
            c.dstH = keySize
        end, z, renderSpace)

        command_buffer.queueDrawSpriteTopLeft(layers.sprites, function(c)
            c.spriteName = "keyboard_s.png"
            c.x = x + keySize + gap
            c.y = bottomY
            c.dstW = keySize
            c.dstH = keySize
        end, z, renderSpace)

        command_buffer.queueDrawSpriteTopLeft(layers.sprites, function(c)
            c.spriteName = "keyboard_d.png"
            c.x = x + (keySize + gap) * 2
            c.y = bottomY
            c.dstW = keySize
            c.dstH = keySize
        end, z, renderSpace)
    end

    local function drawDashHintIcon(x, y, isPad, z, renderSpace)
        renderSpace = renderSpace or layer.DrawCommandSpace.Screen
        if isPad then
            local size = movementTutorialStyle.buttonSize
            command_buffer.queueDrawSpriteTopLeft(layers.sprites, function(c)
                c.spriteName = "xbox_button_a.png"
                c.x = x
                c.y = y
                c.dstW = size
                c.dstH = size
            end, z, renderSpace)
            return
        end

        command_buffer.queueDrawSpriteTopLeft(layers.sprites, function(c)
            c.spriteName = "keyboard_space.png"
            c.x = x
            c.y = y
            c.dstW = movementTutorialStyle.spaceWidth
            c.dstH = movementTutorialStyle.spaceHeight
        end, z, renderSpace)
    end

    local function drawActionInputTutorial()
        local arenaLeft = SCREEN_BOUND_LEFT or 0
        local arenaTop = SCREEN_BOUND_TOP or 0
        local arenaRight = SCREEN_BOUND_RIGHT or 0
        local arenaBottom = SCREEN_BOUND_BOTTOM or 0
        local renderSpace = layer.DrawCommandSpace.World
        local usingPad = input and input.isPadConnected and input.isPadConnected(0)

        local moveText = localization.get("ui.tutorial_to_move")
        local dashText = localization.get("ui.tutorial_to_dash")
        local fontSize = movementTutorialStyle.fontSize
        local moveTextWidth = localization.getTextWidthWithCurrentFont(moveText, fontSize, 1)
        local dashTextWidth = localization.getTextWidthWithCurrentFont(dashText, fontSize, 1)

        local moveIconW, moveIconH = measureMoveHint(usingPad)
        local dashIconW, dashIconH = measureDashHint(usingPad)
        local rowSpacing = movementTutorialStyle.rowSpacing
        local row1Height = math.max(moveIconH, fontSize)
        local row2Height = math.max(dashIconH, fontSize)
        local contentWidth = math.max(
            moveIconW + movementTutorialStyle.iconTextGap + moveTextWidth,
            dashIconW + movementTutorialStyle.iconTextGap + dashTextWidth
        )
        local contentHeight = row1Height + row2Height + rowSpacing
        local panelW = contentWidth + movementTutorialStyle.paddingX * 2
        local panelH = contentHeight + movementTutorialStyle.paddingY * 2
        local startX = arenaLeft + movementTutorialStyle.margin
        local startY = arenaBottom - movementTutorialStyle.margin - panelH

        -- Keep the tutorial anchored inside the arena bounds.
        local maxStartX = arenaRight - movementTutorialStyle.margin - panelW
        local minStartY = arenaTop + movementTutorialStyle.margin
        if startX > maxStartX then startX = maxStartX end
        if startY < minStartY then startY = minStartY end

        command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
            c.x = startX + panelW * 0.5
            c.y = startY + panelH * 0.5
            c.w = panelW
            c.h = panelH
            c.rx = 10
            c.ry = 10
            c.color = movementTutorialStyle.bgColor
            -- c.outlineColor = movementTutorialStyle.outlineColor
        end, movementTutorialStyle.z, renderSpace)

        local cursorY = startY + movementTutorialStyle.paddingY
        local iconX = startX + movementTutorialStyle.paddingX

        local moveIconY = cursorY + (row1Height - moveIconH) * 0.5
        drawMoveHintIcons(iconX, moveIconY, usingPad, movementTutorialStyle.z + 1, renderSpace)
        local moveTextX = iconX + moveIconW + movementTutorialStyle.iconTextGap
        local moveTextY = cursorY + (row1Height - fontSize) * 0.5
        command_buffer.queueDrawText(layers.sprites, function(c)
            c.text = moveText
            c.font = localization.getFont()
            c.x = moveTextX
            c.y = moveTextY
            c.color = movementTutorialStyle.textColor
            c.fontSize = fontSize
        end, movementTutorialStyle.z + 2, renderSpace)

        cursorY = cursorY + row1Height + rowSpacing
        local dashIconY = cursorY + (row2Height - dashIconH) * 0.5
        drawDashHintIcon(iconX, dashIconY, usingPad, movementTutorialStyle.z + 1, renderSpace)
        local dashTextX = iconX + dashIconW + movementTutorialStyle.iconTextGap
        local dashTextY = cursorY + (row2Height - fontSize) * 0.5
        command_buffer.queueDrawText(layers.sprites, function(c)
            c.text = dashText
            c.font = localization.getFont()
            c.x = dashTextX
            c.y = dashTextY
            c.color = movementTutorialStyle.textColor
            c.fontSize = fontSize
        end, movementTutorialStyle.z + 2, renderSpace)
    end

    -- update combat system every frame / render health bars
    -- Changed from timer.run() to timer.run_every_render_frame() to fix flickering
    -- timer.run() executes during fixed timestep which may skip frames
    timer.run_every_render_frame(
        function()
            -- bail if not in action state
            if not is_state_active(ACTION_STATE) or isLevelUpModalActive() then return end

            local frameDt = GetFrameTime()
            updateAimSpring(frameDt)
            WandExecutor.update(frameDt)
            ctx.time:tick(frameDt)
            if playerDashCooldownRemaining > 0 then
                playerDashCooldownRemaining = math.max(playerDashCooldownRemaining - frameDt, 0)
            end
            if playerDashTimeRemaining > 0 then
                playerDashTimeRemaining = math.max(playerDashTimeRemaining - frameDt, 0)
                if playerDashTimeRemaining <= 0 then
                    playerIsDashing = false
                end
            end
            if dashBufferTimer > 0 then
                dashBufferTimer = math.max(dashBufferTimer - frameDt, 0)
                if dashBufferTimer <= 0 then
                    bufferedDashDir = nil
                end
            end
            if playerStaminaTickerTimer > 0 then
                playerStaminaTickerTimer = math.max(playerStaminaTickerTimer - frameDt, 0)
            end


            -- also, display a health bar indicator above the player entity, and an EXP bar.

            if not survivorEntity or not entity_cache.valid(survivorEntity) then
                return
            end

            local anchorTransform = component_cache.get(survivorEntity, Transform)

            if anchorTransform then
                local centerX = (anchorTransform.visualX or anchorTransform.actualX or 0) +
                    (anchorTransform.visualW or anchorTransform.actualW or 0) * 0.5
                local centerY = (anchorTransform.visualY or anchorTransform.actualY or 0) +
                    (anchorTransform.visualH or anchorTransform.actualH or 0) * 0.5
                centerX = centerX + aimSpring.ox
                centerY = centerY + aimSpring.oy

                local aimAngle = mouseAimAngle or 0
                local autoAimTarget = nil

                if autoAimEnabled then
                    autoAimTarget = findNearestEnemyPosition(centerX, centerY, AUTO_AIM_RADIUS)
                    if autoAimTarget then
                        local dx = autoAimTarget.x - centerX
                        local dy = autoAimTarget.y - centerY
                        if dx * dx + dy * dy > 0.0001 then
                            aimAngle = math.atan(dy, dx)
                        end
                    end
                end

                if not autoAimTarget then
                    local padConnected = input and input.isPadConnected and input.isPadConnected(0)
                    if padConnected and input.getPadAxis then
                        local axisRX = (GamepadAxis and GamepadAxis.GAMEPAD_AXIS_RIGHT_X) or 2
                        local axisRY = (GamepadAxis and GamepadAxis.GAMEPAD_AXIS_RIGHT_Y) or 3
                        local rStickX = input.getPadAxis(0, axisRX) or 0
                        local rStickY = input.getPadAxis(0, axisRY) or 0
                        local mag = math.sqrt(rStickX * rStickX + rStickY * rStickY)
                        if mag > 0.25 then
                            aimAngle = math.atan(rStickY, rStickX)
                        end
                    else
                        local cam = camera and camera.Get and camera.Get("world_camera")
                        if cam and cam.GetMouseWorld then
                            local mouseWorld = cam:GetMouseWorld()
                            if mouseWorld then
                                local dx = mouseWorld.x - centerX
                                local dy = mouseWorld.y - centerY
                                if dx * dx + dy * dy > 0.0001 then
                                    aimAngle = math.atan(dy, dx)
                                end
                            end
                        end
                    end
                end

                mouseAimAngle = aimAngle
                if globals then
                    globals.mouseAimAngle = aimAngle
                end

                if command_buffer and command_buffer.queueDrawTriangle and layers and layers.sprites then
                    local dirX, dirY = math.cos(aimAngle), math.sin(aimAngle)
                    local w = anchorTransform.visualW or anchorTransform.actualW or 0
                    local h = anchorTransform.visualH or anchorTransform.actualH or 0
                    local baseRadius = math.max(w, h, 48) * 0.55
                    local triangleLength = 18
                    local baseDistance = math.max(baseRadius - triangleLength, baseRadius * 0.5)
                    local tipX = centerX + dirX * baseRadius
                    local tipY = centerY + dirY * baseRadius
                    local baseX = centerX + dirX * baseDistance
                    local baseY = centerY + dirY * baseDistance
                    local perpX, perpY = -dirY, dirX
                    local halfWidth = 8
                    local p2x = baseX + perpX * halfWidth
                    local p2y = baseY + perpY * halfWidth
                    local p3x = baseX - perpX * halfWidth
                    local p3y = baseY - perpY * halfWidth
                    local shadowOffset = 3
                    local aimZ = (z_orders.player_vfx or 0) + 1

                    command_buffer.queueDrawTriangle(layers.sprites, function(c)
                        c.p1 = Vec2(tipX + shadowOffset, tipY + shadowOffset)
                        c.p2 = Vec2(p2x + shadowOffset, p2y + shadowOffset)
                        c.p3 = Vec2(p3x + shadowOffset, p3y + shadowOffset)
                        c.color = Col(0, 0, 0, 110)
                    end, aimZ, layer.DrawCommandSpace.World)

                    command_buffer.queueDrawTriangle(layers.sprites, function(c)
                        c.p1 = Vec2(tipX, tipY)
                        c.p2 = Vec2(p2x, p2y)
                        c.p3 = Vec2(p3x, p3y)
                        local baseColor = (util and util.getColor and util.getColor("apricot_cream")) or Col(255, 230, 190, 255)
                        local offColor = Col(255, 245, 230, 200)
                        c.color = autoAimEnabled and baseColor or offColor
                    end, aimZ + 1, layer.DrawCommandSpace.World)
                end

                local playerCombatInfo = ctx.side1[1]

                local playerHealth = playerCombatInfo.hp
                local playerMaxHealth = playerCombatInfo.max_health

                local playerXP = playerCombatInfo.xp or 0
                local playerXPForNextLevel = CombatSystem.Game.Leveling.xp_to_next(ctx, playerCombatInfo,
                    playerCombatInfo.level or 1)

                local hpPct = playerHealth / playerMaxHealth
                local xpPct = math.min(playerXP / playerXPForNextLevel, 1.0)

                ------------------------------------------------------------
                -- DASH STAMINA TICKER (world space, lingers after refilling)
                ------------------------------------------------------------
                if playerStaminaTickerTimer > 0 then
                    local staminaPct = 1.0
                    if playerDashCooldownRemaining > 0 then
                        staminaPct = 1.0 - (playerDashCooldownRemaining / DASH_COOLDOWN_SECONDS)
                    end
                    staminaPct          = math.max(0.0, math.min(1.0, staminaPct))

                    local visualCenterX = anchorTransform.visualX + anchorTransform.visualW * 0.5
                    local visualBottomY = anchorTransform.visualY + anchorTransform.visualH

                    local staminaWidth  = math.max(anchorTransform.visualW * 0.8, 48)
                    local staminaHeight = 6
                    local staminaX      = visualCenterX
                    local staminaY      = visualBottomY + 10

                    command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                        c.x     = staminaX
                        c.y     = staminaY
                        c.w     = staminaWidth
                        c.h     = staminaHeight
                        c.rx    = 3
                        c.ry    = 3
                        c.color = Col(20, 20, 20, 190)
                    end, z_orders.player_vfx + 1, layer.DrawCommandSpace.World)

                    local staminaFillWidth = staminaWidth * staminaPct
                    local staminaFillCenterX = (visualCenterX - staminaWidth * 0.5) + staminaFillWidth * 0.5

                    command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                        c.x              = staminaFillCenterX
                        c.y              = staminaY
                        c.w              = staminaFillWidth
                        c.h              = staminaHeight
                        c.rx             = 3
                        c.ry             = 3
                        local onCooldown = playerDashCooldownRemaining > 0
                        c.color          = onCooldown and Col(90, 180, 255, 235) or Col(90, 230, 140, 255)
                    end, z_orders.player_vfx + 2, layer.DrawCommandSpace.World)
                end

                ------------------------------------------------------------
                -- CHANGE DETECTION & SPRING UPDATES
                ------------------------------------------------------------
                local hpChanged = math.abs(hpPct - prevHpPct) > 0.001
                local xpChanged = math.abs(xpPct - prevXpPct) > 0.001

                if hpChanged then
                    -- Fetch scale spring ref
                    local hpBarScaleSpringRef = spring.get(registry, hpBarScaleSpringEntity)
                    local hpBarDelayedSpringRef = spring.get(registry, hpBarDelayedSpringEntity)

                    -- Trigger scale pulse for undulation
                    hpBarScaleSpringRef.value = 1.15
                    hpBarScaleSpringRef.targetValue = 1.0

                    if hpPct < prevHpPct then
                        -- HP decreased: delayed spring lerps down from old to new
                        hpBarDelayedSpringRef.targetValue = hpPct
                    else
                        -- HP increased: delayed spring jumps to new value
                        hpBarDelayedSpringRef.value = hpPct
                        hpBarDelayedSpringRef.targetValue = hpPct
                    end
                    prevHpPct = hpPct
                end

                if xpChanged then
                    -- Fetch scale spring ref
                    local expBarScaleSpringRef = spring.get(registry, expBarScaleSpringEntity)
                    local expBarMainSpringRef = spring.get(registry, expBarMainSpringEntity)
                    local expBarDelayedSpringRef = spring.get(registry, expBarDelayedSpringEntity)

                    -- Trigger scale pulse for undulation
                    expBarScaleSpringRef.value = 1.15
                    expBarScaleSpringRef.targetValue = 1.0

                    if xpPct < prevXpPct then
                        -- XP decreased (level up): main bar jumps to 0, white bar lerps down
                        expBarMainSpringRef.value = xpPct
                        expBarMainSpringRef.targetValue = xpPct
                        expBarDelayedSpringRef.targetValue = xpPct
                    else
                        -- XP increased: white bar jumps to new value, yellow bar lerps up
                        expBarDelayedSpringRef.value = xpPct
                        expBarDelayedSpringRef.targetValue = xpPct
                        expBarMainSpringRef.targetValue = xpPct
                    end
                    prevXpPct = xpPct
                end

                -- Fetch spring refs for rendering
                local hpBarScaleSpringRef    = spring.get(registry, hpBarScaleSpringEntity)
                local expBarScaleSpringRef   = spring.get(registry, expBarScaleSpringEntity)
                local hpBarDelayedSpringRef  = spring.get(registry, hpBarDelayedSpringEntity)
                local expBarDelayedSpringRef = spring.get(registry, expBarDelayedSpringEntity)
                local expBarMainSpringRef    = spring.get(registry, expBarMainSpringEntity)

                -- Get current spring values
                local hpScale                = hpBarScaleSpringRef.value or 1.0
                local xpScale                = expBarScaleSpringRef.value or 1.0
                local hpDelayedSpringVal     = hpBarDelayedSpringRef.value or hpPct
                local xpDelayedSpringVal     = expBarDelayedSpringRef.value or xpPct
                local xpMainSpringVal        = expBarMainSpringRef.value or xpPct

                local screenCenterX          = globals.screenWidth() * 0.5
                local barOutlineWidth        = 3
                local barGap                 = 0

                local baseExpBarWidth        = globals.screenWidth()
                local baseExpBarHeight       = 20

                local expBarWidth            = baseExpBarWidth
                local expBarHeight           = baseExpBarHeight

                local expBarX                = screenCenterX
                local expBarY                = math.max(barOutlineWidth, 0)

                ------------------------------------------------------------
                -- HEALTH BAR (container only – no scaling)
                ------------------------------------------------------------
                local baseHealthBarWidth     = globals.screenWidth() * 0.4
                local baseHealthBarHeight    = 20

                local healthBarWidth         = baseHealthBarWidth
                local healthBarHeight        = baseHealthBarHeight

                local healthBarX             = screenCenterX
                local healthBarY             = expBarY + expBarHeight + barGap

                -- background container
                command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                    c.x     = healthBarX
                    c.y     = healthBarY + healthBarHeight * 0.5
                    c.w     = healthBarWidth
                    c.h     = healthBarHeight
                    c.rx    = 5
                    c.ry    = 5
                    c.color = util.getColor("dark_gray")
                end, z_orders.background, layer.DrawCommandSpace.Screen)

                ------------------------------------------------------------
                -- HEALTH BARS: Two bars - main (red) and delayed (white)
                -- Decrease: red moves to new value, white (behind) catches up
                -- Increase: white jumps to new value, red catches up
                -- White bar always rendered behind red bar
                ------------------------------------------------------------
                local hpDelayedPct = hpDelayedSpringVal

                -- White bar shows: max of current and delayed (so it's always the "bigger" reference)
                local hpWhitePct = math.max(hpPct, hpDelayedPct)
                -- Red bar shows: min of current and delayed (so it's always the "smaller" or actual)
                local hpRedPct = math.min(hpPct, hpDelayedPct)

                -- White bar (behind) - shows the larger value
                local fillWhiteWidth = baseHealthBarWidth * hpWhitePct
                local fillWhiteCenterX = (healthBarX - healthBarWidth * 0.5) + fillWhiteWidth * 0.5

                command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                    c.x     = fillWhiteCenterX
                    c.y     = healthBarY + healthBarHeight * 0.5
                    c.w     = fillWhiteWidth
                    c.h     = healthBarHeight * hpScale
                    c.rx    = 5
                    c.ry    = 5
                    c.color = Col(255, 255, 255, 255)
                end, z_orders.background + 1, layer.DrawCommandSpace.Screen)

                command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                    local outlineW = math.max(0, baseHealthBarWidth - barOutlineWidth)
                    local outlineH = math.max(0, (healthBarHeight * hpScale) - barOutlineWidth)
                    c.x         = healthBarX
                    c.y         = healthBarY + healthBarHeight * 0.5
                    c.w         = outlineW
                    c.h         = outlineH
                    c.rx        = 5
                    c.ry        = 5
                    c.color     = Col(255, 255, 255, 255)
                    c.lineWidth = barOutlineWidth
                end, z_orders.background + 1, layer.DrawCommandSpace.Screen)

                -- Red bar (front) - shows the smaller/current value
                local fillRedWidth = baseHealthBarWidth * hpRedPct
                local fillRedCenterX = (healthBarX - healthBarWidth * 0.5) + fillRedWidth * 0.5

                command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                    c.x     = fillRedCenterX
                    c.y     = healthBarY + healthBarHeight * 0.5
                    c.w     = fillRedWidth
                    c.h     = healthBarHeight * hpScale
                    c.rx    = 5
                    c.ry    = 5
                    c.color = util.getColor("red")
                end, z_orders.background + 2, layer.DrawCommandSpace.Screen)

                command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                    local outlineW = math.max(0, baseHealthBarWidth - barOutlineWidth)
                    local outlineH = math.max(0, (healthBarHeight * hpScale) - barOutlineWidth)
                    c.x         = healthBarX
                    c.y         = healthBarY + healthBarHeight * 0.5
                    c.w         = outlineW
                    c.h         = outlineH
                    c.rx        = 5
                    c.ry        = 5
                    c.color     = util.getColor("red")
                    c.lineWidth = barOutlineWidth
                end, z_orders.background + 3, layer.DrawCommandSpace.Screen)

                ------------------------------------------------------------
                -- EXP BAR (container only — no scaling)
                ------------------------------------------------------------
                -- background container
                command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                    c.x     = expBarX
                    c.y     = expBarY + expBarHeight * 0.5
                    c.w     = expBarWidth
                    c.h     = expBarHeight
                    c.rx    = 5
                    c.ry    = 5
                    c.color = util.getColor("dark_gray")
                end, z_orders.background, layer.DrawCommandSpace.Screen)

                ------------------------------------------------------------
                -- EXP BARS: Two bars - main (yellow) and delayed (white)
                -- Yellow bar uses main spring (smooth lerp), white bar shows buffer
                ------------------------------------------------------------
                local xpDelayedPct = xpDelayedSpringVal
                local xpYellowPct = xpMainSpringVal

                -- White bar shows: max of main and delayed (buffer)
                local xpWhitePct = math.max(xpYellowPct, xpDelayedPct)

                -- White bar (behind) - shows the larger value
                local xpFillWhiteWidth = baseExpBarWidth * xpWhitePct
                local xpFillWhiteCenterX = (expBarX - expBarWidth * 0.5) + xpFillWhiteWidth * 0.5

                command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                    c.x     = xpFillWhiteCenterX
                    c.y     = expBarY + expBarHeight * 0.5
                    c.w     = xpFillWhiteWidth
                    c.h     = expBarHeight * xpScale
                    c.rx    = 5
                    c.ry    = 5
                    c.color = Col(255, 255, 255, 255)
                end, z_orders.background + 1, layer.DrawCommandSpace.Screen)

                command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                    local outlineW = math.max(0, baseExpBarWidth - barOutlineWidth)
                    local outlineH = math.max(0, (expBarHeight * xpScale) - barOutlineWidth)
                    c.x         = expBarX
                    c.y         = expBarY + expBarHeight * 0.5
                    c.w         = outlineW
                    c.h         = outlineH
                    c.rx        = 5
                    c.ry        = 5
                    c.color     = Col(255, 255, 255, 255)
                    c.lineWidth = barOutlineWidth
                end, z_orders.background + 1, layer.DrawCommandSpace.Screen)

                -- Yellow bar (front) - shows the main spring value (smooth lerp)
                local xpFillYellowWidth = baseExpBarWidth * xpYellowPct
                local xpFillYellowCenterX = (expBarX - expBarWidth * 0.5) + xpFillYellowWidth * 0.5

                command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                    c.x     = xpFillYellowCenterX
                    c.y     = expBarY + expBarHeight * 0.5
                    c.w     = xpFillYellowWidth
                    c.h     = expBarHeight * xpScale
                    c.rx    = 5
                    c.ry    = 5
                    c.color = util.getColor("yellow")
                end, z_orders.background + 2, layer.DrawCommandSpace.Screen)

                command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                    local outlineW = math.max(0, baseExpBarWidth - barOutlineWidth)
                    local outlineH = math.max(0, (expBarHeight * xpScale) - barOutlineWidth)
                    c.x         = expBarX
                    c.y         = expBarY + expBarHeight * 0.5
                    c.w         = outlineW
                    c.h         = outlineH
                    c.rx        = 5
                    c.ry        = 5
                    c.color     = util.getColor("yellow")
                    c.lineWidth = barOutlineWidth
                end, z_orders.background + 3, layer.DrawCommandSpace.Screen)

                ------------------------------------------------------------
                -- ENEMY HEALTH BARS (world space, show briefly after damage)
                ------------------------------------------------------------
                local now = GetTime()
                local enemiesToRemove = nil
                for enemyEid, state in pairs(enemyHealthUiState) do
                    if not entity_cache.valid(enemyEid) then
                        enemiesToRemove = enemiesToRemove or {}
                        table.insert(enemiesToRemove, enemyEid)
                    else
                        local actor = state.actor
                        local enemyT = component_cache.get(enemyEid, Transform)
                        local maxHp = actor and (actor.max_health or (actor.stats and actor.stats:get('health')))
                        local showBar = state.visibleUntil and state.visibleUntil > now
                        if showBar and enemyT and actor and maxHp and maxHp > 0 then
                            local hpPct = math.max(0.0, math.min(1.0, (actor.hp or maxHp) / maxHp))
                            local barWidth = math.max(enemyT.actualW, 40)
                            local barHeight = 6
                            local barX = enemyT.actualX + enemyT.actualW * 0.5
                            local barY = enemyT.actualY - 8

                            command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                                c.x     = barX
                                c.y     = barY
                                c.w     = barWidth
                                c.h     = barHeight
                                c.rx    = 3
                                c.ry    = 3
                                c.color = Col(20, 20, 20, 190)
                            end, z_orders.enemies + 1, layer.DrawCommandSpace.World)

                            local hpFillWidth = barWidth * hpPct
                            local hpFillCenterX = (barX - barWidth * 0.5) + hpFillWidth * 0.5

                            command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                                c.x     = hpFillCenterX
                                c.y     = barY
                                c.w     = hpFillWidth
                                c.h     = barHeight
                                c.rx    = 3
                                c.ry    = 3
                                c.color = util.getColor("red")
                            end, z_orders.enemies + 2, layer.DrawCommandSpace.World)
                        end
                    end
                end
                if enemiesToRemove then
                    for _, eid in ipairs(enemiesToRemove) do
                        enemyHealthUiState[eid] = nil
                    end
                end

                ------------------------------------------------------------
                -- DAMAGE NUMBERS (world space, float up and fade)
                ------------------------------------------------------------
                if #damageNumbers > 0 then
                    for i = #damageNumbers, 1, -1 do
                        local dn = damageNumbers[i]
                        dn.age = (dn.age or 0) + frameDt
                        local life = dn.life or DAMAGE_NUMBER_LIFETIME

                        if dn.age >= life then
                            table.remove(damageNumbers, i)
                        else
                            dn.x = dn.x + (dn.vx or 0) * frameDt
                            dn.y = dn.y + (dn.vy or 0) * frameDt
                            dn.vy = (dn.vy or 0) + DAMAGE_NUMBER_GRAVITY * frameDt

                            local remaining = 1.0 - (dn.age / life)
                            -- Stay fully visible, only fade in the last 25% of lifetime
                            local fadeStart = 0.25
                            local alpha = remaining > fadeStart and 1.0 or math.max(0.0, remaining / fadeStart)
                            local color = dn.color or { r = 255, g = 255, b = 255, a = 255 }
                            local scale = (dn.crit and 1.15 or 1.0) * (1.0 + 0.05 * alpha)
                            local fontSize = (dn.fontSize or DAMAGE_NUMBER_FONT_SIZE) * scale
                            local r = color.r or 255
                            local g = color.g or 255
                            local b = color.b or 255
                            local a = color.a or 255
                            local z = z_orders.enemies + 3

                            -- Main text
                            command_buffer.queueDrawText(layers.sprites, function(c)
                                c.text = dn.text
                                c.font = localization.getFont()
                                c.x = dn.x
                                c.y = dn.y
                                c.color = Col(r, g, b, math.floor(a * alpha))
                                c.fontSize = fontSize
                            end, z + 1, layer.DrawCommandSpace.World)
                        end
                    end
                end
                -- Simple manual input tutorial (icons + text) for action phase
                drawActionInputTutorial()
            end
        end

    )
end

function cycleBoardSets(amount)
    current_board_set_index = current_board_set_index + amount
    if current_board_set_index < 1 then
        current_board_set_index = #board_sets
    elseif current_board_set_index > #board_sets then
        current_board_set_index = 1
    end

    -- hide ALL board sets (boards and cards hidden, only wand selector buttons visible)
    for index, boardSet in ipairs(board_sets) do
        toggleBoardSetVisibility(boardSet, false)
    end

    
    -- cam jiggle
    local cam = camera.Get("world_camera")
    cam:SetVisualRotation(1)
    
    -- sfx
    playSoundEffect("effects", "cycle-wand-set")

    -- activate tooltip state
    activate_state(WAND_TOOLTIP_STATE)
end

function cycleBoardSet(targetIndex)
    if not targetIndex or not board_sets or #board_sets == 0 then return end
    local clamped = math.max(1, math.min(#board_sets, targetIndex))
    local delta = clamped - current_board_set_index
    if delta ~= 0 then
        cycleBoardSets(delta)
    end
end

local virtualCardCounter = 0

local function makeVirtualCardFromTemplate(template)
    if not template then return nil end
    virtualCardCounter = virtualCardCounter + 1
    local card = util.deep_copy(template)
    card.card_id = template.id or template.card_id
    card.type = template.type
    card._virtual_handle = "virtual_card_" .. tostring(virtualCardCounter)
    card.handle = function(self) return self._virtual_handle end
    return card
end

local function collectCardPoolForBoardSet(boardSet, silent)
    if not boardSet then return nil end
    local actionBoard = boards[boardSet.action_board_id]
    if not actionBoard or not actionBoard.cards or #actionBoard.cards == 0 then return nil end

    local pool = {}
    local modStats = { total = 0, valid = 0, invalid = 0, noScript = 0 }

    local function pushCard(cardScript)
        if not cardScript then return end
        local stackLen = cardScript.cardStack and #cardScript.cardStack or 0
        if not silent then
            print(string.format("[MANABAR] card=%s stack=%s len=%d",
                cardScript.card_id or "?",
                cardScript.cardStack and "exists" or "nil",
                stackLen))
        end
        if cardScript.cardStack and #cardScript.cardStack > 0 then
            for _, modEid in ipairs(cardScript.cardStack) do
                modStats.total = modStats.total + 1
                if modEid and entity_cache.valid(modEid) then
                    local modScript = getScriptTableFromEntityID(modEid)
                    if modScript then
                        modStats.valid = modStats.valid + 1
                        table.insert(pool, modScript)
                    else
                        modStats.noScript = modStats.noScript + 1
                    end
                else
                    modStats.invalid = modStats.invalid + 1
                    if not silent then
                        print(string.format("[MANABAR] INVALID mod entity: %s (on card %s)",
                            tostring(modEid), cardScript.card_id or "?"))
                    end
                end
            end
        end
        table.insert(pool, cardScript)
    end

    local sortedCards = {}
    for _, cardEid in ipairs(actionBoard.cards) do
        if cardEid and entity_cache.valid(cardEid) then
            local t = component_cache.get(cardEid, Transform)
            local x = t and t.visualX or 0
            table.insert(sortedCards, { eid = cardEid, x = x })
        end
    end
    table.sort(sortedCards, function(a, b) return a.x < b.x end)

    for _, entry in ipairs(sortedCards) do
        pushCard(getScriptTableFromEntityID(entry.eid))
    end

    if boardSet.wandDef and boardSet.wandDef.always_cast_cards then
        for _, alwaysId in ipairs(boardSet.wandDef.always_cast_cards) do
            local template = WandEngine.card_defs[alwaysId]
            local virtualCard = makeVirtualCardFromTemplate(template)
            if virtualCard then
                table.insert(pool, virtualCard)
            end
        end
    end

    if modStats.total > 0 and not silent then
        print(string.format("[MANABAR] modCards: total=%d valid=%d invalid=%d noScript=%d",
            modStats.total, modStats.valid, modStats.invalid, modStats.noScript))
    end

    return pool
end

function countTableEntries(t)
    if type(t) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

function describeBoardSet(index, boardSet)
    if not boardSet then
        return string.format("set %d: <nil>", index)
    end

    local actionBoard = boardSet.action_board_id and boards and boards[boardSet.action_board_id]
    local triggerBoard = boardSet.trigger_board_id and boards and boards[boardSet.trigger_board_id]
    local actionCardCount = actionBoard and actionBoard.cards and #actionBoard.cards or 0
    local triggerCardCount = triggerBoard and triggerBoard.cards and #triggerBoard.cards or 0
    local triggerCardEntity = triggerBoard and triggerBoard.cards and triggerBoard.cards[1]
    local triggerScript = triggerCardEntity and getScriptTableFromEntityID and getScriptTableFromEntityID(triggerCardEntity)
    local triggerId = triggerScript and (triggerScript.card_id or triggerScript.cardID or triggerScript.id) or "nil"
    local wandId = boardSet.wandDef and boardSet.wandDef.id or "nil"
    local currentMarker = (index == current_board_set_index) and "*" or " "

    return string.format("%sset %d wand=%s actionCards=%d trigger=%s (triggerCards=%d)",
        currentMarker, index, tostring(wandId), actionCardCount, tostring(triggerId), triggerCardCount)
end

function logBoardSetStatus(contextLabel)
    if not board_sets or #board_sets == 0 then
        print(string.format("[DEBUG ACTION] %s: board_sets empty", contextLabel))
        return
    end

    print(string.format("[DEBUG ACTION] %s: total_sets=%d current_index=%s",
        contextLabel, #board_sets, tostring(current_board_set_index)))

    for index, boardSet in ipairs(board_sets) do
        print(string.format("[DEBUG ACTION]   %s", describeBoardSet(index, boardSet)))
    end
end

function maybeAutoEnterActionPhase()
    gameplay_cfg.auto_action_state = gameplay_cfg.auto_action_state or {}

    if not gameplay_cfg.auto_action_env then
        if not gameplay_cfg.auto_action_state.reported_disabled then
            print("[DEBUG ACTION] maybeAutoEnterActionPhase: AUTO_ACTION_PHASE not enabled")
            gameplay_cfg.auto_action_state.reported_disabled = true
        end
        return
    end
    if gameplay_cfg.auto_action_state.scheduled then
        return
    end
    gameplay_cfg.auto_action_state.scheduled = true

    print("[DEBUG ACTION] AUTO_ACTION_PHASE enabled - scheduling startActionPhase() in 1s")

    local function fireAction()
        if startActionPhase then
            print("[DEBUG ACTION] AUTO_ACTION_PHASE firing startActionPhase()")
            startActionPhase()
        else
            print("[DEBUG ACTION] AUTO_ACTION_PHASE: startActionPhase not available")
        end
    end

    if timer and timer.after then
        timer.after(1.0, fireAction)
    else
        fireAction()
    end
end

if gameplay_cfg.auto_action_env and timer and timer.after then
    timer.after(5.0, function()
        gameplay_cfg.auto_action_state = gameplay_cfg.auto_action_state or {}
        if gameplay_cfg.auto_action_state.scheduled then
            return
        end
        gameplay_cfg.auto_action_state.scheduled = true
        print("[DEBUG ACTION] AUTO_ACTION_PHASE fallback triggering startActionPhase()")
        if startActionPhase then
            startActionPhase()
        else
            print("[DEBUG ACTION] AUTO_ACTION_PHASE fallback: startActionPhase not available")
        end
    end, "auto_action_fallback", "debug_timers")
end

updateWandResourceBar = function()
    if gameplay_cfg.isGridInventoryEnabled()
        and wandAdapter
        and wandAdapter.getWandCount
        and wandAdapter.getWandDef
        and wandAdapter.collectCardPool then
        local wandCount = wandAdapter.getWandCount()
        if wandCount and wandCount > 0 then
            local wandIndex = current_board_set_index
            local wandDef = wandAdapter.getWandDef(wandIndex)
            local cardPool = wandAdapter.collectCardPool(wandIndex)
            wandResourceBar.update(wandDef, cardPool)
            return
        end
    end

    if not board_sets or #board_sets == 0 then 
        print("[MANABAR] No board_sets")
        return 
    end
    local currentSet = board_sets[current_board_set_index]
    if not currentSet then 
        print("[MANABAR] No currentSet at index", current_board_set_index)
        return 
    end

    local wandDef = currentSet.wandDef
    local cardPool = collectCardPoolForBoardSet(currentSet)
    
    local actionBoard = boards[currentSet.action_board_id]
    local cardCount = actionBoard and actionBoard.cards and #actionBoard.cards or 0
    print(string.format("[MANABAR] boardIndex=%d, boardCards=%d, pool=%s, wand=%s",
        current_board_set_index, cardCount, cardPool and #cardPool or "nil", wandDef and wandDef.id or "nil"))

    wandResourceBar.update(wandDef, cardPool)
end

local tagEvaluationFallbackPlayer = { active_tag_bonuses = {}, active_procs = {} }

local function buildDeckSnapshotFromBoards()
    local cards = {}

    if gameplay_cfg.isGridInventoryEnabled()
        and wandAdapter
        and wandAdapter.getWandCount
        and wandAdapter.collectCardPool then
        local wandCount = wandAdapter.getWandCount()
        if wandCount and wandCount > 0 then
            for wandIndex = 1, wandCount do
                local pool = wandAdapter.collectCardPool(wandIndex)
                if pool then
                    for _, card in ipairs(pool) do
                        cards[#cards + 1] = card
                    end
                end
            end
            return { cards = cards }
        end
    end

    if board_sets then
        for _, boardSet in ipairs(board_sets) do
            local pool = collectCardPoolForBoardSet(boardSet)
            if pool then
                for _, card in ipairs(pool) do
                    cards[#cards + 1] = card
                end
            end
        end
    end

    return { cards = cards }
end

local function getTagEvaluationTargets()
    local playerScript = survivorEntity and getScriptTableFromEntityID(survivorEntity)

    if playerScript and playerScript.combatTable then
        return playerScript.combatTable, playerScript
    end

    if playerScript then
        return playerScript, playerScript
    end

    if player and type(player) == "table" then
        return player, nil
    end

    return tagEvaluationFallbackPlayer, nil
end

reevaluateDeckTags = function()
    if gameplay_cfg.isGridInventoryEnabled()
        and wandAdapter
        and wandAdapter.getWandCount
        and (wandAdapter.getWandCount() or 0) > 0 then
        -- Use adapter-backed deck snapshot in grid inventory mode.
    elseif not board_sets or #board_sets == 0 then
        return
    end

    local deckSnapshot = buildDeckSnapshotFromBoards()
    local playerTarget, playerScript = getTagEvaluationTargets()
    if not playerTarget then return end

    TagEvaluator.evaluate_and_apply(playerTarget, deckSnapshot, combat_context)
    if ui_modules.TagSynergyPanel and ui_modules.TagSynergyPanel.isActive then
        ui_modules.TagSynergyPanel.setData(playerTarget.tag_counts, TagEvaluator.get_breakpoints())
    end
    if ui_modules.AvatarJokerStrip and ui_modules.AvatarJokerStrip.isActive and playerScript and playerScript.avatar_state then
        -- Use playerScript (has avatar_state), not playerTarget (may be combatTable)
        ui_modules.AvatarJokerStrip.syncFrom(playerScript)
    end

    if playerScript and playerTarget ~= playerScript then
        playerScript.tag_counts = playerTarget.tag_counts
        playerScript.active_tag_bonuses = playerTarget.active_tag_bonuses
    end
end
_G.reevaluateDeckTags = reevaluateDeckTags

local DEFAULT_TRIGGER_INTERVAL = 1.0

local function buildTriggerDefForBoardSet(boardSet)
    if not boardSet then return nil end
    local triggerBoard = boards[boardSet.trigger_board_id]
    if not triggerBoard or not triggerBoard.cards or #triggerBoard.cards == 0 then return nil end

    local triggerCard = getScriptTableFromEntityID(triggerBoard.cards[1])
    if not triggerCard then return nil end

    -- Trigger defs are keyed by template name (e.g., TEST_TRIGGER_*), so scan values by their .id
    local triggerTemplate
    local triggerId = triggerCard.card_id or triggerCard.cardID
    if triggerId then
        for _, template in pairs(WandEngine.trigger_card_defs) do
            if template.id == triggerId then
                triggerTemplate = template
                break
            end
        end
    end

    local triggerDef = triggerTemplate and util.deep_copy(triggerTemplate)
        or { id = triggerId or triggerCard.cardID, type = "trigger" }

    triggerDef.id = triggerDef.id or triggerCard.cardID
    triggerDef.type = triggerDef.type or "trigger"

    if triggerDef.id == "every_N_seconds" then
        triggerDef.interval = triggerDef.interval or triggerCard.interval or DEFAULT_TRIGGER_INTERVAL
    elseif triggerDef.id == "on_distance_traveled" then
        triggerDef.distance = triggerDef.distance or triggerCard.distance
    end

    return triggerDef
end

local function loadWandsIntoExecutorFromBoards()
    WandExecutor.cleanup()
    WandExecutor.init()
    virtualCardCounter = 0

    local totalSets = board_sets and #board_sets or "nil"
    print(string.format("[DEBUG ACTION] loadWandsIntoExecutorFromBoards: board_sets=%s", tostring(totalSets)))
    if not board_sets then
        print("[DEBUG ACTION] board_sets is nil - cannot load wands")
        return
    end
    logBoardSetStatus("loadWands entry")

    -- Add default jokers for testing
    JokerSystem.clear_jokers()
    JokerSystem.add_joker("lightning_rod")  -- +15 damage & +1 chain for Lightning spells
    print("[JOKER] Added lightning_rod joker. Total jokers: " .. #JokerSystem.jokers)

    WandExecutor.getPlayerEntity = function()
        return survivorEntity
    end

    WandExecutor.createExecutionContext = function(wandId, state, activeWand)
        local ctx = BaseCreateExecutionContext(wandId, state, activeWand)
        local playerScript = survivorEntity and getScriptTableFromEntityID(survivorEntity)
        if playerScript and playerScript.combatTable and playerScript.combatTable.stats then
            ctx.playerStats = playerScript.combatTable.stats
        end
        return ctx
    end

    local loadedCount = 0
    for index, boardSet in ipairs(board_sets) do
        local cardPool = collectCardPoolForBoardSet(boardSet)
        local triggerDef = buildTriggerDefForBoardSet(boardSet)
        local wandId = boardSet and boardSet.wandDef and boardSet.wandDef.id or "nil"
        local poolCount = cardPool and #cardPool or 0
        local triggerId = triggerDef and triggerDef.id or "nil"

        if boardSet.wandDef and cardPool and #cardPool > 0 and triggerDef then
            print(string.format("[DEBUG ACTION] Loading wand set %d -> wand=%s cards=%d trigger=%s", index,
                tostring(wandId), poolCount, tostring(triggerId)))
            local wandDefCopy = util.deep_copy(boardSet.wandDef)
            WandExecutor.loadWand(wandDefCopy, cardPool, triggerDef)
            loadedCount = loadedCount + 1
        else
            local reasons = {}
            if not boardSet.wandDef then table.insert(reasons, "missing wandDef") end
            if not cardPool or #cardPool == 0 then table.insert(reasons, "no action cards") end
            if not triggerDef then table.insert(reasons, "no trigger card") end
            print(string.format("[DEBUG ACTION] Skipping wand set %d (wand=%s) reason=%s", index,
                tostring(wandId), table.concat(reasons, ", ")))
            log_debug(string.format("Skipping wand load for set %d (cards: %s, trigger: %s)", index,
                cardPool and #cardPool or 0, triggerDef and triggerDef.id or "none"))
        end
    end

    print(string.format("[DEBUG ACTION] loadWands complete: loaded=%d activeWands=%d states=%d pendingSubCasts=%d",
        loadedCount,
        countTableEntries(WandExecutor.activeWands),
        countTableEntries(WandExecutor.wandStates),
        countTableEntries(WandExecutor.pendingSubCasts)))

    if reevaluateDeckTags then
        reevaluateDeckTags()
    end
end

local function playStateTransition()
    -- Pass the localization key instead of resolved text so it updates when language changes
    transitionInOutCircle(0.6, "ui.loading_transition_text", util.getColor("black"),
        { x = globals.screenWidth() / 2, y = globals.screenHeight() / 2 })
end

-- Phase-specific peaches background settings (action uses the default values defined in shader_uniforms).
local peaches_background_defaults = nil
local peaches_background_targets = {
    planning = {
        blob_count = 4.4,
        blob_spacing = -1.2,
        shape_amplitude = 0.14,
        distortion_strength = 2.5,
        noise_strength = 0.08,
        radial_falloff = 0.12,
        wave_strength = 1.1,
        highlight_gain = 2.6,
        cl_shift = -0.04,
        edge_softness_min = 0.45,
        edge_softness_max = 0.86,
        colorTint = { x = 0.22, y = 0.55, z = 0.78 },
        blob_color_blend = 0.55,
        hue_shift = 0.45,
        pixel_size = 5.0,
        pixel_enable = 1.0,
        blob_offset = { x = -0.05, y = -0.05 },
        movement_randomness = 7.5
    },
    shop = {
        blob_count = 6.8,
        blob_spacing = -0.4,
        shape_amplitude = 0.32,
        distortion_strength = 5.0,
        noise_strength = 0.22,
        radial_falloff = -0.15,
        wave_strength = 2.3,
        highlight_gain = 4.6,
        cl_shift = 0.18,
        edge_softness_min = 0.24,
        edge_softness_max = 0.55,
        colorTint = { x = 0.82, y = 0.50, z = 0.28 },
        blob_color_blend = 0.78,
        hue_shift = 0.05,
        pixel_size = 7.0,
        pixel_enable = 1.0,
        blob_offset = { x = 0.08, y = -0.14 },
        movement_randomness = 12.0
    }
}

local function make_vec2(x, y)
    if _G.Vector2 then
        return _G.Vector2(x, y)
    end
    return { x = x, y = y }
end

local function make_vec3(x, y, z)
    if _G.Vector3 then
        return _G.Vector3(x, y, z)
    end
    return { x = x, y = y, z = z }
end

local function copy_vec2(v)
    if not v then return { x = 0, y = 0 } end
    return { x = v.x or v[1] or 0, y = v.y or v[2] or 0 }
end

local function copy_vec3(v)
    if not v then return { x = 0, y = 0, z = 0 } end
    return { x = v.x or v[1] or 0, y = v.y or v[2] or 0, z = v.z or v[3] or 0 }
end

local function ensure_peaches_defaults()
    if peaches_background_defaults or not globalShaderUniforms then
        return peaches_background_defaults ~= nil
    end

    peaches_background_defaults = {
        blob_count = globalShaderUniforms:get("peaches_background", "blob_count") or 0.0,
        blob_spacing = globalShaderUniforms:get("peaches_background", "blob_spacing") or 0.0,
        shape_amplitude = globalShaderUniforms:get("peaches_background", "shape_amplitude") or 0.0,
        distortion_strength = globalShaderUniforms:get("peaches_background", "distortion_strength") or 0.0,
        noise_strength = globalShaderUniforms:get("peaches_background", "noise_strength") or 0.0,
        radial_falloff = globalShaderUniforms:get("peaches_background", "radial_falloff") or 0.0,
        wave_strength = globalShaderUniforms:get("peaches_background", "wave_strength") or 0.0,
        highlight_gain = globalShaderUniforms:get("peaches_background", "highlight_gain") or 0.0,
        cl_shift = globalShaderUniforms:get("peaches_background", "cl_shift") or 0.0,
        edge_softness_min = globalShaderUniforms:get("peaches_background", "edge_softness_min") or 0.0,
        edge_softness_max = globalShaderUniforms:get("peaches_background", "edge_softness_max") or 0.0,
        colorTint = copy_vec3(globalShaderUniforms:get("peaches_background", "colorTint")),
        blob_color_blend = globalShaderUniforms:get("peaches_background", "blob_color_blend") or 0.0,
        hue_shift = globalShaderUniforms:get("peaches_background", "hue_shift") or 0.0,
        pixel_size = globalShaderUniforms:get("peaches_background", "pixel_size") or 0.0,
        pixel_enable = globalShaderUniforms:get("peaches_background", "pixel_enable") or 0.0,
        blob_offset = copy_vec2(globalShaderUniforms:get("peaches_background", "blob_offset")),
        movement_randomness = globalShaderUniforms:get("peaches_background", "movement_randomness") or 0.0
    }

    peaches_background_targets.action = {
        blob_count = peaches_background_defaults.blob_count,
        blob_spacing = peaches_background_defaults.blob_spacing,
        shape_amplitude = peaches_background_defaults.shape_amplitude,
        distortion_strength = peaches_background_defaults.distortion_strength,
        noise_strength = peaches_background_defaults.noise_strength,
        radial_falloff = peaches_background_defaults.radial_falloff,
        wave_strength = peaches_background_defaults.wave_strength,
        highlight_gain = peaches_background_defaults.highlight_gain,
        cl_shift = peaches_background_defaults.cl_shift,
        edge_softness_min = peaches_background_defaults.edge_softness_min,
        edge_softness_max = peaches_background_defaults.edge_softness_max,
        colorTint = copy_vec3(peaches_background_defaults.colorTint),
        blob_color_blend = peaches_background_defaults.blob_color_blend,
        hue_shift = peaches_background_defaults.hue_shift,
        pixel_size = peaches_background_defaults.pixel_size,
        pixel_enable = peaches_background_defaults.pixel_enable,
        blob_offset = copy_vec2(peaches_background_defaults.blob_offset),
        movement_randomness = peaches_background_defaults.movement_randomness
    }

    return true
end

local function tween_peaches_scalar(name, target, duration, tag_suffix)
    if target == nil then return end
    timer.tween_scalar(
        duration,
        function() return globalShaderUniforms:get("peaches_background", name) end,
        function(v) globalShaderUniforms:set("peaches_background", name, v) end,
        target,
        Easing.inOutQuad.f,
        nil,
        "peaches_bg_" .. name .. (tag_suffix or "")
    )
end

local function tween_peaches_vec2(name, target, duration, tag_suffix)
    if not target then return end
    local baseTag = "peaches_bg_" .. name .. (tag_suffix or "")

    timer.tween_scalar(
        duration,
        function()
            local current = globalShaderUniforms:get("peaches_background", name)
            return current and current.x or 0
        end,
        function(v)
            local current = globalShaderUniforms:get("peaches_background", name)
            local y = (current and current.y) or target.y or 0
            globalShaderUniforms:set("peaches_background", name, make_vec2(v, y))
        end,
        target.x,
        Easing.inOutQuad.f,
        nil,
        baseTag .. "_x"
    )

    timer.tween_scalar(
        duration,
        function()
            local current = globalShaderUniforms:get("peaches_background", name)
            return current and current.y or 0
        end,
        function(v)
            local current = globalShaderUniforms:get("peaches_background", name)
            local x = (current and current.x) or target.x or 0
            globalShaderUniforms:set("peaches_background", name, make_vec2(x, v))
        end,
        target.y,
        Easing.inOutQuad.f,
        nil,
        baseTag .. "_y"
    )
end

local function tween_peaches_vec3(name, target, duration, tag_suffix)
    if not target then return end
    local baseTag = "peaches_bg_" .. name .. (tag_suffix or "")

    timer.tween_scalar(
        duration,
        function()
            local current = globalShaderUniforms:get("peaches_background", name)
            return current and current.x or 0
        end,
        function(v)
            local current = globalShaderUniforms:get("peaches_background", name)
            local y = (current and current.y) or target.y or 0
            local z = (current and current.z) or target.z or 0
            globalShaderUniforms:set("peaches_background", name, make_vec3(v, y, z))
        end,
        target.x,
        Easing.inOutQuad.f,
        nil,
        baseTag .. "_x"
    )

    timer.tween_scalar(
        duration,
        function()
            local current = globalShaderUniforms:get("peaches_background", name)
            return current and current.y or 0
        end,
        function(v)
            local current = globalShaderUniforms:get("peaches_background", name)
            local x = (current and current.x) or target.x or 0
            local z = (current and current.z) or target.z or 0
            globalShaderUniforms:set("peaches_background", name, make_vec3(x, v, z))
        end,
        target.y,
        Easing.inOutQuad.f,
        nil,
        baseTag .. "_y"
    )

    timer.tween_scalar(
        duration,
        function()
            local current = globalShaderUniforms:get("peaches_background", name)
            return current and current.z or 0
        end,
        function(v)
            local current = globalShaderUniforms:get("peaches_background", name)
            local x = (current and current.x) or target.x or 0
            local y = (current and current.y) or target.y or 0
            globalShaderUniforms:set("peaches_background", name, make_vec3(x, y, v))
        end,
        target.z,
        Easing.inOutQuad.f,
        nil,
        baseTag .. "_z"
    )
end

local function tween_peaches_background(targets, duration)
    if not targets or not ensure_peaches_defaults() then
        return
    end

    local dur = duration or 1.0
    tween_peaches_scalar("blob_count", targets.blob_count, dur)
    tween_peaches_scalar("blob_spacing", targets.blob_spacing, dur)
    tween_peaches_scalar("shape_amplitude", targets.shape_amplitude, dur)
    tween_peaches_scalar("distortion_strength", targets.distortion_strength, dur)
    tween_peaches_scalar("noise_strength", targets.noise_strength, dur)
    tween_peaches_scalar("radial_falloff", targets.radial_falloff, dur)
    tween_peaches_scalar("wave_strength", targets.wave_strength, dur)
    tween_peaches_scalar("highlight_gain", targets.highlight_gain, dur)
    tween_peaches_scalar("cl_shift", targets.cl_shift, dur)
    tween_peaches_scalar("edge_softness_min", targets.edge_softness_min, dur)
    tween_peaches_scalar("edge_softness_max", targets.edge_softness_max, dur)
    tween_peaches_vec3("colorTint", targets.colorTint, dur)
    tween_peaches_scalar("blob_color_blend", targets.blob_color_blend, dur)
    tween_peaches_scalar("hue_shift", targets.hue_shift, dur)
    tween_peaches_scalar("pixel_size", targets.pixel_size, dur)
    tween_peaches_scalar("pixel_enable", targets.pixel_enable, dur)
    tween_peaches_vec2("blob_offset", targets.blob_offset, dur)
    tween_peaches_scalar("movement_randomness", targets.movement_randomness, dur)
end

local function apply_peaches_background_phase(phase)
    if not globalShaderUniforms then
        return
    end
    if not ensure_peaches_defaults() then
        return
    end
    tween_peaches_background(peaches_background_targets[phase], 1.0)
end

local oily_water_bg = require("core.oily_water_background")

function startActionPhase()
    local previousState = is_state_active(PLANNING_STATE) and "PLANNING" or (is_state_active(SHOP_STATE) and "SHOP" or "default")

    print(string.format("[DEBUG ACTION] startActionPhase requested (planning=%s action=%s shop=%s)",
        tostring(is_state_active and is_state_active(PLANNING_STATE)),
        tostring(is_state_active and is_state_active(ACTION_STATE)),
        tostring(is_state_active and is_state_active(SHOP_STATE))))
    logBoardSetStatus("startActionPhase before clear")

    clear_states()
    if setPlanningPeekMode then
        setPlanningPeekMode(false)
    end

    remove_fullscreen_shader("planning_phase_sepia")

    -- Explicitly deactivate planning phase tooltip states
    if deactivate_state then
        deactivate_state(WAND_TOOLTIP_STATE)
        deactivate_state(CARD_TOOLTIP_STATE)
    end

    -- Clean up planning phase UI elements to prevent flicker
    ui_modules.CastExecutionGraphUI.clear()
    wandResourceBar.hide()

    if record_telemetry then
        local now = os.clock()
        if _G.current_phase and _G.phase_started_at then
            record_telemetry("phase_exit", {
                phase = _G.current_phase,
                duration_s = now - _G.phase_started_at,
                next_phase = "action",
                session_id = telemetry_session_id()
            })
        end
        _G.current_phase = "action"
        _G.phase_started_at = now
    end

    activate_state(ACTION_STATE)
    activate_state("default_state")
    signal.emit("game_state_changed", { previous = previousState, current = "SURVIVORS" })

    if is_state_active then
        print(string.format("[DEBUG ACTION] states after activation (planning=%s action=%s shop=%s)",
            tostring(is_state_active(PLANNING_STATE)),
            tostring(is_state_active(ACTION_STATE)),
            tostring(is_state_active(SHOP_STATE))))
    end

    add_layer_shader("sprites", "pixelate_image")

    setLowPassTarget(0.0)           -- low pass filter off

    input.set_context("gameplay")   -- set input context to action phase.
    print("[DEBUG ACTION] input context set to gameplay")

    PhysicsManager.enable_step("world", true)
    print("[DEBUG ACTION] physics enabled")

    -- Sync wand grid adapter to executor BEFORE combat starts
    -- This syncs the new grid-based loadout UI to WandExecutor
    local sync_ok, sync_err = pcall(function()
        if wandAdapter.anyDirty() then
            WandExecutor.cleanup()
            WandExecutor.init()
            local syncCount = wandAdapter.syncToExecutor(WandExecutor)
            print(string.format("[DEBUG ACTION] wandAdapter synced %d wands to executor", syncCount))
            return syncCount > 0
        end
        return false
    end)

    local gridSyncedWands = sync_ok and sync_err or false
    if not sync_ok then
        print("[DEBUG ACTION] wandAdapter.syncToExecutor error: " .. tostring(sync_err))
    end

    -- Fallback: load from legacy board_sets if grid adapter didn't sync any wands
    if not gridSyncedWands then
        local wand_ok, wand_err = pcall(loadWandsIntoExecutorFromBoards)
        if not wand_ok then
            print("[DEBUG ACTION] ERROR in loadWandsIntoExecutorFromBoards: " .. tostring(wand_err))
        else
            print("[DEBUG ACTION] wands loaded from board_sets (legacy fallback)")
        end
    end

    if WandExecutor and WandExecutor.activeWands then
        print(string.format("[DEBUG ACTION] WandExecutor summary (active=%d states=%d pending=%d)",
            countTableEntries(WandExecutor.activeWands),
            countTableEntries(WandExecutor.wandStates),
            countTableEntries(WandExecutor.pendingSubCasts)))
    end
    logBoardSetStatus("startActionPhase after wand load")
    
    local cast_ok, cast_err = pcall(function()
        ui_modules.CastBlockFlashUI.clear()  -- Clear before init to prevent duplicate items
        ui_modules.CastBlockFlashUI.init()
    end)
    if not cast_ok then
        print("[DEBUG ACTION] ERROR in CastBlockFlashUI: " .. tostring(cast_err))
    else
        print("[DEBUG ACTION] CastBlockFlashUI initialized")
    end
    
    local trigger_ok, trigger_err = pcall(function() ui_modules.TriggerStripUI.show() end)
    if not trigger_ok then
        print("[DEBUG ACTION] ERROR in ui_modules.TriggerStripUI.show: " .. tostring(trigger_err))
    else
        print("[DEBUG ACTION] TriggerStripUI shown")
    end

    playStateTransition()
    oily_water_bg.apply_phase("action")
    print("[DEBUG ACTION] phase transition complete")

    if record_telemetry then
        record_telemetry("phase_enter", { phase = "action", session_id = telemetry_session_id() })
    end

    -- fadeOutMusic("main-menu", 0.3)
    -- fadeOutMusic("shop-music", 0.3)
    -- fadeOutMusic("planning-music", 0.3)
    -- fadeInMusic("action-music", 0.6)


    -- debug
    print("States active:", is_state_active(PLANNING_STATE), is_state_active(ACTION_STATE), is_state_active(SHOP_STATE))

    -- Emit signal for systems that need to react to action phase
    signal.emit("action_phase_started")
    
    -- star particle timer

    local ok, Particles = pcall(require, "core.particles")
    if not ok then
        log_warn("[Stars] Failed to load particles module")
        return
    end

    local screenW = globals.screenWidth()
    local screenH = globals.screenHeight()
    
    local starLayers = {}
    local starStreams = {}
    
    local layerConfigs = {
        { z = -100, size = { 1, 2 }, alpha = 80,  count = 40,  pulse = { 0.3, 1.5, 3.0 } },
        { z = -90,  size = { 1, 3 }, alpha = 120, count = 35,  pulse = { 0.35, 2.0, 4.0 } },
        { z = -80,  size = { 2, 4 }, alpha = 180, count = 25,  pulse = { 0.4, 2.5, 5.0 } },
    }
    
    for i, cfg in ipairs(layerConfigs) do
        local starRecipe = Particles.define()
            :shape("circle")
            :size(cfg.size[1], cfg.size[2])
            :color(255, 255, 220, cfg.alpha)
            :lifespan(9.0, 12.0)
            :fade()
            :velocity(0, 0)
            :space("screen")
            :z(cfg.z)
            :pulse(cfg.pulse[1], cfg.pulse[2], cfg.pulse[3])
        
        starRecipe:burst(cfg.count):inRect(0, 0, screenW, screenH)
        
        local stream = starRecipe
            :burst(math.ceil(cfg.count / 20))
            :inRect(0, 0, screenW, screenH)
            :stream()
            :every(1.0)
        
        starStreams[i] = stream
    end
    
    timer.every(0.016, function()
        for _, stream in ipairs(starStreams) do
            stream:update(0.016)
        end
    end)
end

function startPlanningPhase()
    local previousState = is_state_active(ACTION_STATE) and "SURVIVORS" or (is_state_active(SHOP_STATE) and "SHOP" or "default")
	    clear_states()
	    if setPlanningPeekMode then
	        setPlanningPeekMode(false)
	    end
	    WandExecutor.cleanup()
	    entity_cache.clear()
	    ui_modules.CastBlockFlashUI.clear()
	    ui_modules.SubcastDebugUI.clear()
	    ui_modules.SubcastDebugUI.init()
	    ui_modules.TriggerStripUI.hide()
	    if StatusIndicatorSystem and StatusIndicatorSystem.cleanup then
	        StatusIndicatorSystem.cleanup()
	    end
	    if MarkSystem and MarkSystem.cleanup then
	        MarkSystem.cleanup()
	    end

    if record_telemetry then
        local now = os.clock()
        if _G.current_phase and _G.phase_started_at then
            record_telemetry("phase_exit", {
                phase = _G.current_phase,
                duration_s = now - _G.phase_started_at,
                next_phase = "planning",
                session_id = telemetry_session_id()
            })
        end
        _G.current_phase = "planning"
        _G.phase_started_at = now
    end

    activate_state(PLANNING_STATE)
    activate_state("default_state")
    activate_state(WAND_TOOLTIP_STATE)
    signal.emit("game_state_changed", { previous = previousState, current = "PLANNING" })

    -- DISABLED: planning phase sepia effect (uncomment to re-enable)
    -- add_fullscreen_shader("planning_phase_sepia")
    -- globalShaderUniforms:set("planning_phase_sepia", "u_phase_blend", 1.0)
    -- globalShaderUniforms:set("planning_phase_sepia", "u_intensity", 0.5)

    if board_sets and #board_sets > 0 then
        for index, boardSet in ipairs(board_sets) do
            toggleBoardSetVisibility(boardSet, index == current_board_set_index)
        end
    end

    if updateWandResourceBar then
        updateWandResourceBar()
    end
    wandResourceBar.show()

    remove_layer_shader("sprites", "pixelate_image")

    input.set_context("planning-phase") -- set input context to planning phase.

    PhysicsManager.enable_step("world", false)

    setLowPassTarget(1.0) -- low pass fileter on

    -- fadeOutMusic("planning-music", 0.3)
    -- fadeOutMusic("main-menu", 0.3)
    -- fadeOutMusic("action-music", 0.3)
    -- fadeOutMusic("shop-music", 0.3)
    -- fadeInMusic("planning-music", 0.6)

    -- Reset camera immediately to center to fix intermittent camera positioning bug
    local cam = camera.Get("world_camera")
    if cam then
        cam:SetActualTarget(globals.screenWidth() / 2, globals.screenHeight() / 2)
    end

    playStateTransition()
    oily_water_bg.apply_phase("planning")

    if record_telemetry then
        record_telemetry("phase_enter", { phase = "planning", session_id = telemetry_session_id() })
    end


    -- debug

    print("States active:", is_state_active(PLANNING_STATE), is_state_active(ACTION_STATE), is_state_active(SHOP_STATE))

    maybeAutoEnterActionPhase()
end

function startShopPhase()
    local previousState = is_state_active(ACTION_STATE) and "SURVIVORS" or (is_state_active(PLANNING_STATE) and "PLANNING" or "default")
    local preShopGold = globals.currency or 0
    local interestPreview = ShopSystem.calculateInterest(preShopGold)
    clear_states()
    if setPlanningPeekMode then
        setPlanningPeekMode(false)
    end
    WandExecutor.cleanup()
    if StatusIndicatorSystem and StatusIndicatorSystem.cleanup then
        StatusIndicatorSystem.cleanup()
    end
    if MarkSystem and MarkSystem.cleanup then
        MarkSystem.cleanup()
    end

    if record_telemetry then
        local now = os.clock()
        if _G.current_phase and _G.phase_started_at then
            record_telemetry("phase_exit", {
                phase = _G.current_phase,
                duration_s = now - _G.phase_started_at,
                next_phase = "shop",
                session_id = telemetry_session_id()
            })
        end
        _G.current_phase = "shop"
        _G.phase_started_at = now
    end

    activate_state(SHOP_STATE)
    activate_state("default_state")
    signal.emit("game_state_changed", { previous = previousState, current = "SHOP" })

    remove_layer_shader("sprites", "pixelate_image")

    PhysicsManager.enable_step("world", false)

    setLowPassTarget(1.0) -- low pass fileter on

    -- fadeOutMusic("main-menu", 0.3)
    -- fadeOutMusic("action-music", 0.3)
    -- fadeOutMusic("planning-music", 0.3)
    -- fadeInMusic("shop-music", 0.6)

    -- Reset camera immediately to center to fix intermittent camera positioning bug
    local cam = camera.Get("world_camera")
    if cam then
        cam:SetActualTarget(globals.screenWidth() / 2, globals.screenHeight() / 2)
    end

    transitionGoldInterest(1.35, preShopGold, interestPreview)
    oily_water_bg.apply_phase("shop")

    if record_telemetry then
        record_telemetry("phase_enter", { phase = "shop", session_id = telemetry_session_id() })
    end

    regenerateShopState()


    -- debug

    print("States active:", is_state_active(PLANNING_STATE), is_state_active(ACTION_STATE), is_state_active(SHOP_STATE))
end

local lastFrame = -1

-- Debug card spawner ---------------------------------------------------------
local cardSpawnerState = {
    built = false,
    target = "inventory",
    tested = {},
    untested = {}
}

local function rebuildCardSpawnerLists()
    local testedLookup = {}
    local testedIds = gameplay_cfg.TESTED_CARD_IDS or {}
    for _, id in ipairs(testedIds) do
        testedLookup[id] = true
    end

    cardSpawnerState.tested = {}
    cardSpawnerState.untested = {}

    local function push(def, source)
        if not def then return end
        local cid = def.id or def.card_id
        if not cid then return end
        local entry = {
            id = cid,
            name = def.name or def.test_label or cid,
            type = def.type or (source == "trigger" and "trigger") or def.category or "card",
            source = source
        }
        if testedLookup[cid] then
            table.insert(cardSpawnerState.tested, entry)
        else
            table.insert(cardSpawnerState.untested, entry)
        end
    end

    for _, def in pairs(WandEngine.card_defs or {}) do
        push(def, "card")
    end
    for _, def in pairs(WandEngine.trigger_card_defs or {}) do
        push(def, "trigger")
    end

    local function sortEntries(list)
        table.sort(list, function(a, b)
            return (a.name or a.id or "") < (b.name or b.id or "")
        end)
    end

    sortEntries(cardSpawnerState.tested)
    sortEntries(cardSpawnerState.untested)
    cardSpawnerState.built = true
end

-- NOTE: Legacy function updated for grid inventory (Phase 5)
-- Now returns "inventory" special value for grid inventory, or board ID for wand boards
local function resolveCardSpawnTarget(entry)
    if not entry then return nil end

    -- If target is explicitly "inventory", all card types go to inventory
    if cardSpawnerState.target == "inventory" then
        return "inventory"
    end

    -- Otherwise, route based on card type
    if entry.type == "trigger" then
        -- Triggers go to wand trigger board if target is "action" (wand boards)
        local set = board_sets and board_sets[current_board_set_index]
        if set and set.trigger_board_id and entity_cache.valid(set.trigger_board_id) then
            return set.trigger_board_id
        end
        -- Fallback to inventory if no wand board available
        return "inventory"
    else
        if cardSpawnerState.target == "action" then
            local set = board_sets and board_sets[current_board_set_index]
            if set and set.action_board_id and entity_cache.valid(set.action_board_id) then
                return set.action_board_id
            end
        end
        -- Fallback to grid inventory (Phase 5)
        return "inventory"  -- Special value indicating PlayerInventory
    end
end

local function spawnCardEntry(entry)
    if not entry or not entry.id then return end

    local target = resolveCardSpawnTarget(entry)
    if not target then
        print("[CardSpawner] No valid target for " .. tostring(entry.id))
        return
    end

    local eid
    if entry.type == "trigger" then
        eid = createNewTriggerSlotCard(entry.id, 0, 0, PLANNING_STATE)
    else
        eid = createNewCard(entry.id, 0, 0, PLANNING_STATE)
    end

    if not eid or eid == entt_null or not entity_cache.valid(eid) then
        print("[CardSpawner] Failed to spawn " .. tostring(entry.id))
        return
    end

    local script = getScriptTableFromEntityID(eid)
    if script then
        script.category = script.category or script.type or entry.type
        script.id = script.id or entry.id
        script.card_id = script.card_id or entry.id
        CardMetadata.enrich(script)
    end

    -- Handle "inventory" special value for grid inventory (Phase 5)
    if target == "inventory" then
        local PlayerInventory = require("ui.player_inventory")
        local category = getInventoryCategoryForCard(eid)
        PlayerInventory.addCard(eid, category)
    else
        addCardToBoard(eid, target)
    end
end

local function renderCardList(entries, childId)
    if not entries then return end
    ImGui.BeginChild(childId, 0, 240, true)
    for _, entry in ipairs(entries) do
        ImGui.PushID(entry.id)
        ImGui.Text(string.format("%s (%s)", entry.name or entry.id, entry.type or "card"))
        ImGui.SameLine()
        if ImGui.Button("Spawn##" .. entry.id) then
            spawnCardEntry(entry)
        end
        ImGui.PopID()
    end
    ImGui.EndChild()
end

local function renderCardSpawnerDebugUI()
    if not ImGui or not ImGui.Begin then return end
    if not cardSpawnerState.built then
        rebuildCardSpawnerLists()
    end

    if ImGui.Begin("Card Spawner (Debug)") then
        ImGui.Text("Drop target:")
        if ImGui.Button(cardSpawnerState.target == "inventory" and "[Inventory]" or "Inventory") then
            cardSpawnerState.target = "inventory"
        end
        ImGui.SameLine()
        if ImGui.Button(cardSpawnerState.target == "action" and "[Action Board]" or "Action Board") then
            cardSpawnerState.target = "action"
        end

        ImGui.Separator()
        ImGui.Text(string.format("Untested cards (%d)", #cardSpawnerState.untested))
        renderCardList(cardSpawnerState.untested, "untested_card_list")
        ImGui.Separator()
        ImGui.Text("Tested cards")
        if #cardSpawnerState.tested == 0 then
            ImGui.Text("None marked tested yet.")
        else
            renderCardList(cardSpawnerState.tested, "tested_card_list")
        end
    end
    ImGui.End()
end

local function setQuickAccessMessage(message)
    gameplay_cfg.debugQuickAccessState.lastMessage = message
end

local function shuffleList(list)
    if not list or #list < 2 then return end
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
end

local function getActiveActionBoard()
    if not board_sets or #board_sets == 0 then return nil end
    local set = board_sets[current_board_set_index]
    if not set or not set.action_board_id or not entity_cache.valid(set.action_board_id) then
        return nil
    end
    local board = boards[set.action_board_id]
    if not board then return nil end
    return board, set, set.action_board_id
end

relayoutBoardCardsInOrder = function(board)
    if not board or not board.cards or #board.cards == 0 then return end
    local boardTransform = component_cache.get(board:handle(), Transform)
    if not boardTransform then return end

    local cardW, cardH = 100, 140
    for _, cardEid in ipairs(board.cards) do
        if cardEid and entity_cache.valid(cardEid) then
            local t = component_cache.get(cardEid, Transform)
            if t and t.actualW and t.actualH and t.actualW > 0 and t.actualH > 0 then
                cardW, cardH = t.actualW, t.actualH
                break
            end
        end
    end

    local padding = 20
    local availW = math.max(0, boardTransform.actualW - padding * 2)
    local preferredGap = 24  -- Minimum comfortable gap between card edges
    local maxGap = 60        -- Maximum gap when spreading cards to fill space
    local minGap = 4         -- Minimum visible gap/offset when overlapping
    local n = #board.cards
    local spacing, groupW

    if n == 1 then
        spacing, groupW = 0, cardW
    else
        -- Calculate minimum layout (cards with preferred gap)
        local minGroupW = n * cardW + preferredGap * (n - 1)
        -- Calculate maximum layout (cards with max gap)
        local maxGroupW = n * cardW + maxGap * (n - 1)

        if minGroupW <= availW then
            -- Room for at least preferred separation
            if availW >= maxGroupW then
                -- Lots of room: use max gap (don't over-spread)
                spacing = cardW + maxGap
                groupW = maxGroupW
            else
                -- Spread cards to fill available space (between preferred and max gap)
                local expandedGap = (availW - n * cardW) / (n - 1)
                spacing = cardW + expandedGap
                groupW = availW
            end
        else
            -- Not enough room - need to compress
            -- First try: reduce gap while keeping cards separate (no overlap)
            local gapSpace = availW - n * cardW
            if gapSpace >= minGap * (n - 1) then
                -- Can fit with reduced gaps (no overlap)
                local reducedGap = gapSpace / (n - 1)
                spacing = cardW + reducedGap
                groupW = availW
            else
                -- Must overlap - use minimum visible offset
                local fitSpacing = (availW - cardW) / (n - 1)
                spacing = math.max(minGap, fitSpacing)
                groupW = cardW + spacing * (n - 1)
            end
        end
    end

    local startX = boardTransform.actualX + padding + (availW - groupW) * 0.5
    local centerY = boardTransform.actualY + boardTransform.actualH * 0.5

    board.z_order_cache_per_card = board.z_order_cache_per_card or {}

    for i, cardEid in ipairs(board.cards) do
        if cardEid and entity_cache.valid(cardEid) then
            local t = component_cache.get(cardEid, Transform)
            if t then
                t.actualX = math.floor(startX + (i - 1) * spacing + 0.5)
                t.actualY = math.floor(centerY - (t.actualH or cardH) * 0.5 + 0.5)
            end
            local zi = z_orders.card + (i - 1)
            board.z_order_cache_per_card[cardEid] = zi
            -- Skip z-index assignment if this card is being alt-previewed
            if cardEid ~= card_ui_state.alt_entity then
                layer_order_system.assignZIndexToEntity(cardEid, zi)
            end
        end
    end
end

local function shuffleActiveActionBoard()
    local actionBoard, _, boardId = getActiveActionBoard()
    if not actionBoard or not boardId then
        return false, "No active action board"
    end

    actionBoard.cards = actionBoard.cards or {}
    for i = #actionBoard.cards, 1, -1 do
        local eid = actionBoard.cards[i]
        if not eid or not entity_cache.valid(eid) then
            table.remove(actionBoard.cards, i)
        end
    end

    if #actionBoard.cards < 2 then
        return false, "Need at least 2 valid cards to shuffle"
    end

    shuffleList(actionBoard.cards)
    relayoutBoardCardsInOrder(actionBoard)
    notifyDeckChanged(boardId)
    return true, #actionBoard.cards
end

-- NOTE: Legacy function - inventory_board_id removed in Phase 5
-- Grid inventory uses WandLoadoutUI for equipping cards
local function moveRandomInventoryCardsToActiveActionBoard(count)
    log_debug("[moveRandomInventoryCardsToActiveActionBoard] Legacy function, returning false")
    return false, "Legacy inventory board removed - use WandLoadoutUI"
end

-- call every frame
function debugUI()
    -- open a window (returns shouldDraw)
    -- NOTE: ImGui.End() must ALWAYS be called after ImGui.Begin(), regardless of return value
    if ImGui.Begin("Quick access") then
        if ImGui.Button("Goto Planning Phase") then
            startPlanningPhase()
        end
        if ImGui.Button("Goto Action Phase") then
            startActionPhase()
        end
        if ImGui.Button("Goto Shop Phase") then
            startShopPhase()
        end
        if ImGui.Button("Next Board Set") then
            cycleBoardSets(1)
        end
        ImGui.Separator()
        ImGui.Text("Action board helpers")
        if ImGui.Button("Add 5 random inv -> action") then
            local ok, result = moveRandomInventoryCardsToActiveActionBoard(5)
            if ok then
                setQuickAccessMessage(string.format("Moved %d card(s) to action board", result or 0))
            else
                setQuickAccessMessage(result or "Failed to move cards")
            end
        end
        if ImGui.Button("Shuffle action board") then
            local ok, result = shuffleActiveActionBoard()
            if ok then
                setQuickAccessMessage(string.format("Shuffled %d card(s) on action board", result or 0))
            else
                setQuickAccessMessage(result or "Failed to shuffle cards")
            end
        end
if gameplay_cfg.debugQuickAccessState.lastMessage then
        ImGui.Text(gameplay_cfg.debugQuickAccessState.lastMessage)
        end
        ImGui.Separator()
        ImGui.Text("Debug Panels")
        if ImGui.Button("Toggle Entity Inspector") then
            ui_modules.EntityInspector.toggle()
        end
        if ImGui.Button("Toggle AI Inspector") then
            ui_modules.AIInspector.toggle()
        end
    end
    ImGui.End() -- Must be called even if Begin() returns false

    renderCardSpawnerDebugUI()

    -- Content Debug Panel (Jokers, Projectiles, Tags)
    if ui_modules.ContentDebugPanel and ui_modules.ContentDebugPanel.render then
        ui_modules.ContentDebugPanel.render()
    end

    -- Combat Debug Panel (Stats, Combat, Defense, etc.)
    if ui_modules.CombatDebugPanel and ui_modules.CombatDebugPanel.render then
        ui_modules.CombatDebugPanel.render()
    end

    -- UI Overlay Toggles (visibility controls for action mode overlays)
    if ui_modules.UIOverlayToggles and ui_modules.UIOverlayToggles.render then
        ui_modules.UIOverlayToggles.render()
    end

    -- Entity Inspector Panel (inspect entity components at runtime)
    if ui_modules.EntityInspector and ui_modules.EntityInspector.render then
        ui_modules.EntityInspector.render()
    end

    -- AI Inspector Panel (inspect GOAP AI entities and trace buffer)
    if ui_modules.AIInspector and ui_modules.AIInspector.render then
        ui_modules.AIInspector.render()
    end
end

cardsSoldInShop = {}



local function get_mag_items(world, player, radius)
    local t = component_cache.get(player, Transform)

    local pos = { x = t.actualX + t.actualW / 2, y = t.actualY + t.actualH / 2 }

    local x1 = pos.x - radius
    local y1 = pos.y - radius
    local x2 = pos.x + radius
    local y2 = pos.y + radius

    local candidates = physics.GetObjectsInArea(world, x1, y1, x2, y2)
    local result = {}

    for _, e in ipairs(candidates) do
        if entity_cache.valid(e) then
            local ipos = physics.GetPosition(world, e)
            local dx = ipos.x - pos.x
            local dy = ipos.y - pos.y
            if (dx * dx + dy * dy) <= radius * radius then
                table.insert(result, e)
            end
        end
    end

    return result
end

function createJointedMask(parentEntity, worldName)
    local world = PhysicsManager.get_world(worldName)

    -- Create mask entity with physics
    local maskEntity = animation_system.createAnimatedObjectWithTransform(
        "b6813.png",
        true
    )

    -- Position at parent's head
    local parentT = component_cache.get(parentEntity, Transform)
    local maskT = component_cache.get(maskEntity, Transform)

    local headOffsetY = -parentT.actualH * 0.3
    maskT.actualX = parentT.actualX + parentT.actualW / 2 - maskT.actualW / 2
    maskT.actualY = parentT.actualY + headOffsetY
    maskT.visualX = maskT.actualX
    maskT.visualY = maskT.actualY

    -- Give mask physics (dynamic body)
    physics.create_physics_for_transform(
        registry,
        physics_manager_instance,
        maskEntity,
        worldName,
        {
            shape = "rectangle",
            tag = "mask",
            sensor = true,
            density = 0.0 -- Light weight
        }
    )

    physics.SetBodyType(world, maskEntity, "dynamic")
    physics.SetMass(world, maskEntity, 0.01)

    -- Disable collision between mask and player
    -- physics.enable_trigger_between(world, "mask", "player")

    -- Option 1: PIVOT JOINT (simple hinge)
    -- Mask rotates freely around attachment point
    local pivotJoint = physics.add_pivot_joint_world(
        world,
        parentEntity,
        maskEntity,
        { x = maskT.actualX + maskT.actualW / 2, y = maskT.actualY + maskT.actualH / 2 } -- Attach at mask's initial position
    )

    physics.SetMoment(world, maskEntity, 0.01) -- Keep inertia tiny so it doesn't tug the player

    -- Make joint strong but allow some flex
    -- physics.set_constraint_limits(world, pivotJoint, 10000, nil)  -- maxForce

    -- Option 2: DAMPED SPRING (bouncy attachment)
    -- Uncomment to use instead of pivot:
    -- local spring = physics.add_damped_spring(
    --     world,
    --     parentEntity,
    --     {x = 0, y = headOffsetY},  -- Anchor on parent (local coords)
    --     maskEntity,
    --     {x = 0, y = 0},            -- Anchor on mask (center)
    --     0,                         -- Rest length (0 = tight)
    --     500,                       -- Stiffness
    --     10                         -- Damping
    -- )

    -- Option 3: SLIDE JOINT (constrained distance)
    -- Allows mask to slide within min/max range:
    -- local slideJoint = physics.add_slide_joint(
    --     world,
    --     parentEntity,
    --     {x = 0, y = headOffsetY},
    --     maskEntity,
    --     {x = 0, y = 0},
    --     0,     -- Min distance
    --     10     -- Max distance (can stretch up to 10 units)
    -- )

    -- Add rotary spring to keep mask mostly upright
    local rotarySpring = physics.add_damped_rotary_spring(
        world,
        parentEntity,
        maskEntity,
        0,    -- Rest angle (upright)
        6000, -- Stiffness (lower = more floppy)
        5     -- Damping
    )


    physics.set_sync_mode(registry, maskEntity, physics.PhysicsSyncMode.AuthoritativePhysics)

    -- don't know why this is necessary, but set the rotation of the transform to match physics body
    timer.run(
        function()
            if not entity_cache.valid(maskEntity) then return end

            local bodyAngle = physics.GetAngle(world, maskEntity)
            local t = component_cache.get(maskEntity, Transform)
            t.actualR = math.deg(bodyAngle)
        end
    )

    -- Add some angular damping for smoother rotation
    -- physics.SetDamping(world, maskEntity, 0.3)

    -- Layer above player
    layer_order_system.assignZIndexToEntity(maskEntity, z_orders.player_char + 1)

    return maskEntity
end

function initSurvivorEntity()
    local world = PhysicsManager.get_world("world")

    -- 3856-TheRoguelike_1_10_alpha_649.png
    survivorEntity = animation_system.createAnimatedObjectWithTransform(
        "survivor.png", -- animation ID
        true                                    -- use animation, not sprite identifier, if false
    )

    -- give survivor a script and hook up
    local SurvivorType = Node:extend()
    local survivorScript = SurvivorType {}
    -- TODO: add update method here if needed

    survivorScript:attach_ecs { create_new = false, existing_entity = survivorEntity }

    -- relocate to the center of the screen
    local survivorTransform = component_cache.get(survivorEntity, Transform)
    survivorTransform.actualX = globals.screenWidth() / 2
    survivorTransform.actualY = globals.screenHeight() / 2
    survivorTransform.visualX = survivorTransform.actualX
    survivorTransform.visualY = survivorTransform.actualY

    -- give survivor physics.
    local info = { shape = "rectangle", tag = C.CollisionTags.PLAYER, sensor = false, density = 1.0, inflate_px = -5 }
    physics.create_physics_for_transform(registry,
        physics_manager_instance,                                                                        -- global instance
        survivorEntity,                                                                                  -- entity id
        "world",                                                                                         -- physics world identifier
        info
    )

    -- make it collide with enemies & walls & pickups
    physics.enable_collision_between_many(world, C.CollisionTags.WORLD, { C.CollisionTags.PLAYER, C.CollisionTags.PROJECTILE, C.CollisionTags.ENEMY })
    physics.enable_collision_between_many(world, C.CollisionTags.PLAYER, { C.CollisionTags.WORLD })
    physics.enable_collision_between_many(world, C.CollisionTags.PROJECTILE, { C.CollisionTags.WORLD })
    -- physics.enable_collision_between_many(world, C.CollisionTags.ENEMY, { C.CollisionTags.WORLD })
    physics.enable_collision_between_many(world, C.CollisionTags.PICKUP, { C.CollisionTags.PLAYER })
    physics.enable_collision_between_many(world, C.CollisionTags.PLAYER, { C.CollisionTags.PICKUP })

    physics.update_collision_masks_for(world, C.CollisionTags.PLAYER, { C.CollisionTags.WORLD })
    physics.update_collision_masks_for(world, C.CollisionTags.ENEMY, { C.CollisionTags.WORLD })
    physics.update_collision_masks_for(world, C.CollisionTags.WORLD, { C.CollisionTags.PLAYER, C.CollisionTags.ENEMY })


    -- assign z level
    layer_order_system.assignZIndexToEntity(
        survivorEntity,
        z_orders.player_char
    )


    -- make walls after defining collision relationships
    local wallThickness = SCREEN_BOUND_THICKNESS or 30
    physics.add_screen_bounds(PhysicsManager.get_world("world"),
        SCREEN_BOUND_LEFT - wallThickness,
        SCREEN_BOUND_TOP - wallThickness,
        SCREEN_BOUND_RIGHT + wallThickness,
        SCREEN_BOUND_BOTTOM + wallThickness,
        wallThickness,
        C.CollisionTags.WORLD
    )

    -- make a timer that runs every frame when action state is active, to render the walls
    timer.run(
        function()
            -- bail if not in action state
            if not is_state_active(ACTION_STATE) then return end

            -- draw walls
            command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                c.x     = SCREEN_BOUND_LEFT + (SCREEN_BOUND_RIGHT - SCREEN_BOUND_LEFT) / 2
                c.y     = SCREEN_BOUND_TOP + (SCREEN_BOUND_BOTTOM - SCREEN_BOUND_TOP) / 2
                c.w     = SCREEN_BOUND_RIGHT - SCREEN_BOUND_LEFT
                c.h     = SCREEN_BOUND_BOTTOM - SCREEN_BOUND_TOP
                c.rx    = 30
                c.ry    = 30
                -- c.lineWidth = 10
                c.color = util.getColor("pink"):setAlpha(230)
            end, z_orders.background, layer.DrawCommandSpace.World)
        end
    )

    -- give player fixed rotation.
    physics.use_transform_fixed_rotation(registry, survivorEntity)

    -- give shader pipeline comp for later use
    local shaderPipelineComp = registry:emplace(survivorEntity, shader_pipeline.ShaderPipelineComponent)

    -- give mask (optional)
    if gameplay_cfg.ENABLE_SURVIVOR_MASK then
        survivorMaskEntity = createJointedMask(survivorEntity, "world")
    else
        survivorMaskEntity = nil
    end


    physics.enable_collision_between_many(world, C.CollisionTags.ENEMY, { C.CollisionTags.PLAYER, C.CollisionTags.ENEMY }) -- enemy>player and enemy>enemy
    physics.enable_collision_between_many(world, C.CollisionTags.PLAYER, { C.CollisionTags.ENEMY })          -- player>enemy
    physics.update_collision_masks_for(world, C.CollisionTags.PLAYER, { C.CollisionTags.ENEMY })
    physics.update_collision_masks_for(world, C.CollisionTags.ENEMY, { C.CollisionTags.PLAYER, C.CollisionTags.ENEMY })

    -- entity.set_draw_override(survivorEntity, function(w, h)
    --     -- immediate render version of the same thing.
    --     command_buffer.executeDrawGradientRectRoundedCentered(layers.sprites, function(c)
    --         local survivorT = component_cache.get(survivorEntity, Transform)

    --         c.cx = 0 -- self centered
    --         c.cy = 0
    --         c.width = w
    --         c.height = h
    --         c.roundness = 0.5
    --         c.segments = 8
    --         c.topLeft = util.getColor("apricot_cream")
    --         c.topRight = util.getColor("green")
    --         c.bottomRight = util.getColor("green")
    --         c.bottomLeft = util.getColor("apricot_cream")

    --         end, z_orders.projectiles + 1, layer.DrawCommandSpace.World)
    --     end, true) -- true disables sprite rendering


    -- player vs pickup collision
    physics.on_pair_begin(world, C.CollisionTags.PLAYER, C.CollisionTags.PICKUP, function(arb)
        log_debug("Survivor hit a pickup!")

        local a, b = arb:entities()

        local pickupEntity = nil
        if (a ~= survivorEntity) then
            pickupEntity = a
        else
            pickupEntity = b
        end

        -- remove a couple frames later
        timer.after(0.1, function()
            -- fire off signal
            signal.emit("on_pickup", pickupEntity)

            -- remove pickup entity
            if pickupEntity and entity_cache.valid(pickupEntity) then
                -- create a small particle effect at pickup location
                local pickupTransform = component_cache.get(pickupEntity, Transform)
                if pickupTransform then
                    particle.spawnRadialParticles(
                        pickupTransform.actualX + pickupTransform.actualW / 2,
                        pickupTransform.actualY + pickupTransform.actualH / 2,
                        20,                       -- count
                        0.4,                      -- base lifespan
                        {
                            lifetimeJitter = 0.5, -- ±50% lifetime variance
                            scaleJitter = 0.3,    -- ±30% scale variance
                            minScale = 3,
                            maxScale = 4,
                            scaleEasing = "cubic",
                            minSpeed = 100,
                            maxSpeed = 300,
                            colors = { util.getColor("RED") },
                            renderType = particle.ParticleRenderType.CIRCLE_FILLED,
                            easing = "cubic",
                            rotationSpeed = 90,   -- degrees/sec
                            rotationJitter = 0.5, -- ±50% variance
                            space = "world",
                            z = 0,
                        }
                    )
                end

                registry:destroy(pickupEntity)
            end
        end)
    end)

    -- test
    -- local shaderPipelineComp = component_cache.get(survivorEntity, shader_pipeline.ShaderPipelineComponent)
    -- shaderPipelineComp:addPass("vacuum_collapse")


    -- give survivor collision callback, namely begin.
    -- modifying a file.
    physics.on_pair_begin(world, C.CollisionTags.PLAYER, C.CollisionTags.ENEMY, function(arb)
        log_debug("Survivor hit an enemy!")

        -- ascertain the enemy entity, only on first contact
        if arb:is_first_contact() then
            local a, b = arb:entities()

            local enemyEntity = nil
            if (a ~= survivorEntity) then
                enemyEntity = a
            else
                enemyEntity = b
            end

            local bumpPosition = nil
            if enemyEntity and component_cache then
                local t = component_cache.get(enemyEntity, Transform)
                if t then
                    bumpPosition = { x = t.actualX + t.actualW * 0.5, y = t.actualY + t.actualH * 0.5 }
                end
            end
            signal.emit("on_bump_enemy", enemyEntity, {
                position = bumpPosition,
                entity = enemyEntity
            })
        end

        hitFX(survivorEntity, 10, 0.2)


        -- play sound
        playSoundEffect("effects", "player_hurt", 0.9 + math.random() * 0.2)

        -- DISABLED: time slow and music silencing effects
        -- playSoundEffect("effects", "time_slow", 0.9 + math.random() * 0.2)
        -- setLowPassTarget(1.0)
        -- slowTime(1.5, 0.1)
        -- timer.after(1.0, function()
        --     setLowPassTarget(0.0)
        -- end)

        -- TODO: make player take damage, play hit effect, etc.

        -- local shaderPipelineComp = component_cache.get(survivorEntity, shader_pipeline.ShaderPipelineComponent)
        -- shaderPipelineComp:addPass("flash")

        -- shake camera
        local cam = camera.Get("world_camera")
        if cam then
            cam:Shake(15.0, 0.5, 60)
        end

        -- -- remove after a short delay
        -- timer.after(1.0, function()
        --     local shaderPipelineComp = component_cache.get(survivorEntity, shader_pipeline.ShaderPipelineComponent)
        --     if shaderPipelineComp then
        --         shaderPipelineComp:removePass("flash")
        --     end
        -- end)

        -- set abberation
        globalShaderUniforms:set("crt", "aberation_amount", 10)
        -- set to 0 after 0.5 seconds
        timer.after(0.15, function()
            globalShaderUniforms:set("crt", "aberation_amount", 0)
        end)

        -- tween up noise, then back down
        timer.tween_scalar(
            0.1,                                                                   -- duration in seconds
            function() return globalShaderUniforms:get("crt", "noise_amount") end, -- getter
            function(v) globalShaderUniforms:set("crt", "noise_amount", v) end,    -- setter
            0.7                                                                    -- target value
        )
        timer.after(0.1, function()
            timer.tween_scalar(
                0.1,                                                                   -- duration in seconds
                function() return globalShaderUniforms:get("crt", "noise_amount") end, -- getter
                function(v) globalShaderUniforms:set("crt", "noise_amount", v) end,    -- setter
                0                                                                      -- target value
            )
        end)

        return false -- reject collision
    end)


    -- allow transform manipuation to alter physics body
    physics.set_sync_mode(registry, survivorEntity, physics.PhysicsSyncMode.AuthoritativePhysics)

    physics.SetBodyType(PhysicsManager.get_world("world"), survivorEntity, "dynamic")

    -- give a state tag to the survivor entity
    add_state_tag(survivorEntity, ACTION_STATE)
    -- remove default
    remove_default_state_tag(survivorEntity)



    -- lets move the survivor based on input.
    input.bind("survivor_left",
        { device = "keyboard", key = KeyboardKey.KEY_A, trigger = "Pressed", context = "gameplay" })
    input.bind("survivor_right", {
        device = "keyboard",
        key = KeyboardKey.KEY_D,
        trigger = "Pressed",
        context =
        "gameplay"
    })
    input.bind("survivor_up", { device = "keyboard", key = KeyboardKey.KEY_W, trigger = "Pressed", context = "gameplay" })
    input.bind("survivor_down",
        { device = "keyboard", key = KeyboardKey.KEY_S, trigger = "Pressed", context = "gameplay" })
    input.bind("survivor_dash", {
        device = "keyboard",
        key = KeyboardKey.KEY_SPACE,
        trigger = "Pressed",
        context =
        "gameplay"
    })
    input.bind("toggle_auto_aim", {
        device = "keyboard",
        key = KeyboardKey.KEY_P,
        trigger = "Pressed",
        context = "gameplay"
    })

    for _, ctx in ipairs({ "gameplay", "planning-phase" }) do
        input.bind("toggle_stats_panel", { device = "keyboard", key = KeyboardKey.KEY_C, trigger = "Pressed", context = ctx })
        input.bind("stats_panel_close", { device = "keyboard", key = KeyboardKey.KEY_ESCAPE, trigger = "Pressed", context = ctx })
        input.bind("stats_panel_tab_1", { device = "keyboard", key = KeyboardKey.KEY_ONE, trigger = "Pressed", context = ctx })
        input.bind("stats_panel_tab_2", { device = "keyboard", key = KeyboardKey.KEY_TWO, trigger = "Pressed", context = ctx })
        input.bind("stats_panel_tab_3", { device = "keyboard", key = KeyboardKey.KEY_THREE, trigger = "Pressed", context = ctx })
        input.bind("stats_panel_tab_4", { device = "keyboard", key = KeyboardKey.KEY_FOUR, trigger = "Pressed", context = ctx })
        input.bind("stats_panel_tab_5", { device = "keyboard", key = KeyboardKey.KEY_FIVE, trigger = "Pressed", context = ctx })
    end

    --also allow gamepad.
    -- same dash
    input.bind("survivor_dash", {
        device = "gamepad_button",
        axis = GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_DOWN, -- A button
        trigger = "Pressed",                                 -- or "Threshold" if your system uses analog triggers
        context = "gameplay"
    })
    input.bind("toggle_auto_aim", {
        device = "gamepad_button",
        axis = GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_UP, -- Y button
        trigger = "Pressed",
        context = "gameplay"
    })

    -- Horizontal movement (Left stick X)
    input.bind("gamepad_move_x", {
        device = "gamepad_axis",
        axis = GamepadAxis.GAMEPAD_AXIS_LEFT_X,
        trigger = "AxisPos", -- or "Threshold" if your system uses analog triggers
        threshold = 0.2,     -- deadzone threshold
        context = "gameplay"
    })
    input.bind("gamepad_move_x", {
        device = "gamepad_axis",
        axis = GamepadAxis.GAMEPAD_AXIS_LEFT_X,
        trigger = "AxisNeg", -- or "Threshold" if your system uses analog triggers
        threshold = 0.2,     -- deadzone threshold
        context = "gameplay"
    })

    -- Vertical movement (Left stick Y)
    input.bind("gamepad_move_y", {
        device = "gamepad_axis",
        axis = GamepadAxis.GAMEPAD_AXIS_LEFT_Y,
        trigger = "AxisPos",
        threshold = 0.2,
        context = "gameplay"
    })
    input.bind("gamepad_move_y", {
        device = "gamepad_axis",
        axis = GamepadAxis.GAMEPAD_AXIS_LEFT_Y,
        trigger = "AxisNeg",
        threshold = 0.2,
        context = "gameplay"
    })

    -- Register pickup/level handlers once (guarded to prevent accumulation on restart)
    if not gameplay_cfg.pickupHandlersRegistered then
        gameplay_cfg.pickupHandlersRegistered = true
        local handlers = initGameplayHandlers()

        handlers:on("player_level_up", function()
            log_debug("Player leveled up!")
            playSoundEffect("effects", "level_up", 1.0)
            local playerScript = getScriptTableFromEntityID(survivorEntity)
            timer.after(gameplay_cfg.LEVEL_UP_MODAL_DELAY, function()
                ui_modules.LevelUpScreen.push({
                    playerEntity = survivorEntity,
                    actor = playerScript and playerScript.combatTable
                })
            end, "level_up_modal_delay")
        end)

        handlers:on("on_pickup", function(pickupEntity)
            log_debug("Survivor picked up entity", pickupEntity)

            local playerScript = getScriptTableFromEntityID(survivorEntity)

            if not playerScript or not playerScript.combatTable then
                log_debug("No combat table on player, cannot grant exp!")
                return
            end

            playSoundEffect("effects", "gain_exp_pickup", 1.0)

            CombatSystem.Game.Leveling.grant_exp(combat_context, playerScript.combatTable, 50) -- grant 20 exp per pickup

            -- tug the exp bar spring
            if expBarScaleSpringEntity and entity_cache.valid(expBarScaleSpringEntity) then
                local expBarSpringRef = spring.get(registry, expBarScaleSpringEntity)
                if expBarSpringRef then
                    expBarSpringRef:pull(0.15, 120.0, 14.0)
                end
            end

            local playerT = component_cache.get(survivorEntity, Transform)
            if playerT then
                playerT.visualS = 1.5
            end
        end)
    end


    -- lets run every physics frame, detecting for magnet radus
    timer.every_physics_step(
        function()
            if isLevelUpModalActive() then return end
            local magnetRadius = 200 -- TODO; make this a player stat later.
            local magItems = get_mag_items(PhysicsManager.get_world("world"), survivorEntity, magnetRadius)

            -- iterate
            for _, itemEntity in ipairs(magItems) do
                if entity_cache.valid(itemEntity) then
                    -- get script
                    local itemScript = getScriptTableFromEntityID(itemEntity)
                    if itemScript and itemScript.isPickup and not itemScript.pickedUp then
                        -- enable steering towards player
                        steering.make_steerable(registry, itemEntity, 10000.0, 15000.0, math.pi * 2.0, 10)


                        -- add a timer to move towards player
                        timer.every_physics_step(
                            function()
                                if isLevelUpModalActive() then return end
                                if entity_cache.valid(itemEntity) and entity_cache.valid(survivorEntity) then
                                    local playerT = component_cache.get(survivorEntity, Transform)

                                    -- steering.seek_point(registry, enemyEntity, playerLocation, 1.0, 0.5)

                                    steering.seek_point(registry, itemEntity,
                                        {
                                            x = playerT.actualX + playerT.actualW / 2,
                                            y = playerT.actualY + playerT.actualH / 2
                                        }, 0.1, 60)
                                else
                                    -- cancel timer, entity no longer valid
                                    timer.cancel("player_magnet_steering_" .. tostring(itemEntity))
                                end
                            end,
                            "player_magnet_steering_" .. tostring(itemEntity),
                            nil
                        )

                        itemScript.pickedUp = true -- mark as picked up to avoid double processing
                    end
                end
            end
        end,
        "player_magnet_detection", nil
    )

end

function ensureShopSystemInitialized()
    if shop_system_initialized then
        return
    end
    CardMetadata.registerAllWithShop(ShopSystem)
    ShopSystem.init()
    shop_system_initialized = true
end

local function refreshShopUIFromInstance(shop)
    if globals.ui and globals.ui.refreshShopUIFromInstance then
        globals.ui.refreshShopUIFromInstance(shop or active_shop_instance)
    end
end

-- NOTE: Updated for grid inventory (Phase 5) - legacy inventory_board_id removed
local function addPurchasedCardToInventory(cardInstance)
    if not cardInstance then return end
    local cardId = cardInstance.id or cardInstance.card_id or cardInstance.cardID
    if not cardId then return end

    -- Create card offscreen (grid inventory doesn't need visible spawn position)
    local eid = createNewCard(cardId, -500, -500, PLANNING_STATE)
    local script = getScriptTableFromEntityID(eid)
    if script then
        script.selected = false
    end

    -- Add to grid inventory instead of legacy board
    local PlayerInventory = require("ui.player_inventory")
    local category = getInventoryCategoryForCard(eid)
    PlayerInventory.addCard(eid, category)
    return eid
end

-- NOTE: Updated for grid inventory (Phase 5) - legacy inventory boards removed
-- Now only collects wand board entities (board_sets still used for wand boards)
local function collectPlanningPeekTargets()
    local targets = {}
    local function add(eid)
        if ensure_entity(eid) then
            table.insert(targets, eid)
        end
    end

    -- Legacy inventory boards removed - grid inventory is screen-space UI

    -- Wand boards (action/trigger) are still world-space
    if board_sets then
        for _, set in ipairs(board_sets) do
            add(set.trigger_board_id)
            add(set.action_board_id)
            local trigBoard = set.trigger_board_id and boards[set.trigger_board_id]
            if trigBoard and trigBoard.textEntity then add(trigBoard.textEntity) end
            local actBoard = set.action_board_id and boards[set.action_board_id]
            if actBoard and actBoard.textEntity then add(actBoard.textEntity) end
        end
    end

    return targets
end

-- Shop UI functions removed (setPlanningPeekMode, togglePlanningPeek, formatShopLabel, populateShopBoard)

function regenerateShopState()
    ensureShopSystemInitialized()
    ShopSystem.initUI()

    local playerLevel = (globals.shopState and globals.shopState.playerLevel) or 1
    local player = {
        gold = globals.currency or 0,
        cards = (globals.shopState and globals.shopState.cards) or {}
    }

    local interestEarned = ShopSystem.applyInterest(player)
    globals.currency = player.gold

    active_shop_instance = ShopSystem.generateShop(playerLevel, player.gold)
    globals.shopState = globals.shopState or {}
    globals.shopState.instance = active_shop_instance
    globals.shopState.lastInterest = interestEarned
    globals.shopState.playerLevel = playerLevel
    globals.shopState.cards = player.cards

    globals.shopUIState.rerollCost = active_shop_instance.rerollCost
    globals.shopUIState.rerollCount = active_shop_instance.rerollCount

    setShopLocked(false)

    -- populateShopBoard removed - rebuild shop UI handles this
end

function rerollActiveShop()
    if not active_shop_instance then
        return false
    end

    local player = {
        gold = globals.currency or 0,
        cards = (globals.shopState and globals.shopState.cards) or {}
    }

    local success = ShopSystem.rerollOfferings(active_shop_instance, player)
    if not success then
        return false
    end

    globals.currency = player.gold
    globals.shopState.cards = player.cards
    globals.shopUIState.rerollCost = active_shop_instance.rerollCost
    globals.shopUIState.rerollCount = active_shop_instance.rerollCount

    -- populateShopBoard(active_shop_instance) -- Removed: rebuild shop UI handles this
    return true
end

tryPurchaseShopCard = function(cardScript)
    if not cardScript or not cardScript.shop_slot or not active_shop_instance then
        return false
    end

    globals.shopState = globals.shopState or {}
    local offering = active_shop_instance.offerings[cardScript.shop_slot]
    if not offering or offering.isEmpty then
        return false
    end

    local player = {
        gold = globals.currency or 0,
        cards = (globals.shopState and globals.shopState.cards) or {}
    }

    local success, cardInstance = ShopSystem.purchaseCard(active_shop_instance, cardScript.shop_slot, player)
    if not success then
        playSoundEffect("effects", "cannot-buy")
        newTextPopup(
            "Need more gold",
            globals.screenWidth() * 0.5,
            globals.screenHeight() * 0.4,
            1.4,
            "color=fiery_red"
        )
        return false
    end

    globals.currency = player.gold
    globals.shopState.cards = player.cards
    globals.shopState.instance = active_shop_instance

    addPurchasedCardToInventory(cardInstance)

    playSoundEffect("effects", "shop-buy", 1.0)
    newTextPopup(
        string.format("Bought %s", cardInstance.id or cardInstance.card_id or "card"),
        globals.screenWidth() * 0.5,
        globals.screenHeight() * 0.36,
        1.6,
        "color=marigold"
    )

    -- populateShopBoard(active_shop_instance) -- Removed: rebuild shop UI handles this
    refreshShopUIFromInstance(active_shop_instance)

    -- Notify systems that deck has changed (triggers tag re-evaluation)
    signal.emit("deck_changed", { source = "shop_purchase" })

    return true
end

function tryPurchaseAvatar(avatarId)
    if not avatarId then
        return false
    end

    globals.shopState = globals.shopState or {}
    globals.shopState.avatarPurchases = globals.shopState.avatarPurchases or {}

    local playerTarget = getTagEvaluationTargets and select(1, getTagEvaluationTargets()) or nil
    if not playerTarget then
        return false
    end

    AvatarSystem.check_unlocks(playerTarget, { tag_counts = playerTarget.tag_counts })
    local unlocked = playerTarget.avatar_state and playerTarget.avatar_state.unlocked
        and playerTarget.avatar_state.unlocked[avatarId]
    if not unlocked then
        newTextPopup(
            "Avatar not unlocked yet",
            globals.screenWidth() * 0.72,
            globals.screenHeight() * 0.3,
            1.4,
            "color=fiery_red"
        )
        playSoundEffect("effects", "cannot-buy")
        return false
    end

    if globals.shopState.avatarPurchases[avatarId] then
        newTextPopup(
            "Already purchased",
            globals.screenWidth() * 0.72,
            globals.screenHeight() * 0.3,
            1.2,
            "color=apricot_cream"
        )
        return false
    end

    if (globals.currency or 0) < AVATAR_PURCHASE_COST then
        playSoundEffect("effects", "cannot-buy")
        newTextPopup(
            string.format("Need %dg", AVATAR_PURCHASE_COST),
            globals.screenWidth() * 0.72,
            globals.screenHeight() * 0.3,
            1.4,
            "color=fiery_red"
        )
        return false
    end

    globals.currency = (globals.currency or 0) - AVATAR_PURCHASE_COST
    globals.shopState.avatarPurchases[avatarId] = true
    AvatarSystem.equip(playerTarget, avatarId)

    if ui_modules.AvatarJokerStrip and ui_modules.AvatarJokerStrip.syncFrom then
        ui_modules.AvatarJokerStrip.syncFrom(playerTarget)
    end

    playSoundEffect("effects", "shop-buy")
    newTextPopup(
        string.format("Avatar unlocked: %s", avatarId),
        globals.screenWidth() * 0.72,
        globals.screenHeight() * 0.3,
        1.6,
        "color=marigold"
    )

    refreshShopUIFromInstance(active_shop_instance)
    return true
end

local function buildAvatarOverlayEntries()
    local entries = {}
    local defs = require("data.avatars")
    local purchases = (globals.shopState and globals.shopState.avatarPurchases) or {}
    local playerTarget = getTagEvaluationTargets and select(1, getTagEvaluationTargets()) or nil
    if playerTarget then
        AvatarSystem.check_unlocks(playerTarget, { tag_counts = playerTarget.tag_counts })
    end

    for id, def in pairs(defs or {}) do
        entries[#entries + 1] = {
            id = id,
            name = def.name or id,
            unlocked = playerTarget and playerTarget.avatar_state and playerTarget.avatar_state.unlocked
                and playerTarget.avatar_state.unlocked[id],
            purchased = purchases[id]
        }
    end

    table.sort(entries, function(a, b) return (a.name or a.id) < (b.name or b.id) end)
    return entries
end

-- Shop overlay UI removed - rebuild from scratch

function setShopLocked(locked)
    globals.shopUIState.locked = locked

    if active_shop_instance then
        for i = 1, #active_shop_instance.offerings do
            if active_shop_instance.locks[i] ~= locked then
                if locked then
                    ShopSystem.lockOffering(active_shop_instance, i)
                else
                    ShopSystem.unlockOffering(active_shop_instance, i)
                end
            end
        end
    end

    if globals.ui and globals.ui.setLockIconsVisible then
        globals.ui.setLockIconsVisible(globals.shopUIState.locked)
    end
end

-- Shop overlay draw timer removed - rebuild from scratch

function getActiveShop()
    return active_shop_instance
end

function initShopPhase()
    ensureShopSystemInitialized()
    -- let's make a large board for shopping
    local shopBoardID = createNewBoard(100, 100, 800, 400)
    shop_board_id = shopBoardID
    local shopBoard = boards[shopBoardID]
    shopBoard.borderColor = util.getColor("apricot_cream")

    -- give a text label above the board
    shopBoard.textEntity = ui.definitions.getNewDynamicTextEntry(
        function() return localization.get("ui.shop_area") end, -- initial text
        20.0,                                                   -- font size
        "color=apricot_cream"                                   -- animation spec
    ).config.object

    -- make the text world space
    transform.set_space(shopBoard.textEntity, "world")
    -- let's anchor to top of the trigger board
    transform.AssignRole(registry, shopBoard.textEntity, InheritedPropertiesType.PermanentAttachment, shopBoard:handle(),
        InheritedPropertiesSync.Strong,
        InheritedPropertiesSync.Weak,
        InheritedPropertiesSync.Strong,
        InheritedPropertiesSync.Weak,
        Vec2(0, -10) -- offset it a bit upwards
    );
    local roleComp = component_cache.get(shopBoard.textEntity, InheritedProperties)
    roleComp.flags = AlignmentFlag.VERTICAL_TOP

    -- give the text & board state
    clear_state_tags(shopBoard.textEntity)
    clear_state_tags(shopBoard:handle())
    add_state_tag(shopBoard.textEntity, SHOP_STATE)
    add_state_tag(shopBoard:handle(), SHOP_STATE)

    -- let's add a (buy) board below.
    local buyBoardID = createNewBoard(100, 550, 800, 150)
    shop_buy_board_id = buyBoardID
    local buyBoard = boards[buyBoardID]
    buyBoard.borderColor = util.getColor("green")
    buyBoard.textEntity = ui.definitions.getNewDynamicTextEntry(
        function() return localization.get("ui.buy_area") end, -- initial text
        20.0,                                                  -- font size
        "color=green"                                          -- animation spec
    ).config.object
    -- make the text world space
    transform.set_space(buyBoard.textEntity, "world")
    -- let's anchor to top of the trigger board
    transform.AssignRole(registry, buyBoard.textEntity, InheritedPropertiesType.PermanentAttachment, buyBoard:handle(),
        InheritedPropertiesSync.Strong,
        InheritedPropertiesSync.Weak,
        InheritedPropertiesSync.Strong,
        InheritedPropertiesSync.Weak,
        Vec2(0, -10) -- offset it a bit upwards
    );
    local roleComp = component_cache.get(buyBoard.textEntity, InheritedProperties)
    roleComp.flags = AlignmentFlag.VERTICAL_TOP
    -- give the text & board state
    clear_state_tags(buyBoard.textEntity)
    clear_state_tags(buyBoard:handle())
    add_state_tag(buyBoard.textEntity, SHOP_STATE)
    add_state_tag(buyBoard:handle(), SHOP_STATE)

    buyBoard.cards = {} -- cards are entity ids.

    -- add a different onRelease method
    local buyBoardGameObject = component_cache.get(buyBoard:handle(), GameObject)
    if buyBoardGameObject then
        buyBoardGameObject.methods.onRelease = function(registry, releasedOn, released)
            log_debug("Entity", released, "released on", releasedOn)
            -- when released on top of the buy board, if it's a card in the shop, move it to the buy board.
            -- is the released entity a card?
            local releasedCardScript = getScriptTableFromEntityID(released)
            if not releasedCardScript then return end

            --TODO: buy logic.
        end
    end
    
    local ShopPackUI = gameplay_cfg.getShopPackUI()
    if ShopPackUI then ShopPackUI.init() end
end

SCREEN_BOUND_LEFT = 0
SCREEN_BOUND_TOP = 0
SCREEN_BOUND_RIGHT = 1280
SCREEN_BOUND_BOTTOM = 720
SCREEN_BOUND_THICKNESS = 30

local function spawnWalkDust()
    -- Lightweight puff at the player's feet while walking
    local t = component_cache.get(survivorEntity, Transform)
    if not t then return end

    local jitterX = (math.random() - 0.5) * (t.actualW * 0.25)
    local baseX = t.actualX + t.actualW * 0.5 + jitterX
    local baseY = t.actualY + t.actualH - 6

    particle.spawnRadialParticles(baseX, baseY, 4, 0.35, {
        lifetimeJitter = 0.35,
        scaleJitter = 0.25,
        minScale = 2.0,
        maxScale = 4.0,
        minSpeed = 40,
        maxSpeed = 90,
        colors = { Col(200, 190, 170, 200) },
        renderType = particle.ParticleRenderType.CIRCLE_FILLED,
        easing = "cubic",
        gravity = 0,
        space = "world",
        z = z_orders.player_char - 1,
    })
end

-- location is top left of circle
local function makeSpawnMarkerCircle(x, y, radius, color, state)
    -- make circle marker for enemy appearance, tween it down to 0 scale and then remove it
    local SpawnMarkerType = Node:extend()
    local enemyX = x + radius / 2
    local enemyY = y + radius / 2
    function SpawnMarkerType:update(dt)
        command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
            c.x = enemyX
            c.y = enemyY
            c.w = 64 * self.scale
            c.h = 64 * self.scale
            c.rx = 32
            c.ry = 32
            c.color = color or Col(255, 255, 255, 255)
        end, z_orders.projectiles + 1, layer.DrawCommandSpace.World)
    end

    local spawnMarkerNode = SpawnMarkerType {}
    spawnMarkerNode.scale = 1.0

    spawnMarkerNode:attach_ecs { create_new = true }
    add_state_tag(spawnMarkerNode:handle(), state or ACTION_STATE)

    -- tween down
    -- local h5 = timer.tween(1.2, camera, { x = 320, y = 180, zoom = 1.25 }, nil, nil, "cam_move", "camera")
    timer.tween_fields(0.2, spawnMarkerNode, { scale = 0.0 }, nil, function()
        registry:destroy(spawnMarkerNode:handle())
    end)
end

function spawnExpPickupAt(x, y, opts)
    opts = opts or {}
    local spawnX = x or lume.random(SCREEN_BOUND_LEFT + 50, SCREEN_BOUND_RIGHT - 50)
    local spawnY = y or lume.random(SCREEN_BOUND_TOP + 50, SCREEN_BOUND_BOTTOM - 50)
    local world = PhysicsManager.get_world("world")

    if opts.playSound ~= false then
        playSoundEffect("effects", random_utils.random_element_string(EXP_PICKUP_SOUNDS), 0.9 + math.random() * 0.2)
    end

    local expPickupEntity = animation_system.createAnimatedObjectWithTransform(
        EXP_PICKUP_ANIMATION_ID,
        true
    )

    add_state_tag(expPickupEntity, opts.state or ACTION_STATE)
    remove_default_state_tag(expPickupEntity)

    local expPickupTransform = component_cache.get(expPickupEntity, Transform)
    if expPickupTransform then
        if opts.positionIsCenter then
            spawnX = spawnX - (expPickupTransform.actualW or 0) * 0.5
            spawnY = spawnY - (expPickupTransform.actualH or 0) * 0.5
        end

        expPickupTransform.actualX = spawnX
        expPickupTransform.actualY = spawnY
        expPickupTransform.visualX = spawnX
        expPickupTransform.visualY = spawnY
    end

    if opts.marker ~= false and expPickupTransform then
        makeSpawnMarkerCircle(
            expPickupTransform.actualX,
            expPickupTransform.actualY,
            expPickupTransform.actualW,
            util.getColor("red"),
            opts.state or ACTION_STATE
        )
    end

    local info = { shape = "rectangle", tag = C.CollisionTags.PICKUP, sensor = true, density = 1.0, inflate_px = 0 }

    physics.create_physics_for_transform(
        registry,
        physics_manager_instance,
        expPickupEntity,
        "world",
        info
    )

    if world then
        physics.enable_collision_between_many(world, C.CollisionTags.PICKUP, { C.CollisionTags.PLAYER })
        physics.enable_collision_between_many(world, C.CollisionTags.PLAYER, { C.CollisionTags.PICKUP })
        physics.update_collision_masks_for(world, C.CollisionTags.PICKUP, { C.CollisionTags.PLAYER })
        physics.update_collision_masks_for(world, C.CollisionTags.PLAYER, { C.CollisionTags.PICKUP })
    end

    local expPickupScript = Node {}
    expPickupScript:attach_ecs { create_new = false, existing_entity = expPickupEntity }
    expPickupScript.isPickup = true

    return expPickupEntity
end

function apply_player_projectile_recoil(angle, strength)
    if not angle then return end

    local magnitude = strength or PLAYER_PROJECTILE_RECOIL_STRENGTH
    local dx = math.cos(angle)
    local dy = math.sin(angle)
    if dx == 0 and dy == 0 then return end

    playerShotRecoil.x = playerShotRecoil.x - dx * magnitude
    playerShotRecoil.y = playerShotRecoil.y - dy * magnitude

    local maxKick = PLAYER_PROJECTILE_RECOIL_STRENGTH * 2
    local magSq = playerShotRecoil.x * playerShotRecoil.x + playerShotRecoil.y * playerShotRecoil.y
    if magSq > maxKick * maxKick then
        local mag = math.sqrt(magSq)
        playerShotRecoil.x = playerShotRecoil.x / mag * maxKick
        playerShotRecoil.y = playerShotRecoil.y / mag * maxKick
    end
end







function initActionPhase()
    
    ui_modules.LevelUpScreen.init()
    
    local CastFeedUI = require("ui.cast_feed_ui")
    if not ui_modules.MessageQueueUI.isActive then
        ui_modules.MessageQueueUI.init()
    end
    ensureMessageQueueHooks()
    if gameplay_cfg.DEBUG_AVATAR_TEST_EVENTS then
        fireAvatarDebugEvents()
    end

    -- Clamp the camera to the playable arena so its edges stay on screen.
    -- do
        local cam = camera.Get("world_camera")
        if cam then
            cam:SetBounds {
                x = SCREEN_BOUND_LEFT,
                y = SCREEN_BOUND_TOP,
                width = SCREEN_BOUND_RIGHT - SCREEN_BOUND_LEFT,
                height = SCREEN_BOUND_BOTTOM - SCREEN_BOUND_TOP
            }
            cam:SetBoundsPadding(10) -- small screen-space slack so camera can float while keeping arena visible
        end
    -- end

    -- Initialize CastFeedUI
    CastFeedUI.init()
    ui_modules.WandCooldownUI.init()
    ui_modules.SubcastDebugUI.init()
    ui_modules.TriggerStripUI.show()
    
    -- Demo polish UIs
    local DemoFooterUI = gameplay_cfg.getDemoFooterUI()
    if DemoFooterUI then DemoFooterUI.init() end
    
    local ManualTriggerPromptUI = gameplay_cfg.getManualTriggerPromptUI()
    if ManualTriggerPromptUI then ManualTriggerPromptUI.init() end
    
    -- add shader to backgorund layer
    add_layer_shader("background", "oily_water_background")
    -- add_layer_shader("background", "peaches_background")
    -- add_layer_shader("background", "fireworks")
    -- add_layer_shader("background", "starry_tunnel")
    -- add_layer_shader("background", "vacuum_collapse")
    -- add_fullscreen_shader("peaches_background")

    log_debug("Action phase started!")

    -- setUpScrollingBackgroundSprites()

    local world = PhysicsManager.get_world("world")
    world:AddCollisionTag(C.CollisionTags.SENSOR)
    world:AddCollisionTag(C.CollisionTags.PLAYER)
    world:AddCollisionTag(C.CollisionTags.BULLET)
    world:AddCollisionTag(C.CollisionTags.WORLD)
    world:AddCollisionTag("trap")  -- TODO: add to Constants if used
    world:AddCollisionTag(C.CollisionTags.ENEMY)
    world:AddCollisionTag("card")  -- TODO: add to Constants if used
    world:AddCollisionTag(C.CollisionTags.PICKUP) -- for items on ground
    world:AddCollisionTag(C.CollisionTags.PROJECTILE)
    world:AddCollisionTag("mask")  -- TODO: add to Constants if used

    initSurvivorEntity()

    physics.SetSleepTimeThreshold(world, 100000) -- time in seconds before body goes to sleep

    playerIsDashing = false
    playerDashCooldownRemaining = 0
    playerDashTimeRemaining = 0
    dashBufferTimer = 0
    bufferedDashDir = nil
    playerStaminaTickerTimer = 0
    -- Clear tables instead of replacing them (maintains global reference for enemy_factory.lua)
    for k in pairs(enemyHealthUiState) do enemyHealthUiState[k] = nil end
    for k in pairs(combatActorToEntity) do combatActorToEntity[k] = nil end
    damageNumbers = {}

    local DASH_END_TIMER_NAME = "dash_end_timer"
    local lastMoveInput = { x = 0, y = 0 }

    local function resolveDashDirection(baseDir)
        local dirX = (baseDir and baseDir.x) or 0
        local dirY = (baseDir and baseDir.y) or 0
        local len = math.sqrt(dirX * dirX + dirY * dirY)
        if len == 0 then
            local vel = physics.GetVelocity(world, survivorEntity)
            len = math.sqrt(vel.x * vel.x + vel.y * vel.y)
            if len > 0 then
                dirX = vel.x / len
                dirY = vel.y / len
            else
                dirX, dirY = 0, -1 -- default forward dash (e.g., up)
            end
        else
            dirX, dirY = dirX / len, dirY / len
        end
        return dirX, dirY
    end

    local function queueDashRequest(dir)
        bufferedDashDir = dir and { x = dir.x, y = dir.y } or nil
        dashBufferTimer = DASH_BUFFER_WINDOW
    end

    local function startPlayerDash(dir)
        if not survivorEntity or survivorEntity == entt_null or not entity_cache.valid(survivorEntity) then return end

        local dashX, dashY = resolveDashDirection(dir)
        local moveDir = { x = dashX, y = dashY }

        dashBufferTimer = 0
        bufferedDashDir = nil
        playerIsDashing = true
        playerDashTimeRemaining = DASH_LENGTH_SEC
        playerDashCooldownRemaining = DASH_COOLDOWN_SECONDS
        playerStaminaTickerTimer = DASH_COOLDOWN_SECONDS + STAMINA_TICKER_LINGER

        timer.cancel(DASH_END_TIMER_NAME)

        log_debug("Dash pressed!")

        local t = component_cache.get(survivorEntity, Transform)
        if t then
            -- Base squash/stretch factors
            local dirX, dirY = moveDir.x, moveDir.y
            local absX, absY = math.abs(dirX), math.abs(dirY)
            local dominant = absX > absY and "horizontal" or "vertical"

            local squeeze = 0.6   -- how thin to get
            local stretch = 1.4   -- how long to stretch
            local duration = 0.15 -- squash+stretch speed

            -- store original values
            local originalW = t.visualW
            local originalH = t.visualH
            local originalS = t.visualS or 1.0
            local originalR = t.visualR or 0.0

            if dominant == "horizontal" then
                -- Dash left/right → wider, shorter
                t.visualW = originalW * stretch
                t.visualH = originalH * squeeze
                t.visualS = originalS * 1.1
            else
                -- Dash up/down → taller, thinner
                t.visualH = originalH * stretch
                t.visualW = originalW * squeeze
                t.visualS = originalS * 1.1
            end

            -- Tiny rotational flair for diagonals
            if absX > 0.2 and absY > 0.2 then
                local tilt = math.deg(math.atan(dirY, dirX)) * 0.15
                t.visualR = originalR + tilt
            end
        end



        local maskEntity = survivorMaskEntity
        if gameplay_cfg.ENABLE_SURVIVOR_MASK and maskEntity and entity_cache.valid(maskEntity) then
            -- Apply rotational impulse (torque) to make mask spin
            local torqueStrength = 800 -- Tuned for lighter, mostly-weightless mask
            -- physics.ApplyTorque(world, maskEntity, torqueStrength)
            physics.ApplyAngularImpulse(world, maskEntity, moveDir.x * torqueStrength)
            -- Optional linear impulse skipped while mask disabled
        end

        local DASH_STRENGTH = 340

        -- physics.ApplyImpulse(PhysicsManager.get_world("world"), survivorEntity, moveDir.x * DASH_STRENGTH, moveDir.y * DASH_STRENGTH)

        -- timer.on_new_physics_step(function()
        physics.ApplyImpulse(world, survivorEntity, moveDir.x * DASH_STRENGTH, moveDir.y * DASH_STRENGTH)
        -- end, "dash_impulse_timer")

        local dashPosition = nil
        local st = component_cache.get(survivorEntity, Transform)
        if st then
            dashPosition = { x = st.actualX + st.actualW * 0.5, y = st.actualY + st.actualH * 0.5 }
        end
        signal.emit("on_dash", { player = survivorEntity }, {
            position = dashPosition,
            entity = survivorEntity
        })

        playSoundEffect("effects", random_utils.random_element_string(dash_sfx_list), 0.9 + math.random() * 0.2)

        -- timer.every((DASH_LENGTH_SEC) / 20, function()
        --     local t = component_cache.get(survivorEntity, Transform)
        --     if t then

        --         -- new node

        --         local particleNode = ParticleType{}
        --         particleNode.lifetime = 0.1
        --         particleNode.age = 0.0
        --         particleNode.savedPos = { x = t.visualX, y = t.visualY }


        --         particleNode
        --             :attach_ecs{ create_new = true }
        --             :destroy_when(function(self, eid) return self.age >= self.lifetime end)

        --         add_state_tag(particleNode:handle(), ACTION_STATE)

        --     end
        -- end, 10) -- 5 times

        -- directional dash trail particles
        local survivorTransform = component_cache.get(survivorEntity, Transform)
        if survivorTransform then
            local origin = Vec2(survivorTransform.actualX + survivorTransform.actualW * 0.5,
                survivorTransform.actualY + survivorTransform.actualH * 0.5)

            particle.spawnDirectionalCone(origin, 30, DASH_LENGTH_SEC, {
                direction = Vec2(-moveDir.x, -moveDir.y),
                spread = 30, -- degrees
                colors = {
                    util.getColor("blue")
                },
                endColor = util.getColor("blue"),
                minSpeed = 120,
                maxSpeed = 340,
                minScale = 3,
                maxScale = 10,
                rotationSpeed = 10,
                rotationJitter = 0.2,
                lifetimeJitter = 0.3,
                scaleJitter = 0.1,
                gravity = 0,
                easing = "cubic",
                renderType = particle.ParticleRenderType.CIRCLE_FILLED,
                space = "world",
                z = z_orders.player_vfx - 20
            })

            spawnHollowCircleParticle(
                origin.x,
                origin.y,
                30,
                util.getColor("dim_gray"),
                0.2
            )

            particle.spawnDirectionalStreaksCone(origin, 10, DASH_LENGTH_SEC, {
                direction = Vec2(-moveDir.x, -moveDir.y), -- up
                spread = a,                               -- ±22.5° cone
                minSpeed = 200,
                maxSpeed = 300,
                minScale = 8,
                maxScale = 10,
                autoAspect = true,
                shrink = true,
                colors = { Col(255, 200, 100) },
                space = "world",
                z = 5
            })

            particle.spawnDirectionalLinesCone(origin, 20, 0.8, {
                direction = Vec2(-moveDir.x, -moveDir.y),
                spread = 45,
                minSpeed = 200,
                maxSpeed = 400,
                minLength = 32,
                maxLength = 64,
                minThickness = 2,
                maxThickness = 5,
                colors = { Col(255, 220, 120), Col(255, 180, 80), Col(255, 120, 50) },
                durationJitter = 0.3,
                sizeJitter = 0.2,
                faceVelocity = true,
                shrink = true,
                space = "world",
                z = z_orders.particle_vfx
            })


            -- makeSwirlEmitter(320, 180, 120,
            --     { Col(255, 220, 120), Col(255, 160, 80), Col(255, 100, 60) },
            --     1.0,   -- emitDuration: spawn new dots for 1 second
            --     2.5    -- totalLifetime: fadeout & cleanup
            -- )

            makeSwirlEmitterWithRing(
                320, 180, 96,
                { util.getColor("white"), Col(255, 160, 80), Col(255, 100, 60) },
                1.0, -- emitDuration (how long to spawn new dots)
                2.5  -- totalLifetime
            )

            spawnCrescentParticle(
                200, 200, 40,
                Vec2(250, -60),
                Col(255, 220, 150, 255),
                1.5
            )

            -- Bigger diagonal slash effect
            spawnImpactSmear(320, 180, Vec2(0.7, 0.7), Col(255, 200, 200, 255), 0.3,
                { maxLength = 80, maxThickness = 6, single = true })

            particle.attachTrailToEntity(survivorEntity, DASH_LENGTH_SEC * 0.3, {
                space = "world",
                count = 20,
                direction = Vec2(-moveDir.x, -moveDir.y),
                spread = 45,
                colors = { util.getColor("white") },
                minSpeed = 80,
                maxSpeed = 220,
                lifetime = 0.4,
                interval = 0.01,

                onFinish = function(ent)
                    -- spawn final burst at entity’s last known position
                    local t = component_cache.get(survivorEntity, Transform)
                    if t then
                        particle.spawnDirectionalLinesCone(
                            Vec2(t.actualX + t.actualW * 0.5, t.actualY + t.actualH * 0.5), 10, 0.3, {
                                direction = Vec2(-moveDir.x, -moveDir.y),
                                spread = 360,
                                minSpeed = 200,
                                maxSpeed = 400,
                                minLength = 32,
                                maxLength = 64,
                                minThickness = 2,
                                maxThickness = 5,
                                colors = { util.getColor("white") },
                                durationJitter = 0.3,
                                sizeJitter = 0.2,
                                faceVelocity = true,
                                shrink = false,
                                space = "world",
                                z = z_orders.particle_vfx
                            })
                    end
                end
            })

            -- Yellow rotating dashed circle with faint fill for 2 seconds
            makeDashedCircleArea(320, 500, 80, {
                color = util.getColor("YELLOW"),
                fillColor = Col(255, 255, 100, 200),
                hasFill = true,
                dashLength = 18,
                gapLength = 10,
                rotateSpeed = 120, -- faster rotation
                thickness = 5,
                duration = 2.0
            })

            local p1 = Vec2(200, 600)
            local p2 = Vec2(500, 800)

            makePulsingBeam(p1, p2, {
                color = util.getColor("CYAN"),
                duration = 1.8,
                radius = 14,
                beamThickness = 12,
                pulseSpeed = 3.5,
            })


            -- Wipe upward while facing 45° angle
            -- makeDirectionalWipeWithTimer(320, 180, 400, 200,
            --     Vec2(0.7, 0.7),  -- facing diagonal
            --     Vec2(0, -1),     -- wipe upward
            --     Col(255, 180, 120, 255),
            --     1.0)
        end


        timer.after(DASH_LENGTH_SEC, function()
            timer.on_new_physics_step(function()
                -- physics.SetDamping(world, survivorEntity, 5.0)
                playerIsDashing = false
                playerDashTimeRemaining = 0
            end)
        end, DASH_END_TIMER_NAME)
    end

    local function tryConsumeBufferedDash(fallbackDir)
        if dashBufferTimer > 0 and not playerIsDashing and playerDashCooldownRemaining <= DASH_COYOTE_WINDOW then
            startPlayerDash(bufferedDashDir or fallbackDir)
            return true
        end
        return false
    end
    
    local function decayPlayerShotRecoil(recoilX, recoilY)
        playerShotRecoil.x = recoilX * PLAYER_PROJECTILE_RECOIL_DECAY
        playerShotRecoil.y = recoilY * PLAYER_PROJECTILE_RECOIL_DECAY

        if math.abs(playerShotRecoil.x) < 0.5 then playerShotRecoil.x = 0 end
        if math.abs(playerShotRecoil.y) < 0.5 then playerShotRecoil.y = 0 end
    end

    local playerIdleTime = 0
    local STAND_STILL_THRESHOLD = 1.0
    local standStillTriggered = false

    -- create input timer. this must run every frame.
    timer.every_physics_step(
        function()
            -- Check for death screen click or key press (any input to restart)
            local ds = gameplay_cfg.getDeathScreen()
            if ds.isVisible then
                local clicked = input.isMousePressed(MouseButton.MOUSE_BUTTON_LEFT)
                local keyPressed = isKeyPressed("enter") or isKeyPressed("space")
                if clicked or keyPressed then
                    ds.handleAnyClick()
                end
                return  -- Block all other input while death screen is visible
            end

            if input and input.action_pressed and input.action_pressed("toggle_auto_aim") then
                autoAimEnabled = not autoAimEnabled
                if globals then globals.autoAimEnabled = autoAimEnabled end
                kickAimSpring()
            end

            if isLevelUpModalActive() then
                decayPlayerShotRecoil(playerShotRecoil.x, playerShotRecoil.y)
                return
            end
            -- TODO: debug by logging pos
            -- local debugPos = physics.GetPosition(world, survivorEntity)
            -- log_debug("Survivor pos:", debugPos.x, debugPos.y)

            -- log_debug("Survivor sleeping state:", physics.IsSleeping(world, survivorEntity))

            -- tracy.zoneBeginN("Survivor Input Handling") -- just some default depth to avoid bugs
            if not survivorEntity or survivorEntity == entt_null or not entity_cache.valid(survivorEntity) then
                decayPlayerShotRecoil(playerShotRecoil.x, playerShotRecoil.y)
                return
            end

            local isGamePadActive = input.isPadConnected(0) -- check if gamepad is connected, assuming player 0

            local moveDir = { x = 0, y = 0 }

            local playerMoving = false

            if (isGamePadActive) then
                -- log_debug("Gamepad active for movement")

                local move_x = input.action_value("gamepad_move_x")
                local move_y = input.action_value("gamepad_move_y")

                -- log_debug("Gamepad move x:", move_x, "move y:", move_y)

                -- If you want to invert Y (Raylib default is up = -1)
                -- move_y = -move_y

                -- Normalize deadzone
                local len = math.sqrt(move_x * move_x + move_y * move_y)
                playerMoving = len > 0.15
                if len > 1 then
                    move_x = move_x / len
                    move_y = move_y / len
                end

                moveDir.x = move_x
                moveDir.y = move_y
            else
                -- find intended dash direction from inputs
                if input.action_down("survivor_left") then moveDir.x = moveDir.x - 1 end
                if input.action_down("survivor_right") then moveDir.x = moveDir.x + 1 end
                if input.action_down("survivor_up") then moveDir.y = moveDir.y - 1 end
                if input.action_down("survivor_down") then moveDir.y = moveDir.y + 1 end

                local len = math.sqrt(moveDir.x * moveDir.x + moveDir.y * moveDir.y)
                if len ~= 0 then
                    moveDir.x, moveDir.y = moveDir.x / len, moveDir.y / len
                    playerMoving = true
                else
                    moveDir.x, moveDir.y = 0, 0
                end
            end

            if (moveDir.x > 0) then
                animation_system.set_horizontal_flip(survivorEntity, true)
            elseif (moveDir.x < 0) then
                animation_system.set_horizontal_flip(survivorEntity, false)
            end

            -- if player is moving, keep the timer running. if not, end the timer.
            local timerName = "survivorFootstepsSoundTimer"
            if playerMoving then
                if not timer.get_timer_and_delay(timerName) then
                    -- timer not active. turn it on.
                    timer.every(0.8, function()
                        -- play footstep sound at survivor position
                        playSoundEffect("effects", random_utils.random_element_string(gameplay_cfg.playerFootStepSounds))
                    end, 0, true, nil, timerName)
                else
                    -- timer active, do nothing.
                end
            else
                -- turn off timer if active
                timer.cancel(timerName)
            end

            local dustTimerName = "survivorWalkDustTimer"
            if playerMoving and not playerIsDashing then
                if not timer.get_timer_and_delay(dustTimerName) then
                    timer.every(0.12, function()
                        spawnWalkDust()
                    end, 0, true, nil, dustTimerName)
                end
            else
                timer.cancel(dustTimerName)
            end

            local dashPressed = input.action_pressed("survivor_dash")
            local moveLen = math.sqrt(moveDir.x * moveDir.x + moveDir.y * moveDir.y)
            local prevLen = math.sqrt(lastMoveInput.x * lastMoveInput.x + lastMoveInput.y * lastMoveInput.y)
            local moveInputChanged = false
            if moveLen > 0.1 then
                if prevLen <= 0.1 then
                    moveInputChanged = true
                else
                    local dot = (moveDir.x * lastMoveInput.x + moveDir.y * lastMoveInput.y) / (moveLen * prevLen)
                    moveInputChanged = dot < 0.5
                end
            end

            if playerIsDashing and moveInputChanged then
                startPlayerDash(moveDir)
            elseif dashPressed then
                if (not playerIsDashing) and playerDashCooldownRemaining <= DASH_COYOTE_WINDOW then
                    startPlayerDash(moveDir)
                else
                    queueDashRequest(moveDir)
                end
            end

            tryConsumeBufferedDash(moveDir)

            lastMoveInput.x, lastMoveInput.y = moveDir.x, moveDir.y
            local recoilX, recoilY = playerShotRecoil.x, playerShotRecoil.y

            if playerIsDashing then
                decayPlayerShotRecoil(recoilX, recoilY)
                return -- skip movement input while dashing
            end

            local speed = 200 -- pixels per second

            physics.SetVelocity(
                PhysicsManager.get_world("world"),
                survivorEntity,
                moveDir.x * speed + recoilX,
                moveDir.y * speed + recoilY
            )

            if playerMoving then
                signal.emit("on_step", survivorEntity, {
                    direction = moveDir,
                    speed = speed,
                })
                signal.emit("player_moved", survivorEntity, {
                    direction = moveDir,
                    speed = speed,
                })
                playerIdleTime = 0
                standStillTriggered = false
            else
                playerIdleTime = playerIdleTime + (1 / 60)
                if playerIdleTime >= STAND_STILL_THRESHOLD and not standStillTriggered then
                    standStillTriggered = true
                    signal.emit("on_stand_still", survivorEntity, {
                        idle_time = playerIdleTime,
                    })
                end
            end

            decayPlayerShotRecoil(recoilX, recoilY)

            -- tracy.zoneEnd()
        end,
        nil,                          -- no after
        "survivorEntityMovementTimer" -- timer tag
    )

    input.set_context("gameplay") -- set the input context to gameplay



    initCombatSystem()

    -- DEBUG: Hardcoded enemy spawn timer - DISABLED
    -- This bypasses EnemyFactory and uses old sprites. Use EnemyFactory.spawn() instead.
    --[[ COMMENTED OUT - use wave_director + EnemyFactory instead
    timer.every(5.0, function()
            if is_state_active(ACTION_STATE) and not isLevelUpModalActive() then
                -- animation entity
                local enemyEntity = animation_system.createAnimatedObjectWithTransform(
                    "enemy_type_2.png", -- animation ID
                    true         -- use animation, not sprite identifier, if false
                )

                playSoundEffect("effects", "monster_appear_whoosh", 0.8 + math.random() * 0.3)

                -- give state
                add_state_tag(enemyEntity, ACTION_STATE)
                -- remove default state tag
                remove_default_state_tag(enemyEntity)

                -- set it to a random position, within the screen bounds.
                local enemyTransform = component_cache.get(enemyEntity, Transform)
                enemyTransform.actualX = lume.random(SCREEN_BOUND_LEFT + 50, SCREEN_BOUND_RIGHT - 50)
                enemyTransform.actualY = lume.random(SCREEN_BOUND_TOP + 50, SCREEN_BOUND_BOTTOM - 50)

                -- snap
                enemyTransform.visualX = enemyTransform.actualX
                enemyTransform.visualY = enemyTransform.actualY

                -- give it physics
                local info = { shape = "rectangle", tag = C.CollisionTags.ENEMY, sensor = false, density = 1.0, inflate_px = -4 }
                physics.create_physics_for_transform(registry,
                    physics_manager_instance,                                                                       -- global instance
                    enemyEntity,                                                                                    -- entity id
                    "world",                                                                                        -- physics world identifier
                    info
                )

                -- give pipeline
                registry:emplace(enemyEntity, shader_pipeline.ShaderPipelineComponent)

                physics.update_collision_masks_for(PhysicsManager.get_world("world"), C.CollisionTags.ENEMY, { C.CollisionTags.PLAYER, C.CollisionTags.ENEMY })
                physics.update_collision_masks_for(PhysicsManager.get_world("world"), C.CollisionTags.PLAYER, { C.CollisionTags.ENEMY })

                -- make it steerable
                steering.make_steerable(registry, enemyEntity, 3000.0, 30000.0, math.pi * 2.0, 2.0)


                -- give a blinking timer
                timer.every(0.1, function()
                    if entity_cache.valid(enemyEntity) then
                        local animComp = component_cache.get(enemyEntity, AnimationQueueComponent)
                        if animComp then
                            animComp.noDraw = not animComp.noDraw
                        end
                    end
                end, nil, true, function()
                end, "enemy_blink_timer_" .. tostring(enemyEntity))

                -- tween the multiplier up to 3.0 over 0.5 seconds, then remove the timer
                timer.tween_scalar(0.5, function()
                        return timer.get_multiplier("enemy_blink_timer_" .. tostring(enemyEntity))
                    end,
                    function(v)
                        timer.set_multiplier("enemy_blink_timer_" .. tostring(enemyEntity), v)
                    end, 2, Easing.cubic.f, function()
                        timer.cancel("enemy_blink_timer_" .. tostring(enemyEntity))
                        -- ensure it's visible
                        local animComp = component_cache.get(enemyEntity, AnimationQueueComponent)
                        if animComp then
                            animComp.noDraw = false
                        end
                    end)


                timer.after(0.6, function()
                    -- cancel blinking timer
                    timer.cancel("enemy_blink_timer_" .. tostring(enemyEntity))
                    -- ensure it's visible
                    local animComp = component_cache.get(enemyEntity, AnimationQueueComponent)
                    if animComp then
                        animComp.noDraw = false
                    end
                end)


                -- give it a combat table.

                -- Ogre: tougher target with defense layers and reactive behaviors (reflect/retaliation/block).
                local ogre = combat_context._make_actor('Ogre', combat_context.stat_defs,
                    CombatSystem.Game.Content.attach_attribute_derivations)
                ogre.side = 2
                ogre.stats:add_base('health', 10)
                ogre.stats:add_base('offensive_ability', 10)
                ogre.stats:add_base('defensive_ability', 10)
                ogre.stats:add_base('armor', 10)
                ogre.stats:add_base('armor_absorption_bonus_pct', 0)
                ogre.stats:add_base('fire_resist_pct', 0)
                ogre.stats:add_base('dodge_chance_pct', 0)
                -- ogre.stats:add_base('deflect_chance_pct', 8) -- (deflection not currently used)
                -- ogre.stats:add_base('reflect_damage_pct', 0)
                -- ogre.stats:add_base('retaliation_fire', 8)
                -- ogre.stats:add_base('retaliation_fire_modifier_pct', 25)
                -- ogre.stats:add_base('block_chance_pct', 30)
                -- ogre.stats:add_base('block_amount', 60)
                -- ogre.stats:add_base('block_recovery_reduction_pct', 25)
                -- ogre.stats:add_base('damage_taken_reduction_pct',2000) -- stress test: massive DR → negative damage (healing)
                ogre.stats:recompute()


                CombatSystem.Game.ItemSystem.equip(combat_context, ogre, basic_monster_weapon)

                -- give node
                local enemyScriptNode = Node {}
                enemyScriptNode.combatTable = ogre
                enemyScriptNode:attach_ecs { create_new = false, existing_entity = enemyEntity }
                combatActorToEntity[ogre] = enemyEntity
                ogre.entity_id = enemyEntity  -- For combat_system.lua signal emission
                enemyHealthUiState[enemyEntity] = { actor = ogre, visibleUntil = 0 }


                -- make circle marker for enemy appearance, tween it down to 0 scale and then remove it
                local SpawnMarkerType = Node:extend()
                local enemyX = enemyTransform.actualX + enemyTransform.actualW / 2
                local enemyY = enemyTransform.actualY + enemyTransform.actualH / 2
                function SpawnMarkerType:update(dt)
                    command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
                        c.x = enemyX
                        c.y = enemyY
                        c.w = 64 * self.scale
                        c.h = 64 * self.scale
                        c.rx = 32
                        c.ry = 32
                        c.color = Col(255, 255, 255, 255)
                    end, z_orders.projectiles + 1, layer.DrawCommandSpace.World)
                end

                local spawnMarkerNode = SpawnMarkerType {}
                spawnMarkerNode.scale = 1.0

                spawnMarkerNode:attach_ecs { create_new = true }
                add_state_tag(spawnMarkerNode:handle(), ACTION_STATE)

                -- tween down
                -- local h5 = timer.tween(1.2, camera, { x = 320, y = 180, zoom = 1.25 }, nil, nil, "cam_move", "camera")
                timer.tween_fields(0.2, spawnMarkerNode, { scale = 0.0 }, nil, function()
                    registry:destroy(spawnMarkerNode:handle())
                end)

                timer.every_physics_step(function()
                    if not entity_cache.valid(enemyEntity) then return end
                    if isLevelUpModalActive() then return end
                    local t = component_cache.get(enemyEntity, Transform)

                    local playerLocation = { x = 0, y = 0 }
                    local playerT = component_cache.get(survivorEntity, Transform)
                    if playerT then
                        playerLocation.x = playerT.actualX + playerT.actualW / 2
                        playerLocation.y = playerT.actualY + playerT.actualH / 2
                    end

                    steering.seek_point(registry, enemyEntity, playerLocation, 1.0, 0.5)
                    -- steering.flee_point(registry, player, {x=playerT.actualX + playerT.actualW/2, y=playerT.actualY + playerT.actualH/2}, 300.0, 1.0)
                    steering.wander(registry, enemyEntity, 300.0, 300.0, 150.0, 3)

                    -- steering.path_follow(registry, player, 1.0, 1.0)

                    -- run every frame for this to work
                    -- physics.ApplyTorque(world, player, 1000)
                end)
            end
        end,
        nil,
        "spawnEnemyTimer")
    --]] -- END of commented-out debug spawn timer



    local cam = camera.Get("world_camera")
    -- timer to pan camera to follow player
    timer.run(function()
            -- tracy.zoneBeginN("Camera Pan Timer Tick") -- just some default depth to avoid bugs
            -- log_debug("Camera pan timer tick")
            if entity_cache.state_active(ACTION_STATE) then
                local targetX, targetY = 0, 0
                local t = component_cache.get(survivorEntity, Transform)
                if t then
                    targetX = t.actualX + t.actualW / 2
                    targetY = t.actualY + t.actualH / 2
                    -- Gently steer toward the player instead of hard locking.
                    local current = cam:GetActualTarget()
                    local lerp = 0.045 -- smaller = slower camera drift
                    cam:SetActualTarget(
                        current.x + (targetX - current.x) * lerp,
                        current.y + (targetY - current.y) * lerp
                    )
                end
            else
                -- local cam = camera.Get("world_camera")
                -- log_debug("Camera pan timer tick - no action state, centering camera")
                local c = cam:GetActualTarget()

                -- if not already at halfway point in screen, then move it there
                if math.abs(c.x - globals.screenWidth() / 2) > 5 or math.abs(c.y - globals.screenHeight() / 2) > 5 then
                    camera_smooth_pan_to("world_camera", globals.screenWidth() / 2, globals.screenHeight() / 2) -- pan to the target smoothly
                end
            end
            -- tracy.zoneEnd()
        end,
        nil,
        false,
        nil,
        "cameraPanToPlayerTimer")

    -- timer to spawn an exp pickup every few seconds, for testing purposes.
    timer.every(3.0, function()
        if is_state_active(ACTION_STATE) and not isLevelUpModalActive() then
            spawnExpPickupAt()
        end
    end)

    -- blanket collision update
    -- physics.reapply_all_filters(PhysicsManager.get_world("world"))
end

planningUIEntities = {
    start_action_button_box = nil,
    wand_buttons = {},
    player_stats_button_box = nil,
    player_stats_button = nil
}

function initNewItemRewardText()
    
    -- clear states, enable REWARD_OPENING_STATE
    clear_states()
    activate_state(REWARD_OPENING_STATE)
    
    -- - darken screen.
    
    -- local BackgroundFadeType = Node:extend()
    
    -- BackgroundFadeType.duration = 0.5
    -- BackgroundFadeType.age = 0.0
    
    -- -- make it fade to black
    -- function BackgroundFadeType:update(dt)
    --     self.age = (self.age or 0) + dt  -- Increment age manually!
    --     local fade = math.min(1.0, self.age / self.duration)
    --     log_debug("Background fade age:", self.age, "fade:", fade)
    --     command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
    --         c.x = globals.screenWidth() / 2
    --         c.y = globals.screenHeight() / 2
    --         c.w = globals.screenWidth()
    --         c.h = globals.screenHeight()
    --         c.rx = 0
    --         c.ry = 0
    --         -- fade to black
    --         c.color = Col(0, 0, 0, math.floor(255 * fade))
    --     end, z_orders.background, layer.DrawCommandSpace.Screen)
    -- end
    
    -- local backgroundFadeNode = BackgroundFadeType {}
    -- backgroundFadeNode:attach_ecs { create_new = true }
    -- add_state_tag(backgroundFadeNode:handle(), REWARD_OPENING_STATE)
    -- remove_default_state_tag(backgroundFadeNode:handle())


    -- TODO; remember to remove later.
    
    
    

    
    
    -- - show a chest. it should start to shake, and halo of particles from behind it shoud expand and spin.
        -- frame0012.png
    
        -- make chest sprite, shake it, release particles.
    
    -- make animated entity
    local chestEntity = animation_system.createAnimatedObjectWithTransform(
        "frame0012.png", -- animation ID
        true              -- use animation, not sprite identifier, if false
    )
    -- resize to 300 x 300
    animation_system.resizeAnimationObjectsInEntityToFit(
        chestEntity,
        300, 300 -- target width and height
    )
    -- position it in the center of the screen
    local chestTransform = component_cache.get(chestEntity, Transform)
    chestTransform.actualX = globals.screenWidth() / 2 - chestTransform.actualW / 2
    chestTransform.actualY = globals.screenHeight() / 2 - chestTransform.actualH / 2
    -- snap it to the visual position
    chestTransform.visualX = chestTransform.actualX
    chestTransform.visualY = chestTransform.actualY
    -- give it 3d_skew_polychrome shader
    local pipelineComp = registry:emplace(chestEntity, shader_pipeline.ShaderPipelineComponent)
    pipelineComp:addPass("3d_skew_polychrome")
    -- give entity REWARD_OPENING_STATE
    add_state_tag(chestEntity, REWARD_OPENING_STATE)
    -- remove default state tag
    remove_default_state_tag(chestEntity)
    
    -- set z order to above background
    local chestZOrder = z_orders.background + 10
    layer_order_system.assignZIndexToEntity(chestEntity, chestZOrder)
    
    -- - an exciting shader background that is colorful and dynamic.
    add_layer_shader("background", "spectrum_line_background")
    remove_layer_shader("background", "peaches_background")
    
        -- the explosion shader.
        
    -- remove background shader
    
        
    -- - there should be three escalations, like fanfare, box jerking each time, which will modify the shader background color, maybe make it pulse.
    
        -- need sound for this. also three escalating booom boom boom.
        -- pulse the explosion shader.
        
    -- - it shoudl turn white when it opens, release a pulse (shader), then play a satisfying sound, (maybe a stinger afterward.). Plenty of particles everywhere.
    
        -- ripple shader. 
        -- flash shader on entity to turn it white.
        -- chest open sound + stinger.
        -- particles everywhere. + fireworks shader.
        
    -- dissolve the reward away. 
    
    -- pop in the reward, make it float up and down.
        
    -- -  maybe escalate the background with this? https://www.shadertoy.com/view/MdGGRW move it to the center, make it vary in color as the sound escalates, then show fireworks, then boom.
    -- - Then show the reward, with ambient animation.
    -- - fireworks background https://www.shadertoy.com/view/4lfXRf
    -- - confetti twister https://www.shadertoy.com/view/WsByRW
    -- - existing ripple shader for opening impact 
    -- - varied particles for opening impact
    -- - shake box upon opening.
    -- - some kind of rainbow streaknig as well?
    -- - https://godotshaders.com/shader/2dradial-shine-2/ for shine
    -- - godotshaders.com/shader/pixel-perfect-halo-radiant-glow/ for glow
end

function initPlanningUI()
    -- makeWandTooltip()

    local startButtonText = ui.definitions.getNewDynamicTextEntry(
        function() return localization.get("ui.start_action_phase") end,
        28.0,
        "color=fuchsia"
    )
    local startButtonTemplate = UIElementTemplateNodeBuilder.create()
        :addType(UITypeEnum.HORIZONTAL_CONTAINER)
        :addConfig(
            UIConfigBuilder.create()
            :addColor(util.getColor("gray"))
            :addPadding(16.0)
            :addEmboss(2.0)
            :addHover(true)                                -- needed for button effect
            :addButtonCallback(function()
                playSoundEffect("effects", "button-click") -- play button click sound
                startActionPhase()
            end)
            :addAlign(bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER))
            :addInitFunc(function(registry, entity)
                -- something init-related here
            end)
            :build()
        )
        :addChild(startButtonText)
        :build()

    local startMenuRoot = UIElementTemplateNodeBuilder.create()
        :addType(UITypeEnum.SCROLL_PANE)
        :addConfig(
            UIConfigBuilder.create()
            :addColor(util.getColor("yellow"))
            :addPadding(0)
            :addAlign(bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER))
            :addInitFunc(function(registry, entity)
                -- something init-related here
            end)
            :build()
        )
        :addChild(startButtonTemplate)
        :build()

    -- new uibox for the main menu
    planningUIEntities.start_action_button_box = ui.box.Initialize({ x = 350, y = globals.screenHeight() }, startMenuRoot)

    -- center the ui box X-axi
    local buttonTransform = component_cache.get(planningUIEntities.start_action_button_box, Transform)
    buttonTransform.actualX = globals.screenWidth() / 2 - buttonTransform.actualW / 2
    buttonTransform.actualY = globals.screenHeight() - buttonTransform.actualH - 10

    -- ggive entire box the planning state
    ui.box.AssignStateTagsToUIBox(planningUIEntities.start_action_button_box, PLANNING_STATE)
    -- remove default state
    remove_default_state_tag(planningUIEntities.start_action_button_box)

    -- simple stats button with hover tooltip
    local statsButtonLabel = ui.definitions.getTextFromString("[" .. L("ui.stats_button", "Stats") .. "](color=white;fontSize=14;shadow=false)")
    local statsButtonTemplate = UIElementTemplateNodeBuilder.create()
        :addType(UITypeEnum.HORIZONTAL_CONTAINER)
        :addConfig(
            UIConfigBuilder.create()
            :addId("player_stats_button")
            :addColor(util.getColor("gray"))
            :addPadding(8.0)
            :addEmboss(2.0)
            :addHover(true)
            :addMinWidth(80)
            :addAlign(bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER))
            :build()
        )
        :addChild(statsButtonLabel)
        :build()

    local detailedButtonLabel = ui.definitions.getTextFromString("[" .. L("ui.detailed_button", "Detailed") .. "](color=white;fontSize=14;shadow=false)")
    local detailedButtonTemplate = UIElementTemplateNodeBuilder.create()
        :addType(UITypeEnum.HORIZONTAL_CONTAINER)
        :addConfig(
            UIConfigBuilder.create()
            :addId("player_stats_detailed_button")
            :addColor(util.getColor("gray"))
            :addPadding(8.0)
            :addEmboss(2.0)
            :addHover(true)
            :addMinWidth(80)
            :addAlign(bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER))
            :build()
        )
        :addChild(detailedButtonLabel)
        :build()

    local statsRoot = UIElementTemplateNodeBuilder.create()
        :addType(UITypeEnum.ROOT)
        :addConfig(
            UIConfigBuilder.create()
            :addColor(util.getColor("blank"))
            :addAlign(bit.bor(AlignmentFlag.HORIZONTAL_LEFT, AlignmentFlag.VERTICAL_TOP))
            :build()
        )
        :addChild(statsButtonTemplate)
        :addChild(detailedButtonTemplate)
        :build()

    local statsPosX = 20
    local statsPosY = 90
    planningUIEntities.player_stats_button_box = ui.box.Initialize({ x = statsPosX, y = statsPosY }, statsRoot)
    local statsTransform = component_cache.get(planningUIEntities.player_stats_button_box, Transform)
    if statsTransform then
        statsTransform.actualX = statsPosX
        statsTransform.visualX = statsTransform.actualX
        statsTransform.actualY = statsPosY
        statsTransform.visualY = statsTransform.actualY
    end
    ui.box.ClearStateTagsFromUIBox(planningUIEntities.player_stats_button_box)
    -- HIDDEN: Stats buttons disabled for now
    -- ui.box.AddStateTagToUIBox(planningUIEntities.player_stats_button_box, PLANNING_STATE)
    -- ui.box.AddStateTagToUIBox(planningUIEntities.player_stats_button_box, ACTION_STATE)
    -- ui.box.AddStateTagToUIBox(planningUIEntities.player_stats_button_box, SHOP_STATE)

    local statsButtonEntity = ui.box.GetUIEByID(registry, "player_stats_button")
    planningUIEntities.player_stats_button = statsButtonEntity
    if statsButtonEntity and entity_cache.valid(statsButtonEntity) then
        local go = component_cache.get(statsButtonEntity, GameObject)
        if go then
            go.state.hoverEnabled = true
            go.state.collisionEnabled = true
            go.methods.onHover = function()
                showPlayerStatsTooltip(statsButtonEntity)
            end
            go.methods.onStopHover = function()
                hidePlayerStatsTooltip()
            end
        end
    end

    local detailedButtonEntity = ui.box.GetUIEByID(registry, "player_stats_detailed_button")
    planningUIEntities.player_stats_detailed_button = detailedButtonEntity
    if detailedButtonEntity and entity_cache.valid(detailedButtonEntity) then
        local go = component_cache.get(detailedButtonEntity, GameObject)
        if go then
            go.state.hoverEnabled = true
            go.state.collisionEnabled = true
            go.methods.onHover = function()
                showDetailedStatsTooltip(detailedButtonEntity)
            end
            go.methods.onStopHover = function()
                hideDetailedStatsTooltip()
            end
        end
    end

    -- Synergy panel toggle button
    local synergyButtonLabel = ui.definitions.getTextFromString("[" .. L("ui.synergies_button", "Synergies") .. "](color=white;fontSize=14;shadow=false)")
    local synergyButtonTemplate = UIElementTemplateNodeBuilder.create()
        :addType(UITypeEnum.HORIZONTAL_CONTAINER)
        :addConfig(
            UIConfigBuilder.create()
            :addId("synergy_toggle_button")
            :addColor(util.getColor("gray"))
            :addPadding(8.0)
            :addEmboss(2.0)
            :addHover(true)
            :addMinWidth(80)
            :addAlign(bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER))
            :addButtonCallback(function()
                playSoundEffect("effects", "button-click")
                ui_modules.TagSynergyPanel.toggle()
            end)
            :build()
        )
        :addChild(synergyButtonLabel)
        :build()

    local synergyRoot = UIElementTemplateNodeBuilder.create()
        :addType(UITypeEnum.ROOT)
        :addConfig(
            UIConfigBuilder.create()
            :addColor(util.getColor("blank"))
            :addAlign(bit.bor(AlignmentFlag.HORIZONTAL_RIGHT, AlignmentFlag.VERTICAL_TOP))
            :build()
        )
        :addChild(synergyButtonTemplate)
        :build()

    local synergyPosX = globals.screenWidth() - 140
    local synergyPosY = 20
    planningUIEntities.synergy_button_box = ui.box.Initialize({ x = synergyPosX, y = synergyPosY }, synergyRoot)
    local synergyTransform = component_cache.get(planningUIEntities.synergy_button_box, Transform)
    if synergyTransform then
        synergyTransform.actualX = synergyPosX
        synergyTransform.visualX = synergyTransform.actualX
        synergyTransform.actualY = synergyPosY
        synergyTransform.visualY = synergyTransform.actualY
    end
    ui.box.ClearStateTagsFromUIBox(planningUIEntities.synergy_button_box)
    -- HIDDEN: Synergies button disabled for now
    -- ui.box.AddStateTagToUIBox(planningUIEntities.synergy_button_box, PLANNING_STATE)

    -- Give button higher z-order than the synergy panel so it remains clickable
    if layer_order_system and layer_order_system.assignZIndexToEntity then
        layer_order_system.assignZIndexToEntity(planningUIEntities.synergy_button_box,
            (z_orders.ui_tooltips or 0) + 15)
    end

    local synergyButtonEntity = ui.box.GetUIEByID(registry, "synergy_toggle_button")
    planningUIEntities.synergy_toggle_button = synergyButtonEntity

    -- Set button bounds for click-outside exclusion
    local buttonTransform = component_cache.get(planningUIEntities.synergy_button_box, Transform)
    if buttonTransform then
        ui_modules.TagSynergyPanel.setToggleButtonBounds({
            x = buttonTransform.actualX or synergyPosX,
            y = buttonTransform.actualY or synergyPosY,
            w = buttonTransform.actualW or 100,
            h = buttonTransform.actualH or 40
        })
    end

    -- Execution graph toggle button
    local execGraphButtonLabel = ui.definitions.getTextFromString("[" .. L("ui.exec_graph_button", "Wand Preview") .. "](color=white;fontSize=14;shadow=false)")
    local execGraphButtonTemplate = UIElementTemplateNodeBuilder.create()
        :addType(UITypeEnum.HORIZONTAL_CONTAINER)
        :addConfig(
            UIConfigBuilder.create()
            :addId("exec_graph_toggle_button")
            :addColor(util.getColor("gray"))
            :addPadding(8.0)
            :addEmboss(2.0)
            :addHover(true)
            :addMinWidth(80)
            :addAlign(bit.bor(AlignmentFlag.HORIZONTAL_CENTER, AlignmentFlag.VERTICAL_CENTER))
            :addButtonCallback(function()
                if ui_modules.CastExecutionGraphUI.toggleFromButton then
                    if ui_modules.CastExecutionGraphUI.toggleFromButton() then
                        playSoundEffect("effects", "button-click")
                    end
                else
                    playSoundEffect("effects", "button-click")
                    ui_modules.CastExecutionGraphUI.toggle()
                end
            end)
            :build()
        )
        :addChild(execGraphButtonLabel)
        :build()

    local execGraphRoot = UIElementTemplateNodeBuilder.create()
        :addType(UITypeEnum.ROOT)
        :addConfig(
            UIConfigBuilder.create()
            :addColor(util.getColor("blank"))
            :addAlign(bit.bor(AlignmentFlag.HORIZONTAL_LEFT, AlignmentFlag.VERTICAL_BOTTOM))
            :build()
        )
        :addChild(execGraphButtonTemplate)
        :build()

    local AvatarJokerStrip = require("ui.avatar_joker_strip")
    local panelTopY = ui_modules.AvatarJokerStrip.getPanelTopY() or (globals.screenHeight() - 120)
    local execGraphPosX = 32
    local execGraphPosY = panelTopY - 50
    planningUIEntities.exec_graph_button_box = ui.box.Initialize({ x = execGraphPosX, y = execGraphPosY }, execGraphRoot)
    local execGraphTransform = component_cache.get(planningUIEntities.exec_graph_button_box, Transform)
    if execGraphTransform then
        execGraphTransform.actualX = execGraphPosX
        execGraphTransform.visualX = execGraphTransform.actualX
        execGraphTransform.actualY = execGraphPosY
        execGraphTransform.visualY = execGraphTransform.actualY
    end
    ui.box.ClearStateTagsFromUIBox(planningUIEntities.exec_graph_button_box)
    ui.box.AddStateTagToUIBox(planningUIEntities.exec_graph_button_box, PLANNING_STATE)

    -- Give button higher z-order than the graph panel (which is at ui_tooltips + 5)
    -- so it remains clickable even when the graph overlaps it
    if layer_order_system and layer_order_system.assignZIndexToEntity then
        layer_order_system.assignZIndexToEntity(planningUIEntities.exec_graph_button_box,
            (z_orders.ui_tooltips or 0) + 15)
    end

    local execGraphButtonEntity = ui.box.GetUIEByID(registry, "exec_graph_toggle_button")
    planningUIEntities.exec_graph_toggle_button = execGraphButtonEntity

    -- Set button bounds for click-outside exclusion
    -- Pass the button box entity so bounds can be updated dynamically each frame
    local execGraphButtonTransform = component_cache.get(planningUIEntities.exec_graph_button_box, Transform)
    local execGraphBoundsEntity = planningUIEntities.exec_graph_button_box
    if planningUIEntities.exec_graph_toggle_button
        and planningUIEntities.exec_graph_toggle_button ~= entt_null then
        execGraphBoundsEntity = planningUIEntities.exec_graph_toggle_button
    end
    ui_modules.CastExecutionGraphUI.setToggleButtonBounds(
        {
            x = execGraphButtonTransform and execGraphButtonTransform.actualX or execGraphPosX,
            y = execGraphButtonTransform and execGraphButtonTransform.actualY or execGraphPosY,
            -- Treat 0-sized bounds as "not ready yet" so the manual hit-test
            -- doesn't get stuck failing until a later layout pass.
            w = (execGraphButtonTransform and execGraphButtonTransform.actualW and execGraphButtonTransform.actualW > 0)
                and execGraphButtonTransform.actualW or 120,
            h = (execGraphButtonTransform and execGraphButtonTransform.actualH and execGraphButtonTransform.actualH > 0)
                and execGraphButtonTransform.actualH or 40
        },
        execGraphBoundsEntity  -- Entity for dynamic bounds updates
    )

    if not stats_tooltip.signalRegistered then
        stats_tooltip.signalRegistered = true
        local handlers = initGameplayHandlers()
        handlers:on("stats_recomputed", function(payload)
            local ctx = combat_context
            local playerActor = ctx and ctx.side1 and ctx.side1[1]
            if not playerActor then return end

            local owner = payload and payload.owner
            local stats = payload and payload.stats
            if owner ~= playerActor and stats ~= playerActor.stats then
                return
            end

            local anchor = planningUIEntities and planningUIEntities.player_stats_button
            refreshPlayerStatsTooltip(anchor)
            local detailedAnchor = planningUIEntities and planningUIEntities.player_stats_detailed_button
            refreshDetailedStatsTooltip(detailedAnchor or anchor)
        end)
    end

    -- Legacy board-set wand buttons removed in favor of WandPanel tabs.
end

-- ============================================================================
-- GLOBAL EXPORTS
-- ============================================================================
-- Tooltip functions
_G.makeSimpleTooltip = makeSimpleTooltip
_G.ensureSimpleTooltip = ensureSimpleTooltip
_G.showSimpleTooltipAbove = showSimpleTooltipAbove
_G.hideSimpleTooltip = hideSimpleTooltip
_G.destroyAllSimpleTooltips = destroyAllSimpleTooltips
_G.centerTooltipAboveEntity = centerTooltipAboveEntity
_G.makeCardTooltip = makeCardTooltip
_G.ensureCardTooltip = ensureCardTooltip
_G.makeLocalizedTooltip = makeLocalizedTooltip

-- Entity helpers
_G.isEnemyEntity = isEnemyEntity

-- Constants
_G.AVATAR_PURCHASE_COST = AVATAR_PURCHASE_COST

-- ============================================================================
-- PARTICLE BUILDER TEST (temporary - remove after testing)
-- ============================================================================
timer.after(3.0, function()
    local ok, Particles = pcall(require, "core.particles")
    if not ok then
        log_warn("[ParticleTest] Failed to load particles module")
        return
    end

    log_info("[ParticleTest] Spawning test particles...")

    -- Define test recipes (use screen space so positions are screen coordinates)
    local spark = Particles.define()
        :shape("circle")
        :size(2, 4)
        :color(255, 200, 50)
        :velocity(100, 200)
        :lifespan(0.3, 0.5)
        :fade()
        :gravity(200)
        :space("screen")

    local fire = Particles.define()
        :shape("circle")
        :size(4, 8)
        :color(255, 150, 50)
        :velocity(50, 100)
        :lifespan(0.4, 0.7)
        :fade()
        :shrink()
        :space("screen")

    local smoke = Particles.define()
        :shape("circle")
        :size(8, 16)
        :color(150, 150, 150)
        :velocity(20, 40)
        :lifespan(0.8, 1.2)
        :fade()
        :grow(1.5)
        :space("screen")

    -- Spawn at lower portion of screen (to avoid main menu overlap)
    local cx, cy = 720, 700

    -- Define more test recipes
    local debris = Particles.define()
        :shape("rect")
        :size(3, 6)
        :color(139, 90, 43)  -- brown
        :velocity(150, 300)
        :lifespan(1.5, 2.0)  -- longer lifespan to see gravity
        :gravity(400)
        :spin()
        :space("screen")

    local sparkle = Particles.define()
        :shape("circle")
        :size(1, 3)
        :color(255, 255, 200)  -- pale yellow
        :velocity(30, 60)
        :lifespan(0.4, 0.6)
        :fade()
        :space("screen")

    local bigSmoke = Particles.define()
        :shape("circle")
        :size(20, 40)
        :color(100, 100, 100, 128)  -- semi-transparent gray
        :velocity(10, 30)
        :lifespan(1.5, 2.5)
        :fade()
        :grow(2.0)
        :space("screen")

    -- Stagger each effect with delays so user can see them one by one
    local delay = 0
    local step = 1.5  -- seconds between each effect

    -- Effect 1: Sparks with gravity (yellow, falling)
    timer.after(delay, function()
        log_info("[ParticleTest] 1/7: SPARKS with gravity")
        spark:burst(40):spread(120):at(cx, cy)
    end)
    delay = delay + step

    -- Effect 2: Fire explosion (orange, outward burst)
    timer.after(delay, function()
        log_info("[ParticleTest] 2/7: FIRE explosion outward")
        fire:burst(30):outward():inCircle(cx, cy, 20)
    end)
    delay = delay + step

    -- Effect 3: Smoke rising (gray, upward)
    timer.after(delay, function()
        log_info("[ParticleTest] 3/7: SMOKE rising upward")
        smoke:burst(25):spread(45):angle(-90):at(cx, cy)
    end)
    delay = delay + step

    -- Effect 4: Debris with gravity + spin (brown rectangles falling)
    timer.after(delay, function()
        log_info("[ParticleTest] 4/7: DEBRIS with gravity + spin")
        debris:burst(20):spread(180):at(cx, cy - 50)  -- start higher to see fall
    end)
    delay = delay + step

    -- Effect 5: Fire + Smoke combo
    timer.after(delay, function()
        log_info("[ParticleTest] 5/7: FIRE + SMOKE mix rising")
        Particles.mix({ fire, smoke }):burst(20, 12):spread(40):angle(-90):at(cx, cy)
    end)
    delay = delay + step

    -- Effect 6: Sparks + Debris explosion
    timer.after(delay, function()
        log_info("[ParticleTest] 6/7: SPARKS + DEBRIS explosion")
        Particles.mix({ spark, debris }):burst(25, 15):outward():inCircle(cx, cy, 30)
    end)
    delay = delay + step

    -- Effect 7: Sparkles + Big Smoke
    timer.after(delay, function()
        log_info("[ParticleTest] 7/8: SPARKLES + BIG SMOKE")
        Particles.mix({ sparkle, bigSmoke }):burst(40, 8):spread(360):at(cx, cy)
    end)
    delay = delay + step

    -- Effect 8: STREAMING - continuous particle emission
    timer.after(delay, function()
        log_info("[ParticleTest] 8/13: STREAMING sparks (3 seconds)")
        local streamHandle = spark
            :burst(5)
            :spread(90)
            :angle(-90)  -- upward
            :at(cx, cy)
            :stream()
            :every(0.08)  -- emit every 80ms
            :for_(3.0)    -- run for 3 seconds

        -- Update the stream each frame
        local streamTimer
        streamTimer = timer.every(1/60, function()
            if streamHandle then
                streamHandle:update(1/60)
                if not streamHandle:isActive() then
                    timer.cancel(streamTimer)
                    log_info("[ParticleTest] Stream complete!")
                end
            end
        end)
    end)
    delay = delay + step + 2.0  -- Extra delay for streaming

    -- Effect 9: WIGGLE - oscillating particles
    timer.after(delay, function()
        log_info("[ParticleTest] 9/13: WIGGLE particles")
        local wiggler = Particles.define()
            :shape("circle")
            :size(4, 6)
            :color(100, 200, 255)  -- cyan
            :velocity(150, 200)
            :lifespan(1.5, 2.0)
            :wiggle(30, 8)  -- 30 pixel amplitude, 8 Hz
            :fade()
            :space("screen")

        wiggler:burst(15):spread(30):angle(-90):at(cx, cy)
    end)
    delay = delay + step

    -- Effect 10: BOUNCE - bouncing particles
    timer.after(delay, function()
        log_info("[ParticleTest] 10/13: BOUNCE particles")
        local bouncer = Particles.define()
            :shape("rect")
            :size(6, 10)
            :color(255, 100, 100)  -- red
            :velocity(100, 200)
            :lifespan(4.0, 5.0)
            :gravity(300)
            :bounce(0.7, cy + 100)  -- bounce off cy+100 with 70% restitution
            :spin(180, 360)
            :space("screen")

        bouncer:burst(10):spread(120):at(cx, cy - 50)
    end)
    delay = delay + step

    -- Effect 11: HOMING - particles that seek a target
    timer.after(delay, function()
        log_info("[ParticleTest] 11/13: HOMING particles toward center")
        local homer = Particles.define()
            :shape("circle")
            :size(5, 8)
            :color(255, 255, 100)  -- yellow
            :velocity(80, 120)
            :lifespan(2.5, 3.0)
            :homing(0.5, { x = cx, y = cy })  -- home toward screen center
            :fade()
            :space("screen")

        -- Spawn around the edges, they'll home toward center
        homer:burst(8):at(cx - 200, cy)
        homer:burst(8):at(cx + 200, cy)
        homer:burst(8):at(cx, cy - 150)
    end)
    delay = delay + step

    -- Effect 12: TRAIL - particles that leave trails
    timer.after(delay, function()
        log_info("[ParticleTest] 12/13: TRAIL particles")
        -- Define the trail particle (small, fading)
        local trailDot = Particles.define()
            :shape("circle")
            :size(2, 3)
            :color(255, 150, 50, 200)  -- orange, semi-transparent
            :velocity(0, 0)  -- stationary
            :lifespan(0.3, 0.5)
            :fade()
            :shrink()
            :space("screen")

        -- Main particle that leaves trails
        local tracer = Particles.define()
            :shape("circle")
            :size(8, 10)
            :color(255, 200, 100)  -- bright orange
            :velocity(150, 200)
            :lifespan(2.0, 2.5)
            :trail(trailDot, 0.05)  -- spawn trail every 50ms
            :fade()
            :space("screen")

        tracer:burst(5):spread(60):angle(-45):at(cx - 100, cy)
    end)
    delay = delay + step

    -- Effect 13: FLASH - color cycling particles
    timer.after(delay, function()
        log_info("[ParticleTest] 13/13: FLASH rainbow particles")
        local flasher = Particles.define()
            :shape("circle")
            :size(8, 12)
            :flash(
                { 255, 0, 0 },     -- red
                { 255, 165, 0 },   -- orange
                { 255, 255, 0 },   -- yellow
                { 0, 255, 0 },     -- green
                { 0, 0, 255 },     -- blue
                { 128, 0, 128 }    -- purple
            )
            :velocity(50, 100)
            :lifespan(1.5, 2.0)
            :space("screen")

        flasher:burst(20):spread(360):at(cx, cy)
    end)
    delay = delay + step

    -- Effect 14: STRETCH - velocity-based stretching with ELLIPSE (circles become stretched ellipses)
    timer.after(delay, function()
        log_info("[ParticleTest] 14/16: STRETCH ellipses (circles + stretch)")
        local stretchEllipse = Particles.define()
            :shape("circle")       -- Uses ELLIPSE_STRETCH when :stretch() is called
            :size(12, 16)          -- base size
            :color(100, 200, 255)  -- light blue
            :velocity(250, 400)    -- fast for visible stretch
            :lifespan(0.8, 1.2)
            :stretch()             -- elongate based on velocity
            :fade()
            :space("screen")

        stretchEllipse:burst(20):spread(360):at(cx, cy)
    end)
    delay = delay + step

    -- Effect 15: STRETCH - velocity-based stretching with LINES
    timer.after(delay, function()
        log_info("[ParticleTest] 15/16: STRETCH lines")
        local stretchLine = Particles.define()
            :shape("line")         -- LINE_FACING for stretch
            :size(20, 30)          -- line length
            :color(255, 255, 255)  -- white streaks
            :velocity(300, 500)    -- fast for visible stretch
            :lifespan(0.8, 1.2)
            :stretch()             -- elongate based on velocity
            :fade()
            :space("screen")

        stretchLine:burst(15):spread(360):at(cx, cy)
    end)
    delay = delay + step

    -- Effect 16: COMBINED - multiple effects together
    timer.after(delay, function()
        log_info("[ParticleTest] 16/16: COMBINED effects (stretch + wiggle + bounce)")
        local combined = Particles.define()
            :shape("circle")
            :size(8, 12)
            :color(255, 150, 50)   -- orange
            :velocity(150, 250)
            :lifespan(2.0, 3.0)
            :stretch()             -- velocity-based stretching
            :wiggle(30)            -- lateral oscillation
            :bounce(0.6)           -- bounce off ground
            :fade()
            :space("screen")

        combined:burst(12):spread(120):angle(270):at(cx, cy - 100)  -- shoot downward
    end)
    delay = delay + step

    -- Effect 17: SHADER PARTICLES - particles rendered through shader pipeline
    timer.after(delay, function()
        log_info("[ParticleTest] 17/18: SHADER particles with 'flash' effect")
        local shaderParticle = Particles.define()
            :shape("circle")
            :size(15, 25)
            :color("cyan", "magenta")
            :velocity(80, 150)
            :lifespan(1.5, 2.5)
            :fade()
            :shaders({ "flash" })  -- Render through shader pipeline
            :space("screen")

        shaderParticle:burst(25):spread(360):at(cx, cy)
    end)
    delay = delay + step

    -- Effect 18: CUSTOM DRAW COMMAND - particles with custom rendering
    timer.after(delay, function()
        log_info("[ParticleTest] 18/18: CUSTOM drawCommand particles")
        local draw = require("core.draw")

        local customDrawParticle = Particles.define()
            :shape("circle")
            :size(20)
            :color("yellow")
            :velocity(100, 180)
            :lifespan(1.0, 2.0)
            :fade()
            :shaders({ "flash" })  -- Required for drawCommand to work
            :drawCommand(function(entity, props)
                -- Custom rendering: draw a filled circle through shader pipeline
                if draw and draw.local_command then
                    draw.local_command(entity, "draw_circle_filled", {
                        x = props.x,
                        y = props.y,
                        radius = props.size / 2,
                        color = props.color or WHITE
                    }, { z = 1, space = layer.DrawCommandSpace.Screen })
                end
            end)
            :space("screen")

        customDrawParticle:burst(15):spread(180):at(cx, cy)
    end)

    log_info("[ParticleTest] Starting sequence - 18 effects, 1.5s apart")
end)
