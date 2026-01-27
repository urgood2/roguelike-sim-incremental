#include "ai_system.hpp"

#include "../../components/components.hpp"
#include "../transform/transform.hpp"

#include "../../util/utilities.hpp"

#include "../../core/globals.hpp"

#include "../scripting/scripting_functions.hpp"
#include "../scripting/scripting_system.hpp"
#include "../scripting/binding_recorder.hpp"

#include "../event/event_system.hpp"

#include "../../third_party/GPGOAP/goap.h"
#include "../../third_party/GPGOAP/astar.h"

#include "entt/process/process.hpp"
#include "entt/process/scheduler.hpp"

#include "sol/sol.hpp"

#include <functional>
#include <queue>
#include <iostream>
#include <unordered_map>
#include <string>
#include <any>
#include <optional>
#include <cmath>
#include <limits>
#include <filesystem>
#include <chrono>

#include "../../util/common_headers.hpp"
#include "util/error_handling.hpp"
#include "goap_utils.hpp"

namespace ai_system
{
    namespace
    {
        std::optional<entt::entity> resolve_entity(sol::object obj)
        {
            if (obj.is<entt::entity>()) {
                return obj.as<entt::entity>();
            }
            if (obj.is<int>()) {
                return static_cast<entt::entity>(obj.as<int>());
            }
            if (obj.is<double>()) {
                return static_cast<entt::entity>(static_cast<int>(obj.as<double>()));
            }
            return std::nullopt;
        }

        std::optional<Vector2> extract_position(entt::registry &registry, sol::object obj)
        {
            if (auto maybeEntity = resolve_entity(obj)) {
                entt::entity e = *maybeEntity;
                if (!registry.valid(e)) {
                    return std::nullopt;
                }

                if (registry.any_of<transform::Transform>(e)) {
                    auto &t = registry.get<transform::Transform>(e);
                    float x = t.getActualX() + 0.5f * t.getActualW();
                    float y = t.getActualY() + 0.5f * t.getActualH();

                    if (auto *go = registry.try_get<transform::GameObject>(e)) {
                        if (registry.valid(go->container) && registry.any_of<transform::Transform>(go->container)) {
                            auto &ct = registry.get<transform::Transform>(go->container);
                            x += ct.getActualX();
                            y += ct.getActualY();
                        }
                    }

                    return Vector2{x, y};
                }

                if (registry.any_of<LocationComponent>(e)) {
                    auto &loc = registry.get<LocationComponent>(e);
                    return Vector2{loc.x, loc.y};
                }

                return std::nullopt;
            }

            if (obj.is<sol::table>()) {
                auto t = obj.as<sol::table>();
                if (t["x"].valid() && t["y"].valid()) {
                    return Vector2{t.get_or("x", 0.0f), t.get_or("y", 0.0f)};
                }
            }

            return std::nullopt;
        }
    } // namespace

    bool ai_system_paused = false; // global flag to pause the AI system, from lua
    
    sol::state masterStateLua; // stores all scripts in one state

    std::map<std::string, std::map<std::string, bool>> allPostconditionsForEveryAction; // Contains all post-conditions for every action

    scheduler masterScheduler{}; // master scheduler for AI processes

    float aiUpdateTickInSeconds = 0.5f;
    float aiUpdateTickTotal = 0.0f; // running total of time passed since last tick

    bool goap_worldstate_match(actionplanner_t *ap, worldstate_t current_state, worldstate_t expected_state)
    {
        // Calculate the bits that we should care about (i.e., not "don't care" bits)
        bfield_t relevant_bits = ~expected_state.dontcare;

        // Check if the relevant bits in the current state match the expected state
        // This is done by applying a bitwise AND between the relevant bits and both states' values
        // Then compare the results to see if they match
        bool match = (current_state.values & relevant_bits) == (expected_state.values & relevant_bits);

        return match;
    }

    /**
     * @brief  Converts a GOAP plan (array of action names) into a runnable queue of Lua-backed Actions.
     *
     * This function clears any previously enqueued actions on the specified entity’s GOAPComponent,
     * then—for each action name in the provided plan—looks up the corresponding Lua table
     * (which must have been loaded into `masterStateLua` at init), wraps its `start`/`update`/`finish`
     * functions into a C++ `Action` struct, and pushes it onto the queue.  Finally, it immediately
     * invokes the first action’s `start` callback so that execution can begin on the very next frame.
     *
     * @pre
     *   - `globals::getRegistry()` must contain a valid `GOAPComponent` for entity `e`.
     *   - `masterStateLua` must already have been populated via `require`-ing each action’s Lua file,
     *     so that `masterStateLua[actionName]` returns a table with keys `"start"`, `"update"`, and `"finish"`.
     *
     * @param e
     *   The `entt::entity` whose GOAPComponent’s `actionQueue` will be populated.
     *
     * @param plan
     *   A pointer to an array of C‐strings; each string is an action name produced by the GOAP planner
     *   (i.e., the contents of `goapStruct.plan`).  The array is _not_ required to be null-terminated; its
     *   length is given by `planSize`.
     *
     * @param planSize
     *   The number of entries in `plan`.  Only indices `[0 .. planSize-1]` will be read.
     *
     * @behavior
     *   1. **Clear previous queue**: Pops every remaining `Action` from `cmp.actionQueue`.
     *   2. **Iterate over plan**: For each index `i` in `[0 .. planSize-1]`:
     *      - Read `plan[i]` into `actionName`.
     *      - Fetch `sol::table tbl = masterStateLua[actionName];`.
     *      - Construct an `Action a` with `a.start = tbl["start"]; a.update = tbl["update"]; a.finish = tbl["finish"];`.
     *      - Push `a` onto `cmp.actionQueue`.
     *   3. **Kick off first action**: If the queue is non-empty, call `start(e)` on the front action and mark it `is_running = true`.
     *
     * @sideeffects
     *   - Modifies `GOAPComponent::actionQueue` for entity `e`.
     *   - Immediately invokes one Lua function (`start`) on the same frame you call this.
     *
     * @example
     * @code{.cpp}
     * // After replanning:
     * auto &goapComp = globals::getRegistry().get<GOAPComponent>(myEntity);
     * replan(myEntity);  // fills goapComp.plan[] and goapComp.planSize
     * fill_action_queue_based_on_plan(myEntity,
     *                                  goapComp.plan,
     *                                  goapComp.planSize);
     * // Next frame, behavior_system::update(myEntity, dt) will resume the first action’s coroutine.
     * @endcode
     */
    void fill_action_queue_based_on_plan(entt::registry& registry, entt::entity e, const char **plan, int planSize)
    {
        auto &cmp = registry.get<GOAPComponent>(e);

        while (!cmp.actionQueue.empty())
            cmp.actionQueue.pop();

        for (int i = 0; i < planSize; i++) {
            std::string actionName = plan[i];

            sol::table actionsT = cmp.def["actions"];
            sol::optional<sol::table> maybe = actionsT.get<sol::table>(actionName);
            if (!maybe) {
                SPDLOG_ERROR("Unknown action '{}' in ai.actions", actionName);
                continue;
            }
            sol::table tbl = *maybe;

            // -- coroutine setup (unchanged) --
            sol::function fn_update = tbl["update"];
            sol::thread thr = sol::thread::create(masterStateLua);
            sol::state_view thread_view = thr.state();
            thread_view["__update_fn"] = fn_update;
            sol::function thread_fn = thread_view["__update_fn"];
            sol::coroutine co = sol::coroutine{thread_fn};

            Action a;
            a.name      = actionName;
            a.start     = tbl["start"];
            a.thread    = std::move(thr);
            a.update    = std::move(co);
            a.finish    = tbl["finish"];
            a.abort     = tbl["abort"];                 // optional
            a.watchMask = build_watch_mask(cmp.ap, tbl);// NEW
            a.is_running = false;

            cmp.actionQueue.push(std::move(a));
            SPDLOG_DEBUG("Adding action '{}' to queue for entity {}", actionName, (int)e);
        }

        if (!cmp.actionQueue.empty()) {
            auto startResult = util::safeLuaCall(cmp.actionQueue.front().start, "ai action start", e);
            if (startResult.isErr()) {
                SPDLOG_ERROR("AI start() failed: {}", startResult.error());
            }
            cmp.actionQueue.front().is_running = true;
        }
    }

    [[deprecated("Use fill_action_queue_based_on_plan(registry, e, plan, planSize) instead")]]
    void fill_action_queue_based_on_plan(entt::entity e, const char **plan, int planSize)
    {
        fill_action_queue_based_on_plan(globals::getRegistry(), e, plan, planSize);
    }

    /*
     * @brief Clears the action planner by resetting atom and action counts and data.
     * This function resets the action planner's atoms, actions, and world states,
     * and frees any dynamically allocated memory. Must be called before exiting the program.
     */
     void goap_actionplanner_clear_memory(actionplanner_t *ap)
     {
         // Delegate to library clear so atom/action name allocations are freed.
         goap_actionplanner_clear(ap);
     }

    /**
     * Retrieves the value of a specific atom from the given world state.
     * Example usage:
     *
     *     bool value;
     *     bool valid = goap_worldstate_get(&ap, ws, "alive", &value);
     *
     * This will retrieve the value of the "alive" atom from the given world state.
     * If the atom is not found, valid will be false.
     * Valid will only be true if the "value" variable is successfully set.
     *
     * @param ap The action planner.
     * @param ws The world state.
     * @param atomname The name of the atom to retrieve.
     * @param value A pointer to a boolean variable where the retrieved value will be stored.
     * @return True if the atom is found and its value is successfully retrieved, false otherwise.
     */
    bool goap_worldstate_get(actionplanner_t *ap, worldstate_t ws, const char *atomname, bool *value)
    {
        int idx = -1;

        // Find the index of the atom
        for (int i = 0; i < ap->numatoms; ++i)
        {
            if (strcmp(ap->atm_names[i], atomname) == 0)
            {
                idx = i;
                break;
            }
        }

        // If the atom is not found, return false (error)
        if (idx == -1)
        {
            return false;
        }

        // Check if this atom is a "don't care" bit
        if (ws.dontcare & (1LL << idx))
        {
            return false;
        }

        // Retrieve the value of the atom
        *value = (ws.values & (1LL << idx)) != 0;
        return true;
    }

    /**
     * Checks if the given GOAPComponent structure is valid.
     *
     * @param goapStruct The GOAPComponent structure to be checked.
     * @return True if the structure is valid, false otherwise.
     */
    bool goap_is_goapstruct_valid(GOAPComponent &goapStruct)
    {
        // If the number of plan is zero, the planner is empty
        return goapStruct.planSize == 0 || goapStruct.dirty == true;
    }

    // // takes a loaded-in json object and reads in the actions and their preconditions and postconditions
    // void load_actions_from_json(const json& data, actionplanner_t& planner) {
    //     for (const auto& action : data["actions"]) {
    //         std::string name = action["name"];
    //         int cost = action["cost"].get<int>();

    //         // Debug log the action name and cost
    //         SPDLOG_DEBUG("Loading action: {}, Cost: {}", name, cost);

