local addon_name, addon = ...

-- CACHED GLOBALS AND CONSTANTS
local floor = math.floor
local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local wipe = wipe
local issecretvalue = issecretvalue  -- WoW built-in: true if value is tainted/secret
local C_UnitAuras = C_UnitAuras     -- localize for frequent hot-path calls
local format = format                -- WoW global alias for string.format
local table_sort = table.sort
local SORT_RULE_DEFAULT    = Enum.UnitAuraSortRule.Default
local SORT_RULE_EXPIRATION = Enum.UnitAuraSortRule.ExpirationOnly
local SORT_RULE_NAME       = Enum.UnitAuraSortRule.NameOnly
local SORT_DIR_NORMAL      = Enum.UnitAuraSortDirection.Normal
local TIMER_DIR_REMAINING  = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime

addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames



-- Categorize aura by remaining time.
-- remaining == nil means duration was secret; caller handles that case separately.
local function categorize_aura(remaining, show_key, short_threshold)
    if show_key == "show_static" then
        return remaining == 0
    elseif show_key == "show_short" then
        return remaining > 0 and remaining <= short_threshold
    elseif show_key == "show_long" then
        return remaining > short_threshold
    end
    return true  -- debuff frame: show all
end

-- Logic for converting seconds into readable text strings
local function format_time(s)
    if s >= 3600 then return format("%d h", floor(s/3600)) end
    if s >= 60 then return format("%d m", floor(s/60)) end
    if s >= 5 then return format("%d s", floor(s)) end
    if s >= 1 then return format("%.1f s", s) end
    return format("%.1f s", s)
end
M.format_time = format_time

local function is_timer_text_enabled(db, category, timer_key)
    if category == "static" then
        return false
    end

    local value
    if timer_key then
        value = db and db[timer_key]
    else
        value = db and db["timer_"..category]
    end

    if value == nil then
        return true
    end
    return value and true or false
end

local function get_bar_layout_params(timer_font_size)
    -- Keep this argument available for future size-aware scaling rules.
    timer_font_size = tonumber(timer_font_size) or 10
    -- Dynamically scale timer slot width: enough for 4 wide digits at large font sizes
    local min_width = 36
    local scale_factor = 2.7 -- empirically fits 4 digits at font size 14
    local timer_slot_width = math_max(min_width, math_ceil(timer_font_size * scale_factor))

    return {
        -- Outer bar row geometry and frame inset.
        frame_inset = 6,
        frame_inner_width_pad = 12,
        row_height = 18,

        -- Icon + bar composition.
        icon_size = 18,
        icon_to_bar_gap = 5,
        bar_height = 18,

        -- Left stack/count slot.
        stack_slot_left_pad = 2,
        stack_slot_width = 20,
        stack_slot_height = 18,

        -- Right timer slot.
        timer_slot_width = timer_slot_width,
        timer_slot_right_pad = 2,
        timer_slot_height = 18,

        -- Middle name slot between stack and timer.
        name_slot_left_gap = 2,
        name_slot_right_gap = 2,
        name_slot_right_no_timer = 4,
        name_slot_height = 18,

        -- Text padding inside the name slot.
        name_text_left_pad = 2,
        name_text_right_pad = 2,
    }
end

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

-- Shared ticker update path for all visible aura icon objects.
-- Runs at 0.1s from af_main.lua and keeps timer/bar text fresh between scans.
function M.tick_visible_icons(now)
    now = now or GetTime()
    local db = M.db
    local short_threshold = (db and db.short_threshold) or 60

    for _, frame in pairs(M.frames) do
        if frame:IsVisible() then
            local is_static_frame = (frame.category == "static")
            local show_timer_text = is_timer_text_enabled(db, frame.category)
            local bar_mode = db and db["bar_mode_"..frame.category]
            for i = 1, #frame.icons do
                local obj = frame.icons[i]
                if obj:IsShown() and is_static_frame then
                    obj.time_text:SetText("")
                elseif obj:IsShown() and obj.is_test_preview then
                    M.update_test_preview_display(obj, "show_" .. frame.category, short_threshold, show_timer_text, bar_mode, now)
                elseif obj:IsShown() and obj.aura_index then
                    -- Enforce time_text visibility from the live setting each tick.
                    -- setup_layout is blocked in combat lockdown, so this is the only
                    -- reliable path for mid-combat Show Time Remaining toggles to take effect.
                    if show_timer_text then
                        obj.time_text:Show()
                    else
                        obj.time_text:Hide()
                    end
                    -- Compute remaining from scan-time expiration; no per-tick API calls.
                    -- Previously called C_UnitAuras.GetAuraDuration every 100ms per icon
                    -- (~200 calls/second with 20 visible auras). Now uses stored fields.
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
                        -- Secret-duration fallback: only query live duration when we
                        -- cannot derive remaining from cached scan fields.
                        local live_duration = C_UnitAuras.GetAuraDuration("player", obj.aura_index)
                        if live_duration then
                            live_remaining = live_duration:GetRemainingDuration()
                            if live_remaining ~= nil and not issecretvalue(live_remaining) then
                                remaining = live_remaining
                            end
                        end
                    end
                    -- remaining is nil only when duration is truly hidden (both expiration
                    -- and remaining are secret). Keep the last rendered text in that case.
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

