-- GuildLoot – UI_RaidTab.lua
-- Raid-Tab: Session-Liste, Raid-Rows, Detail-Ansicht

local GL = GuildLoot
local UI = GL.UI

local TAB_LOOT        = UI.TAB_LOOT
local TAB_RAID        = UI.TAB_RAID
local ColorDiff       = UI._H.ColorDiff
local MakeItemLinkBtn = UI._H.MakeItemLinkBtn

-- ============================================================
-- File-local State
-- ============================================================

local listRows         = {}
local detailRows       = {}
-- expandedSessions[sessionID] = true/false; nil = expanded (default)
local expandedSessions   = {}
local expandedUnassigned = true
-- selectedRaid = { sessionID, raidID } | { unassignedIdx } | { ci } (session selected)
local selectedRaid = nil
-- checkedUnassigned[idx] = true für Multi-Select-Assign
local checkedUnassigned = {}

local SESSION_HDR_H = 26
local RAID_LINE_H   = 18   -- Höhe einer einzelnen Textzeile in der Raid-Row
local RAID_ROW_H    = RAID_LINE_H + 4  -- Standardhöhe für einfache Rows (Platzhalter, Unassigned)

-- ============================================================
-- Shims
-- ============================================================

function UI.UpdateEndResumeBtn() end
function UI.UpdateStartRaidBtn() end

-- ============================================================
-- Panel bauen
-- ============================================================

