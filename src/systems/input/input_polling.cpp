#include "input_polling.hpp"
#include "input_constants.hpp"
#include "input_hid.hpp"
#include "input_keyboard.hpp"
#include "input_gamepad.hpp"
#include "input_cursor_events.hpp"
#include "core/engine_context.hpp"
#include "core/events.hpp"
#include "core/globals.hpp"
#include "spdlog/spdlog.h"

#include <cmath>
#include <memory>

namespace input::polling {

// ===========================
// RaylibInputProvider Implementation
// ===========================

bool RaylibInputProvider::is_key_down(int key) const {
    return IsKeyDown(key);
}

bool RaylibInputProvider::is_key_released(int key) const {
    return IsKeyReleased(key);
}

int RaylibInputProvider::get_char_pressed() const {
    return GetCharPressed();
}

bool RaylibInputProvider::is_mouse_button_down(int button) const {
    return IsMouseButtonDown(button);
}

bool RaylibInputProvider::is_mouse_button_pressed(int button) const {
    return IsMouseButtonPressed(button);
}

Vector2 RaylibInputProvider::get_mouse_delta() const {
    return GetMouseDelta();
}

float RaylibInputProvider::get_mouse_wheel_move() const {
    return GetMouseWheelMove();
}

int RaylibInputProvider::get_touch_point_count() const {
    return GetTouchPointCount();
}

bool RaylibInputProvider::is_gamepad_available(int id) const {
    return IsGamepadAvailable(id);
}

bool RaylibInputProvider::is_gamepad_button_down(int id, int button) const {
    return IsGamepadButtonDown(id, button);
}

float RaylibInputProvider::get_gamepad_axis_movement(int id, int axis) const {
    return GetGamepadAxisMovement(id, axis);
}

const char* RaylibInputProvider::get_gamepad_name(int id) const {
    return GetGamepadName(id);
}

int RaylibInputProvider::get_gamepad_axis_count(int id) const {
    return GetGamepadAxisCount(id);
}

// ===========================
// Provider Management
// ===========================

static std::unique_ptr<IInputProvider> g_provider;
static RaylibInputProvider g_default_provider;

IInputProvider& get_provider() {
    if (g_provider) {
        return *g_provider;
    }
    return g_default_provider;
}

void set_provider(std::unique_ptr<IInputProvider> provider) {
    g_provider = std::move(provider);
}

// ===========================
// Polling State (moved from static in input_functions.cpp)
// ===========================

// Track key down state from previous frame
static std::vector<uint8_t> s_keyDownLastFrame(KEY_KP_EQUAL + 1, 0);  // uint8_t for performance

// Track mouse button state from previous frame
static bool s_mouseLeftDownLastFrame = false;
static bool s_mouseRightDownLastFrame = false;

// ===========================
// Helper Functions
// ===========================

// Resolve the event bus from context or globals
static event_bus::EventBus& resolve_event_bus(EngineContext* ctx) {
    if (ctx) {
        return ctx->eventBus;
    }
    return globals::getEventBus();
}

// ===========================
// Main Polling Function
// ===========================

void poll_all_inputs(entt::registry& reg, InputState& state, float dt, EngineContext* ctx) {
    auto& provider = get_provider();
    auto& bus = resolve_event_bus(ctx);

    // ----------------
    // Keyboard Input
    // ----------------
    for (int key = 0; key <= KEY_KP_EQUAL; key++) {
        if (provider.is_key_down(key)) {
            hid::reconfigure_device_info(reg, state, InputDeviceInputCategory::KEYBOARD);
            keyboard::process_key_down(state, static_cast<KeyboardKey>(key));

            // Detect first frame of key press
            if (!s_keyDownLastFrame[key]) {
                s_keyDownLastFrame[key] = 1;
                const bool shift = provider.is_key_down(KEY_LEFT_SHIFT) || provider.is_key_down(KEY_RIGHT_SHIFT);
                const bool ctrl = provider.is_key_down(KEY_LEFT_CONTROL) || provider.is_key_down(KEY_RIGHT_CONTROL);
                const bool alt = provider.is_key_down(KEY_LEFT_ALT) || provider.is_key_down(KEY_RIGHT_ALT);
                bus.publish(events::KeyPressed{key, shift, ctrl, alt});
            }
        }

        if (provider.is_key_released(key)) {
            hid::reconfigure_device_info(reg, state, InputDeviceInputCategory::KEYBOARD);
            keyboard::process_key_release(state, static_cast<KeyboardKey>(key));
            s_keyDownLastFrame[key] = 0;
        }
    }

    // ----------------
    // Touch Input
    // ----------------
    if (provider.get_touch_point_count() > 0) {
        hid::reconfigure_device_info(reg, state, InputDeviceInputCategory::TOUCH);
    }

    // ----------------
    // Mouse Buttons
    // ----------------
    bool mouseLeftDownCurrentFrame = provider.is_mouse_button_down(MOUSE_LEFT_BUTTON);
    bool mouseRightDownCurrentFrame = provider.is_mouse_button_down(MOUSE_RIGHT_BUTTON);

    // Mac right-click emulation: Ctrl+Left-click or Cmd+Left-click acts as right-click
    // This is standard Mac behavior that Raylib/GLFW doesn't handle automatically
    bool ctrlHeld = IsKeyDown(KEY_LEFT_CONTROL) || IsKeyDown(KEY_RIGHT_CONTROL);
    bool cmdHeld = IsKeyDown(KEY_LEFT_SUPER) || IsKeyDown(KEY_RIGHT_SUPER);
    bool emulatedRightClick = mouseLeftDownCurrentFrame && (ctrlHeld || cmdHeld);

    // If emulating right-click, don't treat as left-click
    bool effectiveLeftDown = mouseLeftDownCurrentFrame && !emulatedRightClick;
    bool effectiveRightDown = mouseRightDownCurrentFrame || emulatedRightClick;

    bool mouseDetectDownFirstFrameLeft = effectiveLeftDown && !s_mouseLeftDownLastFrame;
    bool mouseDetectDownFirstFrameRight = effectiveRightDown && !s_mouseRightDownLastFrame;

    if (mouseDetectDownFirstFrameLeft) {
        hid::reconfigure_device_info(reg, state, InputDeviceInputCategory::MOUSE);
        Vector2 mousePos = globals::getScaledMousePositionCached();
        // Margin gating: Block input when outside screen bounds
        if (mousePos.x < globals::VIRTUAL_WIDTH && mousePos.y < globals::VIRTUAL_HEIGHT) {
            cursor_events::enqueue_left_press(state, mousePos.x, mousePos.y);
            bus.publish(events::MouseClicked{mousePos, MOUSE_LEFT_BUTTON});
        }
    }

    if (mouseDetectDownFirstFrameRight) {
        hid::reconfigure_device_info(reg, state, InputDeviceInputCategory::MOUSE);
        Vector2 mousePos = globals::getScaledMousePositionCached();
        // Margin gating: Block input when outside screen bounds
        if (mousePos.x < globals::VIRTUAL_WIDTH && mousePos.y < globals::VIRTUAL_HEIGHT) {
            cursor_events::enqueue_right_press(state, mousePos.x, mousePos.y);
            bus.publish(events::MouseClicked{mousePos, MOUSE_RIGHT_BUTTON});
        }
    }

    if (!effectiveLeftDown && s_mouseLeftDownLastFrame) {
        // Left button release (or switched to emulated right-click)
        hid::reconfigure_device_info(reg, state, InputDeviceInputCategory::MOUSE);
        Vector2 mousePos = globals::getScaledMousePositionCached();
        // Margin gating: Block input when outside screen bounds
        if (mousePos.x < globals::VIRTUAL_WIDTH && mousePos.y < globals::VIRTUAL_HEIGHT) {
            cursor_events::process_left_release(reg, state, mousePos.x, mousePos.y, ctx);
        }
    }

    // Track effective states for next frame comparison
    s_mouseLeftDownLastFrame = effectiveLeftDown;
    s_mouseRightDownLastFrame = effectiveRightDown;

    // ----------------
    // Mouse Movement
    // ----------------
    Vector2 delta = provider.get_mouse_delta();
    if (delta.x != 0.0f || delta.y != 0.0f) {
        hid::reconfigure_device_info(reg, state, InputDeviceInputCategory::MOUSE);
    }

    // ----------------
    // Mouse Wheel
    // ----------------
    float wheelMove = provider.get_mouse_wheel_move();
    if (wheelMove != 0.0f) {
        hid::reconfigure_device_info(reg, state, InputDeviceInputCategory::MOUSE);
        // Dispatch as axis input (using special AXIS_MOUSE_WHEEL_Y code)
        input::DispatchRaw(state,
            InputDeviceInputCategory::GAMEPAD_AXIS, // intentionally using gamepad axis category
            AXIS_MOUSE_WHEEL_Y,
            /*down*/ true,
            /*value*/ wheelMove);
    }

    // ----------------
    // Gamepad Input
    // ----------------
    if (provider.is_gamepad_available(0)) {
        // Gamepad button states
        struct GamepadButtonState {
            bool downLastFrame = false;
            bool downCurrentFrame = false;
        };
        static std::unordered_map<GamepadButton, GamepadButtonState> gamepadButtonStates;

        // Poll all gamepad buttons
        for (int button = GamepadButton::GAMEPAD_BUTTON_LEFT_FACE_UP; button <= GAMEPAD_BUTTON_RIGHT_THUMB; button++) {
            gamepadButtonStates[static_cast<GamepadButton>(button)].downCurrentFrame =
                provider.is_gamepad_button_down(0, static_cast<GamepadButton>(button));

            bool gamepadButtonDetectDownFirstFrame =
                gamepadButtonStates[static_cast<GamepadButton>(button)].downCurrentFrame &&
                !gamepadButtonStates[static_cast<GamepadButton>(button)].downLastFrame;

            bool gamepadButtonDetectUpFirstFrame =
                !gamepadButtonStates[static_cast<GamepadButton>(button)].downCurrentFrame &&
                gamepadButtonStates[static_cast<GamepadButton>(button)].downLastFrame;

            if (gamepadButtonDetectDownFirstFrame) {
                hid::set_current_gamepad(state, provider.get_gamepad_name(0), 0);
                hid::reconfigure_device_info(reg, state, InputDeviceInputCategory::GAMEPAD_BUTTON, static_cast<GamepadButton>(button));
                gamepad::process_button_press(state, static_cast<GamepadButton>(button), ctx);
            }

            if (gamepadButtonDetectUpFirstFrame) {
                hid::set_current_gamepad(state, provider.get_gamepad_name(0), 0);
                hid::reconfigure_device_info(reg, state, InputDeviceInputCategory::GAMEPAD_BUTTON, static_cast<GamepadButton>(button));
                gamepad::process_button_release(state, static_cast<GamepadButton>(button), ctx);
            }

            gamepadButtonStates[static_cast<GamepadButton>(button)].downLastFrame =
                gamepadButtonStates[static_cast<GamepadButton>(button)].downCurrentFrame;
        }

        // Poll gamepad axes
        float axisLeftX = provider.get_gamepad_axis_movement(0, GAMEPAD_AXIS_LEFT_X);
        float axisLeftY = provider.get_gamepad_axis_movement(0, GAMEPAD_AXIS_LEFT_Y);
        float axisRightX = provider.get_gamepad_axis_movement(0, GAMEPAD_AXIS_RIGHT_X);
        float axisRightY = provider.get_gamepad_axis_movement(0, GAMEPAD_AXIS_RIGHT_Y);
        float axisLT = provider.get_gamepad_axis_movement(0, GAMEPAD_AXIS_LEFT_TRIGGER);
        float axisRT = provider.get_gamepad_axis_movement(0, GAMEPAD_AXIS_RIGHT_TRIGGER);

        // Check if any axis exceeds threshold
        if (std::abs(axisLeftX) > constants::GAMEPAD_AXIS_MOVEMENT_THRESHOLD ||
            std::abs(axisLeftY) > constants::GAMEPAD_AXIS_MOVEMENT_THRESHOLD ||
            std::abs(axisRightX) > constants::GAMEPAD_AXIS_MOVEMENT_THRESHOLD ||
            std::abs(axisRightY) > constants::GAMEPAD_AXIS_MOVEMENT_THRESHOLD ||
            axisLT > -1.0f || axisRT > -1.0f) {

            hid::set_current_gamepad(state, provider.get_gamepad_name(0), 0);
            hid::reconfigure_device_info(reg, state, InputDeviceInputCategory::GAMEPAD_AXIS);
            gamepad::update_axis_input(state, reg, dt, ctx);
        }
    }
}

// ===========================
// Mouse Activity Detection
// ===========================

InputDeviceInputCategory detect_mouse_activity(InputState& state) {
    auto& provider = get_provider();
    Vector2 mousePos = globals::getScaledMousePositionCached();

    // Movement threshold
    bool moved = std::fabs(mousePos.x - state.cursor_position.x) > constants::MOUSE_MOVEMENT_THRESHOLD ||
                 std::fabs(mousePos.y - state.cursor_position.y) > constants::MOUSE_MOVEMENT_THRESHOLD;

    // Buttons or wheel
    bool clicked = provider.is_mouse_button_pressed(MOUSE_LEFT_BUTTON) ||
                   provider.is_mouse_button_pressed(MOUSE_RIGHT_BUTTON) ||
                   provider.get_mouse_wheel_move() != 0.0f;

    if (moved || clicked) {
        state.cursor_position = mousePos; // keep in sync
        return InputDeviceInputCategory::MOUSE;
    }

    return InputDeviceInputCategory::NONE;
}

} // namespace input::polling
