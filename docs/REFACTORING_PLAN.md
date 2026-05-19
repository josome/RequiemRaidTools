# Refactoring-Plan & Risikobewertung

**Stand:** 2026-05-19
**Branch:** `feature/util-tests` (Test-Vorbereitung + Paket-A Quick Wins A5/A2/A3 umgesetzt)
**Test-Status:** 119 busted-Tests grün (lokal + CI), 10 pending marks gelistet
**TOC:** 1.0.1.1
**Anwender-Tests (in-game):** noch offen — siehe Abschnitt 7

## Fortschritt

| Paket | Status | Commit |
|-------|--------|--------|
| **Tests-Vorbereitung** | ✅ umgesetzt | `b617fa7` |
| **Pending-Marker-Sichtbarkeit** | ✅ umgesetzt | `1e938c3` |
| **A5** GL.ShortName Bug-Fix | ✅ umgesetzt | `56ccb2d` (Merge `3b805f5`) |
| **A2** GL.ShowItemTooltip | ✅ umgesetzt (10 Call-Sites zusammengeführt) | `b280e9a` (Merge `7ef5ea1`) |
| **A3** GL.FindSessionByID | ✅ umgesetzt (2 Lookups zusammengeführt) | `2ab4bf7` (Merge `ef24806`) |
| **A4** getSessionPriorityConfig | ⏳ offen | — |
| **A1** UI-Helpers (Backdrop, FontString, COLORS) | ⏳ offen | — |
| **B1** FILTER_RULES-Tabelle | ⏳ offen | — |
| **B2** setMiniTabState | ⏳ offen | — |
| **B3** Version-Check-Tabelle | ⏳ offen | — |
| **B4** Tab-Registry | ⏳ offen | — |
| **C1** GL.DeleteSession | ⏳ offen | — |
| **C2** GL.MigratePendingLoot | ⏳ offen | — |
| **C3** BuildRaidPanel zerlegen | ⏳ offen | — |
| **C4** commLoopback-Filter verschieben | ⏳ offen | — |
| **D1** Core.lua aufspalten | ⏳ offen | — |
| **D2** UI.lua entlasten | ⏳ offen | — |

---

## 1. Kontext

Codebase-Review im Mai 2026 hat in folgenden Modulen Schwachstellen, Duplikate und Verletzungen der Design-Prinzipien KISS, DRY, Open/Closed und Separation of Concerns identifiziert:

| Modul | Zeilen | Hauptproblem |
|-------|-------:|--------------|
| `src/Core.lua` | ~1413 | God-Module: DB, Events, Comm, Slash, Orchestrierung vermischt |
| `src/ui/UI_RaidTab.lua` | ~878 | UI-Render mutiert direkt `GuildLootDB` |
| `src/ui/UI_LootTab.lua` | ~783 | Backdrop-/FontString-Boilerplate, Mini-Tab-Duplikate |
| `src/ui/UI.lua` | ~771 | Mehrere Concerns (Framework, Tabs, Settings, Sound, Filter) |
| `src/loot/Loot_Assign.lua` | ~497 | Session-Lookup dupliziert mit `Comm.lua` |

Ziel des Plans: Schrittweise Verbesserungen in kleinen, getesteten Paketen — kein großer Wurf, sondern messbare Reduktion von Duplikation, Modulgrößen und gefährlichen Konzern-Vermischungen.

---

## 2. Befunde

### 2.1 DRY — Duplikate

