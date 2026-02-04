--[[
ASCII Sprites Module

Provides character definitions for ASCII-based UI elements, icons, borders, and structures.
Used by ASCII UI panels and text-based rendering systems.
]]

local ascii_sprites = {}

-- Border character sets for different styles
ascii_sprites.BORDER = {
    simple = {
        top_left = "+", top = "-", top_right = "+",
        left = "|", right = "|",
        bottom_left = "+", bottom = "-", bottom_right = "+"
    },
    double = {
        top_left = "╔", top = "═", top_right = "╗",
        left = "║", right = "║",
        bottom_left = "╚", bottom = "═", bottom_right = "╝"
    },
    rounded = {
        top_left = "╭", top = "─", top_right = "╮",
        left = "│", right = "│",
        bottom_left = "╰", bottom = "─", bottom_right = "╯"
    },
    thick = {
        top_left = "┏", top = "━", top_right = "┓",
        left = "┃", right = "┃",
        bottom_left = "┗", bottom = "━", bottom_right = "┛"
    }
}

-- Icon characters for UI elements
ascii_sprites.ICONS = {
    -- Resource icons
    wood = "♠",       -- Tree/wood symbol
    stone = "◊",      -- Diamond/stone symbol
    food = "♦",       -- Food/berry symbol
    gold = "$",       -- Gold/coin symbol

    -- UI interaction icons
    button_buy = "[BUY]",
    button_max = "[MAX]",
    button_disabled = "[—]",
    button_upgrade = "[↑]",

    -- Status icons
    check = "✓",
    cross = "✗",
    warning = "!",
    info = "i",

    -- Achievement icons
    trophy = "🏆",
    star = "★",
    medal = "●",

    -- Arrow and navigation icons
    arrow_up = "↑",
    arrow_down = "↓",
    arrow_left = "←",
    arrow_right = "→",

    -- Progress indicators
    full_block = "█",
    half_block = "▌",
    empty_block = "░",
    progress_fill = "■",
    progress_empty = "□",

    -- Creature/entity icons
    forager = "@",
    lumberjack = "A",
    miner = "M",
    collector = "C",
    builder = "B"
}

-- Structure characters for game world ASCII representation
ascii_sprites.STRUCTURES = {
    -- Terrain elements
    grass = ".",
    tree = "♠",
    rock = "◊",
    water = "~",

    -- Buildings/constructions
    house = "⌂",
    workshop = "⚒",
    storage = "□",
    farm = "≡",
    mine = "▲",

    -- Special structures
    portal = "◯",
    shrine = "†",
    tower = "♦",
    bridge = "=",

    -- Paths and roads
    path_horizontal = "─",
    path_vertical = "│",
    path_cross = "┼",
    path_corner_tl = "┌",
    path_corner_tr = "┐",
    path_corner_bl = "└",
    path_corner_br = "┘",

    -- Walls and barriers
    wall_horizontal = "═",
    wall_vertical = "║",
    wall_corner = "╬",

    -- Special terrain
    mountain = "▲",
    hill = "△",
    crater = "○",
    swamp = "≋"
}

-- Animation cycles for structures (cycling through different characters)
ascii_sprites.STRUCTURE_CYCLE = {
    -- Fire/heat animation
    fire = { "▲", "△", "▲", "△" },

    -- Water animation
    water = { "~", "≈", "~", "≈" },

    -- Working/active building animation
    workshop_active = { "⚒", "⚒", "⚒", "⚓" },

    -- Portal/magic animation
    portal_active = { "◯", "○", "◯", "○" },

    -- Resource node depletion
    tree_harvesting = { "♠", "♣", "♠", "♣" },
    rock_mining = { "◊", "◦", "◊", "◦" },

    -- Progress indicators
    loading = { "|", "/", "-", "\\" },

    -- Pulsing indicators
    active_pulse = { "●", "○", "●", "○" },
    warning_pulse = { "!", "·", "!", "·" },

    -- Directional flow (for conveyor belts, rivers, etc)
    flow_horizontal = { "←", "→", "←", "→" },
    flow_vertical = { "↑", "↓", "↑", "↓" },

    -- Building construction
    construction = { "◦", "◌", "○", "●" },

    -- Magic/energy effects
    energy = { "◊", "◇", "◊", "◇" },
    sparkle = { "✦", "✧", "✦", "✧" }
}

-- Helper function to get border style
function ascii_sprites.get_border_style(style_name)
    return ascii_sprites.BORDER[style_name or "simple"]
end

-- Helper function to get next frame in animation cycle
function ascii_sprites.get_cycle_frame(cycle_name, frame_index)
    local cycle = ascii_sprites.STRUCTURE_CYCLE[cycle_name]
    if not cycle then return nil end

    local index = ((frame_index - 1) % #cycle) + 1
    return cycle[index]
end

-- Helper function to get all available border styles
function ascii_sprites.get_border_styles()
    local styles = {}
    for style_name, _ in pairs(ascii_sprites.BORDER) do
        table.insert(styles, style_name)
    end
    return styles
end

-- Helper function to get all available cycles
function ascii_sprites.get_cycle_names()
    local cycles = {}
    for cycle_name, _ in pairs(ascii_sprites.STRUCTURE_CYCLE) do
        table.insert(cycles, cycle_name)
    end
    return cycles
end

-- Utility function to create a progress bar using ASCII characters
function ascii_sprites.create_progress_bar(current, maximum, width)
    if width <= 0 or maximum <= 0 then
        return ""
    end

    local ratio = math.min(current / maximum, 1.0)
    local filled_chars = math.floor(ratio * width)
    local empty_chars = width - filled_chars

    local bar = ""
    for i = 1, filled_chars do
        bar = bar .. ascii_sprites.ICONS.progress_fill
    end
    for i = 1, empty_chars do
        bar = bar .. ascii_sprites.ICONS.progress_empty
    end

    return bar
end

return ascii_sprites