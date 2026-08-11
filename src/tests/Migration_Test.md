# Migration Testdokumentation

**Datei:** `src/tests/Migration_Test.lua`
**Framework:** busted (`spec/reqrt_spec.lua`)
**Suite-Name:** `ReqRT.Migration`

---

## Inhaltsverzeichnis

- [Voraussetzungen](#voraussetzungen)
- [Testziel](#testziel)
- [Teststrategie](#teststrategie)
- [Testfälle](#testfälle)
  - [InitDB Defaults & Field-Filling](#initdb-defaults--field-filling)
  - [MigrateRaidHistory](#migrateraidhistory)
  - [InitDB triggert Legacy-Migration](#initdb-triggert-legacy-migration)
  - [Backup-Mechanik](#backup-mechanik)
- [Was diese Tests nicht abdecken](#was-diese-tests-nicht-abdecken)
- [Tests erweitern](#tests-erweitern)

---

## Voraussetzungen

| Bedingung | Warum |
|-----------|-------|

---

## Testziel

Tests für die DB-Migrationen in `src/Core.lua`. Schützt vor Regressions im **kritischsten Code-Pfad**: bei jedem Login wird `GL.InitDB()` aufgerufen, das mehrere Migrationen kaskadiert. Wenn dieser Pfad bricht, ist die Spieler-DB potentiell unbrauchbar.

Abgedeckt:
- `GL.InitDB` (Public-API)
- `GL.MigrateRaidHistory` (Public-API)
- `MigrateCurrentRaidLegacy` (local, indirekt via InitDB)
- `MigrateRaidFormat` (local, indirekt via InitDB)
- `BackupDB` (local, indirekt via InitDB)

---

## Teststrategie

`WithTestDB(initialDB, fn)` ersetzt `GuildLootDB` durch einen handgebauten Test-State (mit gezielt minimalen oder partiellen Daten), ruft `fn` auf, stellt Original wieder her. `GuildLootDBBackup` wird ebenfalls isoliert. `GL.Print` ist während der Tests gemockt, um Konsolenausgaben zu unterdrücken.

Test-Pattern:
```
1. Arrange — WithTestDB mit Partial-State (z.B. nur legacy raidHistory)
2. Act     — GL.InitDB() oder GL.MigrateRaidHistory()
3. Assert  — Bestandsdaten erhalten + Defaults gefüllt + Legacy-Migration korrekt
4. Cleanup — WithTestDB stellt Original automatisch wieder her
```

---

## Testfälle

### InitDB Defaults & Field-Filling

| Test | Was wird geprüft |
|------|------------------|
| `testInitDB_EmptyDB_AppliesDefaults` | Leere DB → alle Default-Felder werden angelegt |
| `testInitDB_PartialDB_FillsMissingFields` | Partiell befüllte DB → Bestandsdaten erhalten, Lücken gefüllt |
| `testInitDB_PreservesExistingSettings` | User-Settings (`chatChannel`, `minQuality`, `rollSeconds`) bleiben, fehlende Defaults werden ergänzt |
| `testInitDB_ResetsTransientFlags` | `isMasterLooter` und `dungeonMode` werden bei jedem Login zurückgesetzt |
| `testInitDB_GeneratesCurrentRaidIDIfMissing` | Leere `currentRaid.id` → wird via `GL.GenerateRaidID` befüllt |
| `testInitDB_PreservesCurrentRaidID` | Existierende `currentRaid.id` bleibt unverändert |

### MigrateRaidHistory

| Test | Was wird geprüft |
|------|------------------|
| `testMigrateRaidHistory_MovesEntriesAndClears` | `raidHistory` Einträge → `unassignedRaids`, `raidHistory` leer |
| `testMigrateRaidHistory_EmptyHistory_NoOp` | Leere `raidHistory` → keine Mutation |
| `testMigrateRaidHistory_AppendsNotReplaces` | Bestehende `unassignedRaids` werden nicht überschrieben — neue werden angehängt |
| `testInitDB_TriggersRaidHistoryMigration` | `GL.InitDB()` triggert MigrateRaidHistory wenn `raidHistory` nicht leer |

### InitDB triggert Legacy-Migration

| Test | Was wird geprüft |
|------|------------------|
| `testInitDB_MigratesLegacyCurrentRaidLootLog` | `currentRaid.lootLog` Einträge → `unassignedRaids`; `currentRaid.lootLog` wird auf `nil` gesetzt |
| `testInitDB_NoLegacyLootLog_NoUnassignedCreated` | Leeres `currentRaid.lootLog` → keine unassigned-Erzeugung |
| `testInitDB_MigratesLegacyRaidsArrayToRaidMeta` | Altes `raidContainers[].raids[]` Format → `raidMeta` + `lootLog` mit raidID/sessionID-Stempel |
| `testInitDB_EnsuresRaidMetaTables` | Session ohne `raidMeta`/`lootLog`/`trashedLoot` → Tables werden angelegt |

### Backup-Mechanik

| Test | Was wird geprüft |
|------|------------------|
| `testInitDB_CreatesBackupWhenLootExists` | Session mit Loot → `GuildLootDBBackup` wird angelegt mit `savedAt`-Timestamp |
| `testInitDB_NoBackupOnEmptyContainers` | Leere `raidContainers` → kein Backup (BackupDB returnt früh) |

---

## Was diese Tests nicht abdecken

| Bereich | Warum nicht abgedeckt |
|---------|-----------------------|
| `DeepMergeDefaults`-Tiefe (verschachtelte Sub-Tables) | Implementation-Detail; über die Settings-/Priorities-Tests indirekt verifiziert |
| `BackupDB`-Schutz vor Überschreiben (kleinere `currentLoot` als `backupLoot`) | Edge-Case; aktuell durch das Loot-Count-Vergleich abgesichert, kein expliziter Test |
| Backup-Restore-Pfad (`/reqrt restore`) | Slash-Command-Handler; eigener Test wäre nötig |
| Schema-Versionierung (Forward-Compat) | Aktuell hat das Addon kein Schema-Version-Feld; Migrationen sind feldspezifisch |

---

## Tests erweitern

```lua
function Tests:testMeinFall()
    WithTestDB({
        -- Test-DB-State
    }, function()
        GL.InitDB()
        AreEqual(expected, GuildLootDB.xxx)
    end)
end
```

**Hinweis:** `WithTestDB` setzt automatisch `GuildLootDB` zurück und unterdrückt `GL.Print`. Wenn du explizite Print-Outputs prüfen willst, mocke `GL.Print` lokal nach dem `WithTestDB`-Aufruf:

```lua
WithTestDB({...}, function()
    local printed
    Mock(GL, "Print", function(msg) printed = msg end)
    GL.MigrateRaidHistory()
    Exists(printed)
end)
```
