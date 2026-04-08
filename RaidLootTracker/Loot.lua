-- GuildLoot – Loot.lua
-- Loot-Erkennung, Chat-Parsing, Roll-Prozess, Zuweisung

GuildLoot = GuildLoot or {}
local GL = GuildLoot
GL.Loot = GL.Loot or {}
local Loot = GL.Loot

-- ============================================================
-- Modul-lokaler Zustand (nicht persistent)
-- ============================================================

-- Offene Handelszuweisungen: { { itemID=N, shortName="X" }, ... }
-- Wird befüllt wenn ML ein Item zuweist; bei TRADE_SHOW abgeglichen.
Loot._pendingTrades = {}

-- pendingLoot wird direkt aus GuildLootDB gelesen (überlebt Reloads)
local function pendingLoot() return GuildLootDB.currentRaid.pendingLoot end
local function trashedLoot() return GuildLootDB.currentRaid.trashedLoot or {} end
local currentItem  = {
    link       = nil,
    name       = nil,
    itemID     = nil,
    itemLevel  = nil,
    category   = nil,
    candidates = {},   -- { [name] = { prio=1 } }
    prioState  = {     -- Prio-Sammelphase
        active   = false,
        timeLeft = 0,
        timer    = nil,
    },
    rollState  = {
        active   = false,
        players  = {},   -- set von Namen die rollen dürfen
        results  = {},   -- { [name] = rollValue }
        timer    = nil,
        timeLeft = 0,
    },
    winner     = nil,
    count      = 1,    -- Anzahl verfügbarer Kopien dieses Items
    winners    = {},   -- { shortName, ... } bei count > 1
    _tieReRoll = nil,  -- { confirmedWinners={}, spotsNeeded=N } während Tie-Re-Roll
}

local function PRIO_SECONDS() return GuildLootDB.settings.prioSeconds or 15 end
local function ROLL_SECONDS() return GuildLootDB.settings.rollSeconds or 15 end

-- Item das noch auf GetItemInfo wartet
local pendingActivation = nil   -- itemLink

-- Items aus OnLootOpened die noch auf GetItemInfo warten
local deferredPendingItems = {}

-- Bereits verarbeitete Roll-IDs (verhindert Doppelverarbeitung bei mehrfachem Event-Fire)
local processedRolls = {}

-- ============================================================
-- Zugriffs-Helfer
-- ============================================================

function Loot.GetPendingLoot()  return pendingLoot()  end
function Loot.GetTrashedLoot()  return trashedLoot()  end
function Loot.GetCurrentItem()  return currentItem  end

-- Prüft Loot-Filter und fügt Item ggf. in pendingLoot ein
function Loot.TryAddPendingItem(item, equipLoc)
    local s = GuildLootDB.settings
    local category = GL.GetItemCategory(item.itemID, equipLoc, item.quality)

    -- Filter: nicht-ausrüstbare Items (Handwerksmaterialien, Reagenzien, etc.)
    if s.filterNonEquip then
        local isEquip = equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
        -- Ausnahme: Class-Tokens haben equipLoc="" sind aber "setItems"
        if not isEquip and category ~= "setItems" then return end
    end

    -- Filter: Kategorie-Filter
    local fc = s.filterCategories
    if fc and fc[category] == false then return end

    item.category = category
    table.insert(pendingLoot(), item)
end

-- ============================================================
-- Loot-Erkennung (LOOT_OPENED)
-- ============================================================

