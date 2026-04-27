-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.PriceDB = {}
local PriceDB = IR.PriceDB

local MAX_SCANS_PER_ITEM = 10
local RETENTION_SECONDS = 14 * 86400

local function db()
    return Iron_DB
end

function PriceDB:RecordScan(auctions)
    if not auctions or #auctions == 0 then return 0 end
    local now = time()
    local byItem = {}

    for _, a in ipairs(auctions) do
        if a.itemID and a.count and a.count > 0 and a.buyout and a.buyout > 0 then
            local unit = a.buyout / a.count
            byItem[a.itemID] = byItem[a.itemID] or {}
            table.insert(byItem[a.itemID], { count = a.count, unit = unit })
        end
    end

    local d = db()
    if not d then return 0 end
    d.prices = d.prices or {}

    local itemsRecorded = 0
    for itemID, listings in pairs(byItem) do
        table.sort(listings, function(a, b) return a.unit < b.unit end)
        local n = #listings

        local _, _, _, _, _, _, _, maxStack = GetItemInfo(itemID)
        if not maxStack or maxStack < 1 then maxStack = 1 end

        local taken = 0
        local totalCost = 0
        for _, l in ipairs(listings) do
            if taken >= maxStack then break end
            local takeNow = math.min(l.count, maxStack - taken)
            totalCost = totalCost + l.unit * takeNow
            taken = taken + takeNow
        end
        local marketValue = (taken > 0) and math.floor(totalCost / taken) or 0
        local lowest = math.floor(listings[1].unit)

        IR:Debug(string.format("PriceDB %d: %d listings, taken=%d, market=%d, lowest=%d",
            itemID, n, taken, marketValue, lowest))

        d.prices[itemID] = d.prices[itemID] or { scans = {} }
        local entry = d.prices[itemID]
        entry.scans = entry.scans or {}
        table.insert(entry.scans, { t = now, m = marketValue, lo = lowest, n = n })
        entry.lastUpdate = now

        while #entry.scans > MAX_SCANS_PER_ITEM do
            table.remove(entry.scans, 1)
        end
        itemsRecorded = itemsRecorded + 1
    end

    d.lastFullScan = now
    return itemsRecorded
end

function PriceDB:GetMarketValue(itemID)
    local d = db()
    if not d or not d.prices then return nil end
    local entry = d.prices[itemID]
    if not entry or not entry.scans or #entry.scans == 0 then return nil end
    local latest = entry.scans[#entry.scans]
    return latest and latest.m
end

function PriceDB:GetLowestSeen(itemID)
    local d = db()
    if not d or not d.prices then return nil end
    local entry = d.prices[itemID]
    if not entry or not entry.scans then return nil end
    local lowest
    for _, scan in ipairs(entry.scans) do
        if scan.lo and (not lowest or scan.lo < lowest) then
            lowest = scan.lo
        end
    end
    return lowest
end

function PriceDB:GetLowestNow(itemID)
    local d = db()
    if not d or not d.prices then return nil end
    local entry = d.prices[itemID]
    if not entry or not entry.scans or #entry.scans == 0 then return nil end
    local latest = entry.scans[#entry.scans]
    return latest and latest.lo
end

function PriceDB:GetLastUpdate(itemID)
    local d = db()
    if not d or not d.prices then return nil end
    local entry = d.prices[itemID]
    return entry and entry.lastUpdate
end

function PriceDB:GetLastFullScan()
    local d = db()
    return (d and d.lastFullScan) or 0
end

function PriceDB:GarbageCollect()
    local d = db()
    if not d or not d.prices then return 0 end
    local cutoff = time() - RETENTION_SECONDS
    local removed = 0
    for itemID, entry in pairs(d.prices) do
        if entry.scans then
            local kept = {}
            for _, scan in ipairs(entry.scans) do
                if scan.t and scan.t >= cutoff then
                    table.insert(kept, scan)
                else
                    removed = removed + 1
                end
            end
            entry.scans = kept
            if #entry.scans == 0 then
                d.prices[itemID] = nil
            end
        end
    end
    return removed
end

function PriceDB:Stats()
    local d = db()
    if not d or not d.prices then return { items = 0, scans = 0, lastFullScan = 0 } end
    local items, scans = 0, 0
    for _, entry in pairs(d.prices) do
        items = items + 1
        if entry.scans then scans = scans + #entry.scans end
    end
    return { items = items, scans = scans, lastFullScan = d.lastFullScan or 0 }
end

IR:On("PLAYER_LOGIN", function()
    local removed = PriceDB:GarbageCollect()
    if removed > 0 then
        IR:Debug(string.format("PriceDB GC: %d expired scans removed", removed))
    end
end)
