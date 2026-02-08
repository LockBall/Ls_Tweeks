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
    local MASK_INSET = 13  -- Increase to make circular "window" smaller (keeps glow off the metal frame)

    -- GLOW SIZE PARAMETERS
    -- BEZEL_SPILL controls how much the glow overlaps the bezel (adds illumination).
    local GLOW_SIZE = 60     -- core glow size, lower # = decreased diameter 
    local BEZEL_SPILL = 7    -- Extra pixels added to glow size to illuminate bezel
    ---------------------------------

    -- CONTAINER
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(parent:GetWidth() - 40, 120)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -200)
    container:SetFrameLevel(parent:GetFrameLevel() + 10)

    -- BACKDROP
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, 
        edgeSize = 30, -- Increased from 16 to 24 for thickness
        insets = { left = 5, right = 5, top = 5, bottom = 5 } -- Increased insets to match thicker edge
    })
    container:SetBackdropColor(0.1, 0.12, 0.15, 1.0) 
    container:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.6)

    -- BOLTED PANEL DETAIL
    local function CreateScrew(point, x, y)

        -- Base Rivet Texture
        local s = container:CreateTexture(nil, "OVERLAY", nil, 6)
        s:SetSize(10, 10)
        s:SetTexture("Interface\\Buttons\\WHITE8x8")
        s:SetVertexColor(0.3, 0.3, 0.3, 1.0) -- red, green, blue, alpha
        s:SetPoint(point, container, point, x, y)

        -- Unique Mask for THIS Rivet
        local m = container:CreateMaskTexture()
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(s)
        s:AddMaskTexture(m)

        -- Shine Dot
        local shine = container:CreateTexture(nil, "OVERLAY", nil, 7)
        shine:SetSize(3, 3)
        shine:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        shine:SetVertexColor(0.8, 0.8, 0.8, 0.4) -- Subtle highlight
        shine:SetPoint("CENTER", s, "CENTER", -2, 2)
        shine:AddMaskTexture(m) -- Uses the same unique mask

        -- depth shadow
        local shadow = container:CreateTexture(nil, "OVERLAY", nil, 5)
        shadow:SetSize(12, 12) -- Slightly larger than the 10x10 rivet
        shadow:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        shadow:SetVertexColor(0, 0, 0, 0.4) -- Very faint black shadow
        shadow:SetPoint("CENTER", s, "CENTER", 0, 0)
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
    eb:SetTextInsets(0, 8, 0, 0) -- Pixels to push text from left, right, top, bottom edge of box
    eb:SetJustifyH("CENTER")

    -- BIG RED BUTTON ICON
    local btn = CreateFrame("Button", nil, container)
    btn:SetSize(64, 64)
    btn:SetPoint("TOP", container, "TOP", 0, -40)

    -- STATIC BUTTON TEXTURE
    local bgTex = btn:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetTexture("Interface\\Icons\\inv_misc_enggizmos_27")
    bgTex:SetAlpha(DIM_ALPHA)
    btn.bgTex = bgTex -- Store on button for scope access

    -- PULSING OVERLAY
    local pulseTex = btn:CreateTexture(nil, "ARTWORK")
    pulseTex:SetSize(GLOW_SIZE + BEZEL_SPILL, GLOW_SIZE + BEZEL_SPILL)
    pulseTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
    pulseTex:SetTexture("Interface\\Icons\\inv_misc_enggizmos_27")
    pulseTex:SetBlendMode("ADD")
    pulseTex:SetAlpha(0)
    btn.pulseTex = pulseTex -- Store on button for scope access

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
    btn.ag = ag -- Store on button for easy access

    -- --- SECURITY LOGIC: AUTO-CLEAR ON HIDE ---
    container:SetScript("OnHide", function()
        eb:SetText("")    -- Clear the text box
        eb:ClearFocus()   -- Remove cursor if active
        btn:Disable()     -- Explicitly disable to ensure state reset
        btn.ag:Stop()     -- Stop animation immediately
    end)

    -- INTERACTIVE SCRIPTS
    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self.ag:Play() end
    end)

    btn:SetScript("OnLeave", function(self)
        self.ag:Stop()
        if self:IsEnabled() then self.pulseTex:SetAlpha(READY_ALPHA) else self.pulseTex:SetAlpha(0) end
    end)

    btn:Disable()

    -- ACTIVATION LOGIC
    eb:SetScript("OnTextChanged", function(self)
        local text = self:GetText():lower()
        if text == "arm" then
            btn:Enable()
            btn.bgTex:SetAlpha(READY_ALPHA)
            btn.pulseTex:SetAlpha(READY_ALPHA)
            self:ClearFocus() -- UI Polish: Closes keyboard/cursor when armed
        else
            btn:Disable()
            btn.ag:Stop()
            btn.bgTex:SetAlpha(DIM_ALPHA)
            btn.pulseTex:SetAlpha(0)
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