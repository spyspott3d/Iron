-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.UI = IR.UI or {}
local UI = {}
IR.UI.IronMail = UI

local IronMail = IR.IronMail

local ATTACH_MAX = ATTACHMENTS_MAX_RECEIVE or 16

local FRAME_W = 600
local FRAME_H = 480
local ROW_H = 28
local INBOX_CONTENT_W = FRAME_W - 56

local frame
local inboxScroll, inboxContent
local rows = {}
local headerText
local openAllBtn
local takeBtn, deleteBtn, returnBtn
local tabInbox, tabSend
local sendTab, sendRecipientEdit, sendSubjectEdit, sendBodyEdit, sendBodyScroll
local sendAttachSlots = {}
local sendMoneyFrame, sendCODCheck, sendBtn, sendClearBtn
local activeTab = "inbox"
local selectedIndex
local allowMailFrame = false
local internalMailVisible = false
local refreshList
local refreshSend
local ATTACH_MAX_SEND = ATTACHMENTS_MAX_SEND or 12

-- Make MailFrame invisible but logically Show()-n so its widgets (send slots,
-- send button, etc.) are usable. We never call MailFrame:Hide() while we still
-- need it because that triggers Blizzard's MailFrame_OnHide → CloseMail() →
-- MAIL_CLOSED, which would close the entire mailbox session.
local function internalShowMailFrame()
    if not MailFrame then return end
    internalMailVisible = true
    MailFrame:SetAlpha(0)
    MailFrame:EnableMouse(false)
    for i = 1, 4 do
        local tab = _G["MailFrameTab" .. i]
        if tab then tab:EnableMouse(false) end
    end
    MailFrame:Show()
    if MailFrameTab2 and MailFrameTab_OnClick then
        MailFrameTab_OnClick(MailFrameTab2)
    end
end

-- Restore MailFrame to fully visible (alpha=1, mouse enabled). Does NOT call
-- Hide() — that would close the mailbox session.
local function internalHideMailFrame()
    if not MailFrame then return end
    internalMailVisible = false
    MailFrame:SetAlpha(1)
    MailFrame:EnableMouse(true)
    for i = 1, 4 do
        local tab = _G["MailFrameTab" .. i]
        if tab then tab:EnableMouse(true) end
    end
end


local function settingsPostAI()
    return Iron_DB and Iron_DB.settings and Iron_DB.settings.ironMail
end

local function savePos()
    if not frame then return end
    local s = settingsPostAI()
    if not s then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    s.framePos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function loadPos()
    if not frame then return end
    local s = settingsPostAI()
    frame:ClearAllPoints()
    if s and s.framePos then
        frame:SetPoint(s.framePos.point, UIParent, s.framePos.relPoint, s.framePos.x, s.framePos.y)
    else
        frame:SetPoint("CENTER")
    end
end

local function showTab(name)
    activeTab = name
    if name == "inbox" then
        inboxScroll:Show()
        if sendTab then sendTab:Hide() end
        tabInbox:Disable()
        tabSend:Enable()
        -- MailFrame stays in whatever state it was (alpha=0 if Send was opened,
        -- hidden if never opened). Don't toggle it — MailFrame:Hide() would
        -- trigger Blizzard's CloseMail() which closes the whole mailbox session.
    else
        inboxScroll:Hide()
        if sendTab then sendTab:Show() end
        tabSend:Disable()
        tabInbox:Enable()
        internalShowMailFrame()
        if refreshSend then refreshSend() end
    end
end

