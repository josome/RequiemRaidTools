# Frame Testdokumentation

**Datei:** `src/tests/Frame_Test.lua`
**Framework:** busted (`spec/reqrt_spec.lua`)
**Suite-Name:** `ReqRT.Frame`

---

## Testziel

Unit-Tests für die gemeinsame Fenster-Positionierung:

- `UI.ClampFrameOffsets` (`src/ui/UI_Common.lua`) — hält gespeicherte Positionen innerhalb des Bildschirms
- `GL.MigrateFramePositions` (`src/core/Core_DB.lua`) — überführt die alten Einzelfelder `settings.framePos` / `settings.frameSize` des Hauptfensters in die gemeinsame Tabelle `settings.framePositions`

Alle verschiebbaren Fenster (Hauptfenster, Loot-Popup, Export-Popup) teilen sich diesen Code; das Dock-Tab bewusst nicht.

---

## Teststrategie

Die gesamte Bildschirm-Arithmetik steckt in `ClampFrameOffsets`, einer reinen Funktion aus sechs Zahlen ohne jeden Frame-Zugriff — dieselbe Trennung wie bei `UI.CreateFramePool`, wo alles Frame-Berührende in den Callbacks lebt.

Für die Speicher-Logik reicht das aber nicht: der erste Fehler dieser Umstellung steckte nicht in der Rechnung, sondern darin, **wann** gespeichert wird. Die WoW-Stubs (`tests/standalone/wow_stubs.lua`) wurden dafür um das Nötigste erweitert:

- Frames sind nach `CreateFrame` **sichtbar**, wie in WoW — genau daran hing der Bug
- `Show`/`Hide` lösen `OnShow`/`OnHide` aus, aber nur beim echten Wechsel
- Geometrie: `GetLeft`/`GetTop` (von Tests über `_left`/`_top` gesetzt), `GetSize`, `GetEffectiveScale`
- `UIParent` als 1600x900-Bildschirm

Anker werden bewusst **nicht** ausgewertet — `SetPoint` bleibt ein No-Op. Diese Tests prüfen, *ob* und *was* gespeichert wird, nicht wohin ein Frame gezeichnet würde.

Die Tests tauschen `GuildLootDB.settings` gegen eine Testtabelle (`WithSettings` / `RestoreSettings`), damit die echten Einstellungen des Testlaufs unberührt bleiben.

---

## Testfälle

### `UI.ClampFrameOffsets(x, y, frameW, frameH, screenW, screenH)`

Koordinatensystem: `x` ist der Offset von `UIParent` TOPLEFT nach rechts (≥ 0), `y` nach unten (≤ 0).

| Test | Was geprüft |
|------|-------------|
| `testClamp_InsideScreen_ReturnsUnchanged` | Position vollständig im Bildschirm bleibt unverändert |
| `testClamp_TooFarRight_StopsAtRightEdge` | Zu weit rechts → `screenW - frameW` |
| `testClamp_TooFarDown_StopsAtBottomEdge` | Zu weit unten → `-(screenH - frameH)` |
| `testClamp_NegativeX_StopsAtLeftEdge` | Negatives `x` → `0` |
| `testClamp_PositiveY_StopsAtTopEdge` | Positives `y` → `0` |
| `testClamp_FrameLargerThanScreen_PinsToTopLeft` | Fenster größer als der Bildschirm (Auflösungswechsel) → `0`/`0`, sonst wäre die Titelzeile nicht mehr greifbar |
| `testClamp_MissingInput_ReturnsNil` | Fehlt eine der sechs Zahlen → `nil` statt Rechnung auf `nil` |

### `UI.SaveFramePosition(frame, key)` — wann gespeichert werden darf

Diese Gruppe hält den Fehler fest, der beim ersten In-Game-Test auffiel: **Popup verschieben, `/reload`, Popup wieder in der Bildschirmmitte.**

