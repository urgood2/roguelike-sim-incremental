#include "systems/ai/ai_system.hpp"
#include "systems/input/input_functions.hpp"
#include "systems/layer/layer.hpp"
#include "systems/physics/transform_physics_hook.hpp"
#include "third_party/rlImGui/imgui.h"
#include "third_party/rlImGui/imgui_internal.h"
#include "third_party/rlImGui/rlImGui.h"
#define RAYGUI_IMPLEMENTATION // needed to use raygui

#define _WIN32_WINNT 0x0600

#include "entt/entt.hpp" // ECS
#include "raylib.h"      // raylib
// #include "tweeny.h"      // tweening library

#if defined(_WIN32)
#define NOGDI  // All GDI defines and routines
#endif

#define SPDLOG_ACTIVE_LEVEL SPDLOG_LEVEL_TRACE // compiler-time log level

#include "spdlog/sinks/basic_file_sink.h"
#include "spdlog/sinks/stdout_color_sinks.h" // or any library that uses Windows.h
#include "spdlog/spdlog.h" // SPD logging lib // or any library that uses Windows.h

#include "util/common_headers.hpp" // common headers like json, spdlog, tracy etc.
#include "util/crash_reporter.hpp"
#include "systems/telemetry/telemetry.hpp"

#if defined(_WIN32) // raylib uses these names as function parameters
#undef near
#undef far
#endif

#if defined(PLATFORM_WEB) || defined(__EMSCRIPTEN__)
#include <emscripten/emscripten.h>
#endif

#include "effolkronium/random.hpp" // https://github.com/effolkronium/random

#include "core/engine_context.hpp"
#include "core/game.hpp"
#include "core/globals.hpp"
#include "core/graphics.hpp"
#include "core/gui.hpp"
#include "third_party/imgui_console/imgui_console.h"
#include "core/init.hpp"
#include "core/ownership.hpp"

#include "util/utilities.hpp" // global utilty methods
#include "util/perf_overlay.hpp"

#define JSON_DIAGNOSTICS 1
#include <nlohmann/json.hpp> // nlohmann JSON parsing
using json = nlohmann::json;

#include <fmt/core.h> // https://github.com/fmtlib/fmt
// #include <boost/stacktrace.hpp> // stack trace

#include <algorithm>
#include <cassert>
#include <cmath>
#include <fstream>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <numeric>
#include <regex>
#include <sstream>
#include <string>

// #define SPINE_USE_STD_FUNCTION
// #include "spine/spine.h"
// #include "third_party/spine_impl/spine_raylib.hpp"

#include "raymath.h"

// #include "systems/physics/physics_world.hpp"
#include "core/events.hpp"
#include "systems/anim_system.hpp"
#include "systems/event/event_system.hpp"
#include "systems/fade/fade_system.hpp"
#include "systems/input/controller_nav.hpp"
#include "systems/input/input.hpp"
#include "systems/layer/layer_optimized.hpp"
#include "systems/localization/localization.hpp"
#include "systems/main_loop_enhancement/main_loop.hpp"
#include "systems/palette/palette_quantizer.hpp"
#include "systems/scripting/scripting_system.hpp"
#include "systems/shaders/shader_pipeline.hpp"
#include "systems/shaders/shader_system.hpp"
#include "systems/sound/sound_system.hpp"
#include "systems/timer/timer.hpp"

using std::string, std::unique_ptr, std::vector;
using namespace std::literals;
// using namespace BT;
using Random =
    effolkronium::random_static; // get base random alias which is auto seeded
                                 // and has static API and internal state

// update methods
auto updateSystems(float dt) -> void;

auto updateTimers(float dt) -> void {
  globals::getTimerReal() += dt;
  globals::getTimerTotal() += dt;
}

bool pauseGameWhenOutofFocus = true;
bool updatedGame = false;
static bool gPausedByVisibilityLoss = false;
auto mainGameStateGameLoop(float dt) -> void {

  // updatedGame = false;
  // bool shouldPauseFromNoFocus = (pauseGameWhenOutofFocus == true &&
  // IsWindowFocused() == false); if (shouldPauseFromNoFocus == false &&
  // game::isGameOver == false)
  // {
  game::update(dt);
  // updatedGame = true;
  // if (game::isPaused == false)
  // }
}

