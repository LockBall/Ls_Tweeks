-- Shared decorative panel style used throughout LsTweeks: marble background, ornate dialog-frame borders, and corner rivet textures.
-- ApplyRivetedPanelStyle() and AddRivetCorners() dress an existing frame; CreateRivetedPanel() builds a fully styled panel from scratch.
local addon_name, addon = ...

addon.RIVETED_PANEL_STYLE = addon.RIVETED_PANEL_STYLE or {
    -- Backdrop appearance
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tileSize = 256,
    backdropInsets = { left = 5, right = 5, top = 5, bottom = 5 },
    bgColor = { 0.65, 0.6, 0.75, 1.0 },
    borderColor = { 0.6, 0.6, 0.6, 0.6 },

    -- Layout helpers for modules that create riveted panels
    padding        = 33,    -- inner content padding
    panel_margin   = 60,    -- margin from parent edges when sizing panel width
    panel_min_height = 60,  -- minimum panel height
    panel_max_width  = 420, -- maximum panel width
    offset_x       = 0,     -- default horizontal placement offset
    offset_y       = -50,   -- default vertical placement offset
    font_panel     = "GameFontHighlightSmall", -- font for text inside panels

    rivet = {
        size = 10,
        texture = "Interface\\Buttons\\WHITE8x8",
        color = { 0.3, 0.3, 0.3, 1.0 },
        shineSize = 3,
        shineTexture = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
        shineColor = { 0.8, 0.8, 0.8, 0.4 },
        shineOffsetX = -2,
        shineOffsetY = 2,
        defaultInset = 14,
    },
}

function addon.ApplyRivetedPanelStyle(frame, opts)
    local style = addon.RIVETED_PANEL_STYLE
    local options = opts or {}
    local edgeSize = options.edgeSize or 36
    local bgColor = options.bgColor or style.bgColor
    local borderColor = options.borderColor or style.borderColor
    local insets = options.insets or style.backdropInsets

    frame:SetBackdrop({
        bgFile   = options.bgFile or "Interface\\FrameGeneral\\UI-Background-Marble",
        edgeFile = options.edgeFile or style.edgeFile,
        tile     = true,
        tileSize = options.tileSize or style.tileSize,
        edgeSize = edgeSize,
        insets   = { left = insets.left, right = insets.right, top = insets.top, bottom = insets.bottom }
    })
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])

    if options.addRivets ~= false then
        addon.AddRivetCorners(
            frame,
            options.rivetInset or style.rivet.defaultInset,
            options.rivetOffsetX,
            options.rivetOffsetY
        )
    end
end

-- Create a riveted textured panel and return (panel, textFontString)
-- parent            : parent frame
-- width, height     : panel size (numbers)
-- anchorTo          : frame to anchor to (optional, defaults to parent)
-- anchorPoint       : anchor point on anchorTo (optional, "TOPLEFT")
-- x, y              : offset from anchor (optional)
-- frameLevelOffset  : panel frame level offset relative to parent (optional)
function addon.CreateRivetedPanel(parent, width, height, anchorTo, anchorPoint, x, y, frameLevelOffset)
    local anchorTarget = anchorTo or parent
    local point = anchorPoint or "TOPLEFT"
    local offsetX = x or 0
    local offsetY = y or 0
    local levelOffset = frameLevelOffset or 8
    local edgeSize = 36
    local rivetInset = edgeSize - 22

    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetPoint(point, anchorTarget, point, offsetX, offsetY)
    panel:SetFrameLevel(parent:GetFrameLevel() + levelOffset)

    addon.ApplyRivetedPanelStyle(panel, {
        bgFile = "Interface\\FrameGeneral\\UI-Background-Marble",
        edgeSize = edgeSize,
        rivetInset = rivetInset,
    })

    local inner = panel:CreateTexture(nil, "BORDER")
    inner:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
    inner:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
    inner:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    inner:SetVertexColor(0.06, 0.06, 0.07, 0.6)

    local text = panel:CreateFontString(nil, "ARTWORK", addon.RIVETED_PANEL_STYLE.font_panel)
    text:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
    text:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)

    return panel, text
end

-- Shared corner-rivet painter. Paints 4 masked screws at the corners of `frame`.
-- Optional offsets allow shifting all rivets together without changing inset.
-- Used by both CreateRivetedPanel (above) and module_reset's CreateGlobalReset.
function addon.AddRivetCorners(frame, inset, offsetX, offsetY)
    local rivetStyle = addon.RIVETED_PANEL_STYLE.rivet
    local ox = offsetX or 0
    local oy = offsetY or 0

    local function PaintRivet(point, rx, ry)
        local s = frame:CreateTexture(nil, "OVERLAY", nil, 6)
        s:SetSize(rivetStyle.size, rivetStyle.size)
        s:SetTexture(rivetStyle.texture)
        s:SetVertexColor(rivetStyle.color[1], rivetStyle.color[2], rivetStyle.color[3], rivetStyle.color[4])
        s:SetPoint(point, frame, point, rx, ry)

        local m = frame:CreateMaskTexture()
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(s)
        s:AddMaskTexture(m)

        local shine = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        shine:SetSize(rivetStyle.shineSize, rivetStyle.shineSize)
        shine:SetTexture(rivetStyle.shineTexture)
        shine:SetVertexColor(rivetStyle.shineColor[1], rivetStyle.shineColor[2], rivetStyle.shineColor[3], rivetStyle.shineColor[4])
        shine:SetPoint("CENTER", s, "CENTER", rivetStyle.shineOffsetX, rivetStyle.shineOffsetY)
        shine:AddMaskTexture(m)
    end
    PaintRivet("TOPLEFT",      inset + ox, -inset + oy)
    PaintRivet("TOPRIGHT",    -inset + ox, -inset + oy)
    PaintRivet("BOTTOMLEFT",   inset + ox,  inset + oy)
    PaintRivet("BOTTOMRIGHT", -inset + ox,  inset + oy)
end