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
            [1] = { active=true,  shortName="BiS",     description="Best in Slot" },
            [2] = { active=true,  shortName="Upgr",    description="Upgrade" },
            [3] = { active=false, shortName="",        description="" },
            [4] = { active=true,  shortName="Transmog", description="Transmog" },
            [5] = { active=false, shortName="",        description="" },
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
        AreEqual("BiS",      args[5][1].shortName)
        IsTrue(args[5][1].active)
        AreEqual("Upgr",     args[5][2].shortName)
        IsFalse(args[5][3].active)
        IsTrue(args[5][4].active)
        AreEqual("Transmog", args[5][4].shortName)
        IsFalse(args[5][5].active)
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
    -- RAID_META mit PrioConfig Roundtrip
    -- Prüft: prioCfg wird serialisiert, übertragen und korrekt deserialisiert
    -- --------------------------------------------------------
    function Tests:testRaidMetaWithPrioConfig()
        local args = nil
        Mock(GuildLoot, "OnCommRaidMeta", function(...) args = {...} end)

        local cfg = {
            [1] = { active=true,  shortName="BiS",     description="Best in Slot" },
            [2] = { active=true,  shortName="Upgr",    description="Upgrade" },
            [3] = { active=false, shortName="",        description="" },
            [4] = { active=true,  shortName="Transmog", description="Transmog" },
            [5] = { active=false, shortName="",        description="" },
        }
        local meta = { tier="Nerub-ar Palace", difficulty="H", startedAt=1700000000, closedAt=nil, participants={} }
        local msg = Roundtrip(function()
            Comm.SendRaidMeta("sess-01", "raid-99", meta, cfg)
        end)

        Exists(msg)
        Comm.OnMessage(msg, "MockSender-Realm")

        Exists(args)
        AreEqual("sess-01", args[1])
        AreEqual("raid-99", args[2])
        local receivedCfg = args[4]
        Exists(receivedCfg)
        AreEqual("BiS",      receivedCfg[1].shortName)
        IsTrue(receivedCfg[1].active)
        AreEqual("Upgr",     receivedCfg[2].shortName)
        IsTrue(receivedCfg[2].active)
        IsFalse(receivedCfg[3].active)
        IsTrue(receivedCfg[4].active)
        AreEqual("Transmog", receivedCfg[4].shortName)
        IsFalse(receivedCfg[5].active)
        MockRestore()
    end

    -- --------------------------------------------------------
    -- RAID_META ohne PrioConfig (Backward-Compat)
    -- Prüft: fehlendes Feld 9 → prioCfg = nil, kein Crash
    -- --------------------------------------------------------
    function Tests:testRaidMetaWithoutPrioConfig()
        local args = nil
        Mock(GuildLoot, "OnCommRaidMeta", function(...) args = {...} end)

        local meta = { tier="Nerub-ar Palace", difficulty="H", startedAt=1700000000, closedAt=nil, participants={} }
        local msg = Roundtrip(function()
            Comm.SendRaidMeta("sess-01", "raid-99", meta, nil)  -- kein prioCfg
        end)

        Exists(msg)
        Comm.OnMessage(msg, "MockSender-Realm")

        Exists(args)
        AreEqual("sess-01", args[1])
        IsFalse(args[4])  -- prioCfg = nil
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

    -- ============================================================
    -- B3: Version-Check-Verhalten in Comm.OnMessage (Comm.lua:340-371)
    -- Fixiert das Bestandsverhalten, bevor die if/elseif-Kette auf
    -- eine Predicate-Tabelle umgestellt wird.
    --
    -- Format einer Nachricht: "VERSION\tCMD\tARG1\t..."
    -- ============================================================

    local SEP_TAB = "\t"

    local function CapturePrints()
        local prints = {}
        Mock(GuildLoot, "Print", function(msg) table.insert(prints, msg) end)
        return prints
    end

    local function MakeMsg(version, cmd, ...)
        local parts = { version, cmd, ... }
        return table.concat(parts, SEP_TAB)
    end

    function Tests:testVersionWarn_IncompatibleOld()
        -- senderMinor < MIN_PROTO_MINOR (5) → "inkompatibel" + return (Handler NICHT aufgerufen)
        local handlerCalled = false
        Mock(GuildLoot.Loot, "OnCommItemActivate", function() handlerCalled = true end)
        local prints = CapturePrints()
        Mock(_G, "GetTime", function() return 100000 end)

        local msg = MakeMsg("0.4", "ITEM_ON", "|Hitem:1|h|r", "trinket")
        Comm.OnMessage(msg, "Older-Realm")

        IsFalse(handlerCalled)
        IsTrue(#prints >= 1)
        IsTrue(prints[1]:find("inkompatibel", 1, true) ~= nil)
        MockRestore()
    end

    function Tests:testVersionWarn_OlderButCompatible_HandlerStillCalled()
        -- senderMinor < localMinor aber >= MIN_PROTO_MINOR → Warnung + Dispatch
        local handlerCalled = false
        Mock(GuildLoot.Loot, "OnCommItemActivate", function() handlerCalled = true end)
        local prints = CapturePrints()
        Mock(_G, "GetTime", function() return 200000 end)

        -- ADDON_VERSION ist die installierte; wenn lokal z.B. "1.0.x" (Minor=10) → Sender "0.5" (Minor=5) ist älter aber kompatibel
        local msg = MakeMsg("0.5", "ITEM_ON", "|Hitem:1|h|r", "trinket")
        Comm.OnMessage(msg, "Compat-Realm")

        -- Bei aktueller installierter Version 1.0.x oder höher ist 0.5 älter → Warnung
        -- Bei installierter 0.5 ist es gleich → keine Warnung
        -- Handler muss in jedem Fall aufgerufen werden (kein early-return außer bei incompat)
        IsTrue(handlerCalled)
        MockRestore()
    end

    function Tests:testVersionWarn_NewerSender_HandlerStillCalled()
        -- senderMinor > localMinor → Warnung + Dispatch
        local handlerCalled = false
        Mock(GuildLoot.Loot, "OnCommItemActivate", function() handlerCalled = true end)
        local prints = CapturePrints()
        Mock(_G, "GetTime", function() return 300000 end)

        -- Major 9 → unrealistisch hoch, garantiert > local
        local msg = MakeMsg("9.99", "ITEM_ON", "|Hitem:1|h|r", "trinket")
        Comm.OnMessage(msg, "Newer-Realm")

        IsTrue(handlerCalled)
        IsTrue(#prints >= 1)
        -- "Deine Version ... ist älter" Warnung
        IsTrue(prints[1]:find("älter", 1, true) ~= nil)
        MockRestore()
    end

    function Tests:testVersionWarn_Cooldown()
        -- Zwei Nachrichten innerhalb von VERSION_WARN_COOLDOWN (300s) vom selben Sender:
        -- nur eine Warnung soll geprintet werden.
        local prints = CapturePrints()
        local sender = "CooldownTester-Realm"
        local t = 500000
        Mock(_G, "GetTime", function() return t end)

        local msg = MakeMsg("9.99", "ITEM_ON", "|Hitem:1|h|r", "trinket")
        Comm.OnMessage(msg, sender)
        local afterFirst = #prints
        t = t + 60  -- 60s später, noch innerhalb Cooldown
        Mock(_G, "GetTime", function() return t end)
        Comm.OnMessage(msg, sender)

        AreEqual(afterFirst, #prints)  -- keine zweite Warnung
        MockRestore()
    end

    function Tests:testVersionWarn_NoVersionPrefix()
        -- Nachricht ohne Version-Trennzeichen → spezielle Warnung + early-return
        local handlerCalled = false
        Mock(GuildLoot.Loot, "OnCommItemActivate", function() handlerCalled = true end)
        local prints = CapturePrints()

        Comm.OnMessage("MALFORMED_NO_TAB", "WeirdSender-Realm")

        IsFalse(handlerCalled)
        IsTrue(#prints >= 1)
        IsTrue(prints[1]:find("ohne Version", 1, true) ~= nil)
        MockRestore()
    end

    -- ============================================================
    -- C4: Self-Filter unterbricht den Dispatch komplett.
    -- testSelfFilter prüft bereits, dass ein einzelner Handler nicht
    -- aufgerufen wird. Dieser Test verifiziert dass der Dispatch
    -- generell stoppt — durch Mock auf einen anderen Handler-Pfad.
    -- ============================================================
    function Tests:testSelfFilter_DispatchStopsCompletely()
        local origLoopback = GuildLootDB.settings.commLoopback
        GuildLootDB.settings.commLoopback = false
        local activateCalled, clearCalled = false, false
        Mock(GuildLoot.Loot, "OnCommItemActivate", function() activateCalled = true end)
        Mock(GuildLoot.Loot, "OnCommItemClear",    function() clearCalled    = true end)

        local msg = Roundtrip(function()
            Comm.SendItemActivate("|Hitem:212426|h|r", "trinket")
        end)
        Comm.OnMessage(msg, UnitName("player"))

        IsFalse(activateCalled)
        IsFalse(clearCalled)
        GuildLootDB.settings.commLoopback = origLoopback
        MockRestore()
    end
end)
