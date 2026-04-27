-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.Scanner = {}
local Scanner = IR.Scanner

local PriceDB = IR.PriceDB

local BAG_IDS = { 0, 1, 2, 3, 4 }

local state
local function newState()
    return {
        running = false,
        mode = "targeted",
        queue = {},
        currentItemID = nil,
        currentItemName = nil,
        currentPage = 0,
        currentSeen = 0,
        currentTotal = 0,
        page = 0,
        totalAuctions = 0,
        seenAuctions = 0,
        results = {},
        startTime = 0,
        processed = false,
        totalItems = 0,
        itemsDone = 0,
    }
end
state = newState()

local timer = CreateFrame("Frame")
timer:Hide()
local timerElapsed = 0
local timerDelay = 0
local timerCb
timer:SetScript("OnUpdate", function(self, dt)
    timerElapsed = timerElapsed + dt
    if timerCb and timerElapsed >= timerDelay then
        local fn = timerCb
        timerCb = nil
        timerElapsed = 0
        self:Hide()
        fn()
    end
end)
local function schedule(delay, fn)
    timerDelay = delay
    timerElapsed = 0
    timerCb = fn
    timer:Show()
end

local trackFrame
local function createTrackFrame()
    if trackFrame then return end
    local f = CreateFrame("Frame", "IronScanFrame", UIParent)
    f:Hide()
    f:SetSize(300, 110)
    f:SetPoint("CENTER", 0, 180)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetBackdropColor(0, 0, 0, 0.92)

    local drag = CreateFrame("Button", nil, f)
    drag:SetPoint("TOPLEFT", 8, -8)
    drag:SetPoint("TOPRIGHT", -8, -8)
    drag:SetHeight(20)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Iron - " .. IR.L["Scan"])

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("TOPLEFT", 16, -34)
    status:SetText("")
    f.status = status

    local elapsed = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    elapsed:SetPoint("TOPLEFT", 16, -52)
    elapsed:SetText("")
    f.elapsed = elapsed

    local abort = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    abort:SetSize(80, 22)
    abort:SetPoint("BOTTOMRIGHT", -12, 12)
    abort:SetText(IR.L["Abort"])
    abort:SetScript("OnClick", function() Scanner:Abort() end)

    f:SetScript("OnUpdate", function(self)
        if state.running and state.startTime > 0 then
            local sec = math.floor(GetTime() - state.startTime)
            self.elapsed:SetText(string.format(IR.L["Elapsed: %ds"], sec))
        end
    end)

    trackFrame = f
end

local function showTrack(text)
    createTrackFrame()
    if text then trackFrame.status:SetText(text) end
    trackFrame:Show()
end

local function hideTrack()
    if trackFrame then trackFrame:Hide() end
end

local function setStatus(text)
    if trackFrame and trackFrame.status then
        trackFrame.status:SetText(text)
    end
end

local function getBagItemIDs()
    local seen = {}
    local list = {}
    for _, bag in ipairs(BAG_IDS) do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID and not seen[itemID] then
                    seen[itemID] = true
                    table.insert(list, itemID)
                end
            end
        end
    end
    return list
end

local processPage, scheduleNextPage, processTargetedPage, nextTargetedItem

