-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.UI = IR.UI or {}
IR.UI.BuyAuctionList = {}
local BuyAuctionList = IR.UI.BuyAuctionList

local FRAME_W = 340
local FRAME_H = 560
local ROW_H = 26
local INNER_W = FRAME_W - 36

local BUY_DELAY = 1.0

local frame, listScroll, listContent, statusFs, titleFs
local qtyEdit, refreshBtn, buyBtn, footerFs
local rows = {}
local strategyBtns = {}

local state = {
    itemID = nil,
    link = nil,
    neededQty = 0,
    results = {},        -- sorted by unit ascending, only buyable (buyoutRaw > 0)
    selected = {},       -- [resultIndex] = true
    scanning = false,
    mode = "browse",     -- "browse" (selecting) or "queue" (processing)
    queue = nil,         -- list of { sig = {count, buyoutRaw, owner, unit}, status = "pending"|"bought"|"failed" }
    processing = false,  -- true between PlaceAuctionBid and result evaluation
    lastError = nil,
    selectStrategy = "more",  -- "less" | "exact" | "more"
}

local function applyStrategyButtons()
    for k, b in pairs(strategyBtns) do
        if k == state.selectStrategy then
            b:LockHighlight()
        else
            b:UnlockHighlight()
        end
    end
end

local timerFrame = CreateFrame("Frame")
timerFrame:Hide()
local timerCb
local timerElapsed = 0
timerFrame:SetScript("OnUpdate", function(self, dt)
    timerElapsed = timerElapsed + dt
    if timerCb and timerElapsed >= timerCb.delay then
        local fn = timerCb.fn
        timerCb = nil
        timerElapsed = 0
        self:Hide()
        fn()
    end
end)
local function schedule(delay, fn)
    timerCb = { delay = delay, fn = fn }
    timerElapsed = 0
    timerFrame:Show()
end
local function cancelTimer()
    timerCb = nil
    timerElapsed = 0
    timerFrame:Hide()
end

local function ahOpen()
    return AuctionFrame and AuctionFrame:IsShown()
end

local errorListenerActive = false
-- Server error listener: capture UI errors during a buy session to mark
-- failures. Stays silent on success — the only chat output comes from the
-- result row updates.
local errorFrame = CreateFrame("Frame")
errorFrame:RegisterEvent("UI_ERROR_MESSAGE")
errorFrame:RegisterEvent("CHAT_MSG_SYSTEM")
errorFrame:SetScript("OnEvent", function(_, ev, msg)
    if not errorListenerActive then return end
    if ev == "UI_ERROR_MESSAGE" then
        state.lastError = msg
    elseif ev == "CHAT_MSG_SYSTEM" and msg then
        local lower = msg:lower()
        if lower:find("ui error") or lower:find("erreur") then
            state.lastError = msg
        end
    end
end)

local function getRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, listContent)
    r:SetSize(INNER_W, ROW_H)
    r:SetPoint("TOPLEFT", 0, -((i - 1) * (ROW_H + 1)))

    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0, 0, 0, 0)
    r.bg = bg

    local cb = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("LEFT", 2, 0)
    r.cb = cb

    local status = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    status:SetPoint("LEFT", 6, 0)
    status:SetWidth(20)
    status:SetJustifyH("CENTER")
    status:Hide()
    r.status = status

    local count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    count:SetWidth(28)
    count:SetJustifyH("LEFT")
    r.count = count

    local unit = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unit:SetPoint("LEFT", count, "RIGHT", 4, 0)
    unit:SetWidth(72)
    unit:SetJustifyH("RIGHT")
    r.unit = unit

    local total = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    total:SetPoint("LEFT", unit, "RIGHT", 4, 0)
    total:SetWidth(72)
    total:SetJustifyH("RIGHT")
    r.total = total

    local seller = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    seller:SetPoint("LEFT", total, "RIGHT", 4, 0)
    seller:SetWidth(60)
    seller:SetJustifyH("LEFT")
    r.seller = seller

    rows[i] = r
    return r
