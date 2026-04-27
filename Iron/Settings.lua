-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.Settings = {}
local Settings = IR.Settings

Settings.tabs = {}
Settings.tabOrder = {}
Settings.refreshHandlers = {}

function Settings.Refresh()
    for i = 1, #Settings.refreshHandlers do
        local ok, err = pcall(Settings.refreshHandlers[i])
        if not ok then
            IR:Print("|cffff5555settings refresh error|r: " .. tostring(err))
        end
    end
end

function IR:RegisterSettingsTab(def)
    if not Settings.tabs[def.name] then
        table.insert(Settings.tabOrder, def.name)
    end
    Settings.tabs[def.name] = def
    if Settings.frame then
        Settings.rebuild()
    end
end

local function buildGeneralTab(parent)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 8, -8)
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(IR.L["Enable debug messages"])

    local function refresh()
        local on = Iron_DB and Iron_DB.settings and Iron_DB.settings.debug
        cb:SetChecked(on and true or false)
    end
    cb:SetScript("OnShow", refresh)
    cb:SetScript("OnClick", function(self)
        if not (Iron_DB and Iron_DB.settings) then return end
        Iron_DB.settings.debug = self:GetChecked() and true or false
        IR:Print(Iron_DB.settings.debug and IR.L["Debug ON"] or IR.L["Debug OFF"])
    end)
    table.insert(Settings.refreshHandlers, refresh)

    local v = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    v:SetPoint("BOTTOMRIGHT", -4, 4)
    v:SetText("v" .. (IR.version or "?"))
end

local function placeholderBuilder(text)
    return function(parent)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER")
        fs:SetText(text)
    end
end

local function showTab(f, name)
    for n, frame in pairs(f.tabFrames) do
        frame:Hide()
    end
    if f.tabFrames[name] then
        f.tabFrames[name]:Show()
    end
    for n, btn in pairs(f.tabButtons) do
        if n == name then
            btn:LockHighlight()
            btn:Disable()
        else
            btn:UnlockHighlight()
            btn:Enable()
        end
    end
    f.activeTab = name
end

local TAB_HEIGHT = 22
local TAB_PADDING = 24
local TAB_MIN_WIDTH = 60
local TAB_GAP = 4
local FRAME_SIDE_MARGIN = 12
local FRAME_MIN_WIDTH = 360

local function buildTabs(f)
    if f.tabButtons then
        for _, btn in pairs(f.tabButtons) do btn:Hide() end
    end
    if f.tabFrames then
        for _, frame in pairs(f.tabFrames) do frame:Hide() end
    end
    f.tabButtons = {}
    f.tabFrames = {}

    local lastBtn
    local rowWidth = FRAME_SIDE_MARGIN
    for i, name in ipairs(Settings.tabOrder) do
        local def = Settings.tabs[name]
        local title = def.title or name
        if type(title) == "function" then title = title() end

        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetText(title)
        local fs = btn:GetFontString()
        local textW = (fs and fs:GetStringWidth()) or TAB_MIN_WIDTH
        local btnW = math.max(TAB_MIN_WIDTH, math.ceil(textW) + TAB_PADDING)
        btn:SetSize(btnW, TAB_HEIGHT)
        if i == 1 then
            btn:SetPoint("TOPLEFT", FRAME_SIDE_MARGIN, -32)
        else
            btn:SetPoint("LEFT", lastBtn, "RIGHT", TAB_GAP, 0)
            rowWidth = rowWidth + TAB_GAP
        end
        rowWidth = rowWidth + btnW
        btn:SetScript("OnClick", function() showTab(f, name) end)
        f.tabButtons[name] = btn

        local tabFrame = CreateFrame("Frame", nil, f.content)
        tabFrame:SetAllPoints(f.content)
        tabFrame:Hide()
        f.tabFrames[name] = tabFrame
        if def.build then
            def.build(tabFrame)
        end

        lastBtn = btn
    end
    rowWidth = rowWidth + FRAME_SIDE_MARGIN

    local needed = math.max(FRAME_MIN_WIDTH, rowWidth)
    if needed > f:GetWidth() then
        f:SetWidth(needed)
    end

    if Settings.tabOrder[1] then
        showTab(f, f.activeTab and f.tabFrames[f.activeTab] and f.activeTab or Settings.tabOrder[1])
    end
end

local function createFrame()
    if Settings.frame then return Settings.frame end

    local f = CreateFrame("Frame", "IronSettingsFrame", UIParent)
    f:SetSize(540, 420)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetBackdropColor(0, 0, 0, 0.9)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Iron - " .. IR.L["Settings"])

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 14, -68)
    content:SetPoint("BOTTOMRIGHT", -14, 14)
    f.content = content

    f:SetScript("OnShow", function() Settings.Refresh() end)

    Settings.frame = f
    Settings.rebuild = function() buildTabs(f) end
    buildTabs(f)

    tinsert(UISpecialFrames, "IronSettingsFrame")

    f:Hide()
    return f
end

function IR:OpenSettings(tabName)
    local f = createFrame()
    if tabName and Settings.tabs[tabName] and showTab then
        showTab(f, tabName)
        f:Show()
        return
    end
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end

IR:RegisterSettingsTab({
    name = "general",
    title = function() return IR.L["General"] end,
    build = buildGeneralTab,
})
IR:RegisterSettingsTab({
    name = "ironmail",
    title = "IronMail",
    build = placeholderBuilder(IR.L["IronMail settings will appear here."]),
})
IR:RegisterSettingsTab({
    name = "ironvault",
    title = "IronVault",
    build = placeholderBuilder(IR.L["IronVault settings will appear here."]),
})
IR:RegisterSettingsTab({
    name = "ironsell",
    title = "IronSell",
    build = placeholderBuilder(IR.L["IronSell settings will appear here."]),
})
IR:RegisterSettingsTab({
    name = "ironbuy",
    title = "IronBuy",
    build = placeholderBuilder(IR.L["IronBuy settings will appear here."]),
})

IR:RegisterSlashCommand("settings", function() IR:OpenSettings() end, "open settings panel")
IR:RegisterSlashCommand("config", function() IR:OpenSettings() end, "open settings panel")
