--[[
================================================================================
TEST: Achievements Deserialize Function
================================================================================
Tests that achievements.deserialize correctly restores state from serialized data
and properly ignores unknown achievement IDs (e.g., from old save files).

Run with: lua test_achievements_deserialize.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached modules if re-running
package.loaded["idle_game.achievements"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Achievements Deserialize - Unknown ID Filtering", function()

    local achievements = nil

    t.before_each(function()
        achievements = require("idle_game.achievements")
    end)

    -- Test 1: Deserialize with valid achievement IDs
    t.it("correctly restores known achievement states", function()
        achievements.init()

        -- Create save state with known achievement IDs
        local save_state = {
            unlocked = {
                res_wood_100 = true,
                res_gold_25 = true,
                crt_total_25 = false,  -- Explicitly false
                upg_first_purchase = true
            },
            game_time = 123.45
        }

        achievements.deserialize(save_state)

        -- Verify known achievements were restored correctly
        t.expect(achievements.is_unlocked("res_wood_100")).to_be_truthy()
        t.expect(achievements.is_unlocked("res_gold_25")).to_be_truthy()
        t.expect(achievements.is_unlocked("crt_total_25")).to_be_falsy()
        t.expect(achievements.is_unlocked("upg_first_purchase")).to_be_truthy()

        -- Verify game time was restored
        t.expect(achievements.get_game_time()).to_equal(123.45)
    end)

    -- Test 2: Deserialize with unknown achievement IDs (should be ignored)
    t.it("ignores unknown achievement IDs from old save files", function()
        achievements.init()

        -- Create save state with mix of known and unknown achievement IDs
        local save_state = {
            unlocked = {
                res_wood_100 = true,              -- Known ✓
                old_achievement_removed = true,    -- Unknown - should be ignored
                legacy_popup_10 = true,           -- Unknown - should be ignored
                res_gold_25 = true,               -- Known ✓
                deprecated_speed_upgrade = false, -- Unknown - should be ignored
                crt_builder_exists = true         -- Known ✓
            },
            game_time = 67.89
        }

        achievements.deserialize(save_state)

        -- Verify known achievements were restored
        t.expect(achievements.is_unlocked("res_wood_100")).to_be_truthy()
        t.expect(achievements.is_unlocked("res_gold_25")).to_be_truthy()
        t.expect(achievements.is_unlocked("crt_builder_exists")).to_be_truthy()

        -- Verify game time was restored
        t.expect(achievements.get_game_time()).to_equal(67.89)

        -- Verify that trying to check unknown IDs fails appropriately
        local success, error_msg = pcall(function()
            return achievements.is_unlocked("old_achievement_removed")
        end)
        t.expect(success).to_be_falsy()
        t.expect(error_msg).to_be_type("string")
    end)

    -- Test 3: Deserialize with nil state (should initialize cleanly)
    t.it("initializes cleanly when given nil state", function()
        -- First, unlock some achievements
        achievements.init()
        achievements.unlock("res_wood_100", 100)

        -- Then deserialize nil state (should reset everything)
        achievements.deserialize(nil)

        -- Verify everything is reset
        t.expect(achievements.is_unlocked("res_wood_100")).to_be_falsy()
        t.expect(achievements.get_game_time()).to_equal(0)
    end)

    -- Test 4: Deserialize with empty state
    t.it("handles empty state gracefully", function()
        achievements.init()

        local empty_state = {}
        achievements.deserialize(empty_state)

        -- Verify defaults are used
        t.expect(achievements.get_game_time()).to_equal(0)

        -- Verify no achievements are unlocked
        local all_achievements = achievements.get_all()
        for id, achievement in pairs(all_achievements) do
            t.expect(achievements.is_unlocked(id)).to_be_falsy()
        end
    end)

    -- Test 5: Deserialize with malformed unlocked data
    t.it("handles malformed unlocked data safely", function()
        achievements.init()

        local malformed_state = {
            unlocked = {
                res_wood_100 = "not_boolean",     -- Invalid type
                res_gold_25 = nil,                -- nil value
                crt_total_25 = 1,                 -- Non-boolean truthy
                upg_first_purchase = 0            -- Non-boolean falsy
            },
            game_time = 42.0
        }

        achievements.deserialize(malformed_state)

        -- Verify only proper boolean true values are treated as unlocked
        t.expect(achievements.is_unlocked("res_wood_100")).to_be_falsy()  -- "not_boolean" != true
        t.expect(achievements.is_unlocked("res_gold_25")).to_be_falsy()   -- nil != true
        t.expect(achievements.is_unlocked("crt_total_25")).to_be_falsy()  -- 1 != true
        t.expect(achievements.is_unlocked("upg_first_purchase")).to_be_falsy()  -- 0 != true

        t.expect(achievements.get_game_time()).to_equal(42.0)
    end)

    -- Test 6: Round-trip serialization/deserialization
    t.it("preserves state through serialize/deserialize cycle", function()
        achievements.init()

        -- Unlock some achievements
        achievements.unlock("res_wood_100", 100)
        achievements.unlock("crt_builder_exists", 1)

        -- Simulate game time passage
        achievements.update(15.5)  -- Add 15.5 seconds

        -- Serialize current state
        local saved_state = achievements.serialize()

        -- Reset and deserialize
        achievements.init()
        achievements.deserialize(saved_state)

        -- Verify achievements preserved
        t.expect(achievements.is_unlocked("res_wood_100")).to_be_truthy()
        t.expect(achievements.is_unlocked("crt_builder_exists")).to_be_truthy()
        t.expect(achievements.is_unlocked("res_gold_25")).to_be_falsy()  -- Should remain false

        -- Verify game time preserved
        t.expect(achievements.get_game_time()).to_equal(15.5)
    end)

    -- Test 7: Deserialize state with unknown IDs doesn't affect serialize
    t.it("serialized state only contains known achievement IDs", function()
        achievements.init()

        -- Deserialize state containing unknown IDs
        local contaminated_state = {
            unlocked = {
                res_wood_100 = true,
                unknown_achievement = true,
                another_unknown = false,
                res_gold_25 = true
            },
            game_time = 30.0
        }

        achievements.deserialize(contaminated_state)

        -- Serialize the current state
        local clean_state = achievements.serialize()

        -- Verify serialized state only contains known IDs
        local has_unknown = false
        for id, _ in pairs(clean_state.unlocked or {}) do
            if not achievements.get_all()[id] then
                has_unknown = true
                break
            end
        end
        t.expect(has_unknown).to_be_falsy()

        -- Verify known achievements are preserved
        t.expect(clean_state.unlocked.res_wood_100).to_be_truthy()
        t.expect(clean_state.unlocked.res_gold_25).to_be_truthy()
        t.expect(clean_state.game_time).to_equal(30.0)
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()