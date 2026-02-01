local addon_name, addon = ...

---------------------------------------------------------
-- SETTINGS BUILDER REGISTRATION (modules use this)
---------------------------------------------------------
addon.settings_builders = {}

function addon.register_settings_builder(func)
    table.insert(addon.settings_builders, func)
end

---------------------------------------------------------
-- CREATE MAIN FRAME
---------------------------------------------------------
local function create_main_frame()
    if addon.main_frame then
        return addon.main_frame
    end

    ---------------------------------------------------------
    -- MAIN FRAME
    ---------------------------------------------------------
    local frame = CreateFrame("Frame", "Ls_Tweeks_main_frame", UIParent, "BackdropTemplate")
    frame:SetSize(450, 350)
    frame:SetPoint("CENTER")
    frame:Hide()

    -- Movement (must be BEFORE title bar drag scripts)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    -- Main backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    frame:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    ---------------------------------------------------------
    -- TITLE BAR
    ---------------------------------------------------------
    local title_bar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    title_bar:SetHeight(26)
    title_bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    title_bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)

    title_bar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    title_bar:SetBackdropColor(0.12, 0.12, 0.12, 0.95)

    -- Dragging via title bar (ONLY place that handles dragging)
    title_bar:EnableMouse(true)
    title_bar:RegisterForDrag("LeftButton")
    title_bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    title_bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    -- Title text
    local title_text = title_bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title_text:SetPoint("CENTER", title_bar, "CENTER", 0, -1)
    title_text:SetText("L's Tweeks")

    ---------------------------------------------------------
    -- CLOSE BUTTON
    ---------------------------------------------------------
    local close_button = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close_button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    close_button:SetScript("OnClick", function()
        frame:Hide()
    end)

    ---------------------------------------------------------
    -- CONTENT AREA (modules draw inside here)
    ---------------------------------------------------------
    local content = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -28)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)

    content:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    content:SetBackdropColor(0.08, 0.08, 0.08, 0.9)

    frame.content = content

    ---------------------------------------------------------
    -- RESIZE GRIP
    ---------------------------------------------------------
    frame:SetResizable(true)
    frame:SetResizeBounds(350, 250, 900, 700)

    local grip = CreateFrame("Frame", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

    grip.texture = grip:CreateTexture(nil, "OVERLAY")
    grip.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip.texture:SetAllPoints()

    grip:EnableMouse(true)
    grip:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
    end)

    ---------------------------------------------------------
    -- STORE AND RETURN
    ---------------------------------------------------------
    addon.main_frame = frame
    return frame
end

---------------------------------------------------------
-- INITIALIZER (called from init.lua)
---------------------------------------------------------
function addon.init_main_frame()
    local frame = create_main_frame()

    -- Let each module add its own settings UI
    for _, builder in ipairs(addon.settings_builders) do
        builder(frame.content)
    end
end