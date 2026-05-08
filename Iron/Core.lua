-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...
_G.Iron = IR

IR.version = "1.0.0"
IR.dbVersion = 1

local GOLD_ICON = "|cffffd700g|r"
local SILVER_ICON = "|cffc7c7cfs|r"
local COPPER_ICON = "|cffeda55fc|r"

function IR:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffIron|r: " .. tostring(msg))
end

function IR:AttachTooltip(widget, text, anchor)
    if not widget or not text then return end
    widget:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, anchor or "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

IR.debugBuffer = {}
local MAX_LOG_LINES = 500

function IR:Debug(msg)
    msg = tostring(msg or "")
    local line = "[" .. date("%H:%M:%S") .. "] " .. msg
    table.insert(IR.debugBuffer, line)
    if #IR.debugBuffer > MAX_LOG_LINES then
        table.remove(IR.debugBuffer, 1)
    end
    if Iron_DB then
        Iron_DB.debugLog = Iron_DB.debugLog or {}
        table.insert(Iron_DB.debugLog, line)
        if #Iron_DB.debugLog > MAX_LOG_LINES then
            table.remove(Iron_DB.debugLog, 1)
        end
    end
    if Iron_DB and Iron_DB.settings and Iron_DB.settings.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9933MAI debug|r: " .. msg)
    end
    if IR.logsFrame and IR.logsFrame:IsShown() then
        IR:RefreshLogs()
    end
end

local logsFrame
function IR:RefreshLogs()
    if not logsFrame or not logsFrame.editBox then return end
    logsFrame.editBox:SetText(table.concat(IR.debugBuffer, "\n"))
end

function IR:OpenLogs()
    if not logsFrame then
        local f = CreateFrame("Frame", "IronLogsFrame", UIParent)
        f:Hide()
        f:SetSize(680, 480)
        f:SetPoint("CENTER")
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
        drag:SetPoint("TOPRIGHT", -32, -8)
        drag:SetHeight(20)
        drag:RegisterForDrag("LeftButton")
        drag:SetScript("OnDragStart", function() f:StartMoving() end)
        drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -14)
        title:SetText("Iron - Logs")

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        close:SetScript("OnClick", function() f:Hide() end)

        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", 16, -42)
        hint:SetText("Click in box -> Ctrl+A to select all -> Ctrl+C to copy")

        local sf = CreateFrame("ScrollFrame", "IronLogsScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 16, -64)
        sf:SetPoint("BOTTOMRIGHT", -36, 48)

        local edit = CreateFrame("EditBox", nil, sf)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(620)
        edit:SetMaxLetters(0)
        edit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
        sf:SetScrollChild(edit)
        f.editBox = edit

        local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        refreshBtn:SetSize(90, 22)
        refreshBtn:SetPoint("BOTTOMRIGHT", -110, 14)
        refreshBtn:SetText("Refresh")
        refreshBtn:SetScript("OnClick", function() IR:RefreshLogs() end)

        local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        clearBtn:SetSize(90, 22)
        clearBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 4, 0)
        clearBtn:SetText("Clear")
        clearBtn:SetScript("OnClick", function()
            IR.debugBuffer = {}
            if Iron_DB then Iron_DB.debugLog = {} end
            IR:RefreshLogs()
        end)

        tinsert(UISpecialFrames, "IronLogsFrame")
        logsFrame = f
        IR.logsFrame = f
    end
    IR:RefreshLogs()
    logsFrame:Show()
end

function IR:CopperToString(copper)
    copper = tonumber(copper) or 0
    local sign = ""
    if copper < 0 then
        sign = "-"
        copper = -copper
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        return string.format("%s%d%s %d%s %d%s", sign, g, GOLD_ICON, s, SILVER_ICON, c, COPPER_ICON)
    elseif s > 0 then
        return string.format("%s%d%s %d%s", sign, s, SILVER_ICON, c, COPPER_ICON)
    else
        return string.format("%s%d%s", sign, c, COPPER_ICON)
    end
end

local function defaultDB()
    return {
        version = IR.dbVersion,
        firstInstall = time(),
        loadCount = 0,
        prices = {},
        recipes = {},
        lastFullScan = 0,
        settings = {
            debug = false,
            ironMail = {
                takeMoney = true,
                takeItems = true,
                deleteEmpty = true,
                skipCOD = true,
                throttleSeconds = 0.3,
            },
            ironVault = {
                groups = {},
                nextGroupID = 1,
                autoOpenOnBankShow = true,
                showSurplusWarning = true,
            },
            ironSell = {
                blacklist = {},
                undercutPercent = 5,
                defaultDuration = 12,
                stackStrategy = "full",
                includeGrey = false,
                staleThresholdSeconds = 3600,
            },
            ironBuy = {
                defaultQuantity = 20,
                autoSelectCheapest = true,
                sortCraftsBy = "skill",
                showOnlyCraftable = true,
                purchaseDelaySeconds = 0.3,
                lastSelectedTab = "sell",
                defaultSelectStrategy = "more",
            },
        },
    }
end

