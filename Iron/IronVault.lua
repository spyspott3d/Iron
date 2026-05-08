-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.IronVault = {}
local IronVault = IR.IronVault

local function settings()
    return Iron_DB and Iron_DB.settings and Iron_DB.settings.ironVault
end

local function vaultData()
    -- Per-character bucket holding groups + nextGroupID. Other ironVault
    -- preferences (autoOpenOnBankShow, showSurplusWarning) stay account-wide
    -- in settings().
    local c = IR and IR.CharDB and IR:CharDB()
    return c and c.vault or nil
end

function IronVault:GetGroupsTable()
    local v = vaultData()
    return (v and v.groups) or {}
end

function IronVault:GetGroups()
    return self:GetGroupsTable()
end

function IronVault:GetGroup(id)
    local v = vaultData()
    if not v or not id then return nil end
    return v.groups[id]
end

function IronVault:CreateGroup(name, direction)
    local v = vaultData()
    if not v then return nil end
    name = name and name:match("^%s*(.-)%s*$") or ""
    if name == "" then name = IR.L["New Group"] end
    if direction ~= "withdraw" then direction = "deposit" end
    local id = v.nextGroupID or 1
    v.nextGroupID = id + 1
    v.groups[id] = { id = id, name = name, items = {}, direction = direction }
    return id
end

function IronVault:DeleteGroup(id)
    local v = vaultData()
    if not v or not id then return end
    v.groups[id] = nil
end

function IronVault:RenameGroup(id, name)
    local g = IronVault:GetGroup(id)
    if not g then return false end
    name = name and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return false end
    g.name = name
    return true
end

function IronVault:SetGroupDirection(id, direction)
    local g = IronVault:GetGroup(id)
    if not g then return false end
    if direction ~= "withdraw" then direction = "deposit" end
    g.direction = direction
    return true
end

function IronVault:SetItemTarget(groupID, itemID, target)
    local g = IronVault:GetGroup(groupID)
    if not g then return false end
    itemID = tonumber(itemID)
    target = tonumber(target)
    if not itemID or itemID < 1 then return false end
    if not target or target < 0 then target = 0 end
    local previous = g.items[itemID]
    g.items[itemID] = target
    return true, previous
end

function IronVault:RemoveItem(groupID, itemID)
    local g = IronVault:GetGroup(groupID)
    if not g then return end
    g.items[tonumber(itemID)] = nil
end

function IronVault:ParseItemFromText(text)
    if not text or text == "" then return nil end
    local id = text:match("|Hitem:(%d+):")
    if id then return tonumber(id) end
    return tonumber(text:match("^%s*(%d+)%s*$"))
end

local BAG_IDS = { 0, 1, 2, 3, 4 }
local BANK_IDS = { -1, 5, 6, 7, 8, 9, 10, 11 }

IronVault.bankOpen = false

local function enumerateContainer(bagID)
    local items = {}
    local numSlots = GetContainerNumSlots(bagID) or 0
    for slot = 1, numSlots do
        local link = GetContainerItemLink(bagID, slot)
        if link then
            local itemID = tonumber(link:match("item:(%d+)"))
            local _, count = GetContainerItemInfo(bagID, slot)
            if itemID and count and count > 0 then
                items[itemID] = items[itemID] or { totalCount = 0, stacks = {} }
                items[itemID].totalCount = items[itemID].totalCount + count
                table.insert(items[itemID].stacks, { bag = bagID, slot = slot, count = count })
            end
        end
    end
    return items
end

local function enumerateMultiple(bagIDs)
    local result = {}
    for _, bag in ipairs(bagIDs) do
        local single = enumerateContainer(bag)
        for itemID, data in pairs(single) do
            if not result[itemID] then
                result[itemID] = { totalCount = 0, stacks = {} }
            end
            result[itemID].totalCount = result[itemID].totalCount + data.totalCount
            for _, stack in ipairs(data.stacks) do
                table.insert(result[itemID].stacks, stack)
            end
        end
    end
    return result
end

local function findFreeSlots(bagIDs)
    local free = {}
    for _, bag in ipairs(bagIDs) do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            if not GetContainerItemLink(bag, slot) then
                table.insert(free, { bag = bag, slot = slot })
            end
        end
    end
    return free
