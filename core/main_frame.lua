local addon_name, addon = ...

-- ============================================================================
-- CATEGORY REGISTRATION (modules use this)
-- ============================================================================
addon.categories = {}

function addon.register_category(name, builder)
    table.insert(addon.categories, { name = name, builder = builder })
end

-- MAIN FRAME UI CREATION
local function create_main_frame()
    if addon.main_frame then return addon.main_frame end

    -- MAIN CONTAINER
    local frame = CreateFrame("Frame", "Ls_Tweeks_main_frame", UIParent, "BackdropTemplate")
    frame:SetSize(900, 740) -- increased size for more controls, rows, and columns
    frame:SetPoint("CENTER")
    frame:Hide()

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    frame:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    -- TITLE BAR
    local title_bar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    title_bar:SetHeight(26)
    title_bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    title_bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    title_bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    title_bar:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
    title_bar:EnableMouse(true)
    title_bar:RegisterForDrag("LeftButton")
    title_bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    title_bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    local title_text = title_bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title_text:SetPoint("CENTER", title_bar, "CENTER", 0, -1)
    title_text:SetText("L's Tweeks")

    -- CLOSE BUTTON
    local close_button = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close_button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    close_button:SetScript("OnClick", function() frame:Hide() end)

    -- SIDEBAR (Left)
    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -28)
    sidebar:SetWidth(140)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    sidebar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    sidebar:SetBackdropColor(0.10, 0.10, 0.10, 0.9)
    frame.sidebar = sidebar

    -- CONTENT AREA (Right)
    local content_area = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    content_area:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 1, 0)
    content_area:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    content_area:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    content_area:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    content_area:SetFrameLevel(frame:GetFrameLevel() + 1)
    frame.content_area = content_area

    addon.main_frame = frame
    return frame
end

-- ABOUT PAGE CONTENT
-- (Moved to modules/about.lua as a self-registering module)

-- INITIALIZER (Dynamic Tab & Sidebar System)
function addon.init_main_frame()
    local frame = create_main_frame()
    local selected_button = nil
    
    frame.tabs = {}     -- Cache for tab frames
    frame.buttons = {}  -- Cache for sidebar buttons

    -- TAB SELECTION LOGIC
    local function select_tab(name, builder, btn)
        if selected_button then selected_button:UnlockHighlight() end
        btn:LockHighlight()
        selected_button = btn
        if Ls_Tweeks_DB then Ls_Tweeks_DB.last_open_module = name end

        -- Hide all current tabs
        for _, tab in pairs(frame.tabs) do
            if tab then tab:Hide() end
        end

        -- Rebuild tab if it doesn't exist (or was cleared by reset)
        if not frame.tabs[name] then
            local new_tab = CreateFrame("Frame", nil, frame.content_area)
            new_tab:SetAllPoints()
            new_tab:SetFrameLevel(frame.content_area:GetFrameLevel() + 2)
            builder(new_tab) 
            frame.tabs[name] = new_tab
        end

        frame.tabs[name]:Show()
    end

    -- SIDEBAR REFRESH LOGIC
    local function RefreshSidebar()
        -- Hide and clear existing category buttons
        for _, btn in ipairs(frame.buttons) do btn:Hide() end
        wipe(frame.buttons)

        local y = -10

        -- Build Category Buttons from registered modules (includes About module)
        for _, cat in ipairs(addon.categories) do
            local btn = CreateFrame("Button", nil, frame.sidebar, "UIPanelButtonTemplate")
            btn:SetSize(120, 22)
            btn:SetPoint("TOPLEFT", frame.sidebar, "TOPLEFT", 10, y)
            btn:SetText(cat.name)
            btn:SetScript("OnClick", function()
                select_tab(cat.name, cat.builder, btn)
            end)
            table.insert(frame.buttons, btn)
            y = y - 26
        end

        -- If nothing is selected, restore last open module or default to first
        if not selected_button and #frame.buttons > 0 then
            local target_idx = 1
            local saved = Ls_Tweeks_DB and Ls_Tweeks_DB.last_open_module
            if saved then
                for i, cat in ipairs(addon.categories) do
                    if cat.name == saved then target_idx = i; break end
                end
            end
            local cat = addon.categories[target_idx]
            select_tab(cat.name, cat.builder, frame.buttons[target_idx])
        end
    end

    -- Every time the main frame is shown, refresh the sidebar and apply saved alpha
    frame:SetScript("OnShow", function()
        RefreshSidebar()
        if addon.apply_interface_alpha then addon.apply_interface_alpha() end
    end)
end