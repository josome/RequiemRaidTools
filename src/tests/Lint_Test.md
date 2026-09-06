# Lint Testdokumentation

**Datei:** `src/tests/Lint_Test.lua`  
**Framework:** busted (`spec/reqrt_spec.lua`)
**Suite-Name:** `ReqRT.Lint`

---

## Inhaltsverzeichnis

- [Voraussetzungen](#voraussetzungen)
- [Testziel](#testziel)
- [Teststrategie: statische Quellcode-Prüfung](#teststrategie-statische-quellcode-prüfung)
- [Testfälle](#testfälle)
  - [testTocFilesAreFound](#testtocfilesarefound)
  - [testNoWritesToForeignGlobals](#testnowritestoforeignglobals)
  - [testNoLegacyDropdownApi](#testnolegacydropdownapi)
  - [testNoHandWrittenFrameMoving](#testnohandwrittenframemoving)
  - [testNoDuplicateAnchorNormalization](#testnoduplicateanchornormalization)
- [Was diese Tests nicht abdecken](#was-diese-tests-nicht-abdecken)
- [Wenn ein Test rot wird](#wenn-ein-test-rot-wird)

---

## Voraussetzungen

| Bedingung | Warum |
|-----------|-------|
| Lauf über busted vom Repo-Root | Die Suite liest Quelldateien über relative Pfade (`RequiemRaidTools.toc`, `src/...`) |
| `io.open` verfügbar | In WoW gibt es keinen Dateizugriff — die Suite überspringt sich dort still |

---

## Testziel

Verhindern, dass bekannte Fehlermuster zurückkehren. Zwei Gruppen:

1. **Taint** (`testNoWritesToForeignGlobals`, `testNoLegacyDropdownApi`) — siehe unten.
2. **Fenster-Position** (`testNoHandWrittenFrameMoving`, `testNoDuplicateAnchorNormalization`) —
   drei Bugs beim Verschieben und Skalieren, von denen zwei nach ihrer Behebung bei einem
   späteren Umbau wieder verlorengingen. Details bei den jeweiligen Testfällen.

### Taint

Beide
hatten dieselbe Wirkung: Ein Blizzard-Global trägt den Addon-Stempel, `Blizzard_PlayerChoice`
liest es beim Nachladen, `PlayerChoiceFrame` bleibt für die restliche Session markiert — und
jedes ESC scheitert an `ClearTarget()`.

| Vorfall | Muster | Belegt in |
|---|---|---|
| v1.0.4.0-beta | `UIDropDownMenu_Initialize()` schreibt `UIDROPDOWNMENU_MENU_LEVEL` | `taint.log`, 2026-08-11 08:52 |
| v1.0.4.2-beta | `StaticPopupDialogs = StaticPopupDialogs or {}` schreibt das Global selbst | `taint.log`, 2026-08-11 10:22 |

Beide wären von dieser Suite gemeldet worden, bevor sie je ein Nutzer gesehen hätte.

---

## Teststrategie: statische Quellcode-Prüfung

Anders als alle übrigen Suites wird hier kein Verhalten getestet, sondern Text gelesen.

**Dateiliste kommt aus der TOC**, nicht hartkodiert: `ShippedFiles()` liest
`RequiemRaidTools.toc` und nimmt jede Zeile, die auf `.lua` endet. Damit gilt automatisch:
- neu aufgenommene Dateien werden ohne Zutun mitgeprüft
- alles, was nicht ausgeliefert wird, bleibt außen vor — insbesondere
  `src/ui/UI_PlayerTab.lua`, das weiterhin Legacy-Dropdowns enthält, aber nicht in der TOC
  steht und deshalb im Spiel nie geladen wird

Kommentarzeilen (`^%s*--`) gelten nie als Verstoß.

---

## Testfälle

### testTocFilesAreFound

Sicherung der Sicherung: Liest die TOC und prüft, dass mehr als zehn Lua-Dateien gefunden
werden. Ohne diesen Test wären die beiden folgenden bei einem kaputten Pfad oder umbenannter
TOC stillschweigend grün — und damit wertlos.

### testNoWritesToForeignGlobals

Sucht Zuweisungen an Globals auf **Spaltenposition 0**: `^([A-Z][%w_]*)%s*=[^=]`.

Erlaubt sind ausschließlich:

| Global | Grund |
|---|---|
| `GuildLoot` | eigener Namespace des Addons |
| `SLASH_REQUIEMRAIDTOOLS1` / `2` | Blizzard-Konvention zum Registrieren von Slash-Commands, alternativlos. Im `taint.log` tun `BugSack` und `!BugGrabber` dasselbe — folgenlos, weil der Chat-Parser nichts Geschütztes aufruft |

**Bewusst nicht erfasst:** eingerückte Zeilen. `    NAME = wert,` ist fast immer ein
Tabellenfeld in einem Konstruktor (`Comm.lua` allein hat davon ein Dutzend) und würde
massenhaft Fehlalarme erzeugen. Zuweisungen an fremde Globals stehen praktisch immer auf
Top-Level — der reale Fall (`UI_Common.lua:185`) wäre gefunden worden.

**Ebenfalls kein Treffer, und das ist korrekt:** `StaticPopupDialogs["KEY"] = {...}`. Nach dem
Namen folgt `[`, nicht `=`. Solche Slot-Writes sind unbedenklich und werden von dutzenden
Addons verwendet; nur die Zuweisung des Globals selbst ist das Problem.

### testNoLegacyDropdownApi

Meldet jedes Vorkommen von `UIDropDownMenu` in ausgelieferten Dateien. Ersatz ist
`UI.CreateDropdown` bzw. `UI.CreateOptionDropdown` aus `src/ui/UI_Common.lua`.

### testNoHandWrittenFrameMoving

Meldet jeden Aufruf von `StartMoving` außerhalb von `src/ui/UI_Common.lua` und
`src/ui/UI_DockTab.lua`.

Hintergrund ist dieselbe Sorte Rückfall wie bei den Taint-Regeln: Beim Hauptfenster war
`RegisterForDrag` auf dem Frame selbst mit `StartSizing` auf demselben Frame kollidiert
(`a843d6b`) — Verschieben und Größenänderung blockierten sich gegenseitig. Die Lösung, ein
eigener Mover-Streifen über der Titelzeile, steckt seitdem in `UI.RegisterMovableFrame`. Wer
Bewegung wieder von Hand verdrahtet, umgeht sie.

Ausgenommen sind:

| Datei | Grund |
|---|---|
| `src/ui/UI_Common.lua` | enthält den gemeinsamen Code selbst |
| `src/ui/UI_DockTab.lua` | klebt am Bildschirmrand und merkt sich nur seine Y-Position — bewusst ein eigener, viel einfacherer Weg |

**Geprüft wird allein `StartMoving`**, nicht `RegisterForDrag`. Ohne `StartMoving` bewegt sich
kein Fenster, und `RegisterForDrag` wäre der falsche Marker: `src/ui/UI_DropPanel.lua` benutzt
es, um per `OnReceiveDrag` ein Item entgegenzunehmen — mit Fensterposition hat das nichts zu
tun. Die erste, breitere Fassung dieser Regel hat genau darauf angeschlagen.

### testNoDuplicateAnchorNormalization

Meldet jedes `SetPoint("TOPLEFT", UIParent, "TOPLEFT", …)` außerhalb von
`src/ui/UI_Common.lua`.

Das Umankern eines Fensters auf genau einen TOPLEFT-Anker muss immer derselben Reihenfolge
folgen — Größe merken, `ClearAllPoints`, `SetPoint`, Größe zurücksetzen. Fehlt der letzte
Schritt, geht beim Umankern die Größe verloren, weil `ClearAllPoints` die von `StartSizing`
gesetzten Anker mitnimmt. Genau das ist zweimal passiert:

| Vorfall | Muster |
|---|---|
| `b589c9d` | CENTER-Anker ließ das Fenster nach `StopMovingOrSizing()` springen |
| `7f8caaa` | Umankern ohne anschließendes `SetSize` verlor die neue Größe |

Beide Fixes gingen später beim Umbau auf den Mover-Streifen wieder verloren. Deshalb steht das
Umankern jetzt nur noch an einer Stelle, in `UI.NormalizeFrameAnchor`, und diese Regel hält es
dort.

---

## Was diese Tests nicht abdecken

- **Andere Taint-Quellen.** Geprüft werden genau die zwei bekannten Muster, nicht Taint im
  Allgemeinen. Ein Addon kann auf viele Arten tainten (Hooks, Secure-Frames, Mixins).
- **Eingerückte Global-Zuweisungen** (siehe oben, bewusste Abwägung gegen Fehlalarme).
- **Laufzeitverhalten.** Ob ein Dropdown korrekt funktioniert, sagt diese Suite nicht — nur,
  dass es die richtige API benutzt.
- **`src/ui/UI_PlayerTab.lua`**, solange die Datei nicht in der TOC steht. Wird sie wieder
  aufgenommen, schlägt `testNoLegacyDropdownApi` sofort an — dann muss sie erst migriert werden.

---

## Wenn ein Test rot wird

Die Fehlermeldung nennt Datei, Zeilennummer und Inhalt jedes Verstoßes.

- **Fremdes Global:** Prüfen, ob wirklich das Global gesetzt werden muss. Meist reicht ein
  Tabellen-Slot (`Tabelle["KEY"] = ...`) oder eine `local`-Variable. Ist die Zuweisung
  unvermeidbar und nachweislich harmlos, gehört das Global mit Begründung in `ALLOWED_GLOBALS`.
- **Legacy-Dropdown:** Auf `UI.CreateDropdown` / `UI.CreateOptionDropdown` umstellen. Muster
  siehe `src/ui/UI_Settings.lua` (Einfachauswahl) und `src/ui/UI_SeasonControls.lua`
  (Mehrfachauswahl mit Checkboxen).
- **Handgeschriebenes `StartMoving`:** Auf `UI.RegisterMovableFrame(frame, key, opts)`
  umstellen. Der Rückgabewert ist der Mover-Streifen; die Knöpfe der Titelzeile anschließend
  mit `UI.RaiseAboveMover(mover, …)` darüber heben, sonst nehmen sie keine Klicks mehr an.
  Muster siehe `src/ui/UI_PlayerPopup.lua`.
- **Dupliziertes Umankern:** `UI.NormalizeFrameAnchor(frame)` rufen statt `ClearAllPoints` +
  `SetPoint` selbst zu schreiben. Wird nur die Position gebraucht, tut es
  `UI.SaveFramePosition` / `UI.RestoreFramePosition`.
