-- RequiemRaidTools – Loot_Trade.lua
-- Auto-Handel: TRADE_SHOW, TRADE_ACCEPT_UPDATE, TRADE_CLOSED

local GL   = GuildLoot
local Loot = GL.Loot

-- Pending-Accept-Flag (modul-lokal, nur Trade-Funktionen benötigen es)
local _tradeAccepted = false

-- Stabiler Präfix der 2h-BoP-Trade-Tooltip-Zeile (lokalisiert via Globalstring).
-- BIND_TRADE_TIME_REMAINING = "You may trade this item ... for the next %s."
-- Zur Laufzeit gelesen (Globalstring steht beim Laden evtl. noch nicht bereit).
local function TradeTimerPrefix()
    local s = BIND_TRADE_TIME_REMAINING
    if type(s) ~= "string" then return nil end
    local p = s:match("^(.-)%%s")
    if not p or p == "" then return s end
    return p
end

-- Ist die Bag-Position aktuell handelbar?
-- - Nicht gebunden → ja.
-- - Gebunden → nur wenn der Tooltip die 2h-Trade-Zeile zeigt (frisch gelootet).
-- - Erkennung nicht verfügbar (kein C_TooltipInfo/Globalstring) → ja (nicht blockieren).
local function IsBagItemTradeable(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return false end
    if info.isBound == false then return true end
    local prefix = TradeTimerPrefix()
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem and prefix) then
        return true
    end
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    if data and data.lines then
        for _, line in ipairs(data.lines) do
            local txt = line.leftText
            if txt and txt:find(prefix, 1, true) then return true end
        end
    end
    return false
end

-- Sucht eine Bag-Position für itemID und bevorzugt eine handelbare Kopie.
-- Verhindert, dass eine gleiche-itemID-aber-gebundene Kopie (z.B. eigene Beute aus
-- einem früheren Raid) gegriffen wird und ClickTradeButton lautlos scheitert.
-- @return bag, slot, tradeable  (oder nil wenn itemID gar nicht in den Taschen)
local function FindBagSlotForTrade(itemID)
    local firstBag, firstSlot
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                if not firstBag then firstBag, firstSlot = bag, slot end
                if IsBagItemTradeable(bag, slot) then
                    return bag, slot, true
                end
            end
        end
    end
    if firstBag then return firstBag, firstSlot, false end  -- Fallback: erste Kopie
    return nil
end

local function IsDevMode()
    return GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode
end

-- Wird bei TRADE_SHOW aufgerufen: legt alle zugewiesenen Items automatisch in den Handel,
-- wenn der Handelspartner ein bekannter Gewinner ist (bis zu 6 Slots).
-- Fix: Gesamte Logik um 0.1s verzögert (TRADE_SHOW kann vor Frame-Befüllung feuern).
-- Fix: CursorHasItem()-Guard entfernt (WoW ignoriert ClickTradeButton mit leerem Cursor).
-- Fix: strtrim() auf Partner-Namen (Whitespace-Schutz).
-- Fix: Cross-Realm-Suffix "(*)"-Stripping (RCLootCouncil-Pattern).
function Loot.OnTradeShow()
    if not GL.IsMasterLooter() then return end
    if #Loot._pendingTrades == 0 then return end

    C_Timer.After(0.1, function()
        -- Re-Check nach Delay
        if #Loot._pendingTrades == 0 then return end

        -- Handelspartner-Name: primär TradeFrame-Element, Fallback UnitName("NPC")
        -- "NPC" ist in WoW das Unit-ID für den aktuellen Interaktionspartner (Handel, Händler...).
        local partnerName = ""
        local recipientFrame = TradeFrameRecipientNameText
        if recipientFrame then
            local rawText = strtrim(recipientFrame:GetText() or "")
            local cleanText = strtrim(rawText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
            -- Cross-Realm-Suffix entfernen: "Name(*)" oder "Name (Realm)" → "Name"
            cleanText = strtrim(cleanText:gsub("%s*%(.*%)$", ""))
            partnerName = GL.ShortName(cleanText)
        end
        if partnerName == "" then
            partnerName = GL.ShortName(UnitName("NPC") or "")
        end
        if partnerName == "" then
            GL.Print("[ReqRT] Auto-Trade: Handelspartner-Name konnte nicht ermittelt werden.")
            return
        end

        -- Bis zu 6 Zuweisungen für diesen Spieler in Staging verschieben (WoW-Limit: 6 Slots).
        -- Rest bleibt in _pendingTrades für das nächste Handelsfenster.
        Loot._inTradeItems = {}
        _tradeAccepted = false
        for i = #Loot._pendingTrades, 1, -1 do
            if #Loot._inTradeItems >= 6 then break end
            local pt = Loot._pendingTrades[i]
            if pt.shortName == partnerName then
                table.insert(Loot._inTradeItems, pt)
                table.remove(Loot._pendingTrades, i)
            end
        end
        if IsDevMode() then
            GL.Print(("[ReqRT] AutoTrade: partner=%s, staged=%d, queue=%d")
                :format(partnerName, #Loot._inTradeItems, #Loot._pendingTrades))
        end
        if #Loot._inTradeItems == 0 then return end

        -- Nächsten freien Handelsslot finden (Hilfsfunktion)
        local function nextFreeTradeSlot()
            for i = 1, 6 do
                local slotName = GetTradePlayerItemInfo(i)
                if not slotName or slotName == "" then return i end
            end
            return nil
        end

        -- Jedes Item in den Taschen suchen und mit Delay in einen freien Handelsslot legen
        local delay = 0
        for _, pt in ipairs(Loot._inTradeItems) do
            local capturedID    = pt.itemID
            local capturedDelay = delay
            delay = delay + 0.1

            C_Timer.After(capturedDelay, function()
                local tradeSlot = nextFreeTradeSlot()
                if not tradeSlot then return end

                -- Handelbare Kopie bevorzugen (Fallback: erste itemID-Fundstelle)
                local bag, slot, tradeable = FindBagSlotForTrade(capturedID)
                if bag then
                    ClearCursor()
                    C_Container.PickupContainerItem(bag, slot)
                    ClickTradeButton(tradeSlot)
                    if IsDevMode() then
                        GL.Print(("[ReqRT] AutoTrade: item %d → bag %d slot %d (tradeable=%s)")
                            :format(capturedID, bag, slot, tostring(tradeable)))
                    end
                    return
                end
                -- Item nicht im Inventar gefunden (verkauft/gelöscht/bereits getradet)
                for i2, inPt in ipairs(Loot._inTradeItems) do
                    if inPt.itemID == capturedID then
                        table.remove(Loot._inTradeItems, i2)
                        GL.Print("|cffff4444[ReqRT] Item " .. capturedID .. " nicht im Inventar — wurde es verkauft oder gelöscht?|r")
                        break
                    end
                end
            end)
        end
    end)
end

-- Beide Seiten haben den Handel bestätigt → Flag setzen
function Loot.OnTradeAcceptUpdate(playerAccepted, targetAccepted)
    if playerAccepted == 1 and targetAccepted == 1 then
        _tradeAccepted = true
    end
end

-- Handelsfenster geschlossen: Erfolg → Staging leeren; Abbruch → Items zurück in Queue
function Loot.OnTradeClosed()
    if _tradeAccepted then
        Loot._inTradeItems = {}
    else
        for _, pt in ipairs(Loot._inTradeItems) do
            table.insert(Loot._pendingTrades, pt)
        end
        Loot._inTradeItems = {}
    end
    _tradeAccepted = false
end
