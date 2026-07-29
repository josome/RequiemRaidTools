# Attendance-Tracking — Season-Roster + Matrix (Phase 1: Anzeige/Erfassung, ohne Loot-Rules)

## Context

Ziel: **Attendance-Tracking**, das langfristig die Loot-Vergabe beeinflusst. Die **Loot-Regeln
sind noch in Debatte** und ändern sich häufig — deshalb wird **zuerst nur die Erfassung + Liste**
gebaut, entkoppelt von den Regeln.

Aus der Klärung mit dem User ergibt sich das Modell (korrigiert gegenüber der ersten Annahme
„alle Daten sind schon da" — sie sind es **nicht** vollständig):

- **Season ist ein eigenes Konzept.** Roster *und* Attendance sind **season-abhängig**.
- **Zeilen-Achse = Raider-Roster aus dem WoW-Gildenroster**, gefiltert nach **einstellbaren
  Gildenrängen**. Season-abhängig.
- **Spalten-Achse = Raid-Abende, zweistufig/aufklappbar:** eingeklappt eine Spalte pro
  **Raid Session**, aufgeklappt eine Unterspalte pro **Bosskill**. Session = Vereinigung ihrer Kills.
- **Zelle:** grün = anwesend, schwarz = abwesend (später: gold = Bench).
- **Att.%** bezieht sich auf die **ganze Season** (anwesende Sessions / Sessions der Season).
- **Trial**: dauerhafter Flag am Spieler, bleibt bis manuell entfernt (typ. ~3 Sessions),
  Pflege durch die Raidleitung.

Was heute fehlt und neu gebaut wird:
1. **Season-Datenmodell** (Start/Name/Rang-Filter, aktive Season). Ersetzt die ursprünglich
   angedachte simple `settings.seasonStart`.
2. **Gildenroster-Anbindung** (WoW-API) + Rang-Filter → Zeilen-Achse.
3. **Pro-Bosskill-Historie**: heute existiert nur `currentRaid.currentKillParticipants`, das bei
   jedem Kill **überschrieben** wird ([Core_Events.lua:185](../src/core/Core_Events.lua#L185)). Für die
   aufgeklappte Ebene muss jeder Kill **persistent** in der Session abgelegt werden.

Einordnung (nicht Teil Phase 1): „Priorität" ist hier ein **Label** (BIS/OS/Transmog), kein Score
([UI_LootAnnounceWidget.lua:189](../src/ui/UI_LootAnnounceWidget.lua#L189)). Attendance kann später nur
als Anzeige/Sortierung/Ausschluss wirken.

## Scope

**Phase 1 (jetzt bauen):** Season-Konzept, Gildenroster-Roster, Pro-Bosskill-Erfassung,
Attendance-Matrix (read-only), Trial-Flag setzen/anzeigen.
**Phase 2 (später, Regeln offen):** Trial→Loot-Ausschluss, Bench-Klick, Attendance→Priorität.

---

## Phase 1a — Season-Konzept & Gildenroster

**Datenmodell** (`Core_DB.lua`, via `DeepMergeDefaults` auto-migriert, kein Schema-Bump):
- `db.seasons = { [id] = { id, name, startedAt, endedAt=nil, rankFilter={ [rankIndex]=true } } }`
- `db.activeSeasonId`
- Minimal-Verwaltung: aktive Season setzen, Start/Name, „neue Season starten" (alte `endedAt` stempeln).

**Gildenroster** (neues Modul `src/core/Core_Guild.lua`, gekapselt für Testbarkeit):
- `C_GuildInfo.GuildRoster()` anstoßen; `GetNumGuildMembers()` + `GetGuildRosterInfo(i)`
  → Name-Realm, rankIndex, classFileName.
- Rang-Namen für die Config: `GuildControlGetNumRanks` / `GuildControlGetRankName` (bzw. Fallback).
- `GL.GetSeasonRoster(seasonId)` → Menge der Raider = aktuelle Gildenmitglieder mit
  `rankFilter`-Rang **∪** alle Namen mit Attendance in der Season (damit ausgetretene Spieler in
  vergangenen Seasons sichtbar bleiben). Reine Aggregation, testbar (WoW-API hinter dünnem Wrapper).

**UI-Settings** ([UI_Settings.lua]): Abschnitt „Season & Roster" — aktive Season (Name/Start),
Rang-Checkboxen (welche Ränge zählen), Button „Neue Season".

## Phase 1b — Pro-Bosskill-Erfassung (persistent)

- In `OnEventEncounterEnd` ([Core_Events.lua:165](../src/core/Core_Events.lua#L165)) **zusätzlich** zum
  bestehenden `currentKillParticipants` (bleibt für Roll-Eligibility unverändert) einen
  **persistenten Kill-Eintrag** in die aktive Session/Container schreiben:
  `container.kills[] = { ts, encounterName, difficulty, raidID, participants={…} }`.
- `participants` = Snapshot der laufenden Raid-Teilnehmer bei diesem Kill (via bestehende
  Roster-Logik/`NormalizeName`). Damit steht pro Kill fest wer dabei war; die Session-Ebene ist die
  Vereinigung ihrer Kills → „zum Schluss weiß man wer alles teilgenommen hat".
- Bestehende `EnsureRaidMeta`-Logik bleibt unangetastet (SRP/Open-Closed): neue Zuständigkeit =
  neue Funktion `GL.RecordKillAttendance(...)`, nicht in EnsureRaidMeta hineinwachsen lassen.

## Phase 1c — Attendance-Matrix (UI, read-only)

Den **dormanten Players-Tab** ([UI.lua:369](../src/ui/UI.lua#L369) „no function yet") als
**Attendance-Tab** aktivieren (Button einblenden; Inhalt von `RefreshPlayerTab` ersetzen).

- **Datenquelle:** neues, reines Aggregat `GL.ComputeAttendance(seasonId)` →
  `nights` (Sessions der Season, je mit `kills[]`), `roster`-Zeilen (aus `GetSeasonRoster`),
  pro Spieler `present[killId]`/`present[sessionId]`, `attended`/`total` Sessions, `pct`, `class`,
  `trial`. Season-gefiltert (`startedAt ∈ Season`). Testbar.
- **Layout:** linker fixer Block **Name (klassenfarbig) | Att.% | Trial-Toggle**; rechts das
  horizontal scrollbare Zellen-Grid. Kopfzeile = Session-Spalten, **aufklappbar** → pro Bosskill
  eine Unterspalte. Zellen grün/schwarz aus `present`.
- **Frames gepoolt** via `UI.CreateFramePool` ([UI_Common.lua:96](../src/ui/UI_Common.lua#L96)) — passt
  zum Grid, vermeidet Frame-Leaks pro Refresh.
- **Trial-Toggle:** setzt `db.players[name].trial` (persistent). **Nur Flag + Anzeige** — der
  Loot-Effekt kommt in Phase 2.

## Phase 1d — JSON-Export der Tabelle

Ziel: die Attendance-Matrix als **JSON exportieren** (Copy-Paste), damit sie z.B. in einen
Discord-Channel importiert werden kann (Bot ingestiert das JSON — der Addon macht **kein**
Netzwerk, nur Text zum Kopieren).

Bestehende Infrastruktur wiederverwenden statt neu bauen:
- `GL.ExportJSON` / `GL.ExportCSV` ([Util.lua:456](../src/Util.lua#L456)) — vorhandenes Export-Muster.
- Geteilter Copy-Paste-Dialog `UI.ShowExportPopup(data, textOverride)`
  ([UI_LogTab.lua:115](../src/ui/UI_LogTab.lua#L115)) — zeigt den fertigen String in einer EditBox.
- `settings.exportFormat` (JSON|CSV) existiert bereits.

Umsetzung:
- Neue reine Funktion `GL.ExportAttendanceJSON(seasonId)` — serialisiert das Aggregat aus
  `GL.ComputeAttendance(seasonId)` in ein stabiles, Discord-freundliches Schema
  (Season-Meta + `nights` + pro Raider `{ name, class, pct, attended, total, trial, present[] }`).
  SRP: eigene Funktion, nicht `ExportJSON` (loot-fokussiert) überladen.
- **Export-Button** im Attendance-Tab → `UI.ShowExportPopup` mit dem Attendance-JSON.
- Schema kurz in `docs/` dokumentieren, damit die Discord-Seite (Bot) dagegen entwickeln kann.
- Tests in eigener/erweiterter Export-Suite (leere Season, Sonderzeichen/Escaping wie
  `Export_Test.lua`, Trial-Flag im Output, present-Mapping).

## Tests (tests-first, busted maßgeblich)

Pflicht-Paare `*_Test.lua` + `*_Test.md`, in den busted-Loader aufnehmen:
- `Guild_Test`: Rang-Filter, Roster-Aggregation (WoW-API gemockt), Namensnormalisierung.
- `Attendance_Test`: leere Season, Season-Grenze filtert alte Sessions/Kills, Spieler in n/m
  Sessions → korrekte `pct`, Kill-Vereinigung → Session-Präsenz, Roster-∪-Attendance.
- Kill-Erfassung: `RecordKillAttendance` schreibt/merged korrekt, überschreibt nichts, mehrere Kills.
- Export: `ExportAttendanceJSON` — Schema/Felder, leere Season, Escaping, Trial-Flag + present im Output.

## Verifikation

1. `busted` grün (neue Suites inkl.), bestehende Suites unverändert grün.
2. In-Game `/reload`: Season anlegen + Ränge wählen → Roster-Zeilen erscheinen; Bosskills erzeugen
   Kill-Einträge; Matrix zeigt Sessions (aufklappbar zu Kills) mit grün/schwarz + Att.%; Trial-Toggle
   persistiert über `/reload`.
3. Season-Grenze: alte Sessions fallen aus Spalten und %-Berechnung.
4. Frische/leere DB & ohne Gilde (solo): kein Lua-Error, leere Matrix.

## Phase 2 (dokumentiert, NICHT jetzt — Regeln in Debatte)

- **Trial → Loot-Ausschluss** am Gate `IsParticipant` ([Loot_Roll.lua:14](../src/loot/Loot_Roll.lua#L14));
  totes `lootEligible` kann dort scharf geschaltet werden.
- **Bench:** per-(Spieler×Abend)-Markierung (Gold-Zelle), von der Raidleitung per Klick.
- **Attendance → Priorität:** Mechanik noch offen.

## Konventionen (CLAUDE.md / Memory)

- **Kein Auto-Commit/Push** — am Ende Commit mit Message-Vorschlag anbieten.
- **TOC-Version** letzte Stelle pro Commit hochziehen; neue Version dem User nennen.
- **Eigener Branch** `feat/attendance` (thematisch getrennt von `refactor/ui-frame-pooling`),
  linear, Welle-Strategie (1a→1b→1c), Merge erst am Ende.
- Neue Module in `RequiemRaidTools.toc` (Core vor UI) eintragen. Test-`.lua`/`.md` synchron halten.
