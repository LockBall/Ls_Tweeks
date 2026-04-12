local addon_name, addon = ...

-- Create a stylized checkbox with label and callback
function addon.CreateCheckbox(parent, label_text, is_checked, on_click_callback)
    local theme = addon.UI_THEME
    
    -- Container frame (will be sized dynamically)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(24)
    
    -- Checkbox button
    local checkbox = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    checkbox:SetSize(24, 24)
    checkbox:SetPoint("LEFT", container, "LEFT", 0, 0)
    checkbox:SetChecked(is_checked)
    
    -- Label
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
    label:SetText(label_text)
    label:SetTextColor(1, 1, 1, 1)
    
    -- Calculate dynamic width based on label text
    local label_width = label:GetStringWidth()
    local checkbox_width = 24
    local gap = 8
    local padding = 4
    local total_width = checkbox_width + gap + label_width + padding
    container:SetWidth(total_width)
    
    -- Click handler
    checkbox:SetScript("OnClick", function(self)
        if type(on_click_callback) == "function" then
            on_click_callback(self:GetChecked())
        end
    end)
    
    return container, checkbox, label
end
