local addon_name, addon = ...

-- Shared slider with paired numeric input and reset button.
function addon.CreateSliderWithBox(name, parent, label_text, min_v, max_v, step, db_table, db_key, defaults_table, callback)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(295, 58)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    container:SetBackdropColor(0, 0, 0, 0.3)
    container:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)

    local slider = CreateFrame("Slider", name, container, "MinimalSliderTemplate")
    slider:SetSize(155, 16)
    slider:SetPoint("TOPLEFT", container, "TOPLEFT", 12, -21)
    slider:SetMinMaxValues(min_v, max_v)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue((db_table and db_table[db_key]) or min_v)

    local title = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("BOTTOM", slider, "TOP", 0, 4)
    title:SetText(label_text)

    local low_lbl = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    low_lbl:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
    low_lbl:SetText(min_v)

    local high_lbl = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    high_lbl:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
    high_lbl:SetText(max_v)

    local eb = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    eb:SetSize(50, 20)
    eb:SetPoint("LEFT", slider, "RIGHT", 18, 1)
    eb:SetAutoFocus(false)
    eb:SetJustifyH("CENTER")
    eb:SetTextInsets(0, 0, 0, 0)
    eb:SetText(format(step < 1 and "%.2f" or "%.1f", (db_table and db_table[db_key]) or min_v))

    local reset = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    reset:SetSize(42, 16)
    reset:SetPoint("LEFT", eb, "RIGHT", 8, 0)
    reset:SetText("Reset")
    reset:SetNormalFontObject("GameFontNormalSmall")

    local function run_callback()
        if type(callback) == "function" then
            callback()
        end
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if db_table then
            db_table[db_key] = value
        end
        eb:SetText(format(step < 1 and "%.2f" or "%.1f", value))
        run_callback()
    end)

    eb:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            val = math.max(min_v, math.min(max_v, val))
            slider:SetValue(val)
        end
        self:ClearFocus()
    end)

    reset:SetScript("OnClick", function()
        local default_value = defaults_table and defaults_table[db_key]
        if default_value == nil then
            default_value = min_v
        end
        slider:SetValue(default_value)
    end)

    return container
end