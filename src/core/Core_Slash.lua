-- GuildLoot – Core_Slash.lua
-- Slash-Commands /reqrt und /requiemraidtools mit Sub-Command-Dispatcher.
-- Lädt zuletzt im Core-Bundle (nach Core_Events.lua), greift auf alle
-- GL.*-Funktionen der vorher geladenen Module zu.

GuildLoot = GuildLoot or {}
local GL = GuildLoot

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

    elseif cmd == "names" then
        GL.PrintNameVariants(arg)

    elseif cmd == "realms" then
        GL.PrintRealmSpread()

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

    elseif cmd == "testwin" then
        -- Gewinner-Anzeige (Glanz-Puls + Sound + 6s-Auto-Close) ohne echten ASSIGN auslösen.
        -- Ungated (kein devMode nötig), damit der Effekt ohne Taint-Risiko testbar ist.
        if GL.UI and GL.UI.ShowPlayerPopupWin then
            GL.UI.ShowPlayerPopupWin("|cffa335ee|Hitem:18832::::::::70:::::|h[Brutality Blade]|h|r")
        else
            GL.Print("UI not loaded.")
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
