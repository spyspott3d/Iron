-- Iron, Copyright (c) 2026 SpySpoTt3d, MIT License

local addonName, IR = ...

IR.IronMail = {}
local IronMail = IR.IronMail

local ATTACH_MAX = ATTACHMENTS_MAX_RECEIVE or 16

local STAGE_MAIL_START = 1
local STAGE_TAKE_MONEY = 2
local STAGE_TAKE_ITEM = 3
local STAGE_VERIFY_ITEM = 4
local STAGE_DELETE = 5

local function settings()
    return Iron_DB and Iron_DB.settings and Iron_DB.settings.ironMail or {}
end

local function newState()
    return {
        running = false,
        aborted = false,
        singleMail = false,
        stage = nil,
        mailIndex = 0,
        attachIndex = 0,
        retryCount = 0,
        totalMails = 0,
        stats = { mails = 0, items = 0, money = 0, codSkipped = 0, errors = 0 },
    }
end

local state = newState()
IronMail.mailboxOpen = false

local function countFreeSlots()
    local total = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local free = GetContainerNumFreeSlots(bag)
        total = total + (free or 0)
    end
    return total
end

local timerFrame = CreateFrame("Frame")
timerFrame:Hide()
local timerElapsed = 0
local timerCallback
timerFrame:SetScript("OnUpdate", function(self, dt)
    timerElapsed = timerElapsed + dt
    if timerCallback and timerElapsed >= timerCallback.delay then
        local fn = timerCallback.fn
        timerCallback = nil
        timerElapsed = 0
        self:Hide()
        fn()
    end
end)

local function schedule(delay, fn)
    timerCallback = { delay = delay, fn = fn }
    timerElapsed = 0
    timerFrame:Show()
end

local function notifyChange()
    if IronMail.onChange then
        local ok, err = pcall(IronMail.onChange)
        if not ok then IR:Print("|cffff5555postai ui error|r: " .. tostring(err)) end
    end
end

local step

local function syncMinimapMail()
    -- The minimap envelope icon is tied to UPDATE_PENDING_MAIL which the
    -- server only fires periodically. After we drain the inbox via TakeInbox*
    -- the client-side HasNewMail() updates immediately but the icon doesn't,
    -- so we sync it manually.
    if MiniMapMailFrame then
        if HasNewMail and HasNewMail() then
            MiniMapMailFrame:Show()
        else
            MiniMapMailFrame:Hide()
        end
    end
end

local function finish(reason)
    state.running = false
    local s = state.stats
    if reason == "invfull" then
        local at = state.totalMails - state.mailIndex + 1
        if at < 1 then at = 1 end
        if at > state.totalMails then at = state.totalMails end
        IR:Print(string.format(IR.L["Inventory full, stopped at mail %d/%d"], at, state.totalMails))
    elseif reason == "closed" then
        local at = state.totalMails - state.mailIndex + 1
        if at < 1 then at = 1 end
        if at > state.totalMails then at = state.totalMails end
        IR:Print(string.format(IR.L["Mailbox closed, stopped at mail %d/%d"], at, state.totalMails))
    end
    if not state.singleMail or reason ~= "done" then
        IR:Print(string.format(IR.L["%d mails processed, %d items, %s collected, %d COD skipped, %d errors"],
            s.mails, s.items, IR:CopperToString(s.money), s.codSkipped, s.errors))
    end
    syncMinimapMail()
    notifyChange()
end

