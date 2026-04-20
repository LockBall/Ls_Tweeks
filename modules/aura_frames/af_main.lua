local addon_name, addon = ...
local M = addon.aura_frames

-- CACHED GLOBALS AND CONSTANTS
local MAX_POOL_SIZE = 40 -- Default pool size
local MIN_FRAME_WIDTH = 180
local MIN_FRAME_HEIGHT = 44
local format = string.format
-- Outline debug helper: now dynamic
local function is_outline_enabled()
    return Ls_Tweeks_DB and Ls_Tweeks_DB.show_bar_section_outlines
end

-- Draw a simple 1px border using textures (safe alternative to Backdrop).
local function add_debug_outline(frame, r, g, b, a)
    if not is_outline_enabled() then return end
    if not frame then return end
    local t = 1
-- Called when the outlines setting changes; refresh all aura frames
function M.refresh_section_outlines()
    for _, frame in pairs(M.frames or {}) do
        if frame and frame.icons then
            for _, obj in ipairs(frame.icons) do
                -- Remove all previous outline textures (OVERLAY, 1px)
                local slots = { obj.stack_slot, obj.name_slot, obj.timer_slot }
                for _, slot in ipairs(slots) do
                    local regions = { slot:GetRegions() }
                    for _, region in ipairs(regions) do
                        if region and region:GetObjectType() == "Texture" then
                            region:Hide()
                            region:SetTexture(nil)
                            region:SetParent(nil) -- fully detach from frame
                        end
                    end
                end
            end
        end
    end
    -- Re-add outlines if enabled
    if is_outline_enabled() then
        for _, frame in pairs(M.frames or {}) do
            if frame and frame.icons then
                for _, obj in ipairs(frame.icons) do
                    add_debug_outline(obj.stack_slot, 1, 0.4, 0, 0.9)
                    add_debug_outline(obj.name_slot, 0, 0.6, 1, 0.9)
                    add_debug_outline(obj.timer_slot, 0, 1, 0.3, 0.9)
                end
            end
        end
    end
end

    local top = frame:CreateTexture(nil, "OVERLAY")
    top:SetColorTexture(r, g, b, a)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(t)

    local bottom = frame:CreateTexture(nil, "OVERLAY")
    bottom:SetColorTexture(r, g, b, a)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(t)

    local left = frame:CreateTexture(nil, "OVERLAY")
    left:SetColorTexture(r, g, b, a)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(t)

    local right = frame:CreateTexture(nil, "OVERLAY")
    right:SetColorTexture(r, g, b, a)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(t)
end

M.NUMBER_FONT_OPTIONS = {
    {
        key = "source_code_pro",
        label = "Source Code Pro",
        path = "Interface\\AddOns\\LsTweeks\\media\\fonts\\SourceCodePro-Regular.ttf",
        size = 9,
        flags = "",
    },
    {
        key = "game_default",
        label = "Game Default",
        path = nil,
        size = nil,
        flags = nil,
    },
}

-- bold variant paths; nil means no bold available for that font
M.NUMBER_FONT_BOLD_PATHS = {
    inconsolata    = "Interface\\AddOns\\LsTweeks\\media\\fonts\\Inconsolata-Bold.ttf",
    jetbrains_mono = "Interface\\AddOns\\LsTweeks\\media\\fonts\\JetBrainsMono-Bold.ttf",
    source_code_pro= "Interface\\AddOns\\LsTweeks\\media\\fonts\\SourceCodePro-Bold.ttf",
    roboto_mono    = "Interface\\AddOns\\LsTweeks\\media\\fonts\\RobotoMono-Bold.ttf",
    ["0xproto"]   = "Interface\\AddOns\\LsTweeks\\media\\fonts\\0xProto-Bold.ttf",
}

local function get_number_font_def(key, category)
    local selected_key = key
    if not selected_key and M.db then
        if category and M.db["timer_number_font_"..category] then
            selected_key = M.db["timer_number_font_"..category]
        else
            selected_key = M.db.timer_number_font
        end
    end
    selected_key = selected_key or "source_code_pro"
    for _, def in ipairs(M.NUMBER_FONT_OPTIONS) do
        if def.key == selected_key then
            return def
        end
    end
    return M.NUMBER_FONT_OPTIONS[1]