    //         goap_set_cost(&planner, name.c_str(), cost);

    //         // Debugging the preconditions
    //         // SPDLOG_DEBUG("  Preconditions:");
    //         for (const auto& precondition : action["preconditions"].items()) {
    //             const std::string pre_key = precondition.key();
    //             const bool pre_value = precondition.value().get<bool>();

    //             // Log the precondition
    //             // SPDLOG_DEBUG("    {}: {}", pre_key, pre_value ? "true" : "false");

    //             goap_set_pre(&planner, name.data(), pre_key.data(), pre_value);
    //             SPDLOG_DEBUG("goap_set_pre(&planner, {}, {}, {})", name, pre_key, pre_value);
    //         }

    //         // Debugging the postconditions
    //         // SPDLOG_DEBUG("  Postconditions:");
    //         for (const auto& postcondition : action["postconditions"].items()) {
    //             const std::string post_key = postcondition.key();
    //             const bool post_value = postcondition.value().get<bool>();

    //             // Log the postcondition
    //             // SPDLOG_DEBUG("    {}: {}", post_key, post_value ? "true" : "false");

    //             goap_set_pst(&planner, name.data(), post_key.data(), post_value);
    //             SPDLOG_DEBUG("goap_set_pst(&planner, {}, {}, {})", name, post_key, post_value);

    //             allPostconditionsForEveryAction[name][post_key] = post_value ;
    //         }

    //         SPDLOG_DEBUG("Planner state after loading action: {}", name);

    //         char desc[ 4096 ];
    //         goap_description( &planner, desc, sizeof(desc) );
    //         SPDLOG_INFO("{}", desc);
    //     }
    // }

    // void load_worldstate_from_json(const json& data, actionplanner_t& planner, worldstate_t& initialState, worldstate_t& goalState) {
    //     // Debugging initial state
    //     SPDLOG_DEBUG("Loading initial world state:");
    //     for (const auto& atom : data["initial_state"].items()) {
    //         const std::string& atom_key = atom.key();
    //         const bool atom_value = atom.value().get<bool>();

    //         // Log the initial state atom
    //         // SPDLOG_DEBUG("  {}: {}", atom_key, atom_value ? "true" : "false");

    //         goap_worldstate_set(&planner, &initialState, atom_key.c_str(), atom_value);
    //         SPDLOG_DEBUG("goap_worldstate_set(&planner, &initialState, {}, {})", atom_key.c_str(), atom_value);
    //     }

    //     // Debugging goal state
    //     SPDLOG_DEBUG("Loading goal world state:");
    //     for (const auto& atom : data["goal_state"].items()) {
    //         const std::string& atom_key = atom.key();
    //         const bool atom_value = atom.value().get<bool>();

    //         // Log the goal state atom
    //         // SPDLOG_DEBUG("  {}: {}", atom_key, atom_value ? "true" : "false");

    //         goap_worldstate_set(&planner, &goalState, atom_key.c_str(), atom_value);
    //         SPDLOG_DEBUG("goap_worldstate_set(&planner, &goalState, {}, {})", atom_key.c_str(), atom_value);
    //     }

    //     SPDLOG_DEBUG("Finished loading world state\n");
    // }

    // Function to find a Lua function by key in a table
    sol::protected_function find_function_in_table(sol::table &tbl, const std::string &func_name)
    {
        sol::protected_function func = tbl[func_name]; // Try to fetch the function by name
        if (func.valid() && func.get_type() == sol::type::function)
        {
            SPDLOG_DEBUG("Function '{}' found in table.", func_name);
            return func;
        }
        else
        {
            SPDLOG_DEBUG("Function '{}' not found in table.", func_name);
            return sol::lua_nil; // sol::nil works fine in windows?
        }
    }

    // Function to debug the result of a Lua function call.
    // If the result is invalid, it will log the error message.
    auto debugLuaProtectedFunctionResult(sol::protected_function_result &result, std::string functionName) -> void
    {
        if (!result.valid())
        {
            sol::error err = result;
            SPDLOG_ERROR("Error calling Lua function: {}", err.what());
        }
        else
        {
            SPDLOG_DEBUG("Lua function call to '{}' successful.", functionName);
        }
    }

    /**
     * The string identfier given will be used to refer to a table and find a
     * blackboard initialization function in the lua master state. If nothing is found, a default blackboard initialization function will be used.
     * Also clears the blackboard before initializing it.
     */
    auto runBlackboardInitFunction(entt::registry& registry, entt::entity entity, const std::string &identifier) -> void
    {
        auto &goapStruct = registry.get<GOAPComponent>(entity);
        goapStruct.blackboard.clear();

        // 1) Grab the lua table you populated in ai.init.lua
        sol::table initTable = goapStruct.def["blackboard_init"];
        if (!initTable.valid())
        {
            SPDLOG_ERROR("ai.blackboard_init table is missing!");
            return;
        }

        // 2) Try the specific function
        sol::optional<sol::protected_function> maybeFunc =
            initTable.get<sol::protected_function>(identifier);

        // 3) Fallback to the "default" key if not found
        sol::protected_function func;
        if (maybeFunc)
        {
            func = *maybeFunc;
            SPDLOG_DEBUG("Found blackboard init for '{}'", identifier);
        }
        else
        {
            SPDLOG_WARN("No blackboard init for '{}', using default", identifier);
            sol::optional<sol::protected_function> maybeDefault =
                initTable.get<sol::protected_function>("default");
            if (!maybeDefault)
            {
                SPDLOG_ERROR("ai.blackboard_init.default is missing!");
                return;
            }
            func = *maybeDefault;
        }

        // 4) Call it
        auto result = util::safeLuaCall(func, std::string("ai blackboard init:") + identifier, entity);
        if (result.isErr())
        {
            SPDLOG_ERROR("Error in blackboard init '{}': {}", identifier, result.error());
        }
    }

    [[deprecated("Use runBlackboardInitFunction(registry, entity, identifier) instead")]]
    auto runBlackboardInitFunction(entt::entity entity, const std::string &identifier) -> void
    {
        runBlackboardInitFunction(globals::getRegistry(), entity, identifier);
    }

    /**
     * Load actions from Lua definition into GOAP planner.
     *
     * @return true if loading succeeded, false on failure (atom cap exceeded, exception, etc.)
     */
    bool load_actions_from_lua(GOAPComponent &comp, actionplanner_t &planner)
    {
        try {
            sol::table actions = comp.def["actions"];
            for (auto &[key, val] : actions)
            {
                std::string name = key.as<std::string>();
                sol::table tbl = val.as<sol::table>();

                int cost = tbl["cost"].get_or(1);
                goap_set_cost(&planner, name.c_str(), cost);

                sol::table pre = tbl["pre"];
                for (auto &[pre_key, pre_val] : pre)
                    goap_set_pre(&planner, name.c_str(), pre_key.as<std::string>().c_str(), pre_val.as<bool>());

                sol::table post = tbl["post"];
                for (auto &[post_key, post_val] : post)
                {
                    goap_set_pst(&planner, name.c_str(), post_key.as<std::string>().c_str(), post_val.as<bool>());
                    allPostconditionsForEveryAction[name][post_key.as<std::string>()] = post_val.as<bool>();
                }
            }

            // Phase 0.3: Validate atom count - early return on failure to prevent UB
            if (!ai::validate_atom_count(planner)) {
                SPDLOG_ERROR("GOAP atom count ({}) exceeds safe limit ({}). "
                             "Actions NOT loaded. Reduce the number of unique atoms.",
                             planner.numatoms, ai::get_safe_atom_cap());
                return false;  // Don't increment version, signal failure
            }

            // Phase 0.4: Increment actionset version ONLY on complete success
            comp.actionset_version++;
            return true;
        } catch (const sol::error& e) {
            SPDLOG_ERROR("Lua error in load_actions_from_lua: {}", e.what());
            return false;  // Version not incremented on exception
        } catch (const std::exception& e) {
            SPDLOG_ERROR("Exception in load_actions_from_lua: {}", e.what());
            return false;  // Version not incremented on exception
        }
    }

    /**
     * Load worldstate (initial state and goal) from Lua definition.
     *
     * @return true if loading succeeded, false on failure (unknown type, atom cap exceeded)
     */
    bool load_worldstate_from_lua(GOAPComponent &comp,
                                  const std::string &creature_type,
                                  actionplanner_t &planner,
                                  worldstate_t &initial,
                                  worldstate_t &goal)
    {
        sol::table types = comp.def["entity_types"];
        sol::optional<sol::table> maybe_def = types.get<sol::table>(creature_type);
        if (!maybe_def)
        {
            SPDLOG_ERROR("Unknown creature_type '{}'", creature_type);
            return false;  // Don't increment version
        }
        sol::table def = *maybe_def;

        sol::table init = def["initial"];
        sol::table target = def["goal"];

        for (auto &kv : init)
        {
            auto key = kv.first.as<std::string>();
            auto value = kv.second.as<bool>();
            goap_worldstate_set(&planner, &initial, key.c_str(), value);
        }

        for (auto &kv : target)
        {
            auto key = kv.first.as<std::string>();
            auto value = kv.second.as<bool>();
            goap_worldstate_set(&planner, &goal, key.c_str(), value);
        }

        // Phase 0.3: Validate atom count - early return on failure to prevent UB
        if (!ai::validate_atom_count(planner)) {
            SPDLOG_ERROR("GOAP atom count ({}) exceeds safe limit ({}) for type '{}'. "
                         "Worldstate NOT loaded. Reduce the number of unique atoms.",
                         planner.numatoms, ai::get_safe_atom_cap(), creature_type);
            return false;  // Don't increment version, signal failure
        }

        // Phase 0.4: Increment atom schema version ONLY on complete success
        comp.atom_schema_version++;
        return true;
    }

    void initGOAPComponent(entt::registry& registry, entt::entity entity,
                           const std::string &type,
                           sol::optional<sol::table> overrides /*may be nil*/)
    {
        auto &goap = registry.get<GOAPComponent>(entity);

        // look up prototype
        sol::table types = masterStateLua["ai"]["entity_types"];
        sol::optional<sol::table> maybe_def = types.get<sol::table>(type);
        if (!maybe_def)
        {
            SPDLOG_ERROR("Unknown creature_type '{}'", type);
            return;
        }
        sol::table proto = *maybe_def;
        sol::table aiTable = masterStateLua["ai"];
        sol::function dc = masterStateLua["deep_copy"];
        sol::table def_instance = dc(aiTable);

        masterStateLua["dump"](def_instance);

        // --- NEW: apply overrides, if any ---
        if (overrides && overrides.value().valid())
        {
            for (auto &kv : overrides.value())
            {
                def_instance[kv.first] = kv.second;
            }
        }

        // store the per-entity table
        goap.def = def_instance;

        // the rest of your classic setup:
        goap_actionplanner_clear(&goap.ap);

        // Load actions and worldstate - abort initialization if either fails
        if (!load_actions_from_lua(goap, goap.ap)) {
            SPDLOG_ERROR("initGOAPComponent failed for entity {} type '{}': actions load failed",
                        static_cast<int>(entity), type);
            goap.dirty = true;  // Mark as needing replan (won't work without valid actions)
            return;
        }

        if (!load_worldstate_from_lua(goap, type, goap.ap, goap.current_state, goap.goal)) {
            SPDLOG_ERROR("initGOAPComponent failed for entity {} type '{}': worldstate load failed",
                        static_cast<int>(entity), type);
            goap.dirty = true;  // Mark as needing replan
            return;
        }

        goap.type = type;
        runBlackboardInitFunction(entity, type); // Initialize the blackboard for this entity type
        select_goal(entity);
    }

