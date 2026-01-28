local task = require("task.task")
local timer = require("core.timer")
local component_cache = require("core.component_cache")
local entity_cache = require("core.entity_cache")
local Easing = require("util.easing")
local Node = require("monobehavior.behavior_script_v2")
local z_orders = require("core.z_orders")
-- local bit = require("bit") -- LuaJIT's bit library
-- local entity_cache = require("core.entity_cache")
-- local component_cache = require("core.component_cache")

--===========================================================================
-- STRICT MODE CONFIGURATION
--===========================================================================
-- Enable STRICT_MODE to get warnings when common operations fail silently.
-- This helps catch bugs during development without breaking production.
-- Set via: _G.STRICT_MODE = true (before requiring util.lua) or DEBUG_MODE
local STRICT_MODE = rawget(_G, "STRICT_MODE") or rawget(_G, "DEBUG_MODE") or false

--- Enable or disable strict mode at runtime
--- @param enabled boolean
function set_strict_mode(enabled)
    STRICT_MODE = enabled
    if enabled then
        log_info("[util] Strict mode ENABLED - nil returns will log warnings")
    end
end

--- Check if strict mode is currently enabled
--- @return boolean
function is_strict_mode()
    return STRICT_MODE
end

local function resolveEasing(name, defaultName)
    -- Safely grab an easing entry; fall back to a known good curve.
    if name and Easing[name] then
        return Easing[name]
    end
    if defaultName and Easing[defaultName] then
        return Easing[defaultName]
    end
    return Easing.linear
end




-- return the object lua table from an entt id
-- In strict mode, logs warnings when the entity is invalid or lacks ScriptComponent
function getScriptTableFromEntityID(eid)
    if not eid or eid == entt_null then
        if STRICT_MODE then
            log_warn(("[STRICT] getScriptTableFromEntityID: invalid entity id (%s)"):format(tostring(eid)))
        end
        return nil
    end
    if not entity_cache.valid(eid) then
        if STRICT_MODE then
            log_warn(("[STRICT] getScriptTableFromEntityID: entity %s is not valid"):format(tostring(eid)))
        end
        return nil
    end
    if not registry:has(eid, ScriptComponent) then
        if STRICT_MODE then
            log_warn(("[STRICT] getScriptTableFromEntityID: entity %s has no ScriptComponent"):format(tostring(eid)))
        end
        return nil
    end
    local scriptComp = component_cache.get(eid, ScriptComponent)
    return scriptComp.self
end

--- Safely get a script table, with optional warning on failure.
--- Use this when you expect the entity to have a script and want to log if it doesn't.
--- @param eid number Entity ID
--- @param warn_on_nil boolean? If true, logs a warning when script is not found (default: false)
--- @return table|nil The script table or nil
function safe_script_get(eid, warn_on_nil)
    -- Check for nil entity
    if not eid then
        if warn_on_nil then
            log_warn("safe_script_get: nil entity provided")
        end
        return nil
    end

    -- Validate entity exists in registry
    if registry and registry.valid then
        if not registry:valid(eid) then
            if warn_on_nil then
                log_warn(("safe_script_get: Invalid entity %s"):format(tostring(eid)))
            end
            return nil
        end
    end

    -- Try to get script table with pcall for extra safety
    local ok, script = pcall(getScriptTableFromEntityID, eid)
    if not ok or not script then
        if warn_on_nil then
            log_warn(("safe_script_get: Script table missing for entity %s"):format(tostring(eid)))
        end
        return nil
    end

    return script
end

--- Safely get a field from an entity's script table.
--- @param eid number Entity ID
--- @param field string Field name to retrieve
--- @param default any Default value if script or field is nil
--- @return any The field value or default
function script_field(eid, field, default)
    local script = safe_script_get(eid)
    if not script then return default end
    local value = script[field]
    if value == nil then return default end
    return value
end

--- Check if an entity has a valid script table.
--- @param eid number Entity ID
--- @return boolean True if entity has a script table
function has_script(eid)
    return safe_script_get(eid) ~= nil
end

--- Check if an entity is valid and active.
--- Consolidates the various entity validation patterns into one function.
--- @param eid number Entity ID
--- @return boolean True if entity is valid
function ensure_entity(eid)
    return eid and eid ~= entt_null and entity_cache.valid(eid)
end

--- Check if an entity is valid and has a script component.
--- @param eid number Entity ID
--- @return boolean True if entity is valid and has a script
function ensure_scripted_entity(eid)
    return ensure_entity(eid) and registry:has(eid, ScriptComponent)
end

--===========================================================================
-- STRICT COMPONENT ACCESS
--===========================================================================

--- Safely get a component with optional strict-mode warnings.
--- @param eid number Entity ID
--- @param comp_type any Component type (e.g., Transform)
--- @param context string? Optional context for error messages
--- @return any|nil The component or nil
function safe_component_get(eid, comp_type, context)
    if not ensure_entity(eid) then
        if STRICT_MODE then
            local ctx = context and (" in " .. context) or ""
            log_warn(("[STRICT] safe_component_get: invalid entity%s"):format(ctx))
        end
        return nil
    end
    local comp = component_cache.get(eid, comp_type)
    if not comp and STRICT_MODE then
        local ctx = context and (" in " .. context) or ""
        log_warn(("[STRICT] safe_component_get: component not found for entity %s%s"):format(tostring(eid), ctx))
    end
    return comp
end

