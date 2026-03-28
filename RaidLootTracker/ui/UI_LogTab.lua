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
        title:SetText("JSON Export – press Mark All, then Ctrl+C")

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

    exportPopup.editBox:SetText(GL.ExportJSON(raidData))
    exportPopup.editBox:HighlightText()
    exportPopup:Show()
    exportPopup.editBox:SetFocus()
end

-- ============================================================
-- Log-Tab Refresh
-- ============================================================

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
        ts:SetWidth(100)
        ts:SetText(GL.FormatTimestamp(entry.timestamp))
        ts:SetTextColor(0.6, 0.6, 0.6)

        local playerLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        playerLbl:SetPoint("LEFT", ts, "RIGHT", 4, 0)
        playerLbl:SetWidth(120)
        playerLbl:SetText(GL.ShortName(entry.player or "?"))

        local diffLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        diffLbl:SetPoint("LEFT", playerLbl, "RIGHT", 4, 0)
        diffLbl:SetWidth(30)
        diffLbl:SetText(ColorDiff(entry.difficulty))

        MakeItemLinkBtn(row, diffLbl, 4, entry.link or entry.item, entry.item or "?")

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