    [[deprecated("Use initGOAPComponent(registry, entity, type, overrides) instead")]]
    void initGOAPComponent(entt::entity entity,
                           const std::string &type,
                           sol::optional<sol::table> overrides)
    {
        initGOAPComponent(globals::getRegistry(), entity, type, overrides);
    }

    // void initGOAPComponent(entt::entity entity, const std::string& type)
    // {
    //     auto& goap = globals::getRegistry().get<GOAPComponent>(entity);

    //     // 1) look up the prototype
    //     sol::table types = masterStateLua["ai"]["entity_types"];
    //     sol::optional<sol::table> maybe_def = types.get<sol::table>(type);
    //     if (!maybe_def) {
    //         SPDLOG_ERROR("Unknown creature_type '{}'", type);
    //         return;
    //     }
    //     sol::table proto = *maybe_def;

    //     // 2) deep‐copy so each entity can mutate freely
    //     sol::function dc = masterStateLua["deep_copy"];
    //     sol::table def_instance = dc(proto);
    //     goap.def = def_instance; // store the prototype table in the component

    //     goap_actionplanner_clear(&goap.ap);

    //     load_actions_from_lua(goap, goap.ap); // all actions, global

    //     // Per-creature world state
    //     load_worldstate_from_lua(goap, type, goap.ap, goap.current_state, goap.goal);

    //     // Cache type string
    //     goap.type = type;

    //     // Goal will be selected after worldstate is updated
    //     select_goal(entity);
    // }

    auto onGOAPComponentDestroyed(entt::registry &reg, entt::entity entity) -> void
    {
        // clear memory of goap strings (c-style, needs manual memory management)
        goap_actionplanner_clear_memory(&reg.get<GOAPComponent>(entity).ap);
        SPDLOG_DEBUG("GOAPComponent for entity {} destroyed, cleared memory.", static_cast<int>(entity));
    }

    // TODO: each entity type (humans, animals, etc) should have custom blackboard initialization functions in lua

    // TODO: make human entity def file

    // creature tags should be globally avaiable to lua scripts

    bool resetGOAPAndLuaStateRequested{false};

    /**
     * Issues a LuaStateResetEvent to all systems when this takes place.
     */
    auto requestAISystemReset() -> void
    {
        SPDLOG_DEBUG("Requesting a reset of the AI system.");
        resetGOAPAndLuaStateRequested = true;
    }

    // Note that this should not be called from lua state, it will cause a crash. Operations like this should be queued and done later.
    auto resetAllGOAPComponentsAndScripting() -> void
    {

        SPDLOG_DEBUG("Resetting all GOAP components and reinitializing them.");
        // iterate over all entities with GOAPComponent and reset them
        std::vector<entt::entity> entitiesWithGOAP{};
        auto view = globals::getRegistry().view<GOAPComponent>();
        for (auto entity : view)
        {
            // remove the goap component
            globals::getRegistry().remove<GOAPComponent>(entity);
            entitiesWithGOAP.push_back(entity);
        }

        // now reset lua master state and initialize it again
        SPDLOG_DEBUG("Resetting Lua master state and re-loading scripts from disk.");
        masterStateLua = sol::state{};
        init();
        // re-init all the goap components
        for (auto entity : entitiesWithGOAP)
        {
            globals::getRegistry().emplace<GOAPComponent>(entity);
        }

        event_system::Publish<LuaStateResetEvent>({&masterStateLua}); // this will update any other systems that need the master lua state
    }

    auto init() -> void
    {
        // debug message indicating that ai_system::init() was called
        // SPDLOG_DEBUG("ai_system::init() called - doing nothing (goap inits on individual basis)");

        // get value of ai_tick_rate_seconds from config json and store it in aiUpdateTickInSeconds
        aiUpdateTickInSeconds = globals::getConfigJson()["global_tick_settings"]["ai_tick_rate_seconds"];

        // globals::getRegistry().on_construct<GOAPComponent>().connect<&onGOAPComponentCreated>();
        globals::getRegistry().on_destroy<GOAPComponent>().connect<&onGOAPComponentDestroyed>();

        // ------------------------------------------------------
        // methods for entt registry access & monobehavior
        // ------------------------------------------------------
        scripting::monobehavior_system::init(globals::getRegistry(), masterStateLua, globals::g_ctx);
        scripting::monobehavior_system::generateBindingsToLua(masterStateLua);

        // read in master lua state

        std::string tutorialDir = util::getRawAssetPathNoUUID(fmt::format("scripts/{}", globals::getAiConfigJson()["tutorialDirectory"].get<std::string>()));
        std::string coreDir = util::getRawAssetPathNoUUID(fmt::format("scripts/{}", globals::getAiConfigJson()["coreDirectory"].get<std::string>()));
        std::string monoBehaviorDir = util::getRawAssetPathNoUUID(fmt::format("scripts/{}", globals::getAiConfigJson()["monoBehaviorDirectory"].get<std::string>()));
        std::string taskDir = util::getRawAssetPathNoUUID(fmt::format("scripts/{}", globals::getAiConfigJson()["taskDirectory"].get<std::string>()));
        std::string aiInitDir = util::getRawAssetPathNoUUID("scripts/ai");

        std::vector<std::string> luaFiles{};

        // Iterate over all files in the directories
        getLuaFilesFromDirectory(tutorialDir, luaFiles);
        getLuaFilesFromDirectory(coreDir, luaFiles);
        getLuaFilesFromDirectory(monoBehaviorDir, luaFiles);
        getLuaFilesFromDirectory(taskDir, luaFiles);
        getLuaFilesFromDirectory(aiInitDir, luaFiles);

        // run default initialization function
        scripting::initLuaMasterState(masterStateLua, luaFiles, globals::g_ctx);
    }

    auto cleanup() -> void
    {
        // Clear all GOAP components before destroying the Lua state
        auto view = globals::getRegistry().view<GOAPComponent>();
        for (auto entity : view)
        {
            globals::getRegistry().remove<GOAPComponent>(entity);
        }

        // Drop all event listeners before the Lua state is torn down to avoid
        // dangling sol::function handles pointing at a dead lua_State.
        event_system::ClearAllListeners();

        // Properly close the Lua state to avoid crashes on exit
        // The sol::state destructor will handle lua_close internally,
        // but we need to ensure it happens before other cleanup
        masterStateLua.collect_garbage();
        masterStateLua = sol::state{}; // Reset to empty state

        SPDLOG_DEBUG("AI system cleanup complete - Lua state closed");
    }

    void getLuaFilesFromDirectory(const std::string &actionsDir, std::vector<std::string> &luaFiles)
    {
        for (const auto &entry : std::filesystem::directory_iterator(actionsDir))
        {
            std::string file_path = entry.path().string();
            // Check if the file has a .lua extension
            if (entry.path().extension() == ".lua")
            {
                // Normalize the path to use forward slashes
                std::replace(file_path.begin(), file_path.end(), '\\', '/');

                SPDLOG_DEBUG("Found Lua file: {}", file_path);
                // Add the Lua file to the list
                luaFiles.push_back(file_path);
            }
        }
    }

    /**
     * Call this method after using astar_plan().
     * Checks if the GOAPComponent is dirty by comparing its current plan size with the initial plan buffer size. If there is a match or the plan size is zero,
     * the struct is considered not properly initialized.
     */
    void checkAndSetGOAPDirty(GOAPComponent &goapStruct, int initialPlanBufferSize)
    {
        if (goapStruct.planSize == 0 || goapStruct.planSize == initialPlanBufferSize || goapStruct.planCost == -1)
        { // -1 means not initialized
            goapStruct.dirty = true;
        }
        else
        {
            goapStruct.dirty = false;
        }
    }

    /**
     * Handles the situation when no plan can be found for the given GOAP component.
     *
     * This function allows you to implement a strategy for when no plan can be found.
     * It provides an example of setting a fallback goal (e.g., wandering) and finding a plan using A* search algorithm.
     * If no plan is found, it suggests entering an idle state or default action.
     *
     * @param goapStruct The GOAP component structure.
     */
    void handle_no_plan(entt::registry& registry, entt::entity entity)
    {
        auto &goapStruct = registry.get<GOAPComponent>(entity);

        goap_worldstate_clear(&goapStruct.goal);

        if (goapStruct.planSize == 0)
        {
        }
    }

    [[deprecated("Use handle_no_plan(registry, entity) instead")]]
    void handle_no_plan(entt::entity entity)
    {
        handle_no_plan(globals::getRegistry(), entity);
    }

    /**
     * Selects a goal for the AI system based on the current state of the GOAPComponent.
     * If the creature is hungry, the goal is set to eat.
     * If an enemy is visible, the goal is set to attack the enemy.
     * If none of the above conditions are met, the default goal is set to wander.
     * After selecting the goal, a new plan is generated based on the selected goal.
     *
     * @param goapStruct A pointer to the GOAPComponent containing the current state and goal.
     */
    // void select_goal(entt::entity entity) {

    //     auto table = masterStateLua[globals::aiConfigJSON["goalSelectionLogicTableName"].get<std::string>()];
    //     sol::protected_function selectGoal = table[globals::aiConfigJSON["goalSelectionLogicFunctionName"].get<std::string>()];

    //     sol::protected_function_result result = selectGoal(entity);

    //     if (!result.valid()) {
    //         sol::error err = result;
    //         SPDLOG_ERROR("{}: Error selecting goal: {}", static_cast<int>(entity), err.what());
    //         return;
    //     }

    //     // Generate a new plan based on the selected goal
    //     replan(entity);
    // }

    void select_goal(entt::registry& registry, entt::entity entity)
    {
        auto &goap = registry.get<GOAPComponent>(entity);
        auto type = goap.type;

        sol::table goals = goap.def["goal_selectors"];
        sol::protected_function func = goals[type];
        if (!func.valid())
        {
            SPDLOG_ERROR("No goal selector found for type '{}'", type);
            return;
        }

        auto result = util::safeLuaCall(func, "ai goal selection", entity);
        if (result.isErr())
        {
            SPDLOG_ERROR("Goal selection failed: {}", result.error());
            return;
        }

        replan(entity);
    }

    [[deprecated("Use select_goal(registry, entity) instead")]]
    void select_goal(entt::entity entity)
    {
        select_goal(globals::getRegistry(), entity);
    }

