-- RaidLootTracker – Comm.lua
-- Addon-Kommunikation: ML → Observer-Sync via unsichtbarem Addon-Kanal

GuildLoot = GuildLoot or {}
local GL = GuildLoot

GL.Comm = GL.Comm or {}
local Comm = GL.Comm

local PREFIX = "RequiemRLT"
local SEP    = "\t"   -- Tab als Trennzeichen (sicher in Addon-Nachrichten)

-- Protokoll-Versionierung: die Minor-Version (0.X.y.z) ist die Protokoll-Version.
-- MIN_PROTO_MINOR NUR erhöhen wenn das Nachrichtenformat inkompatibel geändert wird.
local ADDON_VERSION   = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("RequiemRaidTools", "Version"))
                     or (GetAddOnMetadata and GetAddOnMetadata("RequiemRaidTools", "Version"))
                     or "0.5"  -- Fallback mit gültiger Minor-Version
local MIN_PROTO_MINOR = 5  -- älteste kompatible Minor-Version
local VERSION_WARN_COOLDOWN = 60  -- Sekunden zwischen Warnungen pro Sender
local versionWarnedAt = {}  -- sender -> GetTime() der letzten Warnung

local function MinorVersion(v)
    local minor = v:match("^%d+%.(%d+)")
    return tonumber(minor) or 0
end

-- Prefix beim Laden registrieren
if C_ChatInfo then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

-- ============================================================
-- Intern: Senden an Gruppe
-- ============================================================

Comm._isInRaid  = function() return IsInRaid()  end
Comm._isInGroup = function() return IsInGroup() end

local function SendToGroup(msg)
    if not C_ChatInfo then return end
    local versioned = ADDON_VERSION .. SEP .. msg
    if Comm._isInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, versioned, "RAID")
    elseif Comm._isInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, versioned, "PARTY")
    end
end

-- ============================================================
-- Send-Funktionen (nur ML ruft diese auf)
-- ============================================================

--- ML hat ein Item freigegeben
function Comm.SendItemActivate(link, category)
    SendToGroup("ITEM_ON" .. SEP .. (link or "") .. SEP .. (category or "other"))
end

--- ML hat das aktive Item abgebrochen/zurückgesetzt
function Comm.SendItemClear()
    SendToGroup("ITEM_OFF")
end

--- ML hat die Roll-Phase gestartet
--- @param seconds  number  Dauer der Roll-Phase
--- @param players  table   Liste der Kurznames der berechtigten Würfler
function Comm.SendRollStart(seconds, players)
    local list = table.concat(players or {}, ",")
    SendToGroup("ROLL_START" .. SEP .. tostring(seconds) .. SEP .. list)
end

--- ML hat Loot einem Spieler zugewiesen (inkl. sessionID + raidID für Observer-Sync)
function Comm.SendAssign(playerName, difficulty, itemLink, category, quality, winnerPrio, boss, sessionID, raidID)
    SendToGroup("ASSIGN" .. SEP .. (playerName or "") .. SEP
                         .. (difficulty or "") .. SEP .. (itemLink or "")
                         .. SEP .. (category or "other") .. SEP .. tostring(quality or 0)
                         .. SEP .. tostring(winnerPrio or 0) .. SEP .. (boss or "")
                         .. SEP .. (sessionID or "") .. SEP .. (raidID or ""))
end

--- Observer fragt nach aktiver Session (Late-Joiner Pull); inCombat = ob OBS gerade im Kampf ist
function Comm.SendRaidQuery(inCombat)
    local flag = (inCombat or (UnitAffectingCombat and UnitAffectingCombat("player"))) and "1" or "0"
    SendToGroup("RAID_QUERY" .. SEP .. flag)
end

-- ---- Session-System ----

--- ML hat eine neue Session gestartet (oder eine geschlossene fortgesetzt)
local function SerializePrioCfg(cfg)
    local parts = {}
    for i = 1, 5 do
        local p = cfg and cfg[i] or {}
        local active = (p.active) and "1" or "0"
        local name   = (p.shortName or ""):gsub(":", ""):gsub(";", "")
        local desc   = (p.description or ""):gsub(":", ""):gsub(";", "")
        table.insert(parts, active .. ":" .. name .. ":" .. desc)
    end
    return table.concat(parts, ";")