**Hart kopierter Code:**
- Backdrop-Block `bgFile=DialogFrame…, edgeFile=UI-Tooltip-Border…` 6× wörtlich in `src/ui/UI_RaidTab.lua:205-210, 226-230, 860-864` und `src/ui/UI.lua:88-92, 331-335, 483-487`.
- Mini-Tab Select/Deselect — zwei nahezu identische Funktionen in `src/ui/UI_LootTab.lua:22-47`.
- `GameTooltip:SetHyperlink`-Sequenz 7× ohne Wrapper (`UI_LootTab.lua:222, 246, 467, 496, 830, 838`, `UI_LogTab.lua:286`).
- `CreateFontString(nil, "OVERLAY", "GameFontNormal…")` >20× ohne Factory.
- Hover-Color-Pattern (`SetColorTexture(1, 0.8, 0, 0.15) / (1, 1, 1, 0.04)`) mehrfach in `UI_RaidTab.lua:440, 442, 444, 446, 510-514, 936-937`.
- `for _, c in ipairs(GuildLootDB.raidContainers)`-Schleife mit gleicher Form in `Core.lua:115-120, 153, 1476`.
- Chat-Channel-Routing als if/elseif-Kette in `Core.lua:542-551`.
- Print-Prefix `[ReqRT]` mit unterschiedlichen Farbcodes in `Comm.lua:336, 350, 359, 366`, `Core.lua:531`.

**Magic Strings / Numbers:**

| Wert | Vorkommen | Vorschlag |
|------|-----------|-----------|
| `"RAID"/"PARTY"/"INSTANCE_CHAT"/"AUTO"/"OFF"` | `Core.lua`, `Comm.lua`, `UI_Settings.lua` | `CHAT_CHANNELS`-Konstante |
| `0.4, 0.4, 0.4, 1` (Divider) | 6× UI-Module | `COLORS.DIVIDER` |
| `0, 0.4, 0.05, 0.22` (Awarded-BG) | 4× `UI_RaidTab.lua` | `COLORS.BG_AWARDED` |
| `1, 0.8, 0, 0.15` (Hover) | 4× `UI_RaidTab.lua` | `COLORS.HIGHLIGHT_HOVER` |
| `[ReqRT]` + Farb-Prefix | `Test.lua`, `Core.lua`, `Comm.lua` | einheitlicher `GL.Print()` |
| Session-Lookup nach ID | `Loot_Assign.lua:505-509`, `Comm.lua:278-284` | `GL.FindSessionByID()` |

### 2.2 SRP & Separation of Concerns

**God-Module:**
- `src/Core.lua` (1413 Z.) — DB-Migration, Session-/Raid-Lifecycle, WoW-Event-Handler (`ENCOUNTER_END`, `LOOT_OPENED`, `CHAT_MSG_ADDON`), Slash-Commands, Roster-Sync, ML-Comm, UI-Refresh-Aufrufe. **Splitvorschlag:** `Core_DB.lua`, `Core_Events.lua`, `Core_Session.lua`, `Core_Slash.lua`.
- `src/ui/UI.lua` (771 Z.) — Framework-Setup, Tab-Routing, Settings-Plumbing, Sound, Popup-Filtering. Mindestens Sound + Filter ausgliedern.
- `src/ui/UI_RaidTab.lua` (878 Z.) — Render + direkte DB-Mutation.

**Konkrete Mischungen:**
1. Delete-Button-Closure in `UI_RaidTab.lua:149-168` ruft `table.remove(GuildLootDB.raidContainers, ci)` direkt — sollte über `GL.DeleteSession(ci)` laufen.
2. `GL.StartContainer` (`Core.lua:296`) macht in 60 Z. Session-Erstellung + orphan-Loot-Migration (`Core.lua:318-334`) + Broadcast + UI-Refresh.
3. `GL.StartRaid` (`Core.lua:715`) kombiniert DB-Set, Roster-Laden, ML-Ankündigung, Meta-Erzeugen und UI-Refresh.
4. `UI.BuildRaidPanel` (`UI_RaidTab.lua:41`) > 210 Z. monolithisch.
5. `Comm.OnMessage` (`Comm.lua:328`) prüft `commLoopback` mitten im Dispatch.

### 2.3 KISS-Verletzungen

