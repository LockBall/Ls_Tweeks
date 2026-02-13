local addon_name, addon = ...

-- LibDataBroker + LibDBIcon
local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

-- ============================================================================
-- LDB DATA OBJECT
-- ============================================================================
addon.data_object = LDB:NewDataObject("Ls_Tweeks_Minimap", {
    type = "launcher",
    icon = "Interface\\AddOns\\Ls_Tweeks\\media\\icon_256", 

    OnClick = function(_, button)
        if button == "LeftButton" then
            if addon.main_frame then
                if addon.main_frame:IsShown() then
                    addon.main_frame:Hide()
                else
                    addon.main_frame:Show()
                end
            else
                if addon.init_main_frame then 
                    addon.init_main_frame() 
                    if addon.main_frame then addon.main_frame:Show() end
                end
            end
        elseif button == "RightButton" then
            print("|cff00ff00Ls_Tweeks:|r Right-click menu not implemented yet.")
        end
    end,

    OnTooltipShow = function(tooltip)
        tooltip:AddLine("L's Tweeks")
        tooltip:AddLine("Left-click: Open main window", 1, 1, 1)
        tooltip:AddLine("Right-click: (reserved)", 1, 1, 1)
    end,
})

-- ============================================================================
-- HELPERS
-- ============================================================================
function addon.toggle_minimap_button(show)
    Ls_Tweeks_DB.minimap = Ls_Tweeks_DB.minimap or {}
    Ls_Tweeks_DB.minimap.hide = not show

    if show then
        LDBIcon:Show("Ls_Tweeks_Minimap")
    else
        LDBIcon:Hide("Ls_Tweeks_Minimap")
    end
end

-- ============================================================================
-- INITIALIZER
-- ============================================================================
function addon.init_minimap_button()
    if not Ls_Tweeks_DB then Ls_Tweeks_DB = {} end
    Ls_Tweeks_DB.minimap = Ls_Tweeks_DB.minimap or {}

    -- Register with LibDBIcon
    LDBIcon:Register("Ls_Tweeks_Minimap", addon.data_object, Ls_Tweeks_DB.minimap)

    -- Respect saved state
    if Ls_Tweeks_DB.minimap.hide then
        LDBIcon:Hide("Ls_Tweeks_Minimap")
    else
        LDBIcon:Show("Ls_Tweeks_Minimap")
    end
end