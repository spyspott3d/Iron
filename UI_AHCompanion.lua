-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.UI = IR.UI or {}
local UI = {}
IR.UI.AHCompanion = UI

local FRAME_W = 360
local FRAME_H = 540

local frame, contentArea
local tabButtons, tabContents = {}, {}
local registeredTabs = {}
local tabOrder = {}
local activeTab

local function settingsBuyAI()
    return Iron_DB and Iron_DB.settings and Iron_DB.settings.ironBuy
end

local function closeAuxFrames()
    if IR.UI.AuctionList and IR.UI.AuctionList.Close then
        IR.UI.AuctionList:Close()
    end
    if IR.UI.BuyAuctionList and IR.UI.BuyAuctionList.Close then
        IR.UI.BuyAuctionList:Close()
    end
end

local function showTab(name)
    if activeTab and activeTab ~= name then
        closeAuxFrames()
    end
    activeTab = name
    for n, content in pairs(tabContents) do
        if n == name then content:Show() else content:Hide() end
    end
    for n, btn in pairs(tabButtons) do
        if n == name then
            btn:Disable()
            btn:LockHighlight()
        else
            btn:Enable()
            btn:UnlockHighlight()
        end
    end
    local s = settingsBuyAI()
    if s then s.lastSelectedTab = name end
    local def = registeredTabs[name]
    if def and def.onShow then
        local ok, err = pcall(def.onShow)
        if not ok then IR:Print("|cffff5555ah tab error|r: " .. tostring(err)) end
    end
end

local function rebuildTabs()
    if not contentArea then return end
    for _, btn in pairs(tabButtons) do btn:Hide() end
    for _, c in pairs(tabContents) do c:Hide() end
    tabButtons = {}

    local lastBtn
    for i, name in ipairs(tabOrder) do
        local def = registeredTabs[name]
        local title = def.title or name
        if type(title) == "function" then title = title() end

        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(80, 22)
        btn:SetText(title)
        if i == 1 then
            btn:SetPoint("TOPLEFT", 14, -34)
        else
            btn:SetPoint("LEFT", lastBtn, "RIGHT", 4, 0)
        end
        btn:SetScript("OnClick", function() showTab(name) end)
        if IR.AttachTooltip and def.tooltip then
            IR:AttachTooltip(btn, def.tooltip)
        end
        tabButtons[name] = btn

        if not tabContents[name] then
            local c = CreateFrame("Frame", nil, contentArea)
            c:SetAllPoints(contentArea)
            c:Hide()
            tabContents[name] = c
            if def.build then
                def.build(c)
            end
        end

        lastBtn = btn
    end
end

function UI:RegisterTab(def)
    if not registeredTabs[def.name] then
        table.insert(tabOrder, def.name)
    end
    registeredTabs[def.name] = def
    if frame then rebuildTabs() end
end

function UI:GetContentFrame(name)
    return tabContents[name]
end

function UI:GetMainFrame()
    return frame
end

function UI:RefreshActiveTab()
    if not activeTab then return end
    local def = registeredTabs[activeTab]
    if def and def.onShow then
        local ok, err = pcall(def.onShow)
        if not ok then IR:Print("|cffff5555ah refresh error|r: " .. tostring(err)) end
    end
end

local function findAHAnchor()
    if AuctionFrame and AuctionFrame:IsShown() then
        return AuctionFrame
    end
    return nil
end

local function createFrame()
    if frame then return end

    frame = CreateFrame("Frame", "IronAHFrame", UIParent)
    frame:Hide()
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetScript("OnHide", closeAuxFrames)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.92)

    local drag = CreateFrame("Button", nil, frame)
    drag:SetPoint("TOPLEFT", 8, -8)
    drag:SetPoint("TOPRIGHT", -32, -8)
    drag:SetHeight(20)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Iron - " .. IR.L["Auction House"])

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)

    contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT", 14, -64)
    contentArea:SetPoint("BOTTOMRIGHT", -14, 14)

    rebuildTabs()
end

function UI:Show()
    createFrame()
    local anchor = findAHAnchor()
    frame:ClearAllPoints()
    if anchor then
        frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end

    local s = settingsBuyAI()
    local lastTab = (s and s.lastSelectedTab) or tabOrder[1] or "sell"
    if not registeredTabs[lastTab] then
        lastTab = tabOrder[1]
    end
    if lastTab then showTab(lastTab) end
    frame:Show()
end

function UI:Hide()
    if frame then frame:Hide() end
end

IR:On("AUCTION_HOUSE_SHOW", function() UI:Show() end)
IR:On("AUCTION_HOUSE_CLOSED", function() UI:Hide() end)
