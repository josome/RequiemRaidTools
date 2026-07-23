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
dofile("src/tests/Util_Test.lua")
dofile("src/tests/Roll_Test.lua")
dofile("src/tests/Migration_Test.lua")
dofile("src/tests/Loot_Test.lua")
dofile("src/tests/Export_Test.lua")
dofile("src/tests/Pool_Test.lua")

-- ADDON_LOADED feuern → alle _loader-Frames registrieren ihre Suites bei WoWUnit
FireEvent("ADDON_LOADED", "RequiemRaidTools")

-- Suites bei busted als describe/it registrieren
WoWUnit.RegisterWithBusted(describe, it)

-- ============================================================
-- API-Snapshot — fängt Load-Order-Regressionen ab (Paket D1).
-- Wenn Core.lua aufgespalten wird, müssen all diese Funktionen
-- weiterhin nach dem Load existieren. Schlägt an, sobald eine
-- Funktion fehlt oder vor Definition referenziert wurde.
-- ============================================================
describe("ReqRT.API", function()
    local function expectFunction(path)
        it(path .. " ist definiert", function()
            local cur = _G.GuildLoot
            assert(cur ~= nil, "GuildLoot nicht geladen")
            for segment in path:gmatch("[^%.]+") do
                if segment == "GuildLoot" then
                    -- skip
                else
                    cur = cur[segment]
                    assert(cur ~= nil, path .. " — Segment '" .. segment .. "' ist nil")
                end
            end
            assert(type(cur) == "function",
                path .. " ist " .. type(cur) .. ", erwartet function")
        end)
    end

    -- Core / Session
    expectFunction("GuildLoot.StartContainer")
    expectFunction("GuildLoot.CloseContainer")
    expectFunction("GuildLoot.ResetCurrentRaid")
    expectFunction("GuildLoot.LoadRaidRoster")
    expectFunction("GuildLoot.EnsureRaidMeta")

    -- Util
    expectFunction("GuildLoot.ShortName")
    expectFunction("GuildLoot.GetActivePrios")
    expectFunction("GuildLoot.GetPrioLabel")
    expectFunction("GuildLoot.ParseLootInput")

    -- Comm
    expectFunction("GuildLoot.Comm.OnMessage")
    expectFunction("GuildLoot.Comm.SendAssign")
    expectFunction("GuildLoot.Comm.SendSessionStart")
    expectFunction("GuildLoot.Comm.SendMLAnnounce")

    -- Loot
    expectFunction("GuildLoot.Loot.AssignLootConfirm")
    expectFunction("GuildLoot.Loot.OnCommAssign")
end)
