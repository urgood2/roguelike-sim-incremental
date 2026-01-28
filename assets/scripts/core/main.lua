require("init.bit_compat")
require("core.globals")
-- registry is a C++ global exposed via Sol2, not a Lua module - removed invalid require
require("ai.init") -- Read in ai scripts and populate the ai table
require("idle_game.init")
-- Set up forma package aliases before any forma modules are loaded
require("core.procgen.vendor")
local sim_scene = require("idle_game.scenes.sim_scene")
require("util.util")
require("ui.ui_defs")
require("core.entity_factory")
-- NOTE: core/gameplay.lua moved to idle_game/legacy/ (had hard requires on combat/wand)
-- pcall(function() require("idle_game.legacy.gameplay") end)
local profile = require("external.profile")  -- https://github.com/2dengine/profile.lua
local z_orders = require("core.z_orders")
local Node = require("monobehavior.behavior_script_v2") -- the new monobehavior script
local palette = require("color.palette")
local combat_core
pcall(function() combat_core = require("combat.combat_system") end)
local TimerChain = require("core.timer_chain")
local timer = require("core.timer")
local component_cache = require("core.component_cache")
local entity_cache = require("core.entity_cache")
local shader_uniforms = require("core.shader_uniforms")
local CastFeedUI = require("ui.cast_feed_ui")
-- REMOVED: InventoryTabMarker is redundant - player_inventory.lua creates its own tab marker
-- local InventoryTabMarker = require("ui.inventory_tab_marker")
-- local bit = require("bit") -- LuaJIT's bit library
local shader_prepass = require("shaders.prepass_example")
lume = require("external.lume")
local TextBuilderDemo = require("demos.text_builder_demo")
local Text = require("core.text") -- TextBuilder system for fire-and-forget text
local ok_tutorial, TutorialDialogueDemo = pcall(require, "tutorial.dialogue.demo")
if not ok_tutorial then
    TutorialDialogueDemo = nil
end
local LightingDemo = require("demos.lighting_demo")
local UIFillerDemo = require("demos.ui_filler_demo")
-- local RenderGroupsTest = require("tests.test_render_groups_visual") -- Visual test for render groups (disabled: DrawRenderGroup command not registered)
local SpecialItem = require("core.special_item")
SaveManager = require("core.save_manager") -- Global for C++ debug UI access
local PatchNotesModal = require("ui.patch_notes_modal")
local ok, InventoryGridDemo = pcall(require, "examples.inventory_grid_demo")
if not ok then
    print("[ERROR] Failed to load InventoryGridDemo: " .. tostring(InventoryGridDemo))
    InventoryGridDemo = nil
end
-- Represents game loop main module
main = main or {}

PROFILE_ENABLED = false -- set to true to enable profiling

-- Game state (used only in lua)
GAMESTATE = {
    MAIN_MENU = 0,
    IN_GAME = 1,
    SIM_GAME = 2
}

shapeAnimationPhase = 0

local currentGameState = GAMESTATE.MAIN_MENU -- Set the initial game state to IN_GAME
local autoStartMainGameEnv = (os.getenv and ((os.getenv("AUTO_START_MAIN_GAME") == "1") or (os.getenv("AUTO_ACTION_PHASE") == "1"))) or false

local telemetry_once_flags = {}
local function record_telemetry(event, props)
    -- Guard against missing bindings or runtime errors so gameplay keeps going.
    if type(telemetry) ~= "table" or type(telemetry.record) ~= "function" then
        return
    end
    local ok, err = pcall(telemetry.record, event, props or {})
    if not ok then
        if log_debug then
            log_debug(string.format("telemetry.record failed for %s: %s", event, tostring(err)))
        else
            print("telemetry.record failed for " .. tostring(event) .. ": " .. tostring(err))
        end
    end
end

-- Expose helpers globally for other modules (planning/action/shop phases).
_G.record_telemetry = record_telemetry

_G.telemetry_session_id = function()
    if type(telemetry) == "table" and type(telemetry.session_id) == "function" then
        return telemetry.session_id()
    end
    return "lua-session-unknown"
end

local function record_telemetry_once(flag, event, props)
    if telemetry_once_flags[flag] then
        return
    end
    telemetry_once_flags[flag] = true
    record_telemetry(event, props)
end

-- Global so demos can access main menu entities for repositioning
mainMenuEntities = {
}

local MAIN_MENU_TIMER_GROUP = "main_menu"
local MAIN_MENU_PHASE_TIMER_TAG = "main_menu_shape_phase"

function myCustomCallback()
    -- a test to see if the callback works for text typing
    wait(5)
    return true
end

