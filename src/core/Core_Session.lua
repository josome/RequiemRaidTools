-- GuildLoot – Core_Session.lua
-- Session-Lifecycle, Chat-Output, Roster-Verwaltung, Raid-Lifecycle,
-- Observer/ML-Comm-Handler, History-Helper.
-- Lädt nach Core_DB.lua und vor Comm.lua (TOC-Reihenfolge).

GuildLoot = GuildLoot or {}
local GL = GuildLoot

-- ============================================================
-- Session (Container) System
-- ============================================================

--- Verschiebt einen unassigned Raid-Snapshot in eine Session.
--- Reads:  db.unassignedRaids, db.raidContainers
--- Writes: db.raidContainers[ci].raidMeta, db.raidContainers[ci].lootLog,
---         db.raidContainers[ci].trashedLoot, db.unassignedRaids
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

--- Gibt den Timestamp des letzten EU-Weekly-Resets zurück (Mittwoch 07:00).
--- Pure — kein Zugriff auf globalen State.
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

--- Gibt true zurück wenn ein Session-Label bereits vergeben ist.
--- @param label    string   Zu prüfender Name
--- @param exceptCI number|nil  Container-Index der ausgeschlossen wird (beim Umbenennen)
function GL.IsSessionLabelTaken(label, exceptCI)
    for i, s in ipairs(GuildLootDB.raidContainers or {}) do
        if i ~= exceptCI and s.label == label then return true end
    end
    return false
end

--- Gibt einen eindeutigen Session-Label zurück.
--- Falls label bereits vergeben ist, wird " (2)", " (3)" etc. angehängt.
local function uniqueSessionLabel(label)
    local result, n = label, 2
    while GL.IsSessionLabelTaken(result) do
        result = string.format("%s (%d)", label, n)
        n = n + 1
    end
    return result
end

--- Migriert orphaned pendingLoot-Items in einen separaten Legacy-Container.
--- Idempotent: zweiter Aufruf ohne neue Items ist No-Op.
--- Reads:  db.currentRaid.pendingLoot, db.settings.priorities
--- Writes: db.raidContainers (neuer Legacy-Eintrag), db.currentRaid.pendingLoot (geleert)
function GL.MigratePendingLoot()
    local db = GuildLootDB
    local orphaned = db.currentRaid and db.currentRaid.pendingLoot
    if not orphaned or #orphaned == 0 then return end
    local count = #orphaned
    local legacyTs = time()
    local legacy = {
        id             = string.format("legacy-%08x", legacyTs),
        label          = "Legacy Loot",
        startedAt      = legacyTs,
        closedAt       = legacyTs,
        pendingLoot    = orphaned,
        lootLog        = {},
        trashedLoot    = {},
        raidMeta       = {},
        priorityConfig = CopyTable(db.settings.priorities or {}),
    }
    table.insert(db.raidContainers, legacy)
    db.currentRaid.pendingLoot = {}
    GL.Print(string.format("%d Item(s) in Legacy-Session gesichert.", count))
end

--- Löscht eine Session aus raidContainers und passt activeContainerIdx an.
--- - Aktive Session gelöscht → activeContainerIdx = nil + ResetCurrentRaid.
--- - Index vor aktiver Session gelöscht → activeContainerIdx dekrementieren.
--- - Out-of-Bounds oder ungültiger Index → No-Op.
--- Reads:  db.raidContainers, db.activeContainerIdx
--- Writes: db.raidContainers, db.activeContainerIdx, db.currentRaid (via ResetCurrentRaid)
--- @param ci number  1-basierter Index in raidContainers
function GL.DeleteSession(ci)
    local db = GuildLootDB
    if type(ci) ~= "number" or not db.raidContainers
       or ci < 1 or ci > #db.raidContainers then
        return
    end
    table.remove(db.raidContainers, ci)
    if db.activeContainerIdx == ci then
        db.activeContainerIdx = nil
        GL.ResetCurrentRaid()
    elseif db.activeContainerIdx and db.activeContainerIdx > ci then
        db.activeContainerIdx = db.activeContainerIdx - 1
    end
