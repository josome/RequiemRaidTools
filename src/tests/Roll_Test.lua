-- RequiemRaidTools — src/tests/Roll_Test.lua
-- Tests für Loot_Roll.lua: StartRoll, OnSystemMessage, FinalizeRoll (inkl. Tie-Re-Roll),
-- CancelRoll, OnCommRollStart (Observer).
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

    local Tests = WoWUnit("ReqRT.Roll")
    local GL    = GuildLoot
    local Loot  = GL.Loot

    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue
    local IsFalse  = WoWUnit.IsFalse
    local Exists   = WoWUnit.Exists

    -- --------------------------------------------------------
    -- Mock-Infrastruktur
    -- --------------------------------------------------------
    local _mocks = {}
    local function Mock(tbl, key, fn)
        table.insert(_mocks, { tbl=tbl, key=key, orig=tbl[key] })
        tbl[key] = fn
    end
    local function MockRestore()
        for i = #_mocks, 1, -1 do
            local m = _mocks[i]
            m.tbl[m.key] = m.orig
        end
        _mocks = {}
    end

    --- DB-Swap mit cleanup
    local function WithTestDB(fn)
        local origDB = GuildLootDB
        GuildLootDB = {
            activeContainerIdx = 1,
            raidContainers     = { { id = "sess-A", priorityConfig = {
                [1] = { active = true,  shortName = "BIS" },
                [2] = { active = true,  shortName = "MS"  },
                [3] = { active = false, shortName = "OS"  },
                [4] = { active = true,  shortName = "TR"  },
                [5] = { active = false, shortName = "TM"  },
            } } },
            currentRaid = {
                id = "raid-01",
                participants            = {},
                currentKillParticipants = {},
                absent                  = {},
            },
            settings = { rollSeconds = 15, isMasterLooter = true },
        }
        local ok, err = pcall(fn)
        GuildLootDB = origDB
        if not ok then error(err, 2) end
    end

    --- Default-Mocks (ML, kein Netz, no-op UI, sync Timer der nichts feuert)
    local function MockBasics()
        Mock(GL, "IsMasterLooter", function() return true end)
        Mock(GL, "Print",          function() end)
        Mock(GL, "PostToRaid",     function() end)
        Mock(GL, "PostRaidWarn",   function() end)
        if not GL.Comm then GL.Comm = {} end
        Mock(GL.Comm, "SendRollStart", function() end)
        Mock(_G, "C_Timer", {
            -- NewTicker liefert ein Cancel-fähiges Stub-Objekt;
            -- der Callback wird NICHT gefeuert (Tests prüfen Setup-State).
            NewTicker = function(_, _, _) return { Cancel = function() end } end,
            After     = function(_, fn) fn() end,
        })
        Mock(_G, "UnitName", function() return "Tester-Realm" end)
    end

    --- Setup für currentItem mit Kandidaten
    local function SetupCurrentItem(count, candidates)
        local ci = Loot.GetCurrentItem()
        ci.link       = "|Hitem:99999|h[TestItem]|h|r"
        ci.itemID     = 99999
        ci.count      = count or 1
        ci.candidates = candidates or {}
        ci.winners    = {}
        ci.winner     = nil
        ci._tieReRoll = nil
        ci.prioState  = { active=false, timeLeft=0, timer=nil }
        ci.rollState  = { active=false, players={}, results={}, timer=nil, timeLeft=0 }
        return ci
    end

    -- ========================================================
    -- StartRoll
    -- ========================================================

    function Tests:testStartRoll_SingleEligible_NoRollNeeded()
        WithTestDB(function()
            MockBasics()
            local ci = SetupCurrentItem(1, {
                ["Alice-Realm"] = { prio = 1 },
            })
            Loot.StartRoll()
            IsFalse(ci.rollState.active)            -- kein Roll gestartet
            AreEqual(1, #ci.winners)
            AreEqual("Alice", ci.winners[1])
            AreEqual("Alice", ci.winner)
            MockRestore()
        end)
    end

    function Tests:testStartRoll_MultipleEligible_TriggersRoll()
        WithTestDB(function()
            MockBasics()
            local ci = SetupCurrentItem(1, {
                ["Alice-Realm"] = { prio = 1 },
                ["Bob-Realm"]   = { prio = 1 },
                ["Carol-Realm"] = { prio = 1 },
            })
            Loot.StartRoll()
            IsTrue(ci.rollState.active)
            IsTrue(ci.rollState.players["Alice"])
            IsTrue(ci.rollState.players["Bob"])
            IsTrue(ci.rollState.players["Carol"])
            AreEqual(15, ci.rollState.timeLeft)
            MockRestore()
        end)
    end

    function Tests:testStartRoll_NoCandidates_Aborts()
        WithTestDB(function()
            MockBasics()
            local printed = nil
            Mock(GL, "Print", function(msg) printed = msg end)
            local ci = SetupCurrentItem(1, {})
            Loot.StartRoll()
            IsFalse(ci.rollState.active)
            Exists(printed)
            IsTrue(printed:find("No prio") ~= nil)
            MockRestore()
        end)
    end

    function Tests:testStartRoll_CrossTier_FillsByPrioOrder()
        -- 2 Kopien, 3 Kandidaten: 1× Prio 1, 1× Prio 2, 1× Prio 4
        -- Erwartung: Prio 1 + Prio 2 (zwei Tiers) gewinnen direkt — kein Roll nötig (#players == count)
        WithTestDB(function()
            MockBasics()
            local ci = SetupCurrentItem(2, {
                ["Alice-Realm"] = { prio = 1 },
                ["Bob-Realm"]   = { prio = 2 },
                ["Carol-Realm"] = { prio = 4 },
            })
            Loot.StartRoll()
            IsFalse(ci.rollState.active)
            AreEqual(2, #ci.winners)
            -- Reihenfolge: Alice (prio 1), Bob (prio 2)
            IsTrue(ci.winners[1] == "Alice")
            IsTrue(ci.winners[2] == "Bob")
            MockRestore()
        end)
    end

    -- ========================================================
    -- OnSystemMessage — Roll-Pattern-Matching
    -- ========================================================

    function Tests:testOnSystemMessage_EnglishPattern()
        WithTestDB(function()
            MockBasics()
            local ci = SetupCurrentItem(1, {})
            ci.rollState.active = true
            ci.rollState.players = { Alice = true }
            Loot.OnSystemMessage("Alice rolls 73 (1-100)")
            AreEqual(73, ci.rollState.results["Alice"])
            MockRestore()
        end)
    end

    function Tests:testOnSystemMessage_GermanPattern()
        WithTestDB(function()
            MockBasics()
            local ci = SetupCurrentItem(1, {})
            ci.rollState.active = true
            ci.rollState.players = { Alice = true }
            Loot.OnSystemMessage("Alice würfelt. Sie erhält eine 50 (1-100).")
            AreEqual(50, ci.rollState.results["Alice"])
            MockRestore()
        end)
    end

    function Tests:testOnSystemMessage_OnlyFirstRollCounts()
        WithTestDB(function()
            MockBasics()
            local ci = SetupCurrentItem(1, {})
            ci.rollState.active = true
            ci.rollState.players = { Alice = true }
            Loot.OnSystemMessage("Alice rolls 30 (1-100)")
            Loot.OnSystemMessage("Alice rolls 95 (1-100)")  -- soll ignoriert werden
            AreEqual(30, ci.rollState.results["Alice"])
            MockRestore()
        end)
    end

    function Tests:testOnSystemMessage_NonParticipant_Ignored()
        WithTestDB(function()
            MockBasics()
            local ci = SetupCurrentItem(1, {})
            ci.rollState.active = true
            ci.rollState.players = { Alice = true }
            Loot.OnSystemMessage("Eve rolls 99 (1-100)")  -- Eve nicht in players
            AreEqual(nil, ci.rollState.results["Eve"])
            MockRestore()
        end)
    end

    function Tests:testOnSystemMessage_RollNotActive_Ignored()
        WithTestDB(function()
            MockBasics()
            local ci = SetupCurrentItem(1, {})
            ci.rollState.active = false   -- Roll nicht aktiv
            ci.rollState.players = { Alice = true }
            Loot.OnSystemMessage("Alice rolls 73 (1-100)")
            AreEqual(nil, ci.rollState.results["Alice"])
            MockRestore()
        end)
    end

    -- ========================================================
    -- FinalizeRoll
    -- ========================================================

    function Tests:testFinalizeRoll_ClearWinner_NoTie()
        WithTestDB(function()
            MockBasics()
            local ci = SetupCurrentItem(1, {
                ["Alice-Realm"] = { prio = 1 },
                ["Bob-Realm"]   = { prio = 1 },
                ["Carol-Realm"] = { prio = 1 },
            })
            ci.rollState.active  = true
            ci.rollState.players = { Alice = true, Bob = true, Carol = true }
            ci.rollState.results = { Alice = 50, Bob = 75, Carol = 30 }
            Loot.FinalizeRoll()
            IsFalse(ci.rollState.active)
            AreEqual(1, #ci.winners)
            AreEqual("Bob", ci.winners[1])  -- höchster Roll
            AreEqual("Bob", ci.winner)
            AreEqual(nil, ci._tieReRoll)
            MockRestore()
        end)
    end

    function Tests:testFinalizeRoll_TieAtBoundary_TriggersReRoll()
        WithTestDB(function()
            MockBasics()
            local ci = SetupCurrentItem(1, {
                ["Alice-Realm"] = { prio = 1 },
                ["Bob-Realm"]   = { prio = 1 },
                ["Carol-Realm"] = { prio = 1 },
            })
            ci.rollState.active  = true
            ci.rollState.players = { Alice = true, Bob = true, Carol = true }
            ci.rollState.results = { Alice = 80, Bob = 80, Carol = 30 }  -- Alice + Bob tie auf 80
            Loot.FinalizeRoll()
            -- Re-Roll soll triggern
            IsTrue(ci.rollState.active)
            Exists(ci._tieReRoll)
            AreEqual(0, #ci._tieReRoll.confirmedWinners)
            AreEqual(1, ci._tieReRoll.spotsNeeded)
            -- Boundary-Gruppe muss in neuer players-Liste sein
            IsTrue(ci.rollState.players["Alice"])
            IsTrue(ci.rollState.players["Bob"])
            -- Carol nicht (war unter Boundary)
            IsFalse(ci.rollState.players["Carol"] == true)
            MockRestore()
        end)
    end

    function Tests:testFinalizeRoll_TieBetweenPrios_HigherPrioWins()
        WithTestDB(function()
            MockBasics()
            local ci = SetupCurrentItem(1, {
                ["Alice-Realm"] = { prio = 1 },
                ["Bob-Realm"]   = { prio = 2 },
            })
            ci.rollState.active  = true
            ci.rollState.players = { Alice = true, Bob = true }
            ci.rollState.results = { Alice = 50, Bob = 95 }  -- Bob höher, aber niedrigere Prio
            Loot.FinalizeRoll()
            -- Alice gewinnt wegen Prio 1 < Prio 2 (besser)
            IsFalse(ci.rollState.active)
            AreEqual(1, #ci.winners)
            AreEqual("Alice", ci.winners[1])
            MockRestore()
        end)
    end

    function Tests:testFinalizeRoll_FewerRollsThanSpots_AllWin()
        WithTestDB(function()
            MockBasics()
            local ci = SetupCurrentItem(2, {  -- 2 Kopien
                ["Alice-Realm"] = { prio = 1 },
                ["Bob-Realm"]   = { prio = 1 },
            })
            ci.rollState.active  = true
            ci.rollState.players = { Alice = true, Bob = true }
            ci.rollState.results = { Alice = 50 }  -- nur Alice hat gerollt
            Loot.FinalizeRoll()
            IsFalse(ci.rollState.active)
            AreEqual(1, #ci.winners)
            AreEqual("Alice", ci.winners[1])
            AreEqual(nil, ci._tieReRoll)
            MockRestore()
        end)
    end

    -- ========================================================
    -- CancelRoll
    -- ========================================================

    function Tests:testCancelRoll()
        WithTestDB(function()
            MockBasics()
            local ci = SetupCurrentItem(1, {})
            ci.rollState.active = true
            ci.rollState.timer  = { Cancel = function() end }
            Loot.CancelRoll()
            IsFalse(ci.rollState.active)
            AreEqual(nil, ci.rollState.timer)
            MockRestore()
        end)
    end

    -- ========================================================
    -- OnCommRollStart (Observer)
    -- ========================================================

    function Tests:testOnCommRollStart_ObserverPath()
        WithTestDB(function()
            MockBasics()
            Mock(GL, "IsMasterLooter", function() return false end)  -- Observer
            local ci = SetupCurrentItem(1, {})
            Loot.OnCommRollStart(15, { "Alice", "Bob" })
            IsTrue(ci.rollState.active)
            IsTrue(ci.rollState.players["Alice"])
            IsTrue(ci.rollState.players["Bob"])
            AreEqual(15, ci.rollState.timeLeft)
            IsFalse(ci.prioState.active)
            IsFalse(ci.rollState.iRolled)  -- neuer Roll → wieder rollbar (Reopen-Fix)
            MockRestore()
        end)
    end

    function Tests:testOnCommRollStart_MasterLooter_Ignored()
        WithTestDB(function()
            MockBasics()
            -- IsMasterLooter ist default true via MockBasics
            local ci = SetupCurrentItem(1, {})
            Loot.OnCommRollStart(15, { "Alice", "Bob" })
            -- ML soll OnCommRollStart ignorieren
            IsFalse(ci.rollState.active)
            MockRestore()
        end)
    end
end)
