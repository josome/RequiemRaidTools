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

-- Prio 1 = "BIS" (siehe db.settings.priorities in Core_DB.lua). Nur dieser Gewinn wird in
-- der Matrix markiert.
local BIS_PRIO = 1

--- Vereinigt zwei Sets zu einem neuen; nil-Eingaben sind erlaubt, nil-Ergebnis wenn beide
--- leer sind (so bleibt "nicht aufgezeichnet" von "niemand" unterscheidbar).
local function MergeSets(a, b)
    if not a and not b then return nil end
    local out = {}
    for k in pairs(a or {}) do out[k] = true end
    for k in pairs(b or {}) do out[k] = true end
    return out
end

--- Ordnet die BIS-Loot-Einträge eines raidMeta seinen Kills zu.
--- Zuordnung über den Bossnamen; kam derselbe Boss im selben raidID mehrfach vor, gewinnt
--- der letzte Kill VOR dem Loot-Zeitstempel. Ohne Zeitstempel (Altdaten) der erste Treffer.
--- @param entries table  BIS-Einträge dieses raidID
--- @param kills   table  Array der Kill-Rohdaten (mit .boss und .ts)
--- @return table  index → { [name] = true }
local function MapBisToKills(entries, kills)
    local out = {}
    for _, e in ipairs(entries or {}) do
        local best = nil
        for i, kill in ipairs(kills) do
            if (kill.boss or "") ~= "" and kill.boss == e.boss then
                if not e.timestamp or not kill.ts then
                    best = best or i
                elseif kill.ts <= e.timestamp
                       and (not best or (kills[best].ts or 0) < kill.ts) then
                    best = i
                end
            end
        end
        if best then
            local set = out[best]
            if not set then set = {}; out[best] = set end
            set[e.player] = true
        end
    end
    return out
