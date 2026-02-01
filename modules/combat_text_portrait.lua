local addon_name, addon = ...

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
function addon.update_combat_text_portrait()
    if Ls_Tweeks_DB.combat_text_portrait_disabled then
        hide_portrait_combat_text()
    else
        show_portrait_combat_text()
    end
end

---------------------------------------------------------
-- Module initializer
---------------------------------------------------------
function addon.init_combat_text_portrait()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function()
        addon.update_combat_text_portrait()
    end)
end

---------------------------------------------------------
-- CATEGORY UI
---------------------------------------------------------
addon.register_category("Combat Text", function(parent)
    local cb = CreateFrame("CheckButton", "LST_CombatTextPortraitCB", parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -20)
    cb.Text:SetText("Disable portrait combat text")

    cb:SetChecked(Ls_Tweeks_DB.combat_text_portrait_disabled)

    cb:SetScript("OnClick", function(self)
        Ls_Tweeks_DB.combat_text_portrait_disabled = self:GetChecked()
        addon.update_combat_text_portrait()
    end)
end)