# Session Testdokumentation

**Datei:** `src/tests/Session_Test.lua`  
**Framework:** [WoWUnit](https://www.curseforge.com/wow/addons/wowunit) (läuft in-game, kein externer Lua-Runner)  
**Suite-Name im WoWUnit-Fenster:** `ReqRT.Session`

---

## Voraussetzungen

| Bedingung | Warum |
|-----------|-------|
| WoWUnit installiert | Test-Framework |
| `/reqrt devmode` aktiv | Tests registrieren sich nicht ohne devMode |
| `/reload` nach devMode-Toggle | GuildLootDB muss korrekt initialisiert sein |

---

## Testziel

Integrationstests für den gesamten Session-Lifecycle sowie die Observer-seitige Comm-Verarbeitung:

```
StartContainer → EnsureRaidMeta → AssignLootConfirm → CloseContainer
SESSION_SYNC-Whisper → Observer-DB-Aufbau
MergeSessionIntoActive → pendingLoot-Migration
```

---

## Teststrategie

- `WithTestDB(fn)` — DB-Swap mit pcall-Schutz (GuildLootDB wird immer wiederhergestellt). Test-State enthält leere `raidContainers`, keinen aktiven Container, vorbereiteten `currentRaid`-Buffer (`id="raid-01"`, `pendingLoot={}`, ein Teilnehmer).
- `MockSideEffects()` — stubbt alle Comm- und UI-Funktionen die von `StartContainer`/`CloseContainer` aufgerufen werden.
- `CaptureWhispers(session)` — ruft `Comm.SendSessionSync` auf, fängt alle generierten WHISPER-Nachrichten ab. Für Late-Joiner-Tests ohne echte Netzwerkpakete.
- `SetupCurrentItem(raidID, sessionID)` — befüllt `currentItem` für Assign-Schritte innerhalb von Session-Tests.

---

## Testfälle

### `testStart`
`GL.StartContainer("KW 15 2026")` aufrufen.
- `#raidContainers == 1`, `activeContainerIdx == 1`
- `label == "KW 15 2026"`, `id` und `startedAt` vorhanden

### `testRename`
Session anlegen, dann `session.label = "Neuer Name"` setzen.
- `raidContainers[1].label == "Neuer Name"`

### `testClose`
Session anlegen, dann `GL.CloseContainer()` aufrufen.
- `activeContainerIdx == nil`
- `raidContainers[1].closedAt` vorhanden und > 0

### `testDelete`
Session anlegen, schließen, dann `table.remove` + `activeContainerIdx = nil`.
- `#raidContainers == 0`

### `testStartBlockedWhenActive`
Session anlegen, dann erneut `StartContainer` aufrufen.
- Nur 1 Session in `raidContainers`, Label der ersten Session

### `testDefaultLabel`
`StartContainer("")` aufrufen.
- `label` ist nicht nil und nicht leer (auto-generiert als "KW XX YYYY")

### `testPriorityConfig`
`settings.priorities` mit bekannten Werten belegen, dann `StartContainer`.
- `session.priorityConfig` enthält dieselben Werte

### `testResume`
Session anlegen, raidMeta befüllen, schließen, dann `GL.ResumeContainer(1)`.
- `activeContainerIdx == 1`, `session.closedAt == nil`
- `currentRaid.id` und `.tier` aus raidMeta geladen

### `testRaidsInSession`
Session anlegen, 4 Raids durchlaufen (je `EnsureRaidMeta` + `AssignLootConfirm`).
- `#lootLog == 4`, `raidMeta` hat 4 Einträge
- Jeder lootLog-Eintrag hat die korrekte `raidID`

### `testLateJoinerSyncNewSession`
`CaptureWhispers` generiert SESSION_SYNC-Whisper, alle durch `Comm.OnMessage` jagen.
- Neue Session + `raidMeta` korrekt angelegt (`id`, `label`, `raidMeta`)
- Slim-Sync: `#lootLog == 0` (keine Loot-Historie beim Observer)

### `testLateJoinerSyncWithLootTrash`
SESSION_SYNC einer Session mit `trashedLoot`-Eintrag.
- Slim-Sync: kein Trash-Replay → Observer-`trashedLoot` bleibt leer (`#trashedLoot == 0`)

### `testLateJoinerSyncUpdatesExistingSession`
Bestehende inaktive Session mit gleicher ID ist bereits in `raidContainers`.
- Kein Duplikat, Session reaktiviert, neues `raidMeta`-Feld hinzugefügt

### `testBroadcastSessionStartObserverChain`
ML sendet SESSION_START als RAID-Broadcast → Observer-Seite empfängt via `Comm.OnMessage`.
- Session in Observer-DB angelegt, `activeContainerIdx` gesetzt, `isMasterLooter` bleibt false

### `testRaidMetaAppliesPrioConfig`
`GL.OnCommRaidMeta` mit prioCfg aufrufen.
- `session.priorityConfig` enthält die übertragenen Werte

### `testRaidQuerySendsMLAnnounce`
`GL.OnCommRaidQuery` aufrufen (nicht im Kampf).
- `Comm.SendMLAnnounce` wird aufgerufen

### `testObserverPrioFromSession`
Observer hat lokale Prios `Blah/Blub`. ML sendet SESSION_START mit `BIS/OS`.
- `session.priorityConfig` enthält `BIS/OS`
- `settings.priorities` enthält weiterhin `Blah/Blub`

### `testObserverLocalPriosUnchangedAfterSessionEnd`
SESSION_START gefolgt von SESSION_END.
- `settings.priorities` noch `Blah/Blub`, `activeContainerIdx == nil`

### `testRaidQueryCombatGate`
`UnitAffectingCombat` gibt "player" zurück → ML ist im Kampf.
- `SendSessionSync` wird nicht aufgerufen
- Request landet in `GL._pendingSyncRequests`

### `testAssignWithoutRaidMetaCreatesStub`
Observer empfängt `ASSIGN` für eine `raidID`, die noch nicht in `session.raidMeta` existiert (z.B. verpasstes `RAID_META`-Broadcast wegen `/reload` oder Disconnect).
- Slim-Sync: **kein** `lootLog`-Eintrag (Observer führt keine Historie)
- `session.raidMeta[raidID]` wird mit `isStub=true`, `difficulty=<diff>`, `tier=""`, leerem `participants` als Selbstheilungs-Stub angelegt — damit der UI-Raid-Tab den Raid sofort listen kann

### `testAssignWithoutRaidMetaTriggersRaidQuery`
Gleicher Aufruf wie oben.
- `Comm.SendRaidQuery` wird einmal aufgerufen, damit der ML via `SendSessionSync` die vollständigen `raidMeta`-Daten nachschickt
- Rate-limited über `GL._lastRaidQuery` (geteilter Throttle mit `Core_Events.OnEventRosterUpdate`)

### `testRaidMetaOverwritesStub`
Bestehender Stub-Eintrag (`isStub=true`) wird durch ein echtes `RAID_META` ersetzt.
- `tier`, `participants` und alle anderen Felder kommen aus dem RAID_META
- `isStub`-Flag ist im neuen Eintrag nicht mehr gesetzt

### `testRaidMetaDoesNotOverwriteRealEntry`
Bereits vollständiger `raidMeta`-Eintrag (ohne `isStub`) bleibt durch ein zweites `RAID_META` unverändert (bestehende Semantik — Late-Join-Sync soll nichts kaputtmachen).
- Tier, Difficulty, startedAt, Participants behalten ihre Werte

### `testLegacySessionCreatedWhenPendingLootExists`
`currentRaid.pendingLoot` hat 2 Items, dann `StartContainer` aufrufen.
- 2 Sessions in `raidContainers` (Legacy + Neue)
- Legacy-Session hat `closedAt` gesetzt und enthält beide Items
- Neue Session ist aktiv (`activeContainerIdx == 2`)

### `testNoLegacySessionWhenPendingLootEmpty`
`pendingLoot` leer, dann `StartContainer`.
- Nur 1 Session, kein Legacy-Container

### `testLegacySessionClearsPendingLoot`
`pendingLoot` hat 1 Item, dann `StartContainer`.
- `currentRaid.pendingLoot` danach leer

### `testMergeMovesItemsToActiveSession`
Legacy-Session (Index 1, geschlossen, 2 Items) + aktive Session (Index 2). `MergeSessionIntoActive(1)` aufrufen.
- Nur noch 1 Session, Items A und B in `activeSession.pendingLoot`

### `testMergeCorrectesActiveIdx`
Source-Index (1) < `activeContainerIdx` (2). Nach Merge: `activeContainerIdx == 1`

### `testMergeWithoutActiveSessionIsNoop`
`activeContainerIdx = nil`, dann `MergeSessionIntoActive(1)`.
- Session bleibt unverändert, Items bleiben in Legacy-Session

---

## Refactoring-Vorbereitung (PENDING-Tests)

Diese Tests gaten sich selbst über `type(GuildLoot.X) == "function"`. Solange die Refactorings (Paket C1/C2 des Code-Reviews) nicht umgesetzt sind, werden sie no-op-passed; sobald die Funktion existiert, prüfen sie das Verhalten.

### C1 — `GuildLoot.DeleteSession(ci)`

| Test | Was wird geprüft |
|------|------------------|
| `testDeleteSession_RemovesFromContainers` | Eintrag wird aus `raidContainers` entfernt |
| `testDeleteSession_ClearsActiveIdxWhenDeletingActive` | Löschen der aktiven Session nullt `activeContainerIdx` |
| `testDeleteSession_KeepsActiveIdxWhenDeletingOther` | Bei Löschen einer Session vor der aktiven rückt der Index korrekt vor |
| `testDeleteSession_OutOfBoundsIndex_NoOp` | Ungültiger Index crasht nicht und ändert nichts |

### C2 — `GuildLoot.MigratePendingLoot()`

| Test | Was wird geprüft |
|------|------------------|
| `testMigratePendingLoot_CreatesLegacyContainer` | Direktaufruf erzeugt Legacy-Container, `currentRaid.pendingLoot` wird geleert |
| `testMigratePendingLoot_Idempotent` | Zweiter Aufruf erzeugt keinen zweiten Legacy-Container |
| `testMigratePendingLoot_EmptyPending_NoOp` | Leeres `currentRaid.pendingLoot` → kein Legacy-Container |

### EnsureRaidParticipants

Solo feuert WoW kein `GROUP_ROSTER_UPDATE`, und `StartContainer` überspringt `LoadRaidRoster`
mangels Gruppe — `currentRaid.participants` bliebe leer und der Bosskill damit ohne Teilnehmer
(keine Zeile, keine grüne Zelle in der Attendance-Matrix). `GL.EnsureRaidParticipants` schließt
diese Lücke vor `GL.EnsureRaidMeta` in `OnEventEncounterEnd`.

| Test | Prüft |
|------|-------|
| `testEnsureRaidParticipants_SoloFillsEmptyList` | Leere Liste + solo → eigener Char wird eingetragen |
| `testEnsureRaidParticipants_KeepsExistingList` | Befüllte Liste bleibt unangetastet (kumulativ, darf nicht auf den Gruppenstand zurückfallen) |

### RecordKillAttendance

`GL.EnsureRaidMeta` legt `raidMeta[id]` nur **einmal** pro Raid-ID an — und eine Raid-ID ist eine
Tier+Difficulty-Kombination, kein Boss. Die Teilnehmerliste fror dadurch beim ersten Bosskill des
Abends ein: wer später nachrückte, fehlte für den gesamten Abend, und eine Boss-Ebene gab es
überhaupt nicht.

`GL.RecordKillAttendance(bossName, encounterID)` läuft bei **jedem** Kill (aufgerufen in
`OnEventEncounterEnd` direkt nach `GL.EnsureRaidMeta`) und tut zwei Dinge: den Gruppenstand zum
Kill als eigenen `kills`-Eintrag anhängen und dieselben Namen in `meta.participants` vereinigen.
Die Einzelliste wird zusätzlich gespeichert, weil sie nicht rekonstruierbar ist — aus den
Einzellisten lässt sich die Vereinigung jederzeit bilden, umgekehrt nie.

| Test | Prüft |
|------|-------|
| `testRecordKillAttendance_FirstKillCreatesKillsList` | Erster Kill legt `kills` an, mit `boss`, `encounterID`, `ts` und Teilnehmern |
| `testRecordKillAttendance_SecondKillAppends` | Zweiter Kill hängt an statt zu überschreiben → eine Spalte je Boss |
| `testRecordKillAttendance_LateJoinerAddedToNightList` | Nachrücker landet in `meta.participants` (der eigentliche Bug) |
| `testRecordKillAttendance_NoDuplicatesInNightList` | Wiederholte Namen werden nicht dupliziert (Set-Semantik) |
| `testRecordKillAttendance_LeaverStaysInNightList` | Wer geht, bleibt in der Abend-Liste; der Kill selbst kennt nur die Anwesenden |
| `testRecordKillAttendance_EmptySnapshotFallsBackToNightList` | Ohne frischen Snapshot greift `currentRaid.participants` statt einer leeren Spalte |
| `testRecordKillAttendance_RecordsTrialStateAtKill` | `kill.trials` hält fest, wer zum Kill Trial war |
| `testRecordKillAttendance_LaterPromotionLeavesOldKillUntouched` | Beförderung zwischen zwei Kills ändert den ersten nicht |
| `testRecordKillAttendance_TrialsTableExistsWhenNobodyIsTrial` | Leere Tabelle statt `nil` — unterscheidet „niemand war Trial" von „nicht aufgezeichnet" |
| `testRecordKillAttendance_NoSessionIsNoOp` | `ENCOUNTER_END` ohne laufende Session wirft nicht |
| `testRecordKillAttendance_UnknownRaidMetaIsNoOp` | Fehlender `raidMeta`-Eintrag legt keinen an — das ist Sache von `EnsureRaidMeta` |

**Trial-Stand beim Kill.** Die Trial-Rolle endet nach drei Raids. Würde die Matrix das aktuelle
Flag einfärben, würde eine Beförderung rückwirkend alle bereits gelaufenen Abende der Season
umdeuten. `kill.trials` friert den Stand deshalb pro Kill ein.

### DeleteKillAttendance / DeleteEmptySession

Zum Aufräumen von Testleichen und Fehlaufzeichnungen aus dem Attendance-Tab (Rechtsklick auf den
Spaltenkopf, zweistufig). Beide fassen die **Loot-Historie nicht an** — gelöschter Loot ist nicht
wiederherstellbar, und wer die Attendance korrigiert, will selten den Loot verlieren.

`GL.DeleteKillAttendance(sessionId, raidID, killIndex)` entfernt einen einzelnen Bosskill. Bleibt
der `raidMeta`-Eintrag ohne Kills zurück, verschwindet er ganz (sonst bliebe eine Geisterspalte
mit Teilnehmern ohne Kill). Sonst wird `meta.participants` aus den verbliebenen Kills neu gebildet.

`GL.DeleteEmptySession(sessionId)` entfernt eine Session, an der nichts mehr hängt — der einzige
Weg, eine Spalte **ohne** Bosskill loszuwerden. Sie verweigert bei Kills, Loot, aussortiertem oder
offenem Loot und bei der laufenden Session, und nennt den Grund.

| Test | Prüft |
|------|-------|
| `testDeleteKillAttendance_RemovesOnlyThatKill` | Nur der gewählte Kill geht, der Rest bleibt |
| `testDeleteKillAttendance_RebuildsNightParticipants` | Wer nur bei diesem Kill dabei war, verschwindet aus der Abend-Liste |
| `testDeleteKillAttendance_LastKillRemovesRaidMeta` | Letzter Kill nimmt den `raidMeta`-Eintrag mit |
| `testDeleteKillAttendance_KeepsLootLog` | `lootLog` und Session bleiben bestehen |
| `testDeleteKillAttendance_UnknownTargetsAreNoOp` | Unbekannte Session/raidID/Index → `false` |
| `testDeleteEmptySession_RemovesSessionWithoutKillsOrLoot` | Leere Session wird entfernt |
| `testDeleteEmptySession_RefusesWhenSomethingIsWorthKeeping` | Kills bzw. Loot → Ablehnung mit Grund |
| `testDeleteEmptySession_RefusesActiveSession` | Die laufende Session wird nie angefasst |

---

## Was diese Tests nicht abdecken

| Bereich | Warum nicht abgedeckt |
|---------|-----------------------|
| Comm-Übertragung | → Zuständigkeit der `ReqRT.Comm`-Suite |
| UI-Rendering | UI-Layer ist nicht Gegenstand der Session-Tests |