    // Execute the current action in the plan
    // returns false if a replan is required
    bool execute_current_action(entt::entity entity)
    {
        // just call update on action queue, assuming nothing has changed in the world state
        auto result = run_action_queue(entity, aiUpdateTickInSeconds); // std::optional value

        // if this value is failure, it may mean the action is being retried.
        // std::nullopt is the only indicator of replan required

        if (!result)
        {                 // std::nullopt means replan is required
            return false; // replan required
        }

        return true; // actions are running as intended
    }

    /**
     * Updates the current action in the GOAPComponent.
     *
     * @param goapComponent The GOAPComponent containing the action queue.
     * @param deltaTime The time elapsed since the last update.
     * @return The result of the action. Empty if action queue is invalid or only start() was called, otherwise the result of the action from running the update() method. Empty return (std::nullopt) indicates that the plan must be re-planned.
     */
    std::optional<Action::Result> run_action_queue(entt::entity entity, float deltaTime)
    {
        auto &goapComponent = globals::getRegistry().get<GOAPComponent>(entity);

        if (goapComponent.actionQueue.empty())
        {
            // SPDLOG_DEBUG("Action queue is empty");
            return std::nullopt;
        }

        Action &currentAction = goapComponent.actionQueue.front();
        if (!currentAction.is_running)
        {
            // SPDLOG_DEBUG("Current action is not running");
            return std::nullopt;
        }

        // // turn into isolated coroutine
        // goapComponent.currentUpdateCoroutine = currentAction.update;

        // // we run update() as a coroutine to let it call methods like wait(i)
        // sol::coroutine &updateCoroutine = goapComponent.currentUpdateCoroutine;

        // coroutine can return an action result or simply yield.
        auto luaResult = currentAction.update(entity, deltaTime);
        if (luaResult.valid() == false)
        {
            // An error has occured
            sol::error err = luaResult;
            std::string what = err.what();
            SPDLOG_ERROR("Return value error in action update: {}", what);
        }

        // if the coroutine has yielded, return running
        if (luaResult.status() == sol::call_status::yielded)
        {
            // SPDLOG_DEBUG("Action {} is still running (yielded)", goapComponent.plan[goapComponent.current_action]);
            return Action::Result::RUNNING;
        }

        // coroutine has not yielded, get result value

        Action::Result result = luaResult.get<Action::Result>();

        // // … after checking for yield …
        // int returns = luaResult.return_count();
        // Action::Result result;

        // // no explicit return → assume SUCCESS
        // if (returns == 0) {
        //     result = Action::Result::SUCCESS;
        //     SPDLOG_DEBUG("Action {} completed successfully", goapComponent.plan[goapComponent.current_action]);
        // } else {
        //     // peek at what’s on the stack
        //     sol::object ret = luaResult.get<sol::object>(1);
        //     if (ret.get_type() == sol::type::number) {
        //         result = ret.as<Action::Result>();
        //     } else {
        //         SPDLOG_ERROR(
        //         "Action update returned {} values but first isn't a number; treating as FAILURE",
        //         returns);
        //         result = Action::Result::FAILURE;
        //     }
        // }

        // move on to next action if current action is successful
        if (result == Action::Result::SUCCESS)
        {
            // SPDLOG_DEBUG("Action {} completed, calling start() on next action", goapComponent.plan[goapComponent.current_action]);

            auto finishResult = util::safeLuaCall(currentAction.finish, "ai action finish", entity);
            if (finishResult.isErr()) {
                SPDLOG_ERROR("AI finish() failed: {}", finishResult.error());
            }
            goapComponent.actionQueue.pop();

            // Reset retries on success
            goapComponent.retries = 0;

            // set postconditions
            auto postConditions = allPostconditionsForEveryAction[goapComponent.plan[goapComponent.current_action]];
            for (const auto &postCondition : postConditions)
            {
                const std::string post_key = postCondition.first;
                const bool post_value = postCondition.second;
                goap_worldstate_set(&goapComponent.ap, &goapComponent.current_state, post_key.c_str(), post_value);
                SPDLOG_DEBUG("Automatically setting postcondition {} to {}", post_key, post_value);
            }

            // Move to the next action
            goapComponent.current_action++;

            // run next action start if available
            if (!goapComponent.actionQueue.empty())
            {
                auto startResult = util::safeLuaCall(goapComponent.actionQueue.front().start, "ai action start", entity);
                if (startResult.isErr()) {
                    SPDLOG_ERROR("AI start() failed: {}", startResult.error());
                }
                goapComponent.actionQueue.front().is_running = true;
            }
            else
            {
                // SPDLOG_DEBUG("Action queue is now empty");
                return std::nullopt; // this will force caller to replan
            }
        }
        // upon failure, retry X number of times by calling start() again
        else if (result == Action::Result::FAILURE)
        {
            goapComponent.retries++;
            if (goapComponent.retries >= goapComponent.max_retries)
            {
                // If retries exceed max_retries, re-plan
                // SPDLOG_DEBUG("Maximum retries exceeded, re-planning...");
                return std::nullopt; // this will force caller to replan
            }
            // SPDLOG_DEBUG("Action {} failed, retrying", goapComponent.plan[goapComponent.current_action]);
            // reset blackboard and rerun start REVIEW: re-attempting an action shouldn't reset the blackboard, right?
            // goapComponent.blackboard.clear();
            // goapComponent.blackboardInit(goapComponent.blackboard);
            goapComponent.actionQueue.front().start(entity);
        }
        else
        {
            // SPDLOG_DEBUG("Action {} is still running", goapComponent.plan[goapComponent.current_action]);
        }
        // let caller know the result of the action too
        return result;
    }

    // called when an entity's action is interrupted, replans the action queue
    // LATER: This should also be triggered (with replan) by events that interrupt the entities, after world state is also updated. When  an entity is interrupted, it should wait for a bit before replanning, for instance
    void on_interrupt(entt::entity entity)
    {
        auto &goapComponent = globals::getRegistry().get<GOAPComponent>(entity);

        if (!goapComponent.actionQueue.empty()) {
            Action& cur = goapComponent.actionQueue.front();
            if (cur.abort.valid()) {
                auto ar = util::safeLuaCall(cur.abort, "ai abort interrupt", entity, "interrupt");
                if (ar.isErr()) {
                    SPDLOG_ERROR("abort() error during interrupt: {}", ar.error());
                }
            }
        }

        while (!goapComponent.actionQueue.empty()) goapComponent.actionQueue.pop();

        runBlackboardInitFunction(entity, goapComponent.type);
        select_goal(entity);
    }


    // TODO: some method ideas: showTutorialMessageBox(), showTutorialHighlightCircle()

