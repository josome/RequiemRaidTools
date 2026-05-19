# Loot Testdokumentation

**Datei:** `src/tests/Loot_Test.lua`
**Framework:** [WoWUnit](https://www.curseforge.com/wow/addons/wowunit) in-game und busted standalone (`spec/reqrt_spec.lua`)
**Suite-Name im WoWUnit-Fenster:** `ReqRT.Loot`

---

## Inhaltsverzeichnis

- [Voraussetzungen](#voraussetzungen)
- [Testziel](#testziel)
- [Teststrategie](#teststrategie)
- [Testfälle](#testfälle)
  - [OnLootOpened](#onlootopened)
  - [OnLootRollStart (MASTER-Loot)](#onlootrollstart-master-loot)
  - [AddItemManually](#additemmanually)
  - [TryAddPendingItem-Filter](#tryaddpendingitem-filter)
  - [Trash-Operations](#trash-operations)
  - [Reset / Cancel](#reset--cancel)
- [Was diese Tests nicht abdecken](#was-diese-tests-nicht-abdecken)
- [Tests erweitern](#tests-erweitern)

---

## Voraussetzungen

| Bedingung | Warum |
|-----------|-------|
| WoWUnit installiert (in-game) **oder** busted (CI) | Test-Framework |
| `/reqrt devmode` aktiv (in-game) | Schützt Produktiv-Nutzer |
| `/reload` nach devMode-Toggle (in-game) | DB-Initialisierung |

---

## Testziel

Tests für `src/loot/Loot.lua`. Deckt den **User-Hot-Path** ab: Boss tot → Items werden via `OnLootOpened` (Boss-Korpse) oder `OnLootRollStart` (Group-Loot-Roll) erkannt, in `pendingLoot` einsortiert, manipulierbar via Trash-Operations. Bisher kein Auto-Test → wichtigste Coverage-Lücke vor Refactorings im Loot-Bereich.

---

## Teststrategie

`WithTestDB(fn)` ersetzt `GuildLootDB` durch einen Test-State mit aktiver Session (`sess-A`), Standard-Filter-Settings (`minQuality=4`, `filterNonEquip=true`, alle Kategorien aktiv) und `currentRaid` (raidID=`raid-01`, difficulty=`H`, lastBoss=`Ulgrax`).

`MockBasics()` mocked: `IsMasterLooter` → true, `Print`/UI-Refresh als No-Op, `Comm.SendItemClear` als No-Op, plus eine Standard-Item-Info via `MockItemInfo()` (Cloth-Chest, Epic, BoP, kein Set, kein Token).

`MockLootSlots(slots)` / `MockLootRoll(rollID, link, quality)` setzen die WoW-API-Stubs für die jeweiligen Loot-Erkennungs-Pfade.

---

## Testfälle

### OnLootOpened

| Test | Was wird geprüft |
|------|------------------|
| `testOnLootOpened_NotMasterLooter_Ignored` | Observer ignoriert das Loot-Fenster |
| `testOnLootOpened_AddsQualifiedItems` | Zwei Epic-Items → beide in `pendingLoot` |
| `testOnLootOpened_FiltersLowQuality` | Quality < `minQuality` → ignoriert |
| `testOnLootOpened_FiltersQuestItems` | `isQuestItem=true` → ignoriert |
| `testOnLootOpened_DeduplicatesAgainstExistingPending` | Item bereits in `pendingLoot` → kein Duplikat |
| `testOnLootOpened_AllowsMultipleDrops` | 2× gleiches Item im Loot-Fenster, 0× in pending → beide hinzu |

### OnLootRollStart (MASTER-Loot)

| Test | Was wird geprüft |
|------|------------------|
| `testOnLootRollStart_NotMasterLooter_Ignored` | Observer ignoriert |
| `testOnLootRollStart_NoActiveSession_Ignored` | Keine aktive Session → no-op |
| `testOnLootRollStart_AddsItem` | Item wird in `pendingLoot` eingefügt |
| `testOnLootRollStart_LowQuality_Ignored` | Quality < `minQuality` → ignoriert |
| `testOnLootRollStart_DuplicateRollIDIgnored` | Zweiter Aufruf mit gleicher `rollID` → kein Duplikat |

### AddItemManually

| Test | Was wird geprüft |
|------|------------------|
| `testAddItemManually_AddsToPending` | Item direkt in `pendingLoot` |
| `testAddItemManually_DeferredWhenItemInfoMissing` | `GetItemInfo`-Cache-Miss → in `_deferredPendingItems` mit `manual=true` |

### TryAddPendingItem-Filter

| Test | Was wird geprüft |
|------|------------------|
| `testTryAddPendingItem_FiltersWarbound` | `bindType=8` (ToBnetAccount) → ausgefiltert |
| `testTryAddPendingItem_FiltersNonEquipWhenSet` | Leerer `equipLoc` + nicht-`setItems` → ausgefiltert |
| `testTryAddPendingItem_StampsRaidAndSessionID` | Item bekommt `sessionID`, `raidID`, `difficulty` aus aktuellem Kontext |

### Trash-Operations

| Test | Was wird geprüft |
|------|------------------|
| `testRemovePendingItem_MovesToTrash` | `pendingLoot` → `trashedLoot` |
| `testRestoreFromTrash_MovesBack` | `trashedLoot` → `pendingLoot` |
| `testDeleteFromTrash_Removes` | Endgültig aus Trash entfernt, nicht in Pending |
| `testTrashActiveItem_ClearsCurrent` | `currentItem` wird gelöscht UND Item aus Pending in Trash verschoben |

### Reset / Cancel

| Test | Was wird geprüft |
|------|------------------|
| `testResetCurrentItem_ClearsLink` | `currentItem.link` wird auf `nil` gesetzt |
| `testCancelPrio_OnlyWhenPrioActive` | `prioState.active=false` → no-op; `=true` → ClearCurrentItem |

---

## Was diese Tests nicht abdecken

| Bereich | Warum nicht abgedeckt |
|---------|-----------------------|
| `getRaidIDForCurrentLoot` Edge-Cases | Lokale Helper-Funktion; die kritischen Pfade werden über `testTryAddPendingItem_StampsRaidAndSessionID` indirekt verifiziert |
| Loot-Erkennung mit `_deferredPendingItems`-Replay | Über `OnItemInfoReceived` in `Loot_Assign.lua` — eigene Test-Suite |
| MASTER-Loot vs. Group-Loot Unterschiede | Aktuell nur Group-Loot-Pfad (`OnLootRollStart`); MASTER-Loot über `OnLootOpened` ist abgedeckt |
| Filter-Kategorie-Tests | → `ReqRT.Filter`-Suite (`Filter_Test.lua`) |
| Roll-Logik | → `ReqRT.Roll`-Suite (`Roll_Test.lua`) |

---

## Tests erweitern

```lua
function Tests:testMeinFall()
    WithTestDB(function()
        MockBasics()
        MockLootSlots({
            { link = "|Hitem:1234|h|r", quality = 4 },
        })
        Loot.OnLootOpened()
        AreEqual(1, #Loot.GetPendingLoot())
        MockRestore()
    end)
end
```

**Hinweis:** `MockItemInfo({...})` mit Overrides für `bindType`, `subType`, `equipLoc`, `setID` ermöglicht das Testen unterschiedlicher Item-Charakteristika ohne den Filter zu trickern.
