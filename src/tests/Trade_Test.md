# Trade Testdokumentation

**Datei:** `src/tests/Trade_Test.lua`
**Framework:** busted (`spec/reqrt_spec.lua`)
**Suite-Name:** `ReqRT.Trade`

---

## Voraussetzungen

| Bedingung | Warum |
|-----------|-------|
| devMode aktiv | Wie alle Suites — ohne devMode registriert sich die Suite nicht |

---

## Testziel

Auto-Handel (`Loot_Trade.lua`): `TRADE_SHOW` → automatisches Einlegen der dem
Handelspartner zugewiesenen Items, `TRADE_ACCEPT_UPDATE`, Trade-Systemmeldungen und
`TRADE_CLOSED`. Die Queue kommt aus `GL.TradeLog`, also aus gespeicherten
Session-Einträgen (`entry.trade`), nicht mehr aus einer flüchtigen Liste.

```
OnTradeShow → Partnername ermitteln → TradeLog.EntriesFor(partner) (max. 6)
            → _inTradeItems (Staging, Status "staged") → handelbare Bag-Kopie suchen → ClickTradeButton
OnTradeAcceptUpdate → Handelsslots festhalten (Snapshot)
OnTradeUIMessage(ERR_TRADE_COMPLETE) → zweites Erfolgssignal
OnTradeClosed → (0,5 s später) FinalizeTrade:
                Erfolg: nur Items im Snapshot → "traded", Rest bleibt offen
                Abbruch: "aborted", bleiben in der Queue
```

---

## Teststrategie

- `WithSession(fn)` — frische aktive Raid Session + leeres Trade-Protokoll, stellt
  DB, Mocks und Trade-Zustand danach wieder her.
- `Queue(session, {{itemID, player}, ...})` — legt Zuteilungen als offene
  Auto-Trade-Einträge (`trade.status = "queued"`) im lootLog an.
- `ResetTradeState()` — leert `_pendingTrades`, `_inTradeItems`, `_lastPartner`,
  `TradeLog._orphans`, ruft `OnTradeClosed()` (setzt `_tradeAccepted = false`).
  `_lastPartner` muss mit zurück, sonst greift der Secret-Value-Rückfall quer über Tests.
- `MockBasics()` — stubbt `IsMasterLooter`, `Print`, **synchrones** `C_Timer.After`
  (Staging-Verzögerung und Auswertung nach `TRADE_CLOSED` laufen sofort),
  `GetTradePlayerItemInfo` (Slot frei), `ClearCursor`, `ClickTradeButton`, leeres `C_Container`.
- `MockBagWithItems(id, ...)` — Bag 0 ab Slot 1 enthält die Items.
- `MockTradeSlots(id, ...)` — `GetTradePlayerItemLink(i)` liefert das i-te Item.
- `MockPartner(name)` — `TradeFrameRecipientNameText` liefert den Namen und `UnitName`
  liefert nil, damit gezielt der Widget-Pfad geprüft wird (die Unit-API hat Vorrang).
- `MockSecretPartner()` — `GetText()` liefert einen Wert, bei dem jede String-Operation
  wirft, und `issecretvalue` erkennt genau diesen Wert. Bildet Blizzards geschützte
  Werte ab (WoW 11.2+).

---

## Testfälle

### `testNameFromTradeFrame`
Partnername aus `TradeFrameRecipientNameText` (inkl. Cross-Realm-Suffix-Strip
„Name (*)" → „Name"). Item wandert nach `_inTradeItems`, raus aus `_pendingTrades`;
Status `staged`, `attempts == 1`.

### `testResolvesViaUnitName`
Widget nicht vorhanden → Name aus `UnitName("NPC")`. Das ist seit dem Secret-Value-Fix
die **primäre** Quelle; das Widget ist nur noch Rückfall.

### `testBothSourcesEmpty`
Beide Namensquellen leer → kein Crash, Eintrag bleibt `queued`.

### `testNoMatchingItem`
Partner ohne passende Zuweisung → Staging leer, Queue unverändert.

### `testSixItemLimit`
7 Items zugewiesen → nur 6 in `_inTradeItems`, 1 bleibt in `_pendingTrades`
(WoW-Slot-Limit).

### `testTradeSuccess`
Staging, `OnTradeAcceptUpdate(1,1)` mit dem Item im Handelsslot, `OnTradeClosed`
→ Status `traded`, Queue leer.

### `testTradeCancel`
`OnTradeClosed` ohne Accept und ohne Abschluss-Meldung → Status `aborted`,
Item wieder in `_pendingTrades`.

### `testClickTradeButtonCalled`
`ClickTradeButton` wird pro Item genau einmal aufgerufen.

### `testPicksTradeableCopyOverBoundDuplicate`
Zwei Bag-Slots gleiche `itemID`: Slot 1 gebunden ohne 2h-Trade-Tooltip-Zeile,
Slot 2 mit Zeile. Erwartet: **Slot 2** (handelbare Kopie) wird aufgenommen, nicht
die erste (gebundene). Deckt den „Item nicht eingelegt"-Bug beim Raid-1→Raid-2-
Wechsel ab (gebundene Duplikat-Kopie aus dem Vorraid).

### `testFallbackToFirstMatchWhenNoneTradeable`
Nur eine (gebundene, kein Timer) Kopie → Fallback nimmt sie trotzdem
(altes Verhalten, kein Regress). Status `bound` macht den Grund in der Trade-Liste sichtbar.

