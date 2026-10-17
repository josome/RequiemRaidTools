# TradeLog Testdokumentation

**Datei:** `src/tests/TradeLog_Test.lua`
**Framework:** busted (`spec/reqrt_spec.lua`)
**Suite-Name:** `ReqRT.TradeLog`

---

## Testziel

`Loot_TradeLog.lua` hält den Auto-Trade-Zustand jeder Zuteilung direkt am gespeicherten
Eintrag (`entry.trade`). Die Auto-Trade-Queue ist nur eine daraus abgeleitete Sicht
(`BuildQueue`, `EntriesFor`, Spiegel in `Loot._pendingTrades`). Die Suite prüft:

- die Zustandsübergänge bei Zuteilung, Ablauf und manuellen Eingriffen,
- die beiden Fehler, die der getrennte, flüchtige Aufbau vorher hatte (B1, B2),
- die Daten, die das Debug-Fenster anzeigt.

---

## Teststrategie

- `WithSession(fn)` — frische aktive Raid Session, leeres Protokoll, leere `players`;
  Queue-Spiegel, `_inTradeItems`, `_orphans` und DB werden danach wiederhergestellt.
- `Assign(session, itemID, player, ts)` — lootLog-Eintrag wie `AssignLootConfirm` ihn
  schreibt, danach `TradeLog.Track`.
- Feste Zeit `NOW` wird explizit übergeben, damit das 2h-Fenster deterministisch ist.
- Der `UnitName`-Stub liefert `TestPlayer` — damit testet `TestPlayer-TestRealm` den
  eigenen Charakter.

---

## Testfälle

### Zuteilung

| Test | Prüft |
|---|---|
| `testTrackQueues` | Zuteilung → `queued`, `attempts == 0`, offen |
| `testTrackSelfIsNotQueued` | **B5:** Zuteilung an den ML selbst → `self`, nicht in der Queue |

### Fehlerbilder des alten Aufbaus

| Test | Prüft |
|---|---|
| `testReassignFollowsPlayer` | **B1:** Reassign im Log-Tab (`entry.player` ändern) → Auto-Trade gilt für den neuen Spieler, nicht mehr für den alten |
| `testQueueSurvivesReload` | **B2:** `_pendingTrades` leer (Zustand nach `/reload`) → `OnLogin` baut die Queue aus den gespeicherten Einträgen wieder auf |
| `testMirrorSkipsStagedItems` | Spiegel enthält keine Items, die gerade im Handelsfenster liegen |

### 2h-Handelsfenster

| Test | Prüft |
|---|---|
| `testExpireStale` | Einträge älter als 2 h → `expired`, jüngere bleiben `queued` |
| `testLegacyEntriesIgnored` | lootLog-Einträge ohne `trade` (Altdaten) kommen nie in die Queue, erscheinen in `Rows` mit `status == nil` („—“) |
| `testEntriesForLimitedToSixSlots` | Höchstens 6 Einträge pro Handelspartner, älteste zuerst |

### Manuelle Eingriffe

| Test | Prüft |
|---|---|
| `testRedirectOnlyChangesTradeRecipient` | Umleiten ändert nur den Auto-Trade-Empfänger, `entry.player` bleibt |
| `testRedirectBackClearsOverride` | Zurück auf den zugeteilten Spieler → Umleitung entfällt |
| `testRedirectReopensTradedEntry` | Umleiten eines erledigten Eintrags → wieder `queued`, 2h-Fenster neu |
| `testMarkDone` | „Erledigt“ → `traded`, `manualDone`, raus aus der Queue |
| `testRequeueRestartsWindow` | Abgelaufen → „Wieder in Queue“ → `queued` und wieder offen |
| `testRequeueSelfStaysSelf` | „Wieder in Queue“ bei eigenem Item → bleibt `self`, kein Handel mit sich selbst |
| `testRemoveAssignmentKeepsLootLog` | Entfernen einer Zuteilung → `removed`, lootLog-Eintrag bleibt |
| `testAddManual` | Item von Hand vorbereitet → in `manualTrades`, kein lootLog-Eintrag, keine Spielerhistorie |
| `testManualEntryNeverExpires` | Manuelle Einträge laufen nicht ab |
| `testRemoveManualDeletesEntry` | Entfernen eines manuellen Eintrags löscht ihn |
| `testAddManualWithoutSession` | Ohne Raid Session → Laufzeit-Eintrag in `_orphans`, trotzdem im Auto-Trade |

### Anzeige & Protokoll

| Test | Prüft |
|---|---|
| `testRowsNewestFirstWithRemaining` | `Rows`: neueste zuerst, Umleitung markiert, Restzeit korrekt |
| `testQueueSummary` | Zählung „wartend“ / „im Handel“ |
| `testManualActionsAreTraced` | Jede manuelle Änderung erzeugt einen `manual`-Protokolleintrag |

---

## Was diese Tests nicht abdecken

| Bereich | Warum |
|---------|-------|
| Ablauf im Handelsfenster | → `ReqRT.Trade` |
| UI-Rendering, Klicks, Drop-Zone | `UI_TradeDebug.lua` wird im busted-Lauf nicht geladen |
| Zuteilung über `AssignLootConfirm` | → `ReqRT.Assign` (`testAssignTracksTrade`, `testAssignToSelfNotQueued`) |
