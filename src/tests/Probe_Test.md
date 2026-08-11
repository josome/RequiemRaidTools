# Probe_Test — Smoke-Test

**Suite:** `ReqRT.Probe`

## Zweck

Stellt sicher dass der Testrunner korrekt geladen ist und die Assertion-Helfer grundsätzlich funktionieren. Schlägt dieser Test fehl, liegt das Problem am Test-Setup (Shim/Loader), nicht beim Addon-Code.

## Testfälle

| Test | Was geprüft wird |
|------|-----------------|
| `testSmokeGreen` | `AreEqual(1,1)` und `IsTrue(true)` — Testrunner läuft |

## Infrastruktur

Kein `WithTestDB`, keine Mocks — reiner Assertions-Smoke-Test.
