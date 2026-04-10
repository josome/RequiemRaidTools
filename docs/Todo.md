# RequiemRaidTools – Todo

> **Geplant (nach PR-Merge):** Addon-Rename zu **RequiemRaidTools** (Abk. `Reqrt`) + Versionierung auf `Major.Minor.Patch.Build` (Stable) / `Major.Minor.Patch.Build-beta` (Test-Addon)

## Konvention
Erledigte Items werden mit zwei Checkboxen markiert:
`erledigt: [x] getestet: [ ]`

---

## Offen

### Spieler-Tab: Aufklappbare Loot-Historie

- [x] **Expandable Player Rows**
  Jede Zeile im Spieler-Tab aufklappbar. Beim Aufklappen erscheinen alle erhaltenen Items
  des aktuellen Raids als eingerückte Sub-Rows (Item, Kategorie, Schwierigkeitsgrad, Prio).
  - Toggle-Button `▶`/`▼` links vom Namen (16px), restliche Spalten bleiben unverändert
  - Expansion-State in `local expandedPlayers = {}` (file-local, überlebt Refresh, nicht Reload)
  - Sub-Rows aus `currentRaid.lootLog` gefiltert nach `GL.ShortName(fullName)`
  - Sub-Rows landen in `playerRows` → automatisch aufgeräumt beim nächsten Refresh
  - Scroll-Höhe passt sich automatisch an (gleicher `yOff`-Counter)
  - Zebra-Stripe-Fix: separater `zebraIdx`-Zähler statt `#playerRows % 2`
  - Nur `UI_SpielerTab.lua` betroffen, keine anderen Dateien

- [ ] **Loot-Historie aus alten Raids anzeigen**
  Aufgeklappte Spieler-Rows zeigen zusätzlich Loot aus `raidHistory` (abgeschlossene Raids),
  gruppiert nach Raid mit Separator-Header (Raid-Name + Datum).
  - Scan über alle `raidHistory[i].lootLog` nach `entry.player == GL.ShortName(fullName)`
  - `itemID` überlebt SavedVariables-Reload → WoWhead-Links funktionieren auch für alte Einträge
  - Aktueller Raid zuerst, danach ältere Raids chronologisch absteigend
  - Optional: Limit auf letzte N Raids oder letzte X Items

- [x] **Bei lootverteilung mit prio 4 sollen die bevorzugt werden die das item tragen können**
        Platte aber nur platte und nicht auch stoff, leder und schwere rüstung

- [x] **wenn zwei mal das identische Item droppt sollten beide (oder mehr) Items mit einem gang verrollt werden können**

- [ ] NEW **Startet der ML einen Raid soll es einen broadcast an alle OBS geben, diese bekommen eine Meldung das ein Raid gestartet wurde**
- [ ] Einstellen der Prioritäten 1-5 über settings mit [] für aktiv und mit Freitext für Name, und Beschreibung 
      [x] Prio: 1 = <BIS> Description: <Best in Slot>
      [x] Prio: 2 = <OS> Description: <Offspec>
      [] Prio: 3 = <> Description: <>
      [x] Prio: 4 = <Tmog> Description: <Transmog>
      [] Prio: 5 = <> Description: <>
      Problem, inkosistenz mit alten Raids, aber da diese Ergebnisse im Raid gespeichert werden sind sie weiterhin ansehbar  
- [ ] OBS sollte die Itemliste bekommen, damit er sieht wie weit die Lootvergabe fortgeschritten ist
- erledigt: [x] getestet: [ ] ML-Checkbox nur für Raid-Leader/Assistenten sichtbar — verhindert unbefugten ML-Claim
- erledigt: [x] getestet: [x] whisper an gewinner
- [ ] Spezial Items wie Baupläne und Rezepte müssten verteilt werden
- erledigt: [x] getestet: [x] Einfügen von Items im inventar in die Pending List (Drag & Drop auf >> Button)
## Bugs
- erledigt: [x] getestet: [x] Wenn das Lootverteilen abgebrochen wurde dann geht bei erneuten anhandeln die automatische Verteilung nicht mehr
- erledigt: [x] getestet: [x] bei mehr als 6 items werden die ersten 6 ins handelnsfenster gelegt, beim erneuten anhandeln bleibt das fenster leer, die restlichen items müssen manuel verteilt werden
- [ ] Warbound items erscheinen auch in der Liste, das ist nicht optimal
- erledigt: [x] getestet: [x] Omnitoken mit "Chiming void Curio" oder "Läuternde Leerenkuriosität" im Namen weiterhin nicht in Lootliste, spezieller Filter notwendig

- Prio 4 [ ] Prio wird dem OBS nicht mit übertragen,

