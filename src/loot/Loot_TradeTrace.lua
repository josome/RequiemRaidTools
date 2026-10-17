-- RequiemRaidTools – Loot_TradeTrace.lua
-- Ereignisprotokoll für den Auto-Trade: Zuteilung, Handelsfenster, Accept, Abschluss.
--
-- Der Auto-Trade versagt sporadisch, ohne dass sich der Fehler bisher eingrenzen ließ.
-- Deshalb wird jeder Schritt dauerhaft aufgezeichnet (unabhängig vom devMode) und
-- überlebt /reload und Disconnect. Nach einem Vorfall lässt sich der Ablauf im
-- Trade-Debug-Fenster lesen und als Text kopieren.
--
-- Speicher: GuildLootDB.tradeTrace = { { ts, kind, text }, ... } — Ringpuffer.

local GL = GuildLoot
GL.TradeTrace = GL.TradeTrace or {}
local TradeTrace = GL.TradeTrace

-- Obergrenze des Ringpuffers. Ein Raidabend mit 30 Items erzeugt grob 150 Einträge.
TradeTrace.MAX_ENTRIES = 300

--- Liefert die Protokoll-Tabelle, legt sie bei Bedarf an.
local function Store()
    GuildLootDB.tradeTrace = GuildLootDB.tradeTrace or {}
    return GuildLootDB.tradeTrace
end

--- Hängt ein Ereignis an. Ältestes fällt heraus, wenn MAX_ENTRIES erreicht ist.
--- Im devMode zusätzlich als Chatzeile.
--- @param kind string  Kurzes Schlagwort, z.B. "assign", "show", "item", "accept", "close"
--- @param fmt  string  string.format-Muster
function TradeTrace.Add(kind, fmt, ...)
    if not GuildLootDB then return end
    local ok, text = pcall(string.format, fmt, ...)
    if not ok then text = tostring(fmt) end
    local log = Store()
    table.insert(log, { ts = time(), kind = kind, text = text })
    while #log > TradeTrace.MAX_ENTRIES do table.remove(log, 1) end
    if GuildLootDB.settings and GuildLootDB.settings.devMode then
        GL.Print("|cff888888[Trade:" .. kind .. "]|r " .. text)
    end
end

--- Eine Zeile für Anzeige und Export: "17.10. 21:04:33  [show]  text"
function TradeTrace.Format(e)
    return date("%d.%m. %H:%M:%S", e.ts or 0) .. "  [" .. (e.kind or "?") .. "]  " .. (e.text or "")
end

--- Alle Einträge, neueste zuerst.
function TradeTrace.Entries()
    local log, out = Store(), {}
    for i = #log, 1, -1 do out[#out + 1] = log[i] end
    return out
end

--- Gesamtes Protokoll als Text in chronologischer Reihenfolge (zum Kopieren).
function TradeTrace.AsText()
    local lines = {}
    for _, e in ipairs(Store()) do lines[#lines + 1] = TradeTrace.Format(e) end
    return table.concat(lines, "\n")
end

function TradeTrace.Clear()
    if not GuildLootDB then return end
    GuildLootDB.tradeTrace = {}
end
