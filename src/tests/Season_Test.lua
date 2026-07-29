-- RequiemRaidTools — src/tests/Season_Test.lua
-- Unit-Tests für die Season-Verwaltung (src/core/Core_Season.lua) via WoWUnit.
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

    local Tests = WoWUnit("ReqRT.Season")
    local GL    = GuildLoot

    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue
    local IsFalse  = WoWUnit.IsFalse
    local Exists   = WoWUnit.Exists

    --- DB-Swap: setzt GuildLootDB, ruft fn, stellt Original immer wieder her.
    local function WithTestDB(initialDB, fn)
        local origDB = GuildLootDB
        GuildLootDB = initialDB
        local ok, err = pcall(fn)
        GuildLootDB = origDB
        if not ok then error(err, 2) end
    end

    local function FreshDB()
        return { seasons = {}, activeSeasonId = nil }
    end

    -- ========================================================
    -- CreateSeason
    -- ========================================================
    function Tests:testCreateSeason_SetsActiveAndStoresFields()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S1", { [2] = true, [3] = true })
            Exists(id)
            AreEqual(id, GuildLootDB.activeSeasonId)
            local s = GuildLootDB.seasons[id]
            Exists(s)
            AreEqual("S1", s.name)
            IsTrue(s.startedAt > 0)
            AreEqual(nil, s.endedAt)
            IsTrue(s.rankFilter[2])
            IsTrue(s.rankFilter[3])
        end)
    end

    function Tests:testCreateSeason_OnlyEnabledRanksKept()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S", { [1] = true, [2] = false })
            local rf = GuildLootDB.seasons[id].rankFilter
            IsTrue(rf[1])
            AreEqual(nil, rf[2])
        end)
    end

    function Tests:testCreateSeason_EndsPreviousActive()
        WithTestDB(FreshDB(), function()
            local first  = GL.CreateSeason("S1")
            local second = GL.CreateSeason("S2")
            IsTrue(first ~= second)
            AreEqual(second, GuildLootDB.activeSeasonId)
            -- alte Season wurde beim Anlegen der neuen beendet
            IsTrue(GuildLootDB.seasons[first].endedAt ~= nil)
            AreEqual(nil, GuildLootDB.seasons[second].endedAt)
        end)
    end

    function Tests:testCreateSeason_NoDB_ReturnsNil()
        WithTestDB(nil, function()
            AreEqual(nil, GL.CreateSeason("S"))
        end)
    end

    -- ========================================================
    -- SetActiveSeason / GetActiveSeason
    -- ========================================================
    function Tests:testSetActiveSeason_KnownAndUnknown()
        WithTestDB(FreshDB(), function()
            local a = GL.CreateSeason("A")
            GL.CreateSeason("B")             -- B ist jetzt aktiv
            IsTrue(GL.SetActiveSeason(a))
            AreEqual(a, GuildLootDB.activeSeasonId)
            IsFalse(GL.SetActiveSeason("does-not-exist"))
            AreEqual(a, GuildLootDB.activeSeasonId)  -- unverändert
        end)
    end

    function Tests:testGetActiveSeason_ReturnsActiveOrNil()
        WithTestDB(FreshDB(), function()
            AreEqual(nil, GL.GetActiveSeason())
            local id = GL.CreateSeason("S")
            local s  = GL.GetActiveSeason()
            Exists(s)
            AreEqual(id, s.id)
        end)
    end

    -- ========================================================
    -- EndSeason
    -- ========================================================
    function Tests:testEndSeason_StampsEndedAtAndClearsActive()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            IsTrue(GL.EndSeason(id))
            IsTrue(GuildLootDB.seasons[id].endedAt ~= nil)
            AreEqual(nil, GuildLootDB.activeSeasonId)
        end)
    end

    function Tests:testEndSeason_UnknownReturnsFalse()
        WithTestDB(FreshDB(), function()
            IsFalse(GL.EndSeason("nope"))
        end)
    end

    -- ========================================================
    -- SetSeasonRankFilter
    -- ========================================================
    function Tests:testSetSeasonRankFilter_Toggle()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            IsTrue(GL.SetSeasonRankFilter(id, 4, true))
            IsTrue(GuildLootDB.seasons[id].rankFilter[4])
            IsTrue(GL.SetSeasonRankFilter(id, 4, false))
            AreEqual(nil, GuildLootDB.seasons[id].rankFilter[4])
        end)
    end

    function Tests:testSetSeasonRankFilter_UnknownReturnsFalse()
        WithTestDB(FreshDB(), function()
            IsFalse(GL.SetSeasonRankFilter("nope", 1, true))
        end)
    end

    -- ========================================================
    -- InitDB-Defaults
    -- ========================================================
    function Tests:testInitDB_HasSeasonDefaults()
        local origDB, origBackup, origPrint = GuildLootDB, GuildLootDBBackup, GL.Print
        GuildLootDB, GuildLootDBBackup = nil, nil
        GL.Print = function() end
        local ok, err = pcall(function()
            GL.InitDB()
            Exists(GuildLootDB.seasons)
            AreEqual("table", type(GuildLootDB.seasons))
            AreEqual(nil, GuildLootDB.activeSeasonId)
        end)
        GuildLootDB, GuildLootDBBackup, GL.Print = origDB, origBackup, origPrint
        if not ok then error(err, 2) end
    end
end)