function Loot.OnLootOpened()
    if not GL.IsMasterLooter() then return end  -- Observer ignorieren das Loot-Fenster
    local minQ = GuildLootDB.settings.minQuality or 4

    -- Alle qualifizierten Items aus dem Loot-Fenster sammeln
    local lootItems = {}
    for slot = 1, GetNumLootItems() do
        local _, name, _, _, quality, _, isQuestItem = GetLootSlotInfo(slot)
        if quality and quality >= minQ and not isQuestItem then
            local link = GetLootSlotLink(slot)
            if link then
                local itemID = tonumber(link:match("item:(%d+)"))
                table.insert(lootItems, { link = link, name = name or "?", itemID = itemID, quality = quality })
            end
        end
    end

    -- Wie oft ist jeder Link bereits in pendingLoot?
    local pendingCounts = {}
    for _, p in ipairs(pendingLoot()) do
        pendingCounts[p.link] = (pendingCounts[p.link] or 0) + 1
    end

    -- Nur Items hinzufügen die noch nicht (oder nicht oft genug) in pendingLoot sind
    -- → erlaubt mehrfache Drops desselben Items
    local lootCounts = {}
    local toAdd = {}
    for _, item in ipairs(lootItems) do
        lootCounts[item.link] = (lootCounts[item.link] or 0) + 1
        if lootCounts[item.link] > (pendingCounts[item.link] or 0) then
            table.insert(toAdd, item)
        end
    end

    if #toAdd > 0 then
        for _, item in ipairs(toAdd) do
            local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(item.link)
            if equipLoc ~= nil then
                Loot.TryAddPendingItem(item, equipLoc)
            else
                table.insert(deferredPendingItems, item)
            end
        end
        if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
    end
end

function Loot.OnLootClosed()
    -- pendingLoot einfrieren — Liste bleibt erhalten bis alle Items vergeben sind
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

-- Wird bei START_LOOT_ROLL aufgerufen: erkennt Items aus WoW's Group-Loot-Roll-Fenster
-- und fügt sie zu pendingLoot hinzu — auch wenn der ML die Leiche nie selbst geöffnet hat.
function Loot.OnLootRollStart(rollID)
    if not GL.IsMasterLooter() then return end
    if not GuildLootDB.currentRaid.active then return end
    if processedRolls[rollID] then return end
    processedRolls[rollID] = true

    local link = GetLootRollItemLink(rollID)
    if not link then return end

    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return end

    -- Qualitätsfilter: GetLootRollItemInfo gibt u.a. quality zurück
    local minQ = GuildLootDB.settings.minQuality or 4
    local _, name, _, quality = GetLootRollItemInfo(rollID)
    if not quality or quality < minQ then return end

    -- equipLoc für Kategorie-Erkennung (GetItemInfo ist gecacht wenn Item bekannt)
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    local item = { link = link, name = name or "?", itemID = itemID, quality = quality }

    if equipLoc ~= nil then
        Loot.TryAddPendingItem(item, equipLoc)
    else
        -- GetItemInfo noch nicht verfügbar → deferred (GET_ITEM_INFO_RECEIVED löst aus)
        table.insert(deferredPendingItems, item)
    end

    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

-- ============================================================
-- Item freigeben (LM klickt Item-Button)
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

    -- Handle deferred pending items (OnLootOpened)
    local refreshNeeded = false
    for i = #deferredPendingItems, 1, -1 do
        local di = deferredPendingItems[i]
        if di.itemID == itemID then
            local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(di.link)
            if equipLoc ~= nil then
                Loot.TryAddPendingItem(di, equipLoc)
                table.remove(deferredPendingItems, i)
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
    for _, p in ipairs(pendingLoot()) do
        local pid = tonumber(p.link:match("item:(%d+)"))
        if pid == itemID then copyCount = copyCount + 1 end
    end
    currentItem.count = (copyCount > 0) and copyCount or 1

    -- Prio-Sammel-Timer starten
    local prioSecs = PRIO_SECONDS()
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
-- Chat-Parsing – Bedarfsmeldungen
-- ============================================================