function initMainMenu()
    log_debug("[initMainMenu] Starting main menu initialization...")

    local MainMenuButtons = require("ui.main_menu_buttons")

    -- create a timer to increment the phase
    timer.run(
        function()
            shapeAnimationPhase = shapeAnimationPhase + 1
        end,
        nil,
        MAIN_MENU_PHASE_TIMER_TAG,
        MAIN_MENU_TIMER_GROUP
    )


    globals.currentGameState = GAMESTATE.MAIN_MENU -- Set the game state to MAIN_MENU
    record_telemetry_once("scene_main_menu", "scene_enter", { scene = "main_menu" })
    setCategoryVolume("effects", 0.5)
    playMusic("main-menu", true)
    setTrackVolume("main-menu", 0.3)

    local screenW = globals.screenWidth()
    local screenH = globals.screenHeight()

    -- REMOVED: Special items (per spec - Phase 1)
    -- REMOVED: Input text field (per spec - Phase 1)

    -- NEW: Minimalist main menu buttons using MainMenuButtons module
    MainMenuButtons.setButtons({
        {
            label = localization.get("ui.start_game_button"),
            onClick = function()
                record_telemetry("start_game_clicked", { scene = "main_menu" })
                startGameButtonCallback()
            end
        },
        {
            label = localization.get("ui.start_game_feedback"),  -- "Discord" text
            onClick = function()
                record_telemetry("discord_button_clicked", { scene = "main_menu" })
                OpenURL("https://discord.gg/rp6yXxKu5z")
            end
        },
        {
            label = localization.get("ui.start_game_follow"),  -- "Bluesky" text
            onClick = function()
                record_telemetry("follow_button_clicked", { scene = "main_menu", platform = "bluesky" })
                OpenURL("https://bsky.app/profile/chugget.itch.io")
            end
        },
        {
            label = localization.get("ui.switch_language"),  -- "Language" text
            onClick = function()
                -- Switch the language
                if (localization.getCurrentLanguage() == "en_us") then
                    record_telemetry("language_changed", { from = "en_us", to = "ko_kr", session_id = telemetry_session_id() })
                    localization.setCurrentLanguage("ko_kr")
                else
                    record_telemetry("language_changed", { from = "ko_kr", to = "en_us", session_id = telemetry_session_id() })
                    localization.setCurrentLanguage("en_us")
                end
            end
        },
    })
    MainMenuButtons.init()

    -- Store reference for cleanup and for keyboard handling in main.update()
    mainMenuEntities.mainMenuButtons = MainMenuButtons

    -- Create main logo (centered horizontally, above menu buttons)
    globals.ui.logo = animation_system.createAnimatedObjectWithTransform(
        "b3832.png", -- animation ID
        true             -- use animation, not sprite identifier, if false
    )
    animation_system.resizeAnimationObjectsInEntityToFit(
        globals.ui.logo,
        64 * 3,   -- width
        64 * 3    -- height
    )
    -- Position: centered horizontally, positioned above menu area
    local logoTransform = component_cache.get(globals.ui.logo, Transform)
    local logoBaseY = screenH * 0.20  -- Position in upper portion of screen
    logoTransform.actualX = screenW / 2 - logoTransform.actualW / 2
    logoTransform.actualY = logoBaseY

    -- Logo bob animation (subtle float effect per spec)
    local LOGO_BOB_HEIGHT = 8   -- pixels
    local LOGO_BOB_SPEED = 2    -- oscillations per second

    timer.every(
        0.05, -- 20fps update for smooth animation
        function()
            if not globals.ui.logo or not entity_cache.valid(globals.ui.logo) then
                timer.cancel("logo_text_pulse")  -- Stop timer when entity is invalid
                return
            end
            local transformComp = component_cache.get(globals.ui.logo, Transform)
            if not transformComp then
                timer.cancel("logo_text_pulse")  -- Stop timer when component missing
                return
            end
            -- Use menu elapsed time for animation to pause with the game
            local time = globals.main_menu_elapsed_time or 0
            local bobOffset = math.sin(time * LOGO_BOB_SPEED) * LOGO_BOB_HEIGHT
            transformComp.actualY = logoBaseY + bobOffset
        end,
        0, -- infinite repetitions
        true, -- start immediately
        nil, -- no "after" callback
        "logo_text_pulse",
        MAIN_MENU_TIMER_GROUP
    )

    -- REMOVED: Old colored button panels (replaced by MainMenuButtons above)
    -- Corner buttons (icon-only with scale hover, per spec)
    PatchNotesModal.init()
    createPatchNotesButton()       -- bottom-left
    createLanguageCornerButton()   -- bottom-right
    createTabDemo()
    createInventoryTestButton()
    createGOAPDemoButton()

    log_debug("[initMainMenu] Main menu initialized with minimalist UI")
end

function createInventoryTestButton()
    local dsl = require("ui.ui_syntax_sugar")
    local PlayerInventory = require("ui.player_inventory")
    local timer = require("core.timer")
    
    local buttonDef = dsl.strict.root {
        config = {
            color = util.getColor("green_jade"),
            padding = 8,
            emboss = 3,
        },
        children = {
            dsl.strict.button("Test Inventory", {
                fontSize = 14,
                color = "transparent",
                textColor = "white",
                shadow = true,
                onClick = function()
                    log_debug("[TEST] Inventory button clicked!")
                    if playSoundEffect then playSoundEffect("effects", "button-click") end
                    PlayerInventory.toggle()
                    log_debug("[TEST] PlayerInventory.isOpen() = " .. tostring(PlayerInventory.isOpen()))

                    if PlayerInventory.isOpen() then
                        timer.after_opts({
                            delay = 0.1,
                            action = function()
                                PlayerInventory.spawnDummyCards()
                                log_debug("[TEST] Dummy cards spawned")
                            end,
                            tag = "spawn_dummy_cards"
                        })
                    end
                end
            })
        }
    }
    
    mainMenuEntities.inventory_test_button = dsl.spawn(
        { x = 120, y = globals.screenHeight() - 60 },
        buttonDef,
        "ui",
        100
    )
    ui.box.set_draw_layer(mainMenuEntities.inventory_test_button, "ui")
    log_debug("[TRACE] Inventory test button created")

    if os.getenv and os.getenv("AUTO_TEST_INVENTORY") == "1" then
        timer.after_opts({
            delay = 0.1,
            action = function()
                PlayerInventory.toggle()
                if PlayerInventory.isOpen() then
                    PlayerInventory.spawnDummyCards()
                end
            end,
            tag = "auto_open_test_inventory"
        })
    end
end