    void bind_ai_utilities(sol::state &lua)
    {
        auto &rec = BindingRecorder::instance();

        // 1) InputState usertype
        rec.add_type("ai");


        // 1) Create (or overwrite) the `ai` table:
        lua.create_named_table("ai"); // equivalent to lua["ai"] = {}
        sol::table ai = lua["ai"];

        // 1) Expose a getter that returns the entity’s AI-definition table:
        ai.set_function(
        "get_entity_ai_def",
        [](entt::entity e) -> sol::table {
            auto &cmp = globals::getRegistry().get<GOAPComponent>(e);
            return cmp.def;
        }
        );
        
        ai.set_function(
            "pause_ai_system",
            []() {
                ai_system_paused = true;
                SPDLOG_DEBUG("AI system paused.");
            });
            
        rec.record_method("ai", {
            "pause_ai_system",
            "---@param self ai\n"
            "---@return nil",
            "Pauses the AI system, preventing any updates or actions from being processed."
        });
        ai.set_function(
            "resume_ai_system",
            []() {
                ai_system_paused = false;
                SPDLOG_DEBUG("AI system resumed.");
            });
        rec.record_method("ai", {
            "resume_ai_system",
            "---@param self ai\n"
            "---@return nil",
            "Resumes the AI system after it has been paused."
        });
        // 2) Move each binding into ai:
        ai.set_function("set_worldstate", [](entt::entity e, std::string key, bool value)
                        {
            auto& goap = globals::getRegistry().get<GOAPComponent>(e);
            goap_worldstate_set(&goap.ap, &goap.current_state, key.c_str(), value); });
        
        // 3. Expose a getter for a single world-state flag:
        ai.set_function("get_worldstate",
            // we need to capture lua state in order to return sol::nil on error
            [&](sol::this_state L, entt::entity e, const std::string & key) -> sol::object {
            auto &goap = globals::getRegistry().get<GOAPComponent>(e);
            bool value = false;
            bool ok = goap_worldstate_get(&goap.ap,
                                            goap.current_state,
                                            key.c_str(),
                                            &value);
            if (!ok) {
                // atom not found or "dontcare" bit set → return nil
                return sol::make_object(L, sol::lua_nil);
            }
            // otherwise return the boolean
            return sol::make_object(L, value);
            }
        );

        ai.set_function("set_goal", [](entt::entity e, sol::table goal)
                        {
            auto& goap = globals::getRegistry().get<GOAPComponent>(e);
            goap_worldstate_clear(&goap.goal);
            for (auto& [k, v] : goal)
                goap_worldstate_set(&goap.ap, &goap.goal,
                                    k.as<std::string>().c_str(), v.as<bool>()); });

        // patch a single world‐state flag, without clearing anything else
        ai.set_function("patch_worldstate", [](entt::entity e, const std::string &key, bool value)
                        {
            auto& goap = globals::getRegistry().get<GOAPComponent>(e);
            // this will only set that one bit
            goap_worldstate_set(&goap.ap, &goap.current_state, key.c_str(), value); });

        // patch multiple goal flags, without clearing the whole goal first
        ai.set_function("patch_goal", [](entt::entity e, sol::table tbl)
                        {
            auto& goap = globals::getRegistry().get<GOAPComponent>(e);
            // leave existing goal bits alone, just set these ones
            for (auto& [k, v] : tbl) {
                std::string key = k.as<std::string>();
                bool        val = v.as<bool>();
                goap_worldstate_set(&goap.ap, &goap.goal, key.c_str(), val);
            } });

        sol::table bb = ai["bb"].get_or_create<sol::table>();
        bb.set_function("set", [](sol::object entityObj, const std::string &key, sol::object v) {
            auto &registry = globals::getRegistry();
            auto maybeEntity = resolve_entity(entityObj);
            if (!maybeEntity) {
                return;
            }
            entt::entity e = *maybeEntity;
            if (!registry.valid(e) || !registry.any_of<GOAPComponent>(e)) {
                return;
            }

            auto &blackboard = registry.get<GOAPComponent>(e).blackboard;
            if (v.is<bool>()) {
                blackboard.set(key, v.as<bool>());
                return;
            }
            if (v.is<std::string>()) {
                blackboard.set(key, v.as<std::string>());
                return;
            }
            if (v.get_type() == sol::type::number) {
                double num = v.as<double>();
                double intPart = 0.0;
                if (std::modf(num, &intPart) == 0.0 &&
                    num >= static_cast<double>(std::numeric_limits<int>::min()) &&
                    num <= static_cast<double>(std::numeric_limits<int>::max())) {
                    blackboard.set(key, static_cast<int>(num));
                } else {
                    blackboard.set(key, static_cast<float>(num));
                }
                return;
            }
            if (v.is<entt::entity>()) {
                blackboard.set(key, v.as<entt::entity>());
                return;
            }
            if (v.is<sol::table>()) {
                auto t = v.as<sol::table>();
                if (t["x"].valid() && t["y"].valid()) {
                    Vector2 pos{t.get_or("x", 0.0f), t.get_or("y", 0.0f)};
                    blackboard.set(key, pos);
                    return;
                }
            }
            SPDLOG_WARN("ai.bb.set: unsupported type for key '{}'", key);
        });

        bb.set_function("get", [](sol::this_state L, sol::object entityObj,
                                  const std::string &key, sol::object def) -> sol::object {
            auto &registry = globals::getRegistry();
            auto maybeEntity = resolve_entity(entityObj);
            if (!maybeEntity) {
                return sol::make_object(L, sol::lua_nil);
            }
            entt::entity e = *maybeEntity;
            if (!registry.valid(e) || !registry.any_of<GOAPComponent>(e)) {
                return sol::make_object(L, sol::lua_nil);
            }

            auto &blackboard = registry.get<GOAPComponent>(e).blackboard;
            if (!blackboard.contains(key)) {
                return def.valid() ? def : sol::make_object(L, sol::lua_nil);
            }

            if (!def.valid()) {
                try { return sol::make_object(L, blackboard.get<bool>(key)); } catch (...) {}
                try { return sol::make_object(L, blackboard.get<int>(key)); } catch (...) {}
                try { return sol::make_object(L, static_cast<double>(blackboard.get<float>(key))); } catch (...) {}
                try { return sol::make_object(L, blackboard.get<double>(key)); } catch (...) {}
                try { return sol::make_object(L, blackboard.get<std::string>(key)); } catch (...) {}
                try { return sol::make_object(L, blackboard.get<entt::entity>(key)); } catch (...) {}
                try {
                    auto p = blackboard.get<Vector2>(key);
                    sol::state_view sv(L);
                    sol::table out = sv.create_table();
                    out["x"] = p.x;
                    out["y"] = p.y;
                    return sol::make_object(L, out);
                } catch (...) {}
                return sol::make_object(L, sol::lua_nil);
            }

            try {
                if (def.is<bool>()) {
                    return sol::make_object(L, blackboard.get<bool>(key));
                }
                if (def.is<int>()) {
                    try { return sol::make_object(L, blackboard.get<int>(key)); } catch (...) {}
                    try { return sol::make_object(L, static_cast<double>(blackboard.get<float>(key))); } catch (...) {}
                    try { return sol::make_object(L, blackboard.get<double>(key)); } catch (...) {}
                    return def;
                }
                if (def.is<double>()) {
                    try { return sol::make_object(L, static_cast<double>(blackboard.get<float>(key))); } catch (...) {}
                    try { return sol::make_object(L, blackboard.get<double>(key)); } catch (...) {}
                    try { return sol::make_object(L, static_cast<double>(blackboard.get<int>(key))); } catch (...) {}
                    return def;
                }
                if (def.is<std::string>()) {
                    return sol::make_object(L, blackboard.get<std::string>(key));
                }
                if (def.is<entt::entity>()) {
                    try { return sol::make_object(L, blackboard.get<entt::entity>(key)); } catch (...) {}
                    try { return sol::make_object(L, static_cast<entt::entity>(blackboard.get<int>(key))); } catch (...) {}
                    return def;
                }
                if (def.is<sol::table>()) {
                    auto p = blackboard.get<Vector2>(key);
                    sol::state_view sv(L);
                    sol::table out = sv.create_table();
                    out["x"] = p.x;
                    out["y"] = p.y;
                    return sol::make_object(L, out);
                }
            } catch (...) {
                return def;
            }

            return def;
        });

        bb.set_function("has", [](sol::object entityObj, const std::string &key) -> bool {
            auto &registry = globals::getRegistry();
            auto maybeEntity = resolve_entity(entityObj);
            if (!maybeEntity) {
                return false;
            }
            entt::entity e = *maybeEntity;
            if (!registry.valid(e) || !registry.any_of<GOAPComponent>(e)) {
                return false;
            }
            return registry.get<GOAPComponent>(e).blackboard.contains(key);
        });

        bb.set_function("clear", [](sol::object entityObj) {
            auto &registry = globals::getRegistry();
            auto maybeEntity = resolve_entity(entityObj);
            if (!maybeEntity) {
                return;
            }
            entt::entity e = *maybeEntity;
            if (!registry.valid(e) || !registry.any_of<GOAPComponent>(e)) {
                return;
            }
            registry.get<GOAPComponent>(e).blackboard.clear();
        });

        bb.set_function("set_vec2", [](sol::object entityObj, const std::string &key, sol::table pos) {
            auto &registry = globals::getRegistry();
            auto maybeEntity = resolve_entity(entityObj);
            if (!maybeEntity) {
                return;
            }
            entt::entity e = *maybeEntity;
            if (!registry.valid(e) || !registry.any_of<GOAPComponent>(e)) {
                return;
            }
            Vector2 p{pos.get_or("x", 0.0f), pos.get_or("y", 0.0f)};
            registry.get<GOAPComponent>(e).blackboard.set(key, p);
        });

        bb.set_function("get_vec2", [](sol::this_state L, sol::object entityObj, const std::string &key) -> sol::object {
            auto &registry = globals::getRegistry();
            auto maybeEntity = resolve_entity(entityObj);
            if (!maybeEntity) {
                return sol::make_object(L, sol::lua_nil);
            }
            entt::entity e = *maybeEntity;
            if (!registry.valid(e) || !registry.any_of<GOAPComponent>(e)) {
                return sol::make_object(L, sol::lua_nil);
            }
            auto &blackboard = registry.get<GOAPComponent>(e).blackboard;
            if (!blackboard.contains(key)) {
                return sol::make_object(L, sol::lua_nil);
            }
            try {
                auto p = blackboard.get<Vector2>(key);
                sol::state_view sv(L);
                sol::table out = sv.create_table();
                out["x"] = p.x;
                out["y"] = p.y;
                return sol::make_object(L, out);
            } catch (...) {
                return sol::make_object(L, sol::lua_nil);
            }
        });

        bb.set_function("inc", [](sol::object entityObj, const std::string &key,
                                  float delta, sol::optional<float> def) -> float {
            auto &registry = globals::getRegistry();
            auto maybeEntity = resolve_entity(entityObj);
            if (!maybeEntity) {
                return 0.0f;
            }
            entt::entity e = *maybeEntity;
            if (!registry.valid(e) || !registry.any_of<GOAPComponent>(e)) {
                return 0.0f;
            }
            auto &blackboard = registry.get<GOAPComponent>(e).blackboard;

            auto read_number = [&](float fallback) -> float {
                if (!blackboard.contains(key)) {
                    return fallback;
                }
                try { return blackboard.get<float>(key); } catch (...) {}
                try { return static_cast<float>(blackboard.get<double>(key)); } catch (...) {}
                try { return static_cast<float>(blackboard.get<int>(key)); } catch (...) {}
                return fallback;
            };

            float current = read_number(def.value_or(0.0f));
            float newVal = current + delta;
            blackboard.set(key, newVal);
            return newVal;
        });

        bb.set_function("decay", [](sol::object entityObj, const std::string &key,
                                    float rate, float dt, sol::optional<float> def) -> float {
            auto &registry = globals::getRegistry();
            auto maybeEntity = resolve_entity(entityObj);
            if (!maybeEntity) {
                return 0.0f;
            }
            entt::entity e = *maybeEntity;
            if (!registry.valid(e) || !registry.any_of<GOAPComponent>(e)) {
                return 0.0f;
            }
            auto &blackboard = registry.get<GOAPComponent>(e).blackboard;

            auto read_number = [&](float fallback) -> float {
                if (!blackboard.contains(key)) {
                    return fallback;
                }
                try { return blackboard.get<float>(key); } catch (...) {}
                try { return static_cast<float>(blackboard.get<double>(key)); } catch (...) {}
                try { return static_cast<float>(blackboard.get<int>(key)); } catch (...) {}
                return fallback;
            };

            float current = read_number(def.value_or(0.0f));
            float newVal = current * std::exp(-rate * dt);
            blackboard.set(key, newVal);
            return newVal;
        });

        sol::table sense = ai["sense"].get_or_create<sol::table>();
        sense.set_function("position", [](sol::this_state L, sol::object entityObj) -> sol::object {
            auto &registry = globals::getRegistry();
            auto pos = extract_position(registry, entityObj);
            if (!pos) {
                return sol::make_object(L, sol::lua_nil);
            }
            sol::state_view sv(L);
            sol::table out = sv.create_table();
            out["x"] = pos->x;
            out["y"] = pos->y;
            return sol::make_object(L, out);
        });

        sense.set_function("distance", [](sol::this_state L, sol::object a, sol::object b) -> float {
            auto &registry = globals::getRegistry();
            auto pa = extract_position(registry, a);
            auto pb = extract_position(registry, b);
            if (!pa || !pb) {
                return std::numeric_limits<float>::infinity();
            }
            float dx = pb->x - pa->x;
            float dy = pb->y - pa->y;
            return std::sqrt(dx * dx + dy * dy);
        });

        sense.set_function("nearest", [](sol::this_state L, sol::object selfObj, float radius,
                                         sol::optional<sol::table> opts) -> sol::variadic_results {
            sol::variadic_results results;
            auto &registry = globals::getRegistry();

            auto maybeSelf = resolve_entity(selfObj);
            if (!maybeSelf) {
                results.push_back(sol::make_object(L, sol::lua_nil));
                return results;
            }
            entt::entity self = *maybeSelf;

            auto selfPos = extract_position(registry, selfObj);
            if (!selfPos) {
                results.push_back(sol::make_object(L, sol::lua_nil));
                return results;
            }

            sol::optional<sol::function> filter;
            if (opts && opts->valid()) {
                filter = opts->get<sol::function>("filter");
            }
            int scanLimit = opts ? opts->get_or("scan_limit", std::numeric_limits<int>::max()) : std::numeric_limits<int>::max();

            float bestDistSq = radius * radius;
            entt::entity bestEntity = entt::null;

            int considered = 0;
            auto consider = [&](entt::entity e) {
                if (e == self) return;
                if (++considered > scanLimit) return;

                auto otherPos = extract_position(registry, sol::make_object(L, e));
                if (!otherPos) return;

                float dx = otherPos->x - selfPos->x;
                float dy = otherPos->y - selfPos->y;
                float distSq = dx * dx + dy * dy;
                if (distSq >= bestDistSq) return;

                if (filter && filter->valid()) {
                    sol::protected_function pf = *filter;
                    auto res = pf(e);
                    if (!res.valid() || !res.get<bool>()) {
                        return;
                    }
                }

                bestDistSq = distSq;
                bestEntity = e;
            };

            auto viewTransform = registry.view<transform::Transform>();
            for (auto e : viewTransform) {
                if (considered >= scanLimit) break;
                consider(e);
            }

            auto viewLocation = registry.view<LocationComponent>(entt::exclude<transform::Transform>);
            for (auto e : viewLocation) {
                if (considered >= scanLimit) break;
                consider(e);
            }

            if (bestEntity != entt::null) {
                results.push_back(sol::make_object(L, bestEntity));
                results.push_back(sol::make_object(L, std::sqrt(bestDistSq)));
            } else {
                results.push_back(sol::make_object(L, sol::lua_nil));
            }
            return results;
        });

        sense.set_function("all_in_range", [](sol::this_state L, sol::object selfObj, float radius,
                                              sol::optional<sol::table> opts) -> sol::table {
            auto &registry = globals::getRegistry();
            sol::state_view sv(L);
            sol::table out = sv.create_table();

            auto maybeSelf = resolve_entity(selfObj);
            if (!maybeSelf) return out;
            entt::entity self = *maybeSelf;

            auto selfPos = extract_position(registry, selfObj);
            if (!selfPos) return out;

            sol::optional<sol::function> filter;
            if (opts && opts->valid()) {
                filter = opts->get<sol::function>("filter");
            }
            int maxReturn = opts ? opts->get_or("max", 32) : 32;
            int scanLimit = opts ? opts->get_or("scan_limit", std::numeric_limits<int>::max()) : std::numeric_limits<int>::max();

            float r2 = radius * radius;
            int considered = 0;
            int added = 0;

            auto consider = [&](entt::entity e) {
                if (e == self) return;
                if (++considered > scanLimit) return;
                if (added >= maxReturn) return;

                auto otherPos = extract_position(registry, sol::make_object(L, e));
                if (!otherPos) return;

                float dx = otherPos->x - selfPos->x;
                float dy = otherPos->y - selfPos->y;
                float distSq = dx * dx + dy * dy;
                if (distSq > r2) return;

                if (filter && filter->valid()) {
                    sol::protected_function pf = *filter;
                    auto res = pf(e);
                    if (!res.valid() || !res.get<bool>()) {
                        return;
                    }
                }

                out[++added] = e;
            };

            auto viewTransform = registry.view<transform::Transform>();
            for (auto e : viewTransform) {
                if (considered >= scanLimit || added >= maxReturn) break;
                consider(e);
            }

            auto viewLocation = registry.view<LocationComponent>(entt::exclude<transform::Transform>);
            for (auto e : viewLocation) {
                if (considered >= scanLimit || added >= maxReturn) break;
                consider(e);
            }

            return out;
        });

        // 3) Register the Blackboard usertype under ai:
        lua.new_usertype<Blackboard>("Blackboard",
                                     "set_bool", &Blackboard::set<bool>,
                                     "set_int", &Blackboard::set<int>,
                                     "set_double", &Blackboard::set<double>,
                                     "set_string", &Blackboard::set<std::string>,
                                     "set_float", &Blackboard::set<float>,
                                     "get_bool", &Blackboard::get<bool>,
                                     "get_int", &Blackboard::get<int>,
                                     "get_double", &Blackboard::get<double>,
                                     "get_float", &Blackboard::get<float>,
                                     "get_string", &Blackboard::get<std::string>,

                                     "contains", &Blackboard::contains,
                                     "clear", &Blackboard::clear,
                                     "size", &Blackboard::size,
                                     "isEmpty", &Blackboard::isEmpty);

        ai.set_function("get_blackboard", [](entt::entity e) -> Blackboard *
                        {
            auto &registry = globals::getRegistry();

            if (!registry.valid(e)) {
                SPDLOG_WARN("ai.get_blackboard called with invalid entity");
                return nullptr;
            }

            if (!registry.any_of<GOAPComponent>(e)) {
                SPDLOG_WARN("ai.get_blackboard called for entity {} without GOAPComponent", static_cast<int>(e));
                return nullptr;
            }

            return &registry.get<GOAPComponent>(e).blackboard;
        });

        lua.set_function("create_ai_entity",
                         sol::overload(
                             [&](const std::string &type)
                             {
                                 auto e = transform::CreateOrEmplace(
                                     &globals::getRegistry(),
                                     globals::getGameWorldContainer(),
                                     0, 0, 50, 50);
                                 globals::getRegistry().emplace<GOAPComponent>(e);
                                 initGOAPComponent(e, type, sol::nullopt);
                                 return e;
                             },
                             [&](const std::string &type, sol::table overrides)
                             {
                                 auto e = transform::CreateOrEmplace(
                                     &globals::getRegistry(),
                                     globals::getGameWorldContainer(),
                                     0, 0, 50, 50);
                                 globals::getRegistry().emplace<GOAPComponent>(e);
                                 initGOAPComponent(e, type, overrides);
                                 return e;
                             }));

        lua.set_function("create_ai_entity_with_overrides",
                         [&](const std::string &type, sol::table overrides)
                         {
                             auto e = transform::CreateOrEmplace(
                                 &globals::getRegistry(),
                                globals::getGameWorldContainer(),
                                 0, 0, 50, 50);
                             globals::getRegistry().emplace<GOAPComponent>(e);
                             initGOAPComponent(e, type, overrides);
                             return e;
                         });

        //

        ai.set_function("force_interrupt", [](entt::entity e)
                        { ai_system::on_interrupt(e); });

        ai.set_function("list_lua_files", [](const std::string &dir)
                        {
                            std::string rel = dir;
                            std::replace(rel.begin(), rel.end(), '.', '/');
                            std::filesystem::path scriptDir =
                                std::filesystem::path(util::getRawAssetPathNoUUID("scripts")) / rel;

                            std::vector<std::string> result;
                            for (auto &entry : std::filesystem::directory_iterator(scriptDir))
                            {
                                if (entry.path().extension() == ".lua")
                                    result.push_back(entry.path().stem().string());
                            }
                            return result; // Sol2 → Lua table
                        });

        
        // 2) Record it in your BindingRecorder:
        rec.record_method("ai", {
        "get_entity_ai_def",
        "---@param e Entity\n"
        "---@return table # The Lua AI-definition table (with entity_types, actions, goal_selectors, etc.)",
        "Returns the mutable AI-definition table for the given entity."
        });

        rec.record_method("ai", {"set_worldstate",
                                 "---@param e Entity\n"
                                 "---@param key string\n"
                                 "---@param value boolean\n"
                                 "---@return nil",
                                 "Sets a single world-state flag on the entity’s current state."});
                                 
        rec.record_method("ai", {
        "get_worldstate",
        "---@param e Entity\n"
        "---@param key string\n"
        "---@return boolean|nil",
        "Retrieves the value of a single world-state flag from the entity’s current state; returns nil if the flag is not set or is marked as 'don't care'."
    });

        rec.record_method("ai", {"set_goal",
                                 "---@param e Entity\n"
                                 "---@param goal table<string,boolean>\n"
                                 "---@return nil",
                                 "Clears existing goal and assigns new goal flags for the entity."});

        rec.record_method("ai", {"patch_worldstate",
                                 "---@param e Entity\n"
                                 "---@param key string\n"
                                 "---@param value boolean\n"
                                 "---@return nil",
                                 "Patches one world-state flag without resetting other flags."});

        rec.record_method("ai", {"patch_goal",
                                 "---@param e Entity\n"
                                 "---@param tbl table<string,boolean>\n"
                                 "---@return nil",
                                 "Patches multiple goal flags without clearing the current goal."});

        rec.record_method("ai.bb", {"set",
                                    "---@param e Entity\n"
                                    "---@param key string\n"
                                    "---@param value any\n"
                                    "---@return nil",
                                    "Sets a blackboard value with basic type inference."});
        rec.record_method("ai.bb", {"get",
                                    "---@param e Entity\n"
                                    "---@param key string\n"
                                    "---@param default? any\n"
                                    "---@return any|nil",
                                    "Gets a blackboard value; uses default for type selection and fallback."});
        rec.record_method("ai.bb", {"has",
                                    "---@param e Entity\n"
                                    "---@param key string\n"
                                    "---@return boolean",
                                    "Returns true if the blackboard contains the key."});
        rec.record_method("ai.bb", {"clear",
                                    "---@param e Entity\n"
                                    "---@return nil",
                                    "Clears all blackboard entries for the entity."});
        rec.record_method("ai.bb", {"set_vec2",
                                    "---@param e Entity\n"
                                    "---@param key string\n"
                                    "---@param pos table{x:number,y:number}\n"
                                    "---@return nil",
                                    "Stores a Vector2-like position in the blackboard."});
        rec.record_method("ai.bb", {"get_vec2",
                                    "---@param e Entity\n"
                                    "---@param key string\n"
                                    "---@return table{x:number,y:number}|nil",
                                    "Reads a Vector2-like position from the blackboard."});
        rec.record_method("ai.bb", {"inc",
                                    "---@param e Entity\n"
                                    "---@param key string\n"
                                    "---@param delta number\n"
                                    "---@param default? number\n"
                                    "---@return number",
                                    "Increments a numeric blackboard value and returns the new value."});
        rec.record_method("ai.bb", {"decay",
                                    "---@param e Entity\n"
                                    "---@param key string\n"
                                    "---@param rate number\n"
                                    "---@param dt number\n"
                                    "---@param default? number\n"
                                    "---@return number",
                                    "Decays a numeric blackboard value toward zero."});

        rec.record_method("ai.sense", {"position",
                                       "---@param e Entity\n"
                                       "---@return table{x:number,y:number}|nil",
                                       "Returns the entity position as a table with x/y, or nil if unavailable."});
        rec.record_method("ai.sense", {"distance",
                                       "---@param a Entity|table{x:number,y:number}\n"
                                       "---@param b Entity|table{x:number,y:number}\n"
                                       "---@return number",
                                       "Returns the distance between two entities or positions."});
        rec.record_method("ai.sense", {"nearest",
                                       "---@param e Entity\n"
                                       "---@param radius number\n"
                                       "---@param opts? table\n"
                                       "---@return Entity|nil, number|nil",
                                       "Finds the nearest entity within radius and returns it with distance."});
        rec.record_method("ai.sense", {"all_in_range",
                                       "---@param e Entity\n"
                                       "---@param radius number\n"
                                       "---@param opts? table\n"
                                       "---@return Entity[]",
                                       "Returns all entities within radius (bounded by opts.max if provided)."});

        rec.record_method("ai", {"get_blackboard",
                                 "---@param e Entity\n"
                                 "---@return Blackboard|nil",
                                 "Returns the entity’s Blackboard component if present; nil otherwise."});

        rec.record_method("ai", {"create_ai_entity",
                                 "---@param type string\n"
                                 "---@param overrides table<string,any>?\n"
                                 "---@return Entity",
                                 "Creates a new GOAP entity of the given type, applying optional AI overrides."});

        rec.record_method("ai", {"force_interrupt",
                                 "---@param e Entity\n"
                                 "---@return nil",
                                 "Immediately interrupts the entity’s current GOAP action."});

        rec.record_method("ai", {"list_lua_files",
                                 "---@param dir string\n"
                                 "---@return string[]",
                                 "Returns a list of Lua script filenames (without extensions) from the specified directory."});

        // Phase 1.2: Goal selection breakdown reporting
        ai.set_function("report_goal_selection",
            [](entt::entity e, const std::string& goal_name, const std::string& band,
               sol::optional<int> score, sol::optional<sol::table> candidates) {
                auto& registry = globals::getRegistry();
                if (!registry.valid(e) || !registry.any_of<GOAPComponent>(e)) {
                    SPDLOG_WARN("ai.report_goal_selection called for invalid entity or entity without GOAPComponent");
                    return;
                }

                auto& goap = registry.get<GOAPComponent>(e);
                uint32_t eid = static_cast<uint32_t>(e);

                // Record the goal selection event
                ai::trace_goal_selected(goap.trace_buffer, eid, goal_name, band,
                                        score.value_or(0));

                // If candidates table is provided, log extra debug info
                if (candidates) {
                    std::string candidate_info;
                    for (auto& [k, v] : candidates.value()) {
                        if (v.get_type() == sol::type::table) {
                            sol::table c = v.as<sol::table>();
                            std::string cid = c.get_or("id", std::string("?"));
                            std::string cband = c.get_or("band", std::string("?"));
                            double cpre = c.get_or("pre", 0.0);
                            if (!candidate_info.empty()) candidate_info += ", ";
                            candidate_info += cid + "(" + cband + ":" +
                                              std::to_string(static_cast<int>(cpre * 100)) + "%)";
                        }
                    }
                    if (!candidate_info.empty()) {
                        SPDLOG_DEBUG("Goal selection for entity {}: {} candidates: {}",
                                     eid, goal_name, candidate_info);
                    }
                }
            });

        rec.record_method("ai", {"report_goal_selection",
                                 "---@param e Entity\n"
                                 "---@param goal_name string\n"
                                 "---@param band string\n"
                                 "---@param score integer?\n"
                                 "---@param candidates table?\n"
                                 "---@return nil",
                                 "Reports a goal selection to the AI trace buffer for debugging."});

        // Phase 1.2: Get trace buffer contents for debugging
        ai.set_function("get_trace_events",
            [&](sol::this_state L, entt::entity e, sol::optional<int> count) -> sol::object {
                auto& registry = globals::getRegistry();
                if (!registry.valid(e) || !registry.any_of<GOAPComponent>(e)) {
                    return sol::make_object(L, sol::lua_nil);
                }

                auto& goap = registry.get<GOAPComponent>(e);
                size_t n = count.value_or(10);
                auto events = goap.trace_buffer.get_recent(n);

                sol::table result = sol::state_view(L).create_table();
                int idx = 1;
                for (const auto& event : events) {
                    sol::table entry = sol::state_view(L).create_table();
                    entry["type"] = ai::trace_event_type_name(event.type);
                    entry["message"] = event.message;
                    entry["timestamp"] = event.timestamp;
                    entry["entity_id"] = event.entity_id;

                    // Include extra_data if present
                    if (!event.extra_data.empty()) {
                        sol::table extra = sol::state_view(L).create_table();
                        for (const auto& [k, v] : event.extra_data) {
                            extra[k] = v;
                        }
                        entry["extra_data"] = extra;
                    }

                    result[idx++] = entry;
                }
                return sol::make_object(L, result);
            });

        rec.record_method("ai", {"get_trace_events",
                                 "---@param e Entity\n"
                                 "---@param count integer?\n"
                                 "---@return table[]|nil",
                                 "Returns the most recent trace events for the entity (default 10)."});

        // Phase 1.2: Clear trace buffer
        ai.set_function("clear_trace",
            [](entt::entity e) {
                auto& registry = globals::getRegistry();
                if (!registry.valid(e) || !registry.any_of<GOAPComponent>(e)) {
                    return;
                }
                auto& goap = registry.get<GOAPComponent>(e);
                goap.trace_buffer.clear();
            });

        rec.record_method("ai", {"clear_trace",
                                 "---@param e Entity\n"
                                 "---@return nil",
                                 "Clears the entity's AI trace buffer."});

        // Phase 1.3: List all entities with GOAPComponent for AI inspector
        ai.set_function("list_goap_entities",
            [&](sol::this_state L) -> sol::object {
                sol::state_view lua(L);
                auto& registry = globals::getRegistry();
                auto view = registry.view<GOAPComponent>();

                sol::table result = lua.create_table();
                int idx = 1;
                for (auto entity : view) {
                    result[idx++] = entity;
                }
                return result;
            });

        rec.record_method("ai", {"list_goap_entities",
                                 "---@return Entity[]\n",
                                 "Returns a list of all entities with GOAPComponent."});

        // Phase 1.3: Get GOAP state summary for AI inspector
        ai.set_function("get_goap_state",
            [&](sol::this_state L, entt::entity e) -> sol::object {
                sol::state_view lua(L);
                auto& registry = globals::getRegistry();
                if (!registry.valid(e) || !registry.any_of<GOAPComponent>(e)) {
                    return sol::make_object(L, sol::lua_nil);
                }

                auto& goap = registry.get<GOAPComponent>(e);
                sol::table result = lua.create_table();

                // Basic state info
                result["type"] = goap.type;
                result["dirty"] = goap.dirty;
                result["plan_size"] = goap.planSize;
                result["current_action_idx"] = goap.current_action;
                result["retries"] = goap.retries;
                result["max_retries"] = goap.max_retries;

                // Current plan (array of action names)
                sol::table plan = lua.create_table();
                for (int i = 0; i < goap.planSize && i < 64; ++i) {
                    if (goap.plan[i]) {
                        plan[i + 1] = goap.plan[i];
                    }
                }
                result["plan"] = plan;

                // Current action being executed
                if (!goap.actionQueue.empty()) {
                    result["current_action"] = goap.actionQueue.front().name;
                    result["action_running"] = goap.actionQueue.front().is_running;
                } else {
                    result["current_action"] = sol::make_object(L, sol::lua_nil);
                    result["action_running"] = false;
                }

                // Action queue size
                result["queue_size"] = goap.actionQueue.size();

                // World state atoms
                sol::table atoms = lua.create_table();
                for (int i = 0; i < goap.ap.numatoms; ++i) {
                    if (goap.ap.atm_names[i]) {
                        sol::table atom = lua.create_table();
                        atom["name"] = goap.ap.atm_names[i];

                        // Current state value
                        bool isDontCare = (goap.current_state.dontcare & (1LL << i)) != 0;
                        if (isDontCare) {
                            atom["current"] = "dontcare";
                        } else {
                            atom["current"] = ((goap.current_state.values & (1LL << i)) != 0);
                        }

                        // Goal value
                        bool goalDontCare = (goap.goal.dontcare & (1LL << i)) != 0;
                        if (goalDontCare) {
                            atom["goal"] = "dontcare";
                        } else {
                            atom["goal"] = ((goap.goal.values & (1LL << i)) != 0);
                        }

                        atoms[i + 1] = atom;
                    }
                }
                result["atoms"] = atoms;
                result["num_atoms"] = goap.ap.numatoms;

                // Current goal from blackboard (using std::any storage)
                if (goap.blackboard.contains("current_goal")) {
                    try {
                        result["current_goal"] = goap.blackboard.get<std::string>("current_goal");
                    } catch (...) {
                        result["current_goal"] = sol::make_object(L, sol::lua_nil);
                    }
                } else {
                    result["current_goal"] = sol::make_object(L, sol::lua_nil);
                }

                // Versioning info
                result["actionset_version"] = goap.actionset_version;
                result["atom_schema_version"] = goap.atom_schema_version;

                return result;
            });

        rec.record_method("ai", {"get_goap_state",
                                 "---@param e Entity\n"
                                 "---@return table|nil\n",
                                 "Returns a table with GOAP state info for debugging, or nil if entity has no GOAPComponent."});
    }

