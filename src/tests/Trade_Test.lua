-- RequiemRaidTools — src/tests/Trade_Test.lua
-- Integrationstests für Loot_Trade.lua
-- (Auto-Trade: TRADE_SHOW, TRADE_ACCEPT_UPDATE, Systemmeldungen, TRADE_CLOSED)
--
-- VORAUSSETZUNGEN
--   1. WoWUnit-Addon installiert (OptionalDep in der TOC).
--   2. devMode aktiv: /reqrt devmode → /reload
--
-- HINWEIS
--   Die Queue kommt aus GL.TradeLog, also aus Einträgen einer Test-Session
--   (lootLog mit entry.trade). Queue() legt sie an; WithSession stellt die DB danach
--   wieder her.
--   C_Timer.After wird synchron gemockt, damit der 0.1s-Callback beim Staging und die
--   0.5s-Auswertung nach TRADE_CLOSED deterministisch im selben Frame laufen.
--   _tradeAccepted ist modul-lokal; ResetTradeState() ruft OnTradeClosed()
--   auf leerem State auf, um das Flag zuverlässig auf false zu setzen.

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests    = WoWUnit("ReqRT.Trade")
    local GL       = GuildLoot
    local Loot     = GL.Loot
    local TradeLog = GL.TradeLog

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
        Loot._lastPartner   = nil  -- sonst greift der Secret-Value-Rückfall quer über Tests
        TradeLog._orphans   = {}
        Loot.OnTradeClosed()  -- setzt _tradeAccepted = false
    end

    --- Führt fn mit einer frischen aktiven Test-Session aus und stellt die DB danach her.
    local function WithSession(fn)
        local db = GuildLootDB
        local savedContainers, savedIdx, savedTrace = db.raidContainers, db.activeContainerIdx, db.tradeTrace
        local session = { id = "trade-test", lootLog = {}, manualTrades = {} }
        db.raidContainers     = { session }
        db.activeContainerIdx = 1
        db.tradeTrace         = {}
        ResetTradeState()
        -- Erst nach dem Reset leeren: dessen OnTradeClosed() schreibt selbst eine
        -- close-Zeile, die sonst jede Protokollprüfung trivial grün machen würde.
        db.tradeTrace         = {}
        local ok, err = pcall(fn, session)
        MockRestore()
        ResetTradeState()
        db.raidContainers, db.activeContainerIdx, db.tradeTrace = savedContainers, savedIdx, savedTrace
        if not ok then error(err, 0) end
    end

    --- Legt Zuteilungen als offene Auto-Trade-Einträge in der Session an.
    --- @param list table { {itemID, player}, ... }
    --- @return table Einträge in derselben Reihenfolge
    local function Queue(session, list)
        local now, out = time(), {}
        for i, it in ipairs(list) do
            local e = {
                itemID    = it[1],
                link      = "|Hitem:" .. it[1] .. "::|h[Test " .. it[1] .. "]|h",
                player    = it[2],
                timestamp = now - 60 + i,  -- aufsteigend: Reihenfolge bleibt stabil
            }
            TradeLog.SetStatus(e, "queued", now)
            table.insert(session.lootLog, e)
            out[i] = e
        end
        return out
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

    -- Überschreibt C_Container so dass Bag 0 ab Slot 1 die gesuchten Items enthält
    local function MockBagWithItems(...)
        local ids = { ... }
        Mock(_G, "C_Container", {
            GetContainerNumSlots = function(bag) return bag == 0 and 10 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                if bag == 0 and ids[slot] then return { itemID = ids[slot] } end
                return nil
            end,
            PickupContainerItem  = function() end,
        })
    end

    -- Handelsslots: liefert für Slot i den Link des i-ten übergebenen Items
    local function MockTradeSlots(...)
        local ids = { ... }
        Mock(_G, "GetTradePlayerItemLink", function(i)
            return ids[i] and ("|Hitem:" .. ids[i] .. "::|h[x]|h") or nil
        end)
    end

    local function MockPartner(name)
        Mock(_G, "TradeFrameRecipientNameText", { GetText = function() return name end })
        Mock(_G, "UnitName", function() return nil end)
    end

    -- --------------------------------------------------------
    -- Test 1: Primärpfad — Name aus TradeFrameRecipientNameText
    -- TradeFrame liefert "Barbossbär (*)" → Strip → "Barbossbär" → Match
    -- --------------------------------------------------------
    function Tests:testNameFromTradeFrame()
        WithSession(function(session)
            local e = Queue(session, { { 100, "Barbossbär-Malfurion" } })[1]
            MockBasics()
            MockBagWithItems(100)
            MockPartner("Barbossbär (*)")

            Loot.OnTradeShow()

            AreEqual(1,        #Loot._inTradeItems)
            AreEqual(0,        #Loot._pendingTrades)
            AreEqual(100,      Loot._inTradeItems[1].itemID)
            AreEqual("staged", e.trade.status)
            AreEqual(1,        e.trade.attempts)
        end)
    end

    -- --------------------------------------------------------
    -- Test 2: Fallback — UnitName("NPC") wenn TradeFrame nil ist
    -- --------------------------------------------------------
    function Tests:testFallbackToUnitName()
        WithSession(function(session)
            Queue(session, { { 200, "Barbossbär-Malfurion" } })
            MockBasics()
            MockBagWithItems(200)
            Mock(_G, "TradeFrameRecipientNameText", nil)
            Mock(_G, "UnitName", function(unit)
                if unit == "NPC" then return "Barbossbär-Malfurion" end
                return nil
            end)

            Loot.OnTradeShow()

            AreEqual(1,   #Loot._inTradeItems)
            AreEqual(0,   #Loot._pendingTrades)
            AreEqual(200, Loot._inTradeItems[1].itemID)
        end)
    end

    -- --------------------------------------------------------
    -- Test 3: Beide Quellen leer → kein Crash, _inTradeItems leer
    -- --------------------------------------------------------
    function Tests:testBothSourcesEmpty()
        WithSession(function(session)
            local e = Queue(session, { { 300, "Barbossbär" } })[1]
            MockBasics()
            MockPartner("")

            Loot.OnTradeShow()

            AreEqual(0,        #Loot._inTradeItems)
            AreEqual("queued", e.trade.status)  -- Item bleibt in Queue
        end)
    end

    -- --------------------------------------------------------
    -- Test 4: Kein passendes Item für Handelspartner
    -- --------------------------------------------------------
    function Tests:testNoMatchingItem()
        WithSession(function(session)
            Queue(session, { { 400, "Barbossbär" } })
            MockBasics()
            MockPartner("AndererSpieler")

            Loot.OnTradeShow()

            AreEqual(0, #Loot._inTradeItems)
            AreEqual(1, #Loot._pendingTrades)
        end)
    end

    -- --------------------------------------------------------
    -- Test 5: 6-Item-Limit — 7 Items zugewiesen, nur 6 in _inTradeItems
    -- --------------------------------------------------------
    function Tests:testSixItemLimit()
        WithSession(function(session)
            local list = {}
            for i = 1, 7 do list[i] = { 500 + i, "Barbossbär" } end
            Queue(session, list)
            MockBasics()
            MockBagWithItems(501, 502, 503, 504, 505, 506, 507)
            MockPartner("Barbossbär")

            Loot.OnTradeShow()

            AreEqual(6, #Loot._inTradeItems)
            AreEqual(1, #Loot._pendingTrades)
        end)
    end

    -- --------------------------------------------------------
    -- Test 6: Trade erfolgreich → Eintrag "traded", Queue leer
    -- --------------------------------------------------------
    function Tests:testTradeSuccess()
        WithSession(function(session)
            local e = Queue(session, { { 600, "Barbossbär" } })[1]
            MockBasics()
            MockBagWithItems(600)
            MockPartner("Barbossbär")
            MockTradeSlots(600)

            Loot.OnTradeShow()
            Loot.OnTradeAcceptUpdate(1, 1)
            Loot.OnTradeClosed()

            AreEqual("traded", e.trade.status)
            AreEqual(0, #Loot._inTradeItems)
            AreEqual(0, #Loot._pendingTrades)
        end)
    end

    -- --------------------------------------------------------
    -- Test 7: Trade abgebrochen → "aborted", Item zurück in der Queue
    -- --------------------------------------------------------
    function Tests:testTradeCancel()
        WithSession(function(session)
            local e = Queue(session, { { 700, "Barbossbär" } })[1]
            MockBasics()
            MockBagWithItems(700)
            MockPartner("Barbossbär")

            Loot.OnTradeShow()
            -- Kein Accept, keine Abschluss-Meldung → Abbruch
            Loot.OnTradeClosed()

            AreEqual("aborted", e.trade.status)
            AreEqual(0,   #Loot._inTradeItems)
            AreEqual(1,   #Loot._pendingTrades)
            AreEqual(700, Loot._pendingTrades[1].itemID)
        end)
    end

    -- --------------------------------------------------------
    -- Test 8: ClickTradeButton wird für jedes Item genau einmal aufgerufen
    -- --------------------------------------------------------
    function Tests:testClickTradeButtonCalled()
        WithSession(function(session)
            Queue(session, { { 800, "Barbossbär" } })
            MockBasics()
            MockBagWithItems(800)
            MockPartner("Barbossbär")

            local clickCount = 0
            Mock(_G, "ClickTradeButton", function() clickCount = clickCount + 1 end)

            Loot.OnTradeShow()

            AreEqual(1, clickCount)
        end)
    end

    -- --------------------------------------------------------
    -- Test 9: Gebundene Duplikat-Kopie wird übersprungen, handelbare bevorzugt
    -- Slot 1: gleiche itemID, gebunden, kein Trade-Timer → nicht handelbar
    -- Slot 2: gleiche itemID, gebunden, MIT Trade-Timer → handelbar → wird genommen
    -- --------------------------------------------------------
    function Tests:testPicksTradeableCopyOverBoundDuplicate()
        WithSession(function(session)
            local e = Queue(session, { { 900, "Barbossbär" } })[1]
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
            MockPartner("Barbossbär")

            Loot.OnTradeShow()

            AreEqual(0, pickedBag)
            AreEqual(2, pickedSlot)  -- handelbare Kopie, nicht die erste (gebundene)
            AreEqual("staged", e.trade.status)
        end)
    end

    -- --------------------------------------------------------
    -- Test 10: Keine handelbare Kopie → Fallback nimmt erste Fundstelle,
    -- Status "bound" macht den Grund in der Trade-Liste sichtbar
    -- --------------------------------------------------------
    function Tests:testFallbackToFirstMatchWhenNoneTradeable()
        WithSession(function(session)
            local e = Queue(session, { { 950, "Barbossbär" } })[1]
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
            MockPartner("Barbossbär")

            Loot.OnTradeShow()

            AreEqual(1, pickedSlot)  -- einzige Kopie wird trotz „nicht handelbar" genommen
            AreEqual("bound", e.trade.status)
        end)
    end

    -- --------------------------------------------------------
    -- Test 11: Nicht gebundenes Item ist handelbar (ohne Tooltip-Scan)
    -- --------------------------------------------------------
    function Tests:testUnboundItemIsTradeable()
        WithSession(function(session)
            Queue(session, { { 980, "Barbossbär" } })
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
            MockPartner("Barbossbär")

            Loot.OnTradeShow()

            AreEqual(1, pickedSlot)
        end)
    end

    -- --------------------------------------------------------
    -- Test 12 (B3): Erfolg kommt nur über die Systemmeldung "Handel abgeschlossen",
    -- TRADE_ACCEPT_UPDATE(1,1) bleibt aus → trotzdem "traded"
    -- --------------------------------------------------------
    function Tests:testSuccessViaTradeCompleteMessage()
        WithSession(function(session)
            local e = Queue(session, { { 1200, "Barbossbär" } })[1]
            MockBasics()
            MockBagWithItems(1200)
            MockPartner("Barbossbär")
            MockTradeSlots(1200)
            Mock(_G, "ERR_TRADE_COMPLETE", "Trade complete.")

            Loot.OnTradeShow()
            Loot.OnTradeAcceptUpdate(1, 0)          -- nur eigene Seite
            Loot.OnTradeUIMessage("Trade complete.")
            Loot.OnTradeClosed()

            AreEqual("traded", e.trade.status)
            AreEqual(0, #Loot._pendingTrades)
        end)
    end

    -- --------------------------------------------------------
    -- Test 13 (B3): Die Abschluss-Meldung kommt erst NACH der Auswertung →
    -- der als Abbruch gewertete Handel wird nachträglich korrigiert
    -- --------------------------------------------------------
    function Tests:testLateTradeCompleteCorrectsAbort()
        WithSession(function(session)
            local e = Queue(session, { { 1300, "Barbossbär" } })[1]
            MockBasics()
            MockBagWithItems(1300)
            MockPartner("Barbossbär")
            MockTradeSlots(1300)
            Mock(_G, "ERR_TRADE_COMPLETE", "Trade complete.")

            Loot.OnTradeShow()
            Loot.OnTradeAcceptUpdate(1, 0)
            Loot.OnTradeClosed()
            AreEqual("aborted", e.trade.status)

            Loot.OnTradeUIMessage("Trade complete.")

            AreEqual("traded", e.trade.status)
            AreEqual(0, #Loot._pendingTrades)
        end)
    end

    -- --------------------------------------------------------
    -- Test 14 (B4): Handel erfolgreich, aber ein Item lag nie im Handelsfenster
    -- (z.B. gebundene Kopie) → nur das tatsächlich gehandelte wird "traded"
    -- --------------------------------------------------------
    function Tests:testItemMissingFromTradeSlotsStaysOpen()
        WithSession(function(session)
            local list = Queue(session, { { 1401, "Barbossbär" }, { 1402, "Barbossbär" } })
            MockBasics()
            MockBagWithItems(1401, 1402)
            MockPartner("Barbossbär")
            MockTradeSlots(1401)  -- 1402 fehlt im Handelsfenster

            Loot.OnTradeShow()
            Loot.OnTradeAcceptUpdate(1, 1)
            Loot.OnTradeClosed()

            AreEqual("traded", list[1].trade.status)
            AreEqual("queued", list[2].trade.status)
            AreEqual(1,    #Loot._pendingTrades)
            AreEqual(1402, Loot._pendingTrades[1].itemID)
        end)
    end

    -- --------------------------------------------------------
    -- Test 15: TRADE_CLOSED feuert doppelt → genau eine Auswertung
    -- --------------------------------------------------------
    function Tests:testDoubleTradeClosedFinalizesOnce()
        WithSession(function(session)
            Queue(session, { { 1500, "Barbossbär" } })
            MockBasics()
            MockBagWithItems(1500)
            MockPartner("Barbossbär")

            Loot.OnTradeShow()

            local scheduled = {}
            Mock(C_Timer, "After", function(_, fn) scheduled[#scheduled + 1] = fn end)
            Loot.OnTradeClosed()
            Loot.OnTradeClosed()

            AreEqual(1, #scheduled)
            scheduled[1]()  -- Auswertung ausführen, damit der Zustand sauber endet
        end)
    end

    -- --------------------------------------------------------
    -- Test 16: Item nicht im Inventar → "notFound", raus aus dem Staging
    -- --------------------------------------------------------
    function Tests:testItemNotInBagsMarkedNotFound()
        WithSession(function(session)
            local e = Queue(session, { { 1600, "Barbossbär" } })[1]
            MockBasics()  -- leere Taschen
            MockPartner("Barbossbär")

            Loot.OnTradeShow()

            AreEqual("notFound", e.trade.status)
            AreEqual(0, #Loot._inTradeItems)
        end)
    end

    -- --------------------------------------------------------
    -- Test 17: Jeder Schritt landet im Trade-Protokoll
    -- --------------------------------------------------------
    function Tests:testTradeFlowIsTraced()
        WithSession(function(session)
            Queue(session, { { 1700, "Barbossbär" } })
            MockBasics()
            MockBagWithItems(1700)
            MockPartner("Barbossbär")
            MockTradeSlots(1700)

            Loot.OnTradeShow()
            Loot.OnTradeAcceptUpdate(1, 1)
            Loot.OnTradeClosed()

            local kinds = {}
            for _, ev in ipairs(GuildLootDB.tradeTrace) do kinds[ev.kind] = true end
            IsTrue(kinds.show,   "TRADE_SHOW nicht protokolliert")
            IsTrue(kinds.item,   "Item-Platzierung nicht protokolliert")
            IsTrue(kinds.accept, "Accept nicht protokolliert")
            IsTrue(kinds.close,  "Abschluss nicht protokolliert")
        end)
    end

    -- --------------------------------------------------------
    -- Test 18: Ein Fehler beim Auffrischen des Trade-Debug-Fensters darf die
    -- Platzierung nicht verhindern. Das Fenster rendert eine Frame-Zeile pro
    -- Loot-Eintrag der Session, die Liste wächst über den Raidabend — vorher lief
    -- NotifyChanged() vor der Platzierung im selben Callback und riss sie mit.
    -- --------------------------------------------------------
    function Tests:testPlacementRunsWhenRefreshFails()
        WithSession(function(session)
            Queue(session, { { 1800, "Barbossbär" } })
            MockBasics()
            MockBagWithItems(1800)
            MockPartner("Barbossbär")
            Mock(GL.UI, "RefreshTradeDebug", function() error("render exploded") end)

            local clickCount = 0
            Mock(_G, "ClickTradeButton", function() clickCount = clickCount + 1 end)

            Loot.OnTradeShow()

            AreEqual(1, clickCount)

            local kinds = {}
            for _, ev in ipairs(GuildLootDB.tradeTrace) do kinds[ev.kind] = true end
            IsTrue(kinds.ui, "Fehlgeschlagener Refresh nicht protokolliert")
        end)
    end

    -- Ein Wert, der sich wie ein geschützter WoW-Wert verhält: jede String-Operation
    -- darauf wirft. issecretvalue wird passend dazu gemockt.
    local function MockSecretPartner()
        local protected = setmetatable({}, {
            __index    = function() error("secret value touched") end,
            __concat   = function() error("secret value touched") end,
            __tostring = function() error("secret value touched") end,
        })
        Mock(_G, "TradeFrameRecipientNameText", { GetText = function() return protected end })
        Mock(_G, "UnitName",       function() return nil end)
        Mock(_G, "issecretvalue",  function(v) return v == protected end)
        return protected
    end

    -- --------------------------------------------------------
    -- Test 19: Ein geschützter Partnername darf den Callback nicht sprengen.
    -- Vorher lief strtrim/gsub direkt auf GetText() — der Lua-Fehler beendete
    -- TRADE_SHOW vor jeder Protokoll- und Chatausgabe (lautloser Totalausfall).
    -- --------------------------------------------------------
    function Tests:testSecretPartnerNameDoesNotThrow()
        WithSession(function(session)
            local e = Queue(session, { { 1900, "Barbossbär" } })[1]
            MockBasics()
            MockSecretPartner()

            Loot.OnTradeShow()   -- darf nicht werfen

            AreEqual(0,        #Loot._inTradeItems)
            AreEqual("queued", e.trade.status)   -- Item bleibt offen

            local kinds = {}
            for _, ev in ipairs(GuildLootDB.tradeTrace) do kinds[ev.kind] = true end
            IsTrue(kinds.show, "Eintritts-Trace fehlt")
            IsTrue(kinds.skip, "Abbruchgrund nicht protokolliert")
        end)
    end

    -- --------------------------------------------------------
    -- Test 20: Ist der Name geschützt, aber ein Partner aus einem früheren
    -- Handelsfenster bekannt, wird darauf ausgewichen (RCLootCouncil-Muster).
    -- --------------------------------------------------------
    function Tests:testSecretPartnerFallsBackToLastPartner()
        WithSession(function(session)
            Queue(session, { { 1910, "Barbossbär" } })
            MockBasics()
            MockBagWithItems(1910)

            -- 1. Durchgang: Name lesbar → merkt sich den Partner
            MockPartner("Barbossbär")
            Loot.OnTradeShow()
            AreEqual("Barbossbär", Loot._lastPartner)
            Loot.OnTradeClosed()

            -- 2. Durchgang: Name geschützt → Rückfall greift, Item wird gestaged
            Queue(session, { { 1911, "Barbossbär" } })
            MockBagWithItems(1911)
            MockSecretPartner()
            Loot.OnTradeShow()

            IsTrue(#Loot._inTradeItems > 0, "Rückfall auf den letzten Partner griff nicht")
        end)
    end

    -- --------------------------------------------------------
    -- Test 21: Der Eintritts-Trace steht VOR allen Guards. Ohne ML bricht der
    -- Auto-Trade ab, die Zeile muss aber trotzdem im Protokoll stehen — nur so ist
    -- "Event kam nicht an" von "Event kam, Guard hat abgelehnt" unterscheidbar.
    -- --------------------------------------------------------
    function Tests:testEntryTraceBeforeGuards()
        WithSession(function(session)
            Queue(session, { { 1920, "Barbossbär" } })
            MockBasics()
            MockPartner("Barbossbär")
            Mock(GL, "IsMasterLooter", function() return false end)

            Loot.OnTradeShow()

            AreEqual(0, #Loot._inTradeItems)
            local found = false
            for _, ev in ipairs(GuildLootDB.tradeTrace) do
                if ev.kind == "show" and ev.text:find("ML=false", 1, true) then found = true end
            end
            IsTrue(found, "Eintritts-Trace mit ML=false fehlt")
        end)
    end

end)