1. Verschachtelter Prio-Config-Lookup 2× identisch in `Util.lua:150-162` und `:166-176`.
2. Mini-Tab-Setter als zwei Funktionen in `UI_LootTab.lua:22-47` statt parametrisiert.
3. `Loot.ResolvePendingMeta` (`Loot_Assign.lua:42-72`) setzt redundant `raidID/difficulty/sessionID` mehrfach.
4. `PopupFilterMatches` (`Util.lua:241-275`) als if-Kette.
5. Subtiler Bug in `GL.ShortName` (`Util.lua:325`): `return (ok and name) or fullName` fällt bei `ok=true, name=nil` ungewollt auf `fullName` zurück.

### 2.4 Open/Closed-Verletzungen

1. `GL.PopupFilterMatches` (`Util.lua:241-275`) — neue Kategorie = neue `elseif`-Zeile.
2. Version-Vergleich in `Comm.OnMessage` (`Comm.lua:348-371`) — 3 hartcodierte Blöcke.
3. Session-Lookup nach ID dupliziert.
4. Filter-Kategorien hartcodiert in `Core.lua:50-55`.
5. Tab-Konstanten in `UI.lua:14-23` als nummerierte Konstanten.

### 2.5 Weitere Schwachstellen

- Fehlende Bounds-Checks auf `GuildLootDB.activeContainerIdx` (`Util.lua:150-176`).
- Race-Risiko in `getRaidIDForCurrentLoot` (`Loot.lua:27-43`).
- Ungenutzte UI-State-Variablen in `UI_LootTab.lua:92`.
- String-Allokation `(payload .. SEP):gmatch(...)` in `Comm.lua:373-382` im Hot-Path.

---

## 3. Refactoring-Pakete

### Paket A — Quick Wins (geringes Risiko, hoher Lesegewinn)
- **A1:** ⏳ `src/ui/UI_Common.lua` neu: `UI.CreateBackdropFrame()`, `UI.CreateGameFontString()`, `UI.COLORS`, `UI.BACKDROPS`. Ersetzt 6× Backdrop, >20× FontString, Color-Magic.
- **A2:** ✅ `GL.ShowItemTooltip(link, frame, anchor)` in `Util.lua` — 10 Call-Sites umgestellt (`b280e9a`).
- **A3:** ✅ `GL.FindSessionByID(id)` in `Util.lua` — Lookups in `Comm.HandleLootTrash` und `Loot.OnCommAssign` zusammengeführt (`2ab4bf7`).
- **A4:** ⏳ `getSessionPriorityConfig()` (lokal in `Util.lua`) — beide Lookups aufräumen.
- **A5:** ✅ `GL.ShortName`-Fallback-Bug gefixt (`Util.lua:325`, jetzt explizites if-else statt `(ok and name) or fullName`) (`56ccb2d`).

### Paket B — Open/Closed-Aufräumarbeiten
- **B1:** `FILTER_RULES`-Tabelle für `PopupFilterMatches`.
- **B2:** `setMiniTabState(btn, selected)` ersetzt Doppel-Funktionen.
- **B3:** Version-Check-Tabelle in `Comm.OnMessage`.
- **B4:** Tab-Registry in `UI.lua` (Liste + Lookup statt nummerierte Konstanten).

### Paket C — SRP / Concerns trennen (mittel)
- **C1:** `GL.DeleteSession(ci)` extrahieren, UI-Closure umstellen.
- **C2:** `GL.MigratePendingLoot()` aus `GL.StartContainer` extrahieren.
- **C3:** `BuildRaidPanel` in `BuildRaidList()` + `BuildRaidDetail()` + `BuildRaidActions()` zerlegen.
- **C4:** `commLoopback`-Check aus `Comm.OnMessage` raus in die Registrierung.

### Paket D — Größere Strukturarbeit (Refactoring-Branch, separat planen)
- **D1:** `Core.lua` aufspalten in `Core_DB.lua` / `Core_Events.lua` / `Core_Session.lua` / `Core_Slash.lua`.
- **D2:** `UI.lua` Slimming (Sound, Popup-Filter ausgliedern).

