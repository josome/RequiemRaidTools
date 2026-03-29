-- GuildLoot – UI.lua
-- Hauptfenster: Frame, Dock, Tabs, Session-Bar, Position

GuildLoot = GuildLoot or {}
local GL = GuildLoot
GL.UI = GL.UI or {}
local UI = GL.UI

-- ============================================================
-- Konstanten
-- ============================================================

local FRAME_W, FRAME_H = 720, 560
local TAB_LOOT, TAB_SPIELER, TAB_LOG, TAB_RAID = 1, 2, 3, 4
UI.TAB_LOOT = TAB_LOOT
local DIFF_COLORS = { N = "|cff1eff00", H = "|cff0070dd", M = "|cffff8000" }

-- Tab-Konstanten für Split-Dateien
UI.TAB_LOOT    = TAB_LOOT
UI.TAB_SPIELER = TAB_SPIELER
UI.TAB_LOG     = TAB_LOG
UI.TAB_RAID    = TAB_RAID

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

local function MakeItemLinkBtn(parent, leftAnchorFrame, xOff, link, displayText)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("TOPLEFT", leftAnchorFrame, "TOPRIGHT", xOff, 0)
    btn:SetPoint("RIGHT", parent,           "RIGHT",    -4,   0)
    btn:SetHeight(18)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetAllPoints()
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
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

-- Hilfsfunktionen für Split-Dateien bereitstellen
UI._H = {
    ColorDiff       = ColorDiff,
    MakeButton      = MakeButton,
    MakeItemLinkBtn = MakeItemLinkBtn,
}

-- ============================================================
-- Frame-Globals & Status
-- ============================================================

local mainFrame
local contentFrame
local dockTab
UI.activeTab = TAB_LOOT

local tabButtons = {}
local settingsPanel

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
        local w = mainFrame:GetWidth()
        local h = mainFrame:GetHeight()
        local x = mainFrame:GetLeft()
        local y = mainFrame:GetTop() - UIParent:GetTop()
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
        mainFrame:SetSize(w, h)
        UI.SavePosition()
    end)

    -- Titelzeile
    mainFrame.TitleText:SetText("RaidLootTracker v1.2")

    -- Settings-Button (Zahnrad-Icon)
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

    -- ML-Checkbox
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
        local wantsML = self:GetChecked()
        if wantsML then
            -- ML-Claim-Protokoll
            local currentML = GuildLootDB.currentRaid and GuildLootDB.currentRaid.mlName or ""
            local myName    = GL.ShortName(UnitName("player") or "")
            if currentML ~= "" and GL.ShortName(currentML) ~= myName and GL.IsPlayerInGroup(currentML) then
                -- Aktueller ML ist noch in der Gruppe → Anfrage stellen
                self:SetChecked(false)  -- noch nicht setzen, erst auf Bestätigung warten
                if GL.Comm then GL.Comm.SendMLRequest(UnitName("player") or "") end
                GL.Print("ML-Anfrage an " .. GL.ShortName(currentML) .. " gesendet...")
                return
            else
                -- Kein ML oder ML weg → sofort übernehmen
                GuildLootDB.settings.isMasterLooter = true
                if GL.Comm and (IsInRaid() or IsInGroup()) then
                    GL.Comm.SendMLAnnounce(UnitName("player") or "")
                end
            end
        else
            GuildLootDB.settings.isMasterLooter = false
        end
        GL.Print("Master Looter: " .. (GuildLootDB.settings.isMasterLooter and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
        if UI.RefreshLootTab then UI.RefreshLootTab() end
    end)
    UI.mlCheck = mlCheck

    -- Andocken-Button
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

    -- Session-Leiste
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

    local statusLbl = sessionBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLbl:SetPoint("LEFT", sessionBar, "LEFT", 8, 0)
    statusLbl:SetJustifyH("LEFT")
    statusLbl:SetText("|cff888888No active raid|r")
    UI.sessionStatusLbl = statusLbl

    local crashWarnLbl = sessionBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    crashWarnLbl:SetPoint("RIGHT", sessionBar, "RIGHT", -8, 0)
    crashWarnLbl:SetJustifyH("RIGHT")
    crashWarnLbl:SetText("|cffff4444Absturz gefährdet Log-Daten — /reload sichert.|r")
    crashWarnLbl:Hide()
    UI.sessionCrashWarnLbl = crashWarnLbl

    -- Content-Frame
    contentFrame = CreateFrame("Frame", nil, mainFrame)
    contentFrame:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",     4, -26)
    contentFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 42)

    -- Tab-Buttons
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

    -- Panels (in je eigener Datei definiert)
    UI.lootPanel    = UI.BuildLootPanel(contentFrame)
    UI.spielerPanel = UI.BuildSpielerPanel(contentFrame)
    UI.logPanel     = UI.BuildLogPanel(contentFrame)
    UI.raidPanel    = UI.BuildRaidPanel(contentFrame)

    -- Settings-Panel
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

    local title = dockTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", dockTab, "TOP", 0, -8)
    title:SetText("|cff00ccffG|r")

    local title2 = dockTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title2:SetPoint("TOP", title, "BOTTOM", 0, -2)
    title2:SetText("|cff00ccffL|r")

    UI.dockLootCount = dockTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.dockLootCount:SetPoint("CENTER", dockTab, "CENTER", 0, 0)
    UI.dockLootCount:SetText("")

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
    UI.ShowStartupTab()
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
    UI.activeTab = tabID
    UI.lootPanel:Hide()
    UI.spielerPanel:Hide()
    UI.logPanel:Hide()
    if UI.raidPanel then UI.raidPanel:Hide() end

    for i, tb in ipairs(tabButtons) do
        if i == tabID then
            PanelTemplates_SelectTab(tb)
        else
            PanelTemplates_DeselectTab(tb)
        end
    end

    if tabID == TAB_LOOT then
        UI.lootPanel:Show()
        UI.RefreshLootTab()
    elseif tabID == TAB_SPIELER then
        UI.spielerPanel:Show()
        UI.RefreshSpielerTab()
    elseif tabID == TAB_LOG then
        UI.logPanel:Show()
        UI.RefreshLogTab()
    elseif tabID == TAB_RAID then
        if UI.raidPanel then UI.raidPanel:Show() end
        UI.RefreshRaidTab()
    end
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
        UI.sessionStatusLbl:SetText("|cff00ff00Raid active|r" .. tierStr .. "  |cffffcc00" .. count .. " players|r")
        if UI.sessionCrashWarnLbl then UI.sessionCrashWarnLbl:Show() end
        if UI.tierBox      then UI.tierBox:SetText(raid.tier or "") end
        if UI.startRaidBtn then UI.startRaidBtn:SetText("Reload Roster") end
    else
        UI.sessionStatusLbl:SetText("|cff888888No active raid|r")
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
    if UI.activeTab == TAB_LOOT    then UI.RefreshLootTab()    end
    if UI.activeTab == TAB_SPIELER then UI.RefreshSpielerTab() end
    if UI.activeTab == TAB_LOG     then UI.RefreshLogTab()     end
    if UI.activeTab == TAB_RAID    then UI.RefreshRaidTab()    end
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
        UI.Undock()
    elseif mainFrame and mainFrame:IsShown() then
        UI.Dock()
    else
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

local difficultyPopup

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
