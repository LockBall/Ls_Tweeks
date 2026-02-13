local addon_name, addon = ...

-- Initialize module table for reset-sync compatibility
addon.combat_text = {
    controls = {},
    frames = {} -- We don't have movable frames here, but keep it for logic consistency
}

local M = addon.combat_text

-- Default Settings
local defaults = {
    combat_text_portrait_disabled = false,
}

---------------------------------------------------------
-- Internal helpers
---------------------------------------------------------
local function hide_portrait_combat_text()
    local h = PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator

    if h then
        h:Hide()
        h.Show = function() end
    end
end

local function show_portrait_combat_text()
    local h = PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator

    if h then
        h.Show = nil
        h:Show()
    end
end

---------------------------------------------------------
-- Update function
---------------------------------------------------------
function M.update_combat_text_portrait()
    if Ls_Tweeks_DB.combat_text_portrait_disabled then
        hide_portrait_combat_text()
    else
        show_portrait_combat_text()
    end
end

-- Compatibility hook for the Global Reset button
function M.on_reset_complete()
    M.update_combat_text_portrait()
end

---------------------------------------------------------
-- Module initializer
---------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name == addon_name then
        -- Initialize Database Defaults
        if not Ls_Tweeks_DB then Ls_Tweeks_DB = {} end
        for k, v in pairs(defaults) do
            if Ls_Tweeks_DB[k] == nil then Ls_Tweeks_DB[k] = v end
        end

        M.update_combat_text_portrait()
        
        -- Register the GUI Category
        if addon.register_category then
            addon.register_category("Combat Text", function(parent)
                local cb = CreateFrame("CheckButton", "LST_CombatTextPortraitCB", parent, "InterfaceOptionsCheckButtonTemplate")
                cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -20)
                cb.Text:SetText("Disable portrait combat text")
                cb:SetChecked(Ls_Tweeks_DB.combat_text_portrait_disabled)

                cb:SetScript("OnClick", function(self)
                    Ls_Tweeks_DB.combat_text_portrait_disabled = self:GetChecked()
                    M.update_combat_text_portrait()
                end)

                -- Register control so Reset Button can find it
                M.controls["combat_text_portrait_disabled"] = cb
            end)
        end
    end
end)