local function deepFill(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            deepFill(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

local SETTINGS_RENAME_MAP = {
    postAI = "ironMail",
    vaultAI = "ironVault",
    sellAI = "ironSell",
    buyAI = "ironBuy",
}

local function migrateRenamedSettings()
    if type(Iron_DB) ~= "table" or type(Iron_DB.settings) ~= "table" then return end
    local s = Iron_DB.settings
    for oldKey, newKey in pairs(SETTINGS_RENAME_MAP) do
        if s[oldKey] ~= nil and s[newKey] == nil then
            s[newKey] = s[oldKey]
        end
        s[oldKey] = nil
    end
end

-- Move shared recipes / blacklist / vault groups out of the account-wide
-- bucket and into a one-shot legacy archive. The user explicitly imports it
-- onto the right character via /iron import (see cmdImport).
local function migrateToPerChar()
    if Iron_DB.perCharMigrated then return end
    Iron_DB.perCharMigrated = true

    local s = Iron_DB.settings or {}
    local sellS = s.ironSell or {}
    local vaultS = s.ironVault or {}

    local hasRecipes = type(Iron_DB.recipes) == "table" and next(Iron_DB.recipes) ~= nil
    local hasBlacklist = type(sellS.blacklist) == "table" and next(sellS.blacklist) ~= nil
    local hasGroups = type(vaultS.groups) == "table" and next(vaultS.groups) ~= nil

    if hasRecipes or hasBlacklist or hasGroups then
        Iron_DB.legacy = {
            recipes = Iron_DB.recipes or {},
            blacklist = sellS.blacklist or {},
            groups = vaultS.groups or {},
            nextGroupID = vaultS.nextGroupID or 1,
        }
        Iron_DB.legacyAvailable = true
    end

    Iron_DB.recipes = {}
    if s.ironSell then s.ironSell.blacklist = {} end
    if s.ironVault then
        s.ironVault.groups = {}
        s.ironVault.nextGroupID = 1
    end
end

local function ensureDB()
    if type(Iron_DB) ~= "table" then
        Iron_DB = {}
    end
    migrateRenamedSettings()
    deepFill(Iron_DB, defaultDB())
    migrateToPerChar()
    Iron_DB.chars = Iron_DB.chars or {}
end

function IR:CharKey()
    local realm = (GetRealmName and GetRealmName()) or "unknown"
    local name = UnitName and UnitName("player") or nil
    if not name or name == "" or name == "Unknown" then return nil end
    return realm .. "-" .. name
end

function IR:CharDB()
    if type(Iron_DB) ~= "table" then return nil end
    local key = self:CharKey()
    if not key then return nil end
    Iron_DB.chars = Iron_DB.chars or {}
    local bucket = Iron_DB.chars[key]
    if not bucket then
        bucket = { recipes = {}, blacklist = {}, vault = { groups = {}, nextGroupID = 1 } }
        Iron_DB.chars[key] = bucket
    end
    bucket.recipes = bucket.recipes or {}
    bucket.blacklist = bucket.blacklist or {}
    bucket.vault = bucket.vault or { groups = {}, nextGroupID = 1 }
    bucket.vault.groups = bucket.vault.groups or {}
    bucket.vault.nextGroupID = bucket.vault.nextGroupID or 1
    return bucket
end

IR.slashHandlers = {}
IR.slashOrder = {}

function IR:RegisterSlashCommand(name, handler, helpText)
    if not IR.slashHandlers[name] then
        table.insert(IR.slashOrder, name)
    end
    IR.slashHandlers[name] = { handler = handler, help = helpText or "" }
end

local function handleSlash(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    if not cmd then
        cmd = "help"
        rest = ""
    end
    cmd = cmd:lower()
    local entry = IR.slashHandlers[cmd]
    if entry then
        entry.handler(rest or "")
    else
        IR:Print(string.format(IR.L["Unknown command: %s. Try /iron help"], cmd))
    end
end

local function cmdHelp()
    IR:Print(IR.L["Commands:"])
    for _, name in ipairs(IR.slashOrder) do
        local entry = IR.slashHandlers[name]
        DEFAULT_CHAT_FRAME:AddMessage("  /iron " .. name .. " (" .. IR.L[entry.help] .. ")")
    end
end

local function cmdStats()
    local first = Iron_DB.firstInstall or time()
    IR:Print(string.format(IR.L["Loaded %d times since first install (on %s)."],
        Iron_DB.loadCount or 0, date("%Y-%m-%d", first)))
end

local function cmdDebug(rest)
    rest = (rest or ""):lower()
    local changed = false
    if rest == "on" then
        Iron_DB.settings.debug = true
        IR:Print(IR.L["Debug ON"])
        changed = true
    elseif rest == "off" then
        Iron_DB.settings.debug = false
        IR:Print(IR.L["Debug OFF"])
        changed = true
    else
        local state = Iron_DB.settings.debug and IR.L["ON"] or IR.L["OFF"]
        IR:Print(string.format(IR.L["Debug is %s. Use /iron debug on|off"], state))
    end
    if changed and IR.Settings and IR.Settings.Refresh then
        IR.Settings.Refresh()
    end
end

IR.eventCallbacks = {}
local eventFrame = CreateFrame("Frame")
IR.eventFrame = eventFrame

function IR:On(event, callback)
    if not IR.eventCallbacks[event] then
        IR.eventCallbacks[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(IR.eventCallbacks[event], callback)
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded == addonName then
            ensureDB()
            Iron_DB.loadCount = (Iron_DB.loadCount or 0) + 1
            IR:Debug("Init done. loadCount=" .. Iron_DB.loadCount)
        end
    end
    local cbs = IR.eventCallbacks[event]
    if cbs then
        for i = 1, #cbs do
            local ok, err = pcall(cbs[i], ...)
            if not ok then
                IR:Print("|cffff5555error|r in " .. event .. ": " .. tostring(err))
            end
        end
    end
end)

SLASH_IRON1 = "/iron"
SLASH_IRON2 = "/ir"
SlashCmdList["IRON"] = handleSlash

local SUPPORTED_LOCALES = {
    enUS = true, enGB = true,
    frFR = true,
    deDE = true,
    esES = true,
    zhCN = true,
}

local function cmdAbout()
    IR:Print("|cff66ccffIron|r v" .. (IR.version or "?"))
    IR:Print(IR.L["Mail, bank, and AH automation for Ascension"])
    DEFAULT_CHAT_FRAME:AddMessage("  Copyright (c) 2026 SpySpoTt3d, MIT License")
    local loc = IR.locale or "?"
    local status = SUPPORTED_LOCALES[loc] and "|cff66ff66native|r" or "|cffffaa00fallback to English|r"
    DEFAULT_CHAT_FRAME:AddMessage("  locale: " .. loc .. " (" .. status .. ")")
    DEFAULT_CHAT_FRAME:AddMessage("  /iron help    " .. IR.L["show this help"])
    DEFAULT_CHAT_FRAME:AddMessage("  /iron config  " .. IR.L["open settings panel"])
    DEFAULT_CHAT_FRAME:AddMessage("  /iron stats   " .. IR.L["show load statistics"])
    DEFAULT_CHAT_FRAME:AddMessage("  /iron debug   " .. IR.L["toggle debug mode, on|off"])
end

local function cmdImport(rest)
    rest = (rest or ""):lower():match("^%s*(.-)%s*$") or ""
    if not Iron_DB.legacyAvailable or type(Iron_DB.legacy) ~= "table" then
        IR:Print(IR.L["No legacy archive to import."])
        return
    end
    if rest == "discard" then
        Iron_DB.legacy = nil
        Iron_DB.legacyAvailable = false
        IR:Print(IR.L["Legacy archive discarded."])
        return
    end

    local char = IR:CharDB()
    if not char then
        IR:Print(IR.L["Unable to resolve current character; try again after login."])
        return
    end
    local legacy = Iron_DB.legacy

    local recipeCount = 0
    for prof, entry in pairs(legacy.recipes or {}) do
        if char.recipes[prof] == nil then
            char.recipes[prof] = entry
            recipeCount = recipeCount + 1
        end
    end

    local blCount = 0
    for itemID in pairs(legacy.blacklist or {}) do
        if not char.blacklist[itemID] then
            char.blacklist[itemID] = true
            blCount = blCount + 1
        end
    end

    local groupCount = 0
    local nextID = char.vault.nextGroupID or 1
    for existingID in pairs(char.vault.groups) do
        if (existingID + 1) > nextID then nextID = existingID + 1 end
    end
    for id, g in pairs(legacy.groups or {}) do
        local targetID = id
        if char.vault.groups[targetID] then
            targetID = nextID
            nextID = nextID + 1
            g.id = targetID
        elseif (targetID + 1) > nextID then
            nextID = targetID + 1
        end
        char.vault.groups[targetID] = g
        groupCount = groupCount + 1
    end
    char.vault.nextGroupID = math.max(nextID, legacy.nextGroupID or 1)

    Iron_DB.legacy = nil
    Iron_DB.legacyAvailable = false

    IR:Print(string.format(IR.L["Imported: %d professions, %d blacklist entries, %d groups."],
        recipeCount, blCount, groupCount))
    if IR.Settings and IR.Settings.Refresh then
        IR.Settings.Refresh()
    end
end

IR:On("PLAYER_LOGIN", function()
    if Iron_DB and Iron_DB.legacyAvailable then
        IR:Print(IR.L["Iron data is now per-character. Use /iron import to copy the previous shared data to this character, or /iron import discard to discard it."])
    end
end)

IR:RegisterSlashCommand("help", cmdHelp, "show this help")
IR:RegisterSlashCommand("stats", cmdStats, "show load statistics")
IR:RegisterSlashCommand("debug", cmdDebug, "toggle debug mode, on|off")
IR:RegisterSlashCommand("logs", function() IR:OpenLogs() end, "open log viewer (copyable)")
IR:RegisterSlashCommand("about", cmdAbout, "show addon version and overview")
IR:RegisterSlashCommand("import", cmdImport, "import legacy shared data to this character (or 'discard' to drop)")
