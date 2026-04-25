-- 20 px snap-to-grid system for aura frame positioning, aligned to the screen center (matching the LsTweeks coordinate origin).
-- snap_to_grid(v, is_y) rounds a coordinate to the nearest grid cell; set_grid_visible(show) toggles the visual overlay of grid lines on screen.

local _, addon = ...

addon.aura_frames = addon.aura_frames or {}
local M = addon.aura_frames

local GRID_SIZE     = 20    -- matches Blizzard Edit Mode grid spacing
local GRID_OFFSET_X = -1.5  -- right (positive, no + sign) or left (negative)
local GRID_OFFSET_Y = -0.5  -- up (positive, no + sign) or down (negative)

function M.build_grid_lines()
    local overlay = M.grid_overlay
    if not overlay then return end

    local w   = UIParent:GetWidth()
    local h   = UIParent:GetHeight()
    local ucx, ucy = UIParent:GetCenter()
    local cx  = math.floor(ucx - UIParent:GetLeft() + 0.5) + GRID_OFFSET_X
    local cy  = math.floor(UIParent:GetTop() - ucy  + 0.5) - GRID_OFFSET_Y

    -- build flat list of line specs
    local specs = {}
    local function vspec(x, a) specs[#specs+1] = { v=true,  pos=x, alpha=a } end
    local function hspec(y, a) specs[#specs+1] = { v=false, pos=y, alpha=a } end

    vspec(cx, 0.25)
    hspec(cy, 0.25)
    local step = GRID_SIZE
    while step <= math.max(cx, w - cx) + GRID_SIZE do
        vspec(cx + step, 0.10)
        vspec(cx - step, 0.10)
        step = step + GRID_SIZE
    end
    step = GRID_SIZE
    while step <= math.max(cy, h - cy) + GRID_SIZE do
        hspec(cy + step, 0.10)
        hspec(cy - step, 0.10)
        step = step + GRID_SIZE
    end

    -- Reuse pooled textures; only allocate when pool is exhausted.
    -- WoW cannot destroy textures, so the pool grows to the high-water mark
    -- and stabilises there — no unbounded accumulation across rebuilds.
    M.grid_lines = M.grid_lines or {}
    local pool = M.grid_lines
    for i, s in ipairs(specs) do
        local t = pool[i]
        if not t then
            t = overlay:CreateTexture(nil, "BACKGROUND")
            pool[i] = t
        else
            t:ClearAllPoints()
        end
        t:SetColorTexture(1, 1, 1, s.alpha)
        if s.v then
            t:SetSize(1, h)
            t:SetPoint("TOPLEFT", overlay, "TOPLEFT", s.pos, 0)
        else
            t:SetSize(w, 1)
            t:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, -s.pos)
        end
        t:Show()
    end
    -- hide pool entries beyond what this layout needs
    for i = #specs + 1, #pool do
        pool[i]:Hide()
    end
end

function M.create_grid_overlay()
    if M.grid_overlay then return end
    local overlay = CreateFrame("Frame", "LsTweaksGridOverlay", UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("BACKGROUND")
    overlay:SetFrameLevel(0)
    overlay:Hide()
    M.grid_overlay = overlay
    C_Timer.After(0, function()
        M.build_grid_lines()
        if M.db and M.db.show_grid then overlay:Show() end
    end)
end

function M.set_grid_visible(show)
    if not M.grid_overlay then M.create_grid_overlay() end
    if show then M.grid_overlay:Show() else M.grid_overlay:Hide() end
end

-- snap a coordinate to the nearest grid line (respects offset)
function M.snap_to_grid(v, is_y)
    local offset = is_y and GRID_OFFSET_Y or GRID_OFFSET_X
    return math.floor((v - offset) / GRID_SIZE + 0.5) * GRID_SIZE + offset
end