-- BLIZZARD Buff & Debuff FRAME TOGGLES
local function set_blizz_frame_state(frame, hide)
    if not frame then return end

    if hide then
        frame:Hide()
        frame:UnregisterAllEvents()
        if frame.SetScript then frame:SetScript("OnShow", nil) end
        -- When hiding, optionally restore parent and position if needed (optional, not required by user)
    else
        -- Re-register the essential events
        frame:RegisterEvent("UNIT_AURA")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- Do NOT re-anchor or re-parent when showing (per user request)
        frame:Show()
        if frame.UpdateAuras then
            frame:UpdateAuras()
        end
        if frame.UpdateLayout then
            frame:UpdateLayout()
        end
    end
end

function M.toggle_blizz_buffs(hide)
    set_blizz_frame_state(BuffFrame, hide)
end

function M.toggle_blizz_debuffs(hide)
    set_blizz_frame_state(DebuffFrame, hide)
end

-- ============================================================================
-- MAP-BASED AURA TRACKING HELPERS

-- Returns remaining seconds, or nil if duration is nil/secret (can't compare).
-- Callers must check for nil before any arithmetic/comparison on the result.
local function compute_remaining(duration, expiration)
    if not duration or issecretvalue(duration) then return nil end
    if duration <= 0 then return 0 end
    if not expiration or issecretvalue(expiration) then
        return duration  -- known duration, unknown expiration: use duration as estimate
    end
    if expiration > 0 then return math_max(0, expiration - GetTime()) end
    return duration
end

-- Build an entry table. duration/expiration/count are pre-validated (non-secret).
-- name/icon/dispel_name may be secret strings — safe for SetText/SetTexture.
local function make_entry(iid, name, icon, duration, expiration, spell_id, dispel_name, rem, count, filter, added_at)
    return {
        instance_id = iid,
        name        = name,
        icon        = icon,
        duration    = duration,
        expiration  = expiration,
        spell_id    = spell_id,
        dispel_name = dispel_name,
        remaining   = rem,
        count       = count,
        filter      = filter,
        added_at    = added_at or GetTime(),
    }
end

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

    -- If we have no non-secret aura identity fields, skip keying entirely.
    if not sid and not n and not i then
        return nil
    end

    return f .. "|" .. (sid or "") .. "|" .. (n or "") .. "|" .. (i or "")
end

local function get_safe_spell_id(raw_spell_id, old_entry)
    if raw_spell_id ~= nil and not issecretvalue(raw_spell_id) then
        return raw_spell_id
    end
    if old_entry and old_entry.spell_id ~= nil and not issecretvalue(old_entry.spell_id) then
        return old_entry.spell_id
    end
    return nil
end

-- Build a lookup of auraInstanceID -> aura data (or true) from UNIT_AURA info.
-- Returns lookup table and count of added entries.
local function build_added_lookup(info)
    local lookup = {}
    local count = 0
    if not info then return lookup, count end
    if info.addedAuras then
        for _, added_aura in ipairs(info.addedAuras) do
            local iid = added_aura and added_aura.auraInstanceID
            if iid then
                lookup[iid] = added_aura
                count = count + 1
            end
        end
    elseif info.addedAuraInstanceIDs then
        for _, iid in ipairs(info.addedAuraInstanceIDs) do
            if iid then
                lookup[iid] = true
                count = count + 1
            end
        end
    end
    return lookup, count
end

-- Build a key->earliest added_at map from an existing aura map (for stable ordering).
local function build_added_by_key(map)
    local by_key = {}
    for _, entry in pairs(map) do
        local key = make_order_key(entry.spell_id, entry.name, entry.icon, entry.filter)
        if key and entry.added_at and (not by_key[key] or entry.added_at < by_key[key]) then
            by_key[key] = entry.added_at
        end
    end
    return by_key
end

-- Shared helpful-aura scan/classifier.
-- 12.0.5+ API usage:
--   * C_UnitAuras.GetBuffDataByIndex
--   * C_UnitAuras.DoesAuraHaveExpirationTime
--   * C_UnitAuras.GetAuraDuration
-- Each helpful aura is assigned to exactly one category: static/short/long.
local function scan_helpful_shared(info, short_threshold, max_limit_hint)
    M._helpful_shared = M._helpful_shared or {
        map = {},
        category_by_iid = {},
        category_by_spell = {},
    }

    local shared = M._helpful_shared
    local old_map = shared.map or {}
    local old_cat_iid = shared.category_by_iid or {}
    local old_cat_spell = shared.category_by_spell or {}

    local old_added_by_key = build_added_by_key(old_map)
    local added_lookup, added_count = build_added_lookup(info)

    local removed_count = 0
    local replacement_pref = nil
    if info and info.removedAuraInstanceIDs then
        removed_count = #info.removedAuraInstanceIDs
        if removed_count == 1 and added_count == 1 then
            local rid = info.removedAuraInstanceIDs[1]
            replacement_pref = old_cat_iid[rid]
        end
    end

    local db = M.db
    local shared_max = math_max(
        db.max_icons_static or 40,
        math_max(db.max_icons_short or 40, db.max_icons_long or 40)
    )
    local max_limit = math_max(max_limit_hint or 0, shared_max)

    local new_map = {}
    local new_cat_iid = {}
    local new_cat_spell = {}

    local i, count = 1, 0
    while count < max_limit do
        local aura = C_UnitAuras.GetBuffDataByIndex("player", i)
        if not aura then break end
        i = i + 1

        local iid = aura.auraInstanceID
        if not iid then break end

        local old_entry = old_map[iid]
        local safe_spell_id = get_safe_spell_id(aura.spellId, old_entry)
        local duration = aura.duration
        local expiration = aura.expirationTime
        local rem = compute_remaining(duration, expiration)
        -- Only call GetAuraDuration when the raw scan fields are secret/nil.
        -- Out of combat rem is always readable, so this avoids the API call entirely.
        local need_live = (rem == nil) or issecretvalue(rem) or issecretvalue(expiration)
        local live_duration = need_live and C_UnitAuras.GetAuraDuration("player", iid)
        local live_expiration = nil
        local live_remaining = nil
        if live_duration then
            if live_duration.GetExpirationTime then
                local e = live_duration:GetExpirationTime()
                if e ~= nil and not issecretvalue(e) then
                    live_expiration = e
                end
            end
            local r = live_duration:GetRemainingDuration()
            if r ~= nil and not issecretvalue(r) then
                live_remaining = r
            end
        end

        local category = nil
        local static_confirmed = false

        -- Use the best available remaining time for classification.
        -- live_remaining is preferred (readable via GetAuraDuration even in combat);
        -- fall back to rem (from scan fields) which may be nil/secret.
        local classify_rem = live_remaining or rem

        -- Self-heal stale static-learning entries when we now see a readable duration.
        if safe_spell_id
                and M.db.known_static_spell_ids[safe_spell_id]
                and classify_rem ~= nil
                and not issecretvalue(classify_rem)
                and classify_rem > 0 then
            M.db.known_static_spell_ids[safe_spell_id] = nil
        end

        if safe_spell_id and M.db.known_static_spell_ids[safe_spell_id] then
            category = "show_static"
            static_confirmed = true
        elseif safe_spell_id and M.db.known_long_spell_ids[safe_spell_id] and classify_rem == nil then
            -- Brand-new long buff in combat: all time fields are secret, but we
            -- learned this spell was long-duration out-of-combat.
            category = "show_long"
        elseif classify_rem ~= nil then
            if classify_rem == 0 then
                category = "show_static"
                static_confirmed = true
            elseif classify_rem <= short_threshold then
                category = "show_short"
            else
                category = "show_long"
            end
        else
            local expires = C_UnitAuras.DoesAuraHaveExpirationTime("player", iid)
            local expires_known
            if type(expires) ~= "boolean" or issecretvalue(expires) then
                expires_known = nil
            else
                expires_known = expires
            end

            if expires_known == false then
                category = "show_static"
                static_confirmed = true
            elseif expires_known == true then
                -- Refreshed buffs get a new auraInstanceID; prefer spell-based old cat.
                local old_cat = old_cat_iid[iid] or (safe_spell_id and old_cat_spell[safe_spell_id])
                if old_cat then
                    category = old_cat
                else
                    category = "show_short"
                end
            else
                local old_cat = old_cat_iid[iid] or (safe_spell_id and old_cat_spell[safe_spell_id])
                if old_cat then
                    category = old_cat
                elseif added_lookup[iid] and replacement_pref then
                    category = replacement_pref
                else
                    -- Unknown expiration state: prefer short over static to avoid
                    -- permanently mis-learning timed buffs as static.
                    category = "show_short"
                end
            end
        end

        if category then
            local name = aura.name
            local icon = aura.icon
            local dispel = aura.dispelName
            if issecretvalue(dispel) then dispel = nil end

            local applications = aura.applications
            local stacks = (not issecretvalue(applications) and applications and applications > 1) and applications or 0

            local safe_duration = (not issecretvalue(duration)) and duration
                or (old_entry and old_entry.duration)
                or 0
            local safe_expiration = (not issecretvalue(expiration)) and expiration
                or live_expiration
                or (live_remaining and live_remaining > 0 and (GetTime() + live_remaining))
                or (old_entry and old_entry.expiration)
                or 0
            local safe_remaining = rem
            if live_remaining and live_remaining > 0 then
                safe_remaining = live_remaining
            elseif (not safe_remaining or safe_remaining <= 0) and safe_expiration and safe_expiration > 0 then
                safe_remaining = math_max(0, safe_expiration - GetTime())
            elseif (not safe_remaining or safe_remaining <= 0) and old_entry and old_entry.remaining then
                safe_remaining = old_entry.remaining
            end

            local key = make_order_key(aura.spellId, name, icon, "HELPFUL")
            local recovered_added_at = (old_entry and old_entry.added_at)
                or (key and old_added_by_key[key] or nil)

            local entry = make_entry(
                iid,
                name,
                icon,
                safe_duration,
                safe_expiration,
                safe_spell_id,
                dispel,
                safe_remaining or 0,
                stacks,
                "HELPFUL",
                recovered_added_at or GetTime()
            )

            new_map[iid] = entry
            new_cat_iid[iid] = category
            if safe_spell_id then
                new_cat_spell[safe_spell_id] = category
            end

            if category == "show_static" and safe_spell_id and static_confirmed then
                M.db.known_static_spell_ids[safe_spell_id] = true
            end
            if category == "show_long" and safe_spell_id and classify_rem ~= nil then
                -- Only learn from readable remaining so we don't lock in a wrong value.
                M.db.known_long_spell_ids[safe_spell_id] = true
            end

            count = count + 1
        end
    end

    shared.map = new_map
    shared.category_by_iid = new_cat_iid
    shared.category_by_spell = new_cat_spell
    return shared
end

-- Full scan using ElkBuffBars approach:
--   • Runs after deferred bucket, including in combat
--   • issecretvalue() only where comparisons/arithmetic need protection
--   • Stores raw name/icon fields for rendering, even if secret
--   • Uses UNIT_AURA payload as a hint for brand-new unknown-timing auras
local function full_scan(aura_map, filter, show_key, short_threshold, max_limit, info)
    local get_fn = (filter == "HELPFUL")
        and C_UnitAuras.GetBuffDataByIndex
        or  C_UnitAuras.GetDebuffDataByIndex

    local added_lookup, added_count = build_added_lookup(info)

    local removed_count = 0
    if info and info.removedAuraInstanceIDs then
        removed_count = #info.removedAuraInstanceIDs
    end

    -- Snapshot pre-wipe so we can restore entries when fields turn secret
    local old_map = {}
    for iid, entry in pairs(aura_map) do old_map[iid] = entry end
    local frame_had_removal = false
    if info and info.removedAuraInstanceIDs then
        for _, rid in ipairs(info.removedAuraInstanceIDs) do
            if old_map[rid] ~= nil then
                frame_had_removal = true
                break
            end
        end
    end
    local old_added_by_key = build_added_by_key(old_map)
    wipe(aura_map)

    local i, count = 1, 0
    while count < max_limit do
        local aura = get_fn("player", i)
        if not aura then break end
        i = i + 1

        local iid = aura.auraInstanceID  -- always readable
        if not iid then break end

        local duration    = aura.duration
        local expiration  = aura.expirationTime
        local name        = aura.name
        local icon        = aura.icon
        local dispel      = aura.dispelName
        local applications = aura.applications
        local stacks = (not issecretvalue(applications) and applications and applications > 1) and applications or 0

        local rem = compute_remaining(duration, expiration)

        if rem == nil then
            -- ----------------------------------------------------------------
            -- Secret duration: use safe boolean API (ElkBuffBars technique).
            -- We know the aura EXISTS (we have its iid) but can't read fields.
            -- ----------------------------------------------------------------
            local expires = C_UnitAuras.DoesAuraHaveExpirationTime("player", iid)
            -- DoesAuraHaveExpirationTime can return a secret boolean — guard before any use.
            -- type() is safe on secret values; issecretvalue() catches secret booleans.
            -- type() is safe on secret values. Distinguish nil/broken from secret boolean.
            -- A secret boolean's actual value (true/false) is unreadable — permanent buffs
            -- and short procs both return secret booleans, so we cannot guess the category.
            -- Use nil as a sentinel meaning "unknown"; categorize via old_map only.
            local expires_known  -- true/false if readable, nil if secret/unknown
            if type(expires) ~= "boolean" then
                expires_known = false    -- nil or broken return: treat as permanent
            elseif issecretvalue(expires) then
                expires_known = nil      -- secret boolean: cannot determine value
            else
                expires_known = expires  -- real boolean: use directly
            end

            local belongs
            local added_data = added_lookup and added_lookup[iid]
            local old_entry = old_map[iid]
            local safe_spell_id = get_safe_spell_id(aura.spellId, old_entry)
            local hinted_duration
            local hinted_expiration
            local hinted_spell_id
            if type(added_data) == "table" then
                hinted_duration = added_data.duration
                if issecretvalue(hinted_duration) then hinted_duration = nil end
                hinted_expiration = added_data.expirationTime
                if issecretvalue(hinted_expiration) then hinted_expiration = nil end
                hinted_spell_id = get_safe_spell_id(added_data.spellId, nil)
            end
            local is_new_added = (old_map[iid] == nil) and (added_data ~= nil)

            -- For brand-new auras added during combat, classify deterministically:
            -- static unless we have explicit timed evidence.
            if is_new_added then
                local is_timed = false
                local timed_known = false
                local known_static = false

                if hinted_spell_id and M.db.known_static_spell_ids[hinted_spell_id] then
                    known_static = true
                elseif safe_spell_id and M.db.known_static_spell_ids[safe_spell_id] then
                    known_static = true
                end

                if known_static then
                    is_timed = false
                    timed_known = true
                end

                if not timed_known and hinted_duration ~= nil then
                    is_timed = (hinted_duration > 0)
                    timed_known = true
                elseif not timed_known and hinted_expiration ~= nil then
                    is_timed = (hinted_expiration > 0)
                    timed_known = true
                elseif not timed_known and expires_known ~= nil then
                    -- Trust explicit API boolean when readable.
                    is_timed = expires_known
                    timed_known = true
                elseif not timed_known then
                    local live_duration = C_UnitAuras.GetAuraDuration("player", iid)
                    if live_duration then
                        -- A live duration object is strong timed evidence for normal combat buffs.
                        -- Known static buffs are already handled above by the learned lookup.
                        is_timed = true
                        timed_known = true
                    end
                end

                if not timed_known then
                    -- Last resort for unknown new adds:
                    -- prefer short unless we have explicit non-expiring evidence.
                    -- This keeps normal short buffs from falling into static while
                    -- still allowing permanent auras to route static when expires_known=false.
                    if show_key == "show_static" and frame_had_removal then
                        -- Static-aura replacement in combat (e.g. paladin aura swap).
                        is_timed = false
                    elseif show_key == "show_short"
                        and not frame_had_removal
                        and removed_count > 0
                        and added_count <= 1 then
                        -- Likely replacement swap handled by another frame; prevent
                        -- unknown new aura from leaking into short as a duplicate.
                        is_timed = false
                    else
                        is_timed = (expires_known ~= false)
                    end
                end

                if show_key == "show_debuff" then
                    belongs = true
                elseif show_key == "show_static" then
                    belongs = not is_timed
                elseif show_key == "show_short" then
                    belongs = is_timed
                elseif show_key == "show_long" then
                    belongs = false
                else
                    belongs = false
                end

            elseif expires_known == nil then
                -- For established auras with fully unknown timing, keep prior placement.
                if old_map[iid] ~= nil then
                    belongs = true
                elseif show_key == "show_debuff" then
                    belongs = true
                else
                    belongs = false
                end

            elseif show_key == "show_static" then
                belongs = not expires_known

            elseif show_key == "show_long" then
                -- Keep previously-known long auras; reject new unknowns (can't confirm they're long).
                belongs = expires_known and (old_map[iid] ~= nil)

            elseif show_key == "show_short" then
                -- Show if timed and was here before, OR timed and not in the long frame's map.
                if expires_known then
                    if old_map[iid] then
                        belongs = true
                    else
                        local long_frame = M.frames and M.frames["show_long"]
                        local long_map = long_frame and long_frame._aura_map
                        belongs = not (long_map and long_map[iid])
                    end
                else
                    belongs = false
                end

            else  -- show_debuff
                belongs = true
            end

            if belongs then
                -- Restore the previous entry when available (keeps full name/icon/duration from OOC).
                -- New auras with entirely secret fields get a minimal stub.
                local entry = old_map[iid]
                if not entry then
                    local key = make_order_key(aura.spellId, name, icon, filter)
                    local recovered_added_at = key and old_added_by_key[key] or nil
                    entry = make_entry(iid, name, icon, 0, 0, safe_spell_id, dispel, 0, stacks, filter, recovered_added_at or GetTime())
                end
                aura_map[iid] = entry
                count = count + 1
            end
        else
            -- ----------------------------------------------------------------
            -- Normal case: duration is readable.
            -- ----------------------------------------------------------------
            local belongs = categorize_aura(rem, show_key, short_threshold)

            -- For debuffs: also show if they have a readable dispel type
            if not belongs and filter == "HARMFUL" then
                if not issecretvalue(dispel) and dispel and dispel ~= "" then
                    belongs = true
                end
            end

            if belongs then
                local old_entry = old_map[iid]
                local safe_spell_id = get_safe_spell_id(aura.spellId, old_entry)
                local safe_duration = (not issecretvalue(duration)) and duration
                    or (old_entry and old_entry.duration)
                    or 0
                local safe_expiration = (not issecretvalue(expiration)) and expiration
                    or (old_entry and old_entry.expiration)
                    or 0
                local safe_count = (not issecretvalue(applications) and applications and applications > 1) and applications
                    or (old_entry and old_entry.count)
                    or 0
                local safe_remaining = rem
                if (not safe_remaining or safe_remaining <= 0) and safe_expiration and safe_expiration > 0 then
                    safe_remaining = math_max(0, safe_expiration - GetTime())
                elseif (not safe_remaining or safe_remaining <= 0) and old_entry and old_entry.remaining then
                    safe_remaining = old_entry.remaining
                end
                local key = make_order_key(aura.spellId, name, icon, filter)
                local recovered_added_at = (old_entry and old_entry.added_at)
                    or (key and old_added_by_key[key] or nil)
                aura_map[iid] = make_entry(
                    iid, name, icon,
                    safe_duration, safe_expiration,
                    safe_spell_id, dispel,
                    safe_remaining or 0, safe_count, filter,
                    recovered_added_at or GetTime()
                )

                if show_key == "show_static" and safe_spell_id then
                    M.db.known_static_spell_ids[safe_spell_id] = true
                end
                count = count + 1
            end
        end
    end
end

-- Render the aura_map into the icon pool.
-- Uses C_UnitAuras.GetUnitAuraInstanceIDs for sort order (ElkBuffBars technique):
-- the game provides a pre-sorted list of IDs; we display only those in our map.
local function render_aura_map(self, aura_map, bar_mode, color, bar_bg_color, max_limit, filter, sort_mode, show_timer_text)
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
            obj.bar:SetStatusBarColor(color.r, color.g, color.b)
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
                local short_threshold = (M.db and M.db.short_threshold) or 60
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

-- ============================================================================
-- LAYOUT ENGINE: Pre-calculates positions. Only runs out of combat or on init.

function M.setup_layout(self, show_key, spacing_key, bar_mode)
    if not self or not self.icons then return end

    local db = M.db
    local category = show_key:sub(6)
    local frame_width = db["width_"..category] or 200
    local spacing = db[spacing_key] or 6
    local growth = db["growth_"..category] or "DOWN"

    local show_timer_text = is_timer_text_enabled(db, category)
    local timer_font_size = (M.get_timer_number_font_size and M.get_timer_number_font_size(category)) or 10
    local bar_layout = get_bar_layout_params(timer_font_size)
    local timer_text_align = (category == "long") and "CENTER" or "RIGHT"
    -- Anchor point matches horizontal justification so timer text grows/shrinks
    -- from the same reference point inside the fixed timer slot.
    local timer_anchor_point = (timer_text_align == "CENTER") and "CENTER" or "RIGHT"
    local bar_timer_slot_width = bar_layout.timer_slot_width
    local bar_timer_slot_right_pad = bar_layout.timer_slot_right_pad

    local icon_size = 32
    local icon_footprint = icon_size + spacing
    local icons_per_row = (growth == "DOWN" or growth == "UP")
        and 1
        or math_max(1, floor((frame_width - 12 + spacing) / icon_footprint))

    for i = 1, #self.icons do
        local obj = self.icons[i]
        obj:ClearAllPoints()
        obj.texture:ClearAllPoints()

        if bar_mode then
            local bar_h = bar_layout.row_height
            local step  = bar_h + spacing
            obj:SetSize(frame_width - bar_layout.frame_inner_width_pad, bar_h)

            if growth == "UP" then
                obj:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", bar_layout.frame_inset, (i - 1) * step + bar_layout.frame_inset)
            else
                obj:SetPoint("TOPLEFT", self, "TOPLEFT", bar_layout.frame_inset, -((i - 1) * step + bar_layout.frame_inset))
            end

            obj.texture:SetSize(bar_layout.icon_size, bar_layout.icon_size)
            obj.texture:SetPoint("LEFT", obj, "LEFT", 0, 0)

            obj.bar:ClearAllPoints()
            obj.bar:SetPoint("LEFT", obj.texture, "RIGHT", bar_layout.icon_to_bar_gap, 0)
            obj.bar:SetPoint("RIGHT", obj, "RIGHT", 0, 0)
            obj.bar:SetHeight(bar_layout.bar_height)

            -- Stack slot: left zone (stack count area)
            obj.stack_slot:ClearAllPoints()
            obj.stack_slot:SetPoint("LEFT", obj.bar, "LEFT", bar_layout.stack_slot_left_pad, 0)
            obj.stack_slot:SetSize(bar_layout.stack_slot_width, bar_layout.stack_slot_height)
            obj.stack_slot:Show()

            -- Timer slot: right zone
            obj.timer_slot:ClearAllPoints()
            obj.timer_slot:SetPoint("RIGHT", obj.bar, "RIGHT", -bar_timer_slot_right_pad, 0)
            obj.timer_slot:SetSize(bar_timer_slot_width, bar_layout.timer_slot_height)

            -- Name slot: middle zone, between stack and timer
            obj.name_slot:ClearAllPoints()
            obj.name_slot:SetPoint("LEFT", obj.stack_slot, "RIGHT", bar_layout.name_slot_left_gap, 0)
            if show_timer_text then
                obj.name_slot:SetPoint("RIGHT", obj.timer_slot, "LEFT", -bar_layout.name_slot_right_gap, 0)
            else
                obj.name_slot:SetPoint("RIGHT", obj.bar, "RIGHT", -bar_layout.name_slot_right_no_timer, 0)
            end
            obj.name_slot:SetHeight(bar_layout.name_slot_height)
            obj.name_slot:Show()

            obj.name_text:ClearAllPoints()
            obj.name_text:SetPoint("LEFT", obj.name_slot, "LEFT", bar_layout.name_text_left_pad, 0)
            obj.name_text:SetPoint("RIGHT", obj.name_slot, "RIGHT", -bar_layout.name_text_right_pad, 0)
            obj.name_text:SetJustifyV("MIDDLE")
            obj.name_text:Show()

            obj.time_text:ClearAllPoints()
            obj.time_text:SetJustifyV("MIDDLE")
            obj.time_text:SetPoint(timer_anchor_point, obj.timer_slot, timer_anchor_point, 0, 0)
            obj.time_text:SetWidth(bar_timer_slot_width)
            obj.time_text:SetJustifyH(timer_text_align)
            if show_timer_text then
                obj.timer_slot:Show()
                obj.time_text:Show()
            else
                obj.timer_slot:Hide()
                obj.time_text:Hide()
            end

            obj.count_text:ClearAllPoints()
            obj.count_text:SetPoint("CENTER", obj.stack_slot, "CENTER", 0, 0)
            obj.count_text:Hide()  -- stacks shown inline with name in bar mode

        else
            obj:SetSize(icon_size, icon_size)
            obj.texture:SetAllPoints(obj)

            local col_idx = (i - 1) % icons_per_row
            local row_idx = floor((i - 1) / icons_per_row)
            local row_h   = icon_size + spacing + 12

            -- Always anchor according to growth direction, even for test/preview icon
            if growth == "UP" then
                obj:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 6, row_idx * row_h + 6)
            elseif growth == "DOWN" then
                obj:SetPoint("TOPLEFT", self, "TOPLEFT", 6, -(row_idx * row_h + 6))
            elseif growth == "LEFT" then
                obj:SetPoint("TOPRIGHT", self, "TOPRIGHT",
                    -(col_idx * icon_footprint + 6), -(row_idx * row_h + 6))
            else  -- RIGHT (default)
                obj:SetPoint("TOPLEFT", self, "TOPLEFT",
                    col_idx * icon_footprint + 6, -(row_idx * row_h + 6))
            end

            obj.stack_slot:ClearAllPoints()
            obj.stack_slot:Hide()

            obj.name_slot:ClearAllPoints()
            obj.name_slot:Hide()

            obj.name_text:ClearAllPoints()
            obj.name_text:Hide()

            obj.timer_slot:ClearAllPoints()
            obj.timer_slot:SetPoint("TOPRIGHT", obj, "BOTTOMRIGHT", 0, -2)
            obj.timer_slot:SetSize(icon_size, 12)

            obj.time_text:ClearAllPoints()
            obj.time_text:SetPoint(timer_anchor_point, obj.timer_slot, timer_anchor_point, 0, 0)
            obj.time_text:SetWidth(icon_size)
            obj.time_text:SetJustifyH(timer_text_align)
            if show_timer_text then
                obj.timer_slot:Show()
                obj.time_text:Show()
            else
                obj.timer_slot:Hide()
                obj.time_text:Hide()
            end

            -- Stack count: bottom-right corner of icon (matches WoW default buff display)
            obj.count_text:ClearAllPoints()
            obj.count_text:SetPoint("BOTTOMRIGHT", obj, "BOTTOMRIGHT", 0, 1)
        end
    end

    self._layout_cache = {
        bar_mode        = bar_mode,
        show_timer_text = show_timer_text,
        icons_per_row   = icons_per_row,
        frame_width     = frame_width,
        spacing         = spacing,
        growth          = growth,
        row_height      = bar_layout.row_height,
    }
