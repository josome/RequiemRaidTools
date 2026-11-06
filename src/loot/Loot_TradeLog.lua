-- RequiemRaidTools – Loot_TradeLog.lua
-- Trade-Zustand je Zuteilung: wer bekommt das Item per Auto-Trade, und was ist passiert.
--
-- Der Zustand hängt direkt am gespeicherten Eintrag (entry.trade), die Auto-Trade-Queue
-- ist nur eine daraus abgeleitete Sicht. Früher lebte die Queue getrennt und flüchtig in
-- Loot._pendingTrades — sie ging bei /reload verloren und folgte keinem nachträglichen
-- Reassign im Log-Tab. Beides kann hier nicht mehr auseinanderlaufen.
--
-- Datenquellen (alle über ForEachTradeEntry):
--   session.lootLog[i]      — normale Zuteilungen (mit entry.trade seit dieser Version)
--   session.manualTrades[i] — von Hand vorbereitete Trades (Item aus der Tasche)
--   TradeLog._orphans       — Zuteilungen ohne aktive Raid Session (nur Laufzeit)
--
-- entry.trade = {
--   status    = "queued"|"staged"|"traded"|"aborted"|"notFound"|"bound"|"self"|"expired"|"removed",
--   recipient = nil | "Name-Realm",  -- Umleitung nur für den Auto-Trade; nil = entry.player
--   attempts  = 0,                   -- geöffnete Handelsfenster mit diesem Item
--   updated   = <unix>,              -- letzte Statusänderung
--   since     = nil | <unix>,        -- Start des 2h-Fensters nach manuellem Requeue
-- }

local GL = GuildLoot
GL.TradeLog = GL.TradeLog or {}
local TradeLog = GL.TradeLog

-- Handelsfenster für frisch gelootete BoP-Items (WoW: 2 Stunden)
TradeLog.TRADE_WINDOW = 2 * 3600
-- Handelsslots pro Fenster (WoW: 6, der siebte ist "wird nicht gehandelt")
TradeLog.MAX_SLOTS = 6

-- Status, bei denen der Auto-Trade das Item beim nächsten Handel anbietet
local OPEN = { queued = true, aborted = true, staged = true, bound = true }

-- Zuteilungen ohne aktive Raid Session: nicht persistent, aber im Auto-Trade dabei
TradeLog._orphans = {}

local function Trace(kind, fmt, ...)
    if GL.TradeTrace then GL.TradeTrace.Add(kind, fmt, ...) end
end

local function LinkOf(entry)
    return entry.link or entry.item or "?"
end

-- ============================================================
-- Grundfunktionen
-- ============================================================

--- Empfänger für den Auto-Trade: manuelle Umleitung, sonst der zugeteilte Spieler.
function TradeLog.Recipient(entry)
    if not entry then return nil end
    return (entry.trade and entry.trade.recipient) or entry.player
end

--- itemID aus dem Eintrag, Fallback aus dem Link.
function TradeLog.ItemID(entry)
    if entry.itemID then return entry.itemID end
    return tonumber(tostring(LinkOf(entry)):match("item:(%d+)"))
end

--- Setzt den Status. Legt entry.trade bei Bedarf an. Nil-sicher.
function TradeLog.SetStatus(entry, status, now)
    if not entry then return end
    entry.trade = entry.trade or { attempts = 0 }
    entry.trade.status  = status
    entry.trade.updated = now or time()
end

--- Ist der Name der eigene Charakter? Mit sich selbst kann man nicht handeln.
function TradeLog.IsSelf(fullName)
    if not fullName or fullName == "" then return false end
    return GL.ShortName(fullName) == GL.ShortName(UnitName("player") or "")
end

--- Bietet der Auto-Trade dieses Item beim nächsten Handel an?
--- Manuelle Einträge laufen nie ab — der Spieler hat sie bewusst vorbereitet.
function TradeLog.IsOpen(entry, now)
    local t = entry and entry.trade
    if not (t and OPEN[t.status]) then return false end
    if entry.manual then return true end
    return (now - (t.since or entry.timestamp or 0)) <= TradeLog.TRADE_WINDOW
