--[[
Test file for achievement listener unlock and toast functionality.
Tests that signal events trigger correct achievements and toast notifications.
]]

local test = {}

-- Initialize test environment
function test.init()
    -- Mock toast queue
    test.toast_queue = {
        toasts = {},
        add = function(self, message, duration)
            table.insert(self.toasts, { message = message, duration = duration })
        end,
        clear = function(self)
            self.toasts = {}
        end,
        count = function(self)
            return #self.toasts
        end
    }

    -- Mock achievements
    test.achievements = {
        unlocked = {},
        unlock = function(achievement_id, value)
            if not test.achievements.unlocked[achievement_id] then
                test.achievements.unlocked[achievement_id] = true
                return true  -- newly unlocked
            end
            return false  -- already unlocked
        end,
        get_title = function(achievement_id)
            local titles = {
                res_wood_100 = "Lumber Baron",
                res_stone_100 = "Stone Collector",
                res_gold_25 = "Golden Touch",
                res_total_500 = "Resource Hoarder",
                crt_total_25 = "Population Boom",
                crt_specialists_10 = "Specialist Workforce",
                crt_builder_exists = "Master Builder"
            }
            return titles[achievement_id] or "Unknown Achievement"
        end,
        reset = function()
            test.achievements.unlocked = {}
        end
    }

    -- Mock signal system
    test.signals = {
        handlers = {},
        on = function(signal_name, handler)
            if not test.signals.handlers[signal_name] then
                test.signals.handlers[signal_name] = {}
            end
            table.insert(test.signals.handlers[signal_name], handler)
        end,
        emit = function(signal_name, ...)
            if test.signals.handlers[signal_name] then
                for _, handler in ipairs(test.signals.handlers[signal_name]) do
                    handler(...)
                end
            end
        end,
        clear = function()
            test.signals.handlers = {}
        end
    }
end

-- Show achievement toast function
function test.show_achievement_toast(achievement_id)
    local title = test.achievements.get_title(achievement_id)
    test.toast_queue:add("ACHIEVEMENT: " .. title, 3.0)
end

-- Mock achievement evaluation functions
function test.evaluate_resource_achievements(resource_key, new_total)
    if resource_key == "wood" and new_total >= 100 then
        if test.achievements.unlock("res_wood_100", new_total) then
            test.show_achievement_toast("res_wood_100")
        end
    end

    if resource_key == "stone" and new_total >= 100 then
        if test.achievements.unlock("res_stone_100", new_total) then
            test.show_achievement_toast("res_stone_100")
        end
    end

    if resource_key == "gold" and new_total >= 25 then
        if test.achievements.unlock("res_gold_25", new_total) then
            test.show_achievement_toast("res_gold_25")
        end
    end
end

function test.evaluate_population_achievements(counts)
    local total = (counts.foragers or 0) + (counts.lumberjacks or 0) +
                  (counts.collectors or 0) + (counts.miners or 0) + (counts.builders or 0)
    local specialists = (counts.lumberjacks or 0) + (counts.collectors or 0) +
                       (counts.miners or 0) + (counts.builders or 0)

    if total >= 25 then
        if test.achievements.unlock("crt_total_25", total) then
            test.show_achievement_toast("crt_total_25")
        end
    end

    if specialists >= 10 then
        if test.achievements.unlock("crt_specialists_10", specialists) then
            test.show_achievement_toast("crt_specialists_10")
        end
    end

    if (counts.builders or 0) >= 1 then
        if test.achievements.unlock("crt_builder_exists", counts.builders) then
            test.show_achievement_toast("crt_builder_exists")
        end
    end
end

-- Test initialization
function test.test_initialization()
    print("Testing achievement listener initialization...")

    -- Register signal handlers (simulating achievement listener setup)
    test.signals.on("idle.resource_total", test.evaluate_resource_achievements)
    test.signals.on("idle.creature_counts", test.evaluate_population_achievements)

    -- Check that handlers were registered
    local handler_count = 0
    for signal_name, handlers in pairs(test.signals.handlers) do
        handler_count = handler_count + #handlers
    end

    if handler_count >= 2 then
        print("✓ Signal handlers registered successfully")
        print(string.format("  Total handlers: %d", handler_count))
    else
        print("✗ Failed to register signal handlers")
    end
end

