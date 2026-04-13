-- GuildLoot – UI_LogTab.lua
-- Log-Tab: Build, JSON-Export, Refresh

local GL = GuildLoot
local UI = GL.UI

local TAB_LOG       = UI.TAB_LOG
local ColorDiff     = UI._H.ColorDiff

-- ============================================================
-- Tab-Widgets (file-local)
-- ============================================================

local logRows    = {}
local exportPopup
local playerPickerPanel

local function ShowPlayerPicker(entry)
    local participants = GuildLootDB.currentRaid and GuildLootDB.currentRaid.participants or {}
    local names = {}
    for _, name in ipairs(participants) do table.insert(names, name) end  -- Array, nicht Hash
    table.sort(names)
    if #names == 0 then return end

    local mf = GuildLootMainFrame
    if not mf then return end

    if not playerPickerPanel then
        playerPickerPanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        playerPickerPanel:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left=4, right=4, top=4, bottom=4 },
        })
        playerPickerPanel:SetFrameStrata("DIALOG")
        playerPickerPanel:SetClampedToScreen(true)
        playerPickerPanel:SetWidth(200)
        playerPickerPanel:SetPoint("TOPRIGHT",    mf, "TOPLEFT",    -4, 0)
        playerPickerPanel:SetPoint("BOTTOMRIGHT", mf, "BOTTOMLEFT", -4, 0)

        -- X-Button zum Schließen ohne Auswahl
        local closeBtn = CreateFrame("Button", nil, playerPickerPanel, "UIPanelCloseButton")
        closeBtn:SetSize(18, 18)
        closeBtn:SetPoint("TOPRIGHT", playerPickerPanel, "TOPRIGHT", 2, 2)
        closeBtn:SetScript("OnClick", function() playerPickerPanel:Hide() end)

        local scroll = CreateFrame("ScrollFrame", nil, playerPickerPanel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",     playerPickerPanel, "TOPLEFT",     6,  -20)
        scroll:SetPoint("BOTTOMRIGHT", playerPickerPanel, "BOTTOMRIGHT", -26, 6)
        local inner = CreateFrame("Frame", nil, scroll)
        inner:SetWidth(scroll:GetWidth())
        scroll:SetScrollChild(inner)
        playerPickerPanel.inner = inner
    end

    local inner = playerPickerPanel.inner
    for _, b in ipairs(inner.buttons or {}) do b:Hide() end
    inner.buttons = {}

    local ROW_H = 22
    local yOff  = 0
    for _, name in ipairs(names) do
        local btn = CreateFrame("Button", nil, inner)
        btn:SetPoint("TOPLEFT",  inner, "TOPLEFT",  4, yOff)
        btn:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -4, yOff)
        btn:SetHeight(ROW_H)
        btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetAllPoints()
        lbl:SetJustifyH("LEFT")
        lbl:SetText(name)   -- voller Name inkl. Realm
        local capName = name
        btn:SetScript("OnClick", function()
            entry.player = capName
            playerPickerPanel:Hide()
            GL.UI.RefreshLogTab()
        end)
        table.insert(inner.buttons, btn)
        yOff = yOff - ROW_H
    end
    inner:SetHeight(math.max(1, -yOff))
    playerPickerPanel:Show()
end

-- ============================================================
-- Log-Panel bauen
-- ============================================================

