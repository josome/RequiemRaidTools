# Attendance_Test — Dokumentation

Unit-Tests für das Attendance-Aggregat in
[`src/core/Core_Attendance.lua`](../core/Core_Attendance.lua). Suite-Name: `ReqRT.Attendance`.
Läuft in-game via WoWUnit (devMode) und standalone über busted
([`spec/reqrt_spec.lua`](../../spec/reqrt_spec.lua)).

`GL.ComputeAttendance(seasonId)` ist die **einzige Datenquelle des Attendance-Tabs** — die UI
rechnet nichts selbst. Rückgabe:

```
{ season, nights = { { id, label, startedAt, kills = { { id, name, ts, difficulty } } } },
          rows   = { { name, class, group, present, trialAt, attended, total, pct, trial } } }
```

## Setup

- `Mock(tbl, key, fn)` / `MockRestore()` — ersetzt Funktionen und stellt sie wieder her.
- `WithDB(db, fn)` — swappt `GuildLootDB`, ruft `fn`, restauriert DB + Mocks.
- `TS(day, hour, min)` — Zeitstempel im August 2026, für Fixtures mit echten Tagesabständen.
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

### Gruppierung nach Raid-Tag

Ein Attendance-Abend ist ein **Raid-Tag**, nicht eine Session. Eine über zwei Tage fortgesetzte
Session ergibt zwei Spalten, zwei Raids an einem Tag nur eine — damit hängt die Zählung nicht
daran, ob zwischendurch eine neue Session angelegt wurde. Tagesgrenze ist der Raid-Reset um
7 Uhr, ein Kill um 01:30 zählt also noch zum Vorabend.

Welche Sessions überhaupt betrachtet werden, entscheidet weiterhin `session.startedAt` im
Season-Fenster; erst die Kills darin werden nach ihrem eigenen Zeitstempel auf Tage verteilt.

| Test | Prüft |
|------|-------|
| `testCollectNights_SessionAcrossTwoDaysSplitsIntoTwoNights` | Am Folgetag fortgesetzte Session → zwei Abende, `attended = 2`. |
| `testCollectNights_TwoSessionsSameDayMergeIntoOneNight` | Zwei Sessions an einem Tag → ein Abend mit den Bossen beider; Label nennt beide Sessions. |
| `testCollectNights_AfterMidnightBelongsToPreviousRaidDay` | Kill um 01:30 bleibt beim Vorabend. |
| `testCollectNights_MorningAfterResetIsANewDay` | Gegenprobe: 9 Uhr liegt hinter dem Reset → neuer Abend. |
| `testCollectNights_SessionWithoutKillsStillCounts` | Abgebrochener Abend ohne Bosskill bleibt als Spalte und im Nenner von `Att.%`. |

> Fixtures brauchen seitdem echte Tagesabstände — Helper `TS(day, hour, min)` baut Zeitstempel
> im August 2026. Werte wie `100`/`200` lägen alle am selben Raid-Tag.

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

| `testComputeAttendance_PresenceMatchesDespiteRealmSpacing` | Präsenz wird über `GL.NameKey` nachgeschlagen: Kader aus dem Gildenroster (Realm mit Leerzeichen) und Kill-Teilnehmer aus der Raid-API (ohne) müssen dieselbe Zeile treffen — sonst bliebe sie trotz Teilnahme auf 0 %. |

### Trial-Stand zum Zeitpunkt des Kills (`trialAt`)

Die Trial-Rolle endet nach drei Raids. `row.trialAt[key]` hält deshalb fest, ob jemand **damals**
Trial war, statt das aktuelle Flag zu spiegeln — sonst würde eine Beförderung rückwirkend alle
Abende der Season umfärben.

`nil` (Altdaten ohne aufgezeichneten Stand) gilt in der UI als **kein** Trial. Ein Rückgriff aufs
aktuelle Flag wäre naheliegend, ist aber falsch: er färbt beim Setzen des Hakens die gesamte
Historie um — genau die rückwirkende Umdeutung, die `trialAt` verhindern soll. Der Stand von
damals ist für Altdaten schlicht nicht bekannt, und er lässt sich aus dem Heute nicht erschließen.

| Test | Prüft |
|------|-------|
| `testComputeAttendance_TrialAtFromRecordedKill` | `trialAt` je Kill aus `kill.trials`. |
| `testComputeAttendance_TrialAtIgnoresLaterPromotion` | Beförderung ändert ältere Kills nicht; `row.trial` (aktuelles Flag) bleibt davon getrennt. |
| `testComputeAttendance_TrialAtNightIsTrueIfAnyKillWasTrial` | Abend-Ebene ist Trial, wenn bei mindestens einem Kill Trial. |
| `testComputeAttendance_TrialAtEmptyForUnrecordedKills` | Altdaten ohne `trials` → kein Eintrag; das aktuelle Flag bleibt davon getrennt und färbt nichts ein. |

