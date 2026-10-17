# TradeTrace Testdokumentation

**Datei:** `src/tests/TradeTrace_Test.lua`
**Framework:** busted (`spec/reqrt_spec.lua`)
**Suite-Name:** `ReqRT.TradeTrace`

---

## Testziel

`Loot_TradeTrace.lua` zeichnet jeden Auto-Trade-Schritt dauerhaft in
`GuildLootDB.tradeTrace` auf (Ringpuffer, Standard 300 Einträge). Der Auto-Trade
versagte sporadisch, ohne dass sich der Fehler eingrenzen ließ — das Protokoll soll den
Ablauf nach einem Vorfall lesbar machen. Es darf dabei selbst nie den Trade-Ablauf stören.

---

## Teststrategie

`WithEmptyTrace(fn)` startet mit `tradeTrace = nil` (wie bei Altdaten), stummt die
devMode-Chatausgabe (`GL.Print`) und stellt Protokoll, `MAX_ENTRIES` und `GL.Print`
danach wieder her.

---

## Testfälle

| Test | Prüft |
|---|---|
| `testAddCreatesStoreAndAppends` | Erster Eintrag legt `tradeTrace` an; `kind`, formatierter `text`, `ts` gesetzt |
| `testRingBufferDropsOldest` | Bei `MAX_ENTRIES = 3` und 5 Einträgen bleiben die drei neuesten |
| `testBadFormatArgsDoNotThrow` | Falsche `string.format`-Argumente werfen nicht, der Rohtext wird gespeichert |
| `testEntriesNewestFirstAndTextChronological` | `Entries()` neueste zuerst (Anzeige), `AsText()` chronologisch mit `[kind]` (Export) |
| `testClear` | `Clear()` leert das Protokoll |

---

## Was diese Tests nicht abdecken

| Bereich | Warum |
|---------|-------|
| Welche Ereignisse der Trade-Ablauf schreibt | → `ReqRT.Trade` (`testTradeFlowIsTraced`), `ReqRT.TradeLog` (`testManualActionsAreTraced`) |
| Anzeige im Fenster, Kopieren | UI wird im busted-Lauf nicht geladen |
