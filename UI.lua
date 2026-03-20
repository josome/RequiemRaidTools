-- GuildLoot – UI.lua
-- Hauptfenster: Tabs Loot / Spieler / Log + Minimize + ML-Checkbox

GuildLoot = GuildLoot or {}
local GL = GuildLoot
GL.UI = GL.UI or {}
local UI = GL.UI

-- ============================================================
-- Konstanten
-- ============================================================

local FRAME_W, FRAME_H = 720, 560
local SIDEBAR_W = 210
local TAB_LOOT, TAB_SPIELER, TAB_LOG, TAB_VERLAUF = 1, 2, 3, 4
local DIFF_COLORS = { N = "|cff1eff00", H = "|cff0070dd", M = "|cffff8000" }

-- ============================================================
-- Hilfsfunktionen
-- ============================================================

local function ColorDiff(diff)
    if not diff then return "|cff888888—|r" end
    return (DIFF_COLORS[diff] or "") .. diff .. "|r"
end

local function MakeButton(parent, text, w, h, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w, h)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function MakeLabel(parent, text, fs, r, g, b)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:SetText(text)
    if fs then f:SetFont(f:GetFont(), fs) end
    if r then f:SetTextColor(r, g, b) end
    return f
end

-- Item-Link als Button mit Tooltip beim Hover
-- leftAnchorFrame: Frame an das LEFT andocken; link: Hyperlink-String; displayText: angezeigter Text
local function MakeItemLinkBtn(parent, leftAnchorFrame, xOff, link, displayText)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("LEFT",  leftAnchorFrame, "RIGHT", xOff, 0)
    btn:SetPoint("RIGHT", parent,          "RIGHT", -4,   0)
    btn:SetHeight(18)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetAllPoints()
    fs:SetJustifyH("LEFT")
    fs:SetText(displayText or "?")
    if link and link ~= "" then
        btn:EnableMouse(true)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return btn
end

-- ============================================================
-- Haupt-Frame
-- ============================================================

local mainFrame
local contentFrame
local dockTab          -- schmaler Streifen am linken Rand (angedockter Zustand)
local activeTab = TAB_LOOT

-- Panels
local lootPanel, spielerPanel, logPanel, verlaufPanel
local verlaufRows, verlaufDetailRows = {}, {}
local selectedHistoryIndex = nil
-- Tabs
local tabButtons = {}

-- Loot-Tab Widgets
local pendingButtons = {}
local activeItemLabel
local activeItemCategoryLabel
local candidateRows = {}
local rollResultRows = {}
local sessionLootRows = {}
local function sessionHidden()  return GuildLootDB.currentRaid.sessionHidden  end
local function sessionChecked() return GuildLootDB.currentRaid.sessionChecked end
local countdownLabel
local resetItemBtn
local startRollBtn
local difficultyPopup

-- Spieler-Tab Widgets
local playerRows = {}

-- Log-Tab Widgets
local logRows = {}

-- ============================================================
-- Init
-- ============================================================

function UI.Init()
    UI.BuildMainFrame()
    UI.BuildDockTab()
    -- Immer minimiert/angedockt starten
    GuildLootDB.settings.minimized = true
    UI.LoadPosition()
    UI.RefreshSessionBar()
    UI.Refresh()
end

-- ============================================================
-- Hauptfenster bauen
-- ============================================================

function UI.BuildMainFrame()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", "GuildLootMainFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(FRAME_W, FRAME_H)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI.SavePosition()
    end)
    mainFrame:SetToplevel(true)

    -- Titelzeile
    mainFrame.TitleText:SetText("GuildLoot v1.0")

    -- ML-Checkbox (oben rechts in Titelleiste)
    local mlCheck = CreateFrame("CheckButton", "GuildLootMLCheck", mainFrame, "UICheckButtonTemplate")
    mlCheck:SetSize(20, 20)
    mlCheck:SetPoint("RIGHT", mainFrame.CloseButton, "LEFT", -4, 0)
    mlCheck.text:SetText("ML")
    mlCheck.text:SetTextColor(1, 0.8, 0)
    mlCheck.text:ClearAllPoints()
    mlCheck.text:SetPoint("RIGHT", mlCheck, "LEFT", -2, 0)
    mlCheck.text:SetJustifyH("RIGHT")
    mlCheck:SetChecked(GuildLootDB.settings.isMasterLooter)
    mlCheck:SetScript("OnClick", function(self)
        GuildLootDB.settings.isMasterLooter = self:GetChecked()
        GL.Print("Master Looter: " .. (GuildLootDB.settings.isMasterLooter and "|cff00ff00AN|r" or "|cffff4444AUS|r"))
    end)
    UI.mlCheck = mlCheck

    -- Andocken-Button (Pfeil links)
    local minBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    minBtn:SetSize(32, 18)
    minBtn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -5)
    minBtn:SetText("«")
    minBtn:SetScript("OnClick", UI.ToggleMinimize)
    minBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Andocken", 1, 1, 1)
        GameTooltip:AddLine("Fenster als Tab an den linken Rand andocken", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    minBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.minBtn = minBtn

    -- ── Session-Leiste (fest, immer sichtbar, unterhalb des Contents) ────────
    local sessionBar = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    sessionBar:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    sessionBar:SetPoint("BOTTOMLEFT",  mainFrame, "BOTTOMLEFT",  4,  4)
    sessionBar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 4)
    sessionBar:SetHeight(34)
    UI.sessionBar = sessionBar

    -- Status-Label (links)
    local statusLbl = sessionBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLbl:SetPoint("LEFT", sessionBar, "LEFT", 8, 0)
    statusLbl:SetWidth(200)
    statusLbl:SetJustifyH("LEFT")
    statusLbl:SetText("|cff888888Kein Raid aktiv|r")
    UI.sessionStatusLbl = statusLbl

    -- Tier-Eingabe
    local tierBox = CreateFrame("EditBox", "GuildLootTierBox", sessionBar, "InputBoxTemplate")
    tierBox:SetSize(140, 20)
    tierBox:SetPoint("LEFT", statusLbl, "RIGHT", 6, 0)
    tierBox:SetAutoFocus(false)
    tierBox:SetMaxLetters(48)
    tierBox:SetText(GuildLootDB.currentRaid.tier or "")
    tierBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    tierBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        GL.StartRaid(self:GetText() ~= "" and self:GetText() or nil)
        UI.RefreshSessionBar()
    end)
    -- Auto-befüllen wenn Feld leer und Fokus erhalten
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

    -- [Raid starten]-Button
    local startRaidBtn = CreateFrame("Button", nil, sessionBar, "UIPanelButtonTemplate")
    startRaidBtn:SetSize(90, 22)
    startRaidBtn:SetPoint("LEFT", tierBox, "RIGHT", 4, 0)
    startRaidBtn:SetText("Raid starten")
    startRaidBtn:SetScript("OnClick", function()
        local tier = tierBox:GetText()
        GL.StartRaid(tier ~= "" and tier or nil)
        UI.RefreshSessionBar()
        UI.Refresh()
    end)
    UI.startRaidBtn = startRaidBtn

    -- [Raid beenden]-Button
    local closeRaidBtn = CreateFrame("Button", nil, sessionBar, "UIPanelButtonTemplate")
    closeRaidBtn:SetSize(90, 22)
    closeRaidBtn:SetPoint("LEFT", startRaidBtn, "RIGHT", 2, 0)
    closeRaidBtn:SetText("Raid beenden")
    closeRaidBtn:SetScript("OnClick", function()
        GL.CloseRaid()
        UI.RefreshSessionBar()
    end)
    UI.closeRaidBtn = closeRaidBtn

    -- [Reset]-Button
    local resetRaidBtn = CreateFrame("Button", nil, sessionBar, "UIPanelButtonTemplate")
    resetRaidBtn:SetSize(60, 22)
    resetRaidBtn:SetPoint("LEFT", closeRaidBtn, "RIGHT", 2, 0)
    resetRaidBtn:SetText("Reset")
    resetRaidBtn:SetScript("OnClick", function()
        if UI._resetConfirmPending then
            UI._resetConfirmPending = false
            GL.ResetRaid()
            UI.RefreshSessionBar()
            UI.Refresh()
        else
            UI._resetConfirmPending = true
            GL.Print("Nochmal [Reset] drücken zum Bestätigen.")
            C_Timer.After(8, function() UI._resetConfirmPending = false end)
        end
    end)
    UI.resetRaidBtn = resetRaidBtn

    -- Content-Frame (unterhalb der Tabs, oberhalb der Session-Leiste)
    contentFrame = CreateFrame("Frame", nil, mainFrame)
    contentFrame:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",     4, -52)
    contentFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 42)

    -- Tab-Buttons oben im Content-Bereich
    local tabNames = { "Loot", "Spieler", "Log", "Verlauf" }
    for i, name in ipairs(tabNames) do
        local tb = CreateFrame("Button", "GuildLootTab" .. i, mainFrame, "UIPanelButtonTemplate")
        tb:SetSize(80, 22)
        tb:SetText(name)
        tb:SetID(i)
        if i == 1 then
            tb:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 8, -26)
        else
            tb:SetPoint("LEFT", tabButtons[i - 1], "RIGHT", 2, 0)
        end
        tb:SetScript("OnClick", function(self)
            UI.ShowTab(self:GetID())
        end)
        tabButtons[i] = tb
    end

    -- Panels (füllen den gesamten Content-Bereich)
    lootPanel    = UI.BuildLootPanel(contentFrame)
    spielerPanel = UI.BuildSpielerPanel(contentFrame)
    logPanel     = UI.BuildLogPanel(contentFrame)
    verlaufPanel = UI.BuildVerlaufPanel(contentFrame)

    UI.ShowTab(TAB_LOOT)
