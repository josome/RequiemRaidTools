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
        GL.CreateSeason(name ~= "" and name or nil)
        UI.RefreshAttendanceTab()
    end,
    EditBoxOnEnterPressed = function(self)
        local name = self:GetText()
        GL.CreateSeason(name ~= "" and name or nil)
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
        local season  = GL.GetActiveSeason()
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

--- Parst "TT.MM.JJJJ" und setzt damit den Season-Start. Eigene Funktion, damit der
--- Popup-Handler nur weiterreicht und das Parsen testbar/nachvollziehbar bleibt.
function UI.ApplySeasonStart(text)
    local season = GL.GetActiveSeason()
    if not season then return false end
    local d, m, y = tostring(text or ""):match("^%s*(%d%d?)%.(%d%d?)%.(%d%d%d%d)%s*$")
    if not d then
        GL.Print("Datum bitte als TT.MM.JJJJ angeben.")
        return false
    end
    local ts = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d),
                      hour = 0, min = 0, sec = 0 })
    if not GL.SetSeasonStart(season.id, ts) then
        GL.Print("Startdatum konnte nicht gesetzt werden (liegt es nach dem Season-Ende?).")
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
                if season.endedAt then
                    -- Wiederaufnehmen beendet die laufende Season → nachfragen
                    local dlg = StaticPopup_Show("REQRT_REOPEN_SEASON")
                    if dlg then dlg.data = season.id end
                else
                    GL.SetActiveSeason(season.id)
                    UI.RefreshAttendanceTab()
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Startdatum: klickbar, weil eine frisch angelegte Season sonst alle vorhandenen
    -- Raids ausschließt und die Matrix leer bliebe
    local dateBtn = CreateFrame("Button", nil, header)
    dateBtn:SetSize(120, 20)
    dateBtn:SetPoint("LEFT", seasonDD, "RIGHT", -6, 0)
    local dateLbl = dateBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dateLbl:SetAllPoints()
    dateLbl:SetJustifyH("LEFT")
    dateBtn:SetScript("OnClick", function()
        if GL.GetActiveSeason() then StaticPopup_Show("REQRT_SEASON_START") end
    end)
    dateBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Startdatum ändern", 1, 1, 1)
        GameTooltip:AddLine("Raid-Abende vor diesem Datum zählen nicht zur Season.",
                            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    dateBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local newBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    newBtn:SetSize(100, 20)
    newBtn:SetPoint("LEFT", dateBtn, "RIGHT", 4, 0)
    newBtn:SetText("Neue Season")
    newBtn:SetScript("OnClick", function() StaticPopup_Show("REQRT_NEW_SEASON") end)

    -- Löschen der aktiven Season, Muster wie der Delete-Button im Raid-Tab:
    -- erster Klick zeigt "Sure?", ein zweiter innerhalb von 3s löscht.
    -- Beendete Seasons werden über den Dropdown wieder aufgenommen und dann gelöscht.
    local delBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    delBtn:SetSize(60, 20)
    delBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)
    delBtn:SetText("Delete")
    local delPending, delTimer = false, nil
    delBtn:SetScript("OnClick", function()
        local season = GL.GetActiveSeason()
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
        GameTooltip:AddLine("Aktive Season löschen", 1, 1, 1)
        GameTooltip:AddLine("Raid-Sessions und Loot bleiben erhalten — nur die Season selbst geht weg.",
                            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    delBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Expliziter Knopfdruck zum Auslesen. Der Roster wird zwar auch bei Login und über
    -- GUILD_ROSTER_UPDATE aktualisiert, aber ohne sichtbaren Auslöser — und die
    -- Rang-Liste ist nach frischem Login kurz leer.
    local readBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    readBtn:SetSize(100, 20)
    readBtn:SetPoint("LEFT", delBtn, "RIGHT", 4, 0)
    readBtn:SetText("Roster lesen")
    readBtn:SetScript("OnClick", function()
        GL.ReadGuildRosterNow()
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

    -- ── Zeile 2: Kader-Ränge + Zeitschnitt + Zähler ───────────
    local rankLbl = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rankLbl:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -28)
    rankLbl:SetText("Kader:")

    local rankDD = CreateFrame("Frame", "ReqRTSeasonDD_ranks", header, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(rankDD, 130)
    rankDD:SetPoint("LEFT", rankLbl, "RIGHT", -12, 0)
    UIDropDownMenu_Initialize(rankDD, function()
        local names  = GL.GetGuildRankNames()
        local sorted = SortedRankIndices(names)
        local season = GL.GetActiveSeason()

        -- Oben der Normalfall: ein Klick setzt Rang + alles darüber
        local title = UIDropDownMenu_CreateInfo()
        title.text, title.isTitle, title.notCheckable = "Ab Rang (und höher)", true, true
        UIDropDownMenu_AddButton(title)
        for _, i in ipairs(sorted) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = names[i]
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                if season then
                    -- Nur die Auswahl merken; der Kader wird erst mit "Roster lesen" neu
                    -- gebildet, damit er sich nicht unter der Hand ändert.
                    GL.SetSeasonRankThreshold(season.id, i)
                    UI.RefreshSeasonControls()
                end
            end
            UIDropDownMenu_AddButton(info)
        end

        -- Darunter die Feinkorrektur für Gilden mit Sonderrängen
        local title2 = UIDropDownMenu_CreateInfo()
        title2.text, title2.isTitle, title2.notCheckable = "Einzeln an/aus", true, true
        UIDropDownMenu_AddButton(title2)
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
        countLbl = countLbl,
        delBtn   = delBtn,
    }
end

-- ============================================================
-- Refresh
-- ============================================================

--- Aktualisiert die Kopfzeile aus dem aktuellen DB-Stand.
--- @param data  optional das Ergebnis von GL.ComputeAttendance (spart eine zweite Berechnung)
function UI.RefreshSeasonControls(data)
    if not S then return end
    local season = GL.GetActiveSeason()

    UIDropDownMenu_SetText(S.seasonDD, SeasonLabel(season))
    S.delBtn:SetEnabled(season ~= nil)
    S.dateLbl:SetText(season
        and ("|cff888888seit|r |cffffffff" .. date("%d.%m.%Y", season.startedAt or 0) .. "|r")
        or  "|cff888888noch keine Season angelegt|r")

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
    local stale = season and GL.IsSeasonRosterStale(season.id)
    S.countLbl:SetText(string.format(
        "|cff888888Kader|r |cffffffff%d|r |cff888888· weitere|r |cffffffff%d|r%s",
        kader, guests,
        stale and "   |cffff8000→ Roster lesen|r" or ""))
end
