local addon_name, addon = ...
addon.name = addon_name

-- ============================================================================
-- VERSION RETRIEVAL
-- ============================================================================
local v_frame = CreateFrame("Frame")
v_frame:RegisterEvent("ADDON_LOADED")
v_frame:SetScript("OnEvent", function(self, event, name)
    if name == addon_name then
        addon.version = C_AddOns.GetAddOnMetadata(addon_name, "Version")
    end
end)

-- ============================================================================
-- DATABASE INITIALIZATION
-- ============================================================================
local function init_db()
    if not Ls_Tweeks_DB then
        Ls_Tweeks_DB = {}
    end

    -- Core UI settings (Minimap)
    if not Ls_Tweeks_DB.minimap then
        Ls_Tweeks_DB.minimap = { hide = false }
    end
    
    -- Module specific defaults are now handled within the modules themselves
    -- to keep this file clean and truly modular.
end

-- ============================================================================
-- MAIN INITIALIZATION SEQUENCE
-- ============================================================================
local function on_addon_loaded(self, event, name)
    if name ~= addon_name then return end

    -- 1. Initialize Global Database
    init_db()

    -- 2. Initialize Core UI Framework
    -- This must happen before modules register their categories
    if addon.init_main_frame then
        addon.init_main_frame()
    end

    -- 3. Initialize Minimap Button (LDB)
    if addon.init_minimap_button then
        addon.init_minimap_button()
    end

    -- Note: Module-specific init functions (like aura frames) are now 
    -- self-starting via their own ADDON_LOADED scripts.
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", on_addon_loaded)

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================
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