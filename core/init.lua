local addon_name, addon = ...

-- Addon namespace table
addon.name = addon_name

-- SavedVariables initialization
local function init_db()
    if not Ls_Tweeks_DB then
        Ls_Tweeks_DB = {}
    end

    if Ls_Tweeks_DB.combat_text_portrait_disabled == nil then
        Ls_Tweeks_DB.combat_text_portrait_disabled = false
    end

    if not Ls_Tweeks_DB.minimap then
        Ls_Tweeks_DB.minimap = { hide = false }
    end
end

-- Module initialization
local function init_modules()
    if addon.init_combat_text_portrait then
        addon.init_combat_text_portrait()
    end
end

-- Main frame UI
local function init_main_frame_wrapper()
    if addon.init_main_frame then
        addon.init_main_frame()
    end
end

-- Minimap button
local function init_minimap_button_wrapper()
    if addon.init_minimap_button then
        addon.init_minimap_button()
    end
end

-- Main initialization sequence
local function on_addon_loaded(self, event, name)
    if name ~= addon_name then
        return
    end

    init_db()
    init_main_frame_wrapper()
    init_minimap_button_wrapper()
    init_modules()
end

-- Event frame
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", on_addon_loaded)