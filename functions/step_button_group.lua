local addon_name, addon = ...

function addon.CreateStepButtonGroup(parent, button_height, on_increment, on_decrement)
    local button_width = 18
    local vertical_gap = 2
    
    local group = CreateFrame("Frame", nil, parent)
    group:SetSize(button_width, (button_height * 2) + vertical_gap)

    local plus = CreateFrame("Button", nil, group, "UIPanelButtonTemplate")
    plus:SetSize(button_width, button_height)
    plus:SetPoint("TOPLEFT", group, "TOPLEFT", 0, 0)
    plus:SetText("+")
    plus:SetNormalFontObject("GameFontNormalSmall")
    plus:SetScript("OnClick", function()
        if type(on_increment) == "function" then
            on_increment()
        end
    end)

    local minus = CreateFrame("Button", nil, group, "UIPanelButtonTemplate")
    minus:SetSize(button_width, button_height)
    minus:SetPoint("TOPLEFT", plus, "BOTTOMLEFT", 0, -vertical_gap)
    minus:SetText("-")
    minus:SetNormalFontObject("GameFontNormalSmall")
    minus:SetScript("OnClick", function()
        if type(on_decrement) == "function" then
            on_decrement()
        end
    end)

    group.plus = plus
    group.minus = minus

    return group
end

addon.CreateStepButtonStack = addon.CreateStepButtonGroup