end

-- ============================================================
-- Dock-Tab (linker Bildschirmrand, angedockter Zustand)
-- ============================================================


function UI.BuildDockTab()
    if dockTab then return end

    dockTab = CreateFrame("Button", "GuildLootDockTab", UIParent, "BackdropTemplate")
    dockTab:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    dockTab:SetSize(22, 110)
    dockTab:SetPoint("LEFT", UIParent, "LEFT", 0, 0)
    dockTab:SetFrameStrata("HIGH")
    dockTab:SetMovable(false)
    dockTab:SetScript("OnClick", UI.Undock)
    dockTab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("GuildLoot", 1, 0.8, 0)
        local pending = GL.Loot and GL.Loot.GetPendingLoot and #GL.Loot.GetPendingLoot() or 0
        if pending > 0 then
            GameTooltip:AddLine(pending .. " Item(s) warten", 1, 1, 0)
        end
        GameTooltip:AddLine("Klicken zum Öffnen", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    dockTab:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- "GL"-Label vertikal (oben)
    local title = dockTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", dockTab, "TOP", 0, -8)
    title:SetText("|cff00ccffG|r")

    local title2 = dockTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title2:SetPoint("TOP", title, "BOTTOM", 0, -2)
    title2:SetText("|cff00ccffL|r")

    -- Loot-Zähler Badge (Mitte)
    UI.dockLootCount = dockTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.dockLootCount:SetPoint("CENTER", dockTab, "CENTER", 0, 0)
    UI.dockLootCount:SetText("")

    -- Raid-Status Punkt (unten)
    UI.dockRaidDot = dockTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.dockRaidDot:SetPoint("BOTTOM", dockTab, "BOTTOM", 0, 8)
    UI.dockRaidDot:SetText("")

    dockTab:Hide()
    UI.dockTab = dockTab
end

function UI.RefreshDockTab()
    if not dockTab then return end
    local pending = (GL.Loot and GL.Loot.GetPendingLoot) and #GL.Loot.GetPendingLoot() or 0
    if pending > 0 then
        UI.dockLootCount:SetText("|cffffcc00" .. pending .. "|r\n|cff888888Item(s)|r")
    else
        UI.dockLootCount:SetText("")
    end
    if GuildLootDB.currentRaid.active then
        UI.dockRaidDot:SetText("|cff00ff00●|r")
    else
        UI.dockRaidDot:SetText("|cff888888●|r")
    end
end

-- Andocken: Hauptfenster verstecken, Dock-Tab zeigen
function UI.Dock()
    if not mainFrame then return end
    UI.SavePosition()
    GuildLootDB.settings.minimized = true
    mainFrame:Hide()
    UI.BuildDockTab()
    UI.RefreshDockTab()
    dockTab:Show()
end

-- Abdocken: Dock-Tab verstecken, Hauptfenster wiederherstellen
function UI.Undock()
    if dockTab then dockTab:Hide() end
    GuildLootDB.settings.minimized = false
    if not mainFrame then UI.BuildMainFrame() end
    UI.LoadPosition()
    mainFrame:Show()
    UI.Refresh()
end

function UI.ToggleMinimize()
    if GuildLootDB.settings.minimized then
        UI.Undock()
    else
        UI.Dock()
    end
end

-- ============================================================
-- Tabs
-- ============================================================

function UI.ShowTab(tabID)
    activeTab = tabID
    lootPanel:Hide()
    spielerPanel:Hide()
    logPanel:Hide()
    if verlaufPanel then verlaufPanel:Hide() end

    for i, tb in ipairs(tabButtons) do
        if i == tabID then
            tb:SetAlpha(1.0)
            tb:LockHighlight()
        else
            tb:SetAlpha(0.55)
            tb:UnlockHighlight()
        end
    end

    if tabID == TAB_LOOT then
        lootPanel:Show()
        UI.RefreshLootTab()
    elseif tabID == TAB_SPIELER then
        spielerPanel:Show()
        UI.RefreshSpielerTab()
    elseif tabID == TAB_LOG then
        logPanel:Show()
        UI.RefreshLogTab()
    elseif tabID == TAB_VERLAUF then
        if verlaufPanel then verlaufPanel:Show() end
        UI.RefreshVerlaufTab()
    end
end

-- ============================================================
-- Loot-Panel
-- ============================================================

function UI.BuildLootPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    panel:Hide()

    -- ── RECHTE SIDEBAR: Pending Loot ──────────────────────────
    local sidebar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    sidebar:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=8,
        insets={left=2,right=2,top=2,bottom=2} })
    sidebar:SetPoint("TOPRIGHT",    panel, "TOPRIGHT",    -4,  -2)
    sidebar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4,   4)
    sidebar:SetWidth(SIDEBAR_W)

    local pendingLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pendingLabel:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 6, -6)
    pendingLabel:SetText("|cffffcc00Pending Loot:|r")

    local pendingScroll = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    pendingScroll:SetPoint("TOPLEFT",     pendingLabel, "BOTTOMLEFT", 0, -2)
    pendingScroll:SetPoint("BOTTOMRIGHT", sidebar,      "BOTTOMRIGHT", -22, 4)
    local pendingContent = CreateFrame("Frame", nil, pendingScroll)
    pendingContent:SetSize(pendingScroll:GetWidth(), 1)
    pendingScroll:SetScrollChild(pendingContent)
    panel.pendingFrame   = sidebar       -- für Höhenanpassung (nicht mehr nötig)
    panel.pendingContent = pendingContent
    panel.pendingScroll  = pendingScroll

    -- ── HAUPT-BEREICH: alles vertikal links ───────────────────
    local main = CreateFrame("Frame", nil, panel)
    main:SetPoint("TOPLEFT",     panel,   "TOPLEFT",   4,  -2)
    main:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMLEFT", -6,  4)

    -- Timer-Dropdowns
    local function MakeTimerDD(par, label, key, opts, anchor, xOff)
        local lbl = par:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", anchor, "RIGHT", xOff, 0)
        lbl:SetText(label)
        local dd = CreateFrame("Frame", "GuildLootDD_"..key, par, "UIDropDownMenuTemplate")
        UIDropDownMenu_SetWidth(dd, 55)
        UIDropDownMenu_SetText(dd, (GuildLootDB.settings[key] or 15).."s")
        dd:SetPoint("LEFT", lbl, "RIGHT", -8, 0)
        UIDropDownMenu_Initialize(dd, function()
            for _, s in ipairs(opts) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = s.."s"
                info.notCheckable = true
                info.func = function()
                    GuildLootDB.settings[key] = s
                    UIDropDownMenu_SetText(dd, s.."s")
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        return dd
    end

    local timerLbl = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerLbl:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -4)
    timerLbl:SetText("|cff888888Zeiten:|r")
    local ddPrio = MakeTimerDD(main, "Prio", "prioSeconds", {10,15,20,30,45,60}, timerLbl, 4)
    local ddRoll = MakeTimerDD(main, "Roll", "rollSeconds", {10,15,20,30}, ddPrio, 4)

    -- Aktives Item
    local divA = main:CreateTexture(nil, "BACKGROUND")
    divA:SetColorTexture(0.3, 0.3, 0.3, 1)
    divA:SetHeight(1)
    divA:SetPoint("TOPLEFT",  main, "TOPLEFT",  0, -30)
    divA:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, -30)

    activeItemLabel = main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    activeItemLabel:SetPoint("TOPLEFT", divA, "BOTTOMLEFT", 0, -4)
    activeItemLabel:SetPoint("RIGHT", main, "RIGHT", -110, 0)
    activeItemLabel:SetJustifyH("LEFT")
    activeItemLabel:SetText("Kein aktives Item")

    activeItemCategoryLabel = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    activeItemCategoryLabel:SetPoint("LEFT", activeItemLabel, "RIGHT", 4, 0)
    activeItemCategoryLabel:SetTextColor(0.7, 0.7, 0.7)

    resetItemBtn = MakeButton(main, "Zurücksetzen", 100, 22, function()
        GL.Loot.ResetCurrentItem()
    end)
    resetItemBtn:SetPoint("RIGHT", main, "RIGHT", 0, 0)
    resetItemBtn:SetPoint("TOP",   divA, "BOTTOM", 0, -2)

    -- Kandidaten
    local candLabel = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    candLabel:SetPoint("TOPLEFT", activeItemLabel, "BOTTOMLEFT", 0, -10)
    candLabel:SetText("|cffffcc00Bedarfsmeldungen:|r")

    local candScroll = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
    candScroll:SetPoint("TOPLEFT",  candLabel, "BOTTOMLEFT", 0, -2)
    candScroll:SetPoint("TOPRIGHT", main,      "TOPRIGHT",  -22, 0)
    candScroll:SetHeight(90)
    local candContent = CreateFrame("Frame", nil, candScroll)
    candContent:SetSize(candScroll:GetWidth(), 1)
    candScroll:SetScrollChild(candContent)
    panel.candContent = candContent
    panel.candScroll  = candScroll

    -- Buttons: Roll-Aktion + Abbrechen + Countdown
    startRollBtn = MakeButton(main, "Roll freigeben", 130, 24, function()
        GL.Loot.StartRoll()
    end)
    startRollBtn:SetPoint("TOPLEFT", candScroll, "BOTTOMLEFT", 0, -6)

    local cancelPrioBtn = MakeButton(main, "Roll jetzt", 90, 24, function()
        GL.Loot.StartRoll()
    end)
    cancelPrioBtn:SetPoint("LEFT", startRollBtn, "RIGHT", 4, 0)
    panel.cancelPrioBtn = cancelPrioBtn

    countdownLabel = main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    countdownLabel:SetPoint("LEFT", cancelPrioBtn, "RIGHT", 8, 0)
    countdownLabel:SetTextColor(1, 0.5, 0)
    countdownLabel:SetText("")

    -- Ergebnisse
    local resultLabel = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resultLabel:SetPoint("TOPLEFT", startRollBtn, "BOTTOMLEFT", 0, -8)
    resultLabel:SetText("|cffffcc00Ergebnisse:|r")

    local resultScroll = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
    resultScroll:SetPoint("TOPLEFT",  resultLabel, "BOTTOMLEFT", 0, -2)
    resultScroll:SetPoint("TOPRIGHT", main,        "TOPRIGHT",  -22, 0)
    resultScroll:SetHeight(130)
    local resultContent = CreateFrame("Frame", nil, resultScroll)
    resultContent:SetSize(resultScroll:GetWidth(), 1)
    resultScroll:SetScrollChild(resultContent)
    panel.resultContent = resultContent
    panel.resultScroll  = resultScroll

    -- Session-Loot
    local divS = main:CreateTexture(nil, "BACKGROUND")
    divS:SetColorTexture(0.3, 0.3, 0.3, 1)
    divS:SetHeight(1)
    divS:SetPoint("TOPLEFT",  resultScroll, "BOTTOMLEFT",  0, -6)
    divS:SetPoint("TOPRIGHT", resultScroll, "BOTTOMRIGHT", 0, -6)

    local sessionLabel = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionLabel:SetPoint("TOPLEFT", divS, "BOTTOMLEFT", 0, -4)
    sessionLabel:SetText("|cffffcc00Session-Loot:|r")

    local clearSessionBtn = MakeButton(main, "Liste leeren", 90, 18, function()
        local log = GuildLootDB.currentRaid.lootLog
        for _, entry in ipairs(log) do
            local k = tostring(entry.timestamp) .. (entry.player or "")
            sessionHidden()[k] = true
        end
        UI.RefreshSessionLoot()
    end)
    clearSessionBtn:SetPoint("LEFT", sessionLabel, "RIGHT", 8, 0)
    clearSessionBtn:SetPoint("TOP",  sessionLabel, "TOP",   0,  2)

    local sessionScroll = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
    sessionScroll:SetPoint("TOPLEFT",     sessionLabel, "BOTTOMLEFT", 0, -2)
    sessionScroll:SetPoint("BOTTOMRIGHT", main,         "BOTTOMRIGHT", -22, 4)
    local sessionContent = CreateFrame("Frame", nil, sessionScroll)
    sessionContent:SetSize(sessionScroll:GetWidth(), 1)
    sessionScroll:SetScrollChild(sessionContent)
    panel.sessionContent = sessionContent
    panel.sessionScroll  = sessionScroll

    return panel
