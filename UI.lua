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
local SIDEBAR_W = 240
local TAB_LOOT, TAB_SPIELER, TAB_LOG, TAB_RAID = 1, 2, 3, 4
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
local lootPanel, spielerPanel, logPanel, raidPanel, settingsPanel
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
        local x = self:GetLeft()
        local y = self:GetTop() - UIParent:GetTop()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
        UI.SavePosition()
    end)
    mainFrame:SetToplevel(true)
    mainFrame:SetResizable(true)
    mainFrame:SetResizeBounds(720, 500, 1400, 1000)

    -- Resize-Grip (untere rechte Ecke)
    local resizeGrip = CreateFrame("Button", nil, mainFrame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -2, 2)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function() mainFrame:StartSizing("BOTTOMRIGHT") end)
    resizeGrip:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        local x = mainFrame:GetLeft()
        local y = mainFrame:GetTop() - UIParent:GetTop()
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
        UI.SavePosition()
    end)

    -- Titelzeile
    mainFrame.TitleText:SetText("RaidLootTracker v1.2")

    -- Settings-Button (Zahnrad-Icon) rechts neben ML-Checkbox
    local settingsBtn = CreateFrame("Button", nil, mainFrame)
    settingsBtn:SetSize(20, 20)
    settingsBtn:SetPoint("RIGHT", mainFrame.CloseButton, "LEFT", -4, 0)
    settingsBtn:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    settingsBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Round", "ADD")
    settingsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Settings", 1, 1, 1)
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    settingsBtn:SetScript("OnClick", function()
        if settingsPanel then
            if settingsPanel:IsShown() then
                settingsPanel:Hide()
            else
                settingsPanel:Show()
            end
        end
    end)
    UI.settingsBtn = settingsBtn

    -- Settings-Panel schließen wenn Hauptfenster versteckt wird
    mainFrame:SetScript("OnHide", function()
        if settingsPanel then settingsPanel:Hide() end
    end)

    -- ML-Checkbox (oben rechts in Titelleiste, links neben Settings-Button)
    local mlCheck = CreateFrame("CheckButton", "GuildLootMLCheck", mainFrame, "UICheckButtonTemplate")
    mlCheck:SetSize(20, 20)
    mlCheck:SetPoint("RIGHT", settingsBtn, "LEFT", -8, 0)
    mlCheck.text:SetText("ML")
    mlCheck.text:SetTextColor(1, 0.8, 0)
    mlCheck.text:ClearAllPoints()
    mlCheck.text:SetPoint("RIGHT", mlCheck, "LEFT", -2, 0)
    mlCheck.text:SetJustifyH("RIGHT")
    mlCheck:SetChecked(GuildLootDB.settings.isMasterLooter)
    mlCheck:SetScript("OnClick", function(self)
        GuildLootDB.settings.isMasterLooter = self:GetChecked()
        GL.Print("Master Looter: " .. (GuildLootDB.settings.isMasterLooter and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
        if UI.RefreshLootTab then UI.RefreshLootTab() end
    end)
    UI.mlCheck = mlCheck

    -- Andocken-Button (Pfeil links)
    local minBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    minBtn:SetSize(32, 18)
    minBtn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -2)
    minBtn:SetText("«")
    minBtn:SetScript("OnClick", UI.ToggleMinimize)
    minBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Dock", 1, 1, 1)
        GameTooltip:AddLine("Dock the window as a tab on the left edge", 0.7, 0.7, 0.7, true)
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

    -- Status-Label links
    local statusLbl = sessionBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLbl:SetPoint("LEFT", sessionBar, "LEFT", 8, 0)
    statusLbl:SetJustifyH("LEFT")
    statusLbl:SetText("|cff888888● No active raid|r")
    UI.sessionStatusLbl = statusLbl

    -- Absturz-Warnung rechts (nur wenn Raid aktiv)
    local crashWarnLbl = sessionBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    crashWarnLbl:SetPoint("RIGHT", sessionBar, "RIGHT", -8, 0)
    crashWarnLbl:SetJustifyH("RIGHT")
    crashWarnLbl:SetText("|cffff4444● Absturz gefährdet Log-Daten — /reload sichert.|r")
    crashWarnLbl:Hide()
    UI.sessionCrashWarnLbl = crashWarnLbl

    -- Content-Frame (unterhalb der Titelleiste, oberhalb der Session-Leiste)
    contentFrame = CreateFrame("Frame", nil, mainFrame)
    contentFrame:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",     4, -26)
    contentFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 42)

    -- Tab-Buttons am unteren Rand des Frames (WoW-native Stil wie CharacterFrame)
    local tabNames = { "Loot", "Players", "Log", "Raid" }
    for i, name in ipairs(tabNames) do
        local tb = CreateFrame("Button", "GuildLootMainFrameTab" .. i, mainFrame, "CharacterFrameTabTemplate")
        tb:SetScript("OnLoad", nil)
        tb:SetScript("OnShow", nil)
        tb:SetFrameStrata("FULLSCREEN")
        tb:SetText(name)
        PanelTemplates_TabResize(tb, 0)
        tb:SetID(i)
        if i == 1 then
            tb:SetPoint("TOPLEFT", mainFrame, "BOTTOMLEFT", 11, 2)
        else
            tb:SetPoint("LEFT", tabButtons[i - 1], "RIGHT", 4, 0)
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
    raidPanel = UI.BuildRaidPanel(contentFrame)

    -- Settings-Panel: klappt rechts neben dem Hauptfenster aus
    settingsPanel = UI.BuildSettingsPanel(UIParent)
    settingsPanel:SetWidth(320)
    settingsPanel:SetPoint("TOPLEFT",    mainFrame, "TOPRIGHT",    4, 0)
    settingsPanel:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMRIGHT", 4, 0)
    settingsPanel:SetClampedToScreen(true)
    settingsPanel:SetFrameStrata("DIALOG")
    settingsPanel:Hide()

    UI.ShowStartupTab()
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
    local savedY = (GuildLootDB.settings and GuildLootDB.settings.dockTabY) or 0
    dockTab:SetPoint("LEFT", UIParent, "LEFT", 0, savedY)
    dockTab:SetFrameStrata("HIGH")
    dockTab:SetMovable(true)
    dockTab:EnableMouse(true)
    dockTab:RegisterForDrag("LeftButton")
    dockTab:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dockTab:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Nur Y-Position behalten, X immer am linken Rand
        local _, _, _, _, y = self:GetPoint()
        self:ClearAllPoints()
        self:SetPoint("LEFT", UIParent, "LEFT", 0, y)
        GuildLootDB.settings.dockTabY = y
    end)
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

