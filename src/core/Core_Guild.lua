-- GuildLoot – Core_Guild.lua
-- Gildenroster-Anbindung: gefilterter Roster-Durchlauf + Season-Roster (Zeilen-Achse der
-- Attendance-Matrix). Der Roster wird NIE vollständig materialisiert oder gespeichert —
-- jede Zeile wird beim Lesen geprüft und verworfen, wenn sie nicht in den Kader gehört.
-- WoW-API hinter dünnen, mockbaren Wrappern → busted-testbar.
-- Muss NACH Util.lua geladen werden (nutzt GL.NormalizeName).

GuildLoot = GuildLoot or {}
local GL = GuildLoot

-- Einmal pro Session warnen, wenn der Roster unvollständig gelesen wurde.
local warnedIncomplete = false

-- GUILD_ROSTER_UPDATE feuert in Schüben; Sekunden zwischen zwei Auswertungen.
local ROSTER_UPDATE_THROTTLE = 10
local lastRosterUpdate = nil

--- Stößt eine Aktualisierung des Gildenrosters an (WoW liefert die Daten asynchron
--- über GUILD_ROSTER_UPDATE nach). No-Op wenn die API fehlt.
--- Rührt bewusst KEINE Roster-Filter des Spielers an: Online/Offline ist für den Kader
--- irrelevant, gelesen wird die volle Liste und danach nach Rang gefiltert. Falls die API
--- doch weniger Zeilen liefert als sie Mitglieder meldet, meldet das
--- GL.CheckGuildRosterCompleteness — statt still einen halben Kader zu zeigen.
function GL.RefreshGuildRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
end

--- Einmaliger Durchlauf über den Gildenroster.
--- accept(rankIndex) entscheidet pro Zeile, ob sie behalten wird; abgelehnte Zeilen werden
--- sofort verworfen statt in ein Zwischenarray zu wandern. accept = nil behält alles.
--- Online/Offline spielt bewusst keine Rolle — gelesen werden IMMER alle Mitglieder, der
--- einzige Schnitt ist der Rang. Die Rang-Namen werden im selben Durchlauf eingesammelt
--- (Feld 2 der Roster-Zeile) — permissionsfrei, im Gegensatz zur Guild-Control-API.
--- Returns: members (Array von { name, rankIndex, class }), rankNames ([idx]=Name),
---          readCount (Zeilen, die die API tatsächlich geliefert hat — für die Diagnose).
function GL.CollectGuildMembers(accept)
    local members, rankNames, readCount = {}, {}, 0
    if not (IsInGuild and IsInGuild()) then return members, rankNames, readCount end
    if not GetGuildRosterInfo then return members, rankNames, readCount end
    local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
    for i = 1, n do
        local name, rankName, rankIndex, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            readCount = readCount + 1
            rankIndex = rankIndex or 0
            if rankName and rankNames[rankIndex] == nil then
                rankNames[rankIndex] = rankName
            end
            if (not accept) or accept(rankIndex) then
                table.insert(members, {
                    name      = GL.NormalizeName(name),
                    rankIndex = rankIndex,
                    class     = classFile,
                })
            end
        end
    end
    return members, rankNames, readCount
end

--- Alle Gildenmitglieder, ungefiltert. Dünner Wrapper über GL.CollectGuildMembers, damit die
--- Zeilen-Leselogik nur an einer Stelle existiert.
--- Returns: Array von { name (realm-qualifiziert), rankIndex (0-basiert), class }.
function GL.GetGuildMembers()
    return (GL.CollectGuildMembers(nil))
end

--- Liest die Rang-Namen aus dem Roster und legt sie in db.guildRankNames ab.
--- Quelle für den Fallback in GL.GetGuildRankNames, wenn die Guild-Control-API schweigt.
--- Writes: db.guildRankNames
function GL.UpdateGuildRankNames()
    local db = GuildLootDB
    if not db then return end
    local _, rankNames = GL.CollectGuildMembers(function() return false end)
    db.guildRankNames = db.guildRankNames or {}
    for idx, name in pairs(rankNames) do
        db.guildRankNames[idx] = name
    end
end

--- Prüft, ob die Gilden-API so viele Zeilen geliefert hat wie sie Mitglieder meldet.
--- Ist sie kürzer, filtert der Client den Roster (typisch: "Offline-Mitglieder anzeigen" aus)
--- und der Kader wäre unvollständig — ohne diese Meldung ein lautloser Fehler. Warnt einmal
--- pro Session; die Einstellung des Spielers wird nicht angetastet.
--- Returns: reported, readCount
function GL.CheckGuildRosterCompleteness()
    local reported = (GetNumGuildMembers and GetNumGuildMembers()) or 0
    local _, _, readCount = GL.CollectGuildMembers(function() return false end)
    if reported > readCount and not warnedIncomplete then
        warnedIncomplete = true
        GL.Print(string.format(
            "|cffff8000Gildenroster unvollständig gelesen: %d von %d Mitgliedern.|r " ..
            "Im Gildenfenster \"Offline-Mitglieder anzeigen\" aktivieren, sonst fehlen " ..
            "ausgeloggte Raider im Kader.", readCount, reported))
    end
    return reported, readCount
