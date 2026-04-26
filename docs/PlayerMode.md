# Player Mode — Dokumentation

## Übersicht

RequiemRaidTools kennt drei UI-Ebenen, abhängig von der Rolle des Spielers im Raid:

| Rolle | Bedingung | UI | Minimap-Button |
|---|---|---|---|
| **Master Looter (ML)** | `isMasterLooter = true` | Volles Hauptfenster, alle Funktionen aktiv | Hauptfenster toggle |
| **Observer** | Raid-Assist oder Raid-Lead, aber kein ML | Volles Hauptfenster, Buttons read-only; Loot-Popup | Hauptfenster toggle |
| **Player** | Im Raid, aber kein Assist/Lead/ML | Nur Loot-Popup + Filter-Konfiguration | **ausschließlich Popup toggle** |

> **Außerhalb eines Raids** (solo, Dungeon, kein Raid): Player Mode ist inaktiv → volles Hauptfenster für alle. Der ML-Toggle (`/reqrt ml`) bleibt immer zugänglich.

---

## Player Mode

### Was ist Player Mode?

Player Mode ist die UI-Ebene für normale Raider ohne Raid-Assist oder Raid-Lead. Das große ML-/Observer-Fenster (Loot-Tab, Spieler-Tab, Log, Raid-Verwaltung) ist für diese Spieler nicht relevant — sie brauchen nur zu wissen wann ein Item announced wird und welche Prio sie drücken sollen.

### Was sieht ein Player?

Wenn der Master Looter ein Item freigegeben hat (announced), erscheint automatisch ein **Loot-Popup**:

```
┌───────────────────────────────────────────┐
│  [Icon] Itemname (farbig)                 │
├───────────────────────────────────────────┤
│  [1 BIS]  [2 OS]  [---]  [---]  [5 Tmog]  │
│   ← Prio-Buttons (inaktive grau) →        │
├───────────────────────────────────────────┤
│  [Roll]  (aktiv wenn Roll-Phase)          │
├───────────────────────────────────────────┤
│  Announce-Filter:                         │
│  ☑ Cloth   ☑ non usable Weapons  ☑ Other│
│  ☑ Leather ☑ Trinkets                    │
│  ☑ Mail    ☑ Rings                       │
│  ☑ Plate   ☑ Necks                       |
└───────────────────────────────────────────┘
```

### Minimap-Button

Für Player gilt: der Minimap-Button öffnet und schließt **ausschließlich das Popup** — das Hauptfenster wird nie geöffnet. Das ist die einzige Rolle bei der der MMB-Klick nicht das Hauptfenster toggelt.

- **1. Klick**: Popup öffnet sich in Filter-Only-Ansicht (kein aktives Item)
- **2. Klick**: Popup schließt sich
- **✕-Button** im Popup: schließt das Popup, nächster MMB-Klick öffnet es wieder

> `/reqrt popup` öffnet das Popup immer in Filter-Only-Ansicht, unabhängig von der Rolle.

### Prio-Buttons

- Die 5 Buttons zeigen die Kurznamen und die Prio-Nummer der aktuellen Raid-Session-Konfiguration (z.B. "BIS", "OS", "Tmog").
- **Inaktive Prios** (vom ML nicht aktiviert) sind ausgegraut und nicht klickbar.
- Ein Klick postet die Priorität automatisch in den Raid-Chat — exakt wie wenn der Spieler manuell `/ra 1`, `/ra 2` etc. schreibt.
- Der zuletzt geklickte Button bleibt visuell markiert.
- Prio-Namen werden bei Änderung durch den ML per **Apply**-Button übertragen (`SESSION_START` mit neuer prioCfg).

### Roll-Button

- Erscheint, wird aber erst aktiv wenn der ML die Roll-Phase startet (`ROLL_START`).
- Aktiv wird er **nur wenn der eigene Charakter in der Roll-Liste steht** (ML entscheidet wer rollen darf).
- Ein Klick führt `/roll` aus (`RandomRoll(1, 100)`) — genau wie in WoW-Chat.
- Nach dem ersten Klick deaktiviert sich der Button (zweimal rollen nicht möglich).

### Gewinner-Anzeige

Wenn das Item zugewiesen wird (`ASSIGN`) und der lokale Spieler der Gewinner ist, zeigt das Popup:

> **Du bekommst:** [Itemname]

Das Popup schließt sich nach 6 Sekunden automatisch oder per Klick auf ✕.

Ist jemand anderes der Gewinner, schließt sich das Popup still.

---

## Announce-Filter

Der **Announce-Filter** steuert, für welche Item-Typen das Loot-Popup überhaupt erscheint. Default ist alles aktiviert.

| Filter | Bedeutung |
|---|---|
| Cloth | Items mit Rüstungstyp Cloth |
| Leather | Items mit Rüstungstyp Leather |
| Mail | Items mit Rüstungstyp Mail |
| Plate | Items mit Rüstungstyp Plate |
| non usable Weapons | Waffen die der Spieler nicht ausrüsten kann |
| Trinkets | Schmuckstücke (Trinket-Slot) |
| Rings | Ringe (Finger-Slot) |
| Necks | Halsketten (Neck-Slot) |
| Other | Alles andere (nicht-zuordenbare Items, Tokens etc.) |

