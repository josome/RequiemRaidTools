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

    --- Stubt die WoW-Gilden-API mit dem übergebenen Roster-Array
    --- (Einträge: { name, rankIndex, class }). name darf realm-los sein.
    local function MockGuild(roster)
        Mock(_G, "IsInGuild",          function() return true end)
        Mock(_G, "GetNumGuildMembers", function() return #roster end)
        Mock(_G, "GetGuildRosterInfo", function(i)
            local m = roster[i]
            if not m then return nil end
            -- name, rank, rankIndex, level, class, zone, note, off, online, status, classFile
            return m.name, "RankName", m.rankIndex, 70, "ClassLoc",
                   "Zone", "", "", true, nil, m.class
        end)
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

    local function SeasonDB(rankFilter)
        return { seasons = { ["s1"] = { id = "s1", name = "S", rankFilter = rankFilter or {} } } }
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
    -- GetSeasonRoster
    -- ========================================================
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
            local roster = GL.GetSeasonRoster("s1")
            AreEqual(1, #roster)                         -- keine Dublette
            AreEqual("MAGE", roster[1].class)            -- Klasse aus Gilde bleibt erhalten
        end)
    end
end)
