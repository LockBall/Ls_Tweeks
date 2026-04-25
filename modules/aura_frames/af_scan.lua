-- Aura scanning and classification into static / short / long / debuff category maps.
-- In combat, WoW hides aura duration and expiration as "secret values" to prevent ability tracking.
-- This file works around that by calling C_UnitAuras.GetAuraDuration() which returns a live Duration
-- object readable even in combat, and by learning spell IDs out of combat (known_static_spell_ids,
-- known_long_spell_ids) so auras can be re-categorized stably when their fields go secret mid-fight.
-- DoesAuraHaveExpirationTime() provides a final fallback boolean when all time fields are unreadable.

local addon_name, addon = ...

local floor      = math.floor
local math_max   = math.max
local GetTime    = GetTime
local wipe       = wipe
local issecretvalue = issecretvalue
local C_UnitAuras   = C_UnitAuras
local format        = format

addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

-- ============================================================================
-- AURA CLASSIFICATION

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

-- Update an existing entry table in place (avoids allocation on unchanged auras).
local function update_entry(entry, name, icon, duration, expiration, spell_id, dispel_name, rem, count, live_rem, live_cnt)
    entry.name          = name
    entry.icon          = icon
    entry.duration      = duration
    entry.expiration    = expiration
    entry.spell_id      = spell_id
    entry.dispel_name   = dispel_name
    entry.remaining     = rem
    entry.count         = count
    entry.live_remaining = live_rem
    entry.live_count     = live_cnt
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

-- ============================================================================
-- HELPFUL AURA SHARED SCAN

-- Shared helpful-aura scan/classifier.
-- 12.0.5+ API usage:
--   * C_UnitAuras.GetBuffDataByIndex
--   * C_UnitAuras.DoesAuraHaveExpirationTime
--   * C_UnitAuras.GetAuraDuration
-- Each helpful aura is assigned to exactly one category: static/short/long.
function M.scan_helpful_shared(info, short_threshold, max_limit_hint)
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

    -- Update shared maps in place: track which IIDs are seen this scan,
    -- then remove stale ones after the loop. Avoids wipe + full realloc.
    local cur_map      = shared.map
    local cur_cat_iid  = shared.category_by_iid
    local cur_cat_spell = shared.category_by_spell
    local seen_iids = {}

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
            local need_live_count = (stacks == 0)
            local live_count = need_live_count and C_UnitAuras.GetAuraApplicationDisplayCount("player", iid) or nil

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

            local entry = cur_map[iid]
            if entry then
                update_entry(entry, name, icon, safe_duration, safe_expiration,
                    safe_spell_id, dispel, safe_remaining or 0, stacks, live_remaining, live_count)
            else
                local key = make_order_key(aura.spellId, name, icon, "HELPFUL")
                local recovered_added_at = (old_entry and old_entry.added_at)
                    or (key and old_added_by_key[key] or nil)
                entry = make_entry(iid, name, icon, safe_duration, safe_expiration,
                    safe_spell_id, dispel, safe_remaining or 0, stacks,
                    "HELPFUL", recovered_added_at or GetTime())
                entry.live_remaining = live_remaining
                entry.live_count     = live_count
                cur_map[iid] = entry
            end
            seen_iids[iid] = true
            cur_cat_iid[iid] = category
            if safe_spell_id then
                cur_cat_spell[safe_spell_id] = category
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

    -- Remove IIDs that were not seen in this scan pass.
    for iid in pairs(cur_map) do
        if not seen_iids[iid] then
            cur_map[iid] = nil
            cur_cat_iid[iid] = nil
        end
    end
    -- Purge stale spell->category entries (a spell may have changed category).
    for spell_id in pairs(cur_cat_spell) do
        if not seen_iids[spell_id] then
            -- spell_id key is used, not iid; only purge if no live entry holds it
            local still_live = false
            for _, entry in pairs(cur_map) do
                if entry.spell_id == spell_id then still_live = true; break end
            end
            if not still_live then cur_cat_spell[spell_id] = nil end
        end
    end
    return shared
end

-- ============================================================================
-- FULL SCAN (debuffs + per-frame helpful fallback)

-- Full scan using ElkBuffBars approach:
--   • Runs after deferred bucket, including in combat
--   • issecretvalue() only where comparisons/arithmetic need protection
--   • Stores raw name/icon fields for rendering, even if secret
--   • Uses UNIT_AURA payload as a hint for brand-new unknown-timing auras
function M.full_scan(aura_map, filter, show_key, short_threshold, max_limit, info)
    local get_fn = (filter == "HELPFUL")
        and C_UnitAuras.GetBuffDataByIndex
        or  C_UnitAuras.GetDebuffDataByIndex

    local added_lookup, added_count = build_added_lookup(info)

    local removed_count = 0
    if info and info.removedAuraInstanceIDs then
        removed_count = #info.removedAuraInstanceIDs
    end

    -- Snapshot the pre-scan state without copying (we need old data for secret-field fallback).
    -- Use a cheap alias; full_scan will update aura_map in place.
    local old_map = aura_map  -- same table reference — we read before writing each slot
    local seen_iids = {}
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
                if not old_map[iid] then
                    local key = make_order_key(aura.spellId, name, icon, filter)
                    local recovered_added_at = key and old_added_by_key[key] or nil
                    aura_map[iid] = make_entry(iid, name, icon, 0, 0, safe_spell_id, dispel, 0, stacks, filter, recovered_added_at or GetTime())
                end
                -- existing entry stays in place (already in aura_map)
                seen_iids[iid] = true
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
                local need_live_count = (safe_count == 0)
                local live_count = need_live_count and C_UnitAuras.GetAuraApplicationDisplayCount("player", iid) or nil
                local safe_remaining = rem
                if (not safe_remaining or safe_remaining <= 0) and safe_expiration and safe_expiration > 0 then
                    safe_remaining = math_max(0, safe_expiration - GetTime())
                elseif (not safe_remaining or safe_remaining <= 0) and old_entry and old_entry.remaining then
                    safe_remaining = old_entry.remaining
                end
                if old_entry then
                    update_entry(old_entry, name, icon, safe_duration, safe_expiration,
                        safe_spell_id, dispel, safe_remaining or 0, safe_count, nil, live_count)
                else
                    local key = make_order_key(aura.spellId, name, icon, filter)
                    local recovered_added_at = key and old_added_by_key[key] or nil
                    local e = make_entry(iid, name, icon, safe_duration, safe_expiration,
                        safe_spell_id, dispel, safe_remaining or 0, safe_count, filter,
                        recovered_added_at or GetTime())
                    e.live_count = live_count
                    aura_map[iid] = e
                end
                seen_iids[iid] = true

                if show_key == "show_static" and safe_spell_id then
                    M.db.known_static_spell_ids[safe_spell_id] = true
                end
                count = count + 1
            end
        end
    end

    -- Remove IIDs that were not seen in this scan pass (aura expired/removed).
    for iid in pairs(aura_map) do
        if not seen_iids[iid] then
            aura_map[iid] = nil
        end
    end
end