end

--- Erstellt eine neue Raid-Session und setzt sie als aktiv.
--- Reads:  db.activeContainerIdx, db.settings.priorities, db.currentRaid.tier
--- Writes: db.raidContainers, db.activeContainerIdx, db.settings.isMasterLooter,
---         db.currentRaid.participants (via LoadRaidRoster, falls Bosskills vorangingen),
---         db.raidContainers[i].raidMeta (via EnsureRaidMeta, falls Bosskills vorangingen)
--- Sends:  Comm.SendMLAnnounce, Comm.SendSessionStart,
---         Comm.SendRaidMeta (via EnsureRaidMeta, falls Bosskills vorangingen)
function GL.StartContainer(label)
    local db = GuildLootDB
    if db.activeContainerIdx then
        GL.Print("Session bereits offen.")
        return
    end
    local ts  = time()
    local kw  = GL.ISOWeek(ts)
    local yr  = tonumber(date("%Y", ts))
    local finalLabel = uniqueSessionLabel(
        (label and label ~= "") and label or string.format("KW %02d %d", kw, yr)
    )
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
    GL.MigratePendingLoot()

    table.insert(db.raidContainers, session)
    db.activeContainerIdx = #db.raidContainers
    GL.Print("Session gestartet: " .. finalLabel)
    -- Wer die Session startet, ist automatisch ML
    db.settings.isMasterLooter = true
    -- Falls bereits Bosskills stattgefunden haben (currentRaid.tier gesetzt durch ENCOUNTER_END),
    -- raidMeta-Eintrag retroaktiv anlegen und broadcasten.
    if (IsInRaid() or IsInGroup()) and db.currentRaid.tier ~= "" then
        GL.LoadRaidRoster()
        GL.EnsureRaidMeta()
    end
    if GL.Comm and (IsInRaid() or IsInGroup()) then
        GL.Comm.SendMLAnnounce(UnitName("player") or "")
    end
    if GL.Comm and GL.Comm.SendSessionStart then
        GL.Comm.SendSessionStart(session.id, finalLabel, ts, session.priorityConfig)
    end
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

--- Schließt die aktive Session.
--- Reads:  db.activeContainerIdx, db.raidContainers, db.currentRaid.id
--- Writes: db.raidContainers[i].raidMeta[id].closedAt, db.raidContainers[i].closedAt,
---         db.activeContainerIdx, db.currentRaid (via ResetCurrentRaid)
--- Sends:  Comm.SendSessionEnd
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

--- Verschiebt alle pendingLoot-Items einer geschlossenen Session in die aktive Session.
--- Reads:  db.activeContainerIdx, db.raidContainers[sourceCI].pendingLoot
--- Writes: db.raidContainers (remove source), db.activeContainerIdx (korrigiert),
---         db.raidContainers[activeIdx].pendingLoot
function GL.MergeSessionIntoActive(sourceCI)
    local db = GuildLootDB
    if not db.activeContainerIdx then
        GL.Print("Kein aktive Session zum Mergen.")
        return
    end
    if sourceCI == db.activeContainerIdx then
        GL.Print("Kann aktive Session nicht mit sich selbst mergen.")
        return
    end
    local source = db.raidContainers[sourceCI]
    if not source then return end
    local activeSession = db.raidContainers[db.activeContainerIdx]
    local items = source.pendingLoot or {}
    local count = #items
    for _, item in ipairs(items) do
        table.insert(activeSession.pendingLoot, item)
    end
    local sourceLabel = source.label
    table.remove(db.raidContainers, sourceCI)
    if sourceCI < db.activeContainerIdx then
        db.activeContainerIdx = db.activeContainerIdx - 1
    end
    GL.Print(string.format("%d Item(s) aus '%s' übernommen.", count, sourceLabel))
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

