# Guild_Test — Dokumentation

Unit-Tests für die Gildenroster-Anbindung in [`src/core/Core_Guild.lua`](../core/Core_Guild.lua).
Suite-Name: `ReqRT.Guild`. Läuft in-game via WoWUnit (devMode) und standalone über busted
([`spec/reqrt_spec.lua`](../../spec/reqrt_spec.lua)).

## Setup

- `Mock(tbl, key, fn)` / `MockRestore()` — ersetzt Globals/Funktionen und stellt sie (auch
  `nil`-Originale) wieder her.
- `MockGuild(roster)` — stubt die WoW-Gilden-API (`IsInGuild`, `GetNumGuildMembers`,
  `GetGuildRosterInfo`) aus einem Roster-Array `{ name, rankIndex, class }`.
- `WithDB(db, fn)` — swappt `GuildLootDB`, ruft `fn`, restauriert DB + Mocks.
- `SeasonDB(rankFilter)` — DB mit einer Season `s1` und dem gegebenen Rang-Filter.

## Testfälle

| Test | Prüft |
|------|-------|
| `testGetGuildMembers_NotInGuild_Empty` | Ohne Gilde (`IsInGuild=false`) → leere Mitgliederliste. |
| `testGetGuildMembers_ReadsFieldsAndNormalizes` | Liest `name`/`rankIndex`/`class` aus `GetGuildRosterInfo`; realm-loser Name wird via `NormalizeName` realm-qualifiziert. |
| `testGetGuildRankNames_MappedByRankIndex` | `GetGuildRankNames` mappt auf 0-basierten rankIndex: `names[0..2]` = `GuildControlGetRankName(1..3)`. |
| `testGetSeasonRoster_UnknownSeason_Empty` | Unbekannte Season-ID → leeres Roster. |
| `testGetSeasonRoster_FiltersByRank` | Nur Mitglieder mit im `rankFilter` aktivem rankIndex; Ausgabe nach Name sortiert, Klasse übernommen. |
| `testGetSeasonRoster_EmptyFilter_NoGuildRows` | Leerer Rang-Filter → keine Gilden-Zeilen (Ränge müssen explizit gewählt werden). |
| `testGetSeasonRoster_UnionWithAttendees` | Vereinigung mit `GetSeasonAttendees`: ausgetretener Spieler mit Attendance erscheint (Klasse `nil`). |
| `testGetSeasonRoster_AttendeeAlreadyInGuild_NoDuplicate` | Attendee, der noch in der Gilde ist, erzeugt keine Dublette; Gilden-Klasse bleibt erhalten. |

## Hinweis

`GL.GetSeasonAttendees` ist in Phase 1a ein **Platzhalter** (liefert `{}`); die Ableitung aus der
Kill-/Session-Historie folgt in Phase 1b/1c. Die Tests mocken den Seam, um die Vereinigungslogik
schon jetzt abzusichern.
