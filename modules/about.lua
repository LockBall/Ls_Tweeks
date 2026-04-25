-- The "About" settings page: displays the addon name, version, author, and a brief description.
-- Registered as the first sidebar category so it appears when the settings window is opened for the first time.

local addon_name, addon = ...

-- Initialize module table
addon.about = addon.about or {
    controls = {},
    frames = {}
}

local M = addon.about

-- UI Configuration Constants (module-specific)
-- Shared values (padding, panel sizes, etc.) come from addon.UI_THEME
local UI_CONFIG = {
    title_offset_x = 20,
    title_offset_y = -20,
    version_offset_y = -10,
    panel_offset_y = -20,
}

-- UI Strings and Labels
local STRINGS = {
    category_name = "About",
    title = "To begin, click a module button on the left.",
    version_label = "Version: ",
    description = "A modular collection of UI tweaks."
    .. "\n\nBuff and DeBuff handling inspired by and based on Elkano's Buff Bars by Elkano.",
}

-- Build About page content
local function build_about_page(parent)
    local cfg = UI_CONFIG
    local theme = addon.UI_THEME
    local panel_style = addon.RIVETED_PANEL_STYLE

    local title = parent:CreateFontString(nil, "OVERLAY", theme.font_title)
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", cfg.title_offset_x, cfg.title_offset_y)
    title:SetText(STRINGS.title)

    local version = parent:CreateFontString(nil, "OVERLAY", theme.font_subtitle)
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, cfg.version_offset_y)
    version:SetText(STRINGS.version_label .. (addon.version or "0.1.0"))

    -- Create riveted panel for description
    local panelWidth = math.min(panel_style.panel_max_width, 741 - panel_style.panel_margin)
    local descPanel, descText = addon.CreateRivetedPanel(
        parent,                       -- parent frame
        panelWidth,                   -- width
        panel_style.panel_min_height, -- initial height
        version,                      -- anchor to version
        "TOPLEFT",                    -- anchor point
        0,                            -- x offset
        cfg.panel_offset_y            -- y offset
    )

    -- Safety check
    if not descPanel or not descText then return end

    -- Configure description text in panel
    local pad = panel_style.padding
    descText:ClearAllPoints()
    descText:SetJustifyH("LEFT")
    descText:SetJustifyV("TOP")
    descText:SetWordWrap(true)
    descText:SetText(STRINGS.description)

    -- Anchor with padding
    descText:SetPoint("TOPLEFT", descPanel, "TOPLEFT", pad, -pad)
    descText:SetPoint("RIGHT", descPanel, "RIGHT", -pad, 0)

    -- Auto-size panel to fit content
    local textHeight = descText:GetHeight()
    descPanel:SetHeight(math.max(panel_style.panel_min_height, textHeight + (pad * 2)))
    
end

-- Module initializer
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addon_name then return end
        
        -- Register the GUI Category
        if addon.register_category then
            addon.register_category(STRINGS.category_name, build_about_page)
        end
        
        self:UnregisterEvent("ADDON_LOADED")
        self:SetScript("OnEvent", nil)
    end
end)
