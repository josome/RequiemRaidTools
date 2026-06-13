# Changelog

## v1.0.2.0-beta

**New Features**
- Winner loot popup now flashes gold and plays a sound when you win an item (glow extended to ~1s). Preview it with `/reqrt testwin`.
- The loot popup restores the current item when reopened and auto-reopens when a roll starts — you no longer miss a roll if you closed the popup.

**Bug Fixes**
- Auto-trade now picks a tradeable copy from your bags when you hold several of the same item.
- Observers that missed the raid metadata (e.g. after a /reload) self-heal: the raid appears immediately and the master looter resends the data.
- No more duplicate loot rows on observers: the loot history is no longer re-synced on every reconnect (slim observer sync), which also reduces addon traffic.
- Session labels can no longer be duplicated when creating or renaming a session.

**Internal**
- Large refactor: Core.lua split into focused modules (DB / session / events / slash), several UI panels extracted, numbered tabs replaced by a tab registry. No functional change intended.
- Expanded automated test coverage (Roll, Migration, Loot, Export, Util suites) on busted + CI; 213 tests green.

## v1.0.0.0

**New Features**
- **Dancing character** — When the pending loot list is empty, your character dances in the sidebar as a fun visual. Can be disabled in the Settings panel ("Tanzende Figur bei leerem Loot").
- **Loot sound** — A sound plays when a new item is added to the pending loot list. Can be toggled in the Loot Popup.
- **Priority 4 (Transmog)** — The fourth priority slot is now enabled by default with the label "Transmog".

**Internal**
- Standalone unit test runner via busted + GitHub Actions CI (all 66 tests run on every push).

## v0.5.9.5

**Bug Fixes**
- Fixed auto-trade not working after a WoW patch changed the trade frame internals. The trade partner's name is now resolved via `UnitName("NPC")` as a fallback when `TradeFrameRecipientNameText` is unavailable or empty.

## v0.5.8.0

**Improvements**
- The Observer Roll Tab has been redesigned to match the Raider popup: item icon, priority buttons, roll button, and announce filter now appear in the same layout in both places.
- The Announce Filter has been moved from the Settings panel to the Roll Tab and the Raider popup, where it is easier to adjust on the fly during a raid (e.g. filter out rings after you receive your BIS ring).

**Bug Fixes**
- Fixed the ML checkbox and the dock/minimize button in the main window title bar not responding to clicks.
- Fixed right-click on the minimap button in Raider Mode opening the filter popup instead of the main window.

## v0.5.7.0

**Bug Fixes**
- Fixed priority configuration not being transferred to Observers when a session was resumed or when a new group member joined mid-session. Observers would fall back to their own local priority settings instead of using the Master Looter's configuration.
- Fixed a session showing loot entries but no Raid entry when the Master Looter started the session after boss kills had already occurred. The session now retroactively creates the raid context entry and broadcasts it to all Observers.

**Improvements**
- Minimap button click behaviour is now role-dependent: in Player Mode, left-click opens the Loot Popup and right-click opens the main window; for Master Looter and Observers the assignments are reversed.
- The Loot Popup title bar now shows the current addon version.
- The Help panel in the Loot Popup now has a scrollbar for longer content.

## v0.5.5.0-beta

**New Features**
- **Player Mode** — Raiders without Raid Assist or Raid Lead now get a dedicated Loot Popup instead of the full addon window. The popup appears automatically when the Master Looter announces an item.
- **Loot Popup** — Shows the announced item with icon and colored link, five priority buttons (matching the current session config), and a Roll button that activates when the ML starts a roll phase. Clicking a priority button posts your priority to raid chat automatically.
- **Announce Filter** — Each player can configure which item types trigger the popup: armor types (Cloth / Leather / Mail / Plate), non-equippable weapons, Trinkets, Rings, Necks, and Other. Usable weapons always appear regardless of the filter.
- **Winner notification** — When the Master Looter assigns an item to you, the popup briefly shows "You receive: [Item]" before closing automatically after 6 seconds.
- **Minimap button for Players** — In Player Mode the minimap button toggles the popup exclusively; the main window is never opened. A first click opens the popup in filter-only view for pre-configuration, a second click closes it.
- **Priority name sync** — When the ML changes priority names and clicks Apply, the new names are broadcast to all raid members and update their popup buttons immediately.
- **Enable checkbox** — A checkbox in the top-right corner of the popup controls whether it appears automatically on item announcements. Leaving it unset uses auto mode (on during a raid, off outside).
- **Help panel** — The "i" button next to the enable checkbox opens a side panel describing what each announce filter does.

**Bug Fixes**
- Fixed an issue where the popup would not appear for non-ML players if an old `isMasterLooter = true` value was stuck in SavedVariables from a previous test session.
- Fixed announce filter not working for legacy items (e.g. Shadowlands content on Midnight clients) whose item data had not yet been cached. The popup is now briefly deferred until the data arrives, then the filter is applied correctly.
- Fixed priority buttons showing generic numbers instead of the session's configured names on clients that joined after the session started.
- Fixed the minimap button sometimes opening the main window instead of the popup when in Player Mode.
- Fixed the winner popup being immediately hidden because the item-clear event fired on the same frame as the win notification.

## v0.5.0.0-beta

**New Features**
- Introduced the Session system: group multiple raids into a named Session (typically one per week). Start a new Session with an auto-generated or custom label, close it to archive, and resume it later without losing any data.
- The Raid tab now shows all Sessions with their raids and loot counts. The active Session is highlighted in green.
- Sessions sync automatically to all Observers when they join mid-raid.
- Loot reassignment: in the Log tab, the Master Looter can click the `<<` button next to any loot entry to reassign it to a different raid member via a player picker panel.
- Difficulty correction: clicking the difficulty badge (N/H/M) on a log entry cycles through Normal → Heroic → Mythic, allowing post-hoc corrections.

## v0.4.5.0-beta

**New Features**
- The session log now shows which boss dropped each item
- The docked sidebar now displays your ML status and whether a raid is active (☑/☐)
- Unchecking the ML checkbox now notifies all Observers that no Master Looter is active

**Bug Fixes**
- Warbound items are no longer added to the pending loot list (they cannot be traded)
- Winner priority is now correctly shown in the Observer's session log
- Fixed a rare crash when cross-realm players submitted a priority during the prio phase

## v0.4.4.1-beta

**Bug Fixes**
- Fixed items not appearing in Pending Loot when the ML could not loot the boss directly (already-rolled items)
- Omni-tokens with special names (e.g. "Chiming Void Curio") are now correctly recognized
- Fixed auto-trade not resuming correctly after a cancelled trade
- Fixed remaining items not appearing after re-trading when more than 6 items were assigned
