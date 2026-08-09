-- GuildLoot – UI_SeasonControls.lua
-- Season-Bedienung in der Kopfzeile des Attendance-Tabs: Season wählen/anlegen,
-- Startdatum, Kader-Rang-Schnitt, Zeitschnitt für Inaktive, Zähler.
-- Sitzt bewusst am Tab statt unter Settings — die Wirkung jeder Einstellung ist direkt
-- in der Matrix darunter sichtbar.
-- Muss NACH UI_Common.lua geladen werden.

local GL = GuildLoot
local UI = GL.UI

-- Gebaute Widgets; nil solange die Kopfzeile nicht existiert (Refresh ist dann No-Op).
local S = nil

-- Ausgewählte Season — getrennt von der AKTIVEN, genau wie selectedRaid im Raid-Tab.
-- Nötig, weil GL.EndSeason activeSeasonId leert: ohne eigene Auswahl wäre nach dem
-- Schließen keine Season mehr im Kopf und alle Buttons tot. So lässt sich eine beendete
-- Season auch nur ansehen, ohne sie dafür wieder aufnehmen zu müssen.
local selectedId = nil

--- Die Season, auf die sich Kopfzeile und Matrix beziehen: die ausgewählte, sonst die
--- aktive, sonst die neueste. Nie nil, solange überhaupt eine Season existiert.
function UI.GetSelectedSeason()
    local db = GuildLootDB
    if not (db and db.seasons) then return nil end
    if selectedId and db.seasons[selectedId] then return db.seasons[selectedId] end
    local active = GL.GetActiveSeason()
    if active then return active end
    local newest = nil
    for _, s in pairs(db.seasons) do
        if not newest or (s.startedAt or 0) > (newest.startedAt or 0) then newest = s end
    end
    return newest
end

--- Setzt die Auswahl; nil fällt auf die Automatik in UI.GetSelectedSeason zurück.
function UI.SetSelectedSeason(id)
    selectedId = id
end

--- Rang-Indizes aufsteigend (0 = Gildenmeister); GetGuildRankNames kann lückenhaft sein.
local function SortedRankIndices(names)
    local idx = {}
    for i in pairs(names) do table.insert(idx, i) end
    table.sort(idx)
    return idx
end

local function SeasonsNewestFirst()
    local out = {}
    for _, s in pairs((GuildLootDB and GuildLootDB.seasons) or {}) do
        table.insert(out, s)
    end
    table.sort(out, function(a, b) return (a.startedAt or 0) > (b.startedAt or 0) end)
    return out
end

local function SeasonLabel(season)
    if not season then return "keine aktive Season" end
    local label = (season.name ~= "" and season.name) or "(ohne Namen)"
    -- Die laufende Season orange: seit der Dropdown nur noch auswählt statt zu öffnen,
    -- ist sonst nicht erkennbar, in welche gerade aufgezeichnet wird.
    -- Nur der Name wird eingefärbt — ein |r um den grauen Zusatz würde die Farbe
    -- vorzeitig beenden.
    local db = GuildLootDB
    if db and db.activeSeasonId == season.id then
        label = "|cffff8000" .. label .. "|r"
    end
    if season.endedAt then label = label .. " |cff888888(beendet)|r" end
    return label
end

--- Startzeitpunkt der ältesten vorhandenen Raid-Session — Vorschlag fürs Startdatum,
--- damit bereits gelaufene Raids in die Season fallen.
local function EarliestSessionStart()
    local earliest = nil
    for _, session in ipairs((GuildLootDB and GuildLootDB.raidContainers) or {}) do
        local ts = session.startedAt or 0
        if ts > 0 and (not earliest or ts < earliest) then earliest = ts end
    end
    return earliest
end

-- ============================================================
-- StaticPopups
-- ============================================================