end

function IronVault:BankIsOpen()
    return self.bankOpen == true
end

function IronVault:BuildRestockPlan(groupID)
    local g = self:GetGroup(groupID)
    if not g then return nil, nil end

    local direction = g.direction or "deposit"
    local bagItems = enumerateMultiple(BAG_IDS)
    local bankItems = enumerateMultiple(BANK_IDS)

    -- Direction-symmetric src/dst. For deposit: src=bag, dst=bank. For
    -- withdraw: src=bank, dst=bag. The plan and execution are identical
    -- otherwise: pickup from src, drop on dst.
    local srcItems, dstItems, freeDstSlots
    if direction == "withdraw" then
        srcItems, dstItems = bankItems, bagItems
        freeDstSlots = findFreeSlots(BAG_IDS)
    else
        srcItems, dstItems = bagItems, bankItems
        freeDstSlots = findFreeSlots(BANK_IDS)
    end

    local moves = {}
    local report = {}

    for itemID, target in pairs(g.items) do
        local srcCount = (srcItems[itemID] and srcItems[itemID].totalCount) or 0
        local dstCount = (dstItems[itemID] and dstItems[itemID].totalCount) or 0
        local needed
        if target == 0 then
            needed = srcCount
        else
            needed = math.max(0, target - dstCount)
        end

        if needed == 0 then
            table.insert(report, {
                itemID = itemID, status = "ok",
                dstCount = dstCount, target = target, direction = direction,
            })
        elseif srcCount == 0 then
            table.insert(report, {
                itemID = itemID, status = "missing_src",
                dstCount = dstCount, target = target, needed = needed, direction = direction,
            })
        else
            local available = math.min(needed, srcCount)
            local stillNeeded = available
            local _, _, _, _, _, _, _, maxStack = GetItemInfo(itemID)
            maxStack = maxStack or 1

            local partialStacks = {}
            if dstItems[itemID] then
                for _, stack in ipairs(dstItems[itemID].stacks) do
                    if stack.count < maxStack then
                        table.insert(partialStacks, { bag = stack.bag, slot = stack.slot, count = stack.count })
                    end
                end
                table.sort(partialStacks, function(a, b) return a.count > b.count end)
            end

            local srcStacks = {}
            if srcItems[itemID] then
                for _, stack in ipairs(srcItems[itemID].stacks) do
                    table.insert(srcStacks, { bag = stack.bag, slot = stack.slot, count = stack.count })
                end
                table.sort(srcStacks, function(a, b) return a.count < b.count end)
            end

            for _, srcStack in ipairs(srcStacks) do
                if stillNeeded <= 0 then break end
                local takeFromThisStack = math.min(srcStack.count, stillNeeded)
                local taken = 0

                local pidx = 1
                while taken < takeFromThisStack and pidx <= #partialStacks do
                    local pStack = partialStacks[pidx]
                    local space = maxStack - pStack.count
                    local moveCount = math.min(takeFromThisStack - taken, space)
                    if moveCount > 0 then
                        local isPartial = (taken + moveCount) < srcStack.count
                        table.insert(moves, {
                            srcBag = srcStack.bag, srcSlot = srcStack.slot,
                            dstBag = pStack.bag, dstSlot = pStack.slot,
                            count = moveCount, partial = isPartial,
                        })
                        pStack.count = pStack.count + moveCount
                        taken = taken + moveCount
                        if pStack.count >= maxStack then
                            table.remove(partialStacks, pidx)
                        else
                            pidx = pidx + 1
                        end
                    else
                        pidx = pidx + 1
                    end
                end

                while taken < takeFromThisStack and #freeDstSlots > 0 do
                    local freeSlot = freeDstSlots[1]
                    local moveCount = math.min(takeFromThisStack - taken, maxStack)
                    if moveCount > 0 then
                        local isPartial = (taken + moveCount) < srcStack.count
                        table.insert(moves, {
                            srcBag = srcStack.bag, srcSlot = srcStack.slot,
                            dstBag = freeSlot.bag, dstSlot = freeSlot.slot,
                            count = moveCount, partial = isPartial,
                        })
                        if moveCount < maxStack then
                            table.insert(partialStacks, 1, { bag = freeSlot.bag, slot = freeSlot.slot, count = moveCount })
                        end
                        table.remove(freeDstSlots, 1)
                        taken = taken + moveCount
                    else
                        break
                    end
                end

                stillNeeded = stillNeeded - taken
            end

            local transferred = available - stillNeeded
            local status
            if transferred == needed then
                status = "full"
            elseif transferred == 0 then
                status = "no_dst_space"
            else
                status = "partial"
            end
            table.insert(report, {
                itemID = itemID, status = status,
                dstCount = dstCount, target = target,
                needed = needed, transferred = transferred,
                direction = direction,
            })
        end
    end

    return moves, report
