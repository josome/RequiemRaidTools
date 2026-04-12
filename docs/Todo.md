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

- [ ] **Loot-Historie aus alten Raids anzeigen** ⚠️ Konzept erforderlich — zurückgestellt
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
      Nur Observer mit Raid-Leader oder Raid-Assist Rolle erhalten den Broadcast (nur Spieler die theoretisch ML sein könnten)
- [ ] Alle Prioritäten 1-5 über Settings konfigurierbar — jeweils: aktiv/inaktiv, Kurzname, Beschreibung
      Aktuell vorkonfiguriert: 1=BIS, 2=OS, 4=Tmog — alle sollen frei anpassbar sein
      [x] Prio: 1 = <BIS> Description: <Best in Slot>
      [x] Prio: 2 = <OS> Description: <Offspec>
      [] Prio: 3 = <> Description: <>
      [x] Prio: 4 = <Tmog> Description: <Transmog>
      [] Prio: 5 = <> Description: <>
      Problem: Inkonsistenz mit alten Raids — da Ergebnisse im Raid gespeichert werden, bleiben sie weiterhin lesbar
- [ ] **Drei UI-Ebenen**
  - **ML** — volle Kontrolle (bereits vorhanden)
  - **Observer** (Raid-Leader/Assist) — read-only, komplette Ansicht: Pending Loot, aktives Item, Roll-Ergebnisse, Session Log
  - **Player** — optionales minimales Popup für alle Raid-Mitglieder: poppt automatisch auf sobald der ML ein Item auswählt, zeigt aktuelles Item, Prio-Buttons (Klick postet automatisch ins Chat), Roll-Button (führt `/roll` aus)
### Raidverwaltung
- [ ] **Mehrerer Raids per Multiselect [] links neben Raid auswählen für delete oder export**
- [ ] **zusammenfassen von einzelnen Raids**
      Mögliche Stukturen Kalenderwochen, Daten z.B. 
      unklar wie zuweisen, drag & drop möglich (manuell)
  
      -> oder durch Start wird ein Raid Ordner erzeugt (08.04.26 - 14.04.26 / KW 15) und beim Bosskill wird geprüft wo und auf welchem schwierigkeitsgrad man ist? und je nachdem wird ein Raid eintrag im Ordner angelegt bzw falls es den Raid schon gibt der boss dem Raid zugewiesen?

      + 08.04.26 - 14.04.26 / KW 15 (zugeklappt)

      - 08.04.26 - 14.04.26 / KW 15 (aufgeklappt)
        -> Raid A N
        -> Raid A H
        -> Raid B N
        -> Raid B H


- erledigt: [x] getestet: [x] ML-Checkbox nur für Raid-Leader/Assistenten sichtbar — verhindert unbefugten ML-Claim
- erledigt: [x] getestet: [x] whisper an gewinner
- erledigt: [x] getestet: [x] Einfügen von Items im inventar in die Pending List (Drag & Drop auf >> Button)
- Readme.md aktualisieren, slash commands z.B.
   

## Bugs
- erledigt: [x] getestet: [x] Wenn das Lootverteilen abgebrochen wurde dann geht bei erneuten anhandeln die automatische Verteilung nicht mehr
- erledigt: [x] getestet: [x] bei mehr als 6 items werden die ersten 6 ins handelnsfenster gelegt, beim erneuten anhandeln bleibt das fenster leer, die restlichen items müssen manuel verteilt werden
- erledigt: [x] getestet: [ ] Warbound Items aus der Pending Loot Liste rausfiltern — nicht tradebar, daher nutzlos im Tool
- erledigt: [x] getestet: [x] Omnitoken mit "Chiming void Curio" oder "Läuternde Leerenkuriosität" im Namen weiterhin nicht in Lootliste, spezieller Filter notwendig

- Prio 4 erledigt: [x] getestet: [ ] Prio wird dem Observer nicht übertragen — im Session Log des Observers fehlt mit welcher Prio ein Item gewonnen wurde
- erledigt: [x] getestet: [ ] Addon-Prefix von [RLT] auf [ReqRT] umbenannt
- erledigt: [x] getestet: [ ] Boss-Name wird im Loot-Log gespeichert und angezeigt (ML + Observer, Session Log)
- erledigt: [x] getestet: [ ] Dock-Tab: Titel auf RT geändert, ML-Status und Raid-Status als ☑/☐ angezeigt
- erledigt: [x] getestet: [ ] ML-Checkbox abwählen sendet Broadcast an Observer ("Kein Master Looter aktiv.")

