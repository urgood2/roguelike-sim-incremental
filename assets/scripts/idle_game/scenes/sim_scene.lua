-- Minimal idle game scene
local sim_scene = {}

function sim_scene.init()
    print("sim_scene.init() called")
    -- Will add terrain generation here later
end

function sim_scene.update(dt)
    -- Will add entity updates here later
end

function sim_scene.draw()
    -- Queue a colored background to prove scene is rendering (dark green)
    if command_buffer then
        command_buffer.queueClearBackground(Col(50, 100, 50, 255))
    end
end

return sim_scene
