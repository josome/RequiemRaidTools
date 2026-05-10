-- spec/reqrt_spec.lua
-- busted Entry Point für RequiemRaidTools Unit-Tests.
-- Lädt WoW-Stubs, Source-Dateien und Test-Dateien, dann feuert ADDON_LOADED
-- damit alle Test-Suites sich bei WoWUnit registrieren.

dofile("tests/standalone/wow_stubs.lua")
dofile("tests/standalone/wowunit_shim.lua")
dofile("tests/standalone/loader.lua")

dofile("src/tests/Probe_Test.lua")
dofile("src/tests/Comm_Test.lua")
dofile("src/tests/Assign_Test.lua")
dofile("src/tests/Session_Test.lua")
dofile("src/tests/Trade_Test.lua")
dofile("src/tests/Filter_Test.lua")

-- ADDON_LOADED feuern → alle _loader-Frames registrieren ihre Suites bei WoWUnit
FireEvent("ADDON_LOADED", "RequiemRaidTools")

-- Suites bei busted als describe/it registrieren
WoWUnit.RegisterWithBusted(describe, it)
