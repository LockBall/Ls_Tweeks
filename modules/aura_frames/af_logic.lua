local addon_name, addon = ...

-- CACHED GLOBALS AND CONSTANTS
local floor, math_max, math_ceil = floor, math.max, math.ceil
local GetAuraData = C_UnitAuras.GetAuraDataByIndex
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local debug_mode = false

addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

-- UTILITY FUNCTIONS

-- Logic for converting seconds into readable text strings
local function format_time(s)
    if s >= 3600 then return format("%dh", floor(s/3600)) end
    if s >= 60 then return format("%dm", floor(s/60)) end
    if s >= 5 then return format("%ds", floor(s)) end
    return format("%.1fs", s)
end
M.format_time = format_time

-- HELPER: Safely compares secret numbers in combat
-- Returns true if the comparison succeeds and matches
-- Returns false if the value is secret or comparison fails
local function safe_check(val, comparison_type, threshold)
    local success, result = pcall(function()
        local now = GetTime()
        if comparison_type == "static" then
            return val == 0
        elseif comparison_type == "short" then
            return val > 0 and (val - now) <= threshold
        elseif comparison_type == "long" then
            return val > 0 and (val - now) > threshold
        end
        return false
    end)
    return success and result
end

-- ============================================================================
-- LAYOUT ENGINE:    Pre-calculates positions. Only runs out of combat or on init

function M.setup_layout(self, show_key, spacing_key, use_bars)
    if InCombatLockdown() then return end
    if not self or not self.icons then return end
    
    local db = M.db
    local category = show_key:sub(6)
    local frame_width = db["width_"..category] or 200
    local spacing = db[spacing_key] or 6
    
    local icon_footprint = 32 + spacing
    local icons_per_row = math_max(1, floor((frame_width - 12 + spacing) / icon_footprint))
    
    for i = 1, #self.icons do
        local obj = self.icons[i]
        obj:ClearAllPoints()
        obj.texture:ClearAllPoints()
        
        if use_bars then
            obj:SetSize(frame_width - 12, 20)
            obj:SetPoint("TOPLEFT", self, "TOPLEFT", 6, -((i - 1) * (20 + spacing) + 6))
            obj.texture:SetSize(18, 18)
            obj.texture:SetPoint("LEFT", obj, "LEFT", 0, 0)
            
            obj.bar:ClearAllPoints()
            obj.bar:SetPoint("LEFT", obj.texture, "RIGHT", 5, 0)
            obj.bar:SetPoint("RIGHT", obj, "RIGHT", 0, 0)
            obj.bar:SetHeight(18)
            
            obj.name_text:ClearAllPoints()
            obj.name_text:SetPoint("LEFT", obj.bar, "LEFT", 4, 0)
            
            obj.time_text:ClearAllPoints()
            obj.time_text:SetPoint("RIGHT", obj.bar, "RIGHT", -4, 0)
        else -- icon mode
            obj:SetSize(32, 32)
            obj.texture:SetAllPoints(obj)
            local col = (i - 1) % icons_per_row
            local row = floor((i - 1) / icons_per_row)
            obj:SetPoint("TOPLEFT", self, "TOPLEFT", col * icon_footprint + 6, -(row * (32 + spacing + 12) + 6))
            
            obj.time_text:ClearAllPoints()
            obj.time_text:SetPoint("TOP", obj, "BOTTOM", 0, -2)
        end
    end
    
    self._layout_cache = {
        use_bars = use_bars,
        icons_per_row = icons_per_row,
        frame_width = frame_width,
        spacing = spacing
    }
end

-- ============================================================================
-- AURA SCANNING AND RENDERING

