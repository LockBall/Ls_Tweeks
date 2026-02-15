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
        h:Show()
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

                -- Riveted panel note
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
                M.controls = M.controls or {}
                M.controls.portraitNotePanel = notePanel
                M.controls.portraitNoteText  = noteText

            end)
        end

        self:UnregisterEvent("ADDON_LOADED")
    end
end)