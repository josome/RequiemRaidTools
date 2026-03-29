# GuildLoot Addon – Implementierungsplan (vereinfacht)

## Context
WoW Retail Addon (12.0.1 / Midnight) für Raid-Loot-Tracking.
Offiziere entscheiden selbst wer Loot bekommt — das Addon trackt nur **wer wann welches Item erhalten hat**.
Alle Queue- und Rotationssysteme entfallen komplett.
Aktuell existiert nur `PLANNING.md`, alle 6 Dateien werden neu erstellt.

---

## Loot-Workflow (exakt)

1. **Boss stirbt** → `LOOT_OPENED` event → Addon liest alle Loot-Slots automatisch
2. **Items erscheinen im Addon-Panel** (gefiltert nach Qualität, z.B. nur Epic+)
3. **LM klickt ein Item** → Addon postet in Raid-Chat: `>> [Itemname] roll >>`
4. **Spieler posten ihren Bedarf** im Raid-Chat: nur eine Zahl `1`–`4`
   - `1` = höchster Bedarf (BIS), `4` = niedrigster
   - Optionale Zusätze wie `1up`, `1bis` werden akzeptiert — nur die **führende Zahl** zählt
5. **LM klickt "Roll freigeben"** → Addon postet: `"Jetzt bitte würfeln! Ihr habt 30 Sekunden: [Spieler1], [Spieler2]..."`
   - **Nur Spieler mit der niedrigsten vorhandenen Prio-Zahl** werden aufgefordert
   - Gibt es eine `1` → nur alle mit `1`; keine `1` aber `2` → alle mit `2`, usw.
6. **30 Sekunden Timer** → Addon sammelt `/roll`-Ergebnisse aus `CHAT_MSG_SYSTEM`
7. **Ergebnisse erscheinen im Addon** — Tabelle zeigt: `Name | Prio | Roll-Ergebnis`
   - LM kann das selbst verifizieren
8. **LM klickt "Zuweisen"** neben einem Spieler → Item wird diesem Spieler zugewiesen
   - Kein Auto-Assign — LM entscheidet bewusst (Gewinner kann spontan ablehnen)
9. **Addon speichert Loot** + postet Gewinner in Raid-Chat

---

## Zu erstellende Dateien (Load-Order)

| Datei | Zweck |
|---|---|
| `GuildLoot.toc` | Addon-Manifest, Interface 120001 |
| `Util.lua` | Hilfsfunktionen |
| `Core.lua` | Namespace, SavedVariables, Events, Slash-Commands |
| `Loot.lua` | Chat-Parsing, Kandidatenliste, Gewinner-Bestätigung |
| `UI.lua` | Frames, Teilnehmerliste, Aktives-Item-Panel |

**Queue.lua entfällt komplett.**

---

## GuildLoot.toc

```
## Interface: 120001
## Title: GuildLoot
## Notes: Raid-Loot-Tracking fuer Gilden-Offiziere
## Version: 1.0.0
## SavedVariables: GuildLootDB

Util.lua
Core.lua
Loot.lua
UI.lua
```

---

## SavedVariables-Struktur (vereinfacht)

```lua
GuildLootDB = {
    players = {
        ["Name-Realm"] = {
            lootHistory = {
                {
                    item       = itemLink,
                    category   = "weapons",   -- "weapons"|"trinket"|"setItems"|"other"
                    difficulty = "M",         -- "N"|"H"|"M" (auto-erkannt, überschreibbar)
                    timestamp  = 0,
                },
                ...
            },
            -- Letzter erhaltener Loot pro Kategorie (für Tabellen-Schnellansicht)
            lastDifficulty = {
                weapons  = nil,  -- "N"|"H"|"M"|nil
                trinket  = nil,
                setItems = nil,
            },
            counts = {
                weapons  = 0,
                trinket  = 0,
                setItems = 0,
                other    = 0,
            },
            lootEligible = true,   -- Checkbox "Lootberechtigt"
            setPieces    = 0,      -- 0–4, manuell vom LM gesetzt
        }
    },
    currentRaid = {
        active       = false,
        tier         = "",
        difficulty   = "",
        participants = {},   -- Liste aktiver Spieler (Name-Realm)
        absent       = {},   -- Abwesende Spieler (Name-Realm → true)
        lootLog      = {},   -- Loot-Log dieser Session
    },
    settings = {
        postToChat      = true,
        chatCommand     = "/gl",
        isMasterLooter  = false,   -- Checkbox in UI — nur einer im Raid sollte true sein
        minQuality      = 4,       -- 4=Epic, 5=Legendary; nur Items >= dieser Qualität werden angezeigt
    }
}
```

