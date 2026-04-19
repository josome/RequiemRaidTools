-- RequiemRaidTools — src/tests/Assign_Test.lua
-- Integrationstests für die Loot-Zuweisung (Loot_Assign.lua) via WoWUnit.
--
-- VORAUSSETZUNGEN
--   1. WoWUnit-Addon installiert (OptionalDep in der TOC).
--   2. devMode aktiv: /reqrt devmode → /reload
--      Ohne devMode registriert sich diese Suite gar nicht — sie erscheint
--      nicht in WoWUnit und wird nicht ausgeführt.
--
-- NEUEN TESTFALL HINZUFÜGEN
--   1. Funktion in der Suite anlegen: function Tests:testMeinFall() ... end
--      Der Name muss mit "test" beginnen (WoWUnit-Konvention).
--   2. Assertions verwenden:
--        AreEqual(expected, actual)   — Werte müssen identisch sein (inkl. Typ)
--        Exists(value)                — Wert darf nicht nil/false sein
--        IsTrue(value)                — Wert muss true sein
--        IsFalse(value)               — Wert muss false/nil sein
--   3. DB-State via WithTestDB(fn) isolieren — nach dem Test wird GuildLootDB automatisch
--      zurückgeschrieben. currentItem am Ende mit Loot.ClearCurrentItem() bereinigen.
--   4. Externe Seiteneffekte (Netzwerk, Chat) via Mock(...) stubben, am Ende MockRestore().
--   5. /reload im Spiel — WoWUnit führt alle Tests beim Laden automatisch aus.

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests = WoWUnit("ReqRT.Assign")
    local Loot  = GuildLoot.Loot

    local Exists   = WoWUnit.Exists
    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue
    local IsFalse  = WoWUnit.IsFalse

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

    -- --------------------------------------------------------
    -- DB-Swap-Helper
    -- Ersetzt GuildLootDB für die Dauer von fn() durch einen sauberen Test-State.
    -- settings wird aus dem Original übernommen (devMode, Guards).
    -- --------------------------------------------------------
    local function WithTestDB(fn)
        local origDB = GuildLootDB
        -- Settings kopieren und Test-kritische Flags überschreiben
        local testSettings = {}
        for k, v in pairs(origDB.settings) do testSettings[k] = v end
        testSettings.whisperWinner = false  -- verhindert SendChatMessage-Aufruf mit Item-Links
        GuildLootDB = {
            raidContainers     = { {
                id          = "test-sess",
                label       = "Test",
                lootLog     = {},
                trashedLoot = {},
                raidMeta    = {},
                pendingLoot = {},
            } },
            activeContainerIdx = 1,
            settings           = testSettings,
            players            = {},
            currentRaid        = { id="raid-01", participants={"Myriella-Malfurion"}, currentKillParticipants={}, absent={} },
        }
        local session = GuildLootDB.raidContainers[1]
        local ok, err = pcall(fn, session)
        GuildLootDB = origDB  -- immer wiederherstellen, auch bei Fehler
        if not ok then error(err, 2) end
    end

    -- currentItem mit Testdaten befüllen (kein ActivateItem → kein Timer, kein GetItemInfo)
    local TEST_LINK = "|Hitem:212426|h[Egg]|h|r"
    local function SetupCurrentItem()
        local item = Loot.GetCurrentItem()
        item.link       = TEST_LINK
        item.name       = "Egg"
        item.itemID     = 212426
        item.quality    = 4
        item.category   = "trinket"
        item.difficulty = "H"
        item.boss       = "Ulgrax"
        item.raidID     = "raid-01"
        item.sessionID  = "test-sess"
        item.candidates = {}
        item.winners    = {}
        item.count      = 1
        item.prioState  = { active=false, timeLeft=0, timer=nil }
        item.rollState  = { active=false, players={}, results={}, timer=nil, timeLeft=0 }
    end

    -- Mocks für externe Seiteneffekte (Netzwerk, Chat, UI)
    local function MockSideEffects()
        Mock(GuildLoot,      "IsMasterLooter", function() return true end)
        Mock(GuildLoot,      "PostToRaid",     function() end)
        Mock(GuildLoot.Comm, "SendAssign",     function() end)
        Mock(GuildLoot.UI,   "Refresh",        function() end)
        Mock(GuildLoot.UI,   "RefreshLootTab", function() end)
    end

    -- --------------------------------------------------------
    -- testAssignSchreibtLootLog
    -- Prüft: AssignLootConfirm schreibt einen korrekten Eintrag in session.lootLog
    -- --------------------------------------------------------
    function Tests:testWritesLootLog()
        WithTestDB(function(session)
            SetupCurrentItem()
            MockSideEffects()

            -- Spieler meldet sich per Chat → candidates wird befüllt
            Loot.OnChatMessage("1 BIS", "Myriella-Malfurion")

            Loot.AssignLootConfirm("Myriella-Malfurion", "H")

            AreEqual(1,                    #session.lootLog)
            AreEqual("Myriella-Malfurion", session.lootLog[1].player)
            AreEqual(TEST_LINK,            session.lootLog[1].link)
            AreEqual("H",                  session.lootLog[1].difficulty)
            AreEqual("trinket",            session.lootLog[1].category)
            AreEqual(1,                    session.lootLog[1].winnerPrio)
            AreEqual("Ulgrax",             session.lootLog[1].boss)

            MockRestore()
        end)
    end

    -- --------------------------------------------------------
    -- testAssignEntferntAusPending
    -- Prüft: Item wird nach Assign aus pendingLoot entfernt
    -- --------------------------------------------------------
    function Tests:testRemovesFromPending()
        WithTestDB(function(session)
            session.pendingLoot = { { link=TEST_LINK, name="Ei des Eo'themar", itemID=212426, quality=4, category="trinket" } }
            SetupCurrentItem()
            MockSideEffects()

            Loot.AssignLootConfirm("Myriella-Malfurion", "H")

            AreEqual(0, #Loot.GetPendingLoot())

            MockRestore()
        end)
    end

    -- --------------------------------------------------------
    -- testAssignSchreibtPlayerRecord
    -- Prüft: players[name].counts und lootHistory werden korrekt befüllt
    -- --------------------------------------------------------
    function Tests:testWritesPlayerRecord()
        WithTestDB(function(session)
            SetupCurrentItem()
            MockSideEffects()

            Loot.AssignLootConfirm("Myriella-Malfurion", "H")

            local p = GuildLootDB.players["Myriella-Malfurion"]
            Exists(p)
            AreEqual(1,         p.counts.trinket)
            AreEqual(1,         #p.lootHistory)
            AreEqual(TEST_LINK, p.lootHistory[1].item)
            AreEqual("trinket", p.lootHistory[1].category)
            AreEqual("H",       p.lootHistory[1].difficulty)

            MockRestore()
        end)
    end

    -- --------------------------------------------------------
    -- testOnCommAssignSchreibtObserverLog
    -- Prüft: Observer-Pfad via OnCommAssign schreibt in aktive Session
    -- --------------------------------------------------------
    function Tests:testCommAssignObserver()
        WithTestDB(function(session)
            Mock(GuildLoot, "IsMasterLooter", function() return false end)

            GuildLoot.Loot.OnCommAssign(
                "Myriella-Malfurion", "H", TEST_LINK,
                "trinket", 4, 1, "Ulgrax",
                "test-sess", "raid-01"
            )

            AreEqual(1,                    #session.lootLog)
            AreEqual("Myriella-Malfurion", session.lootLog[1].player)
            AreEqual(TEST_LINK,            session.lootLog[1].link)
            AreEqual("H",                  session.lootLog[1].difficulty)
            AreEqual(1,                    session.lootLog[1].winnerPrio)

            MockRestore()
        end)
    end

end)
