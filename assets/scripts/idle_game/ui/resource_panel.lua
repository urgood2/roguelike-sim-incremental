local resource_panel = {}

local resources = require("idle_game.resources")
local terrain = require("idle_game.terrain")

-- Helper to format rate display
local function format_rate(rate)
    if rate < 0.01 then
        return ""
    elseif rate < 1 then
        return string.format(" (+%.1f/s)", rate)
    else
        return string.format(" (+%.0f/s)", rate)
    end
end

function resource_panel.draw()
    if not ImGui then return end

    ImGui.SetNextWindowPos(10, 10, ImGuiCond.Always)
    ImGui.SetNextWindowSize(180, 180, ImGuiCond.Always)

    if ImGui.Begin("Resources") then
        local food = resources.get("food")
        local wood = resources.get("wood")
        local stone = resources.get("stone")
        local gold = resources.get("gold")

        local food_rate = resources.get_rate("food")
        local wood_rate = resources.get_rate("wood")
        local stone_rate = resources.get_rate("stone")
        local gold_rate = resources.get_rate("gold")

        ImGui.Text(string.format("Food:  %d%s", math.floor(food), format_rate(food_rate)))
        ImGui.Text(string.format("Wood:  %d%s", math.floor(wood), format_rate(wood_rate)))
        ImGui.Text(string.format("Stone: %d%s", math.floor(stone), format_rate(stone_rate)))
        ImGui.Text(string.format("Gold:  %.1f%s", gold, format_rate(gold_rate)))

        ImGui.Separator()

        -- Terrain stats
        local stats = terrain.getStats()
        if stats then
            ImGui.Text(string.format("Trees: %d", stats.total_trees or 0))
            ImGui.Text(string.format("Rocks: %d", stats.total_rocks or 0))
            ImGui.Text(string.format("Grass: %d", stats.total_grass or 0))
        end
    end
    ImGui.End()  -- Must always be called after Begin
end

return resource_panel