void mainMenuStateGameLoop(float dt) {

  // FIXME: just set game to main game state for now
  globals::setCurrentGameState(GameState::MAIN_GAME);
  // show main menu here
}

void MainLoopFixedUpdateAbstraction(float dt) {
  ZONE_SCOPED("MainLoopFixedUpdateAbstraction"); // custom label

  updateSystems(dt);

  // this switch statement handles only update logic, rendering is handled in
  // the mainloopRenderAbstraction function
  switch (globals::getCurrentGameState()) {
  case GameState::MAIN_MENU:
    // show main menu
    mainMenuStateGameLoop(dt);
    break;
  case GameState::MAIN_GAME:
    // show main game screen
    mainGameStateGameLoop(dt);
    break;
  case GameState::GAME_OVER:
    // show game over screen
    mainGameStateGameLoop(dt);
    break;
  default:
    globals::setCurrentGameState(GameState::MAIN_MENU);
    break;
  }

  // finalize input state at end of frame
  input::finalizeUpdateAtEndOfFrame(globals::getInputState(), dt);
}

auto mainGameStateGameLoopRender(float dt) -> void { game::draw(dt); }

auto mainMenuStateGameLoopRender(float dt) -> void {}

bool mainMenuFirstFrame{
    true}; // used to determine if this is the first frame of the main menu
auto mainMenuStateGameLoop() -> void {}

auto loadingScreenStateGameLoopRender(float dt) -> void {
  // show loading screen

  ClearBackground(RAYWHITE);
  DrawText("Loading...", 20, 20, 40, LIGHTGRAY);
}

auto gameOverScreenGameLoopRender(float dt) -> void {

  // gui::showGameOverModal();
  // ends the ImGui content mode. Make all ImGui calls before this
}

auto MainLoopRenderAbstraction(float dt) -> void {

  switch (globals::getCurrentGameState()) {
  case GameState::MAIN_MENU:
    mainMenuStateGameLoopRender(dt);
    break;
  case GameState::MAIN_GAME:
    mainGameStateGameLoopRender(dt);
    break;
  case GameState::LOADING_SCREEN:
    loadingScreenStateGameLoopRender(dt);
    break;
  case GameState::GAME_OVER:
    gameOverScreenGameLoopRender(dt);
    break;
  default:
    // draw nothing
    break;
  }

  // Render tamper warning overlay last (so it cannot be covered by game rendering)
  ownership::renderTamperWarningIfNeeded(GetScreenWidth(), GetScreenHeight());
}

auto updatePhysics(float dt, float alpha) -> void {
  main_loop::mainLoop.physicsTicks++;
  {
    ZONE_SCOPED("Physics Transform Hook ApplyAuthoritativeTransform");
    if (globals::getPhysicsManager())
      physics::ApplyAuthoritativeTransform(globals::getRegistry(),
                                           *globals::getPhysicsManager());
  }

  {
    ZONE_SCOPED("Physics Step All Worlds");
    if (globals::getPhysicsManager())
      globals::getPhysicsManager()->stepAll(dt); // step all physics worlds
  }

  {
    ZONE_SCOPED("Physics Transform Hook ApplyAuthoritativePhysics");
    if (globals::getPhysicsManager())
      physics::ApplyAuthoritativePhysics(globals::getRegistry(),
                                         *globals::getPhysicsManager(), alpha);

    // physics post-update
    if (globals::getPhysicsManager())
      globals::getPhysicsManager()->stepAllPostUpdate(dt);
  }
}

