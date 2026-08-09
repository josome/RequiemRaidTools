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

    --- Zeitstempel im August 2026. Seit die Abende nach Raid-Tag gruppiert werden, müssen
    --- Fixtures echte Tagesabstände haben — Werte wie 100/200 lägen alle am selben Tag.
    local function TS(day, hour, min)
        return time({ year = 2026, month = 8, day = day,
                      hour = hour or 20, min = min or 0, sec = 0 })
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
                -- Quelle der BIS-Sterne; Einträge wie in Loot_Assign geschrieben
                lootLog   = s.lootLog or {},
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
            { startedAt = TS(1), label = "Alt" },
            { startedAt = TS(3), label = "Neu" },
            { startedAt = TS(2), label = "Mitte" },
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
        WithDB(AttendanceDB({ startedAt = TS(2), endedAt = TS(4) }, {
            { startedAt = TS(1), label = "davor" },
            { startedAt = TS(3), label = "drin" },
            { startedAt = TS(5), label = "danach" },
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

    function Tests:testComputeAttendance_PresenceMatchesDespiteRealmSpacing()
        -- Kader kommt aus dem Gildenroster (Realm mit Leerzeichen), die Kill-Teilnehmer
        -- aus der Raid-API (ohne). Ohne kanonischen Schlüssel bliebe die Zeile auf 0 %.
        WithDB(AttendanceDB({}, {
            { startedAt = TS(3), raids = {
                { id = "r1", participants = { "Barbossbär-DerMithrilorden" }, kills = {
                    { boss = "A", ts = TS(3, 21),
                      participants = { "Barbossbär-DerMithrilorden" },
                      trials       = { ["Barbossbär-DerMithrilorden"] = true } },
                } },
            } },
        }), function()
            MockRoster({ { name = "Barbossbär-Der Mithrilorden", group = "roster" } })
            local result = GL.ComputeAttendance("s1")
            local row    = result.rows[1]
            AreEqual(1, row.attended)
            AreEqual(100, row.pct)
            IsTrue(row.present[result.nights[1].id])
            IsTrue(row.trialAt["r1#1"])
        end)
    end

    -- ========================================================
    -- BIS-Gewinne (bisAt) — aus dem lootLog abgeleitet, nicht gespeichert
    -- ========================================================

    --- Season mit einem Abend, zwei Bosskills, und dem übergebenen lootLog.
    local function BisDB(lootLog, kills)
        return AttendanceDB({}, {
            { startedAt = TS(3), lootLog = lootLog, raids = {
                { id = "r1", participants = { "Alice-R" }, kills = kills or {
                    { boss = "Ulgrax", ts = TS(3, 21), participants = { "Alice-R" } },
                    { boss = "Sikran", ts = TS(3, 22), participants = { "Alice-R" } },
                } },
            } },
        })
    end

    function Tests:testComputeAttendance_BisMarksKillAndNight()
        WithDB(BisDB({
            { player = "Alice-R", winnerPrio = 1, boss = "Sikran",
              raidID = "r1", timestamp = TS(3, 22) },
        }), function()
            MockRoster({ { name = "Alice-R", group = "roster" } })
            local result = GL.ComputeAttendance("s1")
            local row    = result.rows[1]
            IsTrue(row.bisAt["r1#2"])                      -- der betroffene Kill
            IsTrue(row.bisAt[result.nights[1].id])         -- und der Abend
            AreEqual(nil, row.bisAt["r1#1"])               -- der andere Boss nicht
        end)
    end

    function Tests:testComputeAttendance_NonBisPrioIsIgnored()
        WithDB(BisDB({
            { player = "Alice-R", winnerPrio = 2, boss = "Sikran",
              raidID = "r1", timestamp = TS(3, 22) },
        }), function()
            MockRoster({ { name = "Alice-R", group = "roster" } })
            local row = GL.ComputeAttendance("s1").rows[1]
            AreEqual(nil, row.bisAt["r1#2"])
        end)
    end

    function Tests:testComputeAttendance_BisPrioAsStringCounts()
        -- Über Comm kommt winnerPrio als String an (Loot.OnCommAssign)
        WithDB(BisDB({
            { player = "Alice-R", winnerPrio = "1", boss = "Sikran",
              raidID = "r1", timestamp = TS(3, 22) },
        }), function()
            MockRoster({ { name = "Alice-R", group = "roster" } })
            IsTrue(GL.ComputeAttendance("s1").rows[1].bisAt["r1#2"])
        end)
    end

    function Tests:testComputeAttendance_BisWithUnknownBossOrRaidMissesAll()
        WithDB(BisDB({
            { player = "Alice-R", winnerPrio = 1, boss = "Fremd",  raidID = "r1" },
            { player = "Alice-R", winnerPrio = 1, boss = "Sikran", raidID = "r9" },
        }), function()
            MockRoster({ { name = "Alice-R", group = "roster" } })
            local row = GL.ComputeAttendance("s1").rows[1]
            AreEqual(nil, row.bisAt["r1#1"])
            AreEqual(nil, row.bisAt["r1#2"])
        end)
    end

    function Tests:testComputeAttendance_BisPicksKillBeforeTimestamp()
        -- derselbe Boss zweimal im selben raidID → der Kill VOR dem Loot gewinnt
        WithDB(BisDB({
            { player = "Alice-R", winnerPrio = 1, boss = "Ulgrax",
              raidID = "r1", timestamp = TS(3, 23) },
        }, {
            { boss = "Ulgrax", ts = TS(3, 21), participants = { "Alice-R" } },
            { boss = "Ulgrax", ts = TS(3, 22), participants = { "Alice-R" } },
            { boss = "Ulgrax", ts = TS(4, 10), participants = { "Alice-R" } },
        }), function()
            MockRoster({ { name = "Alice-R", group = "roster" } })
            local row = GL.ComputeAttendance("s1").rows[1]
            AreEqual(nil, row.bisAt["r1#1"])
            IsTrue(row.bisAt["r1#2"])          -- letzter Kill vor dem Zeitstempel
            AreEqual(nil, row.bisAt["r1#3"])   -- der danach nicht
        end)
    end

    function Tests:testComputeAttendance_BisMatchesDespiteRealmSpacing()
        WithDB(BisDB({
            { player = "Alice-DerMithrilorden", winnerPrio = 1, boss = "Sikran",
              raidID = "r1", timestamp = TS(3, 22) },
        }, {
            { boss = "Sikran", ts = TS(3, 22),
              participants = { "Alice-DerMithrilorden" } },
        }), function()
            MockRoster({ { name = "Alice-Der Mithrilorden", group = "roster" } })
            IsTrue(GL.ComputeAttendance("s1").rows[1].bisAt["r1#1"])
        end)
    end

    -- ========================================================
    -- Trial-Stand zum Zeitpunkt des Kills (trialAt)
    -- ========================================================
    function Tests:testComputeAttendance_TrialAtFromRecordedKill()
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = {
                { id = "r1", participants = { "Neu-R", "Alt-R" }, kills = {
                    { boss = "Ulgrax", ts = 110,
                      participants = { "Neu-R", "Alt-R" },
                      trials       = { ["Neu-R"] = true } },
                } },
            } },
        }), function()
            MockRoster({
                { name = "Neu-R", group = "roster" },
                { name = "Alt-R", group = "roster" },
            })
            local result = GL.ComputeAttendance("s1")
            IsTrue(RowByName(result, "Neu-R").trialAt["r1#1"])
            IsFalse(RowByName(result, "Alt-R").trialAt["r1#1"])
        end)
    end

    function Tests:testComputeAttendance_TrialAtIgnoresLaterPromotion()
        -- Kill 1 als Trial, Kill 2 nach der Beförderung — der alte Kill bleibt Trial,
        -- obwohl db.players heute kein trial mehr sagt
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = {
                { id = "r1", participants = { "Neu-R" }, kills = {
                    { boss = "A", ts = 110, participants = { "Neu-R" },
                      trials = { ["Neu-R"] = true } },
                    { boss = "B", ts = 120, participants = { "Neu-R" }, trials = {} },
                } },
            } },
        }, { ["Neu-R"] = { trial = false } }), function()
            MockRoster({ { name = "Neu-R", group = "roster" } })
            local row = RowByName(GL.ComputeAttendance("s1"), "Neu-R")
            IsTrue(row.trialAt["r1#1"])
            IsFalse(row.trialAt["r1#2"])
            IsFalse(row.trial)              -- aktuelles Flag steuert nur die Checkbox
        end)
    end

    function Tests:testComputeAttendance_TrialAtNightIsTrueIfAnyKillWasTrial()
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = {
                { id = "r1", participants = { "Neu-R" }, kills = {
                    { boss = "A", ts = 110, participants = { "Neu-R" }, trials = {} },
                    { boss = "B", ts = 120, participants = { "Neu-R" },
                      trials = { ["Neu-R"] = true } },
                } },
            } },
        }), function()
            MockRoster({ { name = "Neu-R", group = "roster" } })
            local result = GL.ComputeAttendance("s1")
            IsTrue(RowByName(result, "Neu-R").trialAt[result.nights[1].id])
        end)
    end

    function Tests:testComputeAttendance_TrialAtEmptyForUnrecordedKills()
        -- Altdaten ohne trials-Tabelle → kein Eintrag. Das aktuelle Flag darf hier NICHT
        -- einspringen: sonst färbt das Setzen des Hakens die ganze Historie blau.
        WithDB(AttendanceDB({}, {
            { startedAt = 100, raids = { { id = "r1", participants = { "Neu-R" } } } },
        }, { ["Neu-R"] = { trial = true } }), function()
            MockRoster({ { name = "Neu-R", group = "roster" } })
            local row = RowByName(GL.ComputeAttendance("s1"), "Neu-R")
            AreEqual(nil, row.trialAt["r1"])
            IsTrue(row.trial)   -- steuert nur die Checkbox, nicht die Zellfarbe
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
                table.insert(kills, { id = n.id .. "#" .. i, name = k.name, ts = k.ts or 0,
                                      difficulty = k.difficulty, tier = k.tier })
            end
            -- BuildAttendanceColumns interessiert sich nicht für trials
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
        -- Label ist der volle Bossname; die UI kürzt ihn auf die Spaltenbreite
        AreEqual("A",    cols[1].label)
        AreEqual("B",    cols[2].label)
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
        -- Bossname steht auch als Label bereit, nicht nur im Tooltip
        AreEqual("Ulgrax", open[1].label)
    end

    function Tests:testBuildColumns_InstanceStartOnTierChange()
        local cols = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = TS(3), kills = {
                { name = "Ulgrax", tier = "Nerub-ar" },
                { name = "Sikran", tier = "Nerub-ar" },
                { name = "Kyveza", tier = "Castle Nathria" },
                { name = "Sludge",  tier = "Castle Nathria" },
            } },
        }), { n1 = true })
        IsFalse(cols[1].instanceStart)   -- erste Spalte trägt schon den Gruppentrenner
        IsFalse(cols[2].instanceStart)
        IsTrue(cols[3].instanceStart)    -- Wechsel der Raidinstanz
        IsFalse(cols[4].instanceStart)
    end

    function Tests:testBuildColumns_SameInstanceDifferentDifficultyHasNoLine()
        -- drei Durchläufe derselben Instanz auf N/H/M sind EINE Instanz — die Difficulty
        -- unterscheidet die Tönung, nicht der Trennstrich
        local cols = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = TS(3), kills = {
                { name = "Ulgrax", tier = "Nerub-ar", difficulty = "N" },
                { name = "Ulgrax", tier = "Nerub-ar", difficulty = "H" },
                { name = "Ulgrax", tier = "Nerub-ar", difficulty = "M" },
            } },
        }), { n1 = true })
        IsFalse(cols[2].instanceStart)
        IsFalse(cols[3].instanceStart)
    end

    function Tests:testBuildColumns_GroupLabelIsSessionName()
        local nights = Nights({
            { id = "n1", startedAt = TS(3), label = "RW 05.08. – 11.08.",
              kills = { { name = "A" }, { name = "B" } } },
        })
        -- eingeklappt wie aufgeklappt: jede Spalte kennt den Session-Namen, die UI
        -- schreibt ihn über die aufgeklappte Gruppe
        AreEqual("RW 05.08. – 11.08.", GL.BuildAttendanceColumns(nights, {})[1].groupLabel)
        local open = GL.BuildAttendanceColumns(nights, { n1 = true })
        AreEqual("RW 05.08. – 11.08.", open[1].groupLabel)
        AreEqual("RW 05.08. – 11.08.", open[2].groupLabel)
    end

    function Tests:testBuildColumns_GroupLabelFallsBackToDate()
        -- Session ohne Namen: die Gruppe darf nicht unbeschriftet bleiben
        local cols = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = TS(3), kills = { { name = "A" }, { name = "B" } } },
        }), { n1 = true })
        AreEqual("03.08", cols[1].groupLabel)
    end

    function Tests:testBuildColumns_KillColumnsCarryDeleteHandles()
        WithDB(AttendanceDB({}, {
            { startedAt = TS(3), raids = {
                { id = "r1", participants = { "A-R" }, kills = {
                    { boss = "A", ts = TS(3, 21), participants = { "A-R" } },
                    { boss = "B", ts = TS(3, 22), participants = { "A-R" } },
                } },
            } },
        }), function()
            MockRoster({})
            local night = GL.ComputeAttendance("s1").nights[1]
            local cols  = GL.BuildAttendanceColumns({ night }, { [night.id] = true })
            -- der Tab braucht den Rückweg zu den Daten, um einen Kill zu löschen
            AreEqual("c1", cols[1].sessionId)
            AreEqual("r1", cols[1].raidID)
            AreEqual(1,    cols[1].killIndex)
            AreEqual(2,    cols[2].killIndex)
        end)
    end

    function Tests:testBuildColumns_EmptyDayCarriesSessionsToDelete()
        WithDB(AttendanceDB({}, {
            -- Session ohne jeden Bosskill — die Spalte erscheint trotzdem
            { startedAt = TS(3), raids = {} },
        }), function()
            MockRoster({})
            local result = GL.ComputeAttendance("s1")
            local cols   = GL.BuildAttendanceColumns(result.nights, {})
            AreEqual(1,    #cols)
            AreEqual(1,    #cols[1].emptySessions)
            AreEqual("c1", cols[1].emptySessions[1])
        end)
    end

    function Tests:testBuildColumns_SingleEntryNightIsDeletable()
        -- Altdaten ohne Kill-Ebene: ein raidMeta, kein kills-Array. Die Spalte lässt sich
        -- nicht aufklappen, muss aber löschbar sein — killIndex bleibt nil, damit der
        -- ganze raidMeta-Eintrag geht.
        WithDB(AttendanceDB({}, {
            { startedAt = TS(3), raids = { { id = "r1", participants = { "A-R" } } } },
        }), function()
            MockRoster({})
            local cols = GL.BuildAttendanceColumns(GL.ComputeAttendance("s1").nights, {})
            AreEqual(1,    #cols)
            IsFalse(cols[1].expandable)
            AreEqual("c1", cols[1].sessionId)
            AreEqual("r1", cols[1].raidID)
            AreEqual(nil,  cols[1].killIndex)
        end)
    end

    function Tests:testBuildColumns_MultiEntryNightIsNotDeletable()
        -- Mehrere Kills hinter einer eingeklappten Spalte → mehrdeutig, kein Rückweg
        WithDB(AttendanceDB({}, {
            { startedAt = TS(3), raids = {
                { id = "r1", participants = { "A-R" }, kills = {
                    { boss = "A", ts = TS(3, 21), participants = { "A-R" } },
                    { boss = "B", ts = TS(3, 22), participants = { "A-R" } },
                } },
            } },
        }), function()
            MockRoster({})
            local cols = GL.BuildAttendanceColumns(GL.ComputeAttendance("s1").nights, {})
            AreEqual(1,   #cols)
            IsTrue(cols[1].expandable)
            AreEqual(nil, cols[1].sessionId)
        end)
    end

    function Tests:testBuildColumns_DayWithKillsHasNoEmptySessions()
        WithDB(AttendanceDB({}, {
            { startedAt = TS(3), raids = {
                { id = "r1", participants = { "A-R" }, kills = {
                    { boss = "A", ts = TS(3, 21), participants = { "A-R" } },
                } },
            } },
        }), function()
            MockRoster({})
            local result = GL.ComputeAttendance("s1")
            local cols   = GL.BuildAttendanceColumns(result.nights, {})
            -- bei einer Spalte MIT Kills wäre nicht klar, was ein Löschen treffen soll
            AreEqual(nil, cols[1].emptySessions)
        end)
    end

    function Tests:testBuildColumns_KillTooltipCarriesDifficulty()
        local cols = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = TS(3), kills = {
                { name = "Ulgrax", ts = TS(3, 21), difficulty = "H" },
                { name = "Sikran", ts = TS(3, 22), difficulty = "H" },
            } },
        }), { n1 = true })
        Exists(cols[1].tooltipD:find("H"))
    end

    function Tests:testBuildColumns_DifficultyOnKillColumns()
        local cols = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = TS(3), kills = {
                { name = "A", ts = TS(3, 21), difficulty = "H" },
                { name = "B", ts = TS(3, 22), difficulty = "M" },
            } },
        }), { n1 = true })
        AreEqual("H", cols[1].difficulty)
        AreEqual("M", cols[2].difficulty)
    end

    function Tests:testBuildColumns_NightDifficultyOnlyWhenUniform()
        -- einheitlicher Abend → Difficulty auch auf der eingeklappten Spalte
        local same = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = TS(3), kills = {
                { name = "A", difficulty = "H" }, { name = "B", difficulty = "H" },
            } },
        }), {})
        AreEqual("H", same[1].difficulty)

        -- gemischter Abend → keine, statt eine zu behaupten
        local mixed = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = TS(3), kills = {
                { name = "A", difficulty = "H" }, { name = "B", difficulty = "M" },
            } },
        }), {})
        AreEqual(nil, mixed[1].difficulty)
    end

    function Tests:testBuildColumns_KillTooltipWithoutDifficulty()
        -- Altdaten ohne difficulty → kein leerer Trenner im Tooltip
        local cols = GL.BuildAttendanceColumns(Nights({
            { id = "n1", startedAt = TS(3), kills = {
                { name = "A", ts = TS(3, 21) }, { name = "B", ts = TS(3, 22) },
            } },
        }), { n1 = true })
        AreEqual(nil, cols[1].tooltipD:find("·  |cff"))
    end

    -- ========================================================
    -- Gruppierung nach Raid-Tag
    -- ========================================================
    function Tests:testCollectNights_SessionAcrossTwoDaysSplitsIntoTwoNights()
        -- am Folgetag in einem anderen Raid fortgesetzt → zwei Spalten, nicht eine
        WithDB(AttendanceDB({}, {
            { startedAt = TS(3), raids = {
                { id = "r1", participants = { "Alice-R" }, kills = {
                    { boss = "A", ts = TS(3, 20), participants = { "Alice-R" } },
                } },
                { id = "r2", participants = { "Alice-R" }, kills = {
                    { boss = "B", ts = TS(4, 20), participants = { "Alice-R" } },
                } },
            } },
        }), function()
            MockRoster({ { name = "Alice-R", group = "roster" } })
            local result = GL.ComputeAttendance("s1")
            AreEqual(2, #result.nights)
            AreEqual(2, RowByName(result, "Alice-R").attended)   -- zwei Abende, nicht einer
        end)
    end

    function Tests:testCollectNights_TwoSessionsSameDayMergeIntoOneNight()
        -- zwei Raids an einem Tag, jeder in eigener Session → eine Spalte
        WithDB(AttendanceDB({}, {
            { startedAt = TS(3, 10), label = "Vormittag", raids = {
                { id = "r1", participants = { "Alice-R" }, kills = {
                    { boss = "A", ts = TS(3, 11), participants = { "Alice-R" } },
                } },
            } },
            { startedAt = TS(3, 20), label = "Abend", raids = {
                { id = "r2", participants = { "Alice-R" }, kills = {
                    { boss = "B", ts = TS(3, 21), participants = { "Alice-R" } },
                } },
            } },
        }), function()
            MockRoster({ { name = "Alice-R", group = "roster" } })
            local result = GL.ComputeAttendance("s1")
            AreEqual(1, #result.nights)
            AreEqual(2, #result.nights[1].kills)   -- Bosse beider Raids im selben Abend
            AreEqual(1, RowByName(result, "Alice-R").attended)
            -- der Tooltip nennt beide Sessions des Tages
            AreEqual("Vormittag · Abend", result.nights[1].label)
        end)
    end

    function Tests:testCollectNights_AfterMidnightBelongsToPreviousRaidDay()
        -- Raid-Reset ist 7 Uhr: ein Kill um 01:30 gehört noch zum Vorabend
        WithDB(AttendanceDB({}, {
            { startedAt = TS(3, 20), raids = {
                { id = "r1", participants = { "Alice-R" }, kills = {
                    { boss = "A", ts = TS(3, 23),    participants = { "Alice-R" } },
                    { boss = "B", ts = TS(4, 1, 30), participants = { "Alice-R" } },
                } },
            } },
        }), function()
            MockRoster({ { name = "Alice-R", group = "roster" } })
            local result = GL.ComputeAttendance("s1")
            AreEqual(1, #result.nights)
            AreEqual(2, #result.nights[1].kills)
            AreEqual(1, RowByName(result, "Alice-R").attended)
        end)
    end

    function Tests:testCollectNights_MorningAfterResetIsANewDay()
        -- Gegenprobe: 9 Uhr liegt hinter dem Reset und ist damit ein neuer Raid-Tag
        WithDB(AttendanceDB({}, {
            { startedAt = TS(3, 20), raids = {
                { id = "r1", participants = { "Alice-R" }, kills = {
                    { boss = "A", ts = TS(3, 23), participants = { "Alice-R" } },
                    { boss = "B", ts = TS(4, 9),  participants = { "Alice-R" } },
                } },
            } },
        }), function()
            MockRoster({ { name = "Alice-R", group = "roster" } })
            AreEqual(2, #GL.ComputeAttendance("s1").nights)
        end)
    end

    function Tests:testCollectNights_SessionWithoutKillsStillCounts()
        -- abgebrochener Abend darf nicht spurlos aus der Zählung verschwinden
        WithDB(AttendanceDB({}, {
            { startedAt = TS(3), label = "Abgebrochen" },
        }), function()
            MockRoster({ { name = "Alice-R", group = "roster" } })
            local result = GL.ComputeAttendance("s1")
            AreEqual(1, #result.nights)
            AreEqual(0, #result.nights[1].kills)
            AreEqual(1, RowByName(result, "Alice-R").total)
            AreEqual(0, RowByName(result, "Alice-R").attended)
        end)
    end

    -- ========================================================
    -- Präsenz und Att.%
    -- ========================================================
    function Tests:testComputeAttendance_PctFromAttendedNights()
        WithDB(AttendanceDB({}, {
            { startedAt = TS(1), raids = { { id = "r1", participants = { "Alice-R" } } } },
            { startedAt = TS(2), raids = { { id = "r2", participants = { "Alice-R" } } } },
            { startedAt = TS(3), raids = { { id = "r3", participants = { "Bob-R" } } } },
            { startedAt = TS(4), raids = { { id = "r4", participants = { "Bob-R" } } } },
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

    -- ========================================================
    -- CSV-Export / -Import (Phase 1d/1e)
    -- ========================================================

    --- Season mit einem Abend, zwei Bosskills, zwei Teilnehmern; Alice mit BIS bei Boss 2.
    local function ExportDB()
        return AttendanceDB({}, {
            { startedAt = TS(3), lootLog = {
                { player = "Alice-R", winnerPrio = 1, boss = "Sikran",
                  raidID = "r1", timestamp = TS(3, 22) },
            }, raids = {
                { id = "r1", participants = { "Alice-R", "Bob-R" }, kills = {
                    { boss = "Ulgrax", ts = TS(3, 21),
                      participants = { "Alice-R", "Bob-R" } },
                    { boss = "Sikran", ts = TS(3, 22),
                      participants = { "Alice-R" } },
                } },
            } },
        })
    end

    local function Lines(text)
        local out = {}
        for line in text:gmatch("[^\n]+") do table.insert(out, line) end
        return out
    end

    function Tests:testExportSeasonCSV_HeaderAndOneRowPerParticipantAndKill()
        WithDB(ExportDB(), function()
            MockRoster({
                { name = "Alice-R", group = "roster" },
                { name = "Bob-R",   group = "roster" },
            })
            local lines = Lines(GL.ExportSeasonCSV("s1"))
            AreEqual("Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial", lines[1])
            -- Kopfzeile + Season-Zeile + Ulgrax (zwei Teilnehmer) + Sikran (einer)
            AreEqual(5, #lines)
            Exists(lines[2]:find("^Season,"))
        end)
    end

    function Tests:testExportSeasonCSV_MarksBisColumn()
        WithDB(ExportDB(), function()
            MockRoster({
                { name = "Alice-R", group = "roster" },
                { name = "Bob-R",   group = "roster" },
            })
            local csv = GL.ExportSeasonCSV("s1")
            -- Alice bei Sikran mit x, Bob bei Ulgrax ohne
            -- Spalten am Zeilenende: BIS,Trial
            Exists(csv:find("Sikran,Alice%-R,x,"))
            Exists(csv:find("Ulgrax,Bob%-R,,"))
        end)
    end

    function Tests:testExportSeasonCSV_CarriesSeasonRankAndRoster()
        WithDB(AttendanceDB({
            name = "Season 2025-11", startedAt = TS(1), endedAt = TS(9),
            rankFilter = { [1] = true, [2] = true },
            roster = { { name = "Alice-R", class = "MAGE" } },
            rosterGuild = "Requiem",
        }, {}), function()
            MockRoster({})
            local csv = GL.ExportSeasonCSV("s1")
            -- ohne diese Zeilen ließe sich die Season anderswo nicht wiederherstellen
            Exists(csv:find("Season,Season 2025%-11,"))
            Exists(csv:find("Requiem"))
            Exists(csv:find("\nRank,1\n"))
            Exists(csv:find("\nRank,2\n"))
            Exists(csv:find("Roster,Alice%-R,MAGE"))
        end)
    end

    function Tests:testImportAttendanceCSV_ActivatesSeasonWhenNothingWasRunning()
        -- Weitergabe-Fall: leere DB, CSV-Season hatte kein Enddatum (war offen) →
        -- nichts zu beenden, also wird sie direkt nutzbar
        WithDB({ seasons = {}, raidContainers = {}, players = {} }, function()
            GL.ImportAttendanceCSV(table.concat({
                "Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial",
                "Season,Offene Season,2025-11-01,,Requiem",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,Alice-R,,",
            }, "\n"))
            local season = GL.FindSeasonByName("Offene Season")
            Exists(season)
            AreEqual(nil, season.endedAt)
            AreEqual(season.id, GuildLootDB.activeSeasonId)
        end)
    end

    function Tests:testImportAttendanceCSV_ClosesImportedSeasonWhenAnotherIsRunning()
        -- Eine Season läuft schon (der Normalfall beim eigenen Nachtragen) → die
        -- importierte darf NICHT als zweite offene daneben stehen, sonst greift [Resume]
        -- nicht (das nur auf season.endedAt ~= nil reagiert)
        WithDB(AttendanceDB({ name = "Laufende Season" }, {}), function()
            GuildLootDB.activeSeasonId = "s1"   -- s1 läuft bereits
            GL.ImportAttendanceCSV(table.concat({
                "Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial",
                "Season,Alte Season,2025-11-01,,Requiem",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,Alice-R,,",
                "Kill,2025-11-06,20:14,Nerub-ar,H,Sikran,Alice-R,,",
            }, "\n"))
            local season = GL.FindSeasonByName("Alte Season")
            Exists(season)
            Exists(season.endedAt)                     -- jetzt "beendet", nicht offen
            AreEqual("s1", GuildLootDB.activeSeasonId)  -- die laufende bleibt unangetastet
            -- Enddatum = spätestes importiertes Kill-Datum (06.11.), nicht "jetzt"
            AreEqual("2025-11-06", date("%Y-%m-%d", season.endedAt))
        end)
    end

    function Tests:testImportAttendanceCSV_KeepsExplicitEndDate()
        -- War die Season beim Export schon beendet, bleibt IHR Enddatum maßgeblich —
        -- nicht das aus den Kills abgeleitete
        WithDB({ seasons = {}, raidContainers = {}, players = {} }, function()
            GL.ImportAttendanceCSV(table.concat({
                "Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial",
                "Season,Beendete Season,2025-11-01,2025-11-10,Requiem",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,Alice-R,,",
            }, "\n"))
            local season = GL.FindSeasonByName("Beendete Season")
            local y, m, d = date("%Y", season.endedAt), date("%m", season.endedAt),
                             date("%d", season.endedAt)
            AreEqual("2025-11-10", y .. "-" .. m .. "-" .. d)
            AreEqual(nil, GuildLootDB.activeSeasonId)   -- kein automatisches Aktivieren
        end)
    end

    function Tests:testImportAttendanceCSV_CreatesSeasonWhenMissing()
        WithDB({ seasons = {}, raidContainers = {}, players = {} }, function()
            local stats = GL.ImportAttendanceCSV(table.concat({
                "Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial",
                "Season,Season 2025-11,2025-11-01,2025-12-15,Requiem",
                "Rank,2",
                "Roster,Alice-R,MAGE",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,Alice-R,",
            }, "\n"))
            IsTrue(stats.seasonCreated)

            local season = GL.FindSeasonByName("Season 2025-11")
            Exists(season)
            IsTrue(season.rankFilter[2])
            AreEqual(1,         #season.roster)
            AreEqual("Requiem", season.rosterGuild)
            Exists(season.endedAt)
            -- die laufende Season darf davon unberührt bleiben
            AreEqual(nil, GuildLootDB.activeSeasonId)
        end)
    end

    function Tests:testImportAttendanceCSV_KeepsExistingSeasonUntouched()
        WithDB(AttendanceDB({ name = "Season 2025-11", startedAt = TS(1) }, {}), function()
            local stats = GL.ImportAttendanceCSV(table.concat({
                "Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial",
                "Season,Season 2025-11,2025-11-01,2025-12-15,Fremdgilde",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,Alice-R,",
            }, "\n"))
            IsTrue(stats.seasonExisted)
            AreEqual(nil, stats.seasonCreated)
            -- Stammdaten der vorhandenen Season bleiben, wie sie waren
            AreEqual(TS(1), GuildLootDB.seasons["s1"].startedAt)
            AreEqual(nil,   GuildLootDB.seasons["s1"].rosterGuild)
        end)
    end

    function Tests:testImportAttendanceCSV_CreatesSessionAndKills()
        WithDB(AttendanceDB({}, {}), function()
            local stats = GL.ImportAttendanceCSV(table.concat({
                "Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,Alice-R,",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,Bob-R,x",
                "Kill,2025-11-05,20:40,Nerub-ar,H,Sikran,Alice-R,",
            }, "\n"))
            AreEqual(2, stats.kills)
            AreEqual(3, stats.rows)
            AreEqual(0, stats.bad)

            local s = GuildLootDB.raidContainers[1]
            AreEqual("import",        s.source)
            AreEqual("import-2025-11-05", s.id)
            local meta = select(2, next(s.raidMeta))
            AreEqual(2, #meta.kills)
            -- Abend-Liste als Vereinigung beider Kills
            AreEqual(2, #meta.participants)
        end)
    end

    function Tests:testImportAttendanceCSV_IsIdempotent()
        WithDB(AttendanceDB({}, {}), function()
            local csv = table.concat({
                "Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,Alice-R,",
            }, "\n")
            GL.ImportAttendanceCSV(csv)
            local stats = GL.ImportAttendanceCSV(csv)   -- zweiter Durchlauf
            AreEqual(0, stats.kills)
            AreEqual(1, stats.skipped)
            AreEqual(1, #GuildLootDB.raidContainers)
            local meta = select(2, next(GuildLootDB.raidContainers[1].raidMeta))
            AreEqual(1, #meta.kills)
        end)
    end

    function Tests:testImportAttendanceCSV_LeavesRecordedSessionsAlone()
        WithDB(AttendanceDB({}, {
            { startedAt = TS(3), raids = {
                { id = "r1", participants = { "Alice-R" }, kills = {
                    { boss = "Ulgrax", ts = TS(3, 21), participants = { "Alice-R" } },
                } },
            } },
        }), function()
            GL.ImportAttendanceCSV(table.concat({
                "Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,Bob-R,",
            }, "\n"))
            -- die aufgezeichnete Session bleibt unangetastet, die importierte kommt dazu
            AreEqual(2, #GuildLootDB.raidContainers)
            local recorded
            for _, s in ipairs(GuildLootDB.raidContainers) do
                if s.id == "c1" then recorded = s end
            end
            Exists(recorded)
            AreEqual(nil, recorded.source)
            AreEqual(1, #recorded.raidMeta["r1"].kills)
        end)
    end

    function Tests:testRoundtrip_ExportDeleteSeasonImport()
        WithDB(ExportDB(), function()
            MockRoster({
                { name = "Alice-R", group = "roster" },
                { name = "Bob-R",   group = "roster" },
            })
            GuildLootDB.seasons["s1"].name = "Season Test"
            local csv = GL.ExportSeasonCSV("s1")

            -- Season löschen — die Raid-Sessions bleiben dabei bewusst stehen
            GL.DeleteSeason("s1")
            AreEqual(1, #GuildLootDB.raidContainers)

            local stats = GL.ImportAttendanceCSV(csv)
            IsTrue(stats.seasonCreated)
            -- die Kills liegen noch in der Originalsession → nichts darf doppelt entstehen
            AreEqual(0, stats.kills)
            AreEqual(3, stats.rows)      -- drei Teilnehmer-Zeilen
            AreEqual(2, stats.skipped)   -- aber nur zwei Bosskills
            AreEqual(1, #GuildLootDB.raidContainers)

            -- und die Matrix sieht aus wie vorher
            local season = GL.FindSeasonByName("Season Test")
            Exists(season)
            local result = GL.ComputeAttendance(season.id)
            AreEqual(1, #result.nights)
            AreEqual(2, #result.nights[1].kills)
        end)
    end

    function Tests:testRoundtrip_ImportOnAClientWithoutTheRaids()
        -- Der Weitergabe-Fall: jemand bekommt den Export und hat weder Season noch Sessions.
        local csv
        WithDB(ExportDB(), function()
            MockRoster({
                { name = "Alice-R", group = "roster" },
                { name = "Bob-R",   group = "roster" },
            })
            GuildLootDB.seasons["s1"].name = "Season Transfer"
            csv = GL.ExportSeasonCSV("s1")
        end)

        WithDB({ seasons = {}, raidContainers = {}, players = {} }, function()
            local stats = GL.ImportAttendanceCSV(csv)
            IsTrue(stats.seasonCreated)
            AreEqual(2, stats.kills)          -- beide Bosse kommen an
            AreEqual(0, stats.skipped)

            local season = GL.FindSeasonByName("Season Transfer")
            Exists(season)
            MockRoster({
                { name = "Alice-R", group = "roster" },
                { name = "Bob-R",   group = "roster" },
            })
            local result = GL.ComputeAttendance(season.id)
            AreEqual(1, #result.nights)
            AreEqual(2, #result.nights[1].kills)

            local alice = RowByName(result, "Alice-R")
            local bob   = RowByName(result, "Bob-R")
            AreEqual(100, alice.pct)
            AreEqual(100, bob.pct)
            -- der BIS-Stern überlebt, obwohl die importierte Session keinen lootLog hat
            IsTrue(alice.bisAt[result.nights[1].id])
            AreEqual(nil, bob.bisAt[result.nights[1].id])
        end)
    end

    function Tests:testRoundtrip_TrialSurvivesExportImport()
        WithDB(AttendanceDB({ name = "Season Trial" }, {
            { startedAt = TS(3), raids = {
                { id = "r1", participants = { "Neu-R" }, kills = {
                    { boss = "Ulgrax", ts = TS(3, 21), participants = { "Neu-R" },
                      trials = { ["Neu-R"] = true } },
                } },
            } },
        }), function()
            MockRoster({ { name = "Neu-R", group = "roster" } })
            local csv = GL.ExportSeasonCSV("s1")
            Exists(csv:find("Neu%-R,,x"))       -- BIS leer, Trial gesetzt

            -- in eine leere DB einspielen
            GuildLootDB.seasons        = {}
            GuildLootDB.raidContainers = {}
            GL.ImportAttendanceCSV(csv)

            local season = GL.FindSeasonByName("Season Trial")
            local result = GL.ComputeAttendance(season.id)
            IsTrue(result.rows[1].trialAt[result.nights[1].kills[1].id])
        end)
    end

    function Tests:testImportAttendanceCSV_MatchesRealKillDespiteSeconds()
        -- Ein aufgezeichneter Kill hat echte Sekunden, die CSV kennt nur HH:MM (Sekunden
        -- immer :00 beim Reimport). Ein exakter Vergleich hätte NIE getroffen und jeden
        -- Import gegen echte Daten dupliziert — genau der Fall aus der Praxis.
        WithDB(AttendanceDB({}, {
            { startedAt = TS(3, 22, 35), raids = {
                { id = "r1", participants = { "Alice-R" }, kills = {
                    -- 47 Sekunden, wie ein echter ENCOUNTER_END-Zeitstempel
                    { boss = "Ulgrax", ts = TS(3, 22, 35) + 47,
                      participants = { "Alice-R" } },
                } },
            } },
        }), function()
            local stats = GL.ImportAttendanceCSV(table.concat({
                "Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial",
                "Kill,2026-08-03,22:35,Nerub-ar,H,Ulgrax,Alice-R,,",
            }, "\n"))
            AreEqual(0, stats.kills)
            AreEqual(1, stats.skipped)
            AreEqual(1, #GuildLootDB.raidContainers)   -- keine Import-Session entstanden
        end)
    end

    function Tests:testImportAttendanceCSV_CollapsesDuplicateRows()
        -- Eine CSV aus einer bereits doppelt befüllten DB enthält jede Zeile zweimal.
        -- Ohne Zusammenfassen stünde der Spieler zweimal in der Teilnehmerliste und ein
        -- erneuter Export reichte die Dublette weiter.
        WithDB({ seasons = {}, raidContainers = {}, players = {} }, function()
            GL.ImportAttendanceCSV(table.concat({
                "Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,Alice-R,,",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,Alice-R,,",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,Bob-R,,",
            }, "\n"))
            local meta = select(2, next(GuildLootDB.raidContainers[1].raidMeta))
            AreEqual(1, #meta.kills)
            AreEqual(2, #meta.kills[1].participants)   -- Alice einmal, nicht zweimal
        end)
    end

    function Tests:testImportAttendanceCSV_CountsBadLines()
        WithDB(AttendanceDB({}, {}), function()
            local stats = GL.ImportAttendanceCSV(table.concat({
                "Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial",
                "Kill,kein-datum,20:14,Nerub-ar,H,Ulgrax,Alice-R,",
                "Kill,2025-11-05,keine-zeit,Nerub-ar,H,Ulgrax,Alice-R,",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,,",   -- ohne Spieler
            }, "\n"))
            AreEqual(3, stats.bad)
            AreEqual(0, stats.kills)
        end)
    end

    function Tests:testImportedBisShowsWithoutLootLog()
        WithDB(AttendanceDB({}, {}), function()
            GL.ImportAttendanceCSV(table.concat({
                "Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial",
                "Kill,2025-11-05,20:14,Nerub-ar,H,Ulgrax,Alice-R,x",
            }, "\n"))
            -- Season-Fenster über den Importtag legen
            GuildLootDB.seasons["s1"].startedAt = 0
            GuildLootDB.seasons["s1"].endedAt   = nil
            MockRoster({ { name = "Alice-R", group = "roster" } })

            local result = GL.ComputeAttendance("s1")
            local row    = result.rows[1]
            -- die importierte Session hat keinen lootLog — der Stern kommt aus kill.bis
            IsTrue(row.bisAt[result.nights[1].id])
        end)
    end
end)