local function getRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, inboxContent)
    r:SetSize(INBOX_CONTENT_W - 4, ROW_H)
    r:SetPoint("TOPLEFT", inboxContent, "TOPLEFT", 0, -((i - 1) * ROW_H))
    r:RegisterForClicks("LeftButtonUp")

    local hl = r:CreateTexture(nil, "BACKGROUND")
    hl:SetTexture(0.3, 0.5, 0.9)
    hl:SetAlpha(0.3)
    hl:SetAllPoints()
    hl:Hide()
    r.highlight = hl

    local hover = r:CreateTexture(nil, "BACKGROUND")
    hover:SetTexture(1, 1, 1)
    hover:SetAlpha(0.08)
    hover:SetAllPoints()
    hover:Hide()
    r.hover = hover

    local ic = r:CreateTexture(nil, "ARTWORK")
    ic:SetSize(20, 20)
    ic:SetPoint("LEFT", 4, 0)
    r.icon = ic

    local sender = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sender:SetPoint("LEFT", ic, "RIGHT", 6, 0)
    sender:SetWidth(110)
    sender:SetHeight(ROW_H)
    sender:SetJustifyH("LEFT")
    r.sender = sender

    local subject = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subject:SetPoint("LEFT", sender, "RIGHT", 4, 0)
    subject:SetWidth(180)
    subject:SetHeight(ROW_H)
    subject:SetJustifyH("LEFT")
    r.subject = subject

    local money = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    money:SetPoint("LEFT", subject, "RIGHT", 4, 0)
    money:SetWidth(110)
    money:SetHeight(ROW_H)
    money:SetJustifyH("LEFT")
    r.money = money

    local items = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    items:SetPoint("LEFT", money, "RIGHT", 4, 0)
    items:SetWidth(70)
    items:SetHeight(ROW_H)
    items:SetJustifyH("LEFT")
    r.items = items

    local exp = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    exp:SetPoint("RIGHT", -8, 0)
    exp:SetWidth(40)
    exp:SetJustifyH("RIGHT")
    r.exp = exp

    r:SetScript("OnEnter", function(self) self.hover:Show() end)
    r:SetScript("OnLeave", function(self) self.hover:Hide() end)
    r:SetScript("OnClick", function(self)
        selectedIndex = self.mailIndex
        refreshList()
    end)

    rows[i] = r
    return r
end

local lastLoggedN = -1

refreshList = function()
    if not frame or not frame:IsShown() then return end
    if not headerText or not inboxContent then return end
    local n = GetInboxNumItems and GetInboxNumItems() or 0
    if n ~= lastLoggedN then
        IR:Debug("refreshList n=" .. tostring(n))
        lastLoggedN = n
    end

    local totalMoney = 0
    for i = 1, n do
        local _, _, _, _, money = GetInboxHeaderInfo(i)
        if money then totalMoney = totalMoney + money end
    end
    headerText:SetText(string.format(IR.L["%d mails, %s attached"], n, IR:CopperToString(totalMoney)))

    inboxContent:SetHeight(math.max(n * ROW_H, 1))

    for _, r in pairs(rows) do r:Hide() end
    for i = 1, n do
        local r = getRow(i)
        local _, _, sender, subject, money, COD, daysLeft, hasItem = GetInboxHeaderInfo(i)
        r.mailIndex = i
        r.sender:SetText(sender or "?")
        r.subject:SetText(subject or "")
        if COD and COD > 0 then
            r.money:SetText("|cffff7777" .. string.format(IR.L["COD: %s"], IR:CopperToString(COD)) .. "|r")
        elseif money and money > 0 then
            r.money:SetText("|cffffd700" .. IR:CopperToString(money) .. "|r")
        else
            r.money:SetText("")
        end
        local count = 0
        local firstTex
        if hasItem then
            for a = 1, ATTACH_MAX do
                local name, tex = GetInboxItem(i, a)
                if name then
                    count = count + 1
                    if not firstTex then firstTex = tex end
                end
            end
        end
        if count > 0 then
            r.items:SetText(string.format(IR.L["%d items"], count))
            r.icon:SetTexture(firstTex or "Interface\\Icons\\INV_Letter_15")
        else
            r.items:SetText("")
            r.icon:SetTexture("Interface\\Icons\\INV_Letter_15")
        end
        if daysLeft and daysLeft > 0 then
            r.exp:SetText(string.format("%.0fd", daysLeft))
        else
            r.exp:SetText("")
        end
        if selectedIndex == i then r.highlight:Show() else r.highlight:Hide() end
        r:Show()
    end

    if selectedIndex and (selectedIndex < 1 or selectedIndex > n) then
        selectedIndex = nil
    end

    local hasSel = selectedIndex ~= nil
    if takeBtn then if hasSel then takeBtn:Enable() else takeBtn:Disable() end end
    if deleteBtn then if hasSel then deleteBtn:Enable() else deleteBtn:Disable() end end
    if returnBtn then if hasSel then returnBtn:Enable() else returnBtn:Disable() end end

    if openAllBtn then
        local running, current, total = IronMail:GetProgress()
        if running then
            openAllBtn:SetText(string.format(IR.L["Opening %d/%d..."], current, total))
            openAllBtn:Disable()
        elseif n > 0 then
            openAllBtn:SetText(IR.L["Open All"])
            openAllBtn:Enable()
        else
            openAllBtn:SetText(IR.L["Open All"])
            openAllBtn:Disable()
        end
    end
