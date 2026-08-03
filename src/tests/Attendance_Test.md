# Attendance_Test — Dokumentation

Unit-Tests für das Attendance-Aggregat in
[`src/core/Core_Attendance.lua`](../core/Core_Attendance.lua). Suite-Name: `ReqRT.Attendance`.
Läuft in-game via WoWUnit (devMode) und standalone über busted
([`spec/reqrt_spec.lua`](../../spec/reqrt_spec.lua)).

`GL.ComputeAttendance(seasonId)` ist die **einzige Datenquelle des Attendance-Tabs** — die UI
rechnet nichts selbst. Rückgabe:

```
{ season, nights = { { id, label, startedAt, kills = { { id, name, ts } } } },
          rows   = { { name, class, group, present, attended, total, pct, trial } } }
```

## Setup

- `Mock(tbl, key, fn)` / `MockRestore()` — ersetzt Funktionen und stellt sie wieder her.
- `WithDB(db, fn)` — swappt `GuildLootDB`, ruft `fn`, restauriert DB + Mocks.
- `AttendanceDB(seasonFields, sessions, players)` — DB mit Season `s1` und Raid-Sessions
  (`{ startedAt, label, raids = { { id, participants } } }`); `raids` landet als `raidMeta`.
  Ein Raid darf zusätzlich `kills = { { boss, ts, participants } }` tragen — die Boss-Ebene aus
  `GL.RecordKillAttendance`. Ohne `kills` greift der Fallback für Altdaten.
- `MockRoster(rows)` — mockt `GL.GetSeasonRoster`, damit das Aggregat ohne Gilden-API testbar ist.
- `RowByName(result, name)` — sucht eine Zeile im Ergebnis.

## Testfälle

### Leer- und Fehlerfälle

| Test | Prüft |
|------|-------|
| `testComputeAttendance_UnknownSeason_EmptyResult` | Unbekannte Season-ID → `season = nil`, leere `nights`/`rows` statt Fehler. |
| `testComputeAttendance_NoDB_EmptyResult` | Ganz ohne `GuildLootDB` → leeres Ergebnis, kein Fehler. |
| `testComputeAttendance_SeasonWithoutRaids_RowsButNoNights` | Season ohne Raid-Abende: Zeilen erscheinen trotzdem, `total = 0` und `pct = 0` (keine Division durch null). |

### Spalten (`nights`) und Season-Fenster

| Test | Prüft |
|------|-------|
| `testComputeAttendance_NightsNewestFirst` | Raid-Abende sind absteigend nach `startedAt` sortiert. |
| `testComputeAttendance_SeasonWindowFiltersNights` | Sessions vor `startedAt` und nach `endedAt` fallen raus — gleiche Fensterlogik wie `GL.GetSeasonAttendees`. |
| `testComputeAttendance_NightCarriesKills` | Jeder Abend trägt seine Bosskills aus `raidMeta` als `kills`. |

### Boss-Ebene (`raidMeta[*].kills`)

| Test | Prüft |
|------|-------|
| `testComputeAttendance_KillsPerBossWhenRecorded` | Mit aufgezeichneten `kills` gibt es eine Spalte je Bosskill, ID stabil als `raidID#index`, `name` ist der Bossname. |
| `testComputeAttendance_LateJoinerPresentOnlyFromHisKill` | Nachrücker ist beim ersten Boss abwesend, ab seinem Kill anwesend — der Abend zählt genau einmal. |
| `testComputeAttendance_KillsSortedByTimestamp` | Kills eines Abends sind über `raidMeta`-Einträge hinweg nach `ts` sortiert. |
| `testComputeAttendance_FallsBackToNightLevelWithoutKills` | Ohne `kills` (Altdaten, Observer-Sessions) bleibt es bei einem Eintrag je `raidMeta` — die Abend-Ebene stimmt unverändert. |
| `testComputeAttendance_EmptyKillsListUsesFallback` | Leere `kills`-Liste verhält sich wie gar keine. |

### Präsenz und Att.%

| Test | Prüft |
|------|-------|
| `testComputeAttendance_PctFromAttendedNights` | 2 von 4 Abenden → `attended = 2`, `total = 4`, `pct = 50`. |
| `testComputeAttendance_PresentPerNightAndKill` | `present` ist sowohl auf Session- als auch auf Kill-Ebene gesetzt. |
| `testComputeAttendance_SessionPresenceIsUnionOfKills` | Nur beim zweiten Kill dabei → der Abend zählt trotzdem als besucht, der erste Kill aber nicht. |
| `testComputeAttendance_RosterMemberWithoutAttendanceIsZero` | Kader-Mitglied ohne Attendance bleibt sichtbar mit 0 % — genau diese Zeile ist die Information. |

### Gruppen und Trial

| Test | Prüft |
|------|-------|
| `testComputeAttendance_KeepsRosterOrderAndGroups` | Reihenfolge und `group` aus `GetSeasonRoster` bleiben erhalten (Kader vor Gästen), `class` wird durchgereicht. |
| `testComputeAttendance_TrialFlagFromPlayersDB` | `trial` kommt aus `db.players[name].trial`. |
| `testComputeAttendance_UnknownPlayerHasNoTrial` | Spieler ohne `db.players`-Eintrag → `trial = false` statt `nil`. |

## Hinweis

Die `kills`-Ebene kommt aus `raidMeta[*].kills`, geschrieben von `GL.RecordKillAttendance`
(ein Eintrag je Bosskill). `GL.EnsureRaidMeta` legt den `raidMeta`-Eintrag weiterhin nur
**einmal** pro Raid-ID an — eine Raid-ID ist eine Tier+Difficulty-Kombination, kein Boss.

Zwei Datenstände existieren deshalb nebeneinander und werden beide getestet:

| Fall | `kills` | Auflösung |
|------|---------|-----------|
| Ab Phase 1b aufgezeichnet | gefüllt | je Bosskill |
| Altdaten, Observer-Sessions (`RAID_META` überträgt `kills` nicht) | fehlt | je Raid-Abend |

Die Abend-Ebene (`present[nightId]`, `attended`, `pct`) stimmt in beiden Fällen. Der
Attendance-Tab rendert vorerst nur Abend-Spalten; die Boss-Spalten sind eine reine
UI-Erweiterung, die Daten liegen bereit.
