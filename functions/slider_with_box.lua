local addon_name, addon = ...

-- Shared slider with paired numeric input and reset button.
function addon.CreateSliderWithBox(name, parent, label_text, min_v, max_v, step, db_table, db_key, defaults_table, callback)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(130, 95)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    container:SetBackdropColor(0, 0, 0, 0.3)
    container:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)

    local control_gap = 5

    local eb_font_size = 12
    local eb_width = 35
    local eb_height = 12
    
    local reset_width = 42
    local reset_height = 20

    local slider_width = 120
    local button_size = 24
    local slider_inset = 3

    local slider = CreateFrame("Slider", name, container, "MinimalSliderTemplate")
    slider:SetSize(slider_width, 16)
    slider:SetPoint("CENTER", container, "CENTER", 0, -control_gap/2)
    slider:SetMinMaxValues(min_v, max_v)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue((db_table and db_table[db_key]) or min_v)

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", container, "TOP", 0, -control_gap)
    title:SetText(label_text)

    -- Min/Max labels above the slider
    local min_lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    min_lbl:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", slider_inset, control_gap)
    min_lbl:SetText(min_v)

    local max_lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    max_lbl:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", -slider_inset, control_gap)
    max_lbl:SetText(max_v)

    -- Edit box centered below the slider
    local eb = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    eb:SetSize(eb_width, eb_height)
    eb:SetPoint("BOTTOM", slider, "TOP", 2, control_gap)
    eb:SetAutoFocus(false)
    eb:SetJustifyH("CENTER")
    eb:SetTextInsets(-4, 0, 0, 0)
    local font, _, flags = eb:GetFont()
    eb:SetFont(font, eb_font_size, flags)

    -- Minus and plus buttons under the slider, left and right
    local minus_btn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    minus_btn:SetSize(button_size, button_size)
    minus_btn:SetText("-")
    minus_btn:SetNormalFontObject("GameFontNormalLarge")
    minus_btn:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", slider_inset, -control_gap)

    local plus_btn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    plus_btn:SetSize(button_size, button_size)
    plus_btn:SetText("+")
    plus_btn:SetNormalFontObject("GameFontNormalLarge")
    plus_btn:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -slider_inset, -control_gap)

    local reset = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    reset:SetSize(reset_width, reset_height)
    reset:SetPoint("TOP", slider, "BOTTOM", 0, -control_gap)
    reset:SetText("Reset")
    reset:SetNormalFontObject("GameFontNormalSmall")


    local function format_display_value(v)
        if step >= 1 then
            return tostring(math.floor(v + 0.5))
        end
        return format("%.2f", v)
    end

    eb:SetText(format_display_value((db_table and db_table[db_key]) or min_v))


    local function run_callback()
        if type(callback) == "function" then
            callback()
        end
    end

    local debounce_timer = nil
    local function debounced_callback()
        if debounce_timer then debounce_timer:Cancel() end
        debounce_timer = C_Timer.NewTimer(0.1, function()
            debounce_timer = nil
            run_callback()
        end)
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if db_table then
            db_table[db_key] = value
        end
        eb:SetText(format_display_value(value))
        debounced_callback()
    end)

    eb:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            val = math.max(min_v, math.min(max_v, val))
            slider:SetValue(val)
        end
        self:ClearFocus()
    end)

    minus_btn:SetScript("OnClick", function()
        local v = slider:GetValue() - step
        slider:SetValue(math.max(min_v, v))
    end)

    plus_btn:SetScript("OnClick", function()
        local v = slider:GetValue() + step
        slider:SetValue(math.min(max_v, v))
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