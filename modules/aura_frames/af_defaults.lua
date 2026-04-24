local addon_name, addon = ...

-- The Foundation: This shell allows other files to store their 
-- frames and controls without hitting a 'nil value' error.

-- Ensure we don't wipe out the table if it was already created elsewhere
addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

-- Ensure sub-tables exist without overwriting them
M.frames = M.frames or {}
M.controls = M.controls or {}
M.db = M.db or {}

-- Single source of truth for category iteration.
-- Static has no timer controls, so it is excluded from TIMER_CATEGORIES.
M.CATEGORIES       = { "static", "short", "long", "debuff" }
M.TIMER_CATEGORIES = { "short", "long", "debuff" }

-- Single source of truth for default background color and opacity.
M.BAR_BG_ALPHA_DEFAULT = 0.50
M.BAR_BG_GRAY_DEFAULT = 0.50

local function default_bg_color()
    return {
        r = M.BAR_BG_GRAY_DEFAULT,
        g = M.BAR_BG_GRAY_DEFAULT,
        b = M.BAR_BG_GRAY_DEFAULT,
        a = M.BAR_BG_ALPHA_DEFAULT,
    }
end

-- The Data: strictly default values
M.defaults = {
    last_frames_node = "static",

    -- Global Toggles
    enable_blizz_buffs = true,
    enable_blizz_debuffs = true,
    short_threshold = 60,
    timer_number_font = "source_code_pro",
    timer_number_font_size = 10,
    timer_number_font_bold = false,

    -- STATIC
    show_static     = true,
    move_static     = true,
    timer_static    = false,
    bg_static       = false,
    scale_static    = 1.0,
    spacing_static  = 2.0,
    width_static    = 200,
    bar_mode_static = false,
    color_static    = { r = 0, g = 0.5, b = 1 },
    bar_bg_color_static = default_bg_color(),
    max_icons_static = 20,
    growth_static = "RIGHT",
    bg_color_static = default_bg_color(),
    sort_static  = "name",
    test_aura_static = true,

    -- SHORT
    show_short      = true,
    move_short      = true,
    timer_short     = true,
    bg_short        = false,
    scale_short     = 1.0,
    spacing_short   = 1.5,
    width_short     = 200,
    bar_mode_short  = true,
    color_short     = { r = 0, g = 0.5, b = 1 },
    bar_bg_color_short = default_bg_color(),
    max_icons_short = 20,
    growth_short = "DOWN",
    bg_color_short = default_bg_color(),
    sort_short   = "timeleft",
    test_aura_short = true,
    timer_number_font_short = "source_code_pro",
    timer_number_font_size_short = 10,
    timer_number_font_bold_short = false,

    -- LONG
    show_long       = true,
    move_long       = true,
    timer_long      = true,
    bg_long         = false,
    scale_long      = 1.0,
    spacing_long    = 2.0,
    width_long      = 200,
    bar_mode_long   = false,
    color_long      = { r = 0, g = 0.5, b = 1 },
    bar_bg_color_long = default_bg_color(),
    max_icons_long  = 20,
    growth_long = "RIGHT",
    bg_color_long = default_bg_color(),
    sort_long    = "timeleft",
    test_aura_long = true,
    timer_number_font_long = "source_code_pro",
    timer_number_font_size_long = 10,
    timer_number_font_bold_long = false,

    -- DEBUFFS
    show_debuff     = true,
    move_debuff     = true,
    timer_debuff    = true,
    bg_debuff       = false,
    scale_debuff    = 1.0,
    spacing_debuff  = 1.0,
    width_debuff    = 200,
    bar_mode_debuff = true,
    color_debuff    = { r = 1, g = 0.2, b = 0.2 },
    bar_bg_color_debuff = default_bg_color(),
    max_icons_debuff = 20,
    growth_debuff = "UP",
    bg_color_debuff = default_bg_color(),
    sort_debuff  = "timeleft",
    test_aura_debuff = true,
    timer_number_font_debuff = "source_code_pro",
    timer_number_font_size_debuff = 10,
    timer_number_font_bold_debuff = false,
    
    -- Runtime-learned spell classification tables (reset clears the learned set)
    known_static_spell_ids = {},
    known_long_spell_ids   = {},

    -- POSITIONS
    -- pos.x = left edge offset from screen center; pos.y = top edge offset from screen center
    positions = {
        static = { point = "TOPLEFT", x = -100, y = 175 },
        short  = { point = "TOPLEFT", x = -100, y = 125 },
        long   = { point = "TOPLEFT", x = -100, y =  75 },
        debuff = { point = "TOPLEFT", x = -100, y = -25 },
    }
}

-- Single source of truth for timer font-size lookup.
-- Category-specific value -> global value -> default global value.
function M.get_timer_number_font_size(category)
    local db = M.db or {}
    local defaults = M.defaults or {}

    if category then
        local category_size = tonumber(db["timer_number_font_size_"..category])
        if category_size then return category_size end
    end

    local global_size = tonumber(db.timer_number_font_size)
    if global_size then return global_size end

    return tonumber(defaults.timer_number_font_size) or 10
end