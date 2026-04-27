# Iron

A plug and play addon suite for WoW WotLK 3.3.5a covering mail, bank, and Auction House workflows. Built and tested on Project Ascension.

Iron is not trying to replace TSM or compete with it. TSM is more powerful and will stay that way. Iron is for players who want most of the day-to-day value (bulk mail, bank restocking, AH selling, mat buying) without spending an evening configuring groups, operations, and custom price strings before anything works.

Open the addon, click a button, it works. That is the whole pitch.

## What it does

Four independent modules sharing a single addon. None require setup before first use.

**IronSell** lists everything in your bags that isn't blacklisted, computes a sale price from recent AH scans (5% undercut by default), and posts in one click per item. The blacklist approach means it works on day one with zero configuration. Items you don't want sold get added to the blacklist as you go.

**IronBuy** shows your known recipes by profession, displays each reagent's market price and the total reagent cost for the chosen quantity, and lets you click a reagent to see live AH listings sorted cheapest first. Pick a quantity, the addon auto-selects the cheapest auctions to match it, and buys them in batch.

**IronVault** moves items between your bags and bank based on targets you define once. Open a group, drop items into it with target counts ("I want 40 flasks in the bank", or "I want 200 mana potions in my bags"), and from then on a single click at the bank moves what's missing. Each group runs in one direction, deposit (bag to bank) or withdraw (bank to bag), with auto-sync on bank open if you want it.

**IronMail** adds an "Open all" button to your mailbox. One click drains gold and items from your inbox, with throttling so the server doesn't drop attachments. COD mails are skipped by default (a confirmation popup protects you if you ever disable that safety).

## Highlights

Auction House workflows (IronSell + IronBuy) and bank management (IronVault) are the three pillars. If you live at the auction house posting items, sniping mats for crafts, and shuffling stock between bags and bank, those modules will save you the most time. IronMail is the convenience layer that closes the loop after every AH cycle.

No premium tier, no cloud sync, no telemetry. Everything runs locally with your saved variables.

Multilingual: English, French, German, Spanish, Simplified Chinese. Falls back to English on unsupported locales.

## Installation

Download the latest release zip from the Releases page. Extract it into your `World of Warcraft/Interface/AddOns/` folder so the path looks like `Interface/AddOns/Iron/Iron.toc`. Launch the client.

At login, type `/ir about` in chat to confirm the addon is loaded and see the locale status.

## Commands

`/ir help` lists all available commands.
`/ir config` opens the settings panel.
`/ir about` shows version, locale, and a quick command summary.
`/ir logs` opens a copyable debug log window (useful for bug reports).
`/ir debug on|off` toggles verbose chat output.
`/ir stats` shows load count and first install date.

## Compatibility

Tested on Project Ascension (3.3.5a). Should work on other WotLK 3.3.5a private servers since the addon uses standard Blizzard API only, but Ascension is the only confirmed environment.

Plays nicely with Bagnon.

## Bug reports

Open an issue on GitHub with the following:

The addon version (visible via `/ir about`).
The realm and client build you're on.
Steps to reproduce (what you did, what you expected, what happened).
The output of `/ir logs` covering the time the bug occurred (copy from the log window with Ctrl+A then Ctrl+C).

Without the logs, most issues are guesswork.

## License

MIT. Do whatever you want with the code, just keep the copyright notice. See LICENSE for the full text.

Copyright (c) 2026 SpySpoTt3d
