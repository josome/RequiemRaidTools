-- GuildLoot – Core_Season.lua
-- Season-Verwaltung: Anlegen, aktive Season, Beenden, Rang-Filter.
-- Reine DB-Mutation (keine WoW-API) → busted-testbar.
-- Muss NACH Util.lua geladen werden (nutzt GL.GenerateRaidID).

GuildLoot = GuildLoot or {}
local GL = GuildLoot

--- Erzeugt eine stabile Season-ID (djb2-Hash aus Name + Zeitstempel), Präfix "s".
local function GenerateSeasonID(name, timestamp)
    return "s" .. GL.GenerateRaidID(name or "", "season", timestamp or time())
end

--- Legt eine neue Season an und macht sie zur aktiven. Beendet dabei die bisher
--- aktive Season (endedAt-Stempel), falls sie noch offen war ("neue Season starten").
--- Reads:  db.seasons, db.activeSeasonId
--- Writes: db.seasons[id], db.activeSeasonId
--- Returns: neue Season-ID, oder nil ohne DB.
function GL.CreateSeason(name, rankFilter)
    local db = GuildLootDB
    if not db then return nil end
    db.seasons = db.seasons or {}
    local ts = time()
    -- bisher aktive Season beenden
    local prev = db.activeSeasonId and db.seasons[db.activeSeasonId]
    if prev and not prev.endedAt then prev.endedAt = ts end
    -- ID erzeugen (Kollisionsschutz bei gleichem Name + Sekunde)
    local id, n = GenerateSeasonID(name, ts), 0
    while db.seasons[id] do
        n = n + 1
        id = GenerateSeasonID((name or "") .. "#" .. n, ts)
    end
    -- nur aktivierte Ränge in den Filter übernehmen; Schlüssel als Zahl normalisieren,
    -- damit der Lookup filter[rankIndex] auch nach einem JSON-Roundtrip greift
    local filter = {}
    if type(rankFilter) == "table" then
        for k, v in pairs(rankFilter) do
            local idx = tonumber(k)
            if v and idx then filter[idx] = true end
        end
    end
    db.seasons[id] = {
        id         = id,
        name       = name or "",
        startedAt  = ts,
        endedAt    = nil,
        rankFilter = filter,
    }
    db.activeSeasonId = id
    return id
end

--- Setzt die aktive Season — also das Ziel, in das aufgezeichnet wird.
--- Beendete Seasons werden abgewiesen: sonst liefen ab Phase 1b Bosskills in eine
--- abgeschlossene Season. Zum Betrachten vergangener Seasons dient ein eigener Selektor
--- (Phase 1c), zum Wiederaufnehmen GL.ReopenSeason.
--- Returns true bei Erfolg, false wenn ID unbekannt oder die Season beendet ist.
--- Writes: db.activeSeasonId
function GL.SetActiveSeason(id)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[id]
    if not season or season.endedAt then return false end
    db.activeSeasonId = id
    return true
end

--- Nimmt eine beendete Season wieder auf (endedAt zurücksetzen) und macht sie aktiv.
--- Rückweg, wenn "Neue Season" versehentlich geklickt wurde. Beendet dabei die bisher
--- aktive Season, damit immer höchstens eine Season offen ist.
--- Returns true bei Erfolg, false wenn ID unbekannt.
--- Writes: db.seasons[id].endedAt, db.seasons[prev].endedAt, db.activeSeasonId
function GL.ReopenSeason(id)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[id]
    if not season then return false end
    local prev = db.activeSeasonId and db.seasons[db.activeSeasonId]
    if prev and prev ~= season and not prev.endedAt then prev.endedAt = time() end
    season.endedAt = nil
    db.activeSeasonId = id
    return true
end

--- Liefert die aktive Season-Tabelle (oder nil).
--- Reads: db.activeSeasonId, db.seasons
function GL.GetActiveSeason()
    local db = GuildLootDB
    if not (db and db.activeSeasonId and db.seasons) then return nil end
    return db.seasons[db.activeSeasonId]
end

