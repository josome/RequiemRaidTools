# Season_Test — Dokumentation

Unit-Tests für die Season-Verwaltung in [`src/core/Core_Season.lua`](../core/Core_Season.lua).
Suite-Name: `ReqRT.Season`. Läuft in-game via WoWUnit (devMode) und standalone über busted
([`spec/reqrt_spec.lua`](../../spec/reqrt_spec.lua)).

## Setup

- `WithTestDB(initialDB, fn)` — swappt `GuildLootDB` auf `initialDB`, ruft `fn` in `pcall` und
  stellt das Original immer wieder her.
- `FreshDB()` — minimaler DB-Stand `{ seasons = {}, activeSeasonId = nil }`.

## Testfälle

| Test | Prüft |
|------|-------|
| `testCreateSeason_SetsActiveAndStoresFields` | `CreateSeason` legt Season an, setzt sie aktiv, füllt `name`/`startedAt`/`endedAt=nil` und übernimmt den Rang-Filter. |
| `testCreateSeason_OnlyEnabledRanksKept` | Nur mit `true` markierte Ränge landen im `rankFilter`; `false`-Einträge werden verworfen. |
| `testCreateSeason_EndsPreviousActive` | Eine neue Season stempelt `endedAt` der bisher aktiven Season und wird selbst aktiv (offen: `endedAt=nil`). |
| `testCreateSeason_NoDB_ReturnsNil` | Ohne `GuildLootDB` liefert `CreateSeason` `nil` (kein Fehler). |
| `testSetActiveSeason_KnownAndUnknown` | Bekannte ID → aktiv gesetzt (`true`); unbekannte ID → `false`, aktive Season unverändert. |
| `testGetActiveSeason_ReturnsActiveOrNil` | Ohne aktive Season `nil`; sonst die aktive Season-Tabelle mit passender `id`. |
| `testEndSeason_StampsEndedAtAndClearsActive` | `EndSeason` setzt `endedAt` und leert `activeSeasonId`, wenn es die aktive Season war. |
| `testEndSeason_UnknownReturnsFalse` | Unbekannte ID → `false`. |
| `testSetSeasonRankFilter_Toggle` | Rang an/aus: `true` setzt den Eintrag, `false` entfernt ihn (`nil`). |
| `testSetSeasonRankFilter_UnknownReturnsFalse` | Unbekannte Season-ID → `false`. |
| `testInitDB_HasSeasonDefaults` | Nach `InitDB` existiert `seasons` als Tabelle; `activeSeasonId` ist `nil` (via `DeepMergeDefaults`, keine Migration). |
