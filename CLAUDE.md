# LsTweeks — Claude Code Context

## Claude Permissions
- Bash `grep` commands are pre-approved for this project — no need to prompt for permission.

## What This Is
**L's Tweeks** — a modular WoW UI addon (patch 12.0 / Interface 120000) by LockBall.  
Slash command: `/lst` (registered as `SLASH_LSTWEEKS1`). SavedVariables: `Ls_Tweeks_DB`. Note the intentional "Tweeks" spelling throughout.

## File Map
```
core/
  init.lua           — addon entry, theme constants (addon.UI_THEME), DB init, slash cmd
  main_frame.lua     — sidebar + tabbed settings window; addon.register_category()
  minimap_button.lua — LibDataBroker minimap button
functions/
  utils.lua           — addon.deep_copy_into(), addon.apply_defaults()
  checkbox.lua        — addon.CreateCheckbox()
  color_picker.lua    — addon.CreateColorPicker()
  dropdown.lua        — addon.CreateDropdown() — custom popup, NOT UIDropDownMenu
  module_reset.lua    — addon.CreateGlobalReset() — ARM-code safety reset
  panel_riveted.lua   — addon.CreateRivetedPanel() / ApplyRivetedPanelStyle() / AddRivetCorners()
  slider_with_box.lua — addon.CreateSliderWithBox()
  step_button_group.lua — addon.CreateStepButtonGroup()
modules/
  about.lua        — intro/version page
  settings/
    st_defaults.lua — default values for settings module (interface_alpha, minimap, open_on_reload)
    st_main.lua     — minimap toggle, open-on-reload, interface transparency slider; on_reset_complete
  combat_text.lua  — hide portrait combat text; on_reset_complete
  aura_frames/
    af_defaults.lua      — all default config values, single source of truth; M.CATEGORIES, M.TIMER_CATEGORIES
    af_scan.lua          — aura scanning: scan_helpful_shared(), full_scan()
    af_render.lua        — render_aura_map(), set_timer_text(), merge_aura_info()
    af_icon_layout.lua   — setup_layout(), set_height_for_growth(), get_bar_layout_params(), is_timer_text_enabled()
    af_core.lua          — tick_visible_icons(), update_auras(), toggle_blizz_buffs/debuffs()
    af_gui.lua           — settings tab builder; M.BuildSettings(), sync_general_controls_from_db()
    af_main.lua          — init, frame creation, icon pool, drag/resize, on_reset_complete
    af_test_aura.lua     — fake aura preview system
    af_debug_outlines.lua — add_debug_outline(), refresh_section_outlines()
    af_grid.lua          — snap_to_grid(), build_grid_lines(), create_grid_overlay(), set_grid_visible()
libs/            — LibStub, LibDataBroker-1.1, LibDBIcon-1.0, CallbackHandler-1.0
media/fonts/     — monospace TTFs: SourceCodePro (selectable), Inconsolata, JetBrainsMono, RobotoMono, 0xProto (on disk, not yet selectable)
```

## File Header Standard
Every lua file must open with a brief comment (a few sentences) explaining what the file does, placed before `local addon_name, addon = ...`. The comment should describe the file's role/responsibility in plain terms and mention its key public functions or how it fits into the larger system. Do not use a bare filename label as a substitute.

## Architecture Rules
- **Module pattern:** `local addon_name, addon = ...` at top of every file; modules share the `addon` namespace table.
- **Self-registration:** modules call `addon.register_category(name, builder_fn)` to appear in the settings sidebar.
- **DB access:** `Ls_Tweeks_DB.module_key = Ls_Tweeks_DB.module_key or {}` — always guard with `or {}`.
- **Init pattern:** every module creates a loader frame, registers ADDON_LOADED, and unregisters after first fire.
- **Hot paths:** cache WoW globals at file top — `local floor = math.floor`, `local GetTime = GetTime`, etc.
- **Theme constants:** spacing, fonts, widths live in `addon.UI_THEME` (set in `core/init.lua`) — don't hardcode.
- **Deferred batching:** UNIT_AURA events are bucketed at 0.1s; timer ticker runs at 0.1s.
- **InCombatLockdown:** defer layout changes; never call protected WoW API during combat.
- **Reset contract:** every module must implement `M.on_reset_complete()` to resync controls from DB after reset. Apply defaults via `addon.apply_defaults(defaults, db)`, not manual `or` guards.
- **Taint safety:** never call Blizzard frame methods (UpdateAuras, UpdateLayout) from addon context — even deferred. Restore events + Show() only and let Blizzard's handlers fire naturally.

## Layout Rules (critical — violations cause invisible controls)
- **All widget internals anchor to their own container** — never chain anchors off a sibling inside a factory function.
- **One SetPoint per anchor direction per frame** — two TOPLEFT calls on the same frame = conflicting constraint, undefined result.
- **Never call `frame:GetWidth()` at build time** — returns 0 until the frame is rendered; use hardcoded constants for layout math.
- **External placement is always one `SetPoint` call** — factory functions must NOT call SetPoint themselves if the caller will place them.
- **`CreateSliderWithBox` has a built-in 0.1s debounce** — do not add an external debounce in the callback.

