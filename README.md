# RequiemRaidTools (ReqRT)

Ein World of Warcraft Addon für Gilden-Offiziere und Raid-Leader zur strukturierten Loot-Verteilung im Raid — mit Prio-System, automatischer Roll-Auswertung und Echtzeit-Synchronisation zwischen allen Raid-Mitgliedern.

---

## Was ist RequiemRaidTools?

In WoW-Raids übernimmt der **Master Looter (ML)** die Kontrolle darüber, wer welches Item bekommt. RequiemRaidTools unterstützt den ML dabei: Items werden automatisch erkannt, Spieler melden ihren Bedarf per Chat, und das Addon wertet Rolls aus, ermittelt Gewinner und legt das Item beim nächsten Handelsfenster automatisch in die Trade-Slots.

Alle Raid-Mitglieder mit installiertem Addon sehen denselben Stand wie der ML — in Echtzeit, ohne manuellen Abgleich.

**Kernfunktionen:**
- Automatische Loot-Erkennung und Pending-Liste (nicht ausrüstbare Items werden automatisch gefiltert)
- Prio-System mit bis zu 5 frei konfigurierbaren Prio-Slots (Standard: BIS / OS / Transmog)
- Automatische `/roll`-Auswertung mit Tie-Re-Roll
- Echtzeit-Sync zwischen ML und allen Observern (auch Late-Joiner)
- Auto-Handel: Item wird beim Öffnen des Handelsfensters automatisch eingelegt
- Mehrere Kopien desselben Items in einem Roll-Vorgang
- Raid-Sessions mit Log (Boss-Quelle, Prio, Kategorie pro Item)
- Legacy Loot: Items die vor dem Session-Start droppen werden automatisch gesichert
- Export als JSON oder CSV

---

## Installation

1. Ordner `RequiemRaidTools` in `World of Warcraft/_retail_/Interface/AddOns/` kopieren
2. WoW neu starten oder `/reload` eingeben
3. `/reqrt` zum Öffnen des Fensters

---

## UI-Ebenen

Das Addon passt sich automatisch an die Rolle des Spielers im Raid an:

| Rolle | Bedingung | UI |
|---|---|---|
| **Master Looter (ML)** | ML-Checkbox aktiviert | Volles Hauptfenster, alle Funktionen aktiv |
| **Observer** | Raid-Assist oder Raid-Lead, kein ML | Hauptfenster read-only + Roll-Tab |
| **Raider** | Im Raid ohne Assist/Lead | Nur Loot-Popup + Announce-Filter |

Außerhalb eines Raids (solo, Dungeon, Party) ist der Raider-Modus inaktiv — alle Spieler sehen das volle Fenster.

---

## Master Looter Workflow

