-- GuildLoot – UI_RaidTab.lua
-- Raid-Tab: Build, Refresh, History-Detail

local GL = GuildLoot
local UI = GL.UI

local TAB_LOOT      = UI.TAB_LOOT
local TAB_RAID      = UI.TAB_RAID
local ColorDiff     = UI._H.ColorDiff
local MakeItemLinkBtn = UI._H.MakeItemLinkBtn

-- ============================================================
-- Tab-Widgets (file-local)
-- ============================================================

local verlaufRows       = {}
local verlaufDetailRows = {}
local selectedHistoryIndex = nil
local lastDetailIdx        = nil

-- ============================================================
-- Raid-Panel bauen
-- ============================================================

function UI.BuildRaidPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT",     parent, "TOPLEFT",     0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    panel:Hide()

    local LIST_W = 240

    -- Steuerleiste oben
    local controlStrip = CreateFrame("Frame", nil, panel)
    controlStrip:SetPoint("TOPLEFT",  panel, "TOPLEFT",  2, -2)
    controlStrip:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
    controlStrip:SetHeight(30)

    -- Tier-Eingabe
    local tierBox = CreateFrame("EditBox", "GuildLootTierBox", controlStrip, "InputBoxTemplate")
    tierBox:SetSize(LIST_W - 8, 20)
    tierBox:SetPoint("LEFT", controlStrip, "LEFT", 4, 0)
    tierBox:SetAutoFocus(false)
    tierBox:SetMaxLetters(48)
    tierBox:SetText(GuildLootDB.currentRaid.tier or "")
    tierBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    tierBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        GL.StartRaid(self:GetText() ~= "" and self:GetText() or nil)
        UI.RefreshSessionBar()
    end)
    tierBox:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == "" then
            local name, iType = GetInstanceInfo()
            if iType == "raid" or iType == "party" then
                self:SetText(name .. " (" .. date("%d.%m.%Y") .. ")")
                self:HighlightText()
            end
        end
    end)
    UI.tierBox = tierBox

    -- [Start Raid / Reload Roster]-Button
    local startRaidBtn = CreateFrame("Button", nil, controlStrip, "UIPanelButtonTemplate")
    startRaidBtn:SetSize(100, 22)
    startRaidBtn:SetPoint("LEFT", controlStrip, "LEFT", LIST_W + 4, 0)
    startRaidBtn:SetText("Start Raid")
    startRaidBtn:SetScript("OnClick", function()
        local raid = GuildLootDB.currentRaid
        if raid.active and raid.resumed then
            GL.LoadRaidRoster()
            UI.RefreshSessionBar()
            UI.Refresh()
        else
            local tier = tierBox:GetText()
            GL.StartRaid(tier ~= "" and tier or nil)
            UI.RefreshSessionBar()
            UI.Refresh()
            UI.UpdateEndResumeBtn()
        end
        UI.UpdateStartRaidBtn()
    end)
    UI.startRaidBtn = startRaidBtn

    -- [End Raid / Resume Raid]-Button
    local endResumeBtn = CreateFrame("Button", nil, controlStrip, "UIPanelButtonTemplate")
    endResumeBtn:SetSize(100, 22)
    endResumeBtn:SetPoint("LEFT", startRaidBtn, "RIGHT", 2, 0)
    endResumeBtn:SetText("End Raid")
    endResumeBtn:SetEnabled(false)
    endResumeBtn:SetScript("OnClick", function()
        if GuildLootDB.currentRaid and GuildLootDB.currentRaid.active then
            GL.CloseRaid()
            UI.RefreshSessionBar()
            UI.Refresh()
        elseif selectedHistoryIndex then
            GL.ResumeRaid(selectedHistoryIndex)
            selectedHistoryIndex = nil
            UI.ShowTab(TAB_LOOT)
        end
        UI.UpdateEndResumeBtn()
    end)
    UI.endResumeBtn = endResumeBtn

    -- [Reset]-Button
    local resetRaidBtn = CreateFrame("Button", nil, controlStrip, "UIPanelButtonTemplate")
    resetRaidBtn:SetSize(60, 22)
    resetRaidBtn:SetPoint("LEFT", endResumeBtn, "RIGHT", 2, 0)
    resetRaidBtn:SetText("Reset")
    local resetPending = false
    local resetTimer   = nil
    resetRaidBtn:SetScript("OnClick", function()
        if resetPending then
            if resetTimer then resetTimer:Cancel(); resetTimer = nil end
            resetPending = false
            resetRaidBtn:SetText("Reset")
            GL.ResetRaid()
        else
            resetPending = true
            resetRaidBtn:SetText("|cffff4444Sure?|r")
            resetTimer = C_Timer.NewTimer(3, function()
                resetPending = false
                resetTimer   = nil
                resetRaidBtn:SetText("Reset")
            end)
        end
    end)
    UI.resetRaidBtn = resetRaidBtn

    -- [Export JSON]-Button
    local exportRaidBtn = CreateFrame("Button", nil, controlStrip, "UIPanelButtonTemplate")
    exportRaidBtn:SetSize(90, 22)
    exportRaidBtn:SetPoint("LEFT", resetRaidBtn, "RIGHT", 2, 0)
    exportRaidBtn:SetText("Export JSON")
    exportRaidBtn:SetEnabled(false)
    exportRaidBtn:SetScript("OnClick", function()
        UI.ShowExportPopup()
    end)
    UI.exportRaidBtn = exportRaidBtn

    -- [Delete]-Button
    local deletePending = false
    local deleteTimer   = nil
    local deleteRaidBtn = CreateFrame("Button", nil, controlStrip, "UIPanelButtonTemplate")
    deleteRaidBtn:SetSize(70, 22)
    deleteRaidBtn:SetPoint("LEFT", exportRaidBtn, "RIGHT", 2, 0)
    deleteRaidBtn:SetText("Delete")
    deleteRaidBtn:SetEnabled(false)
    deleteRaidBtn:SetScript("OnClick", function()
        if not selectedHistoryIndex then return end
        if deletePending then
            if deleteTimer then deleteTimer:Cancel(); deleteTimer = nil end
            deletePending = false
            deleteRaidBtn:SetText("Delete")
            table.remove(GuildLootDB.raidHistory, selectedHistoryIndex)
            selectedHistoryIndex = nil
            UI.RefreshRaidTab()
            UI.RefreshRaidDetail(nil)
        else
            deletePending = true
            deleteRaidBtn:SetText("|cffff4444Sure?|r")
            deleteTimer = C_Timer.NewTimer(3, function()
                deletePending = false
                deleteTimer   = nil
                deleteRaidBtn:SetText("Delete")
            end)
        end
    end)
    UI.deleteRaidBtn = deleteRaidBtn

    -- Linke Spalte: Raid-Liste
    local listFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    listFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    listFrame:SetPoint("TOPLEFT",    controlStrip, "BOTTOMLEFT",  0, -2)
    listFrame:SetPoint("BOTTOMLEFT", panel,        "BOTTOMLEFT",  2,  2)
    listFrame:SetWidth(LIST_W)

    local listHeader = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    listHeader:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 6, -6)
    listHeader:SetText("|cffffcc00Past Raids:|r")

    local listScroll = CreateFrame("ScrollFrame", "GuildLootRaidListScroll", listFrame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT",     listHeader, "BOTTOMLEFT", 0,   -2)
    listScroll:SetPoint("BOTTOMRIGHT", listFrame,  "BOTTOMRIGHT", -22, 4)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(listScroll:GetWidth(), 1)
    listScroll:SetScrollChild(listContent)
    panel.listContent = listContent
    panel.listScroll  = listScroll

    -- Rechte Seite: Detail-Ansicht
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
    panel.detailHeader:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 6, -6)
    panel.detailHeader:SetText("|cff888888— Select a raid —|r")

    panel.detailIdLabel = detailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.detailIdLabel:SetPoint("TOPLEFT", panel.detailHeader, "BOTTOMLEFT", 0, -2)
    panel.detailIdLabel:SetText("")

    -- Arm-Zustand zurücksetzen wenn Auswahl wechselt
    panel.resetDeleteArm = function()
        if UI.deleteRaidBtn then UI.deleteRaidBtn:SetText("Delete") end
    end

    local detailScroll = CreateFrame("ScrollFrame", "GuildLootRaidDetailScroll", detailFrame, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT",     panel.detailIdLabel, "BOTTOMLEFT", 0,   -4)
    detailScroll:SetPoint("BOTTOMRIGHT", detailFrame,        "BOTTOMRIGHT", -22,  4)
    local detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetSize(detailScroll:GetWidth(), 1)
    detailScroll:SetScrollChild(detailContent)
    panel.detailContent = detailContent
    panel.detailScroll  = detailScroll

    return panel
end

-- ============================================================
-- Button State Updates
-- ============================================================

function UI.UpdateStartRaidBtn()
    if not UI.startRaidBtn then return end
    local raid = GuildLootDB.currentRaid
    if raid.active and raid.resumed then
        UI.startRaidBtn:SetText("Reload Roster")
        UI.startRaidBtn:SetEnabled(true)
    elseif raid.active then
        UI.startRaidBtn:SetText("Start Raid")
        UI.startRaidBtn:SetEnabled(false)
    else
        UI.startRaidBtn:SetText("Start Raid")
        UI.startRaidBtn:SetEnabled(true)
    end
end

function UI.UpdateEndResumeBtn()
    if not UI.endResumeBtn then return end
    local active = GuildLootDB.currentRaid and GuildLootDB.currentRaid.active
    if active then
        UI.endResumeBtn:SetText("End Raid")
        UI.endResumeBtn:SetEnabled(true)
    elseif selectedHistoryIndex then
        UI.endResumeBtn:SetText("Resume Raid")
        UI.endResumeBtn:SetEnabled(true)
    else
        UI.endResumeBtn:SetText("End Raid")
        UI.endResumeBtn:SetEnabled(false)
    end
    UI.UpdateStartRaidBtn()
end

-- ============================================================
-- Raid-Tab Refresh
-- ============================================================

function UI.RefreshRaidTab()
    if UI.activeTab ~= TAB_RAID then return end
    if not UI.raidPanel or not UI.raidPanel.listContent then return end

    local sw = UI.raidPanel.listScroll and UI.raidPanel.listScroll:GetWidth() or 0
    if sw > 10 then UI.raidPanel.listContent:SetWidth(sw) end

    for _, r in ipairs(verlaufRows) do r:Hide() end
    verlaufRows = {}

    local history = GuildLootDB.raidHistory or {}
    local content = UI.raidPanel.listContent
    local yOff    = 0
    local ROW_H   = 40

    -- Aktiver Raid ganz oben
    local raid = GuildLootDB.currentRaid
    if raid.active then
        local row = CreateFrame("Button", nil, content)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOff)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
        row:SetHeight(ROW_H)

        local activeBg = row:CreateTexture(nil, "BACKGROUND")
        activeBg:SetAllPoints()
        activeBg:SetColorTexture(0, 0.8, 0, 0.07)

        local selTex = row:CreateTexture(nil, "BACKGROUND")
        selTex:SetAllPoints()
        selTex:SetColorTexture(1, 0.8, 0, 0.12)
        selTex:SetShown(selectedHistoryIndex == 0)

        local tierLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tierLbl:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
        tierLbl:SetPoint("RIGHT",   row, "RIGHT",  -4, 0)
        tierLbl:SetJustifyH("LEFT")
        tierLbl:SetText("|cff00ff00▶ |r" .. ((raid.tier and raid.tier ~= "") and raid.tier or "|cff888888Unknown|r"))

        local infoLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        infoLbl:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 4)
        local diffStr     = raid.difficulty and ("[" .. raid.difficulty .. "] ") or ""
        local playerCount = raid.participants and #raid.participants or 0
        local lootCount   = raid.lootLog and #raid.lootLog or 0
        infoLbl:SetText("|cff00ff00Active|r  |cff888888" .. diffStr .. playerCount .. " players, " .. lootCount .. " loot|r")

        row:SetScript("OnClick", function()
            selectedHistoryIndex = 0
            UI.RefreshRaidTab()
            UI.RefreshRaidDetail(0)
        end)
        row:SetScript("OnEnter", function(self) self:SetAlpha(0.8) end)
        row:SetScript("OnLeave", function(self) self:SetAlpha(1)   end)

        row:Show()
        table.insert(verlaufRows, row)
        yOff = yOff - ROW_H - 1
    end

    -- Neueste zuerst
    for i = #history, 1, -1 do
        local snap = history[i]
        local idx  = i

        local row = CreateFrame("Button", nil, content)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOff)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
        row:SetHeight(ROW_H)

        if (#verlaufRows % 2 == 0) then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.04)
        end

        local selTex = row:CreateTexture(nil, "BACKGROUND")
        selTex:SetAllPoints()
        selTex:SetColorTexture(1, 0.8, 0, 0.12)
        selTex:SetShown(selectedHistoryIndex == idx)

        local tierLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tierLbl:SetPoint("TOPLEFT", row, "TOPLEFT",  4, -4)
        tierLbl:SetPoint("RIGHT",   row, "RIGHT",   -4, 0)
        tierLbl:SetJustifyH("LEFT")
        tierLbl:SetText((snap.tier and snap.tier ~= "") and snap.tier or "|cff888888Unknown|r")

        local infoLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        infoLbl:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 4)
        local diffStr     = snap.difficulty and ("[" .. snap.difficulty .. "] ") or ""
        local playerCount = snap.participants and #snap.participants or 0
        local lootCount   = snap.lootLog and #snap.lootLog or 0
        local dateStr     = snap.closedAt and date("%d.%m.%Y %H:%M", snap.closedAt) or "?"
        infoLbl:SetText("|cff888888" .. diffStr .. dateStr
                        .. "  " .. playerCount .. " players, " .. lootCount .. " loot|r")

        row:SetScript("OnClick", function()
            selectedHistoryIndex = idx
            UI.RefreshRaidTab()
            UI.RefreshRaidDetail(idx)
        end)
        row:SetScript("OnEnter", function(self) self:SetAlpha(0.8) end)
        row:SetScript("OnLeave", function(self) self:SetAlpha(1)   end)

        row:Show()
        table.insert(verlaufRows, row)
        yOff = yOff - ROW_H - 1
    end

    if #history == 0 then
        local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        empty:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -8)
        empty:SetText("|cff888888No completed raids saved.|r")
        table.insert(verlaufRows, empty)
        yOff = -20
    end

    content:SetHeight(math.max(1, -yOff))

    if selectedHistoryIndex then
        UI.RefreshRaidDetail(selectedHistoryIndex)
    end