end

local function DeserializePrioCfg(str)
    if not str or str == "" then return nil end
    local cfg = {}
    local i = 1
    for entry in str:gmatch("[^;]+") do
        local active, name, desc = entry:match("^([01]):([^:]*):(.*)$")
        if active then
            cfg[i] = { active=(active=="1"), shortName=name, description=desc }
        end
        i = i + 1
        if i > 5 then break end
    end
    return cfg
end

function Comm.SendSessionStart(sessionID, label, startedAt, prioCfg)
    local cfgStr = prioCfg and SerializePrioCfg(prioCfg) or ""
    SendToGroup("SESSION_START" .. SEP .. (sessionID or "") .. SEP .. (label or "")
                                .. SEP .. tostring(startedAt or 0) .. SEP .. cfgStr)
end

--- ML hat die aktive Session geschlossen
function Comm.SendSessionEnd(sessionID, closedAt)
    SendToGroup("SESSION_END" .. SEP .. (sessionID or "") .. SEP .. tostring(closedAt or 0))
end

--- ML broadcastet raidMeta (nach Boss-Kill oder Late-Joiner-Push)
--- @param prioCfg table|nil  aktuelle Prio-Config der Session (optional, Feld 9)
function Comm.SendRaidMeta(sessionID, raidID, meta, prioCfg)
    local parts  = table.concat(meta.participants or {}, ",")
    local cfgStr = prioCfg and SerializePrioCfg(prioCfg) or ""
    SendToGroup("RAID_META" .. SEP .. (sessionID or "") .. SEP .. (raidID or "")
                           .. SEP .. (meta.tier or "") .. SEP .. (meta.difficulty or "")
                           .. SEP .. tostring(meta.startedAt or 0)
                           .. SEP .. tostring(meta.closedAt or 0)
                           .. SEP .. parts
                           .. SEP .. cfgStr)
end

--- ML schickt komplette Session an einen bestimmten Observer (Late-Join-Sync via Whisper)
--- Sendet SESSION_START + RAID_META* + LOOT_ASSIGN* als Whisper-Serie
function Comm.SendSessionSync(session, target)
    if not session or not target then return end
    local function Whisper(msg)
        if C_ChatInfo then
            C_ChatInfo.SendAddonMessage(PREFIX, ADDON_VERSION .. SEP .. msg, "WHISPER", target)
        end
    end
    -- 1. Session-Metadaten
    local cfgStr = session.priorityConfig and SerializePrioCfg(session.priorityConfig) or ""
    Whisper("SESSION_START" .. SEP .. session.id .. SEP .. (session.label or "") .. SEP .. tostring(session.startedAt or 0) .. SEP .. cfgStr)
    -- 2. raidMeta-Einträge
    for raidID, meta in pairs(session.raidMeta or {}) do
        local participants = table.concat(meta.participants or {}, ",")
        Whisper("RAID_META" .. SEP .. session.id .. SEP .. raidID
                           .. SEP .. (meta.tier or "") .. SEP .. (meta.difficulty or "")
                           .. SEP .. tostring(meta.startedAt or 0)
                           .. SEP .. tostring(meta.closedAt or 0)
                           .. SEP .. participants)
    end
    -- 3. Zugewiesener Loot
    for _, item in ipairs(session.lootLog or {}) do
        Whisper("ASSIGN" .. SEP .. (item.player or "") .. SEP .. (item.difficulty or "")
                        .. SEP .. (item.link or "") .. SEP .. (item.category or "other")
                        .. SEP .. tostring(item.quality or 0)
                        .. SEP .. tostring(item.winnerPrio or 0)
                        .. SEP .. (item.boss or "")
                        .. SEP .. (item.sessionID or session.id)
                        .. SEP .. (item.raidID or ""))
    end
    -- 4. Getrashter Loot
    for _, item in ipairs(session.trashedLoot or {}) do
        Whisper("LOOT_TRASH" .. SEP .. (item.link or "")
                             .. SEP .. (item.sessionID or session.id)
                             .. SEP .. (item.raidID or ""))
    end
end

