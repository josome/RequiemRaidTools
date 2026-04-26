-- GuildLoot – Core.lua
-- Namespace, SavedVariables, Events, Slash-Commands, Roster-Verwaltung

GuildLoot = GuildLoot or {}
local GL = GuildLoot

-- ============================================================
-- Default-Struktur
-- ============================================================

local DB_DEFAULTS = {
    players            = {},
    raidHistory        = {},   -- Legacy; wird bei Init nach unassignedRaids migriert
    raidContainers     = {},   -- Array von Session-Objekten
    activeContainerIdx = nil,  -- Index der offenen Session (nil = keine)
    unassignedRaids    = {},   -- Legacy Raid-Snapshots ohne Session
    lastLogout         = 0,
    currentRaid = {
        id                      = "",
        startedAt               = 0,
        tier                    = "",
        difficulty              = "",
        mlName                  = "",
        participants            = {},
        absent                  = {},
        pendingLoot             = {},
        sessionHidden           = {},
        sessionChecked          = {},
        currentKillParticipants = {},
        lastBoss                = nil,
    },
    settings = {
        postToChat     = true,
        chatChannel    = "AUTO",   -- "AUTO", "RAID", "PARTY", "OFF"
        isMasterLooter = false,
        dungeonMode    = false,
        minQuality     = 4,
        prioSeconds    = 15,
        rollSeconds    = 15,
        framePos     = nil,
        minimized    = true,
        minimapAngle = 45,
        lastTab      = nil,
        raidWarnItem   = true,
        whisperWinner  = true,
        exportFormat = "JSON",  -- "JSON" | "CSV"
        commLoopback = false,   -- true: eigene Addon-Nachrichten empfangen (nur für Tests)
        devMode      = false,   -- true: WoWUnit-Tests aktivieren (/reqrt devmode)
        filterNonEquip   = true,
        filterCategories = {
            weapons  = true,
            trinket  = true,
            setItems = true,
            other    = true,
        },
        priorities = {
            [1] = { active=true,  shortName="BIS",      description="Best In Slot" },
            [2] = { active=true,  shortName="OS",        description="Off-Spec" },
            [3] = { active=false, shortName="",          description="" },
            [4] = { active=true,  shortName="Transmog",  description="Transmog" },
            [5] = { active=false, shortName="",          description="" },
        },
        announceFilter = {
            cloth           = true,
            leather         = true,
            mail            = true,
            plate           = true,
            nonUsableWeapon = true,   -- Waffen die der Spieler nicht ausrüsten kann
            trinket         = true,
            ring            = true,
            neck            = true,
            other           = true,
        },
        popupEnabled = nil,   -- nil = auto (Raid=an, Gruppe/Solo=aus); true/false = explizit
    },
}

local function DefaultPlayerRecord()
    return {
        lootHistory    = {},
        lastDifficulty = { weapons = nil, trinket = nil, setItems = nil },
        counts         = { weapons = 0, trinket = 0, setItems = 0, other = 0 },
        lootEligible   = true,
        setPieces      = 0,
        class          = nil,  -- classFileName, z.B. "WARRIOR"
    }
end

-- ============================================================
-- DB-Initialisierung
-- ============================================================

local function DeepMergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            DeepMergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

