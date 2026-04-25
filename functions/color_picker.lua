-- Color picker widget that wraps the system ColorPickerFrame with an integrated reset button.
-- addon.CreateColorPicker(parent, db, key, has_alpha, label, defaults, cb) returns a 95×45 container;
-- the reset button restores the default color from the defaults table.
local addon_name, addon = ...

local control_gap = 5

function addon.CreateColorPicker(parent, db_table, db_key, has_alpha, label_text, defaults_table, callback)

    -- Container
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(95, 45) 
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    container:SetBackdropColor(0, 0, 0, 0.3)
    container:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)

    -- Label
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", control_gap, -control_gap)
    label:SetText(label_text)

    -- Color Picker Button
    local button = CreateFrame("Button", nil, container, "BackdropTemplate")
    button:SetSize(18, 18)
    button:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -control_gap)
    button:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameColorSwatch", 
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", 
        edgeSize = 8
    })

    -- Reset Button
    local reset = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    reset:SetSize(45, 16)
    reset:SetText("Reset")
    reset:SetNormalFontObject("GameFontNormalSmall")
    reset:SetPoint("LEFT", button, "RIGHT", control_gap, 0)

    -- Local update helper
    local function apply_and_refresh(r, g, b, a)
        button:SetBackdropColor(r, g, b, a or 1)
        if type(callback) == "function" then callback() end
    end

    -- Setup Initial Color
    local c = db_table[db_key]
    if c then button:SetBackdropColor(c.r, c.g, c.b, c.a or 1) end

    -- Reset Logic with Type Check
    reset:SetScript("OnClick", function()
        -- Defensive check to ensure defaults_table is actually a table
        if type(defaults_table) ~= "table" then 
            print("|cFFFF0000LsTweaks Error:|r Invalid defaults table in ColorPicker.")
            return 
        end

        local dc = defaults_table[db_key]
        if dc then
            db_table[db_key] = has_alpha and {r=dc.r, g=dc.g, b=dc.b, a=dc.a} or {r=dc.r, g=dc.g, b=dc.b}
            apply_and_refresh(dc.r, dc.g, dc.b, dc.a)
        end
    end)

    -- Color Picker Dialog
    button:SetScript("OnClick", function()
        local current = db_table[db_key]
        ColorPickerFrame:SetupColorPickerAndShow({
            r = current.r, g = current.g, b = current.b,
            hasOpacity = has_alpha,
            opacity = current.a or 1,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = has_alpha and ColorPickerFrame:GetColorAlpha() or 1
                db_table[db_key] = has_alpha and {r=r, g=g, b=b, a=a} or {r=r, g=g, b=b}
                apply_and_refresh(r, g, b, a)
            end,
            cancelFunc = function()
                db_table[db_key] = current
                apply_and_refresh(current.r, current.g, current.b, current.a)
            end
        })
    end)

    return container
end