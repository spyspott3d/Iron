-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.Recipes = {}
local Recipes = IR.Recipes

local SCAN_DEBOUNCE = 0.5

-- Map any localized profession name to its canonical English name so the
-- recipe DB stays single-keyed even when the user switches client locale.
local PROFESSION_CANONICAL = {
    -- enUS (identity)
    ["Alchemy"] = "Alchemy", ["Blacksmithing"] = "Blacksmithing",
    ["Cooking"] = "Cooking", ["Enchanting"] = "Enchanting",
    ["Engineering"] = "Engineering", ["First Aid"] = "First Aid",
    ["Fishing"] = "Fishing", ["Herbalism"] = "Herbalism",
    ["Inscription"] = "Inscription", ["Jewelcrafting"] = "Jewelcrafting",
    ["Leatherworking"] = "Leatherworking", ["Mining"] = "Mining",
    ["Skinning"] = "Skinning", ["Tailoring"] = "Tailoring",
    ["Smelting"] = "Smelting", ["Lockpicking"] = "Lockpicking",
    ["Poisons"] = "Poisons", ["Runeforging"] = "Runeforging",
    -- frFR
    ["Alchimie"] = "Alchemy", ["Forge"] = "Blacksmithing",
    ["Cuisine"] = "Cooking", ["Enchantement"] = "Enchanting",
    ["Ingénierie"] = "Engineering", ["Secourisme"] = "First Aid",
    ["Pêche"] = "Fishing", ["Herboristerie"] = "Herbalism",
    ["Calligraphie"] = "Inscription", ["Joaillerie"] = "Jewelcrafting",
    ["Travail du cuir"] = "Leatherworking", ["Minage"] = "Mining",
    ["Dépeçage"] = "Skinning", ["Couture"] = "Tailoring",
    ["Fonte"] = "Smelting", ["Crochetage"] = "Lockpicking",
    ["Inscription en runes"] = "Runeforging",
}

local function canonicalProfession(name)
    if not name then return nil end
    return PROFESSION_CANONICAL[name] or name
end

local PROFESSION_DISPLAY = {
    frFR = {
        Alchemy = "Alchimie", Blacksmithing = "Forge",
        Cooking = "Cuisine", Enchanting = "Enchantement",
        Engineering = "Ingénierie", ["First Aid"] = "Secourisme",
        Fishing = "Pêche", Herbalism = "Herboristerie",
        Inscription = "Calligraphie", Jewelcrafting = "Joaillerie",
        Leatherworking = "Travail du cuir", Mining = "Minage",
        Skinning = "Dépeçage", Tailoring = "Couture",
        Smelting = "Fonte", Lockpicking = "Crochetage",
        Runeforging = "Inscription en runes",
    },
}

function Recipes:GetLocalizedName(canonicalName)
    if not canonicalName then return canonicalName end
    local map = PROFESSION_DISPLAY[IR.locale or ""]
    return (map and map[canonicalName]) or canonicalName
end

local function db()
    return Iron_DB
end

local scanTimer = CreateFrame("Frame")
scanTimer:Hide()
local timerElapsed = 0

scanTimer:SetScript("OnUpdate", function(self, dt)
    timerElapsed = timerElapsed + dt
    if timerElapsed >= SCAN_DEBOUNCE then
        timerElapsed = 0
        self:Hide()
        Recipes:Snapshot()
    end
end)

-- Track the last successfully snapshotted profession so we skip rescans driven
-- by the user collapsing/expanding categories (which also fire
-- TRADE_SKILL_UPDATE). Reset on TRADE_SKILL_CLOSE so reopening the window
-- re-scans, picking up any recipes learned between sessions.
local lastSnapshotProfession

local function currentProfession()
    if not GetTradeSkillLine then return nil end
    local p = GetTradeSkillLine()
    if not p or p == "UNKNOWN" or p == "" then return nil end
    return canonicalProfession(p)
end

local function scheduleScan()
    local prof = currentProfession()
    if prof and prof == lastSnapshotProfession then return end
    timerElapsed = 0
    scanTimer:Show()
end

local function cancelScheduledScan()
    timerElapsed = 0
    scanTimer:Hide()
end

local function expandAllHeaders()
    if not GetNumTradeSkills or not GetTradeSkillInfo or not ExpandTradeSkillSubClass then return end
    local guard = 0
    local i = 1
    while i <= (GetNumTradeSkills() or 0) do
        local _, skillType, _, isExpanded = GetTradeSkillInfo(i)
        if skillType == "header" and not isExpanded then
            ExpandTradeSkillSubClass(i)
        end
        i = i + 1
        guard = guard + 1
        if guard > 5000 then break end
    end
end

