-- GuildLoot – UI_PlayerPopup.lua
-- Loot-Popup für Observer und Player: Prio-Buttons, Roll-Button, Announce-Filter.
-- Wird durch ITEM_ON angezeigt, durch ITEM_OFF/ASSIGN wieder ausgeblendet.

local GL = GuildLoot
local UI = GL.UI

-- ============================================================
-- Interner Zustand
-- ============================================================

local popup          = nil   -- das Frame
local helpPanel      = nil   -- Filter-Beschreibungs-Panel (links vom Popup)
local enableCheck    = nil   -- Checkbox: Popup aktiviert/deaktiviert
local selectedPrio   = nil   -- zuletzt geklickter Prio-Button-Index
local prioButtons    = {}
local rollBtn        = nil
local winnerLabel    = nil
local filterChecks   = {}    -- { key = CheckButton }
local autoCloseTimer = nil

-- col/row = explizite Gitterposition (3 Spalten, 4 Zeilen)
-- Spalte 0: Rüstungstypen | Spalte 1: Waffe/Schmuck | Spalte 2: Sonstiges
local FILTER_DEFS = {
    { key="cloth",           label="Cloth",              col=0, row=0 },
    { key="leather",         label="Leather",            col=0, row=1 },
    { key="mail",            label="Mail",               col=0, row=2 },
    { key="plate",           label="Plate",              col=0, row=3 },
    { key="nonUsableWeapon", label="non usable Weapons", col=1, row=0 },
    { key="trinket",         label="Trinkets",           col=1, row=1 },
    { key="ring",            label="Rings",              col=1, row=2 },
    { key="neck",            label="Necks",              col=1, row=3 },
    { key="other",           label="Other",              col=2, row=0 },
}

local FILTER_HELP = {
    cloth           = "Cloth armor (Mage, Priest, Warlock...)",
    leather         = "Leather armor (Druid, Rogue, Monk...)",
    mail            = "Mail armor (Hunter, Shaman, Evoker...)",
    plate           = "Plate armor (Warrior, Paladin, DK...)",
    nonUsableWeapon = "Weapons your class cannot equip",
    trinket         = "Trinkets",
    ring            = "Rings",
    neck            = "Neck pieces",
    other           = "All other item types",
}

-- ============================================================
-- Hilfsfunktionen
-- ============================================================

local function GetPrioCfg()
    local db = GuildLootDB
    if db.activeContainerIdx and db.raidContainers then
        local s = db.raidContainers[db.activeContainerIdx]
        if s and s.priorityConfig then return s.priorityConfig end
    end
    return db.settings.priorities
end

local function CancelAutoClose()
    if autoCloseTimer then autoCloseTimer:Cancel(); autoCloseTimer = nil end
end

local function ParseItemName(link)
    if not link then return "?" end
    return link:match("|h%[(.-)%]|h") or link:match("^%[(.-)%]$") or link
end

--- Gibt zurück ob das Popup aktiviert ist (nil = auto: Raid → an, sonst aus).
local function IsPopupEnabled()
    local v = GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.popupEnabled
    if v == nil then return IsInRaid() end
    return v
end

-- ============================================================
-- Help-Panel aufbauen (einmalig)
-- ============================================================

local function BuildHelpPanel()
    if helpPanel then return end

    helpPanel = CreateFrame("Frame", "GuildLootPlayerHelpPanel", UIParent, "BackdropTemplate")
    helpPanel:SetSize(230, 200)   -- Höhe wird dynamisch gesetzt beim Öffnen
    helpPanel:SetFrameStrata("HIGH")
    helpPanel:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 },
    })
    helpPanel:SetBackdropColor(0, 0, 0, 0.9)
    helpPanel:Hide()

    -- Titel
    local title = helpPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", helpPanel, "TOPLEFT", 16, -12)
    title:SetText("|cffffcc00Announce Filter|r")

    -- Divider
    local div = helpPanel:CreateTexture(nil, "BACKGROUND")
    div:SetColorTexture(0.4, 0.4, 0.4, 1)
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  helpPanel, "TOPLEFT",  16, -28)
    div:SetPoint("TOPRIGHT", helpPanel, "TOPRIGHT", -16, -28)

    -- Filter-Beschreibungen
    local y = -38
    for _, def in ipairs(FILTER_DEFS) do
        local nameLbl = helpPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("TOPLEFT", helpPanel, "TOPLEFT", 16, y)
        nameLbl:SetText("|cffffcc00" .. def.label .. ":|r")

        local descLbl = helpPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        descLbl:SetPoint("TOPLEFT", helpPanel, "TOPLEFT", 16, y - 13)
        descLbl:SetPoint("TOPRIGHT", helpPanel, "TOPRIGHT", -16, y - 13)
        descLbl:SetJustifyH("LEFT")
        descLbl:SetTextColor(0.7, 0.7, 0.7)
        descLbl:SetText(FILTER_HELP[def.key] or "")

        y = y - 30
    end

    -- Hinweis unten
    local hint = helpPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT",  helpPanel, "TOPLEFT",  16, y - 4)
    hint:SetPoint("TOPRIGHT", helpPanel, "TOPRIGHT", -16, y - 4)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.5, 0.8, 0.5)
    hint:SetText("Usable weapons always appear regardless of filter.")

    -- Gesamthöhe setzen
    helpPanel:SetHeight(-(y - 4) + 16 + 4)
