# LsTweeks — Claude Code Context

## What This Is
**L's Tweeks** — a modular WoW UI addon (patch 12.0 / Interface 120000) by LockBall.  
Slash command: `/lt`. SavedVariables: `Ls_Tweeks_DB`. Note the intentional "Tweeks" spelling throughout.

## File Map
```
core/
  init.lua          — addon entry, theme constants (addon.UI_THEME), DB init, slash cmd
  main_frame.lua    — sidebar + tabbed settings window; addon.register_category()
  minimap_button.lua — LibDataBroker minimap button
functions/
  checkbox.lua        — addon.CreateCheckbox()
  color_picker.lua    — addon.CreateColorPicker()
  dropdown.lua        — addon.CreateDropdown() — custom popup, NOT UIDropDownMenu
  module_reset.lua    — addon.CreateGlobalReset() — ARM-code safety reset
  panel_riveted.lua   — addon.CreateRivetedPanel() / ApplyRivetedPanelStyle() / AddRivetCorners()
  slider_with_box.lua — addon.CreateSliderWithBox()
  step_button_group.lua — addon.CreateStepButtonGroup()
modules/
  about.lua        — intro/version page
  settings.lua     — minimap toggle
  combat_text.lua  — hide portrait combat text
  aura_frames/
    af_defaults.lua  — all default config values, single source of truth
    af_logic.lua     — core engine: aura scanning, icon pool, layout, timer ticker (1453 lines)
    af_gui.lua       — settings tab builder
    af_main.lua      — init, events, drag mode, test aura wiring
    af_test_aura.lua — fake aura preview system
libs/            — LibStub, LibDataBroker-1.1, LibDBIcon-1.0, CallbackHandler-1.0
media/fonts/     — monospace TTFs: SourceCodePro, Inconsolata, JetBrainsMono, RobotoMono, 0xProto
```

## Architecture Rules
- **Module pattern:** `local addon_name, addon = ...` at top of every file; modules share the `addon` namespace table.
- **Self-registration:** modules call `addon.register_category(name, builder_fn)` to appear in the settings sidebar.
- **DB access:** `Ls_Tweeks_DB.module_key = Ls_Tweeks_DB.module_key or {}` — always guard with `or {}`.
- **Init pattern:** every module creates a loader frame, registers ADDON_LOADED, and unregisters after first fire.
- **Hot paths:** cache WoW globals at file top — `local floor = math.floor`, `local GetTime = GetTime`, etc.
- **Theme constants:** spacing, fonts, widths live in `addon.UI_THEME` (set in `core/init.lua`) — don't hardcode.
- **Pixel snapping:** use the pixel_snap helper in af_logic for any sub-pixel positioning.
- **Deferred batching:** UNIT_AURA events are bucketed at 0.05s; timer ticker runs at 0.1s.
- **InCombatLockdown:** defer layout changes; never call protected WoW API during combat.

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
  last_open_module = string,       -- last sidebar tab name
  show_bar_section_outlines = bool,-- debug outline toggle (top-level, not under aura_frames)
  aura_frames = {
    last_tab_index = number,       -- last selected category tab (1=General, 2=Static, ...)
    short_threshold = number,
    disable_blizz_buffs = bool,
    disable_blizz_debuffs = bool,
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
Category tabs use a numeric column grid. `place_at(control, row, column, slot, opts)`:
- Columns are numeric keys in the `grid` table: `grid[1]=0`, `grid[2]=150`, `grid[3]=300`, `grid[4]=450`
- Column end bounds: `grid["2_end"]=375`, `grid["3_end"]=570`, `grid["4_end"]=760`
- Row heights are variable: `grid.row_heights = {40, 60, 40, 75, 110, 110}` (6 rows)
- `opts.align = "center"` centers the control between `grid[col]` and `grid[col+1_end]`
- `slot` maps to `grid.offsets` for per-type y nudge: `dropdown=8`, `picker=4`, `default=0`
- General tab uses manual anchoring (no `place_at`); category tabs use `place_at`.

## UI Shared Controls — Quick Reference
| Function | Key args | Notes |
|---|---|---|
| `CreateCheckbox(parent, label, checked, cb)` | returns container, checkbox, label | container width is dynamic |
| `CreateSliderWithBox(name, parent, label, min, max, step, db, key, defaults, cb)` | returns container (130×95) | has built-in 0.1s debounce; `container.slider` exposed |
| `CreateDropdown(name, parent, label, options, cfg)` | cfg: width, row_height, get_value, on_select | custom popup |
| `M.CreateListDropdown(name, parent, label, opts, get_val, on_sel, width)` | returns dropdown | af_gui wrapper with font support |
| `CreateColorPicker(parent, db, key, has_alpha, label, defaults, cb)` | integrated reset | container is 95×45 |
| `CreateRivetedPanel(parent, w, h, anchorTo, point, x, y, levelOffset)` | returns panel, fontstring | |
| `CreateGlobalReset(parent, db, defaults)` | ARM-code safety reset | |
| `CreateStepButtonGroup(parent, height, on_inc, on_dec)` | returns group frame | vertical stack layout |

## Debug Outlines (af_main.lua)
`Ls_Tweeks_DB.show_bar_section_outlines` toggles 1px borders on aura icon slots.  
Toggle via `M.refresh_section_outlines()`. Outline textures are tagged `._is_outline = true` for safe removal.  
Do NOT use `SetParent(nil)` to remove textures — use `Hide()` + `SetTexture(nil)` on tagged textures only.

## Riveted Panel Style
Marble background, ornate dialog-frame borders, 4 corner rivet textures. Apply via `addon.ApplyRivetedPanelStyle(frame, opts)` or `addon.AddRivetCorners(frame, inset, offX, offY)`.

## Key WoW API Used
- `C_UnitAuras.GetBuffDataByIndex / GetDebuffDataByIndex` — aura scanning
- `C_UnitAuras.GetAuraDuration` — fallback for secret durations
- `AuraUtil.ForEachAura` — iteration helper
- `ColorPickerFrame` — system color picker
- `InCombatLockdown()` — combat guard
- `LibDataBroker`, `LibDBIcon` — minimap button
