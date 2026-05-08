-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.UI = IR.UI or {}
local UI = {}
IR.UI.IronVault = UI

local IronVault = IR.IronVault

local FRAME_W = 290
local ROW_H = 38
local HEADER_H = 34
local FOOTER_H = 60
local frame, content, statusText
local groupRows = {}
local restockAllBtn

local function findBankAnchor()
    if IsAddOnLoaded and IsAddOnLoaded("Bagnon") then
        local candidates = { "BagnonFrameBank", "BagnonFramebank", "BagnonBank", "BagnonInventoryBank" }
        for _, name in ipairs(candidates) do
            local f = _G[name]
            if f and f.IsShown then
                return f, name
            end
        end
    end
    return BankFrame, "BankFrame"
end

local function sortedGroupIDs()
    local groups = IronVault:GetGroupsTable()
    local list = {}
    if groups then
        for id in pairs(groups) do
            table.insert(list, id)
        end
        -- Same order as RestockAll execution: deposits first, withdraws after,
        -- alphabetical within each direction.
        table.sort(list, function(a, b)
            local ga = groups[a]
            local gb = groups[b]
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

local function getGroupRow(i)
    if groupRows[i] then return groupRows[i] end
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(FRAME_W - 50, ROW_H)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * (ROW_H + 4)))

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(0.08, 0.08, 0.08, 0.6)
    bg:SetAllPoints()

    local dirFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dirFs:SetPoint("TOPLEFT", 6, -2)
    dirFs:SetWidth(18)
    dirFs:SetJustifyH("CENTER")
    row.dir = dirFs

    local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameFs:SetPoint("LEFT", dirFs, "RIGHT", 4, 0)
    nameFs:SetPoint("TOP", row, "TOP", 0, -4)
    nameFs:SetWidth(140)
    nameFs:SetJustifyH("LEFT")
    row.name = nameFs

    local statusFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFs:SetPoint("BOTTOMLEFT", 6, 4)
    statusFs:SetWidth(150)
    statusFs:SetJustifyH("LEFT")
    row.status = statusFs

    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(70, 22)
    btn:SetPoint("RIGHT", -4, 0)
    btn:SetText(IR.L["Restock"])
    row.btn = btn

    groupRows[i] = row
    return row
end

local function refresh()
    if not frame or not frame:IsShown() then return end
    local ids = sortedGroupIDs()
    for _, row in pairs(groupRows) do row:Hide() end

    local totalY = 0
    for i, id in ipairs(ids) do
        local row = getGroupRow(i)
        local g = IronVault:GetGroup(id)
        if g then
            local at, total = IronVault:GetGroupStatus(id)
            local autoTag = g.autoStore and " |cff66ff66[auto]|r" or ""
            row.name:SetText((g.name or "?") .. autoTag)
            if (g.direction or "deposit") == "withdraw" then
                row.dir:SetText("|cff66ccff->|r")
                IR:AttachTooltip(row.btn, IR.L["Move items of this group from the bank into your bags"])
            else
                row.dir:SetText("|cffffaa00<-|r")
                IR:AttachTooltip(row.btn, IR.L["Move items of this group from your bags into the bank"])
            end
            local color
            if total == 0 then
                color = "|cff999999"
            elseif at == total then
                color = "|cff66ff66"
            elseif at == 0 then
                color = "|cffff7777"
            else
                color = "|cffffaa00"
            end
            row.status:SetText(string.format("%s%d/%d|r " .. IR.L["at target"], color, at, total))
            row.btn:SetScript("OnClick", function()
                IronVault:RestockGroup(id, refresh)
            end)
            if IronVault:IsRestocking() then
                row.btn:Disable()
            else
                row.btn:Enable()
            end

            -- Dynamic row height to accommodate wrapped name + status line.
            -- Layout: top pad 4 + name (nameH) + gap 4 + status 14 + bottom pad 4
            local nameH = row.name:GetStringHeight() or 14
            local rowH = math.max(ROW_H, math.ceil(nameH) + 26)
            row:SetHeight(rowH)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -totalY)
            totalY = totalY + rowH + 4

            row:Show()
        end
    end
    content:SetHeight(math.max(totalY, 1))

    local listHeight = math.max(totalY, ROW_H + 4)
    local height = HEADER_H + listHeight + FOOTER_H + 12
    if height < 180 then height = 180 end
    if height > 540 then height = 540 end
    frame:SetHeight(height)

    if statusText then
        if IronVault:IsRestocking() then
            statusText:SetText(IR.L["Restocking..."])
            restockAllBtn:Disable()
        else
            statusText:SetText("")
            if #ids > 0 then restockAllBtn:Enable() else restockAllBtn:Disable() end
        end
    end
end

local function createFrame()
    if frame then return end

    frame = CreateFrame("Frame", "IronVaultFrame", UIParent)
    frame:Hide()
    frame:SetSize(FRAME_W, 200)
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

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -12)
    title:SetText("IronVault")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)

    local scroll = CreateFrame("ScrollFrame", "IronVaultBankScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -HEADER_H)
    scroll:SetPoint("BOTTOMRIGHT", -34, FOOTER_H)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(FRAME_W - 50, 1)
    scroll:SetScrollChild(content)

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", 12, 36)
    statusText:SetText("")

    restockAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    restockAllBtn:SetSize(110, 22)
    restockAllBtn:SetPoint("BOTTOMLEFT", 12, 12)
    restockAllBtn:SetText(IR.L["Restock All"])
    IR:AttachTooltip(restockAllBtn, IR.L["Synchronize all groups (deposits then withdrawals)"])
    restockAllBtn:SetScript("OnClick", function()
        IronVault:RestockAll(refresh)
    end)

    local settingsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    settingsBtn:SetSize(110, 22)
    settingsBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    settingsBtn:SetText(IR.L["Settings"])
    settingsBtn:SetScript("OnClick", function() IR:OpenSettings("ironvault") end)
    IR:AttachTooltip(settingsBtn, IR.L["Open the IronVault settings (groups and targets)"])
end

local function anchorFrame()
    if not frame then return end
    local anchor = findBankAnchor()
    frame:ClearAllPoints()
    if anchor and anchor.IsShown and anchor:IsShown() then
        frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end
end

function UI:Show()
    createFrame()
    anchorFrame()
    frame:Show()
    refresh()
end

function UI:Hide()
    if frame then frame:Hide() end
end

IR:On("BANKFRAME_OPENED", function() UI:Show() end)
IR:On("BANKFRAME_CLOSED", function() UI:Hide() end)

IronVault.onChange = function() refresh() end
