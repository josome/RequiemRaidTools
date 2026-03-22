-- GuildLoot – Loot.lua
-- Loot-Erkennung, Chat-Parsing, Roll-Prozess, Zuweisung

GuildLoot = GuildLoot or {}
local GL = GuildLoot
GL.Loot = GL.Loot or {}
local Loot = GL.Loot

-- ============================================================
-- Modul-lokaler Zustand (nicht persistent)
-- ============================================================

-- pendingLoot wird direkt aus GuildLootDB gelesen (überlebt Reloads)
local function pendingLoot() return GuildLootDB.currentRaid.pendingLoot end
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
    winner = nil,
}

local function PRIO_SECONDS() return GuildLootDB.settings.prioSeconds or 15 end
local function ROLL_SECONDS() return GuildLootDB.settings.rollSeconds or 15 end

-- Item das noch auf GetItemInfo wartet
local pendingActivation = nil   -- itemLink

-- Items aus OnLootOpened die noch auf GetItemInfo warten
local deferredPendingItems = {}

-- ============================================================
-- Zugriffs-Helfer
-- ============================================================

function Loot.GetPendingLoot()  return pendingLoot()  end
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
    local minQ = GuildLootDB.settings.minQuality or 4
    local newItems = {}

    for slot = 1, GetNumLootItems() do
        local icon, name, quantity, currencyID, quality, locked, isQuestItem = GetLootSlotInfo(slot)
        if quality and quality >= minQ and not isQuestItem then
            local link = GetLootSlotLink(slot)
            if link then
                local itemID = tonumber(link:match("item:(%d+)"))
                -- Nur hinzufügen wenn nicht bereits in pendingLoot
                local alreadyIn = false
                for _, p in ipairs(pendingLoot()) do
                    if p.link == link then alreadyIn = true; break end
                end
                if not alreadyIn then
                    table.insert(newItems, { link = link, name = name or "?", itemID = itemID, quality = quality })
                end
            end
        end
    end

    if #newItems > 0 then
        for _, item in ipairs(newItems) do
            -- Kategorie ermitteln + Filter prüfen (GetItemInfo kann nil → deferred)
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

-- ============================================================
-- Item freigeben (LM klickt Item-Button)
-- ============================================================

function Loot.ReleaseItem(itemLink)
    if not GL.IsMasterLooter() then
        GL.Print("|cffff4444Freigabe fehlgeschlagen:|r ML-Checkbox nicht aktiviert.")
        return
    end
    if not GuildLootDB.currentRaid.active then
        GL.Print("|cffff4444Freigabe fehlgeschlagen:|r Kein aktiver Raid. Erst 'Raid starten' drücken.")
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
    currentItem.category   = GL.GetItemCategory(itemID, equipLoc or "", quality or 0)
    currentItem.candidates = {}
    currentItem.winner     = nil
    currentItem.prioState  = { active=false, timeLeft=0, timer=nil }
    currentItem.rollState  = { active=false, players={}, results={}, timer=nil, timeLeft=0 }

    -- Prio-Sammel-Timer starten
    local prioSecs = PRIO_SECONDS()
    GL.PostToRaid("Loot: " .. link .. " -- Bitte Prio posten (" .. prioSecs .. " Sek): 1=BIS, 2=Upgrade, 3=OS, 4=Fun")
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

    -- Kandidaten registrieren (Override erlaubt)
    currentItem.candidates[sender] = { prio = prio }

    if GL.UI and GL.UI.RefreshCandidates then GL.UI.RefreshCandidates() end
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

    local lowestPrio = GetLowestPrio(currentItem.candidates)
    if not lowestPrio then
        GL.Print("Keine Bedarfsmeldungen vorhanden.")
        return
    end

    -- Spieler mit niedrigster Prio
    local rollPlayers = {}
    for name, data in pairs(currentItem.candidates) do
        if data.prio == lowestPrio then
            table.insert(rollPlayers, GL.ShortName(name))
            currentItem.rollState.players[GL.ShortName(name)] = true
        end
    end

    local rollSecs = ROLL_SECONDS()
    currentItem.rollState.active   = true
    currentItem.rollState.results  = {}
    currentItem.rollState.timeLeft = rollSecs

    local playerList = table.concat(rollPlayers, ", ")
    GL.PostToRaid("Bitte /roll eingeben! " .. rollSecs .. " Sekunden: " .. playerList)
    if GL.Comm then GL.Comm.SendRollStart(rollSecs, rollPlayers) end

    -- Countdown in UI
    currentItem.rollState.timer = C_Timer.NewTicker(1, function()
        currentItem.rollState.timeLeft = currentItem.rollState.timeLeft - 1
        if GL.UI and GL.UI.RefreshCountdown then
            GL.UI.RefreshCountdown(currentItem.rollState.timeLeft)
        end
        if currentItem.rollState.timeLeft <= 0 then
            currentItem.rollState.timer:Cancel()
            Loot.FinalizeRoll()
        end
    end, rollSecs)

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
        GL.Print("Kein Roll-Ergebnis erhalten.")
        if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
        return
    end

    -- Höchste Zahl ermitteln
    local topRoller, topValue = nil, -1
    for name, val in pairs(results) do
        if val > topValue then
            topValue  = val
            topRoller = name
        end
    end

    -- Gleichstand?
    local tied = {}
    for name, val in pairs(results) do
        if val == topValue then
            table.insert(tied, name)
        end
    end

    if #tied > 1 then
        -- Erneuter Roll für Gleichstand-Spieler
        GL.Print("Gleichstand! Nochmal würfeln: " .. table.concat(tied, ", "))
        GL.PostToRaid("Gleichstand bei " .. topValue .. "! Nochmal wuerfeln: " .. table.concat(tied, ", "))
        -- Neue Roll-Runde nur für Gleichstand-Spieler
        currentItem.rollState.results = {}
        currentItem.rollState.players = {}
        for _, name in ipairs(tied) do
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
                currentItem.rollState.timer:Cancel()
                Loot.FinalizeRoll()
            end
        end, rollSecs)
    else
        -- Gewinner vorschlagen (LM bestätigt)
        currentItem.winner = topRoller
    end

    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

