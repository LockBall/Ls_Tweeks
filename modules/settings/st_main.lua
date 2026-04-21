-- Ls_Tweeks - settings/st_main.lua

local addon_name, addon = ...

-- Initialize module table
addon.st = addon.st or {
    controls = {},
    frames = {}
}

local M = addon.st

-- UI Configuration Constants (module-specific)
local UI_CONFIG = {
    title_offset_x = 20,
    title_offset_y = -20,
    section_offset_y = -20,
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
    local defaults = addon.module_defaults and addon.module_defaults.st or {}

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

    -- Open on Reload Checkbox
    local reload_container, reload_btn, _ = addon.CreateCheckbox(
        parent,
        "Open on Reload",
        Ls_Tweeks_DB.open_on_reload or defaults.open_on_reload,
        function(is_checked)
            Ls_Tweeks_DB.open_on_reload = is_checked
        end
    )
    reload_container:SetPoint("TOPLEFT", checkbox_container, "BOTTOMLEFT", 0, cfg.section_offset_y)
    M.controls.reload_checkbox = reload_btn

    -- Alpha Slider for Interface Transparency
    local function apply_alpha()
        local a = Ls_Tweeks_DB.interface_alpha
        if not addon.main_frame then return end
        addon.main_frame:SetBackdropColor(0.06, 0.06, 0.06, a)
        if addon.main_frame.title_bar   then addon.main_frame.title_bar:SetBackdropColor(0.12, 0.12, 0.12, a) end
        if addon.main_frame.sidebar     then addon.main_frame.sidebar:SetBackdropColor(0.10, 0.10, 0.10, a) end
        if addon.main_frame.content_area then addon.main_frame.content_area:SetBackdropColor(0.08, 0.08, 0.08, a) end
    end

    Ls_Tweeks_DB.interface_alpha = Ls_Tweeks_DB.interface_alpha or defaults.interface_alpha
    local alpha_slider = addon.CreateSliderWithBox(
        addon_name.."AlphaSlider", parent, "Interface Transparency", 0.0, 1, 0.05, Ls_Tweeks_DB, "interface_alpha", defaults,
        apply_alpha
    )
    alpha_slider:SetPoint("TOPLEFT", reload_container, "BOTTOMLEFT", 0, cfg.section_offset_y)
    M.controls.alpha_slider = alpha_slider

    apply_alpha()
end

-- Module initializer
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addon_name then return end
        if addon.register_category then
            addon.register_category(STRINGS.category_name, build_settings_page)
        end
        self:UnregisterEvent("ADDON_LOADED")
        self:SetScript("OnEvent", nil)
    end
end)