end

-- ============================================================
-- Frame aufbauen (einmalig beim ersten Aufruf)
-- ============================================================

local function BuildPopup()
    if popup then return end

    popup = CreateFrame("Frame", "GuildLootPlayerPopup", UIParent, "BackdropTemplate")
    popup:SetSize(340, 220)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    popup:SetFrameStrata("HIGH")
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop",  popup.StopMovingOrSizing)
    popup:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 },
    })
    popup:SetBackdropColor(0, 0, 0, 0.9)
    popup:Hide()

    -- Titel-Bar (ziehbar)
    local titleBar = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleBar:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -10)
    titleBar:SetText("|cffffcc00Loot Announce|r")

    -- Item-Icon mit Tooltip (gleiche Pattern wie Loot-Tab)
    local iconBtn = CreateFrame("Frame", nil, popup)
    iconBtn:SetSize(36, 36)
    iconBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -28)
    iconBtn:EnableMouse(true)
    local icon = iconBtn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconBtn:SetScript("OnEnter", function(self)
        if popup._link and popup._link:find("|H") then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(popup._link)
            GameTooltip:Show()
        end
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    popup.itemIcon = icon
    popup.itemIconBtn = iconBtn

    -- Item-Link Button (Tooltip)
    local linkBtn = CreateFrame("Button", nil, popup)
    linkBtn:SetSize(260, 36)
    linkBtn:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    local linkLbl = linkBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    linkLbl:SetAllPoints()
    linkLbl:SetJustifyH("LEFT")
    linkLbl:SetWordWrap(false)
    popup.linkLabel = linkLbl
    popup.linkBtn   = linkBtn
    linkBtn:SetScript("OnEnter", function(self)
        if popup._link and popup._link:find("|H") then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetHyperlink(popup._link)
            GameTooltip:Show()
        end
    end)
    linkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    linkBtn:SetScript("OnClick", function()
        if popup._link and popup._link:find("|H") then
            ChatEdit_InsertLink(popup._link)
        end
    end)

    -- Divider 1
    local div1 = popup:CreateTexture(nil, "BACKGROUND")
    div1:SetColorTexture(0.4, 0.4, 0.4, 1)
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT",  popup, "TOPLEFT",  16, -72)
    div1:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -16, -72)

    -- Prio-Label
    local prioLbl = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    prioLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -82)
    prioLbl:SetText("|cffaaaaaa Priority:|r")

    -- Prio-Buttons (5 Stück)
    local btnW = 56
    local btnH = 22
    local btnY = -98
    for i = 1, 5 do
        local btn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        btn:SetSize(btnW, btnH)
        btn:SetPoint("TOPLEFT", popup, "TOPLEFT", 16 + (i - 1) * (btnW + 4), btnY)
        btn:SetText(tostring(i))
        btn:SetScript("OnClick", function()
            if not btn:IsEnabled() then return end
            selectedPrio = i
            for j, b in ipairs(prioButtons) do
                b:SetAlpha(j == i and 1.0 or 0.6)
            end
            local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or "SAY"
            SendChatMessage(tostring(i), channel)
        end)
        prioButtons[i] = btn
    end

    -- Divider 2
    local div2 = popup:CreateTexture(nil, "BACKGROUND")
    div2:SetColorTexture(0.4, 0.4, 0.4, 1)
    div2:SetHeight(1)
    div2:SetPoint("TOPLEFT",  popup, "TOPLEFT",  16, -128)
    div2:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -16, -128)

    -- Roll-Button
    rollBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    rollBtn:SetSize(100, 22)
    rollBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -138)
    rollBtn:SetText("Roll")
    rollBtn:SetEnabled(false)
    rollBtn:SetAlpha(0.4)
    rollBtn:SetScript("OnClick", function()
        RandomRoll(1, 100)
        rollBtn:SetEnabled(false)
        rollBtn:SetAlpha(0.4)
        rollBtn:SetText("Rolled")
    end)

    -- Gewinner-Label (versteckt bis ASSIGN mit eigenem Namen)
    winnerLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    winnerLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -138)
    winnerLabel:SetWidth(300)
    winnerLabel:SetJustifyH("LEFT")
    winnerLabel:Hide()

    -- ── Top-Right Button-Leiste: [✕ Close] [? Help] [☑ Enable] ──────────────

    -- Schließen-Button (ganz rechts)
    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        -- Verzögerten Clear-Timer abbrechen falls Gewinner-Popup früh geschlossen wird
        if GL.Loot and GL.Loot.CancelPendingClear then GL.Loot.CancelPendingClear() end
        if helpPanel then helpPanel:Hide() end
        popup:Hide()
        -- minimized zurücksetzen damit Toggle() beim nächsten Minimap-Klick korrekt öffnet
        if GuildLootDB and GuildLootDB.settings then
            GuildLootDB.settings.minimized = true
        end
    end)

    -- "?"-Button (links vom Close)
    BuildHelpPanel()
    local helpBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    helpBtn:SetSize(22, 22)
    helpBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -28, -5)
    helpBtn:SetText("i")
    helpBtn:SetScript("OnClick", function()
        if helpPanel:IsShown() then
            helpPanel:Hide()
        else
            helpPanel:SetHeight(popup:GetHeight())
            helpPanel:ClearAllPoints()
            helpPanel:SetPoint("TOPLEFT", popup, "TOPRIGHT", 4, 0)
            helpPanel:Show()
        end
    end)

    -- Enable-Checkbox (links vom "?")
    enableCheck = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
    enableCheck:SetSize(22, 22)
    enableCheck:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -52, -5)
    enableCheck:SetScript("OnClick", function(self)
        GuildLootDB.settings.popupEnabled = self:GetChecked()
    end)
    -- Tooltip für die Checkbox
    enableCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Popup enabled", 1, 1, 1)
        GameTooltip:AddLine("Uncheck to suppress automatic\nloot announcements.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    enableCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Announce-Filter Sektion ───────────────────────────────────────────────

    local filterLbl = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -168)
    filterLbl:SetText("|cffaaaaaa Announce Filter:|r")

    local COL_X = { [0]=0, [1]=110, [2]=260 }
    local maxRow = 0
    for _, def in ipairs(FILTER_DEFS) do
        local cb = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", popup, "TOPLEFT", 16 + COL_X[def.col], -182 - def.row * 22)
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(def.label)
        cb:SetScript("OnClick", function(self)
            local f = GuildLootDB.settings.announceFilter
            if f then f[def.key] = self:GetChecked() end
        end)
        filterChecks[def.key] = cb
        if def.row > maxRow then maxRow = def.row end
    end

    -- Frame-Höhe an Filter anpassen
    popup:SetHeight(190 + (maxRow + 1) * 22 + 10)
