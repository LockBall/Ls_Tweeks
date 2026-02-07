local addon_name, addon = ...

function addon.CreateGlobalReset(parent, anchorFrame, db, defaults)
    -- --- CONFIGURATION VARIABLES ---
    local DIM_ALPHA = 0.4    -- Faded when locked
    local READY_ALPHA = 0.8  -- Bright when 'reset' is typed
    local PULSE_MIN = 0.2    -- min 'bright'
    local PULSE_MAX = 1.0    -- max 'bright'
    local PULSE_SPEED = 0.6  -- seconds for one pulse cycle
    
    -- MASK SETTINGS: Increase this number to make the glowing circle SMALLER
    -- 12-14 is usually the "sweet spot" for this specific engineering icon
    local MASK_INSET = 11.5
    -- -------------------------------

    -- Create the Bordered Container Frame
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(parent:GetWidth() - 40, 120) 
    container:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -80)
    
    container:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    container:SetBackdropColor(0, 0, 0, 0.3)
    container:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)

    -- Section Title (Centered)
    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", container, "TOP", 0, -15)
    title:SetText("MODULE RESET")
    title:SetTextColor(1, 0, 0)

    -- Instruction Label
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 15, -45) 
    label:SetText("Input 'arm' !")

    -- Input Box
    local eb = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    eb:SetSize(100, 20)
    eb:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 5, -8)
    eb:SetAutoFocus(false)

    -- The Big Red Button Frame
    local btn = CreateFrame("Button", nil, container)
    btn:SetSize(64, 64) 
    btn:SetPoint("TOP", container, "TOP", 0, -40)

    -- 1. Static Base Texture (The metal part)
    local bgTex = btn:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetTexture("Interface\\Icons\\inv_misc_enggizmos_27")
    bgTex:SetAlpha(DIM_ALPHA)
    btn.bgTex = bgTex

    -- 2. The Pulsing Overlay (The Glow)
    local pulseTex = btn:CreateTexture(nil, "ARTWORK")
    pulseTex:SetAllPoints()
    pulseTex:SetTexture("Interface\\Icons\\inv_misc_enggizmos_27")
    pulseTex:SetBlendMode("ADD") 
    pulseTex:SetAlpha(0)
    btn.pulseTex = pulseTex

    -- 3. Circular Mask (Controlled by MASK_INSET)
    local mask = btn:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    -- We use the variable here to "squeeze" the mask into a smaller circle
    mask:SetPoint("TOPLEFT", pulseTex, "TOPLEFT", MASK_INSET, -MASK_INSET)
    mask:SetPoint("BOTTOMRIGHT", pulseTex, "BOTTOMRIGHT", -MASK_INSET, MASK_INSET)
    pulseTex:AddMaskTexture(mask)

    -- 4. Circular Border (Fixed to remove square overlap)
    local border = btn:CreateTexture(nil, "OVERLAY")
    -- Using a more circular 'Ring' texture to avoid square edges
    border:SetTexture("Interface\\Artifacts\\ArtifactRelic-Slot") 
    border:SetDesaturated(true)
    border:SetAllPoints()
    border:SetAlpha(0.2)

    -- 5. Visual Feedback
    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    -- Ensure the pushed texture is also masked if it looks square
    local pushed = btn:GetPushedTexture()
    pushed:SetBlendMode("MOD") -- Makes it look like it's darkening

    -- Pulse Animation Setup
    local ag = pulseTex:CreateAnimationGroup()
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(PULSE_MIN)
    anim:SetToAlpha(PULSE_MAX)
    anim:SetDuration(PULSE_SPEED)
    anim:SetSmoothing("IN_OUT")
    ag:SetLooping("BOUNCE")

    -- Hover & Activation Scripts
    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then ag:Play() end
    end)

    btn:SetScript("OnLeave", function(self)
        ag:Stop()
        if self:IsEnabled() then pulseTex:SetAlpha(READY_ALPHA) else pulseTex:SetAlpha(0) end
    end)

    btn:Disable()

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

    btn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        table.wipe(db)
        for k, v in pairs(defaults) do db[k] = v end
        if db.positions then db.positions = {} end
        ReloadUI()
    end)
end