// The main game loop function that runs until the application or window is
// closed. The main game loop callback / blocking loop
void RunGameLoop() {
  // ---------- Initialization ----------
  float lastFrameTime = GetTime();

  // Optional frame smoothing (helps even out jitter in GetFrameTime)
  const int frameSmoothingCount = 10;
  std::deque<float> frameTimes;

  // Safety: limit how many fixed updates can run per frame
  const int maxUpdatesPerFrame = 5;

  // FPS tracking
  int frameCounter = 0;
  double fpsLastTime = GetTime();

#ifndef __EMSCRIPTEN__
  while (!WindowShouldClose()) {
    ZONE_SCOPED("RunGameLoop"); // custom label
#endif
    {
      ZONE_SCOPED("BeginDrawing/rlImGuiBegin call");
      BeginDrawing();

      // === BORDERLESS WINDOW DRAGGING ===
      // Must run BEFORE rlImGuiBegin() so we can check WantCaptureMouse from previous frame
      {
          static bool isDragging = false;
          
          // Get ImGui state from previous frame (rlImGuiBegin hasn't been called yet)
          ImGuiIO& io = ImGui::GetIO();
          
          // Only drag if ImGui doesn't want the mouse
          if (!io.WantCaptureMouse) {
              Vector2 mousePos = GetMousePosition();
              int screenW = GetScreenWidth();
              int screenH = GetScreenHeight();
              int edgeMargin = 10;  // resize zone width
              
              // Check if in drag area (not near edges, reserved for resize)
              bool inDragArea = mousePos.x > edgeMargin && mousePos.x < screenW - edgeMargin &&
                               mousePos.y > edgeMargin && mousePos.y < screenH - edgeMargin;
              
              if (IsMouseButtonPressed(MOUSE_LEFT_BUTTON) && inDragArea) {
                  isDragging = true;
              }
              
              if (IsMouseButtonReleased(MOUSE_LEFT_BUTTON)) {
                  isDragging = false;
              }
              
              if (isDragging && IsMouseButtonDown(MOUSE_LEFT_BUTTON)) {
                  Vector2 mouseDelta = GetMouseDelta();
                  Vector2 windowPos = GetWindowPosition();
                  SetWindowPosition((int)(windowPos.x + mouseDelta.x), 
                                   (int)(windowPos.y + mouseDelta.y));
              }
          } else {
              // ImGui wants mouse - cancel any drag
              isDragging = false;
          }
      }
      // === END BORDERLESS WINDOW DRAGGING ===

#ifndef __EMSCRIPTEN__

      if (globals::getUseImGUI())
        rlImGuiBegin(); // Begin ImGui each frame (desktop only)
#endif
    }

    using namespace main_loop;

    // F3 toggles performance overlay
    if (IsKeyPressed(KEY_F3)) {
      perf_overlay::toggle();
    }

    // F7 toggles hot-path analyzer (Lua profiler)
    // Note: F4 is used by game.cpp for physics debug
    if (IsKeyPressed(KEY_F7)) {
      static bool hotpathRunning = false;
      if (ai_system::masterStateLua.lua_state()) {
        try {
          if (!hotpathRunning) {
            ai_system::masterStateLua.script(R"(
              local hotpath = require("tools.hotpath_analyzer")
              hotpath.start()
              print("[F7] Hot-path analyzer started - press F7 again to stop and report")
            )");
            hotpathRunning = true;
          } else {
            ai_system::masterStateLua.script(R"(
              local hotpath = require("tools.hotpath_analyzer")
              hotpath.stop()
              hotpath.report(20)
            )");
            hotpathRunning = false;
          }
        } catch (...) {
          SPDLOG_WARN("F7 hotpath toggle failed");
        }
      }
    }

    // F8 prints ECS dashboard report
    // Note: F5 is used by shader_system.cpp for hot reload
    if (IsKeyPressed(KEY_F8)) {
      if (ai_system::masterStateLua.lua_state()) {
        try {
          ai_system::masterStateLua.script(R"(
            local ecs = require("tools.ecs_dashboard")
            ecs.report()
          )");
        } catch (...) {
          SPDLOG_WARN("F8 ECS dashboard failed");
        }
      }
    }

    if (crash_reporter::IsEnabled() && IsKeyPressed(KEY_F10)) {
      auto report = crash_reporter::CaptureReport("Manual capture (F10)");
      auto path = crash_reporter::PersistReport(report);
      if (path) {
        SPDLOG_INFO("Manual crash report saved to {}", *path);
      } else {
        SPDLOG_WARN("Manual crash report captured but persistence is disabled "
                    "or failed.");
      }
#if defined(__EMSCRIPTEN__)
      // Show a nice notification on web with copy button
      crash_reporter::ShowCaptureNotification(
          "Press 'Copy to Clipboard' to share this report, or check your downloads.");
      // Also copy to clipboard automatically for convenience
      crash_reporter::CopyToClipboard();
#endif
    }

    // ---------- Step 1: Measure REAL frame time ----------
    float rawDeltaTime =
        std::max(GetFrameTime(), 0.001f); // real delta, unaffected by timescale
    mainLoop.rawDeltaTime = rawDeltaTime;

    // Optional smoothing
    frameTimes.push_back(rawDeltaTime);
    if (frameTimes.size() > frameSmoothingCount)
      frameTimes.pop_front();

    float deltaTime =
        std::accumulate(frameTimes.begin(), frameTimes.end(), 0.0f) /
        frameTimes.size();
    mainLoop.smoothedDeltaTime = deltaTime;

    // ---------- Step 2: Accumulate time ----------
    mainLoop.realtimeTimer += deltaTime;
    if (!globals::getIsGamePaused())
      mainLoop.totaltimeTimer += deltaTime;

    // Accumulate lag for fixed-step updates (real time, not scaled)
    const float lagDelta = globals::getIsGamePaused() ? 0.0f : deltaTime;
    mainLoop.lag = std::min(mainLoop.lag + lagDelta,
                            mainLoop.rate * mainLoop.maxFrameSkip);

    // ---------- Step 3: Fixed updates ----------
    int updatesPerformed = 0;
    while (mainLoop.lag >= mainLoop.rate &&
           updatesPerformed < maxUpdatesPerFrame) {
      ZONE_SCOPED("Physics Update Step"); // custom label
      float scaledStep = mainLoop.rate * mainLoop.timescale;

      // Split into two substeps for improved stability
      const int substeps = 2;
      float subDelta = scaledStep / substeps;
      float alpha =
          mainLoop.lag /
          mainLoop
              .rate; // interpolation factor for lerping physics to transform

      for (int i = 0; i < substeps; ++i) {
        updatePhysics(subDelta, alpha);
      }

      // SPDLOG_DEBUG("physics step ({} substeps) of {} ms each at time {}",
      //             substeps, subDelta * 1000.0f, mainLoop.totaltimeTimer);

      mainLoop.lag -= mainLoop.rate;
      mainLoop.updates++;
      updatesPerformed++;
      mainLoop.frame++;
    }

    // ---------- Step 4: Update UPS counter ----------
    mainLoop.updateTimer += deltaTime;
    if (mainLoop.updateTimer >= 1.0f) {
      mainLoop.renderedUPS = mainLoop.updates;
      mainLoop.updates = 0;
      mainLoop.updateTimer = 0.0f;
    }

    // ---------- Step 5: Rendering ----------
    float scaledStep = rawDeltaTime * mainLoop.timescale;
    // ---------- Step 4.5: Fixed update (moved) ----------
    {

      MainLoopFixedUpdateAbstraction(scaledStep);
      // SPDLOG_DEBUG("scaled update step: {}", scaledStep);
    }

    // Render-time timers must run before we enqueue draw commands, otherwise
    // anything they queue gets wiped by layer::Begin() next frame.
    timer::TimerSystem::update_render_timers(deltaTime * mainLoop.timescale);

    // Pass real render deltaTime to renderer
    MainLoopRenderAbstraction(scaledStep);

    // Update performance overlay metrics AFTER rendering so draw call stats are populated
    perf_overlay::update(globals::getRegistry());

    // Render performance overlay (uses ImGui)
    perf_overlay::render();

#ifndef __EMSCRIPTEN__
    // Draw ImGui console (toggle with ` backtick key)
    if (globals::getUseImGUI() && gui::showConsole && gui::consolePtr) {
      gui::consolePtr->Draw();
    }
#endif

    // ---------- Step 6: FPS counter ----------
    frameCounter++;
    double now = GetTime();
    if (now - fpsLastTime >= 1.0) {
      mainLoop.renderedFPS = frameCounter;
      frameCounter = 0;
      fpsLastTime = now;
    }

    {
      ZONE_SCOPED("EndDrawing/rlImGuiEnd call");

#ifndef __EMSCRIPTEN__
      if (globals::getUseImGUI())
        rlImGuiEnd();
#endif
      EndDrawing();
    }

    mainLoop.renderFrame++; // ✅ Count this as one rendered frame

#ifdef __EMSCRIPTEN__
    // (No while loop on web)
#else
} // while (!WindowShouldClose())
#endif
  }

  int main(void) {

  // --------------------------------------------------------------------------------------
  // game init
  // --------------------------------------------------------------------------------------

  crash_reporter::Config crashConfig{};
#if defined(__EMSCRIPTEN__)
    crashConfig.enable_file_output = false;
#else
  crashConfig.enable_browser_download = false;
#endif
    crashConfig.build_id = CRASH_REPORT_BUILD_ID;
    crash_reporter::Init(crashConfig);

    auto engineCtx = createEngineContext("config.json");
    globals::setEngineContext(engineCtx.get());

    init::base_init();
    crash_reporter::AttachSinkToLogger(spdlog::default_logger());
    layer::InitDispatcher();

    main_loop::initMainLoopData(
        std::nullopt, 60); // match monitor refresh rate for fps, 60 ups
    SetTargetFPS(main_loop::mainLoop.framerate);

    SetExitKey(-1);

    init::startInit();

    input::Init(globals::getInputState(), globals::getRegistry(),
                globals::g_ctx);

    game::init();

    // Initialize performance overlay (F3 toggle)
    perf_overlay::init();

#ifdef __EMSCRIPTEN__
    telemetry::SetVisibilityChangeCallback([](const std::string &reason, bool visible) {
        if (!pauseGameWhenOutofFocus)
            return;
        if (!visible)
        {
            if (!globals::getIsGamePaused())
            {
                globals::setIsGamePaused(true);
                gPausedByVisibilityLoss = true;
                SPDLOG_INFO("Pausing game (tab hidden: {})", reason);
            }
            else
            {
                gPausedByVisibilityLoss = false;
            }
        }
        else
        {
            if (gPausedByVisibilityLoss)
            {
                globals::setIsGamePaused(false);
                SPDLOG_INFO("Resuming game (tab visible: {})", reason);
            }
            gPausedByVisibilityLoss = false;
        }
    });
#endif

    // gamepad connected? just connect gamepad 0
    if (IsGamepadAvailable(0)) {
      input::SetCurrentGamepad(globals::getInputState(), GetGamepadName(0), 0);
    }

    // --------------------------------------------------------------------------------------
    // game loop
    // --------------------------------------------------------------------------------------

    // audio::SetMusic(MENU_MUSIC1);

    SPDLOG_INFO("Starting game loop...");
#ifdef __EMSCRIPTEN__

    emscripten_set_main_loop(RunGameLoop, 0, 1);
#else

  // try {

  // Main game loop
  while (!WindowShouldClose()) { // Detect window close button or ESC key
    // FrameMark; // marks one frame
    RunGameLoop();
  }

#endif
    // De-Initialization

    telemetry::RecordEvent("app_exit",
                           {{"reason", "normal"},
                            {"platform", telemetry::PlatformTag()},
                            {"build_id", telemetry::BuildId()},
                            {"build_type", telemetry::BuildTypeTag()},
                            {"release_mode", globals::getReleaseMode()},
                            {"session_id", telemetry::SessionId()}});
    telemetry::Flush();

    // TODO: unload all textures & sprite atlas & sounds
    // TODO: unload all layer commands as welll.
    palette_quantizer::unloadPaletteTexture(); // unload palette texture if any
    layer::UnloadAllLayers();
    shaders::unloadShaders();
    sound_system::Unload();
    shader_pipeline::ShaderPipelineUnload();
    if (globals::physicsManager) {
        globals::physicsManager->clearAllWorlds(); // destroy physics worlds while registry is still alive
    }
    game::physicsWorld.reset();

    // Drop Lua-owned callbacks/handles before tearing down the Lua state.
    timer::TimerSystem::clear_all_timers();
    event_system::ClearAllListeners();
    scripting::monobehavior_system::shutdown(globals::getRegistry());
    localization::clearLanguageChangedCallbacks();
    game::resetLuaRefs();
    controller_nav::NavManager::instance().reset(); // drop nav callbacks before Lua state teardown
    globals::getRegistry().clear();

    // Clean up Lua state before closing window to avoid crashes
    ai_system::cleanup();

    // after your game loop is over, before you close the window
    rlImGuiShutdown(); // cleans up ImGui

    CloseAudioDevice(); // Close audio device

    //--------------------------------------------------------------------------------------
    CloseWindow(); // Close window and OpenGL context
    //--------------------------------------------------------------------------------------

    return 0;
  }

  /// @brief Update the systems that operate on ECS components. Note: dt is in
  /// seconds
  /// @return
  auto updateSystems(float dt) -> void {
    ZONE_SCOPED("UpdateSystems"); // custom label

    // clear layers
    {
      ZONE_SCOPED("layer::Begin");
      layer::Begin(); // clear all commands so we begin fresh next frame, and
                      // also let draw commands from update loop to show up when
                      // rendering (update is called before draw). we do this in
                      // update rather than draw since draw will execute more
                      // often than update.
    }

    {
      ZONE_SCOPED("Input System Update");
      updateTimers(dt); // these are used by event queue system (TODO: replace
                        // with mainloop abstraction)
      fade_system::update(dt); // update fade system
    }

    {
      ZONE_SCOPED("Input System Update");
      input::Update(globals::getRegistry(), globals::getInputState(), dt,
                    globals::g_ctx);
    }

    {
      ZONE_SCOPED("Global Variables Update & sound");
      globals::updateGlobalVariables();
      // SPDLOG_DEBUG("Updating sound with dt of {}",
      // main_loop::mainLoop.rawDeltaTime);
      sound_system::Update(
          main_loop::mainLoop
              .rawDeltaTime); // update sound system, ignore slowed DT here.
    }

    // {
    //     ZONE_SCOPED("Physics Transform Hook ApplyAuthoritativeTransform");
    //     physics::ApplyAuthoritativeTransform(globals::getRegistry(),
    //     *globals::physicsManager);
    // }

    // {
    //     ZONE_SCOPED("Physics Step All Worlds");
    //     globals::physicsManager->stepAll(dt); // step all physics worlds
    // }

    // {
    //     ZONE_SCOPED("Physics Transform Hook ApplyAuthoritativePhysics");
    //     physics::ApplyAuthoritativePhysics(globals::getRegistry(),
    //     *globals::physicsManager);
    // }

    // systems

    shaders::update(dt);
    timer::TimerSystem::update_timers(dt);
    spring::updateAllSprings(globals::getRegistry(), dt);
    animation_system::update(dt);
    transform::ExecuteCallsForTransformMethod<void>(
        globals::getRegistry(), entt::null,
        transform::TransformMethod::UpdateAllTransforms,
        &globals::getRegistry(), dt);
    controller_nav::NavManager::instance().update(dt);
    {
      ZONE_SCOPED("EventQueueSystem::EventManager::update");
      // update event queue
      timer::EventQueueSystem::EventManager::update(dt);
    }

    {
      ZONE_SCOPED("scripting::monobehavior_system::update");
      scripting::monobehavior_system::update(
          globals::getRegistry(),
          dt); // update all monobehavior scripts in the registry
    }
    {
      ZONE_SCOPED("AI System Update");
      ai_system::masterScheduler.update(
          static_cast<ai_system::fsec>(dt)); // update the AI system scheduler
    }

    {
      ZONE_SCOPED("ai_system::updateHumanAI");
      ai_system::updateHumanAI(dt); // update the GOAP AI system for creatures
    }
  }