function UI.BuildRaidPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT",     parent, "TOPLEFT",     0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    panel:Hide()

    local LIST_W = 294

    -- ---- Control Strip ----
    local cs = CreateFrame("Frame", nil, panel)
    cs:SetPoint("TOPLEFT",  panel, "TOPLEFT",  2, -2)
    cs:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
    cs:SetHeight(28)

    -- New Raid Session / Close Raid Session
    local sessionBtn = CreateFrame("Button", nil, cs, "UIPanelButtonTemplate")
    sessionBtn:SetSize(150, 22)
    sessionBtn:SetPoint("LEFT", cs, "LEFT", 4, 0)
    sessionBtn:SetScript("OnClick", function()
        if GuildLootDB.activeContainerIdx then
            GL.CloseContainer()
            UI.RefreshRaidTab()
            UI.RefreshSessionBar()
        else
            StaticPopup_Show("RLT_NEW_SESSION")
        end
    end)
    panel.sessionBtn = sessionBtn

    -- Resume Raid Session
    local resumeBtn = CreateFrame("Button", nil, cs, "UIPanelButtonTemplate")
    resumeBtn:SetSize(90, 22)
    resumeBtn:SetPoint("LEFT", sessionBtn, "RIGHT", 4, 0)
    resumeBtn:SetText("Resume")
    resumeBtn:SetEnabled(false)
    resumeBtn:SetScript("OnClick", function()
        if selectedRaid and selectedRaid.ci then
            GL.ResumeContainer(selectedRaid.ci)
            UI.RefreshRaidTab()
            UI.RefreshSessionBar()
        end
    end)
    panel.resumeBtn = resumeBtn

    -- Export
    local exportBtn = CreateFrame("Button", nil, cs, "UIPanelButtonTemplate")
    exportBtn:SetSize(64, 22)
    exportBtn:SetPoint("LEFT", resumeBtn, "RIGHT", 4, 0)
    exportBtn:SetText("Export")
    exportBtn:SetEnabled(false)
    exportBtn:SetScript("OnClick", function()
        if not selectedRaid then return end
        local db = GuildLootDB
        if selectedRaid.raidID then
            -- Einzelner Raid aus einer Session: gefilterten Snapshot exportieren
            local session = (function()
                for _, s in ipairs(db.raidContainers or {}) do
                    if s.id == selectedRaid.sessionID then return s end
                end
            end)()
            if not session then return end
            local meta = session.raidMeta and session.raidMeta[selectedRaid.raidID]
            local filteredLoot    = {}
            local filteredTrashed = {}
            for _, e in ipairs(session.lootLog or {}) do
                if e.raidID == selectedRaid.raidID then table.insert(filteredLoot, e) end
            end
            for _, e in ipairs(session.trashedLoot or {}) do
                if e.raidID == selectedRaid.raidID then table.insert(filteredTrashed, e) end
            end
            local raidSnap = {
                id          = selectedRaid.raidID,
                tier        = meta and meta.tier       or "",
                difficulty  = meta and meta.difficulty or "",
                startedAt   = meta and meta.startedAt  or 0,
                closedAt    = meta and meta.closedAt   or nil,
                lootLog     = filteredLoot,
                trashedLoot = filteredTrashed,
            }
            UI.ShowExportPopup(raidSnap)
        elseif selectedRaid.ci then
            UI.ShowExportPopup(db.raidContainers[selectedRaid.ci])
        elseif selectedRaid.unassignedIdx then
            UI.ShowExportPopup((db.unassignedRaids or {})[selectedRaid.unassignedIdx])
        end
    end)
    panel.exportBtn = exportBtn

    -- Rename
    local renameBtn = CreateFrame("Button", nil, cs, "UIPanelButtonTemplate")
    renameBtn:SetSize(60, 22)
    renameBtn:SetPoint("LEFT", exportBtn, "RIGHT", 4, 0)
    renameBtn:SetText("Rename")
    renameBtn:SetEnabled(false)
    renameBtn:SetScript("OnClick", function()
        if selectedRaid and selectedRaid.ci then
            StaticPopup_Show("RLT_RENAME_SESSION")
        end
    end)
    panel.renameBtn = renameBtn

    -- Delete
    local deleteBtn = CreateFrame("Button", nil, cs, "UIPanelButtonTemplate")
    deleteBtn:SetSize(54, 22)
    deleteBtn:SetPoint("LEFT", renameBtn, "RIGHT", 4, 0)
    deleteBtn:SetText("Delete")
    deleteBtn:SetEnabled(false)
    local delPending = false; local delTimer = nil
    deleteBtn:SetScript("OnClick", function()
        if not selectedRaid then return end
        if delPending then
            if delTimer then delTimer:Cancel(); delTimer = nil end
            delPending = false; deleteBtn:SetText("Delete")
            local db = GuildLootDB
            if selectedRaid.ci then
                local ci = selectedRaid.ci
                table.remove(db.raidContainers, ci)
                if db.activeContainerIdx == ci then
                    db.activeContainerIdx = nil; GL.ResetCurrentRaid()
                elseif db.activeContainerIdx and db.activeContainerIdx > ci then
                    db.activeContainerIdx = db.activeContainerIdx - 1
                end
            elseif selectedRaid.unassignedIdx then
                table.remove(db.unassignedRaids or {}, selectedRaid.unassignedIdx)
                checkedUnassigned = {}
            end
            selectedRaid = nil
            UI.RefreshRaidTab(); UI.RefreshSessionBar()
        else
            delPending = true; deleteBtn:SetText("|cffff4444Sure?|r")
            delTimer = C_Timer.NewTimer(3, function()
                delPending = false; delTimer = nil; deleteBtn:SetText("Delete")
            end)
        end
    end)
    panel.deleteBtn = deleteBtn

    -- Assign (unassigned raid → session)
    local assignBtn = CreateFrame("Button", nil, cs, "UIPanelButtonTemplate")
    assignBtn:SetSize(70, 22)
    assignBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 4, 0)
    assignBtn:SetText("Assign")
    assignBtn:SetEnabled(false)
    assignBtn:SetScript("OnClick", function()
        if not next(checkedUnassigned) then return end
        UI.ShowSessionPickerForAssign(assignBtn)
    end)
    panel.assignBtn = assignBtn

    -- ---- Liste (links) ----
    local listFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    listFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    listFrame:SetPoint("TOPLEFT",    cs,    "BOTTOMLEFT",  0, -2)
    listFrame:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT",  2,  2)
    listFrame:SetWidth(LIST_W)

    local listScroll = CreateFrame("ScrollFrame", "GuildLootRaidListScroll", listFrame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT",     listFrame, "TOPLEFT",     4, -4)
    listScroll:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -22, 4)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(listScroll:GetWidth(), 1)
    listScroll:SetScrollChild(listContent)
    panel.listContent = listContent
    panel.listScroll  = listScroll

    -- ---- Detail (rechts) ----
    local detailFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    detailFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    detailFrame:SetPoint("TOPLEFT",     listFrame, "TOPRIGHT",     4,  0)
    detailFrame:SetPoint("BOTTOMRIGHT", panel,     "BOTTOMRIGHT", -2,  2)

    panel.detailHeader = detailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.detailHeader:SetPoint("TOPLEFT",  detailFrame, "TOPLEFT",  6,  -6)
    panel.detailHeader:SetPoint("TOPRIGHT", detailFrame, "TOPRIGHT", -28, -6)
    panel.detailHeader:SetWordWrap(true)
    panel.detailHeader:SetJustifyH("LEFT")
    panel.detailHeader:SetText("|cff888888— Auswahl treffen —|r")

    local detailScroll = CreateFrame("ScrollFrame", "GuildLootRaidDetailScroll", detailFrame, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT",     panel.detailHeader, "BOTTOMLEFT",  0, -4)
    detailScroll:SetPoint("BOTTOMRIGHT", detailFrame,        "BOTTOMRIGHT", -22, 4)
    local detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetSize(detailScroll:GetWidth(), 1)
    detailScroll:SetScrollChild(detailContent)
    panel.detailContent = detailContent
    panel.detailScroll  = detailScroll

    return panel
end

-- ============================================================
-- Control-Strip-Buttons aktualisieren
-- ============================================================

local function UpdateControlStrip()
    local panel = UI.raidPanel
    if not panel then return end
    local db = GuildLootDB

    -- Session-Button
    if db.activeContainerIdx then
        local s = db.raidContainers[db.activeContainerIdx]
        panel.sessionBtn:SetText("Close Raid Session")
    else
        panel.sessionBtn:SetText("New Raid Session")
    end

    -- Resume: nur wenn eine inaktive Session selektiert
    local canResume = selectedRaid and selectedRaid.ci
                   and (db.activeContainerIdx ~= selectedRaid.ci)
                   and not db.activeContainerIdx  -- nur wenn gerade keine Session offen
    panel.resumeBtn:SetEnabled(canResume and true or false)

    -- Rename: nur wenn Session-Header selektiert (nicht Einzel-Raid, nicht Unassigned)
    local canRename = selectedRaid and selectedRaid.ci ~= nil and selectedRaid.raidID == nil
    panel.renameBtn:SetEnabled(canRename and true or false)

    -- Export + Delete: wenn etwas selektiert
    local hasSel = selectedRaid ~= nil
    panel.exportBtn:SetEnabled(hasSel)
    panel.deleteBtn:SetEnabled(hasSel)

    -- Assign: wenn mindestens eine Checkbox gecheckt und Sessions vorhanden
    local canAssign = next(checkedUnassigned) ~= nil
                   and #(GuildLootDB.raidContainers or {}) > 0
    panel.assignBtn:SetEnabled(canAssign and true or false)
    local checkedCount = 0
    for _ in pairs(checkedUnassigned) do checkedCount = checkedCount + 1 end
    panel.assignBtn:SetText(checkedCount > 1 and ("Assign (" .. checkedCount .. ")") or "Assign")
end

-- ============================================================
-- Helfer: Detail-Zeile
-- ============================================================

local function MakeDetailRow(parent, entry, yOff)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth() - 20, 20)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOff)

    local ts = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ts:SetPoint("LEFT", row, "LEFT", 4, 0)
    ts:SetWidth(80)
    ts:SetText(GL.FormatTimestamp(entry.timestamp))
    ts:SetTextColor(0.6, 0.6, 0.6)

    local playerLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playerLbl:SetPoint("LEFT", ts, "RIGHT", 4, 0)
    playerLbl:SetWidth(110)
    playerLbl:SetText(GL.ShortName(entry.player or "?"))

    local diffLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    diffLbl:SetPoint("LEFT", playerLbl, "RIGHT", 4, 0)
    diffLbl:SetWidth(25)
    diffLbl:SetText(ColorDiff(entry.difficulty))

    MakeItemLinkBtn(row, diffLbl, 4, entry.link or entry.item, entry.item or "?")

    row:Show()
    table.insert(detailRows, row)
    return 22
