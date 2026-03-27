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
        tier         = "",
        difficulty   = "",
        participants = {},
        absent       = {},
        lootLog         = {},
        pendingLoot     = {},
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
        raidWarnItem = true,
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
    print("|cff00ccff[RLT]|r " .. tostring(msg))
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
    SendChatMessage("[RLT] " .. msg, channel)
end

function GL.PostRaidWarn(msg)
    if not GuildLootDB.settings.raidWarnItem then
        GL.PostToRaid(msg)
        return
    end
    if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
        SendChatMessage("[RLT] " .. msg, "RAID_WARNING")
    else
        GL.PostToRaid(msg)
    end
end

-- ============================================================
-- Roster-Verwaltung
-- ============================================================

local function NormalizeName(name)
    if name and not name:find("-") then
        local realm = GetRealmName()
        if realm then name = name .. "-" .. realm end
    end
    return name
end

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
    local instanceName, instanceType = GetInstanceInfo()
    if instanceType == "raid" or instanceType == "party" then
        return instanceName .. " (" .. date("%d.%m.%Y") .. ")"
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
    raid.lootLog    = {}
    GL.LoadRaidRoster()
    GL.Print("Raid started: " .. raid.tier .. ". " .. #raid.participants .. " players loaded.")
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

function GL.CloseRaid()
    local raid = GuildLootDB.currentRaid
    if not raid.active then return end
    -- Snapshot in History speichern
    local snapshot = {
        tier         = raid.tier,
        difficulty   = raid.difficulty,
        participants = raid.participants,
        lootLog      = raid.lootLog,
        pendingLoot  = raid.pendingLoot,
        closedAt     = time(),
    }
    if not GuildLootDB.raidHistory then GuildLootDB.raidHistory = {} end
    table.insert(GuildLootDB.raidHistory, snapshot)
    -- currentRaid zurücksetzen
    raid.active                  = false
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
    raid.resumed                 = true
    raid.sessionHidden           = {}
    raid.sessionChecked          = {}
    raid.currentKillParticipants = {}
    table.remove(history, idx)
    GL.Print("Raid resumed: " .. (raid.tier ~= "" and raid.tier or "?")
             .. " (" .. #raid.participants .. " players, " .. #raid.lootLog .. " loot entries restored).")
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

function GL.ResetRaid()
    local raid = GuildLootDB.currentRaid
    raid.active       = false
    raid.resumed      = false
    raid.tier         = ""
    raid.difficulty   = ""
    raid.participants = {}
    raid.absent       = {}
    raid.lootLog                = {}
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
eventFrame:RegisterEvent("CHAT_MSG_RAID")
eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_PARTY")
eventFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT")
eventFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "RaidLootTracker" then
            GL.InitDB()
            GL.Print("Loaded. /rlt to open the main window.")
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

    elseif event == "PLAYER_LOGOUT" then
        GuildLootDB.lastLogout = time()
        if GL.UI and GL.UI.SavePosition then GL.UI.SavePosition() end

    elseif event == "RAID_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
        GL.SyncRoster()

    elseif event == "ENCOUNTER_END" then
        -- arg: encounterID, encounterName, difficultyID, groupSize, success
        local success = select(5, ...)
        if success == 1 then
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

    elseif event == "LOOT_OPENED" then
        if GL.Loot and GL.Loot.OnLootOpened then GL.Loot.OnLootOpened() end

    elseif event == "LOOT_SLOT_CHANGED" then
        -- In Group Loot kommen Items asynchron nach LOOT_OPENED
        -- OnLootOpened erneut aufrufen – Dedup verhindert doppelte Einträge
        if GL.Loot and GL.Loot.OnLootOpened then GL.Loot.OnLootOpened() end

    elseif event == "LOOT_CLOSED" then
        if GL.Loot and GL.Loot.OnLootClosed then GL.Loot.OnLootClosed() end

    elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER"
        or event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER"
        or event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
        local msg, sender = ...
        if GL.Loot and GL.Loot.OnChatMessage then GL.Loot.OnChatMessage(msg, sender) end

    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = ...
        if GL.Loot and GL.Loot.OnSystemMessage then GL.Loot.OnSystemMessage(msg) end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix == "RLT" and GL.Comm and GL.Comm.OnMessage then
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

SLASH_RAIDLOOTTRACKER1 = "/rlt"
SLASH_RAIDLOOTTRACKER2 = "/raidloottracker"
SlashCmdList["RAIDLOOTTRACKER"] = function(input)
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

    elseif cmd == "testroll" then
        if GL.Test and GL.Test.SimulateRoll then
            GL.Test.SimulateRoll()
        else
            GL.Print("Test mode not loaded.")
        end

    else
        GL.Print("Commands: /rlt | /rlt start [tier] | /rlt history [name] | /rlt reset | /rlt ml | /rlt test | /rlt testroll")
    end
end
