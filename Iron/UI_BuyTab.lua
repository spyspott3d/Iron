-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.UI = IR.UI or {}
IR.UI.BuyTab = {}
local BuyTab = IR.UI.BuyTab

local Recipes = IR.Recipes
local PriceDB = IR.PriceDB

local INNER_W = 300
local ROW_H_DEFAULT = 32
local ROW_H_RECIPE = 48
local ROW_H_REAGENT = 40
local BAG_IDS = { 0, 1, 2, 3, 4 }

local state = { profession = nil, category = nil, recipeKey = nil, filter = "" }

local breadcrumbFrame
local breadcrumbBtns = {}
local breadcrumbSeps = {}
local listScroll, listContent
local rows = {}
local titleFs
local filterEdit

local SKILL_COLORS = {
    trivial = "|cff808080",
    easy = "|cff40c040",
    medium = "|cffffff00",
    optimal = "|cffff8040",
    difficult = "|cffff4040",
}

local QUALITY_COLORS = {
    [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00",
    [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000", [6] = "|cffe6cc80",
}

local PROF_ICONS = {
    -- enUS
    ["Alchemy"]         = "Interface\\Icons\\Trade_Alchemy",
    ["Blacksmithing"]   = "Interface\\Icons\\Trade_BlackSmithing",
    ["Cooking"]         = "Interface\\Icons\\INV_Misc_Food_15",
    ["Enchanting"]      = "Interface\\Icons\\Trade_Engraving",
    ["Engineering"]     = "Interface\\Icons\\Trade_Engineering",
    ["First Aid"]       = "Interface\\Icons\\Spell_Holy_Heal",
    ["Fishing"]         = "Interface\\Icons\\Trade_Fishing",
    ["Herbalism"]       = "Interface\\Icons\\INV_Misc_Flower_02",
    ["Inscription"]     = "Interface\\Icons\\INV_Inscription_Tradeskill01",
    ["Jewelcrafting"]   = "Interface\\Icons\\INV_Misc_Gem_01",
    ["Leatherworking"]  = "Interface\\Icons\\INV_Misc_ArmorKit_17",
    ["Mining"]          = "Interface\\Icons\\Trade_Mining",
    ["Skinning"]        = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    ["Tailoring"]       = "Interface\\Icons\\Trade_Tailoring",
    ["Smelting"]        = "Interface\\Icons\\Spell_Fire_FlameBlades",
    ["Lockpicking"]     = "Interface\\Icons\\INV_Misc_Key_03",
    ["Poisons"]         = "Interface\\Icons\\Trade_BrewPoison",
    ["Runeforging"]     = "Interface\\Icons\\Spell_DeathKnight_RuneTap",
    -- frFR
    ["Alchimie"]        = "Interface\\Icons\\Trade_Alchemy",
    ["Forge"]           = "Interface\\Icons\\Trade_BlackSmithing",
    ["Cuisine"]         = "Interface\\Icons\\INV_Misc_Food_15",
    ["Enchantement"]    = "Interface\\Icons\\Trade_Engraving",
    ["Ingénierie"]      = "Interface\\Icons\\Trade_Engineering",
    ["Secourisme"]      = "Interface\\Icons\\Spell_Holy_Heal",
    ["Pêche"]           = "Interface\\Icons\\Trade_Fishing",
    ["Herboristerie"]   = "Interface\\Icons\\INV_Misc_Flower_02",
    ["Calligraphie"]    = "Interface\\Icons\\INV_Inscription_Tradeskill01",
    ["Joaillerie"]      = "Interface\\Icons\\INV_Misc_Gem_01",
    ["Travail du cuir"] = "Interface\\Icons\\INV_Misc_ArmorKit_17",
    ["Minage"]          = "Interface\\Icons\\Trade_Mining",
    ["Dépeçage"]        = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    ["Couture"]         = "Interface\\Icons\\Trade_Tailoring",
    ["Fonte"]           = "Interface\\Icons\\Spell_Fire_FlameBlades",
    ["Crochetage"]      = "Interface\\Icons\\INV_Misc_Key_03",
    ["Inscription en runes"] = "Interface\\Icons\\Spell_DeathKnight_RuneTap",
}

local DEFAULT_PROF_ICON = "Interface\\Icons\\INV_Misc_Note_01"
local DEFAULT_CATEGORY_ICON = "Interface\\Icons\\INV_Misc_Bag_07_Black"

local render

local function closeAuctionFrames()
    if IR.UI.AuctionList then IR.UI.AuctionList:Close() end
    if IR.UI.BuyAuctionList then IR.UI.BuyAuctionList:Close() end
end

local function resetFilter()
    state.filter = ""
    if filterEdit then
        filterEdit:SetText("")
        filterEdit:ClearFocus()
    end
end

local function setLevel1()
    state.profession = nil; state.category = nil; state.recipeKey = nil
    resetFilter()
    closeAuctionFrames()
    render()
end
local function setLevel2(prof)
    state.profession = prof; state.category = nil; state.recipeKey = nil
    resetFilter()
    closeAuctionFrames()
    render()
end
local function setLevel3(prof, cat)
    state.profession = prof; state.category = cat; state.recipeKey = nil
    resetFilter()
    closeAuctionFrames()
    render()
end
local function setLevel4(prof, cat, recipeKey)
    state.profession = prof; state.category = cat; state.recipeKey = recipeKey
    resetFilter()
    render()
end

local function matchesFilter(name)
    if not state.filter or state.filter == "" then return true end
    if not name then return false end
    return name:lower():find(state.filter, 1, true) ~= nil
end

-- Descendant search: from the current level, walk down the tree and collect
-- everything matching the filter. Each entry carries enough context to
-- navigate directly to it on click.
local function collectDescendantMatches()
    local f = state.filter
    if not f or f == "" then return {} end
    local results = {}

    local function matchProfession(prof)
        local entry = Recipes:Get(prof)
        if not entry or not entry.crafts then return end
        for key, craft in pairs(entry.crafts) do
            if (craft.name or ""):lower():find(f, 1, true) then
                local cat = craft.category or IR.L["Other"]
                table.insert(results, {
                    type = "recipe", name = craft.name,
                    profession = prof, category = cat, key = key, craft = craft,
                })
            end
        end
    end

    if state.recipeKey then
        local entry = Recipes:Get(state.profession)
        local craft = entry and entry.crafts and entry.crafts[state.recipeKey]
        if craft then
            for itemID, qty in pairs(craft.reagents or {}) do
                local rname = GetItemInfo(itemID) or ("Item #" .. itemID)
                if rname:lower():find(f, 1, true) then
                    table.insert(results, {
                        type = "reagent", name = rname,
                        itemID = itemID, qty = qty,
                    })
                end
            end
        end
    elseif state.category then
        local entry = Recipes:Get(state.profession)
        if entry and entry.crafts then
            for key, craft in pairs(entry.crafts) do
                if (craft.category or IR.L["Other"]) == state.category
                   and (craft.name or ""):lower():find(f, 1, true) then
                    table.insert(results, {
                        type = "recipe", name = craft.name,
                        profession = state.profession, category = state.category, key = key, craft = craft,
                    })
                end
            end
        end
    elseif state.profession then
        matchProfession(state.profession)
    else
        for _, prof in ipairs(Recipes:GetAllProfessions()) do
            local localized = Recipes:GetLocalizedName(prof) or prof
            if prof:lower():find(f, 1, true) or localized:lower():find(f, 1, true) then
                table.insert(results, { type = "profession", name = prof })
            end
            matchProfession(prof)
        end
    end

    return results
end

local function bagCount(itemID)
    if not itemID then return 0 end
    local total = 0
    for _, bag in ipairs(BAG_IDS) do
        local n = GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local link = GetContainerItemLink(bag, slot)
            if link and tonumber(link:match("item:(%d+)")) == itemID then
                local _, count = GetContainerItemInfo(bag, slot)
                total = total + (count or 0)
            end
        end
    end
    return total
end

local function getRow(i, height)
    height = height or ROW_H_DEFAULT
    if rows[i] then
        rows[i]:SetHeight(height)
        rows[i]:ClearAllPoints()
        rows[i]:SetPoint("TOPLEFT", 0, -((i - 1) * (height + 1)))
        return rows[i]
    end
    local r = CreateFrame("Button", nil, listContent)
    r:SetSize(INNER_W, height)
    r:SetPoint("TOPLEFT", 0, -((i - 1) * (height + 1)))
    r:RegisterForClicks("LeftButtonUp")

    local hover = r:CreateTexture(nil, "BACKGROUND")
    hover:SetTexture(1, 1, 1, 0.05)
    hover:SetAllPoints()
    hover:Hide()
    r.hover = hover

    local icon = r:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", 4, 0)
    r.icon = icon

    local primary = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    primary:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -2)
    primary:SetWidth(180)
    primary:SetJustifyH("LEFT")
    r.primary = primary

    local secondary = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    secondary:SetPoint("TOPLEFT", primary, "BOTTOMLEFT", 0, -1)
    secondary:SetWidth(180)
    secondary:SetJustifyH("LEFT")
    r.secondary = secondary

    local rightTop = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rightTop:SetPoint("TOPRIGHT", -6, -4)
    rightTop:SetJustifyH("RIGHT")
    r.rightTop = rightTop

    local rightBottom = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rightBottom:SetPoint("TOPRIGHT", -6, -18)
    rightBottom:SetJustifyH("RIGHT")
    r.rightBottom = rightBottom

    r:SetScript("OnEnter", function(self)
        self.hover:Show()
        if self.tooltipLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.tooltipLink)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)

    rows[i] = r
    return r
