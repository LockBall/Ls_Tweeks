local addon_name, addon = ...

local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

-- Configuration Constants
local CONFIG = {
    name = "Ls_Tweeks_Minimap",
    icon = "Interface\\AddOns\\Ls_Tweeks\\media\\icon_256",
    title = "L's Tweeks",
    tooltip_left_click = "Left-click: Open main window",
    tooltip_right_click = "Right-click: (reserved)",
    msg_right_click = "|cff00ff00Ls_Tweeks:|r Right-click menu not implemented yet.",
}

-- Helper: Toggle main frame visibility
local function toggle_main_frame()
    if addon.main_frame then
        if addon.main_frame:IsShown() then
            addon.main_frame:Hide()
        else
            addon.main_frame:Show()
        end
    elseif addon.init_main_frame then
        addon.init_main_frame()
        if addon.main_frame then addon.main_frame:Show() end
    end
end

-- ============================================================================
-- LDB DATA OBJECT
-- LibDataBroker: Provides a data source for minimap buttons via LibDBIcon.
-- OnClick handles left/right button interactions with the minimap icon.
-- OnTooltipShow provides contextual help when hovering over the button.
addon.data_object = LDB:NewDataObject(CONFIG.name, {
    type = "launcher",
    icon = CONFIG.icon,

    OnClick = function(_, button)
        if button == "LeftButton" then
            toggle_main_frame()
        elseif button == "RightButton" then
            print(CONFIG.msg_right_click)
        end
    end,

    OnTooltipShow = function(tooltip)
        tooltip:AddLine(CONFIG.title)
        tooltip:AddLine(CONFIG.tooltip_left_click, 1, 1, 1)
        tooltip:AddLine(CONFIG.tooltip_right_click, 1, 1, 1)
    end,
})

-- ============================================================================
-- HELPERS
function addon.toggle_minimap_button(show)
    Ls_Tweeks_DB.minimap = Ls_Tweeks_DB.minimap or {}
    Ls_Tweeks_DB.minimap.hide = not show
    
    if show then
        LDBIcon:Show(CONFIG.name)
    else
        LDBIcon:Hide(CONFIG.name)
    end
end

-- ============================================================================
-- INITIALIZER
-- ============================================================================
function addon.init_minimap_button()
    Ls_Tweeks_DB = Ls_Tweeks_DB or {}
    Ls_Tweeks_DB.minimap = Ls_Tweeks_DB.minimap or {}

    -- Register with LibDBIcon (uses saved state in Ls_Tweeks_DB.minimap)
    LDBIcon:Register(CONFIG.name, addon.data_object, Ls_Tweeks_DB.minimap)

    -- Apply saved visibility state
    if Ls_Tweeks_DB.minimap.hide then
        LDBIcon:Hide(CONFIG.name)
    else
        LDBIcon:Show(CONFIG.name)
    end
end