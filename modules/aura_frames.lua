local addon_name, addon = ...

-- CACHED GLOBALS & CONSTANTS
local floor, math_max, math_ceil = floor, math.max, math.ceil
local GetAuraData = C_UnitAuras.GetAuraDataByIndex
local GetTime = GetTime

local M = {}
addon.aura_frames = M

-- DEFAULT SETTINGS
local defaults = {
    -- Global Toggles
    disable_blizz_buffs = false,
    disable_blizz_debuffs = false,
    short_threshold = 60,
    
    -- STATIC
    show_static     = false,
    move_static     = true,
    timer_static    = false,
    bg_static       = false,
    scale_static    = 1.0,
    spacing_static  = 2.00,
    width_static    = 200,
    use_bars_static = false,
    color_static    = { r = 0, g = 0.5, b = 1 },

    -- SHORT
    show_short      = false,
    move_short      = true,
    timer_short     = true,
    bg_short        = false,
    scale_short     = 1.0,
    spacing_short   = 2.00,
    width_short     = 200,
    use_bars_short  = true,
    color_short     = { r = 0, g = 0.5, b = 1 },

    -- LONG
    show_long       = false,
    move_long       = true,
    timer_long      = true,
    bg_long         = false,
    scale_long      = 1.0,
    spacing_long    = 2.00,
    width_long      = 200,
    use_bars_long   = false,
    color_long      = { r = 0, g = 0.5, b = 1 },

    -- DEBUFFS
    show_debuff     = false,
    move_debuff     = true,
    timer_debuff    = true,
    bg_debuff       = false,
    scale_debuff    = 1.0,
    spacing_debuff  = 2.00,
    width_debuff    = 200,
    use_bars_debuff = true,
    color_debuff    = { r = 1, g = 0.2, b = 0.2 },
    
    -- POSITIONS (Consolidated Table)
    positions = {
        static = { point = "CENTER", x = 0, y = 150 },
        short  = { point = "CENTER", x = 0, y = 100 },
        long   = { point = "CENTER", x = 0, y = 50 },
        debuff = { point = "CENTER", x = 0, y = -50 },
    }
}

M.db = {}
M.frames = {}

-- UTILITY FUNCTIONS
local function format_time(s)
    if s >= 3600 then return format("%dh", floor(s/3600)) end
    if s >= 60 then return format("%dm", floor(s/60)) end
    if s >= 5 then return format("%ds", floor(s)) end
    return format("%.1fs", s)
end

local function toggle_blizz_buffs(hide)
    if hide then BuffFrame:Hide() BuffFrame:UnregisterAllEvents() else BuffFrame:Show() BuffFrame:RegisterEvent("UNIT_AURA") end
end

local function toggle_blizz_debuffs(hide)
    if hide then DebuffFrame:Hide() DebuffFrame:UnregisterAllEvents() else DebuffFrame:Show() DebuffFrame:RegisterEvent("UNIT_AURA") end
end

-- GUI COMPONENT BUILDERS
local function CreateSliderWithBox(name, parent, labelText, minV, maxV, step, db_key, callback)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(M.db[db_key] or minV)
    _G[name..'Low']:SetText(minV)
    _G[name..'High']:SetText(maxV)
    _G[name..'Text']:SetText(labelText)
    local eb = CreateFrame("EditBox", nil, slider, "InputBoxTemplate")
    eb:SetSize(45, 20)
    eb:SetPoint("LEFT", slider, "RIGHT", 15, 0)
    eb:SetAutoFocus(false)
    eb:SetText(format(step < 1 and "%.2f" or "%.1f", M.db[db_key] or minV))
    slider:SetScript("OnValueChanged", function(self, value)
        M.db[db_key] = value
        eb:SetText(format(step < 1 and "%.2f" or "%.1f", value))
        callback()
    end)
    eb:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then val = math.max(minV, math.min(maxV, val)) slider:SetValue(val) end
        self:ClearFocus()
    end)
    return slider
end

