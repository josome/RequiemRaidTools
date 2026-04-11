-- RequiemRaidTools – Loot_Assign.lua
-- Item-Freigabe (ReleaseItem/ActivateItem), Zuweisung (AssignLoot/AssignLootConfirm),
-- Observer-Handler für Item-Activate/Clear/Assign

local GL   = GuildLoot
local Loot = GL.Loot

-- Referenz auf gemeinsamen currentItem-Zustand (gleiche Tabelle wie in Loot.lua)
local currentItem = Loot.GetCurrentItem()

-- Item das noch auf GetItemInfo wartet (modul-lokal, nur hier benötigt)
local pendingActivation = nil

-- ============================================================
-- Item freigeben (ML klickt Item-Button)
-- ============================================================

function Loot.ReleaseItem(itemLink)
    if not GL.IsMasterLooter() then
        GL.Print("|cffff4444Release failed:|r ML checkbox not enabled.")
        return
    end
    if not GuildLootDB.currentRaid.active then
        GL.Print("|cffff4444Release failed:|r No active raid. Press 'Start Raid' first.")
        return
    end

    -- Laufenden Roll abbrechen falls vorhanden
    if currentItem.rollState.active then
        Loot.CancelRoll()
    end

    -- Item-Infos laden
    local name, link, quality, iLevel, _, _, _, _, equipLoc, _, _, _, _ = GetItemInfo(itemLink)
    if not name then
        -- Deferred: warten auf GET_ITEM_INFO_RECEIVED
        pendingActivation = itemLink
        return
    end

    Loot.ActivateItem(itemLink, name, iLevel, equipLoc, quality)
end

function Loot.OnItemInfoReceived(itemID)
    -- Handle pendingActivation (ReleaseItem deferred)
    if pendingActivation then
        local storedID = tonumber(pendingActivation:match("item:(%d+)"))
        if storedID == itemID then
            local name, link, quality, iLevel, _, _, _, _, equipLoc = GetItemInfo(pendingActivation)
            if name then
                local savedLink = pendingActivation
                pendingActivation = nil
                Loot.ActivateItem(savedLink, name, iLevel, equipLoc, quality)
            end
        end
    end

    -- Handle deferred pending items (OnLootOpened / OnLootRollStart / AddItemManually)
    local refreshNeeded = false
    for i = #Loot._deferredPendingItems, 1, -1 do
        local di = Loot._deferredPendingItems[i]
        if di.itemID == itemID then
            local name, _, quality, _, _, _, _, _, equipLoc = GetItemInfo(di.link)
            if equipLoc ~= nil then
                if di.manual then
                    local category = GL.GetItemCategory(di.itemID, equipLoc, quality or 0)
                    table.insert(Loot.GetPendingLoot(), { link = di.link, name = name or "?", itemID = di.itemID, quality = quality or 0, category = category })
                    GL.Print("Item manuell hinzugefügt: " .. di.link)
                else
                    Loot.TryAddPendingItem(di, equipLoc)
                end
                table.remove(Loot._deferredPendingItems, i)
                refreshNeeded = true
            end
        end
    end
    if refreshNeeded and GL.UI and GL.UI.RefreshLootTab then
        GL.UI.RefreshLootTab()
    end
end

function Loot.ActivateItem(link, name, iLevel, equipLoc, quality)
    local itemID = tonumber(link:match("item:(%d+)"))

    -- Laufende Timer canceln bevor currentItem überschrieben wird
    if currentItem.prioState and currentItem.prioState.timer then
        currentItem.prioState.timer:Cancel()
    end
    if currentItem.rollState and currentItem.rollState.timer then
        currentItem.rollState.timer:Cancel()
    end

    currentItem.link       = link
    currentItem.name       = name
    currentItem.itemID     = itemID
    currentItem.itemLevel  = iLevel
    currentItem.quality    = quality or 0
    currentItem.category   = GL.GetItemCategory(itemID, equipLoc or "", quality or 0)
    currentItem.candidates = {}
    currentItem.winner     = nil
    currentItem.winners    = {}
    currentItem._tieReRoll = nil
    currentItem.prioState  = { active=false, timeLeft=0, timer=nil }
    currentItem.rollState  = { active=false, players={}, results={}, timer=nil, timeLeft=0 }

    -- Anzahl der Kopien dieses Items in pendingLoot ermitteln (per itemID)
    local copyCount = 0
    for _, p in ipairs(Loot.GetPendingLoot()) do
        local pid = tonumber(p.link:match("item:(%d+)"))
        if pid == itemID then copyCount = copyCount + 1 end
    end
    currentItem.count = (copyCount > 0) and copyCount or 1

    -- Prio-Sammel-Timer starten
    local prioSecs = GuildLootDB.settings.prioSeconds or 15
    local warnPrefix = (currentItem.count > 1) and (currentItem.count .. "x ") or ""
    GL.PostRaidWarn(warnPrefix .. "Loot: " .. link .. " -- Post your prio (" .. prioSecs .. " sec): 1=BIS, 2=OS, 4=Transmog")
    currentItem.prioState.active   = true
    currentItem.prioState.timeLeft = prioSecs
    currentItem.prioState.timer = C_Timer.NewTicker(1, function()
        currentItem.prioState.timeLeft = currentItem.prioState.timeLeft - 1
        if GL.UI and GL.UI.RefreshPrioCountdown then
            GL.UI.RefreshPrioCountdown(currentItem.prioState.timeLeft)
        end
        if currentItem.prioState.timeLeft <= 0 then
            if currentItem.prioState.timer then
                currentItem.prioState.timer:Cancel()
                currentItem.prioState.timer = nil
            end
            currentItem.prioState.active = false
            Loot.StartRoll()
        end
    end, prioSecs)

    -- Observer informieren
    if GL.Comm then GL.Comm.SendItemActivate(link, currentItem.category) end

    if GL.UI then
        if GL.UI.RefreshCandidates  then GL.UI.RefreshCandidates()  end
        if GL.UI.RefreshRollResults then GL.UI.RefreshRollResults() end
        if GL.UI.RefreshLootTab     then GL.UI.RefreshLootTab()     end
    end
