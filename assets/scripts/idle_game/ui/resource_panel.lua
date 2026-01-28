local resource_panel = {}

local resources = require("idle_game.resources")

function resource_panel.draw()
    if not ImGui then return end

    ImGui.SetNextWindowPos(440, 10, ImGuiCond.Always)
    ImGui.SetNextWindowSize(150, 110, ImGuiCond.Always)

    if ImGui.Begin("Resources") then
        local food = resources.get("food")
        local wood = resources.get("wood")
        local stone = resources.get("stone")
        local gold = resources.get("gold")

        ImGui.Text(string.format("* Food:  %d", math.floor(food)))
        ImGui.Text(string.format("= Wood:  %d", math.floor(wood)))
        ImGui.Text(string.format("o Stone: %d", math.floor(stone)))
        ImGui.Text(string.format("$ Gold:  %d", math.floor(gold)))
    end
    ImGui.End()  -- Must always be called after Begin
end

return resource_panel
