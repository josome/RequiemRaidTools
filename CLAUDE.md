# RequiemRaidTools — Claude-Regeln

## Git
- **Kein automatisches Commit und Push.** Dateien bearbeiten ist OK, aber `git commit` und `git push` führt der User selbst aus.
- Ausnahme: Der User fragt explizit "commit" oder "push".

## TOC-Version
- Bei jeder Code-Änderung die letzte Stelle in `## Version` in `RequiemRaidTools.toc` hochziehen (z.B. `0.5.1.0-beta` → `0.5.1.1-beta`).
- Der Git-Tag übernimmt immer die Version die aktuell in der TOC steht — nicht umgekehrt. Vor dem Taggen also sicherstellen dass die TOC-Version die gewünschte Release-Version hat.
- Wenn der User eine Tag-Nummer nennt, wird die TOC automatisch auf diese Version gesetzt (vor dem Taggen).
- Ist die genannte Nummer kleiner als die aktuelle TOC-Version, dem User mitteilen und auf Rückmeldung warten bevor etwas geändert wird.
- Nach jedem Hochziehen dem User mitteilen welche Version es jetzt ist, z.B. "TOC → 0.5.1.1-beta".

## Release-Checkliste (vor jedem Tag)
- `.pkgmeta` prüfen: Neue Dateien/Ordner seit dem letzten Tag evaluieren — gehören sie in den Release oder müssen sie unter `ignore:` eingetragen werden?
- Faustregel: Alles was kein WoW-Addon-Code ist (Entwickler-Notizen, KI-Regeln, Test-Tools, Docs) kommt in die ignore-Liste.

## Refactoring-Vorgehen

- **Single Responsibility Principle.** Jede Funktion tut genau das, wofür sie spezifiziert wurde — nicht mehr. Wird weitere Funktionalität benötigt, kommt sie in eine neue, benannte Funktion. Nie stille Zuständigkeiten in bestehende Funktionen hineinwachsen lassen.
- **Open/Closed Principle.** Bestehende, funktionierende Funktionen werden nicht modifiziert um neues Verhalten hinzuzufügen — sie werden durch neue Funktionen erweitert. Änderungen an bestehenden Funktionen nur zur Bugfixes oder Refactoring, nicht für neue Features.
- **Refactoring-Branches.** Strukturelle Umbauten (Funktionen aufteilen, Zuständigkeiten trennen) laufen auf einem eigenen Branch, nicht direkt auf `main`.

## Protokoll-Versionierung
- Die Minor-Version (`0.X.y.z`) ist die Protokoll-Version. `MIN_PROTO_MINOR` in `src/Comm.lua` nur erhöhen wenn das Nachrichtenformat inkompatibel geändert wird (Felder hinzugefügt/entfernt/umsortiert). Bewusste Entscheidung bei jedem Minor-Version-Bump.

## Projekt-Konventionen
- Slash-Commands: `/reqrt` und `/requiemraidtools` — NICHT `/rlt`
- UI-Begriff für Sessions: **"Raid Session"** (intern `container`/`raidContainer`)
- WoW AddOns Pfad: `G:\games\World of Warcraft\_retail_\Interface\AddOns\` (Symlink auf Repo — `/reload` reicht zum Testen)
- Release-Tags: Nachrichten können kurz/technisch sein — der CurseForge Changelog kommt aus `CHANGELOG.md` (via `manual-changelog` in `.pkgmeta`), NICHT aus der Tag-Message
