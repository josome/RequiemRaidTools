-- RequiemRaidTools – Loot_Trade.lua
-- Auto-Handel: TRADE_SHOW, TRADE_ACCEPT_UPDATE, TRADE_CLOSED, Trade-Systemmeldungen
-- Die Queue liefert GL.TradeLog (Loot_TradeLog.lua) aus gespeicherten Einträgen,
-- jeder Schritt wird in GL.TradeTrace (Loot_TradeTrace.lua) protokolliert.

local GL   = GuildLoot
local Loot = GL.Loot

-- Pending-Accept-Flag (modul-lokal, nur Trade-Funktionen benötigen es)
local _tradeAccepted = false

-- Laufzeitzustand eines geöffneten Handelsfensters
local _finalizePending   = false  -- TRADE_CLOSED feuert oft doppelt; Auswertung nur einmal
local _tradeSlotSnapshot = nil    -- { [itemID-String] = Anzahl } der belegten Handelsslots
local _lastClosed        = nil    -- { at, entries, snapshot } nach einem als Abbruch gewerteten Handel
local _tradeOpen         = false  -- Handelsfenster offen? Verzögerte Platzierung prüft das
local _placedBagSlots    = {}     -- { ["bag:slot"] = true } in diesem Fenster schon gegriffen
-- Letzter lesbar aufgelöster Handelspartner (Kurzname). Als Modulfeld wie
-- _inTradeItems/_pendingTrades: der Auto-Trade weicht darauf aus, wenn der Client
-- den Namen schützt, und Tests können ihn zurücksetzen.
Loot._lastPartner = nil

-- Verzögerung zwischen TRADE_CLOSED und Auswertung. Die Systemmeldung
-- "Handel abgeschlossen" (ERR_TRADE_COMPLETE) kommt teils erst NACH TRADE_CLOSED.
local FINALIZE_DELAY = 0.5
-- Kommt ERR_TRADE_COMPLETE noch später, wird ein als Abbruch gewerteter Handel
-- innerhalb dieses Fensters nachträglich korrigiert.
local LATE_COMPLETE_WINDOW = 10

-- Trade-Systemmeldungen, die protokolliert werden (Globalstrings; fehlende werden übersprungen)
local TRADE_MESSAGES = {
    "ERR_TRADE_COMPLETE", "ERR_TRADE_CANCELLED", "ERR_TRADE_BAG_FULL", "ERR_TRADE_TARGET_BAG_FULL",
    "ERR_TRADE_MAX_COUNT_EXCEEDED", "ERR_TRADE_TARGET_MAX_COUNT_EXCEEDED", "ERR_TRADE_TOO_FAR",
    "ERR_TRADE_BOUND_ITEM", "ERR_TRADE_QUEST_ITEM", "ERR_TRADE_TEMP_ENCHANT_BOUND",
    "ERR_TRADE_NOT_ON_TAPLIST", "ERR_TRADE_TARGET_DEAD", "ERR_TRADE_SELF", "ERR_TRADE_WRONG_REALM",
    "ERR_TRADE_GROUND_ITEM", "ERR_TRADE_BLOCKED_S", "ERR_TRADE_REQUEST_FAILED",
}

local function Trace(kind, fmt, ...)
    if GL.TradeTrace then GL.TradeTrace.Add(kind, fmt, ...) end
end

-- UI-Auffrischung, die den Aufrufer nie mitreißt.
-- Das Trade-Debug-Fenster rendert eine Frame-Zeile pro Loot-Eintrag der Session
-- (UI_TradeDebug.RefreshList). Diese Liste wächst über den Raidabend mit jeder
-- Zuteilung — sie darf nicht darüber entscheiden, ob ein Handel zustande kommt.
local function SafeNotify()
    local TradeLog = GL.TradeLog
    if not (TradeLog and TradeLog.NotifyChanged) then return end
    local ok, err = pcall(TradeLog.NotifyChanged)
    if not ok then
        Trace("ui", "trade window refresh failed: %s", tostring(err))
    end
end

-- WoW 11.2+: Blizzard kann UI-Werte als "secret value" schützen. Lesen ist erlaubt,
-- String-Operationen darauf werfen aber einen Lua-Fehler. Fehlt die Globale, kennt
-- der laufende Client das Konzept nicht und es gibt nichts abzufangen.
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Meldet, warum der Auto-Trade nicht greift, und liefert false, damit Aufrufer
-- `return TradeAbort(...)` schreiben können. Vorher brachen alle diese Pfade stumm ab.
-- quiet=true nur protokollieren (für Fälle, die bei jedem Gold-Handel auftreten).
local function TradeAbort(reason, quiet)
    Trace("skip", "%s", reason)
    if not quiet then
        GL.Print("|cffff9900[ReqRT] Auto-Trade skipped: " .. reason .. "|r")
    end
    return false