---

## 4. Test-Status

**Externer Runner:** `busted spec/reqrt_spec.lua` (GitHub Actions, lokal via scoop-luarocks).
**Stand:** 119 Tests grün, 0 failures, 0 errors, 10 Pending-Marks gelistet (A1×2, B4×1, C1×4, C2×3).

### 4.1 Bestehende Coverage

| Suite | Tests | Bereich |
|-------|------:|---------|
| `ReqRT.Probe` | 1 | Smoke-Test |
| `ReqRT.Comm` | 24 | Roundtrips, ML-Guards, Self-Filter, Version-Checks |
| `ReqRT.Assign` | 4 | LootLog, Pending-Removal, Player-Record, Comm-Observer |
| `ReqRT.Session` | 30 | Lifecycle, Resume, LateJoiner, LegacySession, Merge, DeleteSession (pending), MigratePendingLoot (pending) |
| `ReqRT.Trade` | 8 | Name-Lookup, 6-Item-Limit, Success/Cancel |
| `ReqRT.Filter` | 15 | Slot/Rüstung/Stale + Unknown-Category + Parametrisiert |
| `ReqRT.Util` | 21 | ShortName, GetActivePrios/PrioLabel, FindSessionByID (pending), ShowItemTooltip (pending), UI-Common (pending), Tab-Registry (pending) |
| `ReqRT.API` | 15 | API-Snapshot für D1-Load-Order-Schutz |

### 4.2 Tests pro Refactoring-Paket

| Paket | Tests (busted) | Status |
|-------|---------------:|--------|
| A1 UI-Helper | 2 (Smoke) | ⏳ pending bis `UI.COLORS` / `UI.BACKDROPS` existieren |
| **A2 ShowItemTooltip** | 1 | ✅ **aktiv, grün** |
| **A3 FindSessionByID** | 4 | ✅ **aktiv, grün** |
| A4 PriorityConfig | 8 | **aktiv** (gegen `GetActivePrios`/`GetPrioLabel`) |
| A5 ShortName-Bug | 6 | **aktiv** (fixiert Bestand inkl. Edge-Case `-Realm`) |
| B1 FILTER_RULES | 2 | **aktiv** (Unknown-Category + Parametrisiert) |
| B2 Mini-Tab | — | UI, manuell |
| B3 Version-Checks | 5 | **aktiv** (incompatible, older, newer, cooldown, no-version) |
| B4 Tab-Registry | 1 | pending bis `UI.TABS` existiert |
| C1 DeleteSession | 4 | pending bis `GL.DeleteSession` existiert |
| C2 MigratePendingLoot | 3 | pending bis `GL.MigratePendingLoot` existiert (creates / idempotent / empty) |
| C3 BuildRaidPanel | — | UI, manuell |
| C4 commLoopback | 1 (+ bestehende) | **aktiv** (Dispatch-Stops-Completely) |
| D1 Core.lua split | 15 (Snapshot) | **aktiv** (alle erwarteten `GuildLoot.*`-Funktionen geprüft) |
| D2 UI.lua split | — | UI, manuell |

**Mechanik der Pending-Tests:** Tests gaten sich selbst über `type(GuildLoot.X) == "function"` bzw. `if not GL.X then MarkPending(...); return end`. Solange die Funktion nicht existiert, läuft der Test als no-op-Success durch — sobald die Funktion da ist, aktiviert er sich automatisch. Kein CI-Rot bei TDD-Vorlauf.

---

## 5. Risikobewertung

Skala: 🟢 niedrig · 🟡 mittel · 🟠 mittel-hoch · 🔴 hoch

### 5.1 Risiko-Matrix mit Test-Stand