local function BackupDB()
    if not (GuildLootDB.raidContainers and #GuildLootDB.raidContainers > 0) then return end
    if not GuildLootDBBackup then GuildLootDBBackup = {} end
    -- Nur überschreiben wenn neue Daten mehr enthalten als das letzte Backup
    local backupLoot = 0
    for _, s in ipairs(GuildLootDBBackup.raidContainers or {}) do
        backupLoot = backupLoot + #(s.lootLog or {})
    end
    local currentLoot = 0
    for _, s in ipairs(GuildLootDB.raidContainers) do
        currentLoot = currentLoot + #(s.lootLog or {})
        -- auch raids-Array zählen (altes Format)
        for _, r in ipairs(s.raids or {}) do
            currentLoot = currentLoot + #(r.lootLog or {})
        end
    end
    if currentLoot >= backupLoot then
        GuildLootDBBackup.raidContainers  = CopyTable(GuildLootDB.raidContainers)
        GuildLootDBBackup.unassignedRaids = CopyTable(GuildLootDB.unassignedRaids or {})
        GuildLootDBBackup.raidHistory     = CopyTable(GuildLootDB.raidHistory or {})
        GuildLootDBBackup.savedAt         = time()
    end
end

local function MigrateCurrentRaidLegacy()
    local cr = GuildLootDB.currentRaid
    -- Migration: lootLog-Einträge im currentRaid → als unassigned retten
    if cr.lootLog and #cr.lootLog > 0 then
        table.insert(GuildLootDB.unassignedRaids, {
            id           = cr.id or "",
            tier         = cr.tier or "",
            difficulty   = cr.difficulty or "",
            participants = cr.participants or {},
            lootLog      = cr.lootLog,
            trashedLoot  = cr.trashedLoot or {},
            pendingLoot  = {},
            startedAt    = cr.startedAt or 0,
            closedAt     = time(),
        })
    end
    cr.active      = nil
    cr.lootLog     = nil
    cr.trashedLoot = nil
    cr.resumed     = nil
end

local function MigrateRaidFormat()
    for _, s in ipairs(GuildLootDB.raidContainers or {}) do
        if not s.raidMeta    then s.raidMeta    = {} end
        if not s.lootLog     then s.lootLog     = {} end
        if not s.trashedLoot then s.trashedLoot = {} end
        -- altes 'raids'-Feld migrieren (War Array von Raid-Snapshots)
        if s.raids and #s.raids > 0 then
            for _, snap in ipairs(s.raids) do
                local raidID = snap.id or GL.GenerateRaidID(snap.tier or "", snap.difficulty or "", snap.startedAt or 0)
                if not s.raidMeta[raidID] then
                    s.raidMeta[raidID] = {
                        tier         = snap.tier or "",
                        difficulty   = snap.difficulty or "",
                        startedAt    = snap.startedAt or 0,
                        closedAt     = snap.closedAt,
                        participants = snap.participants or {},
                    }
                end
                for _, item in ipairs(snap.lootLog or {}) do
                    item.raidID    = item.raidID    or raidID
                    item.sessionID = item.sessionID or s.id
                    table.insert(s.lootLog, item)
                end
                for _, item in ipairs(snap.trashedLoot or {}) do
                    item.raidID    = item.raidID    or raidID
                    item.sessionID = item.sessionID or s.id
                    table.insert(s.trashedLoot, item)
                end
            end
        end
        s.raids = nil
    end
end

function GL.InitDB()
    if not GuildLootDB then GuildLootDB = {} end
    BackupDB()
    DeepMergeDefaults(GuildLootDB, DB_DEFAULTS)
    if #(GuildLootDB.raidHistory or {}) > 0 then
        GL.MigrateRaidHistory()
    end
    -- currentRaid.id immer gesetzt (Invariant)
    if not GuildLootDB.currentRaid.id or GuildLootDB.currentRaid.id == "" then
        GuildLootDB.currentRaid.id = GL.GenerateRaidID("unknown", "", time())
    end
    MigrateCurrentRaidLegacy()
    MigrateRaidFormat()
end

function GL.CreatePlayerRecord(name)
    if not GuildLootDB.players[name] then
        GuildLootDB.players[name] = DefaultPlayerRecord()
    end
end

-- ============================================================
-- Session (Container) System
-- ============================================================

--- Alte raidHistory-Einträge in unassignedRaids verschieben (einmalige Migration).
function GL.MigrateRaidHistory()
    local db = GuildLootDB
    for _, snap in ipairs(db.raidHistory or {}) do
        table.insert(db.unassignedRaids, snap)
    end
    local count = #(db.raidHistory or {})
    db.raidHistory = {}
    if count > 0 then
        GL.Print("Migration: " .. count .. " Raids nach unassignedRaids verschoben.")
    end
end

--- Unassigned Raid in eine Session verschieben.
function GL.AssignUnassignedToSession(unassignedIdx, ci)
    local db      = GuildLootDB
    local snap    = (db.unassignedRaids or {})[unassignedIdx]
    local session = (db.raidContainers or {})[ci]
    if not snap or not session then return end

    local raidID = snap.id
    if not raidID or raidID == "" then
        raidID = GL.GenerateRaidID(snap.tier or "", snap.difficulty or "", snap.startedAt or 0)
    end

    if not session.raidMeta[raidID] then
        session.raidMeta[raidID] = {
            tier         = snap.tier or "",
            difficulty   = snap.difficulty or "",
            startedAt    = snap.startedAt or 0,
            closedAt     = snap.closedAt,
            participants = snap.participants or {},
        }
    end

    for _, item in ipairs(snap.lootLog or {}) do
        item.raidID    = raidID
        item.sessionID = session.id
        table.insert(session.lootLog, item)
    end
    for _, item in ipairs(snap.trashedLoot or {}) do
        item.raidID    = raidID
        item.sessionID = session.id
        table.insert(session.trashedLoot, item)
    end

    table.remove(db.unassignedRaids, unassignedIdx)
end

--- Timestamp des letzten EU-Weekly-Resets (Mittwoch 07:00 Systemzeit).
function GL.GetLastWeeklyReset()
    local now         = time()
    local weekday     = tonumber(date("%w", now))        -- 0=So…6=Sa
    local daysSinceWed = (weekday + 7 - 3) % 7
    local lastWedDay  = now - daysSinceWed * 86400
    local y = tonumber(date("%Y", lastWedDay))
    local m = tonumber(date("%m", lastWedDay))
    local d = tonumber(date("%d", lastWedDay))
    local resetTs = time({ year=y, month=m, day=d, hour=7, min=0, sec=0 })
    if resetTs > now then resetTs = resetTs - 7 * 86400 end
    return resetTs
end

--- Neue Session starten.
function GL.StartContainer(label)
    local db = GuildLootDB
    if db.activeContainerIdx then
        GL.Print("Session bereits offen.")
        return
    end
    local ts  = time()
    local kw  = GL.ISOWeek(ts)
    local yr  = tonumber(date("%Y", ts))
    local finalLabel = (label and label ~= "") and label
                       or string.format("KW %02d %d", kw, yr)
    local session = {
        id             = string.format("%04d-W%02d-%08x", yr, kw, ts),
        label          = finalLabel,
        startedAt      = ts,
        closedAt       = nil,
        pendingLoot    = {},
        lootLog        = {},
        trashedLoot    = {},
        raidMeta       = {},
        priorityConfig = CopyTable(db.settings.priorities or {}),
    }
    table.insert(db.raidContainers, session)
    db.activeContainerIdx = #db.raidContainers
    GL.Print("Session gestartet: " .. finalLabel)
    if GL.Comm and GL.Comm.SendSessionStart then
        GL.Comm.SendSessionStart(session.id, finalLabel, ts, session.priorityConfig)
    end
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

--- Offene Session schließen.
function GL.CloseContainer()
    local db = GuildLootDB
    if not db.activeContainerIdx then return end
    local session  = db.raidContainers[db.activeContainerIdx]
    local sessionID = session.id
    if not session.raidMeta    then session.raidMeta    = {} end
    if not session.lootLog     then session.lootLog     = {} end
    if not session.trashedLoot then session.trashedLoot = {} end
    -- Letzte raidMeta schließen
    local raidID = db.currentRaid.id
    if session.raidMeta[raidID] then
        session.raidMeta[raidID].closedAt = time()
    end
    local closedAt = time()
    GL.ResetCurrentRaid()
    session.closedAt      = closedAt
    db.activeContainerIdx = nil
    GL.Print("Session geschlossen.")
    if GL.Comm and GL.Comm.SendSessionEnd then
        GL.Comm.SendSessionEnd(sessionID, closedAt)
    end
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

--- Geschlossene Session wieder öffnen.
function GL.ResumeContainer(ci)
    local db = GuildLootDB
    if db.activeContainerIdx then
        GL.Print("Session bereits offen. Erst schließen.")
        return
    end
    local session = (db.raidContainers or {})[ci]
    if not session then return end
    db.activeContainerIdx = ci
    session.closedAt      = nil
    -- Letzten raidMeta-Kontext in currentRaid laden
    local lastID, lastTs = nil, 0
    for rid, meta in pairs(session.raidMeta or {}) do
        if (meta.startedAt or 0) > lastTs then
            lastTs = meta.startedAt
            lastID = rid
        end
    end
    if lastID then
        local meta = session.raidMeta[lastID]
        local cr   = db.currentRaid
        cr.id         = lastID
        cr.tier       = meta.tier or ""
        cr.difficulty = meta.difficulty or ""
        cr.startedAt  = meta.startedAt or 0
        cr.participants = {}
        for _, p in ipairs(meta.participants or {}) do
            table.insert(cr.participants, p)
        end
    end
    GL.Print("Session fortgesetzt: " .. (session.label or "?"))
    if GL.Comm and GL.Comm.SendSessionStart then
        GL.Comm.SendSessionStart(session.id, session.label or "", session.startedAt or 0)
    end
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

--- Stellt sicher dass raidMeta[currentRaid.id] existiert; legt es beim ersten Bosskill an.
function GL.EnsureRaidMeta()
    local db = GuildLootDB
    if not db.activeContainerIdx then return end
    local session = db.raidContainers[db.activeContainerIdx]
    if not session.raidMeta    then session.raidMeta    = {} end
    if not session.lootLog     then session.lootLog     = {} end
    if not session.trashedLoot then session.trashedLoot = {} end
    local raid    = db.currentRaid
    local id      = raid.id
    if not id or id == "" then return end
    if not session.raidMeta[id] then
        local meta = {
            tier         = raid.tier or "",
            difficulty   = raid.difficulty or "",
            startedAt    = raid.startedAt or time(),
            closedAt     = nil,
            participants = {},
        }
        for _, p in ipairs(raid.participants or {}) do
            table.insert(meta.participants, p)
        end
        session.raidMeta[id] = meta
        if GL.IsMasterLooter() and GL.Comm and GL.Comm.SendRaidMeta then
            GL.Comm.SendRaidMeta(session.id, id, meta)
        end
    end
end

--- currentRaid-Kontext zurücksetzen (neue ID, alles leeren).
function GL.ResetCurrentRaid()
    local cr = GuildLootDB.currentRaid
    cr.id                      = GL.GenerateRaidID("unknown", "", time())
    cr.tier                    = ""
    cr.difficulty              = ""
    cr.startedAt               = 0
    cr.mlName                  = ""
    cr.participants            = {}
    cr.absent                  = {}
    cr.pendingLoot             = {}
    cr.sessionHidden           = {}
    cr.sessionChecked          = {}
    cr.currentKillParticipants = {}
    cr.lastBoss                = nil
    if GL.Loot and GL.Loot.ClearCurrentItem then GL.Loot.ClearCurrentItem() end
end

--- Stellt sicher dass eine Session offen ist; erstellt "Auto KW X" falls keine aktiv.
function GL.EnsureActiveSession()
    if GuildLootDB.activeContainerIdx then return end
    local kw = GL.ISOWeek(time())
    GL.StartContainer(string.format("Auto KW %02d", kw))
end

-- ============================================================
-- Ausgabe-Helfer
-- ============================================================

function GL.Print(msg)
    print("|cff00ccff[ReqRT]|r " .. tostring(msg))
end

function GL.PostToRaid(msg)
    local s  = GuildLootDB.settings
    local ch = s.chatChannel or "AUTO"
    -- Backward-compat: altes postToChat=false verhält sich wie "OFF"
    if ch == "OFF" or (ch == "AUTO" and s.postToChat == false) then return end
    local channel
    if ch == "RAID" then
        channel = "RAID"
    elseif ch == "PARTY" then
        channel = "PARTY"
    elseif ch == "INSTANCE_CHAT" then
        channel = "INSTANCE_CHAT"
    else   -- AUTO
        if     IsInRaid()                                    then channel = "RAID"
        elseif IsInGroup(LE_PARTY_CATEGORY_INSTANCE)         then channel = "INSTANCE_CHAT"
        elseif IsInGroup()                                   then channel = "PARTY"
        else
            local _, instanceType = GetInstanceInfo()
            if instanceType == "raid" then channel = "SAY" else return end
        end
    end
    SendChatMessage("[ReqRT] " .. msg, channel)
end

function GL.PostRaidWarn(msg)
    if not GuildLootDB.settings.raidWarnItem then
        GL.PostToRaid(msg)
        return
    end
    if IsInGroup() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        SendChatMessage("[ReqRT] " .. msg, "RAID_WARNING")
    else
        GL.PostToRaid(msg)
    end
end

-- ============================================================
-- Roster-Verwaltung
-- ============================================================

-- NormalizeName ist jetzt GL.NormalizeName (Util.lua) – hier Alias für Abwärtskompatibilität
local NormalizeName = function(name) return GL.NormalizeName(name) end

function GL.LoadRaidRoster()
    local raid = GuildLootDB.currentRaid
    raid.participants = {}
    raid.absent = {}

    local function AddMember(name, online, classFileName)
        name = NormalizeName(name)
        if not name then return end
        GL.CreatePlayerRecord(name)
        if classFileName then
            GuildLootDB.players[name].class = classFileName
        end
        table.insert(raid.participants, name)
        if online == false then
            raid.absent[name] = true
        end
    end

    if IsInRaid() then
        -- Raid-Gruppe: GetRaidRosterInfo funktioniert
        -- Rückgabe: name, rank, subgroup, level, class, fileName, zone, online, ...
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, fileName, _, online = GetRaidRosterInfo(i)
            if name then AddMember(name, online, fileName) end
        end
    elseif IsInGroup() then
        -- Party: eigenen Char + party1..party4
        local _, playerClass = UnitClass("player")
        AddMember(UnitName("player"), true, playerClass)
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name then
                local _, classFile = UnitClass(unit)
                AddMember(name, UnitIsConnected(unit), classFile)
            end
        end
    else
        -- Solo: nur eigenen Char (Testmodus)
        local _, playerClass = UnitClass("player")
        AddMember(UnitName("player"), true, playerClass)
    end
end

function GL.SyncRoster()
    local raid = GuildLootDB.currentRaid
    if not GuildLootDB.activeContainerIdx then return end

    -- Aktuellen Raid-Stand einlesen
    local currentMembers = {}
    local function AddCurrent(name, online)
        name = NormalizeName(name)
        if name then currentMembers[name] = online end
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name then AddCurrent(name, online) end
        end
    elseif IsInGroup() then
        AddCurrent(UnitName("player"), true)
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name then AddCurrent(name, UnitIsConnected(unit)) end
        end
    else
        AddCurrent(UnitName("player"), true)
    end

    -- Neu beigetreten? → immer zur kumulativen Liste hinzufügen
    for name, online in pairs(currentMembers) do
        if not GL.TableContains(raid.participants, name) then
            GL.CreatePlayerRecord(name)
            table.insert(raid.participants, name)
            GL.Print(GL.ShortName(name) .. " ist dem Raid beigetreten.")
        end
        -- Reconnect
        if raid.absent[name] and online then
            raid.absent[name] = nil
        end
        -- DC markieren
        if not online and not raid.absent[name] then
            raid.absent[name] = true
        end
    end

    -- Verlassen (komplett weg)
    -- Spieler bleiben in participants, werden nur als absent markiert
    for _, name in ipairs(raid.participants) do
        if not currentMembers[name] and not raid.absent[name] then
            raid.absent[name] = true
        end
    end

    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

-- ============================================================
-- Raid-Kontrolle
-- ============================================================

--- Hilfsfunktion: Instanzname + Datum als Tier-String
local function AutoTierName()
    -- In einer Instanz: GetInstanceInfo() liefert den korrekten Raid-/Dungeonname
    local instanceName, instanceType = GetInstanceInfo()
    if instanceName and instanceName ~= "" and instanceType ~= "none" then
        return instanceName .. " (" .. date("%d.%m.%Y") .. ")"
    end
    -- Außerhalb: Karten-API oder Zone als Fallback
    local bestMap = C_Map.GetBestMapForUnit("player")
    local mapInfo = bestMap and C_Map.GetMapInfo(bestMap)
    local zoneName = (mapInfo and mapInfo.name and mapInfo.name ~= "") and mapInfo.name or GetRealZoneText()
    if zoneName and zoneName ~= "" then
        return zoneName .. " (" .. date("%d.%m.%Y") .. ")"
    end
    return date("%d.%m.%Y")
end

function GL.StartRaid(tier)
    -- Ensure a session is open (creates "Auto KW X" if needed)
    GL.EnsureActiveSession()
    local db   = GuildLootDB
    local raid = db.currentRaid
    -- Close existing raidMeta entry if one exists for the current ID
    local session = db.raidContainers[db.activeContainerIdx]
    if session and raid.id and raid.id ~= "" and session.raidMeta[raid.id] then
        session.raidMeta[raid.id].closedAt = time()
    end
    -- Set new context
    raid.tier       = (tier and tier ~= "") and tier or AutoTierName()
    raid.difficulty = GL.DetectDifficulty() or ""
    raid.startedAt  = time()
    raid.id         = GL.GenerateRaidID(raid.tier, raid.difficulty, raid.startedAt)
    GL.LoadRaidRoster()
    raid.mlName = NormalizeName(UnitName("player")) or ""
    GuildLootDB.settings.isMasterLooter = true
    -- Create raidMeta entry and broadcast RAID_META
    GL.EnsureRaidMeta()
    GL.Print("Raid started: " .. raid.tier .. ". " .. #raid.participants .. " players loaded.")
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
    if GL.UI and GL.UI.ShowTab then GL.UI.ShowTab(GL.UI.TAB_LOOT) end
end

function GL.CloseRaid()
    -- Shim: delegates to CloseContainer
    GL.CloseContainer()
end

-- ============================================================
-- Observer-Handler (empfangen Comm-Nachrichten vom ML)
-- ============================================================

-- Vorhandene Session als aktiv setzen; geschlossene Session dabei wieder öffnen.
local function ResumeSession(s, i)
    local db = GuildLootDB
    if s.closedAt then
        s.closedAt = nil
        GL.Print("Session fortgesetzt von ML: " .. (s.label or "?"))
    end
    db.activeContainerIdx = i
end

-- Session-Objekt aus Sync-Daten bauen (keine DB-Seiteneffekte).
local function BuildSessionFromSync(sessionID, label, startedAt, prioCfg)
    local db = GuildLootDB
    return {
        id             = sessionID,
        label          = label or "",
        startedAt      = startedAt or 0,
        closedAt       = nil,
        lootLog        = {},
        trashedLoot    = {},
        raidMeta       = {},
        priorityConfig = prioCfg or CopyTable(db.settings.priorities or {}),
    }
end

--- Observer: empfängt SESSION_START vom ML (neue oder wiedergeöffnete Session).
function GL.OnCommSessionStart(sessionID, label, startedAt, sender, prioCfg)
    local myName = GL.NormalizeName(UnitName("player") or "") or ""
    if GL.NormalizeName(sender or "") == myName then return end
    local db = GuildLootDB
    for i, s in ipairs(db.raidContainers or {}) do
        if s.id == sessionID then
            if prioCfg then s.priorityConfig = prioCfg end
            ResumeSession(s, i)
            if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
            return
        end
    end
    local session = BuildSessionFromSync(sessionID, label, startedAt, prioCfg)
    table.insert(db.raidContainers, session)
    db.activeContainerIdx = #db.raidContainers
    GL.Print("Session von ML synchronisiert: " .. (label or "?"))
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

--- Observer: empfängt SESSION_END vom ML.
function GL.OnCommSessionEnd(sessionID, closedAt)
    local db = GuildLootDB
    for i, s in ipairs(db.raidContainers or {}) do
        if s.id == sessionID then
            s.closedAt = closedAt
            if db.activeContainerIdx == i then
                db.activeContainerIdx = nil
                GL.ResetCurrentRaid()
            end
            break
        end
    end
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

--- Observer: empfängt RAID_META vom ML (neuer Boss-Kill / neuer Raid-Kontext).
function GL.OnCommRaidMeta(sessionID, raidID, meta)
    local db = GuildLootDB
    for _, s in ipairs(db.raidContainers or {}) do
        if s.id == sessionID then
            if not s.raidMeta[raidID] then
                s.raidMeta[raidID] = meta
            end
            -- currentRaid-Kontext auf neueste raidMeta setzen
            local cr = db.currentRaid
            cr.id         = raidID
            cr.tier       = meta.tier or ""
            cr.difficulty = meta.difficulty or ""
            cr.startedAt  = meta.startedAt or 0
            cr.participants = {}
            for _, p in ipairs(meta.participants or {}) do
                table.insert(cr.participants, p)
            end
            break
        end
    end
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

--- RAID_QUERY-Handler (ML-Seite): sendet SESSION_SYNC oder queued den Request.
function GL.OnCommRaidQuery(sender, inCombat)
    if not GL.IsMasterLooter() then return end
    local db = GuildLootDB
    if not db.activeContainerIdx then return end
    -- Combat-Gate: wenn ML oder OBS im Kampf → Request queuen
    local mlInCombat = UnitAffectingCombat and UnitAffectingCombat("player")
    if mlInCombat or inCombat then
        if not GL._pendingSyncRequests then GL._pendingSyncRequests = {} end
        GL._pendingSyncRequests[sender] = true
        return
    end
    local session = db.raidContainers[db.activeContainerIdx]
    if GL.Comm and GL.Comm.SendSessionSync then
        GL.Comm.SendSessionSync(session, sender)
    end
end

--- Observer: komplette Session vom ML empfangen (Late-Join-Sync).
--- Sucht Session nach ID in raidContainers und ersetzt sie.
--- Gibt den Index zurück wenn gefunden, nil wenn neu eingefügt.
function GL.FindOrReplaceSession(session)
    local db = GuildLootDB
    for i, s in ipairs(db.raidContainers or {}) do
        if s.id == session.id then
            db.raidContainers[i] = session
            return i
        end
    end
    table.insert(db.raidContainers, session)
    db.activeContainerIdx = #db.raidContainers
    return nil
end

--- Lädt currentRaid-Kontext aus dem neuesten nicht-geschlossenen raidMeta-Eintrag.
function GL.LoadLastRaidContext(session)
    local db = GuildLootDB
    local lastID, lastTs = nil, 0
    for rid, meta in pairs(session.raidMeta or {}) do
        if (meta.startedAt or 0) > lastTs and not meta.closedAt then
            lastTs = meta.startedAt; lastID = rid
        end
    end
    if lastID then
        local meta = session.raidMeta[lastID]
        local cr   = db.currentRaid
        cr.id = lastID; cr.tier = meta.tier or ""; cr.difficulty = meta.difficulty or ""
        cr.startedAt = meta.startedAt or 0
        cr.participants = {}
        for _, p in ipairs(meta.participants or {}) do table.insert(cr.participants, p) end
    end
end

function GL.OnCommSessionSync(session, sender)
    if GL.IsMasterLooter() then return end
    local db  = GuildLootDB
    local idx = GL.FindOrReplaceSession(session)
    if idx == nil then
        GL.Print("Session synchronisiert: " .. (session.label or "?"))
    elseif db.activeContainerIdx == idx then
        GL.LoadLastRaidContext(session)
    end
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

function GL.OnCommMLAnnounce(newMLName)
    -- Laufenden Claim-Timer abbrechen (Claim wurde bestätigt oder jemand anderes wurde ML)
    if GL._mlClaimTimer then GL._mlClaimTimer:Cancel(); GL._mlClaimTimer = nil end
    local myName    = NormalizeName(UnitName("player")) or ""
    local normalNew = NormalizeName(newMLName or "") or ""
    GuildLootDB.currentRaid.mlName = normalNew   -- immer realm-qualifiziert speichern
    if myName == normalNew then
        GuildLootDB.settings.isMasterLooter = true
    else
        GuildLootDB.settings.isMasterLooter = false
    end
    if normalNew == "" then
        GL.Print("Kein Master Looter aktiv.")
    else
        GL.Print(GL.ShortName(newMLName or "") .. " ist jetzt Master Looter.")
    end
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

function GL.OnCommMLRequest(claimantName, sender)
    if not GL.IsMasterLooter() then return end
    -- Race Condition: nur einen Claim gleichzeitig erlauben
    local normalClaim = NormalizeName(claimantName or "") or ""
    if GL._pendingMLClaim and GL._pendingMLClaim ~= normalClaim then
        if GL.Comm then GL.Comm.SendMLDeny(claimantName) end
        return
    end
    GL._pendingMLClaim = normalClaim
    StaticPopupDialogs["RLT_ML_REQUEST"] = {
        text         = (GL.ShortName(claimantName or "") .. " möchte Master Looter werden. Übergeben?"),
        button1      = "Ja",
        button2      = "Nein",
        OnAccept     = function()
            GL._pendingMLClaim = nil
            GuildLootDB.settings.isMasterLooter = false
            if GL.Comm then GL.Comm.SendMLAnnounce(claimantName) end
        end,
        OnCancel     = function()
            GL._pendingMLClaim = nil
            if GL.Comm then GL.Comm.SendMLDeny(claimantName) end
        end,
        timeout      = 15,
        whileDead    = false,
        hideOnEscape = true,
    }
    StaticPopup_Show("RLT_ML_REQUEST")
end

function GL.OnCommMLDeny(claimantName)
    local myName = NormalizeName(UnitName("player")) or ""
    if myName ~= NormalizeName(claimantName or "") then return end
    -- Laufenden Claim-Timer abbrechen; Flag setzen falls Timer gerade noch läuft
    GL._mlDenied = true
    if GL._mlClaimTimer then GL._mlClaimTimer:Cancel(); GL._mlClaimTimer = nil end
    GuildLootDB.settings.isMasterLooter = false
    GL.Print("|cffff4444ML-Anfrage abgelehnt.|r")
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

-- ResumeRaid is superseded by ResumeContainer(ci). Kept as no-op shim.
function GL.ResumeRaid(idx)
    GL.Print("ResumeRaid: use ResumeContainer(ci) instead.")
end

function GL.ResetRaid()
    GL.ResetCurrentRaid()
    GL.Print("Raid context has been reset.")
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

function GL.ShowHistory(targetName)
    local players = GuildLootDB.players
    -- Partial match erlauben
    local found = nil
    if targetName then
        local lower = targetName:lower()
        for name, _ in pairs(players) do
            if name:lower():find(lower, 1, true) then
                found = name
                break
            end
        end
    end

    if not found then
        GL.Print("Player not found: " .. (targetName or "?"))
        return
    end

    local data = players[found]
    GL.Print("=== Loot History: " .. GL.ShortName(found) .. " ===")
    if #data.lootHistory == 0 then
        GL.Print("  (no entries)")
        return
    end
    for i = #data.lootHistory, math.max(1, #data.lootHistory - 9), -1 do
        local entry = data.lootHistory[i]
        local diff  = entry.difficulty and ("[" .. entry.difficulty .. "] ") or ""
        local cat   = entry.category or "?"
        local ts    = GL.FormatTimestamp(entry.timestamp)
        GL.Print(string.format("  %s %s%s (%s)", ts, diff, entry.item or "?", cat))
    end
end

-- ============================================================
-- Event-Handler
-- ============================================================

local eventFrame = CreateFrame("Frame", "GuildLootEventFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:RegisterEvent("LOOT_SLOT_CHANGED")
eventFrame:RegisterEvent("LOOT_CLOSED")
eventFrame:RegisterEvent("START_LOOT_ROLL")
eventFrame:RegisterEvent("CHAT_MSG_RAID")
eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_PARTY")
eventFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT")
eventFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_SAY")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("TRADE_SHOW")
eventFrame:RegisterEvent("TRADE_CLOSED")
eventFrame:RegisterEvent("TRADE_ACCEPT_UPDATE")

local function OnEventAddonLoaded(addonName)
    if addonName == "RequiemRaidTools" then
        GL.InitDB()
        GL.Print("Loaded. /reqrt to open the main window.")
    end
end

local function OnEventPlayerLogin()
    local db = GuildLootDB
    -- Auto-Close nach Weekly Reset
    if db.activeContainerIdx then
        local reset   = GL.GetLastWeeklyReset()
        local session = db.raidContainers[db.activeContainerIdx]
        if session and (session.startedAt or 0) < reset then
            GL.Print("Session automatisch geschlossen (Weekly Reset).")
            GL.CloseContainer()
        end
    end
    -- Auto-Close nach >4h offline
    if db.activeContainerIdx and db.lastLogout and db.lastLogout > 0 then
        if (time() - db.lastLogout) > 4 * 3600 then
            GL.Print("Session automatisch geschlossen (>4h offline).")
            GL.CloseContainer()
        end
    end
    if GL.UI and GL.UI.Init then GL.UI.Init() end
    -- Delayed RAID_QUERY: Gruppe/Raid-API ist bei Login noch nicht sofort bereit.
    C_Timer.After(3, function()
        if not GL.IsMasterLooter() and not GuildLootDB.activeContainerIdx then
            GL._lastRaidQuery = time()
            if GL.Comm and GL.Comm.SendRaidQuery then GL.Comm.SendRaidQuery() end
        end
    end)
end

local function OnEventPlayerLogout()
    GuildLootDB.lastLogout = time()
    if GL.UI and GL.UI.SavePosition then GL.UI.SavePosition() end
end

local function OnEventPlayerEnteringWorld()
    if GL.UI and GL.UI.OnZoneChanged then GL.UI.OnZoneChanged() end
    -- Zone-Wechsel: nur wenn Session offen und ML
    local db = GuildLootDB
    if db.activeContainerIdx and GL.IsMasterLooter() then
        local newTier = AutoTierName()
        local newDiff = GL.DetectDifficulty() or ""
        local cr      = db.currentRaid
        -- Tier oder Schwierigkeit geändert → altes raidMeta schließen, neue ID
        if (cr.tier ~= "" and cr.tier ~= newTier)
           or (cr.difficulty ~= "" and cr.difficulty ~= newDiff) then
            local session = db.raidContainers[db.activeContainerIdx]
            if not session.raidMeta then session.raidMeta = {} end
            if session and cr.id and cr.id ~= "" and session.raidMeta[cr.id] then
                session.raidMeta[cr.id].closedAt = time()
            end
            cr.id         = GL.GenerateRaidID(newTier, newDiff, time())
            cr.tier       = newTier
            cr.difficulty = newDiff
            cr.startedAt  = time()
            C_Timer.After(0, GL.LoadRaidRoster)
        end
    end
end

local function OnEventTradeShow()
    if GL.Loot and GL.Loot.OnTradeShow then GL.Loot.OnTradeShow() end
end

local function OnEventTradeClosed()
    if GL.Loot and GL.Loot.OnTradeClosed then GL.Loot.OnTradeClosed() end
end

local function OnEventTradeAcceptUpdate(playerAccepted, targetAccepted)
    if GL.Loot and GL.Loot.OnTradeAcceptUpdate then
        GL.Loot.OnTradeAcceptUpdate(playerAccepted, targetAccepted)
    end
end

local function OnEventGroupRosterUpdate()
    if not GL._rosterUpdatePending then
        GL._rosterUpdatePending = true
        C_Timer.After(0, function()
            GL._rosterUpdatePending = nil
            GL.SyncRoster()
            local db = GuildLootDB
            -- ML: Session-State an neue Mitglieder pushen
            if db.activeContainerIdx and GL.IsMasterLooter() then
                local session = db.raidContainers[db.activeContainerIdx]
                if GL.Comm and GL.Comm.SendSessionStart then
                    GL.Comm.SendSessionStart(session.id, session.label, session.startedAt)
                end
            end
            -- Observer ohne aktive Session → Sync anfordern (max. 1x alle 5s)
            if not GL.IsMasterLooter() and not db.activeContainerIdx then
                local now = time()
                if not GL._lastRaidQuery or (now - GL._lastRaidQuery) > 5 then
                    GL._lastRaidQuery = now
                    if GL.Comm and GL.Comm.SendRaidQuery then GL.Comm.SendRaidQuery() end
                end
            end
        end)
    end
end

local function OnEventEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    if success == 1 then
        -- Boss-Name für Loot-Tracking speichern
        GuildLootDB.currentRaid.lastBoss = encounterName
        -- Snapshot der aktuellen Gruppe für Loot-Berechtigung
        local kill = {}
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local n = GetRaidRosterInfo(i)
                if n then table.insert(kill, NormalizeName(n)) end
            end
        elseif IsInGroup() then
            table.insert(kill, NormalizeName(UnitName("player")))
            for i = 1, GetNumGroupMembers() - 1 do
                local n = UnitName("party" .. i)
                if n then table.insert(kill, NormalizeName(n)) end
            end
        else
            table.insert(kill, NormalizeName(UnitName("player")))
        end
        GuildLootDB.currentRaid.currentKillParticipants = kill
        if GL.IsMasterLooter() then
            -- difficultyID direkt aus Event → 100% zuverlässig
            local eventDiff = GL.DiffIDToString(difficultyID)
            local cr        = GuildLootDB.currentRaid
            local newTier   = AutoTierName()
            local db        = GuildLootDB
            -- Neue Raid-ID wenn Tier oder Difficulty sich geändert hat
            local diffChanged = eventDiff and eventDiff ~= "" and eventDiff ~= cr.difficulty
            local tierChanged = newTier ~= "" and newTier ~= cr.tier and cr.tier ~= ""
            if diffChanged or tierChanged then
                -- Alten raidMeta-Eintrag schließen
                local session = db.raidContainers[db.activeContainerIdx]
                if session and session.raidMeta and cr.id and cr.id ~= "" and session.raidMeta[cr.id] then
                    session.raidMeta[cr.id].closedAt = time()
                end
                cr.id         = GL.GenerateRaidID(newTier, eventDiff or "", time())
                cr.tier       = newTier
                cr.difficulty = eventDiff or ""
                cr.startedAt  = time()
            else
                cr.tier       = cr.tier ~= "" and cr.tier or newTier
                cr.difficulty = eventDiff or cr.difficulty or ""
                cr.startedAt  = cr.startedAt ~= 0 and cr.startedAt or time()
            end
            GL.EnsureRaidMeta()
            if GL.UI and GL.UI.AutoExpand then C_Timer.After(0, GL.UI.AutoExpand) end
        end
    end
end

local function OnEventPlayerRegenEnabled()
    -- ML: ausstehende SESSION_SYNC-Anfragen abarbeiten
    if GL.IsMasterLooter() and GL._pendingSyncRequests then
        local db = GuildLootDB
        if db.activeContainerIdx then
            local session = db.raidContainers[db.activeContainerIdx]
            for sender, _ in pairs(GL._pendingSyncRequests) do
                if GL.Comm and GL.Comm.SendSessionSync then
                    GL.Comm.SendSessionSync(session, sender)
                end
            end
        end
        GL._pendingSyncRequests = {}
    end
    -- Observer: RAID_QUERY erneut senden falls im Kampf geblockt
    if not GL.IsMasterLooter() and GL._pendingRaidQueryOnCombatEnd then
        GL._pendingRaidQueryOnCombatEnd = false
        if GL.Comm and GL.Comm.SendRaidQuery then GL.Comm.SendRaidQuery() end
    end
end

local function OnEventStartLootRoll(rollID)
    if GL.IsValidZone() and GL.Loot and GL.Loot.OnLootRollStart then
        GL.Loot.OnLootRollStart(rollID)
    end
end

local function OnEventLootOpened()
    if GL.IsValidZone() and GL.Loot and GL.Loot.OnLootOpened then
        C_Timer.After(0, function() GL.Loot.OnLootOpened() end)
    end
end

local function OnEventLootSlotChanged()
    -- In Group Loot kommen Items asynchron nach LOOT_OPENED
    -- OnLootOpened erneut aufrufen – Dedup verhindert doppelte Einträge
    if GL.IsValidZone() and GL.Loot and GL.Loot.OnLootOpened then
        C_Timer.After(0, function() GL.Loot.OnLootOpened() end)
    end
end

local function OnEventLootClosed()
    if GL.IsValidZone() and GL.Loot and GL.Loot.OnLootClosed then GL.Loot.OnLootClosed() end
end

local function OnEventChatMessage(msg, sender)
    if GL.IsValidZone() then
        if GL.Loot and GL.Loot.OnChatMessage then GL.Loot.OnChatMessage(msg, sender) end
    end
end

local function OnEventChatMessageSay(msg, sender)
    -- SAY nur verarbeiten wenn solo in Raid-Instanz (kein echter Raid/Party)
    local _, instanceType = GetInstanceInfo()
    if GL.IsValidZone() and instanceType == "raid" and not IsInGroup() then
        if GL.Loot and GL.Loot.OnChatMessage then GL.Loot.OnChatMessage(msg, sender) end
    end
end

local function OnEventChatMsgSystem(msg)
    if GL.IsValidZone() then
        if GL.Loot and GL.Loot.OnSystemMessage then GL.Loot.OnSystemMessage(msg) end
    end
end

local function OnEventChatMsgAddon(prefix, msg, _, sender)
    if prefix == "RequiemRLT" and GL.Comm and GL.Comm.OnMessage then
        GL.Comm.OnMessage(msg, sender)
    end
end

local function OnEventGetItemInfoReceived(itemID, success)
    if success and GL.Loot and GL.Loot.OnItemInfoReceived then
        GL.Loot.OnItemInfoReceived(itemID)
    end
end

local eventDispatch = {
    ADDON_LOADED                  = OnEventAddonLoaded,
    PLAYER_LOGIN                  = OnEventPlayerLogin,
    PLAYER_LOGOUT                 = OnEventPlayerLogout,
    PLAYER_ENTERING_WORLD         = OnEventPlayerEnteringWorld,
    TRADE_SHOW                    = OnEventTradeShow,
    TRADE_CLOSED                  = OnEventTradeClosed,
    TRADE_ACCEPT_UPDATE           = OnEventTradeAcceptUpdate,
    RAID_ROSTER_UPDATE            = OnEventGroupRosterUpdate,
    GROUP_ROSTER_UPDATE           = OnEventGroupRosterUpdate,
    ENCOUNTER_END                 = OnEventEncounterEnd,
    PLAYER_REGEN_ENABLED          = OnEventPlayerRegenEnabled,
    START_LOOT_ROLL               = OnEventStartLootRoll,
    LOOT_OPENED                   = OnEventLootOpened,
    LOOT_SLOT_CHANGED             = OnEventLootSlotChanged,
    LOOT_CLOSED                   = OnEventLootClosed,
    CHAT_MSG_RAID                 = OnEventChatMessage,
    CHAT_MSG_RAID_LEADER          = OnEventChatMessage,
    CHAT_MSG_PARTY                = OnEventChatMessage,
    CHAT_MSG_PARTY_LEADER         = OnEventChatMessage,
    CHAT_MSG_INSTANCE_CHAT        = OnEventChatMessage,
    CHAT_MSG_INSTANCE_CHAT_LEADER = OnEventChatMessage,
    CHAT_MSG_SAY                  = OnEventChatMessageSay,
    CHAT_MSG_SYSTEM               = OnEventChatMsgSystem,
    CHAT_MSG_ADDON                = OnEventChatMsgAddon,
    GET_ITEM_INFO_RECEIVED        = OnEventGetItemInfoReceived,
}

eventFrame:SetScript("OnEvent", function(self, event, ...)
    local handler = eventDispatch[event]
    if handler then handler(...) end
end)

-- ============================================================
-- Slash-Commands
-- ============================================================

SLASH_REQUIEMRAIDTOOLS1 = "/reqrt"
SLASH_REQUIEMRAIDTOOLS2 = "/requiemraidtools"
SlashCmdList["REQUIEMRAIDTOOLS"] = function(input)
    local cmd, arg = input:match("^(%S*)%s*(.*)")
    cmd = cmd:lower()

    if cmd == "" then
        if GL.UI and GL.UI.Toggle then GL.UI.Toggle() end

    elseif cmd == "start" then
        GL.StartRaid(arg ~= "" and arg or nil)

    elseif cmd == "history" or cmd == "h" then
        GL.ShowHistory(arg ~= "" and arg or UnitName("player"))

    elseif cmd == "reset" then
        -- Zweistufige Bestätigung
        if GL._resetPending then
            GL._resetPending = false
            GL.ResetRaid()
        else
            GL._resetPending = true
            GL.Print("Reset raid session? Type /reqrt reset again to confirm.")
            C_Timer.After(10, function() GL._resetPending = false end)
        end

    elseif cmd == "ml" then
        local settings = GuildLootDB.settings
        settings.isMasterLooter = not settings.isMasterLooter
        GL.Print("Master Looter: " .. (settings.isMasterLooter and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
        if GL.UI and GL.UI.RefreshMLButton then GL.UI.RefreshMLButton() end

    elseif cmd == "simitem" then
        -- Simuliert ITEM_ON vom ML: erstes equippables Item aus den Taschen
        local simLink, simCat
        for bag = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.hyperlink then
                    local _, _, _, _, _, _, subType, _, equipLoc = GetItemInfo(info.hyperlink)
                    if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" then
                        simLink = info.hyperlink
                        simCat  = GL.CategorizeItem and GL.CategorizeItem(info.hyperlink, equipLoc, subType) or "other"
                        break
                    end
                end
            end
            if simLink then break end
        end
        if simLink and GL.UI and GL.UI.ShowPlayerPopup then
            if GL.PopupFilterMatches and not GL.PopupFilterMatches(simLink, simCat, true) then
                GL.Print("|cffff4444Item vom Announce-Filter geblockt: " .. simLink .. "|r")
            else
                GL.UI.ShowPlayerPopup(simLink, simCat)
                GL.Print("Simulated ITEM_ON (Popup): " .. simLink .. " [" .. (simCat or "?") .. "]")
            end
        else
            GL.Print("|cffff4444Kein equippables Item in den Taschen gefunden.|r")
        end

    elseif cmd == "playermode" then
        local s = GuildLootDB.settings
        s.forcePlayerMode = not s.forcePlayerMode
        GL.Print("Player Mode (Force): " .. (s.forcePlayerMode and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
        if GL.UI and GL.UI.ToggleMinimize then
            -- Fenster kurz neu öffnen damit die Weiche greift
            if not GuildLootDB.settings.minimized then
                GL.UI.Dock()
                GL.UI.Undock()
            end
        end

    elseif cmd == "test" then
        if GL.Test and GL.Test.AddPendingItem then
            GL.Test.AddPendingItem()
        else
            GL.Print("Test mode not loaded.")
        end

    elseif cmd == "testprio" then
        if GL.Test and GL.Test.SimulatePrio then
            GL.Test.SimulatePrio()
        else
            GL.Print("Test mode not loaded.")
        end

    elseif cmd == "testroll" then
        if GL.Test and GL.Test.SimulateRoll then
            GL.Test.SimulateRoll()
        else
            GL.Print("Test mode not loaded.")
        end

    elseif cmd == "testentry" then
        if GL.Test and GL.Test.AddLootEntry then
            GL.Test.AddLootEntry()
        else
            GL.Print("Test mode not loaded.")
        end

    elseif cmd == "testmulti" then
        if GL.Test and GL.Test.SimulateMultiRoll then
            GL.Test.SimulateMultiRoll(arg ~= "" and arg or nil)
        else
            GL.Print("Test mode not loaded.")
        end

    elseif cmd == "testsetup" then
        if GL.Test and GL.Test.SetupTestSession then
            GL.Test.SetupTestSession()
        else
            GL.Print("Test mode not loaded.")
        end

    elseif cmd == "testunassigned" then
        if GL.Test and GL.Test.AddUnassignedRaid then
            GL.Test.AddUnassignedRaid()
        else
            GL.Print("Test mode not loaded.")
        end

    elseif cmd == "simraidstart" then
        GL.OnCommRaidStart("Battle of Dazar'alor (Test)", "H", "test1234", time(), "FakeML")
        GL.Print("Simulated RAID_START from FakeML.")

    elseif cmd == "simraidend" then
        local rid = GuildLootDB.currentRaid.id
        GL.OnCommRaidEnd(rid)
        GL.Print("Simulated RAID_END for id=" .. (rid or "?"))

    elseif cmd == "simmlrequest" then
        GL.OnCommMLRequest("FakeObs1", "FakeObs1")
        GL.Print("Simulated ML_REQUEST from FakeObs1.")

    elseif cmd == "simmlannounce" then
        GL.OnCommMLAnnounce("FakeML2")
        GL.Print("Simulated ML_ANNOUNCE: FakeML2 ist jetzt ML.")

    elseif cmd == "simraidquery" then
        GL.OnCommRaidQuery(UnitName("player") or "")
        GL.Print("Simulated RAID_QUERY (als eigener Sender).")

    elseif cmd == "loopback" then
        local s = GuildLootDB.settings
        s.commLoopback = not s.commLoopback
        GL.Print("Comm Loopback: " .. (s.commLoopback and "|cff00ff00ON|r" or "|cffff4444OFF|r"))

    elseif cmd == "devmode" then
        local s = GuildLootDB.settings
        s.devMode = not s.devMode
        GL.Print("Dev Mode: " .. (s.devMode and "|cff00ff00ON|r (WoWUnit-Tests aktiv nach /reload)|r" or "|cffff4444OFF|r"))

    elseif cmd == "cleanup" then
        local history = GuildLootDB.raidHistory or {}
        local removed = 0
        for i = #history, 1, -1 do
            local snap = history[i]
            if not snap.id or snap.id == "" then
                table.remove(history, i)
                removed = removed + 1
            end
        end
        local raid = GuildLootDB.currentRaid
        local currentReset = 0
        if not raid.id or raid.id == "" then
            GL.ResetRaid()
            currentReset = 1
        end
        GL.Print(string.format("Cleanup done: %d history raid(s) removed, %s.", removed, currentReset == 1 and "active raid reset (no ID)" or "active raid kept"))
        if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end

    elseif cmd == "backup" then
        if not GuildLootDBBackup or not GuildLootDBBackup.savedAt then
            GL.Print("Kein Backup vorhanden.")
        else
            local loot = 0
            for _, s in ipairs(GuildLootDBBackup.raidContainers or {}) do
                loot = loot + #(s.lootLog or {})
            end
            GL.Print(string.format("Backup vom %s: %d Sessions, %d Loot-Einträge, %d unassigned",
                date("%d.%m.%Y %H:%M", GuildLootDBBackup.savedAt),
                #(GuildLootDBBackup.raidContainers or {}),
                loot,
                #(GuildLootDBBackup.unassignedRaids or {})))
            GL.Print("Zum Wiederherstellen: /reqrt restore")
        end

    elseif cmd == "restore" then
        if not GuildLootDBBackup or not GuildLootDBBackup.savedAt then
            GL.Print("Kein Backup vorhanden.")
        elseif GL._restorePending then
            GL._restorePending = false
            GuildLootDB.raidContainers  = CopyTable(GuildLootDBBackup.raidContainers or {})
            GuildLootDB.unassignedRaids = CopyTable(GuildLootDBBackup.unassignedRaids or {})
            GuildLootDB.raidHistory     = CopyTable(GuildLootDBBackup.raidHistory or {})
            GuildLootDB.activeContainerIdx = nil
            GL.ResetCurrentRaid()
            GL.Print("|cff00ff00Backup wiederhergestellt.|r Bitte /reload ausführen.")
            if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
        else
            GL._restorePending = true
            GL.Print("Backup wiederherstellen? /reqrt restore nochmal eingeben (10s).")
            C_Timer.After(10, function() GL._restorePending = false end)
        end

    elseif cmd == "dbinfo" then
        local db = GuildLootDB
        GL.Print(string.format("Sessions: %d | activeIdx: %s | unassigned: %d | raidHistory: %d",
            #(db.raidContainers or {}),
            tostring(db.activeContainerIdx),
            #(db.unassignedRaids or {}),
            #(db.raidHistory or {})))
        for i, s in ipairs(db.raidContainers or {}) do
            local raidCount = 0; for _ in pairs(s.raidMeta or {}) do raidCount = raidCount + 1 end
            GL.Print(string.format("  [%d] %s  raids:%d  loot:%d  closed:%s",
                i, s.label or "?", raidCount, #(s.lootLog or {}),
                s.closedAt and date("%d.%m.%Y", s.closedAt) or "nein"))
        end
        for i, snap in ipairs(db.unassignedRaids or {}) do
            GL.Print(string.format("  unassigned[%d] %s  loot:%d",
                i, snap.tier or "?", #(snap.lootLog or {})))
        end

    else
        GL.Print("Commands: /reqrt | /reqrt start [tier] | /reqrt history [name] | /reqrt reset | /reqrt ml | /reqrt backup | /reqrt restore | /reqrt dbinfo | /reqrt cleanup | /reqrt test")
    end
end