end

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
            -- emptySessions: Sessions, die zu diesem Tag KEINEN Kill beisteuern. Nur solche
            -- Spalten lassen sich im Tab entfernen — bei einer Spalte mit Kills wäre nicht
            -- klar, was gemeint ist.
            day = { startedAt = key, kills = {}, seen = {}, labels = {}, emptySessions = {} }
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
            -- BIS-Gewinne dieser Session, gruppiert nach raidID. Bewusst aus dem lootLog
            -- abgeleitet statt am Kill gespeichert: der Kill entsteht beim Boss, der Roll
            -- kommt später — ein gespeicherter Marker müsste nachträglich editiert werden.
            local bisByRaid = {}
            for _, e in ipairs(session.lootLog or {}) do
                -- tonumber: lokal ist winnerPrio eine Zahl, über Comm kommt sie als String
                if tonumber(e.winnerPrio) == BIS_PRIO and e.player and e.raidID then
                    local list = bisByRaid[e.raidID]
                    if not list then list = {}; bisByRaid[e.raidID] = list end
                    table.insert(list, e)
                end
            end

            local kills = {}
            for raidID, meta in pairs(session.raidMeta or {}) do
                -- participants bleiben in beiden Zweigen erhalten, damit die Präsenz in
                -- einem zweiten Durchlauf ohne erneuten DB-Zugriff aufgebaut werden kann
                if meta.kills and #meta.kills > 0 then
                    -- Boss-Ebene, ab Phase 1b von GL.RecordKillAttendance aufgezeichnet
                    local bisPerKill = MapBisToKills(bisByRaid[raidID], meta.kills)
                    for i, kill in ipairs(meta.kills) do
                        table.insert(kills, {
                            id           = raidID .. "#" .. i,
                            name         = (kill.boss ~= "" and kill.boss) or meta.tier,
                            ts           = kill.ts or meta.startedAt or ts,
                            -- Rückweg zu den Daten, damit der Tab einen Kill löschen kann
                            sessionId    = session.id,
                            raidID       = raidID,
                            killIndex    = i,
                            -- "N"/"H"/"M"; hängt am raidMeta, nicht am einzelnen Kill
                            difficulty   = meta.difficulty,
                            -- Raidinstanz, für den Trennstrich zwischen Instanzen
                            tier         = meta.tier,
                            participants = kill.participants or {},
                            -- nil = nicht aufgezeichnet (Altdaten), {} = niemand war Trial
                            trials       = kill.trials,
                            -- BIS-Gewinner: aus dem lootLog abgeleitet VEREINIGT mit einem
                            -- gespeicherten kill.bis. Importierte Abende haben keinen
                            -- lootLog, selbst geraidete kein kill.bis — nur zusammen decken
                            -- sie beide Fälle ab, ohne sich gegenseitig zu verdrängen.
                            bisWinners   = MergeSets(bisPerKill[i], kill.bis),
                        })
                    end
                else
                    -- Altdaten und Observer-Sessions: ein Eintrag je raidMeta, Teilnehmer
                    -- nur auf Abend-Ebene bekannt. Ohne Kill-Ebene fallen alle BIS-Gewinne
                    -- des Raids auf diese eine Spalte.
                    local bisAll = nil
                    for _, e in ipairs(bisByRaid[raidID] or {}) do
                        bisAll = bisAll or {}
                        bisAll[e.player] = true
                    end
                    table.insert(kills, {
                        id           = raidID,
                        name         = meta.tier,
                        ts           = meta.startedAt or ts,
                        difficulty   = meta.difficulty,
                        tier         = meta.tier,
                        participants = meta.participants or {},
                        -- ohne killIndex: die Spalte steht für den ganzen raidMeta-Eintrag
                        sessionId    = session.id,
                        raidID       = raidID,
                        bisWinners   = bisAll,
                    })
                end
            end
            if #kills == 0 then
                -- Session ohne Bosskill: der Tag erscheint trotzdem, sonst verschwände ein
                -- abgebrochener Abend spurlos aus der Zählung
                local day = DayFor(ts)
                AddLabel(day, session.label)
                table.insert(day.emptySessions, session.id)
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
            -- nur gefüllt, solange der Tag gar keinen Kill hat — dann ist die Spalte
            -- eindeutig einer oder mehreren leeren Sessions zuzuordnen
            emptySessions = (#day.kills == 0) and day.emptySessions or nil,
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
    local bisOf      = {}
    local attendedOf = {}
    for _, night in ipairs(nights) do
        for _, kill in ipairs(night.kills) do
            for _, name in ipairs(kill.participants) do
                -- Schlüssel statt Rohname: der Kader kommt aus dem Gildenroster, die
                -- Teilnehmer aus der Raid-API — beide können denselben Spieler in
                -- unterschiedlicher Realm-Schreibweise liefern (siehe GL.NameKey).
                -- Ohne das bliebe eine Kader-Zeile trotz Teilnahme auf 0 %.
                local key = GL.NameKey(name)
                local p = presenceOf[key]
                if not p then p = {}; presenceOf[key] = p end
                p[kill.id] = true
                if not p[night.id] then
                    p[night.id] = true
                    attendedOf[key] = (attendedOf[key] or 0) + 1
                end

                -- BIS-Gewinn: markiert den Kill und den Abend (mindestens ein Gewinn am Tag)
                if kill.bisWinners and kill.bisWinners[name] then
                    local b = bisOf[key]
                    if not b then b = {}; bisOf[key] = b end
                    b[kill.id]  = true
                    b[night.id] = true
                end

                if kill.trials then
                    local t = trialOf[key]
                    if not t then t = {}; trialOf[key] = t end
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
            kill.bisWinners   = nil
        end
    end

    local total = #nights
    local rows  = {}
    for _, entry in ipairs(GL.GetSeasonRoster(seasonId)) do
        local key      = GL.NameKey(entry.name)
        local attended = attendedOf[key] or 0
        local player   = players[entry.name]
        table.insert(rows, {
            name     = entry.name,
            class    = entry.class,
            group    = entry.group,
            present  = presenceOf[key] or {},
            -- Trial-Stand je Spalte zum Zeitpunkt des Kills; nil-Einträge = nicht
            -- aufgezeichnet, dort fällt die UI auf das aktuelle Flag zurück
            trialAt  = trialOf[key] or {},
            -- Spalten, in denen diese Person Loot mit Prio BIS gewonnen hat
            bisAt    = bisOf[key] or {},
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
---   label       Kopfzeilen-Text (Datum bzw. Bossname)
---   groupLabel  Session-Name des Abends; die UI schreibt ihn über eine aufgeklappte Gruppe
---   tooltipT    Titelzeile des Tooltips
---   tooltipD    Detailzeile des Tooltips
---   nightId     zugehöriger Abend (Klick-Handler, Gruppierung)
---   isKill      true = Bosskill-Spalte
---   expandable  true wenn der Abend mehr als einen Kill hat
---   groupStart  true bei der ersten Spalte eines Abends
--- }
--- Difficulty eines ganzen Abends — nur wenn alle Kills dieselbe haben. Ein Abend, in dem
--- von Heroisch auf Mythisch gewechselt wurde, bekommt keine, statt eine zu behaupten.
local function UnifiedDifficulty(kills)
    local found = nil
    for _, kill in ipairs(kills) do
        local d = kill.difficulty
        if d and d ~= "" then
            if found == nil then
                found = d
            elseif found ~= d then
                return nil
            end
        end
    end
    return found
end

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
        -- Über der aufgeklappten Gruppe steht der Session-Name; ohne Namen das Datum,
        -- damit die Gruppe nie unbeschriftet bleibt
        local groupLabel = (night.label ~= "" and night.label) or dateLabel

        if expandable and expanded[night.id] then
            local prevTier = nil
            for i, kill in ipairs(kills) do
                -- Wechselt die Raidinstanz mitten im Abend, bekommt die erste Spalte der
                -- neuen Instanz einen Trennstrich. Die allererste braucht keinen — dort
                -- sitzt schon der Gruppentrenner.
                local instanceStart = (i > 1) and (kill.tier ~= prevTier) or false
                prevTier = kill.tier
                table.insert(cols, {
                    -- voller Bossname; die UI kürzt ihn auf die Spaltenbreite
                    key        = kill.id,
                    label      = kill.name or "",
                    tooltipT   = kill.name or "",
                    -- Datum des Kills, nicht des Abends: eine über Mitternacht oder auf den
                    -- Folgetag fortgesetzte Session hat Kills mit abweichendem Datum
                    tooltipD   = date("%d.%m", kill.ts or 0) .. ", " .. date("%H:%M", kill.ts or 0)
                                 .. ((kill.difficulty and kill.difficulty ~= "")
                                     and ("  ·  " .. kill.difficulty) or "")
                                 .. "  |cff888888(Boss " .. i .. "/" .. killCount
                                 .. " — klicken zum Zuklappen)|r",
                    groupLabel = groupLabel,
                    difficulty = kill.difficulty,
                    -- Rückweg zum Löschen
                    sessionId  = kill.sessionId,
                    raidID     = kill.raidID,
                    killIndex  = kill.killIndex,
                    nightId       = night.id,
                    isKill        = true,
                    expandable    = true,
                    groupStart    = (i == 1),
                    instanceStart = instanceStart,
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
                groupLabel = groupLabel,
                -- nur wenn der ganze Abend eine Difficulty hatte
                difficulty = UnifiedDifficulty(kills),
                -- Tag ganz ohne Kill: die Spalte gehört zu leeren Sessions und lässt sich
                -- als solche entfernen. Bei einer Spalte mit Kills bleibt das leer.
                emptySessions = night.emptySessions,
                -- Steht hinter der Spalte GENAU EIN Eintrag, ist sie eindeutig und damit
                -- direkt löschbar — ohne sie aufklappen zu müssen. Das ist der Fall bei
                -- Altdaten ohne Kill-Ebene (killIndex bleibt nil, dann geht der ganze
                -- raidMeta-Eintrag) und bei einem Abend mit einem einzigen Bosskill.
                sessionId  = (killCount == 1) and kills[1].sessionId or nil,
                raidID     = (killCount == 1) and kills[1].raidID    or nil,
                killIndex  = (killCount == 1) and kills[1].killIndex or nil,
                nightId    = night.id,
                isKill     = false,
                expandable = expandable,
                groupStart = true,
            })
        end
    end

    return cols
end

-- ============================================================
-- CSV-Export / -Import
-- ============================================================

-- Die erste Spalte sagt, was die Zeile ist. So trägt eine flache Datei sowohl die
-- Season-Stammdaten als auch die Kills, bleibt zeilenweise eindeutig lesbar und lässt sich
-- in einer Tabellenkalkulation nach Typ filtern.
-- Die Kopfzeile beschreibt die Kill-Zeilen (die überwiegende Mehrheit); Season-, Rank- und
-- Roster-Zeilen sind kürzer und über ihr Schlüsselwort selbsterklärend.
local CSV_HEADER = "Type,Date,Time,Instance,Difficulty,Boss,Player,BIS,Trial"

--- Feld für die CSV maskieren — dieselbe Regel wie GL.ExportCSV.
local function Esc(s)
    s = tostring(s or "")
    if s:find('[",\n]') then s = '"' .. s:gsub('"', '""') .. '"' end
    return s
end

--- Exportiert die Attendance einer Season als CSV: eine Zeile je Teilnehmer und Bosskill.
---
--- Bewusst zeilenweise statt verschachtelt: so bleibt jede Zelle atomar, die Datei ist in
--- einer Tabellenkalkulation filter- und sortierbar, und Nachtragen heißt Zeilen kopieren.
--- Die Season selbst steht NICHT in den Zeilen — der Import ordnet über das Datum zu.
---
--- Der BIS-Marker reist als eigene Spalte mit: er wird sonst aus dem lootLog abgeleitet, und
--- der gehört zur Session, nicht zur Season — nach einem Reimport wäre er sonst verloren.
---
--- Reads: GL.ComputeAttendance
--- @return string  CSV inklusive Kopfzeile
function GL.ExportSeasonCSV(seasonId)
    local data  = GL.ComputeAttendance(seasonId)
    local lines = { CSV_HEADER }

    -- Season-Stammdaten voran: ohne sie ließe sich die Season anderswo nicht wiederherstellen,
    -- man müsste Name, Fenster, Rang-Filter und Kader von Hand nachbauen.
    local season = data.season
    if season then
        table.insert(lines, table.concat({
            "Season",
            Esc(season.name or ""),
            Esc(season.startedAt and date("%Y-%m-%d", season.startedAt) or ""),
            Esc(season.endedAt  and date("%Y-%m-%d", season.endedAt)  or ""),
            Esc(season.rosterGuild or ""),
        }, ","))
        local ranks = {}
        for idx, on in pairs(season.rankFilter or {}) do
            if on and tonumber(idx) then table.insert(ranks, tonumber(idx)) end
        end
        table.sort(ranks)
        for _, idx in ipairs(ranks) do
            table.insert(lines, "Rank," .. idx)
        end
        for _, m in ipairs(season.roster or {}) do
            table.insert(lines, table.concat({ "Roster", Esc(m.name), Esc(m.class or "") }, ","))
        end
    end

    -- nights kommen neueste zuerst; für eine Datei ist chronologisch die bessere Ordnung
    local nights = {}
    for _, night in ipairs(data.nights) do table.insert(nights, night) end
    table.sort(nights, function(a, b) return (a.startedAt or 0) < (b.startedAt or 0) end)

    for _, night in ipairs(nights) do
        for _, kill in ipairs(night.kills) do
            local present = {}
            for _, row in ipairs(data.rows) do
                if row.present[kill.id] then table.insert(present, row) end
            end
            table.sort(present, function(a, b) return a.name:lower() < b.name:lower() end)
            for _, row in ipairs(present) do
                table.insert(lines, table.concat({
                    "Kill",
                    Esc(date("%Y-%m-%d", kill.ts or 0)),
                    Esc(date("%H:%M",    kill.ts or 0)),
                    Esc(kill.tier or ""),
                    Esc(kill.difficulty or ""),
                    Esc(kill.name or ""),
                    Esc(row.name),
                    row.bisAt[kill.id] and "x" or "",
                    row.trialAt[kill.id] and "x" or "",
                }, ","))
            end
        end
    end
    return table.concat(lines, "\n")
end

--- Liest eine CSV im Format von GL.ExportSeasonCSV und trägt die Raids nach.
---
--- Zielt NICHT auf eine Season: die Zuordnung läuft über das Datum, eine importierte Session
--- landet automatisch in der Season, deren Zeitfenster den Tag abdeckt — dieselbe Regel wie
--- für selbst geraidete Abende.
---
--- **Ergänzt, überschreibt nie.** Ein Kill mit gleicher raidID, gleichem Boss und gleichem
--- Zeitstempel wird übersprungen; ein zweiter Import derselben Datei ändert also nichts.
--- Angefasst werden ausschließlich Sessions mit source == "import" — selbst aufgezeichnete
--- Abende bleiben unberührt, auch wenn sie am selben Tag liegen.
---
--- Writes: db.raidContainers
--- @return table  { kills, rows, skipped, bad } — Zusammenfassung für die Meldung
function GL.ImportAttendanceCSV(text)
    local db = GuildLootDB
    local stats = { kills = 0, rows = 0, skipped = 0, bad = 0 }
    if not db then return stats end
    db.raidContainers = db.raidContainers or {}

    -- 1. Zeilen einsammeln. Die erste Spalte sagt, worum es sich handelt.
    local killOrder, killByKey = {}, {}
    local meta = nil                       -- Season-Stammdaten aus der Datei
    local ranks, roster = {}, {}

    local function ParseDay(d, t)
        local y, mo, dy = tostring(d or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
        local hh, mi    = tostring(t or ""):match("^(%d%d?):(%d%d)$")
        if not y then return nil end
        -- Vor 1971 bricht time() ab: der Zeitzonenversatz schiebt den 1.1.1970 vor die
        -- Epoche. Betrifft Seasons ohne gesetztes Startdatum, die als 1970-01-01 exportiert
        -- werden — dann lieber kein Datum als ein Fehler.
        if tonumber(y) < 1971 then return nil end
        local ok, ts = pcall(time, {
            year = tonumber(y), month = tonumber(mo), day = tonumber(dy),
            hour = tonumber(hh or 0), min = tonumber(mi or 0), sec = 0,
        })
        return ok and ts or nil
    end

    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local f    = GL.ParseCSVLine(line)
        local kind = f[1]
        if kind == "Type" then                                  -- Kopfzeile
        elseif kind == "Season" then
            meta = {
                name    = f[2] or "",
                startAt = ParseDay(f[3], "00:00"),
                endAt   = ParseDay(f[4], "23:59"),
                guild   = (f[5] ~= "" and f[5]) or nil,
            }
        elseif kind == "Rank" then
            local idx = tonumber(f[2])
            if idx then ranks[idx] = true end
        elseif kind == "Roster" then
            if f[2] and f[2] ~= "" then
                table.insert(roster, { name = GL.NormalizeName(f[2]),
                                       class = (f[3] ~= "" and f[3]) or nil })
            end
        elseif kind == "Kill" then
            local d, t, tier, diff, boss, player = f[2], f[3], f[4], f[5], f[6], f[7]
            local ts = ParseDay(d, t)
            if not (ts and t and t:match("^%d%d?:%d%d$") and player and player ~= "") then
                stats.bad = stats.bad + 1
            else
                local key = table.concat({ d, t, tier or "", diff or "", boss or "" }, "\0")
                local k = killByKey[key]
                if not k then
                    k = { ts = ts, day = d, tier = tier or "", diff = diff or "",
                          boss = boss or "", participants = {}, seen = {},
                          bis = {}, trials = {} }
                    killByKey[key] = k
                    table.insert(killOrder, k)
                end
                local pn = GL.NormalizeName(player)
                -- Doppelte Zeilen für denselben Spieler und Kill zusammenfassen: eine CSV
                -- aus einer bereits doppelt befüllten DB enthält sie zwangsläufig, und ohne
                -- das stünde der Name zweimal in der Teilnehmerliste — ein erneuter Export
                -- reichte die Dublette dann weiter.
                if not k.seen[pn] then
                    k.seen[pn] = true
                    table.insert(k.participants, pn)
                end
                if (f[8] or ""):lower() == "x" then k.bis[pn]    = true end
                if (f[9] or ""):lower() == "x" then k.trials[pn] = true end
                stats.rows = stats.rows + 1
            end
        else
            stats.bad = stats.bad + 1
        end
    end

    -- 2. Season anlegen, falls sie fehlt. Eine vorhandene bleibt unangetastet — ihre
    -- Stammdaten könnten lokal bewusst anders sein, und "ergänzt, überschreibt nie" gilt
    -- hier genauso wie für die Kills.
    if meta and meta.name ~= "" then
        -- Ohne brauchbares Startdatum vom frühesten Kill ableiten: sonst begänne das Fenster
        -- bei "jetzt" und die gerade importierten Raids fielen alle heraus.
        -- Nicht der Kill-Zeitpunkt selbst, sondern Mitternacht seines Raid-Tags — das Fenster
        -- vergleicht gegen session.startedAt, und die Session beginnt vor ihrem ersten Boss.
        if not meta.startAt then
            local earliest = nil
            for _, k in ipairs(killOrder) do
                if not earliest or k.ts < earliest then earliest = k.ts end
            end
            if earliest then meta.startAt = RaidDayStart(earliest) - 12 * 3600 end
        end
        -- Die Season-Invariante "höchstens eine offene Season" (Core_Season.lua) gilt auch
        -- hier: kein Enddatum heißt "offen". Läuft schon eine andere Season, darf die
        -- importierte nicht als ZWEITE offene daneben stehen — sonst wäre sie weder aktiv
        -- noch beendet, und [Resume] (das nur auf beendete Seasons wirkt) griffe ins Leere.
        -- Ohne CSV-Enddatum bekommt sie deshalb eins: das späteste importierte Kill-Datum.
        -- Lief vorher NICHTS, wird sie stattdessen selbst aktiv — da gibt es nichts zu
        -- beenden, und der Weitergabe-Fall (leere DB) bekommt eine sofort nutzbare Season.
        local wasActive = db.activeSeasonId ~= nil
        if not meta.endAt and wasActive then
            local latest = nil
            for _, k in ipairs(killOrder) do
                if not latest or k.ts > latest then latest = k.ts end
            end
            meta.endAt = latest or time()
        end

        if GL.FindSeasonByName(meta.name) then
            stats.seasonExisted = true
        else
            local newId = GL.CreateSeasonFromImport(
                meta.name, meta.startAt, meta.endAt, ranks,
                (#roster > 0) and roster or nil, meta.guild)
            stats.seasonCreated = newId ~= nil
            if newId and not meta.endAt and not wasActive then
                GL.SetActiveSeason(newId)
            end
        end
    end

    -- 3. Je Raid-Tag eine Session; vorhandene Import-Session desselben Tages weiterverwenden
    local function SessionForDay(day, ts)
        local id = "import-" .. day
        for _, s in ipairs(db.raidContainers) do
            if s.id == id then return s end
        end
        local s = {
            id          = id,
            label       = "Import " .. day,
            startedAt   = ts,
            closedAt    = ts,
            source      = "import",
            raidMeta    = {},
            lootLog     = {},
            trashedLoot = {},
            pendingLoot = {},
        }
        table.insert(db.raidContainers, s)
        return s
    end

    --- Gibt es diesen Kill schon irgendwo? Geprüft wird über ALLE Sessions, nicht nur die
    --- Import-Session: GL.DeleteSeason löscht nur den Season-Datensatz, die Raids bleiben
    --- stehen. Ein Export → Season löschen → Import würde sonst jeden Kill verdoppeln, weil
    --- die ursprüngliche Session eine andere ID hat.
    -- Vergleich auf Minutengenauigkeit: die CSV trägt Zeit nur als HH:MM, ein importierter
    -- Zeitstempel hat also immer :00 Sekunden. Ein aufgezeichneter Kill hat echte Sekunden
    -- (z. B. 22:35:47) — ein exakter Vergleich hätte NIE gegen eine echte Session getroffen,
    -- und jeder Import gegen echte Daten hätte den Kill ein zweites Mal angelegt.
    local function SameMinute(a, b)
        return math.floor((a or 0) / 60) == math.floor((b or 0) / 60)
    end
    local function KillExists(boss, ts)
        for _, s in ipairs(db.raidContainers) do
            for _, m in pairs(s.raidMeta or {}) do
                for _, existing in ipairs(m.kills or {}) do
                    if existing.boss == boss and SameMinute(existing.ts, ts) then return true end
                end
            end
        end
        return false
    end

    for _, k in ipairs(killOrder) do
        -- Erst prüfen, dann anlegen: sonst bleibt bei einem vollständig übersprungenen
        -- Import eine leere Session zurück, die als Geisterspalte im Tab auftaucht.
        if KillExists(k.boss, k.ts) then
            stats.skipped = stats.skipped + 1
        else
            local session = SessionForDay(k.day, k.ts)
            local raidID  = GL.GenerateRaidID(k.tier, k.diff, session.startedAt)
            local meta    = session.raidMeta[raidID]
            if not meta then
                meta = { tier = k.tier, difficulty = k.diff, startedAt = k.ts,
                         participants = {}, kills = {} }
                session.raidMeta[raidID] = meta
            end
            table.insert(meta.kills, {
                boss = k.boss, ts = k.ts, participants = k.participants,
                trials = k.trials, bis = next(k.bis) and k.bis or nil,
            })
            -- Abend-Liste als Vereinigung nachziehen, wie GL.RecordKillAttendance es tut
            local seen = {}
            for _, n in ipairs(meta.participants) do seen[n] = true end
            for _, n in ipairs(k.participants) do
                if not seen[n] then seen[n] = true; table.insert(meta.participants, n) end
            end
            stats.kills = stats.kills + 1
        end
    end

    -- NICHT sortieren: db.activeContainerIdx ist ein Index in dieses Array, ein Umsortieren
    -- würde ihn auf eine andere Session zeigen lassen und den Loot dort hineinschreiben.
    -- Die Reihenfolge in raidContainers ist ohnehin egal — die Matrix sortiert nach Datum.
    return stats
end