end

--- Verbleibende Sekunden im 2h-Fenster (nil bei manuellen Einträgen).
function TradeLog.Remaining(entry, now)
    if entry.manual then return nil end
    local start = (entry.trade and entry.trade.since) or entry.timestamp or 0
    return math.max(0, TradeLog.TRADE_WINDOW - (now - start))
end

--- Ruft fn(entry, session, list, index) für jeden Eintrag mit Trade-Bezug auf.
--- lootLog-Einträge ohne entry.trade (Altdaten) werden übersprungen.
local function ForEachTradeEntry(fn)
    for _, s in ipairs(GuildLootDB.raidContainers or {}) do
        for i, e in ipairs(s.lootLog or {}) do
            if e.trade then fn(e, s, s.lootLog, i) end
        end
        for i, e in ipairs(s.manualTrades or {}) do fn(e, s, s.manualTrades, i) end
    end
    for i, e in ipairs(TradeLog._orphans) do fn(e, nil, TradeLog._orphans, i) end
end

--- Aktive Raid Session oder nil.
local function ActiveSession()
    local db = GuildLootDB
    local idx = db.activeContainerIdx
    return idx and db.raidContainers and db.raidContainers[idx] or nil
end

--- Benachrichtigt das Debug-Fenster, falls es offen ist.
function TradeLog.NotifyChanged()
    if GL.UI and GL.UI.RefreshTradeDebug then GL.UI.RefreshTradeDebug() end
end

-- ============================================================
-- Zuteilung
-- ============================================================

--- Wird bei jeder Zuteilung durch den ML aufgerufen.
--- Eigenes Item → "self" (sonst hinge es ewig in der Queue), sonst "queued".
function TradeLog.Track(entry)
    if not entry then return end
    local who = TradeLog.Recipient(entry)
    if TradeLog.IsSelf(who) then
        TradeLog.SetStatus(entry, "self")
        Trace("assign", "%s → %s: own item, no auto-trade", LinkOf(entry), tostring(who))
    else
        TradeLog.SetStatus(entry, "queued")
        Trace("assign", "%s → %s: queued", LinkOf(entry), tostring(who))
    end
    TradeLog.NotifyChanged()
end

--- Zuteilung ohne aktive Raid Session: Eintrag nur zur Laufzeit führen.
function TradeLog.AddOrphan(entry)
    table.insert(TradeLog._orphans, entry)
    Trace("assign", "%s: no active Raid Session — auto-trade only until /reload", LinkOf(entry))
end

-- ============================================================
-- Queue (abgeleitete Sicht)
-- ============================================================

--- Offene Einträge, deren 2h-Fenster abgelaufen ist, auf "expired" setzen.
--- @return number  Anzahl neu abgelaufener Einträge
function TradeLog.ExpireStale(now)
    local n = 0
    ForEachTradeEntry(function(e)
        local t = e.trade
        if t and OPEN[t.status] and not TradeLog.IsOpen(e, now) then
            TradeLog.SetStatus(e, "expired", now)
            Trace("expire", "%s → %s: 2h trade window expired", LinkOf(e), tostring(TradeLog.Recipient(e)))
            n = n + 1
        end
    end)
    return n
end

