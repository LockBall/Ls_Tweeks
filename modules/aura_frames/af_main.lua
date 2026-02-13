local addon_name, addon = ...

-- Grab the unified module table created in af_defaults.lua
local M = addon.aura_frames

-- ============================================================================
-- BLIZZARD FRAME MANAGEMENT
-- ============================================================================
function M.toggle_blizz_buffs(hide)
    if hide then 
        BuffFrame:Hide() 
        BuffFrame:UnregisterAllEvents() 
    else 
        BuffFrame:Show() 
        BuffFrame:RegisterEvent("UNIT_AURA") 
    end
end

function M.toggle_blizz_debuffs(hide)
    if hide then 
        DebuffFrame:Hide() 
        DebuffFrame:UnregisterAllEvents() 
    else 
        DebuffFrame:Show() 
        DebuffFrame:RegisterEvent("UNIT_AURA") 
    end
end

-- ============================================================================
-- AURA CONTAINER GENERATOR
-- ============================================================================
function M.create_aura_frame(show_key, move_key, timer_key, bg_key, scale_key, spacing_key, display_name, is_debuff)
    local category = show_key:sub(6) -- extract "static", "short", etc.
    local frame = CreateFrame("Frame", "LsTweaksAuraFrame_"..show_key, UIParent, "BackdropTemplate")    
    frame:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }})
    frame:SetMovable(true) 
    frame:SetResizable(true) 
    frame:SetClampedToScreen(true)

    -- Set size and position from DB
    frame:SetSize(M.db["width_"..category] or 200, 50) -- Default height, dynamic width

    local pos = M.db.positions and M.db.positions[category]
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, is_debuff and -100 or 100)
    end
    
    local function CreateTitleBar(parent, is_bottom)
        local tb = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        tb:SetPoint(is_bottom and "TOPLEFT" or "BOTTOMLEFT", parent, is_bottom and "BOTTOMLEFT" or "TOPLEFT", 0, is_bottom and 2 or -2)
        tb:SetPoint(is_bottom and "TOPRIGHT" or "BOTTOMRIGHT", parent, is_bottom and "BOTTOMRIGHT" or "TOPRIGHT", 0, is_bottom and 2 or -2)
        tb:SetHeight(20)
        tb:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 12, edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 }})
        tb:SetBackdropColor(0.2, 0.2, 0.2, 1)
        
        local text = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", tb, "CENTER", 0, 0)
        text:SetText(display_name)
        
        tb:EnableMouse(true) 
        tb:RegisterForDrag("LeftButton")
        tb:SetScript("OnDragStart", function() parent:StartMoving() end)
        tb:SetScript("OnDragStop", function() 
            parent:StopMovingOrSizing() 
            local p, _, _, x, y = parent:GetPoint() 
            M.db.positions[category] = { point = p, x = x, y = y } 
        end)
        return tb
    end
    
    frame.title_bar = CreateTitleBar(frame, false)
    frame.bottom_title_bar = CreateTitleBar(frame, true)
    
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

    frame.icons = {}
    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    
    frame:SetScript("OnEvent", function(self) 
        M.update_auras(self, show_key, move_key, timer_key, bg_key, scale_key, spacing_key, is_debuff and "HARMFUL" or "HELPFUL") 
    end)
    
    M.frames[show_key] = frame
    return frame
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name == addon_name then
        if not Ls_Tweeks_DB then Ls_Tweeks_DB = {} end
        
        -- Use M.defaults from af_defaults.lua
        if M.defaults then
            for k, v in pairs(M.defaults) do 
                if Ls_Tweeks_DB[k] == nil then 
                    if type(v) == "table" then
                        Ls_Tweeks_DB[k] = {}
                        -- Deep copy for tables like 'positions' or 'color'
                        for subK, subV in pairs(v) do
                            if type(subV) == "table" then
                                Ls_Tweeks_DB[k][subK] = {}
                                for innerK, innerV in pairs(subV) do Ls_Tweeks_DB[k][subK][innerK] = innerV end
                            else Ls_Tweeks_DB[k][subK] = subV end
                        end
                    else Ls_Tweeks_DB[k] = v end
                end 
            end
        end
        
        -- Crucial: Link M.db to the actual saved variables
        M.db = Ls_Tweeks_DB
        
        -- Create the 4 containers
        M.create_aura_frame("show_static",  "move_static",  "timer_static", "bg_static",    "scale_static", "spacing_static",   "Static",   false)
        M.create_aura_frame("show_short",   "move_short",   "timer_short",  "bg_short",     "scale_short",  "spacing_short",    "Short",    false)
        M.create_aura_frame("show_long",    "move_long",    "timer_long",   "bg_long",      "scale_long",   "spacing_long",     "Long",     false)
        M.create_aura_frame("show_debuff",  "move_debuff",  "timer_debuff", "bg_debuff",    "scale_debuff", "spacing_debuff",   "Debuffs",  true)
        
        -- Run the Blizzard frame visibility logic
        M.toggle_blizz_buffs(M.db.disable_blizz_buffs)
        M.toggle_blizz_debuffs(M.db.disable_blizz_debuffs)

        -- GUI Registration
        if addon.register_category and M.BuildSettings then
            addon.register_category("Buffs & Debuffs", function(parent) 
                M.BuildSettings(parent)
            end)
        end
        
        self:UnregisterEvent("ADDON_LOADED")

    end

    -- This is called automatically by the Big Red Button in module_reset.lua
    function M.on_reset_complete()
        -- 1. Force the Blizzard frames to show/hide based on the new (default) DB values
        -- Since reset sets them to 'false', this will bring them back.
        M.toggle_blizz_buffs(M.db.disable_blizz_buffs)
        M.toggle_blizz_debuffs(M.db.disable_blizz_debuffs)

        -- 2. Update the checkboxes if the settings window is currently open
        if M.controls then
            if M.controls["disable_blizz_buffs"] then
                M.controls["disable_blizz_buffs"]:SetChecked(M.db.disable_blizz_buffs)
            end
            if M.controls["disable_blizz_debuffs"] then
                M.controls["disable_blizz_debuffs"]:SetChecked(M.db.disable_blizz_debuffs)
            end
        end
    end

end)