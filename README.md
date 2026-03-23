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
- JSON-Export aller Loot-Daten eines ausgewählten Raids (Strg+A, Strg+C)

---

## Tabs

| Tab | Inhalt |
|-----|--------|
| **Loot** | Aktives Item, Bedarfsmeldungen, Roll-Ergebnisse, Session-Log |
| **Spieler** | Roster mit Loot-Statistiken pro Spieler |
| **Log** | Vollständiges Session-Protokoll |
| **Raid** | Raid starten/beenden, Verlauf vergangener Raids |

---

## Slash-Befehle

| Befehl | Beschreibung |
|--------|-------------|
| `/gl` | Fenster öffnen/schließen |
| `/gl start [Name]` | Raid starten (optional mit Tier-Name) |
| `/gl reset` | Raid zurücksetzen (zweifache Bestätigung) |
| `/gl history [Spieler]` | Loot-Historie eines Spielers anzeigen |
| `/gl ml` | Master Looter Modus umschalten |

---

## Einstellungen

- **Min. Qualität**: Selten / Episch / Legendär
- **Item-Kategorien**: Welche Kategorien im Loot-Tab angezeigt werden
- **Nicht ausrüstbare Items ausblenden** (Handwerk, Reagenzien)
- **Item-Level-Grenzen** pro Schwierigkeitsgrad (N/H/M) – manuell anpassbar für jede Season
- **Chat-Kanal**: Automatisch / Raid / Gruppe / Aus
- **Item-Ankündigung als Raid-Warnung** (falls Raid-Leader oder Assistent)
- **Prio- und Roll-Timer**: 10 / 15 / 20 / 30 / 45 / 60 Sekunden

---

## Voraussetzungen

- Der verteilende Spieler muss den **Master Looter**-Modus aktivieren (Checkbox oben rechts im Fenster oder `/gl ml`)
- Alle Raid-Mitglieder mit installiertem Addon erhalten automatisch Live-Updates
- Funktioniert in Raid-, Gruppen- und Solo-Umgebung (Solo = Testmodus)

---

## Installation

1. Ordner `RaidLootTracker` in `World of Warcraft/_retail_/Interface/AddOns/` kopieren
2. WoW neu starten oder `/reload` eingeben
3. Minimap-Button oder `/gl` zum Öffnen

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

## Lizenz

Privates Gilden-Tool – kein offizieller Release.