---

## Util.lua

- `GuildLoot.GetItemCategory(itemID, itemLink)` → `"weapons"|"trinket"|"setItems"|"other"`
  - Reihenfolge der Prüfungen (erste Übereinstimmung gewinnt):

  **1. Set-Teile (direktes Tier Armor)**
  ```lua
  local setID = C_Item.GetItemSetID(itemID)
  if setID and setID ~= 0 then return "setItems" end
  ```

  **2. Set-Tokens (Rüstungsklassen-basierte Tausch-Items)**
  In Midnight gibt es klassenbasierte Tokens, gruppiert nach Rüstungstyp:
  - Stoff: Magier, Priester, Hexenmeister
  - Leder: Druide, Dämonenjäger, Mönch, Schurke
  - Kette: Jäger, Rufer, Schamane
  - Platte: Todesritter, Paladin, Krieger

  Erkennung via Tooltip-Scan (sicherste Methode):
  ```lua
  if itemEquipLoc == "" and quality >= 4 then
    -- Temporären Tooltip erstellen und scannen
    -- Zeile enthält "Klassen:" (DE) oder "Classes:" (EN)
    -- → category = "setItems"
  end
  ```
  Implementierung: `GameTooltip:SetItemByID(itemID)` → alle Tooltip-Zeilen iterieren → Pattern `"[Kk]lassen:"` oder `"[Cc]lasses:"`

  **3. Waffen**
  `INVTYPE_WEAPON`, `INVTYPE_MAINHAND`, `INVTYPE_OFFHAND`, `INVTYPE_2HWEAPON`, `INVTYPE_RANGED`, `INVTYPE_RANGEDRIGHT`, `INVTYPE_SHIELD`, `INVTYPE_HOLDABLE`

  **4. Trinkets**
  `INVTYPE_TRINKET`

  **5. Sonstiges**
  Alles andere (Ringe, Halsschmuck, Rüstungsteile ohne Set-ID, etc.)
- `GuildLoot.DetectDifficulty(itemLevel)` → `"N"|"H"|"M"`
  - Heuristik anhand Itemlevel-Ranges der aktuellen Season (konfigurierbar in settings)
  - `settings.difficultyRanges = { N={min=593,max=606}, H={min=606,max=619}, M={min=619,max=639} }`
  - Kein Match → `nil` (LM wird zum Override aufgefordert)
- `GuildLoot.ParseLootInput(message)` → `prio` (1–4) oder `nil`
  - Nur führende Ziffer: Pattern `^(%d)` — ignoriert alles dahinter (`1up`, `1bis` etc.)
- `GuildLoot.IsOfficer()` → `UnitIsOfficer("player")`
- `GuildLoot.GetTimestamp()` → `time()`
- `GuildLoot.FormatTimestamp(ts)` → `"DD.MM.YYYY HH:MM"`
- `GuildLoot.TableContains(t, v)` — prüft ob Wert in Liste

---

## Core.lua

### Namespace & DB-Defaults
```lua
GuildLoot = GuildLoot or {}
```

### Events
```
ADDON_LOADED, PLAYER_LOGIN, PLAYER_LOGOUT,
RAID_ROSTER_UPDATE,
ENCOUNTER_END,          -- Boss-Kill → Auto-Expand + Tab "Loot" aktivieren
LOOT_OPENED, LOOT_CLOSED,
CHAT_MSG_RAID, CHAT_MSG_RAID_LEADER, CHAT_MSG_SYSTEM
```

### Kernfunktionen
- `GL.InitDB()` — fehlende Felder mit Defaults befüllen
- `GL.CreatePlayerRecord(name)` — `{ lootHistory={}, counts={...} }`
- `GL.LoadRaidRoster()` — `GetRaidRosterInfo()` → participants, neue Spieler bekommen Datensatz
- `GL.SyncRoster()` — bei `RAID_ROSTER_UPDATE`: neu hinzugekommen / verlassen / reconnect
- `GL.RequireOfficer()` — Guard für alle mutierenden Operationen
- `GL.StartRaid(tier)` — currentRaid aktivieren, Roster laden
- `GL.ShowHistory(name)` — Loot-Historie in Chat ausgeben
- `GL.PostToRaid(msg)` — Raid-Chat wenn `postToChat=true`
- `GL.Print(msg)` — `[GuildLoot] ...` in lokale Chat-Box

