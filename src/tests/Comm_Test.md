# Comm-Layer Testdokumentation

**Datei:** `src/tests/Comm_Test.lua`  
**Framework:** [WoWUnit](https://www.curseforge.com/wow/addons/wowunit) (läuft in-game, kein externer Lua-Runner)  
**Suite-Name im WoWUnit-Fenster:** `ReqRT.Comm`

---

## Voraussetzungen

| Bedingung | Warum |
|-----------|-------|
| WoWUnit installiert | Test-Framework; ohne es gibt `if not WoWUnit then return end` die Datei sofort frei |
| `/reqrt devmode` aktiv | Schützt Produktiv-Nutzer die WoWUnit installiert haben; Tests überspringen sich selbst wenn devMode aus ist |
| `/reload` nach devMode-Toggle | Damit der Addon-State sauber initialisiert ist |

---

## Teststrategie: Roundtrip

Die Comm-Schicht kann nicht über den echten Addon-Bus getestet werden (kein zweiter Client, kein Netzwerk). Stattdessen wird **synchron roundgetript**:

```
SendXxx()  →  [C_ChatInfo.SendAddonMessage stubbt]  →  msg (string)
                                                           ↓
                                                    Comm.OnMessage(msg, sender)
                                                           ↓
                                              [Handler-Spy prüft Argumente]
```

1. `C_ChatInfo.SendAddonMessage` wird durch einen Spy ersetzt der den Message-String abfängt.
2. Die Send-Funktion wird aufgerufen — der Spy speichert den serialisierten String.
3. Dieser String wird direkt an `Comm.OnMessage` übergeben — genau so wie er auf dem Bus ankäme.
4. Ein zweiter Spy auf dem Ziel-Handler (`OnCommAssign`, `OnCommItemActivate`, …) prüft ob die Argumente korrekt deserialisiert wurden.

**Was das garantiert:** Wird das Sendeformat geändert (Felder umsortiert, Parameter hinzugefügt), läuft der Empfänger im selben Test mit dem neuen String — der Drift wird sofort als Fehler sichtbar.

---

## Mocking-Infrastruktur

### `Mock(tbl, key, fn)` / `MockRestore()`

Minimales eigenes Mock-System (WoWUnit's `Replace`-API passt nicht zum Lebenszyklus dieser Tests).

```lua
Mock(GuildLoot.Loot, "OnCommAssign", function(...) args = {...} end)
-- ... Test ...
MockRestore()  -- stellt alle gemockten Funktionen in umgekehrter Reihenfolge wieder her
```

### `Roundtrip(sendFn) → string`

Setzt intern drei Mocks (SendAddonMessage, IsInRaid, IsInGroup), ruft `sendFn()` auf und entfernt danach **nur die eigenen drei Mocks** (über einen Stack-Savepoint). Test-Spies die vor dem Roundtrip-Aufruf gesetzt wurden bleiben aktiv — das ist wichtig damit der Handler-Spy nach `Comm.OnMessage()` noch greift.

---

## Testfälle

### `testRedTestforVerification`

**Testet:** Prüft die Testquite ob assertion red liefern können

dieser Testfall muss rot sein, und wird irgendwann entfernt

---

### `testAssignRoundtrip`

**Testet:** `Comm.SendAssign` → Serialisierung → `Comm.OnMessage` → `Loot.OnCommAssign`

**Prüft konkret:**
- Alle 9 Parameter kommen vollständig und in der richtigen Reihenfolge an
- `quality` (number) und `winnerPrio` (number) werden korrekt als Zahlen deserialisiert — nicht als Strings (da das Protokoll Tab-separierte Strings überträgt, ist `tonumber()` auf Receiver-Seite erforderlich)

**Warum wichtig:** ASSIGN ist die kritischste Nachricht im System — sie schreibt Loot-Zuweisung in die persistente DB aller Observer.

---

### `testItemOnRoundtrip`

**Testet:** `Comm.SendItemActivate` → `Comm.OnMessage` → `Loot.OnCommItemActivate`

**Prüft konkret:**
- Item-Link und Kategorie kommen unverändert an (Item-Links enthalten Sonderzeichen wie `|H`, `|h`, `|r`)

**Warum wichtig:** Item-Links mit WoW-Farbcodes und Pipe-Zeichen müssen den Transport unbeschädigt überstehen.

---

### `testSessionStartRoundtrip`

**Testet:** `Comm.SendSessionStart` → Serialisierung inkl. PrioCfg → `Comm.OnMessage` → `GL.OnCommSessionStart`

**Prüft konkret:**
- SessionID, Label, Timestamp kommen korrekt an
- Sender-Name wird als 4. Argument durchgereicht (Observer braucht ihn um den ML zu identifizieren)
- `SerializePrioCfg` + `DeserializePrioCfg` werden implizit getestet: `active`, `shortName` der ersten beiden Prios korrekt, `active=false` bei Prio 3

**Warum wichtig:** PrioCfg-Serialisierung ist ein eigenes Format (Semikolon/Doppelpunkt-separiert) — Roundtrip-Test erkennt stille Bugs in beiden Richtungen.

---

### `testMLGuardBlocks`

**Testet:** Als Master Looter (ML) wird eine eingehende `ITEM_ON`-Nachricht ignoriert

**Setup:** `isMasterLooter = true`, dann `Comm.OnMessage` mit einer ITEM_ON-Nachricht von einem fremden Sender

**Prüft:** Item-Link bleibt nil — der Handler hat die Nachricht nicht verarbeitet

**Warum wichtig:** Der ML hat das Item bereits lokal aktiviert. Würde er die eigene Broadcast-Nachricht nochmals verarbeiten, käme es zu doppelten UI-Aktionen.

---

### `testSelfFilterBlocks`

**Testet:** Eigene Nachrichten werden ignoriert wenn `commLoopback = false` (Produktiv-Default)

**Setup:** Sender = `UnitName("player")`, `commLoopback = false`

**Prüft:** `OnCommItemActivate` wird **nicht** aufgerufen

**Warum wichtig:** Der ML verarbeitet Loot lokal — würde er seine eigene Broadcast-Nachricht nochmals empfangen, entstünden Duplikate im Loot-Log.

---

### `testSelfFilterLoopback`

**Testet:** Eigene Nachrichten werden verarbeitet wenn `commLoopback = true`

**Setup:** Sender = `UnitName("player")`, `commLoopback = true`

**Prüft:** `OnCommItemActivate` wird aufgerufen

**Warum wichtig:** `commLoopback` ist ein Dev-Flag das den Self-Filter deaktiviert — wird für Comm-Tests in der Entwicklung gebraucht (Solo-Test ohne zweiten Client). Dieser Test stellt sicher dass das Flag funktioniert.

---

## Was diese Tests nicht abdecken

| Bereich | Warum nicht abgedeckt |
|---------|-----------------------|
| Echte Netzwerkübertragung | Kein zweiter WoW-Client im Testlauf; kein Addon-Bus im Unit-Test |
| Nachrichtenlänge (WoW-Limit: 255 Zeichen) | Kein Längencheck in der Testsuite; sehr lange Item-Links oder PrioCfg könnten truncated werden |
| Protokoll-Versionskompatibilität (Minor-Mismatch) | Kein Test der eine ältere Protokollversion simuliert |
| UI-Reaktionen | UI-Layer ist nicht Gegenstand der Comm-Tests |
| `ROLL_START`, `RAID_QUERY`, `RAID_META`, `SESSION_END`, `ML_ANNOUNCE`, `ML_REQUEST`, `ML_DENY` | Noch nicht durch Roundtrip-Tests abgedeckt |

---

## Tests erweitern

Muster für einen neuen Roundtrip-Test:

```lua
function Tests:testMeinNeuesFeature()
    -- 1. Spy auf den Ziel-Handler
    local args = nil
    Mock(GuildLoot.Loot, "OnCommMeinHandler", function(...) args = {...} end)

    -- 2. Nachricht serialisieren und abfangen
    local msg = Roundtrip(function()
        Comm.SendMeinFeature("param1", 42)
    end)

    -- 3. Nachricht existiert?
    Exists(msg)

    -- 4. Durch OnMessage jagen
    Comm.OnMessage(msg, "TestSender-Realm")

    -- 5. Argumente prüfen
    Exists(args)
    AreEqual("param1", args[1])
    AreEqual(42,       args[2])  -- Zahlen bleiben Zahlen?

    MockRestore()
end
```