--- Öffnet eine geschlossene Session wieder.
--- Reads:  db.activeContainerIdx, db.raidContainers[ci].raidMeta
--- Writes: db.activeContainerIdx, db.raidContainers[ci].closedAt,
---         db.currentRaid.id, db.currentRaid.tier, db.currentRaid.difficulty,
---         db.currentRaid.startedAt, db.currentRaid.participants
--- Sends:  Comm.SendSessionStart, Comm.SendMLAnnounce
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
        GL.Comm.SendSessionStart(session.id, session.label or "", session.startedAt or 0, session.priorityConfig)
    end
    -- Falls wir der ML sind, unsere Rolle ankündigen
    if GL.IsMasterLooter() and GL.Comm and GL.Comm.SendMLAnnounce then
        GL.Comm.SendMLAnnounce(UnitName("player") or "")
    end
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

--- Legt raidMeta-Eintrag für currentRaid an falls noch nicht vorhanden.
--- Reads:  db.activeContainerIdx, db.raidContainers, db.currentRaid
--- Writes: db.raidContainers[i].raidMeta[currentRaid.id]
--- Sends:  Comm.SendRaidMeta (nur wenn IsMasterLooter)
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
            GL.Comm.SendRaidMeta(session.id, id, meta, session.priorityConfig)
        end
    end
end

--- Schreibt einen Bosskill in die raidMeta des laufenden Raids: der Gruppenstand zum
--- Kill wird als eigener kills-Eintrag angehängt UND in die kumulative Teilnehmerliste
--- des Abends vereinigt.
---
--- Bewusst getrennt von GL.EnsureRaidMeta: das legt den raidMeta-Eintrag nur EINMAL an
--- (eine raidMeta-ID ist eine Tier+Difficulty-Kombination, kein Boss). Die participants
--- blieben dadurch auf dem ersten Kill des Abends eingefroren und Nachrücker fehlten für
--- den gesamten Abend. Die Kill-Ebene muss dagegen bei jedem Kill wachsen.
---
--- Die Einzelliste wird zusätzlich zur Vereinigung gespeichert, weil sie nicht
--- rekonstruierbar ist: aus den Einzellisten lässt sich die Vereinigung jederzeit wieder
--- bilden, umgekehrt nie.
---
--- Reads:  db.activeContainerIdx, db.raidContainers, db.currentRaid.id,
---         db.currentRaid.currentKillParticipants, db.currentRaid.participants
--- Writes: db.raidContainers[i].raidMeta[id].kills,
---         db.raidContainers[i].raidMeta[id].participants
function GL.RecordKillAttendance(bossName, encounterID)
    local db = GuildLootDB
    if not db or not db.activeContainerIdx then return end
    local session = db.raidContainers[db.activeContainerIdx]
    if not session or not session.raidMeta then return end
    local raid = db.currentRaid
    local id   = raid and raid.id
    if not id or id == "" then return end
    local meta = session.raidMeta[id]
    if not meta then return end

    -- Gruppenstand zum Kill; ENCOUNTER_END hat currentKillParticipants gerade gesetzt.
    -- Fallback auf die kumulative Liste, damit ein Aufruf ohne frischen Snapshot keinen
    -- leeren Kill (= Boss-Spalte ohne Teilnehmer) aufzeichnet.
    local names = raid.currentKillParticipants or {}
    if #names == 0 then names = raid.participants or {} end

    -- trials ist auch dann eine (leere) Tabelle, wenn niemand Trial war: nur so lässt sich
    -- "damals war niemand auf Probe" von "gar nicht aufgezeichnet" (Altdaten) unterscheiden.
    local kill = {
        boss         = bossName or "",
        encounterID  = encounterID,
        ts           = time(),
        participants = {},
        trials       = {},
    }
    local players = db.players or {}
    for _, name in ipairs(names) do
        table.insert(kill.participants, name)
        -- Trial-Stand zum Kill festhalten: die Rolle endet nach drei Raids, und das darf
        -- die bereits gelaufenen Abende der Season nicht rückwirkend umdeuten
        local p = players[name]
        if p and p.trial then kill.trials[name] = true end
    end
    meta.kills = meta.kills or {}
    table.insert(meta.kills, kill)

    -- Vereinigung: Nachrücker kommen dazu, niemand fällt aus der Abend-Liste heraus
    meta.participants = meta.participants or {}
    local seen = {}
    for _, name in ipairs(meta.participants) do seen[name] = true end
    for _, name in ipairs(names) do
        if not seen[name] then
            seen[name] = true
            table.insert(meta.participants, name)
        end
    end
