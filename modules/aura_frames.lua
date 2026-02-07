local addon_name, addon = ...

local M = {}
addon.aura_frames = M

-- Default Configuration
local defaults = {
    disable_blizz_buffs = false,
    disable_blizz_debuffs = false,
    short_threshold = 60,
    
    show_static = false, move_static = false, timer_static = false, bg_static = true,
    show_short = false, move_short = false, timer_short = true, bg_short = true,
    show_long = false, move_long = false, timer_long = true, bg_long = true,
    show_debuff = false, move_debuff = false, timer_debuff = true, bg_debuff = true,
    
    positions = {} 
}

M.db = {}
M.frames = {}

---------------------------------------------------------
-- HELPERS: FORMATTING & BLIZZARD UI
---------------------------------------------------------
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

local function build_tab_content(panel, show_key, move_key, timer_key, bg_key, is_debuff)
    local filter = is_debuff and "HARMFUL" or "HELPFUL"
    
    local move_cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    move_cb:SetPoint("TOPLEFT", 16, -16)
    move_cb.Text:SetText("Move Mode")
    move_cb:SetChecked(M.db[move_key])
    move_cb:SetScript("OnClick", function(self)
        M.db[move_key] = self:GetChecked()
        M.update_auras(M.frames[show_key], show_key, move_key, timer_key, bg_key, filter)
    end)

    local enable_cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    enable_cb:SetPoint("TOPLEFT", move_cb, "BOTTOMLEFT", 0, -8)
    enable_cb.Text:SetText("Enable Frame")
    enable_cb:SetChecked(M.db[show_key])
    enable_cb:SetScript("OnClick", function(self)
        M.db[show_key] = self:GetChecked()
        M.update_auras(M.frames[show_key], show_key, move_key, timer_key, bg_key, filter)
    end)

    local timer_cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    timer_cb:SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", 0, -8)
    timer_cb.Text:SetText("Display Remaining Time")
    timer_cb:SetChecked(M.db[timer_key])
    timer_cb:SetScript("OnClick", function(self)
        M.db[timer_key] = self:GetChecked()
        M.update_auras(M.frames[show_key], show_key, move_key, timer_key, bg_key, filter)
    end)

    local bg_cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    bg_cb:SetPoint("TOPLEFT", timer_cb, "BOTTOMLEFT", 0, -8)
    bg_cb.Text:SetText("Show Background")
    bg_cb:SetChecked(M.db[bg_key])
    bg_cb:SetScript("OnClick", function(self)
        M.db[bg_key] = self:GetChecked()
        M.update_auras(M.frames[show_key], show_key, move_key, timer_key, bg_key, filter)
    end)
end

