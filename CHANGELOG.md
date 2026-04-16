# Changelog

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
