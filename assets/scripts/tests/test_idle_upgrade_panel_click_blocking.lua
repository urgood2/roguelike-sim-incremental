-- assets/scripts/tests/test_idle_upgrade_panel_click_blocking.lua
-- Integration test: upgrade panel clicks should not trigger world clicks.

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/tests/?.lua"

local t = require("tests.test_runner")

-- Track calls
local handle_click_calls = 0
local upgrade_handle_calls = 0

-- Stub globals and dependencies before requiring sim_scene
_G.log_debug = function() end
_G.globals = {
    screenWidth = function() return 800 end,
    screenHeight = function() return 600 end,
}
_G.MouseButton = { MOUSE_BUTTON_LEFT = 0 }
_G.input = {
    getMouseWheel = function() return 0 end,
    isMousePressed = function() return true end,
    getMousePos = function() return { x = 790, y = 10 } end,
}

package.preload["idle_game.config"] = function()
    return {
        TILE_SIZE = 10,
        GRID_WIDTH = 5,
        GRID_HEIGHT = 5,
        VIRTUAL_WIDTH = 50,
        VIRTUAL_HEIGHT = 50,
    }
end

package.preload["idle_game.terrain"] = function()
    return {
        update = function() end,
    }
end

package.preload["idle_game.terrain_renderer"] = function()
    return { draw = function() end }
end

package.preload["idle_game.spawner"] = function()
    return { processPendingDestructions = function() end, drawCorpses = function() end }
end

package.preload["idle_game.ui.resource_panel"] = function()
    return { draw = function() end }
end

package.preload["idle_game.input"] = function()
    return {
        set_context = function() end,
        handleClick = function(config)
            handle_click_calls = handle_click_calls + 1
            return 1, 1
        end,
    }
end

package.preload["idle_game.resources"] = function()
    return { update = function() end }
end

package.preload["idle_game.selection"] = function()
    return { selectEntity = function() end, findEntityAtPosition = function() return nil end }
end

package.preload["idle_game.ui.debug_panel"] = function()
    return { draw = function() end }
end

package.preload["idle_game.ui.upgrade_panel"] = function()
    return { draw = function() end }
end

package.preload["idle_game.ui.ui_layout"] = function()
    return { aligned_screen = function(tile_size, w, h) return { width = w, height = h } end }
end

package.preload["idle_game.ui.ascii_resource_panel"] = function()
    return {
        init = function() end,
        update = function() end,
        hit_test = function() return { consumed = false } end,
        draw = function() end,
    }
end

package.preload["idle_game.ui.ascii_upgrade_panel"] = function()
    return {
        init = function() end,
        update = function() end,
        hit_test = function() return true end,
        handle_click = function()
            upgrade_handle_calls = upgrade_handle_calls + 1
            return true
        end,
        scroll_by_wheel = function() end,
        draw = function() end,
    }
end

package.preload["idle_game.ui.toast_renderer"] = function()
    return { update = function() end, draw = function() end }
end

package.preload["idle_game.ui.toast_queue"] = function()
    return { init = function() end, update = function() end }
end

package.preload["idle_game.upgrades"] = function()
    return { get_level = function() return 0 end }
end

package.preload["core.popup"] = function()
    return { at = function() end }
end

package.preload["idle_game.achievements"] = function()
    return {}
end

package.preload["idle_game.achievements_persistence"] = function()
    return {}
end

package.preload["idle_game.terrain_persistence"] = function()
    return {}
end

package.preload["idle_game.achievement_listener"] = function()
    return { init = function() end, update = function() end }
end

local sim_scene = require("idle_game.scenes.sim_scene")

t.describe("Upgrade panel click blocking", function()
    t.it("consumes clicks so world handleClick is not called", function()
        handle_click_calls = 0
        upgrade_handle_calls = 0

        sim_scene.update(0.016)

        t.expect(upgrade_handle_calls).to_be(1)
        t.expect(handle_click_calls).to_be(0)
    end)
end)

t.run()
