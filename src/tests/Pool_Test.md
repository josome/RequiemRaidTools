# Pool Testdokumentation

**Datei:** `src/tests/Pool_Test.lua`
**Framework:** [WoWUnit](https://www.curseforge.com/wow/addons/wowunit) in-game und busted standalone (`spec/reqrt_spec.lua`)
**Suite-Name im WoWUnit-Fenster:** `ReqRT.Pool`

---

## Testziel

Unit-Tests für `UI.CreateFramePool` (`src/ui/UI_Common.lua`) — die generische Frame-Pool-Factory für Listen-Rows. WoW-Frames werden nie garbage-collected; die Factory stellt sicher, dass Refreshes Rows wiederverwenden statt neu zu erzeugen (Leak-Prevention).

---

## Teststrategie

Die Factory ist Frame-API-agnostisch: sie ruft selbst nie `Hide`/`ClearAllPoints` — alles Frame-Berührende lebt in `createFn`/`resetFn`. Die Tests nutzen daher **plain Lua-Tables als Frames** (`{ id = n }`) und zählen create/reset-Aufrufe über einen `NewCountingPool()`-Helper. Kein `CreateFrame`, keine WoW-Stubs nötig.

---

## Testfälle

| Test | Was geprüft |
|------|-------------|
| `testAcquire_EmptyPool_CallsCreateExactlyOnce` | Acquire auf leerem Pool ruft `createFn` genau 1× und liefert dessen Ergebnis; Active-Count = 1 |
| `testReleaseAll_ResetsEachActiveFrame_ActiveDropsToZero` | `ReleaseAll` ruft `resetFn` pro aktiver Row; Active-Count → 0 |
| `testAcquire_AfterReleaseAll_ReusesSameObject` | Acquire nach ReleaseAll liefert **dasselbe Objekt** — kein zweiter `createFn`-Aufruf |
| `testLeakPrevention_TotalCreationsBoundedByPeak` | 4 simulierte Refreshes à 5 Rows → nur 5 Creations total (Peak), nicht 20 |
| `testTwoPools_AreIsolated` | Zwei Pools teilen keine Frames; getrennte Zähler |
| `testReleaseAll_EmptyPool_IsNoOp` | `ReleaseAll` auf leerem Pool: kein Error, kein `resetFn`-Aufruf |

---

## Tests erweitern

Neue Tests nutzen den `NewCountingPool()`-Helper oder bauen eigene `createFn`/`resetFn`-Paare mit Zählern. Frame-Verhalten (Hide, Anker, Scripts) gehört **nicht** hierher — das lebt in den `resetFn`s der jeweiligen Tab-Dateien und wird in-game verifiziert.
