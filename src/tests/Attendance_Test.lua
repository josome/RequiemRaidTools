-- RequiemRaidTools — src/tests/Attendance_Test.lua
-- Unit-Tests für das Attendance-Aggregat (src/core/Core_Attendance.lua) via WoWUnit.
--
-- VORAUSSETZUNGEN
--   1. WoWUnit-Addon installiert (OptionalDep in der TOC) — in-game.
--   2. devMode aktiv: /reqrt devmode → /reload — in-game.
-- Läuft auch standalone über busted (spec/reqrt_spec.lua).

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests = WoWUnit("ReqRT.Attendance")
    local GL    = GuildLoot

    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue
    local IsFalse  = WoWUnit.IsFalse
    local Exists   = WoWUnit.Exists

    -- --------------------------------------------------------
    -- Setup
    -- --------------------------------------------------------
    local _mocks = {}
    local function Mock(tbl, key, fn)
        table.insert(_mocks, { tbl = tbl, key = key, orig = tbl[key] })
        tbl[key] = fn
    end
    local function MockRestore()
        for i = #_mocks, 1, -1 do
            local m = _mocks[i]
            m.tbl[m.key] = m.orig
        end
        _mocks = {}
    end

    local function WithDB(db, fn)
        local origDB = GuildLootDB
        GuildLootDB = db
        local ok, err = pcall(fn)
        GuildLootDB = origDB
        MockRestore()
        if not ok then error(err, 2) end
    end

    --- Baut eine DB mit Season "s1" und Raid-Sessions.
    --- sessions: Array von { startedAt, label, raids = { { id, participants = {…} }, … } }
    --- Das Gilden-Roster wird über GL.GetSeasonRoster gemockt (roster = Array von
    --- { name, class, group }), damit das Aggregat isoliert testbar bleibt.
    local function AttendanceDB(seasonFields, sessions, players)
        local season = {
            id = "s1", name = "S", rankFilter = {},
            startedAt = 0, endedAt = nil,
        }
        for k, v in pairs(seasonFields or {}) do season[k] = v end

        local containers = {}
        for i, s in ipairs(sessions or {}) do
            local meta = {}
            for _, raid in ipairs(s.raids or {}) do
                meta[raid.id] = {
                    startedAt    = raid.ts or s.startedAt,
                    participants = raid.participants or {},
                }
            end
            containers[i] = {
                id        = "c" .. i,
                label     = s.label or ("Session " .. i),
                startedAt = s.startedAt,
                raidMeta  = meta,
            }
        end
        return {
            seasons        = { ["s1"] = season },
            raidContainers = containers,
            players        = players or {},
        }
    end

    --- Mockt die Zeilen-Achse (sonst bräuchte jeder Test die Gilden-API).
    local function MockRoster(rows)
        Mock(GL, "GetSeasonRoster", function() return rows end)
    end

    local function RowByName(result, name)
        for _, r in ipairs(result.rows) do
            if r.name == name then return r end
        end
    end

    -- ========================================================
    -- Leer- und Fehlerfälle
    -- ========================================================
    function Tests:testComputeAttendance_UnknownSeason_EmptyResult()
        WithDB(AttendanceDB({}, {}), function()
            local result = GL.ComputeAttendance("nope")
            Exists(result)
            AreEqual(nil, result.season)
            AreEqual(0, #result.nights)
            AreEqual(0, #result.rows)
        end)
    end

    function Tests:testComputeAttendance_NoDB_EmptyResult()
        local origDB = GuildLootDB
        GuildLootDB = nil
        local ok, err = pcall(function()
            local result = GL.ComputeAttendance("s1")
            Exists(result)
            AreEqual(0, #result.nights)
            AreEqual(0, #result.rows)
        end)
        GuildLootDB = origDB
        if not ok then error(err, 2) end
    end

    function Tests:testComputeAttendance_SeasonWithoutRaids_RowsButNoNights()
        WithDB(AttendanceDB({}, {}), function()
            MockRoster({ { name = "Alice-R", class = "MAGE", group = "roster" } })
            local result = GL.ComputeAttendance("s1")
            AreEqual(0, #result.nights)
            AreEqual(1, #result.rows)
            AreEqual(0, result.rows[1].total)
            AreEqual(0, result.rows[1].pct)   -- keine Division durch null
        end)
    end

    -- ========================================================
    -- Spalten (nights) und Season-Fenster
    -- ========================================================
    function Tests:testComputeAttendance_NightsNewestFirst()
        WithDB(AttendanceDB({ startedAt = 0 }, {
            { startedAt = 100, label = "Alt" },
            { startedAt = 300, label = "Neu" },
            { startedAt = 200, label = "Mitte" },
        }), function()
            MockRoster({})
            local nights = GL.ComputeAttendance("s1").nights
            AreEqual(3, #nights)
            AreEqual("Neu",   nights[1].label)
            AreEqual("Mitte", nights[2].label)
            AreEqual("Alt",   nights[3].label)
        end)
    end

    function Tests:testComputeAttendance_SeasonWindowFiltersNights()
        WithDB(AttendanceDB({ startedAt = 100, endedAt = 900 }, {
            { startedAt = 50,   label = "davor" },
            { startedAt = 500,  label = "drin" },
            { startedAt = 1000, label = "danach" },
        }), function()
            MockRoster({})
            local nights = GL.ComputeAttendance("s1").nights
            AreEqual(1, #nights)
            AreEqual("drin", nights[1].label)
        end)
    end

    function Tests:testComputeAttendance_NightCarriesKills()
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = {
                { id = "r1", participants = { "Alice-R" } },
            } },
        }), function()
            MockRoster({})
            local night = GL.ComputeAttendance("s1").nights[1]
            AreEqual(1, #night.kills)
            AreEqual("r1", night.kills[1].id)
        end)
    end

    -- ========================================================
    -- Präsenz und Att.%
    -- ========================================================
    function Tests:testComputeAttendance_PctFromAttendedNights()
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = { { id = "r1", participants = { "Alice-R" } } } },
            { startedAt = 200, raids = { { id = "r2", participants = { "Alice-R" } } } },
            { startedAt = 300, raids = { { id = "r3", participants = { "Bob-R" } } } },
            { startedAt = 400, raids = { { id = "r4", participants = { "Bob-R" } } } },
        }), function()
            MockRoster({
                { name = "Alice-R", class = "MAGE",    group = "roster" },
                { name = "Bob-R",   class = "WARRIOR", group = "roster" },
            })
            local result = GL.ComputeAttendance("s1")
            local alice  = RowByName(result, "Alice-R")
            AreEqual(4, alice.total)
            AreEqual(2, alice.attended)
            AreEqual(50, alice.pct)
        end)
    end

    function Tests:testComputeAttendance_PresentPerNightAndKill()
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = { { id = "r1", participants = { "Alice-R" } } } },
        }), function()
            MockRoster({ { name = "Alice-R", class = "MAGE", group = "roster" } })
            local result = GL.ComputeAttendance("s1")
            local night  = result.nights[1]
            local alice  = RowByName(result, "Alice-R")
            IsTrue(alice.present[night.id])    -- Session-Ebene
            IsTrue(alice.present["r1"])        -- Kill-Ebene
        end)
    end

    function Tests:testComputeAttendance_SessionPresenceIsUnionOfKills()
        -- nur beim zweiten Kill dabei → Session zählt trotzdem als anwesend
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = {
                { id = "r1", participants = { "Bob-R" } },
                { id = "r2", participants = { "Alice-R" } },
            } },
        }), function()
            MockRoster({ { name = "Alice-R", class = "MAGE", group = "roster" } })
            local result = GL.ComputeAttendance("s1")
            local alice  = RowByName(result, "Alice-R")
            IsTrue(alice.present[result.nights[1].id])
            IsTrue(alice.present["r2"])
            AreEqual(nil, alice.present["r1"])
            AreEqual(1, alice.attended)
        end)
    end

    function Tests:testComputeAttendance_RosterMemberWithoutAttendanceIsZero()
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = { { id = "r1", participants = { "Alice-R" } } } },
        }), function()
            MockRoster({
                { name = "Alice-R",  class = "MAGE",   group = "roster" },
                { name = "Niemand-R", class = "DRUID", group = "roster" },
            })
            local nobody = RowByName(GL.ComputeAttendance("s1"), "Niemand-R")
            Exists(nobody)                 -- bleibt sichtbar — das ist die Information
            AreEqual(0, nobody.attended)
            AreEqual(0, nobody.pct)
            AreEqual(1, nobody.total)
        end)
    end

    -- ========================================================
    -- Gruppen und Trial
    -- ========================================================
    function Tests:testComputeAttendance_KeepsRosterOrderAndGroups()
        WithDB(AttendanceDB({}, {}), function()
            MockRoster({
                { name = "Kader-R", class = "MAGE",  group = "roster" },
                { name = "Gast-R",  class = "ROGUE", group = "guest" },
            })
            local rows = GL.ComputeAttendance("s1").rows
            AreEqual("Kader-R", rows[1].name)
            AreEqual("roster",  rows[1].group)
            AreEqual("Gast-R",  rows[2].name)
            AreEqual("guest",   rows[2].group)
            AreEqual("MAGE",    rows[1].class)
        end)
    end

    function Tests:testComputeAttendance_TrialFlagFromPlayersDB()
        WithDB(AttendanceDB({}, {}, {
            ["Neu-R"] = { trial = true },
            ["Alt-R"] = { trial = false },
        }), function()
            MockRoster({
                { name = "Neu-R", group = "roster" },
                { name = "Alt-R", group = "roster" },
            })
            local result = GL.ComputeAttendance("s1")
            IsTrue(RowByName(result, "Neu-R").trial)
            IsFalse(RowByName(result, "Alt-R").trial)
        end)
    end

    function Tests:testComputeAttendance_UnknownPlayerHasNoTrial()
        WithDB(AttendanceDB({}, {}), function()
            MockRoster({ { name = "Fremd-R", group = "guest" } })
            IsFalse(RowByName(GL.ComputeAttendance("s1"), "Fremd-R").trial)
        end)
    end
end)
