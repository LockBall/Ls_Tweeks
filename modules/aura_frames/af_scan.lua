-- Unified aura scanning and classification for all aura frame categories (static/short/long/debuff/custom).
-- M.unified_scan() runs one pass over all player buffs and debuffs, classifying each into M._aura_map
-- with an entry.category ("static"/"short"/"long"/"debuff") and entry.is_helpful flag.
-- Spell learning (M._known_static, M._known_long) is session-scoped only — never written to DB.
-- Custom frames post-filter M._aura_map by whitelist; preset frames filter by entry.category.

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

-- Session-scoped spell classification memory (reset on every login/reload, never persisted).
-- Prevents mid-session category jumps when aura fields go secret in combat.
M._known_static = M._known_static or {}  -- spell_id -> true (confirmed permanent)
M._known_long   = M._known_long   or {}  -- spell_id -> true (confirmed long-duration)

-- ============================================================================
-- SHARED HELPERS

-- Returns remaining seconds, or nil if duration is nil/secret.
local function compute_remaining(duration, expiration)
    if not duration or issecretvalue(duration) then return nil end
    if duration <= 0 then return 0 end
    if not expiration or issecretvalue(expiration) then
        return duration
    end
    if expiration > 0 then return math_max(0, expiration - GetTime()) end
    return duration
end

-- Build an entry table.
local function make_entry(iid, name, icon, duration, expiration, spell_id, dispel_name, rem, count, is_helpful, category, added_at)
    return {
        instance_id  = iid,
        name         = name,
        icon         = icon,
        duration     = duration,
        expiration   = expiration,
        spell_id     = spell_id,
        dispel_name  = dispel_name,
        remaining    = rem,
        count        = count,
        is_helpful   = is_helpful,
        category     = category,
        filter       = is_helpful and "HELPFUL" or "HARMFUL",
        added_at     = added_at or GetTime(),
    }
end

-- Update an existing entry in place (avoids allocation on unchanged auras).
local function update_entry(entry, name, icon, duration, expiration, spell_id, dispel_name, rem, count, live_rem, live_cnt, category)
    entry.name          = name
    entry.icon          = icon
    entry.duration      = duration
    entry.expiration    = expiration
    entry.spell_id      = spell_id
    entry.dispel_name   = dispel_name
    entry.remaining     = rem
    entry.count         = count
    entry.live_remaining = live_rem
    entry.live_count    = live_cnt
    if category then entry.category = category end
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

local function make_order_key(spell_id, name, icon, is_helpful)
    local f = is_helpful and "H" or "D"
    local sid = (spell_id ~= nil and not issecretvalue(spell_id)) and tostring(spell_id) or nil
    local n   = (name    ~= nil and not issecretvalue(name))     and tostring(name)     or nil
    local ic  = (icon    ~= nil and not issecretvalue(icon))     and tostring(icon)     or nil
    if not sid and not n and not ic then return nil end
    return f .. "|" .. (sid or "") .. "|" .. (n or "") .. "|" .. (ic or "")
end

local function build_added_by_key(map)
    local by_key = {}
    for _, entry in pairs(map) do
        local key = make_order_key(entry.spell_id, entry.name, entry.icon, entry.is_helpful)
        if key and entry.added_at and (not by_key[key] or entry.added_at < by_key[key]) then
            by_key[key] = entry.added_at
        end
    end
    return by_key
end

local function build_added_lookup(info)
    local lookup = {}
    local count  = 0
    if not info then return lookup, count end
    if info.addedAuras then
        for _, a in ipairs(info.addedAuras) do
            local iid = a and a.auraInstanceID
            if iid then lookup[iid] = a; count = count + 1 end
        end
    elseif info.addedAuraInstanceIDs then
        for _, iid in ipairs(info.addedAuraInstanceIDs) do
            if iid then lookup[iid] = true; count = count + 1 end
        end
    end
    return lookup, count
end

-- ============================================================================
-- HELPFUL AURA CLASSIFICATION
-- Returns "static" | "short" | "long" for a helpful aura given its remaining time.
-- Returns nil when classification is deferred to caller (secret fields).
local function classify_helpful(classify_rem, short_threshold)
    if classify_rem == nil then return nil end
    if classify_rem == 0 then return "static" end
    if classify_rem <= short_threshold then return "short" end
    return "long"
end