end

local function createFrame()
    if frame then return end

    frame = CreateFrame("Frame", "IronPostFrame", UIParent)
    frame:Hide()
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.92)

    local drag = CreateFrame("Button", nil, frame)
    drag:SetPoint("TOPLEFT", 8, -8)
    drag:SetPoint("TOPRIGHT", -130, -8)
    drag:SetHeight(20)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePos()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Iron - " .. IR.L["Mail"])

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        frame:Hide()
        if IronMail.mailboxOpen then CloseMail() end
    end)

    local classicBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    classicBtn:SetSize(80, 22)
    classicBtn:SetPoint("TOPRIGHT", -36, -10)
    classicBtn:SetText(IR.L["Classic"])
    classicBtn:SetScript("OnClick", function() UI:OpenClassicUI(activeTab) end)
    IR:AttachTooltip(classicBtn, IR.L["Switch to the standard WoW mail window"])

    headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerText:SetPoint("TOPLEFT", 16, -42)
    headerText:SetText("")

    openAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    openAllBtn:SetSize(140, 22)
    openAllBtn:SetPoint("TOPRIGHT", -16, -38)
    openAllBtn:SetText(IR.L["Open All"])
    openAllBtn:SetScript("OnClick", function() IronMail:Start() end)

    tabInbox = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    tabInbox:SetSize(90, 22)
    tabInbox:SetPoint("TOPLEFT", 16, -68)
    tabInbox:SetText(IR.L["Inbox"])
    tabInbox:SetScript("OnClick", function() showTab("inbox") end)

    tabSend = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    tabSend:SetSize(90, 22)
    tabSend:SetPoint("LEFT", tabInbox, "RIGHT", 4, 0)
    tabSend:SetText(IR.L["Send"])
    tabSend:SetScript("OnClick", function() showTab("send") end)

    inboxScroll = CreateFrame("ScrollFrame", "IronPostInboxScroll", frame, "UIPanelScrollFrameTemplate")
    inboxScroll:SetPoint("TOPLEFT", 16, -98)
    inboxScroll:SetPoint("BOTTOMRIGHT", -36, 56)
    inboxContent = CreateFrame("Frame", nil, inboxScroll)
    inboxContent:SetSize(INBOX_CONTENT_W, 1)
    inboxScroll:SetScrollChild(inboxContent)

    sendTab = CreateFrame("Frame", nil, frame)
    sendTab:SetPoint("TOPLEFT", 16, -98)
    sendTab:SetPoint("BOTTOMRIGHT", -16, 56)
    sendTab:Hide()

    local toLabel = sendTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toLabel:SetPoint("TOPLEFT", 0, 0)
    toLabel:SetText(IR.L["To:"])

    sendRecipientEdit = CreateFrame("EditBox", nil, sendTab)
    sendRecipientEdit:SetSize(220, 20)
    sendRecipientEdit:SetPoint("TOPLEFT", 70, 0)
    sendRecipientEdit:SetAutoFocus(false)
    sendRecipientEdit:SetFontObject("ChatFontNormal")
    sendRecipientEdit:SetMaxLetters(32)
    sendRecipientEdit:SetTextInsets(4, 4, 0, 0)
    sendRecipientEdit:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    sendRecipientEdit:SetBackdropColor(0, 0, 0, 0.5)
    sendRecipientEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sendRecipientEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        sendSubjectEdit:SetFocus()
    end)
    sendRecipientEdit:SetScript("OnTextChanged", function() refreshSend() end)

    local subjLabel = sendTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subjLabel:SetPoint("TOPLEFT", 0, -28)
    subjLabel:SetText(IR.L["Subject:"])

    sendSubjectEdit = CreateFrame("EditBox", nil, sendTab)
    sendSubjectEdit:SetSize(490, 20)
    sendSubjectEdit:SetPoint("TOPLEFT", 70, -28)
    sendSubjectEdit:SetAutoFocus(false)
    sendSubjectEdit:SetFontObject("ChatFontNormal")
    sendSubjectEdit:SetMaxLetters(64)
    sendSubjectEdit:SetTextInsets(4, 4, 0, 0)
    sendSubjectEdit:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    sendSubjectEdit:SetBackdropColor(0, 0, 0, 0.5)
    sendSubjectEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sendSubjectEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        sendBodyEdit:SetFocus()
    end)

    local bodyLabel = sendTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bodyLabel:SetPoint("TOPLEFT", 0, -56)
    bodyLabel:SetText(IR.L["Body:"])

    sendBodyScroll = CreateFrame("ScrollFrame", nil, sendTab, "UIPanelScrollFrameTemplate")
    sendBodyScroll:SetPoint("TOPLEFT", 0, -76)
    sendBodyScroll:SetSize(540, 110)
    sendBodyScroll:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    sendBodyScroll:SetBackdropColor(0, 0, 0, 0.5)

    sendBodyEdit = CreateFrame("EditBox", nil, sendBodyScroll)
    sendBodyEdit:SetMultiLine(true)
    sendBodyEdit:SetAutoFocus(false)
    sendBodyEdit:SetFontObject("ChatFontNormal")
    sendBodyEdit:SetMaxLetters(500)
    sendBodyEdit:SetWidth(520)
    sendBodyEdit:SetTextInsets(4, 4, 4, 4)
    sendBodyEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sendBodyScroll:SetScrollChild(sendBodyEdit)

    local attachLabel = sendTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    attachLabel:SetPoint("TOPLEFT", 0, -196)
    attachLabel:SetText(IR.L["Attachments:"])

    for i = 1, ATTACH_MAX_SEND do
        local b = CreateFrame("Button", "IronSendSlot" .. i, sendTab)
        b:SetSize(40, 40)
        b:SetPoint("TOPLEFT", (i - 1) * 44, -216)
        b.slot = i

        b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
        local nt = b:GetNormalTexture()
        nt:SetVertexColor(1, 1, 1, 0.9)

        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:Hide()
        b.icon = icon

        local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        count:SetPoint("BOTTOMRIGHT", -3, 3)
        count:SetText("")
        b.count = count

        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

        b:EnableMouse(true)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnClick", function(self)
            if not IronMail.mailboxOpen then return end
            ClickSendMailItemButton(self.slot)
            if refreshSend then refreshSend() end
        end)
        b:SetScript("OnReceiveDrag", function(self)
            if not IronMail.mailboxOpen then return end
            if CursorHasItem() then
                ClickSendMailItemButton(self.slot)
                if refreshSend then refreshSend() end
            end
        end)
        b:SetScript("OnDragStart", function(self)
            if not IronMail.mailboxOpen then return end
            if GetSendMailItem and GetSendMailItem(self.slot) then
                ClickSendMailItemButton(self.slot, 1)
                if refreshSend then refreshSend() end
            end
        end)
        b:SetScript("OnEnter", function(self)
            local link = GetSendMailItemLink and GetSendMailItemLink(self.slot)
            if link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)

        sendAttachSlots[i] = b
    end

    local moneyLabel = sendTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    moneyLabel:SetPoint("TOPLEFT", 0, -264)
    moneyLabel:SetText(IR.L["Money:"])

    sendMoneyFrame = CreateFrame("Frame", "IronSendMoney", sendTab, "MoneyInputFrameTemplate")
    sendMoneyFrame:SetPoint("TOPLEFT", 70, -260)

    sendCODCheck = CreateFrame("CheckButton", nil, sendTab, "UICheckButtonTemplate")
    sendCODCheck:SetPoint("LEFT", sendMoneyFrame, "RIGHT", 60, 0)
    local codLabel = sendCODCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    codLabel:SetPoint("LEFT", sendCODCheck, "RIGHT", 4, 0)
    codLabel:SetText(IR.L["COD (Cash on Delivery)"])

    sendBtn = CreateFrame("Button", nil, sendTab, "UIPanelButtonTemplate")
    sendBtn:SetSize(100, 22)
    sendBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    sendBtn:SetText(IR.L["Send"])
    sendBtn:SetScript("OnClick", function() UI:DoSendMail() end)

    sendClearBtn = CreateFrame("Button", nil, sendTab, "UIPanelButtonTemplate")
    sendClearBtn:SetSize(100, 22)
    sendClearBtn:SetPoint("RIGHT", sendBtn, "LEFT", -4, 0)
    sendClearBtn:SetText(IR.L["Clear"])
    sendClearBtn:SetScript("OnClick", function() UI:ClearSendForm() end)

    refreshSend = function()
        if not sendTab then return end
        for i = 1, ATTACH_MAX_SEND do
            local b = sendAttachSlots[i]
            local name, tex, count, quality
            if GetSendMailItem then
                name, tex, count, quality = GetSendMailItem(i)
            end
            if name and tex then
                b.icon:SetTexture(tex)
                b.icon:Show()
                if count and count > 1 then
                    b.count:SetText(count)
                else
                    b.count:SetText("")
                end
            else
                b.icon:Hide()
                b.count:SetText("")
            end
        end
        local recipient = sendRecipientEdit:GetText() or ""
        local hasRecipient = recipient:gsub("%s", "") ~= ""
        if hasRecipient then sendBtn:Enable() else sendBtn:Disable() end
    end

    takeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    takeBtn:SetSize(100, 22)
    takeBtn:SetPoint("BOTTOMLEFT", 16, 16)
    takeBtn:SetText(IR.L["Take"])
    takeBtn:SetScript("OnClick", function()
        if not selectedIndex then return end
        local _, _, sender, _, _, COD = GetInboxHeaderInfo(selectedIndex)
        if COD and COD > 0 then
            UI:ShowCODPopup(selectedIndex, sender, COD)
        else
            IronMail:TakeMail(selectedIndex)
        end
    end)

    deleteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    deleteBtn:SetSize(100, 22)
    deleteBtn:SetPoint("LEFT", takeBtn, "RIGHT", 4, 0)
    deleteBtn:SetText(IR.L["Delete"])
    deleteBtn:SetScript("OnClick", function()
        if selectedIndex then
            IronMail:DeleteMail(selectedIndex)
            selectedIndex = nil
            refreshList()
        end
    end)

    returnBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    returnBtn:SetSize(100, 22)
    returnBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 4, 0)
    returnBtn:SetText(IR.L["Return"])
    returnBtn:SetScript("OnClick", function()
        if selectedIndex then
            IronMail:ReturnMail(selectedIndex)
            selectedIndex = nil
            refreshList()
        end
    end)

    loadPos()
    showTab("inbox")
