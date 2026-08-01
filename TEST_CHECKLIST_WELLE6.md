# Welle 6 — In-Game Test-Checkliste

**Branch:** `feature/core-ui-split`
**TOC:** 1.0.1.20
**Was refactored wurde:** Core.lua (1578 Z.) → 4 Module in `src/core/`; UI.lua schmaler durch DropPanel + DifficultyPopup ausgliedern

---

## Vorbereitung (einmalig)

- [ ] Branch `feature/core-ui-split` ist aktiv (symlink von Repo → AddOns)
- [ ] WoW starten — **WICHTIG:** das ist der Smoke-Test, alles weitere baut darauf auf

---

## Must-Test (Solo, ~5 Min)

Wenn diese alle grün sind, sind 95% der Refactor-Risiken durch.

- [ ] **`/reload`** läuft durch — kein Lua-Error beim Login (BugSack)
- [ ] **`/reqrt`** öffnet das Hauptfenster
- [ ] **`/reqrt dbinfo`** zeigt Sessions korrekt im Chat
- [ ] **`/reqrt testsetup`** erstellt eine Test-Session → im Raid-Tab sichtbar
- [ ] **Tabs durchklicken**: Loot · Log · Raid · Roll · Player — alle öffnen, keine Errors
- [ ] **Session-Lifecycle**: New Raid Session anlegen → Close Raid Session → Resume

---

## Should-Test (Solo, ~5 Min)

- [ ] **`/reqrt testunassigned`** erstellt Unassigned-Raid → im Raid-Tab Checkbox + Assign-Flow
- [ ] **`/reqrt testpending 3`** → Session starten → "Legacy Loot"-Container erscheint
- [ ] **Drop-Panel** (Loot-Tab → ">>" Button) — Item aus Inventar reinziehen → erscheint in Pending
- [ ] **Difficulty-Popup**: `/reqrt testroll` → Assign auf TestPlayer → Diff-Popup erscheint (N/H/M-Buttons)
- [ ] **Session löschen** (aktive + inaktive) — Index wandert korrekt mit
- [ ] **Session umbenennen** — Eingabe gleicher Name blockiert mit Print

---

## Nice-to-Have (Raid nötig — beim nächsten Gilden-Raid)

- [ ] **Roster laden** beim Einladen in Gruppe/Raid
- [ ] **Boss-Encounter**: ENCOUNTER_END schreibt raidMeta für aktiven Boss
- [ ] **Loot-Pickup**: ML sieht Item in Pending
- [ ] **Trade-Window**: TRADE_SHOW wird erkannt (wenn zufällig Trade öffnet)
- [ ] **Comm**: SESSION_START/ML_ANNOUNCE zwischen ML und Observern funktioniert

---

## Wenn was kaputt ist

1. **Lua-Error beim Login** → vermutlich Load-Order-Problem in TOC. Stack-Trace in den Branch posten.
2. **Funktion fehlt (z.B. "attempt to call a nil value")** → API-Snapshot-Test sollte das eigentlich abdecken, aber check welche Funktion fehlt + in welchem Modul sie sein sollte.
3. **In-Game-Bug ohne Lua-Error** → Verhalten beschreiben + Reproschritte.

**Branch ist nicht gemergt** — jederzeit revertbar via `git reset --hard f7aec2e` (= Stand main vor Welle 6).

---

## 5-Prinzipien-Review nach Test

Nach erfolgreichem In-Game-Test machen wir nochmal eine Review-Runde gegen:

| Prinzip | Was wir prüfen |
|---------|---------------|
| **SRP** — Single Responsibility | Jedes neue Modul hat genau einen Concern? |
| **OCP** — Open/Closed | Erweiterbarkeit über neue Funktionen, nicht Modifikation? |
| **DRY** — Don't Repeat Yourself | Gibt's noch duplizierte Logik zwischen den 4 Core_*-Modulen? (z.B. `AutoTierName` ist aktuell 2× — könnte ein Util sein) |
| **KISS** — Keep It Simple | Sind die Module einfach zu lesen oder gibt's noch Spaghetti? |
| **SoC** — Separation of Concerns | Saubere Schichten DB→Session→Events→Slash, oder gibt's Querverbindungen? |

Ergebnis bestimmt ob Welle 7 nötig ist oder ob wir mergen können.

---

## Bekannte Themen für später

- **AutoTierName** ist aktuell in Core_Session.lua *und* Core_Events.lua dupliziert. Beim Review prüfen ob das in `Util.lua` gehört.
- **4 gelbe WoWUnit-Tests** (`testOnLootRollStart_AddsItem`, `testVersionWarn_In...`, `testVersionWarn_N...`) — pre-existierend, geparkt im Memory.
