local upgrade_panel = {}

local upgrades = require("idle_game.upgrades")
local resources = require("idle_game.resources")

function upgrade_panel.draw()
    if not ImGui then return end

    -- Use FirstUseEver to allow window dragging
    local cond = ImGuiCond.FirstUseEver or 2
    ImGui.SetNextWindowPos(350, 10, cond)
    ImGui.SetNextWindowSize(240, 500, cond)

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

                -- Implement buy button states: [BUY], [MAX], or [—]
                if level >= upgrade.max_level then
                    -- Show [MAX] for maxed upgrades
                    ImGui.Text("[MAX]")
                elseif can_afford then
                    -- Show [BUY] button for affordable upgrades
                    if ImGui.Button("[BUY]##" .. id) then
                        upgrades.purchase(id, resources)
                    end
                else
                    -- Show [—] for unaffordable upgrades (insufficient resources)
                    ImGui.Text("[—]")
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