- Prio 5 [ ] Token werden nicht zuverlässig getradet — tritt aktuell nicht auf, beobachten
- Prio 3 [ ] ML-Übergabe: UI wird nach Bestätigung nicht aktualisiert
      - Beim Observer: alter ML-Name steht noch im Fenster, erst Fenster schließen/öffnen zeigt neuen ML
      - Beim alten ML: ML-Checkbox bleibt aktiv obwohl Rolle übergeben wurde
      → UI-Refresh nach erfolgreicher Übergabe auf beiden Seiten fehlt
- erledigt: [x] getestet: [x] wenn der ML den boss nicht looten kann weil items schon verrollt erscheinen diese nicht im Addon unter Pending Loot

## Raid Sessing Bugs 
- Anlegen von Session nicht möglich, klick New Sessing -> name eingeben -> Start klicken -> nichts passiert fenster bleibt offen keine neue Session
  -> Erwarteung:
    
- wir hatten besprochen das neue Raids in der Session nur durch neuen loot mit RaidIDs entstehen können, jetzt entstehen sie einfach mit zonenwechsel
  Also RaidID wird erstellt wenn Loot droppt, auf dem screenshot zu sehen ist aber das beim Zonenwechsel ein raid entsteht. 
   -> Erwartung:
    Nur Raid einträge in Session für die es loot gibt.
---

## Erledigt

- erledigt: [x] getestet: [x] **Prio löschen per X-Button** — ML kann versehentliche Prios entfernen
- erledigt: [x] getestet: [ ] **Settings-Sync via RAID_START** — minQuality, prioSeconds, rollSeconds werden übertragen
- erledigt: [x] getestet: [x] **Prios umbenannt** — 1=BIS, 2=OS, 4=Transmog
- erledigt: [x] getestet: [x] **Doppel-Item gleichzeitig rollen** — Multi-Winner Roll mit Assign All
- erledigt: [x] getestet: [ ] **Bug: Late-Join Sync** — Client der später beitritt bekommt Raiddaten
- erledigt: [x] getestet: [ ] **Bug: Omni-Token-Erkennung** — Set-Token werden korrekt erkannt
- erledigt: [x] getestet: [x] **Bug: Addon in Dungeons & Tiefen deaktiviert** — kein Loot-Tracking, UI versteckt sich
- erledigt: [x] getestet: [x] **Auto-Handel** — Item wird automatisch ins Handelsfenster gelegt (auch mehrere Items)
- ~~**Abgleich Discord Raid anmeldungen mit eingeladenen personen**~~ — verworfen (Discord-Namen ≠ WoW-Namen)

---

### CSV Roundtrip: Google Sheets ↔ Addon ⚠️ zurückgestellt bis Loot-Historie-Konzept steht

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

- erledigt: [x] getestet: [ ] **Loot.lua modularisiert** — aufgeteilt in `src/loot/`: `Loot.lua`, `Loot_Roll.lua`, `Loot_Assign.lua`, `Loot_Trade.lua`

- [ ] **Chat-Nachrichten farbig hervorheben**
  WoW unterstützt `|cAARRGGBB...|r` in allen Chat-Typen (Raid, Raid-Warning, Whisper).
  Aktuell ist nur der lokale `[ReqRT]`-Prefix in Print-Meldungen cyan eingefärbt.
  → `[ReqRT]`-Prefix auch in `SendChatMessage`-Aufrufen einfärben, ggf. wichtige Meldungen (Winner, Prio-Aufforderung) hervorheben.

- [ ] **Lokalisierung (i18n)** ⚠️ niedrige Priorität — zurückgestellt
  Aktuell ~40+ gestreute Strings, gemischt Deutsch/Englisch, kein L[]-System.
  → `Locales/deDE.lua` + `Locales/enUS.lua` anlegen, alle UI-Strings durch `L["key"]` ersetzen, TOC um Locale-Dateien erweitern.

- [ ] **JSON-Export-Fenster scrollbar machen**
  Das Export-Textfeld ist aktuell nicht scrollbar, der Inhalt geht über das Fenster hinaus.
  → ScrollFrame um das Export-TextBox ergänzen, oder EditBox mit `SetMultiLine(true)` + Scroll-Wrapper


