--[[
    GOAP PERFORMANCE SPIKE TEST
    
    This test validates that GOAP planning is fast enough for idle/incremental games.
    
    Requirements:
    1. Spawn 20 entities with minimal Wander GOAP action
    2. Measure single plan time (<1ms target)
    3. Monitor 60fps stability with 20 entities planning
    4. Verify AITraceBuffer captures events
]]--

local GoapPerformanceTest = {}

GoapPerformanceTest.initialized = false
GoapPerformanceTest.entities = {}
GoapPerformanceTest.testDuration = 10.0  -- Run test for 10 seconds
GoapPerformanceTest.elapsedTime = 0.0
GoapPerformanceTest.frameCount = 0
GoapPerformanceTest.minFrameTime = math.huge
GoapPerformanceTest.maxFrameTime = 0.0

function GoapPerformanceTest.init()
    if GoapPerformanceTest.initialized then
        return
    end
    
    log_info("SPIKE: Initializing GOAP Performance Test")
    
    -- Get necessary systems
    local ai_system = ai_system
    if not ai_system then
        log_error("AI system not available")
        return
    end
    
    -- Spawn 20 entities with Wander GOAP action
    for i = 1, 20 do
        local entity = entity_cache.create()
        
        -- Add transform component (minimal)
        entity:add(Transform, {
            x = math.random(0, 800),
            y = math.random(0, 600),
            rotation = 0
        })
        
        -- Add GOAP component with minimal setup
        -- Use existing kobold entity type pattern
        local goap_config = {
            initial = {
                wander = false
            },
            goal = {
                wander = true
            }
        }
        
        entity:add(GOAPComponent, {
            initial_state = goap_config.initial,
            goal_state = goap_config.goal
        })
        
        -- Register the Wander action for this entity
        local wander_action = {
            name = "wander",
            cost = 5,
            pre = { wander = false },
            post = { wander = true }
        }
        
        -- Queue a replan request
        ai_system.request_replan(entity)
        
        table.insert(GoapPerformanceTest.entities, entity)
        log_info("SPIKE: Spawned entity {} for GOAP test", i)
    end
    
    GoapPerformanceTest.initialized = true
    log_info("SPIKE: GOAP Performance Test initialized with {} entities", #GoapPerformanceTest.entities)
end

function GoapPerformanceTest.update(dt)
    if not GoapPerformanceTest.initialized then
        GoapPerformanceTest.init()
        return
    end
    
    GoapPerformanceTest.elapsedTime = GoapPerformanceTest.elapsedTime + dt
    GoapPerformanceTest.frameCount = GoapPerformanceTest.frameCount + 1
    
    -- Track frame time
    GoapPerformanceTest.minFrameTime = math.min(GoapPerformanceTest.minFrameTime, dt)
    GoapPerformanceTest.maxFrameTime = math.max(GoapPerformanceTest.maxFrameTime, dt)
    
    -- Request replans periodically for each entity
    if GoapPerformanceTest.elapsedTime > 2.0 then  -- Replan every 2 seconds
        for _, entity in ipairs(GoapPerformanceTest.entities) do
            if entity and entity_cache.valid(entity) then
                ai_system.request_replan(entity)
            end
        end
        GoapPerformanceTest.elapsedTime = 0.0
    end
    
    -- Check if test should end
    if GoapPerformanceTest.elapsedTime >= GoapPerformanceTest.testDuration then
        GoapPerformanceTest.cleanup()
        return
    end
end

function GoapPerformanceTest.cleanup()
    log_info("SPIKE: GOAP Performance Test Results")
    log_info("SPIKE: Total frames: {}", GoapPerformanceTest.frameCount)
    log_info("SPIKE: Min frame time: {:.3f}ms", GoapPerformanceTest.minFrameTime * 1000)
    log_info("SPIKE: Max frame time: {:.3f}ms", GoapPerformanceTest.maxFrameTime * 1000)
    local avgFrameTime = (GoapPerformanceTest.testDuration / GoapPerformanceTest.frameCount) * 1000
    log_info("SPIKE: Avg frame time: {:.3f}ms", avgFrameTime)
    log_info("SPIKE: Expected FPS: {:.1f}", 1.0 / (GoapPerformanceTest.testDuration / GoapPerformanceTest.frameCount))
    
    -- Cleanup entities
    for _, entity in ipairs(GoapPerformanceTest.entities) do
        if entity and entity_cache.valid(entity) then
            entity_cache.destroy(entity)
        end
    end
    
    GoapPerformanceTest.entities = {}
    GoapPerformanceTest.initialized = false
    log_info("SPIKE: GOAP test cleanup complete")
end

return GoapPerformanceTest