local function finishScan(reason)
    if not state.running then return end
    state.running = false
    local elapsed = math.floor(GetTime() - state.startTime)

    if reason == "aborted" then
        if not state.silent then
            IR:Print(string.format(IR.L["Scan aborted in %ds"], elapsed))
        end
        hideTrack()
    elseif reason == "ah_closed" then
        if not state.silent then
            IR:Print(IR.L["AH closed during scan"])
        end
        hideTrack()
    else
        local recorded
        if state.mode == "targeted" then
            recorded = state.itemsDone or 0
        else
            recorded = PriceDB:RecordScan(state.results)
        end
        if not state.silent then
            IR:Print(string.format(IR.L["Scan complete: %d auctions, %d items recorded (%ds)"],
                #state.results, recorded, elapsed))
            setStatus(string.format(IR.L["Done: %d items"], recorded))
            schedule(2, hideTrack)
        else
            hideTrack()
        end
    end

    local oneShot = state.oneShotComplete
    state.oneShotComplete = nil
    if oneShot then
        local ok, err = pcall(oneShot, state.results, reason)
        if not ok then IR:Print("|cffff5555scan one-shot callback error|r: " .. tostring(err)) end
    end

    if Scanner.onComplete then
        local ok, err = pcall(Scanner.onComplete, state.results, reason)
        if not ok then IR:Print("|cffff5555scan callback error|r: " .. tostring(err)) end
    end
end

processTargetedPage = function()
    if not state.running then return end
    if not (AuctionFrame and AuctionFrame:IsShown()) then
        finishScan("ah_closed")
        return
    end

    local batch, total = GetNumAuctionItems("list")
    batch = batch or 0
    total = total or 0
    state.currentTotal = total

    state.currentItemFound = state.currentItemFound or 0
    state.currentBidOnly = state.currentBidOnly or 0

    local playerName = UnitName("player")
    local playerLower = playerName and playerName:lower() or nil
    state.currentOwnFiltered = state.currentOwnFiltered or 0

    local function isOwnerMe(owner)
        if not owner or not playerLower then return false end
        local ownerStr = tostring(owner):lower()
        if ownerStr == playerLower then return true end
        local stripped = ownerStr:match("^([^-]+)")
        if stripped == playerLower then return true end
        return false
    end

    for i = 1, batch do
        local name, texture, count, quality, canUse, level,
              minBid, minIncrement, buyoutPrice, bidAmount,
              highBidder, owner, sold = GetAuctionItemInfo("list", i)
        local itemID
        local link = GetAuctionItemLink("list", i)
        if link then itemID = tonumber(link:match("item:(%d+)")) end

        local isOwn = isOwnerMe(owner)

        if itemID == state.currentItemID and count and count > 0 and not isOwn then
            local price
            if buyoutPrice and buyoutPrice > 0 then
                price = buyoutPrice
            elseif minBid and minBid > 0 then
                price = minBid
                state.currentBidOnly = state.currentBidOnly + 1
            end
            if price then
                table.insert(state.results, {
                    itemID = itemID, count = count, buyout = price,
                    minBid = minBid, buyoutRaw = buyoutPrice, owner = owner,
                    listIndex = i,
                })
                state.currentItemFound = state.currentItemFound + 1
            end
        elseif itemID == state.currentItemID and isOwn then
            state.currentOwnFiltered = state.currentOwnFiltered + 1
        end
    end

    state.currentSeen = state.currentSeen + batch

    if state.currentSeen >= state.currentTotal or batch == 0 or state.singlePage then
        local bidNote = (state.currentBidOnly > 0)
            and string.format(" (%d bid-only)", state.currentBidOnly) or ""
        local ownNote = (state.currentOwnFiltered > 0)
            and string.format(" (%d own filtered)", state.currentOwnFiltered) or ""
        IR:Debug(string.format("  %s [id=%d]: %d matched%s%s",
            state.currentItemName or "?",
            state.currentItemID or 0,
            state.currentItemFound,
            bidNote,
            ownNote))

        local justFinishedID = state.currentItemID
        local itemResults = {}
        for _, r in ipairs(state.results) do
            if r.itemID == justFinishedID then
                table.insert(itemResults, r)
            end
        end
        if #itemResults > 0 then
            PriceDB:RecordScan(itemResults)
        end
        if Scanner.onItemDone then
            local ok, err = pcall(Scanner.onItemDone, justFinishedID, itemResults)
            if not ok then IR:Print("|cffff5555scan onItemDone error|r: " .. tostring(err)) end
        end

        state.itemsDone = state.itemsDone + 1
        state.currentItemFound = 0
        state.currentBidOnly = 0
        state.currentOwnFiltered = 0
        nextTargetedItem()
    else
        state.currentPage = state.currentPage + 1
        scheduleNextPage()
    end
end

nextTargetedItem = function()
    if not state.running then return end
    if not (AuctionFrame and AuctionFrame:IsShown()) then
        finishScan("ah_closed")
        return
    end

    if #state.queue == 0 then
        finishScan()
        return
    end

    state.currentItemID = table.remove(state.queue, 1)
    state.currentItemName = GetItemInfo(state.currentItemID)
    state.currentPage = 0
    state.currentSeen = 0
    state.currentTotal = 0

    if not state.currentItemName then
        IR:Debug("Skipping itemID " .. state.currentItemID .. " (info not loaded)")
        state.itemsDone = state.itemsDone + 1
        schedule(0.05, nextTargetedItem)
        return
    end

    setStatus(string.format(IR.L["Item %d/%d: %s"],
        state.itemsDone + 1, state.totalItems, state.currentItemName))
    scheduleNextPage()
end

scheduleNextPage = function()
    schedule(0.3, function()
        if not state.running then return end
        if not (AuctionFrame and AuctionFrame:IsShown()) then
            finishScan("ah_closed")
            return
        end
        if not CanSendAuctionQuery() then
            scheduleNextPage()
            return
        end
        state.processed = false
        if state.mode == "targeted" then
            QueryAuctionItems(state.currentItemName, "", "", nil, nil, nil, state.currentPage, nil, -1)
        else
            QueryAuctionItems("", "", "", nil, nil, nil, state.page, nil, -1)
        end
    end)
end

processPage = function()
    if not state.running then return end
    if not (AuctionFrame and AuctionFrame:IsShown()) then
        finishScan("ah_closed")
        return
    end

    local batchAuctions, totalAuctions = GetNumAuctionItems("list")
    state.totalAuctions = totalAuctions or 0

    for i = 1, (batchAuctions or 0) do
        local name, texture, count, quality, canUse, level, levelColHeader,
              minBid, minIncrement, buyoutPrice, bidAmount, hasAllInfo, owner, sold,
              ownerFullName, itemID = GetAuctionItemInfo("list", i)
        if not itemID then
            local link = GetAuctionItemLink("list", i)
            if link then itemID = tonumber(link:match("item:(%d+)")) end
        end
        if itemID and count and count > 0 and buyoutPrice and buyoutPrice > 0 then
            table.insert(state.results, {
                itemID = itemID, count = count, buyout = buyoutPrice,
            })
        end
    end

    state.seenAuctions = state.seenAuctions + (batchAuctions or 0)

    setStatus(string.format(IR.L["Page %d, %d / %d auctions"],
        state.page + 1, state.seenAuctions, state.totalAuctions))

    if state.seenAuctions >= state.totalAuctions or (batchAuctions or 0) == 0 then
        finishScan()
        return
    end

    state.page = state.page + 1
    scheduleNextPage()
end

function Scanner:Start(itemIDs, opts)
    if state.running then
        if not (opts and opts.silent) then
            IR:Print(IR.L["Scan already running"])
        end
        return false, "running"
    end
    if not (AuctionFrame and AuctionFrame:IsShown()) then
        IR:Print(IR.L["Open the auction house first"])
        return false, "ah_closed"
    end
    local canQuery = CanSendAuctionQuery()
    if not canQuery then
        if not (opts and opts.silent) then
            IR:Print(IR.L["Cannot send auction query yet, wait a moment"])
        end
        return false, "throttled"
    end

    local skippedBlacklist = 0
    if not itemIDs then
        if IR.IronSell and IR.IronSell.GetScanCandidates then
            itemIDs, skippedBlacklist = IR.IronSell:GetScanCandidates()
        else
            itemIDs = getBagItemIDs()
        end
    end
    if #itemIDs == 0 then
        IR:Print(IR.L["No items to scan in bags"])
        return false, "empty"
    end

    state = newState()
    state.running = true
    state.mode = "targeted"
    state.queue = itemIDs
    state.totalItems = #itemIDs
    state.itemsDone = 0
    state.startTime = GetTime()
    state.silent = (opts and opts.silent) or false
    state.oneShotComplete = opts and opts.onComplete or nil
    state.singlePage = (opts and opts.singlePage) or false

    if not state.silent then
        if skippedBlacklist > 0 then
            showTrack(string.format(IR.L["Targeted scan: %d items (%d blacklisted skipped)..."],
                state.totalItems, skippedBlacklist))
            IR:Debug(string.format("Targeted scan starting: %d items, %d blacklisted skipped",
                state.totalItems, skippedBlacklist))
        else
            showTrack(string.format(IR.L["Targeted scan: %d items..."], state.totalItems))
            IR:Debug(string.format("Targeted scan starting: %d items", state.totalItems))
        end
    end
    nextTargetedItem()
    return true
end

function Scanner:StartFull()
    if state.running then
        IR:Print(IR.L["Scan already running"])
        return
    end
    if not (AuctionFrame and AuctionFrame:IsShown()) then
        IR:Print(IR.L["Open the auction house first"])
        return
    end
    local canQuery = CanSendAuctionQuery()
    if not canQuery then
        IR:Print(IR.L["Cannot send auction query yet, wait a moment"])
        return
    end

    state = newState()
    state.running = true
    state.mode = "full"
    state.startTime = GetTime()

    showTrack(IR.L["Full scan starting (may take 5-15min)..."])
    IR:Debug("Full scan starting")
    state.processed = false
    QueryAuctionItems("", "", "", nil, nil, nil, 0, nil, -1)
end

function Scanner:IsRunning()
    return state.running
end

function Scanner:Abort()
    if state.running then
        finishScan("aborted")
    end
end

IR:On("AUCTION_ITEM_LIST_UPDATE", function()
    if not state.running then return end
    if state.processed then return end
    state.processed = true

    if state.mode == "targeted" then
        schedule(0.2, processTargetedPage)
    else
        schedule(0.3, processPage)
    end
end)

IR:On("AUCTION_HOUSE_CLOSED", function()
    if state.running then finishScan("ah_closed") end
end)

