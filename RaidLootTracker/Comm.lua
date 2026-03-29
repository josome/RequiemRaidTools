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

--- ML hat Loot einem Spieler zugewiesen
function Comm.SendAssign(playerName, difficulty, itemLink)
    SendToGroup("ASSIGN" .. SEP .. (playerName or "") .. SEP
                         .. (difficulty or "") .. SEP .. (itemLink or ""))
end

--- ML hat Raid gestartet (auch bei GROUP_ROSTER_UPDATE → Late-Joiner-Sync)
function Comm.SendRaidStart(tier, difficulty, id, startedAt)
    SendToGroup("RAID_START" .. SEP .. (tier or "") .. SEP .. (difficulty or "")
                             .. SEP .. (id or "") .. SEP .. tostring(startedAt or 0))
end

--- ML hat Raid beendet
function Comm.SendRaidEnd(raidID)
    SendToGroup("RAID_END" .. SEP .. (raidID or ""))
end

--- Neuer ML steht fest (direkte Übernahme oder nach Bestätigung)
function Comm.SendMLAnnounce(newMLName)
    SendToGroup("ML_ANNOUNCE" .. SEP .. (newMLName or ""))
end

--- Anfrage an aktuellen ML: Claimant möchte ML werden
function Comm.SendMLRequest(claimantName)
    SendToGroup("ML_REQUEST" .. SEP .. (claimantName or ""))
end

--- ML verweigert den Claim
function Comm.SendMLDeny(claimantName)
    SendToGroup("ML_DENY" .. SEP .. (claimantName or ""))
end

-- ============================================================
-- Receive-Handler (alle Addon-User empfangen)
-- ============================================================

function Comm.OnMessage(msg, sender)
    -- Eigene Nachrichten ignorieren (ML hat bereits lokal verarbeitet)
    -- Ausnahme: commLoopback-Flag für Tests
    if sender == UnitName("player") then
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
        local name, diff, link = parts[2], parts[3], parts[4]
        if GL.Loot and GL.Loot.OnCommAssign then
            GL.Loot.OnCommAssign(name, diff, link)
        end

    elseif cmd == "RAID_START" then
        local tier, difficulty, id, startedAt = parts[2], parts[3], parts[4], parts[5]
        if GL.OnCommRaidStart then
            GL.OnCommRaidStart(tier, difficulty, id, tonumber(startedAt) or 0, sender)
        end

    elseif cmd == "RAID_END" then
        if GL.OnCommRaidEnd then
            GL.OnCommRaidEnd(parts[2])
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
