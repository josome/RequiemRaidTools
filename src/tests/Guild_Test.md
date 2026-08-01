# Guild_Test — Dokumentation

Unit-Tests für die Gildenroster-Anbindung in [`src/core/Core_Guild.lua`](../core/Core_Guild.lua).
Suite-Name: `ReqRT.Guild`. Läuft in-game via WoWUnit (devMode) und standalone über busted
([`spec/reqrt_spec.lua`](../../spec/reqrt_spec.lua)).

## Setup

- `Mock(tbl, key, fn)` / `MockRestore()` — ersetzt Globals/Funktionen und stellt sie (auch
  `nil`-Originale) wieder her.
- `MockGuild(roster)` — stubt die WoW-Gilden-API (`IsInGuild`, `GetNumGuildMembers`,
  `GetGuildRosterInfo`) aus einem Roster-Array `{ name, rankIndex, class, rankName? }`.
- `WithDB(db, fn)` — swappt `GuildLootDB`, ruft `fn`, restauriert DB + Mocks.
- `WithTestDBNil(fn)` — wie `WithDB`, aber ganz ohne `GuildLootDB`.
- `SeasonDB(rankFilter, seasonFields)` — DB mit einer Season `s1`; `seasonFields` ergänzt Felder
  wie `startedAt`, `endedAt`.
- `SeasonDBWithRaids(rankFilter, seasonFields, sessions)` — zusätzlich Raid-Sessions
  (`{ startedAt, participants }`), aus denen `GetSeasonAttendees` liest.

## Testfälle

### GetGuildMembers / CollectGuildMembers

| Test | Prüft |
|------|-------|
| `testGetGuildMembers_NotInGuild_Empty` | Ohne Gilde (`IsInGuild=false`) → leere Mitgliederliste. |
| `testGetGuildMembers_ReadsFieldsAndNormalizes` | Liest `name`/`rankIndex`/`class`; realm-loser Name wird via `NormalizeName` realm-qualifiziert. |
| `testCollectGuildMembers_DropsRejectedRows` | `accept` lehnt eine Zeile ab → sie landet nicht im Ergebnis (kein Zwischenarray mit allen Mitgliedern). |
| `testCollectGuildMembers_CollectsRankNamesInSamePass` | Rang-Namen werden im selben Durchlauf gesammelt, auch wenn `accept` **alle** Zeilen ablehnt. |
| `testCollectGuildMembers_NoAcceptKeepsAll` | `accept = nil` behält alle Zeilen. |
| `testCollectGuildMembers_NilRowDoesNotAbortRead` | Meldet die API mehr Zeilen als sie liefert, bricht der Read nicht ab und zählt nur echte Zeilen. |

### Rang-Namen

| Test | Prüft |
|------|-------|
| `testGetGuildRankNames_MappedByRankIndex` | Mapping auf 0-basierten rankIndex: `names[0..2]` = `GuildControlGetRankName(1..3)`. |
| `testGetGuildRankNames_FallsBackToDBWhenGuildControlEmpty` | Liefert Guild-Control 0 Ränge, greift der Fallback auf `db.guildRankNames` — sonst bliebe die Rang-Auswahl im UI leer. |
| `testGetGuildRankNames_GuildControlWinsOverDB` | Liefert Guild-Control Daten, haben sie Vorrang vor dem DB-Fallback. |
| `testUpdateGuildRankNames_WritesToDB` | `UpdateGuildRankNames` schreibt die aus dem Roster gelesenen Rang-Namen nach `db.guildRankNames`. |

### Kader-Schnappschuss (`SnapshotSeasonRoster` / `IsSeasonRosterStale`)