---------------------------------------------------------
-- UNIVERSAL UPDATE LOGIC
---------------------------------------------------------
function M.update_auras(self, show_key, move_key, timer_key, bg_key, filter)
    if not self or not self.icons then return end
    for _, icon in ipairs(self.icons) do 
        icon:Hide()
        if icon.ticker then icon.ticker:Cancel() end 
    end

    local display_index = 1
    local is_enabled = M.db[show_key]
    local is_moving = M.db[move_key]
    local is_timer_enabled = M.db[timer_key]
    local show_bg = M.db[bg_key]

    if is_enabled then
        local index = 1
        while true do
            local aura_data = C_UnitAuras.GetAuraDataByIndex("player", index, filter)
            if not aura_data then break end

            local belongs_here = false
            if filter == "HARMFUL" then
                belongs_here = true
            else
                local is_static = (aura_data.duration == 0)
                local is_short = (aura_data.duration > 0 and aura_data.duration <= M.db.short_threshold)
                local is_long = (aura_data.duration > M.db.short_threshold)
                belongs_here = (show_key == "show_static" and is_static) or (show_key == "show_short" and is_short) or (show_key == "show_long" and is_long)
            end

            if belongs_here then
                local icon_frame = self.icons[display_index]
                if not icon_frame then
                    icon_frame = CreateFrame("Frame", nil, self)
                    icon_frame:SetSize(32, 32)
                    icon_frame.texture = icon_frame:CreateTexture(nil, "ARTWORK")
                    icon_frame.texture:SetAllPoints()
                    icon_frame.time_text = icon_frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    icon_frame.time_text:SetPoint("TOP", icon_frame, "BOTTOM", 0, -2)
                    icon_frame:SetScript("OnEnter", function(f)
                        GameTooltip_SetDefaultAnchor(GameTooltip, f)
                        if filter == "HARMFUL" then GameTooltip:SetUnitDebuff("player", f.auraIndex) else GameTooltip:SetUnitBuff("player", f.auraIndex) end
                        GameTooltip:Show()
                    end)
                    icon_frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    self.icons[display_index] = icon_frame
                end
                icon_frame.auraIndex = index
                icon_frame.texture:SetTexture(aura_data.icon)
                icon_frame:SetPoint("TOPLEFT", self, "TOPLEFT", (display_index - 1) * 38 + 6, -6)                
                if is_timer_enabled and aura_data.expirationTime and aura_data.expirationTime > 0 then
                    icon_frame.time_text:Show()
                    local function update_text()
                        local remaining = aura_data.expirationTime - GetTime()
                        icon_frame.time_text:SetText(remaining > 0 and format_time(remaining) or "")
                    end
                    update_text()
                    icon_frame.ticker = C_Timer.NewTicker(0.1, update_text)
                else
                    icon_frame.time_text:Hide()
                end
                icon_frame:Show()
                display_index = display_index + 1
            end
            index = index + 1
        end
    end

    local should_show = is_moving or (is_enabled and display_index > 1)
    if should_show then
        self:Show()
        self:SetBackdropColor(0, 0, 0, (show_bg or is_moving) and 0.8 or 0)
        self:SetBackdropBorderColor(1, 1, 1, (show_bg or is_moving) and 1 or 0)
        if is_moving then self.title_bar:Show() else self.title_bar:Hide() end
    else
        self:Hide()
    end
end

---------------------------------------------------------
-- FRAME GENERATOR
---------------------------------------------------------
function M.create_aura_frame(show_key, move_key, timer_key, bg_key, display_name, is_debuff)
    local filter = is_debuff and "HARMFUL" or "HELPFUL"
    local frame = CreateFrame("Frame", "LsTweaksAuraFrame_"..show_key, UIParent, "BackdropTemplate")    
    frame:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }})
    frame:SetSize(220, 55)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- Load saved position
    local pos = M.db.positions[show_key]
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.rel_point, pos.x, pos.y)
    else
        local y_off = is_debuff and -100 or (show_key == "show_static" and 200 or show_key == "show_short" and 150 or 100)
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, y_off)
    end
    
    local tb = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    tb:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, -2)
    tb:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, -2)
    tb:SetHeight(20)
    tb:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 12, edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 }})
    tb:SetBackdropColor(0.2, 0.2, 0.2, 1)
    local text = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", tb, "CENTER", 0, 0)
    text:SetText(display_name)

    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() frame:StartMoving() end)
    tb:SetScript("OnDragStop", function() 
        frame:StopMovingOrSizing() 
        local point, _, rel_point, x, y = frame:GetPoint()
        M.db.positions[show_key] = { point = point, rel_point = rel_point, x = x, y = y }
    end)
    
    frame.title_bar, frame.icons = tb, {}
    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(self) M.update_auras(self, show_key, move_key, timer_key, bg_key, filter) end)
    
    M.frames[show_key] = frame
    return frame
end