end

function IronVault:GetGroupStatus(groupID)
    local g = self:GetGroup(groupID)
    if not g then return 0, 0 end
    local direction = g.direction or "deposit"
    local bagItems = enumerateMultiple(BAG_IDS)
    local bankItems = enumerateMultiple(BANK_IDS)
    local srcItems = direction == "withdraw" and bankItems or bagItems
    local dstItems = direction == "withdraw" and bagItems or bankItems
    local atTarget, total = 0, 0
    for itemID, target in pairs(g.items) do
        total = total + 1
        local srcCount = (srcItems[itemID] and srcItems[itemID].totalCount) or 0
        local dstCount = (dstItems[itemID] and dstItems[itemID].totalCount) or 0
        if target == 0 then
            if srcCount == 0 then atTarget = atTarget + 1 end
        else
            if dstCount >= target then atTarget = atTarget + 1 end
        end
    end
    return atTarget, total
end

local STAGE_NEXT = 1
local STAGE_PICKUP = 2
local STAGE_DROP = 3

local restockState
local function newRestockState()
    return {
        running = false, aborted = false,
        groupID = nil, groupName = nil,
        moves = {}, report = nil,
        moveIndex = 0, currentMove = nil,
        stage = STAGE_NEXT,
        stats = { transferred = 0 },
        onComplete = nil,
    }
end
restockState = newRestockState()

local restockTimer = CreateFrame("Frame")
restockTimer:Hide()
local restockElapsed = 0
local restockCb
restockTimer:SetScript("OnUpdate", function(self, dt)
    restockElapsed = restockElapsed + dt
    if restockCb and restockElapsed >= restockCb.delay then
        local fn = restockCb.fn
        restockCb = nil
        restockElapsed = 0
        self:Hide()
        fn()
    end
end)
local function restockSchedule(delay, fn)
    restockCb = { delay = delay, fn = fn }
    restockElapsed = 0
    restockTimer:Show()
end

function IronVault:IsRestocking()
    return restockState.running
end

local function notifyVaultChange()
    if IronVault.onChange then
        local ok, err = pcall(IronVault.onChange)
        if not ok then IR:Print("|cffff5555vault ui error|r: " .. tostring(err)) end
    end
end

local function printReport(report, groupName)
    if not report or #report == 0 then return end
    IR:Debug(string.format("== %s ==", groupName or "?"))
    for _, r in ipairs(report) do
        local name = GetItemInfo(r.itemID) or ("Item #" .. r.itemID)
        local missingMsg = (r.direction == "withdraw") and IR.L["missing in bank"] or IR.L["missing in bags"]
        local fullMsg = (r.direction == "withdraw") and IR.L["bags full"] or IR.L["bank full"]
        if r.status == "ok" then
            IR:Debug(string.format("  %s: OK %d/%d", name, r.dstCount, r.target))
        elseif r.status == "missing_src" then
            IR:Debug(string.format("  %s: %s (need %d)", name, missingMsg, r.needed))
        elseif r.status == "full" then
            IR:Debug(string.format("  %s: +%d (target %d)", name, r.transferred, r.target))
        elseif r.status == "partial" then
            IR:Debug(string.format("  %s: partial %d/%d", name, r.transferred, r.needed))
        elseif r.status == "no_dst_space" then
            IR:Debug(string.format("  %s: %s (need %d)", name, fullMsg, r.needed))
        end
    end
end