-- ============================================================================
-- UNIFIED SCAN
-- Scans all player buffs and debuffs in one pass.
-- Populates M._aura_map: iid -> entry with is_helpful and category fields.
-- Preset frames filter by entry.category; custom frames filter by whitelist.
function M.unified_scan(info, short_threshold, max_helpful_hint, max_debuff_hint)
    M._aura_map = M._aura_map or {}
    local cur_map = M._aura_map

    -- Snapshot old map for stable added_at and secret-field fallback.
    -- We build a shallow copy of keys only (old entries are referenced, not cloned).
    local old_map = {}
    for iid, entry in pairs(cur_map) do old_map[iid] = entry end

    local old_added_by_key = build_added_by_key(old_map)
    local added_lookup, added_count = build_added_lookup(info)

    local removed_count = 0
    local replacement_pref_cat = nil  -- category hint from a 1-for-1 swap
    if info and info.removedAuraInstanceIDs then
        removed_count = #info.removedAuraInstanceIDs
        if removed_count == 1 and added_count == 1 then
            local rid = info.removedAuraInstanceIDs[1]
            local old = old_map[rid]
            if old then replacement_pref_cat = old.category end
        end
    end

    local db = M.db
    local seen_iids = {}

    -- -------------------------------------------------------------------------
    -- PASS 1: HELPFUL (buffs)
    -- -------------------------------------------------------------------------
    local max_helpful = math_max(
        max_helpful_hint or 0,
        math_max(db.max_icons_static or 40, math_max(db.max_icons_short or 40, db.max_icons_long or 40))
    )

    -- Track old category by spell for cross-session refresh hinting.
    -- Built lazily from old_map each scan — no persistent table needed.
    local old_cat_by_spell = {}
    for _, entry in pairs(old_map) do
        if entry.is_helpful and entry.spell_id and entry.category then
            old_cat_by_spell[entry.spell_id] = entry.category
        end
    end

    local i, count = 1, 0
    while count < max_helpful do
        local aura = C_UnitAuras.GetBuffDataByIndex("player", i)
        if not aura then break end
        i = i + 1

        local iid = aura.auraInstanceID
        if not iid then break end

        local old_entry     = old_map[iid]
        local safe_spell_id = get_safe_spell_id(aura.spellId, old_entry)
        local duration      = aura.duration
        local expiration    = aura.expirationTime
        local rem           = compute_remaining(duration, expiration)

        -- GetAuraDuration is readable even when scan fields are secret (combat).
        local need_live = (rem == nil) or issecretvalue(rem) or issecretvalue(expiration)
        local live_duration   = need_live and C_UnitAuras.GetAuraDuration("player", iid)
        local live_expiration = nil
        local live_remaining  = nil
        if live_duration then
            if live_duration.GetExpirationTime then
                local e = live_duration:GetExpirationTime()
                if e ~= nil and not issecretvalue(e) then live_expiration = e end
            end
            local r = live_duration:GetRemainingDuration()
            if r ~= nil and not issecretvalue(r) then live_remaining = r end
        end

        local classify_rem = live_remaining or rem

        -- Self-heal stale static-learning when we now see a readable duration > 0.
        if safe_spell_id and M._known_static[safe_spell_id]
                and classify_rem ~= nil and not issecretvalue(classify_rem)
                and classify_rem > 0 then
            M._known_static[safe_spell_id] = nil
        end

        local category     = nil
        local static_confirmed = false

        if safe_spell_id and M._known_static[safe_spell_id] then
            category = "static"
            static_confirmed = true
        elseif safe_spell_id and M._known_long[safe_spell_id] and classify_rem == nil then
            -- Brand-new long buff in combat: all time fields secret but we learned it OOC.
            category = "long"
        elseif classify_rem ~= nil then
            category = classify_helpful(classify_rem, short_threshold)
            if category == "static" then static_confirmed = true end
        else
            -- Secret fields: use DoesAuraHaveExpirationTime as final boolean.
            local expires = C_UnitAuras.DoesAuraHaveExpirationTime("player", iid)
            local expires_known
            if type(expires) ~= "boolean" or issecretvalue(expires) then
                expires_known = nil
            else
                expires_known = expires
            end

            if expires_known == false then
                category = "static"
                static_confirmed = true
            elseif expires_known == true then
                local old_cat = (old_entry and old_entry.category)
                    or (safe_spell_id and old_cat_by_spell[safe_spell_id])
                category = old_cat or "short"
            else
                local old_cat = (old_entry and old_entry.category)
                    or (safe_spell_id and old_cat_by_spell[safe_spell_id])
                if old_cat then
                    category = old_cat
                elseif added_lookup[iid] and replacement_pref_cat then
                    category = replacement_pref_cat
                else
                    category = "short"
                end
            end
        end

        if category then
            local name  = aura.name
            local icon  = aura.icon
            local dispel = aura.dispelName
            if issecretvalue(dispel) then dispel = nil end

            local applications = aura.applications
            local stacks = (not issecretvalue(applications) and applications and applications > 1) and applications or 0
            local live_count = (stacks == 0) and C_UnitAuras.GetAuraApplicationDisplayCount("player", iid) or nil

            local safe_duration = (not issecretvalue(duration)) and duration
                or (old_entry and old_entry.duration) or 0
            local safe_expiration = (not issecretvalue(expiration)) and expiration
                or live_expiration
                or (live_remaining and live_remaining > 0 and (GetTime() + live_remaining))
                or (old_entry and old_entry.expiration) or 0
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
                    safe_spell_id, dispel, safe_remaining or 0, stacks, live_remaining, live_count, category)
            else
                local key = make_order_key(aura.spellId, name, icon, true)
                local recovered_at = (old_entry and old_entry.added_at)
                    or (key and old_added_by_key[key]) or nil
                entry = make_entry(iid, name, icon, safe_duration, safe_expiration,
                    safe_spell_id, dispel, safe_remaining or 0, stacks,
                    true, category, recovered_at or GetTime())
                entry.live_remaining = live_remaining
                entry.live_count     = live_count
                cur_map[iid] = entry
            end
            seen_iids[iid] = true

            -- Session-scoped learning.
            if category == "static" and safe_spell_id and static_confirmed then
                M._known_static[safe_spell_id] = true
            end
            if category == "long" and safe_spell_id and classify_rem ~= nil then
                M._known_long[safe_spell_id] = true
            end

            count = count + 1
        end
    end

    -- -------------------------------------------------------------------------
    -- PASS 2: HARMFUL (debuffs)
    -- -------------------------------------------------------------------------
    local max_debuff = math_max(max_debuff_hint or 0, db.max_icons_debuff or 40)

    i, count = 1, 0
    while count < max_debuff do
        local aura = C_UnitAuras.GetDebuffDataByIndex("player", i)
        if not aura then break end
        i = i + 1

        local iid = aura.auraInstanceID
        if not iid then break end

        local old_entry     = old_map[iid]
        local duration      = aura.duration
        local expiration    = aura.expirationTime
        local name          = aura.name
        local icon          = aura.icon
        local dispel        = aura.dispelName
        if issecretvalue(dispel) then dispel = nil end
        local applications  = aura.applications
        local stacks = (not issecretvalue(applications) and applications and applications > 1) and applications or 0

        local rem = compute_remaining(duration, expiration)
        local belongs = false

        if rem == nil then
            -- Secret fields: use DoesAuraHaveExpirationTime.
            local expires = C_UnitAuras.DoesAuraHaveExpirationTime("player", iid)
            local expires_known
            if type(expires) ~= "boolean" then
                expires_known = false
            elseif issecretvalue(expires) then
                expires_known = nil
            else
                expires_known = expires
            end

            local added_data  = added_lookup and added_lookup[iid]
            local safe_spell_id = get_safe_spell_id(aura.spellId, old_entry)
            local hinted_duration, hinted_expiration, hinted_spell_id
            if type(added_data) == "table" then
                hinted_duration = added_data.duration
                if issecretvalue(hinted_duration) then hinted_duration = nil end
                hinted_expiration = added_data.expirationTime
                if issecretvalue(hinted_expiration) then hinted_expiration = nil end
                hinted_spell_id = get_safe_spell_id(added_data.spellId, nil)
            end
            local is_new = (old_map[iid] == nil) and (added_data ~= nil)

            if is_new then
                -- Debuffs always belong to the debuff frame regardless of timing.
                belongs = true
            elseif expires_known == nil then
                belongs = (old_map[iid] ~= nil)
            else
                belongs = true
            end
        else
            -- Readable duration: debuffs with a dispel type also belong.
            belongs = true
            if not belongs and not issecretvalue(dispel) and dispel and dispel ~= "" then
                belongs = true
            end
        end

        if belongs then
            local safe_spell_id = get_safe_spell_id(aura.spellId, old_entry)
            local safe_duration = (not issecretvalue(duration)) and duration
                or (old_entry and old_entry.duration) or 0
            local safe_expiration = (not issecretvalue(expiration)) and expiration
                or (old_entry and old_entry.expiration) or 0
            local safe_remaining = rem
            if (not safe_remaining or safe_remaining <= 0) and safe_expiration and safe_expiration > 0 then
                safe_remaining = math_max(0, safe_expiration - GetTime())
            elseif (not safe_remaining or safe_remaining <= 0) and old_entry and old_entry.remaining then
                safe_remaining = old_entry.remaining
            end
            local live_count = (stacks == 0) and C_UnitAuras.GetAuraApplicationDisplayCount("player", iid) or nil

            local entry = cur_map[iid]
            if entry then
                update_entry(entry, name, icon, safe_duration, safe_expiration,
                    safe_spell_id, dispel, safe_remaining or 0, stacks, nil, live_count, "debuff")
                entry.is_helpful = false
            else
                local key = make_order_key(aura.spellId, name, icon, false)
                local recovered_at = (old_entry and old_entry.added_at)
                    or (key and old_added_by_key[key]) or nil
                entry = make_entry(iid, name, icon, safe_duration, safe_expiration,
                    safe_spell_id, dispel, safe_remaining or 0, stacks,
                    false, "debuff", recovered_at or GetTime())
                entry.live_count = live_count
                cur_map[iid] = entry
            end
            seen_iids[iid] = true
            count = count + 1
        end
    end

    -- -------------------------------------------------------------------------
    -- CLEANUP: remove stale IIDs not seen this scan pass.
    -- -------------------------------------------------------------------------
    for iid in pairs(cur_map) do
        if not seen_iids[iid] then cur_map[iid] = nil end
    end