> Detaillierte Verhaltens-Referenz: [Wiki → Master Looter](https://github.com/josome/RequiemRaidTools/wiki/Masterlooter)

### Schritt-für-Schritt

1. **Session starten** → `/reqrt start [Tier-Name]` oder Button im Raid-Tab → Session-Daten werden an alle Observer gesendet
2. **Boss töten** → Loot-Fenster öffnen → Items landen in **Pending Loot**
3. **ML klickt ein Item** → Prio-Phase startet (Standard: 15 Sek.)
4. **Spieler melden Prio** per Raid-Chat (z.B. `1` für BIS, `2` für OS)
5. **Prio-Phase endet** → Roll-Phase startet automatisch für berechtigte Spieler
6. **Spieler `/roll`en** → Ergebnisse erscheinen live im Addon
7. **Gewinner wird ermittelt**: Prio-Tier aufsteigend, Roll-Wert absteigend, bei Gleichstand automatischer Tie-Re-Roll
8. **ML klickt Assign** → Spieler erhält die Zuweisung, Observer werden informiert
9. **Handelsfenster öffnen** → Item wird automatisch in den Trade-Slot gelegt

### Prio-System

Bis zu 5 Prio-Slots, frei konfigurierbar im Settings-Panel. Standard:

| Slot | Kürzel | Bedeutung |
|------|--------|-----------|
| 1 | BIS | Best in Slot |
| 2 | OS | Off-Spec |
| 4 | Tmog | Transmog |

Inaktive Slots werden ausgegraut und sind nicht wählbar. Prio-Namen werden beim Session-Start an alle Observer und Raider übertragen.

---

## Raid-Sessions

Loot wird in **Raid Sessions** erfasst. Eine Session umfasst einen oder mehrere Raids (Boss-Kills) und bleibt erhalten bis sie manuell geschlossen wird.

- **Start**: Session-Start überträgt Metadaten und Prio-Konfiguration an alle
- **Close / Resume**: Geschlossene Sessions können fortgesetzt werden — alle Observer werden erneut synchronisiert
- **Legacy Loot**: Droppt Loot bevor eine Session gestartet wurde, legt das Addon automatisch eine geschlossene "Legacy"-Session an und sichert die Items darin
- **Merge**: Eine Legacy-Session kann per Button in die aktive Session gemergt werden

---

## Mehrere Kopien desselben Items

Droppt dasselbe Item mehrfach (z.B. 2× dasselbe Trinket):

- Das Addon erkennt die Anzahl automatisch — ein Roll-Vorgang für alle Kopien
- Top-N der Rangliste gewinnen
- Statt "Assign" erscheint **"Assign All (N)"** — ein Klick vergibt alle Kopien gleichzeitig

---

## Auto-Handel

Nach der Zuweisung zieht der ML das Item nicht mehr manuell:

1. ML öffnet Handelsfenster mit dem Gewinner
2. Addon erkennt den Handelspartner automatisch (auch Cross-Realm)
3. Passendes Item wird aus den Taschen des ML gesucht und automatisch in den Trade-Slot gelegt
4. Funktioniert auch bei mehreren Items pro Handelssitzung (bis zu 6 Slots)

---

## Observer & Raider

> Vollständige Dokumentation: [Wiki → Raider Mode](https://github.com/josome/RequiemRaidTools/wiki/Raider-Mode)

### Observer (Raid-Assist / Raid-Lead)
- Sieht das volle Hauptfenster im read-only Modus
- Erhält den **Roll-Tab**: identischer Inhalt wie das Raider-Popup (Item, Prio-Buttons, Roll-Button, Gewinner-Anzeige, Announce-Filter)
- Wird automatisch synchronisiert wenn der ML eine Session startet oder nach einem Boss-Kill

### Raider (ohne Assist/Lead)
- Sieht ein kompaktes **Loot-Popup** wenn der ML ein Item announced
- Prio-Buttons zeigen die konfigurierten Slot-Namen der aktuellen Session
- Roll-Button wird aktiv wenn der ML die Roll-Phase startet und der Raider berechtigt ist
- **Announce-Filter**: steuert für welche Item-Typen das Popup erscheint (Cloth, Leather, Trinkets, Rings …)
- Minimap-Button: Links = Popup, Rechts = Hauptfenster

### Late-Joiner
Tritt ein Spieler dem Raid bei wenn eine Session bereits läuft, fragt sein Client automatisch nach dem aktuellen Stand. Der ML antwortet mit allen Session-Daten — der neue Client ist sofort synchron.

---

## ML-Übergabe

1. Observer aktiviert die ML-Checkbox
2. Aktueller ML sieht ein Bestätigungs-Popup (15 Sek.)
3. **OK** → Rolle übertragen, alle Observer informiert
4. **Nein** → Claim abgelehnt
5. **Timeout** (15s) → Übergabe erfolgt automatisch

---

## Pending Loot & Trash

| Bereich | Inhalt | Aktionen |
|---------|--------|----------|
| **Pending Loot** | Erkannte, noch nicht vergebene Items | Aktivieren, In Trash verschieben |
| **Trash Bin** | Verworfene Items (wiederherstellbar) | Wiederherstellen, Dauerhaft löschen |

Items im Trash sind nicht verloren — sie können jederzeit zurück in Pending verschoben werden.

> Items aus dem Inventar können per **Drag & Drop** auf den `>>` Button manuell zur Pending List hinzugefügt werden.

---

## Tabs im Überblick

| Tab | Inhalt |
|-----|--------|
| **Loot** | Aktives Item · Prio-Kandidaten · Roll-Ergebnisse |
| **Log** | Chronologisches Protokoll aller Zuweisungen · Export |
| **Raid** | Session starten/schließen · Session-Liste · Merge |
| **Roll** | Roll-Tab für Observer (Item, Prio, Roll, Gewinner) |
| **Spieler** | Roster mit Loot-Statistiken pro Spieler |

---

## Export

**Format wählbar** in den Einstellungen: JSON oder CSV.

### CSV-Spalten
`RaidID · Tier · Difficulty · Track · Date · Status · Player · Item · Category · Prio · Timestamp`

### JSON
Vollständiges Snapshot-Format mit Session-Metadaten und allen Spieler-Statistiken. Kompatibel mit dem mitgelieferten **Analyzer** (`analyzer/analyzer.html`).

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

| Einstellung | Standard |
|-------------|---------|
| Min. Qualität | Episch |
| Nicht ausrüstbare Items ausblenden | Ja |
| Prio-Phase Timer | 15 Sek. |
| Roll-Phase Timer | 15 Sek. |
| Chat-Kanal | Auto |
| Item-Ankündigung als Raid-Warning | Ja |
| Gewinner per Whisper benachrichtigen | Ja |
| Export-Format | JSON |

---

## Slash-Befehle

| Befehl | Beschreibung |
|--------|-------------|
| `/reqrt` | Fenster öffnen/schließen |
| `/reqrt ml` | Master Looter Modus umschalten |
| `/reqrt start [Tier]` | Neue Raid-Session starten |
| `/reqrt history [Spieler]` | Letzte Loot-Einträge eines Spielers |
| `/reqrt reset` | Session zurücksetzen (zweifache Bestätigung) |
| `/reqrt backup` | Datenbank sichern |
| `/reqrt restore` | Datenbank aus Backup wiederherstellen |
| `/reqrt cleanup` | Leere/fehlerhafte Einträge entfernen |
| `/reqrt dbinfo` | Datenbankinfo anzeigen |

---

## Technisches

- **SavedVariable**: `GuildLootDB`, `GuildLootDBBackup`
- **Addon-Kommunikation**: Prefix `RequiemRLT`, Trennzeichen Tab `\t` — [Wiki → COMM-Protokoll](https://github.com/josome/RequiemRaidTools/wiki/COMM-Protokoll)
- **WoW Interface**: 120005 (Midnight 12.0.5)
- **Sprache**: Deutsch

---

## Lizenz

Privates Gilden-Tool – kein offizieller Release.
