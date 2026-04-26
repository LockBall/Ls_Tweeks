-- Settings panels for custom whitelist aura frames.
-- Provides M.build_custom_settings_panel(p, entry) and M.build_custom_child_panel(p, entry),
-- called lazily by the Frames tab tree in af_gui.lua when a custom node is selected.

local addon_name, addon = ...

local issecretvalue = issecretvalue

addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

-- ============================================================================
-- CUSTOM SETTINGS PANEL
-- Same 4-column grid layout as the preset build_category_tab, but reads/writes
-- from the custom entry table instead of the flat M.db namespace.

function M.build_custom_settings_panel(p, entry)
    local id       = entry.id
    local show_key = "show_" .. id
    local filter   = (entry.filter == "HARMFUL") and "HARMFUL" or "HELPFUL"

    local function update()
        local frame = M.frames[show_key]
        if frame then
            M.update_auras(frame, show_key, "move", "timer", "bg", "scale", "spacing", filter)
        end
    end

    -- Grid (identical constants to build_category_tab in af_gui.lua)
    local col_gap    = 150
    local col_width  = 190
    local col_offset = -20
    local row_gap    = 20
    local grid = {
        [1] = col_offset,
        [2] = col_gap + col_offset,
        [3] = col_gap * 2 + col_offset,
        [4] = col_gap * 3 + col_offset,
        col_width   = col_width,
        col_align   = { "center", "center", "center", "center" },
        row_start   = 10,
        row_gap     = row_gap,
        row_heights = { 130, 60, 60, 110, 110 },
        reset_btn_width = 110,
        offsets     = { default = 0, dropdown = 8, picker = 4 },
        content_rows = 5,
    }

    local function place_at(control, row, column, slot, opts)
        if not control then return end
        opts = opts or {}
        local align = opts.align or grid.col_align[column] or "left"
        local x = grid[column]
        local y = grid.row_start
        for i = 1, (row - 1) do
            y = y - (grid.row_heights[i] or grid.row_heights[#grid.row_heights])
        end
        if opts.valign == "bottom" then
            y = y - (grid.row_heights[row] or grid.row_heights[#grid.row_heights])
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

    local function add_row_separator(row)
        local line = p:CreateTexture(nil, "BACKGROUND")
        line:SetColorTexture(1, 1, 1, 0.08)
        line:SetHeight(2)
        local y = grid.row_start
        for i = 1, row do y = y - (grid.row_heights[i] or grid.row_heights[#grid.row_heights]) end
        line:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y + math.floor(grid.row_gap / 2))
        line:SetWidth(grid[4] + grid.col_width - 12)
    end

    -- Checkbox bound to the entry table.
    local function bound_cb(label, key, row, column, on_change)
        local container, cb, _ = addon.CreateCheckbox(p, label, entry[key],
            function(is_checked)
                entry[key] = is_checked
                if on_change then on_change(is_checked) else update() end
            end
        )
        place_at(container, row, column)
        M.controls["custom_" .. id .. "_" .. key] = cb
        return container, cb
    end

    -- Color picker bound to the entry table.
    local function bound_picker(key, has_alpha, label, row, column)
        local picker = addon.CreateColorPicker(p, entry, key, has_alpha, label, M.CUSTOM_FRAME_TEMPLATE, update)
        place_at(picker, row, column, "picker")
        return picker
    end

    -- ---- Row 1: Move Mode, X/Y position, Width ----
    local pos = entry.position or { x = 0, y = 50 }

    local function update_frame_position()
        local f = M.frames[show_key]
        if f and pos then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "CENTER", pos.x or 0, pos.y or 0)
        end
    end

    local move_container, move_cb = bound_cb("Move Mode", "move", 1, 1, function(is_checked)
        if is_checked then
            local en_cb = M.controls["custom_" .. id .. "_show"]
            if en_cb and en_cb.SetChecked and not en_cb:GetChecked() then
                en_cb:SetChecked(true); entry["show"] = true
            end
        end
        update()
    end)

    local x_slider = addon.CreateSliderWithBox(addon_name..id.."XPos", p, "X Position", -1000, 1000, 1, pos, "x", { x = 0 })
    x_slider.slider:HookScript("OnValueChanged", update_frame_position)
    place_at(x_slider, 1, 2)

    local y_slider = addon.CreateSliderWithBox(addon_name..id.."YPos", p, "Y Position", -1000, 1000, 1, pos, "y", { y = 50 })
    y_slider.slider:HookScript("OnValueChanged", update_frame_position)
    place_at(y_slider, 1, 3)

    local width_slider = addon.CreateSliderWithBox(addon_name..id.."Width", p, "Width", 180, 800, 1, entry, "width", M.CUSTOM_FRAME_TEMPLATE)
    width_slider.slider:HookScript("OnValueChanged", function(_, value)
        local f = M.frames[show_key]
        if f then f:SetWidth(math.floor(value + 0.5)); update() end
    end)
    place_at(width_slider, 1, 4)

    local snap_container = addon.CreateCheckbox(p, "Snap to Grid", M.db.snap_to_grid == true,
        function(is_checked) M.db.snap_to_grid = is_checked end)
    snap_container:SetPoint("TOPLEFT", move_container, "BOTTOMLEFT", 0, -4)

    local show_grid_container = addon.CreateCheckbox(p, "Show Grid", M.db.show_grid == true,
        function(is_checked)
            M.db.show_grid = is_checked
            if M.set_grid_visible then M.set_grid_visible(is_checked) end
        end)
    show_grid_container:SetPoint("TOPLEFT", snap_container, "BOTTOMLEFT", 0, -4)

    local move_reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    move_reset:SetSize(grid.reset_btn_width, 22)
    move_reset:SetPoint("TOPLEFT", show_grid_container, "BOTTOMLEFT", 0, -6)
    move_reset:SetText("Move Reset")
    move_reset:SetScript("OnClick", function()
        local tmpl = M.CUSTOM_FRAME_TEMPLATE
        pos.x = tmpl.position.x; pos.y = tmpl.position.y
        entry.move  = tmpl.move
        entry.width = tmpl.width
        move_cb:SetChecked(false)
        local f = M.frames[show_key]
        if f then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "CENTER", pos.x, pos.y)
            f:SetWidth(entry.width)
            update()
        end
        if x_slider and x_slider.slider then x_slider.slider:SetValue(pos.x) end
        if y_slider and y_slider.slider then y_slider.slider:SetValue(pos.y) end
    end)

    add_row_separator(1)

    -- ---- Row 2: Enable Frame, Test Aura, Frame BG, BG Color ----
    local enable_container, enable_cb = bound_cb("Enable Frame", "show", 2, 1, function(is_checked)
        if not is_checked then
            entry.test_aura = false
            local ta_cb = M.controls["custom_" .. id .. "_test_aura"]
            if ta_cb and ta_cb.SetChecked then ta_cb:SetChecked(false) end
        end
        update()
    end)

    local test_aura_container = bound_cb("Test Aura", "test_aura", 2, 1, function(is_checked)
        if is_checked then
            entry.show = true
            if enable_cb and enable_cb.SetChecked then enable_cb:SetChecked(true) end
        end
        update()
    end)
    test_aura_container:ClearAllPoints()
    test_aura_container:SetPoint("TOPLEFT", enable_container, "BOTTOMLEFT", 0, 0)

    bound_cb("Frame BG", "bg", 2, 2)
    bound_picker("bg_color", true, "Frame BG Color", 2, 3)
    add_row_separator(2)

    -- ---- Row 3: Bar Mode, Bar Color, Bar BG Color, Growth Direction ----
    bound_cb("Bar Mode", "bar_mode", 3, 1)
    bound_picker("color", true, "Bar Color", 3, 2)
    bound_picker("bar_bg_color", true, "Bar BG Color", 3, 3)

    local dir_options = {}
    for _, dir in ipairs({ "RIGHT", "LEFT", "DOWN", "UP" }) do
        dir_options[#dir_options + 1] = { value = dir, text = dir }
    end
    local growth_dd = addon.CreateDropdown(addon_name..id.."Growth", p, "Growth Direction", dir_options, {
        width     = 106,
        get_value = function() return entry.growth or "DOWN" end,
        on_select = function(value) entry.growth = value; update() end,
    })
    place_at(growth_dd, 3, 4, "dropdown", { y_offset = -math.floor((grid.row_heights[3] - 24) / 2) })
    add_row_separator(3)

    -- ---- Row 4: Timer Text, Bold, Font, Font Size ----
    local timer_text_container = bound_cb("Timer Text", "timer", 4, 1)
    local timer_bold_container = bound_cb("Timer Bold", "timer_number_font_bold", 4, 1, function()
        if M.apply_number_font_to_all then M.apply_number_font_to_all() end
        update()
    end)
    timer_bold_container:ClearAllPoints()
    timer_bold_container:SetPoint("TOPLEFT", timer_text_container, "BOTTOMLEFT", 0, -4)

    local font_options = {}
    for _, def in ipairs(M.get_number_font_options and M.get_number_font_options() or {}) do
        font_options[#font_options + 1] = {
            value = def.key, text = def.label,
            font_path = def.path, font_size = def.size, font_flags = def.flags,
        }
    end

    local timer_font_dd = M.CreateListDropdown(addon_name..id.."TimerFont", p, "Timer Font", font_options,
        function() return entry.timer_number_font or "source_code_pro" end,
        function(value)
            entry.timer_number_font = value
            if M.apply_number_font_to_all then M.apply_number_font_to_all() end
            update()
        end, 120)
    place_at(timer_font_dd, 4, 2, nil, { width = 120, y_offset = -15 })

    local font_size_slider = addon.CreateSliderWithBox(addon_name..id.."TimerFontSize", p, "Timer Font Size",
        8, 14, 0.5, entry, "timer_number_font_size", M.CUSTOM_FRAME_TEMPLATE,
        function()
            if M.apply_number_font_to_all then M.apply_number_font_to_all() end
            update()
        end)
    place_at(font_size_slider, 4, 3)
    add_row_separator(4)

    -- ---- Row 5: Scale, Spacing, Max Icons ----
    local scale_slider = addon.CreateSliderWithBox(addon_name..id.."Scale", p, "Scale",
        0.5, 2.5, 0.01, entry, "scale", M.CUSTOM_FRAME_TEMPLATE, update)
    place_at(scale_slider, 5, 1)

    local spacing_slider = addon.CreateSliderWithBox(addon_name..id.."Spacing", p, "Spacing",
        0, 20, 0.1, entry, "spacing", M.CUSTOM_FRAME_TEMPLATE, update)
    place_at(spacing_slider, 5, 2)

    local max_icons_slider = addon.CreateSliderWithBox(addon_name..id.."MaxIcons", p, "Max Icons",
        5, 40, 1, entry, "max_icons", M.CUSTOM_FRAME_TEMPLATE,
        function()
            print("|cFFFFFF00LsTweaks:|r Pool size for " .. entry.name .. " changed. Please /reload to apply.")
        end)
    place_at(max_icons_slider, 5, 4)

    -- Hook title bars so dragging syncs the X/Y sliders.
    local frame = M.frames[show_key]
    if frame then
        local function sync_xy()
            local f = M.frames[show_key]
            if not (f and x_slider and y_slider and x_slider.slider and y_slider.slider) then return end
            local ucx, ucy = UIParent:GetCenter()
            local left = f:GetLeft(); local top = f:GetTop()
            if left and top then
                pos.x = math.floor(left - ucx + 0.5)
                pos.y = math.floor(top  - ucy + 0.5)
                x_slider.slider:SetValue(pos.x)
                y_slider.slider:SetValue(pos.y)
            end
        end
        for _, tb in ipairs({ frame.title_bar, frame.bottom_title_bar }) do
            if tb then
                local old = tb:GetScript("OnDragStop")
                tb:SetScript("OnDragStop", function(...)
                    if old then old(...) end
                    sync_xy()
                end)
            end
        end
    end
end

-- ============================================================================
-- CUSTOM CHILD PANEL
-- Buff/debuff filter toggle, scrollable whitelist, manual spell ID entry,
-- and Capture Mode (live aura list with auto-timeout).

function M.build_custom_child_panel(p, entry)
    local id       = entry.id
    local show_key = "show_" .. id

    local header = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -10)
    header:SetText(entry.name .. " — Whitelist")

    -- ----------------------------------------------------------------
    -- BUFF / DEBUFF TOGGLE
    -- ----------------------------------------------------------------
    local filter_lbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filter_lbl:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -14)
    filter_lbl:SetText("Aura Type:")

    local buff_btn   = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    local debuff_btn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    buff_btn:SetSize(70, 22)
    debuff_btn:SetSize(70, 22)
    buff_btn:SetText("Buffs")
    debuff_btn:SetText("Debuffs")
    buff_btn:SetPoint("LEFT", filter_lbl, "RIGHT", 5, 0)
    debuff_btn:SetPoint("LEFT", buff_btn, "RIGHT", 5, 0)

    local function refresh_filter_btns()
        local is_buff = (entry.filter == "HELPFUL")
        buff_btn:SetAlpha(is_buff and 1 or 0.45)
        debuff_btn:SetAlpha(is_buff and 0.45 or 1)
    end
    refresh_filter_btns()

    local function switch_filter(new_filter)
        if entry.filter == new_filter then return end
        StaticPopupDialogs["LSTWEEKS_FILTER_SWITCH"] = {
            text     = "Changing aura type will clear the whitelist for \"" .. entry.name .. "\". Continue?",
            button1  = "Yes",
            button2  = "Cancel",
            OnAccept = function()
                entry.filter    = new_filter
                entry.whitelist = {}
                refresh_filter_btns()
                local frame = M.frames[show_key]
                if frame then
                    frame.update_params.filter = new_filter
                    M.update_auras(frame, show_key, "move", "timer", "bg", "scale", "spacing", new_filter)
                end
                if p._rebuild_whitelist then p._rebuild_whitelist() end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("LSTWEEKS_FILTER_SWITCH")
    end

    buff_btn:SetScript("OnClick",   function() switch_filter("HELPFUL") end)
    debuff_btn:SetScript("OnClick", function() switch_filter("HARMFUL") end)

    -- ----------------------------------------------------------------
    -- WHITELIST PANEL
    -- ----------------------------------------------------------------
    local WL_X  = 10
    local WL_Y  = -130
    local WL_W  = 280
    local WL_H  = 280
    local ROW_H = 22

    local wl_frame = CreateFrame("Frame", nil, p, "BackdropTemplate")
    wl_frame:SetPoint("TOPLEFT", p, "TOPLEFT", WL_X, WL_Y)
    wl_frame:SetSize(WL_W, WL_H)
    wl_frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = true, tileSize = 8, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    wl_frame:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
    wl_frame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)

    local wl_title = wl_frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wl_title:SetPoint("TOP", wl_frame, "TOP", 0, -5)
    wl_title:SetText("Whitelist")

    local wl_scroll = CreateFrame("ScrollFrame", nil, wl_frame, "UIPanelScrollFrameTemplate")
    wl_scroll:SetPoint("TOPLEFT",     wl_frame, "TOPLEFT",     4, -20)
    wl_scroll:SetPoint("BOTTOMRIGHT", wl_frame, "BOTTOMRIGHT", -24, 4)

    local wl_content = CreateFrame("Frame", nil, wl_scroll)
    wl_content:SetWidth(WL_W - 28)
    wl_content:SetHeight(1)
    wl_scroll:SetScrollChild(wl_content)

    local wl_rows = {}

    local function rebuild_whitelist()
        for _, row in ipairs(wl_rows) do row:Hide() end

        local row_y   = 0
        local row_idx = 0
        for spell_id, spell_name in pairs(entry.whitelist or {}) do
            row_idx = row_idx + 1
            local row = wl_rows[row_idx]
            if not row then
                row = CreateFrame("Frame", nil, wl_content)
                row:SetHeight(ROW_H)

                row.lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.lbl:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.lbl:SetWidth(WL_W - 70)
                row.lbl:SetJustifyH("LEFT")
                row.lbl:SetWordWrap(false)

                row.id_lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.id_lbl:SetPoint("LEFT", row.lbl, "RIGHT", 4, 0)
                row.id_lbl:SetTextColor(0.5, 0.5, 0.5)

                row.del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
                row.del:SetSize(16, 16)
                row.del:SetPoint("RIGHT", row, "RIGHT", -2, 0)

                wl_rows[row_idx] = row
            end

            row:SetWidth(wl_content:GetWidth())
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", wl_content, "TOPLEFT", 0, -row_y)
            row.lbl:SetText(spell_name)
            row.id_lbl:SetText("[" .. tostring(spell_id) .. "]")

            local sid = spell_id
            row.del:SetScript("OnClick", function()
                entry.whitelist[sid] = nil
                rebuild_whitelist()
            end)

            row:Show()
            row_y = row_y + ROW_H
        end

        wl_content:SetHeight(math.max(1, row_y))

        if row_idx == 0 then
            if not wl_content._empty_lbl then
                wl_content._empty_lbl = wl_content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                wl_content._empty_lbl:SetPoint("CENTER", wl_content, "CENTER", 0, -20)
                wl_content._empty_lbl:SetText("Whitelist is empty.\nUse Capture or Add ID below.")
            end
            wl_content._empty_lbl:Show()
        else
            if wl_content._empty_lbl then wl_content._empty_lbl:Hide() end
        end
    end

    p._rebuild_whitelist = rebuild_whitelist

    -- ----------------------------------------------------------------
    -- MANUAL SPELL ID ENTRY
    -- ----------------------------------------------------------------
    local add_lbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    add_lbl:SetPoint("TOPLEFT", wl_frame, "BOTTOMLEFT", 0, -10)
    add_lbl:SetText("Add by Spell ID:")

    local id_box = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    id_box:SetSize(90, 22)
    id_box:SetPoint("LEFT", add_lbl, "RIGHT", 8, 0)
    id_box:SetNumeric(true)
    id_box:SetMaxLetters(8)
    id_box:SetAutoFocus(false)

    local add_id_btn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    add_id_btn:SetSize(50, 22)
    add_id_btn:SetPoint("LEFT", id_box, "RIGHT", 4, 0)
    add_id_btn:SetText("Add")
    add_id_btn:SetScript("OnClick", function()
        local raw = id_box:GetNumber()
        if raw and raw > 0 then
            local sid = raw
            if not entry.whitelist then entry.whitelist = {} end
            if not entry.whitelist[sid] then
                local display_name = "Spell " .. tostring(sid)
                if M._aura_map then
                    for _, ae in pairs(M._aura_map) do
                        if ae.spell_id == sid and ae.name and not issecretvalue(ae.name) then
                            display_name = tostring(ae.name)
                            break
                        end
                    end
                end
                entry.whitelist[sid] = display_name
                rebuild_whitelist()
            end
            id_box:SetText("")
        end
    end)
    id_box:SetScript("OnEnterPressed", function() add_id_btn:Click() end)

    -- ----------------------------------------------------------------
    -- CAPTURE MODE
    -- ----------------------------------------------------------------
    local CAP_INTERVAL = 1.0
    local CAP_MAX      = 20

    local cap_active = false
    local cap_timer  = nil

    local CAP_X   = WL_X + WL_W + 16
    local CAP_W   = 275
    local CAP_TOP = 10   -- aligns with TREE_TOP_Y in af_gui.lua
    local CAP_H   = 480   -- TREE_H from af_gui.lua

    local cap_frame = CreateFrame("Frame", nil, p, "BackdropTemplate")
    cap_frame:SetPoint("TOPLEFT", p, "TOPLEFT", CAP_X, CAP_TOP)
    cap_frame:SetSize(CAP_W, CAP_H)
    cap_frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = true, tileSize = 8, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    cap_frame:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
    cap_frame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)

    local cap_header = cap_frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cap_header:SetPoint("TOP", cap_frame, "TOP", 0, -5)
    cap_header:SetText("Captured Auras")

    local cap_status = cap_frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cap_status:SetPoint("TOPRIGHT", cap_frame, "TOPRIGHT", -6, -5)
    cap_status:SetText("")

    local cap_scroll = CreateFrame("ScrollFrame", nil, cap_frame, "UIPanelScrollFrameTemplate")
    cap_scroll:SetPoint("TOPLEFT",     cap_frame, "TOPLEFT",     4, -20)
    cap_scroll:SetPoint("BOTTOMRIGHT", cap_frame, "BOTTOMRIGHT", -24, 4)

    local cap_content = CreateFrame("Frame", nil, cap_scroll)
    cap_content:SetWidth(CAP_W - 28)
    cap_content:SetHeight(1)
    cap_scroll:SetScrollChild(cap_content)

    local cap_rows  = {}
    local cap_auras = {}

    local function rebuild_cap_list()
        for _, row in ipairs(cap_rows) do row:Hide() end
        local row_y = 0
        for idx, item in ipairs(cap_auras) do
            local row = cap_rows[idx]
            if not row then
                row = CreateFrame("Button", nil, cap_content)
                row:SetHeight(ROW_H)
                row:SetScript("OnEnter", function(s) s.lbl:SetTextColor(1, 1, 0.6) end)
                row:SetScript("OnLeave", function(s) s.lbl:SetTextColor(1, 1, 1) end)

                row.lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.lbl:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.lbl:SetWidth(CAP_W - 50)
                row.lbl:SetJustifyH("LEFT")
                row.lbl:SetWordWrap(false)

                row.id_lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.id_lbl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                row.id_lbl:SetTextColor(0.5, 0.5, 0.5)

                cap_rows[idx] = row
            end

            row:SetWidth(cap_content:GetWidth())
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", cap_content, "TOPLEFT", 0, -row_y)
            row.lbl:SetText(item.name)
            row.id_lbl:SetText(tostring(item.spell_id))

            local sid   = item.spell_id
            local sname = item.name
            row:SetScript("OnClick", function()
                if not entry.whitelist then entry.whitelist = {} end
                entry.whitelist[sid] = sname
                rebuild_whitelist()
            end)

            row:Show()
            row_y = row_y + ROW_H
        end
        cap_content:SetHeight(math.max(1, row_y))

        if #cap_auras == 0 then
            if not cap_content._empty_lbl then
                cap_content._empty_lbl = cap_content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                cap_content._empty_lbl:SetPoint("CENTER", cap_content, "CENTER", 0, -20)
                cap_content._empty_lbl:SetText("Enable Capture Mode\nto see active auras.")
            end
            cap_content._empty_lbl:Show()
        else
            if cap_content._empty_lbl then cap_content._empty_lbl:Hide() end
        end
    end

    local function do_capture_scan()
        local want_helpful = (entry.filter == "HELPFUL")
        local seen = {}
        for _, ae in pairs(M._aura_map or {}) do
            if ae.is_helpful == want_helpful and ae.spell_id and not issecretvalue(ae.spell_id) then
                local sid   = ae.spell_id
                local sname = (ae.name and not issecretvalue(ae.name)) and tostring(ae.name) or ("Spell " .. tostring(sid))
                if not seen[sid] then seen[sid] = sname end
            end
        end
        -- Accumulate: add newly seen auras but never remove ones that expired.
        -- Transient auras (short buffs, debuffs) would disappear before the user
        -- can click them if we pruned on every tick.
        local existing_ids = {}
        for _, item in ipairs(cap_auras) do existing_ids[item.spell_id] = true end
        for sid, sname in pairs(seen) do
            if not existing_ids[sid] and #cap_auras < CAP_MAX then
                table.insert(cap_auras, { spell_id = sid, name = sname })
                existing_ids[sid] = true
            end
        end
        rebuild_cap_list()
    end

    local cap_checkbox_container, cap_checkbox

    local function stop_capture()
        cap_active = false
        if cap_timer then cap_timer:Cancel(); cap_timer = nil end
        cap_status:SetText("")
        if cap_checkbox and cap_checkbox.SetChecked then cap_checkbox:SetChecked(false) end
    end

    local function start_capture()
        if cap_active then return end
        cap_active = true
        cap_auras  = {}
        do_capture_scan()
        cap_timer = C_Timer.NewTicker(CAP_INTERVAL, function()
            cap_status:SetText(string.format("Capturing: %d/%d", #cap_auras, CAP_MAX))
            do_capture_scan()
            if #cap_auras >= CAP_MAX then stop_capture() end
        end)
    end

    cap_checkbox_container, cap_checkbox = addon.CreateCheckbox(p, "Capture Mode", false,
        function(is_checked)
            if is_checked then start_capture() else stop_capture() end
        end
    )
    cap_checkbox_container:SetPoint("TOPLEFT", filter_lbl, "BOTTOMLEFT", 0, -14)

    local cap_hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cap_hint:SetPoint("LEFT", cap_checkbox_container, "RIGHT", 8, 0)
    cap_hint:SetText(string.format("(stops on close or %d auras)", CAP_MAX))

    p:HookScript("OnHide", function() if cap_active then stop_capture() end end)

    rebuild_whitelist()
    rebuild_cap_list()
end
