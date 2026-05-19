# Roll Testdokumentation

**Datei:** `src/tests/Roll_Test.lua`
**Framework:** [WoWUnit](https://www.curseforge.com/wow/addons/wowunit) in-game und busted standalone (`spec/reqrt_spec.lua`)
**Suite-Name im WoWUnit-Fenster:** `ReqRT.Roll`

---

## Inhaltsverzeichnis

- [Voraussetzungen](#voraussetzungen)
- [Testziel](#testziel)
- [Teststrategie](#teststrategie)
- [Testfälle](#testfälle)
  - [StartRoll](#startroll)
  - [OnSystemMessage](#onsystemmessage)
  - [FinalizeRoll](#finalizeroll)
  - [CancelRoll](#cancelroll)
  - [OnCommRollStart](#oncommrollstart)
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

Tests für `src/loot/Loot_Roll.lua`. Deckt die kritische **Tie-Logik in `FinalizeRoll`**, die Roll-Setup-Pfade in `StartRoll` und die Dice-Pattern-Erkennung in `OnSystemMessage` (DE + EN) ab. Wegen Teil-Asynchronität (`C_Timer.NewTicker`) wird der Timer-Callback in den Tests nicht gefeuert — Tests prüfen den Setup-State direkt nach dem Funktionsaufruf.

---

## Teststrategie

- `WithTestDB(fn)` ersetzt `GuildLootDB` durch einen handgebauten Test-State mit aktiver Session und Standard-Prio-Config (1 BIS, 2 MS, 4 TR aktiv).
- `MockBasics()` mocked: `IsMasterLooter`, `Print`, `PostToRaid`, `Comm.SendRollStart`, `C_Timer.NewTicker` (stub mit Cancel), `C_Timer.After` (sync), `UnitName`.
- `SetupCurrentItem(count, candidates)` befüllt `Loot.GetCurrentItem()` mit Pflichtfeldern und liefert die Tabelle zurück.
- Für `FinalizeRoll`-Tests werden `rollState.players` und `rollState.results` direkt gesetzt, um deterministische Eingaben zu haben.

---

## Testfälle

### StartRoll

| Test | Was wird geprüft |
|------|------------------|
| `testStartRoll_SingleEligible_NoRollNeeded` | Genau 1 Kandidat → kein Roll, direkter Winner |
| `testStartRoll_MultipleEligible_TriggersRoll` | 3 Kandidaten, 1 Kopie → `rollState.active = true`, `players` befüllt, `timeLeft = 15` |
| `testStartRoll_NoCandidates_Aborts` | Keine Kandidaten → `Print("No prio…")`, kein Roll |
| `testStartRoll_CrossTier_FillsByPrioOrder` | 2 Kopien, 3 Kandidaten (Prio 1, 2, 4) → Tier 1 + Tier 2 ohne Roll, Prio 4 ignoriert |

### OnSystemMessage

| Test | Was wird geprüft |
|------|------------------|
| `testOnSystemMessage_EnglishPattern` | `"Alice rolls 73 (1-100)"` → `results.Alice = 73` |
| `testOnSystemMessage_GermanPattern` | `"Alice würfelt. Sie erhält eine 50 (1-100)."` → `results.Alice = 50` |
| `testOnSystemMessage_OnlyFirstRollCounts` | Zweiter Roll vom selben Spieler wird ignoriert |
| `testOnSystemMessage_NonParticipant_Ignored` | Spieler nicht in `rollState.players` → kein Eintrag |
| `testOnSystemMessage_RollNotActive_Ignored` | `rollState.active = false` → kein Eintrag |

### FinalizeRoll

| Test | Was wird geprüft |
|------|------------------|
| `testFinalizeRoll_ClearWinner_NoTie` | 3 Rolls eindeutig → höchster gewinnt, kein Tie-Re-Roll |
| `testFinalizeRoll_TieAtBoundary_TriggersReRoll` | 2× Roll 80 (Tie), 1 Kopie → `_tieReRoll` gesetzt, Re-Roll-`players` enthält nur Boundary-Gruppe |
| `testFinalizeRoll_TieBetweenPrios_HigherPrioWins` | Prio 2 mit höherem Roll verliert gegen Prio 1 mit niedrigem Roll |
| `testFinalizeRoll_FewerRollsThanSpots_AllWin` | 1 Roll bei 2 Kopien → der eine gewinnt direkt, kein Re-Roll |

### CancelRoll

| Test | Was wird geprüft |
|------|------------------|
| `testCancelRoll` | Timer wird gecancelt, `rollState.active = false` |

### OnCommRollStart

| Test | Was wird geprüft |
|------|------------------|
| `testOnCommRollStart_ObserverPath` | Observer setzt `rollState.players` aus Comm-Payload, Timer-Setup, `prioState.active = false` |
| `testOnCommRollStart_MasterLooter_Ignored` | ML ignoriert die eigene Comm-Nachricht |

---

## Was diese Tests nicht abdecken

| Bereich | Warum nicht abgedeckt |
|---------|-----------------------|
| Timer-Ablauf (Countdown 15s → 0s) | `C_Timer.NewTicker`-Callback wird im Test nicht gefeuert — der eigentliche Setup-State ist deterministisch testbar, der Timer-Lauf wäre zeitabhängig |
| UI-Updates (`RefreshLootTab`, `RefreshCountdown`) | Schlucken die Aufrufe, kein Frame da |
| Comm-Roundtrip von `SendRollStart` | → `ReqRT.Comm`-Suite |
| Mehrfach-Re-Roll-Kaskaden (Tie nach Tie) | Setup zu komplex für isolierten Test; manuell verifizieren |
| Chat-Parsing-Pfad (Bedarfsmeldung) | `Loot.OnChatMessage` → `ReqRT.Assign`-Suite |

---

## Tests erweitern

```lua
function Tests:testMeinFall()
    WithTestDB(function()
        MockBasics()
        local ci = SetupCurrentItem(1, {
            ["Alice-Realm"] = { prio = 1 },
        })
        ci.rollState.active  = true
        ci.rollState.players = { Alice = true }
        ci.rollState.results = { Alice = 50 }

        Loot.FinalizeRoll()

        AreEqual("Alice", ci.winner)
        MockRestore()
    end)
end
```