---------------------------------------------------------
-- SETTINGS PANEL BUILDER
---------------------------------------------------------
function M.build_settings(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetText("Buffs & Debuffs Configuration")

    local tabs, panels = {}, {}
    local tab_data = {
        { name = "General", is_general = true },
        { name = "Static", show_key = "show_static", move_key = "move_static", timer_key = "timer_static", bg_key = "bg_static" },
        { name = "Short", show_key = "show_short", move_key = "move_short", timer_key = "timer_short", bg_key = "bg_short" },
        { name = "Long", show_key = "show_long", move_key = "move_long", timer_key = "timer_long", bg_key = "bg_long" },
        { name = "Debuffs", show_key = "show_debuff", move_key = "move_debuff", timer_key = "timer_debuff", bg_key = "bg_debuff", is_debuff = true }
    }

    local function show_tab(id)
        for i, panel in ipairs(panels) do
            panel:SetShown(i == id)
            if i == id then PanelTemplates_SelectTab(tabs[i]) else PanelTemplates_DeselectTab(tabs[i]) end
        end
    end

    for i, data in ipairs(tab_data) do
        local tab = CreateFrame("Button", addon_name.."Tab"..i, parent, "PanelTabButtonTemplate")
        tab:SetText(data.name)
        tab:SetID(i)
        tab:SetScript("OnClick", function(self) show_tab(self:GetID()) end)
        tab:SetPoint(i == 1 and "TOPLEFT" or "LEFT", i == 1 and title or tabs[i-1], i == 1 and "BOTTOMLEFT" or "RIGHT", i == 1 and 0 or 5, i == 1 and -15 or 0)
        PanelTemplates_TabResize(tab, 0)

        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -80)
        p:SetSize(parent:GetWidth() - 20, 300)
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

            local slider = CreateFrame("Slider", addon_name.."ThresholdSlider", p, "OptionsSliderTemplate")
            slider:SetPoint("TOPLEFT", b_debuff, "BOTTOMLEFT", 10, -30)
            slider:SetMinMaxValues(10, 300)
            slider:SetValueStep(10)
            slider:SetObeyStepOnDrag(true)
            slider:SetValue(M.db.short_threshold)
            _G[slider:GetName() .. 'Low']:SetText('10s')
            _G[slider:GetName() .. 'High']:SetText('300s')
            _G[slider:GetName() .. 'Text']:SetText("Short Buff Threshold: " .. M.db.short_threshold .. "s")
            slider:SetScript("OnValueChanged", function(self, value)
                M.db.short_threshold = value
                _G[self:GetName() .. 'Text']:SetText("Short Buff Threshold: " .. value .. "s")
                for k, v in pairs(M.frames) do 
                    local f_key = k == "show_debuff" and "HARMFUL" or "HELPFUL"
                    M.update_auras(v, k, "move_"..k:sub(6), "timer_"..k:sub(6), "bg_"..k:sub(6), f_key) 
                end
            end)
        else
            build_tab_content(p, data.show_key, data.move_key, data.timer_key, data.bg_key, data.is_debuff)
        end
        tabs[i], panels[i] = tab, p
    end
    PanelTemplates_SetNumTabs(parent, #tab_data)
    show_tab(1)
end

---------------------------------------------------------
-- DATA LOADING & INITIALIZATION
---------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name == addon_name then
        -- INTENTIONAL SPELLING: Ls_Tweeks_DB
        if not Ls_Tweeks_DB then Ls_Tweeks_DB = {} end
        for k, v in pairs(defaults) do
            if Ls_Tweeks_DB[k] == nil then Ls_Tweeks_DB[k] = v end
        end
        M.db = Ls_Tweeks_DB

        M.create_aura_frame("show_static", "move_static", "timer_static", "bg_static", "Static", false)
        M.create_aura_frame("show_short", "move_short", "timer_short", "bg_short", "Short", false)
        M.create_aura_frame("show_long", "move_long", "timer_long", "bg_long", "Long", false)
        M.create_aura_frame("show_debuff", "move_debuff", "timer_debuff", "bg_debuff", "Debuffs", true)

        toggle_blizz_buffs(M.db.disable_blizz_buffs)
        toggle_blizz_debuffs(M.db.disable_blizz_debuffs)
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

addon.register_category("Buffs & Debuffs", function(parent) M.build_settings(parent) end)