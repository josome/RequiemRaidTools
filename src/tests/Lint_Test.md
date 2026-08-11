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

Verhindern, dass die zwei Muster zurückkehren, die nachweislich Taint erzeugt haben. Beide
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
