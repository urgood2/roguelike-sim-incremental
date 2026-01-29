/**
 * @file layer_lua_bindings.cpp
 * @brief Lua bindings for the layer system.
 * 
 * Extracted from layer.cpp for faster compilation and better organization.
 * Contains the exposeToLua() function which registers all layer-related
 * types and functions with the Lua state.
 */

#include "layer.hpp"

#if defined(PLATFORM_WEB)
#include "util/web_glad_shim.hpp"
#endif

#if defined(__EMSCRIPTEN__)
#define GL_GLEXT_PROTOTYPES
#include <GLES3/gl3.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#else
// #include <GL/gl.h>
// #include <GL/glext.h>
#endif

#include "raylib.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <functional>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <variant>
#include <vector>

#include "core/engine_context.hpp"
#include "core/globals.hpp"
#include "core/init.hpp"
#include "spdlog/spdlog.h"
#include "systems/camera/camera_manager.hpp"
#include "systems/collision/broad_phase.hpp"
#include "systems/layer/layer_optimized.hpp"
#include "systems/scripting/script_process.hpp"
#include "systems/shaders/shader_pipeline.hpp"
#include "systems/ui/box.hpp"
#include "systems/ui/element.hpp"
#include "systems/ui/ui_data.hpp"
#include "systems/uuid/uuid.hpp"
#include "util/error_handling.hpp"

#include "systems/layer/layer_command_buffer_data.hpp"
#include "systems/transform/transform_functions.hpp"

#include "entt/entt.hpp"
#include "rlgl.h"
#include "snowhouse/snowhouse.h"
#include "util/common_headers.hpp"
#include "layer_command_buffer.hpp"
#include "systems/scripting/binding_recorder.hpp"

// Maximum depth for nested transform composite renders
static constexpr size_t MAX_RENDER_STACK_DEPTH = 16;

template <typename F>
static void QueueScopedTransformCompositeRender(
    std::shared_ptr<layer::Layer> layer, entt::entity e, int z,
    layer::DrawCommandSpace space, F &&buildChildren) {
  static std::array<std::vector<layer::DrawCommandV2> *, MAX_RENDER_STACK_DEPTH> s_commandStackArr;
  static int s_stackTop = 0;

  auto *cmd = layer::layer_command_buffer::Add<
      layer::CmdScopedTransformCompositeRender>(layer, z, space);
  cmd->entity = e;

  // Pre-reserve a few children slots
  cmd->children.reserve(8);

  // Populate shader/texture IDs for batching optimization
  layer::layer_command_buffer::PopulateLastCommandIDs<layer::CmdScopedTransformCompositeRender>(layer, cmd);

  auto *prevList = layer->commands_ptr;
  layer->commands_ptr = &cmd->children;

  // Overflow protection for nested render stacks
  if (static_cast<size_t>(s_stackTop) >= MAX_RENDER_STACK_DEPTH) {
    SPDLOG_ERROR("Render stack overflow! Max depth: {}. Skipping nested render.", MAX_RENDER_STACK_DEPTH);
    layer->commands_ptr = prevList;
    return;
  }

  s_commandStackArr[s_stackTop++] = &cmd->children;
  std::forward<F>(buildChildren)();
  --s_stackTop;

  layer->commands_ptr = prevList;
}

namespace layer {

void exposeToLua(sol::state &lua, EngineContext *ctx) {

  sol::state_view luaView{lua};
  auto layerTbl = luaView["layer"].get_or_create<sol::table>();
  if (!layerTbl.valid()) {
    layerTbl = lua.create_table();
    lua["layer"] = layerTbl;
  }

  auto &rec = BindingRecorder::instance();

  // --- Rectangle binding
  // -------------------------------------------------------
  {
    // 1) Usertype with constructors and fields
    auto rectUT = lua.new_usertype<Rectangle>(
        "Rectangle", sol::no_constructor, "x", &Rectangle::x, "y",
        &Rectangle::y, "width", &Rectangle::width, "height", &Rectangle::height,
        // nice for debugging
        sol::meta_function::to_string, [](const Rectangle &r) {
          char buf[96];
          std::snprintf(buf, sizeof(buf),
                        "Rectangle(x=%.2f, y=%.2f, w=%.2f, h=%.2f)", r.x, r.y,
                        r.width, r.height);
          return std::string(buf);
        });

    // Attach a static Rectangle.new(...)
    sol::table rectTbl = lua["Rectangle"];
    rectTbl.set_function(
        "new", sol::overload([]() { return Rectangle{0.f, 0.f, 0.f, 0.f}; },
                             [](float x, float y, float w, float h) {
                               return Rectangle{x, y, w, h};
                             },
                             [](sol::table t) {
                               Rectangle r{};
                               r.x = t.get_or("x", 0.0f);
                               r.y = t.get_or("y", 0.0f);
                               r.width = t.get_or("width", 0.0f);
                               r.height = t.get_or("height", 0.0f);
                               return r;
                             }));

    // 2) Optional utility methods (handy but lightweight)
    rectUT.set_function("center", [](const Rectangle &r) {
      return Vector2{r.x + r.width * 0.5f, r.y + r.height * 0.5f};
    });
    rectUT.set_function("contains", [](const Rectangle &r, float px, float py) {
      return (px >= r.x) && (py >= r.y) && (px <= r.x + r.width) &&
             (py <= r.y + r.height);
    });
    rectUT.set_function("area",
                        [](const Rectangle &r) { return r.width * r.height; });

    // 3) Nice __tostring for debugging
    rectUT[sol::meta_function::to_string] = [](const Rectangle &r) {
      char buf[128];
      std::snprintf(buf, sizeof(buf),
                    "Rectangle(x=%.2f, y=%.2f, w=%.2f, h=%.2f)", r.x, r.y,
                    r.width, r.height);
      return std::string(buf);
    };

    // 4) Convenience free-function constructors:
    //    Rect(x,y,w,h) and Rect{ x=..., y=..., width=..., height=... }
    lua.set_function(
        "Rect", sol::overload([](float x, float y, float w,
                                 float h) { return Rectangle{x, y, w, h}; },
                              [](sol::table t) {
                                Rectangle r{};
                                r.x = t.get_or("x", 0.0f);
                                r.y = t.get_or("y", 0.0f);
                                r.width = t.get_or("width", 0.0f);
                                r.height = t.get_or("height", 0.0f);
                                return r;
                              }));

    // 5) (Optional) Recorder entries for your BindingRecorder docs
    rec.add_type("Rectangle", true).doc = "Raylib Rectangle (x,y,width,height)";
    rec.record_property("Rectangle", {"x", "number", "Top-left X"});
    rec.record_property("Rectangle", {"y", "number", "Top-left Y"});
    rec.record_property("Rectangle", {"width", "number", "Width"});
    rec.record_property("Rectangle", {"height", "number", "Height"});
  }

  // --- NPatchInfo binding
  // -------------------------------------------------------
  {
    auto npatchUT = lua.new_usertype<NPatchInfo>(
        "NPatchInfo", sol::no_constructor,
        "source", &NPatchInfo::source,
        "left", &NPatchInfo::left,
        "top", &NPatchInfo::top,
        "right", &NPatchInfo::right,
        "bottom", &NPatchInfo::bottom,
        "layout", &NPatchInfo::layout,
        sol::meta_function::to_string, [](const NPatchInfo &n) {
          char buf[128];
          std::snprintf(buf, sizeof(buf),
                        "NPatchInfo(left=%d, top=%d, right=%d, bottom=%d)",
                        n.left, n.top, n.right, n.bottom);
          return std::string(buf);
        });

    // Attach a static NPatchInfo.new(...)
    sol::table npatchTbl = lua["NPatchInfo"];
    npatchTbl.set_function(
        "new", sol::overload(
            []() { return NPatchInfo{}; },
            [](Rectangle source, int left, int top, int right, int bottom) {
              NPatchInfo n{};
              n.source = source;
              n.left = left;
              n.top = top;
              n.right = right;
              n.bottom = bottom;
              n.layout = NPATCH_NINE_PATCH;
              return n;
            }));

    rec.add_type("NPatchInfo", true).doc = "Raylib NPatchInfo for 9-patch rendering";
    rec.record_property("NPatchInfo", {"source", "Rectangle", "Source rectangle in texture"});
    rec.record_property("NPatchInfo", {"left", "integer", "Left border offset"});
    rec.record_property("NPatchInfo", {"top", "integer", "Top border offset"});
    rec.record_property("NPatchInfo", {"right", "integer", "Right border offset"});
    rec.record_property("NPatchInfo", {"bottom", "integer", "Bottom border offset"});
    rec.record_property("NPatchInfo", {"layout", "integer", "NPatch layout type"});
  }

  rec.add_type("layer").doc = "namespace for rendering & layer operations";
  rec.add_type("layer.LayerOrderComponent", true).doc =
      "Stores Z-index for layer sorting";
  layerTbl.new_usertype<layer::LayerOrderComponent>(
      "LayerOrderComponent", sol::constructors<>(), "zIndex",
      &layer::LayerOrderComponent::zIndex, "type_id",
      []() { return entt::type_hash<layer::LayerOrderComponent>::value(); });
  rec.record_property("layer.LayerOrderComponent",
                      {"zIndex", "integer", "Z sort order"});

  rec.add_type("layer.Layer", true).doc =
      "Represents a drawing layer and its properties.";
  layerTbl.new_usertype<layer::Layer>(
      "Layer", sol::constructors<>(), "canvases", &layer::Layer::canvases,
      // "drawCommands",    &layer::Layer::drawCommands,
      "fixed", &layer::Layer::fixed, "zIndex", &layer::Layer::zIndex,
      "backgroundColor", &layer::Layer::backgroundColor, "commands",
      &layer::Layer::commands, "isSorted", &layer::Layer::isSorted,
      "postProcessShaders", &layer::Layer::postProcessShaders,
      "removePostProcessShader", &layer::Layer::removePostProcessShader,
      "addPostProcessShader", &layer::Layer::addPostProcessShader,
      "clearPostProcessShaders", &layer::Layer::clearPostProcessShaders,
      "type_id", []() { return entt::type_hash<layer::Layer>::value(); });
  std::vector<std::string> postProcessShaders;

  rec.record_property("layer.Layer",
                      {"canvases", "table", "Map of canvas names to textures"});
  rec.record_property("layer.Layer", {"drawCommands", "table", "Command list"});
  rec.record_property("layer.Layer",
                      {"fixed", "boolean", "Whether layer is fixed"});
  rec.record_property("layer.Layer", {"zIndex", "integer", "Z-index"});
  rec.record_property("layer.Layer",
                      {"backgroundColor", "Color", "Background fill color"});
  rec.record_property("layer.Layer",
                      {"commands", "table", "Draw commands list"});
  rec.record_property("layer.Layer",
                      {"isSorted", "boolean", "True if layer is sorted"});
  rec.record_property("layer.Layer",
                      {"postProcessShaders", "vector",
                       "List of post-process shaders to run after drawing"});

  rec.record_free_function(
      {"layer.Layer"},
      MethodDef{.name = "removePostProcessShader",
                .signature = R"(---@param layer Layer # Target layer
        ---@param shader_name string # Name of the shader to remove
        ---@return void)",
                .doc =
                    R"(Removes a post-process shader from the layer by name.)",
                .is_static = true,
                .is_overload = false});