end

-- ============================================================
-- Zuweisung
-- ============================================================

function Loot.AssignLoot(recipientShortName)
    if not GL.IsMasterLooter() then return end
    if not currentItem.link then return end
    if not recipientShortName then return end

    -- Vollständigen Namen finden
    local fullName = nil
    for _, name in ipairs(GuildLootDB.currentRaid.participants) do
        if GL.ShortName(name) == recipientShortName or name == recipientShortName then
            fullName = name
            break
        end
    end
    -- Fallback: Kurzname als Key
    if not fullName then fullName = recipientShortName end

    -- Difficulty ermitteln
    local diff = GL.DetectDifficulty()
    if not diff then
        -- UI zeigt Popup → wird in UI.lua behandelt
        -- AssignLootConfirm wird danach aufgerufen
        if GL.UI and GL.UI.ShowDifficultyPopup then
            GL.UI.ShowDifficultyPopup(fullName)
        end
        return
    end

    Loot.AssignLootConfirm(fullName, diff)
end

-- clearAfter: ob currentItem nach Zuweisung geleert wird (default true; false bei Multi-Assign)
function Loot.AssignLootConfirm(fullName, diff, clearAfter)
    if not fullName then GL.Print("Fehler: kein Spielername bei Zuweisung"); return end
    if clearAfter == nil then clearAfter = true end
    local category = currentItem.category or "other"
    local link     = currentItem.link
    local itemID   = currentItem.itemID
    local ts       = GL.GetTimestamp()

    -- Prio des Gewinners aus der Kandidaten-Liste (key ist realm-qualifiziert, Fallback auf ShortName)
    local winnerPrio = (currentItem.candidates[fullName] or currentItem.candidates[GL.ShortName(fullName)] or {}).prio

    -- DB-Eintrag
    GL.CreatePlayerRecord(fullName)
    local playerData = GuildLootDB.players[fullName]

    table.insert(playerData.lootHistory, {
        item       = link,
        category   = category,
        difficulty = diff,
        timestamp  = ts,
    })
    playerData.counts[category] = (playerData.counts[category] or 0) + 1
    if category ~= "other" then
        playerData.lastDifficulty[category] = diff
    end

    -- Session-Log
    table.insert(GuildLootDB.currentRaid.lootLog, {
        player     = fullName,
        item       = link,
        link       = link,
        itemID     = currentItem.itemID,
        quality    = currentItem.quality,
        category   = category,
        difficulty = diff,
        winnerPrio = winnerPrio,
        timestamp  = ts,
    })

    -- Raid-Chat
    GL.PostToRaid(GL.ShortName(fullName) .. " receives " .. link .. " - please pick up from the loot master.")

    -- Gewinner anflüstern
    if GuildLootDB.settings.whisperWinner and GL.IsMasterLooter() then
        SendChatMessage("Congratulations! You received " .. link .. " - please pick it up from the loot master.", "WHISPER", nil, GL.NormalizeName(fullName))
    end

    -- Item aus Pending entfernen (per Link; Fallback per itemID für abweichende Tracks)
    local pl = Loot.GetPendingLoot()
    for i, p in ipairs(pl) do
        local pid = tonumber(p.link:match("item:(%d+)"))
        if p.link == link or pid == itemID then
            table.remove(pl, i)
            break
        end
    end

    -- Ausstehenden Handel vormerken (ML legt Item bei nächstem Handel automatisch rein)
    if GL.IsMasterLooter() then
        table.insert(Loot._pendingTrades, { itemID = itemID, shortName = GL.ShortName(fullName) })
    end

    -- Observer informieren (fullName ist bereits realm-qualifiziert)
    if GL.Comm then GL.Comm.SendAssign(fullName, diff, link, category, currentItem.quality) end

    -- Zustand zurücksetzen (nur wenn letzte Zuweisung)
    if clearAfter then
        Loot.ClearCurrentItem()
        if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
    end
end

