# Season_Test — Dokumentation

Unit-Tests für die Season-Verwaltung in [`src/core/Core_Season.lua`](../core/Core_Season.lua).
Suite-Name: `ReqRT.Season`. Läuft über busted
([`spec/reqrt_spec.lua`](../../spec/reqrt_spec.lua)).

## Setup

- `WithTestDB(initialDB, fn)` — swappt `GuildLootDB` auf `initialDB`, ruft `fn` in `pcall` und
  stellt das Original immer wieder her.
- `FreshDB()` — minimaler DB-Stand `{ seasons = {}, activeSeasonId = nil }`.

## Invariante

Es ist immer **höchstens eine Season offen** (`endedAt = nil`). `CreateSeason` und `ReopenSeason`
beenden dafür die bisher aktive. `activeSeasonId` bedeutet eindeutig „wohin wird aufgezeichnet" —
deshalb weist `SetActiveSeason` beendete Seasons ab. Das Betrachten vergangener Seasons bekommt
in Phase 1c einen eigenen Selektor.

## Testfälle

| Test | Prüft |
|------|-------|
| `testCreateSeason_SetsActiveAndStoresFields` | `CreateSeason` legt Season an, setzt sie aktiv, füllt `name`/`startedAt`/`endedAt=nil` und übernimmt den Rang-Filter. |
| `testCreateSeason_OnlyEnabledRanksKept` | Nur mit `true` markierte Ränge landen im `rankFilter`; `false`-Einträge werden verworfen. |
| `testCreateSeason_EndsPreviousActive` | Eine neue Season stempelt `endedAt` der bisher aktiven Season und wird selbst aktiv (offen: `endedAt=nil`). |
| `testCreateSeason_NoDB_ReturnsNil` | Ohne `GuildLootDB` liefert `CreateSeason` `nil` (kein Fehler). |
| `testCreateSeason_IdCollisionResolvesToUniqueId` | Kollidierende Hashes (gleicher Name in derselben Sekunde) führen zu zwei unterschiedlichen, real angelegten Seasons. |
| `testCreateSeason_StringRankKeysNormalized` | String-Schlüssel im übergebenen Rang-Filter (wie nach einem JSON-Roundtrip) werden zu Zahlen normalisiert. |
| `testSetActiveSeason_UnknownIdRejected` | Unbekannte ID → `false`, aktive Season unverändert. |
| `testSetActiveSeason_EndedSeasonRejected` | Beendete Season kann nicht aktiv gesetzt werden — sie ist kein Aufzeichnungsziel. |
| `testSetActiveSeason_OpenSeasonAccepted` | Offene Season lässt sich (wieder) aktiv setzen, z.B. nach verlorenem Zeiger. |
| `testReopenSeason_ClearsEndedAtAndActivates` | `ReopenSeason` nimmt eine beendete Season wieder auf und beendet dafür die bisher aktive — höchstens eine offene Season. |
| `testReopenSeason_UnknownReturnsFalse` | Unbekannte ID → `false`. |
| `testGetActiveSeason_ReturnsActiveOrNil` | Ohne aktive Season `nil`; sonst die aktive Season-Tabelle mit passender `id`. |
| `testEndSeason_StampsEndedAtAndClearsActive` | `EndSeason` setzt `endedAt` und leert `activeSeasonId`, wenn es die aktive Season war. |
| `testEndSeason_UnknownReturnsFalse` | Unbekannte ID → `false`. |
| `testEndSeason_IsIdempotent` | Ein zweiter Aufruf lässt ein bestehendes `endedAt` stehen und verschiebt den Season-Zeitraum nicht. |
| `testSetSeasonRankFilter_NilIndexReturnsFalse` | `rankIndex = nil` → `false` statt hartem `table index is nil`. |
| `testSetSeasonRankFilter_StringIndexNormalized` | `"3"` landet als Zahl `3` im Filter. |
| `testSetSeasonRankFilter_Toggle` | Rang an/aus: `true` setzt den Eintrag, `false` entfernt ihn (`nil`). |
| `testSetSeasonRankFilter_UnknownReturnsFalse` | Unbekannte Season-ID → `false`. |
| `testDeleteSeason_RemovesEntryAndClearsActive` | `DeleteSeason` entfernt den Eintrag; war es die aktive Season, ist danach keine aktiv. |
| `testDeleteSeason_KeepsOtherSeasonsAndRaidData` | Andere Seasons, die aktive Season und `raidContainers` bleiben unberührt. |
| `testDeleteSeason_UnknownReturnsFalse` | Unbekannte ID → `false`. |
| `testRenameSeason_ChangesNameButNotId` | Umbenennen ändert nur `name`; `id` und `activeSeasonId` bleiben — die ID wird zwar aus dem Namen erzeugt, ist danach aber Schlüssel und Referenz. |
| `testRenameSeason_TrimsWhitespace` | Führende/abschließende Leerzeichen werden entfernt. |
| `testRenameSeason_RejectsEmptyName` | Leer, nur Leerzeichen oder `nil` → `false`, Name bleibt unverändert. |
| `testRenameSeason_UnknownIdIsNoOp` | Unbekannte Season-ID → `false`. |
| `testSetSeasonEnd_SetsEndAndClosesSeason` | `SetSeasonEnd` setzt `endedAt` auf einen gewählten Zeitpunkt und schließt die Season (wie `EndSeason`). |
| `testSetSeasonEnd_RejectsEndBeforeStart` | Ende vor Start → `false`; das Fenster bliebe sonst leer. |
| `testSetSeasonEnd_RejectsUnknownOrInvalid` | Unbekannte ID, `nil`, `0`, Nicht-Zahlen → `false`. |
| `testSetSeasonEnd_CanCorrectAnExistingEnd` | Ein von `EndSeason` gestempeltes Ende lässt sich nachträglich korrigieren. |
| `testSetSeasonStart_MovesWindowBack` | `SetSeasonStart` verschiebt `startedAt`; `endedAt` bleibt unangetastet. |
| `testSetSeasonStart_RejectsUnknownOrInvalid` | Unbekannte ID, `nil`, `0` und Nicht-Zahlen → `false`. |
| `testSetSeasonStart_RejectsStartAfterEnd` | Ein Start nach dem Season-Ende wird abgewiesen. |
| `testSetSeasonRankThreshold_EnablesRankAndAllAbove` | Schwelle „Raider" (Index 2) hakt 0 (GM), 1 (Offizier) und 2 an; niedrigere Ränge bleiben aus. |
| `testSetSeasonRankThreshold_ReplacesPreviousSelection` | Die Schwelle **ersetzt** den bisherigen Filter, statt sich dazuzumischen. |
| `testSetSeasonRankThreshold_UnknownSeasonOrBadIndex` | Unbekannte Season-ID oder `nil` als rankIndex → `false` (kein Lua-Fehler). |
| `testCreateSeason_HasMaxOfflineDaysDefault` | Neue Seasons starten mit `maxOfflineDays = 60`. |
| `testInitDB_HasSeasonDefaults` | Nach `InitDB` existiert `seasons` als Tabelle; `activeSeasonId` ist `nil` (via `DeepMergeDefaults`, keine Migration). |

## Hinweise

`GL.DeleteSeason` betrifft **nur** den Season-Eintrag (Name, Zeitfenster, Rang-Filter).
Raid-Sessions und Loot bleiben erhalten — Attendance wird ohnehin aus `raidContainers`
abgeleitet, nicht in der Season gespeichert.

`GL.SetSeasonStart` existiert, weil eine heute angelegte Season `startedAt = jetzt` hat und damit
alle bereits gelaufenen Raid-Sessions aus ihrem Zeitfenster fallen — die Attendance-Matrix bliebe
leer, obwohl Daten vorhanden sind. Zugleich Grundlage fürs Nachtragen alter Raids (Phase 1e).

`GL.SetSeasonRankThreshold` ist eine Bedienhilfe über `GL.SetSeasonRankFilter` — das Datenmodell
bleibt der `rankFilter` als Menge. Grund: Der Kader ist in der Praxis „Raider und alles darüber",
das soll ein Klick sein; Gilden mit einem Nicht-Raider-Rang *oberhalb* von Raider können einzelne
Ränge danach trotzdem wieder abwählen.
