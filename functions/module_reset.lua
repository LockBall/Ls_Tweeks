local addon_name, addon = ...

function addon.CreateGlobalReset(parent, db, defaults)

    -------- CONFIGURATION VARIABLES --------
    local DIM_ALPHA     = 0.5   -- Faded transparency when the button is locked
    local READY_ALPHA   = 0.6   -- Full transparency when 'arm' is typed

    -- PULSE Params
    local PULSE_MIN     = 0.0   -- Minimum brightness during the pulse cycle
    local PULSE_MAX     = 1.1   -- Maximum brightness during the pulse cycle
    local PULSE_SPEED   = 0.75  -- Duration in seconds for one pulse cycle

    -- MASK SETTINGS
    local MASK_INSET    = 13    -- Circular window size adjustment

    -- GLOW SIZE PARAMETERS
    local GLOW_SIZE     = 60
    local BEZEL_SPILL   = 7

    -- LAYOUT: Panel
    local PANEL_MIN_WIDTH   = 300   -- Minimum panel width (px)
    local PANEL_HEIGHT      = 150   -- Panel height (px)
    local PANEL_H_PADDING   = 100   -- Left+right padding around the control group
    local TITLE_Y           = -20   -- Title offset from panel top

    -- LAYOUT: Group
    local GROUP_X           = 0     -- Horizontal offset of the control group from panel center
    local GROUP_Y           = -45   -- Vertical offset of the control group from panel top
    local GROUP_PAD_X       = 6     -- Horizontal inner padding inside the control group
    local GROUP_PAD_TOP     = 4     -- Top inner padding inside the control group
    local GROUP_PAD_BOTTOM  = 4     -- Bottom inner padding inside the control group

    -- LAYOUT: Group Elements
    local INPUT_W           = 75    -- Width of the ARM code input box
    local INPUT_H           = 20    -- Height of the ARM code input box
    local LABEL_GAP         = 10    -- Gap between input top and label bottom
    local BTN_GAP           = 44    -- Gap between input right edge and button left edge
    local BTN_SIZE          = 64    -- Width and height of the icon button
    local RIVET_INSET       = 14    -- Distance of each rivet from panel corners
    local RIVET_OFFSET_X    = 0     -- Horizontal shift for all rivets (px)
    local RIVET_OFFSET_Y    = 0     -- Vertical shift for all rivets (px)
    -----------------------------------------

    -- CONTAINER
    -- No default positioning — caller is responsible for SetPoint after creation.
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(PANEL_MIN_WIDTH, PANEL_HEIGHT)
    container:SetFrameLevel(parent:GetFrameLevel() + 10)

    addon.ApplyRivetedPanelStyle(container, {
        bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
        edgeSize = 30,
        rivetInset = RIVET_INSET,
        rivetOffsetX = RIVET_OFFSET_X,
        rivetOffsetY = RIVET_OFFSET_Y,
    })

    -- TITLE
    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", container, "TOP", 0, TITLE_Y)
    title:SetText("Hal's Module Reset")
    title:SetTextColor(1, 0.82, 0)

    local control_row_width = INPUT_W + BTN_GAP + BTN_SIZE
    local control_row_height = math.max(INPUT_H, BTN_SIZE)

    -- Control group: keeps input, label, and button aligned as one movable unit.
    local controlGroup = CreateFrame("Frame", nil, container)
    controlGroup:SetSize(1, 1)
    controlGroup:SetPoint("TOP", container, "TOP", GROUP_X, GROUP_Y)

    -- INPUT BOX
    local eb = CreateFrame("EditBox", nil, controlGroup, "InputBoxTemplate")
    eb:SetSize(INPUT_W, INPUT_H)
    eb:SetAutoFocus(false)
    eb:SetTextInsets(0, 7, 0, 0)
    eb:SetJustifyH("CENTER")
    eb:SetFontObject("NumberFontNormal")
    eb:SetTextColor(1, 1, 1)

    -- INSTRUCTION LABEL
    local label = controlGroup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetText(" Input 'arm' code !?")

    local label_w = math.ceil(label:GetStringWidth() or 0)
    local label_h = math.ceil(label:GetStringHeight() or 0)
    local content_w = math.max(control_row_width, label_w)
    local top_extent = math.max(BTN_SIZE / 2, INPUT_H / 2 + LABEL_GAP + label_h)
    local bottom_extent = math.max(BTN_SIZE / 2, INPUT_H / 2)
    local content_h = top_extent + bottom_extent
    local group_w = content_w + GROUP_PAD_X * 2
    local group_h = content_h + GROUP_PAD_TOP + GROUP_PAD_BOTTOM

    controlGroup:SetSize(group_w, group_h)

    -- BIG RED BUTTON ICON
    local btn = CreateFrame("Button", nil, controlGroup)
    btn:SetSize(BTN_SIZE, BTN_SIZE)
    btn:SetPoint("CENTER", controlGroup, "CENTER", GROUP_PAD_X + content_w / 2 - BTN_SIZE / 2, 0)
    btn:Disable()

    eb:SetPoint("RIGHT", btn, "LEFT", -BTN_GAP, 0)
    label:SetPoint("BOTTOM", eb, "TOP", 0, LABEL_GAP)

    -- STATIC BUTTON TEXTURE
    local bgTex = btn:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetTexture("Interface\\Icons\\inv_misc_enggizmos_27")
    bgTex:SetAlpha(DIM_ALPHA)

    -- PULSING OVERLAY
    local pulseTex = btn:CreateTexture(nil, "ARTWORK")
    pulseTex:SetSize(GLOW_SIZE + BEZEL_SPILL, GLOW_SIZE + BEZEL_SPILL)
    pulseTex:SetPoint("CENTER")
    pulseTex:SetTexture("Interface\\Icons\\inv_misc_enggizmos_27")
    pulseTex:SetBlendMode("ADD")
    pulseTex:SetAlpha(0)

    -- CIRCULAR MASK
    local mask = btn:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT",     pulseTex, "TOPLEFT",     MASK_INSET, -MASK_INSET)
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
    btn:GetPushedTexture():SetBlendMode("MOD")

    -- Size the panel to its content instead of stretching to the tab width.
    local panel_width = math.max(
        PANEL_MIN_WIDTH,
        math.ceil((title:GetStringWidth() or 0) + 56),
        math.ceil((label:GetStringWidth() or 0) + 56),
        math.ceil(controlGroup:GetWidth() + PANEL_H_PADDING)
    )
    container:SetWidth(panel_width)

    -- PULSE ANIMATION
    local ag = pulseTex:CreateAnimationGroup()
    local animAlpha = ag:CreateAnimation("Alpha")
    animAlpha:SetFromAlpha(PULSE_MIN)
    animAlpha:SetToAlpha(PULSE_MAX)
    animAlpha:SetDuration(PULSE_SPEED)
    animAlpha:SetSmoothing("IN_OUT")
    ag:SetLooping("BOUNCE")

    -- SECURITY LOGIC: AUTO-CLEAR
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
        pulseTex:SetAlpha(self:IsEnabled() and READY_ALPHA or 0)
    end)

    -- TERMINAL INPUT LOGIC
    eb:SetScript("OnTextChanged", function(self)
        local raw = self:GetText()
        local upper = raw:upper()
        if raw ~= upper then self:SetText(upper) end

        if upper == "ARM" then
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

        -- Wipe and restore database from defaults
        table.wipe(db)
        for k, v in pairs(defaults) do
            if type(v) == "table" then
                db[k] = {}
                for subK, subV in pairs(v) do
                    if type(subV) == "table" then
                        db[k][subK] = {}
                        for innerK, innerV in pairs(subV) do
                            db[k][subK][innerK] = innerV
                        end
                    else
                        db[k][subK] = subV
                    end
                end
            else
                db[k] = v
            end
        end

        -- Universal Frame & UI Sync
        for moduleName, module in pairs(addon) do
            if type(module) == "table" and module.frames then
                
                -- Sync UI Controls (Checkboxes and Sliders)
                if module.controls then
                    for key, control in pairs(module.controls) do
                        if control.SetChecked then
                            if db[key] ~= nil then control:SetChecked(db[key]) end
                        elseif control.SetValue then
                            if db[key] ~= nil then control:SetValue(db[key]) end
                        end
                    end
                end
                
                -- Update Physical Frames
                for show_key, frame in pairs(module.frames) do
                    local suffix = show_key:gsub("show_", "")
                    local move_key = "move_" .. suffix
                    
                    if frame then
                        local dPos = db.positions and db.positions[suffix]
                        if dPos then
                            frame:ClearAllPoints()
                            frame:SetPoint(dPos.point, UIParent, dPos.point, dPos.x, dPos.y)
                        end

                        if module.update_auras then
                            module.update_auras(
                                frame, 
                                show_key, 
                                move_key, 
                                "timer_" .. suffix, 
                                "bg_" .. suffix, 
                                "scale_" .. suffix, 
                                "spacing_" .. suffix, 
                                suffix == "debuff" and "HARMFUL" or "HELPFUL"
                            )
                        end
                    end
                end
                
                -- Invalidate cached UI tabs for rebuild
                if (addon.af_gui and addon.af_gui.BuildSettings) or module.build_settings then
                    if addon.main_frame and addon.main_frame.tabs then
                        for tabName, tabFrame in pairs(addon.main_frame.tabs) do
                            if tabName ~= "About" then
                                addon.main_frame.tabs[tabName] = nil
                            end
                        end
                    end
                end
                
                if module.on_reset_complete then
                    module.on_reset_complete()
                end
            end
        end

        print("|cff00ff00LsTweaks:|r Global reset complete and synchronized.")
    end)

    return container
end