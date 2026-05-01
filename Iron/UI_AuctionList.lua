-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.UI = IR.UI or {}
IR.UI.AuctionList = {}
local AuctionList = IR.UI.AuctionList

local FRAME_W = 320
local FRAME_H = 540
local ROW_H = 26
local INNER_W = FRAME_W - 32

local frame, listScroll, listContent, statusFs, titleFs
local rows = {}
local currentItemID

local function ensureFrame()
    if frame then return end

    frame = CreateFrame("Frame", "IronAuctionListFrame", UIParent)
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
    titleFs:SetWidth(FRAME_W - 40)
    titleFs:SetJustifyH("CENTER")
    titleFs:SetText("")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        if AuctionList.onCloseHandler then
            local h = AuctionList.onCloseHandler
            AuctionList.onCloseHandler = nil
            h()
        else
            AuctionList:Close()
        end
    end)

    statusFs = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusFs:SetPoint("TOPLEFT", 14, -38)
    statusFs:SetText("")

    local headerBg = frame:CreateTexture(nil, "BACKGROUND")
    headerBg:SetPoint("TOPLEFT", 14, -54)
    headerBg:SetPoint("TOPRIGHT", -14, -54)
    headerBg:SetHeight(18)
    headerBg:SetTexture(0.1, 0.1, 0.1, 0.6)

    local hCount = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hCount:SetPoint("TOPLEFT", 18, -56)
    hCount:SetText(IR.L["Qty"])
    hCount:SetWidth(36)
    hCount:SetJustifyH("LEFT")

    local hUnit = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hUnit:SetPoint("TOPLEFT", 56, -56)
    hUnit:SetText(IR.L["Unit"])
    hUnit:SetWidth(78)
    hUnit:SetJustifyH("RIGHT")

    local hTotal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hTotal:SetPoint("TOPLEFT", 138, -56)
    hTotal:SetText(IR.L["Buyout"])
    hTotal:SetWidth(82)
    hTotal:SetJustifyH("RIGHT")

    local hOwner = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hOwner:SetPoint("TOPLEFT", 224, -56)
    hOwner:SetText(IR.L["Seller"])
    hOwner:SetWidth(72)
    hOwner:SetJustifyH("LEFT")

    listScroll = CreateFrame("ScrollFrame", "IronAuctionListScroll", frame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 14, -76)
    listScroll:SetPoint("BOTTOMRIGHT", -32, 14)

    listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(INNER_W, 1)
    listScroll:SetScrollChild(listContent)

    tinsert(UISpecialFrames, "IronAuctionListFrame")
end

local function getRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, listContent)
    r:SetSize(INNER_W, ROW_H)
    r:SetPoint("TOPLEFT", 0, -((i - 1) * (ROW_H + 1)))

    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.4, 0.8, 0.4, 0.18)
    bg:Hide()
    r.bg = bg

    local count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("LEFT", 4, 0)
    count:SetWidth(36)
    count:SetJustifyH("LEFT")
    r.count = count

    local unit = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unit:SetPoint("LEFT", 42, 0)
    unit:SetWidth(78)
    unit:SetJustifyH("RIGHT")
    r.unit = unit

    local total = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    total:SetPoint("LEFT", 124, 0)
    total:SetWidth(82)
    total:SetJustifyH("RIGHT")
    r.total = total

    local owner = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    owner:SetPoint("LEFT", 210, 0)
    owner:SetWidth(72)
    owner:SetJustifyH("LEFT")
    r.owner = owner

    rows[i] = r
    return r
end

local function clearRows()
    for _, r in pairs(rows) do
        r:Hide()
        if r.bg then r.bg:Hide() end
    end
end

local function populate(itemID, results)
    if itemID ~= currentItemID then return end
    clearRows()

    local items = {}
    for _, r in ipairs(results or {}) do
        if r.itemID == itemID and r.count and r.count > 0 then
            local unitPrice = r.buyout / r.count
            table.insert(items, {
                count = r.count,
                buyout = r.buyout,
                buyoutRaw = r.buyoutRaw,
                minBid = r.minBid,
                owner = r.owner,
                unit = unitPrice,
            })
        end
    end
    table.sort(items, function(a, b) return a.unit < b.unit end)

    statusFs:SetText(string.format(IR.L["%d auctions sorted by unit price"], #items))
    listContent:SetHeight(math.max(#items * (ROW_H + 1), 1))

    for i, item in ipairs(items) do
        local row = getRow(i)
        row.count:SetText("x" .. item.count)
        row.unit:SetText(IR:CopperToString(math.floor(item.unit)))
        row.total:SetText(IR:CopperToString(item.buyout))
        local ownerText = item.owner or "?"
        if #ownerText > 11 then ownerText = ownerText:sub(1, 10) .. "..." end
        row.owner:SetText(ownerText)
        if i == 1 then
            row.bg:Show()
        else
            row.bg:Hide()
        end
        row:Show()
    end
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

function AuctionList:Open(itemID, link, onScanDone, opts)
    if not itemID then return end
    ensureFrame()
    currentItemID = itemID
    AuctionList.onCloseHandler = opts and opts.onClose or nil

    titleFs:SetText(link or ("Item #" .. itemID))
    statusFs:SetText(IR.L["Scanning..."])
    clearRows()
    listContent:SetHeight(1)

    anchorFrame()
    frame:Show()

    if IR.Scanner then
        local ok = IR.Scanner:Start({ itemID }, {
            silent = true,
            onComplete = function(results, reason)
                if reason == "ah_closed" or reason == "aborted" then
                    if onScanDone then pcall(onScanDone, nil) end
                    return
                end
                populate(itemID, results)
                if onScanDone then
                    local cbOk, err = pcall(onScanDone, results)
                    if not cbOk then IR:Print("|cffff5555auction list callback error|r: " .. tostring(err)) end
                end
            end,
        })
        if not ok then
            statusFs:SetText(IR.L["Scanner busy, try again"])
            if onScanDone then pcall(onScanDone, nil) end
        end
    end
end

function AuctionList:Close()
    currentItemID = nil
    AuctionList.onCloseHandler = nil
    if frame then frame:Hide() end
end

function AuctionList:IsShown()
    return frame and frame:IsShown()
end

IR:On("AUCTION_HOUSE_CLOSED", function() AuctionList:Close() end)