end

-- ============================================================
-- Helfer: Session-Header
-- ============================================================

local function MakeSessionHeader(parent, session, ci, yOff, expanded)
    local db       = GuildLootDB
    local isActive = (db.activeContainerIdx == ci)
    local isSel    = selectedRaid and selectedRaid.ci == ci

    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, yOff)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOff)
    row:SetHeight(SESSION_HDR_H)

    -- Hintergrund
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if isActive then
        bg:SetColorTexture(0, 0.4, 0.05, 0.22)
    elseif isSel then
        bg:SetColorTexture(1, 0.8, 0, 0.15)
    else
        bg:SetColorTexture(0.15, 0.15, 0.2, 0.6)
    end

    -- Aktive Session: obere Rahmenlinie (immer); untere nur wenn zugeklappt
    if isActive then
        local top = row:CreateTexture(nil, "OVERLAY", nil, 7)
        top:SetPoint("TOPLEFT",  row, "TOPLEFT",  0,  0)
        top:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0,  0)
        top:SetHeight(1)
        top:SetColorTexture(0.3, 0.9, 0.4, 0.8)
        if not expanded then
            local bot = row:CreateTexture(nil, "OVERLAY", nil, 7)
            bot:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
            bot:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            bot:SetHeight(1)
            bot:SetColorTexture(0.3, 0.9, 0.4, 0.8)
        end
    end

    -- Expand/Collapse Button (Blizzard +/- Textur)
    local toggleBtn = CreateFrame("Button", nil, row)
    toggleBtn:SetSize(14, 14)
    toggleBtn:SetPoint("LEFT", row, "LEFT", 4, 0)
    toggleBtn:SetNormalTexture(expanded
        and "Interface\\Buttons\\UI-MinusButton-Up"
        or  "Interface\\Buttons\\UI-PlusButton-Up")
    toggleBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    toggleBtn:SetScript("OnClick", function()
        expandedSessions[session.id] = not expanded
        UI.RefreshRaidTab()
    end)

    -- Label (klickbar → Session selektieren)
    local labelBtn = CreateFrame("Button", nil, row)
    labelBtn:SetPoint("LEFT",  toggleBtn, "RIGHT", 4, 0)
    labelBtn:SetPoint("RIGHT", row,       "RIGHT", -4, 0)
    labelBtn:SetHeight(SESSION_HDR_H)
    local labelStr = isActive
        and ("|cff00ff00" .. (session.label or "?") .. "|r")
        or  (session.label or "?")
    if session.closedAt then
        local dateStr = date("%d.%m.", session.closedAt)
        labelStr = labelStr .. " |cff555555(" .. dateStr .. ")|r"
    end
    local plCount = #(session.pendingLoot or {})
    if plCount > 0 then
        labelStr = labelStr .. " |cffffcc00[" .. plCount .. " PL]|r"
    end
    local lbl = labelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetAllPoints()
    lbl:SetJustifyH("LEFT")
    lbl:SetText(labelStr)
    labelBtn:SetScript("OnClick", function()
        selectedRaid = { ci = ci }
        UI.RefreshRaidDetail()
        UI.RefreshRaidTab()
    end)
    labelBtn:SetScript("OnEnter", function() lbl:SetTextColor(1, 1, 0.6) end)
    labelBtn:SetScript("OnLeave", function() lbl:SetTextColor(1, 1, 1)   end)

    row:Show()
    table.insert(listRows, row)
    return SESSION_HDR_H
