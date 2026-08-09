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

    function Tests:testCreateSeason_IdCollisionResolvesToUniqueId()
        WithTestDB(FreshDB(), function()
            local orig, calls = GL.GenerateRaidID, 0
            -- die ersten beiden Hashes kollidieren, danach eindeutig
            GL.GenerateRaidID = function()
                calls = calls + 1
                return (calls <= 2) and "collide" or "unique"
            end
            local a = GL.CreateSeason("S")
            local b = GL.CreateSeason("S")
            GL.GenerateRaidID = orig   -- vor den Assertions restaurieren
            IsTrue(a ~= b)
            Exists(GuildLootDB.seasons[a])
            Exists(GuildLootDB.seasons[b])
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
    function Tests:testSetActiveSeason_UnknownIdRejected()
        WithTestDB(FreshDB(), function()
            local a = GL.CreateSeason("A")
            IsFalse(GL.SetActiveSeason("does-not-exist"))
            AreEqual(a, GuildLootDB.activeSeasonId)  -- unverändert
        end)
    end

    function Tests:testSetActiveSeason_EndedSeasonRejected()
        WithTestDB(FreshDB(), function()
            local a = GL.CreateSeason("A")
            local b = GL.CreateSeason("B")   -- beendet A, B ist aktiv
            IsFalse(GL.SetActiveSeason(a))   -- A ist beendet → kein Aufzeichnungsziel
            AreEqual(b, GuildLootDB.activeSeasonId)
        end)
    end

    function Tests:testSetActiveSeason_OpenSeasonAccepted()
        WithTestDB(FreshDB(), function()
            local a = GL.CreateSeason("A")
            GuildLootDB.activeSeasonId = nil     -- Zeiger verloren, Season noch offen
            IsTrue(GL.SetActiveSeason(a))
            AreEqual(a, GuildLootDB.activeSeasonId)
        end)
    end

    -- ========================================================
    -- ReopenSeason — Rückweg nach versehentlichem "Neue Season"
    -- ========================================================
    function Tests:testReopenSeason_ClearsEndedAtAndActivates()
        WithTestDB(FreshDB(), function()
            local a = GL.CreateSeason("A")
            local b = GL.CreateSeason("B")       -- beendet A versehentlich
            IsTrue(GL.ReopenSeason(a))
            AreEqual(a, GuildLootDB.activeSeasonId)
            AreEqual(nil, GuildLootDB.seasons[a].endedAt)
            -- B wurde im Gegenzug beendet: immer höchstens eine offene Season
            IsTrue(GuildLootDB.seasons[b].endedAt ~= nil)
        end)
    end

    function Tests:testReopenSeason_UnknownReturnsFalse()
        WithTestDB(FreshDB(), function()
            IsFalse(GL.ReopenSeason("nope"))
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

    function Tests:testEndSeason_IsIdempotent()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            GL.EndSeason(id)
            local first = GuildLootDB.seasons[id].endedAt
            GuildLootDB.seasons[id].endedAt = first - 500   -- älteres Ende simulieren
            IsTrue(GL.EndSeason(id))
            -- zweiter Aufruf verschiebt den Season-Zeitraum nicht
            AreEqual(first - 500, GuildLootDB.seasons[id].endedAt)
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

    function Tests:testSetSeasonRankFilter_NilIndexReturnsFalse()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            -- ohne Guard wäre das ein hartes "table index is nil"
            IsFalse(GL.SetSeasonRankFilter(id, nil, true))
            IsFalse(GL.SetSeasonRankFilter(id, nil, false))
        end)
    end

    function Tests:testSetSeasonRankFilter_StringIndexNormalized()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            IsTrue(GL.SetSeasonRankFilter(id, "3", true))
            IsTrue(GuildLootDB.seasons[id].rankFilter[3])   -- Zahl, nicht String
        end)
    end

    function Tests:testCreateSeason_StringRankKeysNormalized()
        WithTestDB(FreshDB(), function()
            -- so kämen die Schlüssel nach einem JSON-Roundtrip zurück
            local id = GL.CreateSeason("S", { ["2"] = true })
            IsTrue(GuildLootDB.seasons[id].rankFilter[2])
        end)
    end

    -- ========================================================
    -- DeleteSeason
    -- ========================================================
    function Tests:testDeleteSeason_RemovesEntryAndClearsActive()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("Verklickt")
            IsTrue(GL.DeleteSeason(id))
            AreEqual(nil, GuildLootDB.seasons[id])
            AreEqual(nil, GuildLootDB.activeSeasonId)
        end)
    end

    function Tests:testDeleteSeason_KeepsOtherSeasonsAndRaidData()
        WithTestDB(FreshDB(), function()
            GuildLootDB.raidContainers = { { id = "c1", startedAt = 100 } }
            local a = GL.CreateSeason("A")
            local b = GL.CreateSeason("B")   -- B ist aktiv
            IsTrue(GL.DeleteSeason(a))
            Exists(GuildLootDB.seasons[b])
            AreEqual(b, GuildLootDB.activeSeasonId)     -- aktive Season unberührt
            AreEqual(1, #GuildLootDB.raidContainers)    -- Raid-Daten bleiben
        end)
    end

    function Tests:testDeleteSeason_UnknownReturnsFalse()
        WithTestDB(FreshDB(), function()
            IsFalse(GL.DeleteSeason("nope"))
        end)
    end

    -- ========================================================
    -- RenameSeason
    -- ========================================================
    function Tests:testRenameSeason_ChangesNameButNotId()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("Alt")
            IsTrue(GL.RenameSeason(id, "Neu"))
            AreEqual("Neu", GuildLootDB.seasons[id].name)
            -- die ID ist Schlüssel in db.seasons und Referenz in activeSeasonId und darf
            -- sich beim Umbenennen nicht mitändern
            AreEqual(id, GuildLootDB.seasons[id].id)
            AreEqual(id, GuildLootDB.activeSeasonId)
        end)
    end

    function Tests:testRenameSeason_TrimsWhitespace()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("Alt")
            IsTrue(GL.RenameSeason(id, "  Neu  "))
            AreEqual("Neu", GuildLootDB.seasons[id].name)
        end)
    end

    function Tests:testRenameSeason_RejectsEmptyName()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("Alt")
            IsFalse(GL.RenameSeason(id, "   "))
            IsFalse(GL.RenameSeason(id, ""))
            IsFalse(GL.RenameSeason(id, nil))
            AreEqual("Alt", GuildLootDB.seasons[id].name)   -- unverändert
        end)
    end

    function Tests:testRenameSeason_UnknownIdIsNoOp()
        WithTestDB(FreshDB(), function()
            IsFalse(GL.RenameSeason("nope", "Neu"))
        end)
    end

    -- ========================================================
    -- SetSeasonEnd — Fenster nach hinten begrenzen
    -- ========================================================
    function Tests:testSetSeasonEnd_SetsEndAndClosesSeason()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            GL.SetSeasonStart(id, 1000)
            IsTrue(GL.SetSeasonEnd(id, 5000))
            AreEqual(5000, GuildLootDB.seasons[id].endedAt)
            -- ein Enddatum schließt die Season, wie GL.EndSeason auch
            AreEqual(nil, GuildLootDB.activeSeasonId)
        end)
    end

    function Tests:testSetSeasonEnd_RejectsEndBeforeStart()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            GL.SetSeasonStart(id, 5000)
            -- das Fenster bliebe sonst leer
            IsFalse(GL.SetSeasonEnd(id, 1000))
            AreEqual(nil, GuildLootDB.seasons[id].endedAt)
        end)
    end

    function Tests:testSetSeasonEnd_RejectsUnknownOrInvalid()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            IsFalse(GL.SetSeasonEnd("nope", 5000))
            IsFalse(GL.SetSeasonEnd(id, nil))
            IsFalse(GL.SetSeasonEnd(id, 0))
            IsFalse(GL.SetSeasonEnd(id, "morgen"))
        end)
    end

    function Tests:testSetSeasonEnd_CanCorrectAnExistingEnd()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            GL.SetSeasonStart(id, 1000)
            GL.EndSeason(id)                       -- stempelt time()
            IsTrue(GL.SetSeasonEnd(id, 5000))      -- nachträglich korrigieren
            AreEqual(5000, GuildLootDB.seasons[id].endedAt)
        end)
    end

    -- ========================================================
    -- SetSeasonStart — Zeitfenster nachträglich verschieben
    -- ========================================================
    function Tests:testSetSeasonStart_MovesWindowBack()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            IsTrue(GL.SetSeasonStart(id, 12345))
            AreEqual(12345, GuildLootDB.seasons[id].startedAt)
            AreEqual(nil, GuildLootDB.seasons[id].endedAt)   -- Ende bleibt unangetastet
        end)
    end

    function Tests:testSetSeasonStart_RejectsUnknownOrInvalid()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            IsFalse(GL.SetSeasonStart("nope", 12345))
            IsFalse(GL.SetSeasonStart(id, nil))
            IsFalse(GL.SetSeasonStart(id, 0))
            IsFalse(GL.SetSeasonStart(id, "keine Zahl"))
        end)
    end

    function Tests:testSetSeasonStart_RejectsStartAfterEnd()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            GuildLootDB.seasons[id].endedAt = 1000
            IsFalse(GL.SetSeasonStart(id, 2000))
            IsTrue(GL.SetSeasonStart(id, 500))
        end)
    end

    -- ========================================================
    -- SetSeasonRankThreshold — "Raider und höher" in einem Klick
    -- ========================================================
    function Tests:testSetSeasonRankThreshold_EnablesRankAndAllAbove()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            -- Schwelle "Raider" = Index 2 → 0 (GM), 1 (Offizier), 2 (Raider) aktiv
            IsTrue(GL.SetSeasonRankThreshold(id, 2))
            local rf = GuildLootDB.seasons[id].rankFilter
            IsTrue(rf[0])
            IsTrue(rf[1])
            IsTrue(rf[2])
            AreEqual(nil, rf[3])
            AreEqual(nil, rf[4])
        end)
    end

    function Tests:testSetSeasonRankThreshold_ReplacesPreviousSelection()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S", { [5] = true })
            GL.SetSeasonRankThreshold(id, 1)
            local rf = GuildLootDB.seasons[id].rankFilter
            IsTrue(rf[0])
            IsTrue(rf[1])
            AreEqual(nil, rf[5])   -- alte Auswahl ist weg, nicht dazugemischt
        end)
    end

    function Tests:testSetSeasonRankThreshold_UnknownSeasonOrBadIndex()
        WithTestDB(FreshDB(), function()
            local id = GL.CreateSeason("S")
            IsFalse(GL.SetSeasonRankThreshold("nope", 2))
            IsFalse(GL.SetSeasonRankThreshold(id, nil))
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
