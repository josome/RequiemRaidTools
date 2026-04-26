# Player Mode — Dokumentation

## Übersicht

RequiemRaidTools kennt drei UI-Ebenen, abhängig von der Rolle des Spielers im Raid:

| Rolle | Bedingung | UI |
|---|---|---|
| **Master Looter (ML)** | `isMasterLooter = true` | Volles Hauptfenster, alle Funktionen aktiv |
| **Observer** | Raid-Assist oder Raid-Lead, aber kein ML | Volles Hauptfenster, Buttons read-only; Loot-Popup |
| **Player** | Im Raid, aber kein Assist/Lead/ML | Nur Loot-Popup + Filter-Konfiguration |

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

### Prio-Buttons

- Die 5 Buttons zeigen die Kurznamen und die Prio Nummer der aktuellen Raid-Session-Konfiguration (z.B. "BIS", "OS", "Tmog").
- **Inaktive Prios** (vom ML nicht aktiviert) sind ausgegraut und nicht klickbar.
- Ein Klick postet die Priorität automatisch in den Raid-Chat — exakt wie wenn der Spieler manuell `/ra 1`, `/ra 2` etc. schreibt.
- Der zuletzt geklickte Button bleibt visuell markiert.

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
| Stoff | Items mit Rüstungstyp Cloth |
| Leder | Items mit Rüstungstyp Leather |
| Kette | Items mit Rüstungstyp Mail |
| Platte | Items mit Rüstungstyp Plate |
| non usable Weapons | filtert alle Waffen raus die der Spieler nicht verwenden kann |
| Trinkets | Schmuckstücke |
| Rings | Ringe |
| Necks | Halsketten |
| Other | Alles andere (inkl. nicht-zuordenbare Items) |

**Token-Erkennung:** Ob ein Token für die eigene Klasse relevant ist, prüft das Addon via `IsUsableItem()` — dieselbe API die WoW intern nutzt um Items grau darzustellen. Omni-Token (für alle Klassen nutzbar) erscheinen entsprechend bei allen.

> Sind Item-Daten noch nicht gecacht wenn ein Item announced wird, erscheint das Popup trotzdem (false positive lieber als verpasstes Item).

### Wo den Filter einstellen?

**Player** (kein Assist/Lead im Raid):
- Die Filter-Checkboxen sind dauerhaft am unteren Rand des Loot-Popups sichtbar und dort direkt bearbeitbar.
- Über `/reqrt` oder den Minimap-Button öffnet sich das Popup in einer Filter-only-Ansicht (ohne aktives Item) zur Vorkonfiguration.

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

`IsPlayerMode()` gibt nur `true` zurück wenn `IsInRaid()` — außerhalb eines Raids greift Player Mode nicht.

### Comm-Nachrichten die den Popup steuern

Alle benötigten Nachrichten existieren bereits im Protokoll (kein Protokoll-Bump):

| Nachricht | Wirkung |
|---|---|
| `SESSION_START` | Liefert `prioCfg` → Prio-Button-Beschriftungen |
| `ITEM_ON` | Popup erscheint (wenn Filter passt) |
| `ITEM_OFF` | Popup verschwindet |
| `ROLL_START` | Roll-Button wird aktiv (wenn Spieler in Liste) |
| `ASSIGN` | Gewinner-Anzeige (wenn lokaler Spieler) oder stilles Schließen |

### Filter-Speicherung

```lua
GuildLootDB.settings.announceFilter = {
    cloth   = true,  -- Default: alles aktiviert
    leather = true,
    mail    = true,
    plate   = true,
    jewelry = true,
    weapon  = true,
    other   = true,
}
```

Privat pro Spieler, wird nicht per Comm übertragen.