end

-- ============================================================
-- Helfer: Raid-Zeile innerhalb Session
-- ============================================================

local function MakeRaidRow(parent, session, raidID, meta, yOff, isCurrentActive, isActiveSession)
    local isSelected = selectedRaid
                    and selectedRaid.sessionID == session.id
                    and selectedRaid.raidID == raidID

    -- Erst Höhe provisorisch setzen; wird unten nach GetStringHeight korrigiert
    local row = CreateFrame("Button", nil, parent)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  20, yOff)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT",  0, yOff)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if isSelected then
        bg:SetColorTexture(1, 0.8, 0, 0.15)
    elseif isCurrentActive then
        bg:SetColorTexture(0, 0.4, 0.05, 0.22)
    elseif isActiveSession then
        bg:SetColorTexture(0, 0.4, 0.05, 0.22)
    else
        bg:SetColorTexture(1, 1, 1, 0.03)
    end

    local dot = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dot:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -2)
    dot:SetWidth(10)
    dot:SetText(isCurrentActive and "|cff00ff00•|r" or "|cff555555·|r")

    local tierStr = (meta.tier and meta.tier ~= "") and meta.tier or "Unknown"
    local diffStr = (meta.difficulty and meta.difficulty ~= "") and (" " .. ColorDiff(meta.difficulty)) or ""
    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", dot, "TOPRIGHT", 2, 0)
    lbl:SetWidth(190)
    lbl:SetWordWrap(true)
    lbl:SetText(tierStr .. diffStr)
    lbl:SetJustifyH("LEFT")
    lbl:SetJustifyV("TOP")

    -- Dynamische Zeilenhöhe: passt sich Zeilenumbrüchen im Titel an
    local rowH = math.max(RAID_LINE_H, lbl:GetStringHeight()) + 4
    row:SetHeight(rowH)

    local lootCount = 0
    for _, item in ipairs(session.lootLog or {}) do
        if item.raidID == raidID then lootCount = lootCount + 1 end
    end
    local infoLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -2)
    infoLbl:SetJustifyV("TOP")
    if isCurrentActive then
        infoLbl:SetText("|cff00ff00aktiv  |r|cff888888" .. lootCount .. "x|r")
    else
        local dateStr = meta.closedAt and date("%d.%m", meta.closedAt) or "?"
        infoLbl:SetText("|cff888888" .. dateStr .. "  " .. lootCount .. "x|r")
    end

    row:SetScript("OnClick", function()
        selectedRaid = { sessionID = session.id, raidID = raidID }
        UI.RefreshRaidDetail()
        UI.RefreshRaidTab()
    end)
    row:SetScript("OnEnter", function(self) self:SetAlpha(0.75) end)
    row:SetScript("OnLeave", function(self) self:SetAlpha(1) end)
    row:Show()
    table.insert(listRows, row)
    return rowH