local function IsParticipant(name)
    if not GuildLootDB.currentRaid.active then return false end
    local raid   = GuildLootDB.currentRaid
    local absent = raid.absent
    local short  = GL.ShortName(name)
    -- Loot-Berechtigung: wer beim Kill dabei war (Snapshot)
    -- Fallback auf kumulative Liste wenn noch kein Kill stattfand (z.B. Testmodus)
    local list = (#raid.currentKillParticipants > 0)
                 and raid.currentKillParticipants
                 or  raid.participants
    for _, p in ipairs(list) do
        if p == name or GL.ShortName(p) == short then
            return not absent[p]
        end
    end
    return false
end

function Loot.OnChatMessage(msg, sender)
    if not currentItem.link then return end
    if currentItem.rollState.active then return end  -- Roll läuft, keine neuen Meldungen
    if not IsParticipant(sender) then return end

    local prio = GL.ParseLootInput(msg)
    if not prio then return end

    -- Kandidaten registrieren (Override erlaubt) – immer realm-qualifiziert als Key
    currentItem.candidates[GL.NormalizeName(sender) or sender] = { prio = prio }

    -- RefreshLootTab statt nur RefreshCandidates: aktualisiert auch Button-States (hasCands)
    if GL.UI and GL.UI.RefreshLootTab then
        GL.UI.RefreshLootTab()
    elseif GL.UI and GL.UI.RefreshCandidates then
        GL.UI.RefreshCandidates()
    end
end

-- ============================================================
-- Roll-Freigabe
-- ============================================================

local function GetLowestPrio(candidates)
    local lowest = nil
    for _, data in pairs(candidates) do
        if lowest == nil or data.prio < lowest then
            lowest = data.prio
        end
    end
    return lowest
end

function Loot.StartRoll()
    if not GL.IsMasterLooter() then return end
    if currentItem.rollState.active then return end

    -- Prio-Timer stoppen (falls noch läuft)
    if currentItem.prioState.timer then
        currentItem.prioState.timer:Cancel()
        currentItem.prioState.timer = nil
    end
    currentItem.prioState.active = false

    if not next(currentItem.candidates) then
        GL.Print("No prio submissions received.")
        return
    end

    local needed = currentItem.count  -- Anzahl zu vergebender Kopien

    -- Prio-Tiers (1=BIS, 2=OS, 4=Transmog) der Reihe nach aufzählen
    -- bis genug Spieler für alle Kopien gesammelt sind (Cross-Tier-Logik)
    local rollPlayers = {}
    currentItem.rollState.players = {}
    for _, prio in ipairs({1, 2, 4}) do
        for name, data in pairs(currentItem.candidates) do
            if data.prio == prio then
                local short = GL.ShortName(name)
                table.insert(rollPlayers, short)
                currentItem.rollState.players[short] = true
            end
        end
        if #rollPlayers >= needed then break end
    end

    -- Alle Kandidaten passen auf die Kopien → kein Roll nötig
    if #rollPlayers <= needed then
        currentItem.winners = rollPlayers
        if needed == 1 then currentItem.winner = rollPlayers[1] end
        local msg
        if #rollPlayers == 1 then
            msg = rollPlayers[1] .. " is the only eligible player — no roll needed."
        else
            msg = "All " .. #rollPlayers .. " eligible players win — no roll needed."
        end
        GL.PostToRaid(msg)
        if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
        return
    end

    local rollSecs = ROLL_SECONDS()
    currentItem.rollState.active   = true
    currentItem.rollState.results  = {}
    currentItem.rollState.timeLeft = rollSecs
    currentItem._tieReRoll = nil

    local playerList = table.concat(rollPlayers, ", ")
    local rollMsg = "Please /roll now! " .. rollSecs .. " seconds"
    if needed > 1 then rollMsg = rollMsg .. " (" .. needed .. " winners)" end
    GL.PostToRaid(rollMsg .. ": " .. playerList)
    if GL.Comm then GL.Comm.SendRollStart(rollSecs, rollPlayers) end

    -- Countdown in UI
    currentItem.rollState.timer = C_Timer.NewTicker(1, function()
        currentItem.rollState.timeLeft = currentItem.rollState.timeLeft - 1
        if GL.UI and GL.UI.RefreshCountdown then
            GL.UI.RefreshCountdown(currentItem.rollState.timeLeft)
        end
        if currentItem.rollState.timeLeft <= 0 then
            if currentItem.rollState.timer then
                currentItem.rollState.timer:Cancel()
                currentItem.rollState.timer = nil
            end
            Loot.FinalizeRoll()
        end
    end)

    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

function Loot.CancelRoll()
    if currentItem.rollState.timer then
        currentItem.rollState.timer:Cancel()
        currentItem.rollState.timer = nil
    end
    currentItem.rollState.active = false
end

-- ============================================================
-- Roll-Monitoring (CHAT_MSG_SYSTEM)
-- ============================================================

-- WoW Roll-Nachricht: "%s würfelt. Er erhält eine %d (1-%d)." oder EN: "%s rolls %d (1-%d)."
local ROLL_PATTERN_DE = "^(.+) w%ürf[ae]lt.* (%d+) %(1%-(%d+)%)"
local ROLL_PATTERN_EN = "^(.+) rolls (%d+) %(1%-(%d+)%)"

function Loot.OnSystemMessage(msg)
    if not currentItem.rollState.active then return end

    local roller, result
    roller, result = msg:match(ROLL_PATTERN_DE)
    if not roller then
        roller, result = msg:match(ROLL_PATTERN_EN)
    end

    if not roller or not result then return end

    local shortRoller = GL.ShortName(roller)
    if not currentItem.rollState.players[shortRoller] then return end
    if currentItem.rollState.results[shortRoller] then return end  -- Nur erster Roll zählt

    currentItem.rollState.results[shortRoller] = tonumber(result)

    if GL.UI and GL.UI.RefreshRollResults then GL.UI.RefreshRollResults() end
end

-- ============================================================
-- Roll auswerten
-- ============================================================

function Loot.FinalizeRoll()
    currentItem.rollState.active = false
    if currentItem.rollState.timer then
        currentItem.rollState.timer:Cancel()
        currentItem.rollState.timer = nil
    end

    local results = currentItem.rollState.results
    if not next(results) then
        GL.Print("No roll results received.")
        if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
        return
    end

    -- Kontext: initiale Runde oder Tie-Re-Roll?
    local confirmedWinners = {}
    local spotsNeeded = currentItem.count
    if currentItem._tieReRoll then
        for _, w in ipairs(currentItem._tieReRoll.confirmedWinners) do
            table.insert(confirmedWinners, w)
        end
        spotsNeeded = currentItem._tieReRoll.spotsNeeded
    end

    -- Prio eines Kurznamens aus candidates nachschlagen
    local function getPrio(shortName)
        for fullName, data in pairs(currentItem.candidates) do
            if GL.ShortName(fullName) == shortName then return data.prio end
        end
        return 99
    end

    -- Alle Roll-Ergebnisse rangieren: Prio aufsteigend, Roll absteigend
    local ranked = {}
    for name, rollVal in pairs(results) do
        table.insert(ranked, { name = name, roll = rollVal, prio = getPrio(name) })
    end
    table.sort(ranked, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        return a.roll > b.roll
    end)

    -- Weniger Ergebnisse als benötigte Spots: alle gewinnen
    if #ranked <= spotsNeeded then
        for _, r in ipairs(ranked) do table.insert(confirmedWinners, r.name) end
        currentItem.winners    = confirmedWinners
        currentItem._tieReRoll = nil
        if currentItem.count == 1 then currentItem.winner = confirmedWinners[1] end
        if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
        return
    end

    -- Boundary (Platz N) ermitteln und Spieler klassifizieren
    local boundaryPrio = ranked[spotsNeeded].prio
    local boundaryRoll = ranked[spotsNeeded].roll

    local clearWinners  = {}  -- eindeutig besser als Boundary
    local boundaryGroup = {}  -- auf demselben Rang wie Boundary
    for _, r in ipairs(ranked) do
        if r.prio < boundaryPrio or (r.prio == boundaryPrio and r.roll > boundaryRoll) then
            table.insert(clearWinners, r.name)
        elseif r.prio == boundaryPrio and r.roll == boundaryRoll then
            table.insert(boundaryGroup, r.name)
        end
    end

    local spotsForBoundary = spotsNeeded - #clearWinners

    if #boundaryGroup > spotsForBoundary then
        -- Gleichstand am Grenzplatz → Re-Roll nur für boundaryGroup
        local newConfirmed = {}
        for _, w in ipairs(confirmedWinners) do table.insert(newConfirmed, w) end
        for _, w in ipairs(clearWinners)     do table.insert(newConfirmed, w) end

        GL.Print("Tie! Rolling again: " .. table.concat(boundaryGroup, ", "))
        GL.PostToRaid("Tie at " .. boundaryRoll .. "! Roll again: " .. table.concat(boundaryGroup, ", "))

        currentItem._tieReRoll = { confirmedWinners = newConfirmed, spotsNeeded = spotsForBoundary }
        currentItem.rollState.results = {}
        currentItem.rollState.players = {}
        for _, name in ipairs(boundaryGroup) do
            currentItem.rollState.players[name] = true
        end
        local rollSecs = ROLL_SECONDS()
        currentItem.rollState.active   = true
        currentItem.rollState.timeLeft = rollSecs
        currentItem.rollState.timer = C_Timer.NewTicker(1, function()
            currentItem.rollState.timeLeft = currentItem.rollState.timeLeft - 1
            if GL.UI and GL.UI.RefreshCountdown then
                GL.UI.RefreshCountdown(currentItem.rollState.timeLeft)
            end
            if currentItem.rollState.timeLeft <= 0 then
                if currentItem.rollState.timer then
                    currentItem.rollState.timer:Cancel()
                    currentItem.rollState.timer = nil
                end
                Loot.FinalizeRoll()
            end
        end, rollSecs)
    else
        -- Kein Gleichstand: alle Gruppen zusammenführen
        for _, w in ipairs(confirmedWinners)  do table.insert(clearWinners, w) end
        for _, w in ipairs(boundaryGroup)     do table.insert(clearWinners, w) end
        currentItem.winners    = clearWinners
        currentItem._tieReRoll = nil
        if currentItem.count == 1 then currentItem.winner = clearWinners[1] end
    end

    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
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

    -- Item aus Pending entfernen (per Link; Fallback per itemID für abweichende Tracks)
    local pl = pendingLoot()
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

-- Wird bei TRADE_SHOW aufgerufen: legt alle zugewiesenen Items automatisch in den Handel,
-- wenn der Handelspartner ein bekannter Gewinner ist (bis zu 6 Slots).
-- Fix: Gesamte Logik um 0.1s verzögert (TRADE_SHOW kann vor Frame-Befüllung feuern).
-- Fix: CursorHasItem()-Guard entfernt (WoW ignoriert ClickTradeButton mit leerem Cursor).
-- Fix: strtrim() auf Partner-Namen (Whitespace-Schutz).
-- Fix: Cross-Realm-Suffix "(*)"-Stripping (RCLootCouncil-Pattern).
function Loot.OnTradeShow()
    if not GL.IsMasterLooter() then return end
    if #Loot._pendingTrades == 0 then return end

    C_Timer.After(0.1, function()
        -- Re-Check nach Delay
        if #Loot._pendingTrades == 0 then return end

        -- Handelspartner-Name aus dem Trade-Frame lesen
        local recipientFrame = TradeFrameRecipientNameText
        if not recipientFrame then return end
        -- WoW-Farbcodes entfernen + Whitespace trimmen
        local rawText = strtrim(recipientFrame:GetText() or "")
        local cleanText = strtrim(rawText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        -- Cross-Realm-Suffix entfernen: "Name(*)" oder "Name (Realm)" → "Name"
        -- (RCLootCouncil-Pattern: TRADE_SHOW liefert bei Cross-Realm "Name(*)" statt "Name-Realm")
        cleanText = strtrim(cleanText:gsub("%s*%(.*%)$", ""))
        local partnerName = GL.ShortName(cleanText)
        if partnerName == "" then return end

        -- Alle offenen Zuweisungen für diesen Spieler sammeln und aus Liste entfernen
        local itemIDs = {}
        for i = #Loot._pendingTrades, 1, -1 do
            local pt = Loot._pendingTrades[i]
            if pt.shortName == partnerName then
                table.insert(itemIDs, pt.itemID)
                table.remove(Loot._pendingTrades, i)
            end
        end
        if #itemIDs == 0 then return end

        -- Nächsten freien Handelsslot finden (Hilfsfunktion)
        local function nextFreeTradeSlot()
            for i = 1, 6 do
                local slotName = GetTradePlayerItemInfo(i)
                if not slotName or slotName == "" then return i end
            end
            return nil
        end

        -- Jedes Item in den Taschen suchen und mit Delay in einen freien Handelsslot legen
        local delay = 0
        for _, itemID in ipairs(itemIDs) do
            local capturedID    = itemID
            local capturedDelay = delay
            delay = delay + 0.1

            C_Timer.After(capturedDelay, function()
                local tradeSlot = nextFreeTradeSlot()
                if not tradeSlot then return end

                for bag = 0, 4 do
                    for slot = 1, C_Container.GetContainerNumSlots(bag) do
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info and info.itemID == capturedID then
                            ClearCursor()
                            C_Container.PickupContainerItem(bag, slot)
                            ClickTradeButton(tradeSlot)
                            return
                        end
                    end
                end
            end)
        end
    end)
end

function Loot.ResetCurrentItem()
    if not GL.IsMasterLooter() then return end
    local itemLink = currentItem.link
    Loot.ClearCurrentItem()
    if GL.Comm then GL.Comm.SendItemClear() end
    GL.Print("Item reset: " .. (itemLink or "?"))
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

function Loot.CancelPrio()
    if not GL.IsMasterLooter() then return end
    if not currentItem.prioState.active then return end
    Loot.ClearCurrentItem()
    if GL.Comm then GL.Comm.SendItemClear() end
    GL.Print("Prio phase cancelled.")
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

function Loot.RemovePendingItem(link)
    if not GL.IsMasterLooter() then return end
    local pl = pendingLoot()
    for i, p in ipairs(pl) do
        if p.link == link then
            table.insert(trashedLoot(), p)  -- in Trash verschieben statt löschen
            table.remove(pl, i)
            break
        end
    end
    if currentItem.link == link then
        Loot.ClearCurrentItem()
        if GL.Comm then GL.Comm.SendItemClear() end
    end
end

function Loot.RestoreFromTrash(link)
    if not GL.IsMasterLooter() then return end
    local tl = trashedLoot()
    for i, p in ipairs(tl) do
        if p.link == link then
            table.insert(pendingLoot(), p)
            table.remove(tl, i)
            break
        end
    end
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

function Loot.DeleteFromTrash(link)
    if not GL.IsMasterLooter() then return end
    local tl = trashedLoot()
    for i, p in ipairs(tl) do
        if p.link == link then
            table.remove(tl, i)
            break
        end
    end
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

function Loot.TrashActiveItem()
    if not GL.IsMasterLooter() then return end
    local link = currentItem.link
    if not link then return end
    Loot.ClearCurrentItem()
    if GL.Comm then GL.Comm.SendItemClear() end
    Loot.RemovePendingItem(link)
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
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
    local pl = pendingLoot()
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
        local pl = pendingLoot()
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

--- ML hat Roll-Phase gestartet → Observer aktivieren Roll-Anzeige
function Loot.OnCommRollStart(seconds, players)
    if GL.IsMasterLooter() then return end
    currentItem.rollState.active   = true
    currentItem.rollState.results  = {}
    currentItem.rollState.players  = {}
    currentItem.rollState.timeLeft = seconds
    currentItem.prioState.active   = false
    for _, p in ipairs(players or {}) do
        currentItem.rollState.players[p] = true
    end
    -- Visueller Countdown (ohne Auto-Trigger)
    if currentItem.rollState.timer then currentItem.rollState.timer:Cancel() end
    currentItem.rollState.timer = C_Timer.NewTicker(1, function()
        currentItem.rollState.timeLeft = currentItem.rollState.timeLeft - 1
        if GL.UI and GL.UI.RefreshCountdown then
            GL.UI.RefreshCountdown(currentItem.rollState.timeLeft)
        end
        if currentItem.rollState.timeLeft <= 0 then
            currentItem.rollState.timer:Cancel()
            currentItem.rollState.timer = nil
        end
    end, seconds)
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
