#include "init.hpp"
#include "../components/components.hpp"
#include "../util/error_handling.hpp"
#include "../util/utilities.hpp"
#include "../util/startup_timer.hpp"
#include "engine_context.hpp"
#include "events.hpp"
#include "globals.hpp"
#include "graphics.hpp"
#include "gui.hpp"
#include "systems/physics/physics_components.hpp"
#include "systems/physics/physics_manager.hpp"
#include "systems/physics/physics_world.hpp"
#include "systems/uuid/uuid.hpp"
#include "third_party/chipmunk/include/chipmunk/chipmunk.h"
#include "third_party/unify/unify.hpp"

#include "../third_party/rlImGui/extras/FA6FreeSolidFontData.h"

#include "../systems/ai/ai_system.hpp"
#include "../systems/localization/localization.hpp"
#include "../systems/physics/physics_manager.hpp"
#include "../systems/shaders/shader_system.hpp"
#include "../systems/shaders/shader_presets.hpp"
#include "../systems/sound/sound_system.hpp"
#include "../systems/telemetry/telemetry.hpp"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <unordered_set>

#if defined(__EMSCRIPTEN__)
#include <emscripten/emscripten.h>
#endif

namespace init {

// Prefer context-backed atlas textures when available, with legacy fallback.
static Texture2D *resolveAtlasTexture(const std::string &atlasUUID) {
  return getAtlasTexture(atlasUUID);
}

namespace {
#ifndef SKIP_ASSET_SCAN_DEFAULT
#define SKIP_ASSET_SCAN_DEFAULT 0
#endif
#ifndef SKIP_UUID_DUMP_DEFAULT
#define SKIP_UUID_DUMP_DEFAULT 0
#endif
bool envFlagSet(const char *name) {
  if (const char *v = std::getenv(name)) {
    std::string val = v;
    std::transform(val.begin(), val.end(), val.begin(), ::tolower);
    return (val == "1" || val == "true" || val == "yes");
  }
  return false;
}
} // namespace

void scanAssetsFolderAndAddAllPaths() {
  const bool skipScan =
      (SKIP_ASSET_SCAN_DEFAULT != 0) || envFlagSet("SKIP_ASSET_SCAN");
  if (skipScan) {
    SPDLOG_INFO("Skipping asset scan ({}).", (SKIP_ASSET_SCAN_DEFAULT != 0)
                                                 ? "CMake default"
                                                 : "env SKIP_ASSET_SCAN");
    return;
  }
#ifdef __EMSCRIPTEN__
  auto folderPath = "assets";
#else
  // read in all items & folders from assets folder for uuid checking &
  // generation
  auto folderPath = util::getRawAssetPathNoUUID("");
#endif

  // This vector will store the paths of all files/folders encountered
  std::vector<std::string> subpaths;

  try {
    // Use a recursive_directory_iterator to go through subfolders as well.
    for (const auto &entry :
         std::filesystem::recursive_directory_iterator(folderPath)) {
      // Convert the path to a string and add it to our vector
      subpaths.push_back(entry.path().string());
    }

    // Print out all the subpaths we collected
    for (const auto &pathStr : subpaths) {
      // SPDLOG_DEBUG("Found asset folder subpath: {}", pathStr);
    }
  } catch (const std::filesystem::filesystem_error &e) {
    // Handle errors (e.g., invalid path, permission issues)
    SPDLOG_ERROR("Filesystem error: {}", e.what());
  } catch (const std::exception &e) {
    // Handle any other exceptions
    SPDLOG_ERROR("Error: {}", e.what());
  }

  std::unordered_set<std::string> seenPaths;
  std::unordered_set<std::string> seenFilenames;

  for (const auto &pathStr : subpaths) {
    if (seenPaths.insert(pathStr).second) {
      uuid::add(pathStr);
    }

    std::filesystem::path fsPath(pathStr);
    if (std::filesystem::is_regular_file(fsPath)) {
      auto filename = fsPath.filename().string(); // e.g., "enemy.png"
      if (seenFilenames.insert(filename).second) {
        uuid::add(filename);
      }
    }
  }
}

// Loads JSON data from various files and initializes game data structures.
auto loadJSONData() -> void {
  auto &bus = globals::getEventBus();
  bus.publish(events::LoadingStageStarted{"load_json_data"});

  try {
    // get language setting from config file
    // configuration file
    std::ifstream jsonStream{};

    // TODO: add all asset folder items to uuids

    auto assignJson = [&](const std::string &path, json &target,
                          json *ctxSlot) {
      auto loadResult = util::tryWithLog(
          [&]() -> json {
            jsonStream.open(path);
            if (!jsonStream.is_open()) {
              throw std::runtime_error("failed to open json: " + path);
            }
            json parsed = json::parse(jsonStream);
            jsonStream.close();
            return parsed;
          },
          std::string("json:load:") + path);

      if (loadResult.isErr()) {
        SPDLOG_ERROR("[json] {}", loadResult.error());
        telemetry::RecordEvent("json_load_failed",
                               {{"path", path},
                                {"error", loadResult.error()},
                                {"platform", telemetry::PlatformTag()},
                                {"build_id", telemetry::BuildId()}});
        return;
      }

      target = std::move(loadResult.value());
      if (ctxSlot && globals::g_ctx) {
        *ctxSlot = target;
      }
    };

    assignJson(util::getRawAssetPathNoUUID("raws/colors.json"),
               globals::colorsJSON,
               globals::g_ctx ? &globals::g_ctx->colorsJson : nullptr);
    assignJson(util::getRawAssetPathNoUUID("graphics/animations.json"),
               globals::animationsJSON,
               globals::g_ctx ? &globals::g_ctx->animationsJson : nullptr);
    assignJson(util::getRawAssetPathNoUUID("config.json"), globals::configJSON,
               globals::g_ctx ? &globals::g_ctx->configJson : nullptr);
    telemetry::Configure(telemetry::Config::FromConfigJson(globals::configJSON));
    telemetry::RecordEvent("app_start",
                           {{"stage", "config_loaded"},
                            {"platform", telemetry::PlatformTag()},
                            {"build_id", telemetry::BuildId()},
                            {"build_type", telemetry::BuildTypeTag()},
                            {"release_mode", globals::getReleaseMode()},
                            {"telemetry_enabled", telemetry::GetConfig().enabled},
                            {"distinct_id", telemetry::GetConfig().distinctId},
                            {"session_id", telemetry::SessionId()},
                            {"locale", globals::configJSON.value("game_language", std::string{"unknown"})}});
    assignJson(util::getRawAssetPathNoUUID("scripts/scripting_config.json"),
               globals::aiConfigJSON,
               globals::g_ctx ? &globals::g_ctx->aiConfigJson : nullptr);
    assignJson(util::getRawAssetPathNoUUID("scripts/ai_worldstate.json"),
               globals::aiWorldstateJSON,
               globals::g_ctx ? &globals::g_ctx->aiWorldstateJson : nullptr);
    assignJson(util::getRawAssetPathNoUUID("scripts/ai_actions.json"),
               globals::aiActionsJSON,
               globals::g_ctx ? &globals::g_ctx->aiActionsJson : nullptr);

    {
      namespace fs = std::filesystem;
      const auto uiStringsPath =
          util::getRawAssetPathNoUUID("raws/ui_strings.json");
      if (fs::exists(uiStringsPath) && fs::file_size(uiStringsPath) > 0) {
        jsonStream.open(uiStringsPath);
        globals::uiStringsJSON = json::parse(jsonStream);
        jsonStream.close();
        if (globals::g_ctx)
          globals::g_ctx->uiStringsJson = globals::uiStringsJSON;
      }
    }

    {
      namespace fs = std::filesystem;
      const auto ninePatchPath =
          util::getRawAssetPathNoUUID("raws/9patch.json");
      if (fs::exists(ninePatchPath) && fs::file_size(ninePatchPath) > 0) {
        jsonStream.open(ninePatchPath);
        globals::ninePatchJSON = json::parse(jsonStream);
        jsonStream.close();
        if (globals::g_ctx)
          globals::g_ctx->ninePatchJson = globals::ninePatchJSON;
      }
    }

    // create map for fast draw access of sprites
    // map filename to frame rectangle

    loadInSpriteFramesFromJSON();

    loadColorsFromJSON();

    // dump uuids to a file for debugging & reference (dev builds only)
    const bool skipDump = (SKIP_UUID_DUMP_DEFAULT != 0) ||
                          envFlagSet("SKIP_UUID_DUMP") ||
                          globals::getReleaseMode();
    if (!skipDump) {
      uuid::dump_to_json(util::getRawAssetPathNoUUID(
          "all_uuids.json #auto_generated #verified.json"));
    } else {
      SPDLOG_INFO("Skipping UUID dump ({}).",
                  (SKIP_UUID_DUMP_DEFAULT != 0)
                      ? "CMake default"
                      : (globals::getReleaseMode() ? "release mode"
                                                   : "env SKIP_UUID_DUMP"));
    }
  } catch (const std::exception &e) {
    bus.publish(
        events::LoadingStageCompleted{"load_json_data", false, e.what()});
    throw;
  }

  bus.publish(events::LoadingStageCompleted{"load_json_data", true, {}});
}

void loadAnimationsFromJSON() {
  auto &bus = globals::getEventBus();
  bus.publish(events::LoadingStageStarted{"load_animations"});
  try {
    for (auto &animation : globals::animationsJSON.items()) {

      SPDLOG_DEBUG("Starting load animation {} with UUID: {}", animation.key(),
                   uuid::add(animation.key()));
      AnimationObject ac{};

      // use uuid for animation id
      auto uuid = uuid::add(animation.key());

      ac.id = animation.key();
      ac.uuid = uuid;
      ac.currentAnimIndex = 0;

      for (auto &frameData : animation.value().at("frames")) {
        // skip char_cp437 reading for now (utf8 issues)
        uuid::add("NONE"); // for color value NONE

        SpriteComponentASCII frame{};

        string colorNameStringFG = frameData.at("fg_color").get<string>();
        string colorNameStringBG = frameData.at("bg_color").get<string>();

        colorNameStringFG = uuid::lookup(colorNameStringFG);
        colorNameStringBG = uuid::lookup(colorNameStringBG);

        if (colorNameStringBG == uuid::lookup("NONE")) {
          frame.noBackgroundColor = true;
        } else {
          frame.bgColor = util::getColor(colorNameStringBG);
        }

        if (colorNameStringFG == uuid::lookup("NONE")) {
          // frame.noForegroundColor = false;
          frame.fgColor = WHITE; // just retain original sprite color
        } else {
          frame.fgColor = util::getColor(colorNameStringFG);
        }

        frame.fgColor = util::getColor(frameData.at("fg_color"));
        frame.bgColor = util::getColor(frameData.at("bg_color"));
        frame.spriteUUID = frameData.at("sprite_UUID");

        using namespace snowhouse;
        const auto spriteFrameData =
            getSpriteFrame(frame.spriteUUID, globals::g_ctx);
        AssertThat(spriteFrameData.frame.width, IsGreaterThan(0));
        frame.spriteData.frame = spriteFrameData.frame;
        // TODO: need to load in the atlas to the texturemap
        auto atlasUUID = spriteFrameData.atlasUUID;
        if (auto *tex = resolveAtlasTexture(atlasUUID)) {
          frame.spriteData.texture = tex;
        } else {
          SPDLOG_ERROR(
              "Texture atlas '{}' not found while loading animation frame '{}'",
              atlasUUID, frame.spriteUUID);
        }
        frame.spriteFrame =
            std::make_shared<globals::SpriteFrameData>(spriteFrameData);

        double duration = frameData.at("duration_seconds");

        ac.animationList.emplace_back(frame, duration);
      }

      if (animation.value().contains("aseDirection")) {
        std::string dir = animation.value().at("aseDirection").get<std::string>();
        if (dir == "reverse") {
          ac.playbackDirection = PlaybackDirection::Reverse;
          ac.currentAnimIndex = ac.animationList.empty() ? 0 : ac.animationList.size() - 1;
        } else if (dir == "pingpong") {
          ac.playbackDirection = PlaybackDirection::Pingpong;
        } else if (dir == "pingpong_reverse") {
          ac.playbackDirection = PlaybackDirection::PingpongReverse;
          ac.pingpongReversing = true;
          ac.currentAnimIndex = ac.animationList.empty() ? 0 : ac.animationList.size() - 1;
        } else if (dir != "forward") {
          SPDLOG_WARN("Unknown aseDirection '{}' for animation '{}', defaulting to forward", dir, ac.id);
        }
      }

      globals::getAnimationsMap()[ac.id] = ac;
    }
  } catch (const std::exception &e) {
    bus.publish(
        events::LoadingStageCompleted{"load_animations", false, e.what()});
    throw;
  }

  bus.publish(events::LoadingStageCompleted{"load_animations", true, {}});
}

void loadColorsFromJSON() {
  auto &colorsJson = globals::getColorsJson();
  auto &colorsMap = globals::getColorsMap();
  for (auto &color : colorsJson) {
    // change to uuid
    auto colorName = std::string(color.at("name").get<string>());
    auto uuuid = uuid::add(colorName);

    int r = color.at("r").get<int>();
    int g = color.at("g").get<int>();
    int b = color.at("b").get<int>();
    int a = 255;
    // if alpha is present, use it
    if (color.find("a") != color.end()) {
      a = color.at("a").get<int>();
    }

    Color c{};
    c.r = r;
    c.g = g;
    c.b = b;
    c.a = a;

    colorsMap[uuuid] = c;

    // B) Append the "auto_generated_uuid" field
    color["auto_generated_uuid"] = uuuid;

    // SPDLOG_DEBUG("Loaded color {} with values r: {} g: {} b: {}", colorName,
    // r, g, b);
  }

  auto filePath = util::getRawAssetPathNoUUID("raws/colors.json");
  std::ofstream outFile(filePath);
  if (!outFile.is_open()) {
    SPDLOG_ERROR("Failed to open '{}' for writing.", filePath);
    return;
  }
  // Pretty-print with an indentation of 4 spaces
  outFile << colorsJson.dump(4);
  outFile.close();

  SPDLOG_INFO("Updated colors JSON saved to '{}'.", filePath);
}

void loadInSpriteFramesFromJSON() {
  namespace fs = std::filesystem;
  const std::string graphicsDir = util::getRawAssetPathNoUUID("graphics/");

  for (const auto &entry : fs::directory_iterator(graphicsDir)) {
    if (!entry.is_regular_file())
      continue;
    const auto &path = entry.path();

    // Match files like sprites-0.json, sprites-1.json, ...
    if (path.extension() == ".json" &&
        path.filename().string().starts_with("sprites-")) {
      std::ifstream jsonStream(path);
      if (!jsonStream.is_open()) {
        SPDLOG_ERROR("Failed to open sprite JSON '{}'", path.string());
        continue;
      }

      json spriteJson;
      jsonStream >> spriteJson;
      jsonStream.close();

      std::string jsonFilename =
          path.filename().string(); // e.g., "sprites-0.json"
      std::string indexPart = path.stem().string().substr(
          8); // Extract index after "sprites-", e.g., "0"
      std::string pngFilename =
          "sprites_atlas-" + indexPart + ".png"; // e.g., "sprites_atlas-0.png"

      // Generate UUID for the matching PNG
      std::string atlasUUID = uuid::add(pngFilename);

      for (auto &cp437Sprite : spriteJson.at("frames")) {
        std::string filename = cp437Sprite.at("filename").get<std::string>();

        // Normalize & derive aliases
        std::filesystem::path fpath(filename);
        const std::string baseName = fpath.filename().string(); // "tile008.png"
        const std::string parentName =
            fpath.parent_path().filename().string(); // "32x32_ui_popups"
        const std::string parentPlus =
            parentName.empty() ? baseName // "32x32_ui_popups/tile008.png"
                               : (parentName + "/" + baseName);

        // Register all keys with your UUID system
        // 1) whatever was in the JSON (full/relative path as provided)
        // 2) parent/filename
        // 3) filename only
        (void)uuid::add(filename);
        if (!parentName.empty())
          (void)uuid::add(parentPlus);
        (void)uuid::add(baseName);

        // Store one canonical UUID back into the JSON (keep your existing
        // behavior)
        std::string id = uuid::add(filename); // or choose baseName/parentPlus
                                              // as the canonical, your call
        cp437Sprite["auto_generated_uuid"] = id;

        // Extract frame details (unchanged)
        globals::SpriteFrameData data{};
        data.frame.x = cp437Sprite.at("frame").at("x").get<int>();
        data.frame.y = cp437Sprite.at("frame").at("y").get<int>();
        data.frame.width = cp437Sprite.at("frame").at("w").get<int>();
        data.frame.height = cp437Sprite.at("frame").at("h").get<int>();
        data.atlasUUID = atlasUUID;

        globals::getSpriteFrameMap()[filename] = data;
      }

      // Overwrite the updated JSON with UUIDs
      std::ofstream outFile(path);
      if (!outFile.is_open()) {
        SPDLOG_ERROR("Failed to open '{}' for writing.", path.string());
        continue;
      }

      outFile << spriteJson.dump(4);
      outFile.close();

      SPDLOG_INFO("Processed '{}', associated with '{}'", jsonFilename,
                  pngFilename);
    }
  }
}

Texture2D retrieveNotAtlasTexture(string refrence) {
  using namespace snowhouse;
  if (auto *tex = resolveAtlasTexture(refrence)) {
    return *tex;
  }
  SPDLOG_ERROR("Texture {} not found in atlas maps", refrence);
  return {};
}

/**
 * @brief Draw a texture from the loaded resources with advanced rendering
 * options.
 *
 * @param texId The ID of the texture in the global `allTextures` vector.
 * @param source The source rectangle defining the portion of the texture to
 * draw.
 * @param dest The destination rectangle defining where to draw the texture.
 * @param origin The point of rotation origin within the destination rectangle.
 * @param rotation The rotation angle (in degrees).
 * @param tint The tint color to apply to the texture.
 */
// void DrawGameTexture(unsigned int texId, mytypes::Rect source, mytypes::Rect
// dest, mytypes::Vec2 origin, float rotation, mytypes::Col tint)
// {
//     // Use DrawTexturePro to draw a texture with the specified parameters
//     DrawTexturePro(
//         allTextures[texId], // Texture to draw {source.position.x,
//         source.position.y, source.size.x, source.size.y}, // Source rectangle
//         {dest.position.x, dest.position.y, dest.size.x, dest.size.y}, //
//         Destination rectangle {origin.x, origin.y}, // Rotation origin
//         rotation, // Rotation angle {tint.r, tint.g, tint.b, tint.a} // Tint
//         color
//     );
// }

AnimationObject getAnimationObject(std::string uuid_or_raw_identifier,
                                   EngineContext *ctx) {
  using namespace snowhouse;
  const auto key = uuid::lookup(uuid_or_raw_identifier);

  EngineContext *effectiveCtx = ctx ? ctx : globals::g_ctx;
  if (effectiveCtx) {
    auto it = effectiveCtx->animations.find(key);
    if (it != effectiveCtx->animations.end()) {
      return it->second;
    }
  }

  auto &animations = globals::getAnimationsMap();
  if (animations.find(key) == animations.end()) {
    SPDLOG_ERROR(
        "Animation with UUID or identifier '{}' not found in animationsMap",
        uuid_or_raw_identifier);
  }
  AssertThat(animations.find(key) != animations.end(), IsTrue());
  return animations[key];
}

std::string getUIString(std::string uuid_or_raw_identifier,
                        EngineContext *ctx) {
  using namespace snowhouse;
  const auto key = uuid::lookup(uuid_or_raw_identifier);

  EngineContext *effectiveCtx = ctx ? ctx : globals::g_ctx;
  if (effectiveCtx) {
    auto it = effectiveCtx->uiStringsJson.find(key);
    if (it != effectiveCtx->uiStringsJson.end()) {
      return it->get<std::string>();
    }
  }

  auto &uiStrings = globals::getUiStringsJson();
  AssertThat(uiStrings.find(key) != uiStrings.end(), IsTrue());
  return uiStrings[key];
}

globals::SpriteFrameData getSpriteFrame(std::string uuid_or_raw_identifier,
                                        EngineContext *ctx) {
  using namespace snowhouse;
  const auto key = uuid::lookup(uuid_or_raw_identifier);

  EngineContext *effectiveCtx = ctx ? ctx : globals::g_ctx;
  if (effectiveCtx) {
    auto it = effectiveCtx->spriteFrames.find(key);
    if (it != effectiveCtx->spriteFrames.end()) {
      return it->second;
    }
  }

  auto &spriteFrames = globals::getSpriteFrameMap();
  if (spriteFrames.find(key) == spriteFrames.end()) {
    SPDLOG_ERROR("Sprite frame with UUID or identifier '{}' not found in "
                 "spriteDrawFrames",
                 uuid_or_raw_identifier);
  }
  AssertThat(spriteFrames.find(key) != spriteFrames.end(), IsTrue());
  return spriteFrames[key];
}

/**
 * Initializes the GUI for the game.
 * Sets up ImGui with a custom style and loads fonts based on the game language.
 * Also sets up toast messages.
 */
auto initGUI() -> void {
  // before your game loop
  // rlImGuiSetup(true); 	// sets up ImGui with ether a dark or light
  // default theme

  const json &configJsonRef = globals::getConfigJson();
  std::string englishFontName = configJsonRef.at("fonts").at("en");
  std::string translationFontName = configJsonRef.at("fonts").at(
      "ko"); // FIXME: hardcoded rn, should be in config file
  int defaultSize =
      configJsonRef.at("fonts").at("default_size").get<int>() + 10;

  // FIXME: config should make clear what is used for ui and what is used for
  // game
  // FIXME: this hardcodes korean, should change this later to read from config
  // file
  //  Korean character codepoints (Hangul syllables: 0xAC00 to 0xD7A3)
  std::vector<int> codepoints;

  // // Add English characters (Basic Latin: 0x0020 to 0x007E)
  for (int codepoint = 0x0020; codepoint <= 0x007E; ++codepoint) {
    codepoints.push_back(codepoint);
  }

  // Hangul Syllables
  for (int i = 0xAC00; i <= 0xD7A3; ++i) {
    codepoints.push_back(i);
  }

  // Hangul Jamo
  for (int i = 0x1100; i <= 0x11FF; ++i) {
    codepoints.push_back(i);
  }

  // Hangul Compatibility Jamo
  for (int i = 0x3130; i <= 0x318F; ++i) {
    codepoints.push_back(i);
  }

  // Basic Latin (ASCII)
  for (int i = 0x0020; i <= 0x007E; ++i) {
    codepoints.push_back(i);
  }

  // Font font = GetFontDefault();
  // Font font = LoadFont(util::getAssetPathUUIDVersion("fonts/pixelplay.png");
  // NOTE: We define a font base size of 32 pixels tall and up-to 250 characters
  // globals::font =
  // LoadFontEx(util::getAssetPathUUIDVersion(englishFontName).c_str(),
  // defaultSize, 0, 250); globals::smallerFont =
  // LoadFontEx(util::getAssetPathUUIDVersion(englishFontName).c_str(),
  // defaultSize / 2, 0, 250); globals::translationFont =
  // LoadFontEx(util::getAssetPathUUIDVersion(translationFontName).c_str(),
  // defaultSize, codepoints.data(), codepoints.size());

  // rlImGuiReloadFonts();// build font atlas
}

/**
 * Initializes the ECS system by connecting listeners to the registry for
 * updating and destroying LocationComponent. Listeners are invoked after
 * updating the component and before removing the component from the entity.
 * TODO: make sure patch() is used to update location of entities now.
 */
auto initECS() -> void {
  // registry.on_update<LocationComponent>().connect<&game::onLocationComponentUpdated>();
  // // call this function whenever location component is changed with replace,
  // emplace_or_replace or patch

  // registry.on_destroy<LocationComponent>().connect<&game::onLocationComponentDestroyed>();
  // // call this function whenever location component is destroyed

  // on_construct - Listeners are invoked **after** assigning the component to
  // the entity.

  // on_destroy - Listeners are invoked **before** removing the component from
  // the entity.

  // on_update - Listeners are invoked **after** updating the component.
}

/**
 * Loads all sprite atlas textures from the graphics directory using UUIDs.
 */
auto loadTextures() -> void {
  namespace fs = std::filesystem;
  auto &bus = globals::getEventBus();
  bus.publish(events::LoadingStageStarted{"load_textures"});
  try {
    const std::string graphicsDir = util::getRawAssetPathNoUUID("graphics/");

    for (const auto &entry : fs::directory_iterator(graphicsDir)) {
      if (!entry.is_regular_file())
        continue;

      const auto &path = entry.path();
      if (path.extension() == ".png" &&
          path.filename().string().starts_with("sprites_atlas-")) {
        std::string pngFilename =
            path.filename().string(); // e.g., sprites-0.png

        // Register and get UUID
        std::string uuid = uuid::add(pngFilename);

        // Load texture with guard
        const auto texResult = util::tryWithLog(
            [&]() { return LoadTexture(path.string().c_str()); },
            std::string("asset:loadTexture:") + pngFilename);
        if (texResult.isErr()) {
          SPDLOG_ERROR("[asset] Failed to load '{}': {}", pngFilename,
                       texResult.error());
          continue;
        }

        Texture2D tex = texResult.value();
        if (tex.id == 0) {
          SPDLOG_ERROR("[asset] Texture '{}' returned id==0", pngFilename);
          continue;
        }

        SetTextureWrap(tex, TEXTURE_WRAP_CLAMP);

        // Store in atlas map
        globals::getTextureAtlasMap()[uuid] = tex;

        SPDLOG_INFO("Loaded texture '{}' as UUID '{}'", pngFilename, uuid);
      }
    }

    // iterate through every animation object and populate the texture map with
    // the atlas textures
    for (auto &animation : globals::getAnimationsMap()) {
      auto &anim = animation.second;
      for (auto &frame : anim.animationList) {
        auto &spriteData = frame.first.spriteData;
        if (spriteData.texture == nullptr) {
          // Load the texture using the UUID
          auto *tex = resolveAtlasTexture(frame.first.spriteFrame->atlasUUID);
          if (tex == nullptr) {
            SPDLOG_ERROR("Texture atlas '{}' not found when populating "
                         "animation textures",
                         frame.first.spriteFrame->atlasUUID);
            continue;
          }
          spriteData.texture = tex;
          spriteData.frame =
              frame.first.spriteFrame
                  ->frame; // set the frame to the spriteFrame data
          // FIXME: we are using both spriteData and spriteFrame, need to phase
          // out one of them
        }
      }
    }

  } catch (const std::exception &e) {
    bus.publish(
        events::LoadingStageCompleted{"load_textures", false, e.what()});
    throw;
  }
  bus.publish(events::LoadingStageCompleted{"load_textures", true, {}});
}

auto loadSounds() -> void {
  auto &bus = globals::getEventBus();
  bus.publish(events::LoadingStageStarted{"load_sounds"});
  try {
    auto audioInit = util::tryWithLog(
        [&]() {
          InitAudioDevice();
          SetAudioStreamBufferSizeDefault(4096);
        },
        "audio:init");

    if (audioInit.isErr()) {
      SPDLOG_ERROR("[audio] init failed: {}", audioInit.error());
      bus.publish(events::LoadingStageCompleted{"load_sounds", false,
                                                audioInit.error()});
      return;
    }

    if (globals::g_ctx && globals::g_ctx->audio) {
      globals::g_ctx->audio->deviceInitialized = true;
    }
  } catch (const std::exception &e) {
    bus.publish(events::LoadingStageCompleted{"load_sounds", false, e.what()});
    throw;
  }
  bus.publish(events::LoadingStageCompleted{"load_sounds", true, {}});
}

// Iterate over all shapes stored in a ColliderComponent (main + extras).
template <typename Fn>
inline void ForEachShapeConst(const physics::ColliderComponent &cc, Fn &&fn) {
  if (cc.shape)
    fn(cc.shape.get());
  for (auto &extra : cc.extraShapes) {
    if (extra.shape)
      fn(extra.shape.get());
  }
}

static void onColliderDestroyed(entt::registry &R, entt::entity e) {
  // This should exist in on_destroy<ColliderComponent>, but guard anyway.
  auto *c = R.try_get<physics::ColliderComponent>(e);
  if (!c)
    return;

  ForEachShapeConst(*c, [&](cpShape *s) {
    if (!s)
      return;
    if (cpSpace *sp = cpShapeGetSpace(s)) {
      cpSpaceRemoveShape(sp, s);
    }
  });

  if (c->body) {
    if (cpSpace *sp = cpBodyGetSpace(c->body.get())) {
      cpSpaceRemoveBody(sp, c->body.get());
    }
  }
  // Let shared_ptr destructors do the actual cpShapeFree/cpBodyFree later.
}

/**
 * @brief Initializes the game engine by setting up logging, loading JSON data
 * and configuration file values, initializing the window, GUI, ECS, AI, and
 * world, loading textures, and performing various tests.
 *
 * @return void
 */
auto base_init() -> void {
  startup_timer::ScopedPhase total_init("total_init");

  // logging setup
  spdlog::set_level(spdlog::level::trace);

  // load root json and other data init from json
  {
    startup_timer::ScopedPhase phase("asset_scanning");
    scanAssetsFolderAndAddAllPaths();
  }

  {
    startup_timer::ScopedPhase phase("json_loading");
    loadJSONData();
    loadColorsFromJSON();
    loadInSpriteFramesFromJSON();
    loadConfigFileValues(); // should be called after loadJSONData()
    // in general, loadConfigFileValues() should be called before any pertinent
    // values are used
  }

  // load physics manager
  {
    startup_timer::ScopedPhase phase("physics_init");
    globals::physicsManager =
        std::make_shared<PhysicsManager>(globals::getRegistry());
    if (globals::g_ctx) {
      globals::g_ctx->physicsManager = globals::physicsManager;
    }

    // set up physics component destruction
    globals::getRegistry()
        .on_destroy<physics::ColliderComponent>()
        .connect<&onColliderDestroyed>();
  }

  {
    startup_timer::ScopedPhase phase("window_graphics_init");
    SetConfigFlags(FLAG_WINDOW_RESIZABLE | FLAG_WINDOW_UNDECORATED);
    InitWindow(globals::getScreenWidth(), globals::getScreenHeight(), "Game");
    SetWindowMinSize(400, 300); // Enforce minimum window size for UI
    SetTextureFilter(GetFontDefault().texture, TEXTURE_FILTER_POINT);

    // fixes mac input bug.
    SetGamepadMappings(LoadFileText(
        util::getRawAssetPathNoUUID("gamecontrollerdb.txt").c_str()));
  }

  {
    startup_timer::ScopedPhase phase("imgui_init");
    // these methods cause crash when taskflow is used
    rlImGuiSetup(true); // sets up ImGui with ether a dark or light default theme
    initGUI();
    gui::initConsole(); // Initialize the debugging console
  }

  {
    startup_timer::ScopedPhase phase("texture_loading");
    loadTextures();
  }

  {
    startup_timer::ScopedPhase phase("animation_loading");
    // load animations map (spriteFrames and colors must be initialized before
    // this part)
    loadAnimationsFromJSON();
  }

  {
    startup_timer::ScopedPhase phase("audio_init");
    // InitAudioDevice(); done in audioManager
    loadSounds();
  }

  {
    startup_timer::ScopedPhase phase("ecs_init");
    initECS();
  }

  // Get the current time
  auto now = std::chrono::system_clock::now();
  // Convert it to a time_t object
  std::time_t now_c = std::chrono::system_clock::to_time_t(now);
  // Use it as a seed for random number generation
  Random::seed(now_c);

  // Print startup summary
  startup_timer::print_summary();
}

// Initializes the necessary systems for the application to run.
// This includes initializing the Lua state shared by all systems and calling
// name_gen::init().
auto initSystems() -> void {
  ai_system::init();

  // Check if lazy shader loading is enabled in config
  if (globals::configJSON.contains("performance") &&
      globals::configJSON["performance"].contains("enable_lazy_shader_loading")) {
    shaders::enableLazyShaderLoading = globals::configJSON["performance"]["enable_lazy_shader_loading"].get<bool>();
    if (shaders::enableLazyShaderLoading) {
      SPDLOG_INFO("Lazy shader loading enabled via config.json");
    }
  }

  shaders::loadShadersFromJSON("shaders/shaders.json");

  // Load shader presets after shaders are loaded
  if (globals::g_ctx) {
    shader_presets::loadPresetsFromLuaFile(globals::g_ctx->lua, "assets/scripts/data/shader_presets.lua");
  }

  sound_system::LoadFromJSON(util::getRawAssetPathNoUUID("sounds/sounds.json"));
}

/**
 * @brief Initializes the game systems and world generation using Taskflow
 * library.
 *
 * @param loadingDone A boolean reference that will be set to true when loading
 * is done.
 */
auto startInit() -> void {
  startup_timer::ScopedPhase total_start_init("total_start_init");

  // try {
  SPDLOG_DEBUG("Starting taskflow task INIT.");

  {
    startup_timer::ScopedPhase phase("systems_init");
    initSystems();
  }

  globals::loadingStateIndex++;

  {
    startup_timer::ScopedPhase phase("ecs_init_2");
    initECS();
  }

  globals::loadingStateIndex++;

  {
    startup_timer::ScopedPhase phase("localization_init");
    localization::setFallbackLanguage("en_us");
    localization::loadLanguage("en_us",
                               util::getRawAssetPathNoUUID("localization/"));
    localization::loadLanguage("ko_kr",
                               util::getRawAssetPathNoUUID("localization/"));
    localization::setCurrentLanguage("en_us");
    localization::loadFontData(
        util::getRawAssetPathNoUUID("localization/fonts.json"));
    // Named fonts (like "tooltip") are now loaded from fonts.json namedFonts section
  }

  // moved over from next task to see if this helps with crash
  Random::seed(globals::getConfigJson().at("seed").get<unsigned>());
  // initWorld(worldGenCurrentStep);
  globals::loadingStateIndex++;
  // }
  // catch(const std::exception& e) {
  //     SPDLOG_ERROR("Error in taskflow INIT task: {}", e.what());
  // }
  // try {
  //     // Random::seed(configJSON.at("seed").get<unsigned>());
  //     SPDLOG_DEBUG("Starting taskflow task WORLD_GEN.");\
        //     globals::loadingStateIndex++;
  // }
  // catch(const std::exception& e) {
  //     SPDLOG_ERROR("Error in taskflow WORLD_GEN task: {}", e.what());
  // }

  SPDLOG_DEBUG("Loading finished.");
  globals::setCurrentGameState(GameState::MAIN_MENU);

#if defined(__EMSCRIPTEN__)
  // Signal to the web shell that the game is ready (triggers loading screen fade-out)
  EM_ASM({
    if (typeof window.gameReady === 'function') {
      window.gameReady();
    }
  });
#endif

  // Print startup summary
  startup_timer::print_summary();
}

// Function to save the UUID map to a file
void saveUUIDMapToFile(
    const std::unordered_map<std::string, std::string> &uuidMap,
    const std::string &outputPath) {
  nlohmann::json outputJson;

  for (const auto &[filename, uuid] : uuidMap) {
    outputJson[filename] = uuid;
  }

  // Write JSON to file
  std::ofstream outFile(outputPath);
  if (!outFile) {
    SPDLOG_ERROR("Failed to open file '{}' for writing UUID map", outputPath);
    return;
  }
  outFile << outputJson.dump(4); // Pretty-print with 4 spaces
  SPDLOG_INFO("UUID map saved to '{}'", outputPath);
}

// Function to extract file number from the filename (filename-X.png or
// filename-X.json or X-filename.png or X-filename.json) if it fails, it returns
// -1
auto extractFileNumber(const std::string &filename) -> int {
  // Pattern for numbers at the end of the filename
  std::regex hyphenNumberPattern(R"(-(\d+)\s*\.\w+$)");

  std::smatch match;

  // Check for a number at the end of the filename
  if (std::regex_search(filename, match, hyphenNumberPattern)) {
    return std::stoi(match[1].str()); // Use match[1] to get the number part
  }

  // Check for a number at the start
  std::regex numberHyphenPattern(R"(^(\d+)-.*\.\w+$)");
  if (std::regex_search(filename, match, numberHyphenPattern)) {
    return std::stoi(match[1].str());
  }

  // If no number is found, return -1
  return -1;
}

/**
 * @brief Loads values from the configuration file into the corresponding
 * variables. Note that this function should be called after loadJSONData().
 *
 * @return void
 */
auto loadConfigFileValues() -> void {
  auto requireField = [](const json &j,
                         std::initializer_list<const char *> keys)
      -> util::Result<const json *, std::string> {
    const json *cur = &j;
    for (auto *k : keys) {
      if (!cur->contains(k)) {
        return util::Result<const json *, std::string>(
            std::string("missing config field: ") + k);
      }
      cur = &cur->at(k);
    }
    return util::Result<const json *, std::string>(cur);
  };

  auto widthField =
      requireField(globals::configJSON, {"render_data", "screen", "width"});
  auto heightField =
      requireField(globals::configJSON, {"render_data", "screen", "height"});

  if (widthField.isErr() || heightField.isErr()) {
    SPDLOG_ERROR("[config] {}",
                 widthField.isErr() ? widthField.error() : heightField.error());
    return;
  }

  globals::screenWidth = widthField.value()->get<int>();
  globals::screenHeight = heightField.value()->get<int>();
}

} // namespace init