local restockStep
function IronVault:RestockGroup(groupID, onComplete, opts)
    opts = opts or {}
    if restockState.running then
        if not opts.silent then IR:Print(IR.L["Restock already running"]) end
        return
    end
    if not self:BankIsOpen() then
        if not opts.silent then IR:Print(IR.L["Bank must be open"]) end
        return
    end
    local g = self:GetGroup(groupID)
    if not g then return end

    local moves, report = self:BuildRestockPlan(groupID)
    if not moves or #moves == 0 then
        IR:Debug(string.format("%s: nothing to restock", g.name))
        if report then printReport(report, g.name) end
        if onComplete then onComplete(0) end
        return
    end

    restockState = newRestockState()
    restockState.running = true
    restockState.groupID = groupID
    restockState.groupName = g.name
    restockState.moves = moves
    restockState.report = report
    restockState.onComplete = onComplete
    restockState.silent = opts.silent and true or false

    IR:Debug(string.format("Restocking %s: %d moves planned", g.name, #moves))
    notifyVaultChange()
    restockSchedule(0.05, restockStep)
end

restockStep = function()
    if not restockState.running then return end
    if restockState.aborted or not IronVault:BankIsOpen() then
        if not restockState.silent then IR:Print(IR.L["Restock interrupted"]) end
        printReport(restockState.report, restockState.groupName)
        local transferred = restockState.stats.transferred
        local cb = restockState.onComplete
        restockState.running = false
        notifyVaultChange()
        if cb then cb(transferred) end
        return
    end

    if restockState.stage == STAGE_NEXT then
        restockState.moveIndex = restockState.moveIndex + 1
        if restockState.moveIndex > #restockState.moves then
            local transferred = restockState.stats.transferred
            if not restockState.silent then
                IR:Print(string.format(IR.L["Restock complete: %s, %d transfers"],
                    restockState.groupName, transferred))
            end
            printReport(restockState.report, restockState.groupName)
            local cb = restockState.onComplete
            restockState.running = false
            notifyVaultChange()
            restockSchedule(0.3, function()
                notifyVaultChange()
                if cb then cb(transferred) end
            end)
            return
        end
        restockState.currentMove = restockState.moves[restockState.moveIndex]
        restockState.stage = STAGE_PICKUP
        restockSchedule(0.05, restockStep)
        return
    end

    if restockState.stage == STAGE_PICKUP then
        local m = restockState.currentMove
        if m.partial then
            SplitContainerItem(m.srcBag, m.srcSlot, m.count)
        else
            PickupContainerItem(m.srcBag, m.srcSlot)
        end
        restockState.stage = STAGE_DROP
        restockSchedule(0.2, restockStep)
        return
    end

    if restockState.stage == STAGE_DROP then
        local m = restockState.currentMove
        local hadItem = CursorHasItem and CursorHasItem()
        PickupContainerItem(m.dstBag, m.dstSlot)
        local stillHasItem = CursorHasItem and CursorHasItem()
        if stillHasItem then
            ClearCursor()
        end
        if hadItem and not stillHasItem then
            restockState.stats.transferred = restockState.stats.transferred + 1
        end
        restockState.stage = STAGE_NEXT
        notifyVaultChange()
        restockSchedule(0.2, restockStep)
        return
    end
end

function IronVault:AbortRestock()
    restockState.aborted = true
end

function IronVault:RestockAll(onComplete)
    local v = vaultData()
    if not v or not v.groups then
        if onComplete then onComplete() end
        return
    end
    -- Run deposits first (free bag space), then withdraws (use newly freed bag
    -- space to refill from bank). Within a direction, order by id ascending.
    local deposits, withdraws = {}, {}
    for id, g in pairs(v.groups) do
        if g.direction == "withdraw" then
            table.insert(withdraws, id)
        else
            table.insert(deposits, id)
        end
    end
    table.sort(deposits)
    table.sort(withdraws)
    local queue = {}
    for _, id in ipairs(deposits) do table.insert(queue, id) end
    for _, id in ipairs(withdraws) do table.insert(queue, id) end

    local totalTransfers = 0
    local touchedGroups = 0

    local function runNext()
        local id = table.remove(queue, 1)
        if not id then
            if totalTransfers > 0 then
                IR:Print(string.format(IR.L["Restock complete: %d transfers across %d groups"],
                    totalTransfers, touchedGroups))
            else
                IR:Print(IR.L["All groups already at target"])
            end
            if onComplete then onComplete() end
            return
        end
        self:RestockGroup(id, function(transferred)
            transferred = transferred or 0
            if transferred > 0 then
                totalTransfers = totalTransfers + transferred
                touchedGroups = touchedGroups + 1
            end
            runNext()
        end, { silent = true })
    end
    runNext()
end

local function runAutoStoreGroups()
    local v = vaultData()
    if not v or not v.groups then return end
    local queue = {}
    for id, g in pairs(v.groups) do
        if g.autoStore then
            table.insert(queue, id)
        end
    end
    if #queue == 0 then return end
    table.sort(queue)
    local totalTransfers = 0
    local touchedGroups = 0
    local function runNext()
        local id = table.remove(queue, 1)
        if not id then
            if totalTransfers > 0 then
                IR:Print(string.format(IR.L["Auto-store: %d transfers across %d groups"],
                    totalTransfers, touchedGroups))
            end
            return
        end
        IronVault:RestockGroup(id, function(transferred)
            transferred = transferred or 0
            if transferred > 0 then
                totalTransfers = totalTransfers + transferred
                touchedGroups = touchedGroups + 1
            end
            runNext()
        end, { silent = true })
    end
    runNext()
end

IR:On("BANKFRAME_OPENED", function()
    IronVault.bankOpen = true
    notifyVaultChange()
    runAutoStoreGroups()
end)

IR:On("BANKFRAME_CLOSED", function()
    IronVault.bankOpen = false
    if restockState.running then restockState.aborted = true end
    notifyVaultChange()
end)

IR:On("BAG_UPDATE", function()
    if IronVault.bankOpen then notifyVaultChange() end
end)

function IronVault:ParseItemsFromText(text)
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
        if single then
            table.insert(items, single)
        end
    end
    return items
end

local function sortedGroupIDs()
    local v = vaultData()
    local list = {}
    if v then
        for id in pairs(v.groups) do
            table.insert(list, id)
        end
        -- Same order as RestockAll: deposits first, withdraws after, alpha within each.
        table.sort(list, function(a, b)
            local ga = v.groups[a]
            local gb = v.groups[b]
            local da = (ga and ga.direction) == "withdraw" and 1 or 0
            local db = (gb and gb.direction) == "withdraw" and 1 or 0
            if da ~= db then return da < db end
            local na = (ga and ga.name) or ""
            local nb = (gb and gb.name) or ""
            if na:lower() == nb:lower() then return a < b end
            return na:lower() < nb:lower()
        end)
    end
    return list
end

local function sortedItemIDs(group)
    local list = {}
    if group and group.items then
        for itemID in pairs(group.items) do
            table.insert(list, itemID)
        end
        table.sort(list, function(a, b)
            local na = GetItemInfo(a) or ""
            local nb = GetItemInfo(b) or ""
            if na == nb then return a < b end
            return na:lower() < nb:lower()
        end)
    end
    return list
end

local selectedGroupID
local groupListFrame, groupRows = nil, {}
local groupNameEdit, itemListFrame, itemRows = nil, nil, {}
local addItemEdit, addTargetEdit
local refreshGroupList, refreshGroupDetail

local function makeEditBox(parent, width, maxLetters, placeholder)
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

local function buildVaultAITab(parent)
    -- Left column: groups list
    local leftBg = CreateFrame("Frame", nil, parent)
    leftBg:SetPoint("TOPLEFT", 0, 0)
    leftBg:SetPoint("BOTTOMLEFT", 0, 0)
    leftBg:SetWidth(190)

    local groupsLabel = leftBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    groupsLabel:SetPoint("TOPLEFT", 4, -4)
    groupsLabel:SetText(IR.L["Groups"])

    local newBtn = CreateFrame("Button", nil, leftBg, "UIPanelButtonTemplate")
    newBtn:SetSize(60, 20)
    newBtn:SetPoint("TOPRIGHT", -4, -4)
    newBtn:SetText(IR.L["New"])
    newBtn:SetScript("OnClick", function()
        StaticPopupDialogs["IRON_VAULT_NEW_GROUP"] = StaticPopupDialogs["IRON_VAULT_NEW_GROUP"] or {
            text = IR.L["New group direction:\n\nDeposit (bag → bank) is for storing items.\nWithdraw (bank → bag) is for refilling your bags."],
            button1 = IR.L["Deposit (bag → bank)"],
            button2 = IR.L["Withdraw (bank → bag)"],
            OnAccept = function()
                local id = IronVault:CreateGroup(IR.L["New Group"], "deposit")
                selectedGroupID = id
                refreshGroupList()
                refreshGroupDetail()
                notifyVaultChange()
            end,
            OnCancel = function()
                local id = IronVault:CreateGroup(IR.L["New Group"], "withdraw")
                selectedGroupID = id
                refreshGroupList()
                refreshGroupDetail()
                notifyVaultChange()
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
        }
        StaticPopup_Show("IRON_VAULT_NEW_GROUP")
    end)

    groupListFrame = CreateFrame("ScrollFrame", "IronVaultGroupScroll", leftBg, "UIPanelScrollFrameTemplate")
    groupListFrame:SetPoint("TOPLEFT", 4, -28)
    groupListFrame:SetPoint("BOTTOMRIGHT", -22, 30)

    local groupContent = CreateFrame("Frame", nil, groupListFrame)
    groupContent:SetSize(160, 1)
    groupListFrame:SetScrollChild(groupContent)
    groupListFrame.content = groupContent

    local deleteBtn = CreateFrame("Button", nil, leftBg, "UIPanelButtonTemplate")
    deleteBtn:SetSize(160, 22)
    deleteBtn:SetPoint("BOTTOMLEFT", 4, 4)
    deleteBtn:SetText(IR.L["Delete Selected"])
    deleteBtn:SetScript("OnClick", function()
        if not selectedGroupID then return end
        IronVault:DeleteGroup(selectedGroupID)
        selectedGroupID = nil
        refreshGroupList()
        refreshGroupDetail()
        notifyVaultChange()
    end)

    -- Right column: group detail
    local right = CreateFrame("Frame", nil, parent)
    right:SetPoint("TOPLEFT", leftBg, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)

    local nameLabel = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", 0, -4)
    nameLabel:SetText(IR.L["Name:"])

    groupNameEdit = makeEditBox(right, 250, 40)
    groupNameEdit:SetPoint("TOPLEFT", 50, -4)
    groupNameEdit:SetScript("OnEnterPressed", function(self)
        if selectedGroupID then
            IronVault:RenameGroup(selectedGroupID, self:GetText())
            refreshGroupList()
            notifyVaultChange()
        end
        self:ClearFocus()
    end)

    local autoStoreCheck = CreateFrame("CheckButton", nil, right, "UICheckButtonTemplate")
    autoStoreCheck:SetPoint("TOPLEFT", 0, -28)
    local autoLabel = autoStoreCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoLabel:SetPoint("LEFT", autoStoreCheck, "RIGHT", 4, 0)
    autoLabel:SetText(IR.L["Auto-store on bank open"])
    autoStoreCheck:SetScript("OnClick", function(self)
        local g = IronVault:GetGroup(selectedGroupID)
        if g then
            g.autoStore = self:GetChecked() and true or false
            notifyVaultChange()
        end
    end)

    local itemsLabel = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemsLabel:SetPoint("TOPLEFT", 0, -56)
    itemsLabel:SetText(IR.L["Items:"])

    local dirDepositBtn = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
    dirDepositBtn:SetSize(28, 20)
    dirDepositBtn:SetPoint("TOPRIGHT", -32, -54)
    dirDepositBtn:SetText("|cffffaa00<-|r")
    IR:AttachTooltip(dirDepositBtn, IR.L["Set this group to deposit (bag -> bank)"])
    dirDepositBtn:SetScript("OnClick", function()
        if not selectedGroupID then return end
        IronVault:SetGroupDirection(selectedGroupID, "deposit")
        refreshGroupDetail()
        refreshGroupList()
        notifyVaultChange()
    end)

    local dirWithdrawBtn = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
    dirWithdrawBtn:SetSize(28, 20)
    dirWithdrawBtn:SetPoint("TOPRIGHT", -2, -54)
    dirWithdrawBtn:SetText("|cff66ccff->|r")
    IR:AttachTooltip(dirWithdrawBtn, IR.L["Set this group to withdraw (bank -> bag)"])
    dirWithdrawBtn:SetScript("OnClick", function()
        if not selectedGroupID then return end
        IronVault:SetGroupDirection(selectedGroupID, "withdraw")
        refreshGroupDetail()
        refreshGroupList()
        notifyVaultChange()
    end)

    itemListFrame = CreateFrame("ScrollFrame", "IronVaultItemScroll", right, "UIPanelScrollFrameTemplate")
    itemListFrame:SetPoint("TOPLEFT", 0, -76)
    itemListFrame:SetPoint("BOTTOMRIGHT", -22, 38)

    local itemContent = CreateFrame("Frame", nil, itemListFrame)
    itemContent:SetSize(280, 1)
    itemListFrame:SetScrollChild(itemContent)
    itemListFrame.content = itemContent

    local addLabel = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("BOTTOMLEFT", 0, 18)
    addLabel:SetText(IR.L["Add (link or itemID):"])

    local addBtn = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
    addBtn:SetSize(60, 20)
    addBtn:SetPoint("BOTTOMRIGHT", 0, -2)
    addBtn:SetText(IR.L["Add"])

    addTargetEdit = makeEditBox(right, 50, 5)
    addTargetEdit:ClearAllPoints()
    addTargetEdit:SetPoint("RIGHT", addBtn, "LEFT", -4, 0)
    addTargetEdit:SetNumeric(true)
    addTargetEdit:SetText("1")

    local targetLabel = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetLabel:SetPoint("RIGHT", addTargetEdit, "LEFT", -4, 0)
    targetLabel:SetText(IR.L["Target:"])

    addItemEdit = makeEditBox(right, 100, 4000)
    addItemEdit:ClearAllPoints()
    addItemEdit:SetPoint("BOTTOMLEFT", 0, -2)
    addItemEdit:SetPoint("RIGHT", targetLabel, "LEFT", -6, 0)
    local function tryAdd()
        if not selectedGroupID then
            IR:Print(IR.L["Select a group first"])
            return
        end
        local ids = IronVault:ParseItemsFromText(addItemEdit:GetText())
        if #ids == 0 then
            IR:Print(IR.L["Invalid item link or ID"])
            return
        end
        local target = tonumber(addTargetEdit:GetText()) or 1
        local g = IronVault:GetGroup(selectedGroupID)
        for _, itemID in ipairs(ids) do
            local existing = g and g.items[itemID]
            local name = GetItemInfo(itemID) or ("Item #" .. itemID)
            if existing then
                IR:Print(string.format(IR.L["%s: already in list (target %d). Edit the row directly."], name, existing))
            else
                IronVault:SetItemTarget(selectedGroupID, itemID, target)
                IR:Print(string.format(IR.L["%s: added with target %d"], name, target))
            end
        end
        addItemEdit:SetText("")
        addTargetEdit:SetText("1")
        addItemEdit:ClearFocus()
        refreshGroupDetail()
        refreshGroupList()
        notifyVaultChange()
    end
    addBtn:SetScript("OnClick", tryAdd)
    addItemEdit:SetScript("OnEnterPressed", tryAdd)

    local function getItemRow(i)
        if itemRows[i] then return itemRows[i] end
        local row = CreateFrame("Frame", nil, itemContent)
        row:SetSize(280, 22)
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

        local target = makeEditBox(row, 40, 5)
        target:SetPoint("RIGHT", removeBtn, "LEFT", -4, 0)
        target:SetNumeric(true)
        row.target = target

        local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        name:SetPoint("RIGHT", target, "LEFT", -4, 0)
        name:SetJustifyH("LEFT")
        row.name = name

        itemRows[i] = row
        return row
    end

    refreshGroupList = function()
        if not groupListFrame then return end
        for _, row in pairs(groupRows) do row:Hide() end
        local ids = sortedGroupIDs()
        groupContent:SetHeight(math.max(#ids * 22, 1))
        for i, id in ipairs(ids) do
            local row = groupRows[i]
            if not row then
                row = CreateFrame("Button", nil, groupContent)
                row:SetSize(160, 20)
                row:SetPoint("TOPLEFT", 0, -((i - 1) * 22))
                row:RegisterForClicks("LeftButtonUp")
                local hl = row:CreateTexture(nil, "BACKGROUND")
                hl:SetTexture(0.3, 0.5, 0.9)
                hl:SetAlpha(0.3)
                hl:SetAllPoints()
                hl:Hide()
                row.highlight = hl
                local hover = row:CreateTexture(nil, "BACKGROUND")
                hover:SetTexture(1, 1, 1)
                hover:SetAlpha(0.08)
                hover:SetAllPoints()
                hover:Hide()
                row.hover = hover
                local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                label:SetPoint("LEFT", 4, 0)
                label:SetWidth(150)
                label:SetJustifyH("LEFT")
                row.label = label
                row:SetScript("OnEnter", function(self) self.hover:Show() end)
                row:SetScript("OnLeave", function(self) self.hover:Hide() end)
                row:SetScript("OnClick", function(self)
                    selectedGroupID = self.groupID
                    refreshGroupList()
                    refreshGroupDetail()
                end)
                groupRows[i] = row
            end
            row.groupID = id
            local v = vaultData()
            local g = v and v.groups[id]
            local count = 0
            if g and g.items then
                for _ in pairs(g.items) do count = count + 1 end
            end
            local arrow = ((g and g.direction) == "withdraw")
                and "|cff66ccff->|r"
                or "|cffffaa00<-|r"
            row.label:SetText(string.format("%s (%d) %s", (g and g.name) or "?", count, arrow))
            if id == selectedGroupID then row.highlight:Show() else row.highlight:Hide() end
            row:Show()
        end
    end

    refreshGroupDetail = function()
        if not groupNameEdit then return end
        local g = IronVault:GetGroup(selectedGroupID)
        if not g then
            groupNameEdit:SetText("")
            groupNameEdit:Disable()
            autoStoreCheck:SetChecked(false)
            autoStoreCheck:Disable()
            dirDepositBtn:Disable()
            dirWithdrawBtn:Disable()
            for _, row in pairs(itemRows) do row:Hide() end
            itemContent:SetHeight(1)
            return
        end
        groupNameEdit:Enable()
        groupNameEdit:SetText(g.name or "")
        autoStoreCheck:Enable()
        autoStoreCheck:SetChecked(g.autoStore and true or false)
        if (g.direction or "deposit") == "withdraw" then
            dirDepositBtn:Enable()
            dirWithdrawBtn:Disable()
        else
            dirDepositBtn:Disable()
            dirWithdrawBtn:Enable()
        end

        local ids = sortedItemIDs(g)
        for _, row in pairs(itemRows) do row:Hide() end
        itemContent:SetHeight(math.max(#ids * 24, 1))
        for i, itemID in ipairs(ids) do
            local row = getItemRow(i)
            local name, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
            if texture then
                row.icon:SetTexture(texture)
            else
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            row.name:SetText(name or ("Item #" .. itemID))
            row.target:SetText(tostring(g.items[itemID] or 1))
            row.target:SetScript("OnEnterPressed", function(self)
                local v = tonumber(self:GetText())
                if v and selectedGroupID then
                    IronVault:SetItemTarget(selectedGroupID, itemID, v)
                    refreshGroupDetail()
                    notifyVaultChange()
                end
                self:ClearFocus()
            end)
            row.removeBtn:SetScript("OnClick", function()
                if selectedGroupID then
                    IronVault:RemoveItem(selectedGroupID, itemID)
                    refreshGroupDetail()
                    refreshGroupList()
                    notifyVaultChange()
                end
            end)
            row:Show()
        end
    end

    table.insert(IR.Settings.refreshHandlers, function()
        refreshGroupList()
        refreshGroupDetail()
    end)
end

IR:RegisterSettingsTab({
    name = "ironvault",
    title = "IronVault",
    build = buildVaultAITab,
})

local origChatEditInsertLink = ChatEdit_InsertLink
function ChatEdit_InsertLink(text)
    if not text then return false end
    if addItemEdit and addItemEdit:IsVisible() and addItemEdit:HasFocus() then
        addItemEdit:Insert(text)
        return true
    end
    return origChatEditInsertLink(text)
end
