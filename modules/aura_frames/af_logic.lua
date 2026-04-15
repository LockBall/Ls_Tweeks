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
    if s >= 3600 then return format("%dh", floor(s/3600)) end
    if s >= 60 then return format("%dm", floor(s/60)) end
    if s >= 5 then return format("%ds", floor(s)) end
    return format("%.1fs", s)
end
M.format_time = format_time

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

-- Apply delta updates during combat using UNIT_AURA event info parameter.
-- Supports both modern payloads (`addedAuras`) and ID-only payloads.
local function apply_combat_delta(aura_map, info, filter, show_key, short_threshold)
    if not info then return false end
    
    -- Remove auras (safe: instance IDs never tainted)
    if info.removedAuraInstanceIDs then
        for _, iid in ipairs(info.removedAuraInstanceIDs) do
            aura_map[iid] = nil
        end
    end
    
    -- Add new auras.
    -- Prefer `addedAuras` when available (can include useful safe fields).
    if info.addedAuras then
        for _, aura in ipairs(info.addedAuras) do
            local iid = aura and aura.auraInstanceID
            if iid and not aura_map[iid] then
                local helpful = aura.isHelpful
                local harmful = aura.isHarmful
                if issecretvalue(helpful) then helpful = nil end
                if issecretvalue(harmful) then harmful = nil end

                local wrong_filter = (filter == "HELPFUL" and harmful == true)
                    or (filter == "HARMFUL" and helpful == true)

                if not wrong_filter then
                    local duration = aura.duration
                    if issecretvalue(duration) then duration = nil end
                    local expiration = aura.expirationTime
                    if issecretvalue(expiration) then expiration = nil end

                    local rem = compute_remaining(duration, expiration)
                    local belongs = false

                    if show_key == "show_debuff" then
                        belongs = true
                    elseif rem ~= nil then
                        belongs = categorize_aura(rem, show_key, short_threshold)
                    else
                        -- Unknown timing in combat: safest mapping is timed->short, permanent->static.
                        local expires = C_UnitAuras.DoesAuraHaveExpirationTime("player", iid)
                        local expires_known
                        if type(expires) ~= "boolean" then
                            expires_known = false
                        elseif issecretvalue(expires) then
                            expires_known = nil
                        else
                            expires_known = expires
                        end

                        if show_key == "show_static" then
                            belongs = (expires_known == false)
                        elseif show_key == "show_short" then
                            belongs = (expires_known == true) or (expires_known == nil)
                        elseif show_key == "show_long" then
                            belongs = false
                        end
                    end

                    if belongs then
                        local applications = aura.applications
                        local stacks = (not issecretvalue(applications) and applications and applications > 1) and applications or 0
                        local name = aura.name
                        local icon = aura.icon
                        local spell_id = aura.spellId
                        if issecretvalue(spell_id) then spell_id = nil end
                        local dispel = aura.dispelName
                        if issecretvalue(dispel) then dispel = nil end

                        aura_map[iid] = make_entry(
                            iid,
                            name,
                            icon,
                            duration or 0,
                            expiration or 0,
                            spell_id,
                            dispel,
                            rem or 0,
                            stacks,
                            filter
                        )
                    end
                end
            end
        end
    end

    -- Fallback payload support: some clients/addons may only provide IDs.
    if info.addedAuraInstanceIDs then
        for _, iid in ipairs(info.addedAuraInstanceIDs) do
            if not aura_map[iid] then
                aura_map[iid] = make_entry(iid, "...", nil, 0, 0, nil, nil, 0, 0, filter)
            end
        end
    end
    
    -- Updated auras: leave cached data unchanged in combat
    -- Fields will be refreshed when combat ends and full_scan runs
    
    return true
end