-- Alle Gewinner (bei Mehrfach-Drop) auf einmal zuweisen
function Loot.AssignAllWinners()
    if not GL.IsMasterLooter() then return end
    local winners = {}
    for _, w in ipairs(currentItem.winners or {}) do
        table.insert(winners, w)  -- Kopie vor Mutation
    end
    if #winners == 0 then return end

    local function doAssign(diff)
        for i, shortName in ipairs(winners) do
            local fullName = shortName
            for _, name in ipairs(GuildLootDB.currentRaid.participants) do
                if GL.ShortName(name) == shortName or name == shortName then
                    fullName = name
                    break
                end
            end
            local isLast = (i == #winners)
            Loot.AssignLootConfirm(fullName, diff, isLast)
        end
        if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
    end

    local diff = GL.DetectDifficulty()
    if not diff then
        -- Difficulty unbekannt (nicht in Instanz) → Popup mit Callback
        if GL.UI and GL.UI.ShowDifficultyPopup then
            GL.UI.ShowDifficultyPopup(nil, doAssign)
        end
        return
    end

    doAssign(diff)
end

function Loot.ClearCurrentItem()
    -- Prio-Timer abbrechen
    if currentItem.prioState.timer then
        currentItem.prioState.timer:Cancel()
        currentItem.prioState.timer = nil
    end
    currentItem.prioState.active   = false
    currentItem.prioState.timeLeft = 0
    Loot.CancelRoll()
    currentItem.link       = nil
    currentItem.name       = nil
    currentItem.itemID     = nil
    currentItem.itemLevel  = nil
    currentItem.category   = nil
    currentItem.candidates = {}
    currentItem.winner     = nil
    currentItem.count      = 1
    currentItem.winners    = {}
    currentItem._tieReRoll = nil
    pendingActivation      = nil
end

-- ============================================================
-- Observer-Handler (empfangen vom ML via Comm.lua)
-- ============================================================

--- ML hat ein Item freigegeben → Observer zeigen es an
function Loot.OnCommItemActivate(link, category)
    if GL.IsMasterLooter() then return end  -- ML hat bereits lokal verarbeitet
    local name   = link:match("%[(.-)%]") or "?"
    local itemID = tonumber(link:match("item:(%d+)")) or 0
    -- Laufende Timer auf Beobachterseite (falls vorhanden) abbrechen
    if currentItem.prioState.timer then currentItem.prioState.timer:Cancel() end
    if currentItem.rollState.timer  then currentItem.rollState.timer:Cancel()  end
    currentItem.link       = link
    currentItem.name       = name
    currentItem.itemID     = itemID
    currentItem.category   = category
    currentItem.candidates = {}
    currentItem.winner     = nil
    currentItem.winners    = {}
    currentItem.count      = 1
    currentItem._tieReRoll = nil
    currentItem.prioState  = { active = true,  timeLeft = 0, timer = nil }
    currentItem.rollState  = { active = false, players  = {}, results = {}, timer = nil, timeLeft = 0 }
    -- Item auch in lokale pendingLoot einfügen damit die Sidebar es anzeigt
    local pl = Loot.GetPendingLoot()
    local found = false
    for _, p in ipairs(pl) do
        if p.link == link then found = true; break end
    end
    if not found then
        table.insert(pl, { link = link, name = name, itemID = itemID, quality = 0, category = category })
    end
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

--- ML hat Item abgebrochen → Observer leeren Anzeige
function Loot.OnCommItemClear()
    if GL.IsMasterLooter() then return end
    -- Item aus lokaler pendingLoot entfernen
    local link = currentItem.link
    if link then
        local pl = Loot.GetPendingLoot()
        for i = #pl, 1, -1 do
            if pl[i].link == link then table.remove(pl, i); break end
        end
    end
    if currentItem.prioState.timer then currentItem.prioState.timer:Cancel() end
    if currentItem.rollState.timer  then currentItem.rollState.timer:Cancel()  end
    currentItem.link       = nil
    currentItem.name       = nil
    currentItem.candidates = {}
    currentItem.winner     = nil
    currentItem.prioState  = { active = false, timeLeft = 0, timer = nil }
    currentItem.rollState  = { active = false, players  = {}, results = {}, timer = nil, timeLeft = 0 }
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

--- ML hat Loot zugewiesen → Observer aktualisieren Session-Log
function Loot.OnCommAssign(playerName, diff, link, category, quality)
    if GL.IsMasterLooter() then return end
    if not playerName or playerName == "" then return end
    -- Name realm-qualifizieren und in participants suchen
    playerName = GL.NormalizeName(playerName) or playerName
    local fullName = playerName
    for _, p in ipairs(GuildLootDB.currentRaid.participants) do
        if p == playerName or GL.ShortName(p) == GL.ShortName(playerName) then
            fullName = p; break
        end
    end
    table.insert(GuildLootDB.currentRaid.lootLog, {
        player     = fullName,
        item       = link or "",
        link       = link or "",
        category   = category or "other",
        quality    = quality or 0,
        difficulty = diff or "",
        timestamp  = time(),
    })
    Loot.OnCommItemClear()
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end
