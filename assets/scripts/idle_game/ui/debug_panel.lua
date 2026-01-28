--[[
================================================================================
GOAP Debug Panel - Display GOAP state for selected entity
================================================================================
ImGui-based read-only panel showing GOAP debugging information:
- Always-visible summary of all GOAP entities
- Detailed view when entity is selected
]]

local debug_panel = {}

-- Dependencies
local selection = require("idle_game.selection")

--===========================================================================
-- STATE
--===========================================================================

debug_panel.panel_width = 280
debug_panel.panel_height = 400
debug_panel.panel_x = 10
debug_panel.panel_y = 60  -- Below resource panel

--===========================================================================
-- ALWAYS-VISIBLE SUMMARY
--===========================================================================

--- Draw a compact always-visible GOAP summary
function debug_panel.drawSummary()
    if not ImGui then return end
    if not ai or not ai.list_goap_entities then return end

    local entities = ai.list_goap_entities() or {}
    if #entities == 0 then return end

    -- Count actions
    local action_counts = {}
    for _, e in ipairs(entities) do
        local state = ai.get_goap_state(e)
        if state then
            local action = state.current_action or "idle"
            action_counts[action] = (action_counts[action] or 0) + 1
        end
    end

    -- Get flag values safely
    local flags = 0
    if ImGuiWindowFlags then
        flags = (ImGuiWindowFlags.NoResize or 0) + (ImGuiWindowFlags.NoMove or 0) + (ImGuiWindowFlags.NoCollapse or 0)
    end
    local cond = 1  -- ImGuiCond_Always = 1
    if ImGuiCond and ImGuiCond.Always then
        cond = ImGuiCond.Always
    end

    -- Draw compact summary panel in top-left
    ImGui.SetNextWindowPos(10, 10, cond)
    ImGui.SetNextWindowSize(180, 0, cond)
    ImGui.SetNextWindowBgAlpha(0.8)

    local open, shouldDraw = ImGui.Begin("GOAP Status", true, flags)
    if open and shouldDraw then
        ImGui.Text(string.format("Entities: %d", #entities))
        ImGui.Separator()

        -- Show action distribution
        for action, count in pairs(action_counts) do
            ImGui.TextColored(0.8, 0.8, 0.2, 1,
                string.format("  %s: %d", action, count))
        end

        -- Show selected entity hint
        if selection.selected_entity then
            ImGui.Separator()
            ImGui.TextColored(0.2, 1, 0.2, 1, "Selected: " .. tostring(selection.selected_entity))
        else
            ImGui.Separator()
            ImGui.TextColored(0.5, 0.5, 0.5, 1, "Click to select")
        end
    end
    ImGui.End()
end

--===========================================================================
-- DETAILED VIEW (when entity selected)
--===========================================================================

--- Render detailed GOAP debug panel for selected entity
function debug_panel.drawDetails()
    if not ImGui then return end
    if not selection.selected_entity then return end

    local cond = 1  -- ImGuiCond_Always
    if ImGuiCond and ImGuiCond.Always then cond = ImGuiCond.Always end
    local flags = 0
    if ImGuiWindowFlags and ImGuiWindowFlags.NoResize then flags = ImGuiWindowFlags.NoResize end

    ImGui.SetNextWindowPos(220, 10, cond)
    ImGui.SetNextWindowSize(debug_panel.panel_width, debug_panel.panel_height, cond)

    local open, shouldDraw = ImGui.Begin("Entity Details", true, flags)
    if not (open and shouldDraw) then
        ImGui.End()
        return
    end
    
    local entity = selection.selected_entity

    -- Fetch GOAP state
    local goap_state = nil
    if not ai or not ai.get_goap_state then
        ImGui.TextColored(1, 0.3, 0.3, 1, "ai module not available")
        ImGui.End()
        return
    end

    goap_state = ai.get_goap_state(entity)

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
    -- API returns goap_state.atoms as array: [{name, current, goal}, ...]
    if goap_state.atoms then
        for _, atom in ipairs(goap_state.atoms) do
            if atom and atom.name then
                local value = atom.current
                local color
                if value == "dontcare" then
                    color = {0.5, 0.5, 0.5, 1}  -- gray for don't care
                elseif value then
                    color = {0, 1, 0, 1}  -- green for true
                else
                    color = {1, 0.3, 0.3, 1}  -- red for false
                end
                ImGui.TextColored(color[1], color[2], color[3], color[4],
                    string.format("  %s: %s", atom.name, tostring(value)))
            end
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
        end
        ImGui.EndChild()  -- Must always be called after BeginChild
    end
    
    ImGui.End()
end

--===========================================================================
-- MAIN DRAW FUNCTION
--===========================================================================

--- Main draw function - called from sim_scene.draw() each frame
function debug_panel.draw()
    debug_panel.drawSummary()  -- Always visible
    debug_panel.drawDetails()  -- Only when entity selected
end

return debug_panel