### Slash-Commands
| Command | Funktion |
|---|---|
| `/gl` | Hauptfenster ein/ausschalten |
| `/gl start [tier]` | Raid starten |
| `/gl history [Name]` | Historie eines Spielers in Chat |
| `/gl reset` | Aktuelle Session zurücksetzen (Offizier) |

---

## Roster-Verwaltung (RAID_ROSTER_UPDATE)

**`GL.SyncRoster()` Logik:**
1. Aktuellen Raid via `GetRaidRosterInfo()` lesen → Menge `currentMembers`
2. **Neu beigetreten** (in `currentMembers`, nicht in `participants`):
   - `CreatePlayerRecord` falls kein DB-Eintrag
   - Zur `participants`-Liste hinzufügen
   - `absent` Flag entfernen
3. **Verlassen/DC** (war in `participants`, nicht mehr in `currentMembers`):
   - **Bleibt in `participants`** — Loot-Historie bleibt erhalten
   - `absent[name] = true`
   - UI zeigt ihn ausgegraut mit "(abwesend)"
4. **Reconnect** (war absent, taucht wieder auf):
   - `absent[name] = nil`
5. `GL.UI.Refresh()`

**Abwesende Spieler bei Loot:**
- Können sich nicht per Chat melden (Guard in `OnChatMessage`)
- Offizier kann sie als Gewinner trotzdem manuell auswählen (z.B. für Bankitems)

---

## Loot.lua

### Modul-lokaler Zustand (nicht persistent)
```lua
currentItem = {
    link       = nil,
    name       = nil,
    category   = nil,
    candidates = {},  -- { name, prio, category } — rein informativ für Offizier
    rollState  = { active=false, players={}, results={}, needed=0 },
    winner     = nil,
}
```

### Automatische Loot-Erkennung (Boss stirbt)
- Events: `LOOT_OPENED` → Addon liest Loot-Slots
- `GetNumLootItems()` → für jeden Slot: `GetLootSlotLink(slot)` + `GetLootSlotInfo(slot)`
- `GetLootSlotLink()` ist **keine** geschützte Funktion → kein Taint-Problem
- Filter: nur Items mit Qualität ≥ Epic (4 = epic, 5 = legendary, 6 = artifact) — konfigurierbar in `settings.minQuality`
- Alle gefundenen Items → `pendingLoot[]` Liste, erscheinen im Addon-Panel
- `LOOT_CLOSED` → pendingLoot-Liste einfrieren (Loot-Fenster weg)

### Item freigeben (LM klickt Item in der Liste)
1. `GL.Loot.ReleaseItem(itemLink)` — `GetItemInfo()` aufrufen
2. Falls nil → `GET_ITEM_INFO_RECEIVED` abwarten (deferred loading)
3. `GL.Loot.ActivateItem(...)` — `currentItem` setzen, Raid-Chat: `>> [Item] roll >>`

### Chat-Parsing — Bedarfsmeldungen
- `OnChatMessage(msg, sender)`: Guard `currentItem.link` + `IsParticipant(sender)`
- `ParseLootInput(message)` — extrahiert **nur die führende Zahl**: `^(%d)` → Prio 1–4
  - Akzeptiert: `"1"`, `"2"`, `"1up"`, `"1bis"`, `"2 UP"` etc. — immer nur erste Ziffer
- `RegisterCandidate(name, prio)`: bestehenden Eintrag ersetzen (Korrektur erlaubt)
- Kandidatenliste in UI wird live aktualisiert

### Roll-Freigabe (LM klickt Button)
1. Niedrigste vorhandene Prio-Zahl ermitteln: `GetLowestPrio(candidates)`
2. Alle Spieler mit dieser Zahl → `rollPlayers` Liste
3. Raid-Chat: `"Jetzt bitte würfeln! Ihr habt 30 Sekunden: [Spieler1], [Spieler2], ..."`
4. `StartRoll(rollPlayers)` → `rollState.active = true`
5. `C_Timer.After(30, FinalizeRoll)` — fester 30-Sekunden-Timer

### Roll-Monitoring
- `OnSystemMessage(msg)`: Pattern aus `RANDOM_ROLL_RESULT` ableiten
- Nur Rolls von Spielern in `rollState.players` akzeptieren
- Nur erster Roll pro Spieler zählt
- `FinalizeRoll()`: höchste Zahl gewinnt; bei echtem Gleichstand → erneuter Roll

