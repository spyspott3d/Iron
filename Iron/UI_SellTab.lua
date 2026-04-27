-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

local IronSell = IR.IronSell
local Scanner = IR.Scanner
local PriceDB = IR.PriceDB

local ROW_H = 40
local LIST_INNER_W = 308

local listContent
local rows = {}
local lastScanLabel
local refresh

local QUALITY_COLORS = {
    [0] = "|cff9d9d9d",
    [1] = "|cffffffff",
    [2] = "|cff1eff00",
    [3] = "|cff0070dd",
    [4] = "|cffa335ee",
    [5] = "|cffff8000",
    [6] = "|cffe6cc80",
}

local function ageString(seconds)
    if not seconds or seconds <= 0 then return "?" end
    if seconds < 3600 then return string.format("%dm", math.floor(seconds / 60)) end
    if seconds < 86400 then return string.format("%.1fh", seconds / 3600) end
    return string.format("%.1fd", seconds / 86400)
end

local function getRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, listContent)
    r:SetSize(LIST_INNER_W, ROW_H)
    r:SetPoint("TOPLEFT", 0, -((i - 1) * (ROW_H + 2)))
    r:RegisterForClicks("LeftButtonUp")

    local hover = r:CreateTexture(nil, "BACKGROUND")
    hover:SetTexture(1, 1, 1)
    hover:SetAlpha(0.06)
    hover:SetAllPoints()
    hover:Hide()
    r.hover = hover

    local icon = r:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", 4, 0)
    r.icon = icon

    local nameFs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameFs:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -2)
    nameFs:SetWidth(140)
    nameFs:SetJustifyH("LEFT")
    r.name = nameFs

    local countFs = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -2)
    r.count = countFs

    local marketFs = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    marketFs:SetPoint("TOPRIGHT", -72, -4)
    marketFs:SetJustifyH("RIGHT")
    marketFs:SetWidth(80)
    r.market = marketFs

    local saleFs = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    saleFs:SetPoint("TOPRIGHT", -72, -20)
    saleFs:SetJustifyH("RIGHT")
    saleFs:SetWidth(80)
    r.sale = saleFs

    local sellBtn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    sellBtn:SetSize(64, 22)
    sellBtn:SetPoint("RIGHT", -4, 0)
    sellBtn:SetText(IR.L["Sell"])
    r.sellBtn = sellBtn
    IR:AttachTooltip(sellBtn, IR.L["Quick Sell: post all stacks at the suggested price"])

    r:SetScript("OnEnter", function(self)
        self.hover:Show()
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self)
        if self.info then IR.UI.SellTab:OpenValidation(self.info) end
    end)

    rows[i] = r
    return r
end