### Spaltenliste (`GL.BuildAttendanceColumns`)

Verdichtet `nights` zu einer flachen Spaltenliste für den Tab: aufgeklappte Abende liefern eine
Spalte je Bosskill, alle anderen genau eine. Liegt im Core-Modul statt in der UI, weil
`UI_AttendanceTab.lua` nicht im busted-Loader ist — so bleibt die einzige nennenswerte Logik des
Aufklappens pur und testbar. Helper `Nights(spec)` baut die Eingabe ohne DB.

| Test | Prüft |
|------|-------|
| `testBuildColumns_CollapsedGivesOneColumnPerNight` | Eingeklappt → eine Spalte je Abend, `key == nightId`. |
| `testBuildColumns_ExpandedGivesOneColumnPerKill` | Aufgeklappt → eine Spalte je Kill, `key == "nightId#index"`, `label` ist die Kill-Nummer; andere Abende bleiben einspaltig. |
| `testBuildColumns_SingleKillNightIsNotExpandable` | Abend mit einem Kill bleibt auch explizit aufgeklappt eine Abend-Spalte. |
| `testBuildColumns_ExpandableFlagFollowsKillCount` | `expandable` nur bei mehr als einem Kill — deckt Altdaten ohne `kills`-Ebene mit ab. |
| `testBuildColumns_GroupStartOnFirstColumnOfEachNight` | `groupStart` sitzt genau auf der ersten Spalte jedes Abends (Trenner im Kopf). |
| `testBuildColumns_NightIdOnEveryColumn` | Auch Bossspalten tragen `nightId` — der Klick-Handler braucht ihn zum Zuklappen. |
| `testBuildColumns_KeepsNightOrder` | Reihenfolge aus `ComputeAttendance` (neueste zuerst) wird nicht umsortiert. |
| `testBuildColumns_EmptyAndNilInputs` | Leere und fehlende Eingaben → leere Liste statt Fehler; `expanded` ist optional. |
| `testBuildColumns_LabelsAndTooltips` | Abend-Tooltip nennt die Anzahl Bosse, Bossspalten nennen den Bossnamen. |
| `testBuildColumns_GroupLabelIsSessionName` | `groupLabel` trägt den Session-Namen — die UI schreibt ihn über die aufgeklappte Gruppe. |
| `testBuildColumns_GroupLabelFallsBackToDate` | Session ohne Namen → Datum, damit die Gruppe nie unbeschriftet bleibt. |
| `testBuildColumns_KillTooltipCarriesDifficulty` | Bosskill-Tooltip nennt N/H/M aus `meta.difficulty`. |
| `testBuildColumns_KillTooltipWithoutDifficulty` | Altdaten ohne `difficulty` → kein leerer Trenner im Tooltip. |
| `testBuildColumns_DifficultyOnKillColumns` | `difficulty` je Bossspalte — die UI hinterlegt den Kopf danach (N grün, H blau, M lila). |
| `testBuildColumns_KillColumnsCarryDeleteHandles` | Bossspalten tragen `sessionId`/`raidID`/`killIndex` — der Rückweg, den der Tab zum Löschen braucht. |
| `testBuildColumns_EmptyDayCarriesSessionsToDelete` | Tag ganz ohne Kill → `emptySessions` nennt die betroffenen Sessions. |
| `testBuildColumns_DayWithKillsHasNoEmptySessions` | Spalte mit Kills trägt kein `emptySessions` — dort wäre nicht klar, was ein Löschen träfe. |
| `testBuildColumns_SingleEntryNightIsDeletable` | Steht **genau ein** Eintrag hinter einer eingeklappten Spalte, trägt sie den Rückweg — der Fall für Altdaten ohne Kill-Ebene, `killIndex` bleibt `nil`. |
| `testBuildColumns_MultiEntryNightIsNotDeletable` | Mehrere Kills hinter einer eingeklappten Spalte → kein Rückweg, weil mehrdeutig. |
| `testBuildColumns_NightDifficultyOnlyWhenUniform` | Eingeklappte Spalte nur bei einheitlichem Abend; nach einem Wechsel H→M keine, statt eine zu behaupten. |

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

Die Abend-Ebene (`present[nightId]`, `attended`, `pct`) stimmt in beiden Fällen. Im Tab lässt
sich eine Abend-Spalte per Klick in ihre Bosskill-Spalten aufklappen — Abende ohne
aufgezeichnete Kills sind dabei nicht klickbar (`expandable == false`).

`Att.%` bleibt abend-basiert, auch bei aufgeklappten Spalten: eine Prozentzahl über Bosskills
wäre eine andere Kennzahl.
