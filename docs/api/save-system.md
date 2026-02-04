# Save System API

Cross-platform persistence system supporting both Desktop (local filesystem) and Web (IndexedDB via IDBFS).

## Quick Start

```lua
-- SaveManager is initialized automatically in main.lua
-- Just register your collectors

SaveManager.register("my_module", {
    collect = function()
        return { score = currentScore, level = currentLevel }
    end,
    distribute = function(data)
        currentScore = data.score or 0
        currentLevel = data.level or 1
    end
})

-- Save triggers automatically or manually:
SaveManager.save()
```

## SaveManager API

### Registration

```lua
SaveManager.register(key, collector)
```

Register a data collector for a section of the save file.

| Parameter | Type | Description |
|-----------|------|-------------|
| key | string | Unique key in save file (e.g., "statistics", "inventory") |
| collector | table | Object with `collect()` and `distribute()` functions |

**Collector interface:**
```lua
{
    collect = function() -> table,      -- Return data to save
    distribute = function(data) -> nil  -- Restore data on load
}
```

**Example:**
```lua
SaveManager.register("player_stats", {
    collect = function()
        return {
            health = player.health,
            mana = player.mana,
            position = { x = player.x, y = player.y }
        }
    end,
    distribute = function(data)
        player.health = data.health or 100
        player.mana = data.mana or 50
        player.x = data.position and data.position.x or 0
        player.y = data.position and data.position.y or 0
    end
})
```

**Registration flow (current):**
- Validates the collector has `collect` and `distribute`, then stores it in `SaveManager.collectors`.
- If `SaveManager.cache` already has data for the key (a save was loaded), it immediately calls `collector.distribute(data)` inside `pcall` and logs a warning on failure.

This supports late registration, but registering before `SaveManager.init()` is still recommended.

### Save/Load Operations

```lua
SaveManager.save(callback)
```
Asynchronously save all collected data. Atomic write with backup.

| Parameter | Type | Description |
|-----------|------|-------------|
| callback | function (optional) | Called with `success` boolean |

```lua
SaveManager.load()
```
Synchronously load and distribute saved data. Auto-migrates old versions.

```lua
SaveManager.has_save() -> boolean
```
Check if a save file exists.

```lua
SaveManager.delete_save()
```
Delete all save data (main file and backup).

```lua
SaveManager.peek(key) -> table|nil
```
Get cached data for a key without triggering a load.

### Initialization

```lua
SaveManager.init()
```
Initialize the save system. Called automatically in `main.lua`.
- Desktop: Creates `saves/` directory
- Web: Mounts IDBFS and syncs from IndexedDB

## Save File Structure

```json
{
    "version": 1,
    "saved_at": "2025-12-25T10:30:00Z",
    "statistics": {
        "runs_completed": 5,
        "highest_wave": 12
    },
    "inventory": {
        "gold": 1500,
        "items": ["sword", "shield"]
    }
}
```

## Migrations

Handle save file version upgrades in `assets/scripts/core/save_migrations.lua`:

```lua
local migrations = {}

-- Migration from v1 to v2
migrations[2] = function(data)
    -- Rename old field
    if data.old_stats then
        data.statistics = data.old_stats
        data.old_stats = nil
    end
    return data
end

-- Migration from v2 to v3
migrations[3] = function(data)
    -- Add new required field
    data.settings = data.settings or { volume = 1.0 }
    return data
end

return migrations
```

Increment `SaveManager.SAVE_VERSION` when adding migrations:
```lua
SaveManager.SAVE_VERSION = 3
```

## Platform Behavior

| Platform | Storage | Async | Atomic |
|----------|---------|-------|--------|
| Desktop | `saves/profile.json` | Yes (thread) | Yes |
| Web | IndexedDB via IDBFS | Yes (callback) | No |

### Desktop
- Saves to `saves/profile.json`
- Atomic write pattern: write to `.tmp`, rename to target
- Background thread for async saves
- Backup at `saves/profile.json.bak`

### Web (Emscripten)
- Uses IDBFS mounted at `/saves`
- Async sync to IndexedDB after writes
- Persistent across browser sessions
- Auto-loads from IndexedDB on init

## Low-Level C++ API (save_io)

For direct file operations (rarely needed):

```lua
-- Synchronous load
local content = save_io.load_file("saves/profile.json")

-- Check existence
local exists = save_io.file_exists("saves/profile.json")

-- Delete file
save_io.delete_file("saves/profile.json")

-- Async save with callback
save_io.save_file_async("saves/profile.json", json_string, function(success)
    print(success and "Saved!" or "Failed!")
end)

-- Initialize filesystem (called by SaveManager.init)
save_io.init_filesystem()
```

## Debug UI

The ImGui DebugWindow includes a "Save System" tab showing:
- Platform info (Desktop/Web)
- Save file status and preview
- Action buttons: Save Now, Reload, Delete
- Registered collectors list
- Live Statistics editor

## Best Practices

1. **Register early** - Call `register()` before `SaveManager.init()`
2. **Defensive distribute** - Always provide defaults: `data.field or defaultValue`
3. **Keep it simple** - Only save what's needed to restore state
4. **Avoid circular refs** - JSON can't serialize circular references
5. **Test both platforms** - Desktop and Web have different behaviors

## Example: Statistics Collector

```lua
-- assets/scripts/core/statistics.lua
local Statistics = {
    runs_completed = 0,
    highest_wave = 0,
    total_kills = 0,
    total_gold_earned = 0,
    playtime_seconds = 0,
}

SaveManager.register("statistics", {
    collect = function()
        return {
            runs_completed = Statistics.runs_completed,
            highest_wave = Statistics.highest_wave,
            total_kills = Statistics.total_kills,
            total_gold_earned = Statistics.total_gold_earned,
            playtime_seconds = Statistics.playtime_seconds,
        }
    end,
    distribute = function(data)
        Statistics.runs_completed = data.runs_completed or 0
        Statistics.highest_wave = data.highest_wave or 0
        Statistics.total_kills = data.total_kills or 0
        Statistics.total_gold_earned = data.total_gold_earned or 0
        Statistics.playtime_seconds = data.playtime_seconds or 0
    end
})

return Statistics
```

## Troubleshooting

### Web: Changes not persisting across refresh
- Ensure `save_io.init_filesystem()` is called before any loads
- Check browser dev tools for IndexedDB errors

### Desktop: Save file not created
- Check `saves/` directory exists (created by `init_filesystem()`)
- Check file permissions

### Data missing after load
- Verify collector is registered before `SaveManager.init()`
- Check `distribute()` handles missing fields with defaults