--- Require a component - returns the component or throws an error.
--- Use when the component MUST exist (programming error if it doesn't).
--- @param eid number Entity ID
--- @param comp_type any Component type
--- @param context string? Optional context for error messages
--- @return any The component (never nil)
function require_component(eid, comp_type, context)
    local ctx = context and (" in " .. context) or ""
    assert(ensure_entity(eid), ("require_component: invalid entity%s"):format(ctx))
    local comp = component_cache.get(eid, comp_type)
    assert(comp, ("require_component: missing component for entity %s%s"):format(tostring(eid), ctx))
    return comp
end

--===========================================================================
-- COMPONENT ACCESS BEST PRACTICES
--===========================================================================
-- PREFERRED: Use component_cache.get() for cached, efficient access:
--   local transform = component_cache.get(entity, Transform)
--
-- AVOID: Using registry:get() directly (no caching, no validation):
--   local transform = registry:get(entity, Transform)  -- NOT RECOMMENDED
--
-- Use safe_component_get() when you're unsure if the component exists
-- Use require_component() when the component MUST exist (programming error if not)
--===========================================================================

-- Deprecation tracking for registry:get usage (opt-in)
local _registry_get_warned = {}

--- Wrapper around registry:get that logs deprecation warnings in strict mode.
--- Use this during migration to track direct registry:get usage.
--- @param eid number Entity ID
--- @param comp_type any Component type
--- @return any|nil The component
function deprecated_registry_get(eid, comp_type)
    if STRICT_MODE then
        local key = tostring(comp_type)
        if not _registry_get_warned[key] then
            log_warn(("[DEPRECATED] Use component_cache.get() instead of registry:get() for %s"):format(key))
            _registry_get_warned[key] = true
        end
    end
    return registry:get(eid, comp_type)
end

--- Smoothly step the camera toward a target to avoid big-jump jitter.
-- @param camName string   Name used with camera.Get(...)
-- @param tx      number   Target world X
-- @param ty      number   Target world Y
-- @param opts    table?   { increments, interval, tag, after }
--   - increments (int): how many steps (default 5)
--   - interval   (num): seconds between steps (default 0.01)
--   - tag        (str): timer tag to allow cancel/debounce (default "cam_step_<camName>")
--   - after    (func?): optional callback after the move finishes
function camera_smooth_pan_to(camName, tx, ty, opts)
    opts = opts or {}
    local increments = opts.increments or 2
    local interval   = opts.interval   or 0.005
    local tag        = opts.tag        or ("cam_step_" .. camName)

    local cam = camera.Get(camName)
    if not cam then
        log_error(("CameraUtils.step_move: camera '%s' not found"):format(camName))
        return false
    end

    -- Cancel any in-flight timer with the same tag to avoid overlap.
    if timer.cancel then timer.cancel(tag) end

    local cur = cam:GetActualTarget()
    local stepX = (tx - cur.x) / increments
    local stepY = (ty - cur.y) / increments

    -- Finalizer: ensure we land exactly on (tx, ty), then call user 'after' if provided.
    local function on_done()
        -- cam:SetActualTarget(tx, ty)
        if type(opts.after) == "function" then opts.after() end
    end
    
    -- log_debug(("camera_smooth_pan_to: Moving camera '%s' to (%f,%f) over %d steps every %f sec"):format(
    --     camName, tx, ty, increments, interval
    -- ))
    timer.every(
        interval,
        function()
            local c = cam:GetActualTarget()
            log_debug(("stepX=%f stepY=%f cur=(%f,%f)"):format(stepX, stepY, c.x, c.y))

            cam:SetActualTarget(c.x + stepX, c.y + stepY)
        end,
        increments,         -- repetitions
        false,              -- do not start immediately (matches your behavior)
        on_done,            -- after callback
        tag                 -- unique tag
    )
    
    -- log_debug(("Created timer '%s' | delay=%s | type=%s"):format(tag, tostring(interval), "every"))
    -- log_debug("Timer table contents after creating '%s':", tag)
    -- for k, v in pairs(timer.timers) do
    --     log_debug(" - %s (%s)", k, v.type)
    -- end

    return true
end


local function applyDurationVariance(seconds, variance)
    if not variance or variance <= 0 then return seconds end
    local factor = 1.0 + (math.random() * 2.0 - 1.0) * variance  -- random in [1 - v, 1 + v]
    return seconds * factor
end

---@param x number
---@param y number
---@param count integer
---@param seconds number
---@param opts table?
function particle.spawnRadialParticles(x, y, count, seconds, opts)
    opts = opts or {}

    local easing          = resolveEasing(opts.easing, "cubic")
    local startAngle      = math.rad(opts.startAngle or 0)
    local endAngle        = math.rad(opts.endAngle or 360)
    local minRadius       = opts.minRadius or 0
    local maxRadius       = opts.maxRadius or 0
    local minSpeed        = opts.minSpeed or 100
    local maxSpeed        = opts.maxSpeed or 300
    local minScale        = opts.minScale or 5
    local maxScale        = opts.maxScale or 15
    local renderType      = opts.renderType or particle.ParticleRenderType.CIRCLE_FILLED
    local space           = opts.space or "screen"
    local z               = opts.z or 0
    local colorSet        = opts.colors or { util.getColor("WHITE") }
    local gravity         = opts.gravity or 0
    local lifetimeJitter  = opts.lifetimeJitter or 0.0 -- ±fraction of lifetime variance
    local scaleJitter     = opts.scaleJitter or 0.0    -- ±fractional scale variance
    local rotationSpeed   = opts.rotationSpeed or 0.0
    local rotationJitter  = opts.rotationJitter or 0.0

    for i = 1, count do
        -- Random radial direction
        local angle = startAngle + math.random() * (endAngle - startAngle)
        local dir = Vec2(math.cos(angle), math.sin(angle))

        -- Randomized radius offset
        local radius = math.random() * (maxRadius - minRadius) + minRadius

        -- Randomized speed
        local speed = math.random() * (maxSpeed - minSpeed) + minSpeed

        -- Randomized colors
        local startColor = colorSet[math.random(1, #colorSet)]
        local endColor   = opts.endColor or startColor

        -- Jittered lifespan
        local jitterFactorLife = 1 + (math.random() * 2 - 1) * lifetimeJitter
        local lifespan = seconds * jitterFactorLife

        -- Jittered scale
        local scale = math.random() * (maxScale - minScale) + minScale
        local jitterFactorScale = 1 + (math.random() * 2 - 1) * scaleJitter
        scale = scale * jitterFactorScale

        -- Jittered rotation speed (signed)
        local finalRotationSpeed = rotationSpeed * (1 + (math.random() * 2 - 1) * rotationJitter)
        if math.random() < 0.5 then finalRotationSpeed = -finalRotationSpeed end

        particle.CreateParticle(
            Vec2(x + dir.x * radius, y + dir.y * radius),
            Vec2(scale, scale),
            {
                renderType    = renderType,
                velocity      = Vec2(0, 0),
                acceleration  = 0,
                lifespan      = lifespan,
                startColor    = startColor,
                endColor      = endColor,
                rotationSpeed = finalRotationSpeed,
                space         = space,
                z             = z,
                gravity       = gravity,

                onUpdateCallback = function(comp, dt)
                    local age      = comp.age or 0.0
                    local life     = comp.lifespan or lifespan or 0.000001
                    local progress = math.min(math.max(age / life, 0), 1)

                    -- easing-based outward velocity
                    local eased = easing.d(progress)
                    comp.velocity = Vec2(dir.x * speed * eased, dir.y * speed * eased)

                    -- optional easing-based scale growth
                    if opts.scaleEasing then
                        local sEasing = Easing[opts.scaleEasing] or Easing.linear
                        local easedScale = sEasing.f(progress)
                        comp.scale = minScale + (maxScale - minScale) * easedScale
                    end

                    -- apply rotation
                    if finalRotationSpeed ~= 0 then
                        comp.rotation = (comp.rotation or 0) + finalRotationSpeed * dt
                    end

                    -- optional gravity
                    if gravity ~= 0 then
                        comp.velocity.y = comp.velocity.y + gravity * dt
                    end
                end,
            }
        )
    end
end



---@param x number
---@param y number
---@param count integer
---@param seconds number
---@param imageName string
---@param opts table?
function particle.spawnImageBurst(x, y, count, seconds, imageName, opts)
    opts = opts or {}
    local easing = resolveEasing(opts.easing, "quad")
    local startAngle = math.rad(opts.startAngle or 0)
    local endAngle   = math.rad(opts.endAngle or 360)
    local minSpeed   = opts.minSpeed or 100
    local maxSpeed   = opts.maxSpeed or 250
    local z          = opts.z or 0
    local space      = opts.space or "screen"
    seconds = applyDurationVariance(seconds, opts.durationVariance or 0.2)
    
    -- detect sprite vs animation
    local animOpts = {}
    if animOpts.useSpriteNotAnimation then
        animOpts.fg = opts.fg or nil
        animOpts.bg = opts.bg or nil
    end

    if opts.useSpriteNotAnimation or opts.spriteUUID then
        animOpts.animationName = opts.spriteUUID or imageName
        animOpts.useSpriteNotAnimation = true
        animOpts.loop = false
    else
        animOpts.animationName = imageName
        animOpts.useSpriteNotAnimation = false
        animOpts.loop = opts.loop or false
    end


    for i = 1, count do
        local angle = startAngle + math.random() * (endAngle - startAngle)
        local dir   = Vec2(math.cos(angle), math.sin(angle))
        local speed = math.random() * (maxSpeed - minSpeed) + minSpeed

        particle.CreateParticle(
            Vec2(x, y),
            Vec2(opts.size or 16, opts.size or 16),
            {
                renderType   = particle.ParticleRenderType.TEXTURE,
                velocity     = Vec2(0, 0),
                lifespan     = seconds,
                startColor   = opts.startColor or util.getColor("WHITE"),
                endColor     = opts.endColor   or util.getColor("WHITE"),
                space        = space,
                z            = z,
                onUpdateCallback = function(comp, dt)
                    local age = comp.age or 0.0
                    local life = comp.lifespan or seconds
                    local progress = math.min(math.max(age / life, 0), 1)
                    local s = easing.d(progress)
                    comp.velocity = Vec2(dir.x * s * speed, dir.y * s * speed)
                end,
            },
            animOpts
        )
    end
end

---@param x number
---@param y number
---@param count integer
---@param seconds number
---@param radius number
---@param opts table?
function particle.spawnRing(x, y, count, seconds, radius, opts)
    opts = opts or {}
    local easing = resolveEasing(opts.easing, "cubic")
    local colorSet = opts.colors or { util.getColor("WHITE") }
    local space = opts.space or "screen"
    seconds = applyDurationVariance(seconds, opts.durationVariance or 0.2)


    for i = 1, count do
        local angle = (i / count) * (2 * math.pi)
        local dir   = Vec2(math.cos(angle), math.sin(angle))
        local startColor = colorSet[math.random(1, #colorSet)]
        local endColor = opts.endColor or startColor

        particle.CreateParticle(
            Vec2(x + dir.x * radius, y + dir.y * radius),
            Vec2(opts.size or 8, opts.size or 8),
            {
                renderType = opts.renderType or particle.ParticleRenderType.CIRCLE_FILLED,
                lifespan = seconds,
                startColor = startColor,
                endColor = endColor,
                space = space,
                z = opts.z or 0,
                onUpdateCallback = function(comp, dt)
                    local age = comp.age or 0
                    local life = comp.lifespan or seconds
                    local progress = math.min(math.max(age / life, 0), 1)
                    local eased = easing.f(progress)
                    local currentRadius = radius * (1 + (opts.expandFactor or 0.5) * eased)
                    comp.velocity = Vec2(dir.x * currentRadius / life, dir.y * currentRadius / life)
                end
            }
        )
    end
end


---@param x number
---@param y number
---@param w number
---@param h number
---@param count integer
---@param seconds number
---@param opts table?
function particle.spawnRectAreaParticles(x, y, w, h, count, seconds, opts)
    opts = opts or {}
    local easing = resolveEasing(opts.easing, "linear")
    local colorSet = opts.colors or { util.getColor("WHITE") }

    local minSpeed = opts.minSpeed or 50
    local maxSpeed = opts.maxSpeed or 200
    local minScale = opts.minScale or 4
    local maxScale = opts.maxScale or 10
    local angleSpread = math.rad(opts.angleSpread or 360)
    local baseAngle = math.rad(opts.baseAngle or 0)
    local renderType = opts.renderType or particle.ParticleRenderType.CIRCLE_FILLED
    local space = opts.space or "screen"
    local z = opts.z or 0
    seconds = applyDurationVariance(seconds, opts.durationVariance or 0.2)


    for i = 1, count do
        -- random point inside the rectangle
        local px = x + (math.random() - 0.5) * w
        local py = y + (math.random() - 0.5) * h

        -- random velocity direction
        local angle = baseAngle + (math.random() - 0.5) * angleSpread
        local dir   = Vec2(math.cos(angle), math.sin(angle))
        local speed = math.random() * (maxSpeed - minSpeed) + minSpeed

        local startColor = colorSet[math.random(1, #colorSet)]
        local endColor   = opts.endColor or startColor

        particle.CreateParticle(
            Vec2(px, py),
            Vec2(minScale, minScale),
            {
                renderType = renderType,
                lifespan = seconds,
                startColor = startColor,
                endColor = endColor,
                space = space,
                z = z,
                onUpdateCallback = function(comp, dt)
                    local age = comp.age or 0
                    local life = comp.lifespan or seconds
                    local progress = math.min(math.max(age / life, 0), 1)
                    local eased = easing.d(progress)
                    comp.velocity = Vec2(dir.x * speed * eased, dir.y * speed * eased)
                end
            }
        )
    end
end


---@param origin Vector2
---@param count integer
---@param seconds number
---@param opts table?
function particle.spawnDirectionalCone(origin, count, seconds, opts)
    opts = opts or {}
    local easing = resolveEasing(opts.easing, "cubic")
    local direction = opts.direction or Vec2(0, -1)  -- default: upward
    local spread = math.rad(opts.spread or 30)
    local colorSet = opts.colors or { util.getColor("WHITE") }
    local minSpeed = opts.minSpeed or 100
    local maxSpeed = opts.maxSpeed or 300
    local minScale = opts.minScale or 3
    local maxScale = opts.maxScale or 8
    local gravity = opts.gravity or 0
    local renderType = opts.renderType or particle.ParticleRenderType.CIRCLE_FILLED
    local space = opts.space or "screen"
    local z = opts.z or 0
    local lifetimeJitter = opts.lifetimeJitter or 0.0 -- e.g. 0.2 = ±20%
    local scaleJitter = opts.scaleJitter or 0.0       -- e.g. 0.3 = ±30%
    local rotationSpeed = opts.rotationSpeed or 0.0   -- degrees per second (base)
    local rotationJitter = opts.rotationJitter or 0.0 -- e.g. 0.3 = ±30% variance on rotation speed

    -- normalize base direction
    local dirLen = math.sqrt(direction.x^2 + direction.y^2)
    local baseDir = Vec2(direction.x / dirLen, direction.y / dirLen)

    for i = 1, count do
        -- random angle within cone
        local angleOffset = (math.random() - 0.5) * spread
        local cosA, sinA = math.cos(angleOffset), math.sin(angleOffset)
        local dir = Vec2(
            baseDir.x * cosA - baseDir.y * sinA,
            baseDir.x * sinA + baseDir.y * cosA
        )

        -- randomized speed & colors
        local speed = math.random() * (maxSpeed - minSpeed) + minSpeed
        local startColor = colorSet[math.random(1, #colorSet)]
        local endColor = opts.endColor or startColor

        -- jittered lifespan
        local jitterFactorLife = 1 + (math.random() * 2 - 1) * lifetimeJitter
        local lifespan = seconds * jitterFactorLife

        -- jittered scale
        local scale = math.random() * (maxScale - minScale) + minScale
        local jitterFactorScale = 1 + (math.random() * 2 - 1) * scaleJitter
        scale = scale * jitterFactorScale

        -- jittered rotation speed (signed)
        local finalRotationSpeed = rotationSpeed * (1 + (math.random() * 2 - 1) * rotationJitter)
        if math.random() < 0.5 then finalRotationSpeed = -finalRotationSpeed end

        particle.CreateParticle(
            Vec2(origin.x, origin.y),
            Vec2(scale, scale),
            {
                renderType = renderType,
                lifespan = lifespan,
                startColor = startColor,
                endColor = endColor,
                space = space,
                z = z,
                gravity = gravity,
                rotationSpeed = finalRotationSpeed,
                onUpdateCallback = function(comp, dt)
                    local age = comp.age or 0
                    local life = comp.lifespan or lifespan
                    local progress = math.min(math.max(age / life, 0), 1)
                    local eased = easing.d(progress)
                    comp.velocity = Vec2(dir.x * speed * eased, dir.y * speed * eased)
                    if gravity ~= 0 then
                        comp.velocity.y = comp.velocity.y + gravity * dt
                    end
                    -- Apply rotation each frame
                    if finalRotationSpeed ~= 0 then
                        comp.rotation = (comp.rotation or 0) + finalRotationSpeed * dt
                    end
                end
            }
        )
    end
end


---@param a Vector2|entt.entity  -- start point or entity
---@param b Vector2|entt.entity  -- end point or entity
---@param opts table?            -- optional config
function makePulsingBeam(a, b, opts)
    opts = opts or {}
    local color         = opts.color or util.getColor("CYAN")
    local duration      = opts.duration or 1.0
    local pulseSpeed    = opts.pulseSpeed or 5.0
    local easing        = resolveEasing(opts.easing, "cubic")
    local baseRadius    = opts.radius or 12
    local baseThickness = opts.beamThickness or 10
    local z             = opts.z or z_orders.particle_vfx
    local space         = opts.space or layer.DrawCommandSpace.World

    ----------------------------------------------------------------
    -- Helper: resolve entity or vector to center position
    ----------------------------------------------------------------
    local function getCenter(target)
        if type(target) == "userdata" and registry:valid(target) then
            local tr = component_cache.get(target, Transform)
            if tr then
                return Vec2(
                    tr.actualX + tr.actualW * 0.5,
                    tr.actualY + tr.actualH * 0.5
                )
            end
        elseif type(target) == "table" and target.x and target.y then
            return Vec2(target.x, target.y)
        end
        return Vec2(0, 0)
    end

    ----------------------------------------------------------------
    -- Node definition
    ----------------------------------------------------------------
    local Beam = Node:extend()
    Beam.age = 0
    Beam.lifetime = duration

    function Beam:init()
        timer.tween_scalar(
            self.lifetime,
            function() return self.age end,
            function(v) self.age = v end,
            duration,
            Easing.linear.f,
            function()
                registry:destroy(self:handle())
            end,
            "beam_" .. tostring(self:handle())
        )
    end

    function Beam:update(dt)
        self.age = self.age + dt

        -- resolve live positions (supports moving entities)
        local p1 = getCenter(a)
        local p2 = getCenter(b)

        local dx, dy = p2.x - p1.x, p2.y - p1.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local angleDeg = math.deg(math.atan(dy, dx))
        local midX, midY = (p1.x + p2.x) * 0.5, (p1.y + p2.y) * 0.5

        -- progress + pulsing
        local progress = math.min(self.age / self.lifetime, 1.0)
        local fade = 1.0 - progress
        local pulse = 0.5 + 0.5 * math.sin(self.age * pulseSpeed * math.pi * 2)
        local alpha = math.floor(color.a * (0.6 + 0.4 * pulse) * fade)

        ------------------------------------------------------------
        -- 1. Endpoint pulsing circles
        ------------------------------------------------------------
        local rNow = baseRadius * (0.8 + 0.4 * pulse)

        command_buffer.queueDrawCenteredEllipse(layers.sprites, function(c)
            c.x = p1.x
            c.y = p1.y
            c.rx = rNow
            c.ry = rNow
            c.color = Col(color.r, color.g, color.b, alpha)
            c.lineWidth = nil
        end, z, space)

        command_buffer.queueDrawCenteredEllipse(layers.sprites, function(c)
            c.x = p2.x
            c.y = p2.y
            c.rx = rNow
            c.ry = rNow
            c.color = Col(color.r, color.g, color.b, alpha)
            c.lineWidth = nil
        end, z, space)

        ------------------------------------------------------------
        -- 2. Pulsing connecting rectangle
        ------------------------------------------------------------
        local beamThicknessNow = baseThickness * (0.6 + 0.4 * pulse)

        command_buffer.queuePushMatrix(layers.sprites, function() end, z, space)
        command_buffer.queueTranslate(layers.sprites, function(c)
            c.x = midX
            c.y = midY
        end, z, space)
        command_buffer.queueRotate(layers.sprites, function(c)
            c.angle = angleDeg
        end, z, space)

        command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
            c.x = 0
            c.y = 0
            c.w = dist
            c.h = beamThicknessNow
            c.rx = beamThicknessNow * 0.5
            c.ry = beamThicknessNow * 0.5
            c.color = Col(color.r, color.g, color.b, alpha)
        end, z, space)
        command_buffer.queuePopMatrix(layers.sprites, function() end, z, space)
    end

    ----------------------------------------------------------------
    -- Instantiate and attach
    ----------------------------------------------------------------
    local beamNode = Beam{}
    beamNode:attach_ecs{ create_new = true }
    add_state_tag(beamNode:handle(), ACTION_STATE)
    return beamNode
end


---@param p1 Vector2   -- start point
---@param p2 Vector2   -- end point
---@param opts table?  -- { color, duration, radius, beamThickness, pulseSpeed, easing }
function makePulsingBeam(p1, p2, opts)
    opts = opts or {}
    local color         = opts.color or util.getColor("CYAN")
    local duration      = opts.duration or 1.0
    local pulseSpeed    = opts.pulseSpeed or 5.0  -- how many pulses per second
    local easing        = resolveEasing(opts.easing, "cubic")
    local baseRadius    = opts.radius or 12
    local baseThickness = opts.beamThickness or 10
    local z             = opts.z or z_orders.particle_vfx
    local space         = opts.space or layer.DrawCommandSpace.World

    ----------------------------------------------------------------
    -- Derived values
    ----------------------------------------------------------------
    local dx = p2.x - p1.x
    local dy = p2.y - p1.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local angleDeg = math.deg(math.atan(dy, dx))

    ----------------------------------------------------------------
    -- Node definition
    ----------------------------------------------------------------
    local Beam = Node:extend()
    Beam.age = 0
    Beam.lifetime = duration

    function Beam:init()
        timer.tween_scalar(
            self.lifetime,
            function() return self.age end,
            function(v) self.age = v end,
            duration,
            Easing.linear.f,
            function()
                registry:destroy(self:handle())
            end,
            "beam_" .. tostring(self:handle())
        )
    end

    function Beam:update(dt)
        self.age = self.age + dt
        local progress = math.min(self.age / self.lifetime, 1.0)
        local fade = 1.0 - progress
        local pulse = 0.5 + 0.5 * math.sin(self.age * pulseSpeed * math.pi * 2)

        ------------------------------------------------------------
        -- 1. Pulsing circles at endpoints
        ------------------------------------------------------------
        local rNow = baseRadius * (0.8 + 0.4 * pulse)
        local alpha = math.floor(color.a * (0.5 + 0.5 * pulse) * fade)

        -- Start circle
        command_buffer.queueDrawCenteredEllipse(layers.sprites, function(c)
            c.x = p1.x
            c.y = p1.y
            c.rx = rNow
            c.ry = rNow
            c.color = Col(color.r, color.g, color.b, alpha)
            c.lineWidth = nil
        end, z, space)

        -- End circle
        command_buffer.queueDrawCenteredEllipse(layers.sprites, function(c)
            c.x = p2.x
            c.y = p2.y
            c.rx = rNow
            c.ry = rNow
            c.color = Col(color.r, color.g, color.b, alpha)
            c.lineWidth = nil
        end, z, space)

        ------------------------------------------------------------
        -- 2. Beam body — rectangle connecting them
        ------------------------------------------------------------
        local beamThicknessNow = baseThickness * (0.6 + 0.4 * pulse)
        local midX = (p1.x + p2.x) * 0.5
        local midY = (p1.y + p2.y) * 0.5

        command_buffer.queuePushMatrix(layers.sprites, function() end, z, space)
        command_buffer.queueTranslate(layers.sprites, function(c)
            c.x = midX
            c.y = midY
        end, z, space)

        command_buffer.queueRotate(layers.sprites, function(c)
            c.angle = angleDeg
        end, z, space)

        command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
            c.x = 0
            c.y = 0
            c.w = dist
            c.h = beamThicknessNow
            c.rx = beamThicknessNow * 0.5
            c.ry = beamThicknessNow * 0.5
            c.color = Col(color.r, color.g, color.b, alpha)
        end, z, space)

        command_buffer.queuePopMatrix(layers.sprites, function() end, z, space)
    end

    ----------------------------------------------------------------
    -- Instantiate and attach
    ----------------------------------------------------------------
    local beamNode = Beam{}
    beamNode:attach_ecs{ create_new = true }
    add_state_tag(beamNode:handle(), ACTION_STATE)
    return beamNode
end


function makeSwirlEmitter(x, y, radius, colorSet, emitDuration, totalLifetime)
    colorSet = colorSet or { Col(255, 255, 255, 255) }
    emitDuration = emitDuration or 1.0
    totalLifetime = totalLifetime or (emitDuration + 1.0)

    local SwirlEmitter = Node:extend()
    SwirlEmitter.radius = radius
    SwirlEmitter.age = 0
    SwirlEmitter.lifetime = totalLifetime
    SwirlEmitter.emitTimer = 0
    SwirlEmitter.dots = {}
    SwirlEmitter.spawnRate = 1 / 40  -- spawn every 1/40 sec (≈40 per sec)
    SwirlEmitter.timeSinceLast = 0

    function SwirlEmitter:update(dt)
        self.age = self.age + dt
        self.timeSinceLast = self.timeSinceLast + dt

        ------------------------------------------------------------
        -- 1. Spawn phase (emit new dots gradually)
        ------------------------------------------------------------
        if self.age <= emitDuration then
            while self.timeSinceLast >= self.spawnRate do
                self.timeSinceLast = self.timeSinceLast - self.spawnRate

                local angle = math.random() * math.pi * 2
                local d = {
                    angle = angle,
                    dist  = self.radius,
                    -- spiral properties
                    swirlSpeed = (math.random() * 2.5 + 1.5) * (math.random() < 0.5 and -1 or 1),
                    pullSpeed  = math.random() * 40 + 60,
                    life = math.random() * 1.2 + 0.8, -- per-dot life
                    age = 0,
                    rx = math.random() * 8 + 4,
                    ry = math.random() * 3 + 2,
                    color = colorSet[math.random(1, #colorSet)],
                    spin = (math.random() - 0.5) * 0.4
                }
                table.insert(self.dots, d)
            end
        end

        ------------------------------------------------------------
        -- 2. Update all live dots
        ------------------------------------------------------------
        for i = #self.dots, 1, -1 do
            local d = self.dots[i]
            d.age = d.age + dt
            local progress = math.min(d.age / d.life, 1.0)
            local decay = 1.0 - progress

            -- spiral inward: angular rotation + radius shrink
            d.angle = d.angle + d.swirlSpeed * dt  -- swirl
            d.dist  = d.dist - d.pullSpeed * dt * (0.6 + 0.4 * decay) -- inward pull slows near center

            if d.dist < 4 then
                table.remove(self.dots, i)
                goto continue
            end

            -- compute position
            local px = x + math.cos(d.angle) * d.dist
            local py = y + math.sin(d.angle) * d.dist

            -- orientation: tangent direction of spiral
            local dirAngle = d.angle + math.pi / 2
            local scale = decay
            local rx = d.rx * scale
            local ry = d.ry * scale

            --------------------------------------------------------
            -- draw facing ellipse
            --------------------------------------------------------
            command_buffer.queuePushMatrix(layers.sprites, function() end,
                z_orders.particle_vfx, layer.DrawCommandSpace.World)

            command_buffer.queueTranslate(layers.sprites, function(c)
                c.x = px
                c.y = py
            end, z_orders.particle_vfx, layer.DrawCommandSpace.World)

            command_buffer.queueRotate(layers.sprites, function(c)
                c.angle = math.deg(dirAngle)
            end, z_orders.particle_vfx, layer.DrawCommandSpace.World)

            command_buffer.queueDrawCenteredEllipse(layers.sprites, function(c)
                c.x = 0
                c.y = 0
                c.rx = rx
                c.ry = ry
                c.color = d.color:setAlpha(math.floor(255 * decay))
                c.lineWidth = nil -- filled
            end, z_orders.particle_vfx, layer.DrawCommandSpace.World)

            command_buffer.queuePopMatrix(layers.sprites, function() end,
                z_orders.particle_vfx, layer.DrawCommandSpace.World)

            ::continue::
        end

        ------------------------------------------------------------
        -- 3. Cleanup when all dots gone and time expired
        ------------------------------------------------------------
        if self.age >= self.lifetime and #self.dots == 0 then
            registry:destroy(self:handle())
        end
    end

    local emitterNode = SwirlEmitter{}
    emitterNode:attach_ecs{ create_new = true }
    add_state_tag(emitterNode:handle(), ACTION_STATE)
    return emitterNode
end


function particle.spawnDirectionalStreaksCone(origin, count, seconds, opts)
    opts = opts or {}
    local easing      = resolveEasing(opts.easing, "cubic")
    local colorSet    = opts.colors or { util.getColor("WHITE") }
    local minSpeed    = opts.minSpeed or 150
    local maxSpeed    = opts.maxSpeed or 350
    local minScale    = opts.minScale or 8
    local maxScale    = opts.maxScale or 20
    local shrink      = (opts.shrink ~= false)     -- true by default
    local aspect      = opts.aspect or 3.0
    local durationJitter = opts.durationJitter or 0.2
    local scaleJitter    = opts.scaleJitter or 0.3
    local space       = opts.space or "screen"
    local z           = opts.z or 0
    local direction   = opts.direction or Vec2(0, -1)  -- default: upward
    local spread      = math.rad(opts.spread or 30)    -- degrees → radians
    local autoAspect  = opts.autoAspect or false       -- enable speed-based elongation

    -- normalize base direction
    local len = math.sqrt(direction.x^2 + direction.y^2)
    local baseDir = Vec2(direction.x / len, direction.y / len)

    for i = 1, count do
        -- random deviation within cone
        local offset = (math.random() - 0.5) * spread
        local cosA, sinA = math.cos(offset), math.sin(offset)
        local dir = Vec2(
            baseDir.x * cosA - baseDir.y * sinA,
            baseDir.x * sinA + baseDir.y * cosA
        )

        local speed = math.random() * (maxSpeed - minSpeed) + minSpeed
        local lifespan = seconds * (1 + (math.random() * 2 - 1) * durationJitter)
        local scale = math.random() * (maxScale - minScale) + minScale
        scale = scale * (1 + (math.random() * 2 - 1) * scaleJitter)
        local color = colorSet[math.random(1, #colorSet)]

        particle.CreateParticle(
            Vec2(origin.x, origin.y),
            Vec2(scale, scale / aspect),
            {
                renderType = particle.ParticleRenderType.ELLIPSE_STRETCH,
                lifespan = lifespan,
                startColor = color,
                endColor = color,
                space = space,
                z = z,
                autoAspect = autoAspect,
                onUpdateCallback = function(comp, dt)
                    local age = comp.age or 0
                    local life = comp.lifespan or lifespan
                    local progress = math.min(age / life, 1.0)
                    local eased = easing.d(progress)
                    comp.velocity = Vec2(dir.x * speed * eased, dir.y * speed * eased)

                    if shrink then
                        local shrinkFactor = 1 - progress
                        comp.scale = math.max(0.1, scale * shrinkFactor)
                    end
                end
            }
        )
    end
end

---@param origin Vector2
---@param count integer
---@param seconds number
---@param opts table?
function particle.spawnDirectionalLinesCone(origin, count, seconds, opts)
    opts = opts or {}
    local easing         = resolveEasing(opts.easing, "cubic")
    local colorSet       = opts.colors or { util.getColor("WHITE") }
    local minSpeed       = opts.minSpeed or 150
    local maxSpeed       = opts.maxSpeed or 350
    local minLength      = opts.minLength or 24
    local maxLength      = opts.maxLength or 64
    local minThickness   = opts.minThickness or 2.0
    local maxThickness   = opts.maxThickness or 4.0
    local shrink         = (opts.shrink ~= false)   -- shrink over time by default
    local durationJitter = opts.durationJitter or 0.2
    local sizeJitter     = opts.sizeJitter or 0.3
    local space          = opts.space or "screen"
    local z              = opts.z or 0
    local direction      = opts.direction or Vec2(0, -1)  -- default: upward
    local spread         = math.rad(opts.spread or 30)    -- degrees → radians
    local faceVelocity   = (opts.faceVelocity ~= false)

    -- normalize base direction
    local len = math.sqrt(direction.x^2 + direction.y^2)
    local baseDir = Vec2(direction.x / len, direction.y / len)

    for i = 1, count do
        ----------------------------------------------------------
        -- Randomized per-particle properties
        ----------------------------------------------------------
        local offset = (math.random() - 0.5) * spread
        local cosA, sinA = math.cos(offset), math.sin(offset)
        local dir = Vec2(
            baseDir.x * cosA - baseDir.y * sinA,
            baseDir.x * sinA + baseDir.y * cosA
        )

        local speed = math.random() * (maxSpeed - minSpeed) + minSpeed
        local lifespan = seconds * (1 + (math.random() * 2 - 1) * durationJitter)
        local length = math.random() * (maxLength - minLength) + minLength
        length = length * (1 + (math.random() * 2 - 1) * sizeJitter)
        local thickness = math.random() * (maxThickness - minThickness) + minThickness
        local color = colorSet[math.random(1, #colorSet)]

        ----------------------------------------------------------
        -- Particle creation
        ----------------------------------------------------------
        particle.CreateParticle(
            Vec2(origin.x, origin.y),
            Vec2(length, thickness),
            {
                renderType    = particle.ParticleRenderType.LINE_FACING,
                lifespan      = lifespan,
                startColor    = color,
                endColor      = color,
                velocity      = Vec2(dir.x * speed, dir.y * speed),
                color         = color,
                faceVelocity  = faceVelocity,
                space         = space,
                z             = z,

                onUpdateCallback = function(comp, dt)
                    local age  = comp.age or 0.0
                    local life = comp.lifespan or lifespan
                    local progress = math.min(age / life, 1.0)
                    local eased = easing.d(progress)

                    -- Velocity eases outward
                    comp.velocity = Vec2(dir.x * speed * eased, dir.y * speed * eased)

                    -- Shrink / fade behavior
                    if shrink then
                        local shrinkFactor = 1.0 - progress
                        comp.scale = math.max(0.1, shrinkFactor)
                    end
                end
            }
        )
    end
end


---@param x number
---@param y number
---@param count integer
---@param seconds number
---@param opts table?
function particle.spawnFountain(x, y, count, seconds, opts)
    opts = opts or {}
    opts.direction = opts.direction or Vec2(0, -1)
    opts.spread = opts.spread or 45
    opts.gravity = opts.gravity or 120
    opts.minSpeed = opts.minSpeed or 80
    opts.maxSpeed = opts.maxSpeed or 160
    opts.easing = opts.easing or "cubic"
    opts.colors = opts.colors or {
        util.getColor("WHITE"),
        util.getColor("GRAY"),
        util.getColor("LIGHTGRAY")
    }
    particle.spawnDirectionalCone(Vec2(x, y), count, seconds, opts)
end



function makeDirectionalWipeWithTimer(cx, cy, w, h, facingDir, wipeDir, color, duration, rx, ry, easing)
    color = color or Col(255, 255, 255, 255)
    duration = duration or 1.0
    easing = easing or Easing.cubic.f
    rx, ry = rx or 0, ry or 0

    ------------------------------------------------------------
    -- Normalize direction vectors
    ------------------------------------------------------------
    local fx, fy = facingDir.x, facingDir.y
    local flen = math.sqrt(fx*fx + fy*fy)
    if flen == 0 then fx, fy = 1, 0; flen = 1 end
    fx, fy = fx / flen, fy / flen

    local wx, wy = wipeDir.x or 1, wipeDir.y or 0
    local wlen = math.sqrt(wx*wx + wy*wy)
    if wlen == 0 then wx, wy = 1, 0; wlen = 1 end
    wx, wy = wx / wlen, wy / wlen

    local angle = math.deg(math.atan(fy, fx))

    ------------------------------------------------------------
    -- Node definition
    ------------------------------------------------------------
    local node = Node:extend()
    node.progress = 0

    function node:update(dt)
        local t = self.progress
        local visFrac = t

        -- Rectangle size depending on wipe axis
        local drawW = (math.abs(wx) > math.abs(wy)) and (w * visFrac) or w
        local drawH = (math.abs(wy) > math.abs(wx)) and (h * visFrac) or h

        -- Offset so it expands from one edge
        local localOffsetX = -wx * (w - drawW) * 0.5
        local localOffsetY = -wy * (h - drawH) * 0.5

        ------------------------------------------------------------
        -- Transform stack (rotation to face, anchored wipe)
        ------------------------------------------------------------
        command_buffer.queuePushMatrix(layers.sprites, function() end,
            z_orders.particle_vfx, layer.DrawCommandSpace.World)

        command_buffer.queueTranslate(layers.sprites, function(c)
            c.x = cx
            c.y = cy
        end, z_orders.particle_vfx, layer.DrawCommandSpace.World)

        command_buffer.queueRotate(layers.sprites, function(c)
            c.angle = angle
        end, z_orders.particle_vfx, layer.DrawCommandSpace.World)

        command_buffer.queueTranslate(layers.sprites, function(c)
            c.x = localOffsetX
            c.y = localOffsetY
        end, z_orders.particle_vfx, layer.DrawCommandSpace.World)

        command_buffer.queueDrawCenteredFilledRoundedRect(layers.sprites, function(c)
            c.x = 0
            c.y = 0
            c.w = drawW
            c.h = drawH
            c.rx = rx
            c.ry = ry
            c.color = color
        end, z_orders.particle_vfx, layer.DrawCommandSpace.World)

        command_buffer.queuePopMatrix(layers.sprites, function() end,
            z_orders.particle_vfx, layer.DrawCommandSpace.World)
    end

    local wipeNode = node{}
    wipeNode:attach_ecs{ create_new = true }
    add_state_tag(wipeNode:handle(), ACTION_STATE)

    ------------------------------------------------------------
    -- Timer tween drives progress + cleanup
    ------------------------------------------------------------
    timer.tween_scalar(
        duration,
        function() return wipeNode.progress end,
        function(v) wipeNode.progress = v end,
        1.0,
        easing,
        function()
            registry:destroy(wipeNode:handle())
        end,
        "wipe_" .. tostring(wipeNode:handle())
    )

    return wipeNode
end



function spawnCrescentParticle(x, y, radius, velocity, color, lifetime)
    local Crescent = Node:extend()
    Crescent.radius = radius
    Crescent.age = 0
    Crescent.lifetime = lifetime
    Crescent.color = color or Col(255, 255, 255, 255)
    Crescent.vx = velocity.x or 0
    Crescent.vy = velocity.y or 0
    Crescent.cx = x
    Crescent.cy = y
    Crescent.cutOffsetBase = radius * 0.6     -- base offset for the "bite"
    Crescent.innerShrinkBase = 0.85           -- base inner circle shrink

    function Crescent:update(dt)
        self.age = self.age + dt
        local t = math.min(self.age / self.lifetime, 1.0)
        local decay = 1.0 - t

        ------------------------------------------------------------
        -- motion + speed-based deformation
        ------------------------------------------------------------
        self.cx = self.cx + self.vx * dt
        self.cy = self.cy + self.vy * dt
        local speed = math.sqrt(self.vx * self.vx + self.vy * self.vy)

        -- deformation multipliers
        local stretch = 1.0 + math.min(speed / 600.0, 1.2) * 0.6  -- faster → longer
        local flatten = 1.0 / stretch                            -- faster → thinner
        local cutOffset = self.cutOffsetBase * stretch * 0.9
        local innerShrink = self.innerShrinkBase * flatten

        ------------------------------------------------------------
        -- orientation
        ------------------------------------------------------------
        local angle = math.deg(math.atan(self.vy, self.vx))
        local drawColor = self.color:setAlpha(math.floor(self.color.a * decay))

        ------------------------------------------------------------
        -- stencil crescent construction
        ------------------------------------------------------------
        local L = layers.sprites
        local z = z_orders.particle_vfx
        local space = layer.DrawCommandSpace.World

        -- Begin stencil
        command_buffer.queueClearStencilBuffer(L, function() end, z, space)
        command_buffer.queueBeginStencilMode(L, function() end, z, space)

        -- Outer mask
        command_buffer.queueBeginStencilMask(L, function() end, z, space)
        command_buffer.queuePushMatrix(L, function() end, z, space)
        command_buffer.queueTranslate(L, function(c)
            c.x = self.cx
            c.y = self.cy
        end, z, space)
        command_buffer.queueRotate(L, function(c)
            c.angle = angle
        end, z, space)

        command_buffer.queueScale(L, function(c)
            c.scaleX = stretch
            c.scaleY = flatten
        end, z, space)

        command_buffer.queueDrawCenteredEllipse(L, function(c)
            c.x, c.y = 0, 0
            c.rx, c.ry = self.radius, self.radius
            c.color = util.getColor("WHITE")
        end, z, space)

        -- Cut inner area (erase backward)
        command_buffer.queueRenderBatchFlush(L, function() end, z, space)
        command_buffer.queueStencilFunc(L, function(c)
            c.func = GL_ALWAYS
            c.ref = 0
            c.mask = 0xFF
        end, z, space)
        command_buffer.queueStencilOp(L, function(c)
            c.sfail = GL_KEEP
            c.dpfail = GL_KEEP
            c.dppass = GL_REPLACE
        end, z, space)
        command_buffer.queueColorMask(L, function(c)
            c.r, c.g, c.b, c.a = false, false, false, false
        end, z, space)

        command_buffer.queueTranslate(L, function(c)
            c.x = -cutOffset
            c.y = 0
        end, z, space)

        command_buffer.queueDrawCenteredEllipse(L, function(c)
            c.x, c.y = 0, 0
            c.rx, c.ry = self.radius * innerShrink, self.radius * innerShrink
            c.color = util.getColor("WHITE")
        end, z, space)

        -- End stencil mask
        command_buffer.queuePopMatrix(L, function() end, z, space)
        command_buffer.queueEndStencilMask(L, function() end, z, space)

        ------------------------------------------------------------
        -- Draw crescent visible area
        ------------------------------------------------------------
        command_buffer.queuePushMatrix(L, function() end, z, space)
        command_buffer.queueTranslate(L, function(c)
            c.x = self.cx
            c.y = self.cy
        end, z, space)
        command_buffer.queueRotate(L, function(c)
            c.angle = angle
        end, z, space)
        command_buffer.queueScale(L, function(c)
            c.scaleX = stretch
            c.scaleY = flatten
        end, z, space)

        command_buffer.queueDrawCenteredEllipse(L, function(c)
            c.x, c.y = 0, 0
            c.rx, c.ry = self.radius, self.radius
            c.color = drawColor
        end, z, space)

        command_buffer.queuePopMatrix(L, function() end, z, space)
        command_buffer.queueEndStencilMode(L, function() end, z, space)

        ------------------------------------------------------------
        -- cleanup
        ------------------------------------------------------------
        if self.age >= self.lifetime then
            registry:destroy(self:handle())
        end
    end

    local e = Crescent{}
    e:attach_ecs{ create_new = true }
    add_state_tag(e:handle(), ACTION_STATE)
    return e
end


function spawnHollowCircleParticle(x, y, radius, color, lifetime)
    local HollowCircle = Node:extend()
    HollowCircle.radius = radius
    HollowCircle.age = 0
    HollowCircle.lifetime = lifetime
    HollowCircle.color = color or Col(255, 255, 255, 255)
    
    function HollowCircle:init()
        log_debug("Spawning hollow circle particle at", x, y, "radius", radius, "lifetime", lifetime)
        
        self.innerR = 0
        
        timer.tween_fields(lifetime, self, { innerR = radius }, Easing.inOutCubic.f, nil, "transition_text_scale_up", "ui")
        
        
    end
    
    function HollowCircle:update(dt)
        self.age = self.age + dt
        local t = math.min(self.age / self.lifetime, 1.0)
        local outerR = self.radius
        -- local innerR = outerR * t

        local L = layers.sprites
        local z = z_orders.particle_vfx
        local space = layer.DrawCommandSpace.World
        
        command_buffer.queueClearStencilBuffer(L, function() end, z, space)

        ------------------------------------------------------------------
        -- (1) Begin stencil workflow (enable + clear)
        ------------------------------------------------------------------
        command_buffer.queueBeginStencilMode(L, function() end, z, space)

        ------------------------------------------------------------------
        -- (2) Begin outer mask (set stencil = 1)
        ------------------------------------------------------------------
        command_buffer.queueBeginStencilMask(L, function() end, z, space)
        command_buffer.queueDrawCenteredEllipse(L, function(c)
            c.x, c.y = x, y
            c.rx, c.ry = outerR, outerR
            c.color = util.getColor("WHITE")
        end, z, space)

        -- Flush to ensure outer circle writes stencil=1 before next phase
        command_buffer.queueRenderBatchFlush(L, function() end, z, space)

        ------------------------------------------------------------------
        -- (3) Draw inner circle to erase stencil (set stencil = 0)
        ------------------------------------------------------------------
        -- Enable full stencil write mask
        command_buffer.queueAtomicStencilMask(L, function(c)
            c.mask = 0xFF
        end, z, space)

        -- Always pass, write reference 0 (to erase)
        command_buffer.queueStencilFunc(L, function(c)
            c.func = GL_ALWAYS
            c.ref = 0
            c.mask = 0xFF
        end, z, space)

        -- Replace stencil value with 0 where we draw
        command_buffer.queueStencilOp(L, function(c)
            c.sfail = GL_KEEP
            c.dpfail = GL_KEEP
            c.dppass = GL_REPLACE
        end, z, space)
        
        command_buffer.queueColorMask(L, function(c)
            c.r, c.g, c.b, c.a = false, false, false, false
        end, z, space)

        -- Draw the inner circle — this clears stencil inside
        command_buffer.queueDrawCenteredEllipse(L, function(c)
            c.x, c.y = x, y
            c.rx, c.ry = self.innerR, self.innerR
            c.color = util.getColor("WHITE")
        end, z, space)

        -- Flush to commit erase before restoring state
        command_buffer.queueRenderBatchFlush(L, function() end, z, space)

        ------------------------------------------------------------------
        -- (3b) Disable further stencil writes (glStencilMask(0x00))
        ------------------------------------------------------------------
        -- command_buffer.queueAtomicStencilMask(L, function(c)
        --     c.mask = 0x00
        -- end, z, space)

        ------------------------------------------------------------------
        -- (4) End mask phase — restore stencil test (stencil == 1)
        ------------------------------------------------------------------
        -- command_buffer.queueStencilFunc(L, function(c)
        --     c.func = GL_EQUAL
        --     c.ref = 1
        --     c.mask = 0xFF
        -- end, z, space)

        -- command_buffer.queueStencilOp(L, function(c)
        --     c.sfail = GL_KEEP
        --     c.dpfail = GL_KEEP
        --     c.dppass = GL_KEEP
        -- end, z, space)

        -- Restore color writes (draw visible content again)
        -- command_buffer.queueColorMask(L, function(c)
        --     c.r, c.g, c.b, c.a = true, true, true, true
        -- end, z, space)

        -- End the mask stage (should mirror endStencilMask C++)
        command_buffer.queueEndStencilMask(L, function() end, z, space)

        ------------------------------------------------------------------
        -- (5) Draw visible ring (only where stencil == 1)
        ------------------------------------------------------------------
        command_buffer.queueDrawCenteredEllipse(L, function(c)
            c.x, c.y = x, y
            c.rx, c.ry = outerR, outerR
            c.color = self.color
        end, z, space)

        -- Optional flush for correctness before disabling stencil
        command_buffer.queueRenderBatchFlush(L, function() end, z, space)

        ------------------------------------------------------------------
        -- (6) End stencil mode (disable + cleanup)
        ------------------------------------------------------------------
        -- Restore full write mask before disabling stencil
        -- command_buffer.queueAtomicStencilMask(L, function(c)
        --     c.mask = 0xFF
        -- end, z, space)

        command_buffer.queueEndStencilMode(L, function() end, z, space)

        ------------------------------------------------------------------
        -- (7) Lifetime cleanup
        ------------------------------------------------------------------
        if t >= 1.0 then
            registry:destroy(self:handle())
        end
    end

    local e = HollowCircle{}
    e:attach_ecs{ create_new = true }
    add_state_tag(e:handle(), ACTION_STATE)
end



function spawnImpactSmear(x, y, dir, color, lifetime, opts)
    opts = opts or {}
    color = color or Col(255, 255, 255, 255)
    lifetime = lifetime or 0.25

    local Smear = Node:extend()
    Smear.cx, Smear.cy = x, y
    Smear.dir = dir or Vec2(1, 0)
    Smear.color = color
    Smear.lifetime = lifetime
    Smear.progress = 0
    Smear.single = opts.single or false           -- if true: single streak instead of cross
    Smear.maxLength = opts.maxLength or 60
    Smear.maxThickness = opts.maxThickness or 10

    function Smear:init()
        timer.tween_scalar(
            self.lifetime,
            function() return self.progress end,
            function(v) self.progress = v end,
            1.0,
            Easing.outCubic.f,
            function() registry:destroy(self:handle()) end,
            "smear_" .. tostring(self:handle())
        )
    end

    function Smear:update(dt)
        local t = self.progress
        local decay = 1.0 - t
        local fade = decay * decay

        -- Normalize input direction
        local dx, dy = self.dir.x, self.dir.y
        local len = math.sqrt(dx*dx + dy*dy)
        if len == 0 then dx, dy = 1, 0 else dx, dy = dx/len, dy/len end

        -- perpendicular direction (for orientation)
        local px, py = -dy, dx
        local baseAngle = math.deg(math.atan(py, px))

        -- Animate geometry (shorter + thinner as it fades)
        local length = self.maxLength * (0.6 + 0.4 * fade)
        local thickness = self.maxThickness * fade
        local drawColor = self.color:setAlpha(math.floor(self.color.a * fade))

        local L = layers.sprites
        local z = z_orders.particle_vfx
        local space = layer.DrawCommandSpace.World

        ------------------------------------------------------------
        -- Draw one or multiple elliptical streaks
        ------------------------------------------------------------
        if self.single then
            -- just one perpendicular streak
            command_buffer.queuePushMatrix(L, function() end, z, space)

            command_buffer.queueTranslate(L, function(c)
                c.x = self.cx
                c.y = self.cy
            end, z, space)

            command_buffer.queueRotate(L, function(c)
                c.angle = baseAngle
            end, z, space)

            command_buffer.queueDrawCenteredEllipse(L, function(c)
                c.x = 0
                c.y = 0
                c.rx = length
                c.ry = thickness
                c.color = drawColor
                c.lineWidth = nil
            end, z, space)

            command_buffer.queuePopMatrix(L, function() end, z, space)
        else
            -- four-cross version
            for i = 1, 4 do
                local angleOffset = (i <= 2) and baseAngle or (baseAngle + 90)
                local localScale = (i % 2 == 0) and 0.8 or 1.0

                command_buffer.queuePushMatrix(L, function() end, z, space)

                command_buffer.queueTranslate(L, function(c)
                    c.x = self.cx
                    c.y = self.cy
                end, z, space)

                command_buffer.queueRotate(L, function(c)
                    c.angle = angleOffset
                end, z, space)

                command_buffer.queueDrawCenteredEllipse(L, function(c)
                    c.x = 0
                    c.y = 0
                    c.rx = length * localScale
                    c.ry = thickness * localScale
                    c.color = drawColor
                    c.lineWidth = nil
                end, z, space)

                command_buffer.queuePopMatrix(L, function() end, z, space)
            end
        end
    end

    local e = Smear{}
    e:attach_ecs{ create_new = true }
    add_state_tag(e:handle(), ACTION_STATE)
    return e
end

--- Spawn a short, forward-facing burst of particles and a smear along `direction`.
--- Useful for bullet impacts that should inherit the incoming travel vector.
--- @param x number
--- @param y number
--- @param direction table Vector with x/y components
--- @param opts table? Optional overrides: count, spread, lifetime, colors, space, smearLength, smearThickness
function particle.spawnDirectionalImpact(x, y, direction, opts)
    opts = opts or {}
    if type(x) == "table" then
        direction = direction or opts.direction
        opts = opts or {}
        y = x.y
        x = x.x
    end

    direction = direction or opts.direction or Vec2(1, 0)
    local dx, dy = direction.x or 0, direction.y or 0
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.0001 then return end
    dx, dy = dx / len, dy / len

    particle.spawnDirectionalCone(Vec2(x, y), opts.count or 12, opts.lifetime or 0.35, {
        direction = Vec2(dx, dy),
        spread = opts.spread or 30,
        colors = opts.colors or { util.getColor("WHITE"), util.getColor("YELLOW") },
        minSpeed = opts.minSpeed or 140,
        maxSpeed = opts.maxSpeed or 340,
        minScale = opts.minScale or 3,
        maxScale = opts.maxScale or 7,
        lifetimeJitter = opts.lifetimeJitter or 0.25,
        scaleJitter = opts.scaleJitter or 0.2,
        gravity = opts.gravity or 0,
        space = opts.space or "world",
        z = opts.z or z_orders.particle_vfx,
        renderType = opts.renderType or particle.ParticleRenderType.RECTANGLE_FILLED,
    })

    if opts.smear ~= false then
        spawnImpactSmear(
            x,
            y,
            Vec2(dx, dy),
            opts.smearColor or util.getColor("white"),
            opts.smearLifetime or 0.18,
            {
                single = true,
                maxLength = opts.smearLength or 46,
                maxThickness = opts.smearThickness or 9
            }
        )
    end
end


---@param ent entt.entity              -- entity to trail
---@param duration number              -- total time to emit
---@param opts table?                  -- options (same as spawnDirectionalCone)
function particle.attachTrailToEntity(ent, duration, opts)
    opts = opts or {}
    local interval = opts.interval or 0.05  -- how often to emit (seconds)
    local count = opts.count or 3           -- how many per tick
    local elapsed = 0
    local timerTag = "trail_" .. tostring(ent) .. "_" .. tostring(math.random(10000))
    local onFinish = opts.onFinish or nil   -- optional callback(ent)

    -- Core emission settings
    local easing = opts.easing or "cubic"
    local direction = opts.direction or Vec2(0, -1)
    local spread = opts.spread or 20
    local colorSet = opts.colors or { util.getColor("WHITE") }
    local minSpeed = opts.minSpeed or 100
    local maxSpeed = opts.maxSpeed or 300
    local minScale = opts.minScale or 1
    local maxScale = opts.maxScale or 8
    local lifetime = opts.lifetime or 0.3
    local gravity = opts.gravity or 0
    local space = opts.space or "screen"
    local z = opts.z or 0
    local jitterLife = opts.lifetimeJitter or 0.2
    local jitterScale = opts.scaleJitter or 0.3
    local rotationSpeed = opts.rotationSpeed or 0.0
    local rotationJitter = opts.rotationJitter or 0.2

    ----------------------------------------------------------------
    -- Internal emission logic
    ----------------------------------------------------------------
    local function emitAtCurrentPos()
        if not entity_cache.valid(ent) then return end
        local transform = component_cache.get(ent, Transform)
        if not transform then return end
        local pos = Vec2(transform.actualX + transform.actualW * 0.5, transform.actualY + transform.actualH * 0.5)

        particle.spawnDirectionalCone(
            pos,
            count,
            lifetime,
            {
                easing = easing,
                direction = direction,
                spread = spread,
                colors = colorSet,
                minSpeed = minSpeed,
                maxSpeed = maxSpeed,
                minScale = minScale,
                maxScale = maxScale,
                gravity = gravity,
                space = space,
                z = z,
                lifetimeJitter = jitterLife,
                scaleJitter = jitterScale,
                rotationSpeed = rotationSpeed,
                rotationJitter = rotationJitter,
            }
        )
    end

    ----------------------------------------------------------------
    -- Emit at a fixed interval using timer.every()
    ----------------------------------------------------------------
    timer.every(interval, function()
        if not registry:valid(ent) then
            timer.clear(timerTag)
            if onFinish then onFinish(ent) end
            return
        end

        elapsed = elapsed + interval
        if elapsed <= duration then
            emitAtCurrentPos()
        else
            timer.cancel(timerTag)
            if onFinish then onFinish(ent) end
        end
    end, 0, true, nil, timerTag)
end


function makeDashedCircleArea(x, y, radius, opts)
    opts = opts or {}
    local color       = opts.color or util.getColor("YELLOW")
    local fillColor   = opts.fillColor or Col(color.r, color.g, color.b, 40) -- faint translucent
    local hasFill     = (opts.hasFill ~= false)
    local dashLen     = opts.dashLength or 16
    local gapLen      = opts.gapLength or 10
    local thickness   = opts.thickness or 4
    local segments    = opts.segments or 128
    local rotateSpeed = opts.rotateSpeed or 90    -- degrees per second
    local duration    = opts.duration or 1.5
    local z           = opts.z or z_orders.particle_vfx
    local space       = opts.space or layer.DrawCommandSpace.World

    ----------------------------------------------------------------
    -- Node definition
    ----------------------------------------------------------------
    local CircleArea = Node:extend()
    CircleArea.cx = x
    CircleArea.cy = y
    CircleArea.radius = radius
    CircleArea.phase = 0
    CircleArea.age = 0
    CircleArea.lifetime = duration

    function CircleArea:init()
        timer.tween_scalar(
            self.lifetime,
            function() return self.age end,
            function(v) self.age = v end,
            duration,
            Easing.linear.f,
            function()
                registry:destroy(self:handle())
            end,
            "circle_area_" .. tostring(self:handle())
        )
    end

    function CircleArea:update(dt)
        self.phase = (self.phase + rotateSpeed * dt) % 360
        local progress = math.min(self.age / self.lifetime, 1.0)
        -- keep fully visible until last 25%, then fade out
        local fade = 1.0
        if progress > 0.75 then
            fade = 1.0 - ((progress - 0.75) / 0.25)
        end

        ------------------------------------------------------------
        -- Optional semi-translucent fill
        ------------------------------------------------------------
        if hasFill then
            command_buffer.queueDrawCenteredEllipse(layers.sprites, function(c)
                c.x = self.cx
                c.y = self.cy
                c.rx = self.radius
                c.ry = self.radius
                c.color = fillColor:setAlpha(math.floor(fillColor.a * fade))
                c.lineWidth = nil
            end, z, space)
        end

        ------------------------------------------------------------
        -- Rotating dashed circle border
        ------------------------------------------------------------
        command_buffer.queueDrawDashedCircle(layers.sprites, function(c)
            c.center = Vec2(self.cx, self.cy)
            c.radius = self.radius
            c.dashLength = dashLen
            c.gapLength = gapLen
            c.phase = self.phase
            c.segments = segments
            c.thickness = thickness
            c.color = color:setAlpha(math.floor(color.a * fade))
        end, z, space)
    end

    ----------------------------------------------------------------
    -- Create instance and attach
    ----------------------------------------------------------------
    local node = CircleArea{}
    node:attach_ecs{ create_new = true }
    add_state_tag(node:handle(), ACTION_STATE)
    return node
end



function makeSwirlEmitterWithRing(x, y, radius, colorSet, emitDuration, totalLifetime)
    colorSet = colorSet or { Col(255, 255, 255, 255) }
    emitDuration = emitDuration or 1.0
    totalLifetime = totalLifetime or (emitDuration + 1.0)

    local SwirlEmitter = Node:extend()
    SwirlEmitter.radius = radius
    SwirlEmitter.age = 0
    SwirlEmitter.lifetime = totalLifetime
    SwirlEmitter.dots = {}
    SwirlEmitter.spawnRate = 1 / 40   -- how often to emit (40 per sec)
    SwirlEmitter.timeSinceLast = 0
    SwirlEmitter.ringColor = colorSet[1] or Col(255,255,255,255)
    SwirlEmitter.ringShadowColor = Col(0, 0, 0, 255)
    SwirlEmitter.shadowOffset = 8   -- px offset for shadow

    function SwirlEmitter:update(dt)
        self.age = self.age + dt
        self.timeSinceLast = self.timeSinceLast + dt
        local elapsed = self.age
        local decayGlobal = math.max(0.0, 1.0 - (self.age - emitDuration) / (self.lifetime - emitDuration))

        ------------------------------------------------------------
        -- 1. Spawn new dots gradually during emitDuration
        ------------------------------------------------------------
        if elapsed <= emitDuration then
            while self.timeSinceLast >= self.spawnRate do
                self.timeSinceLast = self.timeSinceLast - self.spawnRate
                local angle = math.random() * math.pi * 2
                local d = {
                    angle = angle,
                    dist  = self.radius,
                    swirlSpeed = (math.random() * 2.5 + 1.5) * (math.random() < 0.5 and -1 or 1),
                    pullSpeed  = math.random() * 40 + 60,
                    life = math.random() * 1.2 + 0.8,
                    age = 0,
                    rx = math.random() * 8 + 4,
                    ry = math.random() * 3 + 2,
                    color = colorSet[math.random(1, #colorSet)],
                    spin = (math.random() - 0.5) * 0.4
                }
                table.insert(self.dots, d)
            end
        end

        ------------------------------------------------------------
        -- 2. Draw the static ring (shadow + main outline)
        ------------------------------------------------------------
        local ringZ = z_orders.particle_vfx - 1

        -- Shadow ring
        command_buffer.queueDrawCircleLine(layers.sprites, function(c)
            c.x = x + SwirlEmitter.shadowOffset
            c.y = y + SwirlEmitter.shadowOffset
            c.innerRadius = SwirlEmitter.radius - 3.0
            c.outerRadius = SwirlEmitter.radius
            c.segments = 64
            c.startAngle = 0
            c.endAngle = 360
            c.color = SwirlEmitter.ringShadowColor:setAlpha(math.floor(120 * decayGlobal))
            -- c.lineWidth = 3.0
        end, ringZ, layer.DrawCommandSpace.World)

        -- Main ring
        command_buffer.queueDrawCircleLine(layers.sprites, function(c)
            c.x = x
            c.y = y
            -- c.rx = SwirlEmitter.radius
            -- c.ry = SwirlEmitter.radius
            c.color = SwirlEmitter.ringColor:setAlpha(math.floor(255 * decayGlobal))
            -- c.lineWidth = 3.0
            
            c.innerRadius = SwirlEmitter.radius - 3.0
            c.outerRadius = SwirlEmitter.radius
            c.segments = 64
            c.startAngle = 0
            c.endAngle = 360
        end, ringZ + 1, layer.DrawCommandSpace.World)

        ------------------------------------------------------------
        -- 3. Update and draw swirl dots
        ------------------------------------------------------------
        for i = #self.dots, 1, -1 do
            local d = self.dots[i]
            d.age = d.age + dt
            local progress = math.min(d.age / d.life, 1.0)
            local decay = 1.0 - progress

            -- spiral motion
            d.angle = d.angle + d.swirlSpeed * dt
            d.dist  = d.dist - d.pullSpeed * dt * (0.6 + 0.4 * decay)

            if d.dist < 4 then
                table.remove(self.dots, i)
                goto continue
            end

            local px = x + math.cos(d.angle) * d.dist
            local py = y + math.sin(d.angle) * d.dist

            local dirAngle = d.angle + math.pi / 2
            local rx = d.rx * decay
            local ry = d.ry * decay

            --------------------------------------------------------
            -- draw facing ellipse
            --------------------------------------------------------
            command_buffer.queuePushMatrix(layers.sprites, function() end,
                z_orders.particle_vfx, layer.DrawCommandSpace.World)

            command_buffer.queueTranslate(layers.sprites, function(c)
                c.x = px
                c.y = py
            end, z_orders.particle_vfx, layer.DrawCommandSpace.World)

            command_buffer.queueRotate(layers.sprites, function(c)
                c.angle = math.deg(dirAngle)
            end, z_orders.particle_vfx, layer.DrawCommandSpace.World)

            command_buffer.queueDrawCenteredEllipse(layers.sprites, function(c)
                c.x = 0
                c.y = 0
                c.rx = rx
                c.ry = ry
                c.color = d.color:setAlpha(math.floor(255 * decay * decayGlobal))
                c.lineWidth = nil -- filled
            end, z_orders.particle_vfx, layer.DrawCommandSpace.World)

            command_buffer.queuePopMatrix(layers.sprites, function() end,
                z_orders.particle_vfx, layer.DrawCommandSpace.World)

            ::continue::
        end

        ------------------------------------------------------------
        -- 4. Cleanup
        ------------------------------------------------------------
        if self.age >= self.lifetime and #self.dots == 0 then
            registry:destroy(self:handle())
        end
    end

    local emitterNode = SwirlEmitter{}
    emitterNode:attach_ecs{ create_new = true }
    add_state_tag(emitterNode:handle(), ACTION_STATE)
    return emitterNode
end

---@param x number
---@param y number
---@param count integer
---@param seconds number
---@param opts table?
function particle.spawnExplosion(x, y, count, seconds, opts)
    opts = opts or {}
    local half = math.floor(count * 0.5)
    seconds = applyDurationVariance(seconds, opts.durationVariance or 0.2)


    particle.spawnRadialParticles(x, y, half, seconds * 0.8, {
        easing = opts.easing or "cubic",
        colors = opts.colors or { util.getColor("YELLOW"), util.getColor("ORANGE"), util.getColor("RED") },
        minSpeed = 200, maxSpeed = 500, renderType = particle.ParticleRenderType.CIRCLE_FILLED,
        minScale = 6, maxScale = 12, space = opts.space or "screen"
    })

    particle.spawnDirectionalCone(Vec2(x, y), count - half, seconds, {
        easing = "quad",
        direction = Vec2(0, -1),
        spread = 90,
        minSpeed = 100, maxSpeed = 250,
        gravity = 100,
        colors = opts.colors or { util.getColor("ORANGE"), util.getColor("YELLOW") },
        renderType = particle.ParticleRenderType.RECTANGLE_FILLED
    })
end

---@param x number
---@param y number
---@param count integer
---@param seconds number
---@param opts table?
function particle.spawnDirectionalStreaks(x, y, count, seconds, opts)
    opts = opts or {}
    local easing = resolveEasing(opts.easing, "cubic")
    local colorSet = opts.colors or { util.getColor("WHITE") }
    local minSpeed = opts.minSpeed or 150
    local maxSpeed = opts.maxSpeed or 350
    local minScale = opts.minScale or 8
    local maxScale = opts.maxScale or 20
    local shrink = opts.shrink or true
    local aspect = opts.aspect or 3.0
    local durationJitter = opts.durationJitter or 0.2
    local scaleJitter = opts.scaleJitter or 0.3
    local space = opts.space or "screen"
    local z = opts.z or 0

    for i = 1, count do
        local angle = math.random() * 2 * math.pi
        local dir = Vec2(math.cos(angle), math.sin(angle))
        local speed = math.random() * (maxSpeed - minSpeed) + minSpeed
        local lifespan = seconds * (1 + (math.random() * 2 - 1) * durationJitter)
        local scale = math.random() * (maxScale - minScale) + minScale
        scale = scale * (1 + (math.random() * 2 - 1) * scaleJitter)
        local color = colorSet[math.random(1, #colorSet)]

        particle.CreateParticle(
            Vec2(x, y),
            Vec2(scale, scale / aspect),
            {
                renderType = particle.ParticleRenderType.ELLIPSE_STRETCH,
                lifespan = lifespan,
                startColor = color,
                endColor = color,
                space = space,
                z = z,
                onUpdateCallback = function(comp, dt)
                    local age = comp.age or 0
                    local life = comp.lifespan or lifespan
                    local progress = math.min(age / life, 1.0)
                    local eased = easing.d(progress)
                    comp.velocity = Vec2(dir.x * speed * eased, dir.y * speed * eased)

                    if shrink then
                        local shrinkFactor = 1 - progress
                        comp.scale = math.max(0.1, scale * shrinkFactor)
                    end
                end
            }
        )
    end
end


-- shorthand
local Col = util.getColor
local Vec2 = Vec2

-- Reusable palette
local rainbow = {
    Col("RED"), Col("ORANGE"), Col("YELLOW"), Col("GREEN"),
    Col("CYAN"), Col("BLUE"), Col("PURPLE"), Col("WHITE")
}

-- Example 1: Simple 360° circular burst
function TestCircularBurst()
    particle.spawnRadialParticles(400, 400, 40, 2.0, {
        easing = "cubic",
        minSpeed = 120, maxSpeed = 400,
        minScale = 6, maxScale = 12,
        colors = rainbow,
        rotationSpeed = 180,
        space = "world"
    })
end

-- Example 2: Directional fan (0–90°)
function TestFan()
    particle.spawnRadialParticles(400, 400, 30, 2.5, {
        easing = "cubic",
        startAngle = 0,
        endAngle = 90,
        minSpeed = 200,
        maxSpeed = 400,
        minScale = 4, maxScale = 8,
        colors = { Col("WHITE"), Col("LIGHTGRAY") },
        space = "screen"
    })
end

-- Example 3: Image burst with animated sprites
function TestImageBurst()
    particle.spawnImageBurst(400, 400, 12, 1.5, "idle_animation", {
        easing = "cubic",
        minSpeed = 200, maxSpeed = 300,
        size = 20,
        loop = false,
        startColor = Col("YELLOW"),
        endColor = Col("RED")
    })
end

-- Example 4: Expanding ring
function TestRing()
    particle.spawnRing(400, 400, 60, 3.0, 40, {
        easing = "cubic",
        colors = rainbow,
        renderType = particle.ParticleRenderType.CIRCLE_LINE,
        expandFactor = 1.0
    })
end

-- Example 5: Rectangle area rain effect
function TestRectArea()
    particle.spawnRectAreaParticles(400, 300, 600, 400, 80, 2.0, {
        easing = "linear",
        minSpeed = 150,
        maxSpeed = 300,
        baseAngle = 270, -- downward
        angleSpread = 15,
        renderType = particle.ParticleRenderType.RECTANGLE_FILLED,
        colors = { Col("BLUE"), Col("SKYBLUE") }
    })
end

-- Example 6: Cone spray (smoke or steam)
function TestCone()
    particle.spawnDirectionalCone(Vec2(400, 500), 30, 3.0, {
        direction = Vec2(0, -1),
        spread = 40,
        gravity = 60,
        minSpeed = 120,
        maxSpeed = 250,
        colors = { Col("LIGHTGRAY"), Col("GRAY"), Col("WHITE") },
        easing = "cubic"
    })
end

-- Example 7: Fountain (continuous look)
function TestFountain()
    particle.spawnFountain(400, 500, 40, 3.0, {
        colors = { Col("WHITE"), Col("LIGHTGRAY"), Col("DARKGRAY") }
    })
end

-- Example 8: Explosion (mixed types)
function TestExplosion()
    particle.spawnExplosion(400, 400, 50, 2.0, {
        colors = { Col("YELLOW"), Col("ORANGE"), Col("RED") },
        space = "screen"
    })
end


-- Wraps v into the interval [−size, limit]
function wrap(v, size, limit)
  if v > limit then return -size end
  if v < -size then return limit end
  return v
end

-- simulates a hit for an entity with a shader flash effect + size wobble by 'magnitude' for 'duration' seconds
function hitFX(entity, magnitude, duration) 
  
  if not entity_cache.valid(entity) then
    log_debug("hitFX: entity is not valid, returning")
    return
  end
  
  -- if magnitude is nil, set to 1
  if not magnitude then magnitude = 1 end
  -- if duration is nil, set to 0.1
  if not duration then duration = 0.1 end
  
  -- apply a size wobble by magnitude
  -- if registry:has(entity, Transform) then
    local transformComp = component_cache.get(entity, Transform)
    transformComp.visualS = transformComp.visualS * magnitude
  -- end
  
  if registry:has(entity, shader_pipeline.ShaderPipelineComponent) == false then
    return
  end

  shaderPipelineComp = component_cache.get(entity, shader_pipeline.ShaderPipelineComponent)

  shaderPipelineComp:addPass("flash")

  -- Set per-entity flashStartTime so flash starts at white
  if not registry:has(entity, shaders.ShaderUniformComponent) then
    registry:emplace(entity, shaders.ShaderUniformComponent)
  end
  local uniforms = registry:get(entity, shaders.ShaderUniformComponent)
  uniforms:set("flash", "flashStartTime", GetTime())

  -- remove after duration, or 0.1s if not specified
  timer.after(
    duration or 0.1,
    function()
      if entity_cache.valid(entity) then
        local shaderPipelineComp = component_cache.get(entity, shader_pipeline.ShaderPipelineComponent)
        shaderPipelineComp:removePass("flash")
      end
    end
  )
end

-- Recursively prints any table (with cycle detection)
function print_table(tbl, indent, seen)
  indent = indent or "" -- current indentation
  seen   = seen or {}   -- tables we’ve already visited

  if seen[tbl] then
    print(indent .. "*<recursion>–") -- cycle detected
    return
  end
  seen[tbl] = true

  -- iterate all entries
  for k, v in pairs(tbl) do
    local key = type(k) == "string" and ("%q"):format(k) or tostring(k)
    if type(v) == "table" then
      print(indent .. "[" .. key .. "] = {")
      print_table(v, indent .. "  ", seen)
      print(indent .. "}")
    else
      -- primitive: just tostring it
      print(indent .. "[" .. key .. "] = " .. tostring(v))
    end
  end
end

-- convenience wrapper
function dump(t)
  assert(type(t) == "table", "dump expects a table")
  print_table(t)
end

-- somewhere in your init.lua, before loading ai.entity_types…
function deep_copy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == "table" then
    copy = {}
    for k, v in pairs(orig) do
      copy[deep_copy(k)] = deep_copy(v)
    end
    setmetatable(copy, deep_copy(getmetatable(orig)))
  else
    copy = orig
  end
  return copy
end


-- utility clamp if you don't already have one
local function clamp(val, min, max)
  if val < min then return min end
  if val > max then return max end
  return val
end


function buyRelicFromSlot(slot)
  -- make sure slot doesn't exceed the number of slots
  if slot < 1 or slot > #globals.currentShopSlots then
    log_debug("buyRelicFromSlot: Invalid slot number: ", slot)
    return
  end
  
  -- create animation entity, add it to the top ui box
  local currentID = globals.currentShopSlots[slot].id
  
  local relicDef = findInTable(globals.relicDefs, "id", currentID)
  
  if not relicDef then
    log_debug("buyRelicFromSlot: No relic definition found for ID: ", currentID)
    return
  end
  
  -- check if the player has enough currency
  if globals.currency < relicDef.costToBuy then
    log_debug("buyRelicFromSlot: Not enough currency to buy relic: ", currentID)
    
    playSoundEffect("effects", "cannot-buy") -- play button click sound
    newTextPopup(
      localization.get("ui.not_enough_currency"),
      globals.screenWidth() / 2,
      globals.screenHeight() / 4,
      5, -- duration in seconds
      "color=fiery_red" -- effect string
    )
    return
  end
  
  playSoundEffect("effects", "shop-buy") -- play button click sound
  
  -- deduct the cost from the player's currency
  globals.currency = globals.currency - relicDef.costToBuy
  log_debug("buyRelicFromSlot: Bought relic: ", currentID, " for ", relicDef.costToBuy, " currency. Remaining currency: ", globals.currency)
  
  -- create the animation entity for the relic
  local relicAnimationEntity = animation_system.createAnimatedObjectWithTransform(
    relicDef.spriteID, -- sprite ID for the relic
    true               -- use animation, not sprite identifier, if false
  )
  
  -- animation_system.resizeAnimationObjectsInEntityToFit(
  --   relicAnimationEntity,
  --   globals.tileSize, -- width
  --   globals.tileSize  -- height
  -- )
  
  -- add hover tooltip
  local gameObject = component_cache.get(relicAnimationEntity, GameObject)
  gameObject.methods.onHover = function()
    log_debug("Relic hovered: ", relicDef.id)
    if showSimpleTooltipAbove then
      showSimpleTooltipAbove(
        "relic_" .. relicDef.id,
        localization.get(relicDef.localizationKeyName),
        localization.get(relicDef.localizationKeyDesc),
        relicAnimationEntity
      )
    end
  end
  gameObject.methods.onStopHover = function()
    if hideSimpleTooltip then hideSimpleTooltip("relic_" .. relicDef.id) end
  end
  gameObject.state.hoverEnabled = true
  gameObject.state.collisionEnabled = true
  
  
  -- wrap the animation entity 
  local uie = ui.definitions.wrapEntityInsideObjectElement(
    relicAnimationEntity -- entity to wrap
  )
  
  -- make new ui row
  local uieRow = UIElementTemplateNodeBuilder.create()
        :addType(UITypeEnum.HORIZONTAL_CONTAINER)
        :addConfig(
            UIConfigBuilder.create()
                :addColor(util.getColor("blank"))
                -- :addShadow(true) --- IGNORE ---
                -- :addEmboss(4.0)
                :addPadding(0)
                :addAlign(bit.bor(AlignmentFlag.HORIZONTAL_CENTER , AlignmentFlag.VERTICAL_CENTER))
                :addInitFunc(function(registry, entity)
                    -- something init-related here
                end)
                :build()
        )
        -- add all relic button defs to the row
        :addChild(uie)
        :build()
  
  globals.ui.relicsUIElementRow = ui.box.GetUIEByID(registry, globals.ui.relicsUIBox, "relics_row")
  log_debug("buyRelicFromSlot: Wrapped entity inside UI element row: ", globals.ui.relicsUIElementRow)
  
  --TODO: add to top bar and renew alignment
  -- local gameobjectCompTopBar = component_cache.get(globals.ui.relicsUIElementRow, GameObject)
  -- gameobjectCompTopBar.orderedChildren:add(uie) -- add the wrapped entity to the top bar UI element row
  
  --TODO: document that AddTemplateToUIBox must take a row
  ui.box.AddTemplateToUIBox(
    registry,
    globals.ui.relicsUIBox,
    uieRow, -- def to add
    globals.ui.relicsUIElementRow -- parent UI element row to add to
  )
  
  ui.box.RenewAlignment(registry, globals.ui.relicsUIBox) -- re-align the relics UI element row
  
  -- add to the ownedRelics, run the onBuyCallback
  
  table.insert(globals.ownedRelics, {
    id = relicDef.id,
    entity = uie
  })
  -- log_debug("buyRelicFromSlot: Added relic to ownedRelics: ", lume.serialize(globals.ownedRelics))
  
  if relicDef.onBuyCallback then
    relicDef.onBuyCallback() -- run the onBuyCallback if it exists
  end
end

function handleNewDay()
  
  -- every 3 days, we have a weather event 
  globals.timeUntilNextWeatherEvent = globals.timeUntilNextWeatherEvent + 1
  if globals.timeUntilNextWeatherEvent >= 1 then
    globals.timeUntilNextWeatherEvent = 0 -- reset the timer
    -- trigger a weather event
    globals.current_weather_event = globals.weather_event_defs[math.random(1, #globals.weather_event_defs)].id -- pick a random weather event
    
    -- increment the base damage of the weather event
    globals.current_weather_event_base_damage = globals.current_weather_event_base_damage * 2
  end
  
  playSoundEffect("effects", "end-of-day") -- play button click sound
  
  -- select 3 random items for the shop.
  
  lume.clear(globals.currentShopSlots) -- clear the current shop slots
  
  globals.currentShopSlots[1] = { id = lume.randomchoice(globals.relicDefs).id}
  globals.currentShopSlots[2] = { id = lume.randomchoice(globals.relicDefs).id}
  globals.currentShopSlots[3] = { id = lume.randomchoice(globals.relicDefs).id}
  
  log_debug("Current shop slots: ", lume.serialize(globals.currentShopSlots))
  
  --TODO: now populate the shop ui
  
  -- relic1ButtonAnimationEntity
  
  local relicDef = findInTable(globals.relicDefs, "id", globals.currentShopSlots[1].id)
  
  animation_system.replaceAnimatedObjectOnEntity(
    globals.ui["relic1ButtonAnimationEntity"],
    relicDef.spriteID, -- Default animation ID
    true,               -- ? generate a new still animation from sprite, don't set to true, causes bug
    nil,                 -- shader_prepass, -- Optional shader pass config function
    true                 -- Enable shadow
  )
  animation_system.resizeAnimationObjectsInEntityToFit(
    globals.ui["relic1ButtonAnimationEntity"],
    globals.tileSize, -- width
    globals.tileSize  -- height
  )
  
  -- relic1TextEntity
  log_debug("Setting text for relic1TextEntity to: ", localization.get(relicDef.localizationKeyName), "with key: ", relicDef.localizationKeyName)
  TextSystem.Functions.setText(globals.ui["relic1TextEntity"], localization.get(relicDef.localizationKeyName))
  
  -- relic1CostTextEntity
  local costText = "".. relicDef.costToBuy
  TextSystem.Functions.setText(globals.ui["relic1CostTextEntity"], costText)
  
  -- fetch ui element
  local uiElement1 = ui.box.GetUIEByID(registry, globals.ui.weatherShopUIBox, "relic1UIElement")
  
  -- add hover 
  local gameObject1 = component_cache.get(uiElement1, GameObject)
  local relicDef1 = relicDef
  gameObject1.methods.onHover = function()
    log_debug("Relic 1 hovered!")
    if showSimpleTooltipAbove then
      showSimpleTooltipAbove(
        "shop_relic_1",
        localization.get(relicDef1.localizationKeyName),
        localization.get(relicDef1.localizationKeyDesc),
        uiElement1
      )
    end
  end
  gameObject1.methods.onStopHover = function()
    if hideSimpleTooltip then hideSimpleTooltip("shop_relic_1") end
  end
  
  -- add button callback
  local uieUIConfig1 = component_cache.get(uiElement1, UIConfig)
  -- enable button
  uieUIConfig1.disable_button = false -- enable the button
  uieUIConfig1.buttonCallback = function()
    log_debug("Relic 1 button clicked!")
    buyRelicFromSlot(1) -- buy the relic from slot 1
    -- disable the button
    local uiConfig = component_cache.get(uiElement1, UIConfig)
    uiConfig.disable_button = true -- disable the button
  end
  -- relic2ButtonAnimationEntity
  relicDef = findInTable(globals.relicDefs, "id", globals.currentShopSlots[2].id)
  animation_system.replaceAnimatedObjectOnEntity(
    globals.ui["relic2ButtonAnimationEntity"],
    relicDef.spriteID, -- Default animation ID
    true,               -- ? generate a new still animation from sprite, don't set to true, causes bug
    nil,                 -- shader_prepass, -- Optional shader pass config function
    true                 -- Enable shadow
  )
  animation_system.resizeAnimationObjectsInEntityToFit(
    globals.ui["relic2ButtonAnimationEntity"],
    globals.tileSize, -- width
    globals.tileSize  -- height
  )
  -- relic2TextEntity
  log_debug("Setting text for relic2TextEntity to: ", localization.get(relicDef.localizationKeyName), "with key: ", relicDef.localizationKeyName)
  TextSystem.Functions.setText(globals.ui["relic2TextEntity"], localization.get(relicDef.localizationKeyName))
  
  -- relic2CostTextEntity
  local costText = "".. relicDef.costToBuy
  TextSystem.Functions.setText(globals.ui["relic2CostTextEntity"], costText)
  -- fetch ui element
  
  local uiElement2 = ui.box.GetUIEByID(registry, globals.ui.weatherShopUIBox, "relic2UIElement")
  -- add hover
  local gameObject2 = component_cache.get(uiElement2, GameObject)
  local relicDef2 = relicDef
  gameObject2.methods.onHover = function()
    log_debug("Relic 2 hovered!")
    if showSimpleTooltipAbove then
      showSimpleTooltipAbove(
        "shop_relic_2",
        localization.get(relicDef2.localizationKeyName),
        localization.get(relicDef2.localizationKeyDesc),
        uiElement2
      )
    end
  end
  gameObject2.methods.onStopHover = function()
    if hideSimpleTooltip then hideSimpleTooltip("shop_relic_2") end
  end
  
  -- enable button
  -- add button callback
  local uieUIConfig2 = component_cache.get(uiElement2, UIConfig)
  uieUIConfig2.disable_button = false -- enable the button
  uieUIConfig2.buttonCallback = function()
    log_debug("Relic 2 button clicked!")
    buyRelicFromSlot(2) -- buy the relic from slot 2
    -- disable the button
    local uiConfig = component_cache.get(uiElement2, UIConfig)
    uiConfig.disable_button = true -- disable the button
  end
  -- relic3ButtonAnimationEntity
  relicDef = findInTable(globals.relicDefs, "id", globals.currentShopSlots[3].id)
  animation_system.replaceAnimatedObjectOnEntity(
    globals.ui["relic3ButtonAnimationEntity"],
    relicDef.spriteID, -- Default animation ID
    true,               -- ? generate a new still animation from sprite, don't set to true, causes bug
    nil,                 -- shader_prepass, -- Optional shader pass config function
    true                 -- Enable shadow
  )
  animation_system.resizeAnimationObjectsInEntityToFit(
    globals.ui["relic3ButtonAnimationEntity"],
    globals.tileSize, -- width
    globals.tileSize  -- height
  )
  -- relic3TextEntity
  log_debug("Setting text for relic3TextEntity to: ", localization.get(relicDef.localizationKeyName), "with key: ", relicDef.localizationKeyName)
  TextSystem.Functions.setText(globals.ui["relic3TextEntity"], localization.get(relicDef.localizationKeyName))
  
  -- relic3CostTextEntity
  local costText = "".. relicDef.costToBuy
  TextSystem.Functions.setText(globals.ui["relic3CostTextEntity"], costText)
  -- fetch ui element
  local uiElement3 = ui.box.GetUIEByID(registry, globals.ui.weatherShopUIBox, "relic3UIElement")
  -- add hover
  local gameObject3 = component_cache.get(uiElement3, GameObject)
  local relicDef3 = relicDef
  gameObject3.methods.onHover = function()
    log_debug("Relic 3 hovered!")
    if showSimpleTooltipAbove then
      showSimpleTooltipAbove(
        "shop_relic_3",
        localization.get(relicDef3.localizationKeyName),
        localization.get(relicDef3.localizationKeyDesc),
        uiElement3
      )
    end
  end
  gameObject3.methods.onStopHover = function()
    if hideSimpleTooltip then hideSimpleTooltip("shop_relic_3") end
  end
  -- add button callback
  local uieUIConfig3 = component_cache.get(uiElement3, UIConfig)
  uieUIConfig3.disable_button = false -- enable the button
  uieUIConfig3.buttonCallback = function()
    log_debug("Relic 3 button clicked!")
    buyRelicFromSlot(3) -- buy the relic from slot 3
    -- disable the button
    local uiConfig = component_cache.get(uiElement3, UIConfig)
    uiConfig.disable_button = true -- disable the button
  end
  ui.box.RenewAlignment(registry, globals.ui.weatherShopUIBox) -- re-align the shop UI box
  
  -- update shop uiboxTransform to centered
  local shopUIBoxTransform = component_cache.get(globals.ui.weatherShopUIBox, Transform)
  shopUIBoxTransform.actualX = globals.screenWidth() / 2 - shopUIBoxTransform.actualW / 2
  shopUIBoxTransform.visualX = shopUIBoxTransform.actualX -- snap X
  shopUIBoxTransform.actualY = globals.screenHeight() / 2 - shopUIBoxTransform.actualH / 2
  shopUIBoxTransform.visualY = shopUIBoxTransform.actualY -- snap Y
  -- refer to this:
  
--   local relicSlots = {
--     {id = "relic1", spriteID = "4165-TheRoguelike_1_10_alpha_958.png", text = "ui.relic_slot_1", animHandle = "relic1ButtonAnimationEntity", textHandle = "relic1TextEntity"},
--     {id = "relic2", spriteID = "4169-TheRoguelike_1_10_alpha_962.png", text = "ui.relic_slot_2", animHandle = "relic2ButtonAnimationEntity", textHandle = "relic2TextEntity"},
--     {id = "relic3", spriteID = "4054-TheRoguelike_1_10_alpha_847.png", text = "ui.relic_slot_3", animHandle = "relic3ButtonAnimationEntity", textHandle = "relic3TextEntity"},
-- }

-- local weatherButtonDefs = {}

-- -- populate weatherButtonDefs based on weatherEvents
-- for _, event in ipairs(relicSlots) do

--     -- TODO: so these are stored under globals.ui["relic1TextEntity"] globals.ui["relic1ButtonAnimationEntity"] and so on, we will access these later
--     local buttonDef = createStructurePlacementButton(
--         event.spriteID, -- sprite ID for the weather event
--         event.animHandle, -- global animation handle
--         event.textHandle, -- global text handle
--         event.text, -- localization key for text
--         event.cost -- cost to buy the weather event
--     )
--     -- add buttonDef to weatherButtonDefs
--     table.insert(weatherButtonDefs, buttonDef)
-- end
  
  
  timer.after(
    1.0, -- delay in seconds
    function()
      -- set hours and minutes to 0
      globals.game_time.hours = 0
      globals.game_time.minutes = 0
      ai.pause_ai_system()   -- pause the AI system
      togglePausedState(true)
      -- show the new day message
      if entity_cache.valid(globals.ui.newDayUIBox) then
        local shopTransform = component_cache.get(globals.ui.weatherShopUIBox, Transform)
        
        local transformComp = component_cache.get(globals.ui.newDayUIBox, Transform)
        transformComp.actualY = globals.screenHeight() / 2 - shopTransform.actualH / 2 - transformComp.actualH  + 10 -- show above the shop UI box
        -- cneter x
        transformComp.actualX = globals.screenWidth() / 2 - transformComp.actualW / 2
        transformComp.visualX = transformComp.actualX -- snap X
      end
      
      -- for each healer & damage cushion, detract currency and show text popup
      for _, healerEntry in ipairs(globals.healers) do
        
        local transformComp = component_cache.get(healerEntry, Transform)
        local healerDef = findInTable(globals.creature_defs, "id", "healer")
        local maintenance_cost = healerDef.maintenance_cost
        
        -- show text popup at the location of the healer
        newTextPopup(
          "-"..maintenance_cost,
          transformComp.actualX + transformComp.actualW / 2,
          transformComp.actualY + transformComp.actualH / 2,
          4.0, -- duration in seconds
          "color=fiery_red;slide" -- effect string
        )
        
        --- detract the currency from the player's resources
        globals.currency = globals.currency - maintenance_cost
      end
      
      for _, damageCushionEntry in ipairs(globals.damage_cushions) do
        
        local transformComp = component_cache.get(damageCushionEntry, Transform)
        local damageCushionDef = findInTable(globals.creature_defs, "id", "damage_cushion")
        local maintenance_cost = damageCushionDef.maintenance_cost
        
        -- show text popup at the location of the damage cushion
        newTextPopup(
          "-"..maintenance_cost,
          transformComp.actualX + transformComp.actualW / 2,
          transformComp.actualY + transformComp.actualH / 2,
          4.0, -- duration in seconds
          "color=fiery_red;slide" -- effect string
        )
        
        --- detract the currency from the player's resources
        globals.currency = globals.currency - maintenance_cost
      end
      
      -- for each colonist home, add a coin image to the location, tween it to the currency ui, then vanish it. Then add the currency to the player's resources
      for _, colonistHomeEntry in ipairs(globals.structures.colonist_homes) do
        
        -- add a coin image to the location of the colonist home
        local coinImage = animation_system.createAnimatedObjectWithTransform(
          "4024-TheRoguelike_1_10_alpha_817.png", -- animation ID
          true             -- use animation, not sprite identifier, if false
        )
        animation_system.resizeAnimationObjectsInEntityToFit(
          coinImage,
            globals.tileSize,   -- width
            globals.tileSize    -- height
        )
        
        playSoundEffect("effects", "gold-gain") -- play coin sound effect
        
        local coinTansformComp = component_cache.get(coinImage, Transform)
        
        -- text popup at the location of the colonist home
        newTextPopup(
          "+"..math.floor(findInTable(
            globals.structure_defs,
            "id",
            "colonist_home"
          ).currency_per_day * globals.end_of_day_gold_multiplier),
          coinTansformComp.actualX * globals.tileSize + globals.tileSize / 2,
          coinTansformComp.actualY * globals.tileSize + globals.tileSize / 2,
          1.0, -- duration in seconds
          "color=marigold" -- effect string
        )
        
        local transformComp = component_cache.get(coinImage, Transform)
        local t = component_cache.get(colonistHomeEntry.entity, Transform)
        -- align above the home
        transformComp.actualX = t.actualX + t.actualW / 2 - transformComp.actualW / 2
        transformComp.actualY = t.actualY - transformComp.actualH / 2 - 5
        transformComp.visualX = transformComp.actualX -- snap X
        transformComp.visualY = transformComp.actualY -- snap Y
        
        -- spawn particles at the center of the coin image
        spawnCircularBurstParticles(
          transformComp.actualX + transformComp.actualW / 2,
          transformComp.actualY + transformComp.actualH / 2,
          10, -- number of particles
          0.3 -- particle size
        )
        
        timer.after(
          1.1,
          function()
            playSoundEffect("effects", "money-to-cash-pile") -- play coin sound effect
            if not entity_cache.valid(coinImage) then
              log_debug("Coin image entity is not valid, skipping tweening")
              return
            end
            
            
            -- tween the coin image to the currency UI box
            local uiBoxTransform = component_cache.get(globals.ui.currencyUIBox, Transform)
            local transformComp = component_cache.get(coinImage, Transform)
            transformComp.actualX = uiBoxTransform.actualX + uiBoxTransform.actualW / 2 - transformComp.actualW / 2
            transformComp.actualY = uiBoxTransform.actualY + uiBoxTransform.actualH / 2 - transformComp.actualH / 2
            
            
            
          end
        )
        
        -- delete it after 0.5 seconds
        timer.after(
          2.2, -- delay in seconds
          function()
            if entity_cache.valid(coinImage) then
              registry:destroy(coinImage) -- remove the coin image entity
            end
            -- add the currency to the player's resources
            globals.currency = globals.currency + math.floor(findInTable(
              globals.structure_defs,
              "id",
              "colonist_home"
            ).currency_per_day * globals.end_of_day_gold_multiplier) -- add the currency per day for the colonist home
          end
        )
      end

      -- after 1 second, hide the new day message and show the shop menu
      timer.after(
        3.6,     -- delay in seconds
        function()
          if entity_cache.valid(globals.ui.newDayUIBox) then
            local transformComp = component_cache.get(globals.ui.newDayUIBox, Transform)
            transformComp.actualY = globals.screenHeight()
            -- center x
            transformComp.actualX = globals.screenWidth() / 2 - transformComp.actualW / 2
            transformComp.visualX = transformComp.actualX -- snap X
          end

          toggleShopWindow()       -- toggle the shop window
        end
      )
    end
  )
end


function toggleShopWindow()
  if (globals.isShopOpen) then
    globals.isShopOpen = false
    local transform = component_cache.get(globals.ui.weatherShopUIBox, Transform)
    transform.actualY = globals.screenHeight() -- hide the shop UI box
  else
    globals.isShopOpen = true
    local transform = component_cache.get(globals.ui.weatherShopUIBox, Transform)
    transform.actualY = globals.screenHeight() / 2 - transform.actualH / 2 -- show the shop UI box
  end
  local transform = component_cache.get(globals.ui.weatherShopUIBox, Transform)
  -- center x
  transform.actualX = globals.screenWidth() / 2 - transform.actualW / 2
  transform.visualX = transform.actualX -- snap X
end

function showNewAchievementPopup(achievementID)
  if not globals.ui.newAchievementUIBox then
    log_debug("showNewAchievementPopup: newAchievementUIBox is not set up, skipping")
    return
  end

  -- get the achievement definition
  local achievementDef = findInTable(globals.achievements, "id", achievementID)

  -- replace the animation
  animation_system.replaceAnimatedObjectOnEntity(
    globals.ui.achievementIconEntity,
    achievementDef.anim, -- Default animation ID
    false,               -- ? generate a new still animation from sprite, don't set to true, causes bug
    nil,                 -- shader_prepass, -- Optional shader pass config function
    true                 -- Enable shadow
  )
  animation_system.resizeAnimationObjectsInEntityToFit(
    globals.ui.achievementIconEntity,
    60, -- width
    60  -- height
  )

  -- set tooltip
  local gameObject = component_cache.get(globals.ui.achievementIconEntity, GameObject)
  gameObject.methods.onHover = function()
    achievementDef.tooltipFunc()
  end
  -- gameObject.methods.onStopHover = function()
  --   hideTooltip()
  -- end
  gameObject.state.hoverEnabled = true
  gameObject.state.collisionEnabled = true

  -- renew the alignment of the achievement UI box
  -- ui.box.RenewAlignment(registry, globals.ui.newAchievementUIBox)

  -- play sound
  playSoundEffect("effects", "new_achievement")

  -- if not already at bottom of the screen, move it to the center
  local transformComp = component_cache.get(globals.ui.newAchievementUIBox, Transform)
  transformComp.actualX = globals.screenWidth() / 2 - transformComp.actualW / 2
  transformComp.visualX = transformComp.actualX -- snap X
  transformComp.actualY = globals.screenHeight() / 2 - transformComp.actualH / 2


  -- spawn particles at the center of the box
  spawnCircularBurstParticles(
    transformComp.actualX + transformComp.actualW / 2,
    transformComp.actualY + transformComp.actualH / 2,
    40, -- number of particles
    0.5 -- particle size
  )

  -- dismiss after 5 seconds
  timer.after(
    5.0, -- delay in seconds
    function()
      log_debug("Dismissing achievement popup: ", achievementID)
      -- move the box out of the screen
      local transformComp = component_cache.get(globals.ui.newAchievementUIBox, Transform)
      transformComp.actualY = globals.screenHeight() + 500
    end,
    "dismiss_achievement_popup" -- timer name
  )
end

function centerTransformOnScreen(entity)
  -- center the transform of the entity on the screen
  local transformComp = component_cache.get(entity, Transform)
  transformComp.actualX = globals.screenWidth() / 2 - transformComp.actualW / 2
  transformComp.visualX = transformComp.actualX -- snap X
  transformComp.actualY = globals.screenHeight() / 2 - transformComp.actualH / 2
  transformComp.visualY = transformComp.actualY -- snap Y
end

function newTextPopup(textString, x, y, duration, effectString)
  -- 1) spawn the dynamic text entry
  local entry = ui.definitions.getNewDynamicTextEntry(
    function() return textString end,  -- initial text
    30.0,                              -- font size
    effectString or ""                          -- animation spec
  )
  local entity = entry.config.object

  -- 2) fetch its transform and its size (set by the text system)
  local tc = component_cache.get(entity, Transform)
  local w, h = tc.actualW or 0, tc.actualH or 0

  -- 3) default to center-screen if no x/y passed
  x = x or (globals.screenWidth()  / 2)
  y = y or (globals.screenHeight() / 2) - 100

  -- 4) shift so that (x,y) is the center
  tc.actualX = x - w * 0.5
  tc.actualY = y - h * 0.5
  tc.visualX = tc.actualX
  tc.visualY = tc.actualY

  -- 5) give it some jiggle/motion
  -- transform.InjectDynamicMotion(entity, 0.7, 0)
  
  timer.for_time(
    duration and duration - .2 or 1.8, -- duration in seconds
    function()
      -- move text slowly upward
      local tc2 = component_cache.get(entity, Transform)
      if tc2 then
        tc2.actualY = tc2.actualY - 30 * GetFrameTime()
      end
      
      local textComp = component_cache.get(entity, TextSystem.Text)
      if textComp then
        textComp.globalAlpha = textComp.globalAlpha - 0.1 * GetFrameTime() -- fade out the text
      end
    end,
    nil
  )

  -- 6) after duration, burst and destroy
  timer.after(duration or 2.0, function()
    local tc2 = component_cache.get(entity, Transform)
    if tc2 then
      spawnCircularBurstParticles(
        tc2.actualX + tc2.actualW * 0.5,
        tc2.actualY + tc2.actualH * 0.5,
        5, 0.2
      )
    end
    if entity_cache.valid(entity) then
      registry:destroy(entity)
    end
  end)
end

-- increment converter ui index and set up ui. use 0 to just set up the ui without changing the index
function cycleConverter(inc)
  -- 1) adjust the selected index by inc (can be  1, 0 or -1)
  globals.selectedConverterIndex = globals.selectedConverterIndex + inc
  if globals.selectedConverterIndex > #globals.converter_defs then
    globals.selectedConverterIndex = 1
  elseif globals.selectedConverterIndex < 1 then
    globals.selectedConverterIndex = #globals.converter_defs
  end
  log_debug("Selected converter index: ", globals.selectedConverterIndex)

  -- 2) figure out locked state & tooltip text
  local locked = not globals.converter_defs[globals.selectedConverterIndex].unlocked
  local title, body
  if locked then
    title                   = localization.get("ui.converter_locked_title")
    local requirementString = getRequirementStringForBuildingOrConverter(globals.converter_defs
      [globals.selectedConverterIndex])
    body                    = localization.get("ui.converter_locked_body") .. requirementString
  else
    local costString        = getCostStringForBuildingOrConverter(globals.converter_defs[globals.selectedConverterIndex])
    local requirementString = getRequirementStringForBuildingOrConverter(globals.converter_defs
      [globals.selectedConverterIndex])
    title                   = localization.get(globals.converter_defs[globals.selectedConverterIndex].ui_text_title)
    body                    = localization.get(globals.converter_defs[globals.selectedConverterIndex].ui_text_body) ..
        costString .. requirementString
  end

  log_debug("hookup hover callbacks for converter entity: ", globals.converter_ui_animation_entity)
  -- 3) hook up hover callbacks
  local converterEntity                   = globals.converter_ui_animation_entity
  local converterGameObject               = component_cache.get(converterEntity, GameObject)
  converterGameObject.methods.onHover     = function()
    log_debug("Converter entity hovered!")
    if showSimpleTooltipAbove then
      showSimpleTooltipAbove("converter_ui", title, body, converterEntity)
    end
  end
  converterGameObject.methods.onStopHover = function()
    log_debug("Converter entity stopped hovering!")
    if hideSimpleTooltip then
      hideSimpleTooltip("converter_ui")
    end
  end

  -- 4) immediately show it once
  -- showTooltip(title, body)

  log_debug("swap the animation for converter entity: ", globals.converter_ui_animation_entity)
  -- 5) swap the animation
  local animToShow = globals.converter_defs[globals.selectedConverterIndex].unlocked
      and globals.converter_defs[globals.selectedConverterIndex].anim
      or "locked_upgrade_anim"
  animation_system.replaceAnimatedObjectOnEntity(
    globals.converter_ui_animation_entity,
    animToShow,
    false,
    nil, -- shader_prepass, -- Optional shader pass config function
    true -- Enable shadow
  )

  -- 6) add a jiggle
  transform.InjectDynamicMotion(globals.converter_ui_animation_entity, 0.7, 16)
end

function cycleBuilding(inc)
  -- 1) adjust the selected index by inc (can be  1, 0 or -1)
  globals.selectedBuildingIndex = globals.selectedBuildingIndex + inc
  if globals.selectedBuildingIndex > #globals.building_upgrade_defs then
    globals.selectedBuildingIndex = 1
  elseif globals.selectedBuildingIndex < 1 then
    globals.selectedBuildingIndex = #globals.building_upgrade_defs
  end
  log_debug("Selected converter index: ", globals.selectedBuildingIndex)

  -- 2) figure out locked state & tooltip text
  local locked = not globals.building_upgrade_defs[globals.selectedBuildingIndex].unlocked
  local title, body
  if locked then
    title                   = localization.get("ui.building_locked_title")
    local requirementString = getRequirementStringForBuildingOrConverter(globals.building_upgrade_defs
      [globals.selectedBuildingIndex])
    body                    = localization.get("ui.building_locked_body") .. requirementString
  else
    local costString = getCostStringForBuildingOrConverter(globals.building_upgrade_defs[globals.selectedBuildingIndex])
    local requirementString = getRequirementStringForBuildingOrConverter(globals.building_upgrade_defs
      [globals.selectedBuildingIndex])
    log_debug("Cost string for building: ", costString)
    title = localization.get(globals.building_upgrade_defs[globals.selectedBuildingIndex].ui_text_title)
    body  = localization.get(globals.building_upgrade_defs[globals.selectedBuildingIndex].ui_text_body) ..
        costString .. requirementString
  end

  -- 3) hook up hover callbacks
  local converterEntity                   = globals.building_ui_animation_entity
  local converterGameObject               = component_cache.get(converterEntity, GameObject)
  converterGameObject.methods.onHover     = function()
    if showSimpleTooltipAbove then
      showSimpleTooltipAbove("building_ui", title, body, converterEntity)
    end
  end
  converterGameObject.methods.onStopHover = function()
    if hideSimpleTooltip then
      hideSimpleTooltip("building_ui")
    end
  end

  -- 4) immediately show it once
  -- showTooltip(title, body)

  -- 5) swap the animation
  local animToShow                        = globals.building_upgrade_defs[globals.selectedBuildingIndex].unlocked
      and globals.building_upgrade_defs[globals.selectedBuildingIndex].anim
      or "locked_upgrade_anim"
  animation_system.replaceAnimatedObjectOnEntity(
    globals.building_ui_animation_entity,
    animToShow,
    false
  )

  -- 6) add a jiggle
  transform.InjectDynamicMotion(globals.building_ui_animation_entity, 0.7, 16)
end

function buyConverterButtonCallback()
  -- id of currently selected converter
  local selectedConverter = globals.converter_defs[globals.selectedConverterIndex]

  local uiTransformComp = component_cache.get(globals.converter_ui_animation_entity, Transform)

  if not selectedConverter.unlocked then
    log_debug("Converter is not unlocked yet!")
    newTextPopup(
      localization.get("ui.not_unlocked_msg"),
      uiTransformComp.actualX + uiTransformComp.actualW / 2,
      uiTransformComp.actualY - uiTransformComp.actualH * 2.5,
      2
    )
    playSoundEffect("effects", "cannot-buy")
    return
  end

  -- check if the player has enough resources to buy the converter
  local cost = selectedConverter.cost
  for currency, amount in pairs(cost) do
    if globals.currencies[currency].target < amount then
      log_debug("Not enough", currency, "to buy converter", selectedConverter.id)
      newTextPopup(
        localization.get("ui.not_enough_currency"),
        uiTransformComp.actualX + uiTransformComp.actualW / 2,
        uiTransformComp.actualY - uiTransformComp.actualH * 2.5,
        2
      )
      playSoundEffect("effects", "cannot-buy")
      return
    end
  end

  -- deduct the cost from the player's resources
  for currency, amount in pairs(cost) do
    globals.currencies[currency].target = globals.currencies[currency].target - amount
    log_debug("Deducted", amount, currency, "from player's resources")
  end


  -- create a new example converter entity
  local exampleConverter = create_ai_entity("kobold")

  -- add the converter to the end of the table in the converters table with the id of the converter
  table.insert(globals.converters[selectedConverter.id], exampleConverter)
  log_debug("Added converter entity to globals.converters: ", exampleConverter, " for id: ", selectedConverter.id)

  animation_system.setupAnimatedObjectOnEntity(
    exampleConverter,
    selectedConverter.anim, -- Default animation ID
    false,                  -- ? generate a new still animation from sprite, don't set to true, causes bug
    nil,                    -- shader_prepass, -- Optional shader pass config function
    true                    -- Enable shadow
  )

  animation_system.resizeAnimationObjectsInEntityToFit(
    exampleConverter,
    60, -- width
    60  -- height
  )

  -- make the object draggable
  local gameObjectState = component_cache.get(exampleConverter, GameObject).state
  gameObjectState.dragEnabled = true
  gameObjectState.clickEnabled = true
  gameObjectState.hoverEnabled = true
  gameObjectState.collisionEnabled = true

  -- create a new text entity
  local infoText = ui.definitions.getNewDynamicTextEntry(
    function() return localization.get("ui.drag_me") end, -- initial text
    15.0,                                                 -- font size
    "bump"                                                -- animation spec
  ).config.object

  -- make the text entity follow the converter entity
  local transformComp = component_cache.get(exampleConverter, Transform)
  transform.AssignRole(registry, infoText, InheritedPropertiesType.RoleInheritor, exampleConverter,
    InheritedPropertiesSync.Strong,
    InheritedPropertiesSync.Strong,
    InheritedPropertiesSync.Strong,
    InheritedPropertiesSync.Strong,
    Vec2(0, -20) -- offset the text above the converter
  );

  -- local textRole = component_cache.get(infoText, InheritedProperties)
  -- textRole.flags = AlignmentFlag.HORIZONTAL_CENTER | AlignmentFlag.VERTICAL_TOP

  playSoundEffect("effects", "buy-building")

  -- now locate the converter entity in the game world

  transformComp.actualX = globals.screenWidth() / 2 - transformComp.actualW / 2 -- center it horizontally
  transformComp.actualY = globals.screenHeight() - 300


  -- add onstopdrag method to the converter entity
  local gameObjectComp = component_cache.get(exampleConverter, GameObject)
  gameObjectComp.methods.onHover = function()
    log_debug("Converter entity hovered! WHy not drag?")
  end
  gameObjectComp.methods.onStopDrag = function()
    log_debug("Converter entity stopped dragging!")
    local gameObjectComp = component_cache.get(exampleConverter, GameObject)
    local transformComp = component_cache.get(exampleConverter, Transform)
    local gameObjectState = gameObjectComp.state
    -- get the grid that it's in, grid is 64 pixels wide
    local gridX = math.floor(transformComp.actualX / 64)
    local gridY = math.floor(transformComp.actualY / 64)
    log_debug("Converter entity is in grid: ", gridX, gridY)
    -- snap the entity to the grid, but center it in the grid cell
    local magic_padding = 2
    transformComp.actualX = gridX * 64 + 32 - transformComp.actualW / 2 + magic_padding -- center it in the grid cell
    transformComp.actualY = gridY * 64 + 32 - transformComp.actualH / 2 + magic_padding -- center it in the grid cell
    -- make the entity no longer draggable
    gameObjectState.dragEnabled = false
    gameObjectState.clickEnabled = false
    gameObjectState.hoverEnabled = true
    gameObjectState.collisionEnabled = true

    -- play sound
    playSoundEffect("effects", "place-building")

    -- remove the text entity
    registry:destroy(infoText)
    -- spawn particles at the converter's position center
    spawnCircularBurstParticles(
      transformComp.actualX + transformComp.actualW / 2,
      transformComp.actualY + transformComp.actualH / 2,
      20, -- number of particles
      0.5 -- particle size
    )
    transform.InjectDynamicMotion(exampleConverter, 1.0, 1)
    log_debug("add on hover/stop hover methods to the converter entity")
    -- add on hover/stop hover methods to the building entity
    gameObjectComp.methods.onHover = function()
      if showSimpleTooltipAbove then
        showSimpleTooltipAbove(
          "converter_" .. selectedConverter.id,
          localization.get(selectedConverter.ui_text_title),
          localization.get(selectedConverter.ui_text_body),
          exampleConverter
        )
      end
    end
    gameObjectComp.methods.onStopHover = function()
      log_debug("Converter entity stopped hovering!")
      if hideSimpleTooltip then
        hideSimpleTooltip("converter_" .. selectedConverter.id)
      end
    end
  end
end

function getRequirementStringForBuildingOrConverter(def)
  local reqString = "\nRequirements:\n"

  -- 1) currency requirements
  if def.required_currencies then
    for currencyKey, amount in pairs(def.required_currencies) do
      log_debug("Requirement currency:", currencyKey, "amount:", amount)
      local currencyName = globals.currencies[currencyKey].human_readable_name
      reqString = reqString
          .. localization.get(
            "ui.requirement_unlock_postfix",
            { number = amount, requirement = currencyName }
          )
    end
  end

  -- 2) building or converter requirements
  if def.required_building_or_converter then
    for reqId, amount in pairs(def.required_building_or_converter) do
      log_debug("Requirement building/converter:", reqId, "amount:", amount)
      -- look up the human‐readable name
      local reqDef = findInTable(globals.building_upgrade_defs, "id", reqId)
          or findInTable(globals.converter_defs, "id", reqId)
      local reqName = localization.get(reqDef.ui_text_title)
      reqString = reqString
          .. localization.get(
            "ui.requirement_unlock_postfix",
            { number = amount, requirement = reqName }
          )
    end
  end

  return reqString
