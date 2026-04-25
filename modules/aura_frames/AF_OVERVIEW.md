# Aura Frames Module — File Overview

## Purpose

The aura_frames module replaces and extends the default WoW buff/debuff display. It tracks
player buffs and debuffs across four independently configurable frame categories, renders them
as icons or progress bars, and exposes a full settings GUI inside the addon panel.

All files share a single namespace table: `addon.aura_frames` (aliased as `M` in every file).
Data is persisted in `Ls_Tweeks_DB.aura_frames`. DB keys follow the pattern `<setting>_<category>`
(e.g. `show_short`, `color_debuff`, `bar_mode_long`).

---

## Load Order and File Roles

Files load in the order declared in `LsTweeks.toc`. Each file extends `M` without overwriting
what earlier files placed there.

```
af_defaults.lua        — constants and defaults  (loads first)
af_test_aura.lua       — fake preview aura system
af_scan.lua            — aura data acquisition
af_render.lua          — visual output per frame
af_icon_layout.lua     — geometry and positioning of icons within each category frame
af_core.lua            — ticker, blizz toggles, main update loop
af_gui.lua             — settings tab builder
af_debug_outlines.lua  — developer slot outlines
af_main.lua            — frame construction and addon bootstrap  (loads last)
```

---

## File Descriptions

### af_defaults.lua
**Role:** Single source of truth for all constant values and default settings.

Defines:
- `M.CATEGORIES` — `{ "static", "short", "long", "debuff" }` — used wherever code must iterate all four frames.
- `M.TIMER_CATEGORIES` — `{ "short", "long", "debuff" }` — static has no timer, excluded from font/timer loops.
- `M.BAR_BG_ALPHA_DEFAULT`, `M.BAR_BG_GRAY_DEFAULT` — shared opacity/color constants.
- `M.defaults` — full table of every per-category DB key with its default value.
- `M.get_timer_number_font_size(category)` — resolves font size: category-specific → global → hardcoded 10.

Nothing else in the module should hard-code default values. If a default changes, change it here.

---

### af_test_aura.lua
**Role:** Fake aura preview system for the settings GUI "Test Aura" toggle.

Defines:
- `M.get_test_preview_state(show_key, short_threshold, now)` — returns `duration, remaining, count`
  computed from `GetTime()` so the test aura animates realistically (timer counts down, stack
  count cycles through 1–4 on its own period).
- `M.build_test_aura_entry(show_key, filter, short_threshold)` — returns an aura-map entry table
  that looks identical to a real scanned aura, keyed `"__test_preview__"`.
- `M.append_test_aura(aura_map, show_key, filter, short_threshold)` — inserts the fake entry into
  a live aura map so the normal render path handles it without special casing.
- `M.update_test_preview_display(obj, show_key, ...)` — called from the ticker to advance the
  fake timer and stack count each 0.1s tick without triggering a full re-scan.

The fake entry carries `is_test_preview = true` so the ticker can identify and update it separately
from live auras.

---

### af_scan.lua
**Role:** All aura data acquisition from the WoW API. Produces aura map entries consumed by
af_render and af_core. No UI code lives here.

Defines:
- `M.full_scan(aura_map, filter, show_key, short_threshold, max_limit, info)` — scans debuffs
  (HARMFUL filter). Processes incremental UNIT_AURA payloads (`info.addedAuras`,
  `info.updatedAuraInstanceIDs`, `info.removedAuraInstanceIDs`) when available; falls back to a
  full `AuraUtil.ForEachAura` sweep on `isFullUpdate` or initial load.
- `M.scan_helpful_shared(info, short_threshold, max_limit)` — one-pass shared scan for all three
  helpful categories (static/short/long). Returns a table with `.map` (auraInstanceID → entry)
  and `.category_by_iid` (auraInstanceID → show_key). Stores results in `M._helpful_shared` so
  each call can reference the previous scan's map and category assignments for carry-forward logic
  (stable re-categorization when aura fields become secret in combat). Each of the three HELPFUL
  frames runs this independently on its own deferred timer; `M._helpful_shared` is the shared
  cross-call state, not a within-event deduplication cache.

**Aura classification:** static = permanent (duration == 0), short = remaining ≤ threshold,
long = remaining > threshold. Each aura belongs to exactly one category at a time.

**Entry table fields:**
```
instance_id  — auraInstanceID (number) or nil for previews
spell_id     — spellID
name         — aura name
icon         — icon texture path
duration     — total duration in seconds (0 = permanent)
expiration   — absolute expiration time (GetTime() epoch), 0 if permanent
remaining    — remaining seconds at scan time
count        — stack count
filter       — "HELPFUL" or "HARMFUL"
is_test_preview — true only for fake preview entries
```

---

### af_render.lua
**Role:** Takes a populated aura map and writes all visual state into the icon pool. No layout
math (slot sizes/positions are set by af_icon_layout); render only sets textures, text, bar values.