end

--- Setzt db.currentRaid auf leeren Ausgangszustand.
--- Writes: db.currentRaid (alle Felder)
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

--- Startet eine neue Session falls keine aktiv ist.
--- Reads:  db.activeContainerIdx
--- Writes: indirekt via GL.StartContainer
--- Sends:  indirekt via GL.StartContainer
function GL.EnsureActiveSession()
    if GuildLootDB.activeContainerIdx then return end
    local kw = GL.ISOWeek(time())
    GL.StartContainer(string.format("Auto KW %02d", kw))
end

-- ============================================================
-- Ausgabe-Helfer
-- ============================================================

--- Gibt eine Nachricht in den Chat aus. Reiner UI-Seiteneffekt.
function GL.Print(msg)
    print("|cff00ccff[ReqRT]|r " .. tostring(msg))
end

--- Sendet eine Nachricht in den Raid-/Party-Chat.
--- Reads:  db.settings.chatChannel, db.settings.postToChat
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

--- Sendet eine Nachricht als Raid Warning (oder Raid-Chat je nach Setting).
--- Reads:  db.settings.raidWarnItem
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

--- Liest die aktuelle Gruppe aus der WoW-API und aktualisiert currentRaid.
--- Reads:  db.currentRaid
--- Writes: db.currentRaid.participants, db.currentRaid.absent, db.players[*].class
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

--- Stellt sicher, dass currentRaid.participants befüllt ist, bevor ein Bosskill aufgezeichnet
--- wird. Nötig, weil GROUP_ROSTER_UPDATE nicht feuert, solange man allein ist: solo wird
--- GL.LoadRaidRoster nirgends angestoßen (StartContainer überspringt es mangels Gruppe), die
--- Liste bliebe leer und der Kill damit ohne Teilnehmer.
--- Eine bereits befüllte Liste bleibt unangetastet — sie ist kumulativ und darf nicht auf den
--- aktuellen Gruppenstand zurückfallen.
--- Writes: db.currentRaid.participants (via GL.LoadRaidRoster)
function GL.EnsureRaidParticipants()
    local raid = GuildLootDB and GuildLootDB.currentRaid
    if not raid then return end
    if #(raid.participants or {}) == 0 then
        GL.LoadRaidRoster()
    end
end

--- Bereinigt currentRaid.participants gegen aktuelle Gruppe (neue Mitglieder hinzufügen, DCs markieren).
--- Reads:  db.activeContainerIdx, db.currentRaid.participants
--- Writes: db.currentRaid.participants, db.currentRaid.absent
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