-- ============================================================================
-- MAIN CORE LOGIC (Aura Scanning & Rendering)
-- ============================================================================
function M.update_auras(self, show_key, move_key, timer_key, bg_key, scale_key, spacing_key, filter)
    if not self or not self.icons then return end
    
    local db = M.db
    local category = show_key:sub(6)
    local use_bars = db["use_bars_"..category]
    local frame_width = db["width_"..category] or 200
    local spacing = db[spacing_key] or 6
    local color = db["color_"..category] or {r=1, g=1, b=1}
    local short_threshold = db.short_threshold
    
    self:SetScale(db[scale_key] or 1.0)
    self:SetWidth(frame_width)

    for i = 1, #self.icons do
        local obj = self.icons[i]
        obj:Hide()
        if obj.ticker then obj.ticker:Cancel() end 
    end

    local is_moving = db[move_key]
    if not db[show_key] then 
        if is_moving then 
            self:Show()
            -- Set up move mode styling: always show background in move mode for visibility
            self:SetBackdropColor(0, 0, 0, 0.8)
            self:SetBackdropBorderColor(1, 1, 1, 1)
            self:SetHeight(44)
            self.title_bar:Show()
            self.bottom_title_bar:Show()
            self.resizer:Show()
        else 
            self:Hide() 
        end
        return 
    end

    local icon_footprint = 32 + spacing
    local icons_per_row = math_max(1, floor((frame_width - 12 + spacing) / icon_footprint))
    local display_index = 1
    local index = 1
    
    while true do
        local aura_data = GetAuraData("player", index, filter)
        if not aura_data then break end

        -- Calculate duration safely from expirationTime to avoid taint issues
        -- expirationTime is tainted during combat, so wrap comparison in pcall
        local expirationTime = aura_data.expirationTime
        local duration = 0
        if expirationTime then
            local ok, result = pcall(function() 
                if expirationTime > 0 then
                    return expirationTime - GetTime()
                else
                    return 0
                end
            end)
            if ok and result > 0 then
                duration = result
            end
        end
        local belongs_here = false
        
        if filter == "HARMFUL" then 
            belongs_here = true 
        else
            if show_key == "show_static" then 
                belongs_here = (duration == 0)
            elseif show_key == "show_short" then 
                -- Safe comparison using calculated duration
                belongs_here = (duration > 0 and duration <= short_threshold)
            elseif show_key == "show_long" then 
                -- Safe comparison using calculated duration
                belongs_here = (duration > short_threshold)
            end
        end

        if belongs_here then
            local obj = self.icons[display_index]
            if not obj then
                obj = CreateFrame("Frame", nil, self)
                obj.texture = obj:CreateTexture(nil, "ARTWORK")
                obj.time_text = obj:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                obj.bar = CreateFrame("StatusBar", nil, obj)
                obj.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                obj.bar_bg = obj.bar:CreateTexture(nil, "BACKGROUND")
                obj.bar_bg:SetAllPoints()
                obj.bar_bg:SetColorTexture(0, 0, 0, 0.5)
                obj.name_text = obj:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                obj.name_text:SetShadowOffset(1, -1)
                obj.name_text:SetShadowColor(0, 0, 0, 1)
                obj.time_text:SetShadowOffset(1, -1)
                obj.time_text:SetShadowColor(0, 0, 0, 1)

                obj:EnableMouse(true)
                obj:SetScript("OnEnter", function(s)
                    if s.aura_index then
                        GameTooltip_SetDefaultAnchor(GameTooltip, s)
                        GameTooltip:SetUnitAura("player", s.aura_index, filter)
                        GameTooltip:Show()
                    end
                end)
                obj:SetScript("OnLeave", function() GameTooltip:Hide() end)
                self.icons[display_index] = obj
            end

            obj.aura_index = index 
            obj:ClearAllPoints()
            obj.texture:ClearAllPoints()
            
            if use_bars then
                obj:SetSize(frame_width - 12, 20)
                obj:SetPoint("TOPLEFT", self, "TOPLEFT", 6, -((display_index - 1) * (20 + spacing) + 6))
                obj.texture:SetSize(18, 18)
                obj.texture:SetPoint("LEFT", obj, "LEFT", 0, 0)
                obj.bar:Show()
                obj.bar:SetStatusBarColor(color.r, color.g, color.b)
                obj.bar:SetPoint("LEFT", obj.texture, "RIGHT", 5, 0)
                obj.bar:SetPoint("RIGHT", obj, "RIGHT", 0, 0)
                obj.bar:SetHeight(18)
                obj.name_text:SetParent(obj.bar)
                obj.name_text:SetPoint("LEFT", obj.bar, "LEFT", 4, 0)
                obj.name_text:SetText(aura_data.name or "Unknown")
                obj.name_text:Show()
                obj.time_text:SetParent(obj.bar)
                obj.time_text:SetPoint("RIGHT", obj.bar, "RIGHT", -4, 0)
            else
                obj:SetSize(32, 32)
                obj.bar:Hide()
                obj.name_text:Hide()
                obj.texture:SetAllPoints(obj)
                local col = (display_index - 1) % icons_per_row
                local row = floor((display_index - 1) / icons_per_row)
                obj:SetPoint("TOPLEFT", self, "TOPLEFT", col * icon_footprint + 6, -(row * (32 + spacing + 12) + 6))
                obj.time_text:SetParent(obj)
                obj.time_text:SetPoint("TOP", obj, "BOTTOM", 0, -2)
            end

            obj.texture:SetTexture(aura_data.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            obj.time_text:Show()

            if duration > 0 then
                local storedExpiration = aura_data.expirationTime  -- Store value once
                local function update()
                    local remain = 0
                    if storedExpiration then
                        local ok, result = pcall(function() return storedExpiration - GetTime() end)
                        if ok and result > 0 then
                            remain = result
                        end
                    end
                    obj.time_text:SetText(format_time(remain))
                    if use_bars then obj.bar:SetMinMaxValues(0, duration) obj.bar:SetValue(remain) end
                end
                update()
                obj.ticker = C_Timer.NewTicker(0.1, update)
            else
                obj.time_text:SetText("") 
                if use_bars then obj.bar:SetMinMaxValues(0, 1) obj.bar:SetValue(1) end
            end

            obj:Show()
            display_index = display_index + 1
        end
        index = index + 1
    end

    local active_count = display_index - 1
    local should_show = active_count > 0 or is_moving or db[show_key]
    if should_show then
        self:Show()
        local height
        if active_count > 0 then
            height = use_bars and (active_count * (20 + spacing) + 12) or (math_ceil(active_count / icons_per_row) * (32 + spacing + 12) + 12)
        else
            -- Minimal visible height when the frame is enabled but has no auras
            height = 44
        end
        self:SetHeight(math_max(height, is_moving and 44 or 0))

        local bg_alpha = (db[bg_key] or is_moving) and 0.8 or 0
        self:SetBackdropColor(0, 0, 0, bg_alpha)
        self:SetBackdropBorderColor(1, 1, 1, bg_alpha > 0 and 1 or 0)
        self.title_bar:SetShown(is_moving)
        self.bottom_title_bar:SetShown(is_moving)
        self.resizer:SetShown(is_moving)
    else
        self:Hide()
    end
end

-- ============================================================================
-- AURA CONTAINER GENERATOR (Backdrop, Move Handles, Events)
-- ============================================================================
function M.create_aura_frame(show_key, move_key, timer_key, bg_key, scale_key, spacing_key, display_name, is_debuff)
    local category = show_key:sub(6) -- e.g. "static", "short"
    local frame = CreateFrame("Frame", "LsTweaksAuraFrame_"..show_key, UIParent, "BackdropTemplate")    
    frame:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }})
    frame:SetMovable(true) frame:SetResizable(true) frame:SetClampedToScreen(true)

    -- LOAD POSITION FROM CONSOLIDATED DB
    local pos = M.db.positions and M.db.positions[category]
    if pos then
        local point = pos.point or "CENTER"
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, point, pos.x or 0, pos.y or 0)
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
        tb:EnableMouse(true) tb:RegisterForDrag("LeftButton")
        tb:SetScript("OnDragStart", function() parent:StartMoving() end)
        tb:SetScript("OnDragStop", function() 
            parent:StopMovingOrSizing() 
            local p, _, _, x, y = parent:GetPoint() 
            -- Save back to consolidated table
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
    frame.resizer:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() M.db["width_"..category] = frame:GetWidth() M.update_auras(frame, show_key, move_key, timer_key, bg_key, scale_key, spacing_key, is_debuff and "HARMFUL" or "HELPFUL") end)

    frame.icons = {}
    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(self) M.update_auras(self, show_key, move_key, timer_key, bg_key, scale_key, spacing_key, is_debuff and "HARMFUL" or "HELPFUL") end)
    M.frames[show_key] = frame
    return frame
