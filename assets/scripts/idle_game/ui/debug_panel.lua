--[[
================================================================================
GOAP Debug Panel - Display GOAP state for selected entity
================================================================================
ImGui-based read-only panel showing GOAP debugging information:
- Current goal name
- Current action name
- World state atoms
- Recent trace events (last 10)

Automatically appears when entity is selected via Selection.selected_entity,
dismisses when nothing is selected.
]]

local debug_panel = {}

-- Dependencies
local selection = require("idle_game.selection")

--===========================================================================
-- STATE
--===========================================================================

debug_panel.panel_width = 250
debug_panel.panel_height = 500
debug_panel.panel_x = 10
debug_panel.panel_y = 10

--===========================================================================
-- MAIN RENDER
--===========================================================================

--- Render the GOAP debug panel
--- Called from sim_scene.draw() each frame
function debug_panel.draw()
    if not ImGui then return end
    if not selection.selected_entity then return end
    
    ImGui.SetNextWindowPos(debug_panel.panel_x, debug_panel.panel_y, ImGuiCond.Always)
    ImGui.SetNextWindowSize(debug_panel.panel_width, debug_panel.panel_height, ImGuiCond.Always)
    
    local open = ImGui.Begin("GOAP Debug", true, ImGuiWindowFlags.NoResize)
    if not open then
        ImGui.End()
        return
    end
    
    local entity = selection.selected_entity
    
    -- Fetch GOAP state
    local goap_state = nil
    if ai and ai.get_goap_state then
        goap_state = ai.get_goap_state(entity)
    end
    
    if not goap_state then
        ImGui.TextColored(0.5, 0.5, 0.5, 1, "No GOAP component")
        ImGui.End()
        return
    end
    
    -- Display goal
    ImGui.Text("Goal:")
    ImGui.SameLine()
    ImGui.TextColored(0.2, 0.8, 1.0, 1.0, goap_state.current_goal or "(none)")
    
    -- Display action
    ImGui.Text("Action:")
    ImGui.SameLine()
    if goap_state.current_action then
        ImGui.TextColored(1.0, 1.0, 0.2, 1.0, goap_state.current_action)
    else
        ImGui.TextColored(0.5, 0.5, 0.5, 1, "(none)")
    end
    
    ImGui.Separator()
    ImGui.Text("World State:")
    
    -- Display world state atoms as read-only text
    if goap_state.worldstate then
        for atom, value in pairs(goap_state.worldstate) do
            local color = value and {0, 1, 0, 1} or {1, 0.3, 0.3, 1}
            ImGui.TextColored(color[1], color[2], color[3], color[4],
                string.format("  %s: %s", atom, tostring(value)))
        end
    else
        ImGui.TextColored(0.5, 0.5, 0.5, 1, "  (none)")
    end
    
    ImGui.Separator()
    ImGui.Text("Trace Events (last 10):")
    
    -- Fetch trace events
    local events = {}
    if ai and ai.get_trace_events then
        events = ai.get_trace_events(entity, 10) or {}
    end
    
    if #events == 0 then
        ImGui.TextColored(0.5, 0.5, 0.5, 1, "  (none)")
    else
        -- Use child window for scrolling if many events
        if ImGui.BeginChild("trace_events", 0, 200, true) then
            for _, event in ipairs(events) do
                local msg = event.message or tostring(event.type or "")
                ImGui.TextWrapped(msg)
            end
            ImGui.EndChild()
        end
    end
    
    ImGui.End()
end

return debug_panel