end

local function hookMailFrame()
    if not MailFrame or UI._hooked then return end
    UI._hooked = true
    MailFrame:UnregisterEvent("MAIL_SHOW")
    MailFrame:HookScript("OnShow", function(self)
        if allowMailFrame or internalMailVisible then return end
        self:Hide()
    end)
    MailFrame:HookScript("OnHide", function()
        if internalMailVisible then return end
        if allowMailFrame and IronMail.mailboxOpen then
            allowMailFrame = false
            UI:Show()
        end
    end)
end

function UI:OpenClassicUI(tab)
    if not MailFrame then return end
    internalHideMailFrame()
    allowMailFrame = true
    if frame then frame:Hide() end
    MailFrame:Show()
    local target = MailFrameTab1
    if tab == "send" and MailFrameTab2 then target = MailFrameTab2 end
    if target and MailFrameTab_OnClick then
        MailFrameTab_OnClick(target)
    end
end

function UI:ClearSendForm()
    if sendRecipientEdit then sendRecipientEdit:SetText("") end
    if sendSubjectEdit then sendSubjectEdit:SetText("") end
    if sendBodyEdit then sendBodyEdit:SetText("") end
    if sendMoneyFrame and MoneyInputFrame_ResetMoney then
        MoneyInputFrame_ResetMoney(sendMoneyFrame)
    end
    if sendCODCheck then sendCODCheck:SetChecked(false) end
    if ClearSendMail then ClearSendMail() end
    if refreshSend then refreshSend() end