end

-- ============================================================================
-- MERGE HELPER (unchanged from original — used by af_main event handler)
function M.merge_aura_info(existing, new_info)
    if not new_info then return existing end
    if not existing then return new_info end

    local merged = {}

    -- Merge addedAuras
    if new_info.addedAuras or existing.addedAuras then
        merged.addedAuras = {}
        if existing.addedAuras then
            for _, a in ipairs(existing.addedAuras) do
                merged.addedAuras[#merged.addedAuras + 1] = a
            end
        end
        if new_info.addedAuras then
            for _, a in ipairs(new_info.addedAuras) do
                merged.addedAuras[#merged.addedAuras + 1] = a
            end
        end
    end

    -- Merge addedAuraInstanceIDs
    if new_info.addedAuraInstanceIDs or existing.addedAuraInstanceIDs then
        merged.addedAuraInstanceIDs = {}
        if existing.addedAuraInstanceIDs then
            for _, id in ipairs(existing.addedAuraInstanceIDs) do
                merged.addedAuraInstanceIDs[#merged.addedAuraInstanceIDs + 1] = id
            end
        end
        if new_info.addedAuraInstanceIDs then
            for _, id in ipairs(new_info.addedAuraInstanceIDs) do
                merged.addedAuraInstanceIDs[#merged.addedAuraInstanceIDs + 1] = id
            end
        end
    end

    -- Merge removedAuraInstanceIDs
    if new_info.removedAuraInstanceIDs or existing.removedAuraInstanceIDs then
        merged.removedAuraInstanceIDs = {}
        if existing.removedAuraInstanceIDs then
            for _, id in ipairs(existing.removedAuraInstanceIDs) do
                merged.removedAuraInstanceIDs[#merged.removedAuraInstanceIDs + 1] = id
            end
        end
        if new_info.removedAuraInstanceIDs then
            for _, id in ipairs(new_info.removedAuraInstanceIDs) do
                merged.removedAuraInstanceIDs[#merged.removedAuraInstanceIDs + 1] = id
            end
        end
    end

    return merged
end

-- ============================================================================
-- SORT HELPER (used by af_render.lua)
function M.get_entry_sort_id(entry)
    if type(entry.instance_id) == "number" then return entry.instance_id end
    return entry.preview_sort_id or 0
end