Defines:
- `M.format_time(s)` — converts seconds to a human-readable string (`"2 h"`, `"45 m"`, `"12 s"`,
  `"3.2 s"`). Used by both the render path and the ticker.
- `M.set_timer_text(font_string, category, seconds)` — single timer text writer for all display
  paths (live + test). Short/show_short categories format to one decimal (`"3.2"`); all others use
  `format_time`. Handles nil seconds (clear), `issecretvalue` (live fallback), and zero (clear).
- `M.merge_aura_info(dst, src)` — merges two UNIT_AURA event payloads into one. Used by af_main's
  OnEvent handler to collapse multiple rapid events into a single deferred scan without losing any
  added/updated/removed IDs.
- `M.render_aura_map(self, aura_map, bar_mode, color, bar_bg_color, max_limit, filter, sort_mode, show_timer_text)` —
  main render function. Sorts the aura map using `C_UnitAuras.GetUnitAuraInstanceIDs` (game-native
  sort order). For the "short" category applies a stable per-aura order key so stack refreshes do
  not reposition existing bars. Iterates the sorted list up to `max_limit`/pool size, writes icon
  texture, bar color, name text, stack count, and timer text into each pool slot. Hides unused slots.
  Returns `display_count`.

---

### af_icon_layout.lua
**Role:** All geometry: slot sizes, anchor positions, frame height. Never called during combat
(InCombatLockdown guard). No aura data or rendering logic here.

Defines:
- `M.is_timer_text_enabled(db, category, timer_key)` — returns whether the timer text should be
  shown for a category. Static always returns false. Reads `db["timer_<category>"]` (or an explicit
  `timer_key`). Defaults to true when the key is absent so new installs show timers out of the box.
- `M.get_bar_layout_params(timer_font_size)` — returns a table of all geometry constants for bar
  mode: insets, icon size, bar height, stack slot width, timer slot width (scales with font size),
  name slot gaps, text padding. Single source of truth for bar layout math.
- `M.setup_layout(self, show_key, spacing_key, bar_mode)` — iterates the icon pool and calls
  `ClearAllPoints` + `SetPoint` / `SetSize` on every sub-frame (icon, bar, stack_slot, name_slot,
  timer_slot, count_text, time_text). Writes a `_layout_cache` table onto the frame so af_core can
  skip re-layout when nothing has changed. Must not be called in combat.
- `M.set_height_for_growth(self, new_height, growth)` — resizes the aura frame while keeping the
  correct edge anchored. DOWN growth keeps the top edge fixed; UP growth keeps the bottom edge
  fixed. Adjusts the stored y offset to compensate so the frame does not jump on screen.

---

### af_core.lua
**Role:** Runtime loop. Owns the per-tick update, Blizzard frame suppression, and the main
per-frame `update_auras` function that orchestrates scan → layout → render → resize.

Defines:
- `M.tick_visible_icons(now)` — called every 0.1s by the ticker in af_main. Walks all visible
  frames and their icon pools. For each visible live-aura slot: derives `remaining` from the cached
  `aura_expiration` (no per-tick API calls for normal auras); falls back to `C_UnitAuras.GetAuraDuration`
  only when both expiration and remaining are absent (secret-duration auras). Updates `time_text`
  and bar value. Delegates test-preview slots to `M.update_test_preview_display`.
- `set_blizz_frame_state(frame, hide)` (local) — hides or restores BuffFrame / DebuffFrame by
  toggling event registration and visibility.
- `M.toggle_blizz_buffs(hide)` / `M.toggle_blizz_debuffs(hide)` — public wrappers called from
  af_main at load and from the GUI reset callback.
- `M.update_auras(self, show_key, move_key, timer_key, bg_key, scale_key, spacing_key, filter, info)` —
  the main per-frame update. Called from each frame's deferred OnEvent. Steps:
  1. Reads all relevant DB keys for this category.
  2. Sets scale and position from DB (always enforces DB state).
  3. Checks `_layout_cache`; calls `M.setup_layout` if any layout param changed.
  4. Decides frame visibility and move-mode chrome (title bars, resizer).
  5. Calls `M.scan_helpful_shared` (HELPFUL) or `M.full_scan` (HARMFUL) to refresh `_aura_map`.
  6. Injects or removes the test preview entry.
  7. Calls `M.render_aura_map` → gets `display_count`.
  8. Computes new frame height from display count and calls `M.set_height_for_growth`.
  9. Sets backdrop color for move-mode vs. normal display.

---

### af_gui.lua
**Role:** Builds the "Buffs & Debuffs" settings tab inside the main addon panel.

Structure: a General tab plus one tab per category (Static, Short, Long, Debuff). All category
tabs use a `place_at(control, row, col, slot, opts)` grid system (4 equal columns, 6 variable-height
rows). The General tab uses manual anchoring.