| Paket | Risiko vorher | Risiko jetzt | Begründung (Δ) |
|-------|:---:|:---:|------------|
| A1 UI-Helper | 🟢 | 🟢 | UI nicht im Loader; Pending-Smoke aktiviert sich nach Implementierung |
| A2 ShowItemTooltip | 🟢 | 🟢 | Test vorbereitet, aktiviert sich bei Implementierung |
| A3 FindSessionByID | 🟢 | 🟢 | 4 Tests pending-geguarded — Vertrag steht |
| A4 PriorityConfig | 🟡 | **🟢** | 8 Tests fixieren `GetActivePrios`/`GetPrioLabel` über alle Lookup-Pfade |
| A5 ShortName-Bug | 🟢 | 🟢 | 6 Tests fixieren Bestandsverhalten inkl. Edge-Cases |
| B1 FILTER_RULES | 🟡 | **🟢** | 15 Filter-Tests inkl. Parametrisiertem Snapshot |
| B2 Mini-Tab | 🟢 | 🟢 | UI, rein visuell |
| B3 Version-Checks | 🟡 | **🟢** | 5 explizite Cases: incompatible, older, newer, cooldown, no-version-prefix |
| B4 Tab-Registry | 🟡 | 🟡 | UI-Smoke pending, sonst unverändert |
| C1 DeleteSession | 🟠 | **🟡** | 4 Tests als TDD-Vertrag (Index-Korrektur, Active-Idx-Null, Out-of-Bounds) |
| C2 MigratePendingLoot | 🟠 | **🟡** | 3 Direkt-Tests + 3 bestehende Legacy-Session-Tests in Session_Test |
| C3 BuildRaidPanel | 🟡 | 🟡 | UI, manuell |
| C4 commLoopback | 🟢 | 🟢 | + expliziter Dispatch-Stops-Completely-Test |
| D1 Core.lua split | 🔴 | **🟠** | API-Snapshot fängt 15 zentrale Funktionen ab — Load-Order-Brüche detektierbar |
| D2 UI.lua split | 🟠 | 🟠 | UI, manuell |

### 5.2 Risiko-Achsen

- **Test-Abdeckung gut:** Comm, Filter, Session, Assign — Refactorings dort werden durch automatische Tests rückversichert.
- **UI bleibt blind:** A1, B2, B4, C3, D2 brauchen manuelle Klick-Verifikation (UI-Module nicht im Standalone-Loader).
- **Echtes Datenrisiko:** nur C1 (Session-Delete) und C2 (PendingLoot-Migration) — beide mit TDD-Verträgen abgesichert, aber sollten zusätzlich mit DB-Backup-Snapshot vor Test im echten Client laufen.
- **Load-Order-Risiko (D1):** Tests fangen Load-Order-Fehler erst nach erfolgreichem Load. API-Snapshot reduziert das Risiko, aber zirkuläre Abhängigkeiten zwischen den neuen Modulen können erst beim Login auffallen.

### 5.3 Mitigation pro Risiko-Stufe

| Stufe | Mitigation |
|-------|-----------|
| 🟢 | busted-Suite vor und nach Änderung grün, ein `/reload` im Client. |
| 🟡 | busted + `/reload` + manuelle Klick-Checkliste der betroffenen UI-Pfade. |
| 🟠 | Eigener Feature-Branch, kleine Commits, `/reload` nach jedem Commit, DB-Backup vor Test. |
| 🔴 | Eigener Refactoring-Branch (CLAUDE.md), Inkremental-Commits, Login-Test, Backup, Pause vor Merge. |

---

## 6. Empfohlene Reihenfolge

1. ~~**A5 zuerst** — echter Bug-Fix, isoliert, 1 Zeile, Tests vorhanden.~~ ✅
2. ~~**A2 + A3** — klare Wrapper, wenige Call-Sites, Tests aktivieren sich automatisch.~~ ✅
3. **A1 + A4** — mehr Call-Sites; A1 braucht visuelle Sichtprüfung. ← **nächstes**
4. **Paket B komplett** — von Tests gestützt, klarer Erweiterbarkeits-Gewinn.
5. **C1 + C2** mit DB-Backup-Snapshot und auf eigenem Branch.
6. **C3** als reines UI-Refactoring auf Branch.
7. **D1 / D2** nur wenn echter Schmerz da ist; D1 als eigener Refactoring-Branch.