end

function M.get_number_font_options()
    return M.NUMBER_FONT_OPTIONS
end

function M.apply_number_font_to_text(font_string, category)
    if not font_string or not font_string.SetFont then return end
    local def = get_number_font_def(nil, category)
    local size = (M.get_timer_number_font_size and M.get_timer_number_font_size(category))
        or def.size
        or 10
    local flags = def.flags or ""

    -- Always pass an integer size to SetFont. WoW/FreeType rounds fractional
    -- sizes inconsistently; doing it ourselves keeps rendering deterministic.
    size = math.floor(size + 0.5)

    if size < 6 then size = 6 end
    if size > 18 then size = 18 end

    if def.path then
        local use_bold = false
        if M.db then
            local bold_key = category and ("timer_number_font_bold_"..category)
            if bold_key and M.db[bold_key] ~= nil then
                use_bold = M.db[bold_key]
            else
                use_bold = M.db.timer_number_font_bold or false
            end
        end
        local bold_path = use_bold and M.NUMBER_FONT_BOLD_PATHS[def.key]
        font_string:SetFont(bold_path or def.path, size, flags)
    elseif STANDARD_TEXT_FONT then
        font_string:SetFont(STANDARD_TEXT_FONT, size, flags)
    else
        font_string:SetFontObject(GameFontHighlightSmall)
    end
end

function M.apply_number_font_to_all()
    if not M.frames then return end
    for _, frame in pairs(M.frames) do
        if frame and frame.icons then
            local category = frame.category
            for _, obj in ipairs(frame.icons) do
                if obj and obj.time_text then
                    M.apply_number_font_to_text(obj.time_text, category)
                end
            end
        end
    end
end

-- safely copy default tables into saved variables without reference issues
local function deep_copy(src, dest)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = dest[k] or {}
            deep_copy(v, dest[k])
        else
            if dest[k] == nil then dest[k] = v end
        end
    end
end

