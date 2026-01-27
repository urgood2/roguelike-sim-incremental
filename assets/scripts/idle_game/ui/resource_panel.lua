local resource_panel = {}

local resources = require("idle_game.resources")

function resource_panel.draw()
    if not ImGui then return end
    
    ImGui.SetNextWindowPos(440, 10, ImGuiCond.Always)
    ImGui.SetNextWindowSize(150, 110, ImGuiCond.Always)
    
    local flags = ImGuiWindowFlags.NoResize + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoCollapse
    
    if ImGui.Begin("Resources", nil, flags) then
        local food = resources.get("food")
        local wood = resources.get("wood")
        local stone = resources.get("stone")
        local gold = resources.get("gold")
        
        ImGui.Text(string.format("* Food:  %d", food))
        ImGui.Text(string.format("= Wood:  %d", wood))
        ImGui.Text(string.format("o Stone: %d", stone))
        ImGui.Text(string.format("$ Gold:  %d", gold))
        
        ImGui.End()
    end
end

return resource_panel
