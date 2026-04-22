local addon_name, addon = ...

-- Ensure the unified module table is used
addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

-- GUI COMPONENT BUILDERS

-- Shared dropdown mechanics live in functions/dropdown.lua via addon.CreateDropdown.

function M.CreateListDropdown(name, parent, labelText, options, get_value, on_select, width)
    local function get_option_text(option)
        return option.text or tostring(option.value or "")
    end

    local function apply_button_style(btn_text, option)
        if not btn_text then return end
        if option.font_path then
            btn_text:SetFont(option.font_path, option.font_size or 9, option.font_flags or "")
        else
            btn_text:SetFontObject(GameFontHighlightSmall)
        end
    end

    local function apply_row_style(row_text, option)
        if option.font_path then
            row_text:SetFont(option.font_path, option.font_size or 9, option.font_flags or "")
        end
    end

    return M._CreateDropdown(name, parent, labelText, options, {
        width = width or 180,
        get_value = get_value,
        on_select = function(value)
            if on_select then on_select(value) end
        end,
        get_option_text = get_option_text,
        apply_button_style = apply_button_style,
        apply_row_style = apply_row_style,
    })
end

function M._CreateDropdown(name, parent, labelText, options, cfg)
    return addon.CreateDropdown(name, parent, labelText, options, cfg)
end

