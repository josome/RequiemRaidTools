-- RequiemRaidTools — src/tests/Guild_Test.lua
-- Unit-Tests für die Gildenroster-Anbindung (src/core/Core_Guild.lua) via WoWUnit.
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

    local Tests = WoWUnit("ReqRT.Guild")
    local GL    = GuildLoot

    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue
    local IsFalse  = WoWUnit.IsFalse
    local Exists   = WoWUnit.Exists

    -- --------------------------------------------------------
    -- Mock-Infrastruktur (restauriert auch nil-Originale korrekt)
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

    --- Stubt die WoW-Gilden-API mit dem übergebenen Roster-Array.
    --- Einträge: { name, rankIndex, class, rankName? }. name darf realm-los sein.
    local function MockGuild(roster)
        Mock(_G, "IsInGuild",          function() return true end)
        Mock(_G, "GetNumGuildMembers", function() return #roster end)
        Mock(_G, "GetGuildRosterInfo", function(i)
            local m = roster[i]
            if not m then return nil end
            -- name, rank, rankIndex, level, class, zone, note, off, online, status, classFile
            return m.name, m.rankName or "RankName", m.rankIndex, 70, "ClassLoc",
                   "Zone", "", "", true, nil, m.class
        end)
    end

    --- Wie WithDB, aber ganz ohne GuildLootDB — prüft, dass nichts hart auf die DB zugreift.
    local function WithTestDBNil(fn)
        local origDB = GuildLootDB
        GuildLootDB = nil
        local ok, err = pcall(fn)
        GuildLootDB = origDB
        MockRestore()
        if not ok then error(err, 2) end
    end

    --- WithDB: setzt GuildLootDB, ruft fn, stellt Original + Mocks wieder her.
    local function WithDB(db, fn)
        local origDB = GuildLootDB
        GuildLootDB = db
        local ok, err = pcall(fn)
        GuildLootDB = origDB
        MockRestore()
        if not ok then error(err, 2) end
    end

    --- DB mit genau einer Season "s1". seasonFields ergänzt/überschreibt Felder der Season
    --- (z.B. maxOfflineDays, startedAt, endedAt).
    local function SeasonDB(rankFilter, seasonFields)
        local season = { id = "s1", name = "S", rankFilter = rankFilter or {} }
        for k, v in pairs(seasonFields or {}) do season[k] = v end
        return { seasons = { ["s1"] = season }, raidContainers = {}, players = {} }
    end

    --- Season-DB mit Raid-Sessions, aus denen GetSeasonAttendees die Teilnehmer zieht.
    --- sessions: Array von { startedAt, participants = { name, ... } }
    local function SeasonDBWithRaids(rankFilter, seasonFields, sessions)
        local db = SeasonDB(rankFilter, seasonFields)
        for i, s in ipairs(sessions or {}) do
            db.raidContainers[i] = {
                startedAt = s.startedAt,
                raidMeta  = { ["r" .. i] = { participants = s.participants or {} } },
            }
        end
        return db
    end

    -- ========================================================
    -- GetGuildMembers
    -- ========================================================
    function Tests:testGetGuildMembers_NotInGuild_Empty()
        WithDB({}, function()
            Mock(_G, "IsInGuild", function() return false end)
            AreEqual(0, #GL.GetGuildMembers())
        end)
    end

    function Tests:testGetGuildMembers_ReadsFieldsAndNormalizes()
        WithDB({}, function()
            MockGuild({ { name = "Bob", rankIndex = 2, class = "WARRIOR" } })
            local m = GL.GetGuildMembers()
            AreEqual(1, #m)
            AreEqual("Bob-TestRealm", m[1].name)  -- Realm via NormalizeName angehängt
            AreEqual(2, m[1].rankIndex)
            AreEqual("WARRIOR", m[1].class)
        end)
    end

    -- ========================================================
    -- GetGuildRankNames
    -- ========================================================
    function Tests:testGetGuildRankNames_MappedByRankIndex()
        WithDB({}, function()
            Mock(_G, "GuildControlGetNumRanks", function() return 3 end)
            Mock(_G, "GuildControlGetRankName", function(o) return "R" .. o end)
            local names = GL.GetGuildRankNames()
            -- rankIndex 0..2 → GuildControlGetRankName(1..3)
            AreEqual("R1", names[0])
            AreEqual("R2", names[1])
            AreEqual("R3", names[2])
        end)
    end

    -- ========================================================
    -- SnapshotSeasonRoster — Kader nur auf ausdrückliche Aktion
    -- ========================================================
    function Tests:testSnapshotSeasonRoster_StoresFilteredKader()
        WithDB(SeasonDB({ [1] = true }), function()
            MockGuild({
                { name = "Alice-TestRealm", rankIndex = 1, class = "MAGE" },
                { name = "Bob-TestRealm",   rankIndex = 5, class = "WARRIOR" },
            })
            AreEqual(1, GL.SnapshotSeasonRoster("s1"))
            local season = GuildLootDB.seasons["s1"]
            AreEqual(1, #season.roster)
            AreEqual("Alice-TestRealm", season.roster[1].name)
            AreEqual("MAGE", season.roster[1].class)
            IsTrue(season.rosterReadAt > 0)
        end)
    end

    function Tests:testSnapshotSeasonRoster_UnknownSeason_Nil()
        WithDB(SeasonDB({}), function()
            AreEqual(nil, GL.SnapshotSeasonRoster("nope"))
        end)
    end

    function Tests:testGetSeasonRoster_FilterChangeHasNoEffectUntilSnapshot()
        WithDB(SeasonDB({ [1] = true }), function()
            MockGuild({
                { name = "Alice-TestRealm", rankIndex = 1, class = "MAGE" },
                { name = "Bob-TestRealm",   rankIndex = 2, class = "WARRIOR" },
            })
            Mock(GL, "GetSeasonAttendees", function() return {} end)
            GL.SnapshotSeasonRoster("s1")
            AreEqual(1, #GL.GetSeasonRoster("s1"))

            -- Rang 2 dazunehmen — das Roster darf sich NICHT sofort ändern
            GL.SetSeasonRankFilter("s1", 2, true)
            AreEqual(1, #GL.GetSeasonRoster("s1"))

            -- erst das erneute Einlesen übernimmt die Änderung
            GL.SnapshotSeasonRoster("s1")
            AreEqual(2, #GL.GetSeasonRoster("s1"))
        end)
    end

    function Tests:testGetSeasonRoster_DoesNotHitGuildApi()
        WithDB(SeasonDB({ [1] = true }), function()
            MockGuild({ { name = "Alice-TestRealm", rankIndex = 1, class = "MAGE" } })
            Mock(GL, "GetSeasonAttendees", function() return {} end)
            GL.SnapshotSeasonRoster("s1")
            -- Gilde "verschwindet" → das Roster kommt trotzdem aus dem Schnappschuss
            Mock(_G, "IsInGuild", function() return false end)
            AreEqual(1, #GL.GetSeasonRoster("s1"))
        end)
    end

    -- ========================================================
    -- IsSeasonRosterStale
    -- ========================================================
    function Tests:testIsSeasonRosterStale_TrueBeforeFirstRead()
        WithDB(SeasonDB({ [1] = true }), function()
            IsTrue(GL.IsSeasonRosterStale("s1"))
        end)
    end

    function Tests:testIsSeasonRosterStale_FalseAfterSnapshot()
        WithDB(SeasonDB({ [1] = true }), function()
            MockGuild({ { name = "Alice-TestRealm", rankIndex = 1 } })
            GL.SnapshotSeasonRoster("s1")
            IsFalse(GL.IsSeasonRosterStale("s1"))
        end)
    end

    function Tests:testIsSeasonRosterStale_TrueAfterFilterChange()
        WithDB(SeasonDB({ [1] = true }), function()
            MockGuild({ { name = "Alice-TestRealm", rankIndex = 1 } })
            GL.SnapshotSeasonRoster("s1")
            GL.SetSeasonRankFilter("s1", 2, true)
            IsTrue(GL.IsSeasonRosterStale("s1"))
        end)
    end

    function Tests:testIsSeasonRosterStale_UnknownSeason_False()
        WithDB(SeasonDB({}), function()
            IsFalse(GL.IsSeasonRosterStale("nope"))
        end)
    end

    -- ========================================================
    -- GetSeasonRoster
    -- ========================================================
    function Tests:testGetSeasonRoster_NoDB_Empty()
        WithTestDBNil(function()
            AreEqual(0, #GL.GetSeasonRoster("s1"))
            AreEqual(0, #GL.GetSeasonAttendees("s1"))
        end)
    end

    function Tests:testGetGuildRankNames_NoApiNoDB_Empty()
        WithTestDBNil(function()
            Mock(_G, "GuildControlGetNumRanks", function() return 0 end)
            local names = GL.GetGuildRankNames()
            local count = 0
            for _ in pairs(names) do count = count + 1 end
            AreEqual(0, count)
        end)
    end

    function Tests:testGetSeasonRoster_UnknownSeason_Empty()
        WithDB(SeasonDB({ [1] = true }), function()
            AreEqual(0, #GL.GetSeasonRoster("nope"))
        end)
    end

    function Tests:testGetSeasonRoster_FiltersByRank()
        WithDB(SeasonDB({ [1] = true }), function()
            MockGuild({
                { name = "Alice-TestRealm", rankIndex = 1, class = "MAGE" },
                { name = "Bob-TestRealm",   rankIndex = 2, class = "WARRIOR" },
                { name = "Carol-TestRealm", rankIndex = 1, class = "PRIEST" },
            })
            Mock(GL, "GetSeasonAttendees", function() return {} end)
            GL.SnapshotSeasonRoster("s1")
            local roster = GL.GetSeasonRoster("s1")
            AreEqual(2, #roster)                       -- nur Rang 1
            AreEqual("Alice-TestRealm", roster[1].name)  -- sortiert
            AreEqual("Carol-TestRealm", roster[2].name)
            AreEqual("MAGE", roster[1].class)
        end)
    end

    function Tests:testGetSeasonRoster_EmptyFilter_NoGuildRows()
        WithDB(SeasonDB({}), function()
            MockGuild({ { name = "Alice-TestRealm", rankIndex = 1, class = "MAGE" } })
            Mock(GL, "GetSeasonAttendees", function() return {} end)
            GL.SnapshotSeasonRoster("s1")
            AreEqual(0, #GL.GetSeasonRoster("s1"))   -- kein Rang aktiv → keine Zeilen
        end)
    end

    function Tests:testGetSeasonRoster_UnionWithAttendees()
        WithDB(SeasonDB({ [1] = true }), function()
            MockGuild({
                { name = "Alice-TestRealm", rankIndex = 1, class = "MAGE" },
                { name = "Bob-TestRealm",   rankIndex = 2, class = "WARRIOR" },
            })
            -- Zeek ist ausgetreten (nicht mehr in der Gilde), hat aber Attendance
            Mock(GL, "GetSeasonAttendees", function() return { "Zeek-TestRealm" } end)
            GL.SnapshotSeasonRoster("s1")
            local roster = GL.GetSeasonRoster("s1")
            AreEqual(2, #roster)                         -- Alice (Rang 1) + Zeek (Attendance)
            AreEqual("Alice-TestRealm", roster[1].name)
            AreEqual("Zeek-TestRealm", roster[2].name)
            AreEqual(nil, roster[2].class)               -- Klasse des Ausgetretenen unbekannt
        end)
    end

    function Tests:testGetSeasonRoster_AttendeeAlreadyInGuild_NoDuplicate()
        WithDB(SeasonDB({ [1] = true }), function()
            MockGuild({ { name = "Alice-TestRealm", rankIndex = 1, class = "MAGE" } })
            Mock(GL, "GetSeasonAttendees", function() return { "Alice-TestRealm" } end)
            GL.SnapshotSeasonRoster("s1")
            local roster = GL.GetSeasonRoster("s1")
            AreEqual(1, #roster)                         -- keine Dublette
            AreEqual("MAGE", roster[1].class)            -- Klasse aus Gilde bleibt erhalten
        end)
    end

    -- ========================================================
    -- CollectGuildMembers — ein Durchlauf, verwirft direkt
    -- ========================================================
    function Tests:testCollectGuildMembers_DropsRejectedRows()
        WithDB({}, function()
            MockGuild({
                { name = "Alice-TestRealm", rankIndex = 1, class = "MAGE" },
                { name = "Bob-TestRealm",   rankIndex = 5, class = "WARRIOR" },
            })
            local members = GL.CollectGuildMembers(function(rankIndex) return rankIndex <= 1 end)
            AreEqual(1, #members)
            AreEqual("Alice-TestRealm", members[1].name)
        end)
    end

    function Tests:testCollectGuildMembers_CollectsRankNamesInSamePass()
        WithDB({}, function()
            MockGuild({
                { name = "Gm-TestRealm",    rankIndex = 0, rankName = "Gildenmeister" },
                { name = "Off-TestRealm",   rankIndex = 1, rankName = "Offizier" },
                { name = "Raid-TestRealm",  rankIndex = 2, rankName = "Raider" },
            })
            -- accept lehnt alles ab: Rang-Namen müssen trotzdem gesammelt werden
            local members, rankNames = GL.CollectGuildMembers(function() return false end)
            AreEqual(0, #members)
            AreEqual("Gildenmeister", rankNames[0])
            AreEqual("Offizier",      rankNames[1])
            AreEqual("Raider",        rankNames[2])
        end)
    end

    function Tests:testCollectGuildMembers_NoAcceptKeepsAll()
        WithDB({}, function()
            MockGuild({
                { name = "Alice-TestRealm", rankIndex = 1 },
                { name = "Bob-TestRealm",   rankIndex = 5 },
            })
            AreEqual(2, #GL.CollectGuildMembers(nil))
        end)
    end

    function Tests:testCollectGuildMembers_NilRowDoesNotAbortRead()
        WithDB({}, function()
            MockGuild({ { name = "Alice-TestRealm", rankIndex = 1 } })
            -- meldet 3 Zeilen, liefert aber nur die erste → Rest ist nil
            Mock(_G, "GetNumGuildMembers", function() return 3 end)
            local members = GL.CollectGuildMembers(nil)
            AreEqual(1, #members)
            AreEqual("Alice-TestRealm", members[1].name)
        end)
    end

    -- ========================================================
    -- Kader-Schwelle: Offizier/GM stehen ÜBER dem Raider-Rang
    -- ========================================================
    function Tests:testGetSeasonRoster_OfficerAndGmAreInKader()
        -- Schwelle "Raider" (Index 2) → Ränge 0,1,2 aktiv
        WithDB(SeasonDB({ [0] = true, [1] = true, [2] = true }), function()
            MockGuild({
                { name = "Gm-TestRealm",     rankIndex = 0, class = "PALADIN" },
                { name = "Off-TestRealm",    rankIndex = 1, class = "DRUID" },
                { name = "Raider-TestRealm", rankIndex = 2, class = "MAGE" },
                { name = "Twink-TestRealm",  rankIndex = 3, class = "ROGUE" },
            })
            Mock(GL, "GetSeasonAttendees", function() return {} end)
            GL.SnapshotSeasonRoster("s1")
            local roster = GL.GetSeasonRoster("s1")
            AreEqual(3, #roster)
            AreEqual("Gm-TestRealm",     roster[1].name)
            AreEqual("Off-TestRealm",    roster[2].name)
            AreEqual("Raider-TestRealm", roster[3].name)
            AreEqual("roster", roster[1].group)
        end)
    end

    function Tests:testGetSeasonRoster_LongOfflineMemberStaysInKader()
        -- Rang ist der einzige Schnitt: wer im Kader-Rang steht, erscheint —
        -- unabhängig davon, wann er zuletzt online war.
        WithDB(SeasonDB({ [1] = true }), function()
            MockGuild({
                { name = "Aktiv-TestRealm",  rankIndex = 1, class = "MAGE" },
                { name = "Pause-TestRealm",  rankIndex = 1, class = "WARRIOR" },
            })
            Mock(GL, "GetSeasonAttendees", function() return {} end)
            GL.SnapshotSeasonRoster("s1")
            local roster = GL.GetSeasonRoster("s1")
            AreEqual(2, #roster)
            AreEqual("roster", roster[1].group)
            AreEqual("roster", roster[2].group)
        end)
    end

    -- ========================================================
    -- Zweite Gruppe: "guest"
    -- ========================================================
    function Tests:testGetSeasonRoster_LowRankParticipantBecomesGuest()
        WithDB(SeasonDB({ [1] = true }), function()
            MockGuild({
                { name = "Raider-TestRealm", rankIndex = 1, class = "MAGE" },
                { name = "Twink-TestRealm",  rankIndex = 4, class = "ROGUE" },
            })
            Mock(GL, "GetSeasonAttendees", function() return { "Twink-TestRealm" } end)
            GL.SnapshotSeasonRoster("s1")
            local roster = GL.GetSeasonRoster("s1")
            AreEqual(2, #roster)
            AreEqual("Raider-TestRealm", roster[1].name)
            AreEqual("roster", roster[1].group)
            AreEqual("Twink-TestRealm", roster[2].name)
            AreEqual("guest", roster[2].group)
        end)
    end

    function Tests:testGetSeasonRoster_RosterBlockSortsBeforeGuestBlock()
        WithDB(SeasonDB({ [1] = true }), function()
            -- "Zora" im Kader muss trotz Alphabet VOR dem Gast "Adam" stehen
            MockGuild({ { name = "Zora-TestRealm", rankIndex = 1, class = "MAGE" } })
            Mock(GL, "GetSeasonAttendees", function() return { "Adam-TestRealm" } end)
            GL.SnapshotSeasonRoster("s1")
            local roster = GL.GetSeasonRoster("s1")
            AreEqual("Zora-TestRealm", roster[1].name)
            AreEqual("roster", roster[1].group)
            AreEqual("Adam-TestRealm", roster[2].name)
            AreEqual("guest", roster[2].group)
        end)
    end

    function Tests:testGetSeasonRoster_LeaverClassFromPlayersDB()
        local db = SeasonDB({ [1] = true })
        db.players = { ["Zeek-TestRealm"] = { class = "SHAMAN" } }
        WithDB(db, function()
            MockGuild({ { name = "Alice-TestRealm", rankIndex = 1, class = "MAGE" } })
            Mock(GL, "GetSeasonAttendees", function() return { "Zeek-TestRealm" } end)
            GL.SnapshotSeasonRoster("s1")
            local roster = GL.GetSeasonRoster("s1")
            AreEqual(2, #roster)
            AreEqual("Zeek-TestRealm", roster[2].name)
            AreEqual("SHAMAN", roster[2].class)   -- Klasse aus db.players, nicht aus der Gilde
        end)
    end

    -- ========================================================
    -- GetSeasonAttendees — aus raidMeta[*].participants
    -- ========================================================
    function Tests:testGetSeasonAttendees_ReadsParticipantsAndDeduplicates()
        local db = SeasonDBWithRaids({}, { startedAt = 100, endedAt = 900 }, {
            { startedAt = 200, participants = { "Alice-TestRealm", "Bob-TestRealm" } },
            { startedAt = 300, participants = { "Bob-TestRealm",   "Carol-TestRealm" } },
        })
        WithDB(db, function()
            local names = {}
            for _, n in ipairs(GL.GetSeasonAttendees("s1")) do names[n] = true end
            local count = 0
            for _ in pairs(names) do count = count + 1 end
            AreEqual(3, count)                    -- Bob nur einmal
            IsTrue(names["Alice-TestRealm"])
            IsTrue(names["Bob-TestRealm"])
            IsTrue(names["Carol-TestRealm"])
        end)
    end

    function Tests:testGetSeasonAttendees_IgnoresSessionsOutsideSeasonWindow()
        local db = SeasonDBWithRaids({}, { startedAt = 100, endedAt = 900 }, {
            { startedAt = 50,   participants = { "TooEarly-TestRealm" } },
            { startedAt = 500,  participants = { "Inside-TestRealm" } },
            { startedAt = 1000, participants = { "TooLate-TestRealm" } },
        })
        WithDB(db, function()
            local names = GL.GetSeasonAttendees("s1")
            AreEqual(1, #names)
            AreEqual("Inside-TestRealm", names[1])
        end)
    end

    function Tests:testGetSeasonAttendees_NoRaidMeta_Empty()
        local db = SeasonDBWithRaids({}, { startedAt = 0 }, {})
        db.raidContainers = { { startedAt = 100 } }   -- Session ganz ohne raidMeta
        WithDB(db, function()
            AreEqual(0, #GL.GetSeasonAttendees("s1"))
        end)
    end

    function Tests:testGetSeasonAttendees_UnknownSeason_Empty()
        WithDB(SeasonDB({}), function()
            AreEqual(0, #GL.GetSeasonAttendees("nope"))
        end)
    end

    -- ========================================================
    -- Roster-Vollständigkeit: erkennen statt eingreifen
    -- ========================================================
    function Tests:testRefreshGuildRoster_DoesNotTouchPlayerFilter()
        WithDB({}, function()
            local state, setCalls = false, 0
            Mock(_G, "GetGuildRosterShowOffline", function() return state end)
            Mock(_G, "SetGuildRosterShowOffline", function(v)
                setCalls = setCalls + 1
                state = v and true or false
            end)
            GL.RefreshGuildRoster()
            AreEqual(0, setCalls)   -- die Gildenfenster-Einstellung bleibt unangetastet
            IsFalse(state)
        end)
    end

    function Tests:testCheckGuildRosterCompleteness_ReportsTruncatedRead()
        WithDB({ settings = {} }, function()
            MockGuild({ { name = "Alice-TestRealm", rankIndex = 1 } })
            Mock(_G, "GetNumGuildMembers", function() return 40 end)  -- meldet 40, liefert 1
            local printed = nil
            Mock(GL, "Print", function(msg) printed = msg end)
            local reported, readCount = GL.CheckGuildRosterCompleteness()
            AreEqual(40, reported)
            AreEqual(1, readCount)
            Exists(printed)   -- unvollständiger Read wird gemeldet, nicht verschluckt
        end)
    end

    function Tests:testCheckGuildRosterCompleteness_SilentWhenComplete()
        WithDB({ settings = {} }, function()
            MockGuild({
                { name = "Alice-TestRealm", rankIndex = 1 },
                { name = "Bob-TestRealm",   rankIndex = 1 },
            })
            local printed = nil
            Mock(GL, "Print", function(msg) printed = msg end)
            local reported, readCount = GL.CheckGuildRosterCompleteness()
            AreEqual(2, reported)
            AreEqual(2, readCount)
            AreEqual(nil, printed)   -- vollständig → keine Meldung
        end)
    end

    -- ========================================================
    -- OnGuildRosterUpdate
    -- ========================================================
    function Tests:testOnGuildRosterUpdate_RefreshesRankNames()
        WithDB({ guildRankNames = {}, settings = {} }, function()
            MockGuild({ { name = "Raid-TestRealm", rankIndex = 2, rankName = "Raider" } })
            GL.OnGuildRosterUpdate()
            AreEqual("Raider", GuildLootDB.guildRankNames[2])
        end)
    end

    -- ========================================================
    -- Rang-Namen: Fallback auf die DB wenn Guild-Control nichts liefert
    -- ========================================================
    function Tests:testGetGuildRankNames_FallsBackToDBWhenGuildControlEmpty()
        WithDB({ guildRankNames = { [0] = "Gildenmeister", [2] = "Raider" } }, function()
            Mock(_G, "GuildControlGetNumRanks", function() return 0 end)
            local names = GL.GetGuildRankNames()
            AreEqual("Gildenmeister", names[0])
            AreEqual("Raider",        names[2])
        end)
    end

    function Tests:testGetGuildRankNames_GuildControlWinsOverDB()
        WithDB({ guildRankNames = { [0] = "Alt" } }, function()
            Mock(_G, "GuildControlGetNumRanks", function() return 1 end)
            Mock(_G, "GuildControlGetRankName", function(o) return "Live" .. o end)
            AreEqual("Live1", GL.GetGuildRankNames()[0])
        end)
    end

    function Tests:testUpdateGuildRankNames_WritesToDB()
        WithDB({ guildRankNames = {} }, function()
            MockGuild({
                { name = "Gm-TestRealm",   rankIndex = 0, rankName = "Gildenmeister" },
                { name = "Raid-TestRealm", rankIndex = 2, rankName = "Raider" },
            })
            GL.UpdateGuildRankNames()
            AreEqual("Gildenmeister", GuildLootDB.guildRankNames[0])
            AreEqual("Raider",        GuildLootDB.guildRankNames[2])
        end)
    end
end)
