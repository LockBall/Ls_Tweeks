local addon_name, addon = ...

-- Ensure the unified module table is used
addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

-- GUI COMPONENT BUILDERS

-- slider & editbox
-- Uses MinimalSliderTemplate (available 10.0+) and creates labels as explicit children
-- instead of relying on the deprecated _G[name..'Low/High/Text'] global pattern.
function M.CreateSliderWithBox(name, parent, labelText, minV, maxV, step, db_key, defaults_table, callback)
    -- Backward compatibility: allow old call shape without defaults_table.
    if type(defaults_table) == "function" and callback == nil then
        callback = defaults_table
        defaults_table = nil
    end

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(295, 58)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    container:SetBackdropColor(0, 0, 0, 0.3)
    container:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)

    local slider = CreateFrame("Slider", name, container, "MinimalSliderTemplate")
    slider:SetSize(155, 16)
    slider:SetPoint("TOPLEFT", container, "TOPLEFT", 12, -21)
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

    local eb = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    eb:SetSize(50, 20)
    eb:SetPoint("LEFT", slider, "RIGHT", 18, 1)
    eb:SetAutoFocus(false)
    eb:SetJustifyH("CENTER")
    eb:SetTextInsets(0, 0, 0, 0)
    eb:SetText(format(step < 1 and "%.2f" or "%.1f", M.db[db_key] or minV))

    local reset = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    reset:SetSize(42, 16)
    reset:SetPoint("LEFT", eb, "RIGHT", 8, 0)
    reset:SetText("Reset")
    reset:SetNormalFontObject("GameFontNormalSmall")

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

    reset:SetScript("OnClick", function()
        local default_value = defaults_table and defaults_table[db_key]
        if default_value == nil then
            default_value = minV
        end
        slider:SetValue(default_value)
    end)

    return container
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

    local function build_general_tab(p)
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
        local threshold = M.CreateSliderWithBox(addon_name.."Tslider", p, "Short Buff Threshold (s)", 10, 300, 10, "short_threshold", M.defaults, function()
            for k, v in pairs(M.frames) do
                -- Corrected to sub(6) to handle keys like show_static, show_short, etc.
                local cat = k:sub(6)
                M.update_auras(v, k, "move_"..cat, "timer_"..cat, "bg_"..cat, "scale_"..cat, "spacing_"..cat, k == "show_debuff" and "HARMFUL" or "HELPFUL")
            end
        end)
        threshold:SetPoint("TOPLEFT", p, "TOPLEFT", x_left, y)

        y = y - threshold:GetHeight() - 22 -- next row below slider

        -- Global Reset Button
        local resetPanel = addon.CreateGlobalReset(p, M.db, M.defaults)
        resetPanel:SetPoint("TOP", p, "TOP", 0, y)
        y = y - resetPanel:GetHeight() - row
    end

    local function build_category_tab(p, data)
        local cat = data.show_key:sub(6)
        local filter = data.is_debuff and "HARMFUL" or "HELPFUL"
        local function update() -- refreshes current category frame preview
            M.update_auras(M.frames[data.show_key], data.show_key, data.move_key, data.timer_key, data.bg_key, data.scale_key, data.spacing_key, filter)
        end

        -- GRID CONFIGURATION
        local grid = {
            left = 20,
            mid = 180,
            far = 375,
            y = -20,
            row = 42,
            slider_row = 68,
            reset_btn_width = 110,
            dropdown_y = 8,
            picker_y = 4,
        }

        local function place(control, column, y_offset)
            local x = grid[column]
            control:SetPoint("TOPLEFT", p, "TOPLEFT", x, grid.y + (y_offset or 0))
        end

        local function next_row()
            grid.y = grid.y - grid.row
        end

        local function next_slider_row()
            grid.y = grid.y - grid.slider_row
        end

        local function create_bound_checkbox(label, db_key, column, y_offset, on_change, control_key)
            local container, checkbox, _ = addon.CreateCheckbox(
                p,
                label,
                M.db[db_key],
                function(is_checked)
                    M.db[db_key] = is_checked
                    if on_change then
                        on_change(is_checked)
                    else
                        update()
                    end
                end
            )
            place(container, column, y_offset)
            M.controls[control_key or db_key] = checkbox
            return container, checkbox
        end

        local function create_bound_color_picker(db_key, has_alpha, label, column, y_offset)
            local picker = addon.CreateColorPicker(p, M.db, db_key, has_alpha, label, M.defaults, update)
            place(picker, column, y_offset)
            return picker
        end

        local function create_bound_slider(name_suffix, label, min_v, max_v, step, db_key, on_change)
            local slider = M.CreateSliderWithBox(
                addon_name..cat..name_suffix,
                p,
                label,
                min_v,
                max_v,
                step,
                db_key,
                M.defaults,
                on_change or update
            )
            place(slider, "left")
            return slider
        end

        -- first ROW

        -- move mode
        local _, move_cb = create_bound_checkbox("Move Mode", data.move_key, "left")

        -- move Reset
        local move_reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        move_reset:SetSize(grid.reset_btn_width, 22)
        place(move_reset, "mid")
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

        -- Growth Direction (top row, right column)
        place(M.CreateDirectionDropdown(addon_name..cat.."Growth", p, "Growth Direction", "growth_"..cat, update), "far", grid.dropdown_y)

        next_row() -- new row

        -- Enable Frame
        create_bound_checkbox("Enable Frame", data.show_key, "left")

        -- Frame background (same row, right of Enable Frame)
        create_bound_checkbox("Frame Background", data.bg_key, "mid")

        -- Frame BG color picker (same row, right of Frame background)
        create_bound_color_picker("bg_color_"..cat, true, "Frame BG Color", "far", grid.picker_y)

        next_row()

        -- ROW
        -- bar mode
        local bar_mode_key = "use_bars_"..cat
        create_bound_checkbox("Bar Mode", bar_mode_key, "left")

        -- bar color picker
        create_bound_color_picker("color_"..cat, false, "Bar Color", "mid", grid.picker_y)

        -- bar background color picker
        create_bound_color_picker("bar_bg_color_"..cat, true, "Bar BG Color", "far", grid.picker_y)

        if cat ~= "static" then
            next_row()

            -- Fourth row: timer text visibility
            create_bound_checkbox("Show Time Remaining", data.timer_key, "left")
        end

        -- SLIDERS SECTION
        next_slider_row()

        create_bound_slider("Scale", "Scale", 0.5, 2.5, 0.01, data.scale_key)

        next_slider_row()

        create_bound_slider("Spacing", "Spacing", 0, 40, 0.1, data.spacing_key)

        next_slider_row()

        create_bound_slider("PoolSlider", "Max Icons (Requires /reload)", 5, 100, 1, "max_icons_"..cat, function()
            print("|cFFFFFF00LsTweaks:|r Pool size for "..cat.." changed. Please /reload to apply.")
        end)
    end

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
            build_general_tab(p)

        else -- not in general
            build_category_tab(p, data)
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

