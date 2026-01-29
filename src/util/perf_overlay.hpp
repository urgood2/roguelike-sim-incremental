#pragma once

/**
 * Performance Debug Overlay
 *
 * Real-time in-game metrics display showing:
 * - FPS/Frame time with graph
 * - Draw call breakdown (sprites, text, shapes, UI, state changes)
 * - Entity count
 * - Lua memory usage
 * - Batch efficiency metrics
 *
 * Usage:
 *   perf_overlay::toggle();     // Toggle visibility (default: F3)
 *   perf_overlay::render();     // Call in render loop
 *   perf_overlay::setEnabled(true/false);
 *
 * From Lua:
 *   perf_overlay.toggle()
 *   perf_overlay.show()
 *   perf_overlay.hide()
 *   perf_overlay.get_stats() -- returns table with all metrics
 */

#include <array>
#include <string>
#include <cstdint>
#include "entt/entt.hpp"
#include "sol/sol.hpp"

namespace perf_overlay {

// Configuration
struct Config {
    bool enabled = false;
    bool showFrameGraph = true;
    bool showDrawCalls = true;
    bool showEntityCount = true;
    bool showMemory = true;
    bool showBatchStats = true;
    float opacity = 0.85f;
    int position = 0;  // 0=top-left, 1=top-right, 2=bottom-left, 3=bottom-right
};

// Collected metrics per frame
struct FrameMetrics {
    float frameTimeMs = 0.0f;
    float fps = 0.0f;
    int drawCallsTotal = 0;
    int drawCallsSprites = 0;
    int drawCallsText = 0;
    int drawCallsShapes = 0;
    int drawCallsUI = 0;
    int drawCallsState = 0;
    int entityCount = 0;
    float luaMemoryKB = 0.0f;
    int stateChanges = 0;
    int shaderChanges = 0;
    int textureChanges = 0;
};

// Frame time history for graph
constexpr int FRAME_HISTORY_SIZE = 120;

extern Config g_config;
extern FrameMetrics g_currentMetrics;
extern std::array<float, FRAME_HISTORY_SIZE> g_frameTimeHistory;
extern int g_frameHistoryIndex;

// Core functions
void init();
void update(entt::registry& registry);  // Call once per frame to collect metrics
void render();  // Call in render loop to draw overlay

// Control
void toggle();
void setEnabled(bool enabled);
bool isEnabled();
void setPosition(int pos);  // 0-3 for corners
void setOpacity(float alpha);

// Metrics access
const FrameMetrics& getMetrics();
float getAverageFrameTime();
float getAverageFPS();
float getFrameTimeP99();

// Lua binding
void exposeToLua(sol::state& lua);

}  // namespace perf_overlay