> **Usable Weapons**: Waffen die der Spieler ausrüsten kann, erscheinen immer — unabhängig vom non-usable-Weapons-Filter.

### Caching-Verhalten

Der Rüstungstyp eines Items wird über `GetItemInfo` ermittelt. Bei Legacy-Items (z.B. Shadowlands-Content in Midnight) sind die Daten auf dem Client eines anderen Spielers möglicherweise noch nicht gecacht wenn das Item announced wird.

In diesem Fall wird das Popup **kurz zurückgehalten** (unter 1 Sekunde), bis `GET_ITEM_INFO_RECEIVED` feuert und die Typ-Erkennung zuverlässig arbeiten kann. Beim zweiten Announce desselben Items (bereits gecacht) erscheint das Popup sofort.

### Popup aktivieren/deaktivieren

Die **☑ Enable-Checkbox** oben rechts im Popup steuert ob das Popup bei einem `ITEM_ON` automatisch erscheint:

- **nil (nicht gesetzt)**: Auto-Modus — im Raid an, außerhalb aus (wird nicht in der DB gespeichert)
- **Haken gesetzt**: Popup erscheint immer bei ITEM_ON
- **Haken weg**: Popup erscheint nie automatisch (manuell via MMB oder `/reqrt popup` weiterhin möglich)

### Wo den Filter einstellen?

**Player** (kein Assist/Lead im Raid):
- Die Filter-Checkboxen sind dauerhaft am unteren Rand des Loot-Popups sichtbar und dort direkt bearbeitbar.
- Über den Minimap-Button oder `/reqrt popup` öffnet sich das Popup in einer Filter-Only-Ansicht zur Vorkonfiguration.

**Observer** (Raid-Assist/Lead ohne ML):
- Der Announce-Filter-Abschnitt ist im Settings-Panel (Zahnrad-Icon) sichtbar und bearbeitbar.

**ML:**
- Kein Announce-Filter (der ML sieht alle announced Items selbst).

---

## Abgrenzung: Loot-Drop-Filter vs. Announce-Filter

| | Loot-Drop-Filter | Announce-Filter |
|---|---|---|
| **Wer** | ML | Observer / Player (privat) |
| **Wann** | Beim Öffnen einer Leiche | Beim Empfang eines ITEM_ON |
| **Was** | Welche Items in die ML-Pending-Liste kommen | Welche announced Items den Popup triggern |
| **Wo** | Settings-Panel (ML) | Popup (Player) / Settings-Panel (Observer) |

---

## Technische Details

### Rollenerkennung

```lua
GL.IsMasterLooter()  -- true wenn ML-Flag gesetzt oder Solo-Instanz
GL.IsObserver()      -- true wenn Raid-Assist/Lead, aber kein ML
GL.IsPlayerMode()    -- true wenn im Raid, aber weder ML noch Assist/Lead
```

`IsPlayerMode()` gibt nur `true` zurück wenn `IsInRaid()` — außerhalb eines Raids (solo, Dungeon, Party) greift Player Mode nicht.

### ML-Erkennung auf Non-ML-Clients

`isMasterLooter` wird in den SavedVariables gespeichert. Um zu verhindern dass ein alter Testwert (`true`) hängen bleibt:

- `OnCommSessionStart` setzt `isMasterLooter = false` wenn der Sender nicht der lokale Spieler ist
- `StartRaid` und `ResumeContainer` senden nach dem Setzen von `isMasterLooter = true` ein `ML_ANNOUNCE` an alle Raid-Mitglieder

### Comm-Nachrichten die den Popup steuern

Alle benötigten Nachrichten existieren im Protokoll (kein Protokoll-Bump nötig):

| Nachricht | Wirkung |
|---|---|
| `SESSION_START` | Liefert `prioCfg` → Prio-Button-Beschriftungen, setzt isMasterLooter=false |
| `ML_ANNOUNCE` | Setzt isMasterLooter korrekt auf allen Clients |
| `ITEM_ON` | Popup erscheint (wenn Filter passt und popupEnabled) |
| `ITEM_OFF` | Popup verschwindet |
| `ROLL_START` | Roll-Button wird aktiv (wenn Spieler in Liste) |
| `ASSIGN` | Gewinner-Anzeige (wenn lokaler Spieler) oder stilles Schließen |

### Filter-Speicherung

```lua
GuildLootDB.settings.announceFilter = {
    cloth           = true,  -- Default: alles aktiviert
    leather         = true,
    mail            = true,
    plate           = true,
    nonUsableWeapon = true,
    trinket         = true,
    ring            = true,
    neck            = true,
    other           = true,
}
```

Privat pro Spieler, wird **nicht** per Comm übertragen.

### Test-Commands

| Command | Funktion |
|---|---|
| `/reqrt playermode` | `forcePlayerMode`-Flag toggeln — ML kann Popup solo testen |
| `/reqrt simitem` | Erstes equippables Bag-Item als ITEM_ON simulieren (respektiert Filter) |
| `/reqrt popup` | Öffnet Popup in Filter-Only-Ansicht (immer, unabhängig von Rolle) |