function createGOAPDemoButton()
    local dsl = require("ui.ui_syntax_sugar")
    local GOAPDemo = require("demos.goap_ai_demo")

    local buttonDef = dsl.strict.root {
        config = {
            color = util.getColor("cyan"),
            padding = 8,
            emboss = 3,
        },
        children = {
            dsl.strict.button("GOAP AI Demo", {
                fontSize = 14,
                color = "transparent",
                textColor = "white",
                shadow = true,
                onClick = function()
                    log_debug("[GOAP Demo] Button clicked!")
                    if playSoundEffect then playSoundEffect("effects", "button-click") end
                    GOAPDemo.toggle()
                end
            })
        }
    }

    mainMenuEntities.goap_demo_button = dsl.spawn(
        { x = 240, y = globals.screenHeight() - 60 },
        buttonDef,
        "ui",
        100
    )
    ui.box.set_draw_layer(mainMenuEntities.goap_demo_button, "ui")
    log_debug("[TRACE] GOAP AI Demo button created")

    -- Auto-start demo if environment variable is set
    if os.getenv and os.getenv("AUTO_GOAP_DEMO") == "1" then
        local timer = require("core.timer")
        timer.after_opts({
            delay = 0.5,
            action = function()
                GOAPDemo.start()
            end,
            tag = "auto_start_goap_demo"
        })
    end
end

