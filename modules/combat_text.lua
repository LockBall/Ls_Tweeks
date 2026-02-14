local addon_name, addon = ...

-- Initialize module table
addon.combat_text = {
    controls = {},
    frames = {} 
}

local M = addon.combat_text

-- Default Settings
local defaults = {
    combat_text_portrait_disabled = false,
}

-- Internal helpers
local function toggle_portrait_text(disable)
    -- Target the specific Blizzard HitIndicator
    local h = PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator

    if not h then return end

    if disable then
        h:Hide()
        -- Safely stop the frame from reacting to combat events
        h:UnregisterAllEvents() 
    else
        -- Re-enable the standard Blizzard behavior
        h:RegisterEvent("UNIT_COMBAT")
    end
end

-- Update function
function M.update_combat_text_portrait()
    if Ls_Tweeks_DB and Ls_Tweeks_DB.combat_text_portrait_disabled then
        toggle_portrait_text(true)
    else
        toggle_portrait_text(false)
    end
end

-- Module initializer
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
            end)
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)