local addon_name, addon = ...

-- Ensure the unified module table is used
addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

-- GUI COMPONENT BUILDERS
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
        if val then 
            val = math.max(minV, math.min(maxV, val)) 
            slider:SetValue(val) 
        end
        self:ClearFocus()
    end)
    return slider
end

-- ============================================================================
-- SETTINGS PANEL INTERFACE
-- ============================================================================
-- Renamed to M.BuildSettings to match the handshake in af_main.lua
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
            local b_buff = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            b_buff:SetPoint("TOPLEFT", 16, -16)
            b_buff.Text:SetText("Disable Blizzard Buff Frame")
            b_buff:SetChecked(M.db.disable_blizz_buffs)
            b_buff:SetScript("OnClick", function(self) 
                M.db.disable_blizz_buffs = self:GetChecked() 
                M.toggle_blizz_buffs(M.db.disable_blizz_buffs) 
            end)

            local b_debuff = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            b_debuff:SetPoint("TOPLEFT", b_buff, "BOTTOMLEFT", 0, -8)
            b_debuff.Text:SetText("Disable Blizzard Debuff Frame")
            b_debuff:SetChecked(M.db.disable_blizz_debuffs)
            b_debuff:SetScript("OnClick", function(self) 
                M.db.disable_blizz_debuffs = self:GetChecked() 
                M.toggle_blizz_debuffs(M.db.disable_blizz_debuffs) 
            end)

            M.controls["disable_blizz_buffs"] = b_buff
            M.controls["disable_blizz_debuffs"] = b_debuff

            M.CreateSliderWithBox(addon_name.."Tslider", p, "Short Buff Threshold (s)", 10, 300, 10, "short_threshold", function() 
                for k,v in pairs(M.frames) do 
                    M.update_auras(v, k, "move_"..k:sub(7), "timer_"..k:sub(7), "bg_"..k:sub(7), "scale_"..k:sub(7), "spacing_"..k:sub(7), k=="show_debuff" and "HARMFUL" or "HELPFUL") 
                end
            end):SetPoint("TOPLEFT", b_debuff, "BOTTOMLEFT", 20, -40)

            -- Updated to use the unified M.defaults
            addon.CreateGlobalReset(p, b_debuff, M.db, M.defaults)
        else
            local cat = data.show_key:sub(6)
            local filter = data.is_debuff and "HARMFUL" or "HELPFUL"
            local function update() 
                M.update_auras(M.frames[data.show_key], data.show_key, data.move_key, data.timer_key, data.bg_key, data.scale_key, data.spacing_key, filter) 
            end
            
            local move_cb = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
            move_cb:SetPoint("TOPLEFT", 16, -16)
            move_cb.Text:SetText("Move Mode")
            move_cb:SetChecked(M.db[data.move_key])
            move_cb:SetScript("OnClick", function(self) M.db[data.move_key] = self:GetChecked() update() end)
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
                local dc = M.defaults["color_"..cat]
                M.db["color_"..cat] = {r = dc.r, g = dc.g, b = dc.b}
                color_btn:SetBackdropColor(dc.r, dc.g, dc.b)
                update()
            end)

            M.CreateSliderWithBox(addon_name..cat.."Scale", p, "Scale", 0.5, 2.5, 0.01, data.scale_key, update):SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", 20, -35)
            M.CreateSliderWithBox(addon_name..cat.."Spacing", p, "Spacing", 0, 40, 0.1, data.spacing_key, update):SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", 20, -85)

            local reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
            reset:SetSize(120, 22)
            reset:SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", -10, -140)
            reset:SetText("Reset Position")
            reset:SetScript("OnClick", function()
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
    -- 1. Tell the game to show Blizzard frames again (since DB is now false)
    M.toggle_blizz_buffs(M.db.disable_blizz_buffs)
    M.toggle_blizz_debuffs(M.db.disable_blizz_debuffs)

    -- 2. Physically uncheck the boxes in the menu if it's currently open
    if M.controls then
        if M.controls["disable_blizz_buffs"] then
            M.controls["disable_blizz_buffs"]:SetChecked(M.db.disable_blizz_buffs)
        end
        if M.controls["disable_blizz_debuffs"] then
            M.controls["disable_blizz_debuffs"]:SetChecked(M.db.disable_blizz_debuffs)
        end
    end
end