# Export Testdokumentation

**Datei:** `src/tests/Export_Test.lua`
**Framework:** busted (`spec/reqrt_spec.lua`)
**Suite-Name:** `ReqRT.Export`

---

## Inhaltsverzeichnis

- [Voraussetzungen](#voraussetzungen)
- [Testziel](#testziel)
- [Teststrategie](#teststrategie)
- [Testfälle](#testfälle)
  - [ExportCSV](#exportcsv)
  - [ExportJSON](#exportjson)
- [Was diese Tests nicht abdecken](#was-diese-tests-nicht-abdecken)
- [Tests erweitern](#tests-erweitern)

---

## Voraussetzungen

| Bedingung | Warum |
|-----------|-------|

---

## Testziel

Schema-Stabilität für die User-Export-Funktionen `GL.ExportJSON` und `GL.ExportCSV` (`src/Util.lua`). Beide werden über Slash-Commands aufgerufen und liefern Daten die der User in externe Tools (Tabellen, Discord-Bots) weitergibt. Eine Format-Regression hier ist nicht datenkritisch — aber blamabel beim User.

---

## Teststrategie

Direkt-Aufruf mit explizit konstruierten Raid-Tabellen. Keine Mocks für die Export-Funktionen selbst nötig — sie sind pure-Lua. `WithTestDB` wird nur genutzt, wenn der Active-Session-Fallback geprüft wird (`ExportCSV()` / `ExportJSON()` ohne Argument).

---

## Testfälle

### ExportCSV

| Test | Was wird geprüft |
|------|------------------|
| `testExportCSV_Header` | Header-Zeile exakt: `RaidID,Tier,Difficulty,Track,Date,Status,Player,Item,Category,Prio,Timestamp` |
| `testExportCSV_AssignedItemRow` | LootLog-Eintrag wird zur "Assigned"-Zeile; ShortName statt FullName; CAT_LABEL-Mapping (`trinket` → `Trinket`); DiffToTrack (`M` → `Mythic`) |
| `testExportCSV_TrashedItemRow` | TrashedLoot-Eintrag wird zur "Trashed"-Zeile |
| `testExportCSV_EscapesCommasInFields` | Felder mit Komma werden in Quotes gewrappt |
| `testExportCSV_EmptyRaid_OnlyHeader` | Raid ohne Loot → nur Header-Zeile |
| `testExportCSV_UsesActiveSessionByDefault` | `ExportCSV()` ohne Argument → nimmt active Session (nicht `currentRaid`) |

### ExportJSON

| Test | Was wird geprüft |
|------|------------------|
| `testExportJSON_ContainsTopLevelFields` | JSON enthält `"exportedAt"`, `"raid"`, `"players"`; active Session wird verwendet |
| `testExportJSON_AcceptsExplicitRaidData` | Mit explizitem `raidData` Argument → dieser Raid wird serialisiert, nicht der Fallback |
| `testExportJSON_FallsBackToCurrentRaid` | Keine active Session → Fallback auf `currentRaid` |
| `testExportJSON_EscapesQuotesInStrings` | String-Werte mit `"` werden mit `\"` escaped |

---

## Was diese Tests nicht abdecken

| Bereich | Warum nicht abgedeckt |
|---------|-----------------------|
| Vollständige Schema-Validierung (alle Felder durchgehen) | Würde Tests fragil machen; Stichproben-Strategie reicht für Regression |
| Performance bei großen Datensätzen (1000+ Items) | Pure-Lua, kein WoW-API-Risiko |
| UTF-8-Sonderzeichen in Spielernamen | Item-Links sind WoW-Format; UTF-8 wird durch Lua nativ unterstützt |
| Format-Round-Trip (JSON parsen → Original-Daten) | Tests prüfen Output-Stabilität, kein Re-Import-Pfad existiert |

---

## Tests erweitern

```lua
function Tests:testMeinFall()
    local raid = {
        id          = "raid-x",
        tier        = "T",
        difficulty  = "H",
        startedAt   = 0,
        lootLog     = { ... },
        trashedLoot = {},
    }
    local csv = GL.ExportCSV(raid)
    IsTrue(csv:find("Expected-Substring") ~= nil)
end
```
