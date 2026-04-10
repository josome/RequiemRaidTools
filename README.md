# RequiemRaidTools (RLT)

Ein World of Warcraft Addon für Gilden-Offiziere und Raid-Leader zur strukturierten Loot-Verteilung im Raid — mit Prio-System, automatischer Roll-Auswertung und Echtzeit-Synchronisation zwischen allen Raid-Mitgliedern.

---

## Was ist RequiemRaidTools?

In WoW-Raids übernimmt der **Master Looter (ML)** die Kontrolle darüber, wer welches Item bekommt. RequiemRaidTools unterstützt den ML dabei: Items werden automatisch erkannt, Spieler melden ihren Bedarf per Chat, und das Addon wertet Rolls aus, ermittelt Gewinner und legt das Item beim nächsten Handelsfenster automatisch in die Trade-Slots.

Alle Raid-Mitglieder mit installiertem Addon sehen denselben Stand wie der ML — in Echtzeit, ohne manuellen Abgleich.

**Kernfunktionen:**
- Automatische Loot-Erkennung und Pending-Liste
- Prio-System (BIS / OS / Transmog) mit konfigurierbaren Timern
- Automatische `/roll`-Auswertung mit Tie-Re-Roll
- Echtzeit-Sync zwischen ML und allen Observern (auch Late-Joiner)
- Auto-Handel: Item wird beim Öffnen des Handelsfensters automatisch eingelegt
- Mehrere Kopien desselben Items in einem Roll-Vorgang
- Raid-Historie mit Export als JSON oder CSV

---

## Installation

1. Ordner `RequiemRaidTools` in `World of Warcraft/_retail_/Interface/AddOns/` kopieren
2. WoW neu starten oder `/reload` eingeben
3. `/rlt` zum Öffnen des Fensters

---

## Erste Schritte

1. `/rlt` eingeben → Hauptfenster öffnet sich
2. **ML-Checkbox** oben rechts aktivieren (oder `/rlt ml`) → Master Looter Modus an
3. Im **Raid-Tab** auf **Start Raid** klicken → Raid beginnt, alle Observer werden automatisch synchronisiert
4. Boss töten → Loot-Fenster öffnen → Items erscheinen automatisch in der **Pending Loot** Liste

---

## Zonen-Verhalten

| Zone | Addon |
|------|-------|
| Raid-Instanz | aktiv |
| Open World | aktiv |
| Dungeon / Tiefen (Delve) | versteckt |
| Arena / Schlachtfeld | versteckt |

Das Addon zeigt bzw. versteckt sich automatisch beim Betreten einer Zone — kein manueller Eingriff nötig.

---

## Master Looter Workflow

### Schritt-für-Schritt

1. **Raid starten** → Raiddaten (Name, Datum, ML-Name, Timer-Settings) werden an alle Observer gesendet
2. **Boss töten** → Loot-Fenster öffnen → Items landen in **Pending Loot**
3. **ML klickt ein Item** → Prio-Phase startet (Standard: 15 Sek., konfigurierbar)
4. **Spieler melden Prio** per Chat:

   | Eingabe | Bedeutung |
   |---------|-----------|
   | `1` | BIS – Best in Slot |
   | `2` | OS – Offspec |
   | `4` | Transmog |

5. **Prio-Phase endet** → Roll-Phase startet automatisch
6. **Spieler `/roll`en** → Ergebnisse erscheinen live im Addon (DE + EN Systemnachrichten werden erkannt)
7. **Gewinner wird ermittelt**: Prio-Tier aufsteigend, Roll-Wert absteigend, bei Gleichstand automatischer Tie-Re-Roll
8. **ML klickt Assign** → Spieler erhält die Zuweisung, Observer werden informiert
9. **Handelsfenster öffnen** → Item wird automatisch in den Trade-Slot gelegt

### Prio-Priorität beim Roll

Wenn weniger Kandidaten als Item-Kopien vorhanden: Das Addon füllt automatisch aus der nächsten Prio-Stufe auf (BIS → OS → Transmog), sodass kein Roll unnötig ist.

---

## Mehrere Kopien desselben Items (Multi-Winner Roll)

Droppt dasselbe Item mehrfach (z.B. 2× dasselbe Trinket):

- Das Addon erkennt die Anzahl automatisch — es gibt **einen** Roll-Vorgang für alle Kopien
- Gewinner werden von oben der Rangliste gefüllt (Top-N gewinnen)
- Statt "Assign" erscheint **"Assign All (N)"** — ein Klick vergibt alle Kopien gleichzeitig
- Im Raid-Tab und Log werden alle Gewinner separat eingetragen

---

## Auto-Handel

Nach der Zuweisung muss der ML das Item **manuell nicht mehr in den Trade-Slot ziehen**:

1. ML öffnet Handelsfenster mit dem Gewinner
2. Addon erkennt den Handelspartner automatisch
3. Passendes Item wird aus den Taschen des ML gesucht und automatisch in den Trade-Slot gelegt
4. Funktioniert auch bei mehreren Items pro Handelssitzung (bis zu 6 Slots)

---

## Multi-Client Synchronisation

### Observer-Sync
Alle Raid-Mitglieder mit installiertem Addon sehen in Echtzeit:
- Welches Item gerade verteilt wird
- Wer welche Prio gemeldet hat
- Roll-Ergebnisse live
- Finale Zuweisung

### Late-Joiner
Tritt ein Spieler dem Raid bei, wenn ein Raid bereits aktiv ist:
- Sein Client fragt automatisch nach dem aktuellen Raid-Zustand
- Der ML-Client antwortet mit allen Raiddaten
- Der neue Client ist sofort synchron