end

local function clearRows()
    for _, r in pairs(rows) do
        r:Hide()
        r.tooltipLink = nil
        r:SetScript("OnClick", nil)
    end
end

local function renderProfessions()
    titleFs:SetText("")
    local profs = Recipes:GetAllProfessions()
    if #profs == 0 then
        listContent:SetHeight(1)
        titleFs:SetText(IR.L["No recipes recorded yet. Open a profession window."])
        return
    end
    local filtered = {}
    for _, prof in ipairs(profs) do
        if matchesFilter(prof) then table.insert(filtered, prof) end
    end
    listContent:SetHeight(math.max(#filtered * (ROW_H_DEFAULT + 1), 1))
    for i, prof in ipairs(filtered) do
        local r = getRow(i, ROW_H_DEFAULT)
        local entry = Recipes:Get(prof)
        local nCrafts = 0
        for _ in pairs(entry and entry.crafts or {}) do nCrafts = nCrafts + 1 end
        r.icon:SetTexture(PROF_ICONS[prof] or DEFAULT_PROF_ICON)
        r.primary:SetText("|cffffd200" .. Recipes:GetLocalizedName(prof) .. "|r")
        local key = (nCrafts == 1) and "%d recipe" or "%d recipes"
        r.secondary:SetText(string.format(IR.L[key], nCrafts))
        r.rightTop:SetText("")
        r.rightBottom:SetText("")
        r:SetScript("OnClick", function() setLevel2(prof) end)
        r:Show()
    end
end

local function renderCategories(prof)
    titleFs:SetText(Recipes:GetLocalizedName(prof))
    local entry = Recipes:Get(prof)
    if not entry or not entry.crafts then
        listContent:SetHeight(1)
        return
    end

    local catCounts = {}
    local catBestOrder = {}
    local catIcon = {}
    for _, craft in pairs(entry.crafts) do
        local c = craft.category or IR.L["Other"]
        catCounts[c] = (catCounts[c] or 0) + 1
        local order = craft.order or 999999
        if (not catBestOrder[c]) or order < catBestOrder[c] then
            local texture = craft.icon
            if not texture and craft.productItemID then
                texture = select(10, GetItemInfo(craft.productItemID))
            end
            if texture then
                catBestOrder[c] = order
                catIcon[c] = texture
            end
        end
    end
    local cats = {}
    for c in pairs(catCounts) do
        if matchesFilter(c) then table.insert(cats, c) end
    end
    table.sort(cats)

    listContent:SetHeight(math.max(#cats * (ROW_H_DEFAULT + 1), 1))
    for i, cat in ipairs(cats) do
        local r = getRow(i, ROW_H_DEFAULT)
        r.icon:SetTexture(catIcon[cat] or DEFAULT_CATEGORY_ICON)
        r.primary:SetText("|cffffffff" .. cat .. "|r")
        local n = catCounts[cat]
        local key = (n == 1) and "%d recipe" or "%d recipes"
        r.secondary:SetText(string.format(IR.L[key], n))
        r.rightTop:SetText("")
        r.rightBottom:SetText("")
        r:SetScript("OnClick", function() setLevel3(prof, cat) end)
        r:Show()
    end
end

local function renderRecipes(prof, cat)
    titleFs:SetText(cat)
    local entry = Recipes:Get(prof)
    if not entry or not entry.crafts then
        listContent:SetHeight(1)
        return
    end

    local list = {}
    for key, craft in pairs(entry.crafts) do
        if (craft.category or IR.L["Other"]) == cat and matchesFilter(craft.name) then
            table.insert(list, { key = key, craft = craft })
        end
    end
    table.sort(list, function(a, b)
        local oa = a.craft.order or 999999
        local ob = b.craft.order or 999999
        if oa ~= ob then return oa < ob end
        return (a.craft.name or "") < (b.craft.name or "")
    end)

    listContent:SetHeight(math.max(#list * (ROW_H_RECIPE + 1), 1))
    for i, e in ipairs(list) do
        local r = getRow(i, ROW_H_RECIPE)
        local craft = e.craft
        local productID = craft.productItemID
        local icon = craft.icon
        if not icon and productID then
            icon = select(10, GetItemInfo(productID))
        end
        r.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        local name = craft.name or "?"
        local color = SKILL_COLORS[craft.skillType] or "|cffffffff"
        r.primary:SetText(color .. name .. "|r")

        local productLink
        if productID then
            local _, link = GetItemInfo(productID)
            productLink = link
        end
        r.tooltipLink = productLink
        r.secondary:SetText(craft.skillType or "")
        r.rightTop:SetText("")
        r.rightBottom:SetText("")
        local capturedKey = e.key
        r:SetScript("OnClick", function() setLevel4(prof, cat, capturedKey) end)
        r:Show()
    end
end

local function renderReagents(prof, cat, recipeKey)
    local entry = Recipes:Get(prof)
    if not entry or not entry.crafts then return end
    local craft = entry.crafts[recipeKey]
    if not craft then return end

    titleFs:SetText(craft.name or "?")

    local list = {}
    for itemID, qty in pairs(craft.reagents or {}) do
        local rname = GetItemInfo(itemID)
        if matchesFilter(rname or ("Item #" .. itemID)) then
            table.insert(list, { itemID = itemID, qty = qty })
        end
    end
    table.sort(list, function(a, b)
        local na = GetItemInfo(a.itemID) or ""
        local nb = GetItemInfo(b.itemID) or ""
        return na < nb
    end)

    listContent:SetHeight(math.max(#list * (ROW_H_REAGENT + 1), 1))
    for i, e in ipairs(list) do
        local r = getRow(i, ROW_H_REAGENT)
        local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(e.itemID)
        r.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

        local color = QUALITY_COLORS[quality] or QUALITY_COLORS[1]
        r.primary:SetText(color .. (name or ("Item #" .. e.itemID)) .. "|r")
        r.tooltipLink = link

        local have = bagCount(e.itemID)
        local need = e.qty
        local missing = math.max(0, need - have)
        if missing == 0 then
            r.secondary:SetText(string.format("|cff40c040" .. IR.L["%d / %d (OK)"] .. "|r", have, need))
        else
            r.secondary:SetText(string.format(IR.L["%d / %d in bags"], have, need))
        end

        local market = PriceDB:GetMarketValue(e.itemID)
        if market and market > 0 then
            r.rightTop:SetText(IR:CopperToString(market))
            local total = need * market
            r.rightBottom:SetText("|cffffd700" .. IR:CopperToString(total) .. "|r")
        else
            r.rightTop:SetText("|cff999999" .. IR.L["no data"] .. "|r")
            r.rightBottom:SetText("")
        end

        local capturedID = e.itemID
        local capturedLink = link
        local capturedNeed = math.max(1, need - have)
        r:SetScript("OnClick", function()
            if IR.UI.BuyAuctionList then
                IR.UI.BuyAuctionList:Open(
                    capturedID,
                    capturedLink or ("Item #" .. capturedID),
                    capturedNeed,
                    { onScanDone = function() render() end }
                )
            end
        end)
        r:Show()
    end
end

local function buildBreadcrumb(parent)
    breadcrumbFrame = CreateFrame("Frame", nil, parent)
    breadcrumbFrame:SetPoint("TOPLEFT", 0, 0)
    breadcrumbFrame:SetPoint("TOPRIGHT", 0, 0)
    breadcrumbFrame:SetHeight(22)

    for i = 1, 4 do
        local btn = CreateFrame("Button", nil, breadcrumbFrame)
        btn:SetHeight(20)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetAllPoints()
        fs:SetJustifyH("LEFT")
        btn.text = fs
        btn:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1, 1) end)
        btn:SetScript("OnLeave", function()
            if btn.isLast then fs:SetTextColor(1, 1, 0.5, 1)
            else fs:SetTextColor(0.7, 0.7, 0.85, 1) end
        end)
        breadcrumbBtns[i] = btn
    end
    for i = 1, 3 do
        local sep = breadcrumbFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sep:SetText(">")
        breadcrumbSeps[i] = sep
    end
end

local function renderBreadcrumb()
    local isLast = function(seg)
        if state.recipeKey then return false end
        if state.category then return seg == "category" end
        if state.profession then return seg == "profession" end
        return seg == "root"
    end

    local segments = { { text = IR.L["Professions"], action = setLevel1, key = "root" } }
    if state.profession then
        local prof = state.profession
        table.insert(segments, { text = Recipes:GetLocalizedName(prof), action = function() setLevel2(prof) end, key = "profession" })
    end
    if state.category then
        local prof, cat = state.profession, state.category
        table.insert(segments, { text = cat, action = function() setLevel3(prof, cat) end, key = "category" })
    end

    local prevBtn
    for i = 1, 4 do
        local btn = breadcrumbBtns[i]
        local sep = breadcrumbSeps[i - 1]
        if segments[i] then
            btn.text:SetText(segments[i].text)
            btn:SetScript("OnClick", segments[i].action)
            btn.isLast = isLast(segments[i].key)
            if btn.isLast then
                btn.text:SetTextColor(1, 1, 0.5, 1)
            else
                btn.text:SetTextColor(0.7, 0.7, 0.85, 1)
            end
            btn.text:SetWidth(0)
            btn:SetWidth(math.max(20, math.ceil(btn.text:GetStringWidth()) + 4))
            btn:ClearAllPoints()
            if prevBtn then
                if sep then
                    sep:ClearAllPoints()
                    sep:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
                    sep:Show()
                end
                btn:SetPoint("LEFT", sep or prevBtn, sep and "RIGHT" or "RIGHT", 4, 0)
            else
                btn:SetPoint("LEFT", breadcrumbFrame, "LEFT", 0, 0)
            end
            btn:Show()
            prevBtn = btn
        else
            btn:Hide()
            if sep then sep:Hide() end
        end
    end
    for i = #segments, 3 do
        if breadcrumbSeps[i] then breadcrumbSeps[i]:Hide() end
    end
end

local function renderSearchResults()
    local results = collectDescendantMatches()
    clearRows()

    if #results == 0 then
        titleFs:SetText(IR.L["No results"])
        listContent:SetHeight(1)
        return
    end

    titleFs:SetText(string.format(IR.L["%d results"], #results))

    listContent:SetHeight(math.max(#results * (ROW_H_RECIPE + 1), 1))
    for i, r in ipairs(results) do
        local row = getRow(i, ROW_H_RECIPE)
        row.tooltipLink = nil
        row:SetScript("OnEnter", function(self) self.hover:Show() end)
        row:SetScript("OnLeave", function(self) self.hover:Hide() end)

        if r.type == "profession" then
            row.icon:SetTexture(PROF_ICONS[r.name] or DEFAULT_PROF_ICON)
            row.primary:SetText("|cffffd200" .. Recipes:GetLocalizedName(r.name) .. "|r")
            row.secondary:SetText(IR.L["Profession"])
            local prof = r.name
            row:SetScript("OnClick", function() setLevel2(prof) end)

        elseif r.type == "category" then
            row.icon:SetTexture(DEFAULT_CATEGORY_ICON)
            row.primary:SetText(r.name)
            row.secondary:SetText(Recipes:GetLocalizedName(r.profession))
            local prof, cat = r.profession, r.category
            row:SetScript("OnClick", function() setLevel3(prof, cat) end)

        elseif r.type == "recipe" then
            local icon = r.craft.icon
            if not icon and r.craft.productItemID then
                icon = select(10, GetItemInfo(r.craft.productItemID))
            end
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local color = SKILL_COLORS[r.craft.skillType] or "|cffffffff"
            row.primary:SetText(color .. (r.name or "?") .. "|r")
            row.secondary:SetText(Recipes:GetLocalizedName(r.profession) .. "  >  " .. r.category)
            local prof, cat, key = r.profession, r.category, r.key
            row:SetScript("OnClick", function() setLevel4(prof, cat, key) end)

        elseif r.type == "reagent" then
            local _, link, quality, _, _, _, _, _, _, texture = GetItemInfo(r.itemID)
            row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            local color = QUALITY_COLORS[quality] or QUALITY_COLORS[1]
            row.primary:SetText(color .. (r.name or "?") .. "|r")
            row.secondary:SetText(string.format(IR.L["%d required"], r.qty or 0))
            row.tooltipLink = link
            row:SetScript("OnEnter", function(self)
                self.hover:Show()
                if self.tooltipLink then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(self.tooltipLink)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function(self)
                self.hover:Hide()
                GameTooltip:Hide()
            end)
            local id, capLink, capQty = r.itemID, link, r.qty
            row:SetScript("OnClick", function()
                if IR.UI.BuyAuctionList then
                    IR.UI.BuyAuctionList:Open(
                        id, capLink or ("Item #" .. id), capQty,
                        { onScanDone = function() render() end }
                    )
                end
            end)
        end

        row.rightTop:SetText("")
        row.rightBottom:SetText("")
        row:Show()
    end
end

render = function()
    if not listContent then return end
    clearRows()
    renderBreadcrumb()

    if state.filter and state.filter ~= "" then
        renderSearchResults()
        return
    end

    if state.recipeKey then
        renderReagents(state.profession, state.category, state.recipeKey)
    elseif state.category then
        renderRecipes(state.profession, state.category)
    elseif state.profession then
        renderCategories(state.profession)
    else
        renderProfessions()
    end
end

local function build(parent)
    buildBreadcrumb(parent)

    titleFs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOPLEFT", 0, -26)
    titleFs:SetPoint("TOPRIGHT", 0, -26)
    titleFs:SetJustifyH("CENTER")

    filterEdit = CreateFrame("EditBox", nil, parent)
    filterEdit:SetSize(280, 22)
    filterEdit:SetPoint("TOP", parent, "TOP", 0, -50)
    filterEdit:SetAutoFocus(false)
    filterEdit:SetFontObject("ChatFontNormal")
    filterEdit:SetMaxLetters(64)
    filterEdit:SetTextInsets(6, 6, 0, 0)
    filterEdit:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    filterEdit:SetBackdropColor(0, 0, 0, 0.5)

    local placeholder = filterEdit:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("LEFT", 8, 0)
    placeholder:SetText(IR.L["Search..."])
    placeholder:SetTextColor(0.55, 0.55, 0.55, 1)

    local function refreshPlaceholder()
        local text = filterEdit:GetText() or ""
        if text == "" and not filterEdit:HasFocus() then
            placeholder:Show()
        else
            placeholder:Hide()
        end
    end

    filterEdit:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
    filterEdit:SetScript("OnEditFocusLost", refreshPlaceholder)
    filterEdit:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        state.filter = ""
        self:ClearFocus()
        render()
    end)
    filterEdit:SetScript("OnTextChanged", function(self, userInput)
        refreshPlaceholder()
        if not userInput then return end
        state.filter = (self:GetText() or ""):lower()
        render()
    end)
    filterEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    listScroll = CreateFrame("ScrollFrame", "IronBuyTabScroll", parent, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 0, -76)
    listScroll:SetPoint("BOTTOMRIGHT", -22, 4)

    listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(INNER_W, 1)
    listScroll:SetScrollChild(listContent)
end

function BuyTab:Refresh() render() end

function BuyTab:ResetToRoot() setLevel1() end

IR.UI.AHCompanion:RegisterTab({
    name = "buy",
    title = "Buy",
    tooltip = IR.L["Browse profession recipes and buy reagents from the AH"],
    build = build,
    onShow = function() render() end,
})

IR:On("AUCTION_HOUSE_CLOSED", function() setLevel1() end)

local function buildBuyAISettingsTab(parent)
    local function settings()
        return Iron_DB and Iron_DB.settings and Iron_DB.settings.ironBuy
    end

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, -4)
    title:SetText(IR.L["Default selection strategy:"])

    local radios = {}
    local lastRb
    local strategies = {
        { key = "less", label = IR.L["Less"], hint = IR.L["Cheapest without exceeding"] },
        { key = "exact", label = IR.L["Exact"], hint = IR.L["Cheapest combo summing to target"] },
        { key = "more", label = IR.L["More"], hint = IR.L["Cheapest until target reached (may overshoot)"] },
    }

    for i, s in ipairs(strategies) do
        local rb = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
        if i == 1 then
            rb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        else
            rb:SetPoint("TOPLEFT", lastRb, "BOTTOMLEFT", 0, -4)
        end
        local fs = rb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", rb, "RIGHT", 4, 0)
        fs:SetText(string.format("%s  |cff999999(%s)|r", s.label, s.hint))
        rb.value = s.key
        rb:SetScript("OnClick", function(self)
            local cfg = settings()
            if cfg then cfg.defaultSelectStrategy = self.value end
            for _, other in pairs(radios) do
                other:SetChecked(other == self)
            end
        end)
        radios[s.key] = rb
        lastRb = rb
    end

    local function refreshRadios()
        local cfg = settings()
        local cur = (cfg and cfg.defaultSelectStrategy) or "more"
        for k, rb in pairs(radios) do
            rb:SetChecked(k == cur)
        end
    end
    table.insert(IR.Settings.refreshHandlers, refreshRadios)
end

IR:RegisterSettingsTab({
    name = "ironbuy",
    title = "IronBuy",
    build = buildBuyAISettingsTab,
})
