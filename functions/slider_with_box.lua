local addon_name, addon = ...

-- Shared slider with paired numeric input and reset button.
function addon.CreateSliderWithBox(name, parent, label_text, min_v, max_v, step, db_table, db_key, defaults_table, callback)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(160, 85)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    container:SetBackdropColor(0, 0, 0, 0.3)
    container:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)

    local control_gap = 6
    local eb_width = 42
    local reset_width = 42
    local slider_width = 100

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", container, "TOP", 0, -4)
    title:SetText(label_text)

    local step_buttons = addon.CreateStepButtonGroup(container, 16,
        function()
            slider:SetValue(slider:GetValue() + step)
        end,
        function()
            slider:SetValue(slider:GetValue() - step)
        end
    )
    step_buttons:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -control_gap)

    local eb = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    eb:SetSize(eb_width, 20)
    eb:SetPoint("TOPLEFT", step_buttons, "TOPRIGHT", 2*control_gap, 0)
    eb:SetAutoFocus(false)
    eb:SetJustifyH("CENTER")
    eb:SetTextInsets(-4, 0, 0, 0) 

    local reset = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    reset:SetSize(reset_width, 16)
    reset:SetPoint("LEFT", eb, "RIGHT", control_gap, 0)
    reset:SetText("Reset")
    reset:SetNormalFontObject("GameFontNormalSmall")   

    local slider = CreateFrame("Slider", name, container, "MinimalSliderTemplate")
    slider:SetSize(slider_width, 16)
    slider:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", -control_gap, -control_gap)
    slider:SetMinMaxValues(min_v, max_v)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue((db_table and db_table[db_key]) or min_v)

    local function format_display_value(v)
        if step >= 1 then
            return tostring(math.floor(v + 0.5))
        end
        return format("%.2f", v)
    end

    eb:SetText(format_display_value((db_table and db_table[db_key]) or min_v))

    local low_lbl = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    low_lbl:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
    low_lbl:SetText(min_v)

    local high_lbl = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    high_lbl:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
    high_lbl:SetText(max_v)





    local function run_callback()
        if type(callback) == "function" then
            callback()
        end
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if db_table then
            db_table[db_key] = value
        end
        eb:SetText(format_display_value(value))
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

    -- Expose inner slider so callers can call SetValue to update the display.
    container.slider = slider

    return container
end