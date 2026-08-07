-- GuildLoot – Core_Attendance.lua
-- Attendance-Aggregat: verdichtet Season-Roster + Raid-Historie zu der Matrix, die der
-- Attendance-Tab rendert. Reine Aggregation ohne WoW-API → busted-testbar.
-- Einzige Datenquelle des Tabs: die UI rechnet nichts selbst.
-- Muss NACH Core_Guild.lua geladen werden (nutzt GL.GetSeasonRoster).

GuildLoot = GuildLoot or {}
local GL = GuildLoot

local EMPTY = function() return { season = nil, nights = {}, rows = {} } end

-- Ein Attendance-Abend ist ein Raid-TAG, nicht eine Session: eine über zwei Tage
-- fortgesetzte Session ergibt zwei Spalten, zwei Raids an einem Tag nur eine. Damit hängt
-- die Zählung nicht mehr daran, ob zwischendurch eine neue Session angelegt wurde.
-- Tagesgrenze ist der Raid-Reset um 7 Uhr — ein Kill um 01:30 zählt noch zum Vorabend.
local RAID_DAY_OFFSET = 7 * 3600

--- Mittag des Raid-Tags, zu dem ein Zeitpunkt gehört. Dient zugleich als Gruppenschlüssel.
--- Mittag statt Mitternacht, damit Sommerzeitsprünge den Tag nicht kippen.
local function RaidDayStart(ts)
    -- Schutz vor negativen Zeitstempeln: os.date bricht damit auf Windows ab
    local shifted = math.max(0, (ts or 0) - RAID_DAY_OFFSET)
    return time({
        year  = tonumber(date("%Y", shifted)),
        month = tonumber(date("%m", shifted)),
        day   = tonumber(date("%d", shifted)),
        hour  = 12, min = 0, sec = 0,
    })
end

--- Raid-Abende der Season, gruppiert nach Raid-Tag. Berücksichtigt werden Sessions, deren
--- startedAt im Season-Zeitraum liegt (gleiche Fensterlogik wie GL.GetSeasonAttendees);
--- die Kills darin werden dann nach ihrem eigenen Zeitstempel auf Tage verteilt.
--- Returns: Array von { id, label, startedAt, kills = { { id, name, ts }, … } }, neueste zuerst.
local function CollectNights(db, season)
    local from = season.startedAt or 0
    local to   = season.endedAt or time()

    local days, order = {}, {}

    local function DayFor(ts)
        local key = RaidDayStart(ts)
        local day = days[key]
        if not day then
            day = { startedAt = key, kills = {}, seen = {}, labels = {} }
            days[key] = day
            table.insert(order, key)
        end
        return day
    end

    -- Mehrere Sessions können auf denselben Tag fallen; dann nennt der Tooltip beide
    local function AddLabel(day, label)
        if not label or label == "" or day.seen[label] then return end
        day.seen[label] = true
        table.insert(day.labels, label)
    end

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
                            -- nil = nicht aufgezeichnet (Altdaten), {} = niemand war Trial
                            trials       = kill.trials,
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
            if #kills == 0 then
                -- Session ohne Bosskill: der Tag erscheint trotzdem, sonst verschwände ein
                -- abgebrochener Abend spurlos aus der Zählung
                AddLabel(DayFor(ts), session.label)
            else
                for _, kill in ipairs(kills) do
                    local day = DayFor(kill.ts)
                    table.insert(day.kills, kill)
                    AddLabel(day, session.label)
                end
            end
        end
    end

    local nights = {}
    for _, key in ipairs(order) do
        local day = days[key]
        table.sort(day.kills, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
        table.insert(nights, {
            id        = "d" .. key,
            label     = table.concat(day.labels, " · "),
            startedAt = day.startedAt,
            kills     = day.kills,
        })
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
    -- Parallel dazu der Trial-Stand von damals: name -> { [key]=true|false }, nil wo der
    -- Kill ihn nicht aufgezeichnet hat. Drei Zustände, weil "war kein Trial" und "unbekannt"
    -- unterschiedlich behandelt werden müssen.
    local presenceOf = {}
    local trialOf    = {}
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

                if kill.trials then
                    local t = trialOf[name]
                    if not t then t = {}; trialOf[name] = t end
                    local wasTrial = kill.trials[name] and true or false
                    t[kill.id] = wasTrial
                    -- Abend-Ebene: Trial, wenn bei mindestens einem Kill des Abends
                    if wasTrial or t[night.id] == nil then t[night.id] = wasTrial end
                end
            end
        end
        -- participants/trials waren nur Transportmittel; nicht Teil des Rückgabe-Vertrags
        for _, kill in ipairs(night.kills) do
            kill.participants = nil
            kill.trials       = nil
        end
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
            -- Trial-Stand je Spalte zum Zeitpunkt des Kills; nil-Einträge = nicht
            -- aufgezeichnet, dort fällt die UI auf das aktuelle Flag zurück
            trialAt  = trialOf[entry.name] or {},
            attended = attended,
            total    = total,
            pct      = (total > 0) and math.floor((attended / total) * 100 + 0.5) or 0,
            -- aktueller Stand — steuert die Checkbox, nicht die Zellfarbe
            trial    = (player and player.trial) and true or false,
        })
    end

    return { season = season, nights = nights, rows = rows }
