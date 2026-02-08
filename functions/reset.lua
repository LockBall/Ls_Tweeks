local addon_name, addon = ...

function addon.CreateGlobalReset(parent, anchorFrame, db, defaults)

    -------- CONFIGURATION VARIABLES --------
    local DIM_ALPHA = 0.5    -- Faded transparency when the button is locked
    local READY_ALPHA = 0.6  -- Full transparency when 'arm' is typed

    -- PULSE Params
    local PULSE_MIN = 0.0    -- Minimum brightness during the pulse cycle
    local PULSE_MAX = 1.1    -- Maximum brightness during the pulse cycle
    local PULSE_SPEED = 0.75 -- Duration in seconds for one pulse cycle (lower is faster)

    -- MASK SETTINGS
    local MASK_INSET = 13  -- Increase to make circular "window" smaller

    -- GLOW SIZE PARAMETERS
    local GLOW_SIZE = 60 
    local BEZEL_SPILL = 7    
    -----------------------------------------

    -- CONTAINER
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(parent:GetWidth() - 40, 120)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -200)
    container:SetFrameLevel(parent:GetFrameLevel() + 10)

    -- BACKDROP
    container:SetBackdrop({
        bgFile = "Interface\\FrameGeneral\\UI-Background-Rock", -- Grainy stone/metal texture
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, 
        tileSize = 256,
        edgeSize = 30,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    container:SetBackdropColor(0.65, 0.6, 0.75, 1.0 ) 
    container:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.6)

    -- BOLTED PANEL DETAIL (Rivets)
    local function CreateScrew(point, x, y)
        local s = container:CreateTexture(nil, "OVERLAY", nil, 6)
        s:SetSize(10, 10)
        s:SetTexture("Interface\\Buttons\\WHITE8x8")
        s:SetVertexColor(0.3, 0.3, 0.3, 1.0)
        s:SetPoint(point, container, point, x, y)

        local m = container:CreateMaskTexture()
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(s)
        s:AddMaskTexture(m)

        local shine = container:CreateTexture(nil, "OVERLAY", nil, 7)
        shine:SetSize(3, 3)
        shine:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        shine:SetVertexColor(0.8, 0.8, 0.8, 0.4)
        shine:SetPoint("CENTER", s, "CENTER", -2, 2)
        shine:AddMaskTexture(m)
    end

    CreateScrew("TOPLEFT", 14, -14)
    CreateScrew("TOPRIGHT", -14, -14)
    CreateScrew("BOTTOMLEFT", 14, 14)
    CreateScrew("BOTTOMRIGHT", -14, 14)

    -- TITLE
    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", container, "TOP", 0, -15)
    title:SetText("Module Reset")
    title:SetTextColor(1, 0.82, 0)

    -- INSTRUCTION LABEL
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 28, -45)
    label:SetText(" Input 'arm' code !?")

    -- INPUT BOX
    local eb = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    eb:SetSize(75, 20)
    eb:SetPoint("TOP", label, "TOP", 0, -16)
    eb:SetAutoFocus(false)
    eb:SetTextInsets(0, 7, 0, 0)
    eb:SetJustifyH("CENTER")
    eb:SetFontObject("NumberFontNormal")
    eb:SetTextColor(1, 1, 1)

    -- BIG RED BUTTON ICON
    local btn = CreateFrame("Button", nil, container)
    btn:SetSize(64, 64)
    btn:SetPoint("TOP", container, "TOP", 0, -40)

    -- STATIC BUTTON TEXTURE
    local bgTex = btn:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetTexture("Interface\\Icons\\inv_misc_enggizmos_27")
    bgTex:SetAlpha(DIM_ALPHA)

    -- PULSING OVERLAY
    local pulseTex = btn:CreateTexture(nil, "ARTWORK")
    pulseTex:SetSize(GLOW_SIZE + BEZEL_SPILL, GLOW_SIZE + BEZEL_SPILL)
    pulseTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
    pulseTex:SetTexture("Interface\\Icons\\inv_misc_enggizmos_27")
    pulseTex:SetBlendMode("ADD")
    pulseTex:SetAlpha(0)

    -- CIRCULAR MASK
    local mask = btn:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", pulseTex, "TOPLEFT", MASK_INSET, -MASK_INSET)
    mask:SetPoint("BOTTOMRIGHT", pulseTex, "BOTTOMRIGHT", -MASK_INSET, MASK_INSET)
    pulseTex:AddMaskTexture(mask)

    -- CIRCULAR BORDER
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Artifacts\\ArtifactRelic-Slot")
    border:SetDesaturated(true)
    border:SetAllPoints()
    border:SetAlpha(0.2)

    -- PUSHED TEXTURE
    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    local pushed = btn:GetPushedTexture()
    pushed:SetBlendMode("MOD")

    -- PULSE ANIMATION
    local ag = pulseTex:CreateAnimationGroup()
    local animAlpha = ag:CreateAnimation("Alpha")
    animAlpha:SetFromAlpha(PULSE_MIN)
    animAlpha:SetToAlpha(PULSE_MAX)
    animAlpha:SetDuration(PULSE_SPEED)
    animAlpha:SetSmoothing("IN_OUT")
    ag:SetLooping("BOUNCE")

    -- --- SECURITY LOGIC: AUTO-CLEAR ON HIDE ---
    container:SetScript("OnHide", function()
        eb:SetText("")
        eb:ClearFocus()
        btn:Disable()
        ag:Stop()
    end)

    -- INTERACTIVE SCRIPTS
    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then ag:Play() end
    end)

    btn:SetScript("OnLeave", function(self)
        ag:Stop()
        if self:IsEnabled() then 
            pulseTex:SetAlpha(READY_ALPHA) 
        else 
            pulseTex:SetAlpha(0) 
        end
    end)

    btn:Disable()

    -- TERMINAL INPUT LOGIC
    eb:SetScript("OnTextChanged", function(self)
        local rawText = self:GetText()
        local upperText = rawText:upper()

        if rawText ~= upperText then
            self:SetText(upperText)
        end

        if upperText == "ARM" then
            btn:Enable()
            bgTex:SetAlpha(READY_ALPHA)
            pulseTex:SetAlpha(READY_ALPHA)
            self:ClearFocus()
            self:SetFontObject("NumberFont_Shadow_Med")
            self:SetTextColor(0, 1, 0) 
        else
            btn:Disable()
            ag:Stop()
            bgTex:SetAlpha(DIM_ALPHA)
            pulseTex:SetAlpha(0)
            self:SetFontObject("NumberFontNormal")
            self:SetTextColor(1, 1, 1)
        end
    end)

    -- RESET EXECUTION
    btn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        table.wipe(db)
        if type(defaults) == "table" then
            for k, v in pairs(defaults) do db[k] = v end
        end
        if db.positions then db.positions = {} end
        ReloadUI()
    end)
end