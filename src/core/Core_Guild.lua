-- GuildLoot – Core_Guild.lua
-- Gildenroster-Anbindung: Mitglieder + Rang-Namen aus der WoW-API und daraus
-- das Season-Roster (Zeilen-Achse der Attendance-Matrix), gefiltert nach dem
-- Rang-Filter der Season. WoW-API hinter dünnen, mockbaren Wrappern → busted-testbar.
-- Muss NACH Core_Season.lua geladen werden (nutzt GL.NormalizeName, GL.GetSeasonAttendees).

GuildLoot = GuildLoot or {}
local GL = GuildLoot

--- Stößt eine Aktualisierung des Gildenrosters an (WoW liefert die Daten asynchron
--- über GUILD_ROSTER_UPDATE nach). No-Op wenn die API fehlt.
function GL.RefreshGuildRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
end

--- Liest die aktuellen Gildenmitglieder aus der WoW-API.
--- Returns: Array von { name (realm-qualifiziert), rankIndex (0-basiert), class (classFileName) }.
---          Leer, wenn nicht in einer Gilde oder die API fehlt.
function GL.GetGuildMembers()
    local members = {}
    if not (IsInGuild and IsInGuild()) then return members end
    local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
    for i = 1, n do
        local name, _, rankIndex, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            table.insert(members, {
                name      = GL.NormalizeName(name),
                rankIndex = rankIndex or 0,
                class     = classFile,
            })
        end
    end
    return members
end

--- Rang-Namen der Gilde, gemappt auf den 0-basierten rankIndex (wie ihn
--- GetGuildRosterInfo liefert): names[rankIndex] = Anzeigename. WoW' GuildControlGetRankName
--- ist 1-basiert (1 = Gildenmeister), daher rankIndex+1. Für die Rang-Checkboxen im Settings-UI.
--- Returns: Tabelle { [0]=name, [1]=name, ... }; leer wenn API fehlt.
function GL.GetGuildRankNames()
    local names = {}
    if not (GuildControlGetNumRanks and GuildControlGetRankName) then return names end
    local n = GuildControlGetNumRanks() or 0
    for i = 0, n - 1 do
        names[i] = GuildControlGetRankName(i + 1) or ("Rank " .. i)
    end
    return names
end

--- Namen mit Attendance in der Season (für die Vereinigung im Season-Roster, damit
--- ausgetretene Spieler in vergangenen Seasons sichtbar bleiben).
--- PHASE-1a-PLATZHALTER: liefert noch {} — die Ableitung aus der Kill-/Session-Historie
--- kommt mit Phase 1b/1c. Als eigener Seam gehalten, damit GetSeasonRoster schon testbar ist.
--- Returns: Array von Namen (realm-qualifiziert).
function GL.GetSeasonAttendees(seasonId)  -- luacheck: ignore seasonId
    return {}
end

--- Season-Roster = Zeilen-Achse der Attendance-Matrix.
--- Menge = aktuelle Gildenmitglieder, deren rankIndex im rankFilter der Season aktiv ist,
---         VEREINIGT mit allen Namen mit Attendance in der Season (GL.GetSeasonAttendees).
--- Reads:  db.seasons[seasonId].rankFilter, Gilden-API, GL.GetSeasonAttendees
--- Returns: nach Name sortiertes Array von { name, class }. Leer bei unbekannter Season.
function GL.GetSeasonRoster(seasonId)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[seasonId]
    if not season then return {} end
    local filter = season.rankFilter or {}

    local present = {}   -- name -> true
    local classOf = {}   -- name -> classFileName
    -- 1) aktuelle Gildenmitglieder mit aktivem Rang
    for _, m in ipairs(GL.GetGuildMembers()) do
        if filter[m.rankIndex] then
            present[m.name] = true
            classOf[m.name] = m.class
        end
    end
    -- 2) Vereinigung mit Season-Attendees (Klasse ggf. unbekannt)
    for _, name in ipairs(GL.GetSeasonAttendees(seasonId)) do
        present[name] = true
    end

    local out = {}
    for name in pairs(present) do
        table.insert(out, { name = name, class = classOf[name] })
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end