end

-- ============================================================
-- Loot-Tab Refresh
-- ============================================================

function UI.RefreshLootTab()
    if activeTab ~= TAB_LOOT then return end
    if not lootPanel then return end

    local ci = GL.Loot.GetCurrentItem()
    local pl = GL.Loot.GetPendingLoot()

    -- Pending Loot Buttons (vertikale Liste)
    for _, btn in ipairs(pendingButtons) do btn:Hide() end
    pendingButtons = {}
    local pf = lootPanel.pendingContent
    pf:SetWidth(SIDEBAR_W - 26)  -- feste Breite (Sidebar minus Scrollbar)
    local yOff = -2
    local ROW_H = 26
    for i, item in ipairs(pl) do
        local row = CreateFrame("Frame", nil, pf)
        row:SetPoint("TOPLEFT",  pf, "TOPLEFT",  0, yOff)
        row:SetPoint("TOPRIGHT", pf, "TOPRIGHT", 0, yOff)
        row:SetHeight(ROW_H)

        -- Freigeben-Button (links)
        local releaseBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        releaseBtn:SetSize(80, 22)
        releaseBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
        releaseBtn:SetText("Freigeben")
        releaseBtn:SetScript("OnClick", function()
            GL.Loot.ReleaseItem(item.link)
        end)
        if not GL.IsMasterLooter() then releaseBtn:Disable() end

        -- X-Button (rechts) – Item aus Liste entfernen
        local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        removeBtn:SetSize(22, 22)
        removeBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        removeBtn:SetText("X")
        removeBtn:SetScript("OnClick", function()
            GL.Loot.RemovePendingItem(item.link)
            UI.RefreshLootTab()
        end)
        if not GL.IsMasterLooter() then removeBtn:Disable() end

        -- Item-Link Text (klickbar, Tooltip on hover)
        local linkBtn = CreateFrame("Button", nil, row)
        linkBtn:SetPoint("LEFT",  releaseBtn, "RIGHT", 6, 0)
        linkBtn:SetPoint("RIGHT", removeBtn,  "LEFT", -4, 0)
        linkBtn:SetHeight(ROW_H)

        local linkLbl = linkBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        linkLbl:SetAllPoints()
        linkLbl:SetJustifyH("LEFT")
        linkLbl:SetText(item.link or item.name or "?")

        linkBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(item.link)
            GameTooltip:Show()
        end)
        linkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        linkBtn:SetScript("OnClick", function()
            if GL.IsMasterLooter() then GL.Loot.ReleaseItem(item.link) end
        end)

        row:Show()
        table.insert(pendingButtons, row)
        yOff = yOff - ROW_H - 2
    end

    -- Höhe des pendingContent (ScrollChild) dynamisch anpassen
    local totalH = math.max(1, (#pl * (ROW_H + 2)) + 8)
    pf:SetHeight(totalH)

    -- Aktives Item
    if ci.link then
        activeItemLabel:SetText(ci.link)
        local catNames = { weapons="Waffe", trinket="Trinket", setItems="Set/Token", other="Sonstiges" }
        activeItemCategoryLabel:SetText("[" .. (catNames[ci.category] or "?") .. "]")
        resetItemBtn:SetEnabled(GL.IsMasterLooter())
    else
        activeItemLabel:SetText("|cff888888Kein aktives Item|r")
        activeItemCategoryLabel:SetText("")
        resetItemBtn:SetEnabled(false)
    end

    UI.RefreshCandidates()
    UI.RefreshRollResults()
    UI.RefreshSessionLoot()
    UI.RefreshCountdown(ci.rollState.timeLeft)

    -- Roll-Button: Label + Aktion je nach Phase
    local hasItem    = ci.link ~= nil
    local prioActive = ci.prioState and ci.prioState.active
    local rollActive = ci.rollState.active
    local hasCands   = next(ci.candidates) ~= nil
    local isML       = GL.IsMasterLooter()

    if rollActive then
        startRollBtn:SetText("Auswerten")
        startRollBtn:SetScript("OnClick", function() GL.Loot.FinalizeRoll() end)
        startRollBtn:SetEnabled(isML)
    elseif prioActive then
        startRollBtn:SetText("Roll starten")
        startRollBtn:SetScript("OnClick", function() GL.Loot.StartRoll() end)
        startRollBtn:SetEnabled(isML and hasCands)
    else
        startRollBtn:SetText("Roll freigeben")
        startRollBtn:SetScript("OnClick", function() GL.Loot.StartRoll() end)
        startRollBtn:SetEnabled(isML and hasItem and hasCands)
    end
end

function UI.RefreshCandidates()
    local ci = GL.Loot.GetCurrentItem()
    local content = lootPanel and lootPanel.candContent
    if not content then return end
    local sw = lootPanel.candScroll and lootPanel.candScroll:GetWidth() or 0
    if sw > 10 then content:SetWidth(sw) end

    -- Alte Rows entfernen
    for _, r in ipairs(candidateRows) do r:Hide() end
    candidateRows = {}

    -- Kandidaten sortiert nach Prio
    local sorted = {}
    for name, data in pairs(ci.candidates) do
        table.insert(sorted, { name = name, prio = data.prio })
    end
    table.sort(sorted, function(a, b) return a.prio < b.prio end)

    local yOff = 0
    for _, entry in ipairs(sorted) do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(content:GetWidth(), 20)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
        nameText:SetText(GL.ShortName(entry.name))
        nameText:SetWidth(180)

        local prioText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        prioText:SetPoint("LEFT", nameText, "RIGHT", 8, 0)
        prioText:SetText("Prio: |cffffcc00" .. entry.prio .. "|r")

        row:Show()
        table.insert(candidateRows, row)
        yOff = yOff - 20
    end
    content:SetHeight(math.max(1, -yOff))
end

function UI.RefreshRollResults()
    local ci      = GL.Loot.GetCurrentItem()
    local content = lootPanel and lootPanel.resultContent
    if not content then return end
    local sw = lootPanel.resultScroll and lootPanel.resultScroll:GetWidth() or 0
    if sw > 10 then content:SetWidth(sw) end

    for _, r in ipairs(rollResultRows) do r:Hide() end
    rollResultRows = {}

    -- Ergebnisse sortiert (höchster Roll zuerst)
    local results = ci.rollState.results
    local sorted  = {}
    for name, val in pairs(results) do
        table.insert(sorted, { name = name, roll = val })
    end
    -- Auch alle Roll-berechtigten anzeigen die noch nicht gewürfelt haben
    for name, _ in pairs(ci.rollState.players) do
        if not results[name] then
            table.insert(sorted, { name = name, roll = nil })
        end
    end
    table.sort(sorted, function(a, b)
        if a.roll == nil then return false end
        if b.roll == nil then return true end
        return a.roll > b.roll
    end)

    local lowestPrio = nil
    for _, data in pairs(ci.candidates) do
        if lowestPrio == nil or data.prio < lowestPrio then lowestPrio = data.prio end
    end

    local yOff = 0
    for i, entry in ipairs(sorted) do
        local isWinner = entry.name == ci.winner
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(content:GetWidth() - 30, 24)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)

        -- Hervorhebung Gewinner
        if isWinner then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 0.8, 0, 0.15)
        end

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
        nameText:SetWidth(160)
        if isWinner then
            nameText:SetText("|cffffcc00★ " .. entry.name .. "|r")
        else
            nameText:SetText(entry.name)
        end

        -- Prio anzeigen
        local candData = ci.candidates[entry.name]
        -- Kurzname-Lookup
        if not candData then
            for n, d in pairs(ci.candidates) do
                if GL.ShortName(n) == entry.name then candData = d; break end
            end
        end
        local prioText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        prioText:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
        prioText:SetWidth(60)
        prioText:SetText(candData and ("Prio " .. candData.prio) or "")

        local rollText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rollText:SetPoint("LEFT", prioText, "RIGHT", 4, 0)
        rollText:SetWidth(60)
        if entry.roll then
            rollText:SetText("|cff00ff00" .. entry.roll .. "|r")
        else
            rollText:SetText("|cff888888—|r")
        end

        -- Zuweisen-Button
        local assignBtn = MakeButton(row, "Zuweisen", 80, 20, function()
            GL.Loot.AssignLoot(entry.name)
        end)
        assignBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        assignBtn:SetEnabled(GL.IsMasterLooter() and not ci.rollState.active)

        row:Show()
        table.insert(rollResultRows, row)
        yOff = yOff - 26
    end
    content:SetHeight(math.max(1, -yOff))
