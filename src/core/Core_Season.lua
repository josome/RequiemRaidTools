-- GuildLoot – Core_Season.lua
-- Season-Verwaltung: Anlegen, aktive Season, Beenden, Rang-Filter.
-- Reine DB-Mutation (keine WoW-API) → busted-testbar.
-- Muss NACH Core_DB.lua geladen werden (nutzt GL.GenerateRaidID aus Util.lua).

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
    -- nur aktivierte Ränge in den Filter übernehmen
    local filter = {}
    if type(rankFilter) == "table" then
        for k, v in pairs(rankFilter) do
            if v then filter[k] = true end
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

--- Setzt die aktive Season. Returns true bei Erfolg, false wenn ID unbekannt.
--- Writes: db.activeSeasonId
function GL.SetActiveSeason(id)
    local db = GuildLootDB
    if not (db and db.seasons and db.seasons[id]) then return false end
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
--- Returns true bei Erfolg, false wenn ID unbekannt.
--- Writes: db.seasons[id].endedAt, ggf. db.activeSeasonId
function GL.EndSeason(id)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[id]
    if not season then return false end
    season.endedAt = time()
    if db.activeSeasonId == id then db.activeSeasonId = nil end
    return true
end

--- Setzt/entfernt einen Rang im Rang-Filter einer Season.
--- Returns true bei Erfolg, false wenn ID unbekannt.
--- Writes: db.seasons[id].rankFilter[rankIndex]
function GL.SetSeasonRankFilter(id, rankIndex, enabled)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[id]
    if not season then return false end
    season.rankFilter = season.rankFilter or {}
    season.rankFilter[rankIndex] = enabled and true or nil
    return true
end
