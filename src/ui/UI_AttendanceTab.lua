-- GuildLoot – UI_AttendanceTab.lua
-- Attendance-Tab: Matrix aus Raidern (Y) und Raid-Abenden (X).
-- Rechnet nichts selbst — die Daten kommen komplett aus GL.ComputeAttendance
-- (src/core/Core_Attendance.lua). Zeilen und Zellen sind gepoolt (UI.CreateFramePool),
-- damit ein Refresh keine Frames leakt.
-- Passt zu Slot TAB_PLAYER; UI_PlayerTab.lua ist dafür aus der TOC genommen.

local GL = GuildLoot
local UI = GL.UI

local TAB_PLAYER = UI.TAB_PLAYER

-- ============================================================
-- Konstanten & Zustand
-- ============================================================

local NAME_W  = 130
local PCT_W   = 44
local TRIAL_W = 40
local LEFT_W  = NAME_W + PCT_W + TRIAL_W   -- Breite des fixen linken Blocks
local CELL_W  = 34
local ROW_H   = 20
local SEP_H   = 18
local PAGER_W = 92                          -- Platz für ◀ Seite x/y ▶

-- Spalten-Offset beim Blättern (0 = neueste Abende). Modul-lokal, kein DB-Zustand.
local colOffset = 0
local lastSeasonId = nil

-- Aufgeklappte Abende: { [nightId] = true }. Wie colOffset bewusst nur Sitzungszustand —
-- das Aufklappen ist eine Blickrichtung, keine Einstellung.
local expanded = {}

-- Nach dem Aufklappen soll dieser Abend im sichtbaren Fenster stehen; der nächste Refresh
-- rechnet daraus den colOffset. Über eine Variable statt direkt im Klick-Handler, damit der
-- Handler keine veraltete Spaltenliste einfängt.
local pendingFocusNight = nil

local COLOR_PRESENT = { 0.15, 0.65, 0.20, 1 }
local COLOR_ABSENT  = { 1, 1, 1, 0.06 }

--- Wie viele Spalten passen in die aktuelle Breite? Mindestens eine.
local function VisibleColumnCount(panel)
    local w = panel:GetWidth() or 0
    local usable = w - LEFT_W - PAGER_W - 12
    return math.max(1, math.floor(usable / CELL_W))
end

-- ============================================================
-- Aufbau
-- ============================================================

