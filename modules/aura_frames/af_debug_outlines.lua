-- Debug helper that draws 1px border outlines on aura icon slot frames to visualize layout boundaries.
-- refresh_section_outlines() reads M.db.show_bar_section_outlines and adds or removes outlines accordingly; outlines are tagged ._is_outline for safe cleanup.
local addon_name, addon = ...
local M = addon.aura_frames

local function is_outline_enabled()
    return M.db and M.db.show_bar_section_outlines
end

local function add_debug_outline(frame, r, g, b, a)
    if not is_outline_enabled() or not frame then return end
    local t = 1
    local regions = { frame:GetRegions() }
    for _, region in ipairs(regions) do
        if region and region._is_outline then
            region:Hide()
            region:SetTexture(nil)
        end
    end
    local outline_defs = {
        { points = { {"TOPLEFT", 0, 0}, {"TOPRIGHT", 0, 0} }, size = { "Height", t } },
        { points = { {"BOTTOMLEFT", 0, 0}, {"BOTTOMRIGHT", 0, 0} }, size = { "Height", t } },
        { points = { {"TOPLEFT", 0, 0}, {"BOTTOMLEFT", 0, 0} }, size = { "Width", t } },
        { points = { {"TOPRIGHT", 0, 0}, {"BOTTOMRIGHT", 0, 0} }, size = { "Width", t } },
    }
    for _, def in ipairs(outline_defs) do
        local tex = frame:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(r, g, b, a)
        tex:SetPoint(def.points[1][1], frame, def.points[1][1], def.points[1][2], def.points[1][3])
        tex:SetPoint(def.points[2][1], frame, def.points[2][1], def.points[2][2], def.points[2][3])
        tex["Set"..def.size[1]](tex, def.size[2])
        tex._is_outline = true
    end
end

function M.add_debug_outline(frame, r, g, b, a)
    add_debug_outline(frame, r, g, b, a)
end

function M.refresh_section_outlines()
    for _, frame in pairs(M.frames or {}) do
        if frame and frame.icons then
            for _, obj in ipairs(frame.icons) do
                local slots = { obj.stack_slot, obj.name_slot, obj.timer_slot }
                for _, slot in ipairs(slots) do
                    local regions = { slot:GetRegions() }
                    for _, region in ipairs(regions) do
                        if region and region._is_outline then
                            region:Hide()
                            region:SetTexture(nil)
                        end
                    end
                end
                if is_outline_enabled() then
                    local slot_colors = {
                        {obj.stack_slot, 1, 0.4, 0, 0.9},
                        {obj.name_slot, 0, 0.6, 1, 0.9},
                        {obj.timer_slot, 0, 1, 0.3, 0.9},
                    }
                    for _, v in ipairs(slot_colors) do
                        add_debug_outline(v[1], v[2], v[3], v[4], v[5])
                    end
                end
            end
        end
    end
end
