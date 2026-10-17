-- GuildLoot – UI_TradeDebug.lua
-- Trade-Debug-Fenster (/reqrt tradelog): jede Zuteilung der Raid Session mit ihrem
-- Auto-Trade-Status, manuellen Eingriffen und dem Ereignisprotokoll.
--
-- Daten und Aktionen kommen ausschließlich aus GL.TradeLog / GL.TradeTrace — das Fenster
-- rechnet nichts selbst. Damit bleibt die Logik in busted testbar.

local GL = GuildLoot
local UI = GL.UI

local FRAME_W, FRAME_H = 800, 460
local ROW_H            = 20
local DROP_H           = 34

-- Spalten: x-Offset und Breite innerhalb einer Zeile
local COL = {
    time      = {   4,  44 },
    item      = {  52, 210 },
    assigned  = { 266, 100 },
    recipient = { 370, 120 },
    status    = { 494, 100 },
    attempts  = { 598,  30 },
    remaining = { 632,  42 },
    actions   = { 680,  80 },
}

local STATUS_TEXT = {
    queued   = { "wartet",          1.0, 0.82, 0.0 },
    staged   = { "im Handel",       1.0, 0.82, 0.0 },
    traded   = { "gehandelt",       0.2, 0.9,  0.2 },
    aborted  = { "abgebrochen",     1.0, 0.55, 0.1 },
    bound    = { "gebunden",        1.0, 0.27, 0.27 },
    notFound = { "nicht in Tasche", 1.0, 0.27, 0.27 },
    expired  = { "abgelaufen",      1.0, 0.27, 0.27 },
    self     = { "eigenes Item",    0.6, 0.6,  0.6 },
    removed  = { "entfernt",        0.6, 0.6,  0.6 },
}
local STATUS_NONE = { "—", 0.5, 0.5, 0.5 }

-- "Nur offene": alles, was noch Handlungsbedarf hat
local NEEDS_ACTION = { queued = true, staged = true, aborted = true, bound = true, notFound = true, expired = true }

local frame, listScroll, listContent, traceScroll, traceText, summaryText, dropZone
local rowPool, picker, ticker
local showTrace  = false
local onlyOpen   = false
local removeArmed = nil  -- Eintrag, für den "✕" einmal geklickt wurde ("Sure?"-Muster)

-- ============================================================
-- Hilfen
-- ============================================================

local function ActiveSession()
    local db = GuildLootDB
    local idx = db.activeContainerIdx
    return idx and db.raidContainers and db.raidContainers[idx] or nil
end

local function FormatRemaining(sec)
    if not sec then return "" end
    return string.format("%d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60))
end

local function SetTooltip(widget, lines)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local l = type(lines) == "function" and lines() or lines
        for i, line in ipairs(l) do
            if i == 1 then GameTooltip:SetText(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function MakeIconButton(parent, texture, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:SetNormalTexture(texture)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    return b
end

-- ============================================================
-- Spielerauswahl (Raidliste)
-- ============================================================

--- Kandidaten für den Empfänger: aktuelle Raidteilnehmer plus alle Spieler der Session.
local function CollectNames()
    local db, seen, names = GuildLootDB, {}, {}
    local function add(n)
        if n and n ~= "" and not seen[n] then seen[n] = true; names[#names + 1] = n end
    end
    for _, n in ipairs(db.currentRaid and db.currentRaid.participants or {}) do add(n) end
    local session = ActiveSession()
    for _, e in ipairs(session and session.lootLog or {}) do add(e.player) end
    table.sort(names)
    return names
end

--- Öffnet die Raidliste neben dem Fenster und ruft onPick(fullName) bei Auswahl.
local function ShowPicker(title, onPick)
    if not picker then
        local inner
        picker, inner = UI.CreateSidePanel(nil, UIParent, "Trade an …")
        picker:SetFrameStrata("DIALOG")
        picker:SetClampedToScreen(true)
        picker:SetWidth(200)
        picker.inner = inner
        picker.buttons = {}
    end
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT",    frame, "TOPRIGHT",    4, 0)
    picker:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 4, 0)

    local inner = picker.inner
    for _, b in ipairs(picker.buttons) do b:Hide() end

    local names = CollectNames()
    local yOff = 0
    for i, name in ipairs(names) do
        local btn = picker.buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, inner)
            btn:SetHeight(22)
            btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            btn.lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn.lbl:SetAllPoints()
            btn.lbl:SetJustifyH("LEFT")
            picker.buttons[i] = btn
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  inner, "TOPLEFT",  4, yOff)
        btn:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -4, yOff)
        btn.lbl:SetText(name)
        btn:SetScript("OnClick", function()
            picker:Hide()
            onPick(name)
        end)
        btn:Show()
        yOff = yOff - 22
    end
    if #names == 0 then
        GL.Print("Keine Raidteilnehmer bekannt — Raid Session starten oder Gruppe beitreten.")
        picker:Hide()
        return
    end
    inner:SetHeight(math.max(1, -yOff))
    if title then GL.Print(title) end
    picker:Show()
