# Aura Frames Reference (Consolidated)

This is the single source-of-truth document for aura frame behavior in this addon.

Scope:
- modules/aura_frames/af_logic.lua
- modules/aura_frames/AF_main.lua

## 1. Architecture and Flow

1. AF_main.lua registers per-frame aura events:
   - UNIT_AURA (player)
   - PLAYER_ENTERING_WORLD
   - PLAYER_REGEN_DISABLED
   - PLAYER_REGEN_ENABLED
2. UNIT_AURA payloads are merged via merge_aura_info() while scans are pending.
3. Scans are deferred with C_Timer.After(0.1) to avoid event-dispatch taint windows.
4. update_auras() populates each frame's _aura_map.
5. render_aura_map() renders icons/bars from cached entries.
6. A shared C_Timer.NewTicker(0.1) updates timer text/bar values for visible icons.

## 2. Data Model

make_entry() stores per-aura records keyed by auraInstanceID:
- instance_id
- name, icon
- duration, expiration, remaining
- spell_id, dispel_name, count
- filter, added_at

Runtime maps:
- frame._aura_map: per-frame cache used for rendering
- M._helpful_shared.map: shared HELPFUL authoritative map
- M._helpful_shared.category_by_iid: final category assignment per helpful aura
- M._helpful_shared.category_by_spell: category memory by spell ID

## 3. Classification Behavior

### Helpful Auras (single authority)

scan_helpful_shared() assigns each helpful aura to exactly one category:
- show_static
- show_short
- show_long

Classification uses best readable timing first:
- live_remaining from C_UnitAuras.GetAuraDuration("player", iid)
- rem from compute_remaining(duration, expiration)

Stability helpers:
- M.db.known_static_spell_ids
- M.db.known_long_spell_ids

Fallback logic uses:
- C_UnitAuras.DoesAuraHaveExpirationTime("player", iid)
- old category memory (by iid/spell)
- replacement preference when one aura is removed and one is added

### Harmful Auras

Debuffs continue to use full_scan() per frame:
- Reads by index via GetDebuffDataByIndex
- Uses guarded readable checks for timing/fields
- Recovers old entry data when current fields are secret
- Applies per-frame membership with categorize_aura() and dispel-type visibility

## 4. Taint and Secret-Value Strategy

Core rules:
1. Do not process aura fields directly in UNIT_AURA event context.
2. Defer scans (0.1s) and merge payloads first.
3. Guard all comparisons/arithmetic with issecretvalue() where needed.
4. Preserve old cached entry data when current fields are unreadable.

Where this is enforced:
- AF_main.lua
  - merge_aura_info() unions payload deltas
  - OnEvent queues one deferred scan and deduplicates rapid events
- af_logic.lua
  - compute_remaining() returns nil for unreadable timing
  - scan_helpful_shared()/full_scan() branch by readability
  - safe_duration/safe_expiration/safe_remaining fallback chains preserve continuity

Guardrails:
- Keep HELPFUL classification in shared one-pass scan
- Avoid reintroducing independent per-frame HELPFUL scans
- Any new math/comparison on aura fields must check readability first

## 5. Display, Timers, and Stacks

render_aura_map():
- Reads live stack count via GetAuraApplicationDisplayCount()
- Reads live duration via GetAuraDuration()
- Static frame explicitly suppresses timer text
- Uses format_time() for readable output

Ticker (AF_main.lua):
- Runs every 0.1s
- Updates shown icon timers/bars
- Uses cached expiration/remaining fallback when live remaining is secret
- Preserves minute/hour formatting for long durations when available via safe fallback

## 6. API Reference (Used Here)

Active APIs:
1. C_UnitAuras.GetBuffDataByIndex("player", i)
2. C_UnitAuras.GetDebuffDataByIndex("player", i)
3. C_UnitAuras.GetAuraDuration("player", auraInstanceID)
4. C_UnitAuras.GetAuraApplicationDisplayCount("player", auraInstanceID)
5. C_UnitAuras.GetUnitAuraInstanceIDs("player", filter, nil, sortRule, sortDirection)
6. C_UnitAuras.DoesAuraHaveExpirationTime("player", auraInstanceID)
7. GameTooltip:SetUnitAuraByAuraInstanceID("player", auraInstanceID)

Usage notes:
- GetAuraDuration is used both for classification and render-time countdown updates.
- GetUnitAuraInstanceIDs provides game-side sorting; local map filters the final list.
- DoesAuraHaveExpirationTime is treated as tri-state (true/false/unknown-secret) when needed.

## 7. Sorting and Ordering

Primary ordering:
- Enum.UnitAuraSortRule.Default
- Enum.UnitAuraSortRule.ExpirationOnly (timeleft mode)
- Enum.UnitAuraSortRule.NameOnly (name mode)

Short-frame stabilization:
- A persistent _short_order_map keeps buff positions stable during stack changes.
- Removed keys are cleaned up so re-applied buffs are treated as new entries.

## 8. Compatibility Notes

- For this addon target/build, TOC Interface should remain 120000.
- The module is written against modern C_UnitAuras APIs and avoids legacy UnitAura usage.

## 9. Legacy Helper Note

apply_combat_delta() still exists in af_logic.lua, but current update_auras() routing uses:
- HELPFUL -> scan_helpful_shared()
- HARMFUL -> full_scan()
