local upgrade_panel = {}

local upgrades = require("idle_game.upgrades")
local resources = require("idle_game.resources")

function upgrade_panel.draw()
    if not ImGui then return end

    ImGui.SetNextWindowPos(350, 10, ImGuiCond.Always)
    ImGui.SetNextWindowSize(240, 500, ImGuiCond.Always)

    if ImGui.Begin("Upgrades") then
        if ImGui.BeginChild("upgrade_list", 0, 0, true) then
            local all_upgrades = upgrades.get_all()

            for id, upgrade in pairs(all_upgrades) do
                local level = upgrades.get_level(id)
                local cost = upgrades.get_cost(id)
                local can_afford = upgrades.can_afford(id, resources)

                ImGui.Text(string.format("%s (Lv. %d/%d)", upgrade.name, level, upgrade.max_level))

                local cost_parts = {}
                for resource, amount in pairs(cost) do
                    table.insert(cost_parts, string.format("%d %s", amount, resource))
                end
                ImGui.Text("Cost: " .. table.concat(cost_parts, ", "))

                if can_afford then
                    if ImGui.Button("Buy##" .. id) then
                        upgrades.purchase(id, resources)
                    end
                else
                    ImGui.Text("[Cannot afford]")
                end

                ImGui.TextWrapped(upgrade.description)
                ImGui.Separator()
            end
        end
        ImGui.EndChild()  -- Must always be called after BeginChild
    end
    ImGui.End()  -- Must always be called after Begin
end

return upgrade_panel