function UI.BuildLogPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    panel:Hide()
    panel:SetScript("OnHide", function()
        if playerPickerPanel then playerPickerPanel:Hide() end
    end)

    local scroll = CreateFrame("ScrollFrame", "GuildLootLogScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     panel, "TOPLEFT",  4,  -4)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(scroll:GetWidth(), 1)
    scroll:SetScrollChild(content)
    panel.content = content

    return panel
end

-- ============================================================
-- JSON-Export Popup
-- ============================================================

function UI.ShowExportPopup(raidData, textOverride)
    if not exportPopup then
        exportPopup = CreateFrame("Frame", "RaidLootExportPopup", UIParent, "BasicFrameTemplateWithInset")
        exportPopup:SetSize(600, 400)
        exportPopup:SetPoint("CENTER")
        exportPopup:SetFrameStrata("DIALOG")
        exportPopup:SetMovable(true)
        exportPopup:EnableMouse(true)
        exportPopup:RegisterForDrag("LeftButton")
        exportPopup:SetScript("OnDragStart", exportPopup.StartMoving)
        exportPopup:SetScript("OnDragStop",  exportPopup.StopMovingOrSizing)

        local title = exportPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", exportPopup, "TOP", 0, -8)
        exportPopup.titleText = title

        local sf = CreateFrame("ScrollFrame", "RaidLootExportScroll", exportPopup, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT",     exportPopup, "TOPLEFT",    10, -30)
        sf:SetPoint("BOTTOMRIGHT", exportPopup, "BOTTOMRIGHT", -30, 36)

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(GameFontHighlightSmall)
        eb:SetWidth(sf:GetWidth())
        eb:SetScript("OnEscapePressed", function() exportPopup:Hide() end)
        sf:SetScrollChild(eb)
        exportPopup.editBox = eb

        local copyBtn = CreateFrame("Button", nil, exportPopup, "UIPanelButtonTemplate")
        copyBtn:SetSize(100, 22)
        copyBtn:SetPoint("BOTTOM", exportPopup, "BOTTOM", 0, 10)
        copyBtn:SetText("Mark All")
        copyBtn:SetScript("OnClick", function()
            eb:SetFocus()
            eb:HighlightText()
        end)
    end

    local fmt = GuildLootDB.settings.exportFormat or "JSON"
    exportPopup.titleText:SetText(fmt .. " Export – press Mark All, then Ctrl+C")
    local text = textOverride
                 or ((fmt == "CSV") and GL.ExportCSV(raidData) or GL.ExportJSON(raidData))
    exportPopup.editBox:SetText(text)
    exportPopup.editBox:HighlightText()
    exportPopup:Show()
    exportPopup.editBox:SetFocus()
end

-- ============================================================
-- Log-Tab Refresh
-- ============================================================

local PRIO_LABEL = { [1]="|cffffcc00BIS|r", [2]="|cff6699ffOS|r", [4]="|cff888888Tmog|r" }
local CAT_LABEL  = { weapons="Weapon", trinket="Trinket", setItems="Set", other="Other" }

local function TrackColor(diff)
    if diff == "N" then return "|cff0070ddN|r"
    elseif diff == "H" then return "|cffa335eeH|r"
    elseif diff == "M" then return "|cffff8000M|r"
    else return diff or "" end
end

function UI.RefreshLogTab()
    if UI.activeTab ~= TAB_LOG then return end
    if not UI.logPanel or not UI.logPanel.content then return end

    for _, r in ipairs(logRows) do r:Hide() end
    logRows = {}

    local db  = GuildLootDB
    local idx = db.activeContainerIdx
    local log = (idx and db.raidContainers and db.raidContainers[idx])
                and db.raidContainers[idx].lootLog or {}
    local content = UI.logPanel.content
    local yOff    = 0
    local isML    = GL.IsMasterLooter()

    -- Neueste zuerst
    for i = #log, 1, -1 do
        local entry = log[i]
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(content:GetWidth() - 30, 20)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)

        local ts = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ts:SetPoint("LEFT", row, "LEFT", 4, 0)
        ts:SetWidth(88)
        ts:SetText(GL.FormatTimestamp(entry.timestamp))
        ts:SetTextColor(0.6, 0.6, 0.6)

        -- << Button links neben dem Namen (nur ML)
        local editBtn
        if isML then
            editBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            editBtn:SetSize(22, 20)
            editBtn:SetPoint("LEFT", ts, "RIGHT", 4, 0)
            editBtn:SetText("<<")
            editBtn:SetScript("OnClick", function()
                if playerPickerPanel and playerPickerPanel:IsShown() then
                    playerPickerPanel:Hide()
                else
                    ShowPlayerPicker(entry)
                end
            end)
            editBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Spieler umverteilen", 1, 1, 1)
                GameTooltip:Show()
            end)
            editBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        local playerLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        playerLbl:SetPoint("LEFT", editBtn or ts, "RIGHT", 4, 0)
        playerLbl:SetWidth(100)
        playerLbl:SetText(GL.ShortName(entry.player or "?"))

        local trackBtn = CreateFrame("Button", nil, row)
        trackBtn:SetPoint("LEFT", playerLbl, "RIGHT", 4, 0)
        trackBtn:SetSize(24, 20)
        local trackLbl = trackBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        trackLbl:SetAllPoints()
        trackLbl:SetJustifyH("LEFT")
        trackLbl:SetText(TrackColor(entry.difficulty))
        if isML then
            local CYCLE = { N="H", H="M", M="N" }
            trackBtn:SetScript("OnClick", function()
                entry.difficulty = CYCLE[entry.difficulty] or "N"
                trackLbl:SetText(TrackColor(entry.difficulty))
            end)
            trackBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Difficulty ändern (N→H→M)", 1, 1, 1)
                GameTooltip:Show()
            end)
            trackBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        local catLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        catLbl:SetPoint("LEFT", trackLbl, "RIGHT", 4, 0)
        catLbl:SetWidth(52)
        catLbl:SetText(CAT_LABEL[entry.category] or (entry.category or ""))
        catLbl:SetTextColor(0.7, 0.7, 0.7)

        local prioLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        prioLbl:SetPoint("LEFT", catLbl, "RIGHT", 4, 0)
        prioLbl:SetWidth(52)
        prioLbl:SetText(entry.winnerPrio and ("|cffaaaaaa" .. entry.winnerPrio .. "|r " .. (PRIO_LABEL[entry.winnerPrio] or tostring(entry.winnerPrio))) or "|cff555555—|r")

        local bossLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bossLbl:SetPoint("LEFT", prioLbl, "RIGHT", 4, 0)
        bossLbl:SetWidth(110)
        bossLbl:SetText(entry.boss and ("|cff888888" .. entry.boss .. "|r") or "|cff555555—|r")

        -- Item-Link
        local linkBtn = CreateFrame("Button", nil, row)
        linkBtn:SetPoint("TOPLEFT", bossLbl, "TOPRIGHT", 4, 0)
        linkBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        linkBtn:SetHeight(18)
        local linkFs = linkBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        linkFs:SetAllPoints()
        linkFs:SetJustifyH("LEFT")
        linkFs:SetJustifyV("TOP")
        local itemLink  = entry.link or entry.item
        local itemLabel = entry.item or "?"
        linkFs:SetText(itemLabel)
        if itemLink and itemLink ~= "" then
            linkBtn:EnableMouse(true)
            linkBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(itemLink)
                GameTooltip:Show()
            end)
            linkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            linkBtn:SetScript("OnClick", function()
                if IsModifiedClick("CHATLINK") then
                    ChatEdit_InsertLink(itemLink)
                end
            end)
        end

        row:Show()
        table.insert(logRows, row)
        yOff = yOff - 22
    end

    if #log == 0 then
        local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        empty:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
        empty:SetText("|cff888888No loot assigned this session.|r")
        table.insert(logRows, empty)
    end

    content:SetHeight(math.max(1, -yOff))
end