--- Beendet eine Season (endedAt-Stempel). Leert activeSeasonId, falls es die aktive war.
--- Idempotent: ein bereits gesetztes endedAt bleibt stehen, ein zweiter Aufruf verschiebt
--- also nicht den Season-Zeitraum (an dem GL.GetSeasonAttendees hängt).
--- Returns true bei Erfolg, false wenn ID unbekannt.
--- Writes: db.seasons[id].endedAt, ggf. db.activeSeasonId
function GL.EndSeason(id)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[id]
    if not season then return false end
    if not season.endedAt then season.endedAt = time() end
    if db.activeSeasonId == id then db.activeSeasonId = nil end
    return true
end

--- Löscht eine Season. Betrifft NUR den Season-Eintrag (Name, Zeitfenster, Rang-Filter) —
--- Raid-Sessions und Loot bleiben unangetastet, Attendance wird ohnehin daraus abgeleitet.
--- War es die aktive Season, bleibt danach keine aktiv.
--- Returns true bei Erfolg, false wenn ID unbekannt.
--- Writes: db.seasons[id] = nil, ggf. db.activeSeasonId
function GL.DeleteSeason(id)
    local db = GuildLootDB
    if not (db and db.seasons and db.seasons[id]) then return false end
    db.seasons[id] = nil
    if db.activeSeasonId == id then db.activeSeasonId = nil end
    return true
end

--- Benennt eine Season um. Die ID bleibt unangetastet — sie wird zwar aus dem Namen
--- erzeugt, ist danach aber der Schlüssel in db.seasons und die Referenz in
--- db.activeSeasonId; sie mitzuändern würde beides brechen.
--- Leere Namen werden abgewiesen: der Dropdown zeigte sonst nur "(ohne Namen)".
--- Doppelte Namen sind erlaubt, wie beim Anlegen auch — unterschieden wird über die ID.
--- Returns true bei Erfolg, false bei unbekannter ID oder leerem Namen.
--- Writes: db.seasons[id].name
function GL.RenameSeason(id, name)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[id]
    if not season then return false end
    name = tostring(name or ""):match("^%s*(.-)%s*$")   -- trimmen
    if name == "" then return false end
    season.name = name
    return true
end

--- Setzt das Startdatum einer Season. Nötig, weil eine heute angelegte Season sonst alle
--- bereits vorhandenen Raid-Sessions aus ihrem Zeitfenster ausschließt — die Matrix bliebe
--- leer, obwohl Daten da sind. Zugleich die Grundlage für das Nachtragen alter Raids.
--- endedAt bleibt unangetastet; ein Start nach dem Ende wird abgewiesen.
--- Returns true bei Erfolg, false wenn ID oder Zeitstempel unbrauchbar.
--- Writes: db.seasons[id].startedAt
function GL.SetSeasonStart(id, timestamp)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[id]
    if not season then return false end
    timestamp = tonumber(timestamp)
    if not timestamp or timestamp <= 0 then return false end
    if season.endedAt and timestamp > season.endedAt then return false end
    season.startedAt = timestamp
    return true
end

--- Setzt/entfernt einen Rang im Rang-Filter einer Season.
--- Returns true bei Erfolg, false wenn ID oder rankIndex unbrauchbar.
--- Writes: db.seasons[id].rankFilter[rankIndex]
function GL.SetSeasonRankFilter(id, rankIndex, enabled)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[id]
    if not season then return false end
    rankIndex = tonumber(rankIndex)
    if not rankIndex then return false end
    season.rankFilter = season.rankFilter or {}
    season.rankFilter[rankIndex] = enabled and true or nil
    return true
end

--- Setzt den Rang-Filter auf "dieser Rang und alle höheren" (rankIndex 0 = Gildenmeister,
--- aufsteigend = niedriger). Bedienhilfe über GL.SetSeasonRankFilter — der Kader besteht in
--- der Praxis aus Raider plus allem darüber (Offiziere, GM), und das soll ein Klick sein.
--- Ersetzt die bisherige Auswahl vollständig; einzelne Ränge lassen sich danach wieder
--- abwählen (Gilden mit einem Nicht-Raider-Rang oberhalb von Raider).
--- Returns true bei Erfolg, false wenn ID oder rankIndex unbrauchbar.
--- Writes: db.seasons[id].rankFilter
function GL.SetSeasonRankThreshold(id, rankIndex)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[id]
    if not season then return false end
    rankIndex = tonumber(rankIndex)
    if not rankIndex then return false end
    local filter = {}
    for i = 0, rankIndex do filter[i] = true end
    season.rankFilter = filter
    return true
end