-- growth direction dropdown
-- Replaces the deprecated UIDropDownMenu API with a custom popup list.
function M.CreateDirectionDropdown(name, parent, labelText, db_key, callback)
    local dir_values = { "RIGHT", "LEFT", "DOWN", "UP" }
    local options = {}
    for _, dir in ipairs(dir_values) do
        options[#options + 1] = { value = dir, text = dir }
    end

    return M._CreateDropdown(name, parent, labelText, options, {
        width = 106,
        get_value = function()
            return M.db[db_key] or "DOWN"
        end,
        on_select = function(value)
            M.db[db_key] = value
            if callback then callback() end
        end,
    })
end

-- tabs settings controls
function M.BuildSettings(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetText("Buffs & Debuffs Configuration")

    local font_options = {}
    local defs = M.get_number_font_options and M.get_number_font_options() or {}
    for _, def in ipairs(defs) do
        font_options[#font_options + 1] = {
            value = def.key,
            text = def.label,
            font_path = def.path,
            font_size = def.size,
            font_flags = def.flags,
        }
    end

    local size_options = {}
    for i = 8, 14, 2 do
        size_options[#size_options + 1] = { value = i, text = tostring(i) }
    end

    local tabs, panels = {}, {}
    local tab_data = {
        { name = "General", is_general = true },
        { name = "Static", show_key = "show_static", move_key = "move_static", timer_key = "timer_static", bg_key = "bg_static", scale_key = "scale_static", spacing_key = "spacing_static" },
        { name = "Short", show_key = "show_short", move_key = "move_short", timer_key = "timer_short", bg_key = "bg_short", scale_key = "scale_short", spacing_key = "spacing_short" },
        { name = "Long", show_key = "show_long", move_key = "move_long", timer_key = "timer_long", bg_key = "bg_long", scale_key = "scale_long", spacing_key = "spacing_long" },
        { name = "Debuffs", show_key = "show_debuff", move_key = "move_debuff", timer_key = "timer_debuff", bg_key = "bg_debuff", scale_key = "scale_debuff", spacing_key = "spacing_debuff", is_debuff = true }
    }

    local function build_general_tab(p)
        local function refresh_all_category_frames()
            for _, frame in pairs(M.frames) do
                if frame and frame.update_params then
                    local params = frame.update_params
                    M.update_auras(frame, params.show_key, params.move_key, params.timer_key, params.bg_key, params.scale_key, params.spacing_key, params.filter)
                end
            end
        end


        -- Manual layout for General tab

        -- Blizzard Buff & Debuff Enable Frames Section
        local enable_panel = CreateFrame("Frame", nil, p, "BackdropTemplate")
        enable_panel:SetSize(150, 45)
        enable_panel:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -16)
        enable_panel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        enable_panel:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
        enable_panel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

        local panel_title = enable_panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        panel_title:SetText("Enable Blizz Frame")
        panel_title:SetPoint("TOP", enable_panel, "TOP", 0, -5)


        -- Blizzard Buff Frame Checkbox (checked = enabled)
        local enable_blizz_buffs_container, enable_blizz_buffs_cb, _ = addon.CreateCheckbox(enable_panel, "Buff", not M.db.disable_blizz_buffs,
            function(is_checked)
                M.db.disable_blizz_buffs = not is_checked
                M.toggle_blizz_buffs(not is_checked)
            end
        )
        enable_blizz_buffs_container:SetPoint("CENTER", enable_panel, "CENTER", -40, -5)
        M.controls["enable_blizz_buffs"] = enable_blizz_buffs_cb

        -- Blizzard Debuff Frame Checkbox (checked = enabled)
        local enable_blizz_debuffs_container, enable_blizz_debuffs_cb, _ = addon.CreateCheckbox(
            enable_panel,
            "Debuff",
            not M.db.disable_blizz_debuffs,
            function(is_checked)
                M.db.disable_blizz_debuffs = not is_checked
                M.toggle_blizz_debuffs(not is_checked)
            end
        )
        enable_blizz_debuffs_container:SetPoint("CENTER", enable_panel, "CENTER", 40, -5)
        M.controls["enable_blizz_debuffs"] = enable_blizz_debuffs_cb

        -- Short Buff Threshold slider
        local threshold = addon.CreateSliderWithBox(addon_name.."Tslider", p, "Short Buff Threshold", 10, 300, 10, M.db, "short_threshold", M.defaults, function()
            for k, v in pairs(M.frames) do
                local cat = k:sub(6)
                M.update_auras(v, k, "move_"..cat, "timer_"..cat, "bg_"..cat, "scale_"..cat, "spacing_"..cat, k == "show_debuff" and "HARMFUL" or "HELPFUL")
            end
        end)
        threshold:SetPoint("TOPLEFT", enable_panel, "BOTTOMLEFT", 0, -24)


        -- Show Bar Section Outlines Checkbox
        local outlines_container, outlines_btn, _ = addon.CreateCheckbox(p, "Show Bar Section Outlines", Ls_Tweeks_DB.show_bar_section_outlines == true,
            function(is_checked)
                Ls_Tweeks_DB.show_bar_section_outlines = is_checked
                if addon.aura_frames and addon.aura_frames.refresh_section_outlines then
                    addon.aura_frames.refresh_section_outlines()
                end
            end
        )
        outlines_container:SetPoint("TOPLEFT", threshold, "BOTTOMLEFT", 0, -18)
        M.controls.show_bar_section_outlines_checkbox = outlines_btn

        -- reset panel
        local resetPanel = addon.CreateGlobalReset(p, M.db, M.defaults)
        resetPanel:SetPoint("BOTTOM", p, "BOTTOM", 0, -50)
    end

    local function build_category_tab(p, data)
        local cat = data.show_key:sub(6)
        local filter = data.is_debuff and "HARMFUL" or "HELPFUL"
        local test_key = "test_aura_"..cat

        local function update() -- refreshes current category frame preview
            M.update_auras(M.frames[data.show_key], data.show_key, data.move_key, data.timer_key, data.bg_key, data.scale_key, data.spacing_key, filter)
        end

        -- Grid Layout Configuration (row/column placement for controls)
        -- col_gap  = distance between column start positions (moves columns apart/together)
        -- col_width = centering zone within each column (controls how wide the center target is)
        local col_gap   = 150  -- adjust to spread or compress columns
        local col_width = 190  -- adjust independently from gap if needed
        local grid = {
            [1] = 0,
            [2] = col_gap,
            [3] = col_gap * 2,
            [4] = col_gap * 3,
            col_width = col_width,
            col_align = { "center", "center", "center", "center" },
            row_start = -20,
            --             1   2   3   4   5   6
            row_heights = {40, 60, 60, 110, 110, 110},
            reset_btn_width = 110,
            offsets = {
                default = 0,
                dropdown = 8,
                picker = 4,
            },
            content_rows = 6,
        }

        local function place_at(control, row, column, slot, opts)
            opts = opts or {}
            local align = opts.align or grid.col_align[column] or "left"
            local x = grid[column]
            local y = grid.row_start
            for i = 1, (row - 1) do
                y = y - (grid.row_heights[i] or grid.row_heights[#grid.row_heights])
            end
            local y_offset = grid.offsets[slot or "default"] or 0
            if opts.y_offset then y_offset = y_offset + opts.y_offset end
            local width = opts.width or (control.GetWidth and control:GetWidth() or 0)
            if align == "center" then
                x = x + math.floor((grid.col_width - width) / 2)
            elseif align == "right" then
                x = x + grid.col_width - width
            end
            control:SetPoint("TOPLEFT", p, "TOPLEFT", x, y + y_offset)
        end

        local function create_bound_checkbox(label, db_key, row, column, on_change, control_key, extra_on_uncheck, extra_on_check)
            local container, checkbox, _ = addon.CreateCheckbox(p, label, M.db[db_key],
                function(is_checked)
                    M.db[db_key] = is_checked
                    if is_checked and extra_on_check then
                        extra_on_check()
                    end
                    if not is_checked and extra_on_uncheck then
                        extra_on_uncheck()
                    end
                    if on_change then
                        on_change(is_checked)
                    else
                        update()
                    end
                end
            )
            place_at(container, row, column)
            M.controls[control_key or db_key] = checkbox
            return container, checkbox
        end

        local function create_bound_color_picker(db_key, has_alpha, label, row, column)
            local picker = addon.CreateColorPicker(p, M.db, db_key, has_alpha, label, M.defaults, update)
            place_at(picker, row, column, "picker")
            return picker
        end

        local function create_bound_slider(name_suffix, label, min_v, max_v, step, db_key, on_change)
            local slider = addon.CreateSliderWithBox(
                addon_name..cat..name_suffix,
                p,
                label,
                min_v,
                max_v,
                step,
                M.db,
                db_key,
                M.defaults,
                on_change or update
            )
            return slider
        end

        -- Row 1

        -- move mode
        local _, move_cb = create_bound_checkbox("Move Mode", data.move_key, 1, 1)

        -- move Reset
        local move_reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        move_reset:SetSize(grid.reset_btn_width, 22)
        place_at(move_reset, 1, 3)
        move_reset:SetText("Move Reset")
        move_reset:SetScript("OnClick", function()
            local dPos = M.defaults.positions[cat]
            local dMove = M.defaults[data.move_key]
            local dWidth = M.defaults["width_"..cat] or 200
            M.db.positions[cat].point = dPos.point
            M.db.positions[cat].x = dPos.x
            M.db.positions[cat].y = dPos.y
            M.db[data.move_key] = dMove
            M.db["width_"..cat] = dWidth
            move_cb:SetChecked(dMove)
            local f = M.frames[data.show_key]

            if f then
                f:ClearAllPoints()
                f:SetPoint(dPos.point, UIParent, dPos.point, dPos.x, dPos.y)
                f:SetWidth(dWidth)
                update()
            end
        end)

        -- Test Aura
        create_bound_checkbox("Test Aura", test_key, 1, 2, update, nil, nil, check_enable_frame)

        -- Growth Direction
        place_at(M.CreateDirectionDropdown(addon_name..cat.."Growth", p, "Growth Direction", "growth_"..cat, update), 1, 4, "dropdown")

        -- Row 2

        -- Enable Frame
        local cat = data.show_key:sub(6)
        local test_key = "test_aura_"..cat
        local function uncheck_test_aura()
            if M.db[test_key] then
                M.db[test_key] = false
                local test_cb = M.controls[test_key]
                if test_cb and test_cb.SetChecked then
                    test_cb:SetChecked(false)
                end
            end
        end
        local function check_enable_frame()
            if not M.db[data.show_key] then
                M.db[data.show_key] = true
                local enable_cb = M.controls[data.show_key]
                if enable_cb and enable_cb.SetChecked then
                    enable_cb:SetChecked(true)
                end
            end
        end
        create_bound_checkbox("Enable Frame", data.show_key, 2, 1, nil, nil, uncheck_test_aura)

        -- Frame background
        create_bound_checkbox("Frame BG", data.bg_key, 2, 2)

        -- Frame BG color picker (second row, far-right)
        create_bound_color_picker("bg_color_"..cat, true, "Frame BG Color", 2, 3)

        -- Row 3: Bar Mode and color pickers
        local bar_mode_key = "use_bars_"..cat
        create_bound_checkbox("Bar Mode", bar_mode_key, 3, 1)
        create_bound_color_picker("color_"..cat, false, "Bar Color", 3, 2)
        create_bound_color_picker("bar_bg_color_"..cat, true, "Bar BG Color", 3, 3)

        -- Row 4: Timer Text, Font & Font Size
        if cat ~= "static" then
            local timer_text_container = select(1, create_bound_checkbox("Timer Text", data.timer_key, 4, 1))

            local timer_bold_container = select(1, create_bound_checkbox("Timer Bold", "timer_number_font_bold_"..cat, 4, 1, function()
                if M.apply_number_font_to_all then M.apply_number_font_to_all() end
                update()
            end))
            timer_bold_container:ClearAllPoints()
            timer_bold_container:SetPoint("TOPLEFT", timer_text_container, "BOTTOMLEFT", 0, -4)

            local timer_font = M.CreateListDropdown(addon_name..cat.."TimerFont", p, "Timer Font", font_options,
                function()
                    return M.db["timer_number_font_"..cat] or M.db.timer_number_font or "source_code_pro"
                end,
                function(value)
                    M.db["timer_number_font_"..cat] = value
                    if M.apply_number_font_to_all then
                        M.apply_number_font_to_all()
                    end
                    update()
                end,
                120 -- reduced width
            )

            place_at(timer_font, 4, 2, nil, {width=120, y_offset=-15})
            M.controls["timer_number_font_dropdown_"..cat] = timer_font

            local font_size_slider = addon.CreateSliderWithBox(addon_name..cat.."TimerFontSizeSlider", p, "Font Size", 8, 14, 0.5, M.db, "timer_number_font_size_"..cat,
                M.defaults,
                function()
                    if M.apply_number_font_to_all then
                        M.apply_number_font_to_all()
                    end
                    update()
                end
            )
            place_at(font_size_slider, 4, 3)
            M.controls["timer_number_font_size_slider_"..cat] = font_size_slider
        end

        -- Row 5: Scale and Spacing sliders
        local scale_slider = create_bound_slider("Scale", "Scale", 0.5, 2.5, 0.01, data.scale_key, update)
        place_at(scale_slider, 5, 1)

        local spacing_slider = create_bound_slider("Spacing", "Spacing", 0, 20, 0.1, data.spacing_key)
        place_at(spacing_slider, 5, 2)

        local max_icons_slider = create_bound_slider("PoolSlider", "Max Icons", 5, 40, 1, "max_icons_"..cat, function()
            print("|cFFFFFF00LsTweaks:|r Pool size for "..cat.." changed. Please /reload to apply.")
        end)
        place_at(max_icons_slider, 5, 3)
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
            if M.db then M.db.last_tab_index = self:GetID() end
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
    local restore_tab = (M.db and M.db.last_tab_index) or 1
    for i = 1, #tab_data do
        if i == restore_tab then
            panels[i]:Show()
            PanelTemplates_SelectTab(tabs[i])
        else
            panels[i]:Hide()
            PanelTemplates_DeselectTab(tabs[i])
        end
    end
    PanelTemplates_UpdateTabs(parent)
end

-- Sync only GUI control states from DB (used after reset flows).
function M.sync_general_controls_from_db()
    if not M.controls or not M.db then return end

    local buffs = M.controls["disable_blizz_buffs"]
    if buffs and buffs.SetChecked then
        buffs:SetChecked(M.db.disable_blizz_buffs)
    end

    local debuffs = M.controls["disable_blizz_debuffs"]
    if debuffs and debuffs.SetChecked then
        debuffs:SetChecked(M.db.disable_blizz_debuffs)
    end

    for _, cat in ipairs({ "short", "long", "debuff" }) do
        local font_dropdown = M.controls["timer_number_font_dropdown_"..cat]
        if font_dropdown and font_dropdown.SetValue then
            font_dropdown:SetValue(M.db["timer_number_font_"..cat] or M.db.timer_number_font or "source_code_pro")
        end

        local font_size_slider = M.controls["timer_number_font_size_slider_"..cat]
        if font_size_slider and font_size_slider.slider then
            font_size_slider.slider:SetValue(M.db["timer_number_font_size_"..cat] or M.defaults["timer_number_font_size_"..cat] or 10)
        end
    end

    local bold_cb = M.controls["timer_number_font_bold"]
    if bold_cb and bold_cb.SetChecked then
        bold_cb:SetChecked(M.db.timer_number_font_bold)
    end

    for _, cat in ipairs({ "short", "long", "debuff" }) do
        local cat_bold_cb = M.controls["timer_number_font_bold_"..cat]
        if cat_bold_cb and cat_bold_cb.SetChecked then
            cat_bold_cb:SetChecked(M.db["timer_number_font_bold_"..cat] or false)
        end
    end

    local timer_align_dropdown = M.controls["timer_number_alignment_dropdown"]
    if timer_align_dropdown and timer_align_dropdown.SetValue then
        timer_align_dropdown:SetValue(M.db.timer_number_alignment or "center")
    end

end

