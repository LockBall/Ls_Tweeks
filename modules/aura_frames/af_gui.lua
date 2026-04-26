-- Settings UI for the Aura Frames module, registered as a sidebar category in the main window.
-- BuildSettings() creates two tabs:
-- 1) General (global toggles and thresholds)
-- 2) Frames (a tree sidebar listing each category with a per-category settings grid to the right).

local addon_name, addon = ...

local GetTime       = GetTime
local issecretvalue = issecretvalue

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

    return addon.CreateDropdown(name, parent, labelText, options, {
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

-- growth direction dropdown
-- Replaces the deprecated UIDropDownMenu API with a custom popup list.
function M.CreateDirectionDropdown(name, parent, labelText, db_key, callback)
    local dir_values = { "RIGHT", "LEFT", "DOWN", "UP" }
    local options = {}
    for _, dir in ipairs(dir_values) do
        options[#options + 1] = { value = dir, text = dir }
    end

    return addon.CreateDropdown(name, parent, labelText, options, {
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
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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

    local tabs, panels = {}, {}

    -- Category definitions. Keys follow pattern <prefix>_<cat> where cat = name:lower().
    -- prefixes: show, move, timer, bg, scale, spacing  |  cats: static, debuff, short, long
    local function make_cat(name, opts)
        local k = name:lower()
        return {
            name        = name,
            show_key    = "show_"    .. k,
            move_key    = "move_"    .. k,
            timer_key   = "timer_"   .. k,
            bg_key      = "bg_"      .. k,
            scale_key   = "scale_"   .. k,
            spacing_key = "spacing_" .. k,
            is_debuff   = opts and opts.is_debuff,
        }
    end

    local frames_data = {
        make_cat("Static"),
        make_cat("Debuff", { is_debuff = true }),
        make_cat("Short"),
        make_cat("Long"),
    }

    local tab_data = {
        { name = "General", is_general  = true },
        { name = "Frames",  is_frames   = true },
        { name = "Aura ID", is_aura_id  = true },
    }

    local build_category_tab  -- forward declaration so build_frames_tab can reference it

    -- forward declarations needed across panel builders
    local build_custom_settings_panel
    local build_custom_child_panel

    local function build_frames_tab(p)
        -- Left tree list sidebar
        local TREE_W         = 140
        local TREE_H         = 480
        local TREE_GAP_LEFT  = 2
        local TREE_GAP_RIGHT = 10
        local TREE_TOP_Y     = 10
        local PAD            = 10
        local ROW_H          = 22
        local ROW_GAP        = 2
        local ARROW_W        = 18
        local INDENT_CHILD   = 12

        local tree_frame = CreateFrame("Frame", nil, p, "BackdropTemplate")
        tree_frame:SetPoint("TOPLEFT", p, "TOPLEFT", TREE_GAP_LEFT, TREE_TOP_Y)
        tree_frame:SetSize(TREE_W, TREE_H)
        tree_frame:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = true, tileSize = 8, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        tree_frame:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
        tree_frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
        addon.alpha_affected_frames = addon.alpha_affected_frames or {}
        table.insert(addon.alpha_affected_frames, { frame = tree_frame, r = 0.08, g = 0.08, b = 0.08 })
        if addon.apply_interface_alpha then addon.apply_interface_alpha() end

        -- Right content area
        local content = CreateFrame("Frame", nil, p)
        content:SetPoint("TOPLEFT",     p, "TOPLEFT",     TREE_GAP_LEFT + TREE_W + TREE_GAP_RIGHT, 0)
        content:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
        content:SetFrameLevel(p:GetFrameLevel() + 1)

        -- Lazy-built content panels keyed by node string
        local node_panels   = {}
        local current_panel = nil

        local function show_node(key, builder)
            if current_panel then current_panel:Hide() end
            if not node_panels[key] then
                local pnl = CreateFrame("Frame", nil, content)
                pnl:SetAllPoints(content)
                pnl:SetFrameLevel(content:GetFrameLevel() + 1)
                builder(pnl)
                node_panels[key] = pnl
            end
            node_panels[key]:Show()
            current_panel = node_panels[key]
            if M.db then M.db.last_frames_node = key end
        end

        -- Invalidate a cached panel so it is rebuilt next time it is shown.
        -- Used after a custom frame rename/delete to force fresh content.
        local function invalidate_node(key)
            if node_panels[key] then
                node_panels[key]:Hide()
                node_panels[key]:SetParent(nil)
                node_panels[key] = nil
            end
        end

        -- Selection tracking
        local selected_fs = nil
        local SEL_COLOR   = { 1, 0.82, 0 }
        local NORM_COLOR  = { 1, 1,    1 }
        local HOVER_COLOR = { 1, 1,  0.6 }

        local function set_selected(fs)
            if selected_fs then selected_fs:SetTextColor(unpack(NORM_COLOR)) end
            selected_fs = fs
            if fs then fs:SetTextColor(unpack(SEL_COLOR)) end
        end

        -- Base tree button helper
        local function make_tree_btn(parent_f, label, x, y, w)
            local btn = CreateFrame("Button", nil, parent_f)
            btn:SetSize(w, ROW_H)
            btn:SetPoint("TOPLEFT", parent_f, "TOPLEFT", x, y)
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", btn, "LEFT", 4, 0)
            fs:SetText(label)
            btn:SetScript("OnEnter", function()
                if fs ~= selected_fs then fs:SetTextColor(unpack(HOVER_COLOR)) end
            end)
            btn:SetScript("OnLeave", function()
                if fs ~= selected_fs then fs:SetTextColor(unpack(NORM_COLOR)) end
            end)
            return btn, fs
        end

        -- Tracks all custom tree row objects so we can rebuild them.
        local custom_row_frames = {}
        -- Tracks the current y cursor so + Custom button can be repositioned.
        local add_btn_ref = nil  -- set after initial build

        local node_fs_map = {}

        -- ----------------------------------------------------------------
        -- Rebuild function: clears and redraws the entire tree contents.
        -- Called once at build time and again after add/delete/rename.
        -- ----------------------------------------------------------------
        local function rebuild_tree()
            -- Remove previous custom rows
            for _, f in ipairs(custom_row_frames) do
                f:Hide()
                f:SetParent(nil)
            end
            custom_row_frames = {}

            -- Start y below preset rows. Preset rows are static, so we compute
            -- their total height once: 4 cats × (ROW_H + ROW_GAP) = 4 × 24.
            local preset_rows_height = #frames_data * (ROW_H + ROW_GAP)
            local y = -PAD - preset_rows_height

            -- ---- Custom frame rows ----
            if M.db and M.db.custom_frames then
                for _, entry in ipairs(M.db.custom_frames) do
                    local id        = entry.id
                    local cat_key   = id           -- node key for settings panel
                    local child_key = id .. "_custom"  -- node key for child (whitelist) panel

                    -- Track expand state per custom entry (ephemeral)
                    M._custom_expanded = M._custom_expanded or {}
                    if M._custom_expanded[id] == nil then M._custom_expanded[id] = true end

                    -- Expand/collapse arrow
                    local arrow = CreateFrame("Button", nil, tree_frame, "UIPanelButtonTemplate")
                    arrow:SetSize(ARROW_W, ARROW_W)
                    arrow:SetPoint("TOPLEFT", tree_frame, "TOPLEFT", PAD, y)
                    arrow:SetNormalFontObject("GameFontNormalLarge")
                    local arrow_fs = arrow:GetFontString()
                    arrow_fs:SetText(M._custom_expanded[id] and "-" or "+")
                    table.insert(custom_row_frames, arrow)

                    -- Name button (with rename EditBox on click if already selected)
                    local cat_x = PAD + ARROW_W + 2
                    local cat_w = TREE_W - cat_x - PAD - 20  -- leave room for × button
                    local cat_btn = CreateFrame("Button", nil, tree_frame)
                    cat_btn:SetSize(cat_w, ROW_H)
                    cat_btn:SetPoint("TOPLEFT", tree_frame, "TOPLEFT", cat_x, y)
                    local cat_fs = cat_btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    cat_fs:SetPoint("LEFT", cat_btn, "LEFT", 4, 0)
                    cat_fs:SetText(entry.name)
                    cat_fs:SetFont(cat_fs:GetFont(), select(2, cat_fs:GetFont()) or 11, "OUTLINE")
                    cat_btn:SetScript("OnEnter", function()
                        if cat_fs ~= selected_fs then cat_fs:SetTextColor(unpack(HOVER_COLOR)) end
                    end)
                    cat_btn:SetScript("OnLeave", function()
                        if cat_fs ~= selected_fs then cat_fs:SetTextColor(unpack(NORM_COLOR)) end
                    end)
                    node_fs_map[cat_key] = cat_fs
                    table.insert(custom_row_frames, cat_btn)

                    -- Inline rename EditBox (hidden by default; shown on double-click or rename trigger)
                    local rename_box = CreateFrame("EditBox", nil, tree_frame, "InputBoxTemplate")
                    rename_box:SetSize(cat_w - 4, ROW_H - 2)
                    rename_box:SetPoint("TOPLEFT", tree_frame, "TOPLEFT", cat_x + 4, y - 1)
                    rename_box:SetAutoFocus(true)
                    rename_box:SetMaxLetters(32)
                    rename_box:Hide()
                    table.insert(custom_row_frames, rename_box)

                    local function commit_rename()
                        local new_name = rename_box:GetText():match("^%s*(.-)%s*$")
                        rename_box:Hide()
                        cat_btn:Show()
                        if new_name and new_name ~= "" then
                            entry.name = new_name
                            cat_fs:SetText(new_name)
                            -- Update the WoW frame title bars
                            local frame = M.frames["show_" .. id]
                            if frame then
                                if frame.title_bar then
                                    local tb_fs = frame.title_bar:GetFontString()
                                    if tb_fs then tb_fs:SetText(new_name) end
                                end
                                if frame.bottom_title_bar then
                                    local btb_fs = frame.bottom_title_bar:GetFontString()
                                    if btb_fs then btb_fs:SetText(new_name) end
                                end
                            end
                            -- Rebuild cached settings panel so its header reflects the new name
                            invalidate_node(cat_key)
                        end
                    end

                    rename_box:SetScript("OnEnterPressed", commit_rename)
                    rename_box:SetScript("OnEscapePressed", function()
                        rename_box:Hide()
                        cat_btn:Show()
                    end)

                    -- Single-click: select; double-click: open rename
                    local last_click_time = 0
                    cat_btn:SetScript("OnClick", function()
                        local now = GetTime()
                        if (now - last_click_time) < 0.4 then
                            -- Double-click: open inline rename
                            rename_box:SetText(entry.name)
                            rename_box:Show()
                            rename_box:SetFocus()
                            cat_btn:Hide()
                        else
                            set_selected(cat_fs)
                            show_node(cat_key, function(pnl) build_custom_settings_panel(pnl, entry) end)
                        end
                        last_click_time = now
                    end)

                    -- × delete button (appears on hover of the row)
                    local del_btn = CreateFrame("Button", nil, tree_frame, "UIPanelCloseButton")
                    del_btn:SetSize(16, 16)
                    del_btn:SetPoint("TOPRIGHT", tree_frame, "TOPLEFT", TREE_W - PAD, y - 3)
                    del_btn:SetAlpha(0)
                    del_btn:SetScript("OnEnter", function() del_btn:SetAlpha(1) end)
                    del_btn:SetScript("OnLeave", function() del_btn:SetAlpha(0) end)
                    cat_btn:HookScript("OnEnter", function() del_btn:SetAlpha(1) end)
                    cat_btn:HookScript("OnLeave", function() del_btn:SetAlpha(0) end)
                    table.insert(custom_row_frames, del_btn)

                    local del_entry = entry  -- capture for closure
                    del_btn:SetScript("OnClick", function()
                        StaticPopupDialogs["LSTWEEKS_DEL_CUSTOM"] = {
                            text         = 'Delete custom frame "' .. del_entry.name .. '"?',
                            button1      = "Delete",
                            button2      = "Cancel",
                            OnAccept     = function()
                                -- If it was selected, clear current panel
                                if current_panel then current_panel:Hide(); current_panel = nil end
                                invalidate_node(del_entry.id)
                                invalidate_node(del_entry.id .. "_custom")
                                M.destroy_custom_frame(del_entry.id)
                                rebuild_tree()
                                -- Select first preset as fallback
                                if #frames_data > 0 then
                                    local d = frames_data[1]
                                    local c = d.show_key:sub(6)
                                    set_selected(node_fs_map[c])
                                    show_node(c, function(pnl2) build_category_tab(pnl2, d) end)
                                end
                            end,
                            timeout      = 0,
                            whileDead    = true,
                            hideOnEscape = true,
                        }
                        StaticPopup_Show("LSTWEEKS_DEL_CUSTOM")
                    end)

                    y = y - (ROW_H + ROW_GAP)

                    -- Child: Custom (whitelist panel)
                    local child_x = PAD + ARROW_W + INDENT_CHILD
                    local child_w = TREE_W - child_x - PAD
                    local child_btn = CreateFrame("Button", nil, tree_frame)
                    child_btn:SetSize(child_w, ROW_H)
                    child_btn:SetPoint("TOPLEFT", tree_frame, "TOPLEFT", child_x, y)
                    local child_fs = child_btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    child_fs:SetPoint("LEFT", child_btn, "LEFT", 4, 0)
                    child_fs:SetText("Custom")
                    child_btn:SetScript("OnEnter", function()
                        if child_fs ~= selected_fs then child_fs:SetTextColor(unpack(HOVER_COLOR)) end
                    end)
                    child_btn:SetScript("OnLeave", function()
                        if child_fs ~= selected_fs then child_fs:SetTextColor(unpack(NORM_COLOR)) end
                    end)
                    child_btn:SetShown(M._custom_expanded[id])
                    node_fs_map[child_key] = child_fs
                    table.insert(custom_row_frames, child_btn)

                    local child_entry = entry
                    child_btn:SetScript("OnClick", function()
                        set_selected(child_fs)
                        show_node(child_key, function(pnl) build_custom_child_panel(pnl, child_entry) end)
                    end)

                    if M._custom_expanded[id] then
                        y = y - (ROW_H + ROW_GAP)
                    end

                    -- Wire expand/collapse
                    arrow:SetScript("OnClick", function()
                        M._custom_expanded[id] = not M._custom_expanded[id]
                        arrow_fs:SetText(M._custom_expanded[id] and "-" or "+")
                        child_btn:SetShown(M._custom_expanded[id])
                        if not M._custom_expanded[id] then
                            y = y + (ROW_H + ROW_GAP)
                        end
                        -- Reposition + Custom button
                        if add_btn_ref then
                            -- Full rebuild is simplest here to avoid offset drift
                            rebuild_tree()
                        end
                    end)
                end
            end

            -- ---- + Custom button ----
            local max_reached = M.db and M.db.custom_frames
                and #M.db.custom_frames >= (M.MAX_CUSTOM_FRAMES or 4)

            if add_btn_ref then
                add_btn_ref:ClearAllPoints()
                add_btn_ref:SetPoint("TOPLEFT", tree_frame, "TOPLEFT", PAD, y - 4)
                add_btn_ref:SetEnabled(not max_reached)
                add_btn_ref:SetAlpha(max_reached and 0.4 or 1)
            else
                local add_btn = CreateFrame("Button", nil, tree_frame, "UIPanelButtonTemplate")
                add_btn:SetSize(TREE_W - PAD * 2, ROW_H)
                add_btn:SetPoint("TOPLEFT", tree_frame, "TOPLEFT", PAD, y - 4)
                add_btn:SetText("+ Custom")
                add_btn:SetEnabled(not max_reached)
                add_btn:SetAlpha(max_reached and 0.4 or 1)
                add_btn:SetScript("OnClick", function()
                    if InCombatLockdown() then
                        print("|cFFFFFF00LsTweaks:|r Cannot create custom frames in combat.")
                        return
                    end
                    local new_entry = M.spawn_custom_frame()
                    if not new_entry then return end
                    rebuild_tree()
                    -- Auto-select the new entry's settings panel
                    local nk = new_entry.id
                    local nfs = node_fs_map[nk]
                    if nfs then set_selected(nfs) end
                    show_node(nk, function(pnl) build_custom_settings_panel(pnl, new_entry) end)
                end)
                add_btn_ref = add_btn
            end
        end  -- rebuild_tree

        -- ----------------------------------------------------------------
        -- PRESET ROWS (static rows, built once above the custom section)
        -- ----------------------------------------------------------------
        local y = -PAD
        for _, data in ipairs(frames_data) do
            local cat = data.show_key:sub(6)

            -- Preset categories have no children now, so no expand arrow.
            local cat_x = PAD
            local cat_w = TREE_W - cat_x - PAD
            local cat_btn, cat_fs = make_tree_btn(tree_frame, data.name, cat_x, y, cat_w)
            cat_fs:SetFont(cat_fs:GetFont(), select(2, cat_fs:GetFont()) or 11, "OUTLINE")
            node_fs_map[cat] = cat_fs
            cat_btn:SetScript("OnClick", function()
                set_selected(cat_fs)
                show_node(cat, function(pnl) build_category_tab(pnl, data) end)
            end)

            y = y - (ROW_H + ROW_GAP)
        end

        -- Build initial custom rows + + Custom button
        rebuild_tree()

        -- ----------------------------------------------------------------
        -- Restore last selected node
        -- ----------------------------------------------------------------
        local last    = (M.db and M.db.last_frames_node) or "static"
        local restored = false

        -- Check preset nodes
        for _, data in ipairs(frames_data) do
            local cat = data.show_key:sub(6)
            if last == cat then
                set_selected(node_fs_map[cat])
                show_node(cat, function(pnl) build_category_tab(pnl, data) end)
                restored = true
                break
            end
        end

        -- Check custom nodes
        if not restored and M.db and M.db.custom_frames then
            for _, entry in ipairs(M.db.custom_frames) do
                if last == entry.id then
                    local fs = node_fs_map[entry.id]
                    if fs then set_selected(fs) end
                    show_node(entry.id, function(pnl) build_custom_settings_panel(pnl, entry) end)
                    restored = true
                    break
                elseif last == entry.id .. "_custom" then
                    local fs = node_fs_map[entry.id .. "_custom"]
                    if fs then set_selected(fs) end
                    show_node(last, function(pnl) build_custom_child_panel(pnl, entry) end)
                    restored = true
                    break
                end
            end
        end

        -- Fallback to first preset
        if not restored and #frames_data > 0 then
            local data = frames_data[1]
            local cat  = data.show_key:sub(6)
            set_selected(node_fs_map[cat])
            show_node(cat, function(pnl) build_category_tab(pnl, data) end)
        end
    end  -- build_frames_tab

    local function build_aura_id_tab(p)
        local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -16)
        lbl:SetText("Show spell/aura/buff IDs in icon tooltips.")

        local spell_id_container, spell_id_btn, _ = addon.CreateCheckbox(p, "Show Aura / Spell ID in Tooltip", M.db.show_spell_id == true,
            function(is_checked)
                M.db.show_spell_id = is_checked
            end
        )
        spell_id_container:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
        M.controls.show_spell_id_checkbox = spell_id_btn
    end

    local function build_general_tab(p)
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
        local enable_blizz_buffs_container, enable_blizz_buffs_cb, _ = addon.CreateCheckbox(enable_panel, "Buff", M.db.enable_blizz_buffs,
            function(is_checked)
                M.db.enable_blizz_buffs = is_checked
                M.toggle_blizz_buffs(not is_checked)
            end
        )
        enable_blizz_buffs_container:SetPoint("CENTER", enable_panel, "CENTER", -40, -5)
        M.controls["enable_blizz_buffs"] = enable_blizz_buffs_cb

        -- Blizzard Debuff Frame Checkbox (checked = enabled)
        local enable_blizz_debuffs_container, enable_blizz_debuffs_cb, _ = addon.CreateCheckbox(
            enable_panel,
            "Debuff",
            M.db.enable_blizz_debuffs,
            function(is_checked)
                M.db.enable_blizz_debuffs = is_checked
                M.toggle_blizz_debuffs(not is_checked)
            end
        )
        enable_blizz_debuffs_container:SetPoint("CENTER", enable_panel, "CENTER", 35, -5)
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
        local outlines_container, outlines_btn, _ = addon.CreateCheckbox(p, "Show Bar Section Outlines", M.db.show_bar_section_outlines == true,
            function(is_checked)
                M.db.show_bar_section_outlines = is_checked
                if addon.aura_frames and addon.aura_frames.refresh_section_outlines then
                    addon.aura_frames.refresh_section_outlines()
                end
            end
        )
        outlines_container:SetPoint("TOPLEFT", threshold, "BOTTOMLEFT", 0, -18)
        M.controls.show_bar_section_outlines_checkbox = outlines_btn

        -- reset panel
        local resetPanel = addon.CreateGlobalReset(p, M.db, M.defaults)
        resetPanel:SetPoint("TOPLEFT", outlines_container, "BOTTOMLEFT", 0, -16)
    end

    -- ============================================================================
    -- CUSTOM SETTINGS PANEL
    -- Same 4-column grid layout as build_category_tab but reads/writes from entry table.
    build_custom_settings_panel = function(p, entry)
        local id        = entry.id
        local show_key  = "show_" .. id
        local filter    = (entry.filter == "HARMFUL") and "HARMFUL" or "HELPFUL"

        local function update()
            local frame = M.frames[show_key]
            if frame then
                M.update_auras(frame, show_key, "move", "timer", "bg", "scale", "spacing", filter)
            end
        end

        -- Grid (identical constants to build_category_tab)
        local col_gap    = 150
        local col_width  = 190
        local col_offset = -20
        local row_gap    = 20
        local grid = {
            [1] = col_offset,
            [2] = col_gap + col_offset,
            [3] = col_gap * 2 + col_offset,
            [4] = col_gap * 3 + col_offset,
            col_width  = col_width,
            col_align  = { "center", "center", "center", "center" },
            row_start  = 10,
            row_gap    = row_gap,
            row_heights = { 130, 60, 60, 110, 110 },
            reset_btn_width = 110,
            offsets = { default = 0, dropdown = 8, picker = 4 },
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

        -- Helper: checkbox bound to entry table
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

        -- Helper: color picker bound to entry table
        local function bound_picker(key, has_alpha, label, row, column)
            -- CreateColorPicker expects db table + key; pass entry as db with a flat key
            local picker = addon.CreateColorPicker(p, entry, key, has_alpha, label, M.CUSTOM_FRAME_TEMPLATE, update)
            place_at(picker, row, column, "picker")
            return picker
        end

        -- Row 1: move, x pos, y pos, width
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

        -- Row 2: enable, frame BG, BG color
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

        -- Row 3: bar mode, bar color, bar BG color, growth
        bound_cb("Bar Mode", "bar_mode", 3, 1)
        bound_picker("color", true, "Bar Color", 3, 2)
        bound_picker("bar_bg_color", true, "Bar BG Color", 3, 3)

        local dir_values = { "RIGHT", "LEFT", "DOWN", "UP" }
        local dir_options = {}
        for _, dir in ipairs(dir_values) do dir_options[#dir_options + 1] = { value = dir, text = dir } end
        local growth_dd = addon.CreateDropdown(addon_name..id.."Growth", p, "Growth Direction", dir_options, {
            width = 106,
            get_value = function() return entry.growth or "DOWN" end,
            on_select = function(value) entry.growth = value; update() end,
        })
        place_at(growth_dd, 3, 4, "dropdown", { y_offset = -math.floor((grid.row_heights[3] - 24) / 2) })
        add_row_separator(3)

        -- Row 4: timer text, bold, font, font size
        local timer_text_container = bound_cb("Timer Text", "timer", 4, 1)
        local timer_bold_container = bound_cb("Timer Bold", "timer_number_font_bold", 4, 1, function()
            if M.apply_number_font_to_all then M.apply_number_font_to_all() end; update()
        end)
        timer_bold_container:ClearAllPoints()
        timer_bold_container:SetPoint("TOPLEFT", timer_text_container, "BOTTOMLEFT", 0, -4)

        local font_options = {}
        local defs = M.get_number_font_options and M.get_number_font_options() or {}
        for _, def in ipairs(defs) do
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

        local font_size_slider = addon.CreateSliderWithBox(addon_name..id.."TimerFontSize", p, "Timer Font Size", 8, 14, 0.5,
            entry, "timer_number_font_size", M.CUSTOM_FRAME_TEMPLATE, function()
                if M.apply_number_font_to_all then M.apply_number_font_to_all() end; update()
            end)
        place_at(font_size_slider, 4, 3)
        add_row_separator(4)

        -- Row 5: scale, spacing, max icons
        local scale_slider = addon.CreateSliderWithBox(addon_name..id.."Scale", p, "Scale", 0.5, 2.5, 0.01, entry, "scale", M.CUSTOM_FRAME_TEMPLATE, update)
        place_at(scale_slider, 5, 1)

        local spacing_slider = addon.CreateSliderWithBox(addon_name..id.."Spacing", p, "Spacing", 0, 20, 0.1, entry, "spacing", M.CUSTOM_FRAME_TEMPLATE, update)
        place_at(spacing_slider, 5, 2)

        local max_icons_slider = addon.CreateSliderWithBox(addon_name..id.."MaxIcons", p, "Max Icons", 5, 40, 1, entry, "max_icons", M.CUSTOM_FRAME_TEMPLATE, function()
            print("|cFFFFFF00LsTweaks:|r Pool size for " .. entry.name .. " changed. Please /reload to apply.")
        end)
        place_at(max_icons_slider, 5, 4)

        -- Hook title bars to sync position sliders on drag
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
    end  -- build_custom_settings_panel

    -- ============================================================================
    -- CUSTOM CHILD PANEL (buff/debuff toggle + whitelist + capture mode)
    build_custom_child_panel = function(p, entry)
        local id       = entry.id
        local show_key = "show_" .. id

        -- Header label
        local header = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -10)
        header:SetText(entry.name .. " — Whitelist")

        -- ----------------------------------------------------------------
        -- BUFF / DEBUFF TOGGLE
        -- ----------------------------------------------------------------
        local filter_lbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        filter_lbl:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -14)
        filter_lbl:SetText("Aura Type:")

        local buff_btn  = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        local debuff_btn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        buff_btn:SetSize(70, 22)
        debuff_btn:SetSize(70, 22)
        buff_btn:SetText("Buffs")
        debuff_btn:SetText("Debuffs")
        buff_btn:SetPoint("TOPLEFT", filter_lbl, "BOTTOMLEFT", 0, -4)
        debuff_btn:SetPoint("LEFT", buff_btn, "RIGHT", 6, 0)

        local function refresh_filter_btns()
            local is_buff = (entry.filter == "HELPFUL")
            buff_btn:SetAlpha(is_buff and 1 or 0.45)
            debuff_btn:SetAlpha(is_buff and 0.45 or 1)
        end
        refresh_filter_btns()

        local function switch_filter(new_filter)
            if entry.filter == new_filter then return end
            StaticPopupDialogs["LSTWEEKS_FILTER_SWITCH"] = {
                text = "Changing aura type will clear the whitelist for \"" .. entry.name .. "\". Continue?",
                button1 = "Yes",
                button2 = "Cancel",
                OnAccept = function()
                    entry.filter   = new_filter
                    entry.whitelist = {}
                    refresh_filter_btns()
                    -- Rebuild whitelist display
                    -- We clear and rebuild the whitelist scroll by invalidating the panel.
                    -- Simplest approach: hide + rebuild inline.
                    -- The whitelist_scroll region below is rebuilt by show_node invalidation.
                    -- Since we're inside the panel, we force refresh by faking a re-show.
                    local frame = M.frames[show_key]
                    if frame then
                        frame.update_params.filter = new_filter
                        M.update_auras(frame, show_key, "move", "timer", "bg", "scale", "spacing", new_filter)
                    end
                    -- Rebuild the whitelist list in-place
                    if p._rebuild_whitelist then p._rebuild_whitelist() end
                end,
                timeout = 0, whileDead = true, hideOnEscape = true,
            }
            StaticPopup_Show("LSTWEEKS_FILTER_SWITCH")
        end

        buff_btn:SetScript("OnClick",   function() switch_filter("HELPFUL") end)
        debuff_btn:SetScript("OnClick", function() switch_filter("HARMFUL") end)

        -- ----------------------------------------------------------------
        -- WHITELIST PANEL (scrollable list of current whitelist entries)
        -- ----------------------------------------------------------------
        local WL_X     = 10
        local WL_Y     = -130
        local WL_W     = 280
        local WL_H     = 280
        local ROW_H    = 22

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
        wl_title:SetPoint("TOPLEFT", wl_frame, "TOPLEFT", 6, -5)
        wl_title:SetText("Whitelist")

        local wl_scroll = CreateFrame("ScrollFrame", nil, wl_frame, "UIPanelScrollFrameTemplate")
        wl_scroll:SetPoint("TOPLEFT",     wl_frame, "TOPLEFT",     4, -20)
        wl_scroll:SetPoint("BOTTOMRIGHT", wl_frame, "BOTTOMRIGHT", -24, 4)

        local wl_content = CreateFrame("Frame", nil, wl_scroll)
        wl_content:SetWidth(WL_W - 28)
        wl_content:SetHeight(1)
        wl_scroll:SetScrollChild(wl_content)

        -- Pool of row frames for whitelist entries
        local wl_rows = {}

        local function rebuild_whitelist()
            -- Hide all pooled rows
            for _, row in ipairs(wl_rows) do row:Hide() end

            local row_y = 0
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

        -- Expose rebuild so switch_filter can call it
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
                    -- Try to resolve a name from the current scan map
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
        local CAP_INTERVAL  = 1.0   -- scan rate while capturing (seconds)
        local CAP_TIMEOUT   = 30    -- auto-stop after N seconds
        local CAP_MAX       = 20    -- max auras to populate in active list

        local cap_active    = false
        local cap_timer     = nil
        local cap_elapsed   = 0

        -- Active aura list (right side, shows live-captured auras for selection)
        local CAP_X  = WL_X + WL_W + 16
        local CAP_W  = 260
        local CAP_H  = WL_H

        local cap_frame = CreateFrame("Frame", nil, p, "BackdropTemplate")
        cap_frame:SetPoint("TOPLEFT", p, "TOPLEFT", CAP_X, WL_Y)
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
        cap_header:SetPoint("TOPLEFT", cap_frame, "TOPLEFT", 6, -5)
        cap_header:SetText("Active Auras")

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

        local cap_rows   = {}
        local cap_auras  = {}  -- ordered list: { spell_id, name }

        local function rebuild_cap_list()
            for _, row in ipairs(cap_rows) do row:Hide() end
            local row_y = 0
            for idx, item in ipairs(cap_auras) do
                local row = cap_rows[idx]
                if not row then
                    row = CreateFrame("Button", nil, cap_content)
                    row:SetHeight(ROW_H)
                    row:SetScript("OnEnter", function(s)
                        s.lbl:SetTextColor(1, 1, 0.6)
                    end)
                    row:SetScript("OnLeave", function(s)
                        s.lbl:SetTextColor(1, 1, 1)
                    end)

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
            -- Scan from the unified map if available, else run a quick pass
            local source = M._aura_map or {}
            for _, ae in pairs(source) do
                if ae.is_helpful == want_helpful
                        and ae.spell_id
                        and not issecretvalue(ae.spell_id) then
                    local sid  = ae.spell_id
                    local sname = (ae.name and not issecretvalue(ae.name)) and tostring(ae.name) or ("Spell " .. tostring(sid))
                    if not seen[sid] then
                        seen[sid] = sname
                    end
                end
            end
            -- Rebuild cap_auras list (keep existing ordering for stability, add new entries)
            local existing_ids = {}
            for _, item in ipairs(cap_auras) do existing_ids[item.spell_id] = true end
            for sid, sname in pairs(seen) do
                if not existing_ids[sid] and #cap_auras < CAP_MAX then
                    table.insert(cap_auras, { spell_id = sid, name = sname })
                    existing_ids[sid] = true
                end
            end
            -- Remove entries no longer present
            for i = #cap_auras, 1, -1 do
                if not seen[cap_auras[i].spell_id] then
                    table.remove(cap_auras, i)
                end
            end
            rebuild_cap_list()
        end

        local cap_checkbox_container, cap_checkbox
        local function stop_capture()
            cap_active = false
            if cap_timer then cap_timer:Cancel(); cap_timer = nil end
            cap_elapsed = 0
            cap_status:SetText("")
            if cap_checkbox and cap_checkbox.SetChecked then cap_checkbox:SetChecked(false) end
        end

        local function start_capture()
            if cap_active then return end
            cap_active  = true
            cap_elapsed = 0
            cap_auras   = {}
            do_capture_scan()
            cap_timer = C_Timer.NewTicker(CAP_INTERVAL, function()
                cap_elapsed = cap_elapsed + CAP_INTERVAL
                local pct_done = #cap_auras >= CAP_MAX
                local timed_out = cap_elapsed >= CAP_TIMEOUT
                local remaining = math.max(0, CAP_TIMEOUT - cap_elapsed)
                cap_status:SetText(string.format("Cap: %d/%d | %ds", #cap_auras, CAP_MAX, remaining))
                do_capture_scan()
                if timed_out or pct_done then stop_capture() end
            end)
        end

        cap_checkbox_container, cap_checkbox = addon.CreateCheckbox(p, "Capture Mode", false,
            function(is_checked)
                if is_checked then
                    start_capture()
                else
                    stop_capture()
                end
            end
        )
        cap_checkbox_container:SetPoint("TOPLEFT", buff_btn, "BOTTOMLEFT", 0, -14)

        local cap_hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cap_hint:SetPoint("LEFT", cap_checkbox_container, "RIGHT", 8, 0)
        cap_hint:SetText(string.format("(auto-stops: %ds / %d auras)", CAP_TIMEOUT, CAP_MAX))

        -- Initial whitelist render
        rebuild_whitelist()
        rebuild_cap_list()
    end  -- build_custom_child_panel

    -- ============================================================================
    build_category_tab = function(p, data)
        local cat = data.show_key:sub(6)
        local filter = data.is_debuff and "HARMFUL" or "HELPFUL"
        local test_key = "test_aura_"..cat

        local function update() -- refreshes current category frame preview
            M.update_auras(M.frames[data.show_key], data.show_key, data.move_key, data.timer_key, data.bg_key, data.scale_key, data.spacing_key, filter)
        end

        -- Grid Layout Configuration (row/column placement for controls)
        -- col_gap  = distance between column start positions (moves columns apart/together)
        -- col_width = centering zone within each column (controls how wide the center target is)
        local col_gap    = 150  -- adjust to spread or compress columns
        local col_width  = 190  -- adjust independently from gap if needed
        local col_offset = -20  -- shift entire grid left (negative = left)
        local row_gap    = 20   -- fixed space between rows; separators sit at half this
        local grid = {
            [1] = col_offset,
            [2] = col_gap + col_offset,
            [3] = col_gap * 2 + col_offset,
            [4] = col_gap * 3 + col_offset,
            col_width = col_width,
            col_align = { "center", "center", "center", "center" },
            row_start = 10, -- y position of start of first row 
            row_gap = row_gap,
            -- row #       1    2   3   4   5
            row_heights = {130, 60, 60, 110, 110},
            reset_btn_width = 110,
            offsets = {
                default = 0,
                dropdown = 8,
                picker = 4,
            },
            content_rows = 5,
        }

        
        -- Anchors a control into the content grid. row/column index into grid.row_heights and grid[column].
        -- slot offsets the Y by grid.offsets[slot] (e.g. "dropdown", "picker"). opts: align, valign, y_offset, width.
        local function place_at(control, row, column, slot, opts)
            if not control then return end
            opts = opts or {}
            local align = opts.align or grid.col_align[column] or "left"
            local x = grid[column]
            local y = grid.row_start
            for i = 1, (row - 1) do
                y = y - (grid.row_heights[i] or grid.row_heights[#grid.row_heights])
            end
            -- valign="bottom": descend one more row height to land at the row's bottom edge
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
                    elseif label == "Test Aura" then
                        if is_checked then
                            update()
                        end
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
            local slider = addon.CreateSliderWithBox(addon_name..cat..name_suffix, p, label, min_v, max_v, step, M.db, db_key, M.defaults, on_change or update)
            return slider
        end

        -- Draw a 2px horizontal separator in the gap below the given row.
        local function add_row_separator(row)
            local line = p:CreateTexture(nil, "BACKGROUND")
            line:SetColorTexture(1, 1, 1, 0.08)
            line:SetHeight(2)
            -- Accumulate row heights to find the bottom edge of this row, then nudge up by half
            -- the row gap so the line sits centered in the space between rows.
            local y = grid.row_start
            for i = 1, row do y = y - (grid.row_heights[i] or grid.row_heights[#grid.row_heights]) end
            line:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y + math.floor(grid.row_gap / 2))
            -- Width: right edge of col 4 minus 12px to avoid touching the outer frame border.
            line:SetWidth(grid[4] + grid.col_width - 12)
        end

        -- Width slider — defined early so it can be placed in Row 1.
        local width_slider = addon.CreateSliderWithBox(
            addon_name..cat.."WidthSlider",
            p,
            "Width",
            180, 800, 1,
            M.db, "width_"..cat, M.defaults
        )
        width_slider.slider:HookScript("OnValueChanged", function(_, value)
            local f = M.frames[data.show_key]
            if not f then return end
            f:SetWidth(math.floor(value + 0.5))
            update()
        end)
        M.controls["width_slider_"..cat] = width_slider

        -- X/Y Position sliders — defined early so Row 1 and move_reset can reference them.
        local function update_frame_position()
            local pos = M.db.positions[cat]
            local f = M.frames[data.show_key]
            if f and pos then
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", UIParent, "CENTER", pos.x or 0, pos.y or 0)
            end
        end

        local x_slider = addon.CreateSliderWithBox(
            addon_name..cat.."XPosSlider",
            p,
            "X Position",
            -1000, 1000, 1,
            M.db.positions[cat], "x", M.defaults.positions[cat]
        )
        x_slider.slider:HookScript("OnValueChanged", update_frame_position)
        M.controls["x_pos_slider_"..cat] = x_slider

        local y_slider = addon.CreateSliderWithBox(
            addon_name..cat.."YPosSlider",
            p,
            "Y Position",
            -1000, 1000, 1,
            M.db.positions[cat], "y", M.defaults.positions[cat]
        )
        y_slider.slider:HookScript("OnValueChanged", update_frame_position)
        M.controls["y_pos_slider_"..cat] = y_slider

        -- Row 1

        local function uncheck_test_aura()
            if M.db[test_key] then
                M.db[test_key] = false
                local test_cb = M.controls[test_key]
                if test_cb and test_cb.SetChecked then test_cb:SetChecked(false) end
            end
        end
        local function check_enable_frame()
            if not M.db[data.show_key] then
                M.db[data.show_key] = true
                local enable_cb = M.controls[data.show_key]
                if enable_cb and enable_cb.SetChecked then enable_cb:SetChecked(true) end
            end
        end

        -- move mode
        local move_mode_container, move_cb = create_bound_checkbox("Move Mode", data.move_key, 1, 1, function(is_checked)
            if is_checked then
                -- Also check Enable Frame if not already checked
                local enable_cb = M.controls and M.controls[data.show_key]
                if enable_cb and enable_cb.SetChecked and not enable_cb:GetChecked() then
                    enable_cb:SetChecked(true)
                    M.db[data.show_key] = true
                end
            end
            update()
        end)

        place_at(x_slider, 1, 2)
        place_at(y_slider, 1, 3)
        place_at(width_slider, 1, 4)

        -- Snap to Grid / Show Grid: global toggles stacked below Move Mode
        local snap_container, snap_btn, _ = addon.CreateCheckbox(p, "Snap to Grid", M.db.snap_to_grid == true,
            function(is_checked)
                M.db.snap_to_grid = is_checked
            end
        )
        snap_container:SetPoint("TOPLEFT", move_mode_container, "BOTTOMLEFT", 0, -4)
        M.controls.snap_to_grid_checkbox = snap_btn

        local show_grid_container, show_grid_btn, _ = addon.CreateCheckbox(p, "Show Grid", M.db.show_grid == true,
            function(is_checked)
                M.db.show_grid = is_checked
                if M.set_grid_visible then M.set_grid_visible(is_checked) end
            end
        )
        show_grid_container:SetPoint("TOPLEFT", snap_container, "BOTTOMLEFT", 0, -4)
        M.controls.show_grid_checkbox = show_grid_btn

        -- move Reset: stacked below Show Grid in col 1
        local move_reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        move_reset:SetSize(grid.reset_btn_width, 22)
        move_reset:SetPoint("TOPLEFT", show_grid_container, "BOTTOMLEFT", 0, -6)
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
                f:SetPoint("TOPLEFT", UIParent, "CENTER", dPos.x, dPos.y)
                f:SetWidth(dWidth)
                update()
            end
            local xs = M.controls["x_pos_slider_"..cat]
            local ys = M.controls["y_pos_slider_"..cat]
            if xs and xs.slider then xs.slider:SetValue(dPos.x) end
            if ys and ys.slider then ys.slider:SetValue(dPos.y) end
        end)

        add_row_separator(1)

        -- Row 2
        local enable_frame_container = create_bound_checkbox("Enable Frame", data.show_key, 2, 1, nil, nil, uncheck_test_aura)

        -- Test Aura: stacked below Enable Frame in the same cell
        local test_aura_container = create_bound_checkbox("Test Aura", test_key, 2, 1, update, nil, nil, check_enable_frame)
        test_aura_container:ClearAllPoints()
        test_aura_container:SetPoint("TOPLEFT", enable_frame_container, "BOTTOMLEFT", 0, 0)

        -- Frame background
        create_bound_checkbox("Frame BG", data.bg_key, 2, 2)

        -- Frame BG color picker
        create_bound_color_picker("bg_color_"..cat, true, "Frame BG Color", 2, 3)
        add_row_separator(2)

        -- Row 3: Bar Mode and color pickers
        local bar_mode_key = "bar_mode_"..cat
        create_bound_checkbox("Bar Mode", bar_mode_key, 3, 1)
        create_bound_color_picker("color_"..cat, true, "Bar Color", 3, 2)
        create_bound_color_picker("bar_bg_color_"..cat, true, "Bar BG Color", 3, 3)
        add_row_separator(3)

        -- Row 4: Timer Text, Font & Font Size
        if cat ~= "static" then
            local timer_text_container = create_bound_checkbox("Timer Text", data.timer_key, 4, 1)

            local timer_bold_container = create_bound_checkbox("Timer Bold", "timer_number_font_bold_"..cat, 4, 1, function()
                if M.apply_number_font_to_all then M.apply_number_font_to_all() end
                update()
            end)
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

            local font_size_slider = addon.CreateSliderWithBox(addon_name..cat.."TimerFontSizeSlider", p, "Timer Font Size", 8, 14, 0.5, M.db, "timer_number_font_size_"..cat,
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

        add_row_separator(4)

        -- Row 5: Scale, Spacing, Max Icons
        local scale_slider = create_bound_slider("Scale", "Scale", 0.5, 2.5, 0.01, data.scale_key, update)
        place_at(scale_slider, 5, 1)

        local spacing_slider = create_bound_slider("Spacing", "Spacing", 0, 20, 0.1, data.spacing_key)
        place_at(spacing_slider, 5, 2)

        local max_icons_slider = create_bound_slider("PoolSlider", "Max Icons", 5, 40, 1, "max_icons_"..cat, function()
            print("|cFFFFFF00LsTweaks:|r Pool size for "..cat.." changed. Please /reload to apply.")
        end)
        place_at(max_icons_slider, 5, 4)

        -- Growth Direction dropdown in row 3, col 4, vertically centered
        place_at(M.CreateDirectionDropdown(addon_name..cat.."Growth", p, "Growth Direction", "growth_"..cat, update), 3, 4, "dropdown", { y_offset = -math.floor((grid.row_heights[3] - 24) / 2) })

        -- Sync X/Y sliders to the frame's current position (called after a drag).
        -- Defined here so it closes over x_slider/y_slider/cat.
        local function sync_xy_sliders_to_frame()
            local f = M.frames[data.show_key]
            if not (f and x_slider and y_slider and x_slider.slider and y_slider.slider) then return end
            local ucx, ucy = UIParent:GetCenter()
            local left = f:GetLeft()
            local top  = f:GetTop()
            if left and top then
                local x = math.floor(left - ucx + 0.5)
                local y = math.floor(top  - ucy + 0.5)
                M.db.positions[cat].x = x
                M.db.positions[cat].y = y
                M.db.positions[cat].point = "TOPLEFT"
                x_slider.slider:SetValue(x)
                y_slider.slider:SetValue(y)
            end
        end

        -- Hook both title bars so dragging from either handle syncs the sliders.
        local f = M.frames[data.show_key]
        if f then
            for _, tb in ipairs({ f.title_bar, f.bottom_title_bar }) do
                if tb then
                    local old_drag_stop = tb:GetScript("OnDragStop")
                    tb:SetScript("OnDragStop", function(...)
                        if old_drag_stop then old_drag_stop(...) end
                        sync_xy_sliders_to_frame()
                    end)
                end
            end
        end
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
        p:SetSize(741, 50)  -- tab content panel: 925 frame - 12 B.l - 140 sidebar - 12 B.r - 20 margin
        p:Hide()

        if data.is_general then
            build_general_tab(p)
        elseif data.is_frames then
            build_frames_tab(p)
        elseif data.is_aura_id then
            build_aura_id_tab(p)
        end

        tabs[i], panels[i] = tab, p
    end

    PanelTemplates_SetNumTabs(parent, #tab_data)
    local restore_tab = math.min((M.db and M.db.last_tab_index) or 1, #tab_data)
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

    local buffs = M.controls["enable_blizz_buffs"]
    if buffs and buffs.SetChecked then
        buffs:SetChecked(M.db.enable_blizz_buffs)
    end

    local debuffs = M.controls["enable_blizz_debuffs"]
    if debuffs and debuffs.SetChecked then
        debuffs:SetChecked(M.db.enable_blizz_debuffs)
    end

    local snap_cb = M.controls["snap_to_grid_checkbox"]
    if snap_cb and snap_cb.SetChecked then
        snap_cb:SetChecked(M.db.snap_to_grid == true)
    end

    local spell_id_cb = M.controls["show_spell_id_checkbox"]
    if spell_id_cb and spell_id_cb.SetChecked then
        spell_id_cb:SetChecked(M.db.show_spell_id == true)
    end

    local grid_cb = M.controls["show_grid_checkbox"]
    if grid_cb and grid_cb.SetChecked then
        grid_cb:SetChecked(M.db.show_grid == true)
    end

    for _, cat in ipairs(M.TIMER_CATEGORIES) do
        local font_dropdown = M.controls["timer_number_font_dropdown_"..cat]
        if font_dropdown and font_dropdown.SetValue then
            font_dropdown:SetValue(M.db["timer_number_font_"..cat] or M.db.timer_number_font or "source_code_pro")
        end

        local font_size_slider = M.controls["timer_number_font_size_slider_"..cat]
        if font_size_slider and font_size_slider.slider then
            font_size_slider.slider:SetValue(M.db["timer_number_font_size_"..cat] or M.defaults["timer_number_font_size_"..cat] or 10)
        end
    end

    for _, cat in ipairs(M.TIMER_CATEGORIES) do
        local cat_bold_cb = M.controls["timer_number_font_bold_"..cat]
        if cat_bold_cb and cat_bold_cb.SetChecked then
            cat_bold_cb:SetChecked(M.db["timer_number_font_bold_"..cat] or false)
        end
    end

    local outlines_cb = M.controls["show_bar_section_outlines_checkbox"]
    if outlines_cb and outlines_cb.SetChecked then
        outlines_cb:SetChecked(M.db.show_bar_section_outlines == true)
    end
end

