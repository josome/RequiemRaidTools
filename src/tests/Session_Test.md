# Session Testdokumentation

**Datei:** `src/tests/Session_Test.lua`  
**Framework:** [WoWUnit](https://www.curseforge.com/wow/addons/wowunit) (läuft in-game, kein externer Lua-Runner)  
**Suite-Name im WoWUnit-Fenster:** `ReqRT.Session`

---

## Inhaltsverzeichnis

- [Voraussetzungen](#voraussetzungen)
- [Testziel](#testziel)
- [Teststrategie](#teststrategie)
- [Testfälle](#testfälle)
  - [testStart](#teststart)
  - [testRename](#testrename)
  - [testClose](#testclose)
  - [testDelete](#testdelete)
  - [testStartBlockedWhenActive](#teststartblockedwhenactive)
  - [testDefaultLabel](#testdefaultlabel)
  - [testPriorityConfig](#testpriorityconfig)
  - [testResume](#testresume)
  - [testRaidsInSession](#testraidinsession)
- [Was diese Tests nicht abdecken](#was-diese-tests-nicht-abdecken)

---

## Voraussetzungen

| Bedingung | Warum |
|-----------|-------|
| WoWUnit installiert | Test-Framework |
| `/reqrt devmode` aktiv | Tests registrieren sich nicht ohne devMode |
| `/reload` nach devMode-Toggle | GuildLootDB muss korrekt initialisiert sein |
| Keine aktive Raid Session | Tests isolieren GuildLootDB intern — eine aktive Session beim Reload führt zu Konflikten |

---

## Testziel

Integrationstest der Session-Logik:

```
StartContainer  →  EnsureRaidMeta  →  AssignLootConfirm  →  CloseContainer
```

Getestet wird ob Sessions korrekt angelegt, benannt, geschlossen und gelöscht werden,
und ob mehrere Raids mit ihrem Loot korrekt einer Session zugeordnet werden.

---

## Teststrategie

Gleiche Patterns wie `ReqRT.Assign`:
- `WithTestDB(fn)` — DB-Swap mit pcall-Schutz (GuildLootDB wird immer wiederhergestellt)
- `MockSideEffects()` — Comm, UI und Chat-Ausgaben gestubbt
- `SetupCurrentItem(raidID, sessionID)` — Item direkt in currentItem setzen

---

## Testfälle

### `testStart`
`GL.StartContainer("KW 15 2026")` aufrufen.
- `#raidContainers == 1`
- `activeContainerIdx == 1`
- `raidContainers[1].label == "KW 15 2026"`
- `id` und `startedAt` vorhanden

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
- Nur 1 Session in `raidContainers`
- Label ist der der ersten Session

### `testDefaultLabel`
`StartContainer("")` aufrufen.
- `label` ist nicht nil und nicht leer (auto-generiert als "KW XX YYYY")

### `testPriorityConfig`
`settings.priorities` mit bekannten Werten belegen, dann `StartContainer`.
- `session.priorityConfig` enthält dieselben Werte

### `testResume`
Session anlegen, raidMeta befüllen, schließen, dann `GL.ResumeContainer(1)`.
- `activeContainerIdx == 1`
- `session.closedAt == nil`
- `currentRaid.id` und `.tier` aus raidMeta geladen

### `testRaidsInSession`
Session anlegen, 4 Raids durchlaufen (je `EnsureRaidMeta` + `AssignLootConfirm`).
- `#lootLog == 4`
- `raidMeta` hat 4 Einträge
- Jeder lootLog-Eintrag hat die korrekte `raidID`

---

## Was diese Tests nicht abdecken

| Bereich | Warum nicht abgedeckt |
|---------|-----------------------|
| ResumeContainer | Komplex, eigener Testfall bei Bedarf |
| Comm-Übertragung | → Zuständigkeit der `ReqRT.Comm`-Suite |
| UI-Rendering | UI-Layer ist nicht Gegenstand der Session-Tests |