function createTabDemo()
    print("[TRACE] createTabDemo called")
    local dsl = require("ui.ui_syntax_sugar")
    local panelWidth = 480  -- Increased to fit 7 tabs (Game, Graphics, Audio, Sprites, Inventory, Gallery, Showcase)
    local gallerySafeMargins = {
        left = 24,
        right = panelWidth + 40,
        top = 24,
        bottom = 48,
    }
    
    local tabDef = dsl.strict.root {
        config = {
            color = util.getColor("blackberry"),
            padding = 4,
            emboss = 3,
        },
        children = {
            dsl.strict.tabs {
                id = "demo_tabs",
                activeTab = "game",
                contentMinWidth = 460,  -- Increased to fit 7 tabs
                contentMinHeight = 120,
                tabs = {
                    {
                        id = "game",
                        label = "Game",
                        content = function()
                            return dsl.strict.vbox {
                                config = { padding = 4 },
                                children = {
                                    dsl.strict.text("Game Settings", { fontSize = 16, color = "white", shadow = true }),
                                    dsl.strict.spacer(8),
                                    dsl.strict.text("Speed: Normal", { fontSize = 12, color = "gray_light" }),
                                    dsl.strict.text("Difficulty: Medium", { fontSize = 12, color = "gray_light" }),
                                }
                            }
                        end
                    },
                    {
                        id = "graphics",
                        label = "Graphics",
                        content = function()
                            return dsl.strict.vbox {
                                config = { padding = 4 },
                                children = {
                                    dsl.strict.text("Graphics Settings", { fontSize = 16, color = "white", shadow = true }),
                                    dsl.strict.spacer(8),
                                    dsl.strict.text("Fullscreen: Off", { fontSize = 12, color = "gray_light" }),
                                    dsl.strict.text("VSync: On", { fontSize = 12, color = "gray_light" }),
                                }
                            }
                        end
                    },
                    {
                        id = "audio",
                        label = "Audio",
                        content = function()
                            return dsl.strict.vbox {
                                config = { padding = 4 },
                                children = {
                                    dsl.strict.text("Audio Settings", { fontSize = 16, color = "white", shadow = true }),
                                    dsl.strict.spacer(8),
                                    dsl.strict.text("Master: 100%", { fontSize = 12, color = "gray_light" }),
                                    dsl.strict.text("Music: 80%", { fontSize = 12, color = "gray_light" }),
                                    dsl.strict.text("SFX: 100%", { fontSize = 12, color = "gray_light" }),
                                }
                            }
                        end
                    },
                    {
                        id = "sprites",
                        label = "Sprites",
                        content = function()
                            local SpriteShowcase = require("ui.sprite_ui_showcase")
                            return SpriteShowcase.createShowcase()
                        end
                    },
                    {
                        id = "inventory",
                        label = "Inventory",
                        content = function()
                            local PlayerInventory = require("ui.player_inventory")
                            return dsl.strict.vbox {
                                config = { padding = 8 },
                                children = {
                                    dsl.strict.text("Player Inventory Test", { fontSize = 16, color = "white", shadow = true }),
                                    dsl.strict.spacer(8),
                                    dsl.strict.text("Status: " .. (PlayerInventory.isOpen() and "OPEN" or "CLOSED"), { fontSize = 12, color = "gray_light" }),
                                    dsl.strict.spacer(12),
                                    dsl.strict.button("Open Inventory", {
                                        fontSize = 14,
                                        color = "green_jade",
                                        textColor = "white",
                                        minWidth = 140,
                                        onClick = function()
                                            if playSoundEffect then playSoundEffect("effects", "button-click") end
                                            PlayerInventory.open()
                                            print("[TEST] PlayerInventory.open() called")
                                        end
                                    }),
                                    dsl.strict.spacer(4),
                                    dsl.strict.button("Close Inventory", {
                                        fontSize = 14,
                                        color = "indian_red",
                                        textColor = "white",
                                        minWidth = 140,
                                        onClick = function()
                                            if playSoundEffect then playSoundEffect("effects", "button-click") end
                                            PlayerInventory.close()
                                            print("[TEST] PlayerInventory.close() called")
                                        end
                                    }),
                                    dsl.strict.spacer(4),
                                    dsl.strict.button("Toggle Inventory", {
                                        fontSize = 14,
                                        color = "blue_steel",
                                        textColor = "white",
                                        minWidth = 140,
                                        onClick = function()
                                            if playSoundEffect then playSoundEffect("effects", "button-click") end
                                            PlayerInventory.toggle()
                                            print("[TEST] PlayerInventory.toggle() called - now " .. (PlayerInventory.isOpen() and "OPEN" or "CLOSED"))
                                        end
                                    }),
                                }
                            }
                        end
                    },
                    {
                        id = "gallery",
                        label = "Gallery",
                        content = function()
                            local GalleryViewer = require("ui.showcase.gallery_viewer")
                            return dsl.strict.vbox {
                                config = { padding = 8 },
                                children = {
                                    dsl.strict.text("UI Showcase Gallery", { fontSize = 16, color = "white", shadow = true }),
                                    dsl.strict.spacer(8),
                                    dsl.strict.text("Browse UI component examples", { fontSize = 12, color = "gray_light" }),
                                    dsl.strict.text("with live previews and code.", { fontSize = 12, color = "gray_light" }),
                                    dsl.strict.spacer(12),
                                    dsl.strict.button("Open Gallery", {
                                        fontSize = 14,
                                        color = "green_jade",
                                        textColor = "white",
                                        minWidth = 140,
                                        onClick = function()
                                            if playSoundEffect then playSoundEffect("effects", "button-click") end
                                            -- Let the gallery auto-fit to safe screen bounds
                                            GalleryViewer.showGlobalWithOptions(nil, nil, { safeMargins = gallerySafeMargins })
                                            print("[GALLERY] Showcase gallery opened")
                                        end
                                    }),
                                    dsl.strict.spacer(4),
                                    dsl.strict.button("Close Gallery", {
                                        fontSize = 14,
                                        color = "indian_red",
                                        textColor = "white",
                                        minWidth = 140,
                                        onClick = function()
                                            if playSoundEffect then playSoundEffect("effects", "button-click") end
                                            GalleryViewer.hideGlobal()
                                            print("[GALLERY] Showcase gallery closed")
                                        end
                                    }),
                                }
                            }
                        end
                    },
                    {
                        id = "showcase",
                        label = "Showcase",
                        content = function()
                            local FeatureShowcase = require("ui.showcase.feature_showcase")
                            return dsl.strict.vbox {
                                config = { padding = 8 },
                                children = {
                                    dsl.strict.text("Feature Showcase", { fontSize = 16, color = "white", shadow = true }),
                                    dsl.strict.spacer(8),
                                    dsl.strict.text("View all Phase 1-6 features", { fontSize = 12, color = "gray_light" }),
                                    dsl.strict.text("with automated validation.", { fontSize = 12, color = "gray_light" }),
                                    dsl.strict.spacer(12),
                                    dsl.strict.button("Open Showcase", {
                                        fontSize = 14,
                                        color = "green_jade",
                                        textColor = "white",
                                        minWidth = 140,
                                        onClick = function()
                                            if playSoundEffect then playSoundEffect("effects", "button-click") end
                                            FeatureShowcase.show()
                                            print("[SHOWCASE] Feature showcase opened")
                                        end
                                    }),
                                    dsl.strict.spacer(4),
                                    dsl.strict.button("Close Showcase", {
                                        fontSize = 14,
                                        color = "indian_red",
                                        textColor = "white",
                                        minWidth = 140,
                                        onClick = function()
                                            if playSoundEffect then playSoundEffect("effects", "button-click") end
                                            FeatureShowcase.hide()
                                            print("[SHOWCASE] Feature showcase closed")
                                        end
                                    }),
                                }
                            }
                        end
                    },
                }
            }
        }
    }
    
    mainMenuEntities.tab_demo_uibox = dsl.spawn({ x = globals.screenWidth() - panelWidth - 20, y = 20 }, tabDef)
    ui.box.set_draw_layer(mainMenuEntities.tab_demo_uibox, "ui")

    -- Auto-open gallery for testing (one-shot, guarded by module-level flag)
    if os.getenv and os.getenv("AUTO_TEST_GALLERY") == "1" and not _G._galleryTestScheduled then
        _G._galleryTestScheduled = true
        print("[GALLERY_TEST] Scheduling gallery auto-open in 0.5s")
        local timer = require("core.timer")
        timer.after(0.5, function()
            print("[GALLERY_TEST] Timer fired!")
            if _G._galleryTestOpened then
                print("[GALLERY_TEST] Gallery already opened, skipping")
                return
            end
            _G._galleryTestOpened = true
            local ok, err = pcall(function()
                local GalleryViewer = require("ui.showcase.gallery_viewer")
                print("[GALLERY_TEST] Opening gallery (auto-fit)")
                GalleryViewer.showGlobalWithOptions(nil, nil, { safeMargins = gallerySafeMargins })
                print("[GALLERY_TEST] Gallery opened successfully")
            end)
            if not ok then
                print("[GALLERY_TEST] ERROR:", err)
            end
        end)
    end

    -- Auto-open showcase for testing (one-shot, guarded by module-level flag)
    if os.getenv and os.getenv("AUTO_TEST_SHOWCASE") == "1" and not _G._showcaseTestScheduled then
        _G._showcaseTestScheduled = true
        print("[SHOWCASE_TEST] Scheduling showcase auto-open in 0.5s")
        local timer = require("core.timer")
        timer.after(0.5, function()
            print("[SHOWCASE_TEST] Timer fired!")
            if _G._showcaseTestOpened then
                print("[SHOWCASE_TEST] Showcase already opened, skipping")
                return
            end
            _G._showcaseTestOpened = true
            local ok, err = pcall(function()
                local FeatureShowcase = require("ui.showcase.feature_showcase")
                print("[SHOWCASE_TEST] Opening showcase")
                FeatureShowcase.show()
                print("[SHOWCASE_TEST] Showcase opened successfully")
                -- Print verification results
                local results = FeatureShowcase.getVerificationResults()
                if results and results.categories then
                    print("[SHOWCASE_TEST] Verification results:")
                    for catId, catData in pairs(results.categories) do
                        print(string.format("  %s: %d/%d", catId, catData.pass, catData.total))
                    end
                end
            end)
            if not ok then
                print("[SHOWCASE_TEST] ERROR:", err)
            end
        end)
    end
end