--- Initialisiert den currentRaid-Kontext für einen neuen Raid innerhalb der aktiven Session.
--- Reads:  db.activeContainerIdx, db.currentRaid, db.raidContainers
--- Writes: db.currentRaid.tier, db.currentRaid.difficulty, db.currentRaid.startedAt,
---         db.currentRaid.id, db.currentRaid.participants,
---         db.settings.isMasterLooter,
---         db.raidContainers[i].raidMeta[id].closedAt
--- Sends:  Comm.SendMLAnnounce, Comm.SendRaidMeta (via EnsureRaidMeta),
---         Comm.SendSessionStart (via EnsureActiveSession falls keine Session offen)
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
    -- ML-Rolle an alle Raid-Mitglieder ankündigen (damit niemand mit altem isMasterLooter=true im SavedVariables hängt)
    if GL.Comm and GL.Comm.SendMLAnnounce then
        GL.Comm.SendMLAnnounce(UnitName("player") or "")
    end
    -- Create raidMeta entry and broadcast RAID_META
    GL.EnsureRaidMeta()
    GL.Print("Raid started: " .. raid.tier .. ". " .. #raid.participants .. " players loaded.")
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
    if GL.UI and GL.UI.ShowTab then GL.UI.ShowTab(GL.UI.TAB_LOOT) end
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

--- Observer: empfängt SESSION_START vom ML, legt Session an oder reaktiviert sie.
--- Reads:  db.raidContainers
--- Writes: db.settings.isMasterLooter, db.raidContainers, db.activeContainerIdx,
---         db.raidContainers[i].priorityConfig
function GL.OnCommSessionStart(sessionID, label, startedAt, sender, prioCfg)
    local myName = GL.NormalizeName(UnitName("player") or "") or ""
    if GL.NormalizeName(sender or "") == myName then return end
    -- Wir empfangen eine Session von jemand anderem → wir sind definitiv nicht der ML.
    -- Verhindert dass ein alter isMasterLooter=true aus den SavedVariables hängt.
    GuildLootDB.settings.isMasterLooter = false
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

--- Observer: empfängt SESSION_END vom ML, schließt Session lokal.
--- Reads:  db.raidContainers, db.activeContainerIdx
--- Writes: db.raidContainers[i].closedAt, db.activeContainerIdx,
---         db.currentRaid (via ResetCurrentRaid)
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

--- Observer: empfängt RAID_META vom ML, aktualisiert raidMeta und currentRaid-Kontext.
--- Reads:  db.raidContainers
--- Writes: db.raidContainers[i].raidMeta[raidID], db.raidContainers[i].priorityConfig,
---         db.currentRaid.id, db.currentRaid.tier, db.currentRaid.difficulty,
---         db.currentRaid.startedAt, db.currentRaid.participants
function GL.OnCommRaidMeta(sessionID, raidID, meta, prioCfg)
    local db = GuildLootDB
    for _, s in ipairs(db.raidContainers or {}) do
        if s.id == sessionID then
            -- Stub aus OnCommAssign (isStub=true) wird vom echten RAID_META überschrieben
            local existing = s.raidMeta[raidID]
            if not existing or existing.isStub then
                s.raidMeta[raidID] = meta
            end
            if prioCfg then
                s.priorityConfig = prioCfg
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

--- ML: empfängt RAID_QUERY vom Observer, schickt Session-Sync oder queued bei Combat.
--- Reads:  db.activeContainerIdx, db.raidContainers
--- Writes: GL._pendingSyncRequests
--- Sends:  Comm.SendSessionSync, Comm.SendMLAnnounce
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
    if GL.Comm and GL.Comm.SendMLAnnounce then
        GL.Comm.SendMLAnnounce(UnitName("player") or "")
    end
end

--- Observer: empfängt ML_ANNOUNCE, aktualisiert lokalen ML-State.
--- Writes: db.currentRaid.mlName, db.settings.isMasterLooter, GL._mlClaimTimer
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

--- ML: empfängt ML_REQUEST vom Observer, zeigt Bestätigungs-Dialog.
--- Writes: GL._pendingMLClaim, db.settings.isMasterLooter (bei Bestätigung)
--- Sends:  Comm.SendMLDeny (bei Ablehnung), Comm.SendMLAnnounce (bei Bestätigung)
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

--- Observer: empfängt ML_DENY vom ML, bricht Claim-Versuch ab.
--- Writes: GL._mlDenied, GL._mlClaimTimer, db.settings.isMasterLooter
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


--- Setzt den currentRaid-Kontext zurück (Slash-Command-Handler).
--- Writes: db.currentRaid (via ResetCurrentRaid)
function GL.ResetRaid()
    GL.ResetCurrentRaid()
    GL.Print("Raid context has been reset.")
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

--- Gibt die Loot-History eines Spielers in den Chat aus.
--- Reads:  db.players[*].lootHistory
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