-- AURA CONTAINER GENERATOR
function M.create_aura_frame(show_key, move_key, timer_key, bg_key, scale_key, spacing_key, display_name, is_debuff)
    local category = show_key:sub(6)
    local bar_bg_alpha = M.BAR_BG_ALPHA_DEFAULT
    local frame = CreateFrame("Frame", "LsTweaksAuraFrame_"..show_key, UIParent, "BackdropTemplate")
    frame.category = category
    
    -- Updated Backdrop for smoother color filling
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", -- Use a flat white texture for clean coloring
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", 
        tile = true, tileSize = 16, edgeSize = 12, -- Reduced edgeSize slightly for a sleeker look
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })

    frame:SetMovable(true) 
    frame:SetResizable(true) 
    frame:SetClampedToScreen(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_FRAME_WIDTH, MIN_FRAME_HEIGHT)
    end
    if frame.SetMinResize then
        frame:SetMinResize(MIN_FRAME_WIDTH, MIN_FRAME_HEIGHT)
    end
    local initial_width = M.db["width_"..category] or 200
    if initial_width < MIN_FRAME_WIDTH then
        initial_width = MIN_FRAME_WIDTH
        M.db["width_"..category] = initial_width
    end
    frame:SetSize(initial_width, 50)

    local pos = M.db.positions and M.db.positions[category]
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, is_debuff and -100 or 100)
    end
    
    -- TITLE BAR LOGIC
    local TITLEBAR_ANCHORS = {
        top =    { from = "BOTTOM", to = "TOP", offset = -2 },
        bottom = { from = "TOP",    to = "BOTTOM", offset = 2 },
    }

    local function CreateTitleBar(parent, label, is_bottom)
        local cfg = is_bottom and TITLEBAR_ANCHORS.bottom or TITLEBAR_ANCHORS.top
        local tb = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        tb:SetPoint(cfg.from.."LEFT",  parent, cfg.to.."LEFT",  0, cfg.offset)
        tb:SetPoint(cfg.from.."RIGHT", parent, cfg.to.."RIGHT", 0, cfg.offset)
        tb:SetHeight(20)
        tb:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 12, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        tb:SetBackdropColor(0.2, 0.2, 0.2, 1)
        local text = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetText(label)
        tb:EnableMouse(true)
        tb:RegisterForDrag("LeftButton")
        tb:SetScript("OnDragStart", function() parent:StartMoving() end)
        tb:SetScript("OnDragStop", function() 
            parent:StopMovingOrSizing() 
            local p, _, _, x, y = parent:GetPoint()
            M.db.positions[parent.category] = { point = p, x = x, y = y }
        end)
        return tb
    end
    
    frame.title_bar = CreateTitleBar(frame, display_name, false)
    frame.bottom_title_bar = CreateTitleBar(frame, display_name, true)
    
    -- RESIZER
    frame.resizer = CreateFrame("Button", nil, frame)
    frame.resizer:SetSize(16, 16)
    frame.resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

    frame:SetScript("OnSizeChanged", function(s, w)
        if s._clamping_size then return end
        if w and w < MIN_FRAME_WIDTH then
            s._clamping_size = true
            s:SetWidth(MIN_FRAME_WIDTH)
            s._clamping_size = nil
        end
    end)

    frame.resizer:SetScript("OnMouseDown", function() frame:StartSizing("RIGHT") end)
    frame.resizer:SetScript("OnMouseUp", function() 
        frame:StopMovingOrSizing() 
        local clamped_width = frame:GetWidth()
        if clamped_width < MIN_FRAME_WIDTH then
            clamped_width = MIN_FRAME_WIDTH
            frame:SetWidth(clamped_width)
        end
        M.db["width_"..category] = clamped_width
        local params = frame.update_params
        if params then
            M.update_auras(frame, params.show_key, params.move_key, params.timer_key, params.bg_key, params.scale_key, params.spacing_key, params.filter)
        end
    end)

    -- ICON POOL MANAGEMENT    Pre-create set number of icons/bars to avoid combat lockdown errors
    frame.icons = {}
    local pool_size = M.db["max_icons_"..category] or MAX_POOL_SIZE
    local bar_bg_default = M.db["bar_bg_color_"..category] or M.db["color_"..category] or { r = 1, g = 1, b = 1, a = bar_bg_alpha }

    for i = 1, pool_size do
        local obj = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        obj:Hide()
        
        -- Icon Texture
        obj.texture = obj:CreateTexture(nil, "ARTWORK")
        
        -- Status Bar (for bar mode)
        obj.bar = CreateFrame("StatusBar", nil, obj)
        obj.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        obj.bar:SetMinMaxValues(0, 1)
        obj.bar_bg = obj.bar:CreateTexture(nil, "BACKGROUND")
        obj.bar_bg:SetAllPoints()
        obj.bar_bg:SetColorTexture(bar_bg_default.r, bar_bg_default.g, bar_bg_default.b, bar_bg_default.a or bar_bg_alpha)
        obj.bar:Hide()
        
        -- Text Overlay Frame - created AFTER bar so it renders on top
        -- This is a separate frame layer that ensures text is always visible above the bar
        obj.text_overlay = CreateFrame("Frame", nil, obj)
        obj.text_overlay:SetFrameLevel(obj.bar:GetFrameLevel() + 1)

        -- Stack slot: left zone of bar (stack count display area)
        obj.stack_slot = CreateFrame("Frame", nil, obj.text_overlay)
        add_debug_outline(obj.stack_slot, 1, 0.4, 0, 0.9)

        -- Name slot: middle zone of bar
        obj.name_slot = CreateFrame("Frame", nil, obj.text_overlay)
        add_debug_outline(obj.name_slot, 0, 0.6, 1, 0.9)

        -- Text - create as children of text_overlay so they render above the bar
        obj.name_text  = obj.text_overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall", 7)
        obj.name_text:SetJustifyH("LEFT")
        obj.name_text:SetWordWrap(false)
        if obj.name_text.SetMaxLines then
            obj.name_text:SetMaxLines(1)
        end

        -- Timer slot: right zone of bar; timer text anchors here so glyph width
        -- changes do not affect the timer's reference position.
        obj.timer_slot = CreateFrame("Frame", nil, obj.text_overlay)
        add_debug_outline(obj.timer_slot, 0, 1, 0.3, 0.9)

        obj.time_text  = obj.text_overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall", 7)
        M.apply_number_font_to_text(obj.time_text, category)
        obj.time_text:SetWordWrap(false)
        if obj.time_text.SetMaxLines then
            obj.time_text:SetMaxLines(1)
        end

        -- Stack count (shown bottom-right of icon in icon mode; in stack_slot in bar mode)
        obj.count_text = obj.text_overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        obj.count_text:Hide()
        
        -- Tooltip
        obj:EnableMouse(true)
        obj:SetScript("OnEnter", function(s)
            if not s.aura_name then return end
            
            GameTooltip:SetOwner(s, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:ClearLines()
            
            local updated = false
            if s.aura_index then
                -- Modern API (12.0.5+): stable auraInstanceID lookup, no index fragility
                local ok, result = pcall(function()
                    return GameTooltip:SetUnitAuraByAuraInstanceID("player", s.aura_index)
                end)
                updated = ok and result
            end
            
            if not updated then
                GameTooltip:AddLine(s.aura_name, 1, 1, 1)
                if s.aura_duration and s.aura_duration > 0 then
                    local remaining_str = s.aura_remaining and format("%.1f", s.aura_remaining) or "?"
                    local duration_str = format("%.1f", s.aura_duration)
                    GameTooltip:AddLine(remaining_str .. "s / " .. duration_str .. "s", 0.7, 0.7, 1)
                else
                    GameTooltip:AddLine("(Permanent)", 0.7, 0.7, 1)
                end
            end
            
            GameTooltip:Show()
        end)
        obj:SetScript("OnLeave", function() 
            GameTooltip:Hide() 
        end)

        frame.icons[i] = obj
    end

    -- Map-based aura cache: auraInstanceID → entry table. Persists across events.
    frame._aura_map = {}

    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Combat start
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Combat end
    
    -- Store parameters on frame itself for robust access during callbacks
    frame.update_params = {
        show_key = show_key,
        move_key = move_key,
        timer_key = timer_key,
        bg_key = bg_key,
        scale_key = scale_key,
        spacing_key = spacing_key,
        category = category,
        filter = is_debuff and "HARMFUL" or "HELPFUL"
    }
    
    frame:SetScript("OnEvent", function(self, event, unit, info)
        local params = self.update_params
        if not params then return end

        local relevant = (event == "UNIT_AURA" and unit == "player")
            or event == "PLAYER_ENTERING_WORLD"
            or event == "PLAYER_REGEN_DISABLED"
            or event == "PLAYER_REGEN_ENABLED"

        if not relevant then return end

        -- KEY: do NOT scan inside the event handler.
        -- ElkBuffBars uses RegisterBucketEvent("UNIT_AURA", 0.1) for exactly this reason:
        -- C_UnitAuras calls made directly in OnEvent return "secret values" in combat
        -- because the execution context is still tainted by the event dispatch.
        -- Deferring via C_Timer.After(0) runs the scan in the next frame update cycle,
        -- after the tainted context exits — all fields return clean, readable values.
        --
        -- Merge UNIT_AURA payloads while waiting for the deferred scan.
        if event == "UNIT_AURA" then
            self._pending_aura_info = M.merge_aura_info(self._pending_aura_info, info)
        end

        -- Deduplication: if a scan is already queued for this frame, don't queue another.
        -- Multiple rapid UNIT_AURA events (common in combat) collapse to one scan.
        if not self._scan_pending then
            self._scan_pending = true
            local f = self
            -- 0.1s matches ElkBuffBars' RegisterBucketEvent("UNIT_AURA", 0.1) delay.
            -- This ensures the scan runs outside the event-dispatch taint window.
            C_Timer.After(0.1, function()
                f._scan_pending = false
                local event_info = f._pending_aura_info
                f._pending_aura_info = nil
                M.update_auras(f, params.show_key, params.move_key, params.timer_key,
                    params.bg_key, params.scale_key, params.spacing_key, params.filter, event_info)
            end)
        end
    end)
    
    M.frames[show_key] = frame
    return frame
end

-- INITIALIZATION ENGINE: Orchestrate startup of aura frames once addon data is loaded
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name == addon_name then
        -- Ensure the sub-table exists and link the module to the core database
        if not Ls_Tweeks_DB.aura_frames then Ls_Tweeks_DB.aura_frames = {} end
        M.db = Ls_Tweeks_DB.aura_frames

        -- Initialize learned spell-category tables once at load (not per-scan).
        M.db.known_static_spell_ids = M.db.known_static_spell_ids or {}
        M.db.known_long_spell_ids   = M.db.known_long_spell_ids   or {}

        -- Populate missing settings using the defaults defined in af_defaults.lua
        if M.defaults then deep_copy(M.defaults, M.db) end

        if not M.db.timer_number_font then
            M.db.timer_number_font = "source_code_pro"
        end
        if not M.db.timer_number_font_size then
            M.db.timer_number_font_size = (M.get_timer_number_font_size and M.get_timer_number_font_size()) or 10
        end

        -- Migrate legacy global font settings to per-category settings.
        -- Static frame has no timer text, so it does not need per-category timer font settings.
        for _, cat in ipairs({ "short", "long", "debuff" }) do
            local font_key = "timer_number_font_"..cat
            local size_key = "timer_number_font_size_"..cat
            if not M.db[font_key] then
                M.db[font_key] = M.db.timer_number_font or "source_code_pro"
            end
            if not M.db[size_key] then
                M.db[size_key] = (M.get_timer_number_font_size and M.get_timer_number_font_size()) or 10
            end
            local bold_key = "timer_number_font_bold_"..cat
            if M.db[bold_key] == nil then
                M.db[bold_key] = M.db.timer_number_font_bold or false
            end
        end

        local bar_bg_alpha = M.BAR_BG_ALPHA_DEFAULT

        -- Migrate legacy neutral bar background defaults to color-matched default alpha.
        -- Only updates untouched old default values.
        local function is_legacy_bar_bg(c)
            return type(c) == "table"
                and c.r == 0.6 and c.g == 0.6 and c.b == 0.6
                and (c.a == 0.25 or c.a == nil)
        end
        for _, cat in ipairs({ "static", "short", "long", "debuff" }) do
            local bg_key = "bar_bg_color_" .. cat
            if is_legacy_bar_bg(M.db[bg_key]) then
                local fill = M.db["color_" .. cat] or { r = 1, g = 1, b = 1 }
                M.db[bg_key] = { r = fill.r, g = fill.g, b = fill.b, a = bar_bg_alpha }
            end
        end
        
        -- Create the visual containers for each specific category
        M.create_aura_frame("show_static",  "move_static",  "timer_static", "bg_static",    "scale_static", "spacing_static",   "Static",   false)
        M.create_aura_frame("show_short",   "move_short",   "timer_short",  "bg_short",     "scale_short",  "spacing_short",    "Short",    false)
        M.create_aura_frame("show_long",    "move_long",    "timer_long",   "bg_long",      "scale_long",   "spacing_long",     "Long",     false)
        M.create_aura_frame("show_debuff",  "move_debuff",  "timer_debuff", "bg_debuff",    "scale_debuff", "spacing_debuff",   "Debuffs",  true)

        -- Single shared ticker for all frames at 0.1s (ElkBuffBars rate).
        -- Logic is delegated so af_main stays focused on construction/bootstrap.
        C_Timer.NewTicker(0.1, function()
            M.tick_visible_icons()
        end)

        -- Sync the Blizzard frame visibility based on user preferences
        M.toggle_blizz_buffs(M.db.disable_blizz_buffs)
        M.toggle_blizz_debuffs(M.db.disable_blizz_debuffs)

        -- Integrate the settings tab into the main addon configuration menu
        if addon.register_category and M.BuildSettings then
            addon.register_category("Buffs & Debuffs", function(parent) M.BuildSettings(parent) end)
        end

        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- RESET AND REFRESH: Restores UI states following a settings reset or global change
function M.on_reset_complete()
    M.toggle_blizz_buffs(M.db.disable_blizz_buffs)
    M.toggle_blizz_debuffs(M.db.disable_blizz_debuffs)
    M.apply_number_font_to_all()

    if M.sync_general_controls_from_db then
        M.sync_general_controls_from_db()
    end
end