function createPatchNotesButton()
    local dsl = require("ui.ui_syntax_sugar")
    local ui_scale = require("ui.ui_scale")

    local hasUnread = PatchNotesModal.hasUnread()
    local iconSize = ui_scale.ui(32)
    local HOVER_SCALE = 1.15  -- Per spec: simple scale up

    -- Icon-only button with scale hover effect
    local buttonDef = dsl.strict.root {
        config = {
            color = "transparent",  -- No background per spec
            padding = ui_scale.ui(8),
            hover = true,
            buttonCallback = function()
                if playSoundEffect then
                    playSoundEffect("effects", "button-click")
                end
                PatchNotesModal.open()
            end,
            initFunc = function(reg, entity)
                -- Set up hover handlers for scale effect
                local go = component_cache.get(entity, GameObject)
                if go and go.methods then
                    go.methods.onHover = function()
                        local transform = component_cache.get(entity, Transform)
                        if transform then
                            transform.scale = HOVER_SCALE
                        end
                    end
                    go.methods.onStopHover = function()
                        local transform = component_cache.get(entity, Transform)
                        if transform then
                            transform.scale = 1.0
                        end
                    end
                end
            end,
        },
        children = {
            dsl.strict.text("📋", {  -- Icon placeholder for patch notes
                fontSize = iconSize,
                color = "white",
            })
        }
    }

    mainMenuEntities.patch_notes_button = dsl.spawn(
        { x = 20, y = globals.screenHeight() - 60 },
        buttonDef,
        "ui",
        100
    )
    ui.box.set_draw_layer(mainMenuEntities.patch_notes_button, "ui")

    mainMenuEntities._patchNotesHasUnread = hasUnread
end

function createLanguageCornerButton()
    local dsl = require("ui.ui_syntax_sugar")
    local ui_scale = require("ui.ui_scale")

    local iconSize = ui_scale.ui(32)
    local HOVER_SCALE = 1.15  -- Per spec: simple scale up

    -- Icon-only button with scale hover effect (bottom-right corner)
    local buttonDef = dsl.strict.root {
        config = {
            color = "transparent",  -- No background per spec
            padding = ui_scale.ui(8),
            hover = true,
            buttonCallback = function()
                if playSoundEffect then
                    playSoundEffect("effects", "button-click")
                end
                -- Toggle language
                if localization.getCurrentLanguage() == "en_us" then
                    record_telemetry("language_changed", { from = "en_us", to = "ko_kr", session_id = telemetry_session_id() })
                    localization.setCurrentLanguage("ko_kr")
                else
                    record_telemetry("language_changed", { from = "ko_kr", to = "en_us", session_id = telemetry_session_id() })
                    localization.setCurrentLanguage("en_us")
                end
            end,
            initFunc = function(reg, entity)
                -- Set up hover handlers for scale effect
                local go = component_cache.get(entity, GameObject)
                if go and go.methods then
                    go.methods.onHover = function()
                        local transform = component_cache.get(entity, Transform)
                        if transform then
                            transform.scale = HOVER_SCALE
                        end
                    end
                    go.methods.onStopHover = function()
                        local transform = component_cache.get(entity, Transform)
                        if transform then
                            transform.scale = 1.0
                        end
                    end
                end
            end,
        },
        children = {
            dsl.strict.text("🌐", {  -- Icon placeholder for language
                fontSize = iconSize,
                color = "white",
            })
        }
    }

    mainMenuEntities.language_button_uibox = dsl.spawn(
        { x = globals.screenWidth() - 60, y = globals.screenHeight() - 60 },
        buttonDef,
        "ui",
        100
    )
    ui.box.set_draw_layer(mainMenuEntities.language_button_uibox, "ui")
end

function drawPatchNotesBadge()
    if not mainMenuEntities.patch_notes_button then return end
    if not mainMenuEntities._patchNotesHasUnread then return end
    if not PatchNotesModal.hasUnread() then 
        mainMenuEntities._patchNotesHasUnread = false
        return 
    end
    
    -- Get position from UIBoxComponent's uiRoot (UIBox entities store transform there)
    local boxComp = component_cache.get(mainMenuEntities.patch_notes_button, UIBoxComponent)
    if not boxComp or not boxComp.uiRoot then return end
    
    local t = component_cache.get(boxComp.uiRoot, Transform)
    if not t then return end
    
    local badgeX = t.actualX + t.actualW - 4
    local badgeY = t.actualY + 4
    local badgeRadius = 6
    local space = layer.DrawCommandSpace.Screen
    
    command_buffer.queueDrawCenteredEllipse(layers.ui, function(c)
        c.x = badgeX
        c.y = badgeY
        c.rx = badgeRadius
        c.ry = badgeRadius
        c.color = util.getColor("red")
    end, 150, space)
end

function startGameButtonCallback()
    clearMainMenu() -- clear the main menu
                    
    record_telemetry("start_game_clicked", { scene = "main_menu" })
    
    --TODO: add full screeen transition shader, tween the value of that
    add_fullscreen_shader("screen_tone_transition") -- Add the fade out shader
    
    fadeOutMusic("main-menu", 1.0) -- Fade out the main menu music over 1 second
    
    -- 0 is dark, 1 is light
    globalShaderUniforms:set("screen_tone_transition", "position", 1)
    
    timer.tween_scalar(
        1.0, -- duration in seconds
        function() return globalShaderUniforms:get("screen_tone_transition", "position") end, -- getter
        function(v) globalShaderUniforms:set("screen_tone_transition", "position", v) end, -- setter
        0 -- target value
    )
    
    --TODO: change to main game state
    timer.after(
        1.0, -- delay in seconds
        function()
            log_debug("Changing game state to IN_GAME") -- Debug message to indicate the game state change
            timer.tween_scalar(
                1.0, -- duration in seconds
                function() return globalShaderUniforms:get("screen_tone_transition", "position") end, -- getter
                function(v) globalShaderUniforms:set("screen_tone_transition", "position", v) end, -- setter
                1 -- target value
                
            )
            changeGameState(GAMESTATE.IN_GAME) -- Change the game state to IN_GAME
            
        end
    )
    timer.after(
        2.2, -- delay in seconds
        function()
            remove_fullscreen_shader("screen_tone_transition") -- Remove the fade out shader
            add_fullscreen_shader("palette_quantize") -- Apply palette quantize globally
        end,
        "main_menu_to_game_state_change" -- unique tag for this timer
    )
    