function M.update_auras(self, show_key, move_key, timer_key, bg_key, scale_key, spacing_key, filter)
    if not self or not self.icons then return end
    
    local db = M.db
    local category = show_key:sub(6)
    local use_bars = db["use_bars_"..category]
    local frame_width = db["width_"..category] or 200
    local spacing = db[spacing_key] or 6

    local color = db["color_"..category] or {r=1, g=1, b=1}
    local bgC = db["bg_color_"..category] or {r=0, g=0, b=0, a=0.5}
    local short_threshold = db.short_threshold or 60

    -- Scale and Layout Refresh logic
    self:SetScale(db[scale_key] or 1.0)
    
    if not self._layout_cache
        or (not InCombatLockdown()
        and (self._layout_cache.frame_width ~= frame_width
        or self._layout_cache.use_bars ~= use_bars
        or self._layout_cache.spacing ~= spacing
    )) then
        M.setup_layout(self, show_key, spacing_key, use_bars)
    end

    -- Cleanup current state
    for i = 1, #self.icons do
        local obj = self.icons[i]
        obj:Hide()
        if obj.ticker then obj.ticker:Cancel() end 
    end

    -- Check if frame should be shown
    local is_moving = db[move_key]
    
    -- Apply backdrop colors FIRST (before any early returns)
    if is_moving then
        -- Move mode: use custom color if available, otherwise dark with white border
        local is_bg_enabled = db[bg_key]
        if is_bg_enabled and bgC then
            self:SetBackdropColor(bgC.r, bgC.g, bgC.b, bgC.a or 1)
            self:SetBackdropBorderColor(1, 1, 1, 1)  -- White border for visibility in move mode
        else
            -- Fallback to dark background with white border
            self:SetBackdropColor(0, 0, 0, 0.8)
            self:SetBackdropBorderColor(1, 1, 1, 1)
        end
    else
        -- Normal mode: apply custom background if enabled
        local is_bg_enabled = db[bg_key]
        if is_bg_enabled then 
            if bgC then
                self:SetBackdropColor(bgC.r, bgC.g, bgC.b, bgC.a or 1)
                self:SetBackdropBorderColor(0, 0, 0, 0) 
            end
        else
            -- Force transparency if toggle is off
            self:SetBackdropColor(0, 0, 0, 0)
            self:SetBackdropBorderColor(0, 0, 0, 0)
        end
    end

    -- Early exit if not showing and not moving
    if not db[show_key] and not is_moving then
        self:Hide()
        return 
    end

    -- Show title bar and resizer based on move state
    if is_moving then
        self.title_bar:Show()
        self.bottom_title_bar:Show()
        self.resizer:Show()
    else
        self.title_bar:Hide()
        self.bottom_title_bar:Hide()
        self.resizer:Hide()
    end

    -- If in move mode but category not shown, show frame for moving but don't scan auras
    if is_moving and not db[show_key] then
        if not InCombatLockdown() then self:SetHeight(44) end
        self:Show()
        return
    end

    -- Show frame when category is enabled
    if db[show_key] then
        self:Show()
    end

    -- MODERN SCANNING LOOP (Combat Protected)
    local display_index = 1
    local index = 1
    local max_limit = db["max_icons_"..category] or 40

    while true do
        local aura_data = GetAuraData("player", index, filter)
        if not aura_data or (display_index > max_limit) then break end

        if aura_data.name then
            local exp = aura_data.expirationTime or 0
            local belongs_here = false

            -- LOGIC: Use safe_check to avoid Secret Number crashes
            if show_key == "show_static" then
                belongs_here = safe_check(exp, "static")
            elseif filter == "HARMFUL" then
                belongs_here = true
            elseif show_key == "show_short" then
                belongs_here = safe_check(exp, "short", short_threshold)
            elseif show_key == "show_long" then
                -- Fallback logic ensures secret buffs remain visible
                local is_long = safe_check(exp, "long", short_threshold)
                local is_secret = not pcall(function() return exp > 0 end)
                belongs_here = is_long or is_secret
            end

            if belongs_here then
                local obj = self.icons[display_index]
                if obj then
                    obj.aura_index = index 
                    obj.texture:SetTexture(aura_data.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    
                    if use_bars then
                        obj.bar:Show()
                        obj.bar:SetStatusBarColor(color.r, color.g, color.b)
                        obj.name_text:SetText(aura_data.name)
                        obj.name_text:Show()
                    else
                        obj.bar:Hide()
                        obj.name_text:Hide()
                    end

                    -- Timer Logic: Protected against ticker calculation errors
                    local has_timing = false
                    pcall(function() if exp > 0 then has_timing = true end end)

                    if has_timing then
                        local safe_exp = exp
                        local safe_dur = aura_data.duration or 0
                        
                        local function update_timer()
                            -- Formula for remaining duration:
                            -- $$remain = \max(0, safe\_exp - GetTime())$$
                            local remain = math_max(0, safe_exp - GetTime())
                            obj.time_text:SetText(M.format_time(remain))
                            
                            if use_bars and safe_dur > 0 then
                                obj.bar:SetMinMaxValues(0, safe_dur)
                                obj.bar:SetValue(remain)
                            end
                        end
                        
                        update_timer()
                        -- Refreshing at a 0.1 second interval
                        obj.ticker = C_Timer.NewTicker(0.1, update_timer)
                    else
                        obj.time_text:SetText("")
                        if use_bars then
                            obj.bar:SetMinMaxValues(0, 1)
                            obj.bar:SetValue(1)
                        end
                    end

                    obj:Show()
                    display_index = display_index + 1
                end
            end
        end
        index = index + 1
        -- Safety exit to prevent an infinite loop
        if index > 200 then break end 
    end

    -- Update frame height based on count of icons
    if not InCombatLockdown() then
        if display_index > 1 then
            self:Show()
            local total_icons = display_index - 1
            if use_bars then
                self:SetHeight(total_icons * (20 + spacing) + 12)
            else
                local rows = math_ceil(total_icons / self._layout_cache.icons_per_row)
                self:SetHeight(rows * (32 + spacing + 12) + 6)
            end
        elseif not is_moving then
            self:Hide()
        end
    end
end