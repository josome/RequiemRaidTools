# RequiemRaidTools — Claude-Regeln

## Git
- **Kein automatisches Commit und Push.** Dateien bearbeiten ist OK, aber `git commit` und `git push` führt der User selbst aus.
- Ausnahme: Der User fragt explizit "commit" oder "push".

## TOC-Version
- Bei jeder Code-Änderung die letzte Stelle in `## Version` in `RequiemRaidTools.toc` hochziehen (z.B. `0.5.1.0-beta` → `0.5.1.1-beta`).
- Bei einem geplanten Release-Tag die Version auf die Tag-Version setzen (z.B. `0.5.1.0-beta` wenn Tag `v0.5.1.0-beta`).
- Nach jedem Hochziehen dem User mitteilen welche Version es jetzt ist, z.B. "TOC → 0.5.1.1-beta".

## Projekt-Konventionen
- Slash-Commands: `/reqrt` und `/requiemraidtools` — NICHT `/rlt`
- UI-Begriff für Sessions: **"Raid Session"** (intern `container`/`raidContainer`)
- WoW AddOns Pfad: `G:\games\World of Warcraft\_retail_\Interface\AddOns\` (Symlink auf Repo — `/reload` reicht zum Testen)
- Release-Tags: Nachrichten auf Englisch, user-facing (erscheinen als CurseForge Changelog)
