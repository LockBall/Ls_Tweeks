local addon_name, addon = ...

-- Create a riveted textured panel and return (panel, textFontString)
-- parent            : parent frame
-- width, height     : panel size (numbers)
-- anchorTo          : frame to anchor to (optional, defaults to parent)
-- anchorPoint       : anchor point on anchorTo (optional, "TOPLEFT")
-- x, y              : offset from anchor (optional)
-- frameLevelOffset  : panel frame level offset relative to parent (optional)
function addon.CreateRivetedPanel(parent, width, height, anchorTo, anchorPoint, x, y, frameLevelOffset)
    local anchorTo = anchorTo or parent
    local anchorPoint = anchorPoint or "TOPLEFT"
    local x = x or 0
    local y = y or 0
    local frameLevelOffset = frameLevelOffset or 8
    local edgeSize = 36
    local rivet_inset = edgeSize - 22

    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetPoint(anchorPoint, anchorTo, anchorPoint, x, y)
    panel:SetFrameLevel(parent:GetFrameLevel() + frameLevelOffset)

    panel:SetBackdrop({
        bgFile   = "Interface\\FrameGeneral\\UI-Background-Marble",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 256,
        edgeSize = edgeSize,
        insets   = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    panel:SetBackdropColor(0.65, 0.6, 0.75, 1.0)
    panel:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.6)

    local function CreateRivet(point, rx, ry)
        local s = panel:CreateTexture(nil, "OVERLAY", nil, 6)
        s:SetSize(10, 10)
        s:SetTexture("Interface\\Buttons\\WHITE8x8")
        s:SetVertexColor(0.3, 0.3, 0.3, 1.0)
        s:SetPoint(point, panel, point, rx, ry)

        local m = panel:CreateMaskTexture()
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(s)
        s:AddMaskTexture(m)

        local shine = panel:CreateTexture(nil, "OVERLAY", nil, 7)
        shine:SetSize(3, 3)
        shine:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        shine:SetVertexColor(0.8, 0.8, 0.8, 0.4)
        shine:SetPoint("CENTER", s, "CENTER", -2, 2)
        shine:AddMaskTexture(m)
    end

    CreateRivet("TOPLEFT",     rivet_inset, -rivet_inset)
    CreateRivet("TOPRIGHT",   -rivet_inset, -rivet_inset)
    CreateRivet("BOTTOMLEFT",  rivet_inset,  rivet_inset)
    CreateRivet("BOTTOMRIGHT", -rivet_inset,  rivet_inset)

    local inner = panel:CreateTexture(nil, "BORDER")
    inner:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
    inner:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
    inner:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    inner:SetVertexColor(0.06, 0.06, 0.07, 0.6)

    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
    text:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)

    return panel, text
end