function UI.BuildAttendancePanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT",     parent, "TOPLEFT",     0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    panel:Hide()

    -- ── Kopfzeile: Season-Bedienung (UI_SeasonControls.lua) ───
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT",  panel, "TOPLEFT",   8, -6)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -6)
    header:SetHeight(52)
    panel.header = header
    UI.BuildSeasonControls(header)

    -- ── Spaltenkopf ───────────────────────────────────────────
    local colHeader = CreateFrame("Frame", nil, panel)
    colHeader:SetPoint("TOPLEFT",  header, "BOTTOMLEFT",  0, -4)
    colHeader:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
    colHeader:SetHeight(18)
    panel.colHeader = colHeader

    local function FixedHeader(text, x, w)
        local lbl = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", colHeader, "TOPLEFT", x, 0)
        lbl:SetWidth(w)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(text)
        lbl:SetTextColor(1, 0.8, 0)
        return lbl
    end
    FixedHeader("Raider", 0, NAME_W)
    FixedHeader("Att.%",  NAME_W, PCT_W)
    FixedHeader("Trial",  NAME_W + PCT_W, TRIAL_W)

    -- Blättern
    local nextBtn = CreateFrame("Button", nil, colHeader, "UIPanelButtonTemplate")
    nextBtn:SetSize(20, 18)
    nextBtn:SetPoint("TOPRIGHT", colHeader, "TOPRIGHT", 0, 2)
    nextBtn:SetText(">")
    nextBtn:SetScript("OnClick", function()
        colOffset = colOffset + VisibleColumnCount(panel)
        UI.RefreshAttendanceTab()
    end)

    local pageLbl = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pageLbl:SetPoint("RIGHT", nextBtn, "LEFT", -4, 0)
    pageLbl:SetWidth(50)
    pageLbl:SetJustifyH("CENTER")

    local prevBtn = CreateFrame("Button", nil, colHeader, "UIPanelButtonTemplate")
    prevBtn:SetSize(20, 18)
    prevBtn:SetPoint("RIGHT", pageLbl, "LEFT", -4, 0)
    prevBtn:SetText("<")
    prevBtn:SetScript("OnClick", function()
        colOffset = math.max(0, colOffset - VisibleColumnCount(panel))
        UI.RefreshAttendanceTab()
    end)

    panel.pageLbl = pageLbl
    panel.prevBtn = prevBtn
    panel.nextBtn = nextBtn

    -- Spaltenköpfe (gepoolt, Anzahl variiert mit der Breite). Buttons statt FontStrings,
    -- weil ein Kopf klickbar sein muss (Auf-/Zuklappen) und einen Tooltip braucht — in
    -- CELL_W passt kein Bossname, der Name lebt im Tooltip.
    panel.headerPool = UI.CreateFramePool(
        function()
            local btn = CreateFrame("Button", nil, colHeader)
            btn:SetSize(CELL_W, 18)
            btn.fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn.fs:SetAllPoints()
            btn.fs:SetJustifyH("CENTER")
            btn:SetScript("OnEnter", function(self)
                if not self.tooltipT then return end
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(self.tooltipT, 1, 1, 1)
                if self.tooltipD then
                    GameTooltip:AddLine(self.tooltipD, 0.8, 0.8, 0.8, true)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return btn
        end,
        function(_, btn)
            btn:Hide()
            btn:ClearAllPoints()
            -- OnClick muss weg, sonst hängt beim Recycling der Handler der Vorgängerspalte dran
            btn:SetScript("OnClick", nil)
            btn.tooltipT, btn.tooltipD = nil, nil
        end
    )

    -- Senkrechte Trenner zwischen den Abend-Gruppen im Spaltenkopf: bei aufgeklappten
    -- Bossspalten wäre sonst nicht erkennbar, welche Spalte zu welchem Abend gehört.
    panel.groupSepPool = UI.CreateFramePool(
        function()
            local tex = colHeader:CreateTexture(nil, "ARTWORK")
            tex:SetColorTexture(0.5, 0.5, 0.5, 0.7)
            tex:SetSize(1, 16)
            return tex
        end,
        function(_, tex) tex:Hide(); tex:ClearAllPoints() end
    )

    -- ── Trennlinie ────────────────────────────────────────────
    local div = panel:CreateTexture(nil, "BACKGROUND")
    div:SetColorTexture(0.4, 0.4, 0.4, 1)
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  colHeader, "BOTTOMLEFT",  0, -2)
    div:SetPoint("TOPRIGHT", colHeader, "BOTTOMRIGHT", 0, -2)

    -- ── Zeilenbereich ─────────────────────────────────────────
    local scroll = CreateFrame("ScrollFrame", "GuildLootAttendanceScroll", panel,
                               "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     div,   "BOTTOMLEFT",  0, -2)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 1)
    scroll:SetScrollChild(content)
    panel.scroll  = scroll
    panel.content = content

    -- Zeilen-Pool. Die Zellen einer Zeile hängen an der Zeile selbst (Texturen statt
    -- Frames — bei 40 Raidern × 12 Spalten ist das deutlich leichter) und werden
    -- wiederverwendet, wenn die Zeile aus dem Pool kommt.
    panel.rowPool = UI.CreateFramePool(
        function()
            local row = CreateFrame("Frame", nil, content)
            row:SetHeight(ROW_H)

            row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.nameFS:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.nameFS:SetWidth(NAME_W)
            row.nameFS:SetJustifyH("LEFT")

            row.pctFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.pctFS:SetPoint("LEFT", row, "LEFT", NAME_W, 0)
            row.pctFS:SetWidth(PCT_W)
            row.pctFS:SetJustifyH("LEFT")

            row.trialCb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.trialCb:SetSize(16, 16)
            row.trialCb:SetPoint("LEFT", row, "LEFT", NAME_W + PCT_W, 0)
            row.trialCb.text:SetText("")

            row.cells = {}
            return row
        end,
        function(_, row)
            row:Hide()
            row:ClearAllPoints()
            row.trialCb:SetScript("OnClick", nil)
            for _, cell in ipairs(row.cells) do cell:Hide() end
        end
    )

    -- Trenner zwischen Kader- und Gast-Block (es gibt höchstens einen)
    local sep = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sep:SetJustifyH("LEFT")
    sep:SetText("|cff888888weitere Teilnehmer|r")
    sep:Hide()
    panel.sepLbl = sep

    -- ── Leerzustand ───────────────────────────────────────────
    local emptyLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLbl:SetPoint("CENTER", scroll, "CENTER", 0, 0)
    emptyLbl:SetJustifyH("CENTER")
    emptyLbl:Hide()
    panel.emptyLbl = emptyLbl

    return panel
end

-- ============================================================
-- Refresh
-- ============================================================

--- Holt eine Zelle der Zeile (legt sie beim ersten Bedarf an) und färbt sie.
local function SetCell(row, index, present)
    local cell = row.cells[index]
    if not cell then
        cell = row:CreateTexture(nil, "ARTWORK")
        cell:SetSize(CELL_W - 6, ROW_H - 6)
        row.cells[index] = cell
    end
    cell:ClearAllPoints()
    cell:SetPoint("LEFT", row, "LEFT", LEFT_W + (index - 1) * CELL_W + 3, 0)
    local c = present and COLOR_PRESENT or COLOR_ABSENT
    cell:SetColorTexture(c[1], c[2], c[3], c[4])
    cell:Show()
end

function UI.RefreshAttendanceTab()
    local panel = UI.attendancePanel
    if not panel or not panel.content then return end
    if UI.activeTab ~= TAB_PLAYER then return end

    local db     = GuildLootDB
    local season = GL.GetActiveSeason()
    local data   = season and GL.ComputeAttendance(season.id)
                   or { season = nil, nights = {}, rows = {} }

    -- Season-Wechsel setzt Blättern und Aufklappen zurück
    local seasonId = season and season.id or nil
    if seasonId ~= lastSeasonId then
        colOffset    = 0
        expanded     = {}
        lastSeasonId = seasonId
    end

    UI.RefreshSeasonControls(data)

    panel.rowPool:ReleaseAll()
    panel.headerPool:ReleaseAll()
    panel.groupSepPool:ReleaseAll()
    panel.sepLbl:Hide()

    -- ── Leerzustände: ein leerer Tab darf nicht wie ein Defekt aussehen ──
    local msg = nil
    if not season then
        msg = "Keine Season aktiv.\n|cff888888Oben eine anlegen.|r"
    elseif #data.rows == 0 then
        msg = "Kein Rang für den Kader gewählt.\n|cff888888Oben \"Kader ab Rang\" setzen.|r"
    elseif #data.nights == 0 then
        msg = "Noch keine Raid-Abende in dieser Season.\n"
              .. "|cff888888Liegen die Raids davor? Dann das Startdatum der Season zurücksetzen.|r"
    end

    -- ── Spaltenfenster bestimmen ──────────────────────────────
    -- Spalten statt Abende: ein aufgeklappter Abend liefert mehrere (Core_Attendance)
    local allCols   = GL.BuildAttendanceColumns(data.nights, expanded)
    local visible   = VisibleColumnCount(panel)
    local totalCols = #allCols

    -- Frisch aufgeklappt: ans linke Fensterende springen, sonst schiebt der Abend seine
    -- eigenen Bossspalten aus dem Sichtbereich und der Klick sähe folgenlos aus
    if pendingFocusNight then
        for i, col in ipairs(allCols) do
            if col.nightId == pendingFocusNight then colOffset = i - 1; break end
        end
        pendingFocusNight = nil
    end

    local maxOffset = math.max(0, totalCols - visible)
    if colOffset > maxOffset then colOffset = maxOffset end

    local shown = {}
    for i = colOffset + 1, math.min(colOffset + visible, totalCols) do
        table.insert(shown, allCols[i])
    end

    -- Pager nur zeigen, wenn es etwas zu blättern gibt
    local hasPaging = totalCols > visible
    panel.prevBtn:SetShown(hasPaging)
    panel.nextBtn:SetShown(hasPaging)
    panel.prevBtn:SetEnabled(colOffset > 0)
    panel.nextBtn:SetEnabled(colOffset < maxOffset)
    if hasPaging then
        panel.pageLbl:SetText(string.format("|cff888888%d–%d/%d|r",
            colOffset + 1, colOffset + #shown, totalCols))
    else
        panel.pageLbl:SetText("")
    end

    -- ── Spaltenköpfe ──────────────────────────────────────────
    for i, col in ipairs(shown) do
        local x   = LEFT_W + (i - 1) * CELL_W
        local btn = panel.headerPool:Acquire()
        btn:SetPoint("TOPLEFT", panel.colHeader, "TOPLEFT", x, 0)
        btn.fs:SetText(col.label)
        btn.tooltipT, btn.tooltipD = col.tooltipT, col.tooltipD

        if col.expandable then
            btn.fs:SetTextColor(1, 0.8, 0)
            local nightId = col.nightId
            btn:SetScript("OnClick", function()
                if expanded[nightId] then
                    expanded[nightId] = nil
                else
                    expanded[nightId]  = true
                    pendingFocusNight  = nightId
                end
                UI.RefreshAttendanceTab()
            end)
        else
            -- Abend ohne einzelne Bosskills: gedämpft, damit der tote Klick sichtbar ist
            btn.fs:SetTextColor(0.65, 0.55, 0.3)
        end
        btn:Show()

        -- Trenner links vor der ersten Spalte eines Abends (nicht ganz links außen)
        if col.groupStart and i > 1 then
            local tex = panel.groupSepPool:Acquire()
            tex:SetPoint("TOPLEFT", panel.colHeader, "TOPLEFT", x - 1, 0)
            tex:Show()
        end
    end

    if msg then
        panel.emptyLbl:SetText(msg)
        panel.emptyLbl:Show()
        panel.content:SetHeight(1)
        return
    end
    panel.emptyLbl:Hide()

    -- ── Zeilen ────────────────────────────────────────────────
    local scrollW = panel.scroll:GetWidth() or 0
    if scrollW > 10 then panel.content:SetWidth(scrollW) end
    local rowW = math.max(panel.content:GetWidth() - 8, 200)

    local yOff, lastGroup = 0, nil
    for _, entry in ipairs(data.rows) do
        -- Trenner beim Wechsel Kader → Gäste
        if lastGroup == "roster" and entry.group == "guest" then
            panel.sepLbl:ClearAllPoints()
            panel.sepLbl:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 4, yOff - 3)
            panel.sepLbl:Show()
            yOff = yOff - SEP_H
        end
        lastGroup = entry.group

        local row = panel.rowPool:Acquire()
        row:SetWidth(rowW)
        row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 4, yOff)

        row.nameFS:SetText(GL.ColoredName(GL.ShortName(entry.name), entry.class))
        row.pctFS:SetText(string.format("%d%%", entry.pct or 0))

        row.trialCb:SetChecked(entry.trial and true or false)
        local playerName = entry.name
        row.trialCb:SetScript("OnClick", function(self)
            GL.CreatePlayerRecord(playerName)
            db.players[playerName].trial = self:GetChecked() and true or false
        end)

        for i, col in ipairs(shown) do
            -- col.key ist je nach Zustand die Abend- oder die Bosskill-ID
            SetCell(row, i, entry.present[col.key])
        end
        for i = #shown + 1, #row.cells do row.cells[i]:Hide() end

        row:Show()
        yOff = yOff - ROW_H
    end

    panel.content:SetHeight(math.max(math.abs(yOff), 1))
end
