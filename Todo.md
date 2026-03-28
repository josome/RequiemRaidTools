# RaidLootTracker – Todo

## Offen

- [ ] **Lokalisierung (i18n)**
  Aktuell ~40+ gestreute Strings, gemischt Deutsch/Englisch, kein L[]-System.
  → `Locales/deDE.lua` + `Locales/enUS.lua` anlegen, alle UI-Strings durch `L["key"]` ersetzen, TOC um Locale-Dateien erweitern.

- [ ] **JSON-Export-Fenster scrollbar machen**
  Das Export-Textfeld ist aktuell nicht scrollbar, der Inhalt geht über das Fenster hinaus.
  → ScrollFrame um das Export-TextBox ergänzen, oder EditBox mit `SetMultiLine(true)` + Scroll-Wrapper

## Erledigt (diese Session)

- [x] Results-Liste zeigt alle Prio-Spieler sortiert (nicht nur höchste Prio)
- [x] Test-Simulation `/rlt testroll` mit 7 Spielern (4x Prio1, 2x Prio2, 1x Prio3)
- [x] ScrollFrame-Bug behoben (UIPanelScrollFrameTemplate braucht benannte Frames)
- [x] Session Loot Bereich vergrößert (~6 Zeilen)
- [x] Duplikat-Button "Roll Now" entfernt
- [x] Fenster-Mindestgröße beim Laden erzwungen (X-Buttons nicht mehr verdeckt)
- [x] Absturz-Warnung in Raid-Statuszeile
- [x] pendingLoot wird bei CloseRaid im Snapshot gespeichert
- [x] pendingLoot wird bei ResumeRaid aus Snapshot wiederhergestellt
