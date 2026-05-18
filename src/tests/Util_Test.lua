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
    -- Pending: busted (CI) hat globales pending() im it-Env; WoWUnit in-game nicht.
    -- Wir rufen es direkt im Test-Body via _G-Indirektion, damit der Test
    -- in busted als "pending" markiert wird, in WoWUnit aber als grün durchläuft.
    local function MarkPending(reason)
        local p = rawget(_G, "pending")
        if type(p) == "function" then p(reason) end
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
end)
