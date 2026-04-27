# RequiemRaidTools – Todo

> **Geplant (nach PR-Merge):** Addon-Rename zu **RequiemRaidTools** (Abk. `Reqrt`) + Versionierung auf `Major.Minor.Patch.Build` (Stable) / `Major.Minor.Patch.Build-beta` (Test-Addon)

## Konvention
Erledigte Items werden mit zwei Checkboxen markiert:
`erledigt: [x] getestet: [ ]`

---

## Offen

### Spieler-Tab: Aufklappbare Loot-Historie


- [ ] **Loot-Historie aus alten Raids anzeigen** ⚠️ Konzept erforderlich — zurückgestellt
  Aufgeklappte Spieler-Rows zeigen zusätzlich Loot aus `raidHistory` (abgeschlossene Raids),
  gruppiert nach Raid mit Separator-Header (Raid-Name + Datum).
  - Scan über alle `raidHistory[i].lootLog` nach `entry.player == GL.ShortName(fullName)`
  - `itemID` überlebt SavedVariables-Reload → WoWhead-Links funktionieren auch für alte Einträge
  - Aktueller Raid zuerst, danach ältere Raids chronologisch absteigend
  - Optional: Limit auf letzte N Raids oder letzte X Items

- [x] **Bei lootverteilung mit prio 4 sollen die bevorzugt werden die das item tragen können**
        Platte aber nur platte und nicht auch stoff, leder und schwere rüstung

- [ ] NEW **Startet der ML einen Raid soll es einen broadcast an alle OBS geben, diese bekommen eine Meldung das ein Raid gestartet wurde**
      Nur Observer mit Raid-Leader oder Raid-Assist Rolle erhalten den Broadcast (nur Spieler die theoretisch ML sein könnten)
- [x] Alle Prioritäten 1-5 über Settings konfigurierbar — jeweils: aktiv/inaktiv, Kurzname, Beschreibung
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


- Readme.md aktualisieren, slash commands z.B.
 
## Bugs
- erledigt: [x] getestet: [] Wenn das Lootverteilen abgebrochen wurde dann geht bei erneuten anhandeln die automatische Verteilung nicht mehr
- erledigt: [x] getestet: [x] bei mehr als 6 items werden die ersten 6 ins handelnsfenster gelegt, beim erneuten anhandeln bleibt das fenster leer, die restlichen items müssen manuel verteilt werden


- Prio 4 erledigt: [x] getestet: [ ] Prio wird dem Observer nicht übertragen — im Session Log des Observers fehlt mit welcher Prio ein Item gewonnen wurde

- erledigt: [x] getestet: [x] auto trade funktioniert nicht zuverlässig, item klebt am mauszeiger (eventuell)
- erledigt: [x] getestet: [] Curios erscheinen beim observer in pending loot, beim ML dafür nicht
- erledigt: [x] getestet: [] der OBS bekommt keinen session loot, -> lootlog leer :(

## Lua Errors


## Erledigt

- erledigt: [x] getestet: [ ] **Settings-Sync via RAID_START** — minQuality, prioSeconds, rollSeconds werden übertragen

- erledigt: [x] getestet: [ ] **Bug: Late-Join Sync** — Client der später beitritt bekommt Raiddaten
- erledigt: [x] getestet: [ ] **Bug: Omni-Token-Erkennung** — Set-Token werden korrekt erkannt


---