Der Kader wird **nur auf ausdrückliche Aktion** gebildet (Button „Roster lesen"), nicht bei
jedem Refresh. Gespeichert wird `season.roster` — das Ergebnis des Rang-Schnitts (~Kadergröße),
nicht die Gildenliste. Folge: Der Kader ändert sich nicht still, wenn mitten in der Season
jemand befördert oder degradiert wird.

| Test | Prüft |
|------|-------|
| `testSnapshotSeasonRoster_StoresFilteredKader` | Schreibt nur die Mitglieder mit aktivem Rang nach `season.roster`, inkl. Klasse und `rosterReadAt`. |
| `testSnapshotSeasonRoster_UnknownSeason_Nil` | Unbekannte Season-ID → `nil`. |
| `testGetSeasonRoster_FilterChangeHasNoEffectUntilSnapshot` | Eine Rang-Änderung wirkt **erst** nach dem nächsten Einlesen. |
| `testGetSeasonRoster_DoesNotHitGuildApi` | Auch ohne Gilde (`IsInGuild = false`) liefert das Roster den Schnappschuss. |
| `testIsSeasonRosterStale_TrueBeforeFirstRead` | Vor dem ersten Einlesen gilt der Kader als veraltet. |
| `testIsSeasonRosterStale_FalseAfterSnapshot` | Direkt nach dem Einlesen nicht veraltet. |
| `testIsSeasonRosterStale_TrueAfterFilterChange` | Nach einer Rang-Änderung wieder veraltet — die UI weist darauf hin. |
| `testIsSeasonRosterStale_UnknownSeason_False` | Unbekannte Season-ID → `false`. |

### Season-Roster — Kader („roster") und Gäste („guest")

| Test | Prüft |
|------|-------|
| `testGetSeasonRoster_UnknownSeason_Empty` | Unbekannte Season-ID → leeres Roster. |
| `testGetSeasonRoster_NoDB_Empty` | Ganz ohne `GuildLootDB` liefern `GetSeasonRoster`/`GetSeasonAttendees` `{}` statt eines Fehlers. |
| `testGetGuildRankNames_NoApiNoDB_Empty` | Weder Guild-Control noch DB → leere Rang-Tabelle, kein Fehler. |
| `testGetSeasonRoster_FiltersByRank` | Nur Mitglieder mit im `rankFilter` aktivem rankIndex; nach Name sortiert, Klasse übernommen. |
| `testGetSeasonRoster_EmptyFilter_NoGuildRows` | Leerer Rang-Filter → keine Gilden-Zeilen. |
| `testGetSeasonRoster_OfficerAndGmAreInKader` | Schwelle „Raider" (Index 2) nimmt Offizier (1) und GM (0) automatisch mit, Twink (3) bleibt draußen. |
| `testGetSeasonRoster_UnionWithAttendees` | Vereinigung mit `GetSeasonAttendees`: ausgetretener Spieler mit Attendance erscheint. |
| `testGetSeasonRoster_AttendeeAlreadyInGuild_NoDuplicate` | Attendee, der noch in der Gilde ist, erzeugt keine Dublette; Gilden-Klasse bleibt erhalten. |
| `testGetSeasonRoster_LongOfflineMemberStaysInKader` | Der Rang ist der **einzige** Schnitt: wer im Kader-Rang steht, erscheint unabhängig davon, wann er zuletzt online war. |
| `testGetSeasonRoster_LowRankParticipantBecomesGuest` | Teilnehmer mit zu niedrigem Rang landet in `group = "guest"`, nicht im Kader. |
| `testGetSeasonRoster_RosterBlockSortsBeforeGuestBlock` | Kader-Block steht vor dem Gast-Block, auch wenn der Gast alphabetisch vorne läge. |
| `testGetSeasonRoster_LeaverClassFromPlayersDB` | Klasse eines Ausgetretenen kommt aus `db.players[name].class`. |

### GetSeasonAttendees

| Test | Prüft |
|------|-------|
| `testGetSeasonAttendees_ReadsParticipantsAndDeduplicates` | Liest `raidMeta[*].participants` aller Sessions und dedupliziert über Sessions hinweg. |
| `testGetSeasonAttendees_IgnoresSessionsOutsideSeasonWindow` | Sessions vor `startedAt` und nach `endedAt` zählen nicht. |
| `testGetSeasonAttendees_NoRaidMeta_Empty` | Session ganz ohne `raidMeta` → `{}` statt Fehler. |
| `testGetSeasonAttendees_UnknownSeason_Empty` | Unbekannte Season-ID → `{}`. |

### Roster-Vollständigkeit

Online/Offline ist für den Kader vollständig irrelevant: gelesen werden **immer alle**
Mitglieder, der einzige Schnitt ist der Rang. Der Addon greift deshalb weder in die
Roster-Filter des Spielers ein noch fragt er `GetGuildRosterLastOnline` ab. Liefert die
Gilden-API trotzdem weniger Zeilen als sie Mitglieder meldet, wird das gemeldet statt
verschluckt — ein halber Kader wäre sonst ein lautloser Fehler.

| Test | Prüft |
|------|-------|
| `testRefreshGuildRoster_DoesNotTouchPlayerFilter` | `RefreshGuildRoster` ruft `SetGuildRosterShowOffline` nicht auf — die Gildenfenster-Einstellung bleibt unangetastet. |
| `testCheckGuildRosterCompleteness_ReportsTruncatedRead` | Meldet die API 40 Mitglieder, liefert aber 1 Zeile → Warnung an den Spieler. |
| `testCheckGuildRosterCompleteness_SilentWhenComplete` | Stimmen gemeldete und gelesene Zahl überein → keine Meldung. |
| `testOnGuildRosterUpdate_RefreshesRankNames` | Der Event-Handler frischt `db.guildRankNames` auf. |

## Hinweise

- **`GL.GetSeasonAttendees` ist seit B1 implementiert** (Quelle: `raidMeta[*].participants`).
  `GL.EnsureRaidMeta` legt `raidMeta[id]` allerdings nur einmal an — die Teilnehmerliste ist ein
  Schnappschuss vom ersten Bosskill, keine Vereinigung über den Abend. Für die Gruppenzuordnung
  genügt das; die Pro-Kill-Auflösung kommt mit Phase 1b. Tests, die nur die Vereinigungslogik
  prüfen, mocken den Seam weiterhin.
- **Der Throttle in `GL.OnGuildRosterUpdate` (10 s) ist nicht getestet** — er hängt an
  modul-lokalem Laufzeitzustand und `time()`; ein Test dafür wäre von der Ausführungsreihenfolge
  abhängig. `testOnGuildRosterUpdate_RefreshesRankNames` ruft den Handler genau einmal auf.