    // Update the GOAP logic within the game loop
    void update_goap(entt::entity entity)
    {

        // check if reset of all GOAP components and lua state is requested
        if (resetGOAPAndLuaStateRequested)
        {
            resetAllGOAPComponentsAndScripting();
            resetGOAPAndLuaStateRequested = false;
        }

        auto &goapStruct = globals::getRegistry().get<GOAPComponent>(entity);

        // Execute the current action and check if it succeeded
        bool plan_is_running_valid = execute_current_action(entity);
        bool is_goap_info_valid = goap_is_goapstruct_valid(goapStruct);

        // Phase 0.1 fix: Snapshot state AFTER action execution but BEFORE updaters
        // This allows us to distinguish action postcondition changes from updater changes
        worldstate_t state_after_action = goapStruct.current_state;

        runWorldStateUpdaters(goapStruct, entity);

        // Check if re-planning is necessary based on action failure or mismatch with expected state / plan is empty
        if (is_goap_info_valid == false && plan_is_running_valid == false)
        { // plan might be running one action, but plan can be empty otherwise
            SPDLOG_DEBUG("GOAP plan is empty, re-selecting goal...");
            select_goal(entity);
        }
        // if plan is running, but the world state has changed since the plan was made, then replan
        else if ((plan_is_running_valid && goapStruct.current_action < goapStruct.planSize))
        {
            // Phase 0.1 fix: Only detect changes from world state updaters, not from action postconditions
            // This prevents spurious replans when an action legitimately changes watched atoms
            bfield_t changed = ai::compute_replan_changed_bits(
                state_after_action, goapStruct.current_state, goapStruct.cached_current_state);

            bool should_replan = false;

            if (!goapStruct.actionQueue.empty()) {
                Action& cur = goapStruct.actionQueue.front();

                // Only react if this action actually cares about the changed atoms
                if ((changed & cur.watchMask) != 0) {
                    should_replan = true;

                    // your existing debug dump of states
                    SPDLOG_DEBUG("World state has changed, re-planning required...");
                    char desc[4096];
                    goap_worldstate_description(&goapStruct.ap, &goapStruct.current_state, desc, sizeof(desc));
                    SPDLOG_DEBUG("Current world state: {}", desc);
                    goap_worldstate_description(&goapStruct.ap, &goapStruct.cached_current_state, desc, sizeof(desc));
                    SPDLOG_DEBUG("Cached current state: {}", desc);

                    // Optional: call the per-action abort hook BEFORE dropping the plan
                    if (cur.abort.valid()) {
                        SPDLOG_DEBUG("Invoking abort() for action '{}' on entity {}", cur.name, (int)entity);
                        auto ar = util::safeLuaCall(cur.abort, "ai abort worldstate_changed", entity, "worldstate_changed");
                        if (ar.isErr()) {
                            SPDLOG_ERROR("abort() error: {}", ar.error());
                        }
                    }
                }
            } else {
                // No action running → up to you; commonly, don’t knee-jerk replan,
                // but if you want full reactivity here, use:
                // should_replan = (changed != 0);
            }

            if (should_replan) {
                SPDLOG_DEBUG("Reactive replan (masked): worldstate changed on watched bits.");
                select_goal(entity); // queues fresh plan
            }
        }

        // the plan is no longer valid (running actions encountered an error)
        else if (plan_is_running_valid == false)
        {
            // If the plan is not running, re-plan
            // SPDLOG_DEBUG("Plan is not running properly for entity {}, replanning...", static_cast<int>(entity));
            // char desc[4096];
            // goap_worldstate_description(&goapStruct.ap, &goapStruct.current_state, desc, sizeof(desc));
            // SPDLOG_DEBUG("Current world state: {}", desc);
            // // compare to next state
            // goap_worldstate_description(&goapStruct.ap, &goapStruct.cached_current_state, desc, sizeof(desc));
            // SPDLOG_DEBUG("Cached current state: {}", desc);
            select_goal(entity);
            // replan(entity);
        }

        // update cached state
        goapStruct.cached_current_state = goapStruct.current_state;

        // debug output of current plan and world state
        // debugPrintGOAPStruct(goapStruct);
    }

