-- RequiemRaidTools — src/tests/Util_Test.lua
-- Unit-Tests für Helper in src/Util.lua via WoWUnit.
--
-- VORAUSSETZUNGEN
--   1. WoWUnit-Addon installiert (OptionalDep in der TOC).
--   2. devMode aktiv: /reqrt devmode → /reload
-- Läuft auch standalone über busted (spec/reqrt_spec.lua).

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests = WoWUnit("ReqRT.Util")
    local GL    = GuildLoot

    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue
    local IsFalse  = WoWUnit.IsFalse
    local Exists   = WoWUnit.Exists
    -- Pending: busted (CI) zeigt den Test als "pending" an; WoWUnit in-game
    -- ist ein No-Op (WoWUnit.Pending existiert im echten Addon nicht).
    local function MarkPending(reason)
        if WoWUnit.Pending then WoWUnit.Pending(reason) end
    end

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

    local function WithTestDB(db, fn)
        local orig = GuildLootDB
        GuildLootDB = db
        local ok, err = pcall(fn)
        GuildLootDB = orig
        if not ok then error(err, 2) end
    end

    -- ========================================================
    -- A5: GL.ShortName (Util.lua:321)
    -- Fixiert das aktuelle Verhalten. Der dokumentierte Bug
    -- (return (ok and name) or fullName) tritt nur bei pcall-Fehler
    -- auf — in normalen Fällen müssen die Tests vor wie nach Fix grün sein.
    -- ========================================================

    function Tests:testShortName_NameWithRealm()
        AreEqual("Myriella", GL.ShortName("Myriella-Malfurion"))
    end

    function Tests:testShortName_NameWithoutRealm()
        AreEqual("Myriella", GL.ShortName("Myriella"))
    end

    function Tests:testShortName_EmptyString()
        AreEqual("", GL.ShortName(""))
    end

    function Tests:testShortName_Nil()
        AreEqual("", GL.ShortName(nil))
    end

    function Tests:testShortName_MultipleDashes()
        -- "Foo-Bar-Baz" → erstes Segment "Foo"
        AreEqual("Foo", GL.ShortName("Foo-Bar-Baz"))
    end

    function Tests:testShortName_OnlyDashPrefix()
        -- "-Realm" hat kein Segment vor dem Dash → pcall liefert ok=true,name=nil
        -- aktueller Code fällt dann auf fullName zurück
        AreEqual("-Realm", GL.ShortName("-Realm"))
    end

    -- ========================================================
    -- A4: GL.GetActivePrios / GL.GetPrioLabel (Util.lua:150, :166)
    -- Fixiert das Verhalten der verschachtelten Config-Lookups.
    -- Wenn das Refactoring einen internen Helper extrahiert, müssen
    -- diese Tests weiterhin grün bleiben.
    -- ========================================================

    function Tests:testGetActivePrios_FromSessionConfig()
        WithTestDB({
            activeContainerIdx = 1,
            raidContainers = { {
                priorityConfig = {
                    [1] = { active = true,  shortName = "BIS" },
                    [2] = { active = false, shortName = "MS"  },
                    [3] = { active = true,  shortName = "OS"  },
                    [4] = { active = false, shortName = "TR"  },
                    [5] = { active = true,  shortName = "TM"  },
                },
            } },
            settings = { priorities = {} },
        }, function()
            local prios = GL.GetActivePrios()
            AreEqual(3, #prios)
            AreEqual(1, prios[1])
            AreEqual(3, prios[2])
            AreEqual(5, prios[3])
        end)
    end

    function Tests:testGetActivePrios_SessionWithoutConfig_FallsBackToSettings()
        WithTestDB({
            activeContainerIdx = 1,
            raidContainers = { { priorityConfig = nil } },
            settings = {
                priorities = {
                    [1] = { active = true,  shortName = "BIS" },
                    [2] = { active = true,  shortName = "MS"  },
                    [4] = { active = true,  shortName = "TR"  },
                },
            },
        }, function()
            local prios = GL.GetActivePrios()
            AreEqual(3, #prios)
            AreEqual(1, prios[1])
            AreEqual(2, prios[2])
            AreEqual(4, prios[3])
        end)
    end

    function Tests:testGetActivePrios_NoActiveSession_UsesSettings()
        WithTestDB({
            activeContainerIdx = nil,
            raidContainers = {},
            settings = {
                priorities = {
                    [1] = { active = true,  shortName = "BIS" },
                    [4] = { active = true,  shortName = "TR"  },
                },
            },
        }, function()
            local prios = GL.GetActivePrios()
            AreEqual(2, #prios)
            AreEqual(1, prios[1])
            AreEqual(4, prios[2])
        end)
    end

    function Tests:testGetActivePrios_NoConfigAnywhere_Failsafe()
        WithTestDB({
            activeContainerIdx = nil,
            raidContainers = {},
            settings = { priorities = nil },
        }, function()
            local prios = GL.GetActivePrios()
            -- Failsafe in Util.lua:160: {1, 2, 4}
            AreEqual(3, #prios)
            AreEqual(1, prios[1])
            AreEqual(2, prios[2])
            AreEqual(4, prios[3])
        end)
    end

    function Tests:testGetActivePrios_OutOfBoundsActiveIdx_FallsBackToSettings()
        WithTestDB({
            activeContainerIdx = 5,
            raidContainers = {},
            settings = {
                priorities = {
                    [1] = { active = true, shortName = "BIS" },
                },
            },
        }, function()
            local prios = GL.GetActivePrios()
            AreEqual(1, #prios)
            AreEqual(1, prios[1])
        end)
    end

    function Tests:testGetPrioLabel_FromSession()
        WithTestDB({
            activeContainerIdx = 1,
            raidContainers = { {
                priorityConfig = {
                    [1] = { active = true, shortName = "BIS" },
                    [2] = { active = true, shortName = "MS"  },
                },
            } },
            settings = { priorities = {} },
        }, function()
            AreEqual("BIS", GL.GetPrioLabel(1))
            AreEqual("MS",  GL.GetPrioLabel(2))
        end)
    end

    function Tests:testGetPrioLabel_UnknownPrio_DefaultLabel()
        WithTestDB({
            activeContainerIdx = nil,
            raidContainers = {},
            settings = { priorities = {} },
        }, function()
            AreEqual("Prio 3", GL.GetPrioLabel(3))
        end)
    end

    function Tests:testGetPrioLabel_Nil_ReturnsEmpty()
        AreEqual("", GL.GetPrioLabel(nil))
    end

    -- ========================================================
    -- A3: GL.FindSessionByID — PENDING (Funktion existiert noch nicht)
    -- Wenn Refactoring Paket A3 umgesetzt wird, diese Tests aktivieren.
    -- ========================================================

    function Tests:testFindSessionByID_Found()
        if not GL.FindSessionByID then
            MarkPending("A3 not yet implemented — GL.FindSessionByID")
            return
        end
        WithTestDB({
            raidContainers = {
                { id = "sess-A", label = "A" },
                { id = "sess-B", label = "B" },
                { id = "sess-C", label = "C" },
            },
            settings = {},
        }, function()
            local s = GL.FindSessionByID("sess-B")
            Exists(s)
            AreEqual("B", s.label)
        end)
    end

    function Tests:testFindSessionByID_NotFound()
        if not GL.FindSessionByID then
            MarkPending("A3 not yet implemented — GL.FindSessionByID")
            return
        end
        WithTestDB({
            raidContainers = { { id = "sess-A" } },
            settings = {},
        }, function()
            AreEqual(nil, GL.FindSessionByID("sess-X"))
        end)
    end

    function Tests:testFindSessionByID_EmptyContainers()
        if not GL.FindSessionByID then
            MarkPending("A3 not yet implemented — GL.FindSessionByID")
            return
        end
        WithTestDB({ raidContainers = {}, settings = {} }, function()
            AreEqual(nil, GL.FindSessionByID("any"))
        end)
    end

    function Tests:testFindSessionByID_NilID()
        if not GL.FindSessionByID then
            MarkPending("A3 not yet implemented — GL.FindSessionByID")
            return
        end
        WithTestDB({
            raidContainers = { { id = "sess-A" } },
            settings = {},
        }, function()
            AreEqual(nil, GL.FindSessionByID(nil))
        end)
    end

    -- ========================================================
    -- A2: GL.ShowItemTooltip — PENDING (Funktion existiert noch nicht)
    -- ========================================================

    function Tests:testShowItemTooltip_OrderOfCalls()
        if not GL.ShowItemTooltip then
            MarkPending("A2 not yet implemented — GL.ShowItemTooltip")
            return
        end
        local calls = {}
        local fakeTooltip = {
            SetOwner     = function(self, frame, anchor) table.insert(calls, "SetOwner") end,
            SetHyperlink = function(self, link)          table.insert(calls, "SetHyperlink") end,
            Show         = function(self)                table.insert(calls, "Show") end,
            Hide         = function(self)                table.insert(calls, "Hide") end,
        }
        Mock(_G, "GameTooltip", fakeTooltip)
        GL.ShowItemTooltip("|Hitem:99999|h[Test]|h|r")
        MockRestore()
        AreEqual(3, #calls)
        AreEqual("SetOwner",     calls[1])
        AreEqual("SetHyperlink", calls[2])
        AreEqual("Show",         calls[3])
    end

    -- ========================================================
    -- A1: UI.COLORS / UI.BACKDROPS Konstanten — PENDING
    -- Wenn das neue UI_Common.lua existiert, prüfen wir die
    -- Hauptkonstanten-Existenz als Smoke-Test.
    -- ========================================================

    function Tests:testUICommon_ColorsExist()
        local UI = GL.UI
        if not (UI and UI.COLORS) then
            MarkPending("A1 not yet implemented — UI.COLORS table")
            return
        end
        Exists(UI.COLORS.DIVIDER)
        Exists(UI.COLORS.BG_AWARDED)
        Exists(UI.COLORS.HIGHLIGHT_HOVER)
    end

    function Tests:testUICommon_BackdropsExist()
        local UI = GL.UI
        if not (UI and UI.BACKDROPS) then
            MarkPending("A1 not yet implemented — UI.BACKDROPS table")
            return
        end
        Exists(UI.BACKDROPS.TOOLTIP)
        Exists(UI.BACKDROPS.DIALOG)
    end

    -- ========================================================
    -- B4: Tab-Registry — PENDING
    -- Wenn UI.lua die nummerierten Tab-Konstanten auf eine
    -- Registry-Tabelle umstellt, prüfen wir hier dass alle
    -- bekannten Tabs registriert sind.
    -- ========================================================

    function Tests:testTabRegistry_AllTabsRegistered()
        local UI = GL.UI
        if not (UI and UI.TABS) then
            MarkPending("B4 not yet implemented — UI.TABS registry table")
            return
        end
        local expected = { "LOOT", "LOG", "RAID", "ROLL", "PLAYER" }
        for _, name in ipairs(expected) do
            Exists(UI.TABS[name])
        end
    end

    -- ========================================================
    -- T2.5: GetItemCategory — Klassifizierung von Loot-Items
    -- ========================================================

    function Tests:testGetItemCategory_Weapon()
        Mock(_G, "C_Item", { GetItemSetID = function() return 0 end })
        AreEqual("weapons", GL.GetItemCategory(1, "INVTYPE_WEAPON",      4))
        AreEqual("weapons", GL.GetItemCategory(2, "INVTYPE_MAINHAND",    4))
        AreEqual("weapons", GL.GetItemCategory(3, "INVTYPE_2HWEAPON",    4))
        AreEqual("weapons", GL.GetItemCategory(4, "INVTYPE_SHIELD",      4))
        AreEqual("weapons", GL.GetItemCategory(5, "INVTYPE_HOLDABLE",    4))
        MockRestore()
    end

    function Tests:testGetItemCategory_Trinket()
        Mock(_G, "C_Item", { GetItemSetID = function() return 0 end })
        AreEqual("trinket", GL.GetItemCategory(1, "INVTYPE_TRINKET", 4))
        MockRestore()
    end

    function Tests:testGetItemCategory_Other()
        Mock(_G, "C_Item", { GetItemSetID = function() return 0 end })
        AreEqual("other", GL.GetItemCategory(1, "INVTYPE_CHEST",  4))
        AreEqual("other", GL.GetItemCategory(2, "INVTYPE_LEGS",   4))
        AreEqual("other", GL.GetItemCategory(3, "INVTYPE_FINGER", 4))
        MockRestore()
    end

    function Tests:testGetItemCategory_SetItemBySetID()
        -- SetID != 0 → direkt "setItems", egal welches equipLoc
        Mock(_G, "C_Item", { GetItemSetID = function() return 12345 end })
        AreEqual("setItems", GL.GetItemCategory(1, "INVTYPE_CHEST",  4))
        AreEqual("setItems", GL.GetItemCategory(2, "INVTYPE_WEAPON", 4))
        MockRestore()
    end

    function Tests:testGetItemCategory_CurioToken()
        -- Curio = nicht-ausrüstbar, Epic+, Name enthält "curio"
        Mock(_G, "C_Item", { GetItemSetID = function() return 0 end })
        Mock(_G, "GetItemInfo", function() return "Ancient Curio of Power" end)
        AreEqual("setItems", GL.GetItemCategory(1, "", 4))
        MockRestore()
    end

    -- ========================================================
    -- T2.5: DiffIDToString — WoW DifficultyID → "N"/"H"/"M"
    -- ========================================================

    function Tests:testDiffIDToString_Normal()
        AreEqual("N", GL.DiffIDToString(14))  -- Heroic-Raid replaced as Normal
        AreEqual("N", GL.DiffIDToString(1))   -- 5er Normal
        AreEqual("N", GL.DiffIDToString(17))  -- LFR
    end

    function Tests:testDiffIDToString_Heroic()
        AreEqual("H", GL.DiffIDToString(15))
        AreEqual("H", GL.DiffIDToString(2))
    end

    function Tests:testDiffIDToString_Mythic()
        AreEqual("M", GL.DiffIDToString(16))
        AreEqual("M", GL.DiffIDToString(8))
    end

    function Tests:testDiffIDToString_Unknown_ReturnsNil()
        AreEqual(nil, GL.DiffIDToString(999))
        AreEqual(nil, GL.DiffIDToString("foo"))
        AreEqual(nil, GL.DiffIDToString(nil))
    end

    -- ========================================================
    -- T2.5: DetectDifficulty — basiert auf GetInstanceInfo
    -- ========================================================

    function Tests:testDetectDifficulty_InRaid()
        Mock(_G, "GetInstanceInfo", function()
            return "Test Raid", "raid", 14
        end)
        AreEqual("N", GL.DetectDifficulty())
        MockRestore()
    end

    function Tests:testDetectDifficulty_InParty()
        Mock(_G, "GetInstanceInfo", function()
            return "Test Dungeon", "party", 16
        end)
        AreEqual("M", GL.DetectDifficulty())
        MockRestore()
    end

    function Tests:testDetectDifficulty_NotInInstance_ReturnsNil()
        Mock(_G, "GetInstanceInfo", function()
            return "", "none", 0
        end)
        AreEqual(nil, GL.DetectDifficulty())
        MockRestore()
    end

    -- ========================================================
    -- T2.5: NormalizeName — Realm-Suffix anhängen falls fehlend
    -- ========================================================

    function Tests:testNormalizeName_AppendsRealmWhenMissing()
        Mock(_G, "GetRealmName", function() return "Malfurion" end)
        AreEqual("Alice-Malfurion", GL.NormalizeName("Alice"))
        MockRestore()
    end

    function Tests:testNormalizeName_PreservesExistingRealm()
        Mock(_G, "GetRealmName", function() return "Malfurion" end)
        -- Cross-realm-Name → unverändert
        AreEqual("Alice-Antonidas", GL.NormalizeName("Alice-Antonidas"))
        MockRestore()
    end

    function Tests:testNormalizeName_NilSafe()
        Mock(_G, "GetRealmName", function() return "Malfurion" end)
        AreEqual(nil, GL.NormalizeName(nil))
        MockRestore()
    end

    -- ========================================================
    -- SessionLootKey — eindeutiger Hidden/Checked-Key pro
    -- Session-Loot-Eintrag (timestamp|player|item)
    -- ========================================================

    function Tests:testSessionLootKey_DifferentItemsSamePlayerSameSecond()
        -- Der Bug: gleicher Spieler, gleiche Sekunde, zwei Items → Keys müssen verschieden sein
        local a = GL.SessionLootKey({ timestamp = 100, player = "Alice-Malfurion", item = "[Axt der Prüfung]" })
        local b = GL.SessionLootKey({ timestamp = 100, player = "Alice-Malfurion", item = "[Schwert der Prüfung]" })
        IsTrue(a ~= b)
    end

    function Tests:testSessionLootKey_SeparatorDisambiguation()
        -- Ohne Separator wäre "123".."4Foo" == "1234".."Foo"
        local a = GL.SessionLootKey({ timestamp = 123,  player = "4Foo", item = "X" })
        local b = GL.SessionLootKey({ timestamp = 1234, player = "Foo",  item = "X" })
        IsTrue(a ~= b)
    end

    function Tests:testSessionLootKey_NilFieldsTolerated()
        AreEqual("100||", GL.SessionLootKey({ timestamp = 100 }))
        AreEqual("||",    GL.SessionLootKey({}))
    end

    function Tests:testSessionLootKey_Deterministic()
        local e = { timestamp = 100, player = "Alice-Malfurion", item = "[Axt]" }
        AreEqual(GL.SessionLootKey(e), GL.SessionLootKey(e))
    end

    -- --------------------------------------------------------
    -- TruncateText — Bossnamen in schmale Spaltenköpfe
    -- --------------------------------------------------------

    function Tests:testTruncateText_ShortTextUnchanged()
        AreEqual("Ulgrax", GL.TruncateText("Ulgrax", 8))
        AreEqual("Ulgrax", GL.TruncateText("Ulgrax", 6))   -- exakt passend
    end

    function Tests:testTruncateText_LongTextGetsEllipsis()
        -- 8 Zeichen gesamt: 7 Zeichen Text + "…"
        AreEqual("Bloodbo…", GL.TruncateText("Bloodbound Horror", 8))
    end

    function Tests:testTruncateText_CountsCharactersNotBytes()
        -- "Nerub-ar Palast" mit Umlaut: ein Schnitt mitten in der UTF-8-Sequenz
        -- ergäbe ein kaputtes Zeichen auf dem Bildschirm
        local out = GL.TruncateText("Kärgeröd Rakhan", 6)
        AreEqual("Kärge…", out)
    end

    -- --------------------------------------------------------
    -- ParseCSVLine — Gegenstück zum Quoting in GL.ExportCSV
    -- --------------------------------------------------------

    function Tests:testParseCSVLine_PlainFields()
        local f = GL.ParseCSVLine("2025-11-05,20:14,Nerub-ar Palace,H,Ulgrax,Alice-Malfurion,x")
        AreEqual(7, #f)
        AreEqual("2025-11-05",      f[1])
        AreEqual("Nerub-ar Palace", f[3])
        AreEqual("x",               f[7])
    end

    function Tests:testParseCSVLine_QuotedFieldWithComma()
        local f = GL.ParseCSVLine('a,"b,c",d')
        AreEqual(3,     #f)
        AreEqual("b,c", f[2])
    end

    function Tests:testParseCSVLine_DoubledQuotesInsideField()
        -- ExportCSV verdoppelt innenliegende Anführungszeichen
        local f = GL.ParseCSVLine('a,"sagt ""hallo""",b')
        AreEqual('sagt "hallo"', f[2])
        AreEqual("b",            f[3])
    end

    function Tests:testParseCSVLine_EmptyFields()
        local f = GL.ParseCSVLine("a,,b")
        AreEqual(3,  #f)
        AreEqual("", f[2])
        -- Komma am Zeilenende = letztes Feld leer (die BIS-Spalte ohne Marker)
        local g = GL.ParseCSVLine("a,b,")
        AreEqual(3,  #g)
        AreEqual("", g[3])
    end

    function Tests:testParseCSVLine_EmptyAndNil()
        AreEqual(1,  #GL.ParseCSVLine(""))
        AreEqual(1,  #GL.ParseCSVLine(nil))
    end

    -- --------------------------------------------------------
    -- NormalizeName — genau ein Realm, idempotent
    -- --------------------------------------------------------

    function Tests:testNormalizeName_CollapsesRepeatedRealm()
        -- Altbestand aus der DB: der Realm hängt dutzendfach dran
        AreEqual("Barbossbär-Antonidas",
                 GL.NormalizeName("Barbossbär-Antonidas-Antonidas-Antonidas"))
    end

    function Tests:testNormalizeName_Idempotent()
        local once  = GL.NormalizeName("Barbossbär-Antonidas")
        AreEqual(once, GL.NormalizeName(once))
        local bare  = GL.NormalizeName("Barbossbär")
        AreEqual(bare, GL.NormalizeName(bare))
    end

    function Tests:testNormalizeName_KeepsFirstRealm()
        -- der erste Realm ist der echte, spätere Segmente sind Müll
        AreEqual("Barbossbär-Antonidas",
                 GL.NormalizeName("Barbossbär-Antonidas-Malfurion"))
    end

    function Tests:testNormalizeName_AppendsRealmToBareName()
        AreEqual("Bob-TestRealm", GL.NormalizeName("Bob"))
    end

    function Tests:testNormalizeName_EmptyAndNil()
        AreEqual(nil, GL.NormalizeName(nil))
        AreEqual("",  GL.NormalizeName(""))
    end

    -- --------------------------------------------------------
    -- NameKey — Realm-Schreibweisen zusammenführen
    -- --------------------------------------------------------

    function Tests:testNameKey_IgnoresRealmSpacing()
        -- GetRealmName() liefert Leerzeichen, WoW selbst nicht — derselbe Spieler
        AreEqual(GL.NameKey("Barbossbär-Der Mithrilorden"),
                 GL.NameKey("Barbossbär-DerMithrilorden"))
    end

    function Tests:testNameKey_IgnoresCase()
        AreEqual(GL.NameKey("Barbossbär-Malfurion"), GL.NameKey("barbossbär-malfurion"))
    end

    function Tests:testNameKey_KeepsRealmDistinction()
        -- zwei Spieler gleichen Namens auf verschiedenen Realms sind verschiedene Spieler
        IsFalse(GL.NameKey("Barbossbär-Malfurion") == GL.NameKey("Barbossbär-Blackrock"))
    end

    function Tests:testNameKey_CollapsesRepeatedRealmSuffix()
        -- in der DB stecken Namen mit mehrfach angehängtem Realm; ein Spielername enthält
        -- nie einen Bindestrich, alles ab dem zweiten Segment ist Müll
        AreEqual(GL.NameKey("Barbossbär-Malfurion"),
                 GL.NameKey("Barbossbär-Malfurion-Malfurion"))
        AreEqual(GL.NameKey("Barbossbär-Malfurion"),
                 GL.NameKey("Barbossbär-Malfurion-Malfurion-Malfurion-Malfurion"))
        -- der erste Realm bleibt maßgeblich, nicht der letzte
        IsFalse(GL.NameKey("Barbossbär-Antonidas-Malfurion")
                == GL.NameKey("Barbossbär-Malfurion"))
    end

    function Tests:testNameKey_BareNameStaysBare()
        -- ohne Realm-Teil wird keiner erfunden — das ist Sache von GL.NormalizeName
        AreEqual("barbossbär", GL.NameKey("Barbossbär"))
        AreEqual("", GL.NameKey(nil))
    end

    function Tests:testTruncateText_HandlesNilAndZero()
        AreEqual("",       GL.TruncateText(nil, 8))
        AreEqual("Ulgrax", GL.TruncateText("Ulgrax", nil))   -- ohne Limit unverändert
        AreEqual("Ulgrax", GL.TruncateText("Ulgrax", 0))
    end
end)
