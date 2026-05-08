-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.IronSell = {}
local IronSell = IR.IronSell

local PriceDB = IR.PriceDB

local BAG_IDS = { 0, 1, 2, 3, 4 }

local function settings()
    return Iron_DB and Iron_DB.settings and Iron_DB.settings.ironSell
end

local function blacklistTable()
    local c = IR and IR.CharDB and IR:CharDB()
    return c and c.blacklist or nil
end

function IronSell:GetBlacklistTable()
    return blacklistTable() or {}
end

local sbScanner
local function getScanner()
    if not sbScanner then
        sbScanner = CreateFrame("GameTooltip", "IronSellTooltipScanner", nil, "GameTooltipTemplate")
    end
    return sbScanner
end

local function tooltipReason(bag, slot)
    local scanner = getScanner()
    scanner:ClearLines()
    scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    local ok = pcall(scanner.SetBagItem, scanner, bag, slot)
    if not ok then return nil end
    for i = 1, scanner:NumLines() do
        local line = _G["IronSellTooltipScannerTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                if text == ITEM_SOULBOUND or text == ITEM_BIND_ON_PICKUP then
                    return "soulbound"
                end
                if text == ITEM_BIND_QUEST then
                    return "quest"
                end
            end
        end
    end
    return nil
end

function IronSell:IsBlacklisted(itemID)
    local bl = blacklistTable()
    return bl and bl[itemID] == true or false
end

function IronSell:AddToBlacklist(itemID)
    local bl = blacklistTable()
    if not bl then return false end
    itemID = tonumber(itemID)
    if not itemID or itemID < 1 then return false end
    local existed = bl[itemID] == true
    bl[itemID] = true
    return true, existed
end

function IronSell:RemoveFromBlacklist(itemID)
    local bl = blacklistTable()
    if not bl then return end
    bl[tonumber(itemID)] = nil
end

function IronSell:ParseItemFromText(text)
    if not text or text == "" then return nil end
    local id = text:match("|Hitem:(%d+):")
    if id then return tonumber(id) end
    return tonumber(text:match("^%s*(%d+)%s*$"))
end

function IronSell:GetScanCandidates()
    -- Use the sellable list as the scan target so we skip blacklisted,
    -- soulbound, quest, junk (unless includeGrey) items. No point scanning
    -- AH prices for stuff the user can't sell anyway.
    local list, skipReasons = self:EnumerateSellable()
    local items = {}
    local seen = {}
    for _, info in ipairs(list) do
        if info.itemID and not seen[info.itemID] then
            seen[info.itemID] = true
            table.insert(items, info.itemID)
        end
    end
    local skipped = 0
    for _, n in pairs(skipReasons or {}) do
        skipped = skipped + (n or 0)
    end
    return items, skipped
end

function IronSell:ParseItemsFromText(text)
    if not text or text == "" then return {} end
    local items = {}
    local seen = {}
    for id in text:gmatch("|Hitem:(%d+):") do
        local n = tonumber(id)
        if n and not seen[n] then
            seen[n] = true
            table.insert(items, n)
        end
    end
    if #items == 0 then
        local single = tonumber(text:match("^%s*(%d+)%s*$"))
        if single then table.insert(items, single) end
    end
    return items
end

function IronSell:EnumerateSellable()
    local s = settings() or {}
    local items = {}
    local skipReasons = { blacklisted = 0, soulbound = 0, quest = 0, junk = 0 }

    for _, bag in ipairs(BAG_IDS) do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local itemID = tonumber(link:match("item:(%d+)"))
                local _, count = GetContainerItemInfo(bag, slot)
                if itemID and count and count > 0 then
                    if not items[itemID] then
                        local name, itemLink, quality, _, _, _, _, _, _, _, vendor = GetItemInfo(itemID)
                        local reason
                        local bl = blacklistTable()
                        if bl and bl[itemID] then
                            reason = "blacklisted"
                        elseif quality == 0 and not s.includeGrey then
                            reason = "junk"
                        else
                            reason = tooltipReason(bag, slot)
                        end
                        if reason then
                            skipReasons[reason] = (skipReasons[reason] or 0) + 1
                        end
                        items[itemID] = {
                            itemID = itemID,
                            name = name,
                            link = itemLink or link,
                            quality = quality or 1,
                            vendorPrice = vendor or 0,
                            count = 0,
                            sellable = (reason == nil),
                            reason = reason,
                        }
                    end
                    items[itemID].count = items[itemID].count + count
                end
            end
        end
    end

    local now = time()
    -- Backward compat: migrate the old days-based key if present
    local staleThresholdSeconds = s.staleThresholdSeconds
    if not staleThresholdSeconds and s.staleThresholdDays then
        staleThresholdSeconds = s.staleThresholdDays * 86400
        s.staleThresholdSeconds = staleThresholdSeconds
        s.staleThresholdDays = nil
    end
    staleThresholdSeconds = staleThresholdSeconds or 3600
    local undercutFactor = (100 - (s.undercutPercent or 5)) / 100

    local sellableList = {}
    for _, info in pairs(items) do
        if info.sellable then
            local market = PriceDB:GetMarketValue(info.itemID)
            local lastUpdate = PriceDB:GetLastUpdate(info.itemID)
            if not market then
                info.status = "no_data"
            else
                info.market = market
                info.salePrice = math.floor(market * undercutFactor)
                local age = lastUpdate and (now - lastUpdate)
                info.age = age
                if info.vendorPrice > 0 and info.salePrice <= info.vendorPrice then
                    info.status = "vendor_better"
                elseif age and age > staleThresholdSeconds then
                    info.status = "stale"
                else
                    info.status = "ok"
                end
            end
            table.insert(sellableList, info)
        end
    end

    table.sort(sellableList, function(a, b)
        local order = { ok = 1, stale = 2, no_data = 3, vendor_better = 4 }
        local ao = order[a.status or ""] or 99
        local bo = order[b.status or ""] or 99
        if ao ~= bo then return ao < bo end
        return (a.name or "") < (b.name or "")
    end)

    return sellableList, skipReasons
end

-- ============================================================================
-- Posting (Phase 9)
-- ============================================================================

local DURATION_INDEX = { [12] = 1, [24] = 2, [48] = 3 }

local postState = nil
local postTimerFrame = CreateFrame("Frame")
postTimerFrame:Hide()
local postTimerElapsed = 0
local postTimerCb

postTimerFrame:SetScript("OnUpdate", function(self, dt)
    postTimerElapsed = postTimerElapsed + dt
    if postTimerCb and postTimerElapsed >= postTimerCb.delay then
        local fn = postTimerCb.fn
        postTimerCb = nil
        postTimerElapsed = 0
        self:Hide()
        fn()
    end
end)

local function postSchedule(delay, fn)
    postTimerCb = { delay = delay, fn = fn }
    postTimerElapsed = 0
    postTimerFrame:Show()
end

local function postCancelTimer()
    postTimerCb = nil
    postTimerElapsed = 0
    postTimerFrame:Hide()
end

local function ahOpen()
    return AuctionFrame and AuctionFrame:IsShown()
end


local errorListenerActive = false
local lastUIError
local errorListenerFrame = CreateFrame("Frame")
errorListenerFrame:RegisterEvent("UI_ERROR_MESSAGE")
errorListenerFrame:RegisterEvent("CHAT_MSG_SYSTEM")
errorListenerFrame:SetScript("OnEvent", function(_, event, ...)
    if not errorListenerActive then return end
    local msg = ...
    if not msg then return end
    if event == "UI_ERROR_MESSAGE" then
        lastUIError = msg
        IR:Debug("[" .. event .. "] " .. tostring(msg))
    elseif event == "CHAT_MSG_SYSTEM" then
        -- Only treat actual errors as UI errors. "Enchère créée" / "Auction created"
        -- are success notifications and must not block the post.
        local lower = msg:lower()
        if lower:find("erreur") or lower:find("ui error") then
            lastUIError = msg
            IR:Debug("[" .. event .. "] " .. tostring(msg))
        end
    end
end)

local function findSlotWithCount(itemID, minCount)
    for _, bag in ipairs(BAG_IDS) do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = tonumber(link:match("item:(%d+)"))
                if id == itemID then
                    local _, count, locked = GetContainerItemInfo(bag, slot)
                    if count and count >= minCount and not locked then
                        return bag, slot, count
                    end
                end
            end
        end
    end
    return nil
end

local function totalInBags(itemID)
    local total = 0
    for _, bag in ipairs(BAG_IDS) do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link and tonumber(link:match("item:(%d+)")) == itemID then
                local _, count = GetContainerItemInfo(bag, slot)
                total = total + (count or 0)
            end
        end
    end
    return total
end

local postOneStack, verifyAndStart, finishPosting

finishPosting = function(success, reason, extra)
    local s = postState
    postState = nil
    postCancelTimer()

    local posted = s and (s.posted or 0) or 0
    local goal = s and s.opts and s.opts.numStacks or 0
    local link = s and s.opts and (s.opts.itemLink or ("Item #" .. (s.opts.itemID or 0))) or "?"

    if success then
        local salePrice = s.opts.salePrice or 0
        -- salePrice is per-stack buyout already, so total = perStackBuyout × numStacks
        local totalGold = salePrice * posted
        IR:Print(string.format(IR.L["Posted %d/%d stacks of %s, total %s"],
            posted, goal, link, IR:CopperToString(totalGold)))
    else
        if reason == "ah_closed" then
            IR:Print(IR.L["Posting interrupted: AH closed"])
        elseif reason == "deposit_short" then
            IR:Print(string.format(IR.L["Not enough gold for deposit (%s needed)"],
                IR:CopperToString(extra or 0)))
        elseif reason == "no_slot" then
            IR:Print(string.format(IR.L["Cannot find a single slot with %d items of %s"],
                s.opts.stackSize or 0, link))
        elseif reason == "slot_mismatch" then
            IR:Print(IR.L["Auction sell slot did not accept the item"])
        elseif reason == "user_abort" then
            IR:Print(IR.L["Posting aborted"])
        elseif reason == "pickup_failed" then
            IR:Print(IR.L["Could not pick up the item from bag, retry"])
        elseif reason == "start_auction_failed" then
            IR:Print(string.format(IR.L["Server rejected posting: %s"], tostring(extra or "unknown")))
        else
            IR:Print(string.format(IR.L["Posting failed: %s"], tostring(reason)))
        end
        if posted > 0 then
            IR:Print(string.format(IR.L["(Posted %d before stop)"], posted))
        end
    end

    if s and s.onComplete then
        local ok, err = pcall(s.onComplete, success, posted, reason, extra)
        if not ok then IR:Print("|cffff5555posting callback error|r: " .. tostring(err)) end
    end
end

verifyAndStart = function()
    local s = postState
    if not s then return end
    if not ahOpen() then return finishPosting(false, "ah_closed") end

    local needed = s.opts.stackSize * s.opts.numStacks
    local name, _, slotCount = GetAuctionSellItemInfo()
    if not name then
        ClearCursor()
        IR:Debug("  -> slot_mismatch (sell slot empty)")
        return finishPosting(false, "slot_mismatch")
    end

    -- Total available = what's in bags + what's currently parked in the AH slot.
    -- The server pulls from across all bag slots once an item is placed, so we
    -- only require that the grand total covers `needed`.
    local bagBefore = totalInBags(s.opts.itemID) + (slotCount or 0)
    IR:Debug(string.format("[verifyAndStart] sell slot: name=%s slotCount=%s, bagTotal=%d, want %d × %d = %d",
        tostring(name), tostring(slotCount), bagBefore - (slotCount or 0),
        s.opts.stackSize, s.opts.numStacks, needed))

    if bagBefore < needed then
        ClearCursor()
        IR:Debug(string.format("  -> slot_mismatch (have %d total, need %d)", bagBefore, needed))
        return finishPosting(false, "slot_mismatch")
    end

    local runTime = s.runTime
    local buyout = s.opts.salePrice
    local minBid = s.opts.bidPrice or math.max(1, buyout - 1)

    -- Sync the AH UI's internal duration var (the server reads this on some impls)
    if AuctionFrameAuctions then AuctionFrameAuctions.duration = runTime end
    if StartPrice and MoneyInputFrame_SetCopper then MoneyInputFrame_SetCopper(StartPrice, minBid) end
    if BuyoutPrice and MoneyInputFrame_SetCopper then MoneyInputFrame_SetCopper(BuyoutPrice, buyout) end

    lastUIError = nil
    errorListenerActive = true
    StartAuction(minBid, buyout, runTime, s.opts.stackSize, s.opts.numStacks)
    IR:Debug(string.format("StartAuction(%d, %d, %d, %d, %d) called",
        minBid, buyout, runTime, s.opts.stackSize, s.opts.numStacks))

    postSchedule(0.5, function()
        if not postState then return end
        local afterName, _, afterCount = GetAuctionSellItemInfo()
        local afterCountN = (afterName and afterCount) or 0
        local bagAfter = totalInBags(s.opts.itemID) + afterCountN
        local consumed = bagBefore - bagAfter
        IR:Debug(string.format("[post StartAuction] sell slot: name=%s count=%s, bagTotal=%d, consumed=%d (needed %d)",
            tostring(afterName), tostring(afterCount), bagAfter - afterCountN, consumed, needed))
        errorListenerActive = false

        if consumed < needed then
            ClearCursor()
            local errMsg = lastUIError or string.format("only %d items consumed of %d", consumed, needed)
            return finishPosting(false, "start_auction_failed", errMsg)
        end

        s.posted = s.opts.numStacks
        -- Put any leftover items back in the bag
        if afterName and afterCountN > 0 then
            IR:Debug(string.format("  returning %d leftover items to bag", afterCountN))
            ClickAuctionSellItemButton()
            ClearCursor()
        end

        IR:Debug(string.format("Posted %d/%d stacks of itemID %d (stackSize %d, buyout %d each)",
            s.opts.numStacks, s.opts.numStacks, s.opts.itemID, s.opts.stackSize, buyout))
        finishPosting(true)
    end)
end

postOneStack = function()
    local s = postState
    if not s then return end
    if not ahOpen() then return finishPosting(false, "ah_closed") end

    -- Any slot with the item works: once it's parked in the AH sell slot, the
    -- server can pull the rest from across the bags via StartAuction's
    -- stackSize/numStacks args.
    local bag, slot, slotCount = findSlotWithCount(s.opts.itemID, 1)
    IR:Debug(string.format("[postOneStack] itemID=%d need %d × %d = %d total",
        s.opts.itemID, s.opts.stackSize, s.opts.numStacks,
        s.opts.stackSize * s.opts.numStacks))

    if not bag then
        if (s.slotRetry or 0) < 3 then
            s.slotRetry = (s.slotRetry or 0) + 1
            return postSchedule(0.4, postOneStack)
        end
        return finishPosting(false, "no_slot")
    end
    s.slotRetry = 0
    IR:Debug(string.format("  parking from bag=%d slot=%d count=%d",
        bag, slot, slotCount or 0))

    ClearCursor()

    -- Clear any residual item in the AH sell slot first
    local residName, _, residCount = GetAuctionSellItemInfo()
    if residName then
        IR:Debug(string.format("  clearing residual sell slot: %s x%s",
            tostring(residName), tostring(residCount)))
        ClickAuctionSellItemButton()
        ClearCursor()
    end

    -- Pickup the whole stack (no split — Ascension's SplitContainerItem ignores count)
    PickupContainerItem(bag, slot)
    local cursorType, cursorItemID = GetCursorInfo()
    if cursorType ~= "item" or cursorItemID ~= s.opts.itemID then
        ClearCursor()
        if (s.pickupRetry or 0) < 3 then
            s.pickupRetry = (s.pickupRetry or 0) + 1
            return postSchedule(0.5, postOneStack)
        end
        return finishPosting(false, "pickup_failed")
    end
    s.pickupRetry = 0

    ClickAuctionSellItemButton()
    postSchedule(0.3, verifyAndStart)
end

function IronSell:IsPosting()
    return postState ~= nil
end

function IronSell:AbortPosting()
    if postState then
        finishPosting(false, "user_abort")
    end
end

function IronSell:PostAuction(opts, onComplete)
    local cb = onComplete or function() end
    IR:Debug(string.format("[PostAuction] itemID=%s stackSize=%s numStacks=%s salePrice=%s duration=%s",
        tostring(opts and opts.itemID), tostring(opts and opts.stackSize),
        tostring(opts and opts.numStacks), tostring(opts and opts.salePrice),
        tostring(opts and opts.durationHours)))

    if postState then
        IR:Print(IR.L["Posting already in progress"])
        cb(false, 0, "already_running")
        return false
    end
    if not ahOpen() then
        IR:Print(IR.L["Auction House not open"])
        cb(false, 0, "ah_not_open")
        return false
    end
    if not opts or not opts.itemID or not opts.stackSize or not opts.numStacks
       or opts.stackSize < 1 or opts.numStacks < 1
       or not opts.salePrice or opts.salePrice < 1 then
        IR:Print(IR.L["Invalid posting parameters"])
        cb(false, 0, "invalid")
        return false
    end

    local runTime = DURATION_INDEX[opts.durationHours] or 1
    local needed = opts.stackSize * opts.numStacks
    local have = totalInBags(opts.itemID)
    IR:Debug(string.format("  pre-flight: needed=%d have=%d runTime=%d",
        needed, have, runTime))
    if have < needed then
        IR:Print(string.format(IR.L["Not enough items in bags (have %d, need %d)"], have, needed))
        cb(false, 0, "not_enough_items", { have = have, need = needed })
        return false
    end

    postState = {
        opts = opts,
        runTime = runTime,
        posted = 0,
        totalDeposit = 0,
        onComplete = cb,
    }

    IR:Debug(string.format("Posting %s: %d x %d at %s",
        opts.itemLink or ("Item #" .. opts.itemID),
        opts.stackSize, opts.numStacks, IR:CopperToString(opts.salePrice)))

    postSchedule(0.05, postOneStack)
    return true
end

IR:On("AUCTION_HOUSE_CLOSED", function()
    if postState then finishPosting(false, "ah_closed") end
end)

local blacklistContent, blacklistRows = nil, {}
local addBlackEdit
local refreshBlacklist
local includeGreyCheck

local function makeEditBox(parent, width, maxLetters)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetFontObject("ChatFontNormal")
    e:SetMaxLetters(maxLetters or 64)
    e:SetTextInsets(4, 4, 0, 0)
    e:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    e:SetBackdropColor(0, 0, 0, 0.5)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

local function buildSellAITab(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, -4)
    title:SetText(IR.L["Blacklist"])

    includeGreyCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    includeGreyCheck:SetPoint("TOPRIGHT", 0, 0)
    local greyLabel = includeGreyCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    greyLabel:SetPoint("RIGHT", includeGreyCheck, "LEFT", -2, 0)
    greyLabel:SetText(IR.L["Include grey items"])
    includeGreyCheck:SetScript("OnClick", function(self)
        local s = settings()
        if s then s.includeGrey = self:GetChecked() and true or false end
    end)

    local durLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    durLabel:SetPoint("TOPLEFT", 0, -32)
    durLabel:SetText(IR.L["Default Quick Sell duration:"])

    local durRadios = {}
    local lastRadio
    for i, h in ipairs({ 12, 24, 48 }) do
        local rb = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
        if i == 1 then
            rb:SetPoint("LEFT", durLabel, "RIGHT", 12, 0)
        else
            rb:SetPoint("LEFT", lastRadio, "RIGHT", 50, 0)
        end
        local fs = rb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", rb, "RIGHT", 4, 0)
        fs:SetText(string.format("%dh", h))
        rb.value = h
        rb:SetScript("OnClick", function(self)
            local s = settings()
            if s then s.defaultDuration = self.value end
            for _, other in pairs(durRadios) do
                other:SetChecked(other == self)
            end
        end)
        durRadios[h] = rb
        lastRadio = rb
    end

    local function refreshDurRadios()
        local s = settings()
        local cur = (s and s.defaultDuration) or 12
        for h, rb in pairs(durRadios) do
            rb:SetChecked(h == cur)
        end
    end
    table.insert(IR.Settings.refreshHandlers, refreshDurRadios)

    local listFrame = CreateFrame("ScrollFrame", "IronSellBlacklistScroll", parent, "UIPanelScrollFrameTemplate")
    listFrame:SetPoint("TOPLEFT", 0, -60)
    listFrame:SetPoint("BOTTOMRIGHT", -22, 38)

    blacklistContent = CreateFrame("Frame", nil, listFrame)
    blacklistContent:SetSize(490, 1)
    listFrame:SetScrollChild(blacklistContent)

    local addLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("BOTTOMLEFT", 0, 18)
    addLabel:SetText(IR.L["Add (link or itemID):"])

    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetSize(60, 20)
    addBtn:SetPoint("BOTTOMRIGHT", 0, -2)
    addBtn:SetText(IR.L["Add"])

    addBlackEdit = makeEditBox(parent, 100, 4000)
    addBlackEdit:ClearAllPoints()
    addBlackEdit:SetPoint("BOTTOMLEFT", 0, -2)
    addBlackEdit:SetPoint("RIGHT", addBtn, "LEFT", -6, 0)

    local function tryAdd()
        local ids = IronSell:ParseItemsFromText(addBlackEdit:GetText())
        if #ids == 0 then
            IR:Print(IR.L["Invalid item link or ID"])
            return
        end
        for _, itemID in ipairs(ids) do
            local ok, existed = IronSell:AddToBlacklist(itemID)
            if ok then
                local name = GetItemInfo(itemID) or ("Item #" .. itemID)
                if existed then
                    IR:Print(string.format(IR.L["%s: already blacklisted"], name))
                else
                    IR:Print(string.format(IR.L["%s: added to blacklist"], name))
                end
            end
        end
        addBlackEdit:SetText("")
        addBlackEdit:ClearFocus()
        refreshBlacklist()
    end
    addBtn:SetScript("OnClick", tryAdd)
    addBlackEdit:SetScript("OnEnterPressed", tryAdd)

    local function getBlackRow(i)
        if blacklistRows[i] then return blacklistRows[i] end
        local row = CreateFrame("Frame", nil, blacklistContent)
        row:SetSize(490, 22)
        row:SetPoint("TOPLEFT", 0, -((i - 1) * 24))

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 2, 0)
        row.icon = icon

        local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        removeBtn:SetSize(22, 20)
        removeBtn:SetPoint("RIGHT", 0, 0)
        removeBtn:SetText("X")
        row.removeBtn = removeBtn

        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameFs:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        nameFs:SetPoint("RIGHT", removeBtn, "LEFT", -4, 0)
        nameFs:SetJustifyH("LEFT")
        row.name = nameFs

        blacklistRows[i] = row
        return row
    end

    refreshBlacklist = function()
        if not blacklistContent then return end
        for _, row in pairs(blacklistRows) do row:Hide() end

        local s = settings()
        if includeGreyCheck and s then
            includeGreyCheck:SetChecked(s.includeGrey and true or false)
        end

        local ids = {}
        local bl = blacklistTable()
        if bl then
            for itemID in pairs(bl) do table.insert(ids, itemID) end
            table.sort(ids, function(a, b)
                local na = GetItemInfo(a) or ""
                local nb = GetItemInfo(b) or ""
                if na == nb then return a < b end
                return na:lower() < nb:lower()
            end)
        end
        blacklistContent:SetHeight(math.max(#ids * 24, 1))

        for i, itemID in ipairs(ids) do
            local row = getBlackRow(i)
            local name, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
            row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText(name or ("Item #" .. itemID))
            row.removeBtn:SetScript("OnClick", function()
                IronSell:RemoveFromBlacklist(itemID)
                refreshBlacklist()
            end)
            row:Show()
        end
    end

    table.insert(IR.Settings.refreshHandlers, refreshBlacklist)
end

IR:RegisterSettingsTab({
    name = "ironsell",
    title = "IronSell",
    build = buildSellAITab,
})

local origChatEditInsertLink = ChatEdit_InsertLink
function ChatEdit_InsertLink(text)
    if not text then return false end
    if addBlackEdit and addBlackEdit:IsVisible() and addBlackEdit:HasFocus() then
        addBlackEdit:Insert(text)
        return true
    end
    return origChatEditInsertLink(text)
end