end

function UI.RefreshSessionLoot()
    local content = lootPanel and lootPanel.sessionContent
    if not content then return end
    local sw = lootPanel.sessionScroll and lootPanel.sessionScroll:GetWidth() or 0
    if sw > 10 then content:SetWidth(sw) end

    for _, r in ipairs(sessionLootRows) do r:Hide() end
    sessionLootRows = {}

    local log = GuildLootDB.currentRaid.lootLog
    local ROW_H = 22
    local yOff  = 0
    local shown = 0
    -- Neueste zuerst
    for i = #log, 1, -1 do
        local entry = log[i]
        local k = tostring(entry.timestamp) .. (entry.player or "")
        if not sessionHidden()[k] then
            local isChecked = sessionChecked()[k] or false
            local row = CreateFrame("Frame", nil, content)
            row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOff)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
            row:SetHeight(ROW_H)

            -- Upvalues für Closure vorab deklarieren
            local nameText, itemLbl

            -- Checkbox (links)
            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cb:SetSize(18, 18)
            cb:SetPoint("LEFT", row, "LEFT", 0, 0)
            cb:SetChecked(isChecked)
            cb:SetScript("OnClick", function(self)
                sessionChecked()[k] = self:GetChecked()
                local alpha = sessionChecked()[k] and 0.4 or 1
                if nameText then nameText:SetAlpha(alpha) end
                if itemLbl  then itemLbl:SetAlpha(alpha)  end
            end)

            -- X-Button (rechts)
            local xBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            xBtn:SetSize(18, 18)
            xBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            xBtn:SetText("×")
            xBtn:SetScript("OnClick", function()
                sessionHidden()[k] = true
                UI.RefreshSessionLoot()
            end)

            -- Spieler
            nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            nameText:SetWidth(100)
            nameText:SetJustifyH("LEFT")
            nameText:SetText("|cffffcc00" .. GL.ShortName(entry.player or "?") .. "|r")

            -- Schwierigkeit
            local diffLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            diffLbl:SetPoint("LEFT", nameText, "RIGHT", 2, 0)
            diffLbl:SetWidth(20)
            diffLbl:SetText(ColorDiff(entry.difficulty))

            -- Item-Link
            itemLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            itemLbl:SetPoint("LEFT",  diffLbl, "RIGHT",  2,  0)
            itemLbl:SetPoint("RIGHT", xBtn,    "LEFT",  -4,  0)
            itemLbl:SetJustifyH("LEFT")
            itemLbl:SetText(entry.item or "?")

            -- Ausgegraut wenn bereits abgehakt
            if isChecked then
                nameText:SetAlpha(0.4)
                itemLbl:SetAlpha(0.4)
            end

            row:Show()
            table.insert(sessionLootRows, row)
            yOff  = yOff - ROW_H - 1
            shown = shown + 1
        end
    end

    if shown == 0 then
        local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        empty:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
        empty:SetText("|cff888888Noch kein Loot verteilt.|r")
        table.insert(sessionLootRows, empty)
        yOff = -20
    end

    content:SetHeight(math.max(1, -yOff))