end

function getCostStringForBuildingOrConverter(buildingOrConverterDef)
  local costString = "\nCost:\n"
  local cost = buildingOrConverterDef.cost
  for currency, amount in pairs(cost) do
    log_debug("Cost for currency: ", currency, " amount: ", amount)
    costString = costString ..
        localization.get("ui.cost_tooltip_postfix",
          { cost = amount, currencyName = globals.currencies[currency].human_readable_name }) .. " "
  end
  return costString
end

function getUnlockStrinForBuildingOrConverter(buildingOrConverterDef)

end

-- pass in the converter definition used to output the material
function getCostStringForMaterial(converterDef)
  local costString = "\nCost:\n"
  local cost = converterDef.required_currencies
  log_debug("debug printing cost string for material: ", converterDef.id)
  print_table(cost)
  for currency, amount in pairs(cost) do
    costString = costString ..
        localization.get("ui.material_requirement_tooltip_postfix",
          { cost = amount, currencyName = globals.currencies[currency].human_readable_name }) .. " "
  end
  return costString
end

function togglePausedState(forcePause)
  if (globals.gameOver) then
    log_debug("Game is over, cannot toggle paused state")
    return
  end
  
  -- decide whether we should be paused
  -- if forcePause is nil → flip the current state
  -- if forcePause is boolean → use that
  local willPause
  if forcePause == nil then
    willPause = not globals.gamePaused
  else
    willPause = forcePause
  end

  if willPause then
    -- → go into paused state
    globals.gamePaused = true
    log_debug("Pausing game")
    ai.pause_ai_system()
    timer.pause_group("colonist_movement_group")
    if globals.ui.pauseButtonAnimationEntity then
      animation_system.replaceAnimatedObjectOnEntity(
        globals.ui.pauseButtonAnimationEntity,
        "tile_0537.png",     -- play icon
        true
      )
      animation_system.resizeAnimationObjectsInEntityToFit(
        globals.ui.pauseButtonAnimationEntity, 40, 40
      )
    end
  else
    -- → come out of paused state
    globals.gamePaused = false
    log_debug("Unpausing game")
    ai.resume_ai_system()
    timer.resume_group("colonist_movement_group")
    if globals.ui.pauseButtonAnimationEntity then
      animation_system.replaceAnimatedObjectOnEntity(
        globals.ui.pauseButtonAnimationEntity,
        "tile_0538.png",     -- pause icon
        true
      )
      animation_system.resizeAnimationObjectsInEntityToFit(
        globals.ui.pauseButtonAnimationEntity, 40, 40
      )
    end
  end