-- ============================================================
-- Settings-Overlay
-- ============================================================

function UI.BuildSettingsPanel(parent)
    local panel = CreateFrame("Frame", "GuildLootSettingsPanel", parent, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0.05, 0.05, 0.08, 1)

    local y = -12  -- laufende Y-Position

    local function SectionHeader(label)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
        lbl:SetText("|cffffcc00" .. label .. "|r")
        y = y - 18
        local div = panel:CreateTexture(nil, "BACKGROUND")
        div:SetColorTexture(0.5, 0.5, 0.5, 0.5)
        div:SetHeight(1)
        div:SetPoint("TOPLEFT",  panel, "TOPLEFT",  12, y)
        div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, y)
        y = y - 8
        return lbl
    end

    local function MakeCheck(labelText, key, subtable)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
        cb.text:SetText(labelText)
        cb.text:ClearAllPoints()
        cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        local function getVal()
            if subtable then
                return GuildLootDB.settings[subtable] and GuildLootDB.settings[subtable][key]
            end
            return GuildLootDB.settings[key]
        end
        cb:SetChecked(getVal() ~= false)
        cb:SetScript("OnClick", function(self)
            if subtable then
                GuildLootDB.settings[subtable][key] = self:GetChecked()
            else
                GuildLootDB.settings[key] = self:GetChecked()
            end
        end)
        y = y - 24
        return cb
    end

    local function MakeDD(labelText, settingKey, opts, labels, xAnchor, xOff)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if xAnchor then
            lbl:SetPoint("LEFT", xAnchor, "RIGHT", xOff or 8, 0)
        else
            lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
        end
        lbl:SetText(labelText)
        local dd = CreateFrame("Frame", "GuildLootSettingsDD_" .. settingKey, panel, "UIDropDownMenuTemplate")
        UIDropDownMenu_SetWidth(dd, 80)
        local curVal = GuildLootDB.settings[settingKey]
        local curLabel = tostring(curVal)
        for i, v in ipairs(opts) do
            if v == curVal then curLabel = (labels and labels[i]) or tostring(v); break end
        end
        UIDropDownMenu_SetText(dd, curLabel)
        dd:SetPoint("LEFT", lbl, "RIGHT", -8, 0)
        UIDropDownMenu_Initialize(dd, function()
            for i, v in ipairs(opts) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = (labels and labels[i]) or tostring(v)
                info.notCheckable = true
                info.func = function()
                    GuildLootDB.settings[settingKey] = v
                    UIDropDownMenu_SetText(dd, (labels and labels[i]) or tostring(v))
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        return dd, lbl
    end

    -- ── Sektion 1: Loot-Filter ────────────────────────────────
    SectionHeader("Loot Filter")

    -- Min. Qualität Dropdown
    local qualLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qualLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    qualLbl:SetText("Min. Quality:")
    local qualDD = CreateFrame("Frame", "GuildLootSettingsDD_minQuality", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(qualDD, 80)
    qualDD:SetPoint("LEFT", qualLbl, "RIGHT", -8, 0)
    local qualOpts   = { 3, 4, 5 }
    local qualLabels = { "|cff0070ddRare|r", "|cffa335eeEpic|r", "|cffff8000Legendary|r" }
    local function qualLabel(v)
        for i, q in ipairs(qualOpts) do if q == v then return qualLabels[i] end end
        return tostring(v)
    end
    UIDropDownMenu_SetText(qualDD, qualLabel(GuildLootDB.settings.minQuality or 4))
    UIDropDownMenu_Initialize(qualDD, function()
        for i, v in ipairs(qualOpts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = qualLabels[i]
            info.notCheckable = true
            info.func = function()
                GuildLootDB.settings.minQuality = v
                UIDropDownMenu_SetText(qualDD, qualLabels[i])
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    y = y - 30

    MakeCheck("Hide non-equippable items", "filterNonEquip")

    local catLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    catLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    catLbl:SetText("|cff888888Show categories:|r")
    y = y - 22

    -- Kategorie-Checkboxen in 2×2 Grid
    local function MakeCatCheck(labelText, key, col)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(18, 18)
        local xOff = (col == 1) and 20 or 200
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", xOff, y)
        cb.text:SetText(labelText)
        cb.text:ClearAllPoints()
        cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        local s = GuildLootDB.settings
        cb:SetChecked((s.filterCategories and s.filterCategories[key]) ~= false)
        cb:SetScript("OnClick", function(self)
            if not GuildLootDB.settings.filterCategories then
                GuildLootDB.settings.filterCategories = {}
            end
            GuildLootDB.settings.filterCategories[key] = self:GetChecked()
        end)
        return cb
    end
    MakeCatCheck("Weapons",   "weapons",  1)
    MakeCatCheck("Trinkets",  "trinket",  2)
    y = y - 24
    MakeCatCheck("Set Items", "setItems", 1)
    MakeCatCheck("Other",     "other",    2)
    y = y - 14

    -- ── Sektion 2: Timer ──────────────────────────────────────
    SectionHeader("Timers")

    local timerLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    timerLbl:SetText("|cff888888Prio Phase:|r")

    local ddPrio = CreateFrame("Frame", "GuildLootSettingsDD_prioSeconds", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(ddPrio, 80)
    UIDropDownMenu_SetText(ddPrio, (GuildLootDB.settings.prioSeconds or 15) .. "s")
    ddPrio:SetPoint("LEFT", timerLbl, "RIGHT", -8, 0)
    UIDropDownMenu_Initialize(ddPrio, function()
        for _, s in ipairs({10,15,20,30,45,60}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = s .. "s"
            info.notCheckable = true
            info.func = function()
                GuildLootDB.settings.prioSeconds = s
                UIDropDownMenu_SetText(ddPrio, s .. "s")
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    y = y - 28

    local rollLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rollLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    rollLbl:SetText("|cff888888Roll Phase:|r")

    local ddRoll = CreateFrame("Frame", "GuildLootSettingsDD_rollSeconds", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(ddRoll, 80)
    UIDropDownMenu_SetText(ddRoll, (GuildLootDB.settings.rollSeconds or 15) .. "s")
    ddRoll:SetPoint("LEFT", rollLbl, "RIGHT", -8, 0)
    UIDropDownMenu_Initialize(ddRoll, function()
        for _, s in ipairs({10,15,20,30}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = s .. "s"
            info.notCheckable = true
            info.func = function()
                GuildLootDB.settings.rollSeconds = s
                UIDropDownMenu_SetText(ddRoll, s .. "s")
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    y = y - 28

    -- ── Sektion 3: Allgemein ──────────────────────────────────
    SectionHeader("General")

    -- Chat-Kanal Dropdown
    local chatLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chatLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    chatLbl:SetText("|cff888888Chat Channel:|r")

    local chatOpts   = { "AUTO",        "RAID",       "INSTANCE_CHAT",   "PARTY",        "OFF" }
    local chatLabels = { "Automatic",   "Raid Chat",  "Instance Chat",   "Group Chat",   "Off" }
    local function getChatLabel(v)
        for i, c in ipairs(chatOpts) do if c == v then return chatLabels[i] end end
        return "Automatic"
    end
    local ddChat = CreateFrame("Frame", "GuildLootSettingsDD_chatChannel", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(ddChat, 100)
    ddChat:SetPoint("LEFT", chatLbl, "RIGHT", -8, 0)
    UIDropDownMenu_SetText(ddChat, getChatLabel(GuildLootDB.settings.chatChannel or "AUTO"))
    UIDropDownMenu_Initialize(ddChat, function()
        for i, v in ipairs(chatOpts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = chatLabels[i]
            info.notCheckable = true
            info.func = function()
                GuildLootDB.settings.chatChannel = v
                -- postToChat für Backward-Compat mitführen
                GuildLootDB.settings.postToChat = (v ~= "OFF")
                UIDropDownMenu_SetText(ddChat, chatLabels[i])
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    y = y - 30

    MakeCheck("Announce item start as raid warning", "raidWarnItem")

    return panel
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

function UI.ShowStartupTab()
    local raid = GuildLootDB.currentRaid
    if not raid.active then
        UI.ShowTab(TAB_RAID)
    else
        local last = GuildLootDB.settings.lastTab
        if last and last >= TAB_LOOT and last <= TAB_RAID then
            UI.ShowTab(last)
        else
            UI.ShowTab(TAB_LOOT)
        end
    end
end

function UI.ShowTab(tabID)
    GuildLootDB.settings.lastTab = tabID
    activeTab = tabID
    lootPanel:Hide()
    spielerPanel:Hide()
    logPanel:Hide()
    if raidPanel then raidPanel:Hide() end

    for i, tb in ipairs(tabButtons) do
        if i == tabID then
            PanelTemplates_SelectTab(tb)
        else
            PanelTemplates_DeselectTab(tb)
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
    elseif tabID == TAB_RAID then
        if raidPanel then raidPanel:Show() end
        UI.RefreshRaidTab()
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
    local sidebar = CreateFrame("Frame", nil, panel)
    sidebar:SetPoint("TOPRIGHT",    panel, "TOPRIGHT",    -4,  -2)
    sidebar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4,   4)
    sidebar:SetWidth(SIDEBAR_W)

    local pendingLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pendingLabel:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 6, -6)
    pendingLabel:SetText("|cffffcc00Pending Loot:|r")

    local pendingScroll = CreateFrame("ScrollFrame", "GuildLootPendingScroll", sidebar, "UIPanelScrollFrameTemplate")
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

    -- Aktives Item
    local divA = main:CreateTexture(nil, "BACKGROUND")
    divA:SetColorTexture(0.3, 0.3, 0.3, 1)
    divA:SetHeight(1)
    divA:SetPoint("TOPLEFT",  main, "TOPLEFT",  0, -4)
    divA:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, -4)

    local activeItemIcon = CreateFrame("Frame", nil, main)
    activeItemIcon:SetSize(32, 32)
    activeItemIcon:SetPoint("TOPLEFT", divA, "BOTTOMLEFT", 4, -4)
    local iconTex = activeItemIcon:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    activeItemIcon:EnableMouse(true)
    activeItemIcon:SetScript("OnEnter", function(self)
        local ci = GL.Loot.GetCurrentItem()
        if ci and ci.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(ci.link)
            GameTooltip:Show()
        end
    end)
    activeItemIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.activeItemIcon    = activeItemIcon
    panel.activeItemIconTex = iconTex

    activeItemLabel = main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    activeItemLabel:SetPoint("LEFT",  activeItemIcon, "RIGHT", 6, 0)
    activeItemLabel:SetPoint("RIGHT", main, "RIGHT", -110, 0)
    activeItemLabel:SetJustifyH("LEFT")
    activeItemLabel:SetText("No active item")

    -- Tooltip-Hover über aktives Item Label
    local activeItemHover = CreateFrame("Frame", nil, main)
    activeItemHover:SetPoint("LEFT",  activeItemIcon, "RIGHT", 6, 0)
    activeItemHover:SetPoint("RIGHT", main, "RIGHT", -110, 0)
    activeItemHover:SetPoint("TOP",    activeItemIcon, "TOP",    0, 0)
    activeItemHover:SetPoint("BOTTOM", activeItemIcon, "BOTTOM", 0, 0)
    activeItemHover:EnableMouse(true)
    activeItemHover:SetScript("OnEnter", function(self)
        local ci = GL.Loot.GetCurrentItem()
        if ci and ci.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(ci.link)
            GameTooltip:Show()
        end
    end)
    activeItemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    activeItemCategoryLabel = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    activeItemCategoryLabel:SetPoint("TOPLEFT", activeItemLabel, "BOTTOMLEFT", 0, -2)
    activeItemCategoryLabel:SetTextColor(0.7, 0.7, 0.7)

    resetItemBtn = MakeButton(main, "Reset", 100, 22, function()
        GL.Loot.ResetCurrentItem()
    end)
    resetItemBtn:SetPoint("RIGHT", main, "RIGHT", 0, 0)
    resetItemBtn:SetPoint("TOP",   divA, "BOTTOM", 0, -2)

    -- Kandidaten
    local candLabel = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    candLabel:SetPoint("TOPLEFT", activeItemCategoryLabel, "BOTTOMLEFT", 0, -6)
    candLabel:SetText("|cffffcc00Prio Submissions:|r")

    local candScroll = CreateFrame("ScrollFrame", "GuildLootCandScroll", main, "UIPanelScrollFrameTemplate")
    candScroll:SetPoint("TOPLEFT",  candLabel, "BOTTOMLEFT", 0, -2)
    candScroll:SetPoint("TOPRIGHT", main,      "TOPRIGHT",  -22, 0)
    candScroll:SetHeight(90)
    local candContent = CreateFrame("Frame", nil, candScroll)
    candContent:SetSize(candScroll:GetWidth(), 1)
    candScroll:SetScrollChild(candContent)
    panel.candContent = candContent
    panel.candLabel   = candLabel
    panel.candScroll  = candScroll
    candLabel:Hide()
    candScroll:Hide()

    -- Buttons: Roll-Aktion + Abbrechen + Countdown
    startRollBtn = MakeButton(main, "Release Roll", 130, 24, function()
        GL.Loot.StartRoll()
    end)
    startRollBtn:SetPoint("TOPLEFT", activeItemCategoryLabel, "BOTTOMLEFT", 0, -6)

    countdownLabel = main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    countdownLabel:SetPoint("LEFT", startRollBtn, "RIGHT", 8, 0)
    countdownLabel:SetTextColor(1, 0.5, 0)
    countdownLabel:SetText("")

    -- Ergebnisse
    local resultLabel = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resultLabel:SetPoint("TOPLEFT", startRollBtn, "BOTTOMLEFT", 0, -8)
    resultLabel:SetText("|cffffcc00Results:|r")

    local resultScroll = CreateFrame("ScrollFrame", "GuildLootResultScroll", main, "UIPanelScrollFrameTemplate")
    resultScroll:SetPoint("TOPLEFT", resultLabel, "BOTTOMLEFT", 0, -2)
    resultScroll:SetPoint("RIGHT",   main, "RIGHT", -22, 0)
    resultScroll:SetHeight(120)  -- Startwert, wird via equalizeScrolls aktualisiert
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
    sessionLabel:SetText("|cffffcc00Session Loot:|r")

    local clearSessionBtn = MakeButton(main, "Clear List", 90, 18, function()
        local log = GuildLootDB.currentRaid.lootLog
        for _, entry in ipairs(log) do
            local k = tostring(entry.timestamp) .. (entry.player or "")
            sessionHidden()[k] = true
        end
        UI.RefreshSessionLoot()
    end)
    clearSessionBtn:SetPoint("LEFT", sessionLabel, "RIGHT", 8, 0)
    clearSessionBtn:SetPoint("TOP",  sessionLabel, "TOP",   0,  2)

    local sessionScroll = CreateFrame("ScrollFrame", "GuildLootSessionScroll", main, "UIPanelScrollFrameTemplate")
    sessionScroll:SetPoint("TOPLEFT",     sessionLabel, "BOTTOMLEFT", 0, -2)
    sessionScroll:SetPoint("BOTTOMRIGHT", main,         "BOTTOMRIGHT", -22, 4)
    local sessionContent = CreateFrame("Frame", nil, sessionScroll)
    sessionContent:SetSize(sessionScroll:GetWidth(), 1)
    sessionScroll:SetScrollChild(sessionContent)
    panel.sessionContent = sessionContent
    panel.sessionScroll  = sessionScroll

    -- ── Results und Session Loot gleichmäßig aufteilen ────────
    -- Gesamtraum = resultLabel-Unterkante bis main-Unterkante minus Trennbereich
    -- Trennbereich: 2(gap) + 6(divS-gap) + 1(divS) + 4(label-gap) + 12(label) + 2(scroll-gap) + 4(bottom) = 31px
    local function equalizeScrolls()
        local rlb = resultLabel:GetBottom()
        local mb  = main:GetBottom()
        if not rlb or not mb or rlb <= mb then return end
        local each = math.floor((rlb - mb - 31) / 2)
        if each < 20 then return end
        resultScroll:SetHeight(each)
    end
    main:HookScript("OnSizeChanged", function() C_Timer.After(0, equalizeScrolls) end)
    panel:HookScript("OnShow",       function() C_Timer.After(0, equalizeScrolls) end)

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
    local ROW_H = 30
    for i, item in ipairs(pl) do
        local row = CreateFrame("Frame", nil, pf)
        row:SetPoint("TOPLEFT",  pf, "TOPLEFT",  0, yOff)
        row:SetPoint("TOPRIGHT", pf, "TOPRIGHT", 0, yOff)
        row:SetHeight(ROW_H)

        -- « Auswahl-Button (links)
        local releaseBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        releaseBtn:SetSize(22, 22)
        releaseBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
        releaseBtn:SetText("«")
        releaseBtn:SetScript("OnClick", function()
            GL.Loot.ReleaseItem(item.link)
        end)
        releaseBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Item auswählen", 1, 1, 1)
            GameTooltip:Show()
        end)
        releaseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if not GL.IsMasterLooter() then releaseBtn:Disable() end

        -- X-Button (rechts) – Item aus Liste entfernen
        local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        removeBtn:SetSize(22, 22)
        removeBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        removeBtn:SetText("×")
        removeBtn:SetScript("OnClick", function()
            GL.Loot.RemovePendingItem(item.link)
            UI.RefreshLootTab()
        end)
        if not GL.IsMasterLooter() then removeBtn:Disable() end

        -- Item-Icon
        local pendingIcon = CreateFrame("Frame", nil, row)
        pendingIcon:SetSize(24, 24)
        pendingIcon:SetPoint("LEFT", releaseBtn, "RIGHT", 4, 0)
        local pendingIconTex = pendingIcon:CreateTexture(nil, "ARTWORK")
        pendingIconTex:SetAllPoints()
        pendingIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local pIcon = select(10, GetItemInfo(item.link))
        if pIcon then pendingIconTex:SetTexture(pIcon) end
        pendingIcon:EnableMouse(true)
        pendingIcon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(item.link)
            GameTooltip:Show()
        end)
        pendingIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Item-Link Text mit Tooltip-Hover
        local linkBtn = CreateFrame("Frame", nil, row)
        linkBtn:SetPoint("LEFT",  pendingIcon, "RIGHT", 4, 0)
        linkBtn:SetPoint("RIGHT", removeBtn,   "LEFT", -4, 0)
        linkBtn:SetHeight(ROW_H)
        linkBtn:EnableMouse(true)

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
        local catNames = { weapons="Weapon", trinket="Trinket", setItems="Set/Token", other="Other" }
        activeItemCategoryLabel:SetText("[" .. (catNames[ci.category] or "?") .. "]")
        resetItemBtn:SetEnabled(GL.IsMasterLooter())
        if lootPanel.activeItemIconTex then
            local icon = select(10, GetItemInfo(ci.link))
            lootPanel.activeItemIconTex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
    else
        activeItemLabel:SetText("|cff888888No active item|r")
        activeItemCategoryLabel:SetText("")
        resetItemBtn:SetEnabled(false)
        if lootPanel.activeItemIconTex then lootPanel.activeItemIconTex:SetTexture(nil) end
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
    local hasWinner  = ci.winner ~= nil
    local isML       = GL.IsMasterLooter()

    if rollActive then
        startRollBtn:SetText("Evaluate")
        startRollBtn:SetScript("OnClick", function() GL.Loot.FinalizeRoll() end)
        startRollBtn:SetEnabled(isML)
    elseif hasWinner then
        startRollBtn:SetText("Evaluate")
        startRollBtn:SetEnabled(false)
    elseif prioActive then
        startRollBtn:SetText("Start Roll")
        startRollBtn:SetScript("OnClick", function() GL.Loot.StartRoll() end)
        startRollBtn:SetEnabled(isML and hasCands)
    else
        startRollBtn:SetText("Release Roll")
        startRollBtn:SetScript("OnClick", function() GL.Loot.StartRoll() end)
        startRollBtn:SetEnabled(isML and hasItem and hasCands)
    end
end

function UI.RefreshCandidates()
    local ci = GL.Loot.GetCurrentItem()
    local content = lootPanel and lootPanel.candContent
    if not content then GL.Print("[DBG] RefreshCandidates: no content"); return end
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
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
        row:SetPoint("RIGHT",   content, "RIGHT",    0, 0)
        row:SetHeight(20)

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
    for _, r in ipairs(rollResultRows) do r:Hide() end
    rollResultRows = {}

    -- Beste Prio bestimmen
    local bestPrio = nil
    for _, data in pairs(ci.candidates) do
        if bestPrio == nil or data.prio < bestPrio then bestPrio = data.prio end
    end

    -- Alle Kandidaten aufnehmen (nicht nur Roll-berechtigte)
    local sorted = {}
    for name, data in pairs(ci.candidates) do
        local short = GL.ShortName(name)
        table.insert(sorted, {
            name     = short,
            prio     = data.prio,
            roll     = ci.rollState.results[short],
            eligible = (data.prio == bestPrio),
        })
    end

    -- Sortierung: Prio aufsteigend, dann Roll absteigend (nil → hinten)
    table.sort(sorted, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        if a.roll == nil and b.roll == nil then return false end
        if a.roll == nil then return false end
        if b.roll == nil then return true end
        return a.roll > b.roll
    end)

    local yOff = 0
    for _, entry in ipairs(sorted) do
        local isWinner = entry.name == ci.winner
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
        row:SetPoint("RIGHT",   content, "RIGHT",  -30, 0)
        row:SetHeight(24)

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
        elseif not entry.eligible then
            nameText:SetText("|cff888888" .. entry.name .. "|r")
        else
            nameText:SetText(entry.name)
        end

        local prioText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        prioText:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
        prioText:SetWidth(60)
        if not entry.eligible then
            prioText:SetText("|cff888888Prio " .. entry.prio .. "|r")
        else
            prioText:SetText("Prio " .. entry.prio)
        end

        -- Roll-Wert nur für eligible Spieler
        if entry.eligible then
            local rollText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            rollText:SetPoint("LEFT", prioText, "RIGHT", 4, 0)
            rollText:SetWidth(60)
            if entry.roll then
                rollText:SetText("|cff00ff00" .. entry.roll .. "|r")
            else
                rollText:SetText("|cff888888—|r")
            end
        end

        -- Assign-Button nur für eligible Spieler
        if entry.eligible then
            local assignBtn = MakeButton(row, "Assign", 80, 20, function()
                GL.Loot.AssignLoot(entry.name)
            end)
            assignBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            assignBtn:SetEnabled(GL.IsMasterLooter() and not ci.rollState.active)
        end

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
    local ROW_H = 26
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
            local nameText, itemLbl, iconFrame

            -- Checkbox (links)
            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cb:SetSize(18, 18)
            cb:SetPoint("LEFT", row, "LEFT", 0, 0)

            -- Item-Icon
            iconFrame = CreateFrame("Frame", nil, row)
            iconFrame:SetSize(24, 24)
            iconFrame:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            cb:SetChecked(isChecked)
            cb:SetScript("OnClick", function(self)
                sessionChecked()[k] = self:GetChecked()
                local alpha = sessionChecked()[k] and 0.4 or 1
                if nameText  then nameText:SetAlpha(alpha)  end
                if itemLbl   then itemLbl:SetAlpha(alpha)   end
                if iconFrame then iconFrame:SetAlpha(alpha) end
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
            nameText:SetPoint("LEFT", iconFrame, "RIGHT", 4, 0)
            nameText:SetWidth(100)
            nameText:SetJustifyH("LEFT")
            nameText:SetText("|cffffcc00" .. GL.ShortName(entry.player or "?") .. "|r")

            -- Schwierigkeit
            local diffLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            diffLbl:SetPoint("LEFT", nameText, "RIGHT", 2, 0)
            diffLbl:SetWidth(20)
            diffLbl:SetText(ColorDiff(entry.difficulty))

            -- Icon-Textur
            local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
            iconTex:SetAllPoints()
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local icon = select(10, GetItemInfo(entry.item or ""))
            if icon then iconTex:SetTexture(icon) end
            iconFrame:SetScript("OnEnter", function(self)
                if entry.item then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(entry.item)
                    GameTooltip:Show()
                end
            end)
            iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Item-Link
            itemLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            itemLbl:SetPoint("LEFT",  diffLbl, "RIGHT",  4,  0)
            itemLbl:SetPoint("RIGHT", xBtn,    "LEFT",  -4,  0)
            itemLbl:SetJustifyH("LEFT")
            itemLbl:SetText(entry.item or "?")

            -- Transparenter Hover-Frame über dem Item-Text für Tooltip
            local itemHover = CreateFrame("Frame", nil, row)
            itemHover:SetAllPoints(itemLbl)
            itemHover:EnableMouse(true)
            itemHover:SetScript("OnEnter", function(self)
                if entry.item then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(entry.item)
                    GameTooltip:Show()
                end
            end)
            itemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Ausgegraut wenn bereits abgehakt
            if isChecked then
                nameText:SetAlpha(0.4)
                itemLbl:SetAlpha(0.4)
                iconFrame:SetAlpha(0.4)
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
        empty:SetText("|cff888888No loot distributed yet.|r")
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
        countdownLabel:SetText("Roll: " .. secs .. " sec left")
    elseif ci.prioState and ci.prioState.active and ci.prioState.timeLeft > 0 then
        countdownLabel:SetTextColor(0.4, 1, 0.4)
        countdownLabel:SetText("Prio: " .. ci.prioState.timeLeft .. " sec left")
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
    local headers = { "Raider", "Loot", "Set", "Weapon", "Trinket", "Other", "Set Bonus" }
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
    local scroll = CreateFrame("ScrollFrame", "GuildLootSpielerScroll", panel, "UIPanelScrollFrameTemplate")
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
        title:SetText("JSON Export – press Copy All, then Ctrl+C")

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
        empty:SetText("|cff888888No loot assigned this session.|r")
        table.insert(logRows, empty)
    end

    content:SetHeight(math.max(1, -yOff))
end

-- ============================================================
-- Raid-Panel (Raid-History + Steuerung)
-- ============================================================

function UI.BuildRaidPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT",     parent, "TOPLEFT",     0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    panel:Hide()

    local LIST_W = 240

    -- Steuerleiste oben: Raid-Steuerung
    local controlStrip = CreateFrame("Frame", nil, panel)
    controlStrip:SetPoint("TOPLEFT",  panel, "TOPLEFT",  2, -2)
    controlStrip:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
    controlStrip:SetHeight(30)

    -- Tier-Eingabe im controlStrip
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

    -- [Raid starten]-Button
    local startRaidBtn = CreateFrame("Button", nil, controlStrip, "UIPanelButtonTemplate")
    startRaidBtn:SetSize(90, 22)
    startRaidBtn:SetPoint("LEFT", controlStrip, "LEFT", LIST_W + 4, 0)
    startRaidBtn:SetText("Start Raid")
    startRaidBtn:SetScript("OnClick", function()
        local tier = tierBox:GetText()
        GL.StartRaid(tier ~= "" and tier or nil)
        UI.RefreshSessionBar()
        UI.Refresh()
        UI.UpdateEndResumeBtn()
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

    -- Arm-Zustand zurücksetzen wenn Auswahl wechselt
    panel.resetDeleteArm = function()
        if UI.deleteRaidBtn then UI.deleteRaidBtn:SetText("Delete") end
    end

    local detailScroll = CreateFrame("ScrollFrame", "GuildLootRaidDetailScroll", detailFrame, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT",     panel.detailHeader, "BOTTOMLEFT", 0,   -4)
    detailScroll:SetPoint("BOTTOMRIGHT", detailFrame,        "BOTTOMRIGHT", -22,  4)
    local detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetSize(detailScroll:GetWidth(), 1)
    detailScroll:SetScrollChild(detailContent)
    panel.detailContent = detailContent
    panel.detailScroll  = detailScroll

    return panel
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
end

function UI.RefreshRaidTab()
    if activeTab ~= TAB_RAID then return end
    if not raidPanel or not raidPanel.listContent then return end

    local sw = raidPanel.listScroll and raidPanel.listScroll:GetWidth() or 0
    if sw > 10 then raidPanel.listContent:SetWidth(sw) end

    for _, r in ipairs(verlaufRows) do r:Hide() end
    verlaufRows = {}

    local history = GuildLootDB.raidHistory or {}
    local content = raidPanel.listContent
    local yOff    = 0
    local ROW_H   = 40

    -- Aktiver Raid ganz oben (idx = 0 als Sentinel)
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
        tierLbl:SetText((snap.tier and snap.tier ~= "") and snap.tier or "|cff888888Unknown|r")

        -- Datum, Spieler, Loot-Anzahl
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

local lastDetailIdx = nil

function UI.RefreshRaidDetail(idx)
    if not raidPanel or not raidPanel.detailContent then return end

    local sw = raidPanel.detailScroll and raidPanel.detailScroll:GetWidth() or 0
    if sw > 10 then raidPanel.detailContent:SetWidth(sw) end

    for _, r in ipairs(verlaufDetailRows) do r:Hide() end
    verlaufDetailRows = {}

    -- Sonderfall: aktiver Raid (idx == 0)
    if idx == 0 then
        local raid = GuildLootDB.currentRaid
        if not raid.active then
            selectedHistoryIndex = nil  -- Auswahl zurücksetzen
            idx = nil  -- Raid inzwischen beendet → "nichts ausgewählt" zeigen
        else
            if idx ~= lastDetailIdx and raidPanel.resetDeleteArm then
                raidPanel.resetDeleteArm()
            end
            lastDetailIdx = 0
            if UI.deleteRaidBtn then UI.deleteRaidBtn:SetEnabled(false) end  -- aktiven Raid nicht löschbar
            if UI.exportRaidBtn then UI.exportRaidBtn:SetEnabled(true) end
            UI.UpdateEndResumeBtn()
            local diffStr = raid.difficulty and (" [" .. raid.difficulty .. "]") or ""
            raidPanel.detailHeader:SetText("|cff00ff00● Active|r  " .. (raid.tier or "?") .. diffStr)
            local log     = raid.lootLog or {}
            local content = raidPanel.detailContent
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
            raidPanel.detailContent:SetHeight(math.max(1, -yOff))
            return
        end
    end

    local history = GuildLootDB.raidHistory or {}
    local snap    = history[idx]
    if not snap then
        raidPanel.detailHeader:SetText("|cff888888— Select a raid —|r")
        raidPanel.detailContent:SetHeight(1)
        if UI.deleteRaidBtn then UI.deleteRaidBtn:SetEnabled(false) end
        if UI.exportRaidBtn then UI.exportRaidBtn:SetEnabled(false) end
        UI.UpdateEndResumeBtn()
        if raidPanel.resetDeleteArm then raidPanel.resetDeleteArm() end
        lastDetailIdx = nil
        return
    end

    -- Arm nur zurücksetzen wenn Auswahl wechselt, nicht bei jedem Refresh
    if idx ~= lastDetailIdx and raidPanel.resetDeleteArm then
        raidPanel.resetDeleteArm()
    end
    lastDetailIdx = idx
    if UI.deleteRaidBtn then UI.deleteRaidBtn:SetEnabled(true) end
    if UI.exportRaidBtn then UI.exportRaidBtn:SetEnabled(true) end
    UI.UpdateEndResumeBtn()

    local diffStr = snap.difficulty and (" [" .. snap.difficulty .. "]") or ""
    local dateStr = snap.closedAt and date("%d.%m.%Y", snap.closedAt) or "?"
    raidPanel.detailHeader:SetText((snap.tier or "?") .. diffStr .. "  |cff888888" .. dateStr .. "|r")

    local log     = snap.lootLog or {}
    local content = raidPanel.detailContent
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

-- ============================================================
-- Session-Leiste Refresh
-- ============================================================

function UI.RefreshSessionBar()
    if not UI.sessionStatusLbl then return end
    local raid = GuildLootDB.currentRaid
    if raid.active then
        local tierStr = (raid.tier and raid.tier ~= "") and (" – " .. raid.tier) or ""
        local count   = #raid.participants
        UI.sessionStatusLbl:SetText("|cff00ff00●|r Raid active" .. tierStr .. "  |cffffcc00● " .. count .. " players|r")
        if UI.sessionCrashWarnLbl then UI.sessionCrashWarnLbl:Show() end
        if UI.tierBox      then UI.tierBox:SetText(raid.tier or "") end
        if UI.startRaidBtn then UI.startRaidBtn:SetText("Reload Roster") end
    else
        UI.sessionStatusLbl:SetText("|cff888888● No active raid|r")
        if UI.sessionCrashWarnLbl then UI.sessionCrashWarnLbl:Hide() end
        if UI.startRaidBtn then UI.startRaidBtn:SetText("Start Raid") end
    end
    UI.UpdateEndResumeBtn()
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
    if activeTab == TAB_RAID then UI.RefreshRaidTab() end
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
    local x = mainFrame:GetLeft()
    local y = mainFrame:GetTop() - UIParent:GetTop()
    local w, h = mainFrame:GetSize()
    GuildLootDB.settings.framePos  = { x = x, y = y }
    GuildLootDB.settings.frameSize = { w = w, h = h }
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
        local sz = GuildLootDB.settings.frameSize
        if sz then
            local w = math.max(sz.w or FRAME_W, 720)
            local h = math.max(sz.h or FRAME_H, 500)
            mainFrame:SetSize(w, h)
        end
        local pos = GuildLootDB.settings.framePos
        if pos then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x or 0, pos.y or 0)
        end
    end
end
