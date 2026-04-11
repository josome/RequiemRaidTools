-- GuildLoot – Core.lua
-- Namespace, SavedVariables, Events, Slash-Commands, Roster-Verwaltung

GuildLoot = GuildLoot or {}
local GL = GuildLoot

-- ============================================================
-- Default-Struktur
-- ============================================================

local DB_DEFAULTS = {
    players     = {},
    raidHistory = {},
    lastLogout  = 0,
    currentRaid = {
        active       = false,
        id           = "",
        startedAt    = 0,
        resumed      = false,
        tier         = "",
        difficulty   = "",
        mlName       = "",
        participants = {},
        absent       = {},
        lootLog         = {},
        pendingLoot     = {},
        trashedLoot     = {},
        sessionHidden           = {},
        sessionChecked          = {},
        currentKillParticipants = {},
    },
    settings = {
        postToChat     = true,
        chatChannel    = "AUTO",   -- "AUTO", "RAID", "PARTY", "OFF"
        isMasterLooter = false,
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
        filterNonEquip   = true,
        filterCategories = {
            weapons  = true,
            trinket  = true,
            setItems = true,
            other    = true,
        },
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

function GL.InitDB()
    if not GuildLootDB then
        GuildLootDB = {}
    end
    DeepMergeDefaults(GuildLootDB, DB_DEFAULTS)
end

function GL.CreatePlayerRecord(name)
    if not GuildLootDB.players[name] then
        GuildLootDB.players[name] = DefaultPlayerRecord()
    end
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
        else return end
    end
    SendChatMessage("[ReqRT] " .. msg, channel)
end

function GL.PostRaidWarn(msg)
    if not GuildLootDB.settings.raidWarnItem then
        GL.PostToRaid(msg)
        return
    end
    if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
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
    if not raid.active then return end

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
    local mapInfo = C_Map.GetMapInfo(C_Map.GetBestMapForUnit("player"))
    local zoneName = (mapInfo and mapInfo.name and mapInfo.name ~= "") and mapInfo.name or GetRealZoneText()
    if zoneName and zoneName ~= "" then
        return zoneName .. " (" .. date("%d.%m.%Y") .. ")"
    end
    return date("%d.%m.%Y")
end

function GL.StartRaid(tier)
    local raid = GuildLootDB.currentRaid

    if raid.active then
        -- Noch nicht verteilte Items in den lootLog des laufenden Raids sichern
        local ts = time()
        for _, item in ipairs(raid.pendingLoot or {}) do
            table.insert(raid.lootLog, {
                player     = "",
                item       = item.link,
                link       = item.link,
                category   = item.category,
                difficulty = raid.difficulty,
                timestamp  = ts,
                pending    = true,
            })
        end
        GL.CloseRaid()
    else
        raid.pendingLoot = {}
    end

    raid.active     = true
    raid.resumed    = false
    raid.tier       = (tier and tier ~= "") and tier or AutoTierName()
    raid.difficulty = GL.DetectDifficulty() or ""
    raid.startedAt  = time()
    raid.id         = GL.GenerateRaidID(raid.tier, raid.difficulty, raid.startedAt)
    raid.lootLog    = {}
    GL.LoadRaidRoster()
    raid.mlName = NormalizeName(UnitName("player")) or ""
    GuildLootDB.settings.isMasterLooter = true
    GL.Print("Raid started: " .. raid.tier .. ". " .. #raid.participants .. " players loaded.")
    if GL.Comm and GL.Comm.SendRaidStart then
        local s = GuildLootDB.settings
        GL.Comm.SendRaidStart(raid.tier, raid.difficulty, raid.id, raid.startedAt, UnitName("player"),
                              s.minQuality, s.prioSeconds, s.rollSeconds)
    end
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
    if GL.UI and GL.UI.ShowTab then GL.UI.ShowTab(GL.UI.TAB_LOOT) end
end

function GL.CloseRaid()
    local raid = GuildLootDB.currentRaid
    if not raid.active then return end
    -- Snapshot in History speichern
    local snapshot = {
        id           = raid.id,
        startedAt    = raid.startedAt,
        tier         = raid.tier,
        difficulty   = raid.difficulty,
        participants = raid.participants,
        lootLog      = raid.lootLog,
        pendingLoot  = raid.pendingLoot,
        trashedLoot  = raid.trashedLoot,
        closedAt     = time(),
    }
    if not GuildLootDB.raidHistory then GuildLootDB.raidHistory = {} end
    table.insert(GuildLootDB.raidHistory, snapshot)
    -- currentRaid zurücksetzen
    raid.active                  = false
    raid.id                      = ""
    raid.startedAt               = 0
    raid.resumed                 = false
    raid.tier                    = ""
    raid.difficulty              = ""
    raid.participants            = {}
    raid.absent                  = {}
    raid.lootLog                 = {}
    raid.pendingLoot             = {}
    raid.sessionHidden           = {}
    raid.sessionChecked          = {}
    raid.currentKillParticipants = {}
    if GL.Loot and GL.Loot.ClearCurrentItem then GL.Loot.ClearCurrentItem() end
    GL.Print("Raid ended and saved (" .. #snapshot.lootLog .. " loot entries).")
    if GL.Comm and GL.Comm.SendRaidEnd then
        GL.Comm.SendRaidEnd(snapshot.id)
    end
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

-- ============================================================
-- Observer-Handler (empfangen Comm-Nachrichten vom ML)
-- ============================================================

function GL.OnCommRaidStart(tier, difficulty, id, startedAt, sender, mlName, minQuality, prioSeconds, rollSeconds)
    if GL.IsMasterLooter() then
        -- Prüfen ob die Nachricht vom eigenen Client stammt (Self-Filter-Fallback).
        -- Beide Seiten nutzen NormalizeName → gleiche Formatierung → zuverlässiger Vergleich
        -- auch wenn WoW-Sender und GetRealmName() unterschiedliche Realm-Schreibweisen liefern.
        local myNormalName = GL.NormalizeName(UnitName("player") or "") or ""
        local senderML     = GL.NormalizeName(mlName or "") or ""
        if senderML == myNormalName then
            -- Eigene RAID_START-Broadcast empfangen (Self-Filter in Comm hat versagt) → ignorieren
            return
        end
        -- Jemand anderes sendet RAID_START → er ist der aktuelle ML, wir wurden abgelöst
        GuildLootDB.settings.isMasterLooter = false
        GL._pendingMLClaim = nil
        if GL._mlClaimTimer then GL._mlClaimTimer:Cancel(); GL._mlClaimTimer = nil end
        if GL.UI and GL.UI.RefreshMLButton then GL.UI.RefreshMLButton() end
        -- kein return → Raid-State normal synchronisieren
    end
    local raid = GuildLootDB.currentRaid
    -- Gleicher Raid bereits aktiv → nur Roster neu laden (Late-Joiner-Refresh)
    if raid.active and raid.id == id then
        GL.LoadRaidRoster()
        if GL.UI and GL.UI.RefreshSessionBar then GL.UI.RefreshSessionBar() end
        return
    end
    -- Resume-Fall: eigenen History-Snapshot mit gleicher ID suchen und lootLog wiederherstellen
    local restoredLog = {}
    local histIdx = nil
    local history = GuildLootDB.raidHistory or {}
    for i, snap in ipairs(history) do
        if snap.id == id then
            restoredLog = snap.lootLog or {}
            histIdx = i
            break
        end
    end
    raid.active      = true
    raid.tier        = tier or ""
    raid.difficulty  = difficulty or ""
    raid.id          = id or ""
    raid.startedAt   = startedAt or 0
    raid.resumed     = (histIdx ~= nil)
    -- mlName explizit aus Nachricht bevorzugen, sender als Fallback
    raid.mlName      = (mlName and mlName ~= "") and mlName or NormalizeName(sender) or ""
    raid.lootLog     = restoredLog
    raid.pendingLoot = {}
    if histIdx then
        table.remove(history, histIdx)
    end
    GL.LoadRaidRoster()
    -- Settings des ML übernehmen (nur gültige Werte)
    local s = GuildLootDB.settings
    if minQuality and (minQuality == 3 or minQuality == 4 or minQuality == 5) then
        s.minQuality = minQuality
    end
    if prioSeconds and prioSeconds >= 5 and prioSeconds <= 120 then
        s.prioSeconds = prioSeconds
    end
    if rollSeconds and rollSeconds >= 5 and rollSeconds <= 120 then
        s.rollSeconds = rollSeconds
    end
    if histIdx then
        GL.Print("Raid resumed from ML: " .. (tier or "?") .. " (" .. #restoredLog .. " loot entries restored).")
    else
        GL.Print("Raid synced from ML: " .. (tier or "?"))
    end
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

function GL.OnCommRaidQuery(sender)
    if not GL.IsMasterLooter() then return end
    local raid = GuildLootDB.currentRaid
    if not raid.active then return end
    local s = GuildLootDB.settings
    GL.Comm.SendRaidStart(raid.tier, raid.difficulty, raid.id, raid.startedAt, UnitName("player"),
                          s.minQuality, s.prioSeconds, s.rollSeconds)
end

function GL.OnCommRaidEnd(raidID)
    if GL.IsMasterLooter() then return end
    local raid = GuildLootDB.currentRaid
    if not raid.active or raid.id ~= raidID then return end
    local snapshot = {
        id           = raid.id,
        startedAt    = raid.startedAt,
        tier         = raid.tier,
        difficulty   = raid.difficulty,
        participants = raid.participants,
        lootLog      = raid.lootLog,
        pendingLoot  = {},
        trashedLoot  = {},
        closedAt     = time(),
    }
    if not GuildLootDB.raidHistory then GuildLootDB.raidHistory = {} end
    table.insert(GuildLootDB.raidHistory, snapshot)
    raid.active      = false
    raid.id          = ""
    raid.tier        = ""
    raid.difficulty  = ""
    raid.mlName      = ""
    raid.startedAt   = 0
    raid.lootLog     = {}
    raid.pendingLoot = {}
    raid.participants = {}
    if GL.Loot and GL.Loot.ClearCurrentItem then GL.Loot.ClearCurrentItem() end
    GL.Print("Raid ended by ML and saved locally (" .. #snapshot.lootLog .. " loot entries).")
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
    GL.Print(GL.ShortName(newMLName or "") .. " ist jetzt Master Looter.")
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

function GL.ResumeRaid(idx)
    local history = GuildLootDB.raidHistory
    if not history or not history[idx] then
        GL.Print("Raid not found.")
        return
    end
    if GuildLootDB.currentRaid.active then
        GL.Print("Please end the current raid first (/rlt reset or 'End Raid').")
        return
    end
    local snap = history[idx]
    local raid = GuildLootDB.currentRaid
    raid.active     = true
    raid.id         = snap.id or GL.GenerateRaidID(snap.tier, snap.difficulty, snap.startedAt or snap.closedAt or 0)
    raid.startedAt  = snap.startedAt or 0
    raid.tier       = snap.tier
    raid.difficulty = snap.difficulty
    raid.participants = {}
    for _, p in ipairs(snap.participants or {}) do
        table.insert(raid.participants, p)
        GL.CreatePlayerRecord(p)
    end
    raid.lootLog = {}
    for _, e in ipairs(snap.lootLog or {}) do
        table.insert(raid.lootLog, e)
    end
    raid.absent      = {}
    raid.pendingLoot = {}
    for _, item in ipairs(snap.pendingLoot or {}) do
        table.insert(raid.pendingLoot, item)
    end
    raid.trashedLoot = {}
    for _, item in ipairs(snap.trashedLoot or {}) do
        table.insert(raid.trashedLoot, item)
    end
    raid.resumed                 = true
    raid.mlName                  = NormalizeName(UnitName("player")) or ""
    raid.sessionHidden           = {}
    raid.sessionChecked          = {}
    raid.currentKillParticipants = {}
    table.remove(history, idx)
    GL.Print("Raid resumed: " .. (raid.tier ~= "" and raid.tier or "?")
             .. " (" .. #raid.participants .. " players, " .. #raid.lootLog .. " loot entries restored).")
    if GL.Comm and GL.Comm.SendRaidStart then
        local s = GuildLootDB.settings
        GL.Comm.SendRaidStart(raid.tier, raid.difficulty, raid.id, raid.startedAt, UnitName("player"),
                              s.minQuality, s.prioSeconds, s.rollSeconds)
    end
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
    if GL.UI and GL.UI.ShowTab then GL.UI.ShowTab(GL.UI.TAB_LOOT) end
end

function GL.ResetRaid()
    local raid = GuildLootDB.currentRaid
    raid.active       = false
    raid.id           = ""
    raid.startedAt    = 0
    raid.resumed      = false
    raid.tier         = ""
    raid.difficulty   = ""
    raid.participants = {}
    raid.absent       = {}
    raid.lootLog                = {}
    raid.pendingLoot            = {}
    raid.trashedLoot            = {}
    raid.sessionHidden          = {}
    raid.sessionChecked         = {}
    raid.currentKillParticipants = {}
    if GL.Loot and GL.Loot.ClearCurrentItem then GL.Loot.ClearCurrentItem() end
    GL.Print("Session has been reset.")
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
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("TRADE_SHOW")
eventFrame:RegisterEvent("TRADE_CLOSED")
eventFrame:RegisterEvent("TRADE_ACCEPT_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "RequiemRaidTools" then
            GL.InitDB()
            GL.Print("Loaded. /reqrt to open the main window.")
        end

    elseif event == "PLAYER_LOGIN" then
        -- Auto-Close nach >4h offline
        local db = GuildLootDB
        if db.currentRaid.active and db.lastLogout and db.lastLogout > 0 then
            if (time() - db.lastLogout) > 4 * 3600 then
                GL.Print("Raid automatically ended (>4h offline).")
                GL.CloseRaid()
            end
        end
        if GL.UI and GL.UI.Init then GL.UI.Init() end
        -- Delayed RAID_QUERY: Gruppe/Raid-API ist bei Login noch nicht sofort bereit.
        -- C_Timer stellt sicher, dass GROUP_ROSTER_UPDATE schon gefeuert hat.
        C_Timer.After(3, function()
            local r = GuildLootDB.currentRaid
            if not GL.IsMasterLooter() and not r.active then
                GL._lastRaidQuery = time()
                if GL.Comm and GL.Comm.SendRaidQuery then GL.Comm.SendRaidQuery() end
            end
        end)

    elseif event == "PLAYER_LOGOUT" then
        GuildLootDB.lastLogout = time()
        if GL.UI and GL.UI.SavePosition then GL.UI.SavePosition() end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if GL.UI and GL.UI.OnZoneChanged then GL.UI.OnZoneChanged() end

    elseif event == "TRADE_SHOW" then
        if GL.Loot and GL.Loot.OnTradeShow then GL.Loot.OnTradeShow() end

    elseif event == "TRADE_CLOSED" then
        if GL.Loot and GL.Loot.OnTradeClosed then GL.Loot.OnTradeClosed() end

    elseif event == "TRADE_ACCEPT_UPDATE" then
        local playerAccepted, targetAccepted = ...
        if GL.Loot and GL.Loot.OnTradeAcceptUpdate then
            GL.Loot.OnTradeAcceptUpdate(playerAccepted, targetAccepted)
        end

    elseif event == "RAID_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
        GL.SyncRoster()
        -- Late-Joiner: aktiven Raid-State an Gruppe broadcasten (ML-Push)
        local _raid = GuildLootDB.currentRaid
        if _raid.active and GL.IsMasterLooter() and GL.Comm and GL.Comm.SendRaidStart then
            local s = GuildLootDB.settings
            GL.Comm.SendRaidStart(_raid.tier, _raid.difficulty, _raid.id, _raid.startedAt, UnitName("player"),
                                  s.minQuality, s.prioSeconds, s.rollSeconds)
        end
        -- Observer ohne aktiven Raid → aktiv nach Raid fragen (max. 1x alle 5s)
        if not GL.IsMasterLooter() and not _raid.active then
            local now = time()
            if not GL._lastRaidQuery or (now - GL._lastRaidQuery) > 5 then
                GL._lastRaidQuery = now
                if GL.Comm and GL.Comm.SendRaidQuery then GL.Comm.SendRaidQuery() end
            end
        end

    elseif event == "ENCOUNTER_END" then
        -- arg: encounterID, encounterName, difficultyID, groupSize, success
        local encounterName, success = select(2, ...), select(5, ...)
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
                if GL.UI and GL.UI.AutoExpand then GL.UI.AutoExpand() end
            end
        end

    elseif event == "START_LOOT_ROLL" then
        if GL.IsValidZone() and GL.Loot and GL.Loot.OnLootRollStart then
            local rollID = ...
            GL.Loot.OnLootRollStart(rollID)
        end

    elseif event == "LOOT_OPENED" then
        if GL.IsValidZone() and GL.Loot and GL.Loot.OnLootOpened then GL.Loot.OnLootOpened() end

    elseif event == "LOOT_SLOT_CHANGED" then
        -- In Group Loot kommen Items asynchron nach LOOT_OPENED
        -- OnLootOpened erneut aufrufen – Dedup verhindert doppelte Einträge
        if GL.IsValidZone() and GL.Loot and GL.Loot.OnLootOpened then GL.Loot.OnLootOpened() end

    elseif event == "LOOT_CLOSED" then
        if GL.IsValidZone() and GL.Loot and GL.Loot.OnLootClosed then GL.Loot.OnLootClosed() end

    elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER"
        or event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER"
        or event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
        if GL.IsValidZone() then
            local msg, sender = ...
            if GL.Loot and GL.Loot.OnChatMessage then GL.Loot.OnChatMessage(msg, sender) end
        end

    elseif event == "CHAT_MSG_SYSTEM" then
        if GL.IsValidZone() then
            local msg = ...
            if GL.Loot and GL.Loot.OnSystemMessage then GL.Loot.OnSystemMessage(msg) end
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix == "RequiemRLT" and GL.Comm and GL.Comm.OnMessage then
            GL.Comm.OnMessage(msg, sender)
        end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if success and GL.Loot and GL.Loot.OnItemInfoReceived then
            GL.Loot.OnItemInfoReceived(itemID)
        end
    end
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
            GL.Print("Reset raid session? Type /rlt reset again to confirm.")
            C_Timer.After(10, function() GL._resetPending = false end)
        end

    elseif cmd == "ml" then
        local settings = GuildLootDB.settings
        settings.isMasterLooter = not settings.isMasterLooter
        GL.Print("Master Looter: " .. (settings.isMasterLooter and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
        if GL.UI and GL.UI.RefreshMLButton then GL.UI.RefreshMLButton() end

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

    else
        GL.Print("Commands: /rlt | /rlt start [tier] | /rlt history [name] | /rlt reset | /rlt ml | /rlt cleanup | /rlt test | /rlt testprio | /rlt testroll | /rlt testentry")
    end
end