refresh = function()
    if not listContent or not listContent:IsShown() then
        if lastScanLabel then
            local last = PriceDB:GetLastFullScan()
            if last and last > 0 then
                lastScanLabel:SetText(string.format(IR.L["Last scan: %s ago"], ageString(time() - last)))
            else
                lastScanLabel:SetText(IR.L["No scan yet"])
            end
        end
        return
    end

    if lastScanLabel then
        local last = PriceDB:GetLastFullScan()
        if last and last > 0 then
            lastScanLabel:SetText(string.format(IR.L["Last scan: %s ago"], ageString(time() - last)))
        else
            lastScanLabel:SetText(IR.L["No scan yet"])
        end
    end

    local list = IronSell:EnumerateSellable()

    for _, r in pairs(rows) do r:Hide() end
    listContent:SetHeight(math.max(#list * (ROW_H + 2), 1))

    for i, info in ipairs(list) do
        local r = getRow(i)
        r.info = info
        r.itemLink = info.link
        r.icon:SetTexture(select(10, GetItemInfo(info.itemID)) or "Interface\\Icons\\INV_Misc_QuestionMark")

        local color = QUALITY_COLORS[info.quality] or QUALITY_COLORS[1]
        r.name:SetText(color .. (info.name or ("Item #" .. info.itemID)) .. "|r")
        r.count:SetText(string.format(IR.L["x%d in bags"], info.count))

        if info.status == "ok" then
            r.market:SetText(IR:CopperToString(info.market))
            r.sale:SetText("|cffffd700" .. IR:CopperToString(info.salePrice) .. "|r")
            r.sellBtn:Enable()
        elseif info.status == "stale" then
            r.market:SetText("|cffffaa00" .. IR:CopperToString(info.market) .. "|r")
            r.sale:SetText(string.format("|cffffaa00%s (%s)|r",
                IR:CopperToString(info.salePrice), ageString(info.age)))
            r.sellBtn:Enable()
        elseif info.status == "no_data" then
            r.market:SetText("|cff999999" .. IR.L["no data"] .. "|r")
            r.sale:SetText("")
            r.sellBtn:Disable()
        elseif info.status == "vendor_better" then
            r.market:SetText("|cff999999" .. IR.L["vendor"] .. "|r")
            r.sale:SetText("|cff999999" .. IR:CopperToString(info.vendorPrice or 0) .. "|r")
            r.sellBtn:Disable()
        end

        r.sellBtn:SetScript("OnClick", function()
            IR.UI.SellTab:QuickSell(info)
        end)

        r:Show()
    end
end

local listScroll
local validationPanel
local valItem
local scanBtn, refreshBtn

local function settingsSellAI()
    return Iron_DB and Iron_DB.settings and Iron_DB.settings.ironSell
end

local function autoSizeButton(btn, padding)
    padding = padding or 24
    local fs = btn:GetFontString()
    if fs then
        local w = math.max(60, math.ceil(fs:GetStringWidth()) + padding)
        btn:SetWidth(w)
    end
end

local function buildValidationPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints(parent)
    p:Hide()
    p:EnableMouse(true)

    local panelBg = p:CreateTexture(nil, "BACKGROUND")
    panelBg:SetTexture(0, 0, 0, 0.6)
    panelBg:SetAllPoints()

    local iconBg = p:CreateTexture(nil, "BACKGROUND")
    iconBg:SetSize(44, 44)
    iconBg:SetPoint("TOPLEFT", 4, -8)
    iconBg:SetTexture(0, 0, 0, 0.6)
    p.iconBg = iconBg

    local icon = p:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("CENTER", iconBg, "CENTER", 0, 0)
    p.icon = icon

    local nameFs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    nameFs:SetPoint("LEFT", iconBg, "RIGHT", 10, 8)
    nameFs:SetWidth(250)
    nameFs:SetJustifyH("LEFT")
    p.name = nameFs

    local countFs = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countFs:SetPoint("LEFT", iconBg, "RIGHT", 10, -10)
    p.count = countFs

    -- Stack size
    local stackLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stackLabel:SetPoint("TOPLEFT", 4, -76)
    stackLabel:SetText(IR.L["Stack size:"])

    local stackEdit = CreateFrame("EditBox", nil, p)
    stackEdit:SetSize(60, 22)
    stackEdit:SetPoint("LEFT", stackLabel, "RIGHT", 12, 0)
    stackEdit:SetAutoFocus(false)
    stackEdit:SetNumeric(true)
    stackEdit:SetMaxLetters(4)
    stackEdit:SetFontObject("ChatFontNormal")
    stackEdit:SetTextInsets(4, 4, 0, 0)
    stackEdit:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    stackEdit:SetBackdropColor(0, 0, 0, 0.5)
    stackEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    p.stackEdit = stackEdit

    local stackMaxBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    stackMaxBtn:SetSize(40, 22)
    stackMaxBtn:SetPoint("LEFT", stackEdit, "RIGHT", 6, 0)
    stackMaxBtn:SetText(IR.L["Max"])
    p.stackMaxBtn = stackMaxBtn
    IR:AttachTooltip(stackMaxBtn, IR.L["Set stack size to the item's max stack (or your bag count)"])

    local maxStackFs = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    maxStackFs:SetPoint("LEFT", stackMaxBtn, "RIGHT", 6, 0)
    p.maxStack = maxStackFs

    -- Num stacks
    local numLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    numLabel:SetPoint("TOPLEFT", 4, -110)
    numLabel:SetText(IR.L["Num stacks:"])

    local numEdit = CreateFrame("EditBox", nil, p)
    numEdit:SetSize(60, 22)
    numEdit:SetPoint("LEFT", numLabel, "RIGHT", 12, 0)
    numEdit:SetAutoFocus(false)
    numEdit:SetNumeric(true)
    numEdit:SetMaxLetters(4)
    numEdit:SetFontObject("ChatFontNormal")
    numEdit:SetTextInsets(4, 4, 0, 0)
    numEdit:SetBackdrop(stackEdit:GetBackdrop())
    numEdit:SetBackdropColor(0, 0, 0, 0.5)
    numEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    p.numEdit = numEdit

    local numMaxBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    numMaxBtn:SetSize(40, 22)
    numMaxBtn:SetPoint("LEFT", numEdit, "RIGHT", 6, 0)
    numMaxBtn:SetText(IR.L["Max"])
    p.numMaxBtn = numMaxBtn
    IR:AttachTooltip(numMaxBtn, IR.L["Set num stacks to floor(bag count / stack size)"])

    -- Unit price
    local unitLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    unitLabel:SetPoint("TOPLEFT", 4, -150)
    unitLabel:SetText(IR.L["Unit price:"])

    local unitMoney = CreateFrame("Frame", "IronSellUnitMoney", p, "MoneyInputFrameTemplate")
    unitMoney:SetPoint("TOPLEFT", 110, -146)
    p.unitMoney = unitMoney

    for _, suffix in ipairs({ "Gold", "Silver", "Copper" }) do
        local box = _G["IronSellUnitMoney" .. suffix]
        if box then
            box:Disable()
            box:EnableMouse(false)
            box:SetTextColor(0.5, 0.5, 0.5, 1)
        end
    end

    -- Sale price
    local saleLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    saleLabel:SetPoint("TOPLEFT", 4, -184)
    saleLabel:SetText(IR.L["Sale price:"])

    local saleMoney = CreateFrame("Frame", "IronSellSaleMoney", p, "MoneyInputFrameTemplate")
    saleMoney:SetPoint("TOPLEFT", 110, -180)
    p.saleMoney = saleMoney

    -- Undercut percent
    local cutLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cutLabel:SetPoint("TOPLEFT", 4, -218)
    cutLabel:SetText(IR.L["Undercut:"])

    local cutEdit = CreateFrame("EditBox", nil, p)
    cutEdit:SetSize(50, 22)
    cutEdit:SetPoint("LEFT", cutLabel, "RIGHT", 12, 0)
    cutEdit:SetAutoFocus(false)
    cutEdit:SetMaxLetters(5)
    cutEdit:SetFontObject("ChatFontNormal")
    cutEdit:SetTextInsets(4, 4, 0, 0)
    cutEdit:SetBackdrop(stackEdit:GetBackdrop())
    cutEdit:SetBackdropColor(0, 0, 0, 0.5)
    cutEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    p.cutEdit = cutEdit

    local pctFs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pctFs:SetPoint("LEFT", cutEdit, "RIGHT", 4, 0)
    pctFs:SetText("%")

    -- Duration radios
    local durLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    durLabel:SetPoint("TOPLEFT", 4, -256)
    durLabel:SetText(IR.L["Duration:"])

    p.durationRadios = {}
    local lastRadio
    for i, h in ipairs({ 12, 24, 48 }) do
        local rb = CreateFrame("CheckButton", nil, p, "UIRadioButtonTemplate")
        if i == 1 then
            rb:SetPoint("LEFT", durLabel, "RIGHT", 18, 0)
        else
            rb:SetPoint("LEFT", lastRadio, "RIGHT", 60, 0)
        end
        local fs = rb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", rb, "RIGHT", 4, 0)
        fs:SetText(string.format("%dh", h))
        rb.value = h
        rb:SetScript("OnClick", function(self)
            for _, other in pairs(p.durationRadios) do
                other:SetChecked(other == self)
            end
            p.duration = self.value
            if p.updateTotal then p.updateTotal() end
        end)
        p.durationRadios[h] = rb
        lastRadio = rb
    end

    -- Total
    local totalLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalLabel:SetPoint("TOPLEFT", 4, -300)
    totalLabel:SetText(IR.L["Total:"])

    local totalFs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    totalFs:SetPoint("LEFT", totalLabel, "RIGHT", 12, 0)
    totalFs:SetText("")
    p.totalFs = totalFs

    local depositFs = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    depositFs:SetPoint("TOPLEFT", 4, -326)
    depositFs:SetText("")
    p.depositFs = depositFs

    -- Recompute helpers
    local function getUnit() return MoneyInputFrame_GetCopper(unitMoney) or 0 end
    local function getSale() return MoneyInputFrame_GetCopper(saleMoney) or 0 end
    local function getCut() return tonumber(cutEdit:GetText()) or 0 end

    local function calcDeposit(vendor, stack, num, durationHours)
        if not vendor or vendor <= 0 then return 0 end
        local mult = 1
        if durationHours == 24 then mult = 2
        elseif durationHours == 48 then mult = 4 end
        return math.floor(vendor * stack * num * 0.05 * mult)
    end

    local function updateTotal()
        local stack = tonumber(stackEdit:GetText()) or 0
        local num = tonumber(numEdit:GetText()) or 0
        local sale = getSale()
        local total = stack * num * sale
        totalFs:SetText(IR:CopperToString(total))

        local vendor = (valItem and valItem.vendorPrice) or 0
        local deposit = calcDeposit(vendor, stack, num, p.duration or 12)
        local netGain = total - deposit
        depositFs:SetText(string.format(IR.L["Deposit: %s | Net if sold: %s"],
            IR:CopperToString(deposit), IR:CopperToString(netGain)))
    end
    p.updateTotal = updateTotal

    -- defined later inside this function; forward declarations via upvalue
    local clampStackRef, clampNumRef
    stackEdit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            if clampStackRef then clampStackRef() end
            if clampNumRef then clampNumRef() end
        end
        updateTotal()
    end)
    numEdit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            if clampNumRef then clampNumRef() end
        end
        updateTotal()
    end)

    p.stackMaxBtn:SetScript("OnClick", function()
        if not valItem then return end
        local _, _, _, _, _, _, _, maxStack = GetItemInfo(valItem.itemID)
        maxStack = maxStack or 1
        local target = math.min(maxStack, valItem.count or 1)
        if target < 1 then target = 1 end
        stackEdit:SetText(tostring(target))
        stackEdit:ClearFocus()
    end)

    p.numMaxBtn:SetScript("OnClick", function()
        if not valItem then return end
        local stack = tonumber(stackEdit:GetText()) or 0
        if stack < 1 then return end
        local target = math.floor((valItem.count or 0) / stack)
        if target < 1 then target = 1 end
        numEdit:SetText(tostring(target))
        numEdit:ClearFocus()
    end)

    local function clampStack()
        if not valItem then return end
        local raw = stackEdit:GetText()
        local v = tonumber(raw)
        if not v then return end
        local _, _, _, _, _, _, _, maxStack = GetItemInfo(valItem.itemID)
        if not maxStack or maxStack < 1 then maxStack = 1 end
        local upper = math.min(maxStack, valItem.count or 1)
        if upper < 1 then upper = 1 end
        if v > upper then
            stackEdit:SetText(tostring(upper))
            stackEdit:SetCursorPosition(#tostring(upper))
        end
    end

    local function clampNum()
        if not valItem then return end
        local raw = numEdit:GetText()
        local v = tonumber(raw)
        if not v then return end
        local stack = tonumber(stackEdit:GetText()) or 1
        if stack < 1 then stack = 1 end
        local upper = math.floor((valItem.count or 0) / stack)
        if upper < 1 then upper = 1 end
        if v > upper then
            numEdit:SetText(tostring(upper))
            numEdit:SetCursorPosition(#tostring(upper))
        end
    end

    local function ensureMinStack()
        local v = tonumber(stackEdit:GetText())
        if not v or v < 1 then stackEdit:SetText("1") end
    end

    local function ensureMinNum()
        local v = tonumber(numEdit:GetText())
        if not v or v < 1 then numEdit:SetText("1") end
    end

    local function ensureMinCut()
        local v = tonumber(cutEdit:GetText())
        if not v or v < 0 then cutEdit:SetText("0") end
    end

    clampStackRef = clampStack
    clampNumRef = clampNum

    stackEdit:SetScript("OnEditFocusLost", function()
        ensureMinStack(); clampStack(); clampNum()
    end)
    stackEdit:SetScript("OnEnterPressed", function(self)
        ensureMinStack(); clampStack(); clampNum(); self:ClearFocus()
    end)
    numEdit:SetScript("OnEditFocusLost", function() ensureMinNum(); clampNum() end)
    numEdit:SetScript("OnEnterPressed", function(self)
        ensureMinNum(); clampNum(); self:ClearFocus()
    end)

    local function setSaleFromUnit()
        local unit = getUnit()
        local pct = getCut()
        if pct < 0 then pct = 0 end
        if pct > 99 then pct = 99 end
        local sale = math.floor(unit * (100 - pct) / 100)
        p.suppressSaleEvent = true
        MoneyInputFrame_SetCopper(saleMoney, sale)
        p.suppressSaleEvent = false
    end

    local function hookMoneyFrame(mf, onUserChange)
        local goldBox = _G[mf:GetName() .. "Gold"]
        local silverBox = _G[mf:GetName() .. "Silver"]
        local copperBox = _G[mf:GetName() .. "Copper"]
        for _, box in ipairs({ goldBox, silverBox, copperBox }) do
            if box then
                box:HookScript("OnTextChanged", function(_, userInput)
                    if userInput then onUserChange() end
                end)
            end
        end
    end

    hookMoneyFrame(unitMoney, function()
        p.unitManuallyEdited = true
        if not p.saleManuallyEdited then setSaleFromUnit() end
        updateTotal()
    end)
    hookMoneyFrame(saleMoney, function()
        if p.suppressSaleEvent then
            updateTotal()
            return
        end
        p.saleManuallyEdited = true
        updateTotal()
    end)

    p.applyMarketValue = function(newUnit)
        if not newUnit or newUnit <= 0 then return end
        if not p.unitManuallyEdited then
            p.suppressSaleEvent = true
            MoneyInputFrame_SetCopper(unitMoney, newUnit)
            p.suppressSaleEvent = false
        end
        if not p.saleManuallyEdited then
            setSaleFromUnit()
        end
        updateTotal()
    end
    local function clampCut()
        local raw = cutEdit:GetText()
        local v = tonumber(raw)
        if not v then return end
        if v > 99 then
            cutEdit:SetText("99")
            cutEdit:SetCursorPosition(2)
        elseif v < 0 then
            cutEdit:SetText("0")
            cutEdit:SetCursorPosition(1)
        end
    end

    cutEdit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            clampCut()
            p.saleManuallyEdited = false
            setSaleFromUnit()
            updateTotal()
        end
    end)

    cutEdit:SetScript("OnEditFocusLost", function()
        ensureMinCut()
        clampCut()
        p.saleManuallyEdited = false
        setSaleFromUnit()
        updateTotal()
    end)
    cutEdit:SetScript("OnEnterPressed", function(self)
        ensureMinCut()
        clampCut()
        p.saleManuallyEdited = false
        setSaleFromUnit()
        updateTotal()
        self:ClearFocus()
    end)

    -- Buttons
    local cancelBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    cancelBtn:SetHeight(22)
    cancelBtn:SetPoint("BOTTOMLEFT", 4, 4)
    cancelBtn:SetText(IR.L["Cancel"])
    cancelBtn:SetScript("OnClick", function() IR.UI.SellTab:CloseValidation() end)
    autoSizeButton(cancelBtn)
    IR:AttachTooltip(cancelBtn, IR.L["Close this panel without posting"])

    local confirmBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    confirmBtn:SetHeight(22)
    confirmBtn:SetPoint("BOTTOMRIGHT", -4, 4)
    confirmBtn:SetText(IR.L["Confirm"])
    p.confirmBtn = confirmBtn
    confirmBtn:SetScript("OnClick", function()
        if not valItem then return end
        local stack = tonumber(stackEdit:GetText()) or 0
        local num = tonumber(numEdit:GetText()) or 0
        local unitSale = getSale()
        local duration = p.duration or 12
        local item = valItem
        local stackBuyout = unitSale * stack
        confirmBtn:Disable()
        IronSell:PostAuction({
            itemID = item.itemID,
            itemLink = item.link,
            vendorPrice = item.vendorPrice,
            stackSize = stack,
            numStacks = num,
            salePrice = stackBuyout,
            durationHours = duration,
        }, function(ok)
            if confirmBtn and confirmBtn.Enable then confirmBtn:Enable() end
            if ok then IR.UI.SellTab:CloseValidation() end
            refresh()
        end)
    end)
    autoSizeButton(confirmBtn)
    IR:AttachTooltip(confirmBtn, IR.L["Post the auctions with the values above"])

    local blackBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    blackBtn:SetHeight(22)
    blackBtn:SetText(IR.L["Add to Blacklist"])
    blackBtn:SetScript("OnClick", function()
        if valItem then
            IR.IronSell:AddToBlacklist(valItem.itemID)
            IR:Print(string.format(IR.L["%s: added to blacklist"],
                valItem.name or ("Item #" .. valItem.itemID)))
            IR.UI.SellTab:CloseValidation()
            refresh()
        end
    end)
    autoSizeButton(blackBtn)
    blackBtn:SetPoint("LEFT", cancelBtn, "RIGHT", 8, 0)
    IR:AttachTooltip(blackBtn, IR.L["Add this item to the blacklist (skipped from Sell list)"])

    return p
end

local function buildSellTab(parent)
    scanBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    scanBtn:SetHeight(22)
    scanBtn:SetPoint("TOPLEFT", 0, 0)
    scanBtn:SetText(IR.L["Scan bags"])
    scanBtn:SetScript("OnClick", function()
        if Scanner then Scanner:Start() end
    end)
    autoSizeButton(scanBtn)
    IR:AttachTooltip(scanBtn, IR.L["Scan AH for prices of items in your bags"])

    refreshBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    refreshBtn:SetHeight(22)
    refreshBtn:SetPoint("LEFT", scanBtn, "RIGHT", 6, 0)
    refreshBtn:SetText(IR.L["Refresh"])
    refreshBtn:SetScript("OnClick", function() refresh() end)
    autoSizeButton(refreshBtn)
    IR:AttachTooltip(refreshBtn, IR.L["Re-read your bags without rescanning AH prices"])

    lastScanLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lastScanLabel:SetPoint("TOPRIGHT", 0, -4)
    lastScanLabel:SetText("")

    listScroll = CreateFrame("ScrollFrame", "IronSellTabScroll", parent, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 0, -28)
    listScroll:SetPoint("BOTTOMRIGHT", -22, 4)

    listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(LIST_INNER_W, 1)
    listScroll:SetScrollChild(listContent)

    validationPanel = buildValidationPanel(parent)

    if Scanner then
        Scanner.onComplete = function() refresh() end
        Scanner.onItemDone = function() refresh() end
    end
end

IR.UI.SellTab = {}

function IR.UI.SellTab:OpenValidation(info)
    if not validationPanel then return end
    valItem = info
    validationPanel.saleManuallyEdited = false
    validationPanel.unitManuallyEdited = false
    validationPanel.suppressSaleEvent = false

    local _, link, _, _, _, _, _, maxStack, _, texture = GetItemInfo(info.itemID)
    maxStack = maxStack or 1
    local color = QUALITY_COLORS[info.quality] or QUALITY_COLORS[1]

    validationPanel.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    validationPanel.name:SetText(color .. (info.name or "?") .. "|r")
    validationPanel.count:SetText(string.format(IR.L["x%d in bags"], info.count))

    local defaultStack = math.min(maxStack, info.count)
    if defaultStack < 1 then defaultStack = 1 end
    local defaultNum = math.max(1, math.floor(info.count / defaultStack))
    validationPanel.stackEdit:SetText(tostring(defaultStack))
    validationPanel.numEdit:SetText(tostring(defaultNum))
    validationPanel.maxStack:SetText(string.format(IR.L["max %d"], maxStack))

    local s = settingsSellAI()
    local defaultCut = (s and s.undercutPercent) or 5
    validationPanel.cutEdit:SetText(tostring(defaultCut))

    local unit = info.market or 0
    local sale = info.salePrice or 0
    validationPanel.suppressSaleEvent = true
    MoneyInputFrame_SetCopper(validationPanel.unitMoney, unit)
    MoneyInputFrame_SetCopper(validationPanel.saleMoney, sale)
    validationPanel.suppressSaleEvent = false

    local defaultDur = (s and s.defaultDuration) or 12
    validationPanel.duration = defaultDur
    for h, rb in pairs(validationPanel.durationRadios) do
        rb:SetChecked(h == defaultDur)
    end

    validationPanel.updateTotal()

    if listScroll then listScroll:Hide() end
    if scanBtn then scanBtn:Hide() end
    if refreshBtn then refreshBtn:Hide() end
    if lastScanLabel then lastScanLabel:Hide() end
    validationPanel:Show()

    if validationPanel.confirmBtn and validationPanel.confirmBtn.Disable then
        validationPanel.confirmBtn:Disable()
    end
    if IR.UI.AuctionList then
        IR.UI.AuctionList:Open(info.itemID, link or info.link, function()
            if validationPanel.confirmBtn and validationPanel.confirmBtn:IsShown()
               and validationPanel.confirmBtn.Enable then
                validationPanel.confirmBtn:Enable()
            end
            if valItem and valItem.itemID == info.itemID then
                local freshMarket = PriceDB:GetMarketValue(info.itemID)
                if freshMarket and validationPanel.applyMarketValue then
                    validationPanel.applyMarketValue(freshMarket)
                end
            end
            refresh()
        end, {
            onClose = function() IR.UI.SellTab:CloseValidation() end,
        })
    end
end

function IR.UI.SellTab:CloseValidation()
    valItem = nil
    if validationPanel then validationPanel:Hide() end
    if listScroll then listScroll:Show() end
    if scanBtn then scanBtn:Show() end
    if refreshBtn then refreshBtn:Show() end
    if lastScanLabel then lastScanLabel:Show() end
    if IR.UI.AuctionList then IR.UI.AuctionList:Close() end
end

local function quickSellPost(info)
    if not info or not info.itemID then return end
    if not info.market or info.market <= 0 then return end

    local s = settingsSellAI() or {}
    local _, _, _, _, _, _, _, maxStack = GetItemInfo(info.itemID)
    maxStack = maxStack or 1
    if maxStack < 1 then maxStack = 1 end

    local stackSize = math.min(maxStack, info.count or 1)
    if stackSize < 1 then stackSize = 1 end
    local numStacks = math.floor((info.count or 1) / stackSize)
    if numStacks < 1 then numStacks = 1 end

    local undercutFactor = (100 - (s.undercutPercent or 5)) / 100
    local unitSale = info.salePrice or math.floor(info.market * undercutFactor)
    if unitSale < 1 then unitSale = 1 end
    local stackBuyout = unitSale * stackSize

    local duration = s.defaultDuration or 12

    IronSell:PostAuction({
        itemID = info.itemID,
        itemLink = info.link,
        vendorPrice = info.vendorPrice,
        stackSize = stackSize,
        numStacks = numStacks,
        salePrice = stackBuyout,
        durationHours = duration,
    }, function() refresh() end)
end

function IR.UI.SellTab:QuickSell(info)
    if not info or not info.itemID then return end
    if info.status == "no_data" or info.status == "vendor_better" then return end
    if not info.market or info.market <= 0 then return end

    -- If price data is stale, refresh via a single-item scan before posting
    -- so the Quick Sell uses up-to-date market info.
    if info.status == "stale" and Scanner then
        IR:Debug(string.format("Stale data, scanning %s before posting",
            info.link or info.name or "?"))
        local ok = Scanner:Start({ info.itemID }, {
            silent = true,
            singlePage = true,
            onComplete = function(_, reason)
                if reason == "ah_closed" or reason == "aborted" then return end
                local list = IronSell:EnumerateSellable()
                local fresh
                for _, x in ipairs(list) do
                    if x.itemID == info.itemID then fresh = x; break end
                end
                if fresh and fresh.status ~= "no_data" and fresh.market and fresh.market > 0 then
                    quickSellPost(fresh)
                else
                    -- No fresh data after rescan, fall back to original
                    quickSellPost(info)
                end
            end,
        })
        if not ok then quickSellPost(info) end
        return
    end

    quickSellPost(info)
end

function IR.UI.SellTab:Refresh()
    refresh()
end

IR.UI.AHCompanion:RegisterTab({
    name = "sell",
    title = "Sell",
    tooltip = IR.L["List items in your bags ready to be posted"],
    build = buildSellTab,
    onShow = function() refresh() end,
})

IR:On("BAG_UPDATE", function()
    if IR.UI.AHCompanion:GetMainFrame() and IR.UI.AHCompanion:GetMainFrame():IsShown() then
        refresh()
    end
end)

IR:On("AUCTION_HOUSE_CLOSED", function()
    if IR.UI.SellTab and IR.UI.SellTab.CloseValidation then
        IR.UI.SellTab:CloseValidation()
    end
end)
