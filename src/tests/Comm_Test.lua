-- RequiemRaidTools — src/tests/Comm_Test.lua
-- Roundtrip-Tests für die Comm-Schicht via WoWUnit.
-- Voraussetzung: WoWUnit installiert UND /reqrt devmode aktiv (dann /reload).

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests = WoWUnit("ReqRT.Comm")
    local Comm  = GuildLoot.Comm

    local Exists   = WoWUnit.Exists
    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue
    local IsFalse  = WoWUnit.IsFalse

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

    local function Roundtrip(sendFn)
        local captured = nil
        local saveLen  = #_mocks
        Mock(C_ChatInfo, "SendAddonMessage", function(prefix, msg) captured = msg end)
        Mock(Comm, "_isInRaid",  function() return true end)
        Mock(Comm, "_isInGroup", function() return true end)
        sendFn()
        for i = #_mocks, saveLen + 1, -1 do
            local m = _mocks[i]
            m.tbl[m.key] = m.orig
            _mocks[i] = nil
        end
        return captured
    end

    -- --------------------------------------------------------
    -- ASSIGN Roundtrip
    -- Prüft: Serialisierung + Deserialisierung + Typ-Konvertierung (number vs string)
    -- --------------------------------------------------------
    function Tests:testAssignRoundtrip()
        local args = nil
        Mock(GuildLoot.Loot, "OnCommAssign", function(...) args = {...} end)

        local msg = Roundtrip(function()
            Comm.SendAssign("Myriella-Malfurion", "H", "|Hitem:212426|h[Egg]|h|r",
                            "trinket", 4, 1, "Ulgrax", "sess-01", "raid-01")
        end)

        Exists(msg)
        Comm.OnMessage(msg, "MockSender-Realm")

        Exists(args)
        AreEqual("Myriella-Malfurion",       args[1])
        AreEqual("H",                        args[2])
        AreEqual("|Hitem:212426|h[Egg]|h|r", args[3])
        AreEqual("trinket",                  args[4])
        AreEqual(4,                          args[5])
        AreEqual(1,                          args[6])
        AreEqual("Ulgrax",                   args[7])
        AreEqual("sess-01",                  args[8])
        AreEqual("raid-01",                  args[9])
        MockRestore()
    end

    -- --------------------------------------------------------
    -- ITEM_ON Roundtrip
    -- --------------------------------------------------------
    function Tests:testItemOnRoundtrip()
        local args = nil
        Mock(GuildLoot.Loot, "OnCommItemActivate", function(...) args = {...} end)

        local msg = Roundtrip(function()
            Comm.SendItemActivate("|Hitem:212426|h[Egg]|h|r", "trinket")
        end)

        Exists(msg)
        Comm.OnMessage(msg, "MockSender-Realm")

        Exists(args)
        AreEqual("|Hitem:212426|h[Egg]|h|r", args[1])
        AreEqual("trinket",                   args[2])
        MockRestore()
    end

    -- --------------------------------------------------------
    -- SESSION_START mit PrioCfg Roundtrip
    -- Prüft auch SerializePrioCfg / DeserializePrioCfg implizit
    -- --------------------------------------------------------
    function Tests:testSessionStartRoundtrip()
        local args = nil
        Mock(GuildLoot, "OnCommSessionStart", function(...) args = {...} end)

        local cfg = {
            [1] = { active=true,  shortName="BiS",  description="Best in Slot" },
            [2] = { active=true,  shortName="Upgr", description="Upgrade" },
            [3] = { active=false, shortName="",     description="" },
            [4] = { active=false, shortName="",     description="" },
            [5] = { active=false, shortName="",     description="" },
        }
        local msg = Roundtrip(function()
            Comm.SendSessionStart("sess-01", "KW 15 2026", 1700000000, cfg)
        end)

        Exists(msg)
        Comm.OnMessage(msg, "MockSender-Realm")

        Exists(args)
        AreEqual("sess-01",          args[1])
        AreEqual("KW 15 2026",       args[2])
        AreEqual(1700000000,         args[3])
        AreEqual("MockSender-Realm", args[4])
        Exists(args[5])
        AreEqual("BiS",  args[5][1].shortName)
        IsTrue(args[5][1].active)
        AreEqual("Upgr", args[5][2].shortName)
        IsFalse(args[5][3].active)
        MockRestore()
    end

    -- --------------------------------------------------------
    -- ML-Guard: isMasterLooter = true → Observer-Handler ignoriert Nachricht
    -- --------------------------------------------------------
    function Tests:testMLGuard()
        local origML = GuildLootDB.settings.isMasterLooter
        GuildLootDB.settings.isMasterLooter = true
        GuildLoot.Loot.GetCurrentItem().link = nil

        local msg = Roundtrip(function()
            Comm.SendItemActivate("|Hitem:212426|h[Egg]|h|r", "trinket")
        end)
        Comm.OnMessage(msg, "MockSender-Realm")

        IsFalse(GuildLoot.Loot.GetCurrentItem().link)
        GuildLootDB.settings.isMasterLooter = origML
    end

    -- --------------------------------------------------------
    -- Self-Filter: loopback off → eigene Nachricht ignoriert
    -- --------------------------------------------------------
    function Tests:testSelfFilter()
        local origLoopback = GuildLootDB.settings.commLoopback
        GuildLootDB.settings.commLoopback = false
        local called = false
        Mock(GuildLoot.Loot, "OnCommItemActivate", function() called = true end)

        local msg = Roundtrip(function()
            Comm.SendItemActivate("|Hitem:212426|h|r", "trinket")
        end)
        Comm.OnMessage(msg, UnitName("player"))

        IsFalse(called)
        GuildLootDB.settings.commLoopback = origLoopback
        MockRestore()
    end

    -- --------------------------------------------------------
    -- Self-Filter: loopback on → eigene Nachricht verarbeitet
    -- --------------------------------------------------------
    function Tests:testSelfFilterLoopback()
        local origLoopback = GuildLootDB.settings.commLoopback
        GuildLootDB.settings.commLoopback = true
        local called = false
        Mock(GuildLoot.Loot, "OnCommItemActivate", function() called = true end)

        local msg = Roundtrip(function()
            Comm.SendItemActivate("|Hitem:212426|h|r", "trinket")
        end)
        Comm.OnMessage(msg, UnitName("player"))

        IsTrue(called)
        GuildLootDB.settings.commLoopback = origLoopback
        MockRestore()
    end

    -- --------------------------------------------------------
    -- ITEM_OFF Roundtrip
    -- Prüft: SendItemClear → OnCommItemClear wird aufgerufen
    -- --------------------------------------------------------
    function Tests:testItemOffRoundtrip()
        local called = false
        Mock(GuildLoot.Loot, "OnCommItemClear", function() called = true end)

        local msg = Roundtrip(function()
            Comm.SendItemClear()
        end)

        Exists(msg)
        Comm.OnMessage(msg, "MockSender-Realm")

        IsTrue(called)
        MockRestore()
    end

    -- --------------------------------------------------------
    -- SESSION_END Roundtrip
    -- Prüft: sessionID und closedAt (number) kommen korrekt an
    -- --------------------------------------------------------
    function Tests:testSessionEndRoundtrip()
        local args = nil
        Mock(GuildLoot, "OnCommSessionEnd", function(...) args = {...} end)

        local msg = Roundtrip(function()
            Comm.SendSessionEnd("sess-01", 1700001234)
        end)

        Exists(msg)
        Comm.OnMessage(msg, "MockSender-Realm")

        Exists(args)
        AreEqual("sess-01",    args[1])
        AreEqual(1700001234,   args[2])
        MockRestore()
    end

    -- --------------------------------------------------------
    -- RAID_META Roundtrip
    -- Prüft: alle Meta-Felder inkl. participants-Liste und closedAt (number)
    -- --------------------------------------------------------
    function Tests:testRaidMetaRoundtrip()
        local args = nil
        Mock(GuildLoot, "OnCommRaidMeta", function(...) args = {...} end)

        local meta = {
            tier         = "Nerub-ar Palace",
            difficulty   = "H",
            startedAt    = 1700000000,
            closedAt     = 1700003600,
            participants = { "Myriella-Malfurion", "Thorondis-Malfurion" },
        }
        local msg = Roundtrip(function()
            Comm.SendRaidMeta("sess-01", "raid-42", meta)
        end)

        Exists(msg)
        Comm.OnMessage(msg, "MockSender-Realm")

        Exists(args)
        AreEqual("sess-01",           args[1])
        AreEqual("raid-42",           args[2])
        local m = args[3]
        Exists(m)
        AreEqual("Nerub-ar Palace",   m.tier)
        AreEqual("H",                 m.difficulty)
        AreEqual(1700000000,          m.startedAt)
        AreEqual(1700003600,          m.closedAt)
        AreEqual(2,                   #m.participants)
        AreEqual("Myriella-Malfurion",  m.participants[1])
        AreEqual("Thorondis-Malfurion", m.participants[2])
        MockRestore()
    end

    -- --------------------------------------------------------
    -- ROLL_START Roundtrip
    -- Prüft: seconds (number) und players-Liste kommen korrekt an
    -- --------------------------------------------------------
    function Tests:testRollStartRoundtrip()
        local args = nil
        Mock(GuildLoot.Loot, "OnCommRollStart", function(...) args = {...} end)

        local msg = Roundtrip(function()
            Comm.SendRollStart(30, { "Myriella-Malfurion", "Thorondis-Malfurion" })
        end)

        Exists(msg)
        Comm.OnMessage(msg, "MockSender-Realm")

        Exists(args)
        AreEqual(30,                    args[1])
        AreEqual(2,                     #args[2])
        AreEqual("Myriella-Malfurion",  args[2][1])
        AreEqual("Thorondis-Malfurion", args[2][2])
        MockRestore()
    end

    -- --------------------------------------------------------
    -- RAID_QUERY Roundtrip
    -- Prüft: sender und inCombat (bool) kommen korrekt an
    -- --------------------------------------------------------
    function Tests:testRaidQueryRoundtrip()
        local args = nil
        Mock(GuildLoot, "OnCommRaidQuery", function(...) args = {...} end)

        local msg = Roundtrip(function()
            Comm.SendRaidQuery(true)
        end)

        Exists(msg)
        Comm.OnMessage(msg, "MockSender-Realm")

        Exists(args)
        AreEqual("MockSender-Realm", args[1])
        IsTrue(args[2])
        MockRestore()
    end

    -- --------------------------------------------------------
    -- ML_ANNOUNCE Roundtrip
    -- Prüft: neuer ML-Name kommt korrekt an
    -- --------------------------------------------------------
    function Tests:testMLAnnounceRoundtrip()
        local args = nil
        Mock(GuildLoot, "OnCommMLAnnounce", function(...) args = {...} end)

        local msg = Roundtrip(function()
            Comm.SendMLAnnounce("Myriella-Malfurion")
        end)

        Exists(msg)
        Comm.OnMessage(msg, "MockSender-Realm")

        Exists(args)
        AreEqual("Myriella-Malfurion", args[1])
        MockRestore()
    end

    -- --------------------------------------------------------
    -- ML_REQUEST Roundtrip
    -- Prüft: claimantName und sender kommen korrekt an
    -- --------------------------------------------------------
    function Tests:testMLRequestRoundtrip()
        local args = nil
        Mock(GuildLoot, "OnCommMLRequest", function(...) args = {...} end)

        local msg = Roundtrip(function()
            Comm.SendMLRequest("Myriella-Malfurion")
        end)

        Exists(msg)
        Comm.OnMessage(msg, "MockSender-Realm")

        Exists(args)
        AreEqual("Myriella-Malfurion", args[1])
        AreEqual("MockSender-Realm",   args[2])
        MockRestore()
    end

    -- --------------------------------------------------------
    -- ML_DENY Roundtrip
    -- Prüft: claimantName kommt korrekt an
    -- --------------------------------------------------------
    function Tests:testMLDenyRoundtrip()
        local args = nil
        Mock(GuildLoot, "OnCommMLDeny", function(...) args = {...} end)

        local msg = Roundtrip(function()
            Comm.SendMLDeny("Myriella-Malfurion")
        end)

        Exists(msg)
        Comm.OnMessage(msg, "MockSender-Realm")

        Exists(args)
        AreEqual("Myriella-Malfurion", args[1])
        MockRestore()
    end
end)
