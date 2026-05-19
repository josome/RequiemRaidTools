-- RequiemRaidTools — src/tests/Migration_Test.lua
-- Tests für Core.lua DB-Migrationen: InitDB, MigrateRaidHistory + indirekt
-- MigrateCurrentRaidLegacy und MigrateRaidFormat (über InitDB getriggert).
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

    local Tests = WoWUnit("ReqRT.Migration")
    local GL    = GuildLoot

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

    --- Setzt GuildLootDB auf den übergebenen Stand, ruft fn auf, stellt Original wieder her.
    --- Hinweis: fn darf GuildLootDB beliebig mutieren.
    local function WithTestDB(initialDB, fn)
        local origDB     = GuildLootDB
        local origBackup = GuildLootDBBackup
        GuildLootDB       = initialDB
        GuildLootDBBackup = nil
        Mock(GL, "Print", function() end)
        local ok, err = pcall(fn)
        GuildLootDB       = origDB
        GuildLootDBBackup = origBackup
        MockRestore()
        if not ok then error(err, 2) end
    end

    -- ========================================================
    -- InitDB — Defaults & Field-Filling
    -- ========================================================

    function Tests:testInitDB_EmptyDB_AppliesDefaults()
        WithTestDB(nil, function()
            GL.InitDB()
            Exists(GuildLootDB)
            Exists(GuildLootDB.players)
            Exists(GuildLootDB.raidContainers)
            Exists(GuildLootDB.unassignedRaids)
            Exists(GuildLootDB.currentRaid)
            Exists(GuildLootDB.settings)
            AreEqual(0, #GuildLootDB.raidContainers)
            AreEqual(0, #GuildLootDB.unassignedRaids)
            AreEqual(nil, GuildLootDB.activeContainerIdx)
        end)
    end

    function Tests:testInitDB_PartialDB_FillsMissingFields()
        WithTestDB({
            players = { ["Alice-Realm"] = { counts = { weapons = 5 } } },
            -- alles andere fehlt
        }, function()
            GL.InitDB()
            -- Bestandsdaten erhalten
            Exists(GuildLootDB.players["Alice-Realm"])
            AreEqual(5, GuildLootDB.players["Alice-Realm"].counts.weapons)
            -- Fehlende Felder gefüllt
            Exists(GuildLootDB.raidContainers)
            Exists(GuildLootDB.settings.priorities)
            Exists(GuildLootDB.currentRaid)
        end)
    end

    function Tests:testInitDB_PreservesExistingSettings()
        WithTestDB({
            settings = {
                chatChannel = "RAID",
                minQuality  = 3,
                rollSeconds = 20,
            },
        }, function()
            GL.InitDB()
            -- Bestand bleibt
            AreEqual("RAID", GuildLootDB.settings.chatChannel)
            AreEqual(3,      GuildLootDB.settings.minQuality)
            AreEqual(20,     GuildLootDB.settings.rollSeconds)
            -- Default ergänzt
            AreEqual(15,     GuildLootDB.settings.prioSeconds)
        end)
    end

    function Tests:testInitDB_ResetsTransientFlags()
        WithTestDB({
            settings = {
                isMasterLooter = true,   -- aus alter Session
                dungeonMode    = true,   -- transient, soll weg
            },
        }, function()
            GL.InitDB()
            -- Beide werden hart auf false/nil gesetzt
            IsFalse(GuildLootDB.settings.isMasterLooter)
            AreEqual(nil, GuildLootDB.settings.dungeonMode)
        end)
    end

    function Tests:testInitDB_GeneratesCurrentRaidIDIfMissing()
        WithTestDB({
            currentRaid = { id = "" },  -- leere ID
        }, function()
            GL.InitDB()
            IsTrue(GuildLootDB.currentRaid.id ~= "")
            -- 8-Hex-ID Format aus GL.GenerateRaidID
            IsTrue(#GuildLootDB.currentRaid.id >= 1)
        end)
    end

    function Tests:testInitDB_PreservesCurrentRaidID()
        WithTestDB({
            currentRaid = { id = "existing-id-12345" },
        }, function()
            GL.InitDB()
            AreEqual("existing-id-12345", GuildLootDB.currentRaid.id)
        end)
    end

    -- ========================================================
    -- MigrateRaidHistory — direkter Aufruf
    -- ========================================================

    function Tests:testMigrateRaidHistory_MovesEntriesAndClears()
        WithTestDB({
            raidHistory     = {
                { id = "raid-1", tier = "T1", difficulty = "H", lootLog = {} },
                { id = "raid-2", tier = "T2", difficulty = "M", lootLog = {} },
            },
            unassignedRaids = {},
        }, function()
            GL.MigrateRaidHistory()
            AreEqual(0, #GuildLootDB.raidHistory)
            AreEqual(2, #GuildLootDB.unassignedRaids)
            AreEqual("raid-1", GuildLootDB.unassignedRaids[1].id)
            AreEqual("raid-2", GuildLootDB.unassignedRaids[2].id)
        end)
    end

    function Tests:testMigrateRaidHistory_EmptyHistory_NoOp()
        WithTestDB({
            raidHistory     = {},
            unassignedRaids = {},
        }, function()
            GL.MigrateRaidHistory()
            AreEqual(0, #GuildLootDB.raidHistory)
            AreEqual(0, #GuildLootDB.unassignedRaids)
        end)
    end

    function Tests:testMigrateRaidHistory_AppendsNotReplaces()
        WithTestDB({
            raidHistory     = { { id = "new-1" } },
            unassignedRaids = { { id = "existing-1" } },
        }, function()
            GL.MigrateRaidHistory()
            AreEqual(2, #GuildLootDB.unassignedRaids)
            AreEqual("existing-1", GuildLootDB.unassignedRaids[1].id)
            AreEqual("new-1",      GuildLootDB.unassignedRaids[2].id)
        end)
    end

    -- ========================================================
    -- InitDB triggert MigrateRaidHistory
    -- ========================================================

    function Tests:testInitDB_TriggersRaidHistoryMigration()
        WithTestDB({
            raidHistory     = { { id = "legacy-1" } },
            unassignedRaids = {},
        }, function()
            GL.InitDB()
            AreEqual(0, #GuildLootDB.raidHistory)
            AreEqual(1, #GuildLootDB.unassignedRaids)
            AreEqual("legacy-1", GuildLootDB.unassignedRaids[1].id)
        end)
    end

    -- ========================================================
    -- InitDB triggert MigrateCurrentRaidLegacy (currentRaid.lootLog → unassigned)
    -- ========================================================

    function Tests:testInitDB_MigratesLegacyCurrentRaidLootLog()
        WithTestDB({
            currentRaid = {
                id           = "raid-legacy",
                tier         = "Nerub-ar",
                difficulty   = "H",
                participants = { "Alice-Realm", "Bob-Realm" },
                lootLog      = {  -- Legacy-Feld
                    { link = "|Hitem:1|h|r" },
                    { link = "|Hitem:2|h|r" },
                },
            },
        }, function()
            GL.InitDB()
            -- lootLog wurde in unassignedRaids gerettet
            AreEqual(1, #GuildLootDB.unassignedRaids)
            local migrated = GuildLootDB.unassignedRaids[1]
            AreEqual("raid-legacy", migrated.id)
            AreEqual("Nerub-ar",     migrated.tier)
            AreEqual(2, #migrated.lootLog)
            -- currentRaid.lootLog wurde geleert
            AreEqual(nil, GuildLootDB.currentRaid.lootLog)
        end)
    end

    function Tests:testInitDB_NoLegacyLootLog_NoUnassignedCreated()
        WithTestDB({
            currentRaid = {
                id      = "raid-clean",
                lootLog = {},  -- leer
            },
        }, function()
            GL.InitDB()
            AreEqual(0, #GuildLootDB.unassignedRaids)
        end)
    end

    -- ========================================================
    -- InitDB triggert MigrateRaidFormat (raidContainers[].raids → raidMeta)
    -- ========================================================

    function Tests:testInitDB_MigratesLegacyRaidsArrayToRaidMeta()
        WithTestDB({
            raidContainers = {
                {
                    id    = "sess-A",
                    label = "Session A",
                    raids = {  -- altes Format
                        {
                            id           = "raid-x",
                            tier         = "T1",
                            difficulty   = "H",
                            startedAt    = 1700000000,
                            participants = { "Alice-Realm" },
                            lootLog      = { { link = "|Hitem:1|h|r" } },
                            trashedLoot  = {},
                        },
                    },
                },
            },
        }, function()
            GL.InitDB()
            local s = GuildLootDB.raidContainers[1]
            -- raidMeta-Eintrag erzeugt
            Exists(s.raidMeta)
            Exists(s.raidMeta["raid-x"])
            AreEqual("T1", s.raidMeta["raid-x"].tier)
            AreEqual("H",  s.raidMeta["raid-x"].difficulty)
            -- lootLog wurde von raids[] in s.lootLog migriert mit raidID-Stempel
            AreEqual(1,        #s.lootLog)
            AreEqual("raid-x", s.lootLog[1].raidID)
            AreEqual("sess-A", s.lootLog[1].sessionID)
            -- Altes raids-Feld weg
            AreEqual(nil, s.raids)
        end)
    end

    function Tests:testInitDB_EnsuresRaidMetaTables()
        WithTestDB({
            raidContainers = {
                { id = "sess-X" },  -- ohne raidMeta/lootLog/trashedLoot
            },
        }, function()
            GL.InitDB()
            local s = GuildLootDB.raidContainers[1]
            Exists(s.raidMeta)
            Exists(s.lootLog)
            Exists(s.trashedLoot)
            AreEqual(0, #s.lootLog)
        end)
    end

    -- ========================================================
    -- Backup-Mechanik (indirekt über InitDB)
    -- ========================================================

    function Tests:testInitDB_CreatesBackupWhenLootExists()
        WithTestDB({
            raidContainers = {
                { id = "sess-A", lootLog = { { link = "|Hitem:1|h|r" } } },
            },
        }, function()
            GL.InitDB()
            Exists(GuildLootDBBackup)
            Exists(GuildLootDBBackup.raidContainers)
            AreEqual(1, #GuildLootDBBackup.raidContainers)
            Exists(GuildLootDBBackup.savedAt)
        end)
    end

    function Tests:testInitDB_NoBackupOnEmptyContainers()
        WithTestDB({
            raidContainers = {},
        }, function()
            GL.InitDB()
            -- Bei leeren raidContainers → BackupDB returnt früh, kein Backup
            AreEqual(nil, GuildLootDBBackup)
        end)
    end
end)
