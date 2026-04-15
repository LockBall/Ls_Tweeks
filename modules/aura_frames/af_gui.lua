local addon_name, addon = ...

-- Ensure the unified module table is used
addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

-- GUI COMPONENT BUILDERS

-- slider & editbox
-- Uses MinimalSliderTemplate (available 10.0+) and creates labels as explicit children
-- instead of relying on the deprecated _G[name..'Low/High/Text'] global pattern.
function M.CreateSliderWithBox(name, parent, labelText, minV, maxV, step, db_key, callback)
    local slider = CreateFrame("Slider", name, parent, "MinimalSliderTemplate")
    slider:SetSize(155, 16)
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(M.db[db_key] or minV)

    local title = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("BOTTOM", slider, "TOP", 0, 4)
    title:SetText(labelText)

    local low_lbl = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    low_lbl:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
    low_lbl:SetText(minV)

    local high_lbl = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    high_lbl:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
    high_lbl:SetText(maxV)

    local eb = CreateFrame("EditBox", nil, slider, "InputBoxTemplate")
    eb:SetSize(45, 20)
    eb:SetPoint("LEFT", slider, "RIGHT", 30, 0)
    eb:SetAutoFocus(false)
    eb:SetText(format(step < 1 and "%.2f" or "%.1f", M.db[db_key] or minV))

    slider:SetScript("OnValueChanged", function(self, value)
        M.db[db_key] = value
        eb:SetText(format(step < 1 and "%.2f" or "%.1f", value))
        callback()
    end)

    eb:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            val = math.max(minV, math.min(maxV, val))
            slider:SetValue(val)
        end
        self:ClearFocus()
    end)
    return slider
end

-- Shared click-blocker: sits behind all dropdown popups and dismisses the open one
-- when the user clicks anywhere outside it. One instance, reused by all dropdowns.
local _dropdown_blocker = CreateFrame("Frame", "LsTweeksDropdownBlocker", UIParent)
_dropdown_blocker:SetAllPoints(UIParent)
_dropdown_blocker:SetFrameStrata("FULLSCREEN")
_dropdown_blocker:SetFrameLevel(98)
_dropdown_blocker:EnableMouse(true)
_dropdown_blocker:Hide()
_dropdown_blocker._active = nil
_dropdown_blocker:SetScript("OnMouseDown", function(self)
    if self._active then self._active:Hide() end
    self._active = nil
    self:Hide()
end)

local function _show_dropdown(popup, btn)
    if _dropdown_blocker._active and _dropdown_blocker._active ~= popup then
        _dropdown_blocker._active:Hide()
    end
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    popup:Show()
    _dropdown_blocker._active = popup
    _dropdown_blocker:Show()
end

local function _hide_dropdown(popup)
    popup:Hide()
    if _dropdown_blocker._active == popup then
        _dropdown_blocker._active = nil
        _dropdown_blocker:Hide()
    end
end

-- growth direction dropdown
-- Replaces the deprecated UIDropDownMenu API with a custom popup list.
function M.CreateDirectionDropdown(name, parent, labelText, db_key, callback)
    local options = { "RIGHT", "LEFT", "DOWN", "UP" }
    local current = M.db[db_key] or "DOWN"

    -- Anchor container (caller calls :SetPoint on this)
    local container = CreateFrame("Frame", name, parent)
    container:SetSize(106, 22)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", container, "TOP", 0, 2)
    label:SetText(labelText)

    -- Main toggle button
    local btn = CreateFrame("Button", name.."Btn", container, "UIPanelButtonTemplate")
    btn:SetAllPoints(container)
    btn:SetText(current)

    -- Popup list
    local row_h = 22
    local popup = CreateFrame("Frame", name.."Popup", UIParent, "BackdropTemplate")
    popup:SetSize(106, #options * row_h + 4)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(100)
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.08, 0.96)
    popup:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    popup:Hide()

    for i, dir in ipairs(options) do
        local row = CreateFrame("Button", nil, popup)
        row:SetSize(102, row_h)
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", 2, -(2 + (i - 1) * row_h))

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.12)

        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", row, "LEFT", 8, 0)
        txt:SetText(dir)

        row:SetScript("OnClick", function()
            M.db[db_key] = dir
            btn:SetText(dir)
            _hide_dropdown(popup)
            callback()
        end)
    end

    btn:SetScript("OnClick", function()
        if popup:IsShown() then
            _hide_dropdown(popup)
        else
            _show_dropdown(popup, btn)
        end
    end)

    return container
end