end

-- starts walk animation for an entity
function startEntityWalkMotion(e)
  timer.every(0.5,
    function()
      if (not entity_cache.valid(e) or e == entt_null) then
        log_debug("Entity is not valid, stopping walk motion")
        
        -- use schduler to remove the timer
        local task1 = {
              update = function(self, dt)
                  task.wait(0.1) -- wait for 0.5 seconds
                  log_debug("Removing walk timer for entity: ", e)
                  timer.cancel(e .. "_walk_timer") -- cancel the timer
              end
          }
        scheduler:attach(task1) -- attach the task to the scheduler
        return
      end
      local t = component_cache.get(e, Transform)
      t.actualR = 10 * math.sin(GetTime() * 4)   -- Multiply GetTime() by a factor to increase oscillation speed
    end,
    0,
    true,
    function()
      if (not entity_cache.valid(e)) then
        log_debug("Entity is not valid, stopping walk motion")
        return -- stop the timer if the entity is not valid
      end
      local t = component_cache.get(e, Transform)
      t.actualR = 0
    end,
    e .. "_walk_timer" -- unique timer name for this entity
  )
end

-- stops walk animation for an entity (cancels the timer started by startEntityWalkMotion)
function stopEntityWalkMotion(e)
  timer.cancel(e .. "_walk_timer")
  if entity_cache.valid(e) then
    local t = component_cache.get(e, Transform)
    if t then
      t.actualR = 0
    end
  end
