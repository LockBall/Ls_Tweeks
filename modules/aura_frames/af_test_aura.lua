local addon_name, addon = ...

addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local GetTime = GetTime

-- ============================================================================
-- TEST AURA CONFIG
-- Tune preview appearance and animation behavior here.

local CFG = {
    icon            = "Interface\\Icons\\INV_Misc_QuestionMark",
    short_duration  = 20,   -- short preview duration (seconds)
    long_extra_min  = 30,   -- minimum seconds added above threshold for long preview
    long_extra_frac = 0.5,  -- fraction of threshold added for long preview
    sec_per_stack   = 2.0,  -- seconds each stack value is held (0.1 increments)
    stack_steps     = 4,    -- number of distinct steps in the cycle
    stack_min       = 1,    -- lowest stack count shown during the cycle
    stack_max       = 4,    -- highest stack count shown during the cycle
    min_remaining   = 0.1,  -- floor for remaining time so bar never shows fully empty
}

-- Per-category preview label and sort order.
local PREVIEW_META = {
    show_static = { name = "Test Static Buff", sort_id = 1 },
    show_short  = { name = "Test Short Buff",  sort_id = 2 },
    show_long   = { name = "Test Long Buff",   sort_id = 3 },
    show_debuff = { name = "Test DeBuff",       sort_id = 4 },
}

function M.get_test_preview_state(show_key, short_threshold, now)
    now = now or GetTime()

    if show_key == "show_static" then
        return 0, 0, 0
    end

    local threshold = short_threshold or 60
    local short_duration = CFG.short_duration
    local duration = (show_key == "show_long")
        and (threshold + math_max(CFG.long_extra_min, math_floor(threshold * CFG.long_extra_frac)))
        or  short_duration

    local remaining = math_max(CFG.min_remaining, duration - (now % duration))

    -- Stack count cycles on its own period, independent of the timer length.
    -- Each stack value is held for sec_per_stack seconds (tunable in 0.1s increments).
    local full_cycle = CFG.sec_per_stack * CFG.stack_steps
    local stack_bucket = math_floor((now % full_cycle) / CFG.sec_per_stack) + 1
    local count = math_min(CFG.stack_max, math_max(CFG.stack_min, stack_bucket))

    return duration, remaining, count
end

function M.build_test_aura_entry(show_key, filter, short_threshold)
    local now = GetTime()
    local duration, remaining, count = M.get_test_preview_state(show_key, short_threshold, now)
    local meta = PREVIEW_META[show_key] or PREVIEW_META.show_debuff

    return {
        name            = meta.name,
        icon            = CFG.icon,
        duration        = duration,
        expiration      = duration > 0 and (now + remaining) or 0,
        remaining       = remaining,
        count           = count,
        filter          = filter,
        added_at        = now,
        preview_sort_id = meta.sort_id,
        is_test_preview = true,
    }
end

function M.append_test_aura(aura_map, show_key, filter, short_threshold)
    aura_map["__test_preview__"] = M.build_test_aura_entry(show_key, filter, short_threshold)
end

function M.update_test_preview_display(obj, show_key, short_threshold, show_timer_text, bar_mode, now)
    local duration, remaining, count = M.get_test_preview_state(show_key, short_threshold, now)

    obj.aura_duration = duration
    obj.aura_remaining = remaining
    obj.aura_expiration = now + remaining
    obj.aura_scan_time = now

    -- Unify test aura display for all categories (short, long, debuff)
    if bar_mode and obj.bar and obj.bar:IsShown() then
        obj.bar:SetMinMaxValues(0, duration)
        obj.bar:SetValue(remaining)
        -- In bar mode: stack count shown inline with name if >1
        if count and count > 1 then
            obj.count_text:SetText(count)
            obj.count_text:SetPoint("LEFT", obj.bar, "LEFT", 4, 0)
            obj.count_text:Show()
        else
            obj.count_text:Hide()
        end
        if show_timer_text and duration > 0 then
            obj.time_text:Show()
            M.set_timer_text(obj.time_text, show_key:sub(6), remaining)
        else
            obj.time_text:Hide()
        end
    else
        -- Icon mode: stack count at bottom-right if >1
        if count and count > 1 then
            obj.count_text:SetText(count)
            obj.count_text:ClearAllPoints()
            obj.count_text:SetPoint("BOTTOMRIGHT", obj, "BOTTOMRIGHT", 0, 1)
            obj.count_text:Show()
        else
            obj.count_text:Hide()
        end
        if show_timer_text and duration > 0 then
            obj.time_text:Show()
            M.set_timer_text(obj.time_text, show_key:sub(6), remaining)
        else
            obj.time_text:Hide()
        end
    end
end