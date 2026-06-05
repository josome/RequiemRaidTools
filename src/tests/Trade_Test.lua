-- RequiemRaidTools — src/tests/Trade_Test.lua
-- Integrationstests für Loot_Trade.lua
-- (Auto-Trade: TRADE_SHOW, TRADE_ACCEPT_UPDATE, TRADE_CLOSED)
--
-- VORAUSSETZUNGEN
--   1. WoWUnit-Addon installiert (OptionalDep in der TOC).
--   2. devMode aktiv: /reqrt devmode → /reload
--
-- HINWEIS
--   C_Timer.After wird synchron gemockt, damit der 0.1s-Callback
--   deterministisch in demselben Frame ausgeführt wird.
--   _tradeAccepted ist modul-lokal; ResetTradeState() ruft OnTradeClosed()
--   auf leerem State auf, um das Flag zuverlässig auf false zu setzen.

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests = WoWUnit("ReqRT.Trade")
    local GL    = GuildLoot
    local Loot  = GL.Loot

    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue

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

    -- Setzt Trade-State zurück UND stellt sicher dass _tradeAccepted = false ist.
    -- OnTradeClosed() auf leerem _inTradeItems ist ein sicherer Reset des modul-lokalen Flags.
    local function ResetTradeState()
        Loot._inTradeItems  = {}
        Loot._pendingTrades = {}
        Loot.OnTradeClosed()  -- setzt _tradeAccepted = false
    end

    -- Mocks die jeder OnTradeShow-Test benötigt
    local function MockBasics()
        Mock(GL,       "IsMasterLooter",      function() return true end)
        Mock(GL,       "Print",               function() end)
        Mock(C_Timer,  "After",               function(_, fn) fn() end)
        Mock(_G,       "GetTradePlayerItemInfo", function() return nil end)
        Mock(_G,       "ClearCursor",         function() end)
        Mock(_G,       "ClickTradeButton",    function() end)
        -- Standard: leere Bags (kein Item gefunden)
        Mock(_G, "C_Container", {
            GetContainerNumSlots = function() return 0 end,
            GetContainerItemInfo = function() return nil end,
            PickupContainerItem  = function() end,
        })
    end

    -- Überschreibt C_Container so dass Bag 0 Slot 1 das gesuchte Item enthält
    local function MockBagWithItem(itemID)
        Mock(_G, "C_Container", {
            GetContainerNumSlots = function(bag) return bag == 0 and 5 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                if bag == 0 and slot == 1 then return { itemID = itemID } end
                return nil
            end,
            PickupContainerItem  = function() end,
        })
    end

    -- --------------------------------------------------------
    -- Test 1: Primärpfad — Name aus TradeFrameRecipientNameText
    -- TradeFrame liefert "Barbossbär (*)" → Strip → "Barbossbär" → Match
    -- --------------------------------------------------------
    function Tests:testNameFromTradeFrame()
        ResetTradeState()
        Loot._pendingTrades = { { itemID = 100, shortName = "Barbossbär" } }

        MockBasics()
        MockBagWithItem(100)
        Mock(_G, "TradeFrameRecipientNameText", { GetText = function() return "Barbossbär (*)" end })
        Mock(_G, "UnitName", function() return nil end)

        Loot.OnTradeShow()

        AreEqual(1,   #Loot._inTradeItems)
        AreEqual(0,   #Loot._pendingTrades)
        AreEqual(100, Loot._inTradeItems[1].itemID)

        MockRestore()
        ResetTradeState()
    end

    -- --------------------------------------------------------
    -- Test 2: Fallback — UnitName("NPC") wenn TradeFrame nil ist
    -- --------------------------------------------------------
    function Tests:testFallbackToUnitName()
        ResetTradeState()
        Loot._pendingTrades = { { itemID = 200, shortName = "Barbossbär" } }

        MockBasics()
        MockBagWithItem(200)
        Mock(_G, "TradeFrameRecipientNameText", nil)
        Mock(_G, "UnitName", function(unit)
            if unit == "NPC" then return "Barbossbär-Malfurion" end
            return nil
        end)

        Loot.OnTradeShow()

        AreEqual(1,   #Loot._inTradeItems)
        AreEqual(0,   #Loot._pendingTrades)
        AreEqual(200, Loot._inTradeItems[1].itemID)

        MockRestore()
        ResetTradeState()
    end

    -- --------------------------------------------------------
    -- Test 3: Beide Quellen leer → kein Crash, _inTradeItems leer
    -- --------------------------------------------------------
    function Tests:testBothSourcesEmpty()
        ResetTradeState()
        Loot._pendingTrades = { { itemID = 300, shortName = "Barbossbär" } }

        MockBasics()
        Mock(_G, "TradeFrameRecipientNameText", { GetText = function() return "" end })
        Mock(_G, "UnitName", function() return nil end)

        Loot.OnTradeShow()

        AreEqual(0, #Loot._inTradeItems)
        AreEqual(1, #Loot._pendingTrades)  -- Item bleibt in Queue

        MockRestore()
        ResetTradeState()
    end

    -- --------------------------------------------------------
    -- Test 4: Kein passendes Item für Handelspartner
    -- --------------------------------------------------------
    function Tests:testNoMatchingItem()
        ResetTradeState()
        Loot._pendingTrades = { { itemID = 400, shortName = "Barbossbär" } }

        MockBasics()
        Mock(_G, "TradeFrameRecipientNameText", { GetText = function() return "AndererSpieler" end })
        Mock(_G, "UnitName", function() return nil end)

        Loot.OnTradeShow()

        AreEqual(0, #Loot._inTradeItems)
        AreEqual(1, #Loot._pendingTrades)

        MockRestore()
        ResetTradeState()
    end

    -- --------------------------------------------------------
    -- Test 5: 6-Item-Limit — 7 Items zugewiesen, nur 6 in _inTradeItems
    -- --------------------------------------------------------
    function Tests:testSixItemLimit()
        ResetTradeState()
        for i = 1, 7 do
            table.insert(Loot._pendingTrades, { itemID = 500 + i, shortName = "Barbossbär" })
        end

        MockBasics()
        Mock(_G, "C_Container", {
            GetContainerNumSlots = function(bag) return bag == 0 and 10 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                -- Items 501-507 liegen in Bag 0 Slots 1-7
                if bag == 0 and slot >= 1 and slot <= 7 then
                    return { itemID = 500 + slot }
                end
                return nil
            end,
            PickupContainerItem  = function() end,
        })
        Mock(_G, "TradeFrameRecipientNameText", { GetText = function() return "Barbossbär" end })
        Mock(_G, "UnitName", function() return nil end)

        Loot.OnTradeShow()

        AreEqual(6, #Loot._inTradeItems)
        AreEqual(1, #Loot._pendingTrades)

        MockRestore()
        ResetTradeState()
    end

    -- --------------------------------------------------------
    -- Test 6: Trade erfolgreich → _inTradeItems geleert
    -- --------------------------------------------------------
    function Tests:testTradeSuccess()
        ResetTradeState()
        Loot._inTradeItems = { { itemID = 600, shortName = "Barbossbär" } }

        Loot.OnTradeAcceptUpdate(1, 1)
        Loot.OnTradeClosed()

        AreEqual(0, #Loot._inTradeItems)
        AreEqual(0, #Loot._pendingTrades)
    end

    -- --------------------------------------------------------
    -- Test 7: Trade abgebrochen → Items zurück in _pendingTrades
    -- --------------------------------------------------------
    function Tests:testTradeCancel()
        ResetTradeState()
        Loot._inTradeItems = { { itemID = 700, shortName = "Barbossbär" } }

        -- Kein OnTradeAcceptUpdate → _tradeAccepted = false → Items zurück
        Loot.OnTradeClosed()

        AreEqual(0,   #Loot._inTradeItems)
        AreEqual(1,   #Loot._pendingTrades)
        AreEqual(700, Loot._pendingTrades[1].itemID)
    end

    -- --------------------------------------------------------
    -- Test 8: ClickTradeButton wird für jedes Item genau einmal aufgerufen
    -- --------------------------------------------------------
    function Tests:testClickTradeButtonCalled()
        ResetTradeState()
        Loot._pendingTrades = { { itemID = 800, shortName = "Barbossbär" } }

        MockBasics()
        MockBagWithItem(800)
        Mock(_G, "TradeFrameRecipientNameText", { GetText = function() return "Barbossbär" end })
        Mock(_G, "UnitName", function() return nil end)

        local clickCount = 0
        Mock(_G, "ClickTradeButton", function() clickCount = clickCount + 1 end)

        Loot.OnTradeShow()

        AreEqual(1, clickCount)

        MockRestore()
        ResetTradeState()
    end

    -- --------------------------------------------------------
    -- Test 9: Gebundene Duplikat-Kopie wird übersprungen, handelbare bevorzugt
    -- Slot 1: gleiche itemID, gebunden, kein Trade-Timer → nicht handelbar
    -- Slot 2: gleiche itemID, gebunden, MIT Trade-Timer → handelbar → wird genommen
    -- --------------------------------------------------------
    function Tests:testPicksTradeableCopyOverBoundDuplicate()
        ResetTradeState()
        Loot._pendingTrades = { { itemID = 900, shortName = "Barbossbär" } }

        MockBasics()
        local pickedBag, pickedSlot
        Mock(_G, "C_Container", {
            GetContainerNumSlots = function(bag) return bag == 0 and 5 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                if bag == 0 and (slot == 1 or slot == 2) then
                    return { itemID = 900, isBound = true }
                end
                return nil
            end,
            PickupContainerItem = function(bag, slot) pickedBag, pickedSlot = bag, slot end,
        })
        -- Nur Slot 2 zeigt die 2h-Trade-Zeile
        Mock(_G, "BIND_TRADE_TIME_REMAINING", "You may trade this item for the next %s.")
        Mock(_G, "C_TooltipInfo", {
            GetBagItem = function(bag, slot)
                if bag == 0 and slot == 2 then
                    return { lines = { { leftText = "You may trade this item for the next 1 hour." } } }
                end
                return { lines = { { leftText = "Soulbound" } } }
            end,
        })
        Mock(_G, "TradeFrameRecipientNameText", { GetText = function() return "Barbossbär" end })
        Mock(_G, "UnitName", function() return nil end)

        Loot.OnTradeShow()

        AreEqual(0, pickedBag)
        AreEqual(2, pickedSlot)  -- handelbare Kopie, nicht die erste (gebundene)

        MockRestore()
        ResetTradeState()
    end

    -- --------------------------------------------------------
    -- Test 10: Keine handelbare Kopie → Fallback nimmt erste Fundstelle
    -- (altes Verhalten, kein Regress)
    -- --------------------------------------------------------
    function Tests:testFallbackToFirstMatchWhenNoneTradeable()
        ResetTradeState()
        Loot._pendingTrades = { { itemID = 950, shortName = "Barbossbär" } }

        MockBasics()
        local pickedSlot
        Mock(_G, "C_Container", {
            GetContainerNumSlots = function(bag) return bag == 0 and 3 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                if bag == 0 and slot == 1 then return { itemID = 950, isBound = true } end
                return nil
            end,
            PickupContainerItem = function(_, slot) pickedSlot = slot end,
        })
        Mock(_G, "BIND_TRADE_TIME_REMAINING", "You may trade this item for the next %s.")
        Mock(_G, "C_TooltipInfo", {
            GetBagItem = function() return { lines = { { leftText = "Soulbound" } } } end,
        })
        Mock(_G, "TradeFrameRecipientNameText", { GetText = function() return "Barbossbär" end })
        Mock(_G, "UnitName", function() return nil end)

        Loot.OnTradeShow()

        AreEqual(1, pickedSlot)  -- einzige Kopie wird trotz „nicht handelbar" genommen

        MockRestore()
        ResetTradeState()
    end

    -- --------------------------------------------------------
    -- Test 11: Nicht gebundenes Item ist handelbar (ohne Tooltip-Scan)
    -- --------------------------------------------------------
    function Tests:testUnboundItemIsTradeable()
        ResetTradeState()
        Loot._pendingTrades = { { itemID = 980, shortName = "Barbossbär" } }

        MockBasics()
        local pickedSlot
        Mock(_G, "C_Container", {
            GetContainerNumSlots = function(bag) return bag == 0 and 3 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                if bag == 0 and slot == 1 then return { itemID = 980, isBound = false } end
                return nil
            end,
            PickupContainerItem = function(_, slot) pickedSlot = slot end,
        })
        Mock(_G, "TradeFrameRecipientNameText", { GetText = function() return "Barbossbär" end })
        Mock(_G, "UnitName", function() return nil end)

        Loot.OnTradeShow()

        AreEqual(1, pickedSlot)

        MockRestore()
        ResetTradeState()
    end

end)