function Recipes:Snapshot()
    if Recipes.scanning then return end
    if not GetTradeSkillLine or not GetNumTradeSkills then return end
    local rawProfession = GetTradeSkillLine()
    if not rawProfession or rawProfession == "UNKNOWN" or rawProfession == "" then return end
    local profession = canonicalProfession(rawProfession)

    Recipes.scanning = true
    expandAllHeaders()

    local n = GetNumTradeSkills() or 0
    local crafts = {}
    local count = 0
    local productMisses = 0
    local currentCategory = nil

    for i = 1, n do
        local skillName, skillType = GetTradeSkillInfo(i)
        if skillType == "header" then
            currentCategory = skillName
        elseif skillType and skillName then
            local productLink = GetTradeSkillItemLink(i)
            local productItemID
            if productLink then
                productItemID = tonumber(productLink:match("item:(%d+)"))
            end

            local numReagents = GetTradeSkillNumReagents(i) or 0
            local reagents = {}
            local firstReagentID
            for j = 1, numReagents do
                local reagentLink = GetTradeSkillReagentItemLink(i, j)
                local _, _, reagentCount = GetTradeSkillReagentInfo(i, j)
                if reagentLink and reagentCount and reagentCount > 0 then
                    local reagentID = tonumber(reagentLink:match("item:(%d+)"))
                    if reagentID then
                        reagents[reagentID] = (reagents[reagentID] or 0) + reagentCount
                        if not firstReagentID then firstReagentID = reagentID end
                    end
                end
            end

            local icon = GetTradeSkillIcon and GetTradeSkillIcon(i) or nil
            if not icon and productItemID then
                icon = select(10, GetItemInfo(productItemID))
            end
            if not icon and firstReagentID then
                icon = select(10, GetItemInfo(firstReagentID))
            end

            local key = productItemID and tostring(productItemID) or ("enchant:" .. skillName)
            if not productItemID then productMisses = productMisses + 1 end

            crafts[key] = {
                name = skillName,
                productItemID = productItemID,
                icon = icon,
                skillType = skillType,
                category = currentCategory or IR.L["Other"],
                order = i,
                reagents = reagents,
            }
            count = count + 1
        end
    end

    local d = db()
    if not d then
        Recipes.scanning = false
        return
    end
    d.recipes = d.recipes or {}
    d.recipes[profession] = {
        scannedAt = time(),
        learnedBy = UnitName("player"),
        crafts = crafts,
    }

    IR:Debug(string.format("Recipes: %s -> %d crafts (%d entries scanned, %d without product link)",
        profession, count, n, productMisses))

    -- Only mark the session as scanned if we actually found craft entries.
    -- An empty result means TRADE_SKILL_SHOW fired before the server delivered
    -- the recipe data; leave the flag clear so the next UPDATE retries.
    if count > 0 then
        lastSnapshotProfession = profession
    end
    Recipes.scanning = false
end

-- One-shot migration that folds locale-variant entries (e.g. "Couture") into
-- their canonical English key (e.g. "Tailoring"). Run once per session at
-- load. On per-craft conflict, keep the entry from the more recent scan.
function Recipes:MigrateLocaleDuplicates()
    local d = db()
    if not d or type(d.recipes) ~= "table" then return end

    local nonCanonical = {}
    for prof in pairs(d.recipes) do
        local canon = canonicalProfession(prof)
        if canon ~= prof then
            table.insert(nonCanonical, { from = prof, to = canon })
        end
    end
    if #nonCanonical == 0 then return end

    local mergedFrom, mergedInto = 0, 0
    for _, m in ipairs(nonCanonical) do
        local src = d.recipes[m.from]
        local dst = d.recipes[m.to]
        if src and not dst then
            d.recipes[m.to] = src
            mergedInto = mergedInto + 1
        elseif src and dst then
            local srcWins = (src.scannedAt or 0) > (dst.scannedAt or 0)
            dst.crafts = dst.crafts or {}
            for key, craft in pairs(src.crafts or {}) do
                if dst.crafts[key] == nil or srcWins then
                    dst.crafts[key] = craft
                end
            end
            if srcWins then
                dst.scannedAt = src.scannedAt
                dst.learnedBy = src.learnedBy
            end
            mergedFrom = mergedFrom + 1
        end
        d.recipes[m.from] = nil
    end

    IR:Debug(string.format("Recipes: migrated %d locale-variant profession(s), merged %d, renamed %d",
        #nonCanonical, mergedFrom, mergedInto))
end

function Recipes:Get(profession)
    local d = db()
    if not d or not d.recipes then return nil end
    return d.recipes[canonicalProfession(profession)]
end

function Recipes:GetAllProfessions()
    local d = db()
    local out = {}
    if not d or not d.recipes then return out end
    for prof in pairs(d.recipes) do table.insert(out, prof) end
    table.sort(out)
    return out
end

IR:On("TRADE_SKILL_SHOW", scheduleScan)
IR:On("TRADE_SKILL_UPDATE", scheduleScan)
IR:On("TRADE_SKILL_CLOSE", function()
    cancelScheduledScan()
    lastSnapshotProfession = nil
end)

IR:On("PLAYER_LOGIN", function() Recipes:MigrateLocaleDuplicates() end)

