-- RequiemRaidTools – Loot_Trade.lua
-- Auto-Handel: TRADE_SHOW, TRADE_ACCEPT_UPDATE, TRADE_CLOSED

local GL   = GuildLoot
local Loot = GL.Loot

-- Pending-Accept-Flag (modul-lokal, nur Trade-Funktionen benötigen es)
local _tradeAccepted = false

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

        -- Handelspartner-Name aus dem Trade-Frame lesen
        local recipientFrame = TradeFrameRecipientNameText
        if not recipientFrame then return end
        -- WoW-Farbcodes entfernen + Whitespace trimmen
        local rawText = strtrim(recipientFrame:GetText() or "")
        local cleanText = strtrim(rawText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        -- Cross-Realm-Suffix entfernen: "Name(*)" oder "Name (Realm)" → "Name"
        -- (RCLootCouncil-Pattern: TRADE_SHOW liefert bei Cross-Realm "Name(*)" statt "Name-Realm")
        cleanText = strtrim(cleanText:gsub("%s*%(.*%)$", ""))
        local partnerName = GL.ShortName(cleanText)
        if partnerName == "" then return end

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

                for bag = 0, 4 do
                    for slot = 1, C_Container.GetContainerNumSlots(bag) do
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info and info.itemID == capturedID then
                            ClearCursor()
                            C_Container.PickupContainerItem(bag, slot)
                            ClickTradeButton(tradeSlot)
                            return
                        end
                    end
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