end

function spawnRainPlopAtRandomLocation()
    local randomX = random_utils.random_int(0, globals.screenWidth() - 1)
    local randomY = random_utils.random_int(0, globals.screenHeight() - 1)
    spawnCircularBurstParticles(
        randomX, -- X position
        randomY, -- Y position
        10, -- number of particles
        0.5, -- lasting how long
        util.getColor("drab_olive"), -- start color
        util.getColor("green_mos") -- end color
    )
end

function spawnSnowPlopAtRandomLocation()
  local randomX = random_utils.random_int(0, globals.screenWidth() - 1)
  local randomY = random_utils.random_int(0, globals.screenHeight() - 1)
  spawnCircularBurstParticles(
      randomX, -- X position
      randomY, -- Y position
      10, -- number of particles
      0.5, -- lasting how long
      util.getColor("pastel_pink"), -- start color
      util.getColor("blue_sky") -- end color
  )
end

function buyNewColonistHomeCallback() 
  local structureDef = findInTable(globals.structure_defs, "id", "colonist_home")
  
  -- check if the player has enough resources to buy the colonist home
  local cost = structureDef.cost
  if cost > globals.currency then
    log_debug("Not enough resources to buy colonist home")
    newTextPopup(
      localization.get("ui.not_enough_currency"),
      globals.screenWidth() / 2,
      globals.screenHeight() / 2 - 100,
      2
    )
    return  
  end
  
  -- deduct the cost from the player's resources
  globals.currency = globals.currency - cost
  log_debug("Deducted", cost, "from player's resources")
  
  -- create a new colonist home entity
  local colonistHomeEntity = create_transform_entity()
  animation_system.setupAnimatedObjectOnEntity(
    colonistHomeEntity,
    structureDef.spriteID, -- Default animation ID
    true,                  -- ? generate a new still animation from sprite
    nil,                   -- shader_prepass, -- Optional shader pass config
    true
  )
  
  animation_system.resizeAnimationObjectsInEntityToFit(
    colonistHomeEntity,
    globals.tileSize, -- width
    globals.tileSize  -- height
  )
  
  -- make the object draggable
  local gameObjectState = component_cache.get(colonistHomeEntity, GameObject).state
  gameObjectState.dragEnabled = true
  gameObjectState.clickEnabled = true
  gameObjectState.hoverEnabled = true
  gameObjectState.collisionEnabled = true 
  
  -- create a new text entity
  local infoText = ui.definitions.getNewDynamicTextEntry(
    function() return localization.get("ui.drag_me") end, -- initial text
    15.0,                                                 -- font size
    "bump"                                                -- animation spec  
  ).config.object
  
  -- make the text entity follow the colonist home entity
  transform.AssignRole(registry, infoText, InheritedPropertiesType.RoleInheritor, colonistHomeEntity,
    InheritedPropertiesSync.Strong,
    InheritedPropertiesSync.Strong,
    InheritedPropertiesSync.Strong,   
    InheritedPropertiesSync.Strong,
    Vec2(0, -20) -- offset the text above the colonist home
  );
  
  -- now locate the colonist home entity in the game world
  local transformComp = component_cache.get(colonistHomeEntity, Transform)
  transformComp.actualX = globals.screenWidth() / 2 - transformComp.actualW / 2 -- center it horizontally
  transformComp.actualY = globals.screenHeight() - 300  
  
  -- add onstopdrag method to the colonist home entity
  local gameObjectComp = component_cache.get(colonistHomeEntity, GameObject)
  gameObjectComp.methods.onStopDrag = function()
    log_debug("Colonist home entity stopped dragging!") 
    -- add to the table in the buildings table with the id of the building
    table.insert(globals.structures.colonist_homes, { entity = colonistHomeEntity })
    log_debug("Added colonist home entity to globals.structures: ", colonistHomeEntity, " for id: ", structureDef.id) 
    local gameObjectComp = component_cache.get(colonistHomeEntity, GameObject)
    local transformComp = component_cache.get(colonistHomeEntity, Transform)
    local gameObjectState = gameObjectComp.state
    -- get the grid that it's in, grid is 64 pixels wide
    local gridX = math.floor(transformComp.actualX / 64)
    local gridY = math.floor(transformComp.actualY / 64)
    log_debug("Colonist home entity is in grid: ", gridX, gridY)  
    -- snap the entity to the grid, but center it in the grid cell  
    local magic_padding = 2
    transformComp.actualX = gridX * 64 + 32 - transformComp.actualW / 2 + magic_padding -- center it in the grid cell
    transformComp.actualY = gridY * 64 + 32 - transformComp.actualH / 2 + magic_padding -- center it in the grid cell
    -- make the entity no longer draggable
    gameObjectState.dragEnabled = false
    gameObjectState.clickEnabled = false
    gameObjectState.hoverEnabled = true
    gameObjectState.collisionEnabled = true 
    -- remove the text entity
    registry:destroy(infoText)  
    -- spawn particles at the colonist home's position center
    spawnCircularBurstParticles(
      transformComp.actualX + transformComp.actualW / 2,
      transformComp.actualY + transformComp.actualH / 2,
      20, -- number of particles
      0.5 -- particle size
    ) 
    playSoundEffect("effects", "building-plop")
    transform.InjectDynamicMotion(colonistHomeEntity, 1.0, 1) 
    log_debug("add on hover/stop hover methods to the colonist home entity")
    -- add on hover/stop hover methods to the colonist home entity
    gameObjectComp.methods.onHover = function()
      if showSimpleTooltipAbove then
        showSimpleTooltipAbove(
          "colonist_home",
          localization.get(structureDef.ui_tooltip_title),
          localization.get(structureDef.ui_tooltip_body),
          colonistHomeEntity
        )
      end
    end
    gameObjectComp.methods.onStopHover = function()
      log_debug("Colonist home entity stopped hovering!")
      if hideSimpleTooltip then
        hideSimpleTooltip("colonist_home")
      end
    end
    
    -- spawn a new colonist at the colonist home
    spawnNewColonist()
    log_debug("Spawned new colonist at the colonist home")
  end
  
