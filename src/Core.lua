-- GuildLoot – Core.lua
-- Event-Handler und Slash-Commands.
-- (DB lebt in src/core/Core_DB.lua, Session-Lifecycle/Comm-Handler/Roster
--  in src/core/Core_Session.lua, seit Welle 6.)

GuildLoot = GuildLoot or {}
local GL = GuildLoot

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

-- Alias für lokale Nutzung in Event-Handlern (Roster-Vergleiche)
local NormalizeName = function(name) return GL.NormalizeName(name) end

-- AutoTierName ist file-local in Core_Session.lua; hier brauchen wir einen Helper.
-- Wir nutzen dieselbe Logik wie dort (zentralisiert via lokale Funktion).
local function AutoTierName()
    local instanceName, instanceType = GetInstanceInfo()
    if instanceName and instanceName ~= "" and instanceType ~= "none" then
        return instanceName .. " (" .. date("%d.%m.%Y") .. ")"
    end
    local bestMap = C_Map.GetBestMapForUnit("player")
    local mapInfo = bestMap and C_Map.GetMapInfo(bestMap)
    local zoneName = (mapInfo and mapInfo.name and mapInfo.name ~= "") and mapInfo.name or GetRealZoneText()
    if zoneName and zoneName ~= "" then
        return zoneName .. " (" .. date("%d.%m.%Y") .. ")"
    end
    return date("%d.%m.%Y")
end

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
                    GL.Comm.SendSessionStart(session.id, session.label, session.startedAt, session.priorityConfig)
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
            if GL.Comm and GL.Comm.SendMLAnnounce then
                GL.Comm.SendMLAnnounce(UnitName("player") or "")
            end
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

    elseif cmd == "popup" then
        if GL.UI and GL.UI.ShowPlayerPopupFilterOnly then
            GL.UI.ShowPlayerPopupFilterOnly()
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

    elseif cmd == "testpending" then
        if GL.Test and GL.Test.SimulatePending then
            GL.Test.SimulatePending(arg ~= "" and arg or nil)
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
