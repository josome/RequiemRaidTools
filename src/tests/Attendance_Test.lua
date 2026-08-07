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
    --- Ein Raid darf zusätzlich kills = { { boss, ts, participants = {…} }, … } tragen —
    --- das ist die Boss-Ebene aus GL.RecordKillAttendance (Phase 1b). Ohne kills greift
    --- der Fallback für Altdaten.
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
                    kills        = raid.kills,
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
    -- Boss-Ebene (raidMeta[*].kills, Phase 1b)
    -- ========================================================
    function Tests:testComputeAttendance_KillsPerBossWhenRecorded()
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = {
                { id = "r1", participants = { "Alice-R", "Bob-R" }, kills = {
                    { boss = "Ulgrax", ts = 110, participants = { "Alice-R" } },
                    { boss = "Sikran", ts = 120, participants = { "Alice-R", "Bob-R" } },
                } },
            } },
        }), function()
            MockRoster({})
            local night = GL.ComputeAttendance("s1").nights[1]
            -- eine Spalte je Bosskill statt einer je Abend
            AreEqual(2,        #night.kills)
            AreEqual("Ulgrax", night.kills[1].name)
            AreEqual("Sikran", night.kills[2].name)
            AreEqual("r1#1",   night.kills[1].id)
            AreEqual("r1#2",   night.kills[2].id)
        end)
    end

    function Tests:testComputeAttendance_LateJoinerPresentOnlyFromHisKill()
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = {
                { id = "r1", participants = { "Alice-R", "Bob-R" }, kills = {
                    { boss = "Ulgrax", ts = 110, participants = { "Alice-R" } },
                    { boss = "Sikran", ts = 120, participants = { "Alice-R", "Bob-R" } },
                } },
            } },
        }), function()
            MockRoster({ { name = "Bob-R", class = "ROGUE", group = "roster" } })
            local result = GL.ComputeAttendance("s1")
            local bob    = RowByName(result, "Bob-R")
            AreEqual(nil, bob.present["r1#1"])          -- beim ersten Boss noch nicht da
            IsTrue(bob.present["r1#2"])
            IsTrue(bob.present[result.nights[1].id])    -- der Abend zählt trotzdem
            AreEqual(1, bob.attended)                   -- und zwar genau einmal
        end)
    end

    function Tests:testComputeAttendance_KillsSortedByTimestamp()
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = {
                { id = "r1", participants = {}, kills = {
                    { boss = "Zweiter", ts = 200, participants = {} },
                } },
                { id = "r2", participants = {}, kills = {
                    { boss = "Erster", ts = 150, participants = {} },
                } },
            } },
        }), function()
            MockRoster({})
            local night = GL.ComputeAttendance("s1").nights[1]
            AreEqual("Erster",  night.kills[1].name)
            AreEqual("Zweiter", night.kills[2].name)
        end)
    end

    function Tests:testComputeAttendance_FallsBackToNightLevelWithoutKills()
        -- Altdaten von vor Phase 1b und Observer-Sessions: kills fehlt, die Abend-Ebene
        -- muss unverändert funktionieren
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = { { id = "r1", participants = { "Alice-R" } } } },
        }), function()
            MockRoster({ { name = "Alice-R", class = "MAGE", group = "roster" } })
            local result = GL.ComputeAttendance("s1")
            local alice  = RowByName(result, "Alice-R")
            AreEqual(1,    #result.nights[1].kills)
            AreEqual("r1", result.nights[1].kills[1].id)
            IsTrue(alice.present["r1"])
            AreEqual(1, alice.attended)
        end)
    end

    function Tests:testComputeAttendance_EmptyKillsListUsesFallback()
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = {
                { id = "r1", participants = { "Alice-R" }, kills = {} },
            } },
        }), function()
            MockRoster({ { name = "Alice-R", class = "MAGE", group = "roster" } })
            local result = GL.ComputeAttendance("s1")
            AreEqual(1,    #result.nights[1].kills)
            AreEqual("r1", result.nights[1].kills[1].id)
            IsTrue(RowByName(result, "Alice-R").present["r1"])
        end)
    end

    -- ========================================================
    -- Spaltenliste (BuildAttendanceColumns)
    -- ========================================================

    --- Abende, wie ComputeAttendance sie liefert — ohne DB, die Funktion ist pur.
    local function Nights(spec)
        local nights = {}
        for _, n in ipairs(spec) do
            local kills = {}
            for i, k in ipairs(n.kills or {}) do
                table.insert(kills, { id = n.id .. "#" .. i, name = k.name, ts = k.ts or 0 })
            end
            table.insert(nights, {
                id = n.id, label = n.label or "", startedAt = n.startedAt or 0, kills = kills,
            })
        end
        return nights
    end

    function Tests:testBuildColumns_CollapsedGivesOneColumnPerNight()
        local cols = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = 100, kills = { { name = "A" }, { name = "B" } } },
            { id = "n2", startedAt = 200, kills = { { name = "C" } } },
        }), {})
        AreEqual(2,     #cols)
        AreEqual("n1",  cols[1].key)
        AreEqual("n2",  cols[2].key)
        IsFalse(cols[1].isKill)
    end

    function Tests:testBuildColumns_ExpandedGivesOneColumnPerKill()
        local cols = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = 100, kills = { { name = "A" }, { name = "B" } } },
            { id = "n2", startedAt = 200, kills = { { name = "C" }, { name = "D" } } },
        }), { n1 = true })
        -- n1 aufgeklappt (2 Spalten) + n2 eingeklappt (1 Spalte)
        AreEqual(3,      #cols)
        AreEqual("n1#1", cols[1].key)
        AreEqual("n1#2", cols[2].key)
        AreEqual("n2",   cols[3].key)
        AreEqual("1",    cols[1].label)
        AreEqual("2",    cols[2].label)
        IsTrue(cols[1].isKill)
        IsFalse(cols[3].isKill)
    end

    function Tests:testBuildColumns_SingleKillNightIsNotExpandable()
        local nights = Nights({
            { id = "n1", startedAt = 100, kills = { { name = "A" } } },
        })
        -- auch explizit aufgeklappt bleibt es eine Abend-Spalte
        local cols = GL.BuildAttendanceColumns(nights, { n1 = true })
        AreEqual(1,    #cols)
        AreEqual("n1", cols[1].key)
        IsFalse(cols[1].expandable)
        IsFalse(cols[1].isKill)
    end

    function Tests:testBuildColumns_ExpandableFlagFollowsKillCount()
        local cols = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = 100, kills = { { name = "A" }, { name = "B" } } },
            { id = "n2", startedAt = 200, kills = { { name = "C" } } },
        }), {})
        IsTrue(cols[1].expandable)
        IsFalse(cols[2].expandable)
    end

    function Tests:testBuildColumns_GroupStartOnFirstColumnOfEachNight()
        local cols = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = 100, kills = { { name = "A" }, { name = "B" } } },
            { id = "n2", startedAt = 200, kills = { { name = "C" } } },
        }), { n1 = true })
        IsTrue(cols[1].groupStart)
        IsFalse(cols[2].groupStart)   -- zweite Bossspalte desselben Abends
        IsTrue(cols[3].groupStart)
    end

    function Tests:testBuildColumns_NightIdOnEveryColumn()
        local cols = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = 100, kills = { { name = "A" }, { name = "B" } } },
        }), { n1 = true })
        -- der Klick-Handler braucht den Abend auch auf den Bossspalten (Zuklappen)
        AreEqual("n1", cols[1].nightId)
        AreEqual("n1", cols[2].nightId)
    end

    function Tests:testBuildColumns_KeepsNightOrder()
        local cols = GL.BuildAttendanceColumns(Nights({
            { id = "neu", startedAt = 300, kills = { { name = "A" } } },
            { id = "alt", startedAt = 100, kills = { { name = "B" } } },
        }), {})
        -- ComputeAttendance sortiert bereits (neueste zuerst); hier wird nicht umsortiert
        AreEqual("neu", cols[1].key)
        AreEqual("alt", cols[2].key)
    end

    function Tests:testBuildColumns_EmptyAndNilInputs()
        AreEqual(0, #GL.BuildAttendanceColumns({}, {}))
        AreEqual(0, #GL.BuildAttendanceColumns(nil, nil))
        -- expanded weglassen darf nicht werfen
        AreEqual(1, #GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = 100, kills = { { name = "A" } } },
        })))
    end

    function Tests:testBuildColumns_LabelsAndTooltips()
        local cols = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = 100, label = "Mittwoch",
              kills = { { name = "Ulgrax", ts = 110 }, { name = "Sikran", ts = 120 } } },
        }), {})
        AreEqual("Mittwoch", cols[1].tooltipT)
        Exists(cols[1].tooltipD:find("2 Bosse"))    -- Aufklapp-Hinweis

        local open = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = 100,
              kills = { { name = "Ulgrax", ts = 110 }, { name = "Sikran", ts = 120 } } },
        }), { n1 = true })
        AreEqual("Ulgrax", open[1].tooltipT)
        AreEqual("Sikran", open[2].tooltipT)
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