  rec.record_free_function(
      {"layer.Layer"},
      MethodDef{.name = "addPostProcessShader",
                .signature = R"(---@param layer Layer # Target layer
        ---@param shader_name string # Name of the shader to add
        ---@param shader Shader # Shader instance to add
        ---@return void)",
                .doc = R"(Adds a post-process shader to the layer.)",
                .is_static = true,
                .is_overload = false});

  rec.record_free_function(
      {"layer.Layer"},
      MethodDef{.name = "clearPostProcessShaders",
                .signature = R"(---@param layer Layer # Target layer
        ---@return void)",
                .doc = R"(Removes all post-process shaders from the layer.)",
                .is_static = true,
                .is_overload = false});

  layerTbl["layers"] = &layer::layers;
  rec.record_property("layer", {"layers", "table", "Global list of layers"});

  // 5) Overloads helpers
  using LPtr = std::shared_ptr<layer::Layer>;

  // // 6) Functions
  layerTbl.set_function("SortLayers", &layer::SortLayers);
  layerTbl.set_function("UpdateLayerZIndex", &layer::UpdateLayerZIndex);
  layerTbl.set_function("CreateLayer", &layer::CreateLayer);
  layerTbl.set_function("CreateLayerWithSize", &layer::CreateLayerWithSize);
  layerTbl.set_function("RemoveLayerFromCanvas", &layer::RemoveLayerFromCanvas);

  rec.bind_function(lua, {"layer"}, "SortLayers", &layer::SortLayers,
                    "---@return nil",
                    "Sorts all layers by their Z-index.");

  rec.bind_function(
      lua, {"layer"}, "UpdateLayerZIndex", &layer::UpdateLayerZIndex,
      "---@param layer layer.Layer\n"
      "---@param newZIndex integer\n"
      "---@return nil",
      "Updates the Z-index of a layer and resorts the layer list.");

  rec.bind_function(
      lua, {"layer"}, "CreateLayer", &layer::CreateLayer,
      "---@return layer.Layer",
      "Creates a new layer with a default-sized main canvas and returns it.");

  rec.bind_function(lua, {"layer"}, "CreateLayerWithSize",
                    &layer::CreateLayerWithSize,
                    "---@param width integer\n"
                    "---@param height integer\n"
                    "---@return layer.Layer",
                    "Creates a layer with a main canvas of a specified size.");

  rec.bind_function(lua, {"layer"}, "ExecuteScale", &layer::Scale,
                    "---@param x number # Scale factor in X direction\n"
                    "---@param y number # Scale factor in Y direction\n"
                    "---@return nil",
                    "Applies scaling transformation to the current layer, "
                    "immeidately (does not queue).");

  rec.bind_function(lua, {"layer"}, "ExecuteTranslate", &layer::Translate,
                    "---@param x number # Translation in X direction\n"
                    "---@param y number # Translation in Y direction\n"
                    "---@return nil",
                    "Applies translation transformation to the current layer, "
                    "immeidately (does not queue).");

  rec.bind_function(lua, {"layer"}, "RemoveLayerFromCanvas",
                    &layer::RemoveLayerFromCanvas,
                    "---@param layer layer.Layer\n"
                    "---@return nil",
                    "Removes a layer and unloads its canvases.");

  rec.bind_function(lua, {"layer"}, "ResizeCanvasInLayer",
                    &layer::ResizeCanvasInLayer,
                    "---@param layer layer.Layer\n"
                    "---@param canvasName string\n"
                    "---@param newWidth integer\n"
                    "---@param newHeight integer\n"
                    "---@return nil",
                    "Resizes a specific canvas within a layer.");

  // --- Corrected Overload Handling for AddCanvasToLayer ---
  // Base function
  rec.bind_function(
      lua, {"layer"}, "AddCanvasToLayer",
      static_cast<void (*)(LPtr, const std::string &)>(
          &layer::AddCanvasToLayer),
      "---@param layer layer.Layer\n"
      "---@param canvasName string\n"
      "---@return nil",
      "Adds a canvas to the layer, matching the layer's default size.",
      /*is_overload=*/false);
  // Overload with size
  rec.bind_function(lua, {"layer"}, "AddCanvasToLayer",
                    static_cast<void (*)(LPtr, const std::string &, int, int)>(
                        &layer::AddCanvasToLayer),
                    "---@overload fun(layer: layer.Layer, canvasName: string, "
                    "width: integer, height: integer):nil",
                    "Adds a canvas of a specific size to the layer.",
                    /*is_overload=*/true);

  rec.bind_function(lua, {"layer"}, "RemoveCanvas", &layer::RemoveCanvas,
                    "---@param layer layer.Layer\n"
                    "---@param canvasName string\n"
                    "---@return nil",
                    "Removes a canvas by name from a specific layer.");

  rec.bind_function(lua, {"layer"}, "UnloadAllLayers", &layer::UnloadAllLayers,
                    "---@return nil",
                    "Destroys all layers and their contents.");

  rec.bind_function(lua, {"layer"}, "ClearDrawCommands",
                    &layer::ClearDrawCommands,
                    "---@param layer layer.Layer\n"
                    "---@return nil",
                    "Clears draw commands for a specific layer.");

  rec.bind_function(lua, {"layer"}, "ClearAllDrawCommands",
                    &layer::ClearAllDrawCommands,
                    "---@return nil",
                    "Clears all draw commands from all layers.");

  rec.bind_function(
      lua, {"layer"}, "Begin", &layer::Begin,
      "---@return nil",
      "Begins drawing to all canvases. (Calls BeginTextureMode on all).");

  rec.bind_function(
      lua, {"layer"}, "End", &layer::End,
      "---@return nil",
      "Ends drawing to all canvases. (Calls EndTextureMode on all).");

  rec.bind_function(
      lua, {"layer"}, "RenderAllLayersToCurrentRenderTarget",
      &layer::RenderAllLayersToCurrentRenderTarget,
      "---@param camera? Camera2D # Optional camera for rendering.\n"
      "---@return nil",
      "Renders all layers to the current render target.");

  rec.bind_function(
      lua, {"layer"}, "DrawLayerCommandsToSpecificCanvas",
      static_cast<void (*)(LPtr, const std::string &, Camera2D *)>(
          &layer::DrawLayerCommandsToSpecificCanvasOptimizedVersion),
      "---@param layer layer.Layer\n"
      "---@param canvasName string\n"
      "---@param camera Camera2D # The camera to use for rendering.\n"
      "---@return nil",
      "Draws a layer's queued commands to a specific canvas within that "
      "layer.");

  rec.bind_function(lua, {"layer"},
                    "DrawCanvasToCurrentRenderTargetWithTransform",
                    &layer::DrawCanvasToCurrentRenderTargetWithTransform,
                    "---@param layer layer.Layer\n"
                    "---@param canvasName string\n"
                    "---@param x? number\n"
                    "---@param y? number\n"
                    "---@param rotation? number\n"
                    "---@param scaleX? number\n"
                    "---@param scaleY? number\n"
                    "---@param color? Color\n"
                    "---@param shader? Shader\n"
                    "---@param flat? boolean\n"
                    "---@return nil",
                    "Draws a canvas to the current render target with "
                    "transform, color, and an optional shader.");

  rec.bind_function(
      lua, {"layer"}, "DrawCanvasOntoOtherLayer",
      &layer::DrawCanvasOntoOtherLayer,
      "---@param sourceLayer layer.Layer\n"
      "---@param sourceCanvasName string\n"
      "---@param destLayer layer.Layer\n"
      "---@param destCanvasName string\n"
      "---@param x number\n"
      "---@param y number\n"
      "---@param rotation number\n"
      "---@param scaleX number\n"
      "---@param scaleY number\n"
      "---@param tint Color\n"
      "---@return nil",
      "Draws a canvas from one layer onto a canvas in another layer.");

  rec.bind_function(
      lua, {"layer"}, "DrawCanvasOntoOtherLayerWithShader",
      &layer::DrawCanvasOntoOtherLayerWithShader,
      "---@param sourceLayer layer.Layer\n"
      "---@param sourceCanvasName string\n"
      "---@param destLayer layer.Layer\n"
      "---@param destCanvasName string\n"
      "---@param x number\n"
      "---@param y number\n"
      "---@param rotation number\n"
      "---@param scaleX number\n"
      "---@param scaleY number\n"
      "---@param tint Color\n"
      "---@param shader Shader\n"
      "---@return nil",
      "Draws a canvas from one layer onto another with a shader.");

  rec.bind_function(lua, {"layer"},
                    "DrawCanvasToCurrentRenderTargetWithDestRect",
                    &layer::DrawCanvasToCurrentRenderTargetWithDestRect,
                    "---@param layer layer.Layer\n"
                    "---@param canvasName string\n"
                    "---@param destRect Rectangle\n"
                    "---@param color Color\n"
                    "---@param shader Shader\n"
                    "---@return nil",
                    "Draws a canvas to the current render target, fitting it "
                    "to a destination rectangle.");

  rec.bind_function(
      lua, {"layer"}, "DrawCustomLamdaToSpecificCanvas",
      &layer::DrawCustomLamdaToSpecificCanvas,
      "---@param layer layer.Layer\n"
      "---@param canvasName? string\n"
      "---@param drawActions fun():void\n"
      "---@return nil",
      "Executes a custom drawing function that renders to a specific canvas.");

  rec.bind_function(
      lua, {"layer"}, "DrawTransformEntityWithAnimation",
      &layer::DrawTransformEntityWithAnimation,
      "---@param registry Registry\n"
      "---@param entity Entity\n"
      "---@return nil",
      "Draws an entity with a Transform and Animation component directly.");

  rec.bind_function(lua, {"layer"},
                    "DrawTransformEntityWithAnimationWithPipeline",
                    &layer::DrawTransformEntityWithAnimationWithPipeline,
                    "---@param registry Registry\n"
                    "---@param entity Entity\n"
                    "---@return nil",
                    "Draws an entity with a Transform and Animation component "
                    "using the rendering pipeline.");

  // 1) Bind DrawCommandType enum as a plain table:
  layerTbl["DrawCommandType"] = lua.create_table_with(
      "BeginDrawing", layer::DrawCommandType::BeginDrawing, "EndDrawing",
      layer::DrawCommandType::EndDrawing, "ClearBackground",
      layer::DrawCommandType::ClearBackground, "Translate",
      layer::DrawCommandType::Translate, "Scale", layer::DrawCommandType::Scale,
      "Rotate", layer::DrawCommandType::Rotate, "AddPush",
      layer::DrawCommandType::AddPush, "AddPop", layer::DrawCommandType::AddPop,
      "PushMatrix", layer::DrawCommandType::PushMatrix, "PopMatrix",
      layer::DrawCommandType::PopMatrix, "PushObjectTransformsToMatrix",
      layer::DrawCommandType::PushObjectTransformsToMatrix,
      "ScopedTransformCompositeRender",
      layer::DrawCommandType::ScopedTransformCompositeRender, "DrawCircle",
      layer::DrawCommandType::Circle, "DrawRectangle",
      layer::DrawCommandType::Rectangle, "DrawRectanglePro",
      layer::DrawCommandType::RectanglePro, "DrawRectangleLinesPro",
      layer::DrawCommandType::RectangleLinesPro, "DrawLine",
      layer::DrawCommandType::Line, "DrawDashedLine",
      layer::DrawCommandType::DashedLine, "DrawText",
      layer::DrawCommandType::Text,

      "DrawTextCentered", layer::DrawCommandType::DrawTextCentered, "TextPro",
      layer::DrawCommandType::TextPro, "DrawImage",
      layer::DrawCommandType::DrawImage, "TexturePro",
      layer::DrawCommandType::TexturePro, "DrawEntityAnimation",
      layer::DrawCommandType::DrawEntityAnimation,
      "DrawTransformEntityAnimation",
      layer::DrawCommandType::DrawTransformEntityAnimation,
      "DrawTransformEntityAnimationPipeline",
      layer::DrawCommandType::DrawTransformEntityAnimationPipeline, "SetShader",
      layer::DrawCommandType::SetShader, "ResetShader",
      layer::DrawCommandType::ResetShader, "SetBlendMode",
      layer::DrawCommandType::SetBlendMode, "UnsetBlendMode",
      layer::DrawCommandType::UnsetBlendMode, "SendUniformFloat",
      layer::DrawCommandType::SendUniformFloat, "SendUniformInt",
      layer::DrawCommandType::SendUniformInt, "SendUniformVec2",
      layer::DrawCommandType::SendUniformVec2, "SendUniformVec3",
      layer::DrawCommandType::SendUniformVec3, "SendUniformVec4",
      layer::DrawCommandType::SendUniformVec4, "SendUniformFloatArray",
      layer::DrawCommandType::SendUniformFloatArray, "SendUniformIntArray",
      layer::DrawCommandType::SendUniformIntArray, "Vertex",
      layer::DrawCommandType::Vertex, "BeginOpenGLMode",
      layer::DrawCommandType::BeginOpenGLMode, "EndOpenGLMode",
      layer::DrawCommandType::EndOpenGLMode, "SetColor",
      layer::DrawCommandType::SetColor, "SetLineWidth",
      layer::DrawCommandType::SetLineWidth, "SetTexture",
      layer::DrawCommandType::SetTexture, "RenderRectVerticesFilledLayer",
      layer::DrawCommandType::RenderRectVerticesFilledLayer,
      "RenderRectVerticesOutlineLayer",
      layer::DrawCommandType::RenderRectVerticlesOutlineLayer, "DrawPolygon",
      layer::DrawCommandType::Polygon, "RenderNPatchRect",
      layer::DrawCommandType::RenderNPatchRect, "DrawTriangle",
      layer::DrawCommandType::Triangle, "DrawGradientRectCentered",
      layer::DrawCommandType::DrawGradientRectCentered,
      "DrawGradientRectRoundedCentered",
      layer::DrawCommandType::DrawGradientRectRoundedCentered);

  // 1b) EmmyLua docs via BindingRecorder
  rec.add_type("layer.DrawCommandType").doc =
      "Drawing instruction types used by Layer system";

  rec.record_property("layer.DrawCommandType",
                      {"BeginDrawing", "0", "Start drawing a layer frame"});
  rec.record_property("layer.DrawCommandType",
                      {"EndDrawing", "1", "End drawing a layer frame"});
  rec.record_property("layer.DrawCommandType",
                      {"ClearBackground", "2", "Clear background with color"});
  rec.record_property("layer.DrawCommandType",
                      {"Translate", "3", "Translate coordinate system"});
  rec.record_property("layer.DrawCommandType",
                      {"Scale", "4", "Scale coordinate system"});
  rec.record_property("layer.DrawCommandType",
                      {"Rotate", "5", "Rotate coordinate system"});
  rec.record_property("layer.DrawCommandType",
                      {"AddPush", "6", "Push transform matrix"});
  rec.record_property("layer.DrawCommandType",
                      {"AddPop", "7", "Pop transform matrix"});
  rec.record_property("layer.DrawCommandType",
                      {"PushMatrix", "8", "Explicit push matrix command"});
  rec.record_property("layer.DrawCommandType",
                      {"PushObjectTransformsToMatrix", "100",
                       "Push object's transform to matrix stack"});
  rec.record_property("layer.DrawCommandType",
                      {"ScopedTransformCompositeRender", "101",
                       "Scoped transform for composite rendering"});
  rec.record_property("layer.DrawCommandType",
                      {"PopMatrix", "9", "Explicit pop matrix command"});
  rec.record_property("layer.DrawCommandType",
                      {"DrawCircle", "10", "Draw a filled circle"});
  rec.record_property("layer.DrawCommandType",
                      {"DrawRectangle", "11", "Draw a filled rectangle"});
  rec.record_property(
      "layer.DrawCommandType",
      {"DrawRectanglePro", "12", "Draw a scaled and rotated rectangle"});
  rec.record_property("layer.DrawCommandType", {"DrawRectangleLinesPro", "13",
                                                "Draw rectangle outline"});
  rec.record_property("layer.DrawCommandType",
                      {"DrawLine", "14", "Draw a line"});
  rec.record_property("layer.DrawCommandType",
                      {"DrawDashedLine", "15", "Draw a dashed line"});
  rec.record_property("layer.DrawCommandType",
                      {"DrawText", "16", "Draw plain text"});
  rec.record_property("layer.DrawCommandType",
                      {"DrawTextCentered", "17", "Draw text centered"});
  rec.record_property("layer.DrawCommandType",
                      {"TextPro", "18", "Draw stylized/proportional text"});
  rec.record_property("layer.DrawCommandType",
                      {"DrawImage", "19", "Draw a texture/image"});
  rec.record_property("layer.DrawCommandType",
                      {"TexturePro", "20", "Draw transformed texture"});
  rec.record_property("layer.DrawCommandType", {"DrawEntityAnimation", "21",
                                                "Draw animation of an entity"});
  rec.record_property(
      "layer.DrawCommandType",
      {"DrawTransformEntityAnimation", "22", "Draw transform-aware animation"});
  rec.record_property("layer.DrawCommandType",
                      {"DrawTransformEntityAnimationPipeline", "23",
                       "Draw pipelined animation with transform"});
  rec.record_property("layer.DrawCommandType",
                      {"SetShader", "24", "Set active shader"});
  rec.record_property("layer.DrawCommandType",
                      {"ResetShader", "25", "Reset to default shader"});
  rec.record_property("layer.DrawCommandType",
                      {"SetBlendMode", "26", "Set blend mode"});
  rec.record_property("layer.DrawCommandType",
                      {"UnsetBlendMode", "27", "Reset blend mode"});
  rec.record_property(
      "layer.DrawCommandType",
      {"SendUniformFloat", "28", "Send float uniform to shader"});
  rec.record_property("layer.DrawCommandType",
                      {"SendUniformInt", "29", "Send int uniform to shader"});
  rec.record_property("layer.DrawCommandType",
                      {"SendUniformVec2", "30", "Send vec2 uniform to shader"});
  rec.record_property("layer.DrawCommandType",
                      {"SendUniformVec3", "31", "Send vec3 uniform to shader"});
  rec.record_property("layer.DrawCommandType",
                      {"SendUniformVec4", "32", "Send vec4 uniform to shader"});
  rec.record_property(
      "layer.DrawCommandType",
      {"SendUniformFloatArray", "33", "Send float array uniform to shader"});
  rec.record_property(
      "layer.DrawCommandType",
      {"SendUniformIntArray", "34", "Send int array uniform to shader"});
  rec.record_property("layer.DrawCommandType",
                      {"Vertex", "35", "Draw raw vertex"});
  rec.record_property("layer.DrawCommandType",
                      {"BeginOpenGLMode", "36", "Begin native OpenGL mode"});
  rec.record_property("layer.DrawCommandType",
                      {"EndOpenGLMode", "37", "End native OpenGL mode"});
  rec.record_property("layer.DrawCommandType",
                      {"SetColor", "38", "Set current draw color"});
  rec.record_property("layer.DrawCommandType",
                      {"SetLineWidth", "39", "Set width of lines"});
  rec.record_property("layer.DrawCommandType",
                      {"SetTexture", "40", "Bind texture to use"});
  rec.record_property("layer.DrawCommandType",
                      {"RenderRectVerticesFilledLayer", "41",
                       "Draw filled rects from vertex list"});
  rec.record_property("layer.DrawCommandType",
                      {"RenderRectVerticesOutlineLayer", "42",
                       "Draw outlined rects from vertex list"});
  rec.record_property("layer.DrawCommandType",
                      {"DrawPolygon", "43", "Draw a polygon"});
  rec.record_property("layer.DrawCommandType",
                      {"RenderNPatchRect", "44", "Draw a 9-patch rectangle"});
  rec.record_property("layer.DrawCommandType",
                      {"DrawTriangle", "45", "Draw a triangle"});
  rec.record_property(
      "layer.DrawCommandType",
      {"DrawGradientRectCentered", "46", "Draw a gradient rectangle centered"});
  rec.record_property("layer.DrawCommandType",
                      {"DrawGradientRectRoundedCentered", "47",
                       "Draw a rounded gradient rectangle centered"});