end

-- ============================================================
-- Helfer: Unassigned-Raid-Zeile
-- ============================================================

local function MakeUnassignedRow(parent, snap, idx, yOff)
    local isSelected = selectedRaid and selectedRaid.unassignedIdx == idx
    local isChecked  = checkedUnassigned[idx] == true

    local row = CreateFrame("Button", nil, parent)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  20, yOff)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT",  0, yOff)
    row:SetHeight(RAID_ROW_H)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if isChecked then
        bg:SetColorTexture(0.2, 0.6, 1, 0.2)
    elseif isSelected then
        bg:SetColorTexture(1, 0.8, 0, 0.15)
    else
        bg:SetColorTexture(1, 1, 1, 0.03)
    end

    -- Checkbox
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(18, 18)
    cb:SetPoint("LEFT", row, "LEFT", 2, 0)
    cb:SetChecked(isChecked)
    cb:SetScript("OnClick", function(self)
        checkedUnassigned[idx] = self:GetChecked() and true or nil
        UI.RefreshRaidTab()
    end)

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    lbl:SetWidth(110)
    lbl:SetText((snap.tier and snap.tier ~= "") and snap.tier or "Unknown")
    lbl:SetJustifyH("LEFT")

    local diffStr = (snap.difficulty and snap.difficulty ~= "") and (" " .. ColorDiff(snap.difficulty)) or ""
    local diffLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    diffLbl:SetPoint("LEFT", lbl, "RIGHT", 2, 0)
    diffLbl:SetWidth(20)
    diffLbl:SetText(diffStr)

    local lootCount = snap.lootLog and #snap.lootLog or 0
    local dateStr   = snap.closedAt and date("%d.%m", snap.closedAt) or "?"
    local infoLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoLbl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    infoLbl:SetText("|cff888888" .. dateStr .. "  " .. lootCount .. "x|r")

    row:SetScript("OnClick", function()
        selectedRaid = { unassignedIdx = idx }
        UI.RefreshRaidDetail()
        UI.RefreshRaidTab()
    end)
    row:SetScript("OnEnter", function(self) self:SetAlpha(0.75) end)
    row:SetScript("OnLeave", function(self) self:SetAlpha(1) end)
    row:Show()
    table.insert(listRows, row)
    return RAID_ROW_H
end

-- ============================================================
-- Raid-Tab Refresh
-- ============================================================