end

local function set_height_for_growth(self, new_height, growth)
    if not self then return end

    local old_height = self:GetHeight()
    if old_height == new_height then return end
    local delta = new_height - old_height

    -- Preserve the frame's current anchor point while resizing to prevent
    -- unwanted point flips (e.g. snapping to BOTTOMLEFT on short frame updates).
    local point, relative_to, relative_point, x, y = self:GetPoint(1)

    self:SetHeight(new_height)

    if not point then
        return
    end

    if relative_to and relative_to ~= UIParent then
        relative_to = UIParent
    end
    relative_point = relative_point or point
    x = x or 0
    y = y or 0

    -- Respect vertical growth direction even when the user anchor is center-based.
    -- DOWN keeps the top edge stable; UP keeps the bottom edge stable.
    local p = tostring(point or "")
    local is_top = p:find("TOP", 1, true) ~= nil
    local is_bottom = p:find("BOTTOM", 1, true) ~= nil
    if growth == "DOWN" then
        if is_bottom then
            y = y - delta
        elseif not is_top then
            y = y - (delta * 0.5)
        end
    elseif growth == "UP" then
        if is_top then
            y = y + delta
        elseif not is_bottom then
            y = y + (delta * 0.5)
        end
    end

    self:ClearAllPoints()
    self:SetPoint(point, relative_to or UIParent, relative_point, x, y)
