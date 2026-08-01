# Verifikationsliste — Loot-Popup Reopen-Fix

**Branch:** `fix/popup-empty-on-reopen` · **TOC:** 1.0.1.23
**Betrifft:** Loot-Popup bei Raider/Observer — Wiederöffnen während Loot aktiv +
Auto-Reopen bei Roll-Start.

## Setup

- [ ] Beide Clients auf dem Branch (`/reload`, TOC zeigt `v1.0.1.23`).
- [ ] Gruppe/Raid mit 2 Chars: **ML** (Master-Looter-Checkbox an) + **Raider**
      (kein Assist/Lead → Raider-Mode, nur Popup).
- [ ] Beim Raider: Popup-Checkbox **Enable** an, **Sound** beliebig.
- [ ] Aktive Raid Session beim ML (`New Session`).
- [ ] Ein Test-Item bereit (oder ML `/reqrt test` zum Einspeisen).

## Kern-Szenarien

### 1 — Normalfall (keine Regression)
- [ ] ML released Item → Popup erscheint beim Raider mit Item + Prio-Buttons.
- [ ] Raider postet Prio → ML startet Roll → Roll-Button wird aktiv.
- [ ] Raider rollt → ML weist zu → Popup verschwindet sauber.

### 2 — Prio-Phase: schließen & wieder öffnen (der gemeldete Bug)
- [ ] ML released Item → Popup beim Raider.
- [ ] Raider klickt **✕**.
- [ ] Raider öffnet erneut (MMB-Linksklick / `/reqrt popup`).
- [ ] **Erwartet:** Item + Prio-Buttons wieder sichtbar (NICHT leer).
- [ ] Prio lässt sich posten.

### 3 — Auto-Reopen bei Roll-Start
- [ ] ML released Item → Raider postet Prio → Raider klickt **✕**.
- [ ] ML startet **Roll**.
- [ ] **Erwartet:** Popup springt beim Raider **automatisch** wieder auf,
      Roll-Button aktiv.
- [ ] Roll funktioniert.

### 4 — Roll-Phase: manuell wieder öffnen (noch nicht gerollt)
- [ ] Wie 3, aber statt aufs Auto-Popup zu warten: Raider öffnet selbst
      (MMB / `/reqrt popup`) nachdem Roll gestartet ist.
- [ ] **Erwartet:** Item sichtbar, Roll-Button aktiv.

### 5 — Schon gerollt → leer
- [ ] Roll läuft, Raider **rollt** (Button zeigt „Rolled").
- [ ] Raider klickt **✕** → öffnet erneut, *während Item noch aussteht*.
- [ ] **Erwartet:** Popup ist **leer** (nur Announce-Filter, kein Item).

### 6 — Tie-Re-Roll
- [ ] Nach 5: ML startet einen **Re-Roll** (erneuter Roll fürs selbe Item).
- [ ] **Erwartet:** Popup springt auf, Roll-Button wieder aktiv
      (iRolled wurde zurückgesetzt).

### 7 — Nach Verteilung kein Geister-Item
- [ ] ML weist das Item zu (ASSIGN).
- [ ] Raider öffnet erneut.
- [ ] **Erwartet:** leer (Filter-Only), kein altes Item.

## Rand- & Guard-Fälle

### 8 — Nicht interessiert (keine Prio)
- [ ] ML released Item → Raider postet **keine** Prio → schließt **✕**.
- [ ] ML startet Roll.
- [ ] **Erwartet:** **kein** Auto-Popup (nicht eligible).
- [ ] Manuelles Öffnen zeigt das Item, Roll-Button bleibt **aus**.

### 9 — popupEnabled = false
- [ ] Raider: Checkbox **Enable** im Popup **aus**.
- [ ] ML released Item + startet Roll.
- [ ] **Erwartet:** **kein** Auto-Popup (Guard greift).
- [ ] `/reqrt popup` öffnet trotzdem manuell (zeigt Item, wenn aktiv).

### 10 — Gewinner-Anzeige trotz geschlossenem Popup
- [ ] Raider schließt Popup → ML weist das Item **dem Raider** zu.
- [ ] **Erwartet:** „You receive: …"-Anzeige erscheint, schließt nach ~6 s;
      danach Reopen → leer.

### 11 — Observer (volles Fenster, nicht Raider-Mode)
- [ ] Zweiter Tester mit Assist/Lead (Observer) → Roll-Tab vorhanden.
- [ ] Popup-Verhalten + Roll-Tab konsistent (kein Doppel-/Geisterzustand).

## Reopen-Pfade einzeln prüfen

- [ ] **MMB-Linksklick** (Raider-Mode) öffnet korrekt.
- [ ] **`/reqrt popup`** öffnet korrekt.
- [ ] **Undock** (Andock-Tab anklicken im Raider-Mode) öffnet korrekt.

## Abschluss

- [ ] Kein Lua-Error in der Konsole bei allen Schritten.
- [ ] busted lokal grün: `busted spec/reqrt_spec.lua` (PowerShell,
      `$env:LUA_PATH=""`) → 202/0/0.
- [ ] Ergebnis im PR / an Claude zurückmelden.