end

local function clearRows()
    for _, r in pairs(rows) do
        r:Hide()
        if r.cb then r.cb:SetChecked(false) end
        if r.status then r.status:Hide() end
        if r.bg then r.bg:SetTexture(0, 0, 0, 0) end
    end
end

-- Forward declarations: these are defined further down but referenced
-- inside earlier closures (e.g. checkbox OnClick handlers).
local updateBuyButton
local renderRows
local rescanForQueue

-- Cache-bust: Ascension caches QueryAuctionItems results per name. Re-querying
-- the same name shortly after returns the same (stale) list. Sending a dummy
-- query for a name that matches nothing invalidates the cache, then the real
-- query returns fresh data.
local cacheBustFrame = CreateFrame("Frame")
local cacheBustCallback
cacheBustFrame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
cacheBustFrame:SetScript("OnEvent", function()
    if not cacheBustCallback then return end
    local cb = cacheBustCallback
    cacheBustCallback = nil
    cb()
end)

local function bustAndThen(callback)
    if not ahOpen() then return end
    if not CanSendAuctionQuery() then
        schedule(0.25, function() bustAndThen(callback) end)
        return
    end
    cacheBustCallback = function()
        -- Give the AH throttle a moment to clear before the real query
        local function tryRun()
            if not ahOpen() then return end
            if not CanSendAuctionQuery() then
                schedule(0.25, tryRun)
                return
            end
            callback()
        end
        schedule(0.4, tryRun)
    end
    QueryAuctionItems("zzIronBust", "", "", nil, nil, nil, 0, nil, -1)
end

local function selectedTotal()
    local count = 0
    local gold = 0
    for idx, on in pairs(state.selected) do
        if on then
            local a = state.results[idx]
            if a then
                count = count + (a.count or 0)
                gold = gold + (a.buyoutRaw or 0)
            end
        end
    end
    return count, gold
end

local function updateFooter()
    if state.mode == "queue" then
        local pending, bought, failed = 0, 0, 0
        for _, e in ipairs(state.queue or {}) do
            if e.status == "pending" then pending = pending + 1
            elseif e.status == "bought" then bought = bought + 1
            elseif e.status == "failed" then failed = failed + 1 end
        end
        footerFs:SetText(string.format(IR.L["Bought: %d / Failed: %d / Pending: %d"],
            bought, failed, pending))
        return
    end
    local count, gold = selectedTotal()
    footerFs:SetText(string.format(IR.L["Selected: %d for %s"],
        count, IR:CopperToString(gold)))
end

local function renderRowsBrowse()
    clearRows()
    local n = #state.results
    listContent:SetHeight(math.max(n * (ROW_H + 1), 1))
    for i, a in ipairs(state.results) do
        local r = getRow(i)
        r.cb:Show()
        if r.status then r.status:Hide() end
        r.count:SetText("x" .. (a.count or 0))
        local unitPrice = (a.buyoutRaw or 0) / math.max(1, a.count or 1)
        r.unit:SetText(IR:CopperToString(math.floor(unitPrice)))
        r.total:SetText(IR:CopperToString(a.buyoutRaw or 0))
        local seller = a.owner or "?"
        if #seller > 9 then seller = seller:sub(1, 8) .. "..." end
        r.seller:SetText(seller)
        r.cb:SetChecked(state.selected[i] and true or false)
        local capturedI = i
        r.cb:SetScript("OnClick", function(self)
            state.selected[capturedI] = self:GetChecked() and true or nil
            updateFooter()
            updateBuyButton()
        end)
        r:Show()
    end
end