end

-- ============================================================================
-- AURA SCANNING AND RENDERING

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
    local show_timer_text = is_timer_text_enabled(db, category, timer_key)
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
    -- Always enforce DB position and size, regardless of preview/test state
    self:ClearAllPoints()
    if _pos then
        self:SetPoint("TOPLEFT", UIParent, "CENTER", (_pos.x or 0) / scale, (_pos.y or 0) / scale)
    else
        self:SetPoint("TOPLEFT", UIParent, "CENTER", -100, category == "debuff" and -25 or 75)
    end
    self:SetSize(_width, _height)

    if not self._layout_cache
        or (self._layout_cache.frame_width ~= frame_width
        or   self._layout_cache.bar_mode    ~= bar_mode
        or   self._layout_cache.show_timer_text ~= show_timer_text
        or   self._layout_cache.spacing     ~= spacing
        or   self._layout_cache.growth      ~= growth
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
        -- Match minimum height for current mode (bar or icon)
        local timer_font_size = (M.get_timer_number_font_size and M.get_timer_number_font_size(category)) or 10
        local bar_layout = get_bar_layout_params(timer_font_size)
        local spacing = db[spacing_key] or 6
        local bar_mode = db["bar_mode_"..category]
        local min_height
        if bar_mode then
            min_height = (bar_layout.row_height or 18) + spacing + 12
        else
            min_height = (bar_layout.icon_size or 32) + spacing + 12
        end
        set_height_for_growth(self, min_height, growth)
        self:Show()
        return
    end

    if db[show_key] or preview_enabled then self:Show() end

    if not self._aura_map then self._aura_map = {} end

    -- Helpful auras use a shared one-pass classifier so each aura belongs to
    -- exactly one frame category at a time (static/short/long).
    if filter == "HELPFUL" then
        local shared = scan_helpful_shared(info, short_threshold, max_limit)
        wipe(self._aura_map)
        for iid, entry in pairs(shared.map) do
            if shared.category_by_iid[iid] == show_key then
                self._aura_map[iid] = entry
            end
        end
    else
        -- Debuffs remain on per-frame scan logic.
        full_scan(self._aura_map, filter, show_key, short_threshold, max_limit, info)
    end

    if preview_enabled then
        M.append_test_aura(self._aura_map, show_key, filter, short_threshold)
    else
        self._aura_map["__test_preview__"] = nil
    end

    local display_count = render_aura_map(
        self, self._aura_map, bar_mode, color, barBgC, max_limit, filter, sort_mode, show_timer_text
    )

    -- Frame height (only safe to resize out of combat)
    local lc = self._layout_cache
    local new_height = bar_mode and ((lc and lc.row_height or 18) + spacing + 12)
                                 or  ((lc and lc.icon_size or 32) + spacing + 12)
    if display_count > 0 then
        if bar_mode then
            local bar_row_h = lc and lc.row_height or 18
            new_height = display_count * (bar_row_h + spacing) + 12
        elseif lc and (lc.growth == "DOWN" or lc.growth == "UP") then
            local isz = lc.icon_size or 32
            new_height = display_count * (isz + spacing + 12) + 6
        elseif lc and lc.icons_per_row then
            local isz = lc.icon_size or 32
            local rows = math_ceil(display_count / lc.icons_per_row)
            new_height = rows * (isz + spacing + 12) + 6
        else
            new_height = display_count * 44
        end
    end

    if db[show_key] or preview_enabled then
        self:Show()
        set_height_for_growth(self, new_height, growth)
    elseif not is_moving then
        self:Hide()
    end

    if (db[show_key] or preview_enabled) and not self:IsVisible() then self:Show() end

-- Backdrop colors
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

-- Frame storage for registry and refresh
M.frames = {}
