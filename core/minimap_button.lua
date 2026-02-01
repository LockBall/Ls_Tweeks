local addon_name, addon = ...

-- LibDataBroker + LibDBIcon
local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

---------------------------------------------------------
-- Create the LDB data object for the minimap button
---------------------------------------------------------
addon.data_object = LDB:NewDataObject("Ls_Tweeks_Minimap", {
    type = "launcher",
    icon = "Interface\\AddOns\\Ls_Tweeks\\media\\icon_256", -- your icon

    OnClick = function(_, button)
        if button == "LeftButton" then
            -- Toggle the main window
            if addon.main_frame and addon.main_frame:IsShown() then
                addon.main_frame:Hide()
            else
                if addon.main_frame then
                    addon.main_frame:Show()
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

---------------------------------------------------------
-- Minimap button toggle helper
---------------------------------------------------------
function addon.toggle_minimap_button(show)
    Ls_Tweeks_DB.minimap = Ls_Tweeks_DB.minimap or {}
    Ls_Tweeks_DB.minimap.hide = not show

    if show then
        LDBIcon:Show("Ls_Tweeks_Minimap")
    else
        LDBIcon:Hide("Ls_Tweeks_Minimap")
    end
end

---------------------------------------------------------
-- Initializer (called from core/init.lua)
---------------------------------------------------------
function addon.init_minimap_button()
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