local function renderRowsQueue()
    clearRows()
    local q = state.queue or {}
    listContent:SetHeight(math.max(#q * (ROW_H + 1), 1))

    local firstPending
    for i, e in ipairs(q) do
        if e.status == "pending" then firstPending = firstPending or i end
    end

    for i, e in ipairs(q) do
        local r = getRow(i)
        r.cb:Hide()
        if r.status then r.status:Show() end
        local sig = e.sig
        r.count:SetText("x" .. (sig.count or 0))
        r.unit:SetText(IR:CopperToString(math.floor(sig.unit or 0)))
        r.total:SetText(IR:CopperToString(sig.buyoutRaw or 0))
        local seller = sig.owner or "?"
        if #seller > 9 then seller = seller:sub(1, 8) .. "..." end
        r.seller:SetText(seller)

        if e.status == "pending" then
            if i == firstPending then
                r.bg:SetTexture(0.95, 0.85, 0.2, 0.18)
                r.status:SetText(">")
                r.status:SetTextColor(1, 0.9, 0.2, 1)
            else
                r.bg:SetTexture(0, 0, 0, 0)
                r.status:SetText("-")
                r.status:SetTextColor(0.55, 0.55, 0.55, 1)
            end
        elseif e.status == "bought" then
            r.bg:SetTexture(0.2, 0.7, 0.2, 0.15)
            r.status:SetText("v")
            r.status:SetTextColor(0.3, 0.95, 0.3, 1)
        elseif e.status == "failed" then
            r.bg:SetTexture(0.85, 0.25, 0.25, 0.15)
            r.status:SetText("x")
            r.status:SetTextColor(1, 0.4, 0.4, 1)
        end
        r:Show()
    end
end

renderRows = function()
    if state.mode == "queue" then
        renderRowsQueue()
    else
        renderRowsBrowse()
    end
end

-- Selection strategies. All work on state.results sorted by unit price asc.
-- "more": current behavior, take cheapest until cum >= target (may overshoot)
-- "less": take cheapest without overshooting (stop at first one that exceeds)
-- "exact": minimize total cost s.t. sum of counts == target (DP, knapsack)

local function autoSelectMore()
    state.selected = {}
    local target = state.neededQty or 0
    if target < 1 then target = 1 end
    local total = 0
    for i, a in ipairs(state.results) do
        if total >= target then break end
        state.selected[i] = true
        total = total + (a.count or 0)
    end
    if #state.results > 0 and total < target then
        statusFs:SetText(string.format(IR.L["Only %d available"], total))
        statusFs:SetTextColor(1, 0.6, 0.2, 1)
    end
end

local function autoSelectLess()
    state.selected = {}
    local target = state.neededQty or 0
    if target < 1 then return end
    local total = 0
    for i, a in ipairs(state.results) do
        local c = a.count or 0
        if total + c > target then break end
        state.selected[i] = true
        total = total + c
    end
end

local function autoSelectExact()
    state.selected = {}
    local target = state.neededQty or 0
    if target < 1 then return end
    local n = #state.results
    if n == 0 then return end

    local INF = math.huge

    -- dp[i][k] = min total cost using first i auctions to make exactly k items.
    -- 2D for straightforward reconstruction.
    local dp = {}
    for i = 0, n do
        dp[i] = {}
        for k = 0, target do dp[i][k] = INF end
        dp[i][0] = 0
    end

    for i = 1, n do
        local a = state.results[i]
        local c = a.count or 0
        local b = a.buyoutRaw or 0
        for k = 0, target do
            dp[i][k] = dp[i - 1][k]
            if k >= c and dp[i - 1][k - c] + b < dp[i][k] then
                dp[i][k] = dp[i - 1][k - c] + b
            end
        end
    end

    if dp[n][target] == INF then
        if statusFs then
            statusFs:SetText(IR.L["No exact match for %d"]:format(target))
            statusFs:SetTextColor(1, 0.6, 0.2, 1)
        end
        return
    end

    local k = target
    for i = n, 1, -1 do
        if dp[i][k] ~= dp[i - 1][k] then
            state.selected[i] = true
            k = k - (state.results[i].count or 0)
        end
    end
end

local function autoSelect()
    -- Reset status to the post-scan baseline so a stale warning from a
    -- previous strategy/qty call ("No exact match", "Only N available") does
    -- not stick when the new selection succeeds.
    if statusFs then
        statusFs:SetText(string.format(IR.L["%d auctions found"], #state.results))
        statusFs:SetTextColor(0.7, 0.7, 0.7, 1)
    end
    local strategy = state.selectStrategy or "more"
    if strategy == "less" then
        autoSelectLess()
    elseif strategy == "exact" then
        autoSelectExact()
    else
        autoSelectMore()
    end
end

local function startScan()
    if state.scanning or not state.itemID then return end
    state.scanning = true
    state.results = {}
    state.selected = {}
    clearRows()
    statusFs:SetText(IR.L["Scanning..."])
    statusFs:SetTextColor(0.7, 0.7, 0.7, 1)

    if not IR.Scanner then
        state.scanning = false
        return
    end
    IR:Debug(string.format("BuyAuctionList scan start itemID=%d link=%s",
        state.itemID, tostring(state.link)))
    local ok = IR.Scanner:Start({ state.itemID }, {
        silent = true,
        singlePage = true,
        onComplete = function(results, reason)
            state.scanning = false
            if reason == "ah_closed" or reason == "aborted" then
                statusFs:SetText(IR.L["Scan interrupted"])
                statusFs:SetTextColor(1, 0.6, 0.2, 1)
                return
            end
            local filtered = {}
            local playerName = UnitName("player")
            for _, a in ipairs(results or {}) do
                if a.itemID == state.itemID and a.count and a.count > 0
                   and a.buyoutRaw and a.buyoutRaw > 0
                   and a.owner ~= playerName then
                    table.insert(filtered, a)
                end
            end
            table.sort(filtered, function(a, b)
                local ua = (a.buyoutRaw or 0) / math.max(1, a.count or 1)
                local ub = (b.buyoutRaw or 0) / math.max(1, b.count or 1)
                return ua < ub
            end)
            state.results = filtered
            IR:Debug(string.format("BuyAuctionList scan done: %d auctions for itemID %d",
                #filtered, state.itemID))
            statusFs:SetTextColor(0.7, 0.7, 0.7, 1)
            statusFs:SetText(string.format(IR.L["%d auctions found"], #filtered))
            autoSelect()
            renderRows()
            updateFooter()
            updateBuyButton()
            if state.onScanDone then
                local ok, err = pcall(state.onScanDone)
                if not ok then IR:Print("|cffff5555buy onScanDone error|r: " .. tostring(err)) end
            end
        end,
    })
    if not ok then
        state.scanning = false
        statusFs:SetText(IR.L["Scanner busy, try again"])
        statusFs:SetTextColor(1, 0.4, 0.4, 1)
        updateBuyButton()
    end
end

local function findBySignature(sig)
    for _, a in ipairs(state.results) do
        if a.count == sig.count and a.buyoutRaw == sig.buyoutRaw and a.owner == sig.owner then
            return a
        end
    end
    return nil
end

local function queueStats()
    local pending, bought, failed = 0, 0, 0
    for _, e in ipairs(state.queue or {}) do
        if e.status == "pending" then pending = pending + 1
        elseif e.status == "bought" then bought = bought + 1
        elseif e.status == "failed" then failed = failed + 1 end
    end
    return pending, bought, failed
end

updateBuyButton = function()
    if not buyBtn then return end
    if state.mode == "browse" then
        local count = selectedTotal()
        buyBtn:SetText(IR.L["Buy Selected"])
        if count > 0 and ahOpen() and not state.processing and not state.scanning then
            buyBtn:Enable()
        else
            buyBtn:Disable()
        end
    else
        local pending, bought, failed = queueStats()
        local total = #(state.queue or {})
        if pending == 0 then
            buyBtn:SetText(IR.L["Done"])
            buyBtn:Enable()
        else
            buyBtn:SetText(string.format(IR.L["Buy Next (%d/%d)"], bought + failed + 1, total))
            if state.processing or state.scanning or not ahOpen() then
                buyBtn:Disable()
            else
                buyBtn:Enable()
            end
        end
    end
end

rescanForQueue = function()
    if state.scanning then return end
    if not ahOpen() then return end
    state.scanning = true
    state.results = {}
    if statusFs then
        statusFs:SetText(IR.L["Refreshing..."])
        statusFs:SetTextColor(0.7, 0.7, 0.7, 1)
    end
    updateBuyButton()

    bustAndThen(function()
        if not ahOpen() then state.scanning = false; return end
        local ok = IR.Scanner:Start({ state.itemID }, {
            silent = true,
            singlePage = true,
            onComplete = function(results, reason)
            state.scanning = false
            if reason == "ah_closed" or reason == "aborted" then
                if statusFs then statusFs:SetText(IR.L["Scan interrupted"]) end
                updateBuyButton()
                return
            end
            local filtered = {}
            local playerName = UnitName("player")
            for _, x in ipairs(results or {}) do
                if x.itemID == state.itemID and x.count and x.count > 0
                   and x.buyoutRaw and x.buyoutRaw > 0
                   and x.owner ~= playerName then
                    table.insert(filtered, x)
                end
            end
            table.sort(filtered, function(a, b)
                local ua = (a.buyoutRaw or 0) / math.max(1, a.count or 1)
                local ub = (b.buyoutRaw or 0) / math.max(1, b.count or 1)
                return ua < ub
            end)
            state.results = filtered
            if statusFs then
                statusFs:SetText(string.format(IR.L["%d auctions found"], #filtered))
            end
            updateBuyButton()
        end,
        })
        if not ok then
            state.scanning = false
            if statusFs then statusFs:SetText(IR.L["Scanner busy, try again"]) end
            updateBuyButton()
        end
    end)
end

local function enterQueueMode()
    if state.mode == "queue" then return end

    local sigList = {}
    for idx, on in pairs(state.selected) do
        if on then
            local a = state.results[idx]
            if a then
                table.insert(sigList, {
                    count = a.count,
                    buyoutRaw = a.buyoutRaw,
                    owner = a.owner,
                    unit = (a.buyoutRaw or 0) / math.max(1, a.count or 1),
                })
            end
        end
    end
    if #sigList == 0 then return end

    table.sort(sigList, function(a, b) return a.unit < b.unit end)

    state.queue = {}
    for _, sig in ipairs(sigList) do
        table.insert(state.queue, { sig = sig, status = "pending" })
    end
    state.mode = "queue"
    errorListenerActive = true

    local total = #state.queue
    local sumGold = 0
    for _, e in ipairs(state.queue) do sumGold = sumGold + (e.sig.buyoutRaw or 0) end
    if statusFs then
        statusFs:SetText(string.format(IR.L["Queued %d auctions for %s"],
            total, IR:CopperToString(sumGold)))
        statusFs:SetTextColor(0.8, 0.8, 1, 1)
    end

    IR:Debug(string.format("enterQueueMode: %d auctions queued, total %s",
        total, IR:CopperToString(sumGold)))

    renderRows()
    updateBuyButton()
end

local function exitQueueMode()
    state.mode = "browse"
    state.queue = nil
    state.processing = false
    state.selected = {}
    errorListenerActive = false
    -- Refresh from server
    state.results = {}
    if statusFs then
        statusFs:SetText(IR.L["Refreshing..."])
        statusFs:SetTextColor(0.7, 0.7, 0.7, 1)
    end
    renderRows()
    updateBuyButton()
    if not state.scanning and ahOpen() then
        state.scanning = true
        bustAndThen(function()
            if not ahOpen() then state.scanning = false; return end
            if not IR.Scanner then state.scanning = false; return end
            IR.Scanner:Start({ state.itemID }, {
                silent = true,
                singlePage = true,
                onComplete = function(results, reason)
                    state.scanning = false
                    if reason == "ah_closed" or reason == "aborted" then
                        if statusFs then statusFs:SetText(IR.L["Scan interrupted"]) end
                        updateBuyButton()
                        return
                    end
                    local filtered = {}
                    local playerName = UnitName("player")
                    for _, x in ipairs(results or {}) do
                        if x.itemID == state.itemID and x.count and x.count > 0
                           and x.buyoutRaw and x.buyoutRaw > 0
                           and x.owner ~= playerName then
                            table.insert(filtered, x)
                        end
                    end
                    table.sort(filtered, function(a, b)
                        local ua = (a.buyoutRaw or 0) / math.max(1, a.count or 1)
                        local ub = (b.buyoutRaw or 0) / math.max(1, b.count or 1)
                        return ua < ub
                    end)
                    state.results = filtered
                    if statusFs then
                        statusFs:SetText(string.format(IR.L["%d auctions found"], #filtered))
                    end
                    autoSelect()
                    renderRows()
                    updateFooter()
                    updateBuyButton()
                end,
            })
        end)
    end
end

local function processOneBuy()
    if state.processing then return end
    if state.mode ~= "queue" then return end
    if not ahOpen() then
        IR:Print(IR.L["Auction House not open"])
        return
    end

    -- find first pending
    local idx
    for i, e in ipairs(state.queue or {}) do
        if e.status == "pending" then idx = i; break end
    end
    if not idx then return end

    local entry = state.queue[idx]
    local target = findBySignature(entry.sig)
    if not target then
        IR:Debug(string.format("processOneBuy: signature owner=%s count=%d buyout=%s NOT FOUND, marking failed",
            tostring(entry.sig.owner), entry.sig.count or 0,
            IR:CopperToString(entry.sig.buyoutRaw or 0)))
        entry.status = "failed"
        renderRows()
        updateFooter()
        updateBuyButton()
        rescanForQueue()
        return
    end

    if (GetMoney() or 0) < target.buyoutRaw then
        IR:Print(string.format(IR.L["Not enough gold (need %s, have %s)"],
            IR:CopperToString(target.buyoutRaw), IR:CopperToString(GetMoney() or 0)))
        return
    end

    state.processing = true
    state.lastError = nil
    IR:Debug(string.format("PlaceAuctionBid listIndex=%d count=%d buyout=%s owner=%s",
        target.listIndex, target.count or 0, IR:CopperToString(target.buyoutRaw),
        tostring(target.owner)))
    PlaceAuctionBid("list", target.listIndex, target.buyoutRaw)
    updateBuyButton()

    schedule(BUY_DELAY, function()
        if state.lastError then
            entry.status = "failed"
            IR:Debug(string.format("    sig owner=%s marked FAILED: %s",
                tostring(entry.sig.owner), tostring(state.lastError)))
        else
            entry.status = "bought"
            IR:Debug(string.format("    sig owner=%s marked BOUGHT", tostring(entry.sig.owner)))
        end
        state.processing = false
        renderRows()
        updateFooter()
        updateBuyButton()
        -- Refresh AH list in background so the next click has fresh listIndex data
        rescanForQueue()
    end)
end

local function onBuyButtonClick()
    if state.processing then return end
    if state.mode == "browse" then
        if not ahOpen() then
            IR:Print(IR.L["Auction House not open"])
            return
        end
        local count, gold = selectedTotal()
        if count == 0 then return end
        if (GetMoney() or 0) < gold then
            IR:Print(string.format(IR.L["Not enough gold (need %s, have %s)"],
                IR:CopperToString(gold), IR:CopperToString(GetMoney() or 0)))
            return
        end
        enterQueueMode()
    else
        local pending = queueStats()
        if pending == 0 then
            exitQueueMode()
        else
            processOneBuy()
        end
    end
end

local function buildFrame()
    if frame then return end
    frame = CreateFrame("Frame", "IronBuyAuctionFrame", UIParent)
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
    drag:SetPoint("TOPRIGHT", -32, -8)
    drag:SetHeight(20)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    titleFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOP", 0, -14)
    titleFs:SetWidth(FRAME_W - 50)
    titleFs:SetJustifyH("CENTER")
    titleFs:SetText("")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() BuyAuctionList:Close() end)

    statusFs = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusFs:SetPoint("TOPLEFT", 14, -38)
    statusFs:SetText("")

    local qtyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyLabel:SetPoint("TOPLEFT", 14, -60)
    qtyLabel:SetText(IR.L["Qty:"])

    qtyEdit = CreateFrame("EditBox", nil, frame)
    qtyEdit:SetSize(50, 22)
    qtyEdit:SetPoint("LEFT", qtyLabel, "RIGHT", 4, 0)
    qtyEdit:SetAutoFocus(false)
    qtyEdit:SetNumeric(true)
    qtyEdit:SetMaxLetters(5)
    qtyEdit:SetFontObject("ChatFontNormal")
    qtyEdit:SetTextInsets(4, 4, 0, 0)
    qtyEdit:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    qtyEdit:SetBackdropColor(0, 0, 0, 0.5)
    qtyEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local function applyQtyLive()
        if state.mode == "queue" then return end
        local v = tonumber(qtyEdit:GetText())
        if not v or v < 1 then return end
        if v > 9999 then
            v = 9999
            qtyEdit:SetText("9999")
            qtyEdit:SetCursorPosition(4)
        end
        state.neededQty = v
        autoSelect()
        renderRows()
        updateFooter()
        updateBuyButton()
    end

    local function ensureMinQty()
        local v = tonumber(qtyEdit:GetText())
        if not v or v < 1 then
            qtyEdit:SetText("1")
            state.neededQty = 1
            autoSelect()
            renderRows()
            updateFooter()
            updateBuyButton()
        end
    end

    qtyEdit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then applyQtyLive() end
    end)
    qtyEdit:SetScript("OnEditFocusLost", ensureMinQty)
    qtyEdit:SetScript("OnEnterPressed", function(self)
        ensureMinQty()
        self:ClearFocus()
    end)

    -- Strategy buttons: less / exact / more
    local function makeStrategyBtn(key, label, anchorTo, anchorOffset, tooltip)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(28, 22)
        b:SetPoint("LEFT", anchorTo, "RIGHT", anchorOffset, 0)
        b:SetText(label)
        b:SetScript("OnClick", function()
            if state.mode == "queue" then return end
            state.selectStrategy = key
            applyStrategyButtons()
            autoSelect()
            renderRows()
            updateFooter()
            updateBuyButton()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        strategyBtns[key] = b
        return b
    end
    local lessBtn = makeStrategyBtn("less", "<", qtyEdit, 6, IR.L["Less: cheapest without exceeding"])
    local exactBtn = makeStrategyBtn("exact", "=", lessBtn, 2, IR.L["Exact: cheapest combo summing to target"])
    makeStrategyBtn("more", ">", exactBtn, 2, IR.L["More: cheapest until target reached (may overshoot)"])

    refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(110, 22)
    refreshBtn:SetPoint("TOPRIGHT", -16, -56)
    refreshBtn:SetText(IR.L["Refresh listings"])
    refreshBtn:SetScript("OnClick", function()
        if state.mode == "queue" then
            rescanForQueue()
        else
            startScan()
        end
    end)
    IR:AttachTooltip(refreshBtn, IR.L["Re-scan AH for fresh listings"])

    local headerBg = frame:CreateTexture(nil, "BACKGROUND")
    headerBg:SetPoint("TOPLEFT", 14, -90)
    headerBg:SetPoint("TOPRIGHT", -14, -90)
    headerBg:SetHeight(18)
    headerBg:SetTexture(0.1, 0.1, 0.1, 0.6)

    local hCount = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hCount:SetPoint("TOPLEFT", 40, -92)
    hCount:SetText(IR.L["Qty"])
    hCount:SetWidth(28)
    hCount:SetJustifyH("LEFT")

    local hUnit = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hUnit:SetPoint("TOPLEFT", 72, -92)
    hUnit:SetText(IR.L["Unit"])
    hUnit:SetWidth(72)
    hUnit:SetJustifyH("RIGHT")

    local hTotal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hTotal:SetPoint("TOPLEFT", 148, -92)
    hTotal:SetText(IR.L["Total"])
    hTotal:SetWidth(72)
    hTotal:SetJustifyH("RIGHT")

    local hSeller = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hSeller:SetPoint("TOPLEFT", 224, -92)
    hSeller:SetText(IR.L["Seller"])
    hSeller:SetWidth(60)
    hSeller:SetJustifyH("LEFT")

    listScroll = CreateFrame("ScrollFrame", "IronBuyAuctionScroll", frame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 14, -110)
    listScroll:SetPoint("BOTTOMRIGHT", -32, 60)

    listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(INNER_W, 1)
    listScroll:SetScrollChild(listContent)

    footerFs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    footerFs:SetPoint("BOTTOMLEFT", 16, 18)
    footerFs:SetPoint("BOTTOMRIGHT", -130, 18)
    footerFs:SetJustifyH("LEFT")
    footerFs:SetText("")

    buyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    buyBtn:SetSize(110, 28)
    buyBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    buyBtn:SetText(IR.L["Buy Selected"])
    buyBtn:Disable()
    buyBtn:SetScript("OnClick", onBuyButtonClick)
    IR:AttachTooltip(buyBtn, IR.L["Buy: each click processes one auction (Ascension safety)"])

    tinsert(UISpecialFrames, "IronBuyAuctionFrame")
end

local function anchorFrame()
    local main = IR.UI.AHCompanion and IR.UI.AHCompanion:GetMainFrame()
    frame:ClearAllPoints()
    if main and main:IsShown() then
        frame:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 400, 0)
    end
end

function BuyAuctionList:Open(itemID, link, neededQty, opts)
    if not itemID then return end
    buildFrame()
    state.itemID = itemID
    state.link = link
    state.neededQty = (neededQty and neededQty > 0) and neededQty or 20
    state.results = {}
    state.selected = {}
    state.queue = nil
    state.processing = false
    state.mode = "browse"
    state.onScanDone = opts and opts.onScanDone or nil

    local s = Iron_DB and Iron_DB.settings and Iron_DB.settings.ironBuy
    local def = (s and s.defaultSelectStrategy) or "more"
    if def ~= "less" and def ~= "exact" and def ~= "more" then def = "more" end
    state.selectStrategy = def
    applyStrategyButtons()

    titleFs:SetText(link or ("Item #" .. itemID))
    qtyEdit:SetText(tostring(state.neededQty))
    statusFs:SetText("")
    clearRows()
    listContent:SetHeight(1)
    updateFooter()
    updateBuyButton()

    anchorFrame()
    frame:Show()

    startScan()
end

function BuyAuctionList:Close()
    state.processing = false
    errorListenerActive = false
    cancelTimer()
    state.queue = nil
    state.mode = "browse"
    state.itemID = nil
    state.link = nil
    state.results = {}
    state.selected = {}
    if frame then frame:Hide() end
end

function BuyAuctionList:IsShown()
    return frame and frame:IsShown()
end

IR:On("AUCTION_HOUSE_CLOSED", function() BuyAuctionList:Close() end)