end

function UI.RefreshCountdown(secs)
    if not countdownLabel then return end
    local ci = GL.Loot.GetCurrentItem()
    if ci.rollState.active and secs and secs > 0 then
        countdownLabel:SetTextColor(1, 0.5, 0)
        countdownLabel:SetText("Roll: noch " .. secs .. " Sek.")
    elseif ci.prioState and ci.prioState.active and ci.prioState.timeLeft > 0 then
        countdownLabel:SetTextColor(0.4, 1, 0.4)
        countdownLabel:SetText("Prio: noch " .. ci.prioState.timeLeft .. " Sek.")
    else
        countdownLabel:SetText("")
    end
end

function UI.RefreshPrioCountdown(secs)
    UI.RefreshCountdown(secs)
end

-- ============================================================
-- Spieler-Panel
-- ============================================================

function UI.BuildSpielerPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    panel:Hide()

    -- Header
    local headers = { "Raider", "Loot", "Set", "Waffe", "Trinket", "Rest", "SetBonus" }
    local colW    = { 140, 30, 40, 50, 50, 30, 70 }
    local xOff = 4
    for i, h in ipairs(headers) do
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", xOff, -6)
        lbl:SetWidth(colW[i])
        lbl:SetText(h)
        lbl:SetTextColor(1, 0.8, 0)
        xOff = xOff + colW[i] + 4
    end

    -- Trennlinie
    local div = panel:CreateTexture(nil, "BACKGROUND")
    div:SetColorTexture(0.4, 0.4, 0.4, 1)
    div:SetHeight(1)
    div:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -22)
    div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -22)

    -- Scroll-Bereich
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", div, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 1)   -- feste Startbreite, wird beim Refresh aktualisiert
    scroll:SetScrollChild(content)
    panel.content = content
    panel.scroll  = scroll
    panel.colW    = colW

    return panel
