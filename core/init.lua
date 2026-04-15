local addon_name, addon = ...
addon.name = addon_name

-- GLOBAL UI THEME FOR RIVET PANELS (shared across all modules)
-- Centralized configuration for consistent styling of CreateRivetedPanel instances
addon.UI_THEME = {
    -- Rivet Panel Content Spacing
    padding = 33,              -- padding inside rivet panels
    panel_margin = 60,         -- margin around panels from parent edges
    
    -- Rivet Panel Sizing
    panel_min_height = 60,     -- minimum height for rivet panels
    panel_max_width = 420,     -- maximum width for rivet panels
    
    -- Rivet Panel Positioning
    offset_x = 0,              -- default horizontal offset for panel positioning
    offset_y = -50,            -- default vertical offset for panel positioning
    
    -- Typography (Rivet Panel Text)
    font_panel = "GameFontHighlightSmall",  -- font for text inside rivet panels
    
    -- General UI Fonts (used by modules)
    font_title = "GameFontHighlight",
    font_subtitle = "GameFontHighlightSmall",
    font_body = "GameFontNormal",
}

-- DATABASE INITIALIZATION
local function init_db()
    -- Ensure the global DB exists with the Tweeks spelling
    _G.Ls_Tweeks_DB = _G.Ls_Tweeks_DB or {}
    
    -- Core Minimap defaults
    if not Ls_Tweeks_DB.minimap then
        Ls_Tweeks_DB.minimap = { hide = false }
    end

    -- Ensure the aura_frames sub-table exists for the module to use
    if not Ls_Tweeks_DB.aura_frames then
        Ls_Tweeks_DB.aura_frames = {}
    end
end

-- MAIN INITIALIZATION SEQUENCE
local function on_event(self, event, name)
    if name ~= addon_name then return end

    -- Store version from TOC
    addon.version = C_AddOns.GetAddOnMetadata(addon_name, "Version")

    -- Setup Global DB
    init_db()

    -- Initialize the core UI frame
    if addon.init_main_frame then
        addon.init_main_frame()
    end

    -- Initialize the LDB/Minimap button
    if addon.init_minimap_button then
        addon.init_minimap_button()
    end
    
    -- Note: Aura Frames will initialize themselves in af_main.lua
    -- using the Ls_Tweeks_DB.aura_frames table we ensured exists above.
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", on_event)

-- SLASH COMMANDS
-- Primary command: /lt (short for L's Tweeks)
SLASH_LSTWEEKS1 = "/lt"
SlashCmdList["LSTWEEKS"] = function(msg)
    if addon.main_frame then
        if addon.main_frame:IsShown() then
            addon.main_frame:Hide()
        else
            addon.main_frame:Show()
        end
    end
end