--[[
================================================================================
TEST: Idle Game Achievements
================================================================================
Tests unlock behavior, serialization, playtime tracking, and unlocked-id sorting.

Run with: lua assets/scripts/tests/test_idle_achievements.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached module if re-running
package.loaded["idle_game.achievements"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Achievements - Core Functionality", function()

    t.it("unlock() returns true only when threshold met", function()
        local achievements = require("idle_game.achievements")
        achievements.init()

        local unlocked = achievements.unlock("crt_total_25", 24)
        t.expect(unlocked).to_be_falsy()
        t.expect(achievements.is_unlocked("crt_total_25")).to_be_falsy()

        local unlocked_now = achievements.unlock("crt_total_25", 25)
        t.expect(unlocked_now).to_be_truthy()
        t.expect(achievements.is_unlocked("crt_total_25")).to_be_truthy()

        local unlocked_again = achievements.unlock("crt_total_25", 30)
        t.expect(unlocked_again).to_be_falsy()
    end)

    t.it("update() tracks playtime and ignores negative dt", function()
        local achievements = require("idle_game.achievements")
        achievements.init()

        achievements.update(1.5)
        local time_after = achievements.get_game_time()
        t.expect(time_after >= 1.49 and time_after <= 1.51).to_be_truthy()

        achievements.update(-1.0)
        t.expect(achievements.get_game_time()).to_equal(time_after)
    end)

    t.it("serialize()/deserialize() preserves unlocked ids and playtime", function()
        local achievements = require("idle_game.achievements")
        achievements.init()

        achievements.unlock("crt_total_25", 25)
        achievements.unlock("crt_builder_exists", 1)
        achievements.update(5.0)

        local state = achievements.serialize()
        state.unlocked["unknown_id"] = true

        achievements.init()
        t.expect(achievements.is_unlocked("crt_total_25")).to_be_falsy()

        achievements.deserialize(state)
        t.expect(achievements.is_unlocked("crt_total_25")).to_be_truthy()
        t.expect(achievements.is_unlocked("crt_builder_exists")).to_be_truthy()
        t.expect(achievements.get_game_time()).to_equal(state.game_time)
    end)

    t.it("get_unlocked_ids() returns sorted ids", function()
        local achievements = require("idle_game.achievements")
        achievements.init()

        achievements.unlock("crt_specialists_10", 10)
        achievements.unlock("crt_total_25", 25)
        achievements.unlock("crt_builder_exists", 1)

        local unlocked_ids = achievements.get_unlocked_ids()
        t.expect(#unlocked_ids).to_equal(3)
        t.expect(unlocked_ids[1]).to_equal("crt_builder_exists")
        t.expect(unlocked_ids[2]).to_equal("crt_specialists_10")
        t.expect(unlocked_ids[3]).to_equal("crt_total_25")
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()