end

-- ============================================================
-- Filter-Checkboxen aktualisieren
-- ============================================================

local function RefreshFilterChecks()
    local f = GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.announceFilter or {}
    for key, cb in pairs(filterChecks) do
        cb:SetChecked(f[key] ~= false)
    end
end

local function RefreshEnableCheck()
    if enableCheck then
        enableCheck:SetChecked(IsPopupEnabled())
    end
end

-- ============================================================
-- Public API
-- ============================================================

--- Popup anzeigen wenn ITEM_ON empfangen (Observer + Player).
--- Respektiert popupEnabled-Setting — gibt sofort zurück wenn deaktiviert.
function UI.ShowPlayerPopup(link, category)
    -- Guard: popupEnabled prüfen (nil = auto, NICHT speichern)
    -- forcePlayerMode überspringt den Guard (Dev-Test)
    local s = GuildLootDB and GuildLootDB.settings
    if s and not s.forcePlayerMode then
        local enabled = s.popupEnabled
        if enabled == nil then
            enabled = IsInRaid()  -- auto: Raid → an, Gruppe/Solo → aus
        end
        if not enabled then return end
    end

    BuildPopup()
    CancelAutoClose()

    popup._link = link
    selectedPrio = nil

    -- Alle Elemente sichtbar schalten (nach evt. FilterOnly-Modus)
    popup.itemIconBtn:Show()
    for _, btn in ipairs(prioButtons) do btn:Show() end
    rollBtn:Show()

    -- Icon setzen
    local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(link)
    if texture then
        popup.itemIcon:SetTexture(texture)
    else
        popup.itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Item-Name farbig
    popup.linkLabel:SetText(GL.ColoredItemName(link))

    -- Prio-Buttons auffrischen (dynamische Breite basierend auf Text)
    local cfg = GetPrioCfg()
    local MIN_BTN_W = 56
    local BTN_PAD   = 16
    local BTN_GAP   = 4
    local xOff = 16
    for i, btn in ipairs(prioButtons) do
        local prio   = cfg and cfg[i]
        local active = prio and prio.active
        local label  = (prio and prio.shortName ~= "") and prio.shortName or tostring(i)
        btn:SetText(label)
        btn:SetEnabled(active == true)
        btn:SetAlpha(active and 1.0 or 0.3)
        local textW = btn:GetFontString():GetStringWidth()
        local btnW  = math.max(MIN_BTN_W, math.ceil(textW) + BTN_PAD)
        btn:SetSize(btnW, 22)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", popup, "TOPLEFT", xOff, -98)
        xOff = xOff + btnW + BTN_GAP
    end
    -- Frame-Breite an Buttons anpassen
    local requiredW = math.max(340, xOff - BTN_GAP + 16)
    popup:SetWidth(requiredW)

    -- Roll-Button zurücksetzen
    rollBtn:SetEnabled(false)
    rollBtn:SetAlpha(0.4)
    rollBtn:SetText("Roll")
    rollBtn:Show()
    winnerLabel:Hide()

    RefreshFilterChecks()
    RefreshEnableCheck()
    popup:Show()
