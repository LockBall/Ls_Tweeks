local addon_name, addon = ...

local math_max       = math.max
local math_ceil      = math.ceil
local GetTime        = GetTime
local issecretvalue  = issecretvalue
local C_UnitAuras    = C_UnitAuras
local wipe           = wipe

addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

-- ============================================================================
-- TIMER TICKER

-- Shared ticker update path for all visible aura icon objects.
-- Runs at 0.1s from af_main.lua and keeps timer/bar text fresh between scans.
function M.tick_visible_icons(now)
    now = now or GetTime()
    local db = M.db
    local short_threshold = (db and db.short_threshold) or 60

    for _, frame in pairs(M.frames) do
        if frame:IsVisible() then
            local is_static_frame = (frame.category == "static")
            local show_timer_text = M.is_timer_text_enabled(db, frame.category)
            local bar_mode = db and db["bar_mode_"..frame.category]
            for i = 1, #frame.icons do
                local obj = frame.icons[i]
                if obj:IsShown() and is_static_frame then
                    obj.time_text:SetText("")
                elseif obj:IsShown() and obj.is_test_preview then
                    M.update_test_preview_display(obj, "show_" .. frame.category, short_threshold, show_timer_text, bar_mode, now)
                elseif obj:IsShown() and obj.aura_index then
                    if show_timer_text then
                        obj.time_text:Show()
                    else
                        obj.time_text:Hide()
                    end
                    local remaining
                    if obj.aura_expiration and obj.aura_expiration > 0 then
                        remaining = math_max(0, obj.aura_expiration - now)
                    elseif obj.aura_scan_time and obj.aura_remaining
                        and not issecretvalue(obj.aura_remaining)
                        and obj.aura_remaining > 0 then
                        remaining = math_max(0, obj.aura_remaining - (now - obj.aura_scan_time))
                    end
                    local live_remaining
                    local need_live_fallback = (remaining == nil)
                        and (show_timer_text or (obj.bar and obj.bar:IsShown()))
                    if need_live_fallback then
                        local live_duration = C_UnitAuras.GetAuraDuration("player", obj.aura_index)
                        if live_duration then
                            live_remaining = live_duration:GetRemainingDuration()
                            if live_remaining ~= nil and not issecretvalue(live_remaining) then
                                remaining = live_remaining
                            end
                        end
                    end
                    if remaining and remaining > 0 then
                        if show_timer_text then
                            M.set_timer_text(obj.time_text, frame.category, remaining)
                        end
                        if obj.bar and obj.bar:IsShown() then
                            obj.bar:SetValue(remaining)
                        end
                    elseif remaining == 0 then
                        obj.time_text:SetText("")
                    elseif live_remaining ~= nil and issecretvalue(live_remaining) then
                        if show_timer_text then
                            M.set_timer_text(obj.time_text, frame.category, live_remaining)
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- BLIZZARD BUFF/DEBUFF FRAME TOGGLES

local function set_blizz_frame_state(frame, hide)
    if not frame then return end

    if hide then
        frame:Hide()
        frame:UnregisterAllEvents()
        if frame.SetScript then frame:SetScript("OnShow", nil) end
    else
        frame:RegisterEvent("UNIT_AURA")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:Show()
        if frame.UpdateAuras then frame:UpdateAuras() end
        if frame.UpdateLayout then frame:UpdateLayout() end
    end
end

function M.toggle_blizz_buffs(hide)
    set_blizz_frame_state(BuffFrame, hide)
end

function M.toggle_blizz_debuffs(hide)
    set_blizz_frame_state(DebuffFrame, hide)
end

-- ============================================================================
-- AURA UPDATE (main per-frame refresh)