-- tabs settings controls
function M.BuildSettings(parent)
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
        tab:SetScript("OnClick", function(self) 
            for j, p in ipairs(panels) do 
                p:SetShown(j == self:GetID()) 
                if j == self:GetID() then 
                    PanelTemplates_SelectTab(tabs[j]) 
                else 
                    PanelTemplates_DeselectTab(tabs[j]) 
                end 
            end 
        end)
        tab:SetPoint(i == 1 and "TOPLEFT" or "LEFT", i == 1 and title or tabs[i-1], i == 1 and "BOTTOMLEFT" or "RIGHT", i == 1 and 0 or 5, i == 1 and -15 or 0)
        PanelTemplates_TabResize(tab, 0)

        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -80)
        p:SetSize(parent:GetWidth() - 20, 400)
        p:Hide()

        if data.is_general then

            -- LAYOUT CONFIG
            local x_left = 16
            local y = -16        
            local row = 38       
            local slider_row = 60

            -- ROW: Blizzard Buff Toggle
            local blizz_buff_container, blizz_buff, _ = addon.CreateCheckbox(
                p,
                "Disable Blizzard Buff Frame",
                M.db.disable_blizz_buffs,
                function(is_checked)
                    M.db.disable_blizz_buffs = is_checked
                    M.toggle_blizz_buffs(M.db.disable_blizz_buffs)
                end
            )
            blizz_buff_container:SetPoint("TOPLEFT", p, "TOPLEFT", x_left, y)
            M.controls["disable_blizz_buffs"] = blizz_buff

            y = y - row -- next row

            -- Blizzard Debuff Toggle
            local blizz_debuff_container, blizz_debuff, _ = addon.CreateCheckbox(
                p,
                "Disable Blizzard Debuff Frame",
                M.db.disable_blizz_debuffs,
                function(is_checked)
                    M.db.disable_blizz_debuffs = is_checked
                    M.toggle_blizz_debuffs(M.db.disable_blizz_debuffs)
                end
            )
            blizz_debuff_container:SetPoint("TOPLEFT", p, "TOPLEFT", x_left, y)
            M.controls["disable_blizz_debuffs"] = blizz_debuff

            y = y - slider_row -- next row

            -- Threshold Slider
            local threshold = M.CreateSliderWithBox(addon_name.."Tslider", p, "Short Buff Threshold (s)", 10, 300, 10, "short_threshold", function()
                for k, v in pairs(M.frames) do 
                    -- Corrected to sub(6) to handle keys like show_static, show_short, etc.
                    local cat = k:sub(6) 
                    M.update_auras(v, k, "move_"..cat, "timer_"..cat, "bg_"..cat, "scale_"..cat, "spacing_"..cat, k == "show_debuff" and "HARMFUL" or "HELPFUL") 
                end
            end)
            threshold:SetPoint("TOPLEFT", p, "TOPLEFT", x_left + 20, y)

            y = y - 50 -- Space below the slider

            -- Global Reset Button
            addon.CreateGlobalReset(p, threshold, M.db, M.defaults)
            if p.globalReset then
                p.globalReset:ClearAllPoints()
                p.globalReset:SetPoint("TOP", p, "TOP", 0, y)
            end

        else -- not in general

            local cat = data.show_key:sub(6)
            local filter = data.is_debuff and "HARMFUL" or "HELPFUL"
            local function update() -- only runs once when user opens options
                M.update_auras(M.frames[data.show_key], data.show_key, data.move_key, data.timer_key, data.bg_key, data.scale_key, data.spacing_key, filter) 
            end

            -- GRID CONFIGURATION
            local x_left = 20 -- left edge of left column
            local x_mid = x_left + 160 -- color pickers
            local x_right = x_mid + 140 -- reset buttons
            local y = -20 -- row spacing
            local row = 42 -- row height
            local slider_row = 50
            local reset_btn_width = 110

            -- first ROW
            
            -- move mode
            local move_cb_container, move_cb, _ = addon.CreateCheckbox(
                p,
                "Move Mode",
                M.db[data.move_key],
                function(is_checked)
                    M.db[data.move_key] = is_checked
                    update()
                end
            )
            move_cb_container:SetPoint("TOPLEFT", p, "TOPLEFT", x_left, y)
            M.controls[data.move_key] = move_cb

            -- move Reset
            local move_reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
            move_reset:SetSize(reset_btn_width, 22)
            move_reset:SetPoint("TOPLEFT", p, "TOPLEFT", x_right, y)
            move_reset:SetText("Move Reset")
            move_reset:SetScript("OnClick", function()
                local dPos = M.defaults.positions[cat]
                local dMove = M.defaults[data.move_key]
                M.db.positions[cat].point = dPos.point
                M.db.positions[cat].x = dPos.x
                M.db.positions[cat].y = dPos.y
                M.db[data.move_key] = dMove
                move_cb:SetChecked(dMove)
                local f = M.frames[data.show_key]

                if f then
                    f:ClearAllPoints()
                    f:SetPoint(dPos.point, UIParent, dPos.point, dPos.x, dPos.y)
                    update()
                end

            end)

            y = y - row -- new row
            
            -- Enable Frame
            local enable_cb_container, enable_cb, _ = addon.CreateCheckbox(
                p,
                "Enable Frame",
                M.db[data.show_key],
                function(is_checked)
                    M.db[data.show_key] = is_checked
                    update()
                end
            )
            enable_cb_container:SetPoint("TOPLEFT", p, "TOPLEFT", x_left, y)
            M.controls[data.show_key] = enable_cb

            -- Growth Direction
            local growth_drop = M.CreateDirectionDropdown(addon_name..cat.."Growth", p, "Growth Direction", "growth_"..cat, update)
            growth_drop:SetPoint("TOPLEFT", p, "TOPLEFT", x_mid - 18, y + 8)

            y = y - row -- new row

            --Show Background
            local bg_cb_container, bg_cb, _ = addon.CreateCheckbox(
                p,
                "Show Background",
                M.db[data.bg_key],
                function(is_checked)
                    M.db[data.bg_key] = is_checked
                    update()
                end
            )
            bg_cb_container:SetPoint("TOPLEFT", p, "TOPLEFT", x_left, y)
            M.controls[data.bg_key] = bg_cb

            -- BG color picker
            local bg_picker = addon.CreateColorPicker(p, M.db, "bg_color_"..cat, true, "BG Color", M.defaults, update)
            bg_picker:SetPoint("TOPLEFT", p, "TOPLEFT", x_mid, y)


            y = y - row

            -- ROW
              -- bar mode
            local bar_mode_cb_container, bar_mode_cb, _ = addon.CreateCheckbox(
                p,
                "Bar Mode",
                M.db["use_bars_"..cat],
                function(is_checked)
                    M.db["use_bars_"..cat] = is_checked
                    update()
                end
            )
            bar_mode_cb_container:SetPoint("TOPLEFT", p, "TOPLEFT", x_left, y)
            M.controls["use_bars_"..cat] = bar_mode_cb

            -- bar color picker
            local color_pick = addon.CreateColorPicker(p, M.db, "color_"..cat, false, "Bar Color", M.defaults, update)
            color_pick:SetPoint("TOPLEFT", p, "TOPLEFT", x_mid, y)

            -- SLIDERS SECTION
            y = y - 60 

            local scale_slider = M.CreateSliderWithBox(addon_name..cat.."Scale", p, "Scale", 0.5, 2.5, 0.01, data.scale_key, update)
            scale_slider:SetPoint("TOPLEFT", p, "TOPLEFT", x_left + 20, y)

            y = y - slider_row

            local space_slider = M.CreateSliderWithBox(addon_name..cat.."Spacing", p, "Spacing", 0, 40, 0.1, data.spacing_key, update)
            space_slider:SetPoint("TOPLEFT", p, "TOPLEFT", x_left + 20, y)

            y = y - slider_row

            local pool_slider = M.CreateSliderWithBox(addon_name..cat.."PoolSlider", p, "Max Icons (Requires /reload)", 5, 100, 1, "max_icons_"..cat, function()
                print("|cFFFFFF00LsTweaks:|r Pool size for "..cat.." changed. Please /reload to apply.")
            end)
            pool_slider:SetPoint("TOPLEFT", p, "TOPLEFT", x_left + 20, y)
        end

        tabs[i], panels[i] = tab, p
    end

    PanelTemplates_SetNumTabs(parent, #tab_data)
    for i = 1, #tab_data do
        if i == 1 then 
            panels[i]:Show() 
            PanelTemplates_SelectTab(tabs[i])
        else 
            panels[i]:Hide() 
            PanelTemplates_DeselectTab(tabs[i]) 
        end
    end
    PanelTemplates_UpdateTabs(parent)
end

-- This function is automatically called by the Big Red Button
function M.on_reset_complete()
    -- Tell the game to show Blizzard frames again (since DB is now false)
    M.toggle_blizz_buffs(M.db.disable_blizz_buffs)
    M.toggle_blizz_debuffs(M.db.disable_blizz_debuffs)

    -- Physically uncheck the boxes in the menu if it's currently open
    if M.controls then
        if M.controls["disable_blizz_buffs"] then
            M.controls["disable_blizz_buffs"]:SetChecked(M.db.disable_blizz_buffs)
        end
        if M.controls["disable_blizz_debuffs"] then
            M.controls["disable_blizz_debuffs"]:SetChecked(M.db.disable_blizz_debuffs)
        end
    end
end