end

-- ============================================================
-- Zeilen
-- ============================================================

local function CreateRow(pool)
    local r = CreateFrame("Frame", nil, listContent)
    r:SetHeight(ROW_H)

    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    r.bg = bg

    local function Text(col, justify)
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", r, "LEFT", COL[col][1], 0)
        fs:SetWidth(COL[col][2])
        fs:SetJustifyH(justify or "LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    r.time      = Text("time")
    r.assigned  = Text("assigned")
    r.status    = Text("status")
    r.attempts  = Text("attempts", "CENTER")
    r.remaining = Text("remaining", "RIGHT")

    -- Item: Tooltip mit dem echten Item
    r.itemBtn = CreateFrame("Button", nil, r)
    r.itemBtn:SetPoint("LEFT", r, "LEFT", COL.item[1], 0)
    r.itemBtn:SetSize(COL.item[2], ROW_H)
    r.itemText = r.itemBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.itemText:SetAllPoints()
    r.itemText:SetJustifyH("LEFT")
    r.itemText:SetWordWrap(false)
    r.itemBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Empfänger: Klick öffnet die Raidliste
    r.recipBtn = CreateFrame("Button", nil, r)
    r.recipBtn:SetPoint("LEFT", r, "LEFT", COL.recipient[1], 0)
    r.recipBtn:SetSize(COL.recipient[2], ROW_H)
    r.recipBtn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.recipText = r.recipBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.recipText:SetAllPoints()
    r.recipText:SetJustifyH("LEFT")
    r.recipText:SetWordWrap(false)

    -- Aktionen: erledigt · wieder in Queue · entfernen
    local x = COL.actions[1]
    r.doneBtn = MakeIconButton(r, "Interface\\RaidFrame\\ReadyCheck-Ready", 16)
    r.doneBtn:SetPoint("LEFT", r, "LEFT", x, 0)
    r.requeueBtn = MakeIconButton(r, "Interface\\Buttons\\UI-RefreshButton", 16)
    r.requeueBtn:SetPoint("LEFT", r.doneBtn, "RIGHT", 6, 0)
    r.removeBtn = MakeIconButton(r, "Interface\\RaidFrame\\ReadyCheck-NotReady", 16)
    r.removeBtn:SetPoint("LEFT", r.requeueBtn, "RIGHT", 6, 0)
    r.sure = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.sure:SetPoint("LEFT", r.removeBtn, "RIGHT", 3, 0)
    r.sure:SetText("|cffff4444Sure?|r")

    SetTooltip(r.doneBtn,    { "Erledigt", "Als gehandelt markieren, z.B. nach einem Handel von Hand." })
    SetTooltip(r.requeueBtn, { "Wieder in Queue", "Der Auto-Trade bietet das Item beim nächsten Handel wieder an. Startet das 2h-Fenster neu." })
    SetTooltip(r.removeBtn,  { "Entfernen", "Aus dem Auto-Trade nehmen. Zweimal klicken. Die Zuteilung selbst bleibt erhalten; von Hand vorbereitete Einträge werden gelöscht." })
    return r
end

local function ResetRow(pool, r)
    r:Hide()
    r:ClearAllPoints()
end

local function FillRow(r, row, index)
    local e = row.entry
    r.bg:SetColorTexture(1, 1, 1, (index % 2 == 0) and 0.04 or 0)

    r.time:SetText(date("%H:%M", row.ts))
    r.itemText:SetText((row.manual and "|cff88ccff[M]|r " or "") .. GL.ColoredItemName(row.link))
    r.itemBtn:SetScript("OnEnter", function(self)
        if row.link and row.link:find("|H") then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(row.link:match("|H(.-)|h") or row.link)
            GameTooltip:Show()
        end
    end)

    r.assigned:SetText(row.manual and "|cff888888(manuell)|r" or GL.ShortName(row.assigned or "?"))
    local recip = GL.ShortName(row.recipient or "?")
    r.recipText:SetText(row.redirected and ("|cff88ccff→ " .. recip .. "|r") or recip)
    r.recipBtn:SetScript("OnClick", function()
        ShowPicker(nil, function(name) GL.TradeLog.Redirect(e, name) end)
    end)
    SetTooltip(r.recipBtn, function()
        local lines = { "Trade an: " .. tostring(row.recipient) }
        if row.redirected then lines[#lines + 1] = "Umgeleitet — zugeteilt war " .. tostring(row.assigned) end
        lines[#lines + 1] = "Klicken, um einen anderen Empfänger für den Auto-Trade zu wählen. Die Zuteilung bleibt unverändert."
        return lines
    end)

    local st = row.status and STATUS_TEXT[row.status] or STATUS_NONE
    r.status:SetText(st[1])
    r.status:SetTextColor(st[2], st[3], st[4])
    r.attempts:SetText(row.attempts > 0 and tostring(row.attempts) or "")
    r.remaining:SetText(FormatRemaining(row.remaining))

    r.doneBtn:SetShown(row.status ~= "traded" and row.status ~= nil)
    r.doneBtn:SetScript("OnClick", function() GL.TradeLog.MarkDone(e) end)
    r.requeueBtn:SetShown(not row.open and row.status ~= "self")
    r.requeueBtn:SetScript("OnClick", function() GL.TradeLog.Requeue(e) end)
    r.removeBtn:SetShown(row.status ~= "removed" and row.status ~= nil)
    r.sure:SetShown(removeArmed == e)
    r.removeBtn:SetScript("OnClick", function()
        if removeArmed == e then
            removeArmed = nil
            GL.TradeLog.Remove(e)
        else
            removeArmed = e
            UI.RefreshTradeDebug()
            C_Timer.After(3, function()
                if removeArmed == e then removeArmed = nil; UI.RefreshTradeDebug() end
            end)
        end
    end)
end

-- ============================================================
-- Refresh
-- ============================================================

local function RefreshList(now)
    rowPool:ReleaseAll()
    local rows, shown = GL.TradeLog.Rows(nil, now), 0
    local y = 0
    for _, row in ipairs(rows) do
        if not onlyOpen or (row.status and NEEDS_ACTION[row.status]) then
            shown = shown + 1
            local r = rowPool:Acquire()
            r:SetPoint("TOPLEFT",  listContent, "TOPLEFT",  0, y)
            r:SetPoint("TOPRIGHT", listContent, "TOPRIGHT", 0, y)
            FillRow(r, row, shown)
            r:Show()
            y = y - ROW_H
        end
    end
    listContent:SetHeight(math.max(1, -y))
    frame.emptyText:SetShown(shown == 0)
end

local function RefreshTrace()
    local lines = {}
    for _, e in ipairs(GL.TradeTrace.Entries()) do lines[#lines + 1] = GL.TradeTrace.Format(e) end
    traceText:SetText(#lines > 0 and table.concat(lines, "\n") or "|cff888888Noch keine Ereignisse aufgezeichnet.|r")
    traceText:SetWidth(traceScroll:GetWidth() - 8)
    traceText:GetParent():SetHeight(math.max(1, traceText:GetStringHeight() + 8))
end

function UI.RefreshTradeDebug()
    if not (frame and frame:IsShown()) then return end
    local now = time()
    GL.TradeLog.ExpireStale(now)

    local session = ActiveSession()
    local waiting, staged = GL.TradeLog.QueueSummary(now)
    summaryText:SetText(string.format("%s   ·   Queue: |cffffd100%d wartend|r · |cffffd100%d im Handel|r   ·   Protokoll: %d",
        session and (session.label or "Raid Session") or "|cffff8888Keine aktive Raid Session|r",
        waiting, staged, #(GuildLootDB.tradeTrace or {})))

    listScroll:SetShown(not showTrace)
    dropZone:SetShown(not showTrace)
    frame.header:SetShown(not showTrace)
    frame.onlyOpen:SetShown(not showTrace)
    traceScroll:SetShown(showTrace)
    frame.emptyText:SetShown(false)
    frame.viewBtn:SetText(showTrace and "Liste" or "Ereignisse")

    if showTrace then RefreshTrace() else RefreshList(now) end
end

-- ============================================================
-- Aufbau
-- ============================================================

local function BuildHeader()
    local h = CreateFrame("Frame", nil, frame)
    h:SetPoint("TOPLEFT",  frame, "TOPLEFT",  10, -56)
    h:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -56)
    h:SetHeight(16)
    local function Head(col, text, justify)
        local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", h, "LEFT", COL[col][1], 0)
        fs:SetWidth(COL[col][2])
        fs:SetJustifyH(justify or "LEFT")
        fs:SetText(text)
    end
    Head("time", "Zeit")
    Head("item", "Item")
    Head("assigned", "Zugeteilt an")
    Head("recipient", "Trade an")
    Head("status", "Status")
    Head("attempts", "Vers.", "CENTER")
    Head("remaining", "Rest", "RIGHT")
    Head("actions", "Aktionen")
    frame.header = h
end

local function BuildDropZone()
    dropZone = CreateFrame("Button", nil, frame, "BackdropTemplate")
    dropZone:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  10, 10)
    dropZone:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    dropZone:SetHeight(DROP_H)
    dropZone:SetBackdrop(UI.BACKDROPS.DARK)
    dropZone:SetBackdropColor(0.05, 0.05, 0.1, 1)
    dropZone:SetBackdropBorderColor(0.4, 0.4, 0.6, 1)
    dropZone:RegisterForDrag("LeftButton")
    local hint = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("CENTER")
    hint:SetText("|cff888888Item aus der Tasche hier ablegen, um einen Handel von Hand vorzubereiten|r")

    dropZone:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.8, 0, 1) end)
    dropZone:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.4, 0.4, 0.6, 1) end)
    local function tryDrop()
        local infoType, _, itemLink = GetCursorInfo()
        if infoType ~= "item" or not itemLink then return end
        ClearCursor()
        ShowPicker("Empfänger für " .. itemLink .. " wählen:", function(name)
            GL.TradeLog.AddManual(itemLink, name)
        end)
    end
    dropZone:SetScript("OnReceiveDrag", tryDrop)
    dropZone:SetScript("OnClick",       tryDrop)
end

local function Build()
    frame = CreateFrame("Frame", "RequiemTradeDebugFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    local mover = UI.RegisterMovableFrame(frame, "tradeDebug")
    UI.RaiseAboveMover(mover, frame.CloseButton)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -6)
    title:SetText("Auto-Trade")

    summaryText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryText:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -34)
    summaryText:SetJustifyH("LEFT")

    local viewBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    viewBtn:SetSize(90, 20)
    viewBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -30)
    viewBtn:SetScript("OnClick", function() showTrace = not showTrace; UI.RefreshTradeDebug() end)
    frame.viewBtn = viewBtn

    local copyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    copyBtn:SetSize(80, 20)
    copyBtn:SetPoint("RIGHT", viewBtn, "LEFT", -4, 0)
    copyBtn:SetText("Kopieren")
    copyBtn:SetScript("OnClick", function()
        UI.ShowExportPopup(nil, GL.TradeTrace.AsText())
    end)
    SetTooltip(copyBtn, { "Protokoll kopieren", "Öffnet das gesamte Ereignisprotokoll als Text zum Kopieren (Strg+C)." })

    local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(70, 20)
    refreshBtn:SetPoint("RIGHT", copyBtn, "LEFT", -4, 0)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function() UI.RefreshTradeDebug() end)

    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("RIGHT", refreshBtn, "LEFT", -80, 0)
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text:SetText("Nur offene")
    cb:SetScript("OnClick", function(self) onlyOpen = self:GetChecked() and true or false; UI.RefreshTradeDebug() end)
    frame.onlyOpen = cb

    BuildHeader()
    BuildDropZone()

    -- Liste
    listScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT",     frame, "TOPLEFT",     10, -74)
    listScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 16 + DROP_H)
    listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(FRAME_W - 40, 1)
    listScroll:SetScrollChild(listContent)
    rowPool = UI.CreateFramePool(CreateRow, ResetRow)

    frame.emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.emptyText:SetPoint("CENTER", listScroll, "CENTER")
    frame.emptyText:SetText("Keine Einträge.")

    -- Ereignisprotokoll
    traceScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    traceScroll:SetPoint("TOPLEFT",     frame, "TOPLEFT",     10, -56)
    traceScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 10)
    local traceContent = CreateFrame("Frame", nil, traceScroll)
    traceContent:SetSize(FRAME_W - 40, 1)
    traceScroll:SetScrollChild(traceContent)
    traceText = traceContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    traceText:SetPoint("TOPLEFT", traceContent, "TOPLEFT", 4, -4)
    traceText:SetJustifyH("LEFT")
    traceText:SetJustifyV("TOP")
    traceScroll:Hide()

    -- Restzeiten laufen weiter, solange das Fenster offen ist
    -- HookScript statt SetScript: RegisterMovableFrame hängt selbst an OnShow (Position)
    frame:HookScript("OnShow", function()
        if ticker then ticker:Cancel() end
        ticker = C_Timer.NewTicker(30, UI.RefreshTradeDebug)
        UI.RefreshTradeDebug()
    end)
    frame:HookScript("OnHide", function()
        if ticker then ticker:Cancel(); ticker = nil end
        if picker then picker:Hide() end
        removeArmed = nil
    end)
end

function UI.ToggleTradeDebug()
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end
