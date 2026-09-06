-- GuildLoot – Core_DB.lua
-- DB-Initialisierung, Defaults, Migrationen, Backup.
-- Muss VOR Core_Session.lua geladen werden (TOC-Reihenfolge).

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
    -- { [id] = { id, name, startedAt, endedAt, rankFilter={},
    --            roster={{name,class}}, rosterReadAt, rosterFilterKey } }
    -- roster = Kader-Schnappschuss, nur via GL.SnapshotSeasonRoster ("Roster lesen")
    seasons            = {},
    activeSeasonId     = nil,  -- ID der aktiven Season (nil = keine); via GL.CreateSeason gesetzt
    guildRankNames     = {},   -- [rankIndex] = Anzeigename; Fallback wenn Guild-Control schweigt
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
        minQuality     = 4,
        prioSeconds    = 15,
        rollSeconds    = 15,
        -- [key] = { x, y, w, h } je verschiebbarem Fenster; gepflegt von UI_Common.lua
        framePositions = {},
        minimized    = true,
        minimapAngle = 45,
        lastTab      = nil,
        raidWarnItem   = true,
        danceEmptyState = true,
        whisperWinner  = true,
        exportFormat = "JSON",  -- "JSON" | "CSV"
        commLoopback = false,   -- true: eigene Addon-Nachrichten empfangen (nur für Tests)
        devMode      = false,   -- true: Diagnose-Ausgaben aktivieren (/reqrt devmode)
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
        trial          = false, -- dauerhafter Flag, von der Raidleitung manuell entfernt
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

--- Überführt die alten Einzelfelder des Hauptfensters in settings.framePositions.
--- Alle verschiebbaren Fenster teilen sich diese Tabelle; framePos/frameSize kannten
--- nur das Hauptfenster.
--- Reads:  db.settings.framePos, db.settings.frameSize
--- Writes: db.settings.framePositions.main, db.settings.framePos, db.settings.frameSize
function GL.MigrateFramePositions()
    local s = GuildLootDB and GuildLootDB.settings
    if not s then return end
    s.framePositions = s.framePositions or {}
    local old = s.framePos
    -- Einen bereits migrierten Eintrag nicht überschreiben
    if old and not s.framePositions.main then
        local size = s.frameSize or {}
        s.framePositions.main = { x = old.x, y = old.y, w = size.w, h = size.h }
    end
    s.framePos  = nil
    s.frameSize = nil
end

--- Initialisiert GuildLootDB mit Defaults falls Felder fehlen. Einmalig beim Login.
--- Writes: db.players, db.raidContainers, db.activeContainerIdx,
---         db.unassignedRaids, db.currentRaid, db.settings, db.raidHistory
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
    GL.MigrateFramePositions()
    -- Transient: nie aus SavedVariables übernehmen
    GuildLootDB.settings.isMasterLooter = false
    GuildLootDB.settings.dungeonMode    = nil
end

--- Legt einen neuen Spieler-Eintrag an falls noch nicht vorhanden.
--- Reads:  db.players
--- Writes: db.players[name]
function GL.CreatePlayerRecord(name)
    if not GuildLootDB.players[name] then
        GuildLootDB.players[name] = DefaultPlayerRecord()
    end
end

--- Migriert veraltetes db.raidHistory in db.unassignedRaids (einmalig).
--- Reads:  db.raidHistory
--- Writes: db.unassignedRaids, db.raidHistory
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