end

--- Zusätzliche Diagnose für devMode: gemeldet / gelesen / Kader.
function GL.PrintGuildRosterDiagnostics()
    local db = GuildLootDB
    local reported, readCount = GL.CheckGuildRosterCompleteness()
    if not (db and db.settings and db.settings.devMode) then return end
    local kader = 0
    for _, row in ipairs(GL.GetSeasonRoster(db.activeSeasonId)) do
        if row.group == "roster" then kader = kader + 1 end
    end
    GL.Print(string.format(
        "[Guild] gemeldet: %d | gelesen: %d | Kader: %d", reported, readCount, kader))
end

--- Liest den Gildenroster sofort neu ein — der explizite Knopfdruck aus der Kopfzeile.
--- Fordert zusätzlich eine Aktualisierung beim Server an; deren Daten laufen über
--- GUILD_ROSTER_UPDATE nach. Meldet das Ergebnis im Chat, damit der Klick sichtbar wirkt.
--- Returns: reported, readCount
function GL.ReadGuildRosterNow()
    GL.RefreshGuildRoster()
    GL.UpdateGuildRankNames()
    local reported, readCount = GL.CheckGuildRosterCompleteness()

    local season = GL.GetActiveSeason()
    local kader  = season and GL.SnapshotSeasonRoster(season.id)
    if kader then
        GL.Print(string.format("Gildenroster gelesen: %d Mitglieder, Kader: %d.",
                               readCount, kader))
    else
        GL.Print(string.format("Gildenroster gelesen: %d Mitglieder. "
                               .. "|cff888888Keine aktive Season — kein Kader gesetzt.|r",
                               readCount))
    end
    return reported, readCount
end

--- Handler für GUILD_ROSTER_UPDATE. Das Event feuert häufig, daher gedrosselt.
--- Frischt die Rang-Namen auf (Quelle für die Rang-Auswahl im Settings-UI) und meldet
--- im devMode, wie vollständig der Read war.
function GL.OnGuildRosterUpdate()
    local now = time()
    if lastRosterUpdate and (now - lastRosterUpdate) < ROSTER_UPDATE_THROTTLE then return end
    lastRosterUpdate = now
    GL.UpdateGuildRankNames()
    GL.PrintGuildRosterDiagnostics()
    if GL.UI and GL.UI.RefreshAttendanceTab then GL.UI.RefreshAttendanceTab() end
end

--- Rang-Namen der Gilde, gemappt auf den 0-basierten rankIndex (wie ihn
--- GetGuildRosterInfo liefert): names[rankIndex] = Anzeigename. WoW' GuildControlGetRankName
--- ist 1-basiert (1 = Gildenmeister), daher rankIndex+1. Für die Rang-Auswahl im Settings-UI.
--- Liefert die Guild-Control-API nichts (Daten noch nicht geladen), greift der Fallback auf
--- db.guildRankNames aus dem Roster — sonst bliebe die Rang-Liste im UI leer.
--- Returns: Tabelle { [0]=name, [1]=name, ... }; leer wenn beide Quellen nichts haben.
function GL.GetGuildRankNames()
    local names = {}
    if GuildControlGetNumRanks and GuildControlGetRankName then
        local n = GuildControlGetNumRanks() or 0
        for i = 0, n - 1 do
            names[i] = GuildControlGetRankName(i + 1) or ("Rank " .. i)
        end
    end
    if next(names) then return names end
    local db = GuildLootDB
    for idx, name in pairs((db and db.guildRankNames) or {}) do
        names[idx] = name
    end
    return names
end

--- Namen mit Attendance in der Season — aus den Teilnehmerlisten der Raid-Sessions, die im
--- Zeitraum der Season liegen. Basis für die zweite Roster-Gruppe ("guest") und dafür, dass
--- der Zeitschnitt niemanden aus dem Kader wirft, der tatsächlich geraidet hat.
--- HINWEIS: GL.EnsureRaidMeta legt raidMeta[id] nur einmal an, die Teilnehmerliste ist also
--- ein Schnappschuss vom ersten Bosskill, keine Vereinigung über den Abend. Für die
--- Gruppenzuordnung genügt das; die Pro-Kill-Auflösung kommt mit Phase 1b.
--- Reads:  db.seasons[seasonId], db.raidContainers[*].startedAt/.raidMeta
--- Returns: deduplizierte Liste von Namen (realm-qualifiziert), unsortiert.
function GL.GetSeasonAttendees(seasonId)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[seasonId]
    if not season then return {} end
    local from = season.startedAt or 0
    local to   = season.endedAt or time()

    local seen, out = {}, {}
    for _, session in ipairs(db.raidContainers or {}) do
        local ts = session.startedAt or 0
        if ts >= from and ts <= to then
            for _, meta in pairs(session.raidMeta or {}) do
                for _, name in ipairs(meta.participants or {}) do
                    if not seen[name] then
                        seen[name] = true
                        table.insert(out, name)
                    end
                end
            end
        end
    end
    return out
