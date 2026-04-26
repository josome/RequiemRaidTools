# Changelog

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