end
function clearMainMenu()

    -- RenderGroupsTest.cleanup()
    InventoryGridDemo.cleanup()

    -- Clean up the new MainMenuButtons module
    if mainMenuEntities.mainMenuButtons then
        mainMenuEntities.mainMenuButtons.destroy()
        mainMenuEntities.mainMenuButtons = nil
    end

    for _, entity in pairs(mainMenuEntities) do
        if type(entity) == "number" and registry:valid(entity) and registry:has(entity, Transform) then
            local transform = component_cache.get(entity, Transform)
            if transform then
                transform.actualY = globals.screenHeight() + 500
            end
        end
    end
    
    -- move global.ui.logo out of view
    if globals.ui.logo and entity_cache.valid(globals.ui.logo) then
        local logoTransform = component_cache.get(globals.ui.logo, Transform)
        if logoTransform then
            logoTransform.actualY = globals.screenHeight() + 500 -- push it down out of view
        end
    end
    
    
    -- delete tiemrs
    timer.kill_group(MAIN_MENU_TIMER_GROUP)
    timer.cancel("logo_text_update") -- cancel the logo text update timer
    timer.cancel("logo_text_pulse") -- cancel the logo text pulse timer
    timer.cancel(MAIN_MENU_PHASE_TIMER_TAG) -- cancel the shape phase timer
    remove_layer_shader("sprites", "pixelate_image")

    if mainMenuEntities.main_menu_uibox and ui.box and ui.box.Remove then
        ui.box.Remove(registry, mainMenuEntities.main_menu_uibox)
        mainMenuEntities.main_menu_uibox = nil
    end
    if mainMenuEntities.language_button_uibox and ui.box and ui.box.Remove then
        ui.box.Remove(registry, mainMenuEntities.language_button_uibox)
        mainMenuEntities.language_button_uibox = nil
    end
    if mainMenuEntities.patch_notes_button and ui.box and ui.box.Remove then
        ui.box.Remove(registry, mainMenuEntities.patch_notes_button)
        mainMenuEntities.patch_notes_button = nil
    end
    PatchNotesModal.destroy()
    -- Clean up GOAP demo if running
    local ok, GOAPDemo = pcall(require, "demos.goap_ai_demo")
    if ok and GOAPDemo and GOAPDemo.isActive and GOAPDemo.isActive() then
        GOAPDemo.stop()
    end
    if mainMenuEntities.goap_demo_button and ui.box and ui.box.Remove then
        ui.box.Remove(registry, mainMenuEntities.goap_demo_button)
        mainMenuEntities.goap_demo_button = nil
    end
    if mainMenuEntities.inventory_test_button and ui.box and ui.box.Remove then
        ui.box.Remove(registry, mainMenuEntities.inventory_test_button)
        mainMenuEntities.inventory_test_button = nil
    end
    -- Clean up gallery viewer if open
    local GalleryViewer = require("ui.showcase.gallery_viewer")
    GalleryViewer.destroyGlobal()
    if mainMenuEntities.tab_demo_uibox and ui.box and ui.box.Remove then
        ui.box.Remove(registry, mainMenuEntities.tab_demo_uibox)
        local dsl = require("ui.ui_syntax_sugar")
        dsl.cleanupTabs("demo_tabs")
        mainMenuEntities.tab_demo_uibox = nil
    end
    if entity_cache and entity_cache.valid and entity_cache.valid(globals.ui.logo) then
        registry:destroy(globals.ui.logo)
        globals.ui.logo = nil
    end
end

boards = {}



function initMainGame()
    
    print("Runtime:", jit and jit.version or _VERSION)

    
    setTrackVolume("main-menu", 0.0)
    
    playPlaylist({
        "lo_fi_wash_over_main",
        "lo_fi_wash_over_intensity_1",
        "lo_fi_wash_over_intensity_2",
        
    }, true) -- loop.

    
    log_debug("Initializing main game...") -- Debug message to indicate the game is starting
    currentGameState = GAMESTATE.IN_GAME -- Set the game state to IN_GAME
    record_telemetry_once("scene_main_game", "scene_enter", { scene = "main_game" })
    
    initPlanningPhase()
    initActionPhase()
    initPlanningUI()
    initShopPhase()

    -- begin in planning state by default
    startPlanningPhase()
    
    -- run debug ui every frame.
    timer.run_every_render_frame(
        function()
            debugUI()
        end
    )
    
    
    if os.getenv("RUN_PROJECTILE_TESTS") == "1" then
        record_telemetry("debug_tests_enabled", { suite = "projectile" })
        ProjectileSystemTest = require("test_projectiles")
    end

    local runWandTests = os.getenv("RUN_WAND_TESTS") == "1"
    if runWandTests then
        record_telemetry("debug_tests_enabled", { suite = "wand" })
        local WandTests = require("wand.wand_test_examples")
        WandTests.runAllTests()
    end

    -- LightingDemo.start()

end

function changeGameState(newState)
    -- Check if the new state is different from the current state
    if currentGameState == GAMESTATE.MAIN_MENU and newState ~= GAMESTATE.MAIN_MENU then
        clearMainMenu()
    end

    if newState == GAMESTATE.MAIN_MENU then
        initMainMenu()
    elseif newState == GAMESTATE.IN_GAME then
        initMainGame()
    elseif newState == GAMESTATE.SIM_GAME then
        sim_scene.init()
    else
        error("Invalid game state: " .. tostring(newState))
    end
    currentGameState = newState
    globals.currentGameState = newState -- Update the current game state
end




ProjectileSystemTest = nil
  
