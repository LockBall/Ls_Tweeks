-- Single source of truth for all aura frames constants and default DB values.
-- Defines M.CATEGORIES, M.TIMER_CATEGORIES, per-category defaults (show, color, scale, growth, bar mode, font, etc.), and M.get_timer_number_font_size(). Nothing else in the module should hardcode default values.
local addon_name, addon = ...

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
    last_tab_index = 1,

    -- Global Toggles
    enable_blizz_buffs = true,
    enable_blizz_debuffs = true,
    snap_to_grid   = false,
    show_grid      = false,
    show_bar_section_outlines = false,
    show_spell_id = false,
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
    
    -- Custom whitelist frames (array of entry tables, see M.CUSTOM_FRAME_TEMPLATE)
    custom_frames = {},

    -- POSITIONS
    -- pos.x = left edge offset from screen center; pos.y = top edge offset from screen center
    positions = {
        static = { point = "TOPLEFT", x = -100, y = 175 },
        short  = { point = "TOPLEFT", x = -100, y = 125 },
        long   = { point = "TOPLEFT", x = -100, y =  75 },
        debuff = { point = "TOPLEFT", x = -100, y = -25 },
    }
}

-- ============================================================================
-- CUSTOM FRAME TEMPLATE
-- Default values for a newly created custom whitelist frame.
-- Each entry in M.db.custom_frames is a copy of this template with a unique id/name.
M.CUSTOM_FRAME_TEMPLATE = {
    -- Identity (always overwritten on create, never defaulted)
    -- id   = "custom_N"   set by spawn logic
    -- name = "Custom N"   set by spawn logic

    filter   = "HELPFUL",  -- "HELPFUL" or "HARMFUL"; toggling wipes whitelist
    whitelist = {},         -- [spell_id (number)] = display_name (string)

    -- Display
    show     = true,
    move     = true,
    timer    = true,
    bg       = false,
    scale    = 1.0,
    spacing  = 1.5,
    width    = 200,
    bar_mode = true,
    color    = { r = 0.8, g = 0.6, b = 1.0 },
    bar_bg_color = { r = 0.5, g = 0.5, b = 0.5, a = 0.5 },
    bg_color     = { r = 0,   g = 0,   b = 0,   a = 0.5 },
    max_icons    = 20,
    growth       = "DOWN",
    sort         = "timeleft",
    test_aura    = false,

    -- Timer font (matches TIMER_CATEGORIES convention)
    timer_number_font      = "source_code_pro",
    timer_number_font_size = 10,
    timer_number_font_bold = false,

    -- Position
    position = { point = "TOPLEFT", x = 0, y = 50 },
}

-- Max number of custom frames the user can create.
M.MAX_CUSTOM_FRAMES = 4

-- ============================================================================
-- CUSTOM FRAME HELPERS

-- Returns the next available auto-name ("Custom 1" .. "Custom N").
function M.next_custom_name()
    local used = {}
    if M.db and M.db.custom_frames then
        for _, entry in ipairs(M.db.custom_frames) do
            used[entry.name] = true
        end
    end
    for n = 1, M.MAX_CUSTOM_FRAMES do
        local candidate = "Custom " .. n
        if not used[candidate] then return candidate end
    end
    return "Custom"
end

-- Returns the next available stable id ("custom_1" .. "custom_N").
function M.next_custom_id()
    local used = {}
    if M.db and M.db.custom_frames then
        for _, entry in ipairs(M.db.custom_frames) do
            used[entry.id] = true
        end
    end
    for n = 1, M.MAX_CUSTOM_FRAMES do
        local candidate = "custom_" .. n
        if not used[candidate] then return candidate end
    end
    return "custom_x"
end

-- Creates a new custom frame entry table from the template.
function M.new_custom_entry(id, name)
    local entry = {}
    for k, v in pairs(M.CUSTOM_FRAME_TEMPLATE) do
        if type(v) == "table" then
            local t = {}
            for k2, v2 in pairs(v) do t[k2] = v2 end
            entry[k] = t
        else
            entry[k] = v
        end
    end
    entry.id   = id   or M.next_custom_id()
    entry.name = name or M.next_custom_name()
    return entry
end

-- ============================================================================
-- SINGLE SOURCE OF TRUTH FOR TIMER FONT-SIZE LOOKUP
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