local addon_name, addon = ...

function addon.CreateGlobalReset(parent, anchorFrame, db, defaults)

    -- --- CONFIGURATION VARIABLES ---
    local DIM_ALPHA = 0.5    -- Faded transparency when the button is locked
    local READY_ALPHA = 0.6  -- Full transparency when 'arm' is typed

    -- PULSE Params
    local PULSE_MIN = 0.0    -- Minimum brightness during the pulse cycle
    local PULSE_MAX = 1.1    -- Maximum brightness during the pulse cycle
    local PULSE_SPEED = 0.75  -- Duration in seconds for one pulse cycle (lower is faster)

    -- MASK SETTINGS
    local MASK_INSET = 13  -- Increase to make circular "window" smaller (keeps glow off the metal frame)

    -- GLOW SIZE PARAMETERS
    -- GLOW_SIZE .
    -- BEZEL_SPILL controls how much the glow overlaps the bezel (adds illumination).
    local GLOW_SIZE = 60     -- core glow size, lower # = decreased diameter 
    local BEZEL_SPILL = 7    -- Extra pixels added to glow size to illuminate bezel

    ---------------------------------

    -- CONTAINER
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(parent:GetWidth() - 40, 120)
    container:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -80)

    container:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    container:SetBackdropColor(0, 0, 0, 0.4)
    container:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)

    -- TITLE
    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", container, "TOP", 0, -15)
    title:SetText("MODULE RESET")
    title:SetTextColor(1, 0, 0)

    -- INSTRUCTION LABEL
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 15, -45)
    label:SetText("Input 'arm' !")

    -- INPUT BOX
    local eb = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    eb:SetSize(100, 20)
    eb:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 5, -8)
    eb:SetAutoFocus(false)

    -- BIG RED BUTTON
    local btn = CreateFrame("Button", nil, container)
    btn:SetSize(64, 64)
    btn:SetPoint("TOP", container, "TOP", 0, -40)

    -- STATIC BASE TEXTURE
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

    -- PULSE ANIMATION (Alpha only – no scale to avoid jitter)
    local ag = pulseTex:CreateAnimationGroup()

    local animAlpha = ag:CreateAnimation("Alpha")
    animAlpha:SetFromAlpha(PULSE_MIN)
    animAlpha:SetToAlpha(PULSE_MAX)
    animAlpha:SetDuration(PULSE_SPEED)
    animAlpha:SetSmoothing("IN_OUT")

    ag:SetLooping("BOUNCE")

    -- --- SECURITY LOGIC: AUTO-CLEAR ON HIDE ---
    container:SetScript("OnHide", function()
        eb:SetText("")    -- Clear the text box
        eb:ClearFocus()   -- Remove cursor if active
    end)

    -- INTERACTIVE SCRIPTS
    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then ag:Play() end
    end)

    btn:SetScript("OnLeave", function(self)
        ag:Stop()
        if self:IsEnabled() then pulseTex:SetAlpha(READY_ALPHA) else pulseTex:SetAlpha(0) end
    end)

    btn:Disable()

    -- ACTIVATION LOGIC
    eb:SetScript("OnTextChanged", function(self)
        if self:GetText():lower() == "arm" then
            btn:Enable()
            bgTex:SetAlpha(READY_ALPHA)
            pulseTex:SetAlpha(READY_ALPHA)
        else
            btn:Disable()
            ag:Stop()
            bgTex:SetAlpha(DIM_ALPHA)
            pulseTex:SetAlpha(0)
        end
    end)

    -- RESET EXECUTION
    btn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        table.wipe(db)
        for k, v in pairs(defaults) do db[k] = v end
        if db.positions then db.positions = {} end
        ReloadUI()
    end)
end