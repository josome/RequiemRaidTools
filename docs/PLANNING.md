# RequiemRaidTools – Planungsdokument

## Übersicht
WoW Retail Addon (Interface 120001 / The War Within) für faire und strukturierte Raid-Loot-Verteilung.
Wird nur vom Master Looter bedient. Alle anderen Spieler interagieren nur per Chat.

---

## Zielversion
- **WoW Retail Interface 120001 (The War Within)**
- API ist stark eingeschränkt gegenüber älteren Versionen
- Kein automatisches Auslesen der Ausrüstung anderer Spieler möglich
- Spieler geben ihre Prio und Kategorie selbst im Chat an (Vertrauensbasis)

---

## Benutzergruppen
| Rolle | Rechte |
|---|---|
| Master Looter (ML) | Vollzugriff: Raid starten, Items freigeben, Gewinner bestätigen, Reset |
| Beobachter (Observer) | Addon sync – sieht alles, kann aber nicht klicken |
| Normale Raid-Mitglieder | Nur Chat-Eingabe (Prio + Kategorie) |

---

## Workflow

### 1. Raid-Start ✅
- ML startet Raid → Name wird automatisch aus Instanzname + Datum generiert
- Schwierigkeit wird automatisch aus `GetInstanceInfo()` erkannt (N/H/M)
- Teilnehmerliste wird aus der aktuellen Gruppe erstellt
- Liste zeigt alle Spieler mit ihrer bisherigen Loot-Historie

### 2. Item freigeben ✅
- ML gibt ein Item frei (aus dem Loot-Fenster oder manuell)
- Item-Typ wird erkannt: Waffe / Schmuck / Set-Item / Sonstiges
- Item wird im Addon-Fenster als "offen" angezeigt
- Bedarfs-Liste wird beim Freigeben eines neuen Items automatisch geleert

### 3. Spieler melden sich ✅
- Spieler schreiben in den Raid-Chat ihre Prio + Kategorie:
  - Format: `1 BIS` / `2 UP` / `3 OS` (Zahl = Prio, Kürzel = Kategorie)
  - **1** = höchste Priorität, **4** = niedrigste
  - **BIS** = Best in Slot, **UP** = Upgrade, **OS** = Offspec, **Fun** = Fun
- Addon parsed den Chat automatisch und trägt Spieler in die Liste ein
- Nur Spieler die beim Boss-Kill anwesend waren können rollen (Loot-Berechtigung)

### 4. Auswertung & Gewinner ✅
- Addon sortiert nach: Prio (1 vor 2 vor 3 vor 4) → dann Kategorie (BIS > UP > OS)
- Bei Gleichstand → automatischer `/roll` zwischen den betroffenen Spielern
- ML bestätigt den Gewinner mit einem Klick
- Gewinner wird in Raid-Chat gepostet: `[RLT] [Spieler] erhaelt [Item]`

### 5. Queue-Update ✅
- Bei Waffe, Schmuck oder Set-Item: Gewinner rutscht ans Ende der jeweiligen Queue
- Queue gilt über alle Schwierigkeitsgrade hinweg (Normal/Heroic/Mythic)

### 6. Raid beenden ✅
- ML beendet Raid manuell ("Raid beenden"-Button, doppelte Bestätigung geplant)
- Raid wird als Snapshot in `raidHistory` gespeichert
- Auto-Close: Raid wird automatisch beendet wenn >4h offline

---

## Loot-Kategorien & Queues

| Kategorie | Queue | Rotationssystem |
|---|---|---|
| Waffen | Queue 1 | ✅ Ja |
| Schmuck (Ringe, Ketten, Trinkets) | Queue 2 | ✅ Ja |
| Set-Items (Tier) | Queue 3 | ✅ Ja |
| Sonstiges | Queue 4 | ❌ Nein |

---

## Prio-System

### Eingabe-Format im Chat
```
1 BIS   → Prio 1, Best in Slot
2 UP    → Prio 2, Upgrade
3 OS    → Prio 3, Offspec
4 FUN   → Prio 4, Fun (niedrigste)
```

### Sortierung bei Auswertung
1. Prio-Zahl (1 gewinnt vor 2, 3, 4)
2. Kategorie (BIS > UP > OS > Fun)
3. Gleichstand → `/roll`

---

## Roster & Loot-Berechtigung ✅

- `participants` – alle Spieler die jemals im Raid waren (kumulativ, Spieler-Tab)
- `currentKillParticipants` – Snapshot beim Boss-Kill (nur diese dürfen rollen)
- `ENCOUNTER_END` (success=1) → Snapshot wird erstellt
- Post-Kill-Joiner sind automatisch nicht loot-berechtigt
- `absent`-Liste: Spieler können manuell als abwesend markiert werden

---

## Multi-User Sync ✅ (Comm.lua)

- `C_ChatInfo.SendAddonMessage` mit Prefix `"RLT"`
- 4 Message-Typen:
  - `ITEM_ON` – Item wurde freigegeben
  - `ITEM_OFF` – Item wurde zurückgesetzt
  - `ROLL_START` – Roll-Phase gestartet
  - `ASSIGN` – Gewinner wurde bestätigt
- Observer sehen alles, können aber nicht klicken
- Eigene Nachrichten werden ignoriert

---

## Chat-Nachrichten ✅

- Lokale Addon-Meldungen: `[GUILDLOOT] ...`
- Raid/Party-Chat-Meldungen: `[RLT] ...`

---

## UI-Tabs