--- Alle offenen Einträge, älteste zuerst (deren Handelsfenster läuft zuerst ab).
function TradeLog.BuildQueue(now)
    local out = {}
    ForEachTradeEntry(function(e)
        if TradeLog.IsOpen(e, now) then out[#out + 1] = e end
    end)
    table.sort(out, function(a, b) return (a.timestamp or 0) < (b.timestamp or 0) end)
    return out
end

--- Offene Einträge für einen Handelspartner (Kurzname), höchstens MAX_SLOTS.
function TradeLog.EntriesFor(shortName, now)
    local out = {}
    for _, e in ipairs(TradeLog.BuildQueue(now)) do
        if #out >= TradeLog.MAX_SLOTS then break end
        if GL.ShortName(TradeLog.Recipient(e) or "") == shortName then out[#out + 1] = e end
    end
    return out
end

--- Hält Loot._pendingTrades als Laufzeit-Spiegel aktuell: alle offenen Einträge,
--- die nicht gerade im Handelsfenster liegen. Form wie bisher plus entry-Referenz.
function TradeLog.SyncMirror(now)
    local staged = {}
    for _, pt in ipairs(GL.Loot._inTradeItems or {}) do
        if pt.entry then staged[pt.entry] = true end
    end
    local mirror = {}
    for _, e in ipairs(TradeLog.BuildQueue(now)) do
        if not staged[e] then
            mirror[#mirror + 1] = {
                itemID    = TradeLog.ItemID(e),
                shortName = GL.ShortName(TradeLog.Recipient(e) or ""),
                entry     = e,
            }
        end
    end
    GL.Loot._pendingTrades = mirror
end

--- Login/Reload: Abgelaufenes markieren, Spiegel aufbauen, Ergebnis protokollieren.
function TradeLog.OnLogin(now)
    TradeLog.ExpireStale(now)
    TradeLog.SyncMirror(now)
    Trace("login", "Queue after login/reload: %d open", #GL.Loot._pendingTrades)
end

--- Zahlen für die Kopfzeile des Debug-Fensters.
--- @return number waiting, number staged
function TradeLog.QueueSummary(now)
    local waiting, staged = 0, 0
    for _, e in ipairs(TradeLog.BuildQueue(now)) do
        if e.trade.status == "staged" then staged = staged + 1 else waiting = waiting + 1 end
    end
    return waiting, staged
end

--- Zeilen für das Debug-Fenster: alle Zuteilungen der Session plus manuelle Trades,
--- neueste zuerst. Altdaten ohne entry.trade erscheinen mit status = nil ("—").
--- @param session table|nil  nil = aktive Raid Session
function TradeLog.Rows(session, now)
    session = session or ActiveSession()
    local rows = {}
    local function add(e)
        local t = e.trade
        rows[#rows + 1] = {
            entry      = e,
            ts         = e.timestamp or 0,
            link       = LinkOf(e),
            assigned   = e.player,
            recipient  = TradeLog.Recipient(e),
            redirected = (t and t.recipient) ~= nil,
            status     = t and t.status or nil,
            attempts   = t and t.attempts or 0,
            remaining  = TradeLog.IsOpen(e, now) and TradeLog.Remaining(e, now) or nil,
            manual     = e.manual == true,
            open       = TradeLog.IsOpen(e, now),
        }
    end
    if session then
        for _, e in ipairs(session.lootLog or {}) do add(e) end
        for _, e in ipairs(session.manualTrades or {}) do add(e) end
    end
    if session == nil or session == ActiveSession() then
        for _, e in ipairs(TradeLog._orphans) do add(e) end
    end
    table.sort(rows, function(a, b) return a.ts > b.ts end)
    return rows
end

-- ============================================================
-- Manuelle Eingriffe (Debug-Fenster, Log-Tab)
-- ============================================================

--- Auto-Trade an einen anderen Spieler umleiten. Die Zuteilung (entry.player,
--- Historie, Prio-Zähler) bleibt unverändert. Leitet man auf den zugeteilten Spieler
--- zurück, entfällt die Umleitung.
function TradeLog.Redirect(entry, fullName, now)
    if not (entry and fullName) then return end
    now = now or time()
    entry.trade = entry.trade or { attempts = 0 }
    local before = TradeLog.Recipient(entry)
    entry.trade.recipient = (fullName ~= entry.player) and fullName or nil
    if TradeLog.IsSelf(fullName) then
        TradeLog.SetStatus(entry, "self", now)
    elseif not OPEN[entry.trade.status] then
        TradeLog.SetStatus(entry, "queued", now)
        entry.trade.since = now
    end
    Trace("manual", "%s: auto-trade redirected %s → %s", LinkOf(entry), tostring(before), fullName)
    TradeLog.NotifyChanged()
end

--- Als erledigt markieren (z.B. nach einem Handel von Hand).
function TradeLog.MarkDone(entry, now)
    if not entry then return end
    TradeLog.SetStatus(entry, "traded", now)
    entry.trade.manualDone = true
    Trace("manual", "%s → %s: marked as done by hand", LinkOf(entry), tostring(TradeLog.Recipient(entry)))
    TradeLog.NotifyChanged()
end

--- Wieder in die Queue nehmen. Startet das 2h-Fenster neu, sonst liefe ein schon
--- abgelaufener Eintrag sofort wieder ab.
function TradeLog.Requeue(entry, now)
    if not entry then return end
    now = now or time()
    -- Mit sich selbst kann man nicht handeln — nie in die Queue
    if TradeLog.IsSelf(TradeLog.Recipient(entry)) then
        TradeLog.SetStatus(entry, "self", now)
        Trace("manual", "%s: own item, not queued", LinkOf(entry))
        TradeLog.NotifyChanged()
        return
    end
    TradeLog.SetStatus(entry, "queued", now)
    entry.trade.since = now
    entry.trade.manualDone = nil
    Trace("manual", "%s → %s: requeued by hand", LinkOf(entry), tostring(TradeLog.Recipient(entry)))
    TradeLog.NotifyChanged()
end

--- Aus dem Auto-Trade nehmen. Manuelle Einträge werden gelöscht, Zuteilungen
--- bleiben im lootLog und bekommen den Status "removed".
function TradeLog.Remove(entry, now)
    if not entry then return end
    if entry.manual or not entry.trade or entry._orphan then
        local removed = false
        ForEachTradeEntry(function(e, _, list, i)
            if not removed and e == entry and (entry.manual or entry._orphan) then
                table.remove(list, i)
                removed = true
            end
        end)
        if removed then
            Trace("manual", "%s → %s: manual entry deleted", LinkOf(entry), tostring(TradeLog.Recipient(entry)))
            TradeLog.NotifyChanged()
            return
        end
    end
    TradeLog.SetStatus(entry, "removed", now)
    Trace("manual", "%s → %s: removed from auto-trade", LinkOf(entry), tostring(TradeLog.Recipient(entry)))
    TradeLog.NotifyChanged()
end

--- Handel von Hand vorbereiten: Item aus der Tasche einem Spieler zuordnen.
--- Berührt weder lootLog noch Spielerhistorie oder Prio-Zähler.
--- @return table entry
function TradeLog.AddManual(link, fullName, now)
    if not (link and fullName) then return nil end
    now = now or time()
    local entry = {
        link      = link,
        item      = link,
        itemID    = tonumber(link:match("item:(%d+)")),
        player    = fullName,
        timestamp = now,
        manual    = true,
    }
    local session = ActiveSession()
    if session then
        session.manualTrades = session.manualTrades or {}
        table.insert(session.manualTrades, entry)
    else
        entry._orphan = true
        table.insert(TradeLog._orphans, entry)
    end
    TradeLog.SetStatus(entry, TradeLog.IsSelf(fullName) and "self" or "queued", now)
    entry.trade.attempts = 0
    Trace("manual", "%s → %s: prepared by hand%s", link, fullName,
        session and "" or " (no Raid Session — only until /reload)")
    TradeLog.NotifyChanged()
    return entry
end

--- Der Log-Tab hat die Zuteilung selbst umgeschrieben (entry.player). Der Auto-Trade
--- folgt automatisch, weil der Empfänger erst beim Handel aufgelöst wird — hier nur
--- protokollieren und das Fenster aktualisieren.
function TradeLog.OnReassign(entry, oldName, newName)
    if not entry then return end
    local redirected = entry.trade and entry.trade.recipient
    Trace("reassign", "%s: assignment %s → %s%s", LinkOf(entry), tostring(oldName), tostring(newName),
        redirected and (" (auto-trade stays redirected to " .. redirected .. ")") or "")
    TradeLog.NotifyChanged()
end