function UI.RefreshRaidTab()
    if UI.activeTab ~= TAB_RAID then return end
    if not UI.raidPanel or not UI.raidPanel.listContent then return end

    UpdateControlStrip()

    local sw = UI.raidPanel.listScroll and UI.raidPanel.listScroll:GetWidth() or 0
    if sw > 10 then UI.raidPanel.listContent:SetWidth(sw) end

    for _, r in ipairs(listRows) do r:Hide() end
    listRows = {}

    local db      = GuildLootDB
    local content = UI.raidPanel.listContent
    local yOff    = 0

    -- Sessions (neueste zuerst)
    for ci = #(db.raidContainers or {}), 1, -1 do
        local session   = db.raidContainers[ci]
        local isActive  = (db.activeContainerIdx == ci)
        local expanded
        if expandedSessions[session.id] == nil then
            expanded = isActive  -- aktive Session auf, alle anderen zu
        else
            expanded = expandedSessions[session.id]
        end
        yOff = yOff - MakeSessionHeader(content, session, ci, yOff, expanded)

        if expanded then
            local metas = {}
            for raidID, meta in pairs(session.raidMeta or {}) do
                table.insert(metas, { raidID = raidID, meta = meta })
            end
            table.sort(metas, function(a, b)
                return (a.meta.startedAt or 0) > (b.meta.startedAt or 0)
            end)

            local cr = db.currentRaid
            for _, entry in ipairs(metas) do
                local isCurrentActive = isActive
                                     and (cr.id == entry.raidID)
                                     and not entry.meta.closedAt
                yOff = yOff - MakeRaidRow(content, session, entry.raidID, entry.meta, yOff, isCurrentActive, isActive)
            end

            -- Aktiver Raid vor erstem Boss-Kill (noch kein raidMeta)
            if isActiveSess and cr.id and cr.id ~= ""
               and not (session.raidMeta and session.raidMeta[cr.id]) then
                local r = CreateFrame("Frame", nil, content)
                r:SetPoint("TOPLEFT",  content, "TOPLEFT",  20, yOff)
                r:SetPoint("TOPRIGHT", content, "TOPRIGHT",  0, yOff)
                r:SetHeight(RAID_ROW_H)
                local rbg = r:CreateTexture(nil, "BACKGROUND")
                rbg:SetAllPoints()
                rbg:SetColorTexture(0, 0.4, 0.05, 0.22)
                local l = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                l:SetPoint("LEFT", r, "LEFT", 14, 0)
                l:SetText("|cff00ff00• aktiv|r  |cff555555(kein Boss-Kill)|r")
                r:Show()
                table.insert(listRows, r)
                yOff = yOff - RAID_ROW_H
            end

            if not next(session.raidMeta or {}) and db.activeContainerIdx ~= ci then
                local r = CreateFrame("Frame", nil, content)
                r:SetPoint("TOPLEFT",  content, "TOPLEFT",  20, yOff)
                r:SetPoint("TOPRIGHT", content, "TOPRIGHT",  0, yOff)
                r:SetHeight(RAID_ROW_H)
                local l = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                l:SetPoint("LEFT", r, "LEFT", 14, 0)
                l:SetText("|cff555555(keine Raids)|r")
                r:Show()
                table.insert(listRows, r)
                yOff = yOff - RAID_ROW_H
            end

            -- Aktive Session aufgeklappt: untere Rahmenlinie am Ende des Inhalts
            if db.activeContainerIdx == ci then
                local bot = CreateFrame("Frame", nil, content)
                bot:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOff)
                bot:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
                bot:SetHeight(1)
                local t = bot:CreateTexture(nil, "OVERLAY")
                t:SetAllPoints()
                t:SetColorTexture(0.3, 0.9, 0.4, 0.8)
                bot:Show()
                table.insert(listRows, bot)
                yOff = yOff - 1
            end
        end
    end

    -- Unassigned
    local unassigned = db.unassignedRaids or {}
    if #unassigned > 0 then
        local hRow = CreateFrame("Frame", nil, content)
        hRow:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOff)
        hRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
        hRow:SetHeight(SESSION_HDR_H)
        local hBg = hRow:CreateTexture(nil, "BACKGROUND")
        hBg:SetAllPoints()
        hBg:SetColorTexture(0.3, 0.2, 0, 0.5)

        local toggleBtn = CreateFrame("Button", nil, hRow)
        toggleBtn:SetSize(14, 14)
        toggleBtn:SetPoint("LEFT", hRow, "LEFT", 4, 0)
        toggleBtn:SetNormalTexture(expandedUnassigned
            and "Interface\\Buttons\\UI-MinusButton-Up"
            or  "Interface\\Buttons\\UI-PlusButton-Up")
        toggleBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
        toggleBtn:SetScript("OnClick", function()
            expandedUnassigned = not expandedUnassigned
            UI.RefreshRaidTab()
        end)

        local hLbl = hRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hLbl:SetPoint("LEFT", toggleBtn, "RIGHT", 4, 0)
        hLbl:SetText("|cffff9900Unassigned|r")
        hRow:Show()
        table.insert(listRows, hRow)
        yOff = yOff - SESSION_HDR_H

        if expandedUnassigned then
            for i, snap in ipairs(unassigned) do
                yOff = yOff - MakeUnassignedRow(content, snap, i, yOff)
            end
        end
    end

    if #(db.raidContainers or {}) == 0 and #unassigned == 0 then
        local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        empty:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
        empty:SetText("|cff888888Keine Raid Sessions. 'New Raid Session' drücken.|r")
        table.insert(listRows, empty)
        yOff = -20
    end

    content:SetHeight(math.max(1, -yOff))

    if selectedRaid then UI.RefreshRaidDetail() end
end

-- ============================================================
-- Detail-Ansicht
-- ============================================================

