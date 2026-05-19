# Util Testdokumentation

**Datei:** `src/tests/Util_Test.lua`
**Framework:** [WoWUnit](https://www.curseforge.com/wow/addons/wowunit) in-game und busted standalone (`spec/reqrt_spec.lua`)
**Suite-Name im WoWUnit-Fenster:** `ReqRT.Util`

---

## Inhaltsverzeichnis

- [Voraussetzungen](#voraussetzungen)
- [Testziel](#testziel)
- [Teststrategie](#teststrategie)
- [Testfälle](#testfälle)
  - [ShortName](#shortname-a5)
  - [GetActivePrios / GetPrioLabel](#getactiveprios--getpriolabel-a4)
  - [FindSessionByID — PENDING](#findsessionbyid--pending-a3)
  - [ShowItemTooltip — PENDING](#showitemtooltip--pending-a2)
- [Tests erweitern](#tests-erweitern)

---

## Voraussetzungen

| Bedingung | Warum |
|-----------|-------|
| WoWUnit installiert (in-game) **oder** busted (CI) | Test-Framework |
| `/reqrt devmode` aktiv (in-game) | Schützt Produktiv-Nutzer |
| `/reload` nach devMode-Toggle (in-game) | Saubere DB-Initialisierung |

---

## Testziel

Unit-Tests für die Hilfsfunktionen in `src/Util.lua`. Fokus: das aktuelle Verhalten der Helper festschreiben, damit Refactorings (Paket A des Code-Reviews) keine Regressions einführen. Tests für noch nicht implementierte Funktionen sind als **PENDING** markiert und gatten sich selbst (`if not GL.Foo then Pending() end`).

---

## Teststrategie

`WithTestDB(db, fn)` ersetzt `GuildLootDB` durch einen handgebauten Test-State, ruft `fn` auf und stellt die Original-DB hinterher wieder her. Keine Mocks für die Helper selbst — sie laufen direkt gegen den Test-State.

---

## Testfälle

### ShortName (A5)

| Test | Erwartet |
|------|----------|
| `testShortName_NameWithRealm` | `"Myriella-Malfurion"` → `"Myriella"` |
| `testShortName_NameWithoutRealm` | `"Myriella"` → `"Myriella"` |
| `testShortName_EmptyString` | `""` → `""` |
| `testShortName_Nil` | `nil` → `""` |
| `testShortName_MultipleDashes` | `"Foo-Bar-Baz"` → `"Foo"` |
| `testShortName_OnlyDashPrefix` | `"-Realm"` → `"-Realm"` (Fallback) |

Fixiert das Bestandsverhalten von `GL.ShortName`. Der dokumentierte Edge-Case-Bug (`return (ok and name) or fullName` greift bei `ok=true, name=nil`) wird durch `testShortName_OnlyDashPrefix` festgeschrieben.

### GetActivePrios / GetPrioLabel (A4)

| Test | Was geprüft |
|------|-------------|
| `testGetActivePrios_FromSessionConfig` | Session-priorityConfig hat Vorrang vor settings |
| `testGetActivePrios_SessionWithoutConfig_FallsBackToSettings` | Wenn Session keine priorityConfig hat, Fallback auf `settings.priorities` |
| `testGetActivePrios_NoActiveSession_UsesSettings` | `activeContainerIdx = nil` → `settings.priorities` |
| `testGetActivePrios_NoConfigAnywhere_Failsafe` | Komplett leere Config → Failsafe `{1, 2, 4}` |
| `testGetActivePrios_OutOfBoundsActiveIdx_FallsBackToSettings` | `activeContainerIdx` zeigt auf nicht-existierende Session → Fallback auf settings |
| `testGetPrioLabel_FromSession` | Label aus Session-Config |
| `testGetPrioLabel_UnknownPrio_DefaultLabel` | Unbekannte Prio → `"Prio N"` |
| `testGetPrioLabel_Nil_ReturnsEmpty` | `nil` → `""` |

Diese Tests müssen nach dem A4-Refactoring (interner Helper `getSessionPriorityConfig`) unverändert grün bleiben.

### FindSessionByID — PENDING (A3)

| Test | Was geprüft |
|------|-------------|
| `testFindSessionByID_Found` | Korrekte Session bei eindeutiger ID |
| `testFindSessionByID_NotFound` | Unbekannte ID → `nil` |
| `testFindSessionByID_EmptyContainers` | Leerer Container → `nil` |
| `testFindSessionByID_NilID` | `nil`-ID → `nil` |

Alle Tests sind via `if not GL.FindSessionByID then Pending() end` geguarded und werden grün/pending bis das A3-Refactoring die Funktion einführt.

### ShowItemTooltip — PENDING (A2)

| Test | Was geprüft |
|------|-------------|
| `testShowItemTooltip_OrderOfCalls` | Reihenfolge `SetOwner` → `SetHyperlink` → `Show` |

Pending bis A2 (`GL.ShowItemTooltip(link, frame)`) implementiert ist.

### UI-Common — PENDING (A1)

| Test | Was geprüft |
|------|-------------|
| `testUICommon_ColorsExist` | `UI.COLORS.DIVIDER`, `BG_AWARDED`, `HIGHLIGHT_HOVER` |
| `testUICommon_BackdropsExist` | `UI.BACKDROPS.TOOLTIP`, `DIALOG` |

Pending bis A1 (UI-Helper-Modul `src/ui/UI_Common.lua`) angelegt ist.

### Tab-Registry — PENDING (B4)

| Test | Was geprüft |
|------|-------------|
| `testTabRegistry_AllTabsRegistered` | `UI.TABS` enthält `LOOT`, `LOG`, `RAID`, `ROLL`, `PLAYER` |

Pending bis B4 (Tab-Registry-Tabelle statt nummerierter Konstanten).

### GetItemCategory (T2.5)

| Test | Was geprüft |
|------|-------------|
| `testGetItemCategory_Weapon` | `INVTYPE_WEAPON`/`MAINHAND`/`2HWEAPON`/`SHIELD`/`HOLDABLE` → `"weapons"` |
| `testGetItemCategory_Trinket` | `INVTYPE_TRINKET` → `"trinket"` |
| `testGetItemCategory_Other` | `INVTYPE_CHEST`/`LEGS`/`FINGER` → `"other"` |
| `testGetItemCategory_SetItemBySetID` | `C_Item.GetItemSetID()` != 0 → `"setItems"` (egal welcher equipLoc) |
| `testGetItemCategory_CurioToken` | Name enthält `"curio"`, equipLoc leer, Epic+ → `"setItems"` |

`HasClassRestriction` (Tooltip-Scan für Klassen-Token) wird nicht direkt getestet — der Code-Pfad ist über `equipLoc != ""` umgangen, was die Mehrheit der Items abdeckt.

### DiffIDToString (T2.5)

| Test | Was geprüft |
|------|-------------|
| `testDiffIDToString_Normal` | IDs 14, 1, 17 → `"N"` |
| `testDiffIDToString_Heroic` | IDs 15, 2 → `"H"` |
| `testDiffIDToString_Mythic` | IDs 16, 8 → `"M"` |
| `testDiffIDToString_Unknown_ReturnsNil` | Unbekannte ID, String, nil → `nil` |

### DetectDifficulty (T2.5)

| Test | Was geprüft |
|------|-------------|
| `testDetectDifficulty_InRaid` | `instanceType="raid"`, diff=14 → `"N"` |
| `testDetectDifficulty_InParty` | `instanceType="party"`, diff=16 → `"M"` |
| `testDetectDifficulty_NotInInstance_ReturnsNil` | `instanceType="none"` → `nil` |

### NormalizeName (T2.5)

| Test | Was geprüft |
|------|-------------|
| `testNormalizeName_AppendsRealmWhenMissing` | `"Alice"` → `"Alice-Malfurion"` (Realm angehängt) |
| `testNormalizeName_PreservesExistingRealm` | `"Alice-Antonidas"` (cross-realm) → unverändert |
| `testNormalizeName_NilSafe` | `nil` → `nil` |

---

## Tests erweitern

```lua
function Tests:testMeinFall()
    WithTestDB({
        activeContainerIdx = 1,
        raidContainers     = { { ... } },
        settings           = { ... },
    }, function()
        AreEqual(expected, GL.Foo())
    end)
end
```

Für Funktionen die noch nicht existieren: per Funktions-Existenz gaten, damit der Test in CI als pending angezeigt wird, statt rot zu sein:

```lua
function Tests:testNeueFunktion()
    if not GL.NeueFunktion then
        Pending("Funktion noch nicht implementiert")
        return
    end
    -- ... eigentlicher Test
end
```