--- Neuer ML steht fest (direkte Übernahme oder nach Bestätigung)
function Comm.SendMLAnnounce(newMLName)
    SendToGroup("ML_ANNOUNCE" .. SEP .. (GL.NormalizeName(newMLName or "") or ""))
end

--- Anfrage an aktuellen ML: Claimant möchte ML werden
function Comm.SendMLRequest(claimantName)
    SendToGroup("ML_REQUEST" .. SEP .. (GL.NormalizeName(claimantName or "") or ""))
end

--- ML verweigert den Claim
function Comm.SendMLDeny(claimantName)
    SendToGroup("ML_DENY" .. SEP .. (GL.NormalizeName(claimantName or "") or ""))
end

-- ============================================================
-- Receive-Handler (alle Addon-User empfangen)
-- ============================================================

local function HandleItemOn(parts, sender)
    local link, category = parts[2], parts[3]
    if link and link ~= "" and GL.Loot and GL.Loot.OnCommItemActivate then
        GL.Loot.OnCommItemActivate(link, category or "other")
    end
end

local function HandleItemOff(parts, sender)
    if GL.Loot and GL.Loot.OnCommItemClear then
        GL.Loot.OnCommItemClear()
    end
end

local function HandleRollStart(parts, sender)
    local seconds = tonumber(parts[2]) or 15
    local players = {}
    if parts[3] and parts[3] ~= "" then
        for p in parts[3]:gmatch("[^,]+") do
            table.insert(players, p)
        end
    end
    if GL.Loot and GL.Loot.OnCommRollStart then
        GL.Loot.OnCommRollStart(seconds, players)
    end
end

local function HandleAssign(parts, sender)
    local name, diff, link, category, quality, winnerPrio, boss = parts[2], parts[3], parts[4], parts[5], parts[6], parts[7], parts[8]
    local sessionID, raidID = parts[9], parts[10]
    if GL.Loot and GL.Loot.OnCommAssign then
        GL.Loot.OnCommAssign(name, diff, link, category,
                             tonumber(quality) or 0,
                             tonumber(winnerPrio) or nil,
                             boss ~= "" and boss or nil,
                             sessionID ~= "" and sessionID or nil,
                             raidID ~= "" and raidID or nil)
    end
end

local function HandleRaidQuery(parts, sender)
    local inCombat = (parts[2] == "1")
    if GL.OnCommRaidQuery then GL.OnCommRaidQuery(sender, inCombat) end
end

local function HandleSessionStart(parts, sender)
    local sessionID, label, startedAt = parts[2], parts[3], tonumber(parts[4]) or 0
    local prioCfg = parts[5] and DeserializePrioCfg(parts[5]) or nil
    if GL.OnCommSessionStart then GL.OnCommSessionStart(sessionID, label, startedAt, sender, prioCfg) end
end

local function HandleSessionEnd(parts, sender)
    local sessionID, closedAt = parts[2], tonumber(parts[3]) or 0
    if GL.OnCommSessionEnd then GL.OnCommSessionEnd(sessionID, closedAt) end
end

local function HandleRaidMeta(parts, sender)
    local sessionID, raidID = parts[2], parts[3]
    local tier, diff = parts[4], parts[5]
    local startedAt  = tonumber(parts[6]) or 0
    local closedAt   = (parts[7] ~= "" and parts[7] ~= "0") and tonumber(parts[7]) or nil
    local participants = {}
    if parts[8] and parts[8] ~= "" then
        for p in parts[8]:gmatch("[^,]+") do
            table.insert(participants, p)
        end
    end
    local prioCfg = (parts[9] and parts[9] ~= "") and DeserializePrioCfg(parts[9]) or nil
    local meta = { tier=tier, difficulty=diff, startedAt=startedAt, closedAt=closedAt, participants=participants }
    if GL.OnCommRaidMeta then GL.OnCommRaidMeta(sessionID, raidID, meta, prioCfg) end
end

local function HandleLootTrash(parts, sender)
    local link, sessionID, raidID = parts[2], parts[3], parts[4]
    local db = GuildLootDB
    local targetSession = nil
    if sessionID and sessionID ~= "" then
        for _, s in ipairs(db.raidContainers or {}) do
            if s.id == sessionID then targetSession = s; break end
        end
    end
    if not targetSession and db.activeContainerIdx then
        targetSession = db.raidContainers[db.activeContainerIdx]
    end
    if targetSession and link and link ~= "" then
        table.insert(targetSession.trashedLoot, { link=link, sessionID=sessionID or "", raidID=raidID or "" })
    end