function UI.RefreshRaidDetail()
    if not UI.raidPanel or not UI.raidPanel.detailContent then return end

    local sw = UI.raidPanel.detailScroll and UI.raidPanel.detailScroll:GetWidth() or 0
    if sw > 10 then UI.raidPanel.detailContent:SetWidth(sw) end

    for _, r in ipairs(detailRows) do r:Hide() end
    detailRows = {}

    local content = UI.raidPanel.detailContent
    local yOff    = 0

    if not selectedRaid then
        UI.raidPanel.detailHeader:SetText("|cff888888— Auswahl treffen —|r")
        content:SetHeight(1)
        return
    end

    local db = GuildLootDB

    -- Session selektiert (kein Raid)
    if selectedRaid.ci and not selectedRaid.raidID then
        local session = (db.raidContainers or {})[selectedRaid.ci]
        if not session then selectedRaid = nil; UI.raidPanel.detailHeader:SetText("|cff888888— Auswahl treffen —|r"); content:SetHeight(1); return end
        local lootCount = #(session.lootLog or {})
        local raidCount = 0; for _ in pairs(session.raidMeta or {}) do raidCount = raidCount + 1 end
        UI.raidPanel.detailHeader:SetText((session.label or "?")
            .. "  |cff888888" .. raidCount .. " Raids, " .. lootCount .. " Loot|r")
        if lootCount == 0 then
            local e = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            e:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -8)
            e:SetText("|cff888888Kein Loot in dieser Session.|r")
            table.insert(detailRows, e)
            yOff = -20
        else
            for i = #session.lootLog, 1, -1 do
                yOff = yOff - MakeDetailRow(content, session.lootLog[i], yOff)
            end
        end
        content:SetHeight(math.max(1, -yOff))
        return
    end

    -- Unassigned Raid
    if selectedRaid.unassignedIdx then
        local snap = (db.unassignedRaids or {})[selectedRaid.unassignedIdx]
        if not snap then selectedRaid = nil; UI.raidPanel.detailHeader:SetText("|cff888888— Auswahl treffen —|r"); content:SetHeight(1); return end
        local diffStr = (snap.difficulty and snap.difficulty ~= "") and (" " .. ColorDiff(snap.difficulty)) or ""
        UI.raidPanel.detailHeader:SetText("|cffff9900Unassigned|r  " .. (snap.tier or "?") .. diffStr)
        local log = snap.lootLog or {}
        if #log == 0 then
            local e = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            e:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -8)
            e:SetText("|cff888888Kein Loot.|r")
            table.insert(detailRows, e)
            yOff = -20
        else
            for i = #log, 1, -1 do yOff = yOff - MakeDetailRow(content, log[i], yOff) end
        end
        content:SetHeight(math.max(1, -yOff))
        return
    end

    -- Raid innerhalb Session
    local session = nil
    for _, s in ipairs(db.raidContainers or {}) do
        if s.id == selectedRaid.sessionID then session = s; break end
    end
    if not session then selectedRaid = nil; UI.raidPanel.detailHeader:SetText("|cff888888— Auswahl treffen —|r"); content:SetHeight(1); return end

    local raidID = selectedRaid.raidID
    local meta   = session.raidMeta and session.raidMeta[raidID]
    local tierStr = (meta and meta.tier and meta.tier ~= "") and meta.tier or "Unknown"
    local diffStr = (meta and meta.difficulty and meta.difficulty ~= "") and (" " .. ColorDiff(meta.difficulty)) or ""
    local isActive = (db.activeContainerIdx ~= nil)
                  and (db.currentRaid.id == raidID)
                  and not (meta and meta.closedAt)
    UI.raidPanel.detailHeader:SetText(tierStr .. diffStr .. (isActive and " |cff00ff00aktiv|r" or ""))

    local log = {}
    for _, item in ipairs(session.lootLog or {}) do
        if item.raidID == raidID then table.insert(log, item) end
    end

    if #log == 0 then
        local e = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        e:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -8)
        e:SetText("|cff888888Kein Loot für diesen Raid.|r")
        table.insert(detailRows, e)
        yOff = -20
    else
        for i = #log, 1, -1 do yOff = yOff - MakeDetailRow(content, log[i], yOff) end
    end
    content:SetHeight(math.max(1, -yOff))
end

-- ============================================================
-- StaticPopup-Definitionen (einmalig beim Laden registrieren)
-- ============================================================

StaticPopupDialogs["RLT_RENAME_SESSION"] = {
    text         = "Session umbenennen:",
    button1      = "OK",
    button2      = "Abbrechen",
    hasEditBox   = true,
    maxLetters   = 48,
    OnShow       = function(self)
        self.EditBox:SetWidth(260)
        if selectedRaid and selectedRaid.ci then
            local session = GuildLootDB.raidContainers[selectedRaid.ci]
            self.EditBox:SetText(session and session.label or "")
            self.EditBox:HighlightText()
        end
    end,
    OnAccept     = function(self)
        local name = self.EditBox:GetText()
        if name ~= "" and selectedRaid and selectedRaid.ci then
            local session = GuildLootDB.raidContainers[selectedRaid.ci]
            if session then
                session.label = name
                GL.UI.RefreshRaidTab()
                GL.UI.RefreshSessionBar()
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local name = self:GetText()
        if name ~= "" and selectedRaid and selectedRaid.ci then
            local session = GuildLootDB.raidContainers[selectedRaid.ci]
            if session then session.label = name end
        end
        StaticPopup_Hide("RLT_RENAME_SESSION")
        GL.UI.RefreshRaidTab()
        GL.UI.RefreshSessionBar()
    end,
    timeout        = 0,
    whileDead      = false,
    hideOnEscape   = true,
    preferredIndex = 3,
    EditBoxWidth   = 260,
    wide           = 1,
}

