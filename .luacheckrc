-- .luacheckrc
-- Luacheck configuration for the Iron addon (WoW 3.3.5a / Project Ascension).
--
-- Tuned to silence noise from the WoW global namespace while still catching
-- real issues (unused vars, unused args, redefined locals, undefined locals).

std = "lua51"

-- Allow long lines: WoW localization tables and tooltip strings can be wide.
max_line_length = false

-- Cap function complexity. Tune up if needed.
max_cyclomatic_complexity = 30

-- Globals defined by Iron itself. Anything in the addon that lives at the
-- global scope or in the addon namespace gets listed here.
globals = {
    "Iron",
    "IronDB",
    "IronDB_Char",
    "SLASH_IRON1",
    "SLASH_IRON2",
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
    "ChatFrame1", "StaticPopupDialogs", "StaticPopup_Show", "StaticPopup_Hide",
    "PlaySound", "PlaySoundFile", "GetCursorPosition", "GetScreenWidth",
    "GetScreenHeight", "InCombatLockdown", "IsAddOnLoaded", "LoadAddOn",
    "GetAddOnMetadata", "EnableAddOn", "DisableAddOn",

    -- Slash commands
    "SlashCmdList", "ChatEdit_FocusActiveWindow", "ChatFrame_OpenChat",

    -- Items, bags, links
    "GetItemInfo", "GetItemQualityColor", "GetItemIcon", "GetContainerItemInfo",
    "GetContainerItemLink", "GetContainerNumSlots", "GetContainerNumFreeSlots",
    "PickupContainerItem", "UseContainerItem", "SplitContainerItem",
    "GetItemCount", "GetItemFamily", "ContainerIDToInventoryID",
    "GetInventoryItemLink", "GetInventoryItemID", "GetInventoryItemCount",

    -- Mail
    "CheckInbox", "GetInboxNumItems", "GetInboxText", "GetInboxItem",
    "GetInboxItemLink", "GetInboxHeaderInfo", "GetInboxInvoiceInfo",
    "TakeInboxMoney", "TakeInboxItem", "TakeInboxTextItem", "DeleteInboxItem",
    "InboxItemCanDelete", "ReturnInboxItem", "GetInboxNumItems",
    "GetSendMailItem", "GetSendMailItemLink", "AddSendMailCOD", "GetSendMailMoney",
    "ClearSendMail", "SendMail", "ClickSendMailItemButton",

    -- Auction House
    "QueryAuctionItems", "GetAuctionItemInfo", "GetAuctionItemLink",
    "GetNumAuctionItems", "GetSelectedAuctionItem", "SetSelectedAuctionItem",
    "PlaceAuctionBid", "CancelAuction", "ClickAuctionSellItemButton",
    "PostAuction", "StartAuction", "GetAuctionSellItemInfo",
    "GetAuctionItemSubClasses", "GetAuctionItemClasses", "CalculateAuctionDeposit",
    "CanSendAuctionQuery", "AuctionFrame", "BrowseScrollFrame", "BidScrollFrame",
    "AuctionsScrollFrame", "GetCVarBool",

    -- Bank
    "BankFrame", "GetNumBankSlots", "PurchaseSlot", "BankButtonIDToInvSlotID",

    -- Trade skills and professions
    "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillItemLink",
    "GetTradeSkillReagentInfo", "GetTradeSkillNumReagents",
    "ExpandTradeSkillSubClass", "CollapseTradeSkillSubClass",
    "GetSpellInfo", "GetSpellLink", "GetSpellBookItemInfo",

    -- Money
    "GetMoney", "GetCoinTextureString", "MoneyFrame_Update",

    -- Localization
    "GetLocale",

    -- Events / scripts
    "geterrorhandler", "seterrorhandler",

    -- C constants
    "BOOKTYPE_SPELL", "NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS", "BACKPACK_CONTAINER",
    "BANK_CONTAINER", "KEYRING_CONTAINER",

    -- Ace3 (loaded as an embedded lib if used)
    "LibStub",
}

-- Per-file overrides if needed later.
files = {
    ["Iron/Locale/"] = {
        -- Locale tables can have unused keys (placeholder strings).
        ignore = { "211", "212", "213" },
    },
}

-- Globally ignored warnings.
-- 631: line too long (already disabled via max_line_length)
-- 212: unused argument (event handlers often take args they ignore)
-- 213: unused loop variable
ignore = {
    "212",
    "213",
    "631",
}
