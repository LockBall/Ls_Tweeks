local addon_name, addon = ...

local floor      = math.floor
local math_max   = math.max
local math_min   = math.min
local GetTime    = GetTime
local issecretvalue = issecretvalue
local C_UnitAuras   = C_UnitAuras
local format        = format
local table_sort    = table.sort
local SORT_RULE_DEFAULT    = Enum.UnitAuraSortRule.Default
local SORT_RULE_EXPIRATION = Enum.UnitAuraSortRule.ExpirationOnly
local SORT_RULE_NAME       = Enum.UnitAuraSortRule.NameOnly
local SORT_DIR_NORMAL      = Enum.UnitAuraSortDirection.Normal
local TIMER_DIR_REMAINING  = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime

addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

-- ============================================================================
-- TIME FORMATTING

-- Logic for converting seconds into readable text strings
local function format_time(s)
    if s >= 3600 then return format("%d h", floor(s/3600)) end
    if s >= 60 then return format("%d m", floor(s/60)) end
    if s >= 5 then return format("%d s", floor(s)) end
    if s >= 1 then return format("%.1f s", s) end
    return format("%.1f s", s)
end

-- ============================================================================
-- SORT HELPERS (also used in af_scan.lua — kept local, tiny pure functions)

local function get_entry_sort_id(entry)
    if type(entry.instance_id) == "number" then
        return entry.instance_id
    end
    return entry.preview_sort_id or 0
end

local function make_order_key(spell_id, name, icon, filter)
    local f = filter or ""
    local sid = (spell_id ~= nil and not issecretvalue(spell_id)) and tostring(spell_id) or nil
    local n = (name ~= nil and not issecretvalue(name)) and tostring(name) or nil
    local i = (icon ~= nil and not issecretvalue(icon)) and tostring(icon) or nil
    if not sid and not n and not i then return nil end
    return f .. "|" .. (sid or "") .. "|" .. (n or "") .. "|" .. (i or "")
end

-- ============================================================================
-- TIMER TEXT

-- Single timer text renderer for all aura timers (live + test).
-- Keep behavior changes here so all timer displays stay consistent.
function M.set_timer_text(font_string, category, seconds)
    if not font_string then return end

    if seconds == nil then
        font_string:SetText("")
        return
    end

    font_string:Show()

    if issecretvalue(seconds) then
        font_string:SetFormattedText("%.1f", seconds)
        return
    end

    if seconds <= 0 then
        font_string:SetText("")
        return
    end

    local is_short = (category == "short" or category == "show_short")
    if is_short then
        local rounded = floor((seconds * 10) + 0.5) / 10
        font_string:SetText(format("%.1f", rounded))
    else
        font_string:SetText(format_time(seconds))
    end
end

-- ============================================================================
-- AURA INFO MERGING