Exposes:
- `M.BuildSettings(parent)` — called by af_main to register the settings tab via
  `addon.register_category`.
- `M.sync_general_controls_from_db()` — re-reads DB and updates all General tab controls to match.
  Called after a module reset.

Controls stored in `M.controls` for programmatic sync:
- `M.controls["width_slider_<cat>"]` — width slider; the resizer in af_main writes back to it.
- Font dropdowns and sliders for each category in `M.TIMER_CATEGORIES`.
- General tab checkboxes for Blizzard frame suppression and global threshold.

---

### af_debug_outlines.lua
**Role:** Developer tool. Draws 1px colored borders around the three bar-mode sub-slots
(stack_slot = orange, name_slot = blue, timer_slot = green) to verify layout geometry.

Defines:
- `M.add_debug_outline(frame, r, g, b, a)` — called from af_main during icon pool construction.
  Does nothing if `M.db.show_bar_section_outlines` is false. Outlines are tagged
  `._is_outline = true` so they can be safely found and removed without `SetParent(nil)`.
- `M.refresh_section_outlines()` — removes and redraws all outlines; called when the debug toggle
  is flipped in the settings panel.

---

### af_main.lua
**Role:** Addon bootstrap, frame construction, and event wiring. Loads last so all other files
have already populated `M`.

Responsibilities:
- Defines `M.NUMBER_FONT_OPTIONS` and `M.NUMBER_FONT_BOLD_PATHS` — font registry for timer text.
- `M.apply_number_font_to_text(font_string, category)` — sets the correct TTF + size + bold on any
  FontString. Clamps size to 6–18. Called at pool construction time and after font settings change.
- `M.apply_number_font_to_all()` — re-applies font to every time_text in every frame; used after a
  settings change.
- `M.create_aura_frame(show_key, ...)` — allocates the WoW Frame, title bars, resizer, and the
  entire icon pool. Each icon slot gets: texture, StatusBar + background, text_overlay frame,
  stack_slot, name_slot, timer_slot, name_text, time_text, count_text, and a tooltip handler. Wires
  OnEvent with the deferred 0.1s bucket pattern (UNIT_AURA payloads merged via `M.merge_aura_info`,
  single pending scan per frame via `_scan_pending` guard).
- ADDON_LOADED handler — links `M.db` to `Ls_Tweeks_DB.aura_frames`, applies defaults, runs DB
  migrations (font key migration, legacy bar-bg color migration, position anchor migration), calls
  `create_aura_frame` for all four categories, starts the 0.1s ticker, toggles Blizzard frames,
  and registers the settings tab.
- `M.on_reset_complete()` — called by the Hal's reset button after defaults are restored. Re-syncs
  Blizzard frame state, re-applies fonts, and re-syncs GUI controls.

---

## Data Flow Summary

```
WoW Event (UNIT_AURA)
  └─► af_main OnEvent
        merge payload → _pending_aura_info
        C_Timer.After(0.1) ──────────────────────────────────────┐
                                                                  ▼
                                                        af_core: update_auras
                                                          ├─ af_scan: scan_helpful_shared / full_scan
                                                          │     └─► _aura_map populated
                                                          ├─ af_test_aura: append_test_aura (if preview on)
                                                          ├─ af_icon_layout: setup_layout (if layout changed)
                                                          ├─ af_render: render_aura_map
                                                          │     └─► icon pool visual state written
                                                          └─ af_icon_layout: set_height_for_growth

C_Timer.NewTicker(0.1)
  └─► af_core: tick_visible_icons
        ├─ live aura slots: compute remaining from cached expiration → set_timer_text / bar:SetValue
        └─ test preview slots: af_test_aura: update_test_preview_display
```

---

## Key Design Constraints

- **No API calls inside OnEvent.** WoW taints the execution context during event dispatch. All
  C_UnitAuras calls are deferred to the C_Timer.After(0.1) callback.
- **No layout calls in combat.** `setup_layout` (and `set_height_for_growth`) are guarded by
  `InCombatLockdown()`. The ticker handles mid-combat timer/bar updates without touching geometry.
- **Pool is fixed at load time.** Icon frames are created once in `create_aura_frame`. Adding icons
  requires a reload. `max_icons_<cat>` controls the pool size.
- **Shared scan for HELPFUL.** Static, short, and long each call `scan_helpful_shared` on their
  own deferred timers. `M._helpful_shared` carries the previous scan's map and category assignments
  forward so combat-secret aura fields can be re-categorized stably across calls. Each call is a
  full independent sweep; the shared state enables carry-forward, not scan deduplication.
- **`_layout_cache` guards redundant re-layouts.** `update_auras` compares the five layout-relevant
  DB keys against the cache and only calls `setup_layout` when something changed.