Ursache war nicht die Rechnung, sondern der Zeitpunkt. `CreateFrame` liefert ein sichtbares Frame; `BuildPopup` versteckt es direkt nach dem Erzeugen wieder. Der damals registrierte `OnHide`-Hook lief damit mitten im Konstruktor, während das Popup noch auf seinem Default-`CENTER` stand — und ersetzte die gespeicherte Position durch diesen Default. Beim nächsten Öffnen wurde die überschriebene Mitte korrekt wiederhergestellt.

Dieselbe Ursache traf das Hauptfenster auf dem Logout-Pfad: angedockt ist es versteckt und steht auf seinem Default, `SaveAllFramePositions` hätte es bei jedem Ausloggen überschrieben.

Die Regel lautet seitdem: **gespeichert wird nur ein sichtbares Fenster.** Der `OnHide`-Hook ist entfallen — Positionen ändern sich nur durch Ziehen, und das sichert bereits beim Loslassen.

| Test | Was geprüft |
|------|-------------|
| `testHideDuringBuild_DoesNotOverwriteStoredPosition` | `Hide()` direkt nach `RegisterMovableFrame` (das Muster aus `BuildPopup`) lässt die gespeicherte Position unangetastet |
| `testSaveWhileHidden_KeepsStoredPosition` | Direkter `SaveFramePosition`-Aufruf auf einem versteckten Fenster schreibt nicht — deckt den Logout-Pfad ab |
| `testSaveWhileShown_WritesCurrentPosition` | Auf einem sichtbaren Fenster wird die aktuelle Ecke geschrieben (`GetLeft`, `GetTop − UIParent-Top`) |
| `testSaveWithoutSizeOption_StoresNoSize` | Ohne `size = true` wird keine Größe gespeichert — beim Loot-Popup kommt die Breite aus dem Widget |
| `testSaveWithSizeOption_StoresSize` | Mit `size = true` landen `w`/`h` im Speicher (Hauptfenster) |

Beide Regressionstests wurden gegen den wiederhergestellten Fehler geprüft und schlagen dort an.

### `GL.MigrateFramePositions()`

| Test | Was geprüft |
|------|-------------|
| `testMigrate_LegacyFields_MoveToMainEntry` | `framePos`/`frameSize` landen als `framePositions.main` (x, y, w, h) und werden anschließend genullt |
| `testMigrate_RunTwice_ChangesNothing` | Zweiter Lauf ist ein No-Op — die Migration läuft bei jedem Login |
| `testMigrate_ExistingMainEntry_IsKept` | Ein bereits vorhandener `main`-Eintrag gewinnt; sonst überschriebe ein liegengebliebenes Altfeld die aktuelle Position bei jedem Login |
| `testMigrate_NoLegacyFields_CreatesEmptyStore` | Ohne Altfelder entsteht eine leere `framePositions`-Tabelle, kein `main`-Eintrag |

---

## Was hier *nicht* getestet wird

Wohin ein Frame tatsächlich gezeichnet wird: `SetPoint` ist im Stub ein No-Op, Anker werden nicht ausgewertet. Ob der Mover-Streifen Mausklicks bekommt und ob die Titelzeilen-Knöpfe darüber liegen (`UI.RaiseAboveMover`), lässt sich nur in-game prüfen.

Die Regeln, die der Frame-berührende Teil einhalten muss, sichert zusätzlich die Lint-Suite statisch ab (`ReqRT.Lint`):

- `testNoHandWrittenFrameMoving` — niemand ruft `StartMoving` außerhalb von `UI_Common.lua`/`UI_DockTab.lua`
- `testNoDuplicateAnchorNormalization` — das Umankern auf `TOPLEFT`/`UIParent` steht nur in `UI_Common.lua`

---

## Tests erweitern

Neue Rechenlogik der Fensterpositionierung gehört als reine Funktion nach `UI_Common.lua` und wird hier getestet.

Für Logik, die einen Frame braucht, reicht meist der erweiterte Stub: `CreateFrame("Frame")`, `_left`/`_top` setzen, `Show()`/`Hide()` aufrufen und prüfen, was in `settings.framePositions` steht. Braucht ein Test echte Anker-Auswertung, gehört er nicht hierher — dann entweder einen Lint-Wächter ergänzen oder in-game prüfen.