StaticPopupDialogs["REQRT_NEW_SEASON"] = {
    text       = "Name der neuen Season:\n|cffff8000Die laufende Season wird dabei beendet.|r",
    button1    = "Anlegen",
    button2    = "Abbrechen",
    hasEditBox = true,
    maxLetters = 48,
    OnShow     = function(self)
        self.EditBox:SetWidth(260)
        self.EditBox:SetText(date("Season %Y-%m"))
        self.EditBox:HighlightText()
    end,
    OnAccept   = function(self)
        local name = self.EditBox:GetText()
        UI.SetSelectedSeason(GL.CreateSeason(name ~= "" and name or nil))
        UI.RefreshAttendanceTab()
    end,
    EditBoxOnEnterPressed = function(self)
        local name = self:GetText()
        UI.SetSelectedSeason(GL.CreateSeason(name ~= "" and name or nil))
        StaticPopup_Hide("REQRT_NEW_SEASON")
        UI.RefreshAttendanceTab()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["REQRT_REOPEN_SEASON"] = {
    text     = "Beendete Season wieder aufnehmen?\n|cff888888Die aktuell laufende Season wird dafür beendet.|r",
    button1  = "Wieder aufnehmen",
    button2  = "Abbrechen",
    OnAccept = function(self)
        GL.ReopenSeason(self.data)
        UI.SetSelectedSeason(self.data)
        UI.RefreshAttendanceTab()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["REQRT_SEASON_START"] = {
    text       = "Startdatum der Season (TT.MM.JJJJ):\n"
                 .. "|cff888888Raid-Abende vor diesem Datum zählen nicht zur Season.|r",
    button1    = "Setzen",
    button2    = "Abbrechen",
    hasEditBox = true,
    maxLetters = 10,
    OnShow     = function(self)
        -- Vorbelegung: ältester vorhandener Raid → ein Klick, und alles Bisherige zählt
        local suggest = EarliestSessionStart()
        local season  = UI.GetSelectedSeason()
        self.EditBox:SetWidth(160)
        self.EditBox:SetText(date("%d.%m.%Y", suggest or (season and season.startedAt) or time()))
        self.EditBox:HighlightText()
    end,
    OnAccept   = function(self)
        UI.ApplySeasonStart(self.EditBox:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        UI.ApplySeasonStart(self:GetText())
        StaticPopup_Hide("REQRT_SEASON_START")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["REQRT_SEASON_END"] = {
    text       = "Enddatum der Season (TT.MM.JJJJ):\n"
                 .. "|cff888888Raid-Abende nach diesem Datum zählen nicht mehr zur Season. "
                 .. "Die Season gilt damit als beendet.|r",
    button1    = "Setzen",
    button2    = "Abbrechen",
    hasEditBox = true,
    maxLetters = 10,
    OnShow     = function(self)
        local season = UI.GetSelectedSeason()
        self.EditBox:SetWidth(160)
        self.EditBox:SetText(date("%d.%m.%Y", (season and season.endedAt) or time()))
        self.EditBox:HighlightText()
    end,
    OnAccept   = function(self)
        UI.ApplySeasonEnd(self.EditBox:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        UI.ApplySeasonEnd(self:GetText())
        StaticPopup_Hide("REQRT_SEASON_END")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

--- Parst "TT.MM.JJJJ" zu einem Zeitstempel. Gemeinsam für Start- und Enddatum.
--- Returns Zeitstempel oder nil (dann ist die Eingabe unbrauchbar).
--- @param endOfDay boolean  true = 23:59:59 statt 00:00, damit der Tag selbst noch zählt
local function ParseDate(text, endOfDay)
    local d, m, y = tostring(text or ""):match("^%s*(%d%d?)%.(%d%d?)%.(%d%d%d%d)%s*$")
    if not d then return nil end
    return time({
        year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = endOfDay and 23 or 0, min = endOfDay and 59 or 0, sec = endOfDay and 59 or 0,
    })
end

--- Parst "TT.MM.JJJJ" und setzt damit den Season-Start. Eigene Funktion, damit der
--- Popup-Handler nur weiterreicht und das Parsen testbar/nachvollziehbar bleibt.
function UI.ApplySeasonStart(text)
    local season = UI.GetSelectedSeason()
    if not season then return false end
    local ts = ParseDate(text)
    if not ts then
        GL.Print("Datum bitte als TT.MM.JJJJ angeben.")
        return false
    end
    if not GL.SetSeasonStart(season.id, ts) then
        GL.Print("Startdatum konnte nicht gesetzt werden (liegt es nach dem Season-Ende?).")
        return false
    end
    UI.RefreshAttendanceTab()
    return true
end

--- Setzt das Enddatum der ausgewählten Season. Der gewählte Tag zählt noch dazu, deshalb
--- 23:59:59 — sonst fiele ein Raid am Enddatum selbst aus dem Fenster.
function UI.ApplySeasonEnd(text)
    local season = UI.GetSelectedSeason()
    if not season then return false end
    local ts = ParseDate(text, true)
    if not ts then
        GL.Print("Datum bitte als TT.MM.JJJJ angeben.")
        return false
    end
    if not GL.SetSeasonEnd(season.id, ts) then
        GL.Print("Enddatum konnte nicht gesetzt werden (liegt es vor dem Season-Start?).")
        return false
    end
    UI.RefreshAttendanceTab()
    return true
end

-- ============================================================
-- Aufbau
-- ============================================================

--- Baut die Season-Bedienung in den übergebenen Kopfzeilen-Container (zwei Zeilen).
function UI.BuildSeasonControls(header)
    -- ── Zeile 1: Season + Startdatum + Neue Season ────────────
    local seasonDD = CreateFrame("Frame", "ReqRTSeasonDD_active", header, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(seasonDD, 150)
    seasonDD:SetPoint("TOPLEFT", header, "TOPLEFT", -14, 0)
    UIDropDownMenu_Initialize(seasonDD, function()
        local seasons = SeasonsNewestFirst()
        for _, season in ipairs(seasons) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = SeasonLabel(season)
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                -- Auswählen heißt ansehen, nicht öffnen: eine beendete Season lässt sich
                -- damit betrachten, ohne sie wieder aufnehmen zu müssen. Das Wiederaufnehmen
                -- liegt auf [Resume].
                UI.SetSelectedSeason(season.id)
                UI.RefreshAttendanceTab()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Startdatum: klickbar, weil eine frisch angelegte Season sonst alle vorhandenen
    -- Raids ausschließt und die Matrix leer bliebe
    local dateBtn = CreateFrame("Button", nil, header)
    dateBtn:SetSize(100, 22)
    dateBtn:SetPoint("LEFT", seasonDD, "RIGHT", -6, 0)
    local dateLbl = dateBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dateLbl:SetAllPoints()
    dateLbl:SetJustifyH("LEFT")
    dateBtn:SetScript("OnClick", function()
        if UI.GetSelectedSeason() then StaticPopup_Show("REQRT_SEASON_START") end
    end)
    dateBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Startdatum ändern", 1, 1, 1)
        GameTooltip:AddLine("Raid-Abende vor diesem Datum zählen nicht zur Season.",
                            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    dateBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Enddatum: bleibt bei der laufenden Season bewusst leer ("offen") — endedAt = nil
    -- heißt, das Fenster reicht bis jetzt. Gebraucht wird es beim Nachtragen einer alten
    -- Season, damit sie die jüngeren Raids nicht einsammelt.
    local endBtn = CreateFrame("Button", nil, header)
    endBtn:SetSize(100, 22)
    endBtn:SetPoint("LEFT", dateBtn, "RIGHT", 2, 0)
    local endLbl = endBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    endLbl:SetAllPoints()
    endLbl:SetJustifyH("LEFT")
    endBtn:SetScript("OnClick", function()
        if UI.GetSelectedSeason() then StaticPopup_Show("REQRT_SEASON_END") end
    end)
    endBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Enddatum ändern", 1, 1, 1)
        GameTooltip:AddLine("Optional. Ohne Enddatum läuft die Season bis heute. "
                            .. "Ein Enddatum schließt sie ab — nötig, wenn eine ältere Season "
                            .. "nachgetragen wird.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    endBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Umschalter wie sessionBtn im Raid-Tab: ohne laufende Season "New Season", mit
    -- laufender "Close Season".
    local seasonBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    seasonBtn:SetSize(150, 22)
    seasonBtn:SetPoint("LEFT", endBtn, "RIGHT", 4, 0)
    seasonBtn:SetText("New Season")
    seasonBtn:SetScript("OnClick", function()
        local active = GL.GetActiveSeason()
        if active then
            GL.EndSeason(active.id)
            -- Auswahl auf der eben geschlossenen Season lassen, sonst springt die Ansicht
            UI.SetSelectedSeason(active.id)
            UI.RefreshAttendanceTab()
        else
            StaticPopup_Show("REQRT_NEW_SEASON")
        end
    end)

    -- Wiederaufnehmen der ausgewählten, beendeten Season. Vorher nur im Dropdown versteckt.
    local resumeBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    resumeBtn:SetSize(90, 22)
    resumeBtn:SetPoint("LEFT", seasonBtn, "RIGHT", 4, 0)
    resumeBtn:SetText("Resume")
    resumeBtn:SetScript("OnClick", function()
        local season = UI.GetSelectedSeason()
        if not season or not season.endedAt then return end
        -- Beendet die laufende Season → nachfragen
        local dlg = StaticPopup_Show("REQRT_REOPEN_SEASON")
        if dlg then dlg.data = season.id end
    end)

    -- Umbenennen über den gemeinsamen Dialog aus UI_Common (UI.ShowRenameDialog)
    local renameBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    renameBtn:SetSize(60, 22)
    renameBtn:SetPoint("LEFT", resumeBtn, "RIGHT", 4, 0)
    renameBtn:SetText("Rename")
    renameBtn:SetScript("OnClick", function()
        local season = UI.GetSelectedSeason()
        if not season then return end
        UI.ShowRenameDialog("Season umbenennen:", season.name, function(name)
            GL.RenameSeason(season.id, name)
            UI.RefreshAttendanceTab()
        end)
    end)

    -- ── Zeile 2: Export/Import/Delete/Roster, unter Zeile 1 an New Seasons linker
    -- Kante ausgerichtet ──
    -- Export der ausgewählten Season als CSV, eine Zeile je Teilnehmer und Bosskill.
    local exportBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    exportBtn:SetSize(64, 22)
    exportBtn:SetPoint("TOPLEFT", seasonBtn, "BOTTOMLEFT", 0, -4)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        local season = UI.GetSelectedSeason()
        if not season then return end
        UI.ShowExportPopup(nil, GL.ExportSeasonCSV(season.id))
    end)

    -- Import ist bewusst NICHT an die Auswahl gebunden: die Zuordnung läuft über das Datum
    -- der Zeilen, eine importierte Session landet in der Season, deren Fenster den Tag deckt.
    local importBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    importBtn:SetSize(64, 22)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 4, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        UI.ShowTextInputPopup("CSV einfügen (Strg+V), dann Import", "Import", function(text)
            local s = GL.ImportAttendanceCSV(text)
            GL.Print(string.format(
                "Import: %d Bosskills aus %d Zeilen. |cff888888%d übersprungen, %d fehlerhaft.|r",
                s.kills, s.rows, s.skipped, s.bad))
            UI.RefreshAttendanceTab()
        end)
    end)
    importBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Raids nachtragen", 1, 1, 1)
        GameTooltip:AddLine("CSV im Format des Exports. Ordnet über das Datum zu und ergänzt "
                            .. "nur — bereits vorhandene Bosskills werden übersprungen.",
                            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    importBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Wirkt auf die AUSGEWÄHLTE Season, damit sich auch eine beendete löschen lässt.
    local delBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    delBtn:SetSize(54, 22)
    delBtn:SetPoint("LEFT", importBtn, "RIGHT", 4, 0)
    delBtn:SetText("Delete")
    local delPending, delTimer = false, nil
    delBtn:SetScript("OnClick", function()
        local season = UI.GetSelectedSeason()
        if not season then return end
        if delPending then
            if delTimer then delTimer:Cancel(); delTimer = nil end
            delPending = false; delBtn:SetText("Delete")
            GL.DeleteSeason(season.id)
            UI.RefreshAttendanceTab()
        else
            delPending = true; delBtn:SetText("|cffff4444Sure?|r")
            delTimer = C_Timer.NewTimer(3, function()
                delPending = false; delTimer = nil; delBtn:SetText("Delete")
            end)
        end
    end)
    delBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Ausgewählte Season löschen", 1, 1, 1)
        GameTooltip:AddLine("Raid-Sessions und Loot bleiben erhalten — nur die Season selbst geht weg.",
                            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    delBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Expliziter Knopfdruck zum Auslesen. Der Roster wird zwar auch bei Login und über
    -- GUILD_ROSTER_UPDATE aktualisiert, aber ohne sichtbaren Auslöser — und die
    -- Rang-Liste ist nach frischem Login kurz leer.
    local readBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    readBtn:SetSize(100, 22)
    readBtn:SetPoint("LEFT", delBtn, "RIGHT", 4, 0)
    readBtn:SetText("Roster lesen")
    -- Stammt der Kader aus einer anderen Gilde, warnt der erste Klick und erst der zweite
    -- liest wirklich — sonst ersetzt ein Zweitchar den Kader lautlos durch seine Gilde.
    -- Gleiches Muster wie der Delete-Button.
    local readForce, readTimer = false, nil
    readBtn:SetScript("OnClick", function()
        local season = UI.GetSelectedSeason()
        local stored = season and GL.SeasonRosterGuildMismatch(season.id)
        if stored and not readForce then
            GL.ReadGuildRosterNow(false, season.id)   -- meldet die Gilden im Chat
            readForce = true
            readBtn:SetText("|cffff8000Trotzdem?|r")
            if readTimer then readTimer:Cancel() end
            readTimer = C_Timer.NewTimer(5, function()
                readForce = false; readTimer = nil; readBtn:SetText("Roster lesen")
            end)
            return
        end
        if readTimer then readTimer:Cancel(); readTimer = nil end
        readForce = false
        readBtn:SetText("Roster lesen")
        GL.ReadGuildRosterNow(true, season and season.id)
        UI.RefreshAttendanceTab()
    end)
    readBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Gildenroster neu einlesen", 1, 1, 1)
        GameTooltip:AddLine("Liest alle Gildenmitglieder und aktualisiert die Rang-Liste. "
                            .. "Die Anzahl wird im Chat gemeldet.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    readBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Kader-Ränge + Zähler: gleiche Zeile wie Export/Import/Delete/Roster, aber links bei
    -- x=0 statt unter New Season — die beiden Blöcke laufen sich nicht ins Gehege (Kader
    -- endet deutlich vor x≈336, wo Export beginnt).
    --
    -- Verankert an DEMSELBEN Referenzpunkt wie exportBtn (seasonBtn:BOTTOMLEFT), nicht an
    -- einem festen Y-Wert relativ zu header: seasonDD (UIDropDownMenuTemplate) ist höher
    -- als die 22-px-Buttons, und Zeile 1 zentriert sich vertikal an seasonDD — ein fixer
    -- Header-Offset hinkt dieser Verschiebung hinterher und lag sichtbar zu hoch.
    --
    -- Kein "Kader:"-Label mehr davor — die Zeile beginnt direkt mit dem Dropdown, linksbündig
    -- zur Season-Zeile darüber (seasonDD). X-Offset wird zur Laufzeit aus der tatsächlichen
    -- Differenz der beiden Frame-Kanten gemessen statt aus der Button-Breitenkette
    -- zurückgerechnet: UIDropDownMenu_SetWidth setzt nur die sichtbare Breite des inneren
    -- Widgets, nicht die tatsächliche Frame-Breite, mit der SetPoint-Ketten rechnen — eine
    -- Handrechnung darüber (frühere Version) traf die echte Kante nicht zuverlässig.
    local rankDD = CreateFrame("Frame", "ReqRTSeasonDD_ranks", header, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(rankDD, 130)
    local dx = (seasonDD:GetLeft() or 0) - (seasonBtn:GetLeft() or 0)
    rankDD:SetPoint("TOPLEFT", seasonBtn, "BOTTOMLEFT", dx, -4)
    UIDropDownMenu_Initialize(rankDD, function()
        local names  = GL.GetGuildRankNames()
        local sorted = SortedRankIndices(names)
        local season = UI.GetSelectedSeason()

        -- Nur noch Einzelauswahl je Rang — die "Ab Rang (und höher)"-Kurzform ist entfallen.
        local title = UIDropDownMenu_CreateInfo()
        title.text, title.isTitle, title.notCheckable = "Einzeln an/aus", true, true
        UIDropDownMenu_AddButton(title)
        local filter = (season and season.rankFilter) or {}
        for _, i in ipairs(sorted) do
            local info = UIDropDownMenu_CreateInfo()
            info.text             = names[i]
            info.checked          = filter[i] and true or false
            info.keepShownOnClick = true
            info.func = function(_, _, _, checked)
                if season then
                    GL.SetSeasonRankFilter(season.id, i, checked)
                    UI.RefreshSeasonControls()
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local countLbl = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLbl:SetPoint("LEFT", rankDD, "RIGHT", -6, 0)

    S = {
        seasonDD = seasonDD,
        rankDD   = rankDD,
        dateLbl  = dateLbl,
        endLbl   = endLbl,
        countLbl = countLbl,
        delBtn    = delBtn,
        renameBtn = renameBtn,
        seasonBtn = seasonBtn,
        resumeBtn = resumeBtn,
        exportBtn = exportBtn,
        readBtn   = readBtn,
    }
end

-- ============================================================
-- Refresh
-- ============================================================

--- Aktualisiert die Kopfzeile aus dem aktuellen DB-Stand.
--- @param data  optional das Ergebnis von GL.ComputeAttendance (spart eine zweite Berechnung)
function UI.RefreshSeasonControls(data)
    if not S then return end
    local season = UI.GetSelectedSeason()

    UIDropDownMenu_SetText(S.seasonDD, SeasonLabel(season))
    S.delBtn:SetEnabled(season ~= nil)
    S.renameBtn:SetEnabled(season ~= nil)
    S.exportBtn:SetEnabled(season ~= nil)

    -- Umschalter wie im Raid-Tab: läuft eine Season, schließt der Knopf sie; sonst legt er
    -- eine neue an. Resume greift nur bei einer ausgewählten, beendeten Season.
    local active = GL.GetActiveSeason()
    S.seasonBtn:SetText(active and "Close Season" or "New Season")
    S.resumeBtn:SetEnabled((season ~= nil and season.endedAt ~= nil) and true or false)
    -- Auch eine beendete Season braucht einen Kader — eine nachgetragene alte Season hätte
    -- sonst gar keinen und die Matrix bliebe leer. Der Roster ist dann zwangsläufig der
    -- von heute; das ist die beste verfügbare Näherung.
    S.readBtn:SetEnabled(season ~= nil)
    S.dateLbl:SetText(season
        and ("|cff888888seit|r |cffffffff" .. date("%d.%m.%Y", season.startedAt or 0) .. "|r")
        or  "|cff888888noch keine Season angelegt|r")
    -- Ohne Enddatum läuft die Season bis heute — das ist der Normalfall und wird als
    -- "offen" gezeigt, nicht als Lücke
    S.endLbl:SetText(season
        and (season.endedAt
             and ("|cff888888bis|r |cffffffff" .. date("%d.%m.%Y", season.endedAt) .. "|r")
             or  "|cff888888bis offen|r")
        or  "")

    local names  = GL.GetGuildRankNames()
    local filter = (season and season.rankFilter) or {}
    if not next(names) then
        UIDropDownMenu_SetText(S.rankDD, "|cff888888lädt…|r")
    else
        -- niedrigster aktiver Rang = die Schwelle, die der Nutzer gesetzt hat
        local lowest = nil
        for i in pairs(filter) do
            if lowest == nil or i > lowest then lowest = i end
        end
        UIDropDownMenu_SetText(S.rankDD,
            lowest and (names[lowest] or ("Rang " .. lowest)) or "– kein Rang –")
    end
    -- Ohne übergebenes Aggregat direkt aus dem Roster zählen — das liest inzwischen nur
    -- den Schnappschuss und fasst die Gilden-API nicht an, ist also billig.
    local rows = (data and data.rows) or (season and GL.GetSeasonRoster(season.id)) or {}
    local kader, guests = 0, 0
    for _, row in ipairs(rows) do
        if row.group == "roster" then kader = kader + 1 else guests = guests + 1 end
    end

    -- Veralteter Kader: eine folgenlose Filteränderung sähe sonst wie ein Defekt aus
    -- Nur für die laufende Season: dort ist ein fehlender/veralteter Kader ein Hinweis.
    -- Bei einer beendeten baut sich die Liste aus der Attendance, das ist kein Mangel.
    local stale = season and season == active and GL.IsSeasonRosterStale(season.id)
    S.countLbl:SetText(string.format(
        "|cff888888Kader|r |cffffffff%d|r |cff888888· weitere|r |cffffffff%d|r%s",
        kader, guests,
        stale and "   |cffff8000→ Roster lesen|r" or ""))
end