end

-- ============================================================
-- Raid-Detail Refresh
-- ============================================================

function UI.RefreshRaidDetail(idx)
    if not UI.raidPanel or not UI.raidPanel.detailContent then return end

    local sw = UI.raidPanel.detailScroll and UI.raidPanel.detailScroll:GetWidth() or 0
    if sw > 10 then UI.raidPanel.detailContent:SetWidth(sw) end

    for _, r in ipairs(verlaufDetailRows) do r:Hide() end
    verlaufDetailRows = {}

    -- Sonderfall: aktiver Raid (idx == 0)
    if idx == 0 then
        local raid = GuildLootDB.currentRaid
        if not raid.active then
            selectedHistoryIndex = nil
            idx = nil
        else
            if idx ~= lastDetailIdx and UI.raidPanel.resetDeleteArm then
                UI.raidPanel.resetDeleteArm()
            end
            lastDetailIdx = 0
            if UI.deleteRaidBtn then UI.deleteRaidBtn:SetEnabled(false) end
            if UI.exportRaidBtn then UI.exportRaidBtn:SetEnabled(true) end
            UI.UpdateEndResumeBtn()
            local diffStr = raid.difficulty and (" [" .. raid.difficulty .. "]") or ""
            UI.raidPanel.detailHeader:SetText("|cff00ff00● Active|r  " .. (raid.tier or "?") .. diffStr)
            if UI.raidPanel.detailIdLabel then
                local pendingCount = #(raid.pendingLoot or {})
                local pendingStr = pendingCount > 0 and ("  |cffff9900" .. pendingCount .. " pending|r") or ""
                UI.raidPanel.detailIdLabel:SetText("|cff555555ID: " .. (raid.id and raid.id ~= "" and raid.id or "—") .. "|r" .. pendingStr)
            end
            local log     = raid.lootLog or {}
            local content = UI.raidPanel.detailContent
            local yOff    = 0
            for i = #log, 1, -1 do
                local entry = log[i]
                local row = CreateFrame("Frame", nil, content)
                row:SetSize(content:GetWidth() - 20, 20)
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
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
                table.insert(verlaufDetailRows, row)
                yOff = yOff - 22
            end
            UI.raidPanel.detailContent:SetHeight(math.max(1, -yOff))
            return
        end
    end

    local history = GuildLootDB.raidHistory or {}
    local snap    = history[idx]
    if not snap then
        UI.raidPanel.detailHeader:SetText("|cff888888— Select a raid —|r")
        if UI.raidPanel.detailIdLabel then UI.raidPanel.detailIdLabel:SetText("") end
        UI.raidPanel.detailContent:SetHeight(1)
        if UI.deleteRaidBtn then UI.deleteRaidBtn:SetEnabled(false) end
        if UI.exportRaidBtn then UI.exportRaidBtn:SetEnabled(false) end
        UI.UpdateEndResumeBtn()
        if UI.raidPanel.resetDeleteArm then UI.raidPanel.resetDeleteArm() end
        lastDetailIdx = nil
        return
    end

    if idx ~= lastDetailIdx and UI.raidPanel.resetDeleteArm then
        UI.raidPanel.resetDeleteArm()
    end
    lastDetailIdx = idx
    if UI.deleteRaidBtn then UI.deleteRaidBtn:SetEnabled(true) end
    if UI.exportRaidBtn then UI.exportRaidBtn:SetEnabled(true) end
    UI.UpdateEndResumeBtn()

    local diffStr = snap.difficulty and (" [" .. snap.difficulty .. "]") or ""
    local dateStr = snap.closedAt and date("%d.%m.%Y", snap.closedAt) or "?"
    UI.raidPanel.detailHeader:SetText((snap.tier or "?") .. diffStr .. "  |cff888888" .. dateStr .. "|r")
    if UI.raidPanel.detailIdLabel then
        local pendingCount = #(snap.pendingLoot or {})
        local pendingStr = pendingCount > 0 and ("  |cffff9900" .. pendingCount .. " pending|r") or ""
        UI.raidPanel.detailIdLabel:SetText("|cff555555ID: " .. (snap.id and snap.id ~= "" and snap.id or "—") .. "|r" .. pendingStr)
    end

    local log     = snap.lootLog or {}
    local content = UI.raidPanel.detailContent
    local yOff    = 0

    for i = #log, 1, -1 do
        local entry = log[i]
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(content:GetWidth() - 20, 20)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)

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
        table.insert(verlaufDetailRows, row)
        yOff = yOff - 22
    end

    if #log == 0 then
        local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        empty:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -8)
        empty:SetText("|cff888888No loot assigned in this raid.|r")
        table.insert(verlaufDetailRows, empty)
        yOff = -20
    end

    content:SetHeight(math.max(1, -yOff))
end
