-- Ls_Tweeks - combat_text.lua

local addon_name, addon = ...

-- Initialize module table
addon.combat_text = addon.combat_text or {
    controls = {},
    frames = {}
}

local M = addon.combat_text

-- Default Settings
local defaults = {
    combat_text = false,
}
local function toggle_portrait_text(disable)
    local h = PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator

    if not h then return false end

    if disable then
        h:SetAlpha(0)
        if not M._scriptHooked then
            h:HookScript("OnShow", function(self)
                if Ls_Tweeks_DB and Ls_Tweeks_DB.combat_text then
                    self:SetAlpha(0)
                end
            end)
            M._scriptHooked = true
        end
    else
        h:SetAlpha(1)
    end
    return true

end

-- Update function for GUI and Login
function M.update_combat_text()
    if not Ls_Tweeks_DB then return end
    local desired = Ls_Tweeks_DB.combat_text
    toggle_portrait_text(desired)
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

        -- Create a frame to apply the change once the player frame exists
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:SetScript("OnEvent", function()
            M.update_combat_text()
            f:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end)

        -- Register the GUI Category
        if addon.register_category then

            addon.register_category("Combat Text", function(parent)
                local cb = CreateFrame("CheckButton", "LST_CombatTextPortraitCB", parent, "InterfaceOptionsCheckButtonTemplate")
                cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -20)
                cb.Text:SetText("Disable portrait combat text")
                cb:SetChecked(Ls_Tweeks_DB.combat_text)

                -- Real-time click handler
                cb:SetScript("OnClick", function(btn)
                    Ls_Tweeks_DB.combat_text = btn:GetChecked()
                    M.update_combat_text()
                end)

                -- Riveted panel & note
                local panelWidth  = parent:GetWidth() - 60
                local panelHeight = 140
                local anchorTo    = cb
                local anchorPoint = "TOPLEFT", "BOTTOMLEFT"
                local offsetX, offsetY = 0, -40

                local notePanel, noteText = addon.CreateRivetedPanel(
                    parent,         -- parent frame
                    panelWidth,     -- width
                    panelHeight,    -- height
                    anchorTo,       -- anchor frame (cb)
                    anchorPoint,    -- anchor point on anchorTo
                    offsetX,        -- x offset
                    offsetY         -- y offset
                )

                local padding = 24
                local textWidth = notePanel:GetWidth() - (padding * 2)

                noteText:ClearAllPoints()
                noteText:SetPoint("TOPLEFT", notePanel, "TOPLEFT", padding, -padding)
                noteText:SetWidth(textWidth)
                noteText:SetJustifyH("LEFT")
                noteText:SetWordWrap(true)
                -- optional: noteText:SetHeight(whatever) if you want to clamp vertical size

                noteText:SetText("Note: Disabling portrait combat text hides the Blizzard damage and healing numbers on the player portrait."..
                "\n\nThis does not affect floating combat text or other addons that display combat information."..
                "\n\nPortrait combat text does not seem to appear while fighting training dummies in rested areas, zzz")

                -- keep references if you need to update later
                M.controls.portraitNotePanel = notePanel
                M.controls.portraitNoteText  = noteText

            end)
        end

        self:UnregisterEvent("ADDON_LOADED")
    end
end)