end

local function HandleMLAnnounce(parts, sender)
    if GL.OnCommMLAnnounce then GL.OnCommMLAnnounce(parts[2]) end
end

local function HandleMLRequest(parts, sender)
    if GL.OnCommMLRequest then GL.OnCommMLRequest(parts[2], sender) end
end

local function HandleMLDeny(parts, sender)
    if GL.OnCommMLDeny then GL.OnCommMLDeny(parts[2]) end
end

local msgHandlers = {
    ITEM_ON       = HandleItemOn,
    ITEM_OFF      = HandleItemOff,
    ROLL_START    = HandleRollStart,
    ASSIGN        = HandleAssign,
    RAID_QUERY    = HandleRaidQuery,
    SESSION_START = HandleSessionStart,
    SESSION_END   = HandleSessionEnd,
    RAID_META     = HandleRaidMeta,
    LOOT_TRASH    = HandleLootTrash,
    ML_ANNOUNCE   = HandleMLAnnounce,
    ML_REQUEST    = HandleMLRequest,
    ML_DENY       = HandleMLDeny,
}

function Comm.OnMessage(msg, sender)
    -- Eigene Nachrichten ignorieren (ML hat bereits lokal verarbeitet)
    -- Ausnahme: commLoopback-Flag für Tests
    -- Sender ist realm-qualifiziert ("Name-Realm"), UnitName nicht → NormalizeName verwenden
    local myName      = (GL.NormalizeName and GL.NormalizeName(UnitName("player") or "")) or UnitName("player") or ""
    local myShortName = (GL.ShortName and GL.ShortName(myName)) or myName
    local senderShort = (GL.ShortName and GL.ShortName(sender or "")) or (sender or "")
    -- Exakter Vergleich ODER Kurzname-Vergleich als Fallback für Realm-Formatierungs-Unterschiede
    -- (GetRealmName() kann Leerzeichen enthalten, WoW-Sender-Format nicht immer identisch)
    if sender == myName or senderShort == myShortName then
        if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.commLoopback) then
            return
        end
    end

    -- Addon-Version aus erstem Feld extrahieren
    local sep1 = msg:find(SEP, 1, true)
    if not sep1 then
        GL.Print("|cffff4444[ReqRT] Nachricht ohne Version von "
                 .. GL.ShortName(sender or "?") .. " — bitte Addon aktualisieren.|r")
        return
    end
    local senderVersion = msg:sub(1, sep1 - 1)
    local payload       = msg:sub(sep1 + 1)

    local senderMinor = MinorVersion(senderVersion)
    local localMinor  = MinorVersion(ADDON_VERSION)
    local now = GetTime()
    local lastWarn = versionWarnedAt[sender] or 0
    local canWarn = (now - lastWarn) >= VERSION_WARN_COOLDOWN
    if senderMinor < MIN_PROTO_MINOR then
        if canWarn then
            GL.Print("|cffff4444[ReqRT] " .. GL.ShortName(sender or "?")
                     .. " hat v" .. senderVersion
                     .. " — inkompatibel (min Minor: " .. MIN_PROTO_MINOR
                     .. "). Bitte Addon aktualisieren.|r")
            versionWarnedAt[sender] = now
        end
        return
    elseif senderMinor ~= localMinor then
        if canWarn then
            GL.Print("|cffff8800[ReqRT] Protokoll-Version mismatch: "
                     .. GL.ShortName(sender or "?") .. " hat v" .. senderVersion
                     .. ", lokal v" .. ADDON_VERSION .. "|r")
            versionWarnedAt[sender] = now
        end
    end

    -- Nachricht aufsplitten (payload = msg ohne Version-Prefix)
    local parts = {}
    for p in (payload .. SEP):gmatch("(.-)" .. SEP) do
        table.insert(parts, p)
    end
    local cmd = parts[1]
    if not cmd then return end

    local handler = msgHandlers[cmd]
    if handler then handler(parts, sender) end
end
