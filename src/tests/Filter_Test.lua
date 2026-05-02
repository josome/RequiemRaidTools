-- RequiemRaidTools — src/tests/Filter_Test.lua
-- Prüft: kommt ein Item via OnCommItemActivate rein, zeigt der Filter-Check
-- ob ShowPlayerPopup aufgerufen wird oder nicht.
--
-- VORAUSSETZUNGEN
--   1. WoWUnit-Addon installiert
--   2. devMode aktiv: /reqrt devmode → /reload

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests = WoWUnit("ReqRT.Filter")
    local GL    = GuildLoot
    local Loot  = GL.Loot

    local IsTrue  = WoWUnit.IsTrue
    local IsFalse = WoWUnit.IsFalse

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

    -- GetItemInfo: Position 7=subType, 9=equipLoc
    -- subType darf nicht nil sein, sonst geht OnCommItemActivate in den Stale-Branch.
    local function MockItem(subType, equipLoc)
        Mock(_G, "GetItemInfo", function()
            return nil,nil,nil,nil,nil,nil, subType, nil, equipLoc
        end)
    end

    local function MockUsable(val)
        Mock(_G, "IsUsableItem", function() return val end)
    end

    local FAKE = "|Hitem:99999|h[TestItem]|h|r"

    -- --------------------------------------------------------
    -- Setup / Teardown
    -- --------------------------------------------------------
    local origDB
    local function Setup(filter)
        origDB = GuildLootDB
        GuildLootDB = {
            settings    = { isMasterLooter = false, announceFilter = filter },
            currentRaid = { pendingLoot = {} },
            raidContainers     = {},
            activeContainerIdx = nil,
        }
        Mock(GL,    "IsMasterLooter",  function() return false end)
        Mock(GL.UI, "RefreshLootTab",  function() end)
        Mock(GL.UI, "HidePlayerPopup", function() end)
    end

    local function Teardown()
        Loot.ClearCurrentItem()
        GuildLootDB = origDB
        MockRestore()
    end

    -- Ruft OnCommItemActivate auf und gibt zurück ob Popup/Roll-Tab aufgerufen wurden.
    -- Beide müssen identisches Verhalten zeigen (gleicher Filter, gleicher Stale-Guard).
    local function Run(category)
        local popupCalled, rollTabCalled = false, false
        Mock(GL.UI, "ShowPlayerPopup", function() popupCalled   = true end)
        Mock(GL.UI, "UpdateRollTab",   function() rollTabCalled = true end)
        Loot.OnCommItemActivate(FAKE, category)
        return popupCalled, rollTabCalled
    end

    -- --------------------------------------------------------
    -- Tests
    -- --------------------------------------------------------

    function Tests:testNone()
        Setup(nil)
        MockItem("Cloth", "INVTYPE_CHEST")
        local p, rt = Run("armor")
        IsTrue(p); IsTrue(rt)
        Teardown()
    end

    function Tests:testCloth()
        Setup({ cloth = false })
        MockItem("Cloth", "INVTYPE_CHEST")
        local p, rt = Run("armor")
        IsFalse(p); IsFalse(rt)
        Teardown()
    end

    function Tests:testLeather()
        Setup({ leather = false })
        MockItem("Leather", "INVTYPE_CHEST")
        local p, rt = Run("armor")
        IsFalse(p); IsFalse(rt)
        Teardown()
    end

    function Tests:testMail()
        Setup({ leather = false })
        MockItem("Mail", "INVTYPE_CHEST")
        local p, rt = Run("armor")
        IsTrue(p); IsTrue(rt)
        Teardown()
    end

    function Tests:testPlate()
        Setup({ plate = false })
        MockItem("Plate", "INVTYPE_CHEST")
        local p, rt = Run("armor")
        IsFalse(p); IsFalse(rt)
        Teardown()
    end

    function Tests:testTrinket()
        Setup({ trinket = false })
        MockItem("Gem", nil)  -- subType non-nil; category="trinket" → PopupFilterMatches prüft f.trinket
        local p, rt = Run("trinket")
        IsFalse(p); IsFalse(rt)
        Teardown()
    end

    function Tests:testTrinketOn()
        Setup({})
        MockItem("Gem", nil)
        local p, rt = Run("trinket")
        IsTrue(p); IsTrue(rt)
        Teardown()
    end

    function Tests:testWeaponOn()
        Setup({ nonUsableWeapon = false })
        MockItem("Sword", nil)
        MockUsable(true)
        local p, rt = Run("weapons")
        IsTrue(p); IsTrue(rt)
        Teardown()
    end

    function Tests:testWeaponOff()
        Setup({ nonUsableWeapon = false })
        MockItem("Sword", nil)
        MockUsable(false)
        local p, rt = Run("weapons")
        IsFalse(p); IsFalse(rt)
        Teardown()
    end

    function Tests:testNeck()
        Setup({ neck = false })
        MockItem("Plate", "INVTYPE_NECK")
        local p, rt = Run("armor")
        IsFalse(p); IsFalse(rt)
        Teardown()
    end

    function Tests:testRing()
        Setup({ ring = false })
        MockItem("Plate", "INVTYPE_FINGER")
        local p, rt = Run("armor")
        IsFalse(p); IsFalse(rt)
        Teardown()
    end

    function Tests:testOther()
        Setup({ other = false })
        MockItem("Token", nil)  -- kein bekannter subType/equipLoc → other-Fallback
        local p, rt = Run("armor")
        IsFalse(p); IsFalse(rt)
        Teardown()
    end

    function Tests:testStale()
        Setup({})
        Mock(_G, "GetItemInfo", function() return nil end)  -- nicht gecacht → weder Popup noch Roll-Tab sofort
        local p, rt = Run("armor")
        IsFalse(p); IsFalse(rt)
        Teardown()
    end
end)
