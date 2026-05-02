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
- Neue Session korrekt angelegt (`id`, `label`, `raidMeta`, `lootLog`)

### `testLateJoinerSyncWithLootTrash`
SESSION_SYNC mit `trashedLoot`-Eintrag.
- `trashedLoot[1].link` und `.raidID` korrekt übertragen

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

## Was diese Tests nicht abdecken

| Bereich | Warum nicht abgedeckt |
|---------|-----------------------|
| Comm-Übertragung | → Zuständigkeit der `ReqRT.Comm`-Suite |
| UI-Rendering | UI-Layer ist nicht Gegenstand der Session-Tests |
