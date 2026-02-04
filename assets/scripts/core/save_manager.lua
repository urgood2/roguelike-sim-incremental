---@class SaveManager
---@field private collectors table<string, Collector>
---@field private cache table
---@field private save_in_progress boolean
---@field private pending_save table|nil

local json = require("external.json")
local migrations = require("core.save_migrations")

-- Safe logging: use print() which always works
local function log_debug(msg) print("[SaveManager] " .. msg) end
local function log_info(msg)  print("[SaveManager] " .. msg) end
local function log_warn(msg)  print("[SaveManager] WARN: " .. msg) end
local function log_error(msg) print("[SaveManager] ERROR: " .. msg) end

local SaveManager = {
    SAVE_VERSION = 2,  -- v2 adds grid_inventory support
    SAVE_PATH = "saves/profile.json",
    BACKUP_PATH = "saves/profile.json.bak",

    collectors = {},
    cache = {},
    save_in_progress = false,
    pending_save = nil,
}

---@class Collector
---@field collect fun(): table
---@field distribute fun(data: table): nil

--- Register a collector for a save data section
---@param key string The key in the save file
---@param collector Collector The collector with collect/distribute functions
function SaveManager.register(key, collector)
    if not collector.collect or not collector.distribute then
        error("SaveManager.register: collector must have 'collect' and 'distribute' functions")
    end
    SaveManager.collectors[key] = collector
    if SaveManager.cache and SaveManager.cache[key] ~= nil then
        local success, err = pcall(collector.distribute, SaveManager.cache[key])
        if not success then
            log_warn(string.format(" late distributor '%s' failed: %s", key, tostring(err)))
        end
    end
    log_debug(string.format("registered collector '%s'", key))
end

--- Collect all data from registered collectors
---@return table
function SaveManager.collect_all()
    local data = {
        version = SaveManager.SAVE_VERSION,
        saved_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }

    for key, collector in pairs(SaveManager.collectors) do
        local success, result = pcall(collector.collect)
        if success then
            data[key] = result
        else
            log_warn(string.format("collector '%s' failed: %s", key, tostring(result)))
        end
    end

    return data
end

--- Distribute loaded data to all registered collectors
---@param data table
function SaveManager.distribute_all(data)
    for key, collector in pairs(SaveManager.collectors) do
        if data[key] then
            local success, err = pcall(collector.distribute, data[key])
            if not success then
                log_warn(string.format(" distributor '%s' failed: %s", key, tostring(err)))
            end
        end
    end
    SaveManager.cache = data
end

--- Run migrations on old save data
---@param data table
---@return table
local function migrate(data)
    local save_version = data.version or 1

    while save_version < SaveManager.SAVE_VERSION do
        local next_version = save_version + 1
        local migration = migrations[next_version]

        if migration then
            log_info(string.format(" migrating v%d → v%d", save_version, next_version))
            local success, result = pcall(migration, data)
            if success then
                data = result
                data.version = next_version
            else
                log_error(string.format(" migration to v%d failed: %s", next_version, tostring(result)))
                break
            end
        end

        save_version = next_version
    end

    return data
end

--- Trigger an async save
---@param callback? fun(success: boolean)
function SaveManager.save(callback)
    local data = SaveManager.collect_all()

    if SaveManager.save_in_progress then
        -- Queue this save for later
        SaveManager.pending_save = { data = data, callback = callback }
        log_debug(" save queued (another in progress)")
        return
    end

    SaveManager.save_in_progress = true
    local content = json.encode(data)

    save_io.save_file_async(SaveManager.SAVE_PATH, content, function(success)
        SaveManager.save_in_progress = false

        if callback then
            callback(success)
        end

        if success then
            SaveManager.cache = data
            log_debug(" save complete")
        else
            log_warn(" save failed")
        end

        -- Process queued save if any
        if SaveManager.pending_save then
            local queued = SaveManager.pending_save
            SaveManager.pending_save = nil

            -- Use the pre-collected data instead of re-collecting
            SaveManager.save_in_progress = true
            local content = json.encode(queued.data)

            save_io.save_file_async(SaveManager.SAVE_PATH, content, function(success)
                SaveManager.save_in_progress = false

                if queued.callback then
                    queued.callback(success)
                end

                if success then
                    SaveManager.cache = queued.data
                    log_debug(" queued save complete")
                else
                    log_warn(" queued save failed")
                end

                -- Process next queued save if any
                if SaveManager.pending_save then
                    local next_queued = SaveManager.pending_save
                    SaveManager.pending_save = nil
                    SaveManager.save_in_progress = false

                    -- Recursively process by calling save with the callback
                    -- but this will collect new data (intentional for next save)
                    SaveManager.save(next_queued.callback)
                end
            end)
        end
    end)
end

--- Load save data and distribute to collectors
function SaveManager.load()
    -- Try main save
    local content = save_io.load_file(SaveManager.SAVE_PATH)

    if content then
        local success, data = pcall(json.decode, content)
        if success and type(data) == "table" then
            local old_version = data.version or 1

            -- Migrate if needed
            if old_version < SaveManager.SAVE_VERSION then
                data = migrate(data)
                -- Save migrated data immediately
                SaveManager.save()
            end

            SaveManager.distribute_all(data)
            log_info(string.format(" loaded save (v%d)", data.version or 1))
            return
        end
        log_warn(" main save corrupted, trying backup")
    end

    -- Try backup
    local backup = save_io.load_file(SaveManager.BACKUP_PATH)
    if backup then
        local success, data = pcall(json.decode, backup)
        if success and type(data) == "table" then
            data = migrate(data)
            SaveManager.distribute_all(data)
            SaveManager.save() -- Repair main save
            log_info(" restored from backup")
            return
        end
        log_warn(" backup also corrupted")
    end

    -- Fresh start
    log_info(" no valid save found, starting fresh")
    SaveManager.create_new()
end

--- Create a fresh save with defaults
function SaveManager.create_new()
    SaveManager.cache = {
        version = SaveManager.SAVE_VERSION,
        saved_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    SaveManager.distribute_all(SaveManager.cache)
end

--- Check if a save file exists
---@return boolean
function SaveManager.has_save()
    return save_io.file_exists(SaveManager.SAVE_PATH)
end

--- Delete all save data
function SaveManager.delete_save()
    save_io.delete_file(SaveManager.SAVE_PATH)
    save_io.delete_file(SaveManager.BACKUP_PATH)
    SaveManager.cache = {}
    log_info(" save deleted")
end

--- Get cached data for a key without loading
---@param key string
---@return table|nil
function SaveManager.peek(key)
    return SaveManager.cache[key]
end

--- Initialize the save system (call early in startup)
function SaveManager.init()
    log_info("initializing")

    -- Initialize filesystem (creates saves/ dir on desktop, mounts IDBFS on web)
    save_io.init_filesystem()

    SaveManager.load()
end

return SaveManager