step = function()
    if not state.running then return end
    if state.aborted then finish("closed"); return end
    if not IronMail.mailboxOpen then finish("closed"); return end

    local i = state.mailIndex
    if i < 1 then finish("done"); return end

    local s = settings()
    local throttle = s.throttleSeconds or 0.3

    if state.stage == STAGE_MAIL_START then
        local _, _, sender, _, _, COD, _, _ = GetInboxHeaderInfo(i)
        if COD and COD > 0 and s.skipCOD then
            state.stats.codSkipped = state.stats.codSkipped + 1
            IR:Debug(string.format("Skipped COD mail %d (%s)", i, tostring(sender)))
            if state.singleMail then state.mailIndex = 0 else state.mailIndex = i - 1 end
            state.stage = STAGE_MAIL_START
            notifyChange()
            schedule(0.05, step)
            return
        end
        state.stage = STAGE_TAKE_MONEY
        schedule(0.05, step)
        return
    end

    if state.stage == STAGE_TAKE_MONEY then
        local _, _, _, _, money, _, _, _ = GetInboxHeaderInfo(i)
        if money and money > 0 and s.takeMoney then
            TakeInboxMoney(i)
            state.stats.money = state.stats.money + money
        end
        state.stage = STAGE_TAKE_ITEM
        state.attachIndex = ATTACH_MAX
        state.retryCount = 0
        notifyChange()
        schedule(0.05, step)
        return
    end

    if state.stage == STAGE_TAKE_ITEM then
        if not s.takeItems then
            state.stage = STAGE_DELETE
            schedule(0.05, step)
            return
        end
        while state.attachIndex >= 1 do
            local name = GetInboxItem(i, state.attachIndex)
            if name then break end
            state.attachIndex = state.attachIndex - 1
        end
        if state.attachIndex < 1 then
            state.stage = STAGE_DELETE
            schedule(0.05, step)
            return
        end
        if countFreeSlots() < 1 then
            finish("invfull")
            return
        end
        TakeInboxItem(i, state.attachIndex)
        state.stage = STAGE_VERIFY_ITEM
        schedule(throttle, step)
        return
    end

    if state.stage == STAGE_VERIFY_ITEM then
        local stillThere = GetInboxItem(i, state.attachIndex)
        if stillThere then
            if state.retryCount < 1 then
                state.retryCount = state.retryCount + 1
                TakeInboxItem(i, state.attachIndex)
                schedule(0.5, step)
                return
            else
                state.stats.errors = state.stats.errors + 1
                IR:Debug(string.format("Give up on attachment %d of mail %d", state.attachIndex, i))
                state.attachIndex = state.attachIndex - 1
                state.retryCount = 0
                state.stage = STAGE_TAKE_ITEM
                schedule(0.05, step)
                return
            end
        else
            state.stats.items = state.stats.items + 1
            state.attachIndex = state.attachIndex - 1
            state.retryCount = 0
            state.stage = STAGE_TAKE_ITEM
            schedule(0.05, step)
            return
        end
    end

    if state.stage == STAGE_DELETE then
        local _, _, _, _, money, _, _, hasItem = GetInboxHeaderInfo(i)
        local empty = (not hasItem) and (not money or money == 0)
        if empty and s.deleteEmpty then
            DeleteInboxItem(i)
        end
        state.stats.mails = state.stats.mails + 1
        if state.singleMail then state.mailIndex = 0 else state.mailIndex = i - 1 end
        state.stage = STAGE_MAIL_START
        notifyChange()
        schedule(0.05, step)
        return
    end
end

function IronMail:Start()
    IR:Debug("IronMail:Start, running=" .. tostring(state.running) .. ", mailboxOpen=" .. tostring(IronMail.mailboxOpen))
    if state.running then
        IR:Print(IR.L["IronMail is already running"])
        return
    end
    if not IronMail.mailboxOpen then
        IR:Debug("IronMail:Start aborted, mailboxOpen=false")
        return
    end
    local n = GetInboxNumItems and GetInboxNumItems() or 0
    IR:Debug("IronMail:Start, n=" .. tostring(n))
    if n < 1 then return end

    state = newState()
    state.running = true
    state.totalMails = n
    state.mailIndex = n
    state.stage = STAGE_MAIL_START

    if n >= 50 then
        IR:Print(IR.L["Inbox has 50 mails (server cap). Process again after refreshing if more remain."])
    end

    notifyChange()
    schedule(0.05, step)
end

function IronMail:Abort()
    state.aborted = true
end

function IronMail:IsRunning()
    return state.running
end

function IronMail:GetProgress()
    local current = state.totalMails - state.mailIndex + 1
    if current < 1 then current = 1 end
    if current > state.totalMails then current = state.totalMails end
    return state.running, current, state.totalMails
end

function IronMail:TakeMail(mailIndex)
    IR:Debug("IronMail:TakeMail i=" .. tostring(mailIndex) .. ", running=" .. tostring(state.running) .. ", mailboxOpen=" .. tostring(IronMail.mailboxOpen))
    if state.running then return end
    if not IronMail.mailboxOpen then return end
    if not mailIndex or mailIndex < 1 then return end

    state = newState()
    state.running = true
    state.singleMail = true
    state.totalMails = mailIndex
    state.mailIndex = mailIndex
    state.stage = STAGE_MAIL_START
    notifyChange()
    schedule(0.05, step)
end

function IronMail:DeleteMail(mailIndex)
    if not IronMail.mailboxOpen or not mailIndex then return end
    DeleteInboxItem(mailIndex)
end

function IronMail:ReturnMail(mailIndex)
    if not IronMail.mailboxOpen or not mailIndex then return end
    ReturnInboxItem(mailIndex)
end

IR:On("MAIL_SHOW", function()
    IronMail.mailboxOpen = true
    notifyChange()
end)

IR:On("MAIL_CLOSED", function()
    IronMail.mailboxOpen = false
    if state.running then state.aborted = true end
    syncMinimapMail()
    notifyChange()
end)

IR:On("MAIL_INBOX_UPDATE", function()
    notifyChange()
end)

