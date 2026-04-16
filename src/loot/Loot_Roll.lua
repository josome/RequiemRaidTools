-- RequiemRaidTools – Loot_Roll.lua
-- Prio-Phase (Chat-Parsing), Roll-Freigabe, Roll-Monitoring, Roll-Auswertung

local GL   = GuildLoot
local Loot = GL.Loot

-- Referenz auf gemeinsamen currentItem-Zustand (gleiche Tabelle wie in Loot.lua)
local currentItem = Loot.GetCurrentItem()

-- ============================================================
-- Chat-Parsing – Bedarfsmeldungen
-- ============================================================

local function IsParticipant(name)
    if not GuildLootDB.activeContainerIdx then return false end
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

    -- Aktive Prio-Tiers der Reihe nach aufzählen
    -- bis genug Spieler für alle Kopien gesammelt sind (Cross-Tier-Logik)
    local rollPlayers = {}
    currentItem.rollState.players = {}
    for _, prio in ipairs(GL.GetActivePrios()) do
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

    local rollSecs = GuildLootDB.settings.rollSeconds or 15
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
        local rollSecs = GuildLootDB.settings.rollSeconds or 15
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
-- Observer-Handler
-- ============================================================

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