### `testUnboundItemIsTradeable`
`isBound == false` → ohne Tooltip-Scan handelbar.

### `testSuccessViaTradeCompleteMessage` (B3)
`TRADE_ACCEPT_UPDATE(1,1)` bleibt aus, nur die Systemmeldung `ERR_TRADE_COMPLETE`
kommt → trotzdem `traded`. Vorher wurde so ein Handel als Abbruch gewertet und das
Item erneut angeboten.

### `testLateTradeCompleteCorrectsAbort` (B3)
Die Abschluss-Meldung kommt erst **nach** der Auswertung → Status zunächst
`aborted`, danach nachträglich `traded`.

### `testItemMissingFromTradeSlotsStaysOpen` (B4)
Handel erfolgreich, aber nur eines von zwei gestagten Items lag im Handelsfenster
→ nur dieses wird `traded`, das andere bleibt `queued`. Vorher wurden alle gestagten
Items verworfen, auch wenn `ClickTradeButton` lautlos gescheitert war.

### `testDoubleTradeClosedFinalizesOnce`
`TRADE_CLOSED` feuert doppelt → genau eine geplante Auswertung.

### `testItemNotInBagsMarkedNotFound`
Item nicht in den Taschen → Status `notFound`, raus aus dem Staging.

### `testTradeFlowIsTraced`
Ein kompletter Handel erzeugt Protokolleinträge `show`, `item`, `accept`, `close`.

### `testSecretFrameTextStillResolvesViaUnit`
Der belegte Fall aus dem Raid-Log: `TradeFrameRecipientNameText:GetText()` liefert
einen geschützten Wert, `UnitName("NPC")` funktioniert. Der Auto-Trade läuft normal
durch — ein `ClickTradeButton`, Status `staged`, `_lastPartner` gesetzt, **kein**
Rückfall und keine Warnung.

### `testPrefersUnitNameOverFrameText`
Widget und Unit-API liefern verschiedene Namen → die Unit-API gewinnt. Das Widget
wird nur noch angefasst, wenn `UnitName("NPC")` nichts liefert.

### `testSecretPartnerNameDoesNotThrow`
`TradeFrameRecipientNameText:GetText()` liefert einen geschützten Wert (jede
String-Operation darauf wirft), `issecretvalue` ist passend gemockt → `OnTradeShow`
wirft nicht, das Item bleibt `queued`, und Protokoll enthält `show` (Eintritt) sowie
`skip` (Abbruchgrund). Vorher lief `strtrim`/`gsub` direkt auf dem Wert und der
Lua-Fehler beendete den Callback vor jeder Ausgabe.

### `testSecretPartnerFallsBackToLastPartner`
Erster Handel mit lesbarem Namen setzt `Loot._lastPartner`; im zweiten Handelsfenster
ist der Name geschützt → der Auto-Trade weicht auf den gemerkten Partner aus und
staged das Item (Muster von RCLootCouncil `lastAttemptedTradeTarget`).

### `testSkipsLockedBagSlot`
Slot 1 enthält die itemID, ist aber `isLocked` (Item noch in Bewegung) → gegriffen
wird Slot 2. Auf gesperrten Plätzen scheitert `PickupContainerItem` lautlos, und
`ClickTradeButton` mit leerem Cursor danach ebenso.

### `testDoesNotReuseAlreadyPlacedBagSlot`
Zwei Zuteilungen derselben itemID an denselben Spieler → zwei **verschiedene**
Taschenplätze und zwei verschiedene Handelsslots. Vorher wurde zweimal dieselbe
physische Kopie gegriffen und die zweite Platzierung scheiterte stumm.

### `testAbortsWhenTradeWindowClosed`
`C_Timer.After` sammelt die Platzierungs-Callbacks statt sie sofort auszuführen;
zwischen Einplanen und Ausführen kommt `OnTradeClosed()` → kein `ClickTradeButton`.

### `testEntryTraceBeforeGuards`
Ohne Master-Looter-Recht bricht der Auto-Trade ab, die Zeile
`TRADE_SHOW received: ML=false` steht aber trotzdem im Protokoll. Nur so ist
„Event kam nicht an" von „Event kam, Guard hat abgelehnt" unterscheidbar.

### `testPlacementRunsWhenRefreshFails`
`GL.UI.RefreshTradeDebug` wirft einen Fehler → die Items werden trotzdem in den Handel
gelegt (`ClickTradeButton` läuft), und der Fehlschlag landet als `ui` im Protokoll.
Sichert ab, dass das Auffrischen des Debug-Fensters nie auf dem kritischen Pfad der
Platzierung liegt: das Fenster rendert eine Frame-Zeile pro Loot-Eintrag der Session,
und diese Liste wächst über den Raidabend mit jeder Zuteilung.

---

## Was diese Tests nicht abdecken

| Bereich | Warum |
|---------|-------|
| Echte Tooltip-Daten | `C_TooltipInfo.GetBagItem` wird gemockt |
| 2h-Trade-Timer-Ablauf (Server) | WoW-Serverlogik; der Client-seitige Ablauf steht in `ReqRT.TradeLog` |
| Reihenfolge der echten WoW-Events | Ob `ERR_TRADE_COMPLETE` vor oder nach `TRADE_CLOSED` kommt, zeigt erst das Protokoll im Spiel |
| UI-Rendering | `UI_TradeDebug.lua` wird im busted-Lauf nicht geladen — getestet ist nur, dass ein Fehler daraus die Platzierung nicht mitreißt |
