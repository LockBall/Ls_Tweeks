local addon_name, addon = ...

-- Shared click-blocker: sits behind all dropdown popups and dismisses the open one
-- when the user clicks anywhere outside it. One instance, reused by all dropdowns.
local _dropdown_blocker = CreateFrame("Frame", "LsTweeksDropdownBlocker", UIParent)
_dropdown_blocker:SetAllPoints(UIParent)
_dropdown_blocker:SetFrameStrata("FULLSCREEN")
_dropdown_blocker:SetFrameLevel(98)
_dropdown_blocker:EnableMouse(true)
_dropdown_blocker:Hide()
_dropdown_blocker._active = nil
_dropdown_blocker:SetScript("OnMouseDown", function(self)
    if self._active then self._active:Hide() end
    self._active = nil
    self:Hide()
end)

local function _show_dropdown(popup, btn)
    if _dropdown_blocker._active and _dropdown_blocker._active ~= popup then
        _dropdown_blocker._active:Hide()
    end
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    popup:Show()
    _dropdown_blocker._active = popup
    _dropdown_blocker:Show()
end

local function _hide_dropdown(popup)
    popup:Hide()
    if _dropdown_blocker._active == popup then
        _dropdown_blocker._active = nil
        _dropdown_blocker:Hide()
    end
end

-- Shared dropdown constructor used by module UIs.
function addon.CreateDropdown(name, parent, label_text, options, cfg)
    cfg = cfg or {}
    options = options or {}

    local width = cfg.width or 180
    local row_h = cfg.row_height or 22
    local selected = (cfg.get_value and cfg.get_value()) or (options[1] and options[1].value)

    local container = CreateFrame("Frame", name, parent)
    container:SetSize(width, 22)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", container, "TOP", 0, 2)
    label:SetText(label_text)

    local btn = CreateFrame("Button", name.."Btn", container, "UIPanelButtonTemplate")
    btn:SetAllPoints(container)
    local btn_text = btn:GetFontString()

    local popup = CreateFrame("Frame", name.."Popup", UIParent, "BackdropTemplate")
    popup:SetSize(width, #options * row_h + 4)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(100)
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.08, 0.96)
    popup:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    popup:Hide()

    local function get_option_text(option)
        if cfg.get_option_text then
            return cfg.get_option_text(option)
        end
        return option.text or tostring(option.value or "")
    end

    local function apply_button_style(option)
        if cfg.apply_button_style then
            cfg.apply_button_style(btn_text, option)
            return
        end
        if btn_text then
            btn_text:SetFontObject(GameFontHighlightSmall)
        end
    end

    local function set_button_text(value)
        for _, option in ipairs(options) do
            if option.value == value then
                btn:SetText(get_option_text(option))
                apply_button_style(option)
                return
            end
        end

        local fallback = options[1]
        btn:SetText(fallback and get_option_text(fallback) or "")
        if fallback then
            apply_button_style(fallback)
        elseif btn_text then
            btn_text:SetFontObject(GameFontHighlightSmall)
        end
    end

    for i, option in ipairs(options) do
        local row = CreateFrame("Button", nil, popup)
        row:SetSize(width - 4, row_h)
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", 2, -(2 + (i - 1) * row_h))

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.12)

        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", row, "LEFT", 8, 0)
        txt:SetText(get_option_text(option))
        if cfg.apply_row_style then
            cfg.apply_row_style(txt, option)
        end

        row:SetScript("OnClick", function()
            selected = option.value
            set_button_text(selected)
            _hide_dropdown(popup)
            if cfg.on_select then
                cfg.on_select(selected, option)
            end
        end)
    end

    btn:SetScript("OnClick", function()
        if popup:IsShown() then
            _hide_dropdown(popup)
        else
            _show_dropdown(popup, btn)
        end
    end)

    container.SetValue = function(_, value)
        selected = value
        set_button_text(selected)
    end

    container.GetValue = function()
        return selected
    end

    set_button_text(selected)
    return container
end