---

## 7. Manuelle Verifikations-Checkliste (UI-Pakete)

### 7.1 Offene Anwender-Tests für aktuell umgesetzte Pakete (A5, A2, A3)

**Status: noch nicht durchgeführt.** Vor weiteren Refactorings sollten diese Punkte in-game (`/reload` auf aktuellem `feature/util-tests`) verifiziert werden:

- [ ] **A5 ShortName** — Namen mit Realm-Suffix (z.B. `Aedalena-Malfurion`) erscheinen weiter korrekt als Kurzname in Chat-Output, Roll-Tab, Loot-Log und Player-Popup.
- [ ] **A2 ShowItemTooltip** — Tooltips erscheinen beim Hover über:
  - Pending-Loot-Icons + Link-Buttons (Loot-Tab)
  - Aktiv-Item-Icon + Hover-Bereich (Loot-Tab)
  - Loot-Log-Icons + Item-Hover (Loot-Tab History-Section)
  - Item-Links im Log-Tab
  - LootAnnounce-Widget (Icon + Name)
  - Window-Header-Item-Buttons
- [ ] **A3 FindSessionByID** — ML weist Item zu → Observer schreibt in **die per sessionID gestempelte Session**, nicht in die aktuell aktive (Test: zwei Sessions parallel anlegen, ML in Session 1 zuweisen, dann Session 2 aktivieren, Observer-Schreiben prüfen).
- [ ] **Generell** — kein Lua-Error beim Login (BugSack / BugGrabber falls verfügbar).

### 7.2 Zukünftige Pakete

Pflicht für A1, B2, B4, C3, D2 — keine Auto-Tests möglich:

1. Main-Frame öffnen, alle Tabs einmal anklicken: **Loot · Log · Raid · Roll · Player · Settings**.
2. Raid-Session anlegen, zweite Session anlegen, zwischen ihnen wechseln.
3. Item zuweisen → Roll-Tab-Anzeige prüfen.
4. Player-Popup öffnen (im Raid mit Test-Item via `/reqrt test`).
5. Settings-Tab: Filter umstellen, Loopback toggeln.
6. Minimap-Button + Dock-Icon klicken.
7. `/reload` und prüfen, dass kein Lua-Error beim Login erscheint.

---

## 8. Kritische Dateien

- `src/Util.lua` — Helper-Heimat für A2/A3/A4/A5
- `src/ui/UI.lua` + neues `src/ui/UI_Common.lua` — A1
- `src/Core.lua` — C1/C2, später D1
- `src/ui/UI_RaidTab.lua` — C1/C3
- `src/loot/Loot_Assign.lua` + `src/Comm.lua` — A3, B3, C4
- `src/ui/UI_LootTab.lua` — B2

### Test-Dateien

- `src/tests/Util_Test.lua` — A2/A3/A4/A5/A1/B4
- `src/tests/Filter_Test.lua` — B1
- `src/tests/Comm_Test.lua` — B3/C4
- `src/tests/Session_Test.lua` — C1/C2
- `spec/reqrt_spec.lua` — D1 API-Snapshot

---

## 9. Test ausführen

**Lokal (Windows, scoop):**
```
/c/Users/joern/scoop/apps/luarocks/current/rocks/bin/busted.bat spec/reqrt_spec.lua
```

**CI:** GitHub Actions `.github/workflows/tests.yml` — läuft auf push & pull_request.

**In-Game:** WoWUnit-Suiten (`ReqRT.Comm`, `ReqRT.Session`, ...) registrieren sich automatisch bei `/reload` wenn `devMode` aktiv (`/reqrt devmode`).