-- Shared helpful-aura scan/classifier.
-- 12.0.5+ API usage:
--   * C_UnitAuras.GetBuffDataByIndex
--   * C_UnitAuras.DoesAuraHaveExpirationTime
--   * C_UnitAuras.GetAuraDuration
-- Each helpful aura is assigned to exactly one category: static/short/long.
local function scan_helpful_shared(info, short_threshold, max_limit_hint)
    M.db.known_static_spell_ids = M.db.known_static_spell_ids or {}
    M._helpful_shared = M._helpful_shared or {
        map = {},
        category_by_iid = {},
        category_by_spell = {},
    }

    local shared = M._helpful_shared
    local old_map = shared.map or {}
    local old_cat_iid = shared.category_by_iid or {}
    local old_cat_spell = shared.category_by_spell or {}

    local old_added_by_key = {}
    for _, entry in pairs(old_map) do
        local key = make_order_key(entry.spell_id, entry.name, entry.icon, entry.filter)
        if key and entry.added_at and (not old_added_by_key[key] or entry.added_at < old_added_by_key[key]) then
            old_added_by_key[key] = entry.added_at
        end
    end

    local added_lookup = {}
    local added_count = 0
    if info then
        if info.addedAuras then
            for _, added_aura in ipairs(info.addedAuras) do
                local iid = added_aura and added_aura.auraInstanceID
                if iid then
                    added_lookup[iid] = added_aura
                    added_count = added_count + 1
                end
            end
        elseif info.addedAuraInstanceIDs then
            for _, iid in ipairs(info.addedAuraInstanceIDs) do
                if iid then
                    added_lookup[iid] = true
                    added_count = added_count + 1
                end
            end
        end
    end

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

        local category = nil

        if safe_spell_id and M.db.known_static_spell_ids[safe_spell_id] then
            category = "show_static"
        elseif rem ~= nil then
            if rem == 0 then
                category = "show_static"
            elseif rem <= short_threshold then
                category = "show_short"
            else
                category = "show_long"
            end
        else
            local expires = C_UnitAuras.DoesAuraHaveExpirationTime("player", iid)
            local expires_known
            if type(expires) ~= "boolean" then
                expires_known = false
            elseif issecretvalue(expires) then
                expires_known = nil
            else
                expires_known = expires
            end

            if expires_known == false then
                category = "show_static"
            elseif expires_known == true then
                local old_cat = old_cat_iid[iid] or (safe_spell_id and old_cat_spell[safe_spell_id])
                if old_cat == "show_long" then
                    category = "show_long"
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
                    local live_duration = C_UnitAuras.GetAuraDuration("player", iid)
                    category = live_duration and "show_short" or "show_static"
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
                or (old_entry and old_entry.expiration)
                or 0
            local safe_remaining = rem
            if (not safe_remaining or safe_remaining <= 0) and safe_expiration and safe_expiration > 0 then
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

            if category == "show_static" and safe_spell_id then
                M.db.known_static_spell_ids[safe_spell_id] = true
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
    M.db.known_static_spell_ids = M.db.known_static_spell_ids or {}
    local get_fn = (filter == "HELPFUL")
        and C_UnitAuras.GetBuffDataByIndex
        or  C_UnitAuras.GetDebuffDataByIndex

    local added_lookup
    local added_count = 0
    if info then
        if info.addedAuras then
            added_lookup = {}
            for _, added_aura in ipairs(info.addedAuras) do
                local iid = added_aura and added_aura.auraInstanceID
                if iid then
                    added_lookup[iid] = added_aura
                    added_count = added_count + 1
                end
            end
        elseif info.addedAuraInstanceIDs then
            added_lookup = {}
            for _, iid in ipairs(info.addedAuraInstanceIDs) do
                if iid then
                    added_lookup[iid] = true
                    added_count = added_count + 1
                end
            end
        end
    end

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
    local old_added_by_key = {}
    for _, entry in pairs(old_map) do
        local key = make_order_key(entry.spell_id, entry.name, entry.icon, entry.filter)
        if key and entry.added_at and (not old_added_by_key[key] or entry.added_at < old_added_by_key[key]) then
            old_added_by_key[key] = entry.added_at
        end
    end
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
local function render_aura_map(self, aura_map, use_bars, color, max_limit, filter, sort_mode)
    -- Resolve sort parameters for GetUnitAuraInstanceIDs
    local sort_rule = Enum.UnitAuraSortRule.Default
    local sort_dir  = Enum.UnitAuraSortDirection.Normal
    if sort_mode == "timeleft" then
        sort_rule = Enum.UnitAuraSortRule.ExpirationOnly
        -- Normal = ascending expiration time = soonest to expire first (most urgent)
    elseif sort_mode == "name" then
        sort_rule = Enum.UnitAuraSortRule.NameOnly
    end

    local wow_filter = (filter == "HELPFUL") and "HELPFUL" or "HARMFUL"
    local sorted_ids = C_UnitAuras.GetUnitAuraInstanceIDs("player", wow_filter, nil, sort_rule, sort_dir)

    -- Build display list in game-sorted order, filtered to entries in this frame's map
    local list = {}
    if sorted_ids then
        for _, iid in ipairs(sorted_ids) do
            local entry = aura_map[iid]
            if entry then list[#list + 1] = entry end
        end
    else
        -- Fallback: iterate map directly (sorted_ids nil = API unavailable)
        for _, entry in pairs(aura_map) do list[#list + 1] = entry end
        table.sort(list, function(a, b) return a.instance_id < b.instance_id end)
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

        table.sort(list, function(a, b)
            local aa = a._short_order or 0
            local bb = b._short_order or 0
            if aa == bb then
                return a.instance_id < b.instance_id
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
        local live_duration = entry.instance_id and C_UnitAuras.GetAuraDuration("player", entry.instance_id)
        local live_remaining = live_duration and live_duration:GetRemainingDuration() or nil
        local live_count = entry.instance_id and C_UnitAuras.GetAuraApplicationDisplayCount("player", entry.instance_id)

        obj.aura_index      = entry.instance_id
        obj.filter_type     = entry.filter
        obj.aura_name       = entry.name
        obj.aura_icon       = entry.icon
        obj.aura_duration   = entry.duration
        obj.aura_remaining  = entry.remaining
        obj.aura_expiration = entry.expiration
        obj.aura_scan_time  = now
        obj.aura_spell_id   = entry.spell_id

        obj.texture:SetTexture(entry.icon)  -- secret icon OK for SetTexture

        local stack_text = nil
        if live_count ~= nil and not issecretvalue(live_count) then
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
        elseif entry.count and entry.count > 1 then
            stack_text = entry.count
        else
            -- Secret live_count is safe to display, but we cannot compare it.
            -- Preserve combat behavior by showing it only when no safe fallback exists.
            stack_text = live_count
        end
        if use_bars then
            obj.bar:Show()
            obj.bar:SetStatusBarColor(color.r, color.g, color.b)
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
            if use_bars then
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
                    if display_remaining > short_threshold then
                        obj.time_text:SetText(M.format_time(display_remaining))
                    else
                        obj.time_text:SetFormattedText("%.1f", rem)
                    end
                else
                    obj.time_text:SetFormattedText("%.1f", rem)
                end
                if use_bars and obj.bar and obj.bar.SetTimerDuration and Enum and Enum.StatusBarTimerDirection then
                    obj.bar:SetTimerDuration(live_duration, nil, Enum.StatusBarTimerDirection.RemainingTime)
                end
            elseif rem > 0 then
                obj.time_text:SetText(M.format_time(rem))
                if use_bars then
                    if obj.bar and obj.bar.SetTimerDuration and Enum and Enum.StatusBarTimerDirection then
                        obj.bar:SetTimerDuration(live_duration, nil, Enum.StatusBarTimerDirection.RemainingTime)
                    else
                        obj.bar:SetMinMaxValues(0, entry.duration > 0 and entry.duration or rem)
                        obj.bar:SetValue(rem)
                    end
                end
            else
                obj.time_text:SetText("")
                if use_bars then
                    obj.bar:SetMinMaxValues(0, 1)
                    obj.bar:SetValue(1)
                end
            end
        elseif entry.duration > 0 then
            rem = entry.expiration > 0 and math_max(0, entry.expiration - now) or entry.remaining
            if rem > 0 then
                obj.time_text:SetText(M.format_time(rem))
                if use_bars then
                    obj.bar:SetMinMaxValues(0, entry.duration)
                    obj.bar:SetValue(rem)
                end
            else
                obj.time_text:SetText("")
                if use_bars then
                    obj.bar:SetMinMaxValues(0, 1)
                    obj.bar:SetValue(1)
                end
            end
        else
            -- Unknown/secret remaining in combat: keep last rendered text/value.
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

function M.setup_layout(self, show_key, spacing_key, use_bars)
    if InCombatLockdown() then return end
    if not self or not self.icons then return end

    local db = M.db
    local category = show_key:sub(6)
    local frame_width = db["width_"..category] or 200
    local spacing = db[spacing_key] or 6
    local growth = db["growth_"..category] or "DOWN"

    local icon_size = 32
    local icon_footprint = icon_size + spacing
    local icons_per_row = (growth == "DOWN" or growth == "UP")
        and 1
        or math_max(1, floor((frame_width - 12 + spacing) / icon_footprint))

    for i = 1, #self.icons do
        local obj = self.icons[i]
        obj:ClearAllPoints()
        obj.texture:ClearAllPoints()

        if use_bars then
            local bar_h = 20
            local step  = bar_h + spacing
            obj:SetSize(frame_width - 12, bar_h)

            if growth == "UP" then
                obj:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 6, (i - 1) * step + 6)
            else
                obj:SetPoint("TOPLEFT", self, "TOPLEFT", 6, -((i - 1) * step + 6))
            end

            obj.texture:SetSize(18, 18)
            obj.texture:SetPoint("LEFT", obj, "LEFT", 0, 0)

            obj.bar:ClearAllPoints()
            obj.bar:SetPoint("LEFT", obj.texture, "RIGHT", 5, 0)
            obj.bar:SetPoint("RIGHT", obj, "RIGHT", 0, 0)
            obj.bar:SetHeight(18)

            obj.name_text:ClearAllPoints()
            obj.name_text:SetPoint("LEFT", obj.bar, "LEFT", 22, 0)
            obj.name_text:Show()

            obj.time_text:ClearAllPoints()
            obj.time_text:SetPoint("RIGHT", obj.bar, "RIGHT", -4, 0)
            obj.time_text:Show()

            obj.count_text:ClearAllPoints()
            obj.count_text:Hide()  -- stacks shown inline with name in bar mode

        else
            obj:SetSize(icon_size, icon_size)
            obj.texture:SetAllPoints(obj)

            local col_idx = (i - 1) % icons_per_row
            local row_idx = floor((i - 1) / icons_per_row)
            local row_h   = icon_size + spacing + 12

            if growth == "DOWN" then
                obj:SetPoint("TOPLEFT", self, "TOPLEFT", 6, -(row_idx * row_h + 6))
            elseif growth == "UP" then
                obj:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 6, row_idx * row_h + 6)
            elseif growth == "LEFT" then
                obj:SetPoint("TOPRIGHT", self, "TOPRIGHT",
                    -(col_idx * icon_footprint + 6), -(row_idx * row_h + 6))
            else  -- RIGHT (default)
                obj:SetPoint("TOPLEFT", self, "TOPLEFT",
                    col_idx * icon_footprint + 6, -(row_idx * row_h + 6))
            end

            obj.name_text:ClearAllPoints()
            obj.name_text:Hide()

            obj.time_text:ClearAllPoints()
            obj.time_text:SetPoint("TOP", obj, "BOTTOM", 0, -2)
            obj.time_text:Show()

            -- Stack count: bottom-right corner of icon (matches WoW default buff display)
            obj.count_text:ClearAllPoints()
            obj.count_text:SetPoint("BOTTOMRIGHT", obj, "BOTTOMRIGHT", 0, 1)
        end
    end

    self._layout_cache = {
        use_bars      = use_bars,
        icons_per_row = icons_per_row,
        frame_width   = frame_width,
        spacing       = spacing,
        growth        = growth,
    }
end

-- ============================================================================
-- AURA SCANNING AND RENDERING

function M.update_auras(self, show_key, move_key, timer_key, bg_key, scale_key, spacing_key, filter, info)
    if not self or not self.icons then return end

    local db = M.db
    local category = show_key:sub(6)
    local use_bars = db["use_bars_"..category]
    local frame_width = db["width_"..category] or 200
    local spacing = db[spacing_key] or 6
    local color = db["color_"..category] or {r=1, g=1, b=1}
    local bgC = db["bg_color_"..category] or {r=0, g=0, b=0, a=0.5}
    local short_threshold = db.short_threshold or 60
    local growth = db["growth_"..category] or "DOWN"
    local max_limit = db["max_icons_"..category] or 40
    local sort_mode = db["sort_"..category] or "timeleft"

    self:SetScale(db[scale_key] or 1.0)

    if not self._layout_cache
        or (not InCombatLockdown()
        and (self._layout_cache.frame_width ~= frame_width
        or   self._layout_cache.use_bars    ~= use_bars
        or   self._layout_cache.spacing     ~= spacing
        or   self._layout_cache.growth      ~= growth
    )) then
        M.setup_layout(self, show_key, spacing_key, use_bars)
    end

    local is_moving = db[move_key]

    if not db[show_key] and not is_moving then
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

    if is_moving and not db[show_key] then
        if not InCombatLockdown() then self:SetHeight(44) end
        self:Show()
        return
    end

    if db[show_key] then self:Show() end

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

    local display_count = render_aura_map(
        self, self._aura_map, use_bars, color, max_limit, filter, sort_mode
    )

    -- Frame height (only safe to resize out of combat)
    local new_height = 44
    if display_count > 0 then
        local lc = self._layout_cache
        if use_bars then
            new_height = display_count * (20 + spacing) + 12
        elseif lc and (lc.growth == "DOWN" or lc.growth == "UP") then
            new_height = display_count * (32 + spacing + 12) + 6
        elseif lc and lc.icons_per_row then
            local rows = math_ceil(display_count / lc.icons_per_row)
            new_height = rows * (32 + spacing + 12) + 6
        else
            new_height = display_count * 44
        end
    end

    if db[show_key] then
        self:Show()
        if not InCombatLockdown() then self:SetHeight(new_height) end
    elseif not is_moving then
        self:Hide()
    end

    if db[show_key] and not self:IsVisible() then self:Show() end

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