end

-- Handelsslots pro Fenster. MAX_TRADE_ITEMS zählt den siebten Slot mit
-- ("wird nicht gehandelt"), der für uns nicht nutzbar ist — daher minus eins.
-- Ohne die Globale bleibt der bisherige Festwert aus TradeLog.
local function MaxSlots()
    local blizz = _G.MAX_TRADE_ITEMS
    if type(blizz) == "number" and blizz > 1 then return blizz - 1 end
    return (GL.TradeLog and GL.TradeLog.MAX_SLOTS) or 6
end

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
            -- Gesperrte Plätze überspringen: das Item ist noch in einer laufenden
            -- Bewegung (z.B. gerade in einen Handelsslot gelegt). PickupContainerItem
            -- scheitert dort lautlos, und ClickTradeButton mit leerem Cursor ebenso.
            -- Schon in diesem Fenster platzierte Plätze ebenfalls auslassen, sonst
            -- greift man bei zwei Kopien derselben itemID zweimal dieselbe.
            if info and info.itemID == itemID
               and not info.isLocked
               and not _placedBagSlots[bag .. ":" .. slot] then
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

--- Liest die belegten eigenen Handelsslots. Mehrere Kopien derselben itemID werden gezählt.
--- @return table { [itemID-String] = Anzahl }, string Kurzliste für das Protokoll
local function SnapshotTradeSlots()
    local counts, list = {}, {}
    if not GetTradePlayerItemLink then return counts, "?" end
    for i = 1, MaxSlots() do
        local link = GetTradePlayerItemLink(i)
        local id = link and link:match("item:(%d+)")
        if id then
            counts[id] = (counts[id] or 0) + 1
            list[#list + 1] = i .. ":" .. id
        end
    end
    return counts, (#list > 0) and table.concat(list, " ") or "empty"
end

--- Zerlegt den Anzeigenamen des Handelsfensters zu einem Kurznamen.
--- Komplett in pcall: ein geschützter Wert, den IsSecret nicht erkennt, würde sonst
--- den ganzen TRADE_SHOW-Callback mitnehmen — vor jeder Protokollausgabe.
--- @return string|nil kurzName, string|nil rohtext  (nil,nil wenn nicht lesbar)
local function CleanPartnerText(text)
    local ok, short, raw = pcall(function()
        local r     = strtrim(text)
        local clean = strtrim(r:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        -- Cross-Realm-Suffix entfernen: "Name(*)" oder "Name (Realm)" → "Name"
        clean = strtrim(clean:gsub("%s*%(.*%)$", ""))
        return GL.ShortName(clean), r
    end)
    if not ok then return nil, nil end
    return short or "", raw or ""
end

--- Ermittelt den Handelspartner. Primär TradeFrame-Element, Fallback UnitName("NPC")
--- ("NPC" ist in WoW die Unit-ID des aktuellen Interaktionspartners: Handel, Händler...).
--- Beide Quellen können seit WoW 11.2 geschützte Werte liefern. Dann bleibt der Name
--- leer und secret ist true — der Aufrufer weicht auf den letzten Partner aus.
--- @return string partnerName (Kurzname, "" wenn unbekannt), string raw, string npc, boolean secret
local function ResolvePartnerName()
    local partnerName, rawText, npcName, secret = "", "", "", false

    local recipientFrame = TradeFrameRecipientNameText
    if recipientFrame then
        local ok, text = pcall(function() return recipientFrame:GetText() end)
        if not ok or IsSecret(text) then
            secret = true
        elseif text then
            local short, raw = CleanPartnerText(text)
            if short then
                partnerName, rawText = short, raw
            else
                secret = true
            end
        end
    end

    if partnerName == "" then
        local ok, unitName = pcall(UnitName, "NPC")
        if ok and unitName then
            if IsSecret(unitName) then
                secret = true
            else
                local okShort, short = pcall(GL.ShortName, unitName)
                if okShort then
                    npcName, partnerName = unitName, short or ""
                else
                    secret = true
                end
            end
        end
    end

    return partnerName, rawText, npcName, secret
end

-- Wird bei TRADE_SHOW aufgerufen: legt alle zugewiesenen Items automatisch in den Handel,
-- wenn der Handelspartner ein bekannter Gewinner ist (bis zu 6 Slots).
-- Fix: Gesamte Logik um 0.1s verzögert (TRADE_SHOW kann vor Frame-Befüllung feuern).
-- Fix: CursorHasItem()-Guard entfernt (WoW ignoriert ClickTradeButton mit leerem Cursor).
-- Fix: strtrim() auf Partner-Namen (Whitespace-Schutz).
-- Fix: Cross-Realm-Suffix "(*)"-Stripping (RCLootCouncil-Pattern).
function Loot.OnTradeShow()
    local TradeLog = GL.TradeLog
    local isML     = GL.IsMasterLooter()
    local queueLen = #TradeLog.BuildQueue(time())
    -- Allererste Zeile, vor jedem Guard und vor jeder Namensauflösung: fehlt sie im
    -- Protokoll, ist TRADE_SHOW nie angekommen. Steht sie da, nennt der folgende
    -- Abbruch den Grund. Diese Unterscheidung fehlte bei allen bisherigen Ausfällen.
    Trace("show", "TRADE_SHOW received: ML=%s, queue=%d", tostring(isML), queueLen)
    if not isML then
        return TradeAbort("you are not set as Master Looter (/reqrt ml)")
    end
    -- Leise: trifft jeden gewöhnlichen Handel ohne offene Zuweisung (Gold, Mats).
    if queueLen == 0 then
        return TradeAbort("no open assignments in the queue", true)
    end

    C_Timer.After(0.1, function()
        local now = time()
        TradeLog.ExpireStale(now)
        local queue = TradeLog.BuildQueue(now)
        -- Re-Check nach Delay
        if #queue == 0 then
            return TradeAbort("no open assignments left - did the 2h trade window close?")
        end

        local partnerName, rawText, npcName, secret = ResolvePartnerName()
        local queued = {}
        for _, e in ipairs(queue) do
            queued[#queued + 1] = GL.ShortName(TradeLog.Recipient(e) or "?") .. ":" .. tostring(TradeLog.ItemID(e))
        end
        Trace("show", "Partner=%q (Frame=%q, NPC=%q, secret=%s), Queue=%d [%s]",
            partnerName, rawText, npcName, tostring(secret), #queue, table.concat(queued, " "))

        -- Name vom Client geschützt: auf den letzten bekannten Partner ausweichen,
        -- wie RCLootCouncil es mit lastAttemptedTradeTarget macht.
        if partnerName == "" and secret and Loot._lastPartner then
            partnerName = Loot._lastPartner
            Trace("show", "partner name protected - falling back to %q", partnerName)
            GL.Print("|cffff9900[ReqRT] Auto-Trade: the client protected the partner name - assuming "
                     .. partnerName .. ". Reopen the trade window if that is wrong.|r")
        end
        if partnerName == "" then
            if secret then
                return TradeAbort("the client protected the trade partner name - please reopen the trade window")
            end
            return TradeAbort("could not determine the trade partner's name")
        end
        Loot._lastPartner = partnerName

        -- Bis zu 6 Zuweisungen für diesen Spieler in Staging (WoW-Limit: 6 Slots).
        -- Rest bleibt offen für das nächste Handelsfenster.
        Loot._inTradeItems = {}
        _tradeAccepted     = false
        _tradeSlotSnapshot = nil
        _lastClosed        = nil
        _tradeOpen         = true
        _placedBagSlots    = {}
        for _, e in ipairs(TradeLog.EntriesFor(partnerName, now)) do
            table.insert(Loot._inTradeItems, { itemID = TradeLog.ItemID(e), shortName = partnerName, entry = e })
            TradeLog.SetStatus(e, "staged", now)
            e.trade.attempts = (e.trade.attempts or 0) + 1
        end
        TradeLog.SyncMirror(now)
        Trace("show", "%s: %d item(s) staged, %d remain in queue",
            partnerName, #Loot._inTradeItems, #Loot._pendingTrades)
        if #Loot._inTradeItems == 0 then
            SafeNotify()
            return TradeAbort(("nothing open for %s (%d queued for other players)")
                :format(partnerName, #queue))
        end

        -- Nächsten freien Handelsslot finden (Hilfsfunktion)
        local function nextFreeTradeSlot()
            for i = 1, MaxSlots() do
                local slotName = GetTradePlayerItemInfo(i)
                if not slotName or slotName == "" then return i end
            end
            return nil
        end

        -- Jedes Item in den Taschen suchen und mit Delay in einen freien Handelsslot legen
        local delay = 0
        for _, pt in ipairs(Loot._inTradeItems) do
            local captured      = pt
            local capturedID    = pt.itemID
            local capturedDelay = delay
            delay = delay + 0.1

            C_Timer.After(capturedDelay, function()
                -- Fenster inzwischen zu (Partner hat abgebrochen, zu weit weg):
                -- nicht ins Leere greifen. RCLootCouncil prüft hier dasselbe.
                if not _tradeOpen then
                    Trace("item", "%s: trade window already closed", tostring(capturedID))
                    return
                end

                local tradeSlot = nextFreeTradeSlot()
                if not tradeSlot then
                    return TradeAbort("no free trade slot for item " .. tostring(capturedID))
                end

                -- Handelbare Kopie bevorzugen (Fallback: erste itemID-Fundstelle)
                local bag, slot, tradeable = FindBagSlotForTrade(capturedID)
                if bag then
                    ClearCursor()
                    C_Container.PickupContainerItem(bag, slot)
                    ClickTradeButton(tradeSlot)
                    _placedBagSlots[bag .. ":" .. slot] = true
                    if not tradeable then
                        TradeLog.SetStatus(captured.entry, "bound")
                        -- Kein Trade-Timer am Tooltip: WoW wird den Slot ablehnen.
                        -- Wir versuchen es trotzdem (die Erkennung kann irren), sagen
                        -- es aber, statt den leeren Slot unerklärt zu lassen.
                        GL.Print("|cffff9900[ReqRT] Item " .. tostring(capturedID)
                                 .. " looks no longer tradable — the trade slot may stay empty.|r")
                    end
                    Trace("item", "%s → bag %d/%d → trade slot %d (tradable=%s)",
                        tostring(capturedID), bag, slot, tradeSlot, tostring(tradeable))
                    return
                end
                -- Item nicht im Inventar gefunden (verkauft/gelöscht/bereits getradet)
                for i2, inPt in ipairs(Loot._inTradeItems) do
                    if inPt == captured then
                        table.remove(Loot._inTradeItems, i2)
                        TradeLog.SetStatus(captured.entry, "notFound")
                        Trace("item", "%s: not in inventory", tostring(capturedID))
                        GL.Print("|cffff4444[ReqRT] Item " .. tostring(capturedID) .. " not in inventory — was it sold or destroyed?|r")
                        break
                    end
                end
                SafeNotify()
            end)
        end

        -- Erst auffrischen, nachdem alle Platzierungen eingeplant sind. C_Timer.After
        -- kann nicht fehlschlagen, ein Fehler im Render erreicht die Platzierung also
        -- nicht mehr — vorher hing der Handel am Rendern der ganzen Session.
        SafeNotify()
    end)
end

-- Accept-Status hat sich geändert. Bei jeder Änderung die belegten Handelsslots
-- festhalten: nach dem Abschluss lässt sich so prüfen, was wirklich gehandelt wurde.
function Loot.OnTradeAcceptUpdate(playerAccepted, targetAccepted)
    if #Loot._inTradeItems > 0 then
        local snap, list = SnapshotTradeSlots()
        if next(snap) then _tradeSlotSnapshot = snap end
        Trace("accept", "me=%s partner=%s, slots: %s", tostring(playerAccepted), tostring(targetAccepted), list)
    end
    if playerAccepted == 1 and targetAccepted == 1 then
        _tradeAccepted = true
    end
end

--- Ordnet eine Systemmeldung einem Trade-Globalstring zu.
--- pcall: Meldungstexte können in neueren Clients geschützte Werte sein.
local function MatchTradeMessage(message)
    for _, key in ipairs(TRADE_MESSAGES) do
        local g = _G[key]
        if type(g) == "string" then
            local ok, same = pcall(function() return message == g end)
            if ok and same then return key end
        end
    end
    return nil
end

-- Systemmeldung (UI_INFO_MESSAGE / UI_ERROR_MESSAGE). "Handel abgeschlossen" ist das
-- zweite Erfolgssignal neben TRADE_ACCEPT_UPDATE(1,1), das nicht immer ankommt.
function Loot.OnTradeUIMessage(message)
    local key = MatchTradeMessage(message)
    if not key then return end
    local active = #Loot._inTradeItems > 0
    local late   = _lastClosed ~= nil and (time() - _lastClosed.at) <= LATE_COMPLETE_WINDOW
    if not (active or late) then return end
    Trace("msg", "%s", key)
    if key ~= "ERR_TRADE_COMPLETE" then return end
    if active then
        _tradeAccepted = true
    else
        Loot.ApplyLateComplete()
    end
end

-- Handelsfenster geschlossen: Auswertung leicht verzögert, damit ein spätes
-- ERR_TRADE_COMPLETE noch zählt. Doppelte TRADE_CLOSED-Events werden ignoriert.
function Loot.OnTradeClosed()
    -- Immer zuerst: ab hier darf keine verzögerte Platzierung mehr greifen,
    -- auch wenn die Auswertung schon läuft oder nichts gestaged war.
    _tradeOpen = false
    if _finalizePending then return end
    if #Loot._inTradeItems == 0 then
        -- Protokollieren statt stumm zurück: trennt "Fenster nie gesehen" von
        -- "Fenster gesehen, aber nichts gestaged".
        Trace("close", "TRADE_CLOSED with nothing staged")
        _tradeAccepted     = false
        _tradeSlotSnapshot = nil
        return
    end
    _finalizePending = true
    C_Timer.After(FINALIZE_DELAY, Loot.FinalizeTrade)
end

--- Prüft, ob ein Item im Handelsfenster lag, und verbraucht die Kopie im Snapshot.
--- Ohne Snapshot (nie ein Accept-Update gesehen) → als gehandelt werten, wie bisher:
--- lieber einmal zu wenig anbieten als ein schon gehandeltes Item erneut.
--- @return boolean inSlot, boolean verified
local function ConsumeFromSnapshot(snap, itemID)
    if snap == nil then return true, false end
    local key = tostring(itemID)
    if (snap[key] or 0) > 0 then
        snap[key] = snap[key] - 1
        return true, true
    end
    return false, true
end

-- Wertet den Handel aus: Erfolg → nur tatsächlich gehandelte Items auf "traded",
-- der Rest bleibt offen. Abbruch → alle auf "aborted" (bleiben in der Queue).
function Loot.FinalizeTrade()
    _finalizePending = false
    local TradeLog = GL.TradeLog
    local now  = time()
    local snap = _tradeSlotSnapshot
    local done, back, aborted = {}, {}, {}
    for _, pt in ipairs(Loot._inTradeItems) do
        local id = tostring(pt.itemID)
        if _tradeAccepted then
            local inSlot, verified = ConsumeFromSnapshot(snap, pt.itemID)
            if inSlot then
                TradeLog.SetStatus(pt.entry, "traded", now)
                done[#done + 1] = id .. (verified and "" or "(unverified)")
            else
                -- Lag nicht im Handelsfenster (z.B. gebundene Kopie) → bleibt offen
                local keep = pt.entry and pt.entry.trade and pt.entry.trade.status == "bound"
                TradeLog.SetStatus(pt.entry, keep and "bound" or "queued", now)
                back[#back + 1] = id
            end
        else
            TradeLog.SetStatus(pt.entry, "aborted", now)
            aborted[#aborted + 1] = pt.entry
            back[#back + 1] = id
        end
    end
    Trace("close", "%s: traded [%s], open [%s]",
        _tradeAccepted and "success" or "cancelled", table.concat(done, " "), table.concat(back, " "))

    _lastClosed = (not _tradeAccepted and #aborted > 0)
        and { at = now, entries = aborted, snapshot = snap } or nil
    Loot._inTradeItems = {}
    _tradeAccepted     = false
    _tradeSlotSnapshot = nil
    _placedBagSlots    = {}
    TradeLog.SyncMirror(now)
    TradeLog.NotifyChanged()
end

-- ERR_TRADE_COMPLETE kam erst nach der Auswertung: als Abbruch gewertete Einträge
-- nachträglich auf "traded" setzen (nur was im Handelsfenster lag).
function Loot.ApplyLateComplete()
    local lc = _lastClosed
    _lastClosed = nil
    if not lc then return end
    local TradeLog = GL.TradeLog
    local now = time()
    local fixed = 0
    for _, e in ipairs(lc.entries) do
        if e and e.trade and e.trade.status == "aborted"
           and ConsumeFromSnapshot(lc.snapshot, TradeLog.ItemID(e)) then
            TradeLog.SetStatus(e, "traded", now)
            fixed = fixed + 1
        end
    end
    Trace("close", "late ERR_TRADE_COMPLETE: %d entry/entries set to traded afterwards", fixed)
    TradeLog.SyncMirror(now)
    TradeLog.NotifyChanged()
end