### Tab 1: Loot ✅
- Aktives Item anzeigen
- Bedarfs-Liste (Prio-Eingaben der Spieler)
- Roll-Phase starten / Gewinner bestätigen
- Session-Loot-Liste unten: Checkboxen zum Abhaken, × zum Löschen, "Liste leeren"

### Tab 2: Spieler ✅
- Roster der aktuellen Raid-Teilnehmer
- Loot-Historie und Counts pro Spieler
- Als abwesend markieren

### Tab 3: Log ✅
- Alle Loot-Vergaben dieser Session
- Item-Links mit Tooltip beim Hover ✅
- JSON-Export Button

### Tab 4: Verlauf ✅
- Liste aller abgeschlossenen Raids (neueste zuerst)
- Klick auf Raid → Detail-Ansicht mit Loot-Log
- "Raid fortsetzen" – lädt Raid aus History zurück als aktiven Raid ✅
- "Löschen" – entfernt Raid aus History (doppelte Bestätigung: 2 Klicks in 3s) ✅

---

## Session-Leiste ✅
- Status: Raid aktiv / inaktiv
- Tier-Name (editierbar, auto-befüllt aus Instanzname)
- "Raid starten" / "Neu laden"
- "Raid beenden" (nur aktiv wenn Raid läuft)
- "Reset" (doppelte Bestätigung: 2 Klicks in 3s) ✅

---

## Sicherheit / Bestätigungen ✅

| Aktion | Bestätigung |
|---|---|
| Reset Raid | 2× klicken in 3 Sekunden |
| Raid aus Verlauf löschen | 2× klicken in 3 Sekunden |

---

## Fenster ✅

- Verschiebbar (Drag auf Titelleiste)
- **Skalierbar** (Resize-Grip unten rechts, min 480×340, max 1400×1000) ✅
- Position und Größe werden gespeichert und wiederhergestellt
- Andockbar als schmaler Tab am linken Bildschirmrand

---

## Minimap-Button ✅
- Kleiner Button an der Minimap (drehbar)
- Klick öffnet/schließt das Hauptfenster

---

## Datenspeicherung (SavedVariables – aktueller Stand)

```lua
GuildLootDB = {
    players = {
        ["Spielername"] = {
            lootHistory    = {},
            lastDifficulty = { weapons=nil, trinket=nil, setItems=nil },
            counts         = { weapons=0, trinket=0, setItems=0, other=0 },
            lootEligible   = true,
            setPieces      = 0,
            class          = nil,
        }
    },
    raidHistory = {           -- abgeschlossene Raids
        { tier, difficulty, participants, lootLog, closedAt }
    },
    lastLogout  = 0,
    currentRaid = {
        active                  = false,
        tier                    = "",
        difficulty              = "",
        participants            = {},     -- alle Raid-Teilnehmer
        absent                  = {},
        lootLog                 = {},
        pendingLoot             = {},
        sessionHidden           = {},     -- UI-Zustand Session-Liste
        sessionChecked          = {},     -- UI-Zustand Session-Liste
        currentKillParticipants = {},     -- Snapshot beim Boss-Kill
    },
    settings = {
        postToChat      = true,
        chatCommand     = "/gl",
        isMasterLooter  = false,
        minQuality      = 4,
        prioSeconds     = 15,
        rollSeconds     = 15,
        difficultyRanges = {
            N = { min=593, max=606 },
            H = { min=607, max=619 },
            M = { min=620, max=639 },
        },
        framePos     = nil,
        frameSize    = nil,       -- gespeicherte Fenstergröße ✅
        minimized    = true,
        minimapAngle = 45,
    },
}
```

---

## Dateistruktur

```
RequiemRaidTools/
├── RequiemRaidTools.toc   – Addon-Manifest (Interface 120001)
├── Util.lua              – Hilfsfunktionen, JSON-Export
├── Core.lua              – Initialisierung, Events, Raid-Lifecycle
├── Comm.lua              – Multi-User Sync (AddonMessage) ✅
├── Loot.lua              – Prio-Logik, Chat-Parsing, Roll-Auswertung
├── MinimapButton.lua     – Minimap-Button
└── UI.lua                – Hauptfenster (4 Tabs + Session-Leiste)
```

---

## Slash-Commands

| Command | Beschreibung |
|---|---|
| `/gl` | Hauptfenster öffnen/schließen |
| `/gl start [tier]` | Raid starten |
| `/gl reset` | Session zurücksetzen (doppelte Bestätigung) |
| `/gl history [Name]` | Loot-Historie eines Spielers |
| `/gl ml` | Master Looter umschalten |

---

## Wichtige API-Hinweise (Interface 120001)

- ❌ Kein `GetInspectItemInfo()` – fremde Ausrüstung nicht auslesbar
- ❌ `SetPropagateMouseInput` existiert nicht in TWW
- ✅ `GetRaidRosterInfo()` – Teilnehmerliste abrufbar
- ✅ `GROUP_ROSTER_UPDATE` – feuert für Party UND Raid (nicht `RAID_ROSTER_UPDATE` allein)
- ✅ `ENCOUNTER_END` (arg5 = success) – Boss-Kill erkennen
- ✅ `C_ChatInfo.SendAddonMessage` / `CHAT_MSG_ADDON` – Addon-Sync
- ✅ `C_Timer.NewTimer` / `C_Timer.After` – Timer
- ✅ `GetInstanceInfo()` – Instanzname und Schwierigkeit
- ✅ `SavedVariables` für persistente Datenspeicherung
- ⚠️ `GROUP_ROSTER_UPDATE` feuert häufig → UI-Refreshes können Timer-Zustände stören
