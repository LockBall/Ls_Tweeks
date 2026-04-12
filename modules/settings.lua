-- Ls_Tweeks - settings.lua

local addon_name, addon = ...

-- Initialize module table
addon.settings = addon.settings or {
    controls = {},
    frames = {}
}

local M = addon.settings

-- UI Configuration Constants (module-specific)
local UI_CONFIG = {
    title_offset_x = 20,
    title_offset_y = -20,
    section_offset_y = -20,
    checkbox_spacing = 30,
}

-- UI Strings and Labels
local STRINGS = {
    category_name = "Settings",
    title = "Addon Main Interface Settings",
    minimap_icon_label = "Minimap Icon",
}

-- Build Settings page content
local function build_settings_page(parent)
    local cfg = UI_CONFIG
    local theme = addon.UI_THEME
    
    -- Title
    local title = parent:CreateFontString(nil, "OVERLAY", theme.font_title)
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", cfg.title_offset_x, cfg.title_offset_y)
    title:SetText(STRINGS.title)
    M.controls.title = title
    
    -- Minimap Icon Checkbox
    Ls_Tweeks_DB = Ls_Tweeks_DB or {}
    Ls_Tweeks_DB.minimap = Ls_Tweeks_DB.minimap or {}
    
    local is_visible = not Ls_Tweeks_DB.minimap.hide
    
    local checkbox_container, checkbox_btn, checkbox_label = addon.CreateCheckbox(
        parent,
        STRINGS.minimap_icon_label,
        is_visible,
        function(is_checked)
            -- Toggle minimap button visibility
            addon.toggle_minimap_button(is_checked)
        end
    )
    
    checkbox_container:SetPoint("TOPLEFT", title, "BOTTOMLEFT", cfg.title_offset_x, cfg.section_offset_y)
    
    -- Caption to explain /lt command
    local caption = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    caption:SetPoint("LEFT", checkbox_container, "RIGHT", 25, 0)
    caption:SetText("(Type |cff00ff00/lt|r to access addon when disabled)")
    caption:SetTextColor(0.8, 0.8, 0.8, 1)
    M.controls.caption = caption
    
    -- Store references
    M.controls.checkbox_container = checkbox_container
    M.controls.checkbox = checkbox_btn
    M.controls.checkbox_label = checkbox_label
end

-- Module initializer
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addon_name then return end
        
        -- Register the GUI Category
        if addon.register_category then
            addon.register_category(STRINGS.category_name, build_settings_page)
        end
        
        self:UnregisterEvent("ADDON_LOADED")
        self:SetScript("OnEvent", nil)
    end
end)
