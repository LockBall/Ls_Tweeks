local addon_name, addon = ...

-- Ensure the unified module table is used
addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

-- GUI COMPONENT BUILDERS

-- slider & editbox
function M.CreateSliderWithBox(name, parent, labelText, minV, maxV, step, db_key, callback)
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

-- growth direction dropdown
function M.CreateDirectionDropdown(name, parent, labelText, db_key, callback)
    local f = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local background = _G[f:GetName().."Middle"]
    label:SetPoint("BOTTOM", f, "TOP", 0, 2)
    label:SetText(labelText)

    UIDropDownMenu_Initialize(f, function(self, level)
        local options = {"UP", "DOWN", "LEFT", "RIGHT"}
        for _, dir in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = dir
            info.func = function()
                UIDropDownMenu_SetSelectedValue(f, dir)
                M.db[db_key] = dir
                callback()
            end
            info.value = dir
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_SetSelectedValue(f, M.db[db_key] or "DOWN")
    UIDropDownMenu_SetText(f, M.db[db_key] or "DOWN")
    UIDropDownMenu_SetWidth(f, 80)
    return f
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
            local blizz_buff = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            blizz_buff:SetPoint("TOPLEFT", p, "TOPLEFT", x_left, y)
            blizz_buff.Text:SetText("Disable Blizzard Buff Frame")
            blizz_buff:SetChecked(M.db.disable_blizz_buffs)
            blizz_buff:SetScript("OnClick", function(self) 
                M.db.disable_blizz_buffs = self:GetChecked() 
                M.toggle_blizz_buffs(M.db.disable_blizz_buffs) 
            end)
            M.controls["disable_blizz_buffs"] = blizz_buff

            y = y - row -- next row

            -- Blizzard Debuff Toggle
            local blizz_debuff = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            blizz_debuff:SetPoint("TOPLEFT", p, "TOPLEFT", x_left, y)
            blizz_debuff.Text:SetText("Disable Blizzard Debuff Frame")
            blizz_debuff:SetChecked(M.db.disable_blizz_debuffs)
            blizz_debuff:SetScript("OnClick", function(self) 
                M.db.disable_blizz_debuffs = self:GetChecked() 
                M.toggle_blizz_debuffs(M.db.disable_blizz_debuffs) 
            end)
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
            local move_cb = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            move_cb:SetPoint("TOPLEFT", p, "TOPLEFT", x_left, y)
            move_cb.Text:SetText("Move Mode")
            move_cb:SetChecked(M.db[data.move_key])
            move_cb:SetScript("OnClick", function(self) M.db[data.move_key] = self:GetChecked() update() end)
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
            local enable_cb = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            enable_cb:SetPoint("TOPLEFT", p, "TOPLEFT", x_left, y)
            enable_cb.Text:SetText("Enable Frame")
            enable_cb:SetChecked(M.db[data.show_key])
            enable_cb:SetScript("OnClick", function(self) M.db[data.show_key] = self:GetChecked() update() end)
            M.controls[data.show_key] = enable_cb

            -- Growth Direction
            local growth_drop = M.CreateDirectionDropdown(addon_name..cat.."Growth", p, "Growth Direction", "growth_"..cat, update)
            growth_drop:SetPoint("TOPLEFT", p, "TOPLEFT", x_mid - 18, y + 8)

            y = y - row -- new row

            --Show Background
            local bg_cb = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            bg_cb:SetPoint("TOPLEFT", p, "TOPLEFT", x_left, y)
            bg_cb.Text:SetText("Show Background")
            bg_cb:SetChecked(M.db[data.bg_key])
            bg_cb:SetScript("OnClick", function(self) M.db[data.bg_key] = self:GetChecked() update() end)
            M.controls[data.bg_key] = bg_cb

            -- BG color picker
            local bg_picker = addon.CreateColorPicker(p, M.db, "bg_color_"..cat, true, "BG Color", M.defaults, update)
            bg_picker:SetPoint("TOPLEFT", p, "TOPLEFT", x_mid, y)


            y = y - row

            -- ROW
              -- bar mode
            local bar_mode_cb = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            bar_mode_cb:SetPoint("TOPLEFT", p, "TOPLEFT", x_left, y)
            bar_mode_cb.Text:SetText("Bar Mode")
            bar_mode_cb:SetChecked(M.db["use_bars_"..cat])
            bar_mode_cb:SetScript("OnClick", function(self) M.db["use_bars_"..cat] = self:GetChecked() update() end)
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