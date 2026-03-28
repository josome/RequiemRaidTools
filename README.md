# RaidLootTracker (RLT)

Ein World of Warcraft Addon für Gilden-Offiziere und Raid-Leader zur strukturierten Loot-Verteilung und -Verfolgung im Raid.

---

## Features

### Loot-Verteilung
- Automatische Erkennung von Boss-Loot beim Öffnen des Loot-Fensters
- **Prio-Phase**: Spieler melden ihren Bedarf per Chat (`1`=BIS, `2`=Upgrade, `3`=OS, `4`=Fun)
- **Roll-Phase**: Automatische `/roll`-Auswertung mit Countdown, Tie-Breaker bei Gleichstand
- Loot-Zuweisung mit optionaler manueller Schwierigkeitsgrad-Auswahl
- Echtzeit-Synchronisierung zwischen Master Looter und allen Raid-Mitgliedern via Addon-Kanal

### Raid-Verwaltung
- Raid starten/beenden mit optionalem Tier-Namen (auto-befüllt mit Instanzname + Datum)
- Automatische Schwierigkeitsgrad-Erkennung anhand des Item-Levels
- Teilnehmerliste mit Online/Offline-Status
- Raid-Verlauf: abgeschlossene Raids speichern und jederzeit fortsetzen
- Aktiver Raid wird in der Verlaufsliste hervorgehoben

### Spieler-Statistiken
- Pro Spieler: Loot-Historie der letzten 10 Items
- Statistiken nach Kategorie (Waffe, Trinket, Set/Token, Sonstiges)
- Letzter erhaltener Schwierigkeitsgrad pro Kategorie

### Export
- **Format wählbar**: JSON oder CSV (Einstellung in den Settings)
- JSON-Export für den Analyzer oder eigene Auswertungen
- CSV-Export für Google Sheets / Excel — flache Tabelle inkl. Status (Assigned / Trashed)
- Beide Formate enthalten: Track (Champion/Hero/Mythic), Kategorie, Prio und Trash-Einträge

---

## Analyzer

Im Ordner `analyzer/` liegt `analyzer.html` — ein eigenständiges Web-Tool zur Auswertung von JSON-Exporten. Keine Installation, kein Backend, läuft lokal im Browser.

### Import
- **Datei**: JSON-Datei per Drag & Drop oder Datei-Dialog
- **JSON-Paste**: Exportierten JSON-String direkt einfügen (Strg+Enter zum Laden)

### Auswertungen
- Raid-Info-Leiste (Tier, Datum, Schwierigkeitsgrad, Teilnehmer)
- Stat-Karten: Loot-Einträge, Teilnehmer, Trash-Items, offenes Pending
- Diagramme: Loot pro Spieler (Balken), Verteilung nach Kategorie und Prio (Donut)
- **Loot-Log**: Vollständige Tabelle mit Zeitstempel, Spieler, Track, Kategorie, Prio und Item — sortierbar, filterbar
- **Spieler-Übersicht**: Loot-Zähler pro Spieler mit Kategorieaufschlüsselung
- **Pending Loot**: Items die noch nicht vergeben wurden
- **Trash Bin**: Verworfene Items

### Item-Links
- Item-Namen sind klickbare Links direkt auf den WoWhead-Datenbank-Eintrag
- Farbe entspricht der WoW-Itemqualität (Episch = Lila, Legendär = Orange, …)
- Kompatibel mit Edge (nutzt `window.open` statt `target="_blank"`)

---

## Tabs

| Tab | Inhalt |
|-----|--------|
| **Loot** | Aktives Item, Bedarfsmeldungen, Roll-Ergebnisse, Session-Log |
| **Spieler** | Roster mit Loot-Statistiken pro Spieler |
| **Log** | Vollständiges Session-Protokoll mit Track, Kategorie und Prio |
| **Raid** | Raid starten/beenden, Export-Button, Verlauf vergangener Raids |

---

## Slash-Befehle