local function buildPostAITab(parent)
    local function check(labelKey, settingKey, anchor, offsetY)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        if anchor then
            cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or -4)
        else
            cb:SetPoint("TOPLEFT", 8, -8)
        end
        local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        fs:SetText(IR.L[labelKey])
        local function refresh()
            cb:SetChecked(settings()[settingKey] and true or false)
        end
        cb:SetScript("OnShow", refresh)
        cb:SetScript("OnClick", function(self)
            if not (Iron_DB and Iron_DB.settings and Iron_DB.settings.ironMail) then return end
            Iron_DB.settings.ironMail[settingKey] = self:GetChecked() and true or false
        end)
        table.insert(IR.Settings.refreshHandlers, refresh)
        return cb
    end

    local sectionTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sectionTitle:SetPoint("TOPLEFT", 8, -8)
    sectionTitle:SetText(IR.L["'Take all' options"])

    local sectionDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sectionDesc:SetPoint("TOPLEFT", sectionTitle, "BOTTOMLEFT", 0, -2)
    sectionDesc:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -28)
    sectionDesc:SetJustifyH("LEFT")
    sectionDesc:SetText(IR.L["These options affect only the 'Take all' button. Per-mail buttons always ask for confirmation on COD."])

    local cb1 = check("Take attached gold", "takeMoney", sectionDesc, -8)
    local cb2 = check("Take attached items", "takeItems", cb1, -4)
    local cb3 = check("Skip COD mails", "skipCOD", cb2, -4)

    -- COD safety: warning text right-aligned on the same row as the checkbox
    local warning = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warning:SetPoint("LEFT", cb3, "RIGHT", 200, 0)
    warning:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    warning:SetJustifyH("RIGHT")
    warning:SetTextColor(1, 0.6, 0.2, 1)
    warning:SetText(IR.L["! In Take all, unchecked = COD paid auto"])

    local cb4 = check("Delete empty mails after processing", "deleteEmpty", cb3, -4)

    -- Wrap the OnClick so unchecking (allow COD) requires confirmation
    cb3:SetScript("OnClick", function(self)
        if not (Iron_DB and Iron_DB.settings and Iron_DB.settings.ironMail) then return end
        local newValue = self:GetChecked() and true or false
        if not newValue then
            -- User is DISABLING the safety. Confirm.
            self:SetChecked(true) -- revert until they confirm
            StaticPopupDialogs["IRON_COD_DISABLE"] = StaticPopupDialogs["IRON_COD_DISABLE"] or {
                text = IR.L["Disable COD safety?\n\nWith this off, taking COD mails will pay them automatically with your gold. Are you sure?"],
                button1 = ACCEPT or IR.L["Confirm"],
                button2 = CANCEL or IR.L["Cancel"],
                OnAccept = function()
                    Iron_DB.settings.ironMail.skipCOD = false
                    cb3:SetChecked(false)
                end,
                timeout = 0,
                whileDead = 1,
                hideOnEscape = 1,
                showAlert = 1,
            }
            StaticPopup_Show("IRON_COD_DISABLE")
        else
            Iron_DB.settings.ironMail.skipCOD = true
        end
    end)

    local slider = CreateFrame("Slider", "IronPostThrottleSlider", parent, "OptionsSliderTemplate")
    slider:SetWidth(220)
    slider:SetHeight(16)
    slider:SetPoint("TOPLEFT", cb4, "BOTTOMLEFT", 4, -28)
    slider:SetMinMaxValues(0.05, 1.0)
    slider:SetValueStep(0.05)
    slider:SetValue(settings().throttleSeconds or 0.3)

    local lowText = _G[slider:GetName() .. "Low"]
    local highText = _G[slider:GetName() .. "High"]
    local labelText = _G[slider:GetName() .. "Text"]
    if lowText then lowText:SetText("0.05s") end
    if highText then highText:SetText("1.0s") end
    if labelText then labelText:SetText(string.format(IR.L["Throttle: %.2fs"], settings().throttleSeconds or 0.3)) end

    local function refreshSlider()
        local v = (settings().throttleSeconds or 0.3)
        slider:SetValue(v)
        if labelText then labelText:SetText(string.format(IR.L["Throttle: %.2fs"], v)) end
    end
    slider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor(value / 0.05 + 0.5) * 0.05
        if Iron_DB and Iron_DB.settings and Iron_DB.settings.ironMail then
            Iron_DB.settings.ironMail.throttleSeconds = rounded
        end
        if labelText then labelText:SetText(string.format(IR.L["Throttle: %.2fs"], rounded)) end
    end)
    table.insert(IR.Settings.refreshHandlers, refreshSlider)
end

IR:RegisterSettingsTab({
    name = "ironmail",
    title = "IronMail",
    build = buildPostAITab,
})