### Ergebnisanzeige nach Roll
Nach `FinalizeRoll()` wird eine Tabelle angezeigt:
```
Name        | Prio | Roll
─────────────────────────
Aragorn     |  1   |  87   ← höchster Roll unter Prio-1-Spielern
Legolas     |  1   |  42
(Gimli      |  2   |  -- ) ← nicht in Roll-Runde (höhere Prio-Zahl vorhanden)
```
- Gewinner wird **hervorgehoben** (Gold), aber NICHT automatisch zugewiesen
- Jeder Spieler in der Liste hat einen `[Zuweisen]`-Button
- LM klickt selbst auf `[Zuweisen]` — bewusste Entscheidung

### Zuweisung (LM klickt [Zuweisen])
```
AssignLoot(name):
  diff = DetectDifficulty(itemLevel)
  falls diff == nil → kleines Popup: LM wählt N/H/M manuell

  playerData.lootHistory += { item, category, difficulty=diff, timestamp }
  playerData.counts[category] += 1
  playerData.lastDifficulty[category] = diff   -- Tabellenspalte aktualisieren
  currentRaid.lootLog += Eintrag
  GL.PostToRaid("[Name] erhält [Item] – bitte beim Lootmaster abholen.")
  Item aus pendingLoot entfernen
  currentItem zurücksetzen
  GL.UI.Refresh()
```

**Difficulty-Override:** In der Teilnehmertabelle kann der LM auf die angezeigte Schwierigkeit (z.B. `H`) klicken → kleines Dropdown `N | H | M` zum Korrigieren.

---

## UI.lua

### Master Looter Modus
Das Addon kann von mehreren Raidern gleichzeitig installiert sein.

**Rollen:**
- **Master Looter (ML)**: Einer pro Raid — führt die Lootverteilung durch
- **Observer**: Alle anderen mit dem Addon — können mitlesen, aber nichts auslösen

**ML-Checkbox in der UI** (persistent in `settings.isMasterLooter`):
- Kleiner Toggle oben im Frame: `☐ Ich bin Master Looter`
- Standardmäßig **aus** — muss bewusst aktiviert werden

**ML-Übergabe während der Session:**
- Die Checkbox ist rein lokal — mehrere MLs gleichzeitig sind technisch harmlos, solange sie sich absprechen
- Übergabe: neuer ML aktiviert Checkbox, alter deaktiviert sie — in beliebiger Reihenfolge
- `/gl ml` Slash-Command als Schnellweg zum Togglen

**Was nur der ML darf (Guard: `settings.isMasterLooter == true`):**
- Auto-Expand nach Boss-Kill
- In Raid-Chat posten (`>> [Item] roll >>`, Roll-Aufforderung, Gewinner-Ansage)
- Item freigeben (Pending Loot Button klickbar)
- Roll freigeben (Button klickbar)
- `[Zuweisen]` Button klickbar

**Was alle sehen (Observer und ML):**
- Teilnehmertabelle (read-only für Observer, editierbar nur für ML)
- Pending Loot Liste (nur ansehen)
- Kandidatenliste live
- Ergebnistabelle nach Roll

### Auto-Expand nach Boss-Kill
- Event: `ENCOUNTER_END` (status=1 = erfolgreicher Kill)
- Guard: `settings.isMasterLooter == true`
- Falls Frame minimiert → automatisch aufklappen + zu Tab "Loot" wechseln

### Frame-Hierarchie
```
GuildLootMainFrame (600×450, BasicFrameTemplateWithInset, movable)
├── MinimizeButton («/») — kollabiert Frame auf ~20px Streifen
├── TabBar: [Loot ★]  [Spieler]  [Log]
│           ↑ Haupt-Tab  ↑ Neben-Tab
├── Tab1 "Loot" (Standard-Tab, aktiv nach Boss-Kill):
│     ← aktives Item-Panel (Pending Loot + Roll-Prozess)
├── Tab2 "Spieler" (Neben-Tab):
│     ← Teilnehmertabelle mit allen Spalten
├── Tab3 "Log":
│     ← Session-Loot-Log
```