end

--- Popup ausblenden (ITEM_OFF).
function UI.HidePlayerPopup()
    if popup then
        CancelAutoClose()
        -- Verzögerten Clear-Timer abbrechen falls Gewinner-Popup früh geschlossen wird
        if GL.Loot and GL.Loot.CancelPendingClear then GL.Loot.CancelPendingClear() end
        if helpPanel then helpPanel:Hide() end
        popup:Hide()
    end
end

--- Roll-Button aktivieren wenn ROLL_START und Spieler in der Liste.
function UI.EnablePlayerPopupRoll()
    if not popup or not popup:IsShown() then return end
    rollBtn:SetEnabled(true)
    rollBtn:SetAlpha(1.0)
    rollBtn:SetText("Roll")
end

--- Filter-Only-Ansicht: Popup ohne aktives Item zeigen (Dock-Klick im Player-Mode).
--- Ignoriert popupEnabled — manuelles Öffnen funktioniert immer.
function UI.ShowPlayerPopupFilterOnly()
    BuildPopup()
    CancelAutoClose()
    popup._link = nil

    -- Item-Bereich ausblenden
    popup.itemIconBtn:Hide()
    popup.linkLabel:SetText("|cff888888No item announced|r")
    for _, btn in ipairs(prioButtons) do btn:Hide() end
    rollBtn:Hide()
    winnerLabel:Hide()

    RefreshFilterChecks()
    RefreshEnableCheck()
    popup:Show()
end

--- Gewinner-Anzeige wenn lokaler Spieler das Item bekommt (ASSIGN).
function UI.ShowPlayerPopupWin(link)
    if not popup then return end
    BuildPopup()
    CancelAutoClose()

    rollBtn:Hide()
    winnerLabel:SetText("|cff00ff00You receive:|r " .. GL.ColoredItemName(link))
    winnerLabel:Show()
    popup:Show()

    -- Auto-Close nach 6 Sekunden
    autoCloseTimer = C_Timer.NewTimer(6, function()
        if helpPanel then helpPanel:Hide() end
        popup:Hide()
        autoCloseTimer = nil
    end)
end