end

function UI:DoSendMail()
    if not IronMail.mailboxOpen then return end
    local recipient = sendRecipientEdit:GetText() or ""
    recipient = recipient:gsub("^%s+", ""):gsub("%s+$", "")
    if recipient == "" then
        IR:Print(IR.L["Recipient is required"])
        return
    end
    local subject = sendSubjectEdit:GetText() or ""
    local body = sendBodyEdit:GetText() or ""
    local copper = (MoneyInputFrame_GetCopper and sendMoneyFrame and MoneyInputFrame_GetCopper(sendMoneyFrame)) or 0
    local isCOD = sendCODCheck:GetChecked() and true or false

    local hasAttachment = false
    for i = 1, ATTACH_MAX_SEND do
        if GetSendMailItem and GetSendMailItem(i) then
            hasAttachment = true
            break
        end
    end

    if isCOD then
        if not hasAttachment then
            IR:Print(IR.L["COD requires at least one attachment"])
            return
        end
        if copper <= 0 then
            IR:Print(IR.L["COD requires an amount > 0"])
            return
        end
        if SetSendMailCOD then SetSendMailCOD(copper) end
        if SetSendMailMoney then SetSendMailMoney(0) end
    else
        if SetSendMailCOD then SetSendMailCOD(0) end
        if SetSendMailMoney then SetSendMailMoney(copper) end
    end

    SendMail(recipient, subject, body)
    IR:Print(string.format(IR.L["Mail sent to %s"], recipient))
    UI:ClearSendForm()
