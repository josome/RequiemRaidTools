# Trade Testdokumentation

**Datei:** `src/tests/Trade_Test.lua`
**Framework:** [WoWUnit](https://www.curseforge.com/wow/addons/wowunit) (läuft in-game) + busted (`spec/reqrt_spec.lua`)
**Suite-Name im WoWUnit-Fenster:** `ReqRT.Trade`

---

## Voraussetzungen

| Bedingung | Warum |
|-----------|-------|
| WoWUnit installiert | Test-Framework |
| `/reqrt devmode` aktiv | Tests registrieren sich nicht ohne devMode |
| `/reload` nach devMode-Toggle | GuildLootDB korrekt initialisiert |

---

## Testziel

Auto-Handel (`Loot_Trade.lua`): `TRADE_SHOW` → automatisches Einlegen der dem
Handelspartner zugewiesenen Items, `TRADE_ACCEPT_UPDATE` / `TRADE_CLOSED`.

```
OnTradeShow → Partnername ermitteln → bis zu 6 Items aus _pendingTrades
            → _inTradeItems (Staging) → handelbare Bag-Kopie suchen → ClickTradeButton
OnTradeClosed → Erfolg: Staging leeren | Abbruch: zurück in _pendingTrades
```

---

## Teststrategie

- `ResetTradeState()` — leert `_pendingTrades` + `_inTradeItems`, ruft
  `OnTradeClosed()` (setzt `_tradeAccepted = false`).
- `MockBasics()` — stubbt `IsMasterLooter`, `Print`, synchrones `C_Timer.After`,
  `GetTradePlayerItemInfo` (Slot frei), `ClearCursor`, `ClickTradeButton`,
  leeres `C_Container`.
- `MockBagWithItem(itemID)` — Bag 0 Slot 1 enthält das Item.

---

## Testfälle

### `testNameFromTradeFrame`
Partnername aus `TradeFrameRecipientNameText` (inkl. Cross-Realm-Suffix-Strip
„Name (*)" → „Name"). Item wandert nach `_inTradeItems`, raus aus `_pendingTrades`.

### `testFallbackToUnitName`
`TradeFrameRecipientNameText` nil → Fallback `UnitName("NPC")`.

### `testBothSourcesEmpty`
Beide Namensquellen leer → kein Crash, Item bleibt in `_pendingTrades`.

### `testNoMatchingItem`
Partner ohne passende Zuweisung → Staging leer, Queue unverändert.

### `testSixItemLimit`
7 Items zugewiesen → nur 6 in `_inTradeItems`, 1 bleibt in `_pendingTrades`
(WoW-Slot-Limit).

### `testTradeSuccess`
`OnTradeAcceptUpdate(1,1)` + `OnTradeClosed` → Staging geleert, endgültig vergeben.

### `testTradeCancel`
`OnTradeClosed` ohne Accept → Items zurück in `_pendingTrades`.

### `testClickTradeButtonCalled`
`ClickTradeButton` wird pro Item genau einmal aufgerufen.

### `testPicksTradeableCopyOverBoundDuplicate`
Zwei Bag-Slots gleiche `itemID`: Slot 1 gebunden ohne 2h-Trade-Tooltip-Zeile,
Slot 2 mit Zeile. Erwartet: **Slot 2** (handelbare Kopie) wird aufgenommen, nicht
die erste (gebundene). Deckt den „Item nicht eingelegt"-Bug beim Raid-1→Raid-2-
Wechsel ab (gebundene Duplikat-Kopie aus dem Vorraid).

### `testFallbackToFirstMatchWhenNoneTradeable`
Nur eine (gebundene, kein Timer) Kopie → Fallback nimmt sie trotzdem
(altes Verhalten, kein Regress).

### `testUnboundItemIsTradeable`
`isBound == false` → ohne Tooltip-Scan handelbar.

---

## Was diese Tests nicht abdecken

| Bereich | Warum |
|---------|-------|
| Echte Tooltip-Daten | `C_TooltipInfo.GetBagItem` wird gemockt |
| 2h-Trade-Timer-Ablauf | WoW-Serverlogik, nicht testbar |
| UI-Rendering | nicht Gegenstand der Trade-Tests |
