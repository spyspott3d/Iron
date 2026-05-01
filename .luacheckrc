-- .luacheckrc
-- Luacheck configuration for the Iron addon (WoW 3.3.5a / Project Ascension).
--
-- Tuned to silence noise from the WoW global namespace while still catching
-- real issues (unused vars, unused args, redefined locals, undefined locals).

std = "lua51"

-- Allow long lines: WoW localization tables and tooltip strings can be wide.
max_line_length = false

-- Cap function complexity. Scanners and enumerators legitimately branch a lot.
max_cyclomatic_complexity = 40

-- Mutable globals: addon namespace, the SavedVariable, slash bindings, and
-- WoW tables/hooks the addon writes into.
globals = {
    "Iron",
    "Iron_DB",
    "SLASH_IRON1",
    "SLASH_IRON2",
    "SlashCmdList",
    "StaticPopupDialogs",
    "ChatEdit_InsertLink",
    "AuctionFrameAuctions",
}

-- Read-only globals from WoW client and Lua stdlib that the addon reads
-- but does not assign to. Trim or extend as needed.
read_globals = {
    -- Lua stdlib that 3.3.5a exposes
    "bit", "string", "table", "math", "type", "select", "pairs", "ipairs",
    "tostring", "tonumber", "unpack", "next", "rawget", "rawset", "setmetatable",
    "getmetatable", "pcall", "xpcall", "error", "assert", "print", "format",
    "wipe", "strsplit", "strjoin", "strtrim", "strsub", "strlen", "strlower",
    "strupper", "strfind", "strmatch", "gmatch", "gsub", "tinsert", "tremove",
    "tContains", "max", "min", "abs", "floor", "ceil", "mod", "random",
    "date", "time", "GetTime", "debugstack",

    -- Frame and UI API
    "CreateFrame", "UIParent", "WorldFrame", "GameTooltip", "DEFAULT_CHAT_FRAME",
    "ChatFrame1", "StaticPopup_Show", "StaticPopup_Hide",
    "PlaySound", "PlaySoundFile", "GetCursorPosition", "GetScreenWidth",
    "GetScreenHeight", "InCombatLockdown", "IsAddOnLoaded", "LoadAddOn",
    "GetAddOnMetadata", "EnableAddOn", "DisableAddOn",
    "UISpecialFrames",

    -- Slash commands
    "ChatEdit_FocusActiveWindow", "ChatFrame_OpenChat",

    -- Cursor and linking
    "ClearCursor", "CursorHasItem", "GetCursorInfo",

    -- Items, bags, links
    "GetItemInfo", "GetItemQualityColor", "GetItemIcon", "GetContainerItemInfo",
    "GetContainerItemLink", "GetContainerNumSlots", "GetContainerNumFreeSlots",
    "PickupContainerItem", "UseContainerItem", "SplitContainerItem",
    "GetItemCount", "GetItemFamily", "ContainerIDToInventoryID",
    "GetInventoryItemLink", "GetInventoryItemID", "GetInventoryItemCount",

    -- Mail
    "MailFrame", "MailFrameTab1", "MailFrameTab2", "MailFrameTab_OnClick",
    "MiniMapMailFrame", "HasNewMail", "CloseMail",
    "CheckInbox", "GetInboxNumItems", "GetInboxText", "GetInboxItem",
    "GetInboxItemLink", "GetInboxHeaderInfo", "GetInboxInvoiceInfo",
    "TakeInboxMoney", "TakeInboxItem", "TakeInboxTextItem", "DeleteInboxItem",
    "InboxItemCanDelete", "ReturnInboxItem",
    "GetSendMailItem", "GetSendMailItemLink",
    "AddSendMailCOD", "SetSendMailCOD", "SetSendMailMoney", "GetSendMailMoney",
    "ClearSendMail", "SendMail", "ClickSendMailItemButton",
    "MoneyInputFrame_GetCopper", "MoneyInputFrame_SetCopper",
    "MoneyInputFrame_ResetMoney",

    -- Auction House
    "QueryAuctionItems", "GetAuctionItemInfo", "GetAuctionItemLink",
    "GetNumAuctionItems", "GetSelectedAuctionItem", "SetSelectedAuctionItem",
    "PlaceAuctionBid", "CancelAuction", "ClickAuctionSellItemButton",
    "PostAuction", "StartAuction", "GetAuctionSellItemInfo",
    "GetAuctionItemSubClasses", "GetAuctionItemClasses", "CalculateAuctionDeposit",
    "CanSendAuctionQuery", "AuctionFrame", "BrowseScrollFrame", "BidScrollFrame",
    "AuctionsScrollFrame", "GetCVarBool",
    "StartPrice", "BuyoutPrice",

    -- Bank
    "BankFrame", "GetNumBankSlots", "PurchaseSlot", "BankButtonIDToInvSlotID",

    -- Trade skills and professions
    "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillItemLink",
    "GetTradeSkillReagentInfo", "GetTradeSkillNumReagents",
    "GetTradeSkillLine", "GetTradeSkillReagentItemLink", "GetTradeSkillIcon",
    "ExpandTradeSkillSubClass", "CollapseTradeSkillSubClass",
    "GetSpellInfo", "GetSpellLink", "GetSpellBookItemInfo",

    -- Player and units
    "UnitName",

    -- Money
    "GetMoney", "GetCoinTextureString", "MoneyFrame_Update",

    -- Localization
    "GetLocale",

    -- Events and scripts
    "geterrorhandler", "seterrorhandler",

    -- C constants
    "BOOKTYPE_SPELL", "NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS", "BACKPACK_CONTAINER",
    "BANK_CONTAINER", "KEYRING_CONTAINER",
    "ATTACHMENTS_MAX_RECEIVE", "ATTACHMENTS_MAX_SEND",
    "ITEM_SOULBOUND", "ITEM_BIND_ON_PICKUP", "ITEM_BIND_QUEST",
    "ACCEPT", "CANCEL",

    -- Ace3 (loaded as an embedded lib if used)
    "LibStub",
}

-- Per-file overrides.
files = {
    ["Iron/Locales.lua"] = {
        -- Locale tables can have unused keys (placeholder strings).
        ignore = { "211", "212", "213" },
    },
}

-- Globally ignored warnings.
-- 211/addonName: standard `local addonName, MAI = ...` header pattern
-- 212: unused argument (event handlers often take args they ignore)
-- 213: unused loop variable
-- 631: line too long (already disabled via max_line_length)
ignore = {
    "211/addonName",
    "212",
    "213",
    "631",
}