-- ============================================================
-- Session-Picker: Unassigned Raid einer Session zuweisen
-- ============================================================

local sessionPickerFrame = nil

local function BuildSessionPickerFrame()
    local f = CreateFrame("Frame", "RLT_SessionPickerFrame", UIParent, "BackdropTemplate")
    f:SetSize(260, 40)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:EnableMouse(true)
    f:Hide()

    f:SetScript("OnHide", function() end)

    -- Klick außerhalb schließt
    f:SetScript("OnMouseDown", function(self, btn)
        if btn == "RightButton" then self:Hide() end
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
    title:SetText("|cffff9900Assign to Session:|r")
    f.title = title

    f.rows = {}
    return f
end

function UI.ShowSessionPickerForAssign(anchorBtn)
    if not sessionPickerFrame then
        sessionPickerFrame = BuildSessionPickerFrame()
    end
    local f = sessionPickerFrame

    -- Alte Rows entfernen
    for _, r in ipairs(f.rows) do r:Hide() end
    f.rows = {}

    local db       = GuildLootDB
    local sessions = db.raidContainers or {}
    local ROW_H    = 20
    local yOff     = -20

    for ci = #sessions, 1, -1 do
        local session = sessions[ci]
        local isActive = (db.activeContainerIdx == ci)
        local label = (session.label or "?")
        if isActive then label = "|cff00ff00" .. label .. "|r" end

        local row = CreateFrame("Button", nil, f)
        row:SetPoint("TOPLEFT",  f, "TOPLEFT",  6, yOff)
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, yOff)
        row:SetHeight(ROW_H)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.04)

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", row, "LEFT", 4, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(label)

        local capturedCI = ci
        row:SetScript("OnClick", function()
            f:Hide()
            -- gecheckte Indices absteigend sortieren (verhindert Index-Shift beim Entfernen)
            local indices = {}
            for k in pairs(checkedUnassigned) do table.insert(indices, k) end
            table.sort(indices, function(a, b) return a > b end)
            for _, uidx in ipairs(indices) do
                GL.AssignUnassignedToSession(uidx, capturedCI)
            end
            checkedUnassigned = {}
            selectedRaid = nil
            UI.RefreshRaidTab()
            UI.RefreshSessionBar()
        end)
        row:SetScript("OnEnter", function(self) bg:SetColorTexture(1, 0.8, 0, 0.15) end)
        row:SetScript("OnLeave", function(self) bg:SetColorTexture(1, 1, 1, 0.04) end)
        row:Show()
        table.insert(f.rows, row)
        yOff = yOff - ROW_H
    end

    local totalH = 24 + (#sessions * ROW_H) + 6
    f:SetHeight(totalH)
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", anchorBtn, "TOPLEFT", 0, 4)
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end

StaticPopupDialogs["RLT_NEW_SESSION"] = {
    text         = "Session-Name:",
    button1      = "Start",
    button2      = "Abbrechen",
    hasEditBox   = true,
    maxLetters   = 48,
    OnShow       = function(self)
        local now  = time()
        local d    = date("*t", now)
        -- EU: Raidwoche startet Mittwoch (wday=4); wday: 1=So,2=Mo,3=Di,4=Mi,5=Do,6=Fr,7=Sa
        local daysSinceWed = (d.wday - 4 + 7) % 7
        local sd = date("*t", now - daysSinceWed * 86400)
        local ed = date("*t", now + (6 - daysSinceWed) * 86400)
        self.EditBox:SetWidth(260)
        self.EditBox:SetText(string.format("RW %02d.%02d. - %02d.%02d.", sd.day, sd.month, ed.day, ed.month))
        self.EditBox:HighlightText()
    end,
    OnAccept     = function(self)
        local name = self.EditBox:GetText()
        GL.StartContainer(name ~= "" and name or nil)
        if GL.UI then
            GL.UI.RefreshRaidTab()
            GL.UI.RefreshSessionBar()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local name = self:GetText()
        GL.StartContainer(name ~= "" and name or nil)
        StaticPopup_Hide("RLT_NEW_SESSION")
        if GL.UI then
            GL.UI.RefreshRaidTab()
            GL.UI.RefreshSessionBar()
        end
    end,
    timeout        = 0,
    whileDead      = false,
    hideOnEscape   = true,
    preferredIndex = 3,
    EditBoxWidth   = 260,
    wide           = 1,
}