### ML-Übergabe
Ein Observer möchte die ML-Rolle übernehmen:
1. Observer aktiviert die ML-Checkbox im Fenster
2. Der aktuelle ML sieht ein Bestätigungs-Popup mit 15 Sekunden Zeit
3. **OK**: Rolle wird übertragen, alle Observer werden informiert
4. **Nein**: Claim wird abgelehnt, Observer bleibt Observer
5. **Timeout** (15s keine Reaktion): Übergabe erfolgt automatisch

---

## Pending Loot & Trash

| Bereich | Inhalt | Aktionen |
|---------|--------|----------|
| **Pending Loot** | Erkannte, noch nicht vergebene Items | Aktivieren (→), In Trash verschieben (✗) |
| **Trash Bin** | Verworfene Items (wiederherstellbar) | Wiederherstellen (↑), Dauerhaft löschen (🗑) |

Items im Trash sind **nicht verloren** — sie können jederzeit zurück in Pending verschoben werden.

---

## Tabs im Überblick

| Tab | Inhalt |
|-----|--------|
| **Loot** | Aktives Item · Prio-Kandidaten · Roll-Ergebnisse · Session-Log |
| **Spieler** | Roster mit Loot-Statistiken pro Spieler (Waffe, Trinket, Set, Sonstiges) |
| **Log** | Chronologisches Protokoll aller Zuweisungen der Session |
| **Raid** | Raid starten/beenden · Raid-Historie · Export |

---

## Raid-Historie & Resume

- Beendete Raids werden automatisch in der Historie gespeichert
- Alle Daten bleiben erhalten: Teilnehmer, Loot-Log, Pending, Trash
- **Resume**: Einen alten Raid aus der Liste auswählen → "Resume Raid" → alle Observer werden erneut synchronisiert
- Export einzelner Raids (aktiv oder Historie) als JSON oder CSV

---

## Export

**Format wählbar** in den Einstellungen: JSON oder CSV.

### CSV-Spalten
`RaidID · Tier · Difficulty · Track · Date · Status · Player · Item · Category · Prio · Timestamp`

- `Status`: `Assigned` oder `Trashed`
- `Track`: Champion / Hero / Mythic
- Google Sheets kompatibel (UTF-8, RFC-4180 Quotes)

### JSON
Vollständiges Snapshot-Format mit Raid-Metadaten und allen Spieler-Statistiken. Kompatibel mit dem mitgelieferten **Analyzer** (`analyzer/analyzer.html`).

---

## Analyzer

Im Ordner `analyzer/` liegt `analyzer.html` — ein eigenständiges Web-Tool für JSON-Exporte. Keine Installation, kein Backend, läuft lokal im Browser.

**Funktionen:**
- Loot-Log: vollständige Tabelle, sortierbar, filterbar
- Diagramme: Loot pro Spieler, Verteilung nach Kategorie und Prio
- Spieler-Übersicht: Loot-Zähler mit Kategorieaufschlüsselung
- Pending Loot und Trash Bin einsehbar
- Item-Namen als klickbare WoWhead-Links (farbkodiert nach Qualität)

---

## Einstellungen

| Einstellung | Optionen | Standard |
|-------------|----------|---------|
| Min. Qualität | Selten / Episch / Legendär | Episch |
| Nicht ausrüstbare Items ausblenden | Ja / Nein | Ja |
| Kategorie-Filter | Waffen / Trinkets / Set-Items / Sonstiges | alle an |
| Prio-Phase Timer | 10 / 15 / 20 / 30 / 45 / 60 Sek. | 15 Sek. |
| Roll-Phase Timer | 10 / 15 / 20 / 30 Sek. | 15 Sek. |
| Chat-Kanal | Auto / Raid / Instanz / Gruppe / Aus | Auto |
| Item-Ankündigung als Raid-Warning | Ja / Nein | Ja |
| Export-Format | JSON / CSV | JSON |

---

## Slash-Befehle

| Befehl | Beschreibung |
|--------|-------------|
| `/rlt` | Fenster öffnen/schließen |
| `/rlt ml` | Master Looter Modus umschalten |
| `/rlt start [Name]` | Raid starten (optional mit Tier-Name) |
| `/rlt reset` | Raid zurücksetzen (zweifache Bestätigung) |
| `/rlt history [Spieler]` | Letzte 10 Items eines Spielers anzeigen |
| `/rlt cleanup` | Leere/fehlerhafte Einträge aus der Historie entfernen |

### Test-Befehle (Entwicklung)

| Befehl | Beschreibung |
|--------|-------------|
| `/rlt test` | Test-Item aus dem Inventar in Pending-Loot einfügen |
| `/rlt testprio` | Prio-Phase mit Fake-Kandidaten simulieren |
| `/rlt testroll` | Roll-Phase mit Fake-Kandidaten simulieren |
| `/rlt testmulti [N]` | Multi-Item-Drop simulieren (N Kopien) |
| `/rlt testentry` | Fertigen Loot-Log-Eintrag direkt einfügen |

---

## UI

- **Dock-Tab**: Fenster dockt als schmale Leiste am linken Bildschirmrand an (`«`-Button)
- **Dock-Tab ziehbar**: Position am Rand per Drag anpassen (wird gespeichert)
- **Vollständig skalierbar**: Fenster per Drag (Titelleiste) verschieben, per Grip (unten rechts) in der Größe anpassen
- **Einstellungen**: Zahnrad-Icon öffnet Panel rechts neben dem Hauptfenster
- **Position persistent**: Fensterposition, -größe und Dock-Zustand bleiben über Sessions erhalten

---

## Technisches

- **SavedVariable**: `GuildLootDB`
- **Addon-Kommunikation**: Prefix `RequiemRLT`
- **WoW Interface**: 110100
- **Sprache**: Deutsch

---

## Lizenz

Privates Gilden-Tool – kein offizieller Release.