// Helper macro to reduce boilerplate
#define BIND_CMD(name, ...)                                                    \
  layerTbl.new_usertype<layer::Cmd##name>(                                     \
      "Cmd" #name, sol::constructors<>(), __VA_ARGS__, "type_id",              \
      []() { return entt::type_hash<layer::Cmd##name>::value(); });

  // 2) Register every Cmd* struct:
  BIND_CMD(BeginDrawing, "dummy", &layer::CmdBeginDrawing::dummy)
  BIND_CMD(EndDrawing, "dummy", &layer::CmdEndDrawing::dummy)
  BIND_CMD(ClearBackground, "color", &layer::CmdClearBackground::color)
  BIND_CMD(Translate, "x", &layer::CmdTranslate::x, "y",
           &layer::CmdTranslate::y)
  BIND_CMD(Scale, "scaleX", &layer::CmdScale::scaleX, "scaleY",
           &layer::CmdScale::scaleY)
  BIND_CMD(BeginScissorMode, "area", &layer::CmdBeginScissorMode::area)
  BIND_CMD(EndScissorMode, "dummy", &layer::CmdEndScissorMode::dummy)
  BIND_CMD(Rotate, "angle", &layer::CmdRotate::angle)
  BIND_CMD(AddPush, "camera", &layer::CmdAddPush::camera)
  BIND_CMD(AddPop, "dummy", &layer::CmdAddPop::dummy)
  BIND_CMD(PushMatrix, "dummy", &layer::CmdPushMatrix::dummy)
  BIND_CMD(PopMatrix, "dummy", &layer::CmdPopMatrix::dummy)
  BIND_CMD(PushObjectTransformsToMatrix, "entity",
           &layer::CmdPushObjectTransformsToMatrix::entity)
  BIND_CMD(ScopedTransformCompositeRender, "entity",
           &layer::CmdScopedTransformCompositeRender::entity, "payload",
           &layer::CmdScopedTransformCompositeRender::children)
  BIND_CMD(DrawCircleFilled, "x", &layer::CmdDrawCircleFilled::x, "y",
           &layer::CmdDrawCircleFilled::y, "radius",
           &layer::CmdDrawCircleFilled::radius, "color",
           &layer::CmdDrawCircleFilled::color)
  BIND_CMD(DrawCircleLine, "x", &layer::CmdDrawCircleLine::x, "y",
           &layer::CmdDrawCircleLine::y, "innerRadius",
           &layer::CmdDrawCircleLine::innerRadius, "outerRadius",
           &layer::CmdDrawCircleLine::outerRadius, "startAngle",
           &layer::CmdDrawCircleLine::startAngle, "endAngle",
           &layer::CmdDrawCircleLine::endAngle, "segments",
           &layer::CmdDrawCircleLine::segments, "color",
           &layer::CmdDrawCircleLine::color)
  BIND_CMD(DrawRectangle, "x", &layer::CmdDrawRectangle::x, "y",
           &layer::CmdDrawRectangle::y, "width",
           &layer::CmdDrawRectangle::width, "height",
           &layer::CmdDrawRectangle::height, "color",
           &layer::CmdDrawRectangle::color, "lineWidth",
           &layer::CmdDrawRectangle::lineWidth)
  BIND_CMD(DrawRectanglePro, "offsetX", &layer::CmdDrawRectanglePro::offsetX,
           "offsetY", &layer::CmdDrawRectanglePro::offsetY, "size",
           &layer::CmdDrawRectanglePro::size, "rotationCenter",
           &layer::CmdDrawRectanglePro::rotationCenter, "rotation",
           &layer::CmdDrawRectanglePro::rotation, "color",
           &layer::CmdDrawRectanglePro::color)
  BIND_CMD(DrawRectangleLinesPro, "offsetX",
           &layer::CmdDrawRectangleLinesPro::offsetX, "offsetY",
           &layer::CmdDrawRectangleLinesPro::offsetY, "size",
           &layer::CmdDrawRectangleLinesPro::size, "lineThickness",
           &layer::CmdDrawRectangleLinesPro::lineThickness, "color",
           &layer::CmdDrawRectangleLinesPro::color)
  BIND_CMD(DrawLine, "x1", &layer::CmdDrawLine::x1, "y1",
           &layer::CmdDrawLine::y1, "x2", &layer::CmdDrawLine::x2, "y2",
           &layer::CmdDrawLine::y2, "color", &layer::CmdDrawLine::color,
           "lineWidth", &layer::CmdDrawLine::lineWidth)
  BIND_CMD(DrawText, "text", &layer::CmdDrawText::text, "font",
           &layer::CmdDrawText::font, "x", &layer::CmdDrawText::x, "y",
           &layer::CmdDrawText::y, "color", &layer::CmdDrawText::color,
           "fontSize", &layer::CmdDrawText::fontSize)
  BIND_CMD(DrawTextCentered, "text", &layer::CmdDrawTextCentered::text, "font",
           &layer::CmdDrawTextCentered::font, "x",
           &layer::CmdDrawTextCentered::x, "y", &layer::CmdDrawTextCentered::y,
           "color", &layer::CmdDrawTextCentered::color, "fontSize",
           &layer::CmdDrawTextCentered::fontSize)
  BIND_CMD(TextPro, "text", &layer::CmdTextPro::text, "font",
           &layer::CmdTextPro::font, "x", &layer::CmdTextPro::x, "y",
           &layer::CmdTextPro::y, "origin", &layer::CmdTextPro::origin,
           "rotation", &layer::CmdTextPro::rotation, "fontSize",
           &layer::CmdTextPro::fontSize, "spacing", &layer::CmdTextPro::spacing,
           "color", &layer::CmdTextPro::color)
  BIND_CMD(DrawImage, "image", &layer::CmdDrawImage::image, "x",
           &layer::CmdDrawImage::x, "y", &layer::CmdDrawImage::y, "rotation",
           &layer::CmdDrawImage::rotation, "scaleX",
           &layer::CmdDrawImage::scaleX, "scaleY", &layer::CmdDrawImage::scaleY,
           "color", &layer::CmdDrawImage::color)
  BIND_CMD(TexturePro, "texture", &layer::CmdTexturePro::texture, "source",
           &layer::CmdTexturePro::source, "offsetX",
           &layer::CmdTexturePro::offsetX, "offsetY",
           &layer::CmdTexturePro::offsetY, "size", &layer::CmdTexturePro::size,
           "rotationCenter", &layer::CmdTexturePro::rotationCenter, "rotation",
           &layer::CmdTexturePro::rotation, "color",
           &layer::CmdTexturePro::color)
  BIND_CMD(DrawEntityAnimation, "e", &layer::CmdDrawEntityAnimation::e,
           "registry", &layer::CmdDrawEntityAnimation::registry, "x",
           &layer::CmdDrawEntityAnimation::x, "y",
           &layer::CmdDrawEntityAnimation::y)
  BIND_CMD(DrawTransformEntityAnimation, "e",
           &layer::CmdDrawTransformEntityAnimation::e, "registry",
           &layer::CmdDrawTransformEntityAnimation::registry)
  BIND_CMD(DrawTransformEntityAnimationPipeline, "e",
           &layer::CmdDrawTransformEntityAnimationPipeline::e, "registry",
           &layer::CmdDrawTransformEntityAnimationPipeline::registry)
  BIND_CMD(SetShader, "shader", &layer::CmdSetShader::shader)
  // instead of BIND_CMD(ResetShader /*no fields*/)
  layerTbl.new_usertype<::layer::CmdResetShader>("CmdResetShader",
                                                 sol::constructors<>());
  BIND_CMD(SetBlendMode, "blendMode", &layer::CmdSetBlendMode::blendMode)
  BIND_CMD(UnsetBlendMode, "dummy", &layer::CmdUnsetBlendMode::dummy)
  BIND_CMD(SendUniformFloat, "shader", &layer::CmdSendUniformFloat::shader,
           "uniform", &layer::CmdSendUniformFloat::uniform, "value",
           &layer::CmdSendUniformFloat::value)
  BIND_CMD(SendUniformInt, "shader", &layer::CmdSendUniformInt::shader,
           "uniform", &layer::CmdSendUniformInt::uniform, "value",
           &layer::CmdSendUniformInt::value)
  BIND_CMD(SendUniformVec2, "shader", &layer::CmdSendUniformVec2::shader,
           "uniform", &layer::CmdSendUniformVec2::uniform, "value",
           &layer::CmdSendUniformVec2::value)
  BIND_CMD(SendUniformVec3, "shader", &layer::CmdSendUniformVec3::shader,
           "uniform", &layer::CmdSendUniformVec3::uniform, "value",
           &layer::CmdSendUniformVec3::value)
  BIND_CMD(SendUniformVec4, "shader", &layer::CmdSendUniformVec4::shader,
           "uniform", &layer::CmdSendUniformVec4::uniform, "value",
           &layer::CmdSendUniformVec4::value)
  BIND_CMD(SendUniformFloatArray, "shader",
           &layer::CmdSendUniformFloatArray::shader, "uniform",
           &layer::CmdSendUniformFloatArray::uniform, "values",
           &layer::CmdSendUniformFloatArray::values)
  BIND_CMD(SendUniformIntArray, "shader",
           &layer::CmdSendUniformIntArray::shader, "uniform",
           &layer::CmdSendUniformIntArray::uniform, "values",
           &layer::CmdSendUniformIntArray::values)
  BIND_CMD(Vertex, "v", &layer::CmdVertex::v, "color", &layer::CmdVertex::color)
  BIND_CMD(BeginOpenGLMode, "mode", &layer::CmdBeginOpenGLMode::mode)
  BIND_CMD(EndOpenGLMode, "dummy", &layer::CmdEndOpenGLMode::dummy)
  BIND_CMD(SetColor, "color", &layer::CmdSetColor::color)
  BIND_CMD(SetLineWidth, "lineWidth", &layer::CmdSetLineWidth::lineWidth)
  BIND_CMD(SetTexture, "texture", &layer::CmdSetTexture::texture)
  BIND_CMD(RenderRectVerticesFilledLayer, "outerRec",
           &layer::CmdRenderRectVerticesFilledLayer::outerRec,
           "progressOrFullBackground",
           &layer::CmdRenderRectVerticesFilledLayer::progressOrFullBackground,
           "cache", &layer::CmdRenderRectVerticesFilledLayer::cache, "color",
           &layer::CmdRenderRectVerticesFilledLayer::color)
  BIND_CMD(RenderRectVerticesOutlineLayer, "cache",
           &layer::CmdRenderRectVerticesOutlineLayer::cache, "color",
           &layer::CmdRenderRectVerticesOutlineLayer::color, "useFullVertices",
           &layer::CmdRenderRectVerticesOutlineLayer::useFullVertices)
  BIND_CMD(DrawPolygon, "vertices", &layer::CmdDrawPolygon::vertices, "color",
           &layer::CmdDrawPolygon::color, "lineWidth",
           &layer::CmdDrawPolygon::lineWidth)
  BIND_CMD(RenderNPatchRect, "sourceTexture",
           &layer::CmdRenderNPatchRect::sourceTexture, "info",
           &layer::CmdRenderNPatchRect::info, "dest",
           &layer::CmdRenderNPatchRect::dest, "origin",
           &layer::CmdRenderNPatchRect::origin, "rotation",
           &layer::CmdRenderNPatchRect::rotation, "tint",
           &layer::CmdRenderNPatchRect::tint)
  BIND_CMD(DrawTriangle, "p1", &layer::CmdDrawTriangle::p1, "p2",
           &layer::CmdDrawTriangle::p2, "p3", &layer::CmdDrawTriangle::p3,
           "color", &layer::CmdDrawTriangle::color)
  BIND_CMD(BeginStencilMode, "dummy", &layer::CmdBeginStencilMode::dummy)
  BIND_CMD(StencilOp, "sfail", &layer::CmdStencilOp::sfail, "dpfail",
           &layer::CmdStencilOp::dpfail, "dppass", &layer::CmdStencilOp::dppass)
  BIND_CMD(RenderBatchFlush, "dummy", &layer::CmdRenderBatchFlush::dummy)
  BIND_CMD(AtomicStencilMask, "mask", &layer::CmdAtomicStencilMask::mask)
  BIND_CMD(ColorMask, "r", &layer::CmdColorMask::red, "g",
           &layer::CmdColorMask::green, "b", &layer::CmdColorMask::blue, "a",
           &layer::CmdColorMask::alpha)
  BIND_CMD(StencilFunc, "func", &layer::CmdStencilFunc::func, "ref",
           &layer::CmdStencilFunc::ref, "mask", &layer::CmdStencilFunc::mask)
  BIND_CMD(EndStencilMode, "dummy", &layer::CmdEndStencilMode::dummy)
  BIND_CMD(ClearStencilBuffer, "dummy", &layer::CmdClearStencilBuffer::dummy)
  BIND_CMD(BeginStencilMask, "dummy", &layer::CmdBeginStencilMask::dummy)
  BIND_CMD(EndStencilMask, "dummy", &layer::CmdEndStencilMask::dummy)
  BIND_CMD(DrawCenteredEllipse, "x", &layer::CmdDrawCenteredEllipse::x, "y",
           &layer::CmdDrawCenteredEllipse::y, "rx",
           &layer::CmdDrawCenteredEllipse::rx, "ry",
           &layer::CmdDrawCenteredEllipse::ry, "color",
           &layer::CmdDrawCenteredEllipse::color, "lineWidth",
           &layer::CmdDrawCenteredEllipse::lineWidth)
  BIND_CMD(DrawRoundedLine, "x1", &layer::CmdDrawRoundedLine::x1, "y1",
           &layer::CmdDrawRoundedLine::y1, "x2", &layer::CmdDrawRoundedLine::x2,
           "y2", &layer::CmdDrawRoundedLine::y2, "color",
           &layer::CmdDrawRoundedLine::color, "lineWidth",
           &layer::CmdDrawRoundedLine::lineWidth)
  BIND_CMD(DrawPolyline, "points", &layer::CmdDrawPolyline::points, "color",
           &layer::CmdDrawPolyline::color, "lineWidth",
           &layer::CmdDrawPolyline::lineWidth)
  BIND_CMD(DrawArc, "type", &layer::CmdDrawArc::type, "x",
           &layer::CmdDrawArc::x, "y", &layer::CmdDrawArc::y, "r",
           &layer::CmdDrawArc::r, "r1", &layer::CmdDrawArc::r1, "r2",
           &layer::CmdDrawArc::r2, "color", &layer::CmdDrawArc::color,
           "lineWidth", &layer::CmdDrawArc::lineWidth, "segments",
           &layer::CmdDrawArc::segments)
  BIND_CMD(DrawTriangleEquilateral, "x", &layer::CmdDrawTriangleEquilateral::x,
           "y", &layer::CmdDrawTriangleEquilateral::y, "w",
           &layer::CmdDrawTriangleEquilateral::w, "color",
           &layer::CmdDrawTriangleEquilateral::color, "lineWidth",
           &layer::CmdDrawTriangleEquilateral::lineWidth)
  BIND_CMD(DrawCenteredFilledRoundedRect, "x",
           &layer::CmdDrawCenteredFilledRoundedRect::x, "y",
           &layer::CmdDrawCenteredFilledRoundedRect::y, "w",
           &layer::CmdDrawCenteredFilledRoundedRect::w, "h",
           &layer::CmdDrawCenteredFilledRoundedRect::h, "rx",
           &layer::CmdDrawCenteredFilledRoundedRect::rx, "ry",
           &layer::CmdDrawCenteredFilledRoundedRect::ry, "color",
           &layer::CmdDrawCenteredFilledRoundedRect::color, "lineWidth",
           &layer::CmdDrawCenteredFilledRoundedRect::lineWidth)
  BIND_CMD(DrawSteppedRoundedRect, "x",
           &layer::CmdDrawSteppedRoundedRect::x, "y",
           &layer::CmdDrawSteppedRoundedRect::y, "w",
           &layer::CmdDrawSteppedRoundedRect::w, "h",
           &layer::CmdDrawSteppedRoundedRect::h, "fillColor",
           &layer::CmdDrawSteppedRoundedRect::fillColor, "borderColor",
           &layer::CmdDrawSteppedRoundedRect::borderColor, "borderWidth",
           &layer::CmdDrawSteppedRoundedRect::borderWidth, "numSteps",
           &layer::CmdDrawSteppedRoundedRect::numSteps)
  BIND_CMD(DrawSpriteCentered, "spriteName",
           &layer::CmdDrawSpriteCentered::spriteName, "x",
           &layer::CmdDrawSpriteCentered::x, "y",
           &layer::CmdDrawSpriteCentered::y, "dstW",
           &layer::CmdDrawSpriteCentered::dstW, "dstH",
           &layer::CmdDrawSpriteCentered::dstH, "tint",
           &layer::CmdDrawSpriteCentered::tint)
  BIND_CMD(DrawSpriteTopLeft, "spriteName",
           &layer::CmdDrawSpriteTopLeft::spriteName, "x",
           &layer::CmdDrawSpriteTopLeft::x, "y",
           &layer::CmdDrawSpriteTopLeft::y, "dstW",
           &layer::CmdDrawSpriteTopLeft::dstW, "dstH",
           &layer::CmdDrawSpriteTopLeft::dstH, "tint",
           &layer::CmdDrawSpriteTopLeft::tint)
  BIND_CMD(DrawDashedCircle, "center", &layer::CmdDrawDashedCircle::center,
           "radius", &layer::CmdDrawDashedCircle::radius, "dashLength",
           &layer::CmdDrawDashedCircle::dashLength, "gapLength",
           &layer::CmdDrawDashedCircle::gapLength, "phase",
           &layer::CmdDrawDashedCircle::phase, "segments",
           &layer::CmdDrawDashedCircle::segments, "thickness",
           &layer::CmdDrawDashedCircle::thickness, "color",
           &layer::CmdDrawDashedCircle::color)
  BIND_CMD(DrawDashedRoundedRect, "rec", &layer::CmdDrawDashedRoundedRect::rec,
           "dashLen", &layer::CmdDrawDashedRoundedRect::dashLen, "gapLen",
           &layer::CmdDrawDashedRoundedRect::gapLen, "phase",
           &layer::CmdDrawDashedRoundedRect::phase, "radius",
           &layer::CmdDrawDashedRoundedRect::radius, "arcSteps",
           &layer::CmdDrawDashedRoundedRect::arcSteps, "thickness",
           &layer::CmdDrawDashedRoundedRect::thickness, "color",
           &layer::CmdDrawDashedRoundedRect::color)
  BIND_CMD(DrawDashedLine, "start", &layer::CmdDrawDashedLine::start,
           "endPoint", &layer::CmdDrawDashedLine::end, "dashLength",
           &layer::CmdDrawDashedLine::dashLength, "gapLength",
           &layer::CmdDrawDashedLine::gapLength, "phase",
           &layer::CmdDrawDashedLine::phase, "thickness",
           &layer::CmdDrawDashedLine::thickness, "color",
           &layer::CmdDrawDashedLine::color)
  BIND_CMD(DrawGradientRectCentered, "cx",
           &layer::CmdDrawGradientRectCentered::cx, "cy",
           &layer::CmdDrawGradientRectCentered::cy, "width",
           &layer::CmdDrawGradientRectCentered::width, "height",
           &layer::CmdDrawGradientRectCentered::height, "topLeft",
           &layer::CmdDrawGradientRectCentered::topLeft, "topRight",
           &layer::CmdDrawGradientRectCentered::topRight, "bottomRight",
           &layer::CmdDrawGradientRectCentered::bottomRight, "bottomLeft",
           &layer::CmdDrawGradientRectCentered::bottomLeft)
  BIND_CMD(DrawGradientRectRoundedCentered, "cx",
           &layer::CmdDrawGradientRectRoundedCentered::cx, "cy",
           &layer::CmdDrawGradientRectRoundedCentered::cy, "width",
           &layer::CmdDrawGradientRectRoundedCentered::width, "height",
           &layer::CmdDrawGradientRectRoundedCentered::height, "roundness",
           &layer::CmdDrawGradientRectRoundedCentered::roundness, "segments",
           &layer::CmdDrawGradientRectRoundedCentered::segments, "topLeft",
           &layer::CmdDrawGradientRectRoundedCentered::topLeft, "topRight",
           &layer::CmdDrawGradientRectRoundedCentered::topRight, "bottomRight",
           &layer::CmdDrawGradientRectRoundedCentered::bottomRight,
           "bottomLeft", &layer::CmdDrawGradientRectRoundedCentered::bottomLeft)
  BIND_CMD(DrawBatchedEntities, "registry",
           &layer::CmdDrawBatchedEntities::registry, "entities",
           &layer::CmdDrawBatchedEntities::entities, "autoOptimize",
           &layer::CmdDrawBatchedEntities::autoOptimize)
  BIND_CMD(DrawRenderGroup, "registry",
           &layer::CmdDrawRenderGroup::registry, "groupName",
           &layer::CmdDrawRenderGroup::groupName, "autoOptimize",
           &layer::CmdDrawRenderGroup::autoOptimize)
#undef BIND_CMD

  rec.add_type("layer.CmdBeginDrawing", true);
  rec.record_property("layer.CmdBeginDrawing",
                      {"dummy", "false", "Unused field"});

  rec.add_type("layer.CmdEndDrawing", true);
  rec.record_property("layer.CmdEndDrawing",
                      {"dummy", "false", "Unused field"});

  rec.add_type("layer.CmdClearBackground", true);
  rec.record_property("layer.CmdClearBackground",
                      {"color", "Color", "Background color"});

  rec.add_type("layer.CmdBeginScissorMode", true);
  rec.record_property("layer.CmdBeginScissorMode",
                      {"area", "Rectangle", "Scissor area rectangle"});
  rec.add_type("layer.CmdEndScissorMode", true);
  rec.record_property("layer.CmdEndScissorMode",
                      {"dummy", "false", "Unused field"});
  rec.add_type("layer.CmdTranslate", true);
  rec.record_property("layer.CmdTranslate", {"x", "number", "X offset"});
  rec.record_property("layer.CmdTranslate", {"y", "number", "Y offset"});
  rec.add_type("layer.CmdRenderBatchFlush", true);

  rec.add_type("layer.CmdStencilOp", true);
  rec.record_property("layer.CmdStencilOp",
                      {"sfail", "number", "Stencil fail action"});

  rec.record_property("layer.CmdStencilOp",
                      {"dpfail", "number", "Depth fail action"});
  rec.record_property("layer.CmdStencilOp",
                      {"dppass", "number", "Depth pass action"});
  rec.add_type("layer.CmdAtomicStencilMask", true);
  rec.record_property("layer.CmdAtomicStencilMask",
                      {"mask", "number", "Stencil mask value"});
  rec.add_type("layer.CmdColorMask", true);
  rec.record_property("layer.CmdColorMask", {"r", "boolean", "Red channel"});
  rec.record_property("layer.CmdColorMask", {"g", "boolean", "Green channel"});
  rec.record_property("layer.CmdColorMask", {"b", "boolean", "Blue channel"});
  rec.record_property("layer.CmdColorMask", {"a", "boolean", "Alpha channel"});
  rec.add_type("layer.CmdStencilFunc", true);
  rec.record_property("layer.CmdStencilFunc",
                      {"func", "number", "Stencil function"});
  rec.record_property("layer.CmdStencilFunc",
                      {"ref", "number", "Reference value"});
  rec.record_property("layer.CmdStencilFunc", {"mask", "number", "Mask value"});
  rec.add_type("layer.CmdBeginStencilMode", true);
  rec.record_property("layer.CmdBeginStencilMode",
                      {"dummy", "false", "Unused field"});
  rec.add_type("layer.CmdEndStencilMode", true);
  rec.record_property("layer.CmdEndStencilMode",
                      {"dummy", "false", "Unused field"});
  rec.add_type("layer.CmdClearStencilBuffer", true);
  rec.record_property("layer.CmdClearStencilBuffer",
                      {"dummy", "false", "Unused field"});
  rec.add_type("layer.CmdBeginStencilMask", true);
  rec.record_property("layer.CmdBeginStencilMask",
                      {"dummy", "false", "Unused field"});
  rec.add_type("layer.CmdEndStencilMask", true);
  rec.record_property("layer.CmdEndStencilMask",
                      {"dummy", "false", "Unused field"});
  rec.add_type("layer.CmdDrawCenteredEllipse", true);
  rec.record_property("layer.CmdDrawCenteredEllipse",
                      {"x", "number", "Center X"});
  rec.record_property("layer.CmdDrawCenteredEllipse",
                      {"y", "number", "Center Y"});
  rec.record_property("layer.CmdDrawCenteredEllipse",
                      {"rx", "number", "Radius X"});
  rec.record_property("layer.CmdDrawCenteredEllipse",
                      {"ry", "number", "Radius Y"});
  rec.record_property("layer.CmdDrawCenteredEllipse",
                      {"color", "Color", "Ellipse color"});
  rec.record_property(
      "layer.CmdDrawCenteredEllipse",
      {"lineWidth", "number|nil", "Line width for outline; nil for filled"});
  rec.add_type("layer.CmdDrawRoundedLine", true);
  rec.record_property("layer.CmdDrawRoundedLine", {"x1", "number", "Start X"});
  rec.record_property("layer.CmdDrawRoundedLine", {"y1", "number", "Start Y"});
  rec.record_property("layer.CmdDrawRoundedLine", {"x2", "number", "End X"});
  rec.record_property("layer.CmdDrawRoundedLine", {"y2", "number", "End Y"});
  rec.record_property("layer.CmdDrawRoundedLine",
                      {"color", "Color", "Line color"});
  rec.record_property("layer.CmdDrawRoundedLine",
                      {"lineWidth", "number", "Line width"});
  rec.add_type("layer.CmdDrawPolyline", true);
  rec.record_property("layer.CmdDrawPolyline",
                      {"points", "Vector2[]", "List of points"});
  rec.record_property("layer.CmdDrawPolyline",
                      {"color", "Color", "Line color"});
  rec.record_property("layer.CmdDrawPolyline",
                      {"lineWidth", "number", "Line width"});
  rec.add_type("layer.CmdDrawArc", true);
  rec.record_property(
      "layer.CmdDrawArc",
      {"type", "string", "Arc type (e.g., 'OPEN', 'CHORD', 'PIE')"});
  rec.record_property("layer.CmdDrawArc", {"x", "number", "Center X"});
  rec.record_property("layer.CmdDrawArc", {"y", "number", "Center Y"});
  rec.record_property("layer.CmdDrawArc", {"r", "number", "Radius"});
  rec.record_property("layer.CmdDrawArc",
                      {"r1", "number", "Inner radius (for ring arcs)"});
  rec.record_property("layer.CmdDrawArc",
                      {"r2", "number", "Outer radius (for ring arcs)"});
  rec.record_property("layer.CmdDrawArc", {"color", "Color", "Arc color"});
  rec.record_property("layer.CmdDrawArc",
                      {"lineWidth", "number", "Line width"});
  rec.record_property("layer.CmdDrawArc",
                      {"segments", "number", "Number of segments"});
  rec.add_type("layer.CmdDrawTriangleEquilateral", true);
  rec.record_property("layer.CmdDrawTriangleEquilateral",
                      {"x", "number", "Center X"});
  rec.record_property("layer.CmdDrawTriangleEquilateral",
                      {"y", "number", "Center Y"});
  rec.record_property("layer.CmdDrawTriangleEquilateral",
                      {"w", "number", "Width of the triangle"});
  rec.record_property("layer.CmdDrawTriangleEquilateral",
                      {"color", "Color", "Triangle color"});
  rec.record_property(
      "layer.CmdDrawTriangleEquilateral",
      {"lineWidth", "number|nil", "Line width for outline; nil for filled"});
  rec.add_type("layer.CmdDrawCenteredFilledRoundedRect", true);
  rec.record_property("layer.CmdDrawCenteredFilledRoundedRect",
                      {"x", "number", "Center X"});
  rec.record_property("layer.CmdDrawCenteredFilledRoundedRect",
                      {"y", "number", "Center Y"});
  rec.record_property("layer.CmdDrawCenteredFilledRoundedRect",
                      {"w", "number", "Width"});
  rec.record_property("layer.CmdDrawCenteredFilledRoundedRect",
                      {"h", "number", "Height"});
  rec.record_property("layer.CmdDrawCenteredFilledRoundedRect",
                      {"rx", "number|nil", "Corner radius X; nil for default"});
  rec.record_property("layer.CmdDrawCenteredFilledRoundedRect",
                      {"ry", "number|nil", "Corner radius Y; nil for default"});
  rec.record_property("layer.CmdDrawCenteredFilledRoundedRect",
                      {"color", "Color", "Fill color"});
  rec.record_property(
      "layer.CmdDrawCenteredFilledRoundedRect",
      {"lineWidth", "number|nil", "Line width for outline; nil for filled"});
  rec.add_type("layer.CmdDrawSteppedRoundedRect", true);
  rec.record_property("layer.CmdDrawSteppedRoundedRect",
                      {"x", "number", "Center X"});
  rec.record_property("layer.CmdDrawSteppedRoundedRect",
                      {"y", "number", "Center Y"});
  rec.record_property("layer.CmdDrawSteppedRoundedRect",
                      {"w", "number", "Width"});
  rec.record_property("layer.CmdDrawSteppedRoundedRect",
                      {"h", "number", "Height"});
  rec.record_property("layer.CmdDrawSteppedRoundedRect",
                      {"fillColor", "Color", "Fill color"});
  rec.record_property("layer.CmdDrawSteppedRoundedRect",
                      {"borderColor", "Color", "Border color"});
  rec.record_property("layer.CmdDrawSteppedRoundedRect",
                      {"borderWidth", "number", "Border thickness"});
  rec.record_property("layer.CmdDrawSteppedRoundedRect",
                      {"numSteps", "number", "Steps per corner (default 4)"});
  rec.add_type("layer.CmdDrawSpriteCentered", true);
  rec.record_property("layer.CmdDrawSpriteCentered",
                      {"spriteName", "string", "Name of the sprite"});
  rec.record_property("layer.CmdDrawSpriteCentered",
                      {"x", "number", "Center X"});
  rec.record_property("layer.CmdDrawSpriteCentered",
                      {"y", "number", "Center Y"});
  rec.record_property(
      "layer.CmdDrawSpriteCentered",
      {"dstW", "number|nil", "Destination width; nil for original width"});
  rec.record_property(
      "layer.CmdDrawSpriteCentered",
      {"dstH", "number|nil", "Destination height; nil for original height"});
  rec.record_property("layer.CmdDrawSpriteCentered",
                      {"tint", "Color", "Tint color"});
  rec.add_type("layer.CmdDrawSpriteTopLeft", true);
  rec.record_property("layer.CmdDrawSpriteTopLeft",
                      {"spriteName", "string", "Name of the sprite"});
  rec.record_property("layer.CmdDrawSpriteTopLeft",
                      {"x", "number", "Top-left X"});
  rec.record_property("layer.CmdDrawSpriteTopLeft",
                      {"y", "number", "Top-left Y"});
  rec.record_property(
      "layer.CmdDrawSpriteTopLeft",
      {"dstW", "number|nil", "Destination width; nil for original width"});
  rec.record_property(
      "layer.CmdDrawSpriteTopLeft",
      {"dstH", "number|nil", "Destination height; nil for original height"});
  rec.record_property("layer.CmdDrawSpriteTopLeft",
                      {"tint", "Color", "Tint color"});
  rec.add_type("layer.CmdDrawDashedCircle", true);
  rec.record_property("layer.CmdDrawDashedCircle",
                      {"center", "Vector2", "Center position"});
  rec.record_property("layer.CmdDrawDashedCircle",
                      {"radius", "number", "Radius"});
  rec.record_property("layer.CmdDrawDashedCircle",
                      {"dashLength", "number", "Length of each dash"});
  rec.record_property("layer.CmdDrawDashedCircle",
                      {"gapLength", "number", "Length of gap between dashes"});
  rec.record_property("layer.CmdDrawDashedCircle",
                      {"phase", "number", "Phase offset for dashes"});
  rec.record_property(
      "layer.CmdDrawDashedCircle",
      {"segments", "number", "Number of segments to approximate the circle"});
  rec.record_property("layer.CmdDrawDashedCircle",
                      {"thickness", "number", "Thickness of the dashes"});
  rec.record_property("layer.CmdDrawDashedCircle",
                      {"color", "Color", "Color of the dashes"});
  rec.add_type("layer.CmdDrawDashedRoundedRect", true);
  rec.record_property("layer.CmdDrawDashedRoundedRect",
                      {"rec", "Rectangle", "Rectangle area"});
  rec.record_property("layer.CmdDrawDashedRoundedRect",
                      {"dashLen", "number", "Length of each dash"});
  rec.record_property("layer.CmdDrawDashedRoundedRect",
                      {"gapLen", "number", "Length of gap between dashes"});
  rec.record_property("layer.CmdDrawDashedRoundedRect",
                      {"phase", "number", "Phase offset for dashes"});
  rec.record_property("layer.CmdDrawDashedRoundedRect",
                      {"radius", "number", "Corner radius"});
  rec.record_property(
      "layer.CmdDrawDashedRoundedRect",
      {"arcSteps", "number", "Number of segments for corner arcs"});
  rec.record_property("layer.CmdDrawDashedRoundedRect",
                      {"thickness", "number", "Thickness of the dashes"});
  rec.record_property("layer.CmdDrawDashedRoundedRect",
                      {"color", "Color", "Color of the dashes"});

  rec.add_type("layer.CmdDrawGradientRectCentered", true);
  rec.record_property("layer.CmdDrawGradientRectCentered",
                      {"cx", "number", "Center X"});
  rec.record_property("layer.CmdDrawGradientRectCentered",
                      {"cy", "number", "Center Y"});
  rec.record_property("layer.CmdDrawGradientRectCentered",
                      {"width", "number", "Width"});
  rec.record_property("layer.CmdDrawGradientRectCentered",
                      {"height", "number", "Height"});
  rec.record_property("layer.CmdDrawGradientRectCentered",
                      {"topLeft", "Color", "Top-left color"});
  rec.record_property("layer.CmdDrawGradientRectCentered",
                      {"topRight", "Color", "Top-right color"});
  rec.record_property("layer.CmdDrawGradientRectCentered",
                      {"bottomRight", "Color", "Bottom-right color"});
  rec.record_property("layer.CmdDrawGradientRectCentered",
                      {"bottomLeft", "Color", "Bottom-left color"});
  rec.add_type("layer.CmdDrawGradientRectRoundedCentered", true);
  rec.record_property("layer.CmdDrawGradientRectRoundedCentered",
                      {"cx", "number", "Center X"});
  rec.record_property("layer.CmdDrawGradientRectRoundedCentered",
                      {"cy", "number", "Center Y"});
  rec.record_property("layer.CmdDrawGradientRectRoundedCentered",
                      {"width", "number", "Width"});
  rec.record_property("layer.CmdDrawGradientRectRoundedCentered",
                      {"height", "number", "Height"});
  rec.record_property("layer.CmdDrawGradientRectRoundedCentered",
                      {"roundness", "number", "Corner roundness"});
  rec.record_property("layer.CmdDrawGradientRectRoundedCentered",
                      {"segments", "number", "Number of segments for corners"});
  rec.record_property("layer.CmdDrawGradientRectRoundedCentered",
                      {"topLeft", "Color", "Top-left color"});
  rec.record_property("layer.CmdDrawGradientRectRoundedCentered",
                      {"topRight", "Color", "Top-right color"});
  rec.record_property("layer.CmdDrawGradientRectRoundedCentered",
                      {"bottomRight", "Color", "Bottom-right color"});
  rec.record_property("layer.CmdDrawGradientRectRoundedCentered",
                      {"bottomLeft", "Color", "Bottom-left color"});
  rec.add_type("layer.CmdDrawBatchedEntities", true);
  rec.record_property("layer.CmdDrawBatchedEntities",
                      {"registry", "Registry", "The entity registry"});
  rec.record_property(
      "layer.CmdDrawBatchedEntities",
      {"entities", "Entity[]", "Array of entities to batch render"});
  rec.record_property(
      "layer.CmdDrawBatchedEntities",
      {"autoOptimize", "boolean",
       "Whether to automatically optimize shader batching (default: true)"});
  rec.add_type("layer.CmdDrawDashedLine", true);
  rec.record_property("layer.CmdDrawDashedLine",
                      {"start", "Vector2", "Start position"});
  rec.record_property("layer.CmdDrawDashedLine",
                      {"endPoint", "Vector2", "End position"});
  rec.record_property("layer.CmdDrawDashedLine",
                      {"dashLength", "number", "Length of each dash"});
  rec.record_property("layer.CmdDrawDashedLine",
                      {"gapLength", "number", "Length of gap between dashes"});
  rec.record_property("layer.CmdDrawDashedLine",
                      {"phase", "number", "Phase offset for dashes"});
  rec.record_property("layer.CmdDrawDashedLine",
                      {"thickness", "number", "Thickness of the dashes"});
  rec.record_property("layer.CmdDrawDashedLine",
                      {"color", "Color", "Color of the dashes"});

  rec.add_type("layer.CmdScale", true);
  rec.record_property("layer.CmdScale", {"scaleX", "number", "Scale in X"});
  rec.record_property("layer.CmdScale", {"scaleY", "number", "Scale in Y"});

  rec.add_type("layer.CmdRotate", true);
  rec.record_property("layer.CmdRotate",
                      {"angle", "number", "Rotation angle in degrees"});

  rec.add_type("layer.CmdAddPush", true);
  rec.record_property("layer.CmdAddPush",
                      {"camera", "table", "Camera parameters"});

  rec.add_type("layer.CmdAddPop", true);
  rec.record_property("layer.CmdAddPop", {"dummy", "false", "Unused field"});

  rec.add_type("layer.CmdPushMatrix", true);
  rec.record_property("layer.CmdPushMatrix",
                      {"dummy", "false", "Unused field"});

  rec.add_type("layer.CmdPushObjectTransformsToMatrix", true);
  rec.record_property("layer.CmdPushObjectTransformsToMatrix",
                      {"entity", "Entity", "Entity to get transforms from"});

  rec.add_type("layer.CmdScopedTransformCompositeRender", true);
  rec.record_property("layer.CmdScopedTransformCompositeRender",
                      {"entity", "Entity", "Entity to get transforms from"});
  rec.record_property("layer.CmdScopedTransformCompositeRender",
                      {"payload", "vector", "Additional payload data"});

  rec.add_type("layer.CmdPopMatrix", true);
  rec.record_property("layer.CmdPopMatrix", {"dummy", "false", "Unused field"});

  rec.add_type("layer.CmdDrawCircleFilled", true);
  rec.record_property("layer.CmdDrawCircleFilled", {"x", "number", "Center X"});
  rec.record_property("layer.CmdDrawCircleFilled", {"y", "number", "Center Y"});
  rec.record_property("layer.CmdDrawCircleFilled",
                      {"radius", "number", "Radius"});
  rec.record_property("layer.CmdDrawCircleFilled",
                      {"color", "Color", "Fill color"});

  rec.add_type("layer.CmdDrawCircleLine", true);
  rec.record_property("layer.CmdDrawCircleLine", {"x", "number", "Center X"});
  rec.record_property("layer.CmdDrawCircleLine", {"y", "number", "Center Y"});
  rec.record_property("layer.CmdDrawCircleLine",
                      {"innerRadius", "number", "Inner radius"});
  rec.record_property("layer.CmdDrawCircleLine",
                      {"outerRadius", "number", "Outer radius"});
  rec.record_property("layer.CmdDrawCircleLine",
                      {"startAngle", "number", "Start angle in degrees"});
  rec.record_property("layer.CmdDrawCircleLine",
                      {"endAngle", "number", "End angle in degrees"});
  rec.record_property("layer.CmdDrawCircleLine",
                      {"segments", "number", "Number of segments"});
  rec.record_property("layer.CmdDrawCircleLine",
                      {"color", "Color", "Line color"});

  rec.add_type("layer.CmdDrawRectangle", true);
  rec.record_property("layer.CmdDrawRectangle", {"x", "number", "Top-left X"});
  rec.record_property("layer.CmdDrawRectangle", {"y", "number", "Top-left Y"});
  rec.record_property("layer.CmdDrawRectangle", {"width", "number", "Width"});
  rec.record_property("layer.CmdDrawRectangle", {"height", "number", "Height"});
  rec.record_property("layer.CmdDrawRectangle",
                      {"color", "Color", "Fill color"});
  rec.record_property("layer.CmdDrawRectangle",
                      {"lineWidth", "number", "Line width"});

  rec.add_type("layer.CmdDrawRectanglePro", true);
  rec.record_property("layer.CmdDrawRectanglePro",
                      {"offsetX", "number", "Offset X"});
  rec.record_property("layer.CmdDrawRectanglePro",
                      {"offsetY", "number", "Offset Y"});
  rec.record_property("layer.CmdDrawRectanglePro", {"size", "Vector2", "Size"});
  rec.record_property("layer.CmdDrawRectanglePro",
                      {"rotationCenter", "Vector2", "Rotation center"});
  rec.record_property("layer.CmdDrawRectanglePro",
                      {"rotation", "number", "Rotation"});
  rec.record_property("layer.CmdDrawRectanglePro", {"color", "Color", "Color"});

  rec.add_type("layer.CmdDrawRectangleLinesPro", true);
  rec.record_property("layer.CmdDrawRectangleLinesPro",
                      {"offsetX", "number", "Offset X"});
  rec.record_property("layer.CmdDrawRectangleLinesPro",
                      {"offsetY", "number", "Offset Y"});
  rec.record_property("layer.CmdDrawRectangleLinesPro",
                      {"size", "Vector2", "Size"});
  rec.record_property("layer.CmdDrawRectangleLinesPro",
                      {"lineThickness", "number", "Line thickness"});
  rec.record_property("layer.CmdDrawRectangleLinesPro",
                      {"color", "Color", "Color"});

  rec.add_type("layer.CmdDrawLine", true);
  rec.record_property("layer.CmdDrawLine", {"x1", "number", "Start X"});
  rec.record_property("layer.CmdDrawLine", {"y1", "number", "Start Y"});
  rec.record_property("layer.CmdDrawLine", {"x2", "number", "End X"});
  rec.record_property("layer.CmdDrawLine", {"y2", "number", "End Y"});
  rec.record_property("layer.CmdDrawLine", {"color", "Color", "Line color"});
  rec.record_property("layer.CmdDrawLine",
                      {"lineWidth", "number", "Line width"});

  rec.add_type("layer.CmdDrawDashedLine", true);
  rec.record_property("layer.CmdDrawDashedLine", {"x1", "number", "Start X"});
  rec.record_property("layer.CmdDrawDashedLine", {"y1", "number", "Start Y"});
  rec.record_property("layer.CmdDrawDashedLine", {"x2", "number", "End X"});
  rec.record_property("layer.CmdDrawDashedLine", {"y2", "number", "End Y"});
  rec.record_property("layer.CmdDrawDashedLine",
                      {"dashSize", "number", "Dash size"});
  rec.record_property("layer.CmdDrawDashedLine",
                      {"gapSize", "number", "Gap size"});
  rec.record_property("layer.CmdDrawDashedLine", {"color", "Color", "Color"});
  rec.record_property("layer.CmdDrawDashedLine",
                      {"lineWidth", "number", "Line width"});

  rec.add_type("layer.CmdDrawText", true);
  rec.record_property("layer.CmdDrawText", {"text", "string", "Text"});
  rec.record_property("layer.CmdDrawText", {"font", "Font", "Font"});
  rec.record_property("layer.CmdDrawText", {"x", "number", "X"});
  rec.record_property("layer.CmdDrawText", {"y", "number", "Y"});
  rec.record_property("layer.CmdDrawText", {"color", "Color", "Color"});
  rec.record_property("layer.CmdDrawText", {"fontSize", "number", "Font size"});

  rec.add_type("layer.CmdDrawTextCentered", true);
  rec.record_property("layer.CmdDrawTextCentered", {"text", "string", "Text"});
  rec.record_property("layer.CmdDrawTextCentered", {"font", "Font", "Font"});
  rec.record_property("layer.CmdDrawTextCentered", {"x", "number", "X"});
  rec.record_property("layer.CmdDrawTextCentered", {"y", "number", "Y"});
  rec.record_property("layer.CmdDrawTextCentered", {"color", "Color", "Color"});
  rec.record_property("layer.CmdDrawTextCentered",
                      {"fontSize", "number", "Font size"});

  rec.add_type("layer.CmdTextPro", true);
  rec.record_property("layer.CmdTextPro", {"text", "string", "Text"});
  rec.record_property("layer.CmdTextPro", {"font", "Font", "Font"});
  rec.record_property("layer.CmdTextPro", {"x", "number", "X"});
  rec.record_property("layer.CmdTextPro", {"y", "number", "Y"});
  rec.record_property("layer.CmdTextPro", {"origin", "Vector2", "Origin"});
  rec.record_property("layer.CmdTextPro", {"rotation", "number", "Rotation"});
  rec.record_property("layer.CmdTextPro", {"fontSize", "number", "Font size"});
  rec.record_property("layer.CmdTextPro", {"spacing", "number", "Spacing"});
  rec.record_property("layer.CmdTextPro", {"color", "Color", "Color"});

  rec.add_type("layer.CmdDrawImage", true);
  rec.record_property("layer.CmdDrawImage", {"image", "Texture2D", "Image"});
  rec.record_property("layer.CmdDrawImage", {"x", "number", "X"});
  rec.record_property("layer.CmdDrawImage", {"y", "number", "Y"});
  rec.record_property("layer.CmdDrawImage", {"rotation", "number", "Rotation"});
  rec.record_property("layer.CmdDrawImage", {"scaleX", "number", "Scale X"});
  rec.record_property("layer.CmdDrawImage", {"scaleY", "number", "Scale Y"});
  rec.record_property("layer.CmdDrawImage", {"color", "Color", "Tint color"});

  rec.add_type("layer.CmdTexturePro", true);
  rec.record_property("layer.CmdTexturePro",
                      {"texture", "Texture2D", "Texture"});
  rec.record_property("layer.CmdTexturePro",
                      {"source", "Rectangle", "Source rect"});
  rec.record_property("layer.CmdTexturePro", {"offsetX", "number", "Offset X"});
  rec.record_property("layer.CmdTexturePro", {"offsetY", "number", "Offset Y"});
  rec.record_property("layer.CmdTexturePro", {"size", "Vector2", "Size"});
  rec.record_property("layer.CmdTexturePro",
                      {"rotationCenter", "Vector2", "Rotation center"});
  rec.record_property("layer.CmdTexturePro",
                      {"rotation", "number", "Rotation"});
  rec.record_property("layer.CmdTexturePro", {"color", "Color", "Color"});

  rec.add_type("layer.CmdDrawEntityAnimation", true);
  rec.record_property("layer.CmdDrawEntityAnimation",
                      {"e", "Entity", "entt::entity"});
  rec.record_property("layer.CmdDrawEntityAnimation",
                      {"registry", "Registry", "EnTT registry"});
  rec.record_property("layer.CmdDrawEntityAnimation", {"x", "number", "X"});
  rec.record_property("layer.CmdDrawEntityAnimation", {"y", "number", "Y"});

  rec.add_type("layer.CmdDrawTransformEntityAnimation", true);
  rec.record_property("layer.CmdDrawTransformEntityAnimation",
                      {"e", "Entity", "entt::entity"});
  rec.record_property("layer.CmdDrawTransformEntityAnimation",
                      {"registry", "Registry", "EnTT registry"});

  rec.add_type("layer.CmdDrawTransformEntityAnimationPipeline", true);
  rec.record_property("layer.CmdDrawTransformEntityAnimationPipeline",
                      {"e", "Entity", "entt::entity"});
  rec.record_property("layer.CmdDrawTransformEntityAnimationPipeline",
                      {"registry", "Registry", "EnTT registry"});

  rec.add_type("layer.CmdSetShader", true);
  rec.record_property("layer.CmdSetShader",
                      {"shader", "Shader", "Shader object"});

  rec.add_type("layer.CmdResetShader", true);

  rec.add_type("layer.CmdSetBlendMode", true);
  rec.record_property("layer.CmdSetBlendMode",
                      {"blendMode", "number", "Blend mode"});

  rec.add_type("layer.CmdUnsetBlendMode", true);
  rec.record_property("layer.CmdUnsetBlendMode",
                      {"dummy", "false", "Unused field"});

  rec.add_type("layer.CmdSendUniformFloat", true);
  rec.record_property("layer.CmdSendUniformFloat",
                      {"shader", "Shader", "Shader"});
  rec.record_property("layer.CmdSendUniformFloat",
                      {"uniform", "string", "Uniform name"});
  rec.record_property("layer.CmdSendUniformFloat",
                      {"value", "number", "Float value"});

  rec.add_type("layer.CmdSendUniformInt", true);
  rec.record_property("layer.CmdSendUniformInt",
                      {"shader", "Shader", "Shader"});
  rec.record_property("layer.CmdSendUniformInt",
                      {"uniform", "string", "Uniform name"});
  rec.record_property("layer.CmdSendUniformInt",
                      {"value", "number", "Int value"});

  rec.add_type("layer.CmdSendUniformVec2", true);
  rec.record_property("layer.CmdSendUniformVec2",
                      {"shader", "Shader", "Shader"});
  rec.record_property("layer.CmdSendUniformVec2",
                      {"uniform", "string", "Uniform name"});
  rec.record_property("layer.CmdSendUniformVec2",
                      {"value", "Vector2", "Vec2 value"});

  rec.add_type("layer.CmdSendUniformVec3", true);
  rec.record_property("layer.CmdSendUniformVec3",
                      {"shader", "Shader", "Shader"});
  rec.record_property("layer.CmdSendUniformVec3",
                      {"uniform", "string", "Uniform name"});
  rec.record_property("layer.CmdSendUniformVec3",
                      {"value", "Vector3", "Vec3 value"});

  rec.add_type("layer.CmdSendUniformVec4", true);
  rec.record_property("layer.CmdSendUniformVec4",
                      {"shader", "Shader", "Shader"});
  rec.record_property("layer.CmdSendUniformVec4",
                      {"uniform", "string", "Uniform name"});
  rec.record_property("layer.CmdSendUniformVec4",
                      {"value", "Vector4", "Vec4 value"});

  rec.add_type("layer.CmdSendUniformFloatArray", true);
  rec.record_property("layer.CmdSendUniformFloatArray",
                      {"shader", "Shader", "Shader"});
  rec.record_property("layer.CmdSendUniformFloatArray",
                      {"uniform", "string", "Uniform name"});
  rec.record_property("layer.CmdSendUniformFloatArray",
                      {"values", "table", "Float array"});

  rec.add_type("layer.CmdSendUniformIntArray", true);
  rec.record_property("layer.CmdSendUniformIntArray",
                      {"shader", "Shader", "Shader"});
  rec.record_property("layer.CmdSendUniformIntArray",
                      {"uniform", "string", "Uniform name"});
  rec.record_property("layer.CmdSendUniformIntArray",
                      {"values", "table", "Int array"});

  rec.add_type("layer.CmdVertex", true);
  rec.record_property("layer.CmdVertex", {"v", "Vector3", "Position"});
  rec.record_property("layer.CmdVertex", {"color", "Color", "Vertex color"});

  rec.add_type("layer.CmdBeginOpenGLMode", true);
  rec.record_property("layer.CmdBeginOpenGLMode",
                      {"mode", "number", "GL mode enum"});

  rec.add_type("layer.CmdEndOpenGLMode", true);
  rec.record_property("layer.CmdEndOpenGLMode",
                      {"dummy", "false", "Unused field"});

  rec.add_type("layer.CmdSetColor", true);
  rec.record_property("layer.CmdSetColor", {"color", "Color", "Draw color"});

  rec.add_type("layer.CmdSetLineWidth", true);
  rec.record_property("layer.CmdSetLineWidth",
                      {"lineWidth", "number", "Line width"});

  rec.add_type("layer.CmdSetTexture", true);
  rec.record_property("layer.CmdSetTexture",
                      {"texture", "Texture2D", "Texture to bind"});

  rec.add_type("layer.CmdRenderRectVerticesFilledLayer", true);
  rec.record_property("layer.CmdRenderRectVerticesFilledLayer",
                      {"outerRec", "Rectangle", "Outer rectangle"});
  rec.record_property("layer.CmdRenderRectVerticesFilledLayer",
                      {"progressOrFullBackground", "bool", "Mode"});
  rec.record_property("layer.CmdRenderRectVerticesFilledLayer",
                      {"cache", "table", "Vertex cache"});
  rec.record_property("layer.CmdRenderRectVerticesFilledLayer",
                      {"color", "Color", "Fill color"});

  rec.add_type("layer.CmdRenderRectVerticesOutlineLayer", true);
  rec.record_property("layer.CmdRenderRectVerticesOutlineLayer",
                      {"cache", "table", "Vertex cache"});
  rec.record_property("layer.CmdRenderRectVerticesOutlineLayer",
                      {"color", "Color", "Outline color"});
  rec.record_property("layer.CmdRenderRectVerticesOutlineLayer",
                      {"useFullVertices", "bool", "Use full vertices"});

  rec.add_type("layer.CmdDrawPolygon", true);
  rec.record_property("layer.CmdDrawPolygon",
                      {"vertices", "table", "Vertex array"});
  rec.record_property("layer.CmdDrawPolygon",
                      {"color", "Color", "Polygon color"});
  rec.record_property("layer.CmdDrawPolygon",
                      {"lineWidth", "number", "Line width"});

  rec.add_type("layer.CmdRenderNPatchRect", true);
  rec.record_property("layer.CmdRenderNPatchRect",
                      {"sourceTexture", "Texture2D", "Source texture"});
  rec.record_property("layer.CmdRenderNPatchRect",
                      {"info", "NPatchInfo", "Nine-patch info"});
  rec.record_property("layer.CmdRenderNPatchRect",
                      {"dest", "Rectangle", "Destination"});
  rec.record_property("layer.CmdRenderNPatchRect",
                      {"origin", "Vector2", "Origin"});
  rec.record_property("layer.CmdRenderNPatchRect",
                      {"rotation", "number", "Rotation"});
  rec.record_property("layer.CmdRenderNPatchRect",
                      {"tint", "Color", "Tint color"});

  rec.add_type("layer.CmdDrawTriangle", true);
  rec.record_property("layer.CmdDrawTriangle", {"p1", "Vector2", "Point 1"});
  rec.record_property("layer.CmdDrawTriangle", {"p2", "Vector2", "Point 2"});
  rec.record_property("layer.CmdDrawTriangle", {"p3", "Vector2", "Point 3"});
  rec.record_property("layer.CmdDrawTriangle",
                      {"color", "Color", "Triangle color"});

  // 3) DrawCommandV2
  layerTbl.new_usertype<layer::DrawCommandV2>(
      "DrawCommandV2", sol::constructors<>(), "type",
      &layer::DrawCommandV2::type, "data", &layer::DrawCommandV2::data, "z",
      &layer::DrawCommandV2::z);

  rec.add_type("layer.DrawCommandV2", true).doc =
      "A single draw command with type, data payload, and z-order.";
  rec.record_property("layer.DrawCommandV2",
                      {"type", "number", "The draw command type enum"});
  rec.record_property("layer.DrawCommandV2",
                      {"data", "any", "The actual command data (CmdX struct)"});
  rec.record_property("layer.DrawCommandV2",
                      {"z", "number", "Z-order depth value for sorting"});

  // 2) Create the command_buffer sub‐table
  auto cb = luaView["command_buffer"].get_or_create<sol::table>();
  if (!cb.valid()) {
    cb = lua.create_table();
    layerTbl["command_buffer"] = cb;
  }

  cb.set_function("pushEntityTransformsToMatrix",
                  [](entt::registry &registry, entt::entity e,
                     std::shared_ptr<layer::Layer> layer, int zOrder) {
                    return pushEntityTransformsToMatrix(registry, e, layer.get(),
                                                        zOrder);
                  });

  rec.record_free_function({"command_buffer"},
                           {"pushEntityTransformsToMatrix",
                            "---@param registry Registry\n"
                            "---@param e Entity\n"
                            "---@param layer Layer\n"
                            "---@param zOrder number\n"
                            "---@return void",
                            "Pushes the transform components of an entity onto "
                            "the layer's matrix stack as draw commands."});

  // 1) Make a DrawCommandSpace table
  sol::table drawSpace = layerTbl.create_named(
      "DrawCommandSpace", "World", DrawCommandSpace::World, "Screen",
      DrawCommandSpace::Screen);

  rec.add_type("layer.DrawCommandSpace", true);
  rec.record_property("layer.DrawCommandSpace",
                      {"Screen", "number", "Screen space draw commands"});
  rec.record_property("layer.DrawCommandSpace",
                      {"World", "number", "World space draw commands"});

  // Recorder: Top-level namespace
  rec.add_type("command_buffer");

  // Record the command_buffer queue/execute helpers (they live under the
  // command_buffer table in Lua).
  const std::vector<std::string> commandBufferCmds = {
      "BeginDrawing",
      "EndDrawing",
      "ClearBackground",
      "Translate",
      "Scale",
      "Rotate",
      "AddPush",
      "AddPop",
      "PushMatrix",
      "PopMatrix",
      "PushObjectTransformsToMatrix",
      "ScopedTransformCompositeRender",
      "DrawCircleFilled",
      "DrawCircleLine",
      "DrawRectangle",
      "DrawRectanglePro",
      "DrawRectangleLinesPro",
      "DrawLine",
      "DrawText",
      "DrawTextCentered",
      "TextPro",
      "DrawImage",
      "TexturePro",
      "DrawEntityAnimation",
      "DrawTransformEntityAnimation",
      "DrawTransformEntityAnimationPipeline",
      "SetShader",
      "ResetShader",
      "SetBlendMode",
      "UnsetBlendMode",
      "SendUniformFloat",
      "SendUniformInt",
      "SendUniformVec2",
      "SendUniformVec3",
      "SendUniformVec4",
      "SendUniformFloatArray",
      "SendUniformIntArray",
      "Vertex",
      "BeginOpenGLMode",
      "EndOpenGLMode",
      "SetColor",
      "SetLineWidth",
      "SetTexture",
      "RenderRectVerticesFilledLayer",
      "RenderRectVerticesOutlineLayer",
      "DrawPolygon",
      "RenderNPatchRect",
      "DrawTriangle",
      "BeginStencilMode",
      "StencilOp",
      "RenderBatchFlush",
      "AtomicStencilMask",
      "ColorMask",
      "StencilFunc",
      "EndStencilMode",
      "ClearStencilBuffer",
      "BeginStencilMask",
      "EndStencilMask",
      "DrawCenteredEllipse",
      "DrawRoundedLine",
      "DrawPolyline",
      "DrawArc",
      "DrawTriangleEquilateral",
      "DrawCenteredFilledRoundedRect",
      "DrawSteppedRoundedRect",
      "DrawSpriteCentered",
      "DrawSpriteTopLeft",
      "DrawDashedCircle",
      "DrawDashedRoundedRect",
      "DrawDashedLine",
      "DrawGradientRectCentered",
      "DrawGradientRectRoundedCentered",
      "DrawBatchedEntities"};

  for (const auto &cmd : commandBufferCmds) {
    rec.record_free_function(
        {"command_buffer"},
        {"queue" + cmd,
         "---@param layer Layer\n"
         "---@param init_fn fun(c: layer.Cmd" +
             cmd +
             ")\n"
             "---@param z integer\n"
             "---@param renderSpace? layer.DrawCommandSpace\n"
             "---@return void",
         "Queues layer.Cmd" + cmd +
             " into a layer via command_buffer (World or Screen space).",
         true, false});

    rec.record_free_function({"command_buffer"},
                             {"execute" + cmd,
                              "---@param layer Layer\n"
                              "---@param init_fn fun(c: layer.Cmd" +
                                  cmd +
                                  ")\n"
                                  "---@return void",
                              "Executes layer.Cmd" + cmd +
                                  " immediately (bypasses the command queue).",
                              true, false});
  }

  lua["GL_KEEP"] = GL_KEEP;
  lua["GL_ZERO"] = GL_ZERO;
  lua["GL_REPLACE"] = GL_REPLACE;
  lua["GL_ALWAYS"] = GL_ALWAYS;
  lua["GL_EQUAL"] = GL_EQUAL;
  lua["GL_FALSE"] = GL_FALSE;

  rec.add_type("GL_KEEP").doc = "OpenGL enum GL_KEEP";
  ;
  rec.add_type("GL_ZERO").doc = "OpenGL enum GL_ZERO";
  rec.add_type("GL_REPLACE").doc = "OpenGL enum GL_REPLACE";
  rec.add_type("GL_ALWAYS").doc = "OpenGL enum GL_ALWAYS";
  rec.add_type("GL_EQUAL").doc = "OpenGL enum GL_EQUAL";
  rec.add_type("GL_FALSE").doc = "OpenGL enum GL_FALSE";
// 3) For each CmdXXX, expose a queueXXX helper
//    Pattern: queueCmdName(layer, init_fn, z, space)
// Replace your QUEUE_CMD impl with a guarded one:
#define QUEUE_CMD(cmd)                                                         \
  cb.set_function("queue" #cmd, [](std::shared_ptr<layer::Layer> lyr,          \
                                   sol::function init, int z,                  \
                                   DrawCommandSpace space =                    \
                                       DrawCommandSpace::Screen) {             \
    return ::layer::QueueCommand<::layer::Cmd##cmd>(                           \
        lyr,                                                                   \
        [&](::layer::Cmd##cmd *c) {                                            \
          sol::protected_function pf(init);                                    \
          if (!pf.valid()) {                                                   \
            std::fprintf(stderr, "[queue%s] init is not a function\n", #cmd);  \
            return;                                                            \
          }                                                                    \
          auto result = util::safeLuaCall(pf, std::string("queue") + #cmd, c); \
          if (result.isErr()) {                                                \
            std::fprintf(stderr, "[queue%s] init error: %s\n", #cmd,           \
                         result.error().c_str());                              \
          }                                                                    \
          /* Optional: dump a few fields for sanity */                         \
          /* std::fprintf(stderr, "[queue%s] dashLen=%.2f gap=%.2f r=%.2f      \
             th=%.2f\n", #cmd, c->dashLen, c->gapLen, c->radius,                                       \
             c->thickness); */                                                 \
        },                                                                     \
        z, space);                                                             \
  });

  QUEUE_CMD(BeginDrawing)
  QUEUE_CMD(EndDrawing)
  QUEUE_CMD(ClearBackground)
  QUEUE_CMD(Translate)
  QUEUE_CMD(Scale)
  QUEUE_CMD(Rotate)
  QUEUE_CMD(AddPush)
  QUEUE_CMD(AddPop)
  QUEUE_CMD(PushMatrix)
  QUEUE_CMD(PopMatrix)
  QUEUE_CMD(PushObjectTransformsToMatrix)
  QUEUE_CMD(ScopedTransformCompositeRender)
  QUEUE_CMD(DrawCircleFilled)
  QUEUE_CMD(DrawCircleLine)
  QUEUE_CMD(DrawRectangle)
  QUEUE_CMD(DrawRectanglePro)
  QUEUE_CMD(DrawRectangleLinesPro)
  QUEUE_CMD(DrawLine)
  QUEUE_CMD(DrawText)
  QUEUE_CMD(DrawTextCentered)
  QUEUE_CMD(TextPro)
  QUEUE_CMD(DrawImage)
  QUEUE_CMD(TexturePro)
  QUEUE_CMD(DrawEntityAnimation)
  QUEUE_CMD(DrawTransformEntityAnimation)
  QUEUE_CMD(DrawTransformEntityAnimationPipeline)
  QUEUE_CMD(SetShader)
  QUEUE_CMD(ResetShader)
  QUEUE_CMD(SetBlendMode)
  QUEUE_CMD(UnsetBlendMode)
  QUEUE_CMD(SendUniformFloat)
  QUEUE_CMD(SendUniformInt)
  QUEUE_CMD(SendUniformVec2)
  QUEUE_CMD(SendUniformVec3)
  QUEUE_CMD(SendUniformVec4)
  QUEUE_CMD(SendUniformFloatArray)
  QUEUE_CMD(SendUniformIntArray)
  QUEUE_CMD(Vertex)
  QUEUE_CMD(BeginOpenGLMode)
  QUEUE_CMD(EndOpenGLMode)
  QUEUE_CMD(SetColor)
  QUEUE_CMD(SetLineWidth)
  QUEUE_CMD(SetTexture)
  QUEUE_CMD(RenderRectVerticesFilledLayer)
  QUEUE_CMD(RenderRectVerticesOutlineLayer)
  QUEUE_CMD(DrawPolygon)
  QUEUE_CMD(RenderNPatchRect)
  QUEUE_CMD(DrawTriangle)
  QUEUE_CMD(BeginStencilMode)
  QUEUE_CMD(StencilOp)
  QUEUE_CMD(RenderBatchFlush)
  QUEUE_CMD(AtomicStencilMask)
  QUEUE_CMD(ColorMask)
  QUEUE_CMD(StencilFunc)
  QUEUE_CMD(EndStencilMode)
  QUEUE_CMD(ClearStencilBuffer)
  QUEUE_CMD(BeginStencilMask)
  QUEUE_CMD(EndStencilMask)
  QUEUE_CMD(DrawCenteredEllipse)
  QUEUE_CMD(DrawRoundedLine)
  QUEUE_CMD(DrawPolyline)
  QUEUE_CMD(DrawArc)
  QUEUE_CMD(DrawTriangleEquilateral)
  QUEUE_CMD(DrawCenteredFilledRoundedRect)
  QUEUE_CMD(DrawSteppedRoundedRect)
  QUEUE_CMD(DrawSpriteCentered)
  QUEUE_CMD(DrawSpriteTopLeft)
  QUEUE_CMD(DrawDashedCircle)
  QUEUE_CMD(DrawDashedRoundedRect)
  QUEUE_CMD(DrawDashedLine)
  QUEUE_CMD(DrawGradientRectCentered)
  QUEUE_CMD(DrawGradientRectRoundedCentered)
  QUEUE_CMD(DrawBatchedEntities)
  QUEUE_CMD(DrawRenderGroup)

#undef QUEUE_CMD

  // special case for scoped render. this allows queuing commands that draw to
  // the local space of a specific transform without having to use direct
  // execution.
  cb.set_function(
      "queueScopedTransformCompositeRender",
      [](std::shared_ptr<layer::Layer> lyr, entt::entity e,
         sol::function child_builder, int z,
         DrawCommandSpace space = DrawCommandSpace::World) {
        QueueScopedTransformCompositeRender(lyr, e, z, space, [&]() {
          sol::protected_function pf(child_builder);
          if (pf.valid()) {
            auto r =
                util::safeLuaCall(pf, "queueScopedTransformCompositeRender");
            if (r.isErr()) {
              std::fprintf(stderr,
                           "[queueScopedTransformCompositeRender] "
                           "child_builder error: %s\n",
                           r.error().c_str());
            }
          } else {
            std::fprintf(
                stderr,
                "[queueScopedTransformCompositeRender] invalid function\n");
          }
        });
      });

  // Like queueScopedTransformCompositeRender, but also executes the shader pipeline
  // for the entity's BatchedLocalCommands. Use this for text/shapes that need
  // to render through shader effects (polychrome, holo, dissolve).
  cb.set_function(
      "queueScopedTransformCompositeRenderWithPipeline",
      [](std::shared_ptr<layer::Layer> lyr, entt::registry* registry, entt::entity e,
         sol::function child_builder, int z,
         DrawCommandSpace space = DrawCommandSpace::World) {
        // Queue a command that will execute the shader pipeline
        auto *cmd = layer::layer_command_buffer::Add<
            layer::CmdScopedTransformCompositeRenderWithPipeline>(lyr, z, space);
        cmd->entity = e;
        cmd->registry = registry;
        cmd->children.reserve(8);

        // Populate shader/texture IDs for batching optimization
        layer::layer_command_buffer::PopulateLastCommandIDs<layer::CmdScopedTransformCompositeRenderWithPipeline>(lyr, cmd);

        // Capture any child commands if the builder function is valid
        if (child_builder.valid()) {
          auto *prevList = lyr->commands_ptr;
          lyr->commands_ptr = &cmd->children;
          sol::protected_function pf(child_builder);
          auto r = util::safeLuaCall(pf, "queueScopedTransformCompositeRenderWithPipeline");
          if (r.isErr()) {
            std::fprintf(stderr,
                         "[queueScopedTransformCompositeRenderWithPipeline] "
                         "child_builder error: %s\n",
                         r.error().c_str());
          }
          lyr->commands_ptr = prevList;
        }
      });

  // -----------------------------------------------------------------------------
// Immediate versions (execute immediately instead of queuing)
// -----------------------------------------------------------------------------
// PERF: Execute* functions now take Layer* instead of shared_ptr<Layer>
// to avoid ref-count overhead on every draw command call
#define EXEC_CMD(execFunc, cmdName)                                            \
  cb.set_function("execute" #cmdName, [](std::shared_ptr<layer::Layer> lyr,    \
                                         sol::function init) {                 \
    ::layer::Cmd##cmdName c{};                                                 \
    sol::protected_function pf(init);                                          \
    if (pf.valid()) {                                                          \
      auto r = util::safeLuaCall(pf, std::string("execute") + #cmdName, &c);   \
      if (r.isErr()) {                                                         \
        std::fprintf(stderr, "[execute%s] init error: %s\n", #cmdName,         \
                     r.error().c_str());                                       \
      }                                                                        \
    }                                                                          \
    ::layer::execFunc(lyr.get(), &c);                                          \
  });

  // Circle & primitives
  EXEC_CMD(ExecuteCircle, DrawCircleFilled)
  EXEC_CMD(ExecuteCircleLine, DrawCircleLine)
  EXEC_CMD(ExecuteRectangle, DrawRectangle)
  EXEC_CMD(ExecuteRectanglePro, DrawRectanglePro)
  EXEC_CMD(ExecuteRectangleLinesPro, DrawRectangleLinesPro)
  EXEC_CMD(ExecuteLine, DrawLine)
  EXEC_CMD(ExecuteDashedLine, DrawDashedLine)
  EXEC_CMD(ExecuteText, DrawText)
  EXEC_CMD(ExecuteTextCentered, DrawTextCentered)
  EXEC_CMD(ExecuteTextPro, TextPro)
  EXEC_CMD(ExecuteDrawImage, DrawImage)
  EXEC_CMD(ExecuteTexturePro, TexturePro)
  EXEC_CMD(ExecuteDrawEntityAnimation, DrawEntityAnimation)
  EXEC_CMD(ExecuteDrawTransformEntityAnimation, DrawTransformEntityAnimation)
  EXEC_CMD(ExecuteDrawTransformEntityAnimationPipeline,
           DrawTransformEntityAnimationPipeline)
  EXEC_CMD(ExecuteSetShader, SetShader)
  EXEC_CMD(ExecuteResetShader, ResetShader)
  EXEC_CMD(ExecuteSetBlendMode, SetBlendMode)
  EXEC_CMD(ExecuteUnsetBlendMode, UnsetBlendMode)
  EXEC_CMD(ExecuteSendUniformFloat, SendUniformFloat)
  EXEC_CMD(ExecuteSendUniformInt, SendUniformInt)
  EXEC_CMD(ExecuteSendUniformVec2, SendUniformVec2)
  EXEC_CMD(ExecuteSendUniformVec3, SendUniformVec3)
  EXEC_CMD(ExecuteSendUniformVec4, SendUniformVec4)
  EXEC_CMD(ExecuteSendUniformFloatArray, SendUniformFloatArray)
  EXEC_CMD(ExecuteSendUniformIntArray, SendUniformIntArray)
  EXEC_CMD(ExecuteVertex, Vertex)
  EXEC_CMD(ExecuteBeginOpenGLMode, BeginOpenGLMode)
  EXEC_CMD(ExecuteEndOpenGLMode, EndOpenGLMode)
  EXEC_CMD(ExecuteSetColor, SetColor)
  EXEC_CMD(ExecuteSetLineWidth, SetLineWidth)
  EXEC_CMD(ExecuteSetTexture, SetTexture)
  EXEC_CMD(ExecuteRenderRectVerticesFilledLayer, RenderRectVerticesFilledLayer)
  EXEC_CMD(ExecuteRenderRectVerticesOutlineLayer,
           RenderRectVerticesOutlineLayer)
  EXEC_CMD(ExecutePolygon, DrawPolygon)
  EXEC_CMD(ExecuteRenderNPatchRect, RenderNPatchRect)
  EXEC_CMD(ExecuteTriangle, DrawTriangle)

  // Transform & stencil
  EXEC_CMD(ExecuteTranslate, Translate)
  EXEC_CMD(ExecuteScale, Scale)
  EXEC_CMD(ExecuteRotate, Rotate)
  EXEC_CMD(ExecuteAddPush, AddPush)
  EXEC_CMD(ExecuteAddPop, AddPop)
  EXEC_CMD(ExecutePushMatrix, PushMatrix)
  EXEC_CMD(ExecutePopMatrix, PopMatrix)
  EXEC_CMD(ExecutePushObjectTransformsToMatrix, PushObjectTransformsToMatrix)
  EXEC_CMD(ExecuteScopedTransformCompositeRender,
           ScopedTransformCompositeRender)
  EXEC_CMD(ExecuteClearStencilBuffer, ClearStencilBuffer)
  EXEC_CMD(ExecuteBeginStencilMode, BeginStencilMode)
  EXEC_CMD(ExecuteStencilOp, StencilOp)
  EXEC_CMD(ExecuteRenderBatchFlush, RenderBatchFlush)
  EXEC_CMD(ExecuteAtomicStencilMask, AtomicStencilMask)
  EXEC_CMD(ExecuteColorMask, ColorMask)
  EXEC_CMD(ExecuteStencilFunc, StencilFunc)
  EXEC_CMD(ExecuteEndStencilMode, EndStencilMode)
  EXEC_CMD(ExecuteBeginStencilMask, BeginStencilMask)
  EXEC_CMD(ExecuteEndStencilMask, EndStencilMask)

  // Advanced primitives
  EXEC_CMD(ExecuteDrawCenteredEllipse, DrawCenteredEllipse)
  EXEC_CMD(ExecuteDrawRoundedLine, DrawRoundedLine)
  EXEC_CMD(ExecuteDrawPolyline, DrawPolyline)
  EXEC_CMD(ExecuteDrawArc, DrawArc)
  EXEC_CMD(ExecuteDrawTriangleEquilateral, DrawTriangleEquilateral)
  EXEC_CMD(ExecuteDrawCenteredFilledRoundedRect, DrawCenteredFilledRoundedRect)
  EXEC_CMD(ExecuteDrawSpriteCentered, DrawSpriteCentered)
  EXEC_CMD(ExecuteDrawSpriteTopLeft, DrawSpriteTopLeft)
  EXEC_CMD(ExecuteDrawDashedCircle, DrawDashedCircle)
  EXEC_CMD(ExecuteDrawDashedRoundedRect, DrawDashedRoundedRect)
  EXEC_CMD(ExecuteDrawDashedLine, DrawDashedLine)
  EXEC_CMD(ExecuteDrawGradientRectCentered, DrawGradientRectCentered)
  EXEC_CMD(ExecuteDrawGradientRectRoundedCentered,
           DrawGradientRectRoundedCentered)

#undef EXEC_CMD

  struct CmdBeginStencilMode {
    bool dummy = false; // Placeholder
  };

  struct CmdEndStencilMode {
    bool dummy = false; // Placeholder
  };

  struct CmdClearStencilBuffer {
    bool dummy = false; // Placeholder
  };

  struct CmdBeginStencilMask {
    bool dummy = false; // Placeholder
  };

  struct CmdEndStencilMask {
    bool dummy = false; // Placeholder
  };

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueBeginDrawing",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdBeginDrawing) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdBeginDrawing into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueClearStencilBuffer",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdClearStencilBuffer) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdClearStencilBuffer into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueColorMask",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdColorMask) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdColorMask into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueStencilOp",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdStencilOp) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdStencilOp into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueRenderBatchFlush",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdRenderBatchFlush) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdRenderBatchFlush into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueAtomicStencilMask",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdAtomicStencilMask) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdAtomicStencilMask into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});
  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueStencilFunc",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdStencilFunc) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdStencilFunc into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});
  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueBeginStencilMode",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdBeginStencilMode) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdBeginStencilMode into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueEndStencilMode",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdEndStencilMode) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdEndStencilMode into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueBeginStencilMask",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdBeginStencilMask) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdBeginStencilMask into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueEndStencilMask",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdEndStencilMask) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdEndStencilMask into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawCenteredEllipse",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawCenteredEllipse) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawCenteredEllipse into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawRoundedLine",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawRoundedLine) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawRoundedLine into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});
  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawPolyline",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawPolyline) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawPolyline into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});
  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawArc",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawArc) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawArc into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});
  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawTriangleEquilateral",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawTriangleEquilateral) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawTriangleEquilateral into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});
  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawCenteredFilledRoundedRect",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawCenteredFilledRoundedRect) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawCenteredFilledRoundedRect into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});
  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawSteppedRoundedRect",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawSteppedRoundedRect) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawSteppedRoundedRect into the layer draw list. Draws rounded rectangle with stepped corners matching C++ UI appearance.)",
          .is_static = true,
          .is_overload = false});
  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawSpriteCentered",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawSpriteCentered) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawSpriteCentered into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});
  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawSpriteTopLeft",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawSpriteTopLeft) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawSpriteTopLeft into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});
  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawDashedCircle",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawDashedCircle) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawDashedCircle into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});
  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawDashedRoundedRect",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawDashedRoundedRect) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawDashedRoundedRect into the layer draw list. Executes init    _fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});
  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawDashedLine",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawDashedLine) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawDashedLine into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawGradientRectCentered",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawGradientRectCentered) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawGradientRectCentered into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawGradientRectRoundedCentered",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawGradientRectRoundedCentered) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawGradientRectRoundedCentered into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawBatchedEntities",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawBatchedEntities) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawBatchedEntities into the layer draw list. This command batches multiple entities for optimized shader rendering, avoiding Lua execution during the render phase. The entities vector and registry are captured when queued and executed during rendering with automatic shader batching.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueEndDrawing",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdEndDrawing) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdEndDrawing into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueClearBackground",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdClearBackground) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdClearBackground into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueBeginScissorMode",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdBeginScissorMode) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdBeginScissorMode into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueEndScissorMode",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdEndScissorMode) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdEndScissorMode into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueTranslate",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdTranslate) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdTranslate into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueScale",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdScale) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdScale into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueRotate",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdRotate) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdRotate into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueAddPush",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdAddPush) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdAddPush into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueAddPop",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdAddPop) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdAddPop into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queuePushObjectTransformsToMatrix",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdPushObjectTransformsToMatrix) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdPushObjectTransformsToMatrix into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order. Use with popMatrix())",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueScopedTransformCompositeRender",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdScopedTransformCompositeRender) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdScopedTransformCompositeRender into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order. Use with popMatrix())",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queuePushMatrix",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdPushMatrix) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdPushMatrix into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queuePopMatrix",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdPopMatrix) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdPopMatrix into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawCircle",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawCircleFilled) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawCircleFilled into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawRectangle",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawRectangle) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawRectangle into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawRectanglePro",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawRectanglePro) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawRectanglePro into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawRectangleLinesPro",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawRectangleLinesPro) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawRectangleLinesPro into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawLine",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawLine) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawLine into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawDashedLine",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawDashedLine) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawDashedLine into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawText",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawText) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawText into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawTextCentered",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawTextCentered) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawTextCentered into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueTextPro",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdTextPro) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdTextPro into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawImage",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawImage) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawImage into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueTexturePro",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdTexturePro) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdTexturePro into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawEntityAnimation",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawEntityAnimation) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawEntityAnimation into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawTransformEntityAnimation",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawTransformEntityAnimation) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawTransformEntityAnimation into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawTransformEntityAnimationPipeline",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawTransformEntityAnimationPipeline) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawTransformEntityAnimationPipeline into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueSetShader",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdSetShader) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdSetShader into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueResetShader",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdResetShader) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdResetShader into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueSetBlendMode",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdSetBlendMode) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdSetBlendMode into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueUnsetBlendMode",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdUnsetBlendMode) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdUnsetBlendMode into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueSendUniformFloat",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdSendUniformFloat) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdSendUniformFloat into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueSendUniformInt",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdSendUniformInt) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdSendUniformInt into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueSendUniformVec2",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdSendUniformVec2) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdSendUniformVec2 into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueSendUniformVec3",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdSendUniformVec3) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdSendUniformVec3 into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueSendUniformVec4",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdSendUniformVec4) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdSendUniformVec4 into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueSendUniformFloatArray",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdSendUniformFloatArray) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdSendUniformFloatArray into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueSendUniformIntArray",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdSendUniformIntArray) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdSendUniformIntArray into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueVertex",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdVertex) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdVertex into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueBeginOpenGLMode",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdBeginOpenGLMode) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdBeginOpenGLMode into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueEndOpenGLMode",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdEndOpenGLMode) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdEndOpenGLMode into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueSetColor",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdSetColor) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdSetColor into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueSetLineWidth",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdSetLineWidth) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdSetLineWidth into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueSetTexture",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdSetTexture) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdSetTexture into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueRenderRectVerticesFilledLayer",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdRenderRectVerticesFilledLayer) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdRenderRectVerticesFilledLayer into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueRenderRectVerticesOutlineLayer",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdRenderRectVerticesOutlineLayer) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdRenderRectVerticesOutlineLayer into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawPolygon",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawPolygon) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawPolygon into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueRenderNPatchRect",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdRenderNPatchRect) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdRenderNPatchRect into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});

  rec.record_free_function(
      {"layer"},
      MethodDef{
          .name = "queueDrawTriangle",
          .signature = R"(---@param layer Layer # Target layer to queue into
        ---@param init_fn fun(c: layer.CmdDrawTriangle) # Function to initialize the command
        ---@param z number # Z-order depth to queue at
        ---@param renderSpace layer.DrawCommandSpace # Draw command space (default: Screen)
        ---@return void)",
          .doc =
              R"(Queues a CmdDrawTriangle into the layer draw list. Executes init_fn with a command instance and inserts it at the specified z-order.)",
          .is_static = true,
          .is_overload = false});
}

} // namespace layer
