local addon_name, addon = ...
local M = addon.aura_frames

-- SETTINGS & CONSTANTS
local MAX_POOL_SIZE = 40 -- Default pre-allocation count

-- BLIZZARD Buff & Debuff FRAME TOGGLES
local function set_blizz_frame_state(frame, hide)
    if not frame then return end
    
    if hide then
        frame:Hide()
        frame:UnregisterAllEvents()
    else -- Re-register the essential events
        frame:RegisterEvent("UNIT_AURA")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:Show()

        if frame == BuffFrame and frame.UpdateAuras then  -- Trigger Blizzard internal refresh logic to rebuild the icon list
            frame:UpdateAuras()
        elseif frame == DebuffFrame and frame.UpdateAuras then
            frame:UpdateAuras()
        end
    end
end

function M.toggle_blizz_buffs(hide)
    set_blizz_frame_state(BuffFrame, hide)
end

function M.toggle_blizz_debuffs(hide)
    set_blizz_frame_state(DebuffFrame, hide)
end

-- safely copy default tables into saved variables without reference issues
local function deep_copy(src, dest)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = dest[k] or {}
            deep_copy(v, dest[k])
        else
            if dest[k] == nil then dest[k] = v end
        end
    end
end

-- AURA CONTAINER GENERATOR
function M.create_aura_frame(show_key, move_key, timer_key, bg_key, scale_key, spacing_key, display_name, is_debuff)
    local category = show_key:sub(6)
    local frame = CreateFrame("Frame", "LsTweaksAuraFrame_"..show_key, UIParent, "BackdropTemplate")
    frame.category = category
    frame:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }})
    frame:SetMovable(true) 
    frame:SetResizable(true) 
    frame:SetClampedToScreen(true)
    frame:SetSize(M.db["width_"..category] or 200, 50)

    local pos = M.db.positions and M.db.positions[category]
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, is_debuff and -100 or 100)
    end
    
    -- TITLE BAR LOGIC
    local TITLEBAR_ANCHORS = {
        top =    { from = "BOTTOM", to = "TOP", offset = -2 },
        bottom = { from = "TOP",    to = "BOTTOM", offset = 2 },
    }

    local function CreateTitleBar(parent, label, is_bottom)
        local cfg = is_bottom and TITLEBAR_ANCHORS.bottom or TITLEBAR_ANCHORS.top
        local tb = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        tb:SetPoint(cfg.from.."LEFT",  parent, cfg.to.."LEFT",  0, cfg.offset)
        tb:SetPoint(cfg.from.."RIGHT", parent, cfg.to.."RIGHT", 0, cfg.offset)
        tb:SetHeight(20)
        tb:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 12, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        tb:SetBackdropColor(0.2, 0.2, 0.2, 1)
        local text = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetText(label)
        tb:EnableMouse(true)
        tb:RegisterForDrag("LeftButton")
        tb:SetScript("OnDragStart", function() parent:StartMoving() end)
        tb:SetScript("OnDragStop", function() 
            parent:StopMovingOrSizing() 
            local p, _, _, x, y = parent:GetPoint()
            M.db.positions[parent.category] = { point = p, x = x, y = y }
        end)
        return tb
    end
    
    frame.title_bar = CreateTitleBar(frame, display_name, false)
    frame.bottom_title_bar = CreateTitleBar(frame, display_name, true)
    
    -- RESIZER
    frame.resizer = CreateFrame("Button", nil, frame)
    frame.resizer:SetSize(16, 16)
    frame.resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    frame.resizer:SetScript("OnMouseDown", function() frame:StartSizing("RIGHT") end)
    frame.resizer:SetScript("OnMouseUp", function() 
        frame:StopMovingOrSizing() 
        M.db["width_"..category] = frame:GetWidth() 
        M.update_auras(frame, show_key, move_key, timer_key, bg_key, scale_key, spacing_key, is_debuff and "HARMFUL" or "HELPFUL") 
    end)

    -- ICON POOL MANAGEMENT    Pre-create set number of icons/bars to avoid combat lockdown errors
    frame.icons = {}
    local pool_size = M.db["max_icons_"..category] or MAX_POOL_SIZE

    for i = 1, pool_size do
        local obj = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        obj:Hide()
        
        -- Icon Texture
        obj.texture = obj:CreateTexture(nil, "ARTWORK")
        
        -- Status Bar (for bar mode)
        obj.bar = CreateFrame("StatusBar", nil, obj)
        obj.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        obj.bar:SetMinMaxValues(0, 1)
        obj.bar:Hide()
        
        -- Text
        obj.name_text = obj.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall", 7)
        obj.time_text = obj.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall", 7)
        
        -- Tooltip
        obj:EnableMouse(true)
        obj:SetScript("OnEnter", function(s)
            if s.aura_index then
                GameTooltip:SetOwner(s, "ANCHOR_BOTTOMRIGHT")
                -- We use the filter passed to update_auras
                local filter = is_debuff and "HARMFUL" or "HELPFUL"
                GameTooltip:SetUnitAura("player", s.aura_index, filter)
                GameTooltip:Show()
            end
        end)
        obj:SetScript("OnLeave", function() GameTooltip:Hide() end)

        frame.icons[i] = obj
    end

    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(self) 
        M.update_auras(self, show_key, move_key, timer_key, bg_key, scale_key, spacing_key, is_debuff and "HARMFUL" or "HELPFUL") 
    end)
    
    M.frames[show_key] = frame
    return frame
end

-- INITIALIZATION
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name == addon_name then
        if not Ls_Tweeks_DB then Ls_Tweeks_DB = {} end
        if M.defaults then deep_copy(M.defaults, Ls_Tweeks_DB) end
        
        M.db = Ls_Tweeks_DB 

        M.create_aura_frame("show_static",  "move_static",  "timer_static", "bg_static",    "scale_static", "spacing_static",   "Static",   false)
        M.create_aura_frame("show_short",   "move_short",   "timer_short",  "bg_short",     "scale_short",  "spacing_short",    "Short",    false)
        M.create_aura_frame("show_long",    "move_long",    "timer_long",   "bg_long",      "scale_long",   "spacing_long",     "Long",     false)
        M.create_aura_frame("show_debuff",  "move_debuff",  "timer_debuff", "bg_debuff",    "scale_debuff", "spacing_debuff",   "Debuffs",  true)
        
        M.toggle_blizz_buffs(M.db.disable_blizz_buffs)
        M.toggle_blizz_debuffs(M.db.disable_blizz_debuffs)

        if addon.register_category and M.BuildSettings then
            addon.register_category("Buffs & Debuffs", function(parent) 
                M.BuildSettings(parent)
            end)
        end
        self:UnregisterEvent("ADDON_LOADED")
    end

    -- This is called automatically by the Big Red Button in module_reset.lua
    -- Since reset sets them to 'false', this will bring them back.
    function M.on_reset_complete()
        M.toggle_blizz_buffs(M.db.disable_blizz_buffs)
        M.toggle_blizz_debuffs(M.db.disable_blizz_debuffs)
        -- 2. Update the checkboxes if the settings window is currently open
        if M.controls then
            if M.controls["disable_blizz_buffs"] then M.controls["disable_blizz_buffs"]:SetChecked(M.db.disable_blizz_buffs) end
            if M.controls["disable_blizz_debuffs"] then M.controls["disable_blizz_debuffs"]:SetChecked(M.db.disable_blizz_debuffs) end
        end
    end
    
end)