local addon_name, addon = ...
local M = addon.aura_frames

-- SETTINGS & CONSTANTS
local MAX_POOL_SIZE = 40 -- Default pre-allocation count
local issecretvalue = issecretvalue or function() return false end

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
 
        if frame.UpdateLayout then
            frame:UpdateLayout()
        end
    end
end

function M.toggle_blizz_buffs(hide)
    set_blizz_frame_state(BuffFrame, hide)
end

function M.toggle_blizz_debuffs(hide)
    set_blizz_frame_state(DebuffFrame, hide)
end

-- Merge UNIT_AURA payloads while a deferred scan is pending.
-- Blizzard can fire multiple UNIT_AURA events inside the 0.1s bucket window;
-- we need to union their added/updated/removed IDs so no aura changes are lost.
local function merge_aura_info(dst, src)
    if not src then return dst end
    dst = dst or {}

    local function merge_id_list(key, list)
        if not list then return end
        dst[key] = dst[key] or {}
        dst[key.."_set"] = dst[key.."_set"] or {}
        for _, iid in ipairs(list) do
            if iid and not dst[key.."_set"][iid] then
                dst[key.."_set"][iid] = true
                dst[key][#dst[key] + 1] = iid
            end
        end
    end

    merge_id_list("removedAuraInstanceIDs", src.removedAuraInstanceIDs)
    merge_id_list("updatedAuraInstanceIDs", src.updatedAuraInstanceIDs)

    -- Modern payload: addedAuras = array of aura tables with auraInstanceID.
    if src.addedAuras then
        dst.addedAuras = dst.addedAuras or {}
        dst.addedAuras_set = dst.addedAuras_set or {}
        for _, aura in ipairs(src.addedAuras) do
            local iid = aura and aura.auraInstanceID
            if iid and not dst.addedAuras_set[iid] then
                dst.addedAuras_set[iid] = true
                dst.addedAuras[#dst.addedAuras + 1] = aura
            end
        end
    end

    -- Backward/alternate payload support.
    merge_id_list("addedAuraInstanceIDs", src.addedAuraInstanceIDs)

    if src.isFullUpdate then
        dst.isFullUpdate = true
    end

    return dst
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
    
    -- frame:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }})

    -- Updated Backdrop for smoother color filling
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", -- Use a flat white texture for clean coloring
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", 
        tile = true, tileSize = 16, edgeSize = 12, -- Reduced edgeSize slightly for a sleeker look
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })

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
        local params = frame.update_params
        if params then
            M.update_auras(frame, params.show_key, params.move_key, params.timer_key, params.bg_key, params.scale_key, params.spacing_key, params.filter)
        end
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
        
        -- Text Overlay Frame - created AFTER bar so it renders on top
        -- This is a separate frame layer that ensures text is always visible above the bar
        obj.text_overlay = CreateFrame("Frame", nil, obj)
        obj.text_overlay:SetFrameLevel(obj.bar:GetFrameLevel() + 1)
        
        -- Text - create as children of text_overlay so they render above the bar
        obj.name_text  = obj.text_overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall", 7)
        obj.time_text  = obj.text_overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall", 7)
        -- Stack count (shown bottom-right of icon in icon mode, or appended in bar mode)
        obj.count_text = obj.text_overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        obj.count_text:Hide()
        
        -- Tooltip
        obj:EnableMouse(true)
        obj:SetScript("OnEnter", function(s)
            if not s.aura_name then return end
            
            GameTooltip:SetOwner(s, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:ClearLines()
            
            local updated = false
            if s.aura_index then
                -- Modern API (12.0.5+): stable auraInstanceID lookup, no index fragility
                local ok, result = pcall(function()
                    return GameTooltip:SetUnitAuraByAuraInstanceID("player", s.aura_index)
                end)
                updated = ok and result
            end
            
            if not updated then
                GameTooltip:AddLine(s.aura_name, 1, 1, 1)
                if s.aura_duration and s.aura_duration > 0 then
                    local remaining_str = s.aura_remaining and string.format("%.1f", s.aura_remaining) or "?"
                    local duration_str = string.format("%.1f", s.aura_duration)
                    GameTooltip:AddLine(remaining_str .. "s / " .. duration_str .. "s", 0.7, 0.7, 1)
                else
                    GameTooltip:AddLine("(Permanent)", 0.7, 0.7, 1)
                end
            end
            
            GameTooltip:Show()
        end)
        obj:SetScript("OnLeave", function() 
            GameTooltip:Hide() 
        end)

        frame.icons[i] = obj
    end

    -- Map-based aura cache: auraInstanceID → entry table. Persists across events.
    frame._aura_map = {}

    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Combat start
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Combat end
    
    -- Store parameters on frame itself for robust access during callbacks
    frame.update_params = {
        show_key = show_key,
        move_key = move_key,
        timer_key = timer_key,
        bg_key = bg_key,
        scale_key = scale_key,
        spacing_key = spacing_key,
        category = category,
        filter = is_debuff and "HARMFUL" or "HELPFUL"
    }
    
    frame:SetScript("OnEvent", function(self, event, unit, info)
        local params = self.update_params
        if not params then return end

        local relevant = (event == "UNIT_AURA" and unit == "player")
            or event == "PLAYER_ENTERING_WORLD"
            or event == "PLAYER_REGEN_DISABLED"
            or event == "PLAYER_REGEN_ENABLED"

        if not relevant then return end

        -- KEY: do NOT scan inside the event handler.
        -- ElkBuffBars uses RegisterBucketEvent("UNIT_AURA", 0.1) for exactly this reason:
        -- C_UnitAuras calls made directly in OnEvent return "secret values" in combat
        -- because the execution context is still tainted by the event dispatch.
        -- Deferring via C_Timer.After(0) runs the scan in the next frame update cycle,
        -- after the tainted context exits — all fields return clean, readable values.
        --
        -- Merge UNIT_AURA payloads while waiting for the deferred scan.
        if event == "UNIT_AURA" then
            self._pending_aura_info = merge_aura_info(self._pending_aura_info, info)
        end

        -- Deduplication: if a scan is already queued for this frame, don't queue another.
        -- Multiple rapid UNIT_AURA events (common in combat) collapse to one scan.
        if not self._scan_pending then
            self._scan_pending = true
            local f = self
            -- 0.1s matches ElkBuffBars' RegisterBucketEvent("UNIT_AURA", 0.1) delay.
            -- This ensures the scan runs outside the event-dispatch taint window.
            C_Timer.After(0.1, function()
                f._scan_pending = false
                local event_info = f._pending_aura_info
                f._pending_aura_info = nil
                M.update_auras(f, params.show_key, params.move_key, params.timer_key,
                    params.bg_key, params.scale_key, params.spacing_key, params.filter, event_info)
            end)
        end
    end)
    
    M.frames[show_key] = frame
    return frame
end

-- INITIALIZATION ENGINE: Orchestrate startup of aura frames once addon data is loaded
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name == addon_name then
        -- Ensure the sub-table exists and link the module to the core database
        if not Ls_Tweeks_DB.aura_frames then Ls_Tweeks_DB.aura_frames = {} end
        M.db = Ls_Tweeks_DB.aura_frames 

        -- Populate missing settings using the defaults defined in af_defaults.lua
        if M.defaults then deep_copy(M.defaults, M.db) end
        
        -- Create the visual containers for each specific category
        M.create_aura_frame("show_static",  "move_static",  "timer_static", "bg_static",    "scale_static", "spacing_static",   "Static",   false)
        M.create_aura_frame("show_short",   "move_short",   "timer_short",  "bg_short",     "scale_short",  "spacing_short",    "Short",    false)
        M.create_aura_frame("show_long",    "move_long",    "timer_long",   "bg_long",      "scale_long",   "spacing_long",     "Long",     false)
        M.create_aura_frame("show_debuff",  "move_debuff",  "timer_debuff", "bg_debuff",    "scale_debuff", "spacing_debuff",   "Debuffs",  true)

        -- Single shared ticker for all frames at 0.1s (ElkBuffBars rate).
        -- One ticker iterating all frames is far cheaper than 4 separate tickers.
        local math_max_local = math.max
        C_Timer.NewTicker(0.1, function()
            local now = GetTime()
            for _, frame in pairs(M.frames) do
                if frame:IsVisible() then
                    local is_static_frame = (frame.category == "static")
                    for i = 1, #frame.icons do
                        local obj = frame.icons[i]
                        if obj:IsShown() and is_static_frame then
                            obj.time_text:SetText("")
                        elseif obj:IsShown() and obj.aura_index then
                            local remaining
                            local live_duration = C_UnitAuras.GetAuraDuration("player", obj.aura_index)
                            if live_duration then
                                remaining = live_duration:GetRemainingDuration()
                            elseif obj.aura_expiration and obj.aura_expiration > 0 then
                                remaining = math_max_local(0, obj.aura_expiration - now)
                            elseif obj.aura_scan_time and obj.aura_remaining then
                                remaining = math_max_local(0, obj.aura_remaining - (now - obj.aura_scan_time))
                            else
                                remaining = 0
                            end
                            if remaining and issecretvalue(remaining) then
                                local display_remaining = nil
                                local short_threshold = (M.db and M.db.short_threshold) or 60
                                if obj.aura_expiration and obj.aura_expiration > 0 then
                                    display_remaining = math_max_local(0, obj.aura_expiration - now)
                                elseif obj.aura_remaining and obj.aura_remaining > 0 then
                                    display_remaining = obj.aura_remaining
                                end

                                if display_remaining and display_remaining > 0 then
                                    if display_remaining > short_threshold then
                                        obj.time_text:SetText(M.format_time(display_remaining))
                                    else
                                        obj.time_text:SetFormattedText("%.1f", remaining)
                                    end
                                else
                                    obj.time_text:SetFormattedText("%.1f", remaining)
                                end
                                if obj.bar and obj.bar:IsShown() and obj.bar.SetTimerDuration and Enum and Enum.StatusBarTimerDirection and live_duration then
                                    obj.bar:SetTimerDuration(live_duration, nil, Enum.StatusBarTimerDirection.RemainingTime)
                                end
                            elseif remaining and remaining > 0 then
                                obj.time_text:SetText(M.format_time(remaining))
                                if obj.bar and obj.bar:IsShown() then
                                    if obj.bar.SetTimerDuration and Enum and Enum.StatusBarTimerDirection and live_duration then
                                        obj.bar:SetTimerDuration(live_duration, nil, Enum.StatusBarTimerDirection.RemainingTime)
                                    else
                                        obj.bar:SetValue(remaining)
                                    end
                                end
                            elseif remaining == 0 then
                                obj.time_text:SetText("")
                            else
                                -- Unknown/secret value: keep last shown timer text.
                            end
                        end
                    end
                end
            end
        end)

        -- Sync the Blizzard frame visibility based on user preferences
        M.toggle_blizz_buffs(M.db.disable_blizz_buffs)
        M.toggle_blizz_debuffs(M.db.disable_blizz_debuffs)

        -- Integrate the settings tab into the main addon configuration menu
        if addon.register_category and M.BuildSettings then
            addon.register_category("Buffs & Debuffs", function(parent) M.BuildSettings(parent) end)
        end

        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- RESET AND REFRESH: Restores UI states following a settings reset or global change
function M.on_reset_complete()
    M.toggle_blizz_buffs(M.db.disable_blizz_buffs)
    M.toggle_blizz_debuffs(M.db.disable_blizz_debuffs)
    
    -- Synchronize the state of any open GUI controls
    if M.controls then
        if M.controls["disable_blizz_buffs"] then M.controls["disable_blizz_buffs"]:SetChecked(M.db.disable_blizz_buffs) end
        if M.controls["disable_blizz_debuffs"] then M.controls["disable_blizz_debuffs"]:SetChecked(M.db.disable_blizz_debuffs) end
    end
end