| Befehl | Beschreibung |
|--------|-------------|
| `/rlt` | Fenster öffnen/schließen |
| `/rlt start [Name]` | Raid starten (optional mit Tier-Name) |
| `/rlt reset` | Raid zurücksetzen (zweifache Bestätigung) |
| `/rlt history [Spieler]` | Loot-Historie eines Spielers anzeigen |
| `/rlt ml` | Master Looter Modus umschalten |
| `/rlt cleanup` | Leere Raid-Einträge aus der History entfernen |
| `/rlt test` | Test-Item aus dem Inventar in Pending-Loot einfügen |
| `/rlt testroll` | Roll-Vorgang mit Fake-Kandidaten simulieren |
| `/rlt testentry` | Loot-Log-Eintrag mit echtem Item direkt einfügen (inkl. itemID, Prio, Kategorie) |

---

## Einstellungen

- **Min. Qualität**: Selten / Episch / Legendär
- **Item-Kategorien**: Welche Kategorien im Loot-Tab angezeigt werden
- **Nicht ausrüstbare Items ausblenden** (Handwerk, Reagenzien)
- **Item-Level-Grenzen** pro Schwierigkeitsgrad (N/H/M) – manuell anpassbar für jede Season
- **Chat-Kanal**: Automatisch / Raid / Instanz-Chat / Gruppe / Aus
- **Item-Ankündigung als Raid-Warnung** (falls Raid-Leader oder Assistent)
- **Prio- und Roll-Timer**: 10 / 15 / 20 / 30 / 45 / 60 Sekunden
- **Export-Format**: JSON oder CSV

---

## Voraussetzungen

- Der verteilende Spieler muss den **Master Looter**-Modus aktivieren (Checkbox oben rechts im Fenster oder `/rlt ml`)
- Alle Raid-Mitglieder mit installiertem Addon erhalten automatisch Live-Updates
- Funktioniert in Raid-, Gruppen- und Solo-Umgebung (Solo = Testmodus)

---

## Installation

1. Ordner `RaidLootTracker` in `World of Warcraft/_retail_/Interface/AddOns/` kopieren
2. WoW neu starten oder `/reload` eingeben
3. Minimap-Button oder `/rlt` zum Öffnen

---

## UI

- **Minimap-Button**: Klicken zum Öffnen, ziehen zum Positionieren, zeigt Anzahl offener Loot-Items
- **Andock-Modus**: Fenster dockt als schmale Leiste am linken Bildschirmrand an
- **Skalierbar**: Fenster per Drag (Titelleiste) verschieben und per Grip (unten rechts) in der Größe anpassen
- **Einstellungen**: Zahnrad-Icon öffnet Panel rechts neben dem Hauptfenster

---

## Technisches

- **SavedVariable**: `GuildLootDB`
- **Addon-Kommunikation**: Prefix `RLT` (RegisterAddonMessagePrefix)
- **WoW Interface**: 120001
- **Sprache**: Deutsch

---

## Entwicklung & Test

Test-Funktionen sind in `Test.lua` definiert und nur für die Entwicklung gedacht. Sie werden über Slash-Commands ausgelöst:

### `/rlt test` — Pending-Item einfügen

Sucht ein zufälliges episches Ausrüstungs-Item aus dem Inventar und fügt es als Pending-Loot in den aktiven Raid ein. Startet den vollständigen Loot-Flow (Prio-Phase → Roll-Phase → Vergabe).

**Voraussetzung:** Aktiver Raid (`/rlt start`), mindestens ein episches Ausrüstungsstück im Inventar.

---

### `/rlt testroll` — Roll-Vorgang simulieren

Aktiviert ein episches Item aus dem Inventar und setzt direkt einen simulierten Roll-State mit 7 Fake-Kandidaten verschiedener Prioritäten. Damit kann die Results-Sektion im Loot-Tab ohne echten Raid getestet werden.

---

### `/rlt testentry` — Loot-Log-Eintrag einfügen

Fügt direkt einen fertigen `lootLog`-Eintrag mit einem echten epischen Item aus dem Inventar ein — inklusive `itemID`, Qualität, Kategorie, Schwierigkeitsgrad und Prio. Verhält sich identisch zu einem echten `AssignLoot`-Eintrag.

**Verwendung:** Schnelles Befüllen des Loot-Logs für Export-Tests und Analyzer-Tests, ohne den vollständigen Prio/Roll/Vergabe-Flow durchlaufen zu müssen.

---

## Lizenz

Privates Gilden-Tool – kein offizieller Release.
