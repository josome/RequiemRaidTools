# Probe_Test — Smoke-Test

**Suite:** `ReqRT.Probe`

## Zweck

Stellt sicher dass WoWUnit korrekt geladen ist und die Assertion-Helfer grundsätzlich funktionieren. Schlägt dieser Test fehl, liegt das Problem bei WoWUnit selbst, nicht beim Addon-Code.

## Testfälle

| Test | Was geprüft wird |
|------|-----------------|
| `testSmokeGreen` | `AreEqual(1,1)` und `IsTrue(true)` — WoWUnit läuft |

## Infrastruktur

Kein `WithTestDB`, keine Mocks — reiner Assertions-Smoke-Test.
