-- Addon entry point: initializes the shared addon table, defines UI_THEME constants,
-- sets up SavedVariables (Ls_Tweeks_DB), and registers the /lst slash command.
-- Loads first; every other file reads addon.UI_THEME and writes into Ls_Tweeks_DB through the patterns established here.

local addon_name, addon = ...
addon.name = addon_name

-- Shared UI font tokens used across all modules.
-- Rivet panel layout constants (padding, sizing, positioning) live in addon.RIVETED_PANEL_STYLE in panel_riveted.lua.
addon.UI_THEME = {
    font_title    = "GameFontHighlight",
    font_subtitle = "GameFontHighlightSmall",
    font_body     = "GameFontNormal",
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

-- AUTO-OPEN on reload/login if the setting is enabled
local f2 = CreateFrame("Frame")
f2:RegisterEvent("PLAYER_ENTERING_WORLD")
f2:SetScript("OnEvent", function(self, event, isInitialLogin, isReloadingUi)
    if (isInitialLogin or isReloadingUi) and Ls_Tweeks_DB and Ls_Tweeks_DB.open_on_reload then
        if addon.main_frame then
            addon.main_frame:Show()
        end
    end
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end)

-- SLASH COMMANDS
-- Primary command: /lst (short for L's Tweeks)
SLASH_LSTWEEKS1 = "/lst"
SlashCmdList["LSTWEEKS"] = function(msg)
    if addon.main_frame then
        if addon.main_frame:IsShown() then
            addon.main_frame:Hide()
        else
            addon.main_frame:Show()
        end
    end
end