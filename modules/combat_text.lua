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

-- UI Configuration Constants (module-specific)
-- Shared values (padding, panel sizes, offsets, etc.) come from addon.UI_THEME
local UI_CONFIG = {
    checkbox_offset_x = 20,
    checkbox_offset_y = -20,
}

-- UI Strings and Labels (easy to locate for localization/customization)
local STRINGS = {
    category_name = "Combat Text",
    checkbox_label = "Disable portrait combat text",
    help_text = 
        "Disabling portrait combat text hides the Blizzard damage and healing numbers on the player portrait."
        .. "\n\nThis does not affect floating combat text or other addons that display combat information."
        .. "\n\nPortrait combat text does not seem to appear while fighting training dummies in rested areas, zzz",
}

-- Cached reference for performance (avoids repeated frame hierarchy traversal)
local hitIndicatorFrame = nil
local hookApplied = false
-- Post-Midnight: Supports both legacy and new UnitFrame paths
local function get_hit_indicator()
    if hitIndicatorFrame then return hitIndicatorFrame end
    
    -- Primary path (WoW 12.0+)
    if PlayerFrame and PlayerFrame.PlayerFrameContent then
        local content = PlayerFrame.PlayerFrameContent
        local main = content.PlayerFrameContentMain
        if main and main.HitIndicator then
            hitIndicatorFrame = main.HitIndicator
            return hitIndicatorFrame
        end
    end
    
    -- Fallback for potential frame restructuring
    if PlayerFrame and PlayerFrame.HitIndicator then
        hitIndicatorFrame = PlayerFrame.HitIndicator
        return hitIndicatorFrame
    end
    
    return nil
end

-- Set up hook only once for efficiency
-- Simplified: always hide when OnShow fires (DB is checked before hooking)
local function setup_on_show_hook(frame)
    if hookApplied or not frame then return end
    
    frame:HookScript("OnShow", function(self)
        self:SetAlpha(0)
    end)
    hookApplied = true
end

-- Apply alpha change and persistence hook
local function toggle_portrait_text(disable)
    local h = get_hit_indicator()
    if not h then return false end
    
    if disable then
        h:SetAlpha(0)
        setup_on_show_hook(h)
    else
        h:SetAlpha(1)
    end
    
    return true
end

-- Public update function for GUI and Login
function M.update_combat_text()
    if not Ls_Tweeks_DB then return end
    toggle_portrait_text(Ls_Tweeks_DB.combat_text)
end

-- Module initializer - consolidated event handling
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_LOGOUT")

-- Local function to handle initialization cleanup
local function init_complete(self)
    self:UnregisterEvent("ADDON_LOADED")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:SetScript("OnEvent", nil)
    -- Register only logout to reset cache for realm changes
    self:RegisterEvent("PLAYER_LOGOUT")
end

loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addon_name then return end
        
        -- Initialize Database Defaults
        Ls_Tweeks_DB = Ls_Tweeks_DB or {}
        for k, v in pairs(defaults) do
            if Ls_Tweeks_DB[k] == nil then
                Ls_Tweeks_DB[k] = v
            end
        end
        
        -- Register the GUI Category early to allow UI setup
        if addon.register_category then
            addon.register_category(STRINGS.category_name, function(parent)
                local cfg = UI_CONFIG
                local theme = addon.UI_THEME
                local cb = CreateFrame("CheckButton", "LST_CombatTextPortraitCB", parent, "InterfaceOptionsCheckButtonTemplate")
                cb:SetPoint("TOPLEFT", parent, "TOPLEFT", cfg.checkbox_offset_x, cfg.checkbox_offset_y)
                cb.Text:SetText(STRINGS.checkbox_label)
                cb:SetChecked(Ls_Tweeks_DB.combat_text)

                -- Real-time click handler
                cb:SetScript("OnClick", function(btn)
                    Ls_Tweeks_DB.combat_text = btn:GetChecked()
                    M.update_combat_text()
                end)

                -- Riveted panel & note
                local panelWidth = math.min(theme.panel_max_width, parent:GetWidth() - theme.panel_margin)
                local notePanel, noteText = addon.CreateRivetedPanel(
                    parent,                -- parent frame
                    panelWidth,            -- width
                    theme.panel_min_height,-- initial height
                    parent,                -- anchor frame
                    "TOP",                 -- anchor point
                    theme.offset_x,        -- x offset
                    theme.offset_y         -- y offset
                )
                
                -- Safety check
                if not notePanel or not noteText then return end

                -- Configure text display
                noteText:ClearAllPoints()
                noteText:SetJustifyH("LEFT")
                noteText:SetJustifyV("TOP")
                noteText:SetWordWrap(true)
                noteText:SetText(STRINGS.help_text)
                
                -- Anchor with padding
                local pad = theme.padding
                noteText:SetPoint("TOPLEFT", notePanel, "TOPLEFT", pad, -pad)
                noteText:SetPoint("RIGHT", notePanel, "RIGHT", -pad, 0)

                -- Auto-size panel to fit content
                local textHeight = noteText:GetHeight()
                notePanel:SetHeight(math.max(theme.panel_min_height, textHeight + (pad * 2)))

                -- Store references
                M.controls.portraitNotePanel = notePanel
                M.controls.portraitNoteText = noteText
            end)
        end
    
    elseif event == "PLAYER_ENTERING_WORLD" then
        M.update_combat_text()
        init_complete(self)
    
    elseif event == "PLAYER_LOGOUT" then
        -- Reset cached frame reference on logout (handles realm changes)
        hitIndicatorFrame = nil
        hookApplied = false
    end
end)