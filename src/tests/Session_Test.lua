-- RequiemRaidTools — src/tests/Session_Test.lua
-- Integrationstests für die Session-Logik (Core.lua) via WoWUnit.
--
-- VORAUSSETZUNGEN
--   1. WoWUnit-Addon installiert (OptionalDep in der TOC).
--   2. devMode aktiv: /reqrt devmode → /reload
--
-- NEUEN TESTFALL HINZUFÜGEN
--   1. Funktion anlegen: function Tests:testMeinFall() ... end
--   2. WithTestDB(fn) für DB-Isolation verwenden — GuildLootDB wird immer wiederhergestellt.
--   3. Externe Seiteneffekte (Comm, UI, Chat) via MockSideEffects() stubben.

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests = WoWUnit("ReqRT.Session")
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
    -- DB-Swap-Helper (pcall → GuildLootDB wird immer wiederhergestellt)
    -- --------------------------------------------------------
    local function WithTestDB(fn)
        local origDB = GuildLootDB
        local testSettings = {}
        for k, v in pairs(origDB.settings) do testSettings[k] = v end
        testSettings.isMasterLooter = true
        testSettings.whisperWinner  = false
        GuildLootDB = {
            raidContainers     = {},
            activeContainerIdx = nil,
            settings           = testSettings,
            players            = {},
            currentRaid        = {
                id                      = "raid-01",
                tier                    = "Nerub-ar Palace",
                difficulty              = "H",
                startedAt               = 1700000000,
                participants            = { "Myriella-Malfurion" },
                currentKillParticipants = {},
                absent                  = {},
            },
            unassignedRaids    = {},
        }
        local ok, err = pcall(fn)
        GuildLootDB = origDB
        if not ok then error(err, 2) end
    end

    -- Mocks für externe Seiteneffekte
    local function MockSideEffects()
        Mock(GuildLoot,      "IsMasterLooter",   function() return true end)
        Mock(GuildLoot,      "PostToRaid",        function() end)
        Mock(GuildLoot,      "Print",             function() end)
        Mock(GuildLoot.Comm, "SendSessionStart",  function() end)
        Mock(GuildLoot.Comm, "SendSessionEnd",    function() end)
        Mock(GuildLoot.Comm, "SendRaidMeta",      function() end)
        Mock(GuildLoot.Comm, "SendAssign",        function() end)
        Mock(GuildLoot.Comm, "SendRaidQuery",     function() end)
        Mock(GuildLoot.UI,   "Refresh",           function() end)
        Mock(GuildLoot.UI,   "RefreshLootTab",    function() end)
    end

    -- currentItem für Assign-Schritte vorbereiten
    local TEST_LINK = "|Hitem:212426|h[Egg]|h|r"
    local function SetupCurrentItem(raidID, sessionID)
        local item = Loot.GetCurrentItem()
        item.link       = TEST_LINK
        item.name       = "Egg"
        item.itemID     = 212426
        item.quality    = 4
        item.category   = "trinket"
        item.difficulty = "H"
        item.boss       = "Ulgrax"
        item.raidID     = raidID or "raid-01"
        item.sessionID  = sessionID or ""
        item.candidates = { ["Myriella-Malfurion"] = { prio=1 } }
        item.winners    = {}
        item.count      = 1
        item.prioState  = { active=false, timeLeft=0, timer=nil }
        item.rollState  = { active=false, players={}, results={}, timer=nil, timeLeft=0 }
    end

    -- --------------------------------------------------------
    -- testStart
    -- Prüft: StartContainer legt Session an und setzt sie als aktiv
    -- --------------------------------------------------------
    function Tests:testStart()
        WithTestDB(function()
            MockSideEffects()

            GuildLoot.StartContainer("KW 15 2026")

            AreEqual(1,            #GuildLootDB.raidContainers)
            AreEqual(1,            GuildLootDB.activeContainerIdx)
            AreEqual("KW 15 2026", GuildLootDB.raidContainers[1].label)
            Exists(GuildLootDB.raidContainers[1].id)
            Exists(GuildLootDB.raidContainers[1].startedAt)

            MockRestore()
        end)
    end

    -- --------------------------------------------------------
    -- testRename
    -- Prüft: Session-Label kann direkt geändert werden
    -- --------------------------------------------------------
    function Tests:testRename()
        WithTestDB(function()
            MockSideEffects()

            GuildLoot.StartContainer("Alter Name")
            GuildLootDB.raidContainers[1].label = "Neuer Name"

            AreEqual("Neuer Name", GuildLootDB.raidContainers[1].label)

            MockRestore()
        end)
    end

    -- --------------------------------------------------------
    -- testClose
    -- Prüft: CloseContainer setzt closedAt und deaktiviert die Session
    -- --------------------------------------------------------
    function Tests:testClose()
        WithTestDB(function()
            MockSideEffects()

            GuildLoot.StartContainer("Test Session")
            GuildLoot.CloseContainer()

            AreEqual(nil, GuildLootDB.activeContainerIdx)
            Exists(GuildLootDB.raidContainers[1].closedAt)
            IsTrue(GuildLootDB.raidContainers[1].closedAt > 0)

            MockRestore()
        end)
    end

    -- --------------------------------------------------------
    -- testDelete
    -- Prüft: Session kann aus raidContainers entfernt werden
    -- --------------------------------------------------------
    function Tests:testDelete()
        WithTestDB(function()
            MockSideEffects()

            GuildLoot.StartContainer("Zu löschende Session")
            GuildLoot.CloseContainer()
            table.remove(GuildLootDB.raidContainers, 1)
            GuildLootDB.activeContainerIdx = nil

            AreEqual(0, #GuildLootDB.raidContainers)

            MockRestore()
        end)
    end

    -- --------------------------------------------------------
    -- testStartBlockedWhenActive
    -- Prüft: StartContainer bricht ab wenn bereits eine Session aktiv ist
    -- --------------------------------------------------------
    function Tests:testStartBlockedWhenActive()
        WithTestDB(function()
            MockSideEffects()

            GuildLoot.StartContainer("Erste Session")
            GuildLoot.StartContainer("Zweite Session")  -- soll ignoriert werden

            AreEqual(1,               #GuildLootDB.raidContainers)
            AreEqual("Erste Session", GuildLootDB.raidContainers[1].label)

            MockRestore()
        end)
    end

    -- --------------------------------------------------------
    -- testDefaultLabel
    -- Prüft: StartContainer ohne Label generiert automatisch ein Label
    -- --------------------------------------------------------
    function Tests:testDefaultLabel()
        WithTestDB(function()
            MockSideEffects()

            GuildLoot.StartContainer("")

            local label = GuildLootDB.raidContainers[1].label
            Exists(label)
            IsTrue(label ~= "")

            MockRestore()
        end)
    end

    -- --------------------------------------------------------
    -- testPriorityConfig
    -- Prüft: session.priorityConfig wird aus settings.priorities übernommen
    -- --------------------------------------------------------
    function Tests:testPriorityConfig()
        WithTestDB(function()
            MockSideEffects()

            GuildLootDB.settings.priorities = {
                [1] = { active=true,  shortName="BiS",  description="Best in Slot" },
                [2] = { active=true,  shortName="Upgr", description="Upgrade" },
                [3] = { active=false, shortName="",     description="" },
            }

            GuildLoot.StartContainer("Prio-Test")

            local cfg = GuildLootDB.raidContainers[1].priorityConfig
            Exists(cfg)
            AreEqual("BiS",  cfg[1].shortName)
            IsTrue(cfg[1].active)
            AreEqual("Upgr", cfg[2].shortName)
            IsFalse(cfg[3].active)

            MockRestore()
        end)
    end

    -- --------------------------------------------------------
    -- testResume
    -- Prüft: ResumeContainer öffnet geschlossene Session wieder und lädt raidMeta
    -- --------------------------------------------------------
    function Tests:testResume()
        WithTestDB(function()
            MockSideEffects()

            GuildLoot.StartContainer("Resume-Test")
            local session = GuildLootDB.raidContainers[1]
            -- raidMeta manuell befüllen damit ResumeContainer currentRaid laden kann
            session.raidMeta["raid-99"] = {
                tier        = "Nerub-ar Palace",
                difficulty  = "H",
                startedAt   = 1700000000,
                closedAt    = nil,
                participants = { "Myriella-Malfurion" },
            }
            GuildLoot.CloseContainer()

            AreEqual(nil, GuildLootDB.activeContainerIdx)

            GuildLoot.ResumeContainer(1)

            AreEqual(1,   GuildLootDB.activeContainerIdx)
            AreEqual(nil, session.closedAt)
            AreEqual("raid-99",          GuildLootDB.currentRaid.id)
            AreEqual("Nerub-ar Palace",  GuildLootDB.currentRaid.tier)

            MockRestore()
        end)
    end

    -- --------------------------------------------------------
    -- testRaidsInSession
    -- Prüft: 4 Raids mit je einem Item-Assign erscheinen alle in Session
    -- --------------------------------------------------------
    function Tests:testRaidsInSession()
        WithTestDB(function()
            MockSideEffects()

            GuildLoot.StartContainer("Raidwoche Test")
            local session = GuildLootDB.raidContainers[GuildLootDB.activeContainerIdx]

            local raidIDs = { "raid-01", "raid-02", "raid-03", "raid-04" }
            for _, raidID in ipairs(raidIDs) do
                GuildLootDB.currentRaid.id = raidID
                GuildLoot.EnsureRaidMeta()
                SetupCurrentItem(raidID, session.id)
                Loot.AssignLootConfirm("Myriella-Malfurion", "H")
            end

            AreEqual(4, #session.lootLog)
            AreEqual(4, (function() local n=0; for _ in pairs(session.raidMeta) do n=n+1 end; return n end)())
            AreEqual("raid-01", session.lootLog[1].raidID)
            AreEqual("raid-02", session.lootLog[2].raidID)
            AreEqual("raid-03", session.lootLog[3].raidID)
            AreEqual("raid-04", session.lootLog[4].raidID)

            MockRestore()
        end)
    end

end)
