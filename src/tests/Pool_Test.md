# Pool Testdokumentation

**Datei:** `src/tests/Pool_Test.lua`
**Framework:** busted (`spec/reqrt_spec.lua`)
**Suite-Name:** `ReqRT.Pool`

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

## `UI.RefreshOnResize(frame, fn)`

Panels, deren Aufteilung von der Fensterbreite abhängt, rechnen sie erst beim Zeichnen aus — ohne
Haken bleibt die Anzeige beim Aufziehen des Fensters stehen. Der Helper kapselt die zwei
Feinheiten, die das Muster sonst an jeder Stelle wiederholen würde: `OnSizeChanged` feuert während
des Ziehens **pro Frame** (Aufrufe werden auf einen je Frame zusammengefasst), und ein
ausgeblendetes Panel bekommt beim Vergrößern gar kein `OnSizeChanged` (deshalb zusätzlich
`OnShow`).

Getestet über ein Fake-Frame mit gesammelten Skripten; `C_Timer.After` wird im Test ersetzt,
einmal auf „sofort ausführen" und einmal auf „sammeln", um das Zusammenfassen zu prüfen.

| Test | Was geprüft |
|------|-------------|
| `testRefreshOnResize_HooksSizeAndShow` | Beide Skripte werden gehakt und lösen je einen Aufruf aus |
| `testRefreshOnResize_CoalescesWithinOneFrame` | Drei `OnSizeChanged` in einem Frame → **ein** geplanter Durchlauf, ein `fn`-Aufruf |
| `testRefreshOnResize_ReschedulesAfterRun` | Nach dem Durchlauf greift der nächste Resize wieder |
| `testRefreshOnResize_NilArgsAreNoOp` | Fehlender Frame oder fehlende Funktion → `nil`, kein Error |

---

## Tests erweitern

Neue Tests nutzen den `NewCountingPool()`-Helper oder bauen eigene `createFn`/`resetFn`-Paare mit Zählern. Frame-Verhalten (Hide, Anker, Scripts) gehört **nicht** hierher — das lebt in den `resetFn`s der jeweiligen Tab-Dateien und wird in-game verifiziert.