end

function buyNewDuplicatorCallback()
  local structureDef = findInTable(globals.structure_defs, "id", "duplicator")

  -- check if the player has enough resources to buy the duplicator
  local cost = structureDef.cost
  if cost > globals.currency then
    log_debug("Not enough resources to buy duplicator")
    newTextPopup(
      localization.get("ui.not_enough_currency"),
      globals.screenWidth() / 2,
      globals.screenHeight() / 2 - 100,
      2
    )
    return
  end

  -- deduct the cost from the player's resources
  globals.currency = globals.currency - cost
  log_debug("Deducted", cost, "from player's resources")

  --TODO: store duplicator in the globals table

  -- create a new duplicator entity
  local duplicatorEntity = create_transform_entity()


  animation_system.setupAnimatedObjectOnEntity(
    duplicatorEntity,
    structureDef.spriteID, -- Default animation ID
    true,                  -- ? generate a new still animation from sprite
    nil,                   -- shader_prepass, -- Optional shader pass config
    true
  )

  animation_system.resizeAnimationObjectsInEntityToFit(
    duplicatorEntity,
    globals.tileSize, -- width
    globals.tileSize  -- height
  )

  -- make the object draggable
  local gameObjectState = component_cache.get(duplicatorEntity, GameObject).state
  gameObjectState.dragEnabled = true
  gameObjectState.clickEnabled = true
  gameObjectState.hoverEnabled = true
  gameObjectState.collisionEnabled = true

  -- create a new text entity
  local infoText = ui.definitions.getNewDynamicTextEntry(
    function() return localization.get("ui.drag_me") end, -- initial text
    15.0,                                                 -- font size
    "bump"                                                -- animation spec
  ).config.object
  -- make the text entity follow the duplicator entity
  transform.AssignRole(registry, infoText, InheritedPropertiesType.RoleInheritor, duplicatorEntity,
    InheritedPropertiesSync.Strong,
    InheritedPropertiesSync.Strong,
    InheritedPropertiesSync.Strong,
    InheritedPropertiesSync.Strong,
    Vec2(0, -20) -- offset the text above the duplicator
  );

  -- now locate the duplicator entity in the game world
  local transformComp = component_cache.get(duplicatorEntity, Transform)
  transformComp.actualX = globals.screenWidth() / 2 - transformComp.actualW / 2 -- center it horizontally
  transformComp.actualY = globals.screenHeight() - 300

  -- add onstopdrag method to the duplicator entity
  local gameObjectComp = component_cache.get(duplicatorEntity, GameObject)
  gameObjectComp.methods.onStopDrag = function()
    log_debug("Duplicator entity stopped dragging!")


    -- add to the table in the buildings table with the id of the building
    table.insert(globals.structures.duplicators, { entity = duplicatorEntity })
    log_debug("Added duplicator entity to globals.structures: ", duplicatorEntity, " for id: ", structureDef.id)

    local gameObjectComp = component_cache.get(duplicatorEntity, GameObject)
    local transformComp = component_cache.get(duplicatorEntity, Transform)
    local gameObjectState = gameObjectComp.state
    -- get the grid that it's in, grid is 64 pixels wide
    local gridX = math.floor(transformComp.actualX / 64)
    local gridY = math.floor(transformComp.actualY / 64)
    log_debug("Duplicator entity is in grid: ", gridX, gridY)
    -- snap the entity to the grid, but center it in the grid cell
    local magic_padding = 2
    transformComp.actualX = gridX * 64 + 32 - transformComp.actualW / 2 + magic_padding -- center it in the grid cell
    transformComp.actualY = gridY * 64 + 32 - transformComp.actualH / 2 + magic_padding -- center it in the grid cell
    -- make the entity no longer draggable
    gameObjectState.dragEnabled = false
    gameObjectState.clickEnabled = false
    gameObjectState.hoverEnabled = true
    gameObjectState.collisionEnabled = true
    -- remove the text entity
    registry:destroy(infoText)

    -- spawn particles at the duplicator's position center
    spawnCircularBurstParticles(
      transformComp.actualX + transformComp.actualW / 2,
      transformComp.actualY + transformComp.actualH / 2,
      20, -- number of particles
      0.5 -- particle size
    )

    transform.InjectDynamicMotion(duplicatorEntity, 1.0, 1)

    log_debug("add on hover/stop hover methods to the duplicator entity")

    -- add on hover/stop hover methods to the duplicator entity
    gameObjectComp.methods.onHover = function()
      if showSimpleTooltipAbove then
        showSimpleTooltipAbove(
          "duplicator",
          localization.get(structureDef.ui_tooltip_title),
          localization.get(structureDef.ui_tooltip_body),
          duplicatorEntity
        )
      end
    end
    gameObjectComp.methods.onStopHover = function()
      log_debug("Duplicator entity stopped hovering!")
      if hideSimpleTooltip then
        hideSimpleTooltip("duplicator")
      end
    end
  end
