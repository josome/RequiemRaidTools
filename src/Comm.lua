-- RaidLootTracker – Comm.lua
-- Addon-Kommunikation: ML → Observer-Sync via unsichtbarem Addon-Kanal

GuildLoot = GuildLoot or {}
local GL = GuildLoot

GL.Comm = GL.Comm or {}
local Comm = GL.Comm

local PREFIX = "RequiemRLT"
local SEP    = "\t"   -- Tab als Trennzeichen (sicher in Addon-Nachrichten)

-- Prefix beim Laden registrieren
if C_ChatInfo then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

-- ============================================================
-- Intern: Senden an Gruppe
-- ============================================================

local function SendToGroup(msg)
    if not C_ChatInfo then return end
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "PARTY")
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
function Comm.SendSessionStart(sessionID, label, startedAt)
    SendToGroup("SESSION_START" .. SEP .. (sessionID or "") .. SEP .. (label or "")
                                .. SEP .. tostring(startedAt or 0))
end

--- ML hat die aktive Session geschlossen
function Comm.SendSessionEnd(sessionID, closedAt)
    SendToGroup("SESSION_END" .. SEP .. (sessionID or "") .. SEP .. tostring(closedAt or 0))
end

--- ML broadcastet raidMeta (nach Boss-Kill oder Late-Joiner-Push)
function Comm.SendRaidMeta(sessionID, raidID, meta)
    local parts = table.concat(meta.participants or {}, ",")
    SendToGroup("RAID_META" .. SEP .. (sessionID or "") .. SEP .. (raidID or "")
                           .. SEP .. (meta.tier or "") .. SEP .. (meta.difficulty or "")
                           .. SEP .. tostring(meta.startedAt or 0)
                           .. SEP .. tostring(meta.closedAt or 0)
                           .. SEP .. parts)
end

--- ML schickt komplette Session an einen bestimmten Observer (Late-Join-Sync via Whisper)
--- Sendet SESSION_START + RAID_META* + LOOT_ASSIGN* als Whisper-Serie
function Comm.SendSessionSync(session, target)
    if not session or not target then return end
    local function Whisper(msg)
        if C_ChatInfo then
            C_ChatInfo.SendAddonMessage(PREFIX, msg, "WHISPER", target)
        end
    end
    -- 1. Session-Metadaten
    Whisper("SESSION_START" .. SEP .. session.id .. SEP .. (session.label or "") .. SEP .. tostring(session.startedAt or 0))
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

    -- Nachricht aufsplitten
    local parts = {}
    for p in (msg .. SEP):gmatch("(.-)" .. SEP) do
        table.insert(parts, p)
    end
    local cmd = parts[1]
    if not cmd then return end

    if cmd == "ITEM_ON" then
        local link, category = parts[2], parts[3]
        if link and link ~= "" and GL.Loot and GL.Loot.OnCommItemActivate then
            GL.Loot.OnCommItemActivate(link, category or "other")
        end

    elseif cmd == "ITEM_OFF" then
        if GL.Loot and GL.Loot.OnCommItemClear then
            GL.Loot.OnCommItemClear()
        end

    elseif cmd == "ROLL_START" then
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

    elseif cmd == "ASSIGN" then
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

    elseif cmd == "RAID_QUERY" then
        local inCombat = (parts[2] == "1")
        if GL.OnCommRaidQuery then GL.OnCommRaidQuery(sender, inCombat) end

    elseif cmd == "SESSION_START" then
        local sessionID, label, startedAt = parts[2], parts[3], tonumber(parts[4]) or 0
        if GL.OnCommSessionStart then GL.OnCommSessionStart(sessionID, label, startedAt, sender) end

    elseif cmd == "SESSION_END" then
        local sessionID, closedAt = parts[2], tonumber(parts[3]) or 0
        if GL.OnCommSessionEnd then GL.OnCommSessionEnd(sessionID, closedAt) end

    elseif cmd == "RAID_META" then
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
        local meta = { tier=tier, difficulty=diff, startedAt=startedAt, closedAt=closedAt, participants=participants }
        if GL.OnCommRaidMeta then GL.OnCommRaidMeta(sessionID, raidID, meta) end

    elseif cmd == "LOOT_TRASH" then
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

    elseif cmd == "ML_ANNOUNCE" then
        if GL.OnCommMLAnnounce then
            GL.OnCommMLAnnounce(parts[2])
        end

    elseif cmd == "ML_REQUEST" then
        if GL.OnCommMLRequest then
            GL.OnCommMLRequest(parts[2], sender)
        end

    elseif cmd == "ML_DENY" then
        if GL.OnCommMLDeny then
            GL.OnCommMLDeny(parts[2])
        end
    end
end