-- Main function to initialize the game. Called at the start of the game.
function main.init()
    log_debug("Game initializing...") -- Debug message to indicate the game is initializing
    record_telemetry_once("session_start", "session_start", {
        session_id = telemetry_session_id(),
        scene = "boot"
    })
    record_telemetry_once("lua_runtime_init", "lua_runtime_init", {
        lua = _VERSION,
        jit = jit and jit.version or "none"
    })

    -- Initialize save system early
    SaveManager.init()

    -- Load modules that register collectors
    Statistics = require("core.statistics") -- Global for C++ debug UI access

    -- Register grid inventory save collector (registers itself with SaveManager on require)
    local GridInventorySave = require("core.grid_inventory_save")

    math.randomseed(12345)
    if PROFILE_ENABLED then
        profile.start()
    end

    -- Initialize shader uniforms in Lua (migrating from C++).
    if globalShaderUniforms then
        shader_uniforms.init()
    else
        log_warn("shader_uniforms.init skipped: globalShaderUniforms not ready")
    end

    
    -- register color palette "RESURRECT-64"
    palette.register{
        names   = {"Blackberry", "Dark Lavender", "Muted Plum", "Dusty Rose", "Warm Taupe", "Shadow Mauve", "Slate Purple", "Soft Steel", "Pale Mint", "White", "Dark Crimson", "Fiery Red", "Tomato Red", "Apricot", "Burgundy", "Coral Red", "Tangerine", "Goldenrod", "Sunflower", "Mulberry", "Chestnut", "Rust", "Amber", "Marigold", "Espresso", "Olive Drab", "Moss Green", "Chartreuse", "Lemon Chiffon", "Deep Teal", "Jade Green", "Seafoam Green", "Mint Green", "Lime", "Charcoal", "Forest Slate", "Verdigris", "Sage", "Olive Mist", "Teal Blue", "Cyan Green", "Turquoise", "Aqua", "Pale Aqua", "Midnight Blue", "Indigo", "Royal Blue", "Sky Blue", "Baby Blue", "Plum", "Violet", "Purple Orchid", "Lavender", "Pink Blush", "Wine", "Rosewood", "Blush Pink", "Coral Pink", "Deep Magenta", "Raspberry", "Fuchsia", "Pastel Pink", "Peach", "Apricot Cream" }
    }
    
    -- input binding test
    input.bind("do_something", { device="keyboard", key=KeyboardKey.KEY_SPACE, trigger="Pressed", context="gameplay" })
    -- input.bind("do_something_else", { device="keyboard", key=KeyboardKey.KEY_SPACE, trigger="Released", context="gameplay" })
    -- input.set_context("gameplay") -- set the input context to gameplay
    input.bind("mouse_click", { device="mouse", key=MouseButton.BUTTON_LEFT, trigger="Pressed", context="gameplay" })
    
    

    
    -- timer.every(0.16, function()
        
        -- if input.action_pressed("do_something") then
        --     log_debug("Space key pressed!") -- Debug message to indicate the space key was pressed
        -- end
        -- if input.action_released("do_something") then
        --     log_debug("Space key released!") -- Debug message to indicate the space key was released
        -- end
    --     if input.action_down("do_something") then
    --         log_debug("Space key down!") -- Debug message to indicate the space key is being held down
            
    --         local mouseT           = component_cache.get(globals.cursor(), Transform)
            
            
    --         -- Try one at a time to see effects clearly
    --         -- TestCircularBurst()
    --         -- TestFan()
    --         -- TestImageBurst()
    --         -- TestRing()
    --         -- TestRectArea()
    --         -- TestCone()
    --         -- TestFountain()
    --         TestExplosion()
            
    --         -- spawnGrowingCircleParticle(mouseT.visualX, mouseT.visualY, 100, 100, 0.2)
            
    --         -- spawnCircularBurstParticles(
    --         --     mouseT.visualX, 
    --         --     mouseT.visualY, 
    --         --     5, -- count
    --         --     0.5, -- seconds
    --         --     util.getColor("blue"), -- start color
    --         --     util.getColor("purple"), -- end color
    --         --     "outCubic", -- from util.easing
    --         --     "screen" -- screen space
    --         -- )
            
    --         -- slowTime(5, 0.2) -- slow time to 50% for 0.2 seconds
    --     end
        
    -- end)
    
    -- enable debug mode if the environment variable is set
    if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
        require("lldebugger").start()
    end

    -- Run DX Audit smoke test to verify new Lua APIs work correctly
    -- Set RUN_DX_AUDIT_TEST=1 to enable, or always run in debug builds
    -- local runDxAuditTest = os.getenv("RUN_DX_AUDIT_TEST") == "1"
    local runDxAuditTest = true
    if runDxAuditTest then
        local ok, test_module = pcall(require, "tests.test_dx_audit_changes")
        if ok and test_module and test_module.run then
            log_debug("[DX Audit] Running smoke test...")
            local results = test_module.run()
            if results.failed > 0 then
                log_warn(string.format("[DX Audit] %d test(s) FAILED - check console output", results.failed))
            else
                log_debug(string.format("[DX Audit] All %d tests passed!", results.passed))
            end
        else
            log_warn("[DX Audit] Could not load test module: " .. tostring(test_module))
        end
    end

    -- Run UIValidator tests (set RUN_UI_VALIDATOR_TESTS=1 to enable)
    local runUIValidatorTests = os.getenv("RUN_UI_VALIDATOR_TESTS") == "1"
    if runUIValidatorTests then
        local ok, test_module = pcall(require, "tests.run_ui_validator_tests")
        if ok and test_module and test_module.run then
            log_debug("[UIValidator] Running tests...")
            local success = test_module.run()
            if success then
                log_debug("[UIValidator] All tests passed!")
            else
                log_warn("[UIValidator] Some tests FAILED - check console output")
            end
        else
            log_warn("[UIValidator] Could not load test module: " .. tostring(test_module))
        end
    end

    -- Run real PlayerInventory validation (set RUN_REAL_INVENTORY_TEST=1 to enable)
    local runRealInventoryTest = os.getenv("RUN_REAL_INVENTORY_TEST") == "1"
    if runRealInventoryTest then
        local ok, test_module = pcall(require, "tests.test_real_player_inventory")
        if ok and test_module and test_module.run then
            log_debug("[RealInventoryTest] Running real PlayerInventory validation...")
            test_module.run()
        else
            log_warn("[RealInventoryTest] Could not load test module: " .. tostring(test_module))
        end
    end

    -- Run UI Filler demo (set RUN_UI_FILLER_DEMO=1 to enable)
    local runUIFillerDemo = os.getenv("RUN_UI_FILLER_DEMO") == "1"
    local autoExitAfterDemo = os.getenv("AUTO_EXIT_AFTER_DEMO") == "1"
    if runUIFillerDemo then
        timer.after(0.5, function()
            log_debug("[UIFillerDemo] Starting UI Filler demo...")
            UIFillerDemo.start()

            if autoExitAfterDemo then
                -- Exit after all demos complete (12 demos * ~6s each = ~72s, add buffer)
                timer.after(90, function()
                    log_debug("[UIFillerDemo] Auto-exit after demo")
                    os.exit(0)
                end, "ui_filler_demo_exit", "ui_filler_demo")
            end
        end, "ui_filler_demo_start", "ui_filler_demo")
    end

    -- Legacy tooltip hide timer - no longer needed with DSL tooltips
    -- Tooltips now hide via onStopHover handlers in the DSL system
    -- This timer was used for mouse-following tooltips which are being phased out
    -- timer.every(0.2, function()
    --     -- tracy.zoneBeginN("Tooltip Hide Timer Tick") -- just some default depth to avoid bugs
    --     if entity_cache.valid(globals.inputState.cursor_hovering_target) == false or globals.inputState.cursor_hovering_target == globals.gameWorldContainerEntity()  then
    --         hideTooltip() -- Hide the tooltip if the cursor is not hovering over any target
    --     end
    --     -- tracy.zoneEnd()
    -- end,
    -- 0, -- start immediately)
    -- true,
    -- nil, -- no "after" callback
    -- "tooltip_hide_timer" -- unique tag for this timer
     -- )
    
    changeGameState(GAMESTATE.SIM_GAME) -- Initialize the game in the SIM_GAME state

    if autoStartMainGameEnv and currentGameState ~= GAMESTATE.SIM_GAME then
        timer.after(0.25, function()
            print("[DEBUG ACTION] AUTO_START_MAIN_GAME triggering startGameButtonCallback()")
            if startGameButtonCallback then
                startGameButtonCallback()
            else
                print("[DEBUG ACTION] AUTO_START_MAIN_GAME fallback state switch")
                changeGameState(GAMESTATE.IN_GAME)
            end
        end, "auto_start_main_game")
    end
    