end

function buyBuildingButtonCallback()
  -- id of currently selected converter
  local selectedBuilding = globals.building_upgrade_defs[globals.selectedBuildingIndex]

  local uiTransformComp = component_cache.get(globals.building_ui_animation_entity, Transform)

  if not selectedBuilding.unlocked then
    log_debug("Building is not unlocked yet!")
    newTextPopup(
      localization.get("ui.not_unlocked_msg"),
      uiTransformComp.actualX + uiTransformComp.actualW / 2,
      uiTransformComp.actualY - uiTransformComp.actualH * 2.5,
      2
    )
    playSoundEffect("effects", "cannot-buy")
    return
  end

  -- check if the player has enough resources to buy the building
  local cost = selectedBuilding.cost
  for currency, amount in pairs(cost) do
    if globals.currencies[currency].target < amount then
      log_debug("Not enough", currency, "to buy building", selectedBuilding.id)
      newTextPopup(
        localization.get("ui.not_enough_currency"),
        uiTransformComp.actualX + uiTransformComp.actualW / 2,
        uiTransformComp.actualY - uiTransformComp.actualH * 2.5,
        2
      )
      playSoundEffect("effects", "cannot-buy")
      return
    end
  end

  -- deduct the cost from the player's resources
  for currency, amount in pairs(cost) do
    globals.currencies[currency].target = globals.currencies[currency].target - amount
    log_debug("Deducted", amount, currency, "from player's resources")
  end


  -- create a new example converter entity
  local exampleBuilding = create_ai_entity("kobold")

  -- add to the table in the buildings table with the id of the building
  table.insert(globals.buildings[selectedBuilding.id], exampleBuilding)
  log_debug("Added building entity to globals.buildings: ", exampleBuilding, " for id: ", selectedBuilding.id)

  playSoundEffect("effects", "buy-building")


  animation_system.setupAnimatedObjectOnEntity(
    exampleBuilding,
    selectedBuilding.anim, -- Default animation ID
    false,                 -- ? generate a new still animation from sprite, don't set to true, causes bug
    nil,                   -- shader_prepass, -- Optional shader pass config function
    true                   -- Enable shadow
  )

  animation_system.resizeAnimationObjectsInEntityToFit(
    exampleBuilding,
    60, -- width
    60  -- height
  )

  -- make the object draggable
  local gameObjectState = component_cache.get(exampleBuilding, GameObject).state
  gameObjectState.dragEnabled = true
  gameObjectState.clickEnabled = true
  gameObjectState.hoverEnabled = true
  gameObjectState.collisionEnabled = true

  -- create a new text entity
  local infoText = ui.definitions.getNewDynamicTextEntry(
    function() return localization.get("ui.drag_me") end, -- initial text
    15.0,                                                 -- font size
    "bump"                                                -- animation spec
  ).config.object

  -- make the text entity follow the converter entity
  transform.AssignRole(registry, infoText, InheritedPropertiesType.RoleInheritor, exampleBuilding,
    InheritedPropertiesSync.Strong,
    InheritedPropertiesSync.Strong,
    InheritedPropertiesSync.Strong,
    InheritedPropertiesSync.Strong,
    Vec2(0, -20) -- offset the text above the converter
  );

  -- local textRole = component_cache.get(infoText, InheritedProperties)
  -- textRole.flags = AlignmentFlag.HORIZONTAL_CENTER | AlignmentFlag.VERTICAL_TOP


  -- now locate the converter entity in the game world

  local transformComp = component_cache.get(exampleBuilding, Transform)
  transformComp.actualX = globals.screenWidth() / 2 - transformComp.actualW / 2 -- center it horizontally
  transformComp.actualY = globals.screenHeight() - 300


  -- add onstopdrag method to the converter entity
  local gameObjectComp = component_cache.get(exampleBuilding, GameObject)
  gameObjectComp.methods.onHover = function()
    log_debug("Converter entity hovered! WHy not drag?")
  end
  gameObjectComp.methods.onStopDrag = function()
    log_debug("Converter entity stopped dragging!")
    local gameObjectComp = component_cache.get(exampleBuilding, GameObject)
    local transformComp = component_cache.get(exampleBuilding, Transform)
    local gameObjectState = gameObjectComp.state
    -- get the grid that it's in, grid is 64 pixels wide
    local gridX = math.floor(transformComp.actualX / 64)
    local gridY = math.floor(transformComp.actualY / 64)
    log_debug("Converter entity is in grid: ", gridX, gridY)
    -- snap the entity to the grid, but center it in the grid cell
    local magic_padding = 2
    transformComp.actualX = gridX * 64 + 32 - transformComp.actualW / 2 + magic_padding -- center it in the grid cell
    transformComp.actualY = gridY * 64 + 32 - transformComp.actualH / 2 + magic_padding -- center it in the grid cell
    -- make the entity no longer draggable
    gameObjectState.dragEnabled = false
    gameObjectState.clickEnabled = false
    gameObjectState.hoverEnabled = true
    gameObjectState.collisionEnabled = true
    -- remove the text entity
    registry:destroy(infoText)
    -- spawn particles at the converter's position center
    spawnCircularBurstParticles(
      transformComp.actualX + transformComp.actualW / 2,
      transformComp.actualY + transformComp.actualH / 2,
      20, -- number of particles
      0.5 -- particle size
    )
    transform.InjectDynamicMotion(exampleBuilding, 1.0, 1)

    playSoundEffect("effects", "place-building")

    log_debug("add on hover/stop hover methods to the building entity")
    -- add on hover/stop hover methods to the building entity

    -- localization.get("ui.currency_text", {currency = math.floor(globals.currencies.whale_dust.amount)})

    gameObjectComp.methods.onHover = function()
      log_debug("Building entity hovered!")
      if showSimpleTooltipAbove then
        showSimpleTooltipAbove(
          "building_" .. selectedBuilding.id,
          localization.get(selectedBuilding.ui_text_title),
          localization.get(selectedBuilding.ui_text_body),
          buildingEntity
        )
      end
    end
    gameObjectComp.methods.onStopHover = function()
      log_debug("Building entity stopped hovering!")
      if hideSimpleTooltip then
        hideSimpleTooltip("building_" .. selectedBuilding.id)
      end
    end


    -- is the building a krill home or krill farm?
    if selectedBuilding.id == "krill_home" then
      -- spawn a krill entity at the building's position
      timer.after(
        0.4, -- delay in seconds
        function()
          spawnNewKrillAtLocation(
            transformComp.actualX + transformComp.actualW / 2,
            transformComp.actualY + transformComp.actualH / 2
          )

          -- spawn particles at the building's position center
          spawnCircularBurstParticles(
            transformComp.actualX + transformComp.actualW / 2,
            transformComp.actualY + transformComp.actualH / 2,
            50, -- number of particles
            0.5 -- seconds
          )

          log_debug("Spawned a krill entity at the building's position")
        end
      )
    elseif selectedBuilding.id == "krill_farm" then
      -- spawn 3
      for j = 1, 3 do
        timer.after(
          j * 0.2, -- delay in seconds
          function()
            spawnNewKrillAtLocation(
              transformComp.actualX + transformComp.actualW / 2,
              transformComp.actualY + transformComp.actualH / 2
            )
            -- spawn particles at the building's position center
            spawnCircularBurstParticles(


              transformComp.actualX + transformComp.actualW / 2,
              transformComp.actualY + transformComp.actualH / 2,
              50, -- number of particles
              0.5 -- seconds
            )
            log_debug("Spawned a krill entity at the building's position")
          end
        )
      end
    end
  end