-- ============================================================
-- Zuweisung
-- ============================================================

function Loot.AssignLoot(recipientShortName)
    if not GL.IsMasterLooter() then return end
    if not currentItem.link then return end

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
    local diff = GL.DetectDifficulty(currentItem.itemLevel)
    if not diff then
        -- UI zeigt Popup → wird in UI.lua behandelt
        -- AssignLootConfirm wird danach aufgerufen
        if GL.UI and GL.UI.ShowDifficultyPopup then
            GL.UI.ShowDifficultyPopup(recipientShortName)
        end
        return
    end

    Loot.AssignLootConfirm(fullName, diff)
end

function Loot.AssignLootConfirm(fullName, diff)
    local category = currentItem.category or "other"
    local link     = currentItem.link
    local ts       = GL.GetTimestamp()

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
        category   = category,
        difficulty = diff,
        timestamp  = ts,
    })

    -- Raid-Chat
    GL.PostToRaid(GL.ShortName(fullName) .. " erhaelt " .. link .. " - bitte beim Lootmaster abholen.")

    -- Item aus Pending entfernen
    local pl = pendingLoot()
    for i, p in ipairs(pl) do
        if p.link == link then
            table.remove(pl, i)
            break
        end
    end

    -- Observer informieren
    if GL.Comm then GL.Comm.SendAssign(GL.ShortName(fullName), diff, link) end

    -- Zustand zurücksetzen
    Loot.ClearCurrentItem()
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
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
    pendingActivation      = nil
end

function Loot.ResetCurrentItem()
    if not GL.IsMasterLooter() then return end
    Loot.ClearCurrentItem()
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

function Loot.CancelPrio()
    if not GL.IsMasterLooter() then return end
    if not currentItem.prioState.active then return end
    Loot.ClearCurrentItem()
    if GL.Comm then GL.Comm.SendItemClear() end
    GL.Print("Prio-Phase abgebrochen.")
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

function Loot.RemovePendingItem(link)
    if not GL.IsMasterLooter() then return end
    local pl = pendingLoot()
    for i, p in ipairs(pl) do
        if p.link == link then
            table.remove(pl, i)
            break
        end
    end
    -- Falls dieses Item gerade aktiv war, zurücksetzen
    if currentItem.link == link then
        Loot.ClearCurrentItem()
    end
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
    currentItem.prioState  = { active = true,  timeLeft = 0, timer = nil }
    currentItem.rollState  = { active = false, players  = {}, results = {}, timer = nil, timeLeft = 0 }
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

--- ML hat Item abgebrochen → Observer leeren Anzeige
function Loot.OnCommItemClear()
    if GL.IsMasterLooter() then return end
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
function Loot.OnCommAssign(playerName, diff, link)
    if GL.IsMasterLooter() then return end
    if not playerName or playerName == "" then return end
    -- Vollständigen Namen suchen (Kurzname-Match)
    local fullName = playerName
    for _, p in ipairs(GuildLootDB.currentRaid.participants) do
        if GL.ShortName(p) == playerName or p == playerName then
            fullName = p; break
        end
    end
    table.insert(GuildLootDB.currentRaid.lootLog, {
        player     = fullName,
        item       = link or "",
        link       = link or "",
        difficulty = diff or "",
        timestamp  = time(),
    })
    Loot.OnCommItemClear()
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end
