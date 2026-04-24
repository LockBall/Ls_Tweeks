local addon_name, addon = ...

local floor          = math.floor
local math_max       = math.max
local math_ceil      = math.ceil
local InCombatLockdown = InCombatLockdown

addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

-- ============================================================================
-- TIMER TEXT ENABLE CHECK

function M.is_timer_text_enabled(db, category, timer_key)
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

-- ============================================================================
-- BAR LAYOUT PARAMS

function M.get_bar_layout_params(timer_font_size)
    timer_font_size = tonumber(timer_font_size) or 10
    local min_width = 36
    local scale_factor = 2.7
    local timer_slot_width = math_max(min_width, math_ceil(timer_font_size * scale_factor))

    return {
        frame_inset = 6,
        frame_inner_width_pad = 12,
        row_height = 18,

        icon_size = 18,
        icon_to_bar_gap = 5,
        bar_height = 18,

        stack_slot_left_pad = 2,
        stack_slot_width = 20,
        stack_slot_height = 18,

        timer_slot_width = timer_slot_width,
        timer_slot_right_pad = 2,
        timer_slot_height = 18,

        name_slot_left_gap = 2,
        name_slot_right_gap = 2,
        name_slot_right_no_timer = 4,
        name_slot_height = 18,

        name_text_left_pad = 2,
        name_text_right_pad = 2,
    }
end

-- ============================================================================
-- FRAME HEIGHT RESIZE (preserves anchor point)

-- Resize self to new_height while keeping the stable edge anchored.
-- DOWN keeps top edge fixed; UP keeps bottom edge fixed.
function M.set_height_for_growth(self, new_height, growth)
    if not self then return end

    local old_height = self:GetHeight()
    if old_height == new_height then return end
    local delta = new_height - old_height

    local point, relative_to, relative_point, x, y = self:GetPoint(1)

    self:SetHeight(new_height)

    if not point then return end

    if relative_to and relative_to ~= UIParent then
        relative_to = UIParent
    end
    relative_point = relative_point or point
    x = x or 0
    y = y or 0

    local p = tostring(point or "")
    local is_top    = p:find("TOP",    1, true) ~= nil
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
-- LAYOUT ENGINE

function M.setup_layout(self, show_key, spacing_key, bar_mode)
    if not self or not self.icons then return end
    if InCombatLockdown() then return end

    local db = M.db
    local category = show_key:sub(6)
    local frame_width = db["width_"..category] or 200
    local spacing = db[spacing_key] or 6
    local growth = db["growth_"..category] or "DOWN"

    local show_timer_text = M.is_timer_text_enabled(db, category)
    local timer_font_size = (M.get_timer_number_font_size and M.get_timer_number_font_size(category)) or 10
    local bar_layout = M.get_bar_layout_params(timer_font_size)
    local timer_text_align = (category == "long") and "CENTER" or "RIGHT"
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

            obj.stack_slot:ClearAllPoints()
            obj.stack_slot:SetPoint("LEFT", obj.bar, "LEFT", bar_layout.stack_slot_left_pad, 0)
            obj.stack_slot:SetSize(bar_layout.stack_slot_width, bar_layout.stack_slot_height)
            obj.stack_slot:Show()

            obj.timer_slot:ClearAllPoints()
            obj.timer_slot:SetPoint("RIGHT", obj.bar, "RIGHT", -bar_timer_slot_right_pad, 0)
            obj.timer_slot:SetSize(bar_timer_slot_width, bar_layout.timer_slot_height)

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
            obj.count_text:Hide()

        else
            obj:SetSize(icon_size, icon_size)
            obj.texture:SetAllPoints(obj)

            local col_idx = (i - 1) % icons_per_row
            local row_idx = floor((i - 1) / icons_per_row)
            local timer_h = show_timer_text and 12 or 0
            local row_h   = icon_size + spacing + timer_h

            local up_offset = 6 + (timer_h > 0 and (timer_h + 2) or 0)
            if growth == "UP" then
                obj:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 6, row_idx * row_h + up_offset)
            elseif growth == "DOWN" then
                obj:SetPoint("TOPLEFT", self, "TOPLEFT", 6, -(row_idx * row_h + 6))
            elseif growth == "LEFT" then
                obj:SetPoint("TOPRIGHT", self, "TOPRIGHT",
                    -(col_idx * icon_footprint + 6), -(row_idx * row_h + 6))
            else
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
        icon_size       = 32,
    }
end