end

--- Find a table entry by a given field name/value.
-- @param list  An array-like table of records.
-- @param field The field name to test (string).
-- @param value The value to match against.
-- @return      The first entry whose entry[field] == value, or nil if none.
function findInTable(list, field, value)
  for _, entry in ipairs(list) do
    if entry[field] == value then
      return entry
    end
  end
  return nil
end

function updateBuildings()
  for buildingID, buildingTable in pairs(globals.buildings) do
    -- loop through each building type
    for i = 1, #buildingTable do
      local buildingEntity = buildingTable[i]

      -- ensure building has been placed
      local gameObject = component_cache.get(buildingEntity, GameObject)
      if gameObject.state.dragEnabled then
        log_debug("Building", buildingID, "is not placed yet, skipping")
        goto continue
      end

      local buildingTransform = component_cache.get(buildingEntity, Transform)
      local buildingDefTable = findInTable(globals.building_upgrade_defs, "id", buildingID)


      -- check the resource collection rate
      local resourceCollectionRate = buildingDefTable.resource_collection_rate
      if not resourceCollectionRate then
        log_debug("Building", buildingID, "has no resource collection rate defined, skipping")
        goto continue
      end
      for resource, amount in pairs(resourceCollectionRate) do
        -- find the entry in the currencies_not_picked_up table
        local currencyEntitiesNotPickedUp = globals.currencies_not_picked_up[resource]
        if currencyEntitiesNotPickedUp then
          -- get as many as the amount specified
          for j = 1, amount do
            if #currencyEntitiesNotPickedUp > 0 then
              local currencyEntity = table.remove(currencyEntitiesNotPickedUp, 1)

              log_debug("Building", buildingID, "gathered", resource, "from entity", currencyEntity)

              --TODO: move the currency entity to the building's position
              local currencyTransform = component_cache.get(currencyEntity, Transform)
              currencyTransform.actualX = buildingTransform.actualX + buildingTransform.actualW / 2
              currencyTransform.actualY = buildingTransform.actualY + buildingTransform.actualH / 2

              log_debug("playing sound effect with ID", buildingID)
              playSoundEffect("effects", buildingID)

              timer.after(
                0.8, -- delay in seconds
                function()
                  -- increment the global currency count
                  globals.currencies[resource].target = globals.currencies[resource].target + 1
                  -- spawn particles at the building's position center
                  spawnCircularBurstParticles(
                    buildingTransform.actualX + buildingTransform.actualW / 2,
                    buildingTransform.actualY + buildingTransform.actualH / 2,
                    10, -- number of particles
                    0.5 -- seconds
                  )
                  -- remove the currency entity from the registry
                  if (entity_cache.valid(currencyEntity) == true) then
                    registry:destroy(currencyEntity)
                  end
                end
              )
            else
              log_debug("No more", resource, "entities to gather from")
              break
            end
          end
        end
      end

      ::continue::
    end
  end
end

function updateConverters()
  for converterID, converterTable in pairs(globals.converters) do
    -- loop through each converter type
    for i = 1, #converterTable do
      local converterEntity = converterTable[i]

      -- ensure converter has been placed
      local gameObject = component_cache.get(converterEntity, GameObject)
      if gameObject.state.dragEnabled then
        log_debug("Converter", converterID, "is not placed yet, skipping")
        goto continue
      end

      local converterTransform = component_cache.get(converterEntity, Transform)
      local converterDefTable = findInTable(globals.converter_defs, "id", converterID)


      -- check the global currencies table for the converter's required currency
      local requirement_met = true -- assume requirement is met
      for currency, amount in pairs(converterDefTable.required_currencies) do
        if globals.currencies[currency].target < amount then
          log_debug("Converter", converterID, "requires", amount, currency, "but only has",
            globals.currencies[currency].target)
          requirement_met = false -- requirement not met
          break
        end
      end
      if requirement_met then
        -- detract from target currency
        for currency, amount in pairs(converterDefTable.required_currencies) do
          globals.currencies[currency].target = globals.currencies[currency].target - amount
          log_debug("Converter", converterID, "detracted", amount, currency, "from target")
        end
        -- spawn the new currency at the converter's position, in converter table's output field
        for currency, amount in pairs(converterDefTable.output) do
          log_debug("Converter", converterID, "added", amount, currency, "to target")

          playSoundEffect("effects", converterID)

          for j = 1, amount do
            timer.after(
              0.1, -- delay in seconds
              function()
                spawnCurrencyAutoCollect(
                  converterTransform.actualX,
                  converterTransform.actualY,
                  currency
                )
              end
            )
          end
        end
      end
      ::continue::
    end
  end
end

function removeValueFromTable(t, value)
  for i, v in ipairs(t) do
    if v == value then
      table.remove(t, i)
      return true
    end
  end
  return false
end

function util.deep_copy(orig, copies)
    copies = copies or {}
    if type(orig) ~= "table" then
        return orig
    end

    -- If this table was already copied, return the same copy (prevents cycles)
    if copies[orig] then
        return copies[orig]
    end

    local copy = {}
    copies[orig] = copy

    for k, v in pairs(orig) do
        copy[ deep_copy(k, copies) ] = deep_copy(v, copies)
    end

    -- Copy metatable (optional)
    local mt = getmetatable(orig)
    if mt then
        setmetatable(copy, deep_copy(mt, copies))
    end

    return copy
end

--------------------------------------------------------
-- GLOBAL EXPORTS
--------------------------------------------------------
-- These helpers are used frequently enough to warrant global access.
-- See CLAUDE.md for documentation on each function.

_G.ensure_entity = ensure_entity
_G.ensure_scripted_entity = ensure_scripted_entity
_G.safe_script_get = safe_script_get
_G.script_field = script_field
_G.has_script = has_script

-- Re-export getScriptTableFromEntityID (already global, but ensure it)
if not _G.getScriptTableFromEntityID then
    _G.getScriptTableFromEntityID = getScriptTableFromEntityID
end
