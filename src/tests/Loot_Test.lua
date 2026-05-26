-- RequiemRaidTools — src/tests/Loot_Test.lua
-- Tests für Loot.lua: OnLootOpened, OnLootRollStart, AddItemManually,
-- TryAddPendingItem-Filter, Trash-Operations, ResetCurrentItem, CancelPrio.
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

    local Tests = WoWUnit("ReqRT.Loot")
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

    --- DB-Swap mit aktiver Session
    local function WithTestDB(fn)
        local origDB = GuildLootDB
        GuildLootDB = {
            activeContainerIdx = 1,
            raidContainers = { {
                id          = "sess-A",
                label       = "A",
                pendingLoot = {},
                lootLog     = {},
                trashedLoot = {},
                raidMeta    = {},
            } },
            currentRaid = {
                id           = "raid-01",
                tier         = "Nerub-ar",
                difficulty   = "H",
                participants = {},
                pendingLoot  = {},  -- Fallback wenn kein Session
                lastBoss     = "Ulgrax",
            },
            settings = {
                minQuality      = 4,
                filterNonEquip  = true,
                filterCategories= { weapons=true, trinket=true, setItems=true, other=true },
            },
        }
        local ok, err = pcall(fn)
        GuildLootDB = origDB
        if not ok then error(err, 2) end
    end

    --- Default-Item-Info: Cloth-Chest, Epic, BoP, kein Set, kein Token.
    --- ItemInfo-Tupel: name, link, quality, iLevel, reqLvl, type, subType, stackCount, equipLoc, icon, sellPrice, classID, subClassID, bindType
    local function MockItemInfo(overrides)
        overrides = overrides or {}
        Mock(_G, "GetItemInfo", function(link)
            return overrides.name     or "TestItem",
                   link,
                   overrides.quality  or 4,
                   overrides.iLevel   or 600,
                   nil, nil,
                   overrides.subType  or "Cloth",
                   nil,
                   overrides.equipLoc or "INVTYPE_CHEST",
                   nil, nil, nil, nil,
                   overrides.bindType or 1  -- BoP
        end)
        Mock(_G, "C_Item", { GetItemSetID = function() return overrides.setID or 0 end })
    end

    local function MockBasics()
        Mock(GL, "IsMasterLooter", function() return true end)
        Mock(GL, "Print",          function() end)
        if not GL.Comm then GL.Comm = {} end
        Mock(GL.Comm, "SendItemClear", function() end)
        if not GL.UI then GL.UI = {} end
        Mock(GL.UI, "RefreshLootTab",  function() end)
        Mock(GL.UI, "HidePlayerPopup", function() end)
        MockItemInfo()
    end

    --- Mockt GetNumLootItems/GetLootSlotInfo/GetLootSlotLink für OnLootOpened.
    --- slots: { { link, name?, quality?, questItem? }, ... }
    local function MockLootSlots(slots)
        Mock(_G, "GetNumLootItems", function() return #slots end)
        Mock(_G, "GetLootSlotInfo", function(slot)
            local s = slots[slot]
            if not s then return nil end
            -- _, name, _, _, quality, _, isQuestItem
            return nil, s.name or "Item", nil, nil, s.quality or 4, nil, s.questItem or false
        end)
        Mock(_G, "GetLootSlotLink", function(slot)
            return slots[slot] and slots[slot].link
        end)
    end

    --- Mockt das WoW group-loot-Roll-Fenster
    local function MockLootRoll(rollID, link, quality)
        Mock(_G, "GetLootRollItemLink", function(id) return id == rollID and link or nil end)
        Mock(_G, "GetLootRollItemInfo", function(id)
            if id ~= rollID then return nil end
            return "TestItem", "TestItem", nil, quality or 4
        end)
    end

    -- ========================================================
    -- OnLootOpened
    -- ========================================================

    function Tests:testOnLootOpened_NotMasterLooter_Ignored()
        WithTestDB(function()
            MockBasics()
            Mock(GL, "IsMasterLooter", function() return false end)
            MockLootSlots({ { link = "|Hitem:1|h|r" } })
            Loot.OnLootOpened()
            AreEqual(0, #Loot.GetPendingLoot())
            MockRestore()
        end)
    end

    function Tests:testOnLootOpened_AddsQualifiedItems()
        WithTestDB(function()
            MockBasics()
            MockLootSlots({
                { link = "|Hitem:1|h|r", quality = 4 },
                { link = "|Hitem:2|h|r", quality = 5 },
            })
            Loot.OnLootOpened()
            AreEqual(2, #Loot.GetPendingLoot())
            MockRestore()
        end)
    end

    function Tests:testOnLootOpened_FiltersLowQuality()
        WithTestDB(function()
            MockBasics()
            -- minQuality = 4; ein Item drunter, eins drauf
            MockLootSlots({
                { link = "|Hitem:1|h|r", quality = 3 },
                { link = "|Hitem:2|h|r", quality = 4 },
            })
            Loot.OnLootOpened()
            AreEqual(1, #Loot.GetPendingLoot())
            MockRestore()
        end)
    end

    function Tests:testOnLootOpened_FiltersQuestItems()
        WithTestDB(function()
            MockBasics()
            MockLootSlots({
                { link = "|Hitem:1|h|r", quality = 4, questItem = true },
                { link = "|Hitem:2|h|r", quality = 4, questItem = false },
            })
            Loot.OnLootOpened()
            AreEqual(1, #Loot.GetPendingLoot())
            MockRestore()
        end)
    end

    function Tests:testOnLootOpened_DeduplicatesAgainstExistingPending()
        WithTestDB(function()
            MockBasics()
            -- Bereits ein Item im Pending
            table.insert(Loot.GetPendingLoot(), { link = "|Hitem:1|h|r", name = "Existing" })
            MockLootSlots({
                { link = "|Hitem:1|h|r" },  -- Duplikat
                { link = "|Hitem:2|h|r" },  -- neu
            })
            Loot.OnLootOpened()
            AreEqual(2, #Loot.GetPendingLoot())  -- 1 existing + 1 neu (Duplikat blockiert)
            MockRestore()
        end)
    end

    function Tests:testOnLootOpened_AllowsMultipleDrops()
        WithTestDB(function()
            MockBasics()
            -- 2× dasselbe Item im Loot-Fenster, 0× in pending → beide hinzu
            MockLootSlots({
                { link = "|Hitem:5|h|r" },
                { link = "|Hitem:5|h|r" },
            })
            Loot.OnLootOpened()
            AreEqual(2, #Loot.GetPendingLoot())
            MockRestore()
        end)
    end

    -- ========================================================
    -- OnLootRollStart (MASTER-Loot)
    -- ========================================================

    function Tests:testOnLootRollStart_NotMasterLooter_Ignored()
        WithTestDB(function()
            MockBasics()
            Mock(GL, "IsMasterLooter", function() return false end)
            MockLootRoll(101, "|Hitem:1|h|r", 4)
            Loot.OnLootRollStart(101)
            AreEqual(0, #Loot.GetPendingLoot())
            MockRestore()
        end)
    end

    function Tests:testOnLootRollStart_NoActiveSession_Ignored()
        WithTestDB(function()
            MockBasics()
            GuildLootDB.activeContainerIdx = nil
            MockLootRoll(102, "|Hitem:1|h|r", 4)
            Loot.OnLootRollStart(102)
            -- Fallback pendingLoot in currentRaid sollte auch leer sein, weil session checked
            local pl = GuildLootDB.currentRaid.pendingLoot
            AreEqual(0, #pl)
            MockRestore()
        end)
    end

    function Tests:testOnLootRollStart_AddsItem()
        WithTestDB(function()
            MockBasics()
            MockLootRoll(103, "|Hitem:7|h|r", 4)
            Loot.OnLootRollStart(103)
            AreEqual(1, #Loot.GetPendingLoot())
            AreEqual("|Hitem:7|h|r", Loot.GetPendingLoot()[1].link)
            MockRestore()
        end)
    end

    function Tests:testOnLootRollStart_LowQuality_Ignored()
        WithTestDB(function()
            MockBasics()
            MockLootRoll(104, "|Hitem:8|h|r", 3)  -- quality 3 < min 4
            Loot.OnLootRollStart(104)
            AreEqual(0, #Loot.GetPendingLoot())
            MockRestore()
        end)
    end

    function Tests:testOnLootRollStart_DuplicateRollIDIgnored()
        WithTestDB(function()
            MockBasics()
            MockLootRoll(105, "|Hitem:9|h|r", 4)
            Loot.OnLootRollStart(105)
            Loot.OnLootRollStart(105)  -- gleiche rollID → ignoriert
            AreEqual(1, #Loot.GetPendingLoot())
            MockRestore()
        end)
    end

    -- ========================================================
    -- AddItemManually
    -- ========================================================

    function Tests:testAddItemManually_AddsToPending()
        WithTestDB(function()
            MockBasics()
            Loot.AddItemManually("|Hitem:42|h|r")
            AreEqual(1, #Loot.GetPendingLoot())
            AreEqual("|Hitem:42|h|r", Loot.GetPendingLoot()[1].link)
        end)
        MockRestore()
    end

    function Tests:testAddItemManually_DeferredWhenItemInfoMissing()
        WithTestDB(function()
            MockBasics()
            Mock(_G, "GetItemInfo", function() return nil end)  -- noch nicht gecacht
            Loot._deferredPendingItems = {}
            Loot.AddItemManually("|Hitem:99|h|r")
            -- Nicht direkt in pending, aber in deferred
            AreEqual(0, #Loot.GetPendingLoot())
            AreEqual(1, #Loot._deferredPendingItems)
            IsTrue(Loot._deferredPendingItems[1].manual)
            MockRestore()
        end)
    end

    -- ========================================================
    -- TryAddPendingItem-Filter
    -- ========================================================

    function Tests:testTryAddPendingItem_FiltersWarbound()
        WithTestDB(function()
            MockBasics()
            MockItemInfo({ bindType = 8 })  -- Warbound (ToBnetAccount)
            local item = { link = "|Hitem:1|h|r", itemID = 1, quality = 4 }
            Loot.TryAddPendingItem(item, "INVTYPE_CHEST")
            AreEqual(0, #Loot.GetPendingLoot())
            MockRestore()
        end)
    end

    function Tests:testTryAddPendingItem_FiltersNonEquipWhenSet()
        WithTestDB(function()
            MockBasics()
            -- filterNonEquip = true (default), equipLoc leer, kein Set-Token
            local item = { link = "|Hitem:1|h|r", itemID = 1, quality = 4 }
            Loot.TryAddPendingItem(item, "")  -- non-equip
            AreEqual(0, #Loot.GetPendingLoot())
            MockRestore()
        end)
    end

    function Tests:testTryAddPendingItem_StampsRaidAndSessionID()
        WithTestDB(function()
            MockBasics()
            local item = { link = "|Hitem:1|h|r", itemID = 1, quality = 4 }
            Loot.TryAddPendingItem(item, "INVTYPE_CHEST")
            AreEqual(1, #Loot.GetPendingLoot())
            local added = Loot.GetPendingLoot()[1]
            AreEqual("sess-A",  added.sessionID)
            AreEqual("raid-01", added.raidID)
            AreEqual("H",       added.difficulty)
            MockRestore()
        end)
    end

    -- ========================================================
    -- Trash-Operations
    -- ========================================================

    function Tests:testRemovePendingItem_MovesToTrash()
        WithTestDB(function()
            MockBasics()
            table.insert(Loot.GetPendingLoot(), { link = "|Hitem:1|h|r" })
            Loot.RemovePendingItem("|Hitem:1|h|r")
            AreEqual(0, #Loot.GetPendingLoot())
            AreEqual(1, #Loot.GetTrashedLoot())
            AreEqual("|Hitem:1|h|r", Loot.GetTrashedLoot()[1].link)
            MockRestore()
        end)
    end

    function Tests:testRestoreFromTrash_MovesBack()
        WithTestDB(function()
            MockBasics()
            table.insert(Loot.GetTrashedLoot(), { link = "|Hitem:2|h|r" })
            Loot.RestoreFromTrash("|Hitem:2|h|r")
            AreEqual(0, #Loot.GetTrashedLoot())
            AreEqual(1, #Loot.GetPendingLoot())
            MockRestore()
        end)
    end

    function Tests:testDeleteFromTrash_Removes()
        WithTestDB(function()
            MockBasics()
            table.insert(Loot.GetTrashedLoot(), { link = "|Hitem:3|h|r" })
            Loot.DeleteFromTrash("|Hitem:3|h|r")
            AreEqual(0, #Loot.GetTrashedLoot())
            AreEqual(0, #Loot.GetPendingLoot())
            MockRestore()
        end)
    end

    function Tests:testTrashActiveItem_ClearsCurrent()
        WithTestDB(function()
            MockBasics()
            -- ClearCurrentItem aus Loot_Assign mocken (keine Roll-State-Mutationen)
            Mock(Loot, "ClearCurrentItem", function()
                Loot.GetCurrentItem().link = nil
            end)
            local ci = Loot.GetCurrentItem()
            ci.link = "|Hitem:5|h|r"
            table.insert(Loot.GetPendingLoot(), { link = "|Hitem:5|h|r" })
            Loot.TrashActiveItem()
            AreEqual(nil, ci.link)
            AreEqual(0,   #Loot.GetPendingLoot())
            AreEqual(1,   #Loot.GetTrashedLoot())
            MockRestore()
        end)
    end

    -- ========================================================
    -- Reset / Cancel
    -- ========================================================

    function Tests:testResetCurrentItem_ClearsLink()
        WithTestDB(function()
            MockBasics()
            Mock(Loot, "ClearCurrentItem", function() Loot.GetCurrentItem().link = nil end)
            Loot.GetCurrentItem().link = "|Hitem:6|h|r"
            Loot.ResetCurrentItem()
            AreEqual(nil, Loot.GetCurrentItem().link)
            MockRestore()
        end)
    end

    function Tests:testCancelPrio_OnlyWhenPrioActive()
        WithTestDB(function()
            MockBasics()
            Mock(Loot, "ClearCurrentItem", function() Loot.GetCurrentItem().link = nil end)
            local ci = Loot.GetCurrentItem()
            ci.link = "|Hitem:7|h|r"
            ci.prioState = { active = false }
            -- prioState.active = false → CancelPrio macht nichts
            Loot.CancelPrio()
            AreEqual("|Hitem:7|h|r", ci.link)
            -- prioState.active = true → CancelPrio läuft durch
            ci.prioState.active = true
            Loot.CancelPrio()
            AreEqual(nil, ci.link)
            MockRestore()
        end)
    end
end)