end

local codPopup
local function buildCODPopup()
    if codPopup then return codPopup end
    codPopup = CreateFrame("Frame", "IronCODPopup", UIParent)
    codPopup:Hide()
    codPopup:SetSize(420, 140)
    codPopup:SetPoint("CENTER")
    codPopup:SetFrameStrata("DIALOG")
    codPopup:EnableMouse(true)
    codPopup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    codPopup:SetBackdropColor(0, 0, 0, 0.95)

    local fs = codPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOP", 0, -22)
    fs:SetWidth(380)
    fs:SetJustifyH("CENTER")
    codPopup.text = fs

    local payBtn = CreateFrame("Button", nil, codPopup, "UIPanelButtonTemplate")
    payBtn:SetSize(120, 22)
    payBtn:SetPoint("BOTTOMLEFT", 18, 16)
    payBtn:SetText(IR.L["Pay & take"])
    codPopup.payBtn = payBtn

    local returnBtn = CreateFrame("Button", nil, codPopup, "UIPanelButtonTemplate")
    returnBtn:SetSize(120, 22)
    returnBtn:SetPoint("BOTTOM", 0, 16)
    returnBtn:SetText(IR.L["Return"])
    codPopup.returnBtn = returnBtn

    local cancelBtn = CreateFrame("Button", nil, codPopup, "UIPanelButtonTemplate")
    cancelBtn:SetSize(120, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", -18, 16)
    cancelBtn:SetText(IR.L["Cancel"])
    cancelBtn:SetScript("OnClick", function() codPopup:Hide() end)

    tinsert(UISpecialFrames, "IronCODPopup")
    return codPopup
end

function UI:ShowCODPopup(idx, sender, codAmount)
    buildCODPopup()
    codPopup.text:SetText(string.format(
        IR.L["This mail charges %s on delivery from %s.\nPay and accept?"],
        IR:CopperToString(codAmount), tostring(sender or "?")))
    codPopup.payBtn:SetScript("OnClick", function()
        codPopup:Hide()
        IronMail:TakeMail(idx)
    end)
    codPopup.returnBtn:SetScript("OnClick", function()
        codPopup:Hide()
        IronMail:ReturnMail(idx)
        selectedIndex = nil
        refreshList()
    end)
    codPopup:Show()
end

function UI:Show()
    createFrame()
    hookMailFrame()
    if MailFrame then MailFrame:Hide() end
    selectedIndex = nil
    frame:Show()
    refreshList()
end

function UI:Hide()
    internalHideMailFrame()
    if frame then frame:Hide() end
    allowMailFrame = false
end

IR:On("MAIL_SHOW", function()
    if CheckInbox then CheckInbox() end
    UI:Show()
end)
IR:On("MAIL_CLOSED", function() UI:Hide() end)
IR:On("MAIL_INBOX_UPDATE", function()
    if frame and frame:IsShown() then refreshList() end
end)

IR:On("MAIL_SEND_INFO_UPDATE", function()
    if sendTab and sendTab:IsShown() and refreshSend then refreshSend() end
end)
IR:On("MAIL_SEND_SUCCESS", function()
    if sendTab and sendTab:IsShown() and refreshSend then refreshSend() end
end)
IR:On("BAG_UPDATE", function()
    if sendTab and sendTab:IsShown() and refreshSend then refreshSend() end
end)

IronMail.onChange = function()
    if frame and frame:IsShown() then refreshList() end
end

hookMailFrame()
