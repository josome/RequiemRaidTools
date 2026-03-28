-- GuildLoot – UI_LogTab.lua
-- Log-Tab: Build, JSON-Export, Refresh

local GL = GuildLoot
local UI = GL.UI

local TAB_LOG       = UI.TAB_LOG
local ColorDiff     = UI._H.ColorDiff
local MakeItemLinkBtn = UI._H.MakeItemLinkBtn

-- ============================================================
-- Tab-Widgets (file-local)
-- ============================================================

local logRows    = {}
local exportPopup

-- ============================================================
-- Log-Panel bauen
-- ============================================================

function UI.BuildLogPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    panel:Hide()

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

function UI.ShowExportPopup(raidData)
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
    local text = (fmt == "CSV") and GL.ExportCSV(raidData) or GL.ExportJSON(raidData)
    exportPopup.editBox:SetText(text)
    exportPopup.editBox:HighlightText()
    exportPopup:Show()
    exportPopup.editBox:SetFocus()
end

-- ============================================================
-- Log-Tab Refresh
-- ============================================================

local PRIO_LABEL = { [1]="|cffffcc00BIS|r", [2]="|cff88ff88Upg|r", [3]="|cff888888OS|r", [4]="|cff888888Fun|r" }
local CAT_LABEL  = { weapons="Weapon", trinket="Trinket", setItems="Set", other="Other" }

local function TrackColor(diff)
    if diff == "N" then return "|cff0070ddChampion|r"
    elseif diff == "H" then return "|cffa335eeHero|r"
    elseif diff == "M" then return "|cffff8000Mythic|r"
    else return diff or "" end
end

function UI.RefreshLogTab()
    if UI.activeTab ~= TAB_LOG then return end
    if not UI.logPanel or not UI.logPanel.content then return end

    for _, r in ipairs(logRows) do r:Hide() end
    logRows = {}

    local log     = GuildLootDB.currentRaid.lootLog
    local content = UI.logPanel.content
    local yOff    = 0

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

        local playerLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        playerLbl:SetPoint("LEFT", ts, "RIGHT", 4, 0)
        playerLbl:SetWidth(100)
        playerLbl:SetText(GL.ShortName(entry.player or "?"))

        local trackLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        trackLbl:SetPoint("LEFT", playerLbl, "RIGHT", 4, 0)
        trackLbl:SetWidth(68)
        trackLbl:SetText(TrackColor(entry.difficulty))

        local catLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        catLbl:SetPoint("LEFT", trackLbl, "RIGHT", 4, 0)
        catLbl:SetWidth(52)
        catLbl:SetText(CAT_LABEL[entry.category] or (entry.category or ""))
        catLbl:SetTextColor(0.7, 0.7, 0.7)

        local prioLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        prioLbl:SetPoint("LEFT", catLbl, "RIGHT", 4, 0)
        prioLbl:SetWidth(52)
        prioLbl:SetText(entry.winnerPrio and (PRIO_LABEL[entry.winnerPrio] or tostring(entry.winnerPrio)) or "|cff555555—|r")

        MakeItemLinkBtn(row, prioLbl, 4, entry.link or entry.item, entry.item or "?")

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