function M.update_auras(self, show_key, move_key, timer_key, bg_key, scale_key, spacing_key, filter, info)
    if not self or not self.icons then return end

    local db = M.db
    local bar_bg_alpha = M.BAR_BG_ALPHA_DEFAULT
    local category = show_key:sub(6)
    local bar_mode = db["bar_mode_"..category]
    local frame_width = db["width_"..category] or 200
    local spacing = db[spacing_key] or 6
    local color = db["color_"..category] or {r=1, g=1, b=1}
    local barBgC = db["bar_bg_color_"..category] or {r=color.r, g=color.g, b=color.b, a=bar_bg_alpha}
    local bgC = db["bg_color_"..category] or {r=0, g=0, b=0, a=0.5}
    local show_timer_text = M.is_timer_text_enabled(db, category, timer_key)
    local short_threshold = db.short_threshold or 60
    local growth = db["growth_"..category] or "DOWN"
    local max_limit = db["max_icons_"..category] or 40
    local sort_mode = db["sort_"..category] or "timeleft"
    local preview_enabled = db["test_aura_"..category]

    local scale = db[scale_key] or 1.0
    self:SetScale(scale)
    local _pos = M.db.positions and M.db.positions[category]
    local _width = db["width_"..category] or 200
    local _height = self:GetHeight() or 50
    if _width < 1 then _width = 200 end
    if _height < 1 then _height = 50 end
    self:ClearAllPoints()
    if _pos then
        self:SetPoint("TOPLEFT", UIParent, "CENTER", (_pos.x or 0) / scale, (_pos.y or 0) / scale)
    else
        self:SetPoint("TOPLEFT", UIParent, "CENTER", -100, category == "debuff" and -25 or 75)
    end
    self:SetSize(_width, _height)

    if not self._layout_cache
        or (self._layout_cache.frame_width    ~= frame_width
        or  self._layout_cache.bar_mode       ~= bar_mode
        or  self._layout_cache.show_timer_text ~= show_timer_text
        or  self._layout_cache.spacing        ~= spacing
        or  self._layout_cache.growth         ~= growth
    ) then
        M.setup_layout(self, show_key, spacing_key, bar_mode)
    end

    local is_moving = db[move_key]

    if not db[show_key] and not is_moving and not preview_enabled then
        self:Hide()
        return
    end

    if is_moving then
        self.title_bar:Show()
        self.bottom_title_bar:Show()
        self.resizer:Show()
    else
        self.title_bar:Hide()
        self.bottom_title_bar:Hide()
        self.resizer:Hide()
    end

    if is_moving and not db[show_key] and not preview_enabled then
        local timer_font_size = (M.get_timer_number_font_size and M.get_timer_number_font_size(category)) or 10
        local bar_layout = M.get_bar_layout_params(timer_font_size)
        local min_height  -- bar_mode and spacing already in outer scope
        if bar_mode then
            min_height = (bar_layout.row_height or 18) + spacing + 12
        else
            local timer_h = show_timer_text and 12 or 0
            local bot_pad = show_timer_text and 14 or 12
            min_height = 32 + timer_h + bot_pad
        end
        M.set_height_for_growth(self, min_height, growth)
        self:Show()
        return
    end

    if db[show_key] or preview_enabled then self:Show() end

    if not self._aura_map then self._aura_map = {} end

    if filter == "HELPFUL" then
        local shared = M.scan_helpful_shared(info, short_threshold, max_limit)
        wipe(self._aura_map)
        for iid, entry in pairs(shared.map) do
            if shared.category_by_iid[iid] == show_key then
                self._aura_map[iid] = entry
            end
        end
    else
        M.full_scan(self._aura_map, filter, show_key, short_threshold, max_limit, info)
    end

    if preview_enabled then
        M.append_test_aura(self._aura_map, show_key, filter, short_threshold)
    else
        self._aura_map["__test_preview__"] = nil
    end

    local display_count = M.render_aura_map(
        self, self._aura_map, bar_mode, color, barBgC, max_limit, filter, sort_mode, show_timer_text
    )

    local lc = self._layout_cache
    local icon_timer_h = show_timer_text and 12 or 0
    local icon_bot_pad = show_timer_text and 14 or 12
    local new_height = bar_mode and ((lc and lc.row_height or 18) + spacing + 12)
                                 or  ((lc and lc.icon_size or 32) + icon_timer_h + icon_bot_pad)
    if display_count > 0 then
        if bar_mode then
            local bar_row_h = lc and lc.row_height or 18
            new_height = display_count * (bar_row_h + spacing) + 12
        elseif lc and (lc.growth == "DOWN" or lc.growth == "UP") then
            local isz = lc.icon_size or 32
            new_height = display_count * (isz + spacing + icon_timer_h) - spacing + icon_bot_pad
        elseif lc and lc.icons_per_row then
            local isz = lc.icon_size or 32
            local rows = math_ceil(display_count / lc.icons_per_row)
            new_height = rows * (isz + spacing + icon_timer_h) - spacing + icon_bot_pad
        else
            new_height = display_count * 44
        end
    end

    if db[show_key] or preview_enabled then
        self:Show()
        M.set_height_for_growth(self, new_height, growth)
    elseif not is_moving then
        self:Hide()
    end

    if (db[show_key] or preview_enabled) and not self:IsVisible() then self:Show() end

    local is_bg_enabled = db[bg_key]
    if is_moving then
        if is_bg_enabled and bgC then
            self:SetBackdropColor(bgC.r, bgC.g, bgC.b, bgC.a or 1)
            self:SetBackdropBorderColor(1, 1, 1, 1)
        else
            self:SetBackdropColor(0, 0, 0, 0.8)
            self:SetBackdropBorderColor(1, 1, 1, 1)
        end
    else
        if is_bg_enabled and bgC then
            self:SetBackdropColor(bgC.r, bgC.g, bgC.b, bgC.a or 1)
            self:SetBackdropBorderColor(0, 0, 0, 0)
        else
            self:SetBackdropColor(0, 0, 0, 0)
            self:SetBackdropBorderColor(0, 0, 0, 0)
        end
    end
end
