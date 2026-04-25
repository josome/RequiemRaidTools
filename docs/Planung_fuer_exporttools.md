### CSV Roundtrip: Google Sheets ↔ Addon ⚠️ zurückgestellt bis Loot-Historie-Konzept steht

- [ ] **CSV um `ItemID` und `Quality` erweitern**
  Aktuelle Spalten: `RaidID, Tier, Difficulty, Track, Date, Status, Player, Item, Category, Prio, Timestamp`
  Erweitert: `RaidID, Tier, Difficulty, Track, Date, Status, Player, Item, ItemID, Quality, Category, Prio, Timestamp`
  → `GL.ExportCSV()` in `Util.lua` anpassen

- [ ] **CSV-Importer im Addon**
  Paste-Feld im Addon (eigener Tab oder im Raid-Tab) für CSV-String aus Google Sheets.
  Parser gruppiert flache Zeilen nach `RaidID` und rekonstruiert `raidHistory`-Einträge
  mit `lootLog` (Status=Assigned) und `trashedLoot` (Status=Trashed).

  **Validierung & Fehlerbehandlung:**
  - Import läuft in temporären Buffer — erst nach vollständiger Validierung committed
  - Pflichtfeld-Check pro Zeile: `RaidID`, `Player`, `Timestamp` (Zahl), `Status` (Assigned/Trashed)
  - Fehlerhafte Zeilen werden übersprungen (Warning), kein kompletter Abbruch
  - Duplikat-Check: falls Raid mit gleicher `RaidID` bereits in `raidHistory` → Confirmation-Dialog
  - Dry-Run Vorschau vor Import: "X Raids, Y Einträge gefunden, Z Zeilen übersprungen"

  **Robustheit gegen Sheets-Eigenheiten:**
  - BOM-Zeichen (`\xEF\xBB\xBF`) am Anfang entfernen
  - `\r\n` und `\n` beide akzeptieren
  - RFC-4180 Quotes behandeln (mehrzeilige Felder, escaped Quotes)
  - Leere Abschlusszeilen ignorieren

---

### Sonstiges

- erledigt: [x] getestet: [ ] **Loot.lua modularisiert** — aufgeteilt in `src/loot/`: `Loot.lua`, `Loot_Roll.lua`, `Loot_Assign.lua`, `Loot_Trade.lua`

- [ ] **Chat-Nachrichten farbig hervorheben**
  WoW unterstützt `|cAARRGGBB...|r` in allen Chat-Typen (Raid, Raid-Warning, Whisper).
  Aktuell ist nur der lokale `[ReqRT]`-Prefix in Print-Meldungen cyan eingefärbt.
  → `[ReqRT]`-Prefix auch in `SendChatMessage`-Aufrufen einfärben, ggf. wichtige Meldungen (Winner, Prio-Aufforderung) hervorheben.

- [ ] **Lokalisierung (i18n)** ⚠️ niedrige Priorität — zurückgestellt
  Aktuell ~40+ gestreute Strings, gemischt Deutsch/Englisch, kein L[]-System.
  → `Locales/deDE.lua` + `Locales/enUS.lua` anlegen, alle UI-Strings durch `L["key"]` ersetzen, TOC um Locale-Dateien erweitern.

- [ ] **JSON-Export-Fenster scrollbar machen**
  Das Export-Textfeld ist aktuell nicht scrollbar, der Inhalt geht über das Fenster hinaus.
  → ScrollFrame um das Export-TextBox ergänzen, oder EditBox mit `SetMultiLine(true)` + Scroll-Wrapper