end

--- Verdichtet die Abende zu einer flachen Spaltenliste für den Tab: aufgeklappte Abende
--- liefern eine Spalte je Bosskill, alle anderen genau eine.
---
--- Liegt hier statt in der UI, weil es die einzige nennenswerte Logik des Aufklappens ist —
--- so bleibt sie pur, in busted testbar und der Grundsatz "die UI rechnet nichts selbst"
--- gewahrt. Der Tab iteriert nur noch über das Ergebnis.
---
--- @param nights    Array aus GL.ComputeAttendance(...).nights
--- @param expanded  Set { [nightId] = true }; nil = alles eingeklappt
--- Returns: Array von {
---   key         Lookup-Schlüssel für row.present (nightId oder killId)
---   label       Kopfzeilen-Text (Datum bzw. Kill-Nummer)
---   tooltipT    Titelzeile des Tooltips
---   tooltipD    Detailzeile des Tooltips
---   nightId     zugehöriger Abend (Klick-Handler, Gruppierung)
---   isKill      true = Bosskill-Spalte
---   expandable  true wenn der Abend mehr als einen Kill hat
---   groupStart  true bei der ersten Spalte eines Abends
--- }
function GL.BuildAttendanceColumns(nights, expanded)
    expanded = expanded or {}
    local cols = {}

    for _, night in ipairs(nights or {}) do
        local kills      = night.kills or {}
        local killCount  = #kills
        -- Ein einzelner Kill ergibt aufgeklappt dieselbe eine Spalte — dann lieber gar nicht
        -- erst anbieten. Deckt zugleich Altdaten ohne kills-Ebene ab.
        local expandable = killCount > 1
        local dateLabel  = date("%d.%m", night.startedAt or 0)

        if expandable and expanded[night.id] then
            for i, kill in ipairs(kills) do
                table.insert(cols, {
                    -- voller Bossname; die UI kürzt ihn auf die Spaltenbreite
                    key        = kill.id,
                    label      = kill.name or "",
                    tooltipT   = kill.name or "",
                    -- Datum des Kills, nicht des Abends: eine über Mitternacht oder auf den
                    -- Folgetag fortgesetzte Session hat Kills mit abweichendem Datum
                    tooltipD   = date("%d.%m", kill.ts or 0) .. ", " .. date("%H:%M", kill.ts or 0)
                                 .. "  |cff888888(Boss " .. i .. "/" .. killCount
                                 .. " — klicken zum Zuklappen)|r",
                    nightId    = night.id,
                    isKill     = true,
                    expandable = true,
                    groupStart = (i == 1),
                })
            end
        else
            table.insert(cols, {
                key        = night.id,
                label      = dateLabel,
                tooltipT   = (night.label ~= "" and night.label) or dateLabel,
                tooltipD   = expandable
                             and (killCount .. " Bosse — klicken zum Aufklappen")
                             or  "Keine einzelnen Bosskills aufgezeichnet",
                nightId    = night.id,
                isKill     = false,
                expandable = expandable,
                groupStart = true,
            })
        end
    end

    return cols
end
