local addon_name, addon = ...
addon.name = addon_name

-- VERSION RETRIEVAL
local v_frame = CreateFrame("Frame")
v_frame:RegisterEvent("ADDON_LOADED")
v_frame:SetScript("OnEvent", function(self, event, name)
    if name == addon_name then
        addon.version = C_AddOns.GetAddOnMetadata(addon_name, "Version")
    end
end)

-- DATABASE INITIALIZATION
local function init_db()
    if not Ls_Tweeks_DB then
        Ls_Tweeks_DB = {}
    end

    -- Core UI settings (Minimap)
    if not Ls_Tweeks_DB.minimap then
        Ls_Tweeks_DB.minimap = { hide = false }
    end
    
end

-- MAIN INITIALIZATION SEQUENCE
local function on_addon_loaded(self, event, name)
    if name ~= addon_name then return end

    init_db() -- Global Database

    if addon.init_main_frame then -- Core UI Framework, must happen before modules register their categories

        addon.init_main_frame()
    end

    if addon.init_minimap_button then
        addon.init_minimap_button()
    end

    -- Module-specific init functions (like aura frames) are self-starting via their own ADDON_LOADED scripts
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", on_addon_loaded)

-- SLASH COMMANDS
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