### Tab "Spieler": ScrollFrame
│     Spalten:
│     ┌──────────┬──────────────┬──────────┬───────┬─────────┬─────────────┬───────────┐
│     │ Raider   │Lootberechtigt│ Set Item │ Waffe │ Trinket │Restl. Loot  │ Set Bonus │
│     ├──────────┼──────────────┼──────────┼───────┼─────────┼─────────────┼───────────┤
│     │ Aragorn  │     ☑        │   M      │   H   │    N    │      1      │   2/4     │
│     │ Legolas  │     ☑        │   —      │   M   │    —    │      0      │   0/4     │
│     │ Gimli    │     ☐        │   H      │   —   │    —    │      2      │   4/4 ✓  │
│     └──────────┴──────────────┴──────────┴───────┴─────────┴─────────────┴───────────┘
├── Tab1 "Loot" (Haupt, Standard nach Boss-Kill):
│     ┌─ Pending Loot ─────────────────────────────────────────┐
│     │  [Item A]  [Item B]  [Item C]  ← klickbare Buttons    │
│     └────────────────────────────────────────────────────────┘
│     Aktives Item: [Itemlink] — Kategorie: Waffe
│     [Freigabe zurücksetzen]
│     ─────────────────────────────────────────────────────────
│     Kandidaten (live): Name | Prio
│     [Roll freigeben] Button (sichtbar wenn ≥1 Kandidat)
│     ─────────────────────────────────────────────────────────
│     Ergebnistabelle (nach Roll):
│       Name        | Prio | Roll  | Aktion
│       Aragorn     |  1   |  87   | [Zuweisen]   ← gold markiert
│       Legolas     |  1   |  42   | [Zuweisen]
│     Countdown-Anzeige während Roll läuft: "Noch 23 Sek."
│
│  Teilnehmer-Tabellen-Interaktionen:
│  - Lootberechtigt-Checkbox: Klick → toggle, sofort gespeichert
│  - N/H/M-Anzeige: Klick → Dropdown N|H|M (Override)
│  - Set Bonus: Klick auf Zahl → Spinner 0–4 (−/+)
└── Tab3 SessionLog: ScrollFrame, alle Loot-Vergaben dieser Session
```

### Collapse/Minimize Feature
- MinimizeButton (`«`/`»`) in Titelleiste
- Minimiert: `f:SetHeight(20)`, ContentFrame versteckt → nur Titelstreifen sichtbar
- Klick auf Streifen → aufklappen
- Position + Zustand werden in `GuildLootDB.settings` gespeichert:
  ```lua
  settings.framePos = { point, x, y }
  settings.minimized = false
  ```
- Beim Login: Position + Zustand wiederherstellen

### Secure Taint
- NIE `LootFrame` oder `MasterLooterFrame` anfassen
- Item-Link via EditBox + Shift-Click (100% taint-sicher)

---

## Edge Cases

| Fall | Behandlung |
|---|---|
| `GetItemInfo()` gibt nil | `GET_ITEM_INFO_RECEIVED` + deferred activation |
| Cross-Realm Spieler | `Name-Realm` Format durchgängig als Key |
| Spieler kommt zu spät | `SyncRoster()` → hinzufügen |
| Spieler verlässt Raid | `absent=true`, bleibt in Liste mit Historie |
| Reconnect | `absent=nil`, Status reaktiviert |
| Mehrfache Chat-Eingabe | `RegisterCandidate` ersetzt vorherigen Eintrag |
| Abwesender meldet sich per Chat | Wird ignoriert (Guard) |
| Roll-Gleichstand | Erneuter Roll für die Gleichstand-Spieler |
| `/gl reset` | Bestätigung erforderlich (zweistufig) |

---

## Verifikation

1. Addon in `Interface/AddOns/GuildLoot/` kopieren
2. WoW starten → Addon-Liste → GuildLoot aktiviert
3. `/gl` → Hauptfenster öffnet sich
4. In Raid-Gruppe → `/gl start TWW S2`
5. Item per Shift-Click in EditBox einfügen → Enter → Item erscheint im Panel
6. Im Raid-Chat: `1 BIS` → Eintrag in Kandidatenliste
7. Kandidat anklicken → Gewinner-Vorschlag → Bestätigen
8. Tab "Teilnehmer" → Loot-Zähler +1
9. Tab "Session-Log" → Eintrag sichtbar
10. `/gl history [Name]` → Ausgabe in Chat
11. Minimize-Button → Frame kollabiert zu Streifen → Klick → aufgeklappt
12. `/logout` + Relog → Position und Daten persistent