-- Merge UNIT_AURA payloads while a deferred scan is pending.
-- Blizzard can fire multiple UNIT_AURA events inside the 0.1s bucket window;
-- we need to union their added/updated/removed IDs so no aura changes are lost.
function M.merge_aura_info(dst, src)
    if not src then return dst end
    dst = dst or {}

    local function merge_id_list(key, list)
        if not list then return end
        dst[key] = dst[key] or {}
        dst[key.."_set"] = dst[key.."_set"] or {}
        for _, iid in ipairs(list) do
            if iid and not dst[key.."_set"][iid] then
                dst[key.."_set"][iid] = true
                dst[key][#dst[key] + 1] = iid
            end
        end
    end

    merge_id_list("removedAuraInstanceIDs", src.removedAuraInstanceIDs)
    merge_id_list("updatedAuraInstanceIDs", src.updatedAuraInstanceIDs)

    -- Modern payload: addedAuras = array of aura tables with auraInstanceID.
    if src.addedAuras then
        dst.addedAuras = dst.addedAuras or {}
        dst.addedAuras_set = dst.addedAuras_set or {}
        for _, aura in ipairs(src.addedAuras) do
            local iid = aura and aura.auraInstanceID
            if iid and not dst.addedAuras_set[iid] then
                dst.addedAuras_set[iid] = true
                dst.addedAuras[#dst.addedAuras + 1] = aura
            end
        end
    end

    -- Backward/alternate payload support.
    merge_id_list("addedAuraInstanceIDs", src.addedAuraInstanceIDs)

    if src.isFullUpdate then
        dst.isFullUpdate = true
    end

    return dst
end

-- ============================================================================
-- AURA MAP RENDERER

-- Render the aura_map into the icon pool.
-- Uses C_UnitAuras.GetUnitAuraInstanceIDs for sort order (ElkBuffBars technique):
-- the game provides a pre-sorted list of IDs; we display only those in our map.
function M.render_aura_map(self, aura_map, bar_mode, color, bar_bg_color, max_limit, filter, sort_mode, show_timer_text)
    local bar_bg_alpha = M.BAR_BG_ALPHA_DEFAULT
    -- Resolve sort parameters for GetUnitAuraInstanceIDs
    local sort_rule = SORT_RULE_DEFAULT
    local sort_dir  = SORT_DIR_NORMAL
    if sort_mode == "timeleft" then
        sort_rule = SORT_RULE_EXPIRATION
        -- Normal = ascending expiration time = soonest to expire first (most urgent)
    elseif sort_mode == "name" then
        sort_rule = SORT_RULE_NAME
    end

    local wow_filter = (filter == "HELPFUL") and "HELPFUL" or "HARMFUL"
    local sorted_ids = C_UnitAuras.GetUnitAuraInstanceIDs("player", wow_filter, nil, sort_rule, sort_dir)

    -- Build display list in game-sorted order, filtered to entries in this frame's map
    local list = {}
    if sorted_ids then
        local seen = {}
        for _, iid in ipairs(sorted_ids) do
            local entry = aura_map[iid]
            if entry then
                list[#list + 1] = entry
                seen[iid] = true
            end
        end
        for key, entry in pairs(aura_map) do
            if not seen[key] then
                list[#list + 1] = entry
            end
        end
    else
        -- Fallback: iterate map directly (sorted_ids nil = API unavailable)
        for _, entry in pairs(aura_map) do list[#list + 1] = entry end
        table_sort(list, function(a, b) return get_entry_sort_id(a) < get_entry_sort_id(b) end)
    end

    -- Short frame ordering: stable per-aura order key so stack updates don't
    -- reposition existing buffs. New keys get appended at the end.
    if self.category == "short" then
        self._short_order_map = self._short_order_map or {}
        self._short_order_next = self._short_order_next or 1

        local seen_keys = {}
        for _, entry in ipairs(list) do
            local key = make_order_key(entry.spell_id, entry.name, entry.icon, entry.filter)
            if not key then
                key = "iid:" .. tostring(entry.instance_id)
            end

            if not self._short_order_map[key] then
                self._short_order_map[key] = self._short_order_next
                self._short_order_next = self._short_order_next + 1
            end

            entry._short_order = self._short_order_map[key]
            seen_keys[key] = true
        end

        -- Cleanup removed keys so re-applied buffs are treated as new entries.
        for key in pairs(self._short_order_map) do
            if not seen_keys[key] then
                self._short_order_map[key] = nil
            end
        end

        table_sort(list, function(a, b)
            local aa = a._short_order or 0
            local bb = b._short_order or 0
            if aa == bb then
                return get_entry_sort_id(a) < get_entry_sort_id(b)
            end
            return aa < bb
        end)
    end

    local display_count = math_min(#list, math_min(max_limit, #self.icons))
    local now = GetTime()
    local is_static_frame = (self.category == "static")

    for i = 1, display_count do
        local obj   = self.icons[i]
        local entry = list[i]
        local need_live_duration = (not is_static_frame) and (show_timer_text or bar_mode)
        local live_duration = need_live_duration and entry.instance_id and C_UnitAuras.GetAuraDuration("player", entry.instance_id)
        local live_remaining = live_duration and live_duration:GetRemainingDuration() or nil
        local need_live_count = entry.instance_id
            and ((entry.count == nil) or issecretvalue(entry.count) or entry.count <= 1)
        local live_count = need_live_count and C_UnitAuras.GetAuraApplicationDisplayCount("player", entry.instance_id)

        obj.aura_index      = entry.instance_id
        obj.filter_type     = entry.filter
        obj.aura_name       = entry.name
        obj.aura_icon       = entry.icon
        obj.aura_duration   = entry.duration
        obj.aura_remaining  = entry.remaining
        obj.aura_expiration = entry.expiration
        obj.aura_scan_time  = now
        obj.aura_spell_id   = entry.spell_id
        obj.is_test_preview = entry.is_test_preview or false

        obj.texture:SetTexture(entry.icon)  -- secret icon OK for SetTexture

        local stack_text = nil
        if entry.count and not issecretvalue(entry.count) and entry.count > 1 then
            stack_text = entry.count
        elseif live_count ~= nil and not issecretvalue(live_count) then
            if type(live_count) == "number" then
                if live_count > 1 then
                    stack_text = live_count
                end
            elseif type(live_count) == "string" then
                if live_count ~= "" and live_count ~= "1" then
                    stack_text = live_count
                end
            else
                stack_text = live_count
            end
        else
            -- Secret live_count is safe to display, but we cannot compare it.
            -- Preserve combat behavior by showing it only when no safe fallback exists.
            stack_text = live_count
        end
        if bar_mode then
            obj.bar:Show()
            obj.bar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
            if obj.bar_bg then
                local bg = bar_bg_color or { r = color.r, g = color.g, b = color.b, a = bar_bg_alpha }
                obj.bar_bg:SetColorTexture(bg.r, bg.g, bg.b, bg.a or 1)
            end
            -- In bar mode: append stack count to name if present
            obj.name_text:SetText(entry.name)  -- name may be secret; SetText is safe
            obj.name_text:Show()
            if stack_text ~= nil then
                obj.count_text:SetText(stack_text)
                obj.count_text:SetPoint("LEFT", obj.bar, "LEFT", 4, 0)
                obj.count_text:Show()
            else
                obj.count_text:Hide()
            end
        else
            obj.bar:Hide()
            obj.name_text:Hide()
            -- In icon mode: stack count at bottom-right of icon
            if stack_text ~= nil then
                obj.count_text:SetText(stack_text)
                obj.count_text:Show()
            else
                obj.count_text:Hide()
            end
        end

        -- Static frame buffs are effectively permanent; never display a timer string.
        if is_static_frame then
            obj.time_text:SetText("")
            if bar_mode then
                obj.bar:SetMinMaxValues(0, 1)
                obj.bar:SetValue(1)
            end
        else
        -- Prefer live duration by auraInstanceID; fall back to cached values.
        local rem = live_remaining
        if rem ~= nil then
            if issecretvalue(rem) then
                local display_remaining = nil
                if entry.expiration and entry.expiration > 0 then
                    display_remaining = math_max(0, entry.expiration - now)
                elseif entry.remaining and entry.remaining > 0 then
                    display_remaining = entry.remaining
                end

                if display_remaining and display_remaining > 0 then
                    if show_timer_text then
                        M.set_timer_text(obj.time_text, self.category, display_remaining)
                    else
                        obj.time_text:SetText("")
                    end
                else
                    if show_timer_text then
                        M.set_timer_text(obj.time_text, self.category, rem)
                    else
                        obj.time_text:SetText("")
                    end
                end
                if bar_mode and obj.bar and obj.bar.SetTimerDuration and TIMER_DIR_REMAINING then
                    obj.bar:SetTimerDuration(live_duration, nil, TIMER_DIR_REMAINING)
                end
            elseif rem > 0 then
                if show_timer_text then
                    M.set_timer_text(obj.time_text, self.category, rem)
                else
                    obj.time_text:SetText("")
                end
                if bar_mode then
                    if obj.bar and obj.bar.SetTimerDuration and TIMER_DIR_REMAINING then
                        obj.bar:SetTimerDuration(live_duration, nil, TIMER_DIR_REMAINING)
                    else
                        obj.bar:SetMinMaxValues(0, entry.duration > 0 and entry.duration or rem)
                        obj.bar:SetValue(rem)
                    end
                end
            else
                obj.time_text:SetText("")
                if bar_mode then
                    obj.bar:SetMinMaxValues(0, 1)
                    obj.bar:SetValue(1)
                end
            end
        elseif entry.duration > 0 then
            rem = entry.expiration > 0 and math_max(0, entry.expiration - now) or entry.remaining
            if rem > 0 then
                if show_timer_text then
                    M.set_timer_text(obj.time_text, self.category, rem)
                else
                    obj.time_text:SetText("")
                end
                if bar_mode then
                    obj.bar:SetMinMaxValues(0, entry.duration)
                    obj.bar:SetValue(rem)
                end
            else
                obj.time_text:SetText("")
                if bar_mode then
                    obj.bar:SetMinMaxValues(0, 1)
                    obj.bar:SetValue(1)
                end
            end
        end
        end

        obj:Show()
    end

    for i = display_count + 1, #self.icons do
        self.icons[i]:Hide()
    end

    return display_count
end
