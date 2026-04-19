# Assign Testdokumentation

**Datei:** `src/tests/Assign_Test.lua`  
**Framework:** [WoWUnit](https://www.curseforge.com/wow/addons/wowunit) (läuft in-game, kein externer Lua-Runner)  
**Suite-Name im WoWUnit-Fenster:** `ReqRT.Assign`

---

## Voraussetzungen

| Bedingung | Warum |
|-----------|-------|
| WoWUnit installiert | Test-Framework; ohne es gibt `if not WoWUnit then return end` die Datei sofort frei |
| `/reqrt devmode` aktiv | Schützt Produktiv-Nutzer die WoWUnit installiert haben; Tests registrieren sich gar nicht wenn devMode aus ist |
| `/reload` nach devMode-Toggle | Damit der Addon-State sauber initialisiert ist und `GuildLootDB` korrekt geladen wurde |

---

## Testziel

Integrationstest des Assign-Flows — von Chat-Prio-Eingabe über Zuweisung bis zum Eintrag in lootLog und players-DB:

```
OnChatMessage("1 BIS")  →  candidates befüllt  →  AssignLootConfirm  →  lootLog + players
```

Nicht getestet: Timer-basierter Ablauf (Prio-Phase, Roll) — der benötigt den WoW-Eventloop.
Externe Seiteneffekte (Netzwerk, UI, Chat) werden gestubbt, die Kernlogik läuft gegen echten DB-State.

---

## Teststrategie: DB-Swap + direkter Funktionsaufruf

GuildLootDB wird für die Dauer jedes Tests durch einen sauberen Test-State ersetzt (`WithTestDB`).
`currentItem` wird direkt befüllt — kein `ActivateItem`, kein Timer, kein `GetItemInfo`.
Der Spieler kommt über den echten Chat-Parser (`OnChatMessage`) in `candidates`.

```
1. Arrange — WithTestDB: saubere Session + currentItem befüllen
2. Act     — OnChatMessage → candidates; AssignLootConfirm aufrufen
3. Assert  — lootLog / pendingLoot / players prüfen
4. Cleanup — WithTestDB schreibt GuildLootDB automatisch zurück; MockRestore()
```

---

## Testfälle

### `testWritesLootLog`

**Testet:** Vollständiger Assign-Flow — Chat-Parsing → Zuweisung → lootLog-Eintrag

**Schritte:**
1. Session und currentItem (Item + Metadaten) aufbauen
2. `OnChatMessage("1 BIS", "Myriella-Malfurion")` → `candidates` wird durch echten Parser befüllt
3. `AssignLootConfirm("Myriella-Malfurion", "H")` aufrufen
4. Prüfen: `lootLog[1].player`, `.link`, `.difficulty`, `.category`, `.winnerPrio`, `.boss`

---

### `testRemovesFromPending`

**Testet:** Item wird nach Assign aus pendingLoot entfernt

**Schritte:**
1. Item manuell in `session.pendingLoot` eintragen
2. `AssignLootConfirm` aufrufen
3. Prüfen: `#Loot.GetPendingLoot() == 0`

---

### `testWritesPlayerRecord`

**Testet:** `players`-DB wird korrekt befüllt (counts, lootHistory)

**Schritte:**
1. `AssignLootConfirm` aufrufen
2. Prüfen: `players["Myriella-Malfurion"].counts.trinket == 1`
3. Prüfen: `lootHistory[1].item`, `.category`, `.difficulty`

---

### `testCommAssignObserver`

**Testet:** Observer-Pfad — `OnCommAssign` schreibt direkt in aktive Session

**Schritte:**
1. `IsMasterLooter` → false (Observer-Kontext)
2. `OnCommAssign(...)` direkt aufrufen
3. Prüfen: `lootLog[1]` in der aktiven Session vorhanden

---

## Was diese Tests nicht abdecken

| Bereich | Warum nicht abgedeckt |
|---------|-----------------------|
| Timer-basierter Prio/Roll-Ablauf | Benötigt WoW-Eventloop (`C_Timer.NewTicker`) |
| Comm-Übertragung des ASSIGN | → Zuständigkeit der `ReqRT.Comm`-Suite |
| UI-Rendering des Log-Tabs | UI-Layer ist nicht Gegenstand der Assign-Tests |

---

## Tests erweitern

```lua
function Tests:testMeinFall()
    WithTestDB(function(session)
        SetupCurrentItem()
        MockSideEffects()

        Loot.OnChatMessage("1 BIS", "Myriella-Malfurion")
        Loot.AssignLootConfirm("Myriella-Malfurion", "H")

        AreEqual(1, #session.lootLog)
        AreEqual("Myriella-Malfurion", session.lootLog[1].player)

        MockRestore()
    end)
end
```