## Saved Variables — Known Keys
```
Ls_Tweeks_DB = {
  minimap = { hide = bool },
  open_on_reload = bool,
  interface_alpha = number,            -- main frame transparency (0–1)
  last_open_module = string,           -- last sidebar tab name (survives reset intentionally)
  combat_text = bool,                  -- hide portrait combat text
  aura_frames = {
    last_tab_index = number,           -- last selected category tab (1=General, 2=Static, ...)
    last_frames_node = string,         -- last selected frame node in category tabs
    short_threshold = number,
    enable_blizz_buffs = bool,
    enable_blizz_debuffs = bool,
    snap_to_grid = bool,
    show_grid = bool,
    show_bar_section_outlines = bool,  -- debug outline toggle (now under aura_frames, not root)
    known_static_spell_ids = table,    -- learned permanent-aura spell IDs
    known_long_spell_ids = table,      -- learned long-aura spell IDs
    -- per-category keys: <setting>_<cat> e.g. show_static, color_debuff, scale_short
    positions = { static={x,y}, short={x,y}, long={x,y}, debuff={x,y} },
  }
}
```

## Aura Frame Categories
Four categories: `static`, `short`, `long`, `debuff`.  
DB keys follow the pattern `aura_frames.<setting>_<category>` (e.g. `show_static`, `color_debuff`).  
Positions are stored under `aura_frames.positions.<category>`.

## af_gui.lua Layout System
`BuildSettings` has two tabs: **General** (manual anchoring) and **Frames** (tree + grid).

**Frames tab** has a left tree sidebar (120px wide) listing Static/Short/Long/Debuffs with expand/collapse. Selecting a node lazy-builds a content panel to the right. Each content panel uses `place_at(control, row, column, slot, opts)` with a 4-column grid:
- `col_gap=150`, `col_offset=-20` → `grid[1]=-20`, `grid[2]=130`, `grid[3]=280`, `grid[4]=430`
- `col_width=190` — centering zone within each column
- All 4 columns center-aligned by default (`col_align = {"center","center","center","center"}`)
- `opts.align` overrides per-call ("left", "center", "right")
- 5 rows: `row_heights = {130, 60, 60, 110, 110}`, `row_start=-20`, `row_gap=20`
- `slot` maps to `grid.offsets`: `dropdown=8`, `picker=4`, `default=0`
- `opts.valign="bottom"` descends one extra row height

## UI Shared Controls — Quick Reference
| Function | Key args | Notes |
|---|---|---|
| `CreateCheckbox(parent, label, checked, cb)` | returns container, checkbox, label | container width is dynamic |
| `CreateSliderWithBox(name, parent, label, min, max, step, db, key, defaults, cb)` | returns container (130×95) | has built-in 0.1s debounce; `container.slider` exposed |
| `CreateDropdown(name, parent, label, options, cfg)` | cfg: width, row_height, get_value, on_select | custom popup |
| `M.CreateListDropdown(name, parent, label, opts, get_val, on_sel, width)` | returns dropdown | af_gui wrapper with font support |
| `CreateColorPicker(parent, db, key, has_alpha, label, defaults, cb)` | integrated reset | container is 95×45 |
| `CreateRivetedPanel(parent, w, h, anchorTo, point, x, y, levelOffset)` | returns panel, fontstring | |
| `CreateGlobalReset(parent, db, defaults)` | ARM-code safety reset; blocked in combat | |
| `CreateStepButtonGroup(parent, height, on_inc, on_dec)` | returns group frame | vertical stack layout |

## Debug Outlines (af_debug_outlines.lua)
`M.db.show_bar_section_outlines` toggles 1px borders on aura icon slots.  
Toggle via `M.refresh_section_outlines()`. Outline textures are tagged `._is_outline = true` for safe removal.  
Do NOT use `SetParent(nil)` to remove textures — use `Hide()` + `SetTexture(nil)` on tagged textures only.

## Grid Snap (af_grid.lua)
20px grid, screen-center origin — matches LsTweeks coordinate system exactly.  
`M.snap_to_grid(v, is_y)` — snaps a coordinate. `M.set_grid_visible(show)` — toggles overlay. 
DB keys: `aura_frames.snap_to_grid`, `aura_frames.show_grid`.

## Riveted Panel Style
Marble background, ornate dialog-frame borders, 4 corner rivet textures. Apply via `addon.ApplyRivetedPanelStyle(frame, opts)` or `addon.AddRivetCorners(frame, inset, offX, offY)`.

## Key WoW API Used
- `C_UnitAuras.GetBuffDataByIndex / GetDebuffDataByIndex` — aura scanning
- `C_UnitAuras.GetAuraDuration` — returns a Duration object (12.0+); use `:GetRemainingDuration()`, `:GetExpirationTime()`
- `C_UnitAuras.GetUnitAuraInstanceIDs` — sort-ordered ID list for render
- `C_UnitAuras.DoesAuraHaveExpirationTime` — secret-safe boolean expiry check
- `C_UnitAuras.GetAuraApplicationDisplayCount` — stack count fallback
- `ColorPickerFrame` — system color picker
- `InCombatLockdown()` — combat guard
- `LibDataBroker`, `LibDBIcon` — minimap button
