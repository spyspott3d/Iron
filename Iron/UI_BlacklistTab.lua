-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.UI = IR.UI or {}
IR.UI.BlacklistTab = {}
local BlacklistTab = IR.UI.BlacklistTab

local IronSell = IR.IronSell

local INNER_W = 290
local ROW_H = 24

local content, scroll, addEdit, addBtn, searchEdit
local rows = {}
local refresh
local searchFilter = ""

local function makeEditBox(parent, width, maxLetters)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetFontObject("ChatFontNormal")
    e:SetMaxLetters(maxLetters or 4000)
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

local function getRow(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(INNER_W, ROW_H)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * (ROW_H + 1)))

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 2, 0)
    row.icon = icon

    local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    removeBtn:SetSize(22, 20)
    removeBtn:SetPoint("RIGHT", 0, 0)
    removeBtn:SetText("X")
    row.removeBtn = removeBtn
    IR:AttachTooltip(removeBtn, IR.L["Remove from blacklist"])

    local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameFs:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameFs:SetPoint("RIGHT", removeBtn, "LEFT", -4, 0)
    nameFs:SetJustifyH("LEFT")
    row.name = nameFs

    rows[i] = row
    return row
end

refresh = function()
    if not content then return end
    for _, r in pairs(rows) do r:Hide() end

    local s = Iron_DB and Iron_DB.settings and Iron_DB.settings.ironSell
    local ids = {}
    if s and s.blacklist then
        for itemID in pairs(s.blacklist) do
            if searchFilter == "" then
                table.insert(ids, itemID)
            else
                local name = GetItemInfo(itemID) or ("Item #" .. itemID)
                if name:lower():find(searchFilter, 1, true) then
                    table.insert(ids, itemID)
                end
            end
        end
        table.sort(ids, function(a, b)
            local na = GetItemInfo(a) or ""
            local nb = GetItemInfo(b) or ""
            if na == nb then return a < b end
            return na:lower() < nb:lower()
        end)
    end
    content:SetHeight(math.max(#ids * (ROW_H + 1), 1))

    for i, itemID in ipairs(ids) do
        local row = getRow(i)
        local name, link, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
        row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.name:SetText(name or ("Item #" .. itemID))
        row.itemLink = link or name
        row:SetScript("OnEnter", function(self)
            if self.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.itemLink)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.removeBtn:SetScript("OnClick", function()
            IronSell:RemoveFromBlacklist(itemID)
            refresh()
            if IR.UI.SellTab and IR.UI.SellTab.Refresh then
                IR.UI.SellTab:Refresh()
            end
        end)
        row:Show()
    end
end

local function tryAdd()
    if not addEdit then return end
    local ids = IronSell:ParseItemsFromText(addEdit:GetText())
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
    addEdit:SetText("")
    addEdit:ClearFocus()
    refresh()
    if IR.UI.SellTab and IR.UI.SellTab.Refresh then
        IR.UI.SellTab:Refresh()
    end
end

local function build(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, -4)
    title:SetText(IR.L["Blacklist"])

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPRIGHT", 0, -6)
    hint:SetText(IR.L["Shift-click items into the field"])

    searchEdit = makeEditBox(parent, 280, 64)
    searchEdit:ClearAllPoints()
    searchEdit:SetPoint("TOP", parent, "TOP", 0, -28)
    searchEdit:SetHeight(22)

    local placeholder = searchEdit:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("LEFT", 8, 0)
    placeholder:SetText(IR.L["Search..."])
    placeholder:SetTextColor(0.55, 0.55, 0.55, 1)

    local function refreshPlaceholder()
        local text = searchEdit:GetText() or ""
        if text == "" and not searchEdit:HasFocus() then
            placeholder:Show()
        else
            placeholder:Hide()
        end
    end

    searchEdit:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
    searchEdit:SetScript("OnEditFocusLost", refreshPlaceholder)
    searchEdit:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        searchFilter = ""
        self:ClearFocus()
        refresh()
    end)
    searchEdit:SetScript("OnTextChanged", function(self, userInput)
        refreshPlaceholder()
        if not userInput then return end
        searchFilter = (self:GetText() or ""):lower()
        refresh()
    end)
    searchEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    scroll = CreateFrame("ScrollFrame", "IronBlacklistTabScroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -56)
    scroll:SetPoint("BOTTOMRIGHT", -22, 32)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(INNER_W, 1)
    scroll:SetScrollChild(content)

    addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetSize(60, 22)
    addBtn:SetPoint("BOTTOMRIGHT", 0, 4)
    addBtn:SetText(IR.L["Add"])
    IR:AttachTooltip(addBtn, IR.L["Add the typed item link or ID to the blacklist"])

    addEdit = makeEditBox(parent, 100, 4000)
    addEdit:ClearAllPoints()
    addEdit:SetPoint("BOTTOMLEFT", 0, 4)
    addEdit:SetPoint("RIGHT", addBtn, "LEFT", -6, 0)
    addEdit:SetHeight(22)

    local addPlaceholder = addEdit:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    addPlaceholder:SetPoint("LEFT", 6, 0)
    addPlaceholder:SetText("[Item ID]")
    addPlaceholder:SetTextColor(0.55, 0.55, 0.55, 1)

    local function refreshAddPlaceholder()
        local text = addEdit:GetText() or ""
        if text == "" and not addEdit:HasFocus() then
            addPlaceholder:Show()
        else
            addPlaceholder:Hide()
        end
    end

    addEdit:HookScript("OnEditFocusGained", function() addPlaceholder:Hide() end)
    addEdit:HookScript("OnEditFocusLost", refreshAddPlaceholder)
    addEdit:HookScript("OnTextChanged", refreshAddPlaceholder)

    addBtn:SetScript("OnClick", tryAdd)
    addEdit:SetScript("OnEnterPressed", tryAdd)
end

function BlacklistTab:Refresh() refresh() end

IR.UI.AHCompanion:RegisterTab({
    name = "blacklist",
    title = "Blacklist",
    tooltip = IR.L["Items excluded from the Sell list"],
    build = build,
    onShow = function() refresh() end,
})

local origChatEditInsertLink = ChatEdit_InsertLink
function ChatEdit_InsertLink(text)
    if text and addEdit and addEdit:IsVisible() and addEdit:HasFocus() then
        addEdit:Insert(text)
        return true
    end
    return origChatEditInsertLink(text)
end