- Prio 2 [ ] Token werden nicht zuverlässig getradet
- Prio 3 [ ] ML übergabe alter ML steht noch in Leiste
- erledigt: [x] getestet: [x] wenn der ML den boss nicht looten kann weil items schon verrollt erscheinen diese nicht im Addon unter Pending Loot



---

## Erledigt

- erledigt: [x] getestet: [ ] **Prio löschen per X-Button** — ML kann versehentliche Prios entfernen
- erledigt: [x] getestet: [ ] **Settings-Sync via RAID_START** — minQuality, prioSeconds, rollSeconds werden übertragen
- erledigt: [x] getestet: [ ] **Prios umbenannt** — 1=BIS, 2=OS, 4=Transmog
- erledigt: [x] getestet: [ ] **Doppel-Item gleichzeitig rollen** — Multi-Winner Roll mit Assign All
- erledigt: [x] getestet: [ ] **Bug: Late-Join Sync** — Client der später beitritt bekommt Raiddaten
- erledigt: [x] getestet: [ ] **Bug: Omni-Token-Erkennung** — Set-Token werden korrekt erkannt
- erledigt: [x] getestet: [ ] **Bug: Addon in Dungeons & Tiefen deaktiviert** — kein Loot-Tracking, UI versteckt sich
- erledigt: [x] getestet: [ ] **Auto-Handel** — Item wird automatisch ins Handelsfenster gelegt (auch mehrere Items)
- ~~**Abgleich Discord Raid anmeldungen mit eingeladenen personen**~~ — verworfen (Discord-Namen ≠ WoW-Namen)

---

### CSV Roundtrip: Google Sheets ↔ Addon

- [ ] **CSV um `ItemID` und `Quality` erweitern**
  Aktuelle Spalten: `RaidID, Tier, Difficulty, Track, Date, Status, Player, Item, Category, Prio, Timestamp`
  Erweitert: `RaidID, Tier, Difficulty, Track, Date, Status, Player, Item, ItemID, Quality, Category, Prio, Timestamp`
  → `GL.ExportCSV()` in `Util.lua` anpassen

- [ ] **CSV-Importer im Addon**
  Paste-Feld im Addon (eigener Tab oder im Raid-Tab) für CSV-String aus Google Sheets.
  Parser gruppiert flache Zeilen nach `RaidID` und rekonstruiert `raidHistory`-Einträge
  mit `lootLog` (Status=Assigned) und `trashedLoot` (Status=Trashed).

  **Validierung & Fehlerbehandlung:**
  - Import läuft in temporären Buffer — erst nach vollständiger Validierung committed
  - Pflichtfeld-Check pro Zeile: `RaidID`, `Player`, `Timestamp` (Zahl), `Status` (Assigned/Trashed)
  - Fehlerhafte Zeilen werden übersprungen (Warning), kein kompletter Abbruch
  - Duplikat-Check: falls Raid mit gleicher `RaidID` bereits in `raidHistory` → Confirmation-Dialog
  - Dry-Run Vorschau vor Import: "X Raids, Y Einträge gefunden, Z Zeilen übersprungen"

  **Robustheit gegen Sheets-Eigenheiten:**
  - BOM-Zeichen (`\xEF\xBB\xBF`) am Anfang entfernen
  - `\r\n` und `\n` beide akzeptieren
  - RFC-4180 Quotes behandeln (mehrzeilige Felder, escaped Quotes)
  - Leere Abschlusszeilen ignorieren

---

### Sonstiges

- [ ] **Loot.lua modularisieren**
  Datei ist zu groß — aufteilen in:
  - `Loot.lua` — Kern: Pending-Loot, Kategorisierung, `TryAddPendingItem`
  - `Loot_Roll.lua` — Roll-Logik: Prio-Phase, Roll-Phase, Timer, Kandidaten
  - `Loot_Trade.lua` — Auto-Handel: `_pendingTrades`, `OnTradeShow`, Staging
  - `Loot_Assign.lua` — Zuweisung: `AssignLoot`, `AssignLootConfirm`, `AssignAllWinners`
  TOC entsprechend erweitern.

- [ ] **Lokalisierung (i18n)**
  Aktuell ~40+ gestreute Strings, gemischt Deutsch/Englisch, kein L[]-System.
  → `Locales/deDE.lua` + `Locales/enUS.lua` anlegen, alle UI-Strings durch `L["key"]` ersetzen, TOC um Locale-Dateien erweitern.

- [ ] **JSON-Export-Fenster scrollbar machen**
  Das Export-Textfeld ist aktuell nicht scrollbar, der Inhalt geht über das Fenster hinaus.
  → ScrollFrame um das Export-TextBox ergänzen, oder EditBox mit `SetMultiLine(true)` + Scroll-Wrapper