end

local prevFrameCounter = 0

local profileFrameCounter = 0
local printProfileEveryNFrames = 1 -- print profile every N frames


physicsTickCounter = 0
function main.update(dt)
    -- tracy.zoneBeginN("lua main.update") -- just some default depth to avoid bugs
    local currentRenderFrameCount = main_loop.data.renderFrame
    local isRenderFrame = (currentRenderFrameCount ~= prevFrameCounter)
    prevFrameCounter = currentRenderFrameCount
    
    if PROFILE_ENABLED then
        profileFrameCounter = profileFrameCounter + 1
        if profileFrameCounter >= printProfileEveryNFrames then
            profileFrameCounter = 0
            local rep = profile.report(30) -- print top X functions
            log_debug("Profile Report:\n" .. rep)
            profile.reset()
        end
    end
    -- begin frame for cache.
    component_cache.begin_frame()

    
    -- timer updates.
    physicsTickCounter = main_loop.data.physicsTicks
    
    timer.update(dt, isRenderFrame) -- Update the timer system
    timer.update_physics_step() -- Update the timer system for physics steps
    
    
    -- caching systems.
    entity_cache.update_frame() -- Update the entity cache for the current frame

    component_cache.update_frame() -- Update the component cache for the current frame
    
    local isPaused = (globals.gamePaused or currentGameState == GAMESTATE.MAIN_MENU)

    if not isPaused then
        -- Node system (lua side)
        Node.update_all(dt) -- Update all nodes with update() functions
    end

    -- TextBuilder system - MUST be called every frame to queue text draw commands
    -- Runs even when paused so UI text still renders
    Text.update(dt)

    -- SIM_GAME update - runs when not paused
    if currentGameState == GAMESTATE.SIM_GAME and not isPaused then
        sim_scene.update(dt)
    end

    if (currentGameState == GAMESTATE.MAIN_MENU) then
        globals.main_menu_elapsed_time = globals.main_menu_elapsed_time + dt
        SpecialItem.update(dt)
        SpecialItem.draw()
        PatchNotesModal.update(dt)
        PatchNotesModal.draw()
        drawPatchNotesBadge()

        -- Keyboard navigation for main menu buttons
        if mainMenuEntities.mainMenuButtons and IsKeyPressed then
            if IsKeyPressed(KEY_UP) or IsKeyPressed(KEY_W) then
                mainMenuEntities.mainMenuButtons.handleKeyDown("UP")
            elseif IsKeyPressed(KEY_DOWN) or IsKeyPressed(KEY_S) then
                mainMenuEntities.mainMenuButtons.handleKeyDown("DOWN")
            elseif IsKeyPressed(KEY_ENTER) or IsKeyPressed(KEY_SPACE) then
                mainMenuEntities.mainMenuButtons.handleKeyDown("ENTER")
            end
        end
    end

    if isPaused then
        component_cache.end_frame()
        return -- If the game is paused, do not update gameplay objects
    end

    if ProjectileSystemTest ~= nil then
        ProjectileSystemTest.update(dt)
    end
    
    -- tracy.zoneEnd()
    
    -- end frame for cache.
    component_cache.end_frame()
end

function main.draw(dt)
    if currentGameState == GAMESTATE.SIM_GAME then
        sim_scene.draw()
    end
end
