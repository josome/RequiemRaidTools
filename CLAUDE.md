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

## Projekt-Konventionen
- Slash-Commands: `/reqrt` und `/requiemraidtools` — NICHT `/rlt`
- UI-Begriff für Sessions: **"Raid Session"** (intern `container`/`raidContainer`)
- WoW AddOns Pfad: `G:\games\World of Warcraft\_retail_\Interface\AddOns\` (Symlink auf Repo — `/reload` reicht zum Testen)
- Release-Tags: Nachrichten können kurz/technisch sein — der CurseForge Changelog kommt aus `CHANGELOG.md` (via `manual-changelog` in `.pkgmeta`), NICHT aus der Tag-Message
