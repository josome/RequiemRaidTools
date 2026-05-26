-- RequiemRaidTools — src/tests/Export_Test.lua
-- Tests für GL.ExportJSON und GL.ExportCSV (Util.lua).
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

    local Tests = WoWUnit("ReqRT.Export")
    local GL    = GuildLoot

    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue
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

    local function WithTestDB(db, fn)
        local origDB = GuildLootDB
        GuildLootDB = db
        local ok, err = pcall(fn)
        GuildLootDB = origDB
        if not ok then error(err, 2) end
    end

    -- ========================================================
    -- ExportCSV
    -- ========================================================

    function Tests:testExportCSV_Header()
        local raid = { id = "r1", tier = "T", difficulty = "H", lootLog = {}, trashedLoot = {} }
        local csv = GL.ExportCSV(raid)
        local firstLine = csv:match("^[^\n]+")
        AreEqual("RaidID,Tier,Difficulty,Track,Date,Status,Player,Item,Category,Prio,Timestamp", firstLine)
    end

    function Tests:testExportCSV_AssignedItemRow()
        local raid = {
            id        = "raid-99",
            tier      = "Nerub-ar",
            difficulty= "M",
            startedAt = 0,
            lootLog   = {
                {
                    player     = "Alice-Realm",
                    item       = "|Hitem:1|h[TestItem]|h|r",
                    category   = "trinket",
                    difficulty = "M",
                    winnerPrio = 1,
                    timestamp  = 0,
                },
            },
            trashedLoot = {},
        }
        local csv = GL.ExportCSV(raid)
        -- Zweite Zeile ist die Item-Zeile
        local lines = {}
        for line in csv:gmatch("[^\n]+") do table.insert(lines, line) end
        AreEqual(2, #lines)  -- Header + 1 Item
        IsTrue(lines[2]:find("raid%-99") ~= nil)
        IsTrue(lines[2]:find("Nerub%-ar") ~= nil)
        IsTrue(lines[2]:find("Mythic") ~= nil)
        IsTrue(lines[2]:find("Assigned") ~= nil)
        IsTrue(lines[2]:find("Alice") ~= nil)        -- ShortName, nicht "Alice-Realm"
        IsTrue(lines[2]:find("Trinket") ~= nil)      -- CAT_LABEL mapping
    end

    function Tests:testExportCSV_TrashedItemRow()
        local raid = {
            id          = "r1",
            tier        = "T",
            difficulty  = "H",
            startedAt   = 0,
            lootLog     = {},
            trashedLoot = {
                { item = "|Hitem:42|h|r", category = "other", link = "|Hitem:42|h|r" },
            },
        }
        local csv = GL.ExportCSV(raid)
        IsTrue(csv:find("Trashed") ~= nil)
        IsTrue(csv:find("Other") ~= nil)
    end

    function Tests:testExportCSV_EscapesCommasInFields()
        local raid = {
            id          = "raid-1",
            tier        = "Tier, with comma",  -- Komma im Feld
            difficulty  = "H",
            startedAt   = 0,
            lootLog     = {
                {
                    player     = "Bob-Realm",
                    item       = "|Hitem:1|h[Item, with comma]|h|r",
                    category   = "weapons",
                    difficulty = "H",
                },
            },
            trashedLoot = {},
        }
        local csv = GL.ExportCSV(raid)
        -- Quotes wrappen Felder mit Komma
        IsTrue(csv:find('"Tier, with comma"') ~= nil)
    end

    function Tests:testExportCSV_EmptyRaid_OnlyHeader()
        local raid = { id = "r1", tier = "T", difficulty = "H", lootLog = {}, trashedLoot = {} }
        local csv = GL.ExportCSV(raid)
        local lines = {}
        for line in csv:gmatch("[^\n]+") do table.insert(lines, line) end
        AreEqual(1, #lines)  -- nur Header
    end

    function Tests:testExportCSV_UsesActiveSessionByDefault()
        WithTestDB({
            activeContainerIdx = 1,
            raidContainers     = { {
                id          = "sess-active",
                tier        = "Active",
                difficulty  = "M",
                startedAt   = 0,
                lootLog     = { { player="Alice", item="X", category="trinket", difficulty="M" } },
                trashedLoot = {},
            } },
            currentRaid = { id = "other", lootLog = {}, trashedLoot = {} },
            players     = {},
            settings    = { priorities = {} },
        }, function()
            local csv = GL.ExportCSV()
            IsTrue(csv:find("sess%-active") ~= nil)
        end)
    end

    -- ========================================================
    -- ExportJSON
    -- ========================================================

    function Tests:testExportJSON_ContainsTopLevelFields()
        WithTestDB({
            activeContainerIdx = 1,
            raidContainers     = { { id = "sess-A", lootLog = {}, trashedLoot = {} } },
            currentRaid = { id = "x" },
            players     = { ["Alice"] = { counts = { weapons = 1 } } },
            settings    = { priorities = {} },
        }, function()
            local json = GL.ExportJSON()
            Exists(json)
            IsTrue(type(json) == "string")
            IsTrue(json:find('"exportedAt"') ~= nil)
            IsTrue(json:find('"raid"')       ~= nil)
            IsTrue(json:find('"players"')    ~= nil)
            -- Active Session wird verwendet, nicht currentRaid
            IsTrue(json:find('sess%-A') ~= nil)
        end)
    end

    function Tests:testExportJSON_AcceptsExplicitRaidData()
        WithTestDB({
            activeContainerIdx = nil,
            raidContainers     = {},
            currentRaid = { id = "fallback" },
            players     = {},
            settings    = { priorities = {} },
        }, function()
            local explicit = { id = "explicit-raid", lootLog = {}, trashedLoot = {} }
            local json = GL.ExportJSON(explicit)
            IsTrue(json:find('explicit%-raid') ~= nil)
            -- Fallback darf NICHT enthalten sein
            IsTrue(json:find('"id":"fallback"') == nil)
        end)
    end

    function Tests:testExportJSON_FallsBackToCurrentRaid()
        WithTestDB({
            activeContainerIdx = nil,
            raidContainers     = {},
            currentRaid = { id = "fallback-raid", tier = "T1" },
            players     = {},
            settings    = { priorities = {} },
        }, function()
            local json = GL.ExportJSON()
            IsTrue(json:find('fallback%-raid') ~= nil)
        end)
    end

    function Tests:testExportJSON_EscapesQuotesInStrings()
        WithTestDB({
            activeContainerIdx = nil,
            raidContainers     = {},
            currentRaid = { id = 'has-"quotes"-inside', lootLog = {}, trashedLoot = {} },
            players     = {},
            settings    = { priorities = {} },
        }, function()
            local json = GL.ExportJSON()
            -- Quotes müssen escaped sein
            IsTrue(json:find('\\"quotes\\"') ~= nil)
        end)
    end
end)
