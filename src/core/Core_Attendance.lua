-- GuildLoot – Core_Attendance.lua
-- Attendance-Aggregat: verdichtet Season-Roster + Raid-Historie zu der Matrix, die der
-- Attendance-Tab rendert. Reine Aggregation ohne WoW-API → busted-testbar.
-- Einzige Datenquelle des Tabs: die UI rechnet nichts selbst.
-- Muss NACH Core_Guild.lua geladen werden (nutzt GL.GetSeasonRoster).

GuildLoot = GuildLoot or {}
local GL = GuildLoot

local EMPTY = function() return { season = nil, nights = {}, rows = {} } end

--- Raid-Abende der Season = Sessions, deren startedAt im Season-Zeitraum liegt.
--- Gleiche Fensterlogik wie GL.GetSeasonAttendees.
--- Returns: Array von { id, label, startedAt, kills = { { id, name, ts }, … } }, neueste zuerst.
local function CollectNights(db, season)
    local from = season.startedAt or 0
    local to   = season.endedAt or time()

    local nights = {}
    for _, session in ipairs(db.raidContainers or {}) do
        local ts = session.startedAt or 0
        if ts >= from and ts <= to then
            local kills = {}
            for raidID, meta in pairs(session.raidMeta or {}) do
                -- participants bleiben in beiden Zweigen erhalten, damit die Präsenz in
                -- einem zweiten Durchlauf ohne erneuten DB-Zugriff aufgebaut werden kann
                if meta.kills and #meta.kills > 0 then
                    -- Boss-Ebene, ab Phase 1b von GL.RecordKillAttendance aufgezeichnet
                    for i, kill in ipairs(meta.kills) do
                        table.insert(kills, {
                            id           = raidID .. "#" .. i,
                            name         = (kill.boss ~= "" and kill.boss) or meta.tier,
                            ts           = kill.ts or meta.startedAt or ts,
                            participants = kill.participants or {},
                        })
                    end
                else
                    -- Altdaten und Observer-Sessions: ein Eintrag je raidMeta, Teilnehmer
                    -- nur auf Abend-Ebene bekannt
                    table.insert(kills, {
                        id           = raidID,
                        name         = meta.tier,
                        ts           = meta.startedAt or ts,
                        participants = meta.participants or {},
                    })
                end
            end
            table.sort(kills, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
            table.insert(nights, {
                id        = session.id or ("night" .. #nights + 1),
                label     = session.label or "",
                startedAt = ts,
                kills     = kills,
            })
        end
    end
    table.sort(nights, function(a, b) return (a.startedAt or 0) > (b.startedAt or 0) end)
    return nights
end

--- Attendance-Matrix für eine Season.
--- Zeilen-Achse (Y) = Raider aus GL.GetSeasonRoster (Kader-Block, darunter Gäste).
--- Spalten-Achse (X) = Raid-Abende, je mit ihren Bosskills.
---
--- Pro Zeile:
---   present[nightId] = true  — an diesem Abend dabei (Vereinigung aller Kills des Abends)
---   present[killId]  = true  — bei diesem Bosskill dabei
---   attended/total   — besuchte Abende / Abende der Season
---   pct              — attended/total in ganzen Prozent, 0 wenn total == 0
---   trial            — db.players[name].trial (nur Flag; Loot-Effekt ist Phase 2)
---
--- Die kills-Ebene kommt aus raidMeta[*].kills (GL.RecordKillAttendance, ein Eintrag je
--- Bosskill). Fehlt sie — Altdaten von vor Phase 1b oder eine über RAID_META empfangene
--- Observer-Session — bleibt es bei einem Eintrag je raidMeta mit den Teilnehmern des
--- Abends. Die Abend-Ebene stimmt in beiden Fällen.
---
--- Reads:  db.seasons[seasonId], db.raidContainers, db.players, GL.GetSeasonRoster
--- Returns: { season, nights, rows } — bei unbekannter Season/fehlender DB leere Listen.
function GL.ComputeAttendance(seasonId)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[seasonId]
    if not season then return EMPTY() end

    local nights  = CollectNights(db, season)
    local players = db.players or {}

    -- Präsenz einmal vorberechnen: name -> { [nightId]=true, [killId]=true }
    local presenceOf = {}
    local attendedOf = {}
    for _, night in ipairs(nights) do
        for _, kill in ipairs(night.kills) do
            for _, name in ipairs(kill.participants) do
                local p = presenceOf[name]
                if not p then p = {}; presenceOf[name] = p end
                p[kill.id] = true
                if not p[night.id] then
                    p[night.id] = true
                    attendedOf[name] = (attendedOf[name] or 0) + 1
                end
            end
        end
        -- participants waren nur Transportmittel; nicht Teil des Rückgabe-Vertrags
        for _, kill in ipairs(night.kills) do kill.participants = nil end
    end

    local total = #nights
    local rows  = {}
    for _, entry in ipairs(GL.GetSeasonRoster(seasonId)) do
        local attended = attendedOf[entry.name] or 0
        local player   = players[entry.name]
        table.insert(rows, {
            name     = entry.name,
            class    = entry.class,
            group    = entry.group,
            present  = presenceOf[entry.name] or {},
            attended = attended,
            total    = total,
            pct      = (total > 0) and math.floor((attended / total) * 100 + 0.5) or 0,
            trial    = (player and player.trial) and true or false,
        })
    end

    return { season = season, nights = nights, rows = rows }
end