end

-- ============================================================================
-- SETTINGS PANEL INTERFACE
-- ============================================================================
function M.build_settings(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetText("Buffs & Debuffs Configuration")

    local tabs, panels = {}, {}
    local tab_data = {
        { name = "General", is_general = true },
        { name = "Static", show_key = "show_static", move_key = "move_static", timer_key = "timer_static", bg_key = "bg_static", scale_key = "scale_static", spacing_key = "spacing_static" },
        { name = "Short", show_key = "show_short", move_key = "move_short", timer_key = "timer_short", bg_key = "bg_short", scale_key = "scale_short", spacing_key = "spacing_short" },
        { name = "Long", show_key = "show_long", move_key = "move_long", timer_key = "timer_long", bg_key = "bg_long", scale_key = "scale_long", spacing_key = "spacing_long" },
        { name = "Debuffs", show_key = "show_debuff", move_key = "move_debuff", timer_key = "timer_debuff", bg_key = "bg_debuff", scale_key = "scale_debuff", spacing_key = "spacing_debuff", is_debuff = true }
    }

    for i, data in ipairs(tab_data) do
        local tab = CreateFrame("Button", addon_name.."Tab"..i, parent, "PanelTabButtonTemplate")
        tab:SetText(data.name)
        tab:SetID(i)
        tab:SetScript("OnClick", function(self) for j, p in ipairs(panels) do p:SetShown(j == self:GetID()) if j == self:GetID() then PanelTemplates_SelectTab(tabs[j]) else PanelTemplates_DeselectTab(tabs[j]) end end end)
        tab:SetPoint(i == 1 and "TOPLEFT" or "LEFT", i == 1 and title or tabs[i-1], i == 1 and "BOTTOMLEFT" or "RIGHT", i == 1 and 0 or 5, i == 1 and -15 or 0)
        PanelTemplates_TabResize(tab, 0)

        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -80)
        p:SetSize(parent:GetWidth() - 20, 400)
        p:Hide()

        if data.is_general then
            local b_buff = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            b_buff:SetPoint("TOPLEFT", 16, -16)
            b_buff.Text:SetText("Disable Blizzard Buff Frame")
            b_buff:SetChecked(M.db.disable_blizz_buffs)
            b_buff:SetScript("OnClick", function(self) M.db.disable_blizz_buffs = self:GetChecked() toggle_blizz_buffs(M.db.disable_blizz_buffs) end)

            local b_debuff = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            b_debuff:SetPoint("TOPLEFT", b_buff, "BOTTOMLEFT", 0, -8)
            b_debuff.Text:SetText("Disable Blizzard Debuff Frame")
            b_debuff:SetChecked(M.db.disable_blizz_debuffs)
            b_debuff:SetScript("OnClick", function(self) M.db.disable_blizz_debuffs = self:GetChecked() toggle_blizz_debuffs(M.db.disable_blizz_debuffs) end)

            if not M.controls then M.controls = {} end
            M.controls["disable_blizz_buffs"] = b_buff
            M.controls["disable_blizz_debuffs"] = b_debuff

            -- Ensure Blizzard frames are toggled after a global reset
            M.on_reset_complete = function()
                toggle_blizz_buffs(M.db.disable_blizz_buffs)
                toggle_blizz_debuffs(M.db.disable_blizz_debuffs)
            end

            CreateSliderWithBox(addon_name.."Tslider", p, "Short Buff Threshold (s)", 10, 300, 10, "short_threshold", function() 
                for k,v in pairs(M.frames) do M.update_auras(v, k, "move_"..k:sub(6), "timer_"..k:sub(6), "bg_"..k:sub(6), "scale_"..k:sub(6), "spacing_"..k:sub(6), k=="show_debuff" and "HARMFUL" or "HELPFUL") end
            end):SetPoint("TOPLEFT", b_debuff, "BOTTOMLEFT", 20, -40)

            addon.CreateGlobalReset(p, b_debuff, M.db, defaults)
        else
            local cat = data.show_key:sub(6)
            local filter = data.is_debuff and "HARMFUL" or "HELPFUL"
            local function update() M.update_auras(M.frames[data.show_key], data.show_key, data.move_key, data.timer_key, data.bg_key, data.scale_key, data.spacing_key, filter) end
            
            local move_cb = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            move_cb:SetPoint("TOPLEFT", 16, -16)
            move_cb.Text:SetText("Move Mode")
            move_cb:SetChecked(M.db[data.move_key])
            move_cb:SetScript("OnClick", function(self) M.db[data.move_key] = self:GetChecked() update() end)
            if not M.controls then M.controls = {} end
            M.controls[data.move_key] = move_cb

            local bars_cb = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            bars_cb:SetPoint("LEFT", move_cb, "RIGHT", 140, 0)
            bars_cb.Text:SetText("Display as Bars")
            bars_cb:SetChecked(M.db["use_bars_"..cat])
            bars_cb:SetScript("OnClick", function(self) M.db["use_bars_"..cat] = self:GetChecked() update() end)
            M.controls["use_bars_"..cat] = bars_cb

            local enable_cb = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            enable_cb:SetPoint("TOPLEFT", move_cb, "BOTTOMLEFT", 0, -4)
            enable_cb.Text:SetText("Enable Frame")
            enable_cb:SetChecked(M.db[data.show_key])
            enable_cb:SetScript("OnClick", function(self) M.db[data.show_key] = self:GetChecked() update() end)
            M.controls[data.show_key] = enable_cb

            local bg_cb = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            bg_cb:SetPoint("LEFT", enable_cb, "RIGHT", 140, 0)
            bg_cb.Text:SetText("Show Background")
            bg_cb:SetChecked(M.db[data.bg_key])
            bg_cb:SetScript("OnClick", function(self) M.db[data.bg_key] = self:GetChecked() update() end)
            M.controls[data.bg_key] = bg_cb

            local color_btn = CreateFrame("Button", nil, p, "BackdropTemplate")
            color_btn:SetSize(22, 22)
            color_btn:SetPoint("LEFT", bg_cb, "RIGHT", 140, 0)
            color_btn:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameColorSwatch", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8})
            local c = M.db["color_"..cat]
            color_btn:SetBackdropColor(c.r, c.g, c.b)
            color_btn:SetScript("OnClick", function()
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = c.r, g = c.g, b = c.b,
                    swatchFunc = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        M.db["color_"..cat] = {r=r, g=g, b=b}
                        color_btn:SetBackdropColor(r, g, b)
                        update()
                    end
                })
            end)
            local c_text = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            c_text:SetPoint("LEFT", color_btn, "RIGHT", 5, 0)
            c_text:SetText("Bar Color")

            local color_reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
            color_reset:SetSize(80, 20)
            color_reset:SetPoint("TOPLEFT", color_btn, "BOTTOMLEFT", 0, -5)
            color_reset:SetText("Reset Color")
            color_reset:SetScript("OnClick", function()
                local dc = defaults["color_"..cat]
                M.db["color_"..cat] = {r = dc.r, g = dc.g, b = dc.b}
                color_btn:SetBackdropColor(dc.r, dc.g, dc.b)
                update()
            end)

            CreateSliderWithBox(addon_name..cat.."Scale", p, "Scale", 0.5, 2.5, 0.01, data.scale_key, update):SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", 20, -35)
            CreateSliderWithBox(addon_name..cat.."Spacing", p, "Spacing", 0, 40, 0.1, data.spacing_key, update):SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", 20, -85)

            -- LOCAL RESET
            local reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
            reset:SetSize(120, 22)
            reset:SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", -10, -140)
            reset:SetText("Reset Position")
            reset:SetScript("OnClick", function()
                -- Reference the factory default position and move state
                local dPos = defaults.positions[cat]
                local dMove = defaults[data.move_key]
                
                -- Sync the active database values with the defaults
                M.db.positions[cat].point = dPos.point
                M.db.positions[cat].x = dPos.x
                M.db.positions[cat].y = dPos.y
                M.db[data.move_key] = dMove
                
                -- Update the UI checkbox to match the new move state
                move_cb:SetChecked(dMove)
                
                -- Update the frame position and visuals in real-time
                local f = M.frames[data.show_key]
                if f then
                    f:ClearAllPoints()
                    f:SetPoint(dPos.point, UIParent, dPos.point, dPos.x, dPos.y)
                    
                    -- Refresh the aura frame to reflect the default settings
                    M.update_auras(f, data.show_key, data.move_key, data.timer_key, data.bg_key, data.scale_key, data.spacing_key, filter)
                    
                    print("|cff00ff00LsTweaks:|r Reset " .. cat .. " to factory defaults.")
                end
            end)

        end

        tabs[i], panels[i] = tab, p
    end

    PanelTemplates_SetNumTabs(parent, #tab_data)
    for i = 1, #tab_data do
        if i == 1 then panels[i]:Show() PanelTemplates_SelectTab(tabs[i])
        else panels[i]:Hide() PanelTemplates_DeselectTab(tabs[i]) end
    end
    PanelTemplates_UpdateTabs(parent)
end

-- INITIALIZATION & ADDON LOADING
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name == addon_name then
        -- Initialize the global database if it does not exist
        if not Ls_Tweeks_DB then Ls_Tweeks_DB = {} end
        
        -- Apply factory defaults to any missing entries
        -- This uses a deep-copy approach for nested tables
        for k, v in pairs(defaults) do 
            if Ls_Tweeks_DB[k] == nil then 
                if type(v) == "table" then
                    Ls_Tweeks_DB[k] = {}
                    for subK, subV in pairs(v) do
                        if type(subV) == "table" then
                            Ls_Tweeks_DB[k][subK] = {}
                            for innerK, innerV in pairs(subV) do
                                Ls_Tweeks_DB[k][subK][innerK] = innerV
                            end
                        else
                            Ls_Tweeks_DB[k][subK] = subV
                        end
                    end
                else
                    Ls_Tweeks_DB[k] = v 
                end
            end 
        end
        
        -- Reference the local database to the global saved variable
        M.db = Ls_Tweeks_DB
        
        -- Construct the main aura containers
        -- Each call sets up the frame, anchors, and event scripts
        M.create_aura_frame("show_static",  "move_static",  "timer_static", "bg_static",    "scale_static", "spacing_static",   "Static",   false)
        M.create_aura_frame("show_short",   "move_short",   "timer_short",  "bg_short",     "scale_short",  "spacing_short",    "Short",    false)
        M.create_aura_frame("show_long",    "move_long",    "timer_long",   "bg_long",      "scale_long",   "spacing_long",     "Long",     false)
        M.create_aura_frame("show_debuff",  "move_debuff",  "timer_debuff", "bg_debuff",    "scale_debuff", "spacing_debuff",   "Debuffs",  true)
        
        -- Sync the Blizzard frame visibility with the saved settings
        toggle_blizz_buffs(M.db.disable_blizz_buffs)
        toggle_blizz_debuffs(M.db.disable_blizz_debuffs)
    end
end)

-- Connect to the main addon settings panel
addon.register_category("Buffs & Debuffs", function(parent) M.build_settings(parent) end)