end

--- Kennzeichnet, mit welchem Rang-Filter ein Kader-Schnappschuss erzeugt wurde.
--- Damit lässt sich erkennen, ob die Auswahl seither geändert wurde.
local function FilterKey(filter)
    local idx = {}
    for i, on in pairs(filter or {}) do
        if on then table.insert(idx, i) end
    end
    table.sort(idx)
    return table.concat(idx, ",")
end

--- Liest den Gildenroster und legt den Kader der Season als Schnappschuss ab.
--- Bewusst NUR auf ausdrückliche Aktion (Button "Roster lesen") — nicht bei jedem Refresh:
--- so ändert sich der Kader nicht still, wenn jemand mitten in der Season befördert oder
--- degradiert wird, und ein Verstellen des Rang-Filters wirkt erst nach dem nächsten Lesen.
--- Gespeichert wird nur das Ergebnis des Rang-Schnitts (~Kadergröße), nicht die Gildenliste.
--- Writes: db.seasons[id].roster, .rosterReadAt, .rosterFilterKey
--- Returns: Anzahl der Kader-Mitglieder, oder nil bei unbekannter Season.
function GL.SnapshotSeasonRoster(seasonId)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[seasonId]
    if not season then return nil end
    local filter = season.rankFilter or {}

    local roster = {}
    for _, m in ipairs(GL.CollectGuildMembers(function(rankIndex) return filter[rankIndex] end)) do
        table.insert(roster, { name = m.name, class = m.class })
    end
    season.roster         = roster
    season.rosterReadAt   = time()
    season.rosterFilterKey = FilterKey(filter)
    return #roster
end

--- true, wenn der Rang-Filter seit dem letzten Einlesen verändert wurde (oder noch nie
--- eingelesen wurde). Die UI weist damit darauf hin, dass "Roster lesen" nötig ist —
--- sonst sähe eine folgenlose Filteränderung wie ein Defekt aus.
function GL.IsSeasonRosterStale(seasonId)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[seasonId]
    if not season then return false end
    if not season.roster then return true end
    return season.rosterFilterKey ~= FilterKey(season.rankFilter)
end

--- Season-Roster = Zeilen-Achse der Attendance-Matrix, in zwei Gruppen:
---   group = "roster" — Kader aus dem zuletzt eingelesenen Schnappschuss
---                      (GL.SnapshotSeasonRoster). Der Rang ist der EINZIGE Schnitt.
---   group = "guest"  — hat Attendance in der Season, steht aber nicht im Kader:
---                      niedrigere Ränge, Ex-Mitglieder, Pugs.
--- Greift NICHT auf die Gilden-API zu — die Zeilen stammen aus dem Schnappschuss.
--- Klasse: aus dem Schnappschuss, für alle anderen aus db.players[name].class.
--- Reads:  db.seasons[seasonId].roster, GL.GetSeasonAttendees, db.players
--- Returns: Array von { name, class, group }; roster-Block vor guest-Block, je alphabetisch.
function GL.GetSeasonRoster(seasonId)
    local db = GuildLootDB
    local season = db and db.seasons and db.seasons[seasonId]
    if not season then return {} end

    -- Attendance bestimmt, wer unterhalb des Kaders als Gast erscheint
    local attended = {}
    for _, name in ipairs(GL.GetSeasonAttendees(seasonId)) do attended[name] = true end

    local rows, inKader = {}, {}
    for _, m in ipairs(season.roster or {}) do
        table.insert(rows, { name = m.name, class = m.class, group = "roster" })
        inKader[m.name] = true
    end

    local players = db.players or {}
    for name in pairs(attended) do
        if not inKader[name] then
            local p = players[name]
            table.insert(rows, { name = name, class = p and p.class, group = "guest" })
        end
    end

    table.sort(rows, function(a, b)
        if a.group ~= b.group then return a.group == "roster" end
        -- kleingeschrieben vergleichen, sonst sortieren Umlaute hinter "z"
        return a.name:lower() < b.name:lower()
    end)
    return rows
end
