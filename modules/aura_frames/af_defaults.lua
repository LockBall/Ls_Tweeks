local addon_name, addon = ...

-- The Foundation: This shell allows other files to store their 
-- frames and controls without hitting a 'nil value' error.
addon.aura_frames = {
    frames = {},
    controls = {},
    db = {}
}

local M = addon.aura_frames

-- The Data: strictly default values
M.defaults = {
    -- Global Toggles
    disable_blizz_buffs = false,
    disable_blizz_debuffs = false,
    short_threshold = 60,
    
    -- STATIC
    show_static     = false,
    move_static     = true,
    timer_static    = false,
    bg_static       = false,
    scale_static    = 1.0,
    spacing_static  = 2.0,
    width_static    = 200,
    use_bars_static = false,
    color_static    = { r = 0, g = 0.5, b = 1 },
    max_icons_static = 40,

    -- SHORT
    show_short      = false,
    move_short      = true,
    timer_short     = true,
    bg_short        = false,
    scale_short     = 1.0,
    spacing_short   = 2.0,
    width_short     = 200,
    use_bars_short  = true,
    color_short     = { r = 0, g = 0.5, b = 1 },
    max_icons_short = 40,

    -- LONG
    show_long       = false,
    move_long       = true,
    timer_long      = true,
    bg_long         = false,
    scale_long      = 1.0,
    spacing_long    = 2.0,
    width_long      = 200,
    use_bars_long   = false,
    color_long      = { r = 0, g = 0.5, b = 1 },
    max_icons_long  = 40,

    -- DEBUFFS
    show_debuff     = false,
    move_debuff     = true,
    timer_debuff    = true,
    bg_debuff       = false,
    scale_debuff    = 1.0,
    spacing_debuff  = 2.0,
    width_debuff    = 200,
    use_bars_debuff = true,
    color_debuff    = { r = 1, g = 0.2, b = 0.2 },
    max_icons_debuff = 40,
    
    -- POSITIONS
    positions = {
        static = { point = "CENTER", x = 0, y = 150 },
        short  = { point = "CENTER", x = 0, y = 100 },
        long   = { point = "CENTER", x = 0, y = 50 },
        debuff = { point = "CENTER", x = 0, y = -50 },
    }
}