    // void runWorldStateUpdaters(entt::entity &entity)
    // {
    //     // update world state using the condition updaters
    //     std::string updateFunctionTable = globals::aiConfigJSON["worldstateUpdaterTable"].get<std::string>();

    //     sol::table worldstateUpdaterTable = masterStateLua[updateFunctionTable];

    //     // Iterate through the table and invoke each and every function
    //     for (auto &pair : worldstateUpdaterTable)
    //     {
    //         sol::object key = pair.first;    // key
    //         sol::object value = pair.second; // value (which should be a function)

    //         if (value.is<sol::function>() == false)
    //             continue;

    //         SPDLOG_DEBUG("Executing worldstate update function: {}", key.as<std::string>());
    //         sol::protected_function func = value.as<sol::function>();
    //         // Call the function in a protected manner
    //         sol::protected_function_result result = func(entity, aiUpdateTickInSeconds); // Call the Lua function
    //         // Check if the function call resulted in an error

    //         if (result.valid())
    //             continue;

    //         // Capture the error message
    //         sol::error err = result;
    //         std::string error_message = err.what();
    //         SPDLOG_DEBUG("Error executing worldstate update function: {}", error_message);
    //     }
    // }

    void runWorldStateUpdaters(GOAPComponent &comp, entt::entity &entity)
    {
        sol::table updaters = comp.def["worldstate_updaters"];
        for (auto &[k, v] : updaters)
        {
            if (!v.is<sol::function>())
                continue;
            sol::protected_function f = v;
            auto result = util::safeLuaCall(f, std::string("ai worldstate updater:") + k.as<std::string>(), entity, aiUpdateTickInSeconds);
            if (result.isErr())
            {
                SPDLOG_ERROR("Error in worldstate updater '{}': {}", k.as<std::string>(), result.error());
            }
        }
    }

    void debugPrintGOAPStruct(GOAPComponent &goapStruct)
    {
        char desc[4096];
        SPDLOG_DEBUG("(UPPERCASE=true, lowercase=false; default action cost=1)");
        SPDLOG_DEBUG("plancost = {}", goapStruct.planCost);
        goap_worldstate_description(&goapStruct.ap, &goapStruct.current_state, desc, sizeof(desc));
        SPDLOG_DEBUG("Initial worldstate {:<23}{}", "", desc);
        if (goapStruct.planSize == 0)
        {
            SPDLOG_DEBUG("No plan found");
            return;
        }
        SPDLOG_DEBUG("==PLAN START==");
        // output plan (if there is none, nothing will print)
        for (int i = 0; i < goapStruct.planSize && i < 16; ++i)
        {
            goap_worldstate_description(&goapStruct.ap, &goapStruct.states[i], desc, sizeof(desc));
            SPDLOG_DEBUG("{}: {:<20}{}", i, goapStruct.plan[i], desc);
        }
        SPDLOG_DEBUG("==PLAN END==");
    }

    /*
     * @brief Generates a map where the key is the atom name (string) and the value is its boolean state.
     * This function returns a std::map<std::string, bool> that describes the current world state.
     */
    std::map<std::string, bool> goap_worldstate_to_map(const actionplanner_t *ap, const worldstate_t *ws)
    {
        std::map<std::string, bool> result; // Map to store atom name and its boolean value

        for (int i = 0; i < MAXATOMS; ++i)
        {
            // If we care about this atom (dontcare flag is not set)
            if ((ws->dontcare & (1LL << i)) == 0LL)
            {
                const char *atomname = ap->atm_names[i];
                if (atomname == NULL)
                    continue; // Skip if atomname is null

                // Check if the value in the world state is set (true or false)
                bool value = (ws->values & (1LL << i)) != 0LL;

                // Insert the atom name and its value into the map
                result[atomname] = value;
            }
        }

        return result; // Return the map of atom names and their boolean values
    }

    /**
     * Replans the actions for the given GOAPComponent.
     *
     * @param goapStruct The GOAPComponent to replan.
     */
    void replan(entt::entity entity)
    {
        auto &goapStruct = globals::getRegistry().get<GOAPComponent>(entity);

        goapStruct.planSize = globals::MAX_ACTIONS;
        
        // SPIKE: Measure GOAP planning performance
        auto astar_start = std::chrono::high_resolution_clock::now();
        goapStruct.planCost = astar_plan(&goapStruct.ap, goapStruct.current_state, goapStruct.goal, goapStruct.plan, goapStruct.states, &goapStruct.planSize);
        auto astar_end = std::chrono::high_resolution_clock::now();
        auto astar_duration_us = std::chrono::duration_cast<std::chrono::microseconds>(astar_end - astar_start);
        SPDLOG_INFO("SPIKE: GOAP astar_plan took {:.3f}ms for entity {}", astar_duration_us.count() / 1000.0, static_cast<int>(entity));
        char desc[4096];
        goap_description(&goapStruct.ap, desc, sizeof(desc));
        // SPDLOG_DEBUG("replan() called for entity {}", static_cast<int>(entity));
        // SPDLOG_INFO("Action planner description: {}", desc);

        // SPDLOG_INFO("plancost = {}", goapStruct.planCost);
        if (goapStruct.planCost == 0)
        {
            SPDLOG_ERROR("No plan found for entity {}. Current world state does not match goal.", static_cast<int>(entity));
            // If no plan is found, we can try to reselect the goal or handle it
        }
        if (goapStruct.planCost > 0)
        {
            SPDLOG_INFO("PLAN FOUND: {} steps", goapStruct.planSize);
        }
        SPDLOG_DEBUG("Current world state for entity {}:", static_cast<int>(entity));
        goap_worldstate_description(&goapStruct.ap, &goapStruct.current_state, desc, sizeof(desc));
        SPDLOG_INFO("{:<23}{}", "", desc);
        
        char buf[512];
        goap_worldstate_description(&goapStruct.ap, &goapStruct.goal, buf, sizeof(buf));
        SPDLOG_DEBUG("Goal world state: {}", buf);
        
        if (goapStruct.planSize > 0)
        {
            SPDLOG_DEBUG("Plan steps:");
        }
        
        for (int i = 0; i < goapStruct.planSize && i < 16; ++i) {
            goap_worldstate_description(&goapStruct.ap, &goapStruct.states[i], desc, sizeof(desc));
            SPDLOG_INFO("step {}: {:<20}{}", i, goapStruct.plan[i], desc);
        }

        goapStruct.current_action = 0;
        goapStruct.retries = 0; // Reset retries after re-planning
        checkAndSetGOAPDirty(goapStruct, globals::MAX_ACTIONS);
        if (goapStruct.dirty == false)
        {
            // // clear and reinit the blackboard
            // runBlackboardInitFunction(entity, goapStruct.type); // FIXME: placeholder value, these should come from the entity type (file)

            fill_action_queue_based_on_plan(entity, goapStruct.plan, goapStruct.planSize);

            // Phase 0.2: Store the state when this plan was created, for drift detection
            goapStruct.plan_start_state = goapStruct.current_state;

            // update cached state
            goapStruct.cached_current_state = goapStruct.current_state;
        }
        else
        {
            SPDLOG_ERROR("Call to replan() produced no plan for entity {}.", static_cast<int>(entity));

            handle_no_plan(entity); // Call a function to handle this scenario
        }
    }

    /**
     * Phase 0.5: Replan for an explicit goal without invoking goal selectors.
     */
    void replan_to_goal(entt::entity entity, const worldstate_t& explicit_goal,
                        bool merge_with_current)
    {
        auto &goapStruct = globals::getRegistry().get<GOAPComponent>(entity);

        // Set the goal - either replace entirely or merge with current
        if (merge_with_current) {
            goapStruct.goal = ai::merge_goal_state(goapStruct.goal, explicit_goal);
        } else {
            goapStruct.goal = explicit_goal;
        }

        // Use the existing replan logic
        goapStruct.planSize = globals::MAX_ACTIONS;
        goapStruct.planCost = astar_plan(&goapStruct.ap, goapStruct.current_state, goapStruct.goal,
                                         goapStruct.plan, goapStruct.states, &goapStruct.planSize);

        if (goapStruct.planCost == 0)
        {
            SPDLOG_ERROR("replan_to_goal: No plan found for entity {}.", static_cast<int>(entity));
            char desc[4096];
            goap_worldstate_description(&goapStruct.ap, &goapStruct.current_state, desc, sizeof(desc));
            SPDLOG_DEBUG("Current state: {}", desc);
            goap_worldstate_description(&goapStruct.ap, &goapStruct.goal, desc, sizeof(desc));
            SPDLOG_DEBUG("Target goal: {}", desc);
        }
        else
        {
            SPDLOG_INFO("replan_to_goal: PLAN FOUND for entity {} ({} steps)", static_cast<int>(entity), goapStruct.planSize);
        }

        goapStruct.current_action = 0;
        goapStruct.retries = 0;
        checkAndSetGOAPDirty(goapStruct, globals::MAX_ACTIONS);

        if (goapStruct.dirty == false)
        {
            fill_action_queue_based_on_plan(entity, goapStruct.plan, goapStruct.planSize);
            goapStruct.plan_start_state = goapStruct.current_state;
            goapStruct.cached_current_state = goapStruct.current_state;
        }
        else
        {
            SPDLOG_ERROR("replan_to_goal: produced no plan for entity {}.", static_cast<int>(entity));
            handle_no_plan(entity);
        }
    }

    auto updateHumanAI(entt::registry& registry, float deltaTime) -> void
    {
        if (ai_system_paused) return;

        aiUpdateTickTotal += deltaTime;

        if (aiUpdateTickTotal < aiUpdateTickInSeconds)
            return;

        SPDLOG_DEBUG("---------- ai_system:: new goap ai tick ------------------");
        aiUpdateTickTotal = 0.0f;

        auto view = registry.view<GOAPComponent>();

        for (auto entity : view)
        {
            update_goap(entity);
        }
    }

    auto updateHumanAI(float deltaTime) -> void
    {
        updateHumanAI(globals::getRegistry(), deltaTime);
    }
}