end

function UI.RefreshSpielerTab()
    if activeTab ~= TAB_SPIELER then return end
    if not spielerPanel or not spielerPanel.content then return end

    -- Breite jetzt setzen, wenn das Frame wirklich gerendert wurde
    local scroll = spielerPanel.scroll
    local w = scroll and scroll:GetWidth() or 0
    if w > 10 then
        spielerPanel.content:SetWidth(w)
    end

    for _, r in ipairs(playerRows) do r:Hide() end
    playerRows = {}

    local participants = GuildLootDB.currentRaid.participants
    local absent       = GuildLootDB.currentRaid.absent
    local players      = GuildLootDB.players
    local colW         = spielerPanel.colW
    local content      = spielerPanel.content

    local yOff = 0
    for _, fullName in ipairs(participants) do
        local data    = players[fullName] or {}
        local isAbsent = absent[fullName]
        local row = CreateFrame("Frame", nil, content)
        local rowW = math.max(content:GetWidth() - 30, 200)
        row:SetSize(rowW, 22)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 4, yOff)

        -- Zebra-Streifen
        if (#playerRows % 2 == 0) then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.03)
        end

        local xOff = 4

        -- Spalte 1: Raider-Name
        local nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLbl:SetPoint("TOPLEFT", row, "TOPLEFT", xOff, -3)
        nameLbl:SetWidth(colW[1])
        local displayName = GL.ShortName(fullName)
        if isAbsent then
            nameLbl:SetText("|cff888888" .. displayName .. " (abw.)|r")
        else
            nameLbl:SetText(GL.ColoredName(displayName, data.class))
        end
        xOff = xOff + colW[1] + 4

        -- Spalte 2: Lootberechtigt (Checkbox)
        local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        check:SetSize(18, 18)
        check:SetPoint("TOPLEFT", row, "TOPLEFT", xOff, -2)
        check:SetChecked(data.lootEligible ~= false)
        check:SetEnabled(GL.IsMasterLooter())
        check:SetScript("OnClick", function(self)
            GL.CreatePlayerRecord(fullName)
            GuildLootDB.players[fullName].lootEligible = self:GetChecked()
        end)
        xOff = xOff + colW[2] + 4

        -- Spalten 3-5: Set, Waffe, Trinket (Difficulty-Anzeige, klickbar für Override)
        local diffCats = { { "setItems", colW[3] }, { "weapons", colW[4] }, { "trinket", colW[5] } }
        for _, dc in ipairs(diffCats) do
            local cat, cw = dc[1], dc[2]
            local ld = data.lastDifficulty and data.lastDifficulty[cat]
            local diffBtn = CreateFrame("Button", nil, row)
            diffBtn:SetSize(cw, 18)
            diffBtn:SetPoint("TOPLEFT", row, "TOPLEFT", xOff, -2)
            local diffLbl = diffBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            diffLbl:SetAllPoints()
            diffLbl:SetJustifyH("CENTER")
            diffLbl:SetText(ColorDiff(ld))
            diffBtn:SetScript("OnClick", function()
                if GL.IsMasterLooter() then
                    UI.ShowDifficultyOverrideMenu(diffBtn, fullName, cat, diffLbl)
                end
            end)
            xOff = xOff + cw + 4
        end

        -- Spalte 6: Rest-Loot Anzahl
        local restCount = (data.counts and data.counts.other) or 0
        local restLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        restLbl:SetPoint("TOPLEFT", row, "TOPLEFT", xOff, -3)
        restLbl:SetWidth(colW[6])
        restLbl:SetJustifyH("CENTER")
        restLbl:SetText(tostring(restCount))
        xOff = xOff + colW[6] + 4

        -- Spalte 7: Set Bonus (Spinner 0-4)
        local setPieces = (data.setPieces) or 0
        local spinFrame = CreateFrame("Frame", nil, row)
        spinFrame:SetSize(colW[7], 18)
        spinFrame:SetPoint("TOPLEFT", row, "TOPLEFT", xOff, -2)

        local minusBtn = CreateFrame("Button", nil, spinFrame, "UIPanelButtonTemplate")
        minusBtn:SetSize(18, 18)
        minusBtn:SetPoint("LEFT", spinFrame, "LEFT", 0, 0)
        minusBtn:SetText("-")

        local pieceLbl = spinFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        pieceLbl:SetPoint("LEFT", minusBtn, "RIGHT", 2, 0)
        pieceLbl:SetWidth(28)
        pieceLbl:SetJustifyH("CENTER")
        local function UpdatePieceLbl()
            GL.CreatePlayerRecord(fullName)
            local sp = GuildLootDB.players[fullName].setPieces or 0
            if sp >= 4 then
                pieceLbl:SetText("|cff00ff00" .. sp .. "/4|r")
            else
                pieceLbl:SetText(sp .. "/4")
            end
        end
        UpdatePieceLbl()

        local plusBtn = CreateFrame("Button", nil, spinFrame, "UIPanelButtonTemplate")
        plusBtn:SetSize(18, 18)
        plusBtn:SetPoint("LEFT", pieceLbl, "RIGHT", 2, 0)
        plusBtn:SetText("+")

        minusBtn:SetEnabled(GL.IsMasterLooter())
        plusBtn:SetEnabled(GL.IsMasterLooter())

        minusBtn:SetScript("OnClick", function()
            GL.CreatePlayerRecord(fullName)
            local p = GuildLootDB.players[fullName]
            p.setPieces = math.max(0, (p.setPieces or 0) - 1)
            UpdatePieceLbl()
        end)
        plusBtn:SetScript("OnClick", function()
            GL.CreatePlayerRecord(fullName)
            local p = GuildLootDB.players[fullName]
            p.setPieces = math.min(4, (p.setPieces or 0) + 1)
            UpdatePieceLbl()
        end)

        row:Show()
        table.insert(playerRows, row)
        yOff = yOff - 24
    end
    content:SetHeight(math.max(1, -yOff))
end

-- Difficulty-Override Dropdown
function UI.ShowDifficultyOverrideMenu(anchor, fullName, category, label)
    local menu = CreateFrame("Frame", "GuildLootDiffMenu", UIParent, "UIDropDownMenuTemplate")
    local options = {
        { text = "Normal (N)",  diff = "N" },
        { text = "Heroic (H)",  diff = "H" },
        { text = "Mythic (M)",  diff = "M" },
        { text = "— (keine)",   diff = nil },
    }
    UIDropDownMenu_Initialize(menu, function(self, level)
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text     = opt.text
            info.notCheckable = true
            info.func     = function()
                GL.CreatePlayerRecord(fullName)
                GuildLootDB.players[fullName].lastDifficulty[category] = opt.diff
                label:SetText(ColorDiff(opt.diff))
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, menu, anchor, 0, 0)
end

-- ============================================================
-- Log-Panel
-- ============================================================

function UI.BuildLogPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    panel:Hide()

    -- Export-Button oben rechts
    local exportBtn = MakeButton(panel, "Export JSON", 100, 22, function()
        UI.ShowExportPopup()
    end)
    exportBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
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

local exportPopup

function UI.ShowExportPopup()
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
        title:SetText("JSON Export – Strg+A dann Strg+C zum Kopieren")

        local eb = CreateFrame("EditBox", nil, exportPopup, "InputBoxTemplate")
        eb:SetPoint("TOPLEFT",     exportPopup, "TOPLEFT",   10, -30)
        eb:SetPoint("BOTTOMRIGHT", exportPopup, "BOTTOMRIGHT", -10, 10)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(GameFontHighlightSmall)
        eb:SetScript("OnEscapePressed", function() exportPopup:Hide() end)
        exportPopup.editBox = eb
    end

    exportPopup.editBox:SetText(GL.ExportJSON())
    exportPopup.editBox:HighlightText()
    exportPopup:Show()
    exportPopup.editBox:SetFocus()
end

function UI.RefreshLogTab()
    if activeTab ~= TAB_LOG then return end
    if not logPanel or not logPanel.content then return end

    for _, r in ipairs(logRows) do r:Hide() end
    logRows = {}

    local log     = GuildLootDB.currentRaid.lootLog
    local content = logPanel.content
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
        empty:SetText("|cff888888Keine Loot-Vergaben in dieser Session.|r")
        table.insert(logRows, empty)
    end

    content:SetHeight(math.max(1, -yOff))
end

-- ============================================================
-- Verlauf-Panel (Raid-History)
-- ============================================================

function UI.BuildVerlaufPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT",     parent, "TOPLEFT",     0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    panel:Hide()

    local LIST_W = 240

    -- Linke Spalte: Raid-Liste
    local listFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    listFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    listFrame:SetPoint("TOPLEFT",    panel, "TOPLEFT",    2, -2)
    listFrame:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 2,  2)
    listFrame:SetWidth(LIST_W)

    local listHeader = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    listHeader:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 6, -6)
    listHeader:SetText("|cffffcc00Vergangene Raids:|r")

    local listScroll = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
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
    panel.detailHeader:SetText("|cff888888— Raid auswählen —|r")

    local resumeBtn = MakeButton(detailFrame, "Raid fortsetzen", 120, 22, function()
        if selectedHistoryIndex then
            GL.ResumeRaid(selectedHistoryIndex)
            selectedHistoryIndex = nil
            UI.ShowTab(TAB_LOOT)
        end
    end)
    resumeBtn:SetPoint("TOPRIGHT", detailFrame, "TOPRIGHT", -6, -4)
    resumeBtn:Hide()
    panel.resumeBtn = resumeBtn

    local deletePending = false
    local deleteTimer   = nil

    local deleteBtn = MakeButton(detailFrame, "Löschen", 80, 22, function()
        if not selectedHistoryIndex then return end
        if deletePending then
            -- zweiter Klick → löschen
            if deleteTimer then deleteTimer:Cancel(); deleteTimer = nil end
            deletePending = false
            panel.deleteBtn:SetText("Löschen")
            table.remove(GuildLootDB.raidHistory, selectedHistoryIndex)
            selectedHistoryIndex = nil
            UI.RefreshVerlaufTab()
            UI.RefreshVerlaufDetail(nil)
        else
            -- erster Klick → 3-Sekunden-Fenster öffnen
            deletePending = true
            panel.deleteBtn:SetText("|cffff4444Sicher?|r")
            deleteTimer = C_Timer.NewTimer(3, function()
                deletePending = false
                deleteTimer   = nil
                if panel.deleteBtn then
                    panel.deleteBtn:SetText("Löschen")
                end
            end)
        end
    end)
    deleteBtn:SetPoint("RIGHT", resumeBtn, "LEFT", -4, 0)
    deleteBtn:Hide()
    panel.deleteBtn = deleteBtn

    -- Arm-Zustand zurücksetzen wenn Auswahl wechselt
    panel.resetDeleteArm = function()
        if deleteTimer then deleteTimer:Cancel(); deleteTimer = nil end
        deletePending = false
        deleteBtn:SetText("Löschen")
    end

    local detailScroll = CreateFrame("ScrollFrame", nil, detailFrame, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT",     panel.detailHeader, "BOTTOMLEFT", 0,   -4)
    detailScroll:SetPoint("BOTTOMRIGHT", detailFrame,        "BOTTOMRIGHT", -22,  4)
    local detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetSize(detailScroll:GetWidth(), 1)
    detailScroll:SetScrollChild(detailContent)
    panel.detailContent = detailContent
    panel.detailScroll  = detailScroll

    return panel
end

function UI.RefreshVerlaufTab()
    if activeTab ~= TAB_VERLAUF then return end
    if not verlaufPanel or not verlaufPanel.listContent then return end

    local sw = verlaufPanel.listScroll and verlaufPanel.listScroll:GetWidth() or 0
    if sw > 10 then verlaufPanel.listContent:SetWidth(sw) end

    for _, r in ipairs(verlaufRows) do r:Hide() end
    verlaufRows = {}

    local history = GuildLootDB.raidHistory or {}
    local content = verlaufPanel.listContent
    local yOff    = 0
    local ROW_H   = 40

    -- Neueste zuerst
    for i = #history, 1, -1 do
        local snap = history[i]
        local idx  = i   -- Closure-Kopie

        local row = CreateFrame("Button", nil, content)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOff)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
        row:SetHeight(ROW_H)

        -- Zebra-Streifen
        if (#verlaufRows % 2 == 0) then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.04)
        end

        -- Auswahl-Hervorhebung
        local selTex = row:CreateTexture(nil, "BACKGROUND")
        selTex:SetAllPoints()
        selTex:SetColorTexture(1, 0.8, 0, 0.12)
        selTex:SetShown(selectedHistoryIndex == idx)

        -- Tier-Name
        local tierLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tierLbl:SetPoint("TOPLEFT", row, "TOPLEFT",  4, -4)
        tierLbl:SetPoint("RIGHT",   row, "RIGHT",   -4, 0)
        tierLbl:SetJustifyH("LEFT")
        tierLbl:SetText((snap.tier and snap.tier ~= "") and snap.tier or "|cff888888Unbekannt|r")

        -- Datum, Spieler, Loot-Anzahl
        local infoLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        infoLbl:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 4)
        local diffStr     = snap.difficulty and ("[" .. snap.difficulty .. "] ") or ""
        local playerCount = snap.participants and #snap.participants or 0
        local lootCount   = snap.lootLog and #snap.lootLog or 0
        local dateStr     = snap.closedAt and date("%d.%m.%Y %H:%M", snap.closedAt) or "?"
        infoLbl:SetText("|cff888888" .. diffStr .. dateStr
                        .. "  " .. playerCount .. " Spieler, " .. lootCount .. " Loot|r")

        row:SetScript("OnClick", function()
            selectedHistoryIndex = idx
            UI.RefreshVerlaufTab()
            UI.RefreshVerlaufDetail(idx)
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
        empty:SetText("|cff888888Keine abgeschlossenen Raids gespeichert.|r")
        table.insert(verlaufRows, empty)
        yOff = -20
    end

    content:SetHeight(math.max(1, -yOff))

    if selectedHistoryIndex then
        UI.RefreshVerlaufDetail(selectedHistoryIndex)
    end
end

function UI.RefreshVerlaufDetail(idx)
    if not verlaufPanel or not verlaufPanel.detailContent then return end

    local sw = verlaufPanel.detailScroll and verlaufPanel.detailScroll:GetWidth() or 0
    if sw > 10 then verlaufPanel.detailContent:SetWidth(sw) end

    for _, r in ipairs(verlaufDetailRows) do r:Hide() end
    verlaufDetailRows = {}

    local history = GuildLootDB.raidHistory or {}
    local snap    = history[idx]
    if not snap then
        verlaufPanel.detailHeader:SetText("|cff888888— Raid auswählen —|r")
        verlaufPanel.detailContent:SetHeight(1)
        if verlaufPanel.resumeBtn    then verlaufPanel.resumeBtn:Hide() end
        if verlaufPanel.deleteBtn    then verlaufPanel.deleteBtn:Hide() end
        if verlaufPanel.resetDeleteArm then verlaufPanel.resetDeleteArm() end
        return
    end

    if verlaufPanel.resetDeleteArm then verlaufPanel.resetDeleteArm() end
    if verlaufPanel.resumeBtn then
        verlaufPanel.resumeBtn:Show()
        verlaufPanel.resumeBtn:SetEnabled(not GuildLootDB.currentRaid.active)
    end
    if verlaufPanel.deleteBtn then verlaufPanel.deleteBtn:Show() end

    local diffStr = snap.difficulty and (" [" .. snap.difficulty .. "]") or ""
    local dateStr = snap.closedAt and date("%d.%m.%Y", snap.closedAt) or "?"
    verlaufPanel.detailHeader:SetText((snap.tier or "?") .. diffStr .. "  |cff888888" .. dateStr .. "|r")

    local log     = snap.lootLog or {}
    local content = verlaufPanel.detailContent
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
        empty:SetText("|cff888888Keine Loot-Vergaben in diesem Raid.|r")
        table.insert(verlaufDetailRows, empty)
        yOff = -20
    end

    content:SetHeight(math.max(1, -yOff))
end

-- ============================================================
-- Session-Leiste Refresh
-- ============================================================

function UI.RefreshSessionBar()
    if not UI.sessionStatusLbl then return end
    local raid = GuildLootDB.currentRaid
    if raid.active then
        local tierStr = (raid.tier and raid.tier ~= "") and (" – " .. raid.tier) or ""
        local count   = #raid.participants
        UI.sessionStatusLbl:SetText("|cff00ff00Raid aktiv|r" .. tierStr .. "  |cffffcc00" .. count .. " Spieler|r")
        if UI.tierBox      then UI.tierBox:SetText(raid.tier or "") end
        if UI.startRaidBtn then UI.startRaidBtn:SetText("Roster neu laden") end
        if UI.closeRaidBtn then UI.closeRaidBtn:Enable() end
    else
        UI.sessionStatusLbl:SetText("|cff888888Kein Raid aktiv|r")
        if UI.startRaidBtn then UI.startRaidBtn:SetText("Raid starten") end
        if UI.closeRaidBtn then UI.closeRaidBtn:Disable() end
    end
    UI.RefreshDockTab()
end

-- ============================================================
-- Globaler Refresh
-- ============================================================

function UI.Refresh()
    if not mainFrame then return end
    UI.RefreshSessionBar()
    if activeTab == TAB_LOOT    then UI.RefreshLootTab()    end
    if activeTab == TAB_SPIELER then UI.RefreshSpielerTab() end
    if activeTab == TAB_LOG     then UI.RefreshLogTab()     end
    if activeTab == TAB_VERLAUF then UI.RefreshVerlaufTab() end
end

function UI.RefreshMLButton()
    if UI.mlCheck then
        UI.mlCheck:SetChecked(GuildLootDB.settings.isMasterLooter)
    end
end

-- ============================================================
-- Toggle / Minimize / Auto-Expand
-- ============================================================

function UI.Toggle()
    if GuildLootDB.settings.minimized then
        -- Angedockt → aufklappen
        UI.Undock()
    elseif mainFrame and mainFrame:IsShown() then
        -- Sichtbar → andocken
        UI.Dock()
    else
        -- Versteckt → zeigen
        if mainFrame then
            mainFrame:Show()
            UI.Refresh()
        end
    end
end

function UI.AutoExpand()
    -- Nur für ML: Bei Boss-Kill Dock öffnen und Loot-Tab zeigen
    if GuildLootDB.settings.minimized then
        UI.Undock()
    elseif mainFrame and not mainFrame:IsShown() then
        mainFrame:Show()
        UI.Refresh()
    end
    UI.ShowTab(TAB_LOOT)
end

-- ============================================================
-- Difficulty-Popup (bei unbekanntem Itemlevel)
-- ============================================================

function UI.ShowDifficultyPopup(recipientShortName)
    if difficultyPopup then difficultyPopup:Hide() end

    local popup = CreateFrame("Frame", "GuildLootDiffPopup", UIParent, "BackdropTemplate")
    popup:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16, insets = {left=4,right=4,top=4,bottom=4} })
    popup:SetFrameStrata("DIALOG")
    popup:SetSize(240, 100)
    popup:SetPoint("CENTER", mainFrame, "CENTER")
    difficultyPopup = popup

    local lbl = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOP", popup, "TOP", 0, -12)
    lbl:SetText("Schwierigkeitsgrad auswählen:")

    local function MakeDiffBtn(text, diff, xPos)
        local btn = MakeButton(popup, text, 60, 24, function()
            popup:Hide()
            GL.Loot.AssignLootConfirm(recipientShortName, diff)
        end)
        btn:SetPoint("BOTTOM", popup, "BOTTOM", xPos, 12)
        return btn
    end

    MakeDiffBtn("Normal", "N", -80)
    MakeDiffBtn("Heroic", "H",  -10)
    MakeDiffBtn("Mythic", "M",   60)

    popup:Show()
end

-- ============================================================
-- Position speichern / wiederherstellen
-- ============================================================

function UI.SavePosition()
    if not mainFrame then return end
    local point, _, relPoint, x, y = mainFrame:GetPoint()
    GuildLootDB.settings.framePos = { point = point, x = x, y = y }
end

function UI.LoadPosition()
    if not mainFrame then return end
    if GuildLootDB.settings.minimized then
        -- War angedockt: Dock-Tab anzeigen, Hauptfenster versteckt lassen
        mainFrame:Hide()
        UI.BuildDockTab()
        UI.RefreshDockTab()
        dockTab:Show()
    else
        -- Position wiederherstellen
        local pos = GuildLootDB.settings.framePos
        if pos then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
        end
    end
end