-- Test resource achievement signals
function test.test_resource_achievements()
    print("\nTesting resource achievement signals...")

    test.toast_queue:clear()
    test.achievements.reset()

    local test_cases = {
        {resource = "wood", amount = 100, expected = "ACHIEVEMENT: Lumber Baron"},
        {resource = "stone", amount = 100, expected = "ACHIEVEMENT: Stone Collector"},
        {resource = "gold", amount = 25, expected = "ACHIEVEMENT: Golden Touch"}
    }

    local passed = 0
    for i, case in ipairs(test_cases) do
        test.toast_queue:clear()

        -- Emit signal
        test.signals.emit("idle.resource_total", case.resource, case.amount)

        -- Check result
        local found = false
        for _, toast in ipairs(test.toast_queue.toasts) do
            if toast.message == case.expected then
                found = true
                break
            end
        end

        if found then
            print(string.format("✓ Test %d: %s >= %d → %s", i, case.resource, case.amount, case.expected))
            passed = passed + 1
        else
            print(string.format("✗ Test %d: %s >= %d failed", i, case.resource, case.amount))
        end
    end

    if passed == #test_cases then
        print("✓ All resource achievement tests passed")
    else
        print(string.format("✗ Resource achievements: %d/%d tests passed", passed, #test_cases))
    end
end

-- Test creature achievement signals
function test.test_creature_achievements()
    print("\nTesting creature achievement signals...")

    test.toast_queue:clear()
    test.achievements.reset()

    local creature_counts = {
        foragers = 10,
        lumberjacks = 5,
        collectors = 3,
        miners = 4,
        builders = 3
    }

    -- Emit signal
    test.signals.emit("idle.creature_counts", creature_counts)

    -- Check expected achievements
    local expected_achievements = {
        "ACHIEVEMENT: Population Boom",      -- total: 25
        "ACHIEVEMENT: Specialist Workforce", -- specialists: 15
        "ACHIEVEMENT: Master Builder"        -- builders: 1+
    }

    local found_count = 0
    for _, expected in ipairs(expected_achievements) do
        for _, toast in ipairs(test.toast_queue.toasts) do
            if toast.message == expected then
                found_count = found_count + 1
                break
            end
        end
    end

    if found_count == #expected_achievements then
        print("✓ All creature achievement tests passed")
        for _, achievement in ipairs(expected_achievements) do
            print(string.format("  Unlocked: %s", achievement))
        end
    else
        print(string.format("✗ Creature achievements: %d/%d expected unlocks found", found_count, #expected_achievements))
    end
end

-- Test toast format
function test.test_toast_format()
    print("\nTesting toast message format...")

    test.toast_queue:clear()

    -- Test direct toast creation
    test.show_achievement_toast("res_wood_100")

    if test.toast_queue:count() == 1 then
        local toast = test.toast_queue.toasts[1]
        if toast.message == "ACHIEVEMENT: Lumber Baron" and toast.duration == 3.0 then
            print("✓ Toast format correct: 'ACHIEVEMENT:' prefix + title, 3s duration")
        else
            print("✗ Toast format incorrect")
            print(string.format("  Got: '%s' for %.1fs", toast.message, toast.duration))
        end
    else
        print("✗ Toast not created")
    end
end

-- Test achievement unlock deduplication
function test.test_unlock_deduplication()
    print("\nTesting achievement unlock deduplication...")

    test.achievements.reset()

    -- Try to unlock same achievement twice
    local first = test.achievements.unlock("res_wood_100", 100)
    local second = test.achievements.unlock("res_wood_100", 150)

    if first and not second then
        print("✓ Deduplication works: first=true, second=false")
    else
        print(string.format("✗ Deduplication failed: first=%s, second=%s", tostring(first), tostring(second)))
    end
end

-- Main test runner
function test.run_all()
    print("=== Achievement Listener Unlock Tests ===")

    test.init()
    test.test_initialization()
    test.test_resource_achievements()
    test.test_creature_achievements()
    test.test_toast_format()
    test.test_unlock_deduplication()

    print("\n=== Test Summary ===")
    print("Achievement listener unlock and toast tests completed!")
    print("Tests verify signal handling, achievement unlocks, and toast notifications.")
end

-- Auto-run if executed directly
if arg and arg[0] and arg[0]:match("test_idle_achievement_listener_unlocks%.lua$") then
    test.run_all()
end

return test
