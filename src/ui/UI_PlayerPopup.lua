-- GuildLoot – UI_PlayerPopup.lua
-- Loot-Popup für Observer und Player: Prio-Buttons, Roll-Button, Announce-Filter.
-- Wird durch ITEM_ON angezeigt, durch ITEM_OFF/ASSIGN wieder ausgeblendet.

local GL = GuildLoot
local UI = GL.UI

-- ============================================================
-- Interner Zustand
-- ============================================================

local popup          = nil   -- das Frame
local selectedPrio   = nil   -- zuletzt geklickter Prio-Button-Index
local prioButtons    = {}
local rollBtn        = nil
local winnerLabel    = nil
local filterChecks   = {}    -- { key = CheckButton }
local autoCloseTimer = nil

local FILTER_DEFS = {
    { key="cloth",   label="Stoff"   },
    { key="leather", label="Leder"   },
    { key="mail",    label="Kette"   },
    { key="plate",   label="Platte"  },
    { key="jewelry", label="Schmuck" },
    { key="weapon",  label="Waffe"   },
    { key="other",   label="Sonstiges" },
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
    titleBar:SetText("|cffffcc00Loot-Announce|r")

    -- Item-Icon
    local icon = popup:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -28)
    popup.itemIcon = icon

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
    prioLbl:SetText("|cffaaaaaa Priorität:|r")

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
            -- Visuelles Feedback: gedrückter Button heller
            for j, b in ipairs(prioButtons) do
                if j == i then
                    b:SetAlpha(1.0)
                else
                    b:SetAlpha(0.6)
                end
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
    rollBtn:SetText("🎲 Roll")
    rollBtn:SetEnabled(false)
    rollBtn:SetAlpha(0.4)
    rollBtn:SetScript("OnClick", function()
        RandomRoll(1, 100)
        rollBtn:SetEnabled(false)
        rollBtn:SetAlpha(0.4)
        rollBtn:SetText("Gerollt")
    end)

    -- Gewinner-Label (versteckt bis ASSIGN mit eigenem Namen)
    winnerLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    winnerLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -138)
    winnerLabel:SetWidth(300)
    winnerLabel:SetJustifyH("LEFT")
    winnerLabel:Hide()

    -- Schließen-Button
    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Announce-Filter Sektion
    local filterLbl = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -168)
    filterLbl:SetText("|cffaaaaaa Announce-Filter:|r")

    local colW = 100
    for idx, def in ipairs(FILTER_DEFS) do
        local col  = (idx - 1) % 3
        local row  = math.floor((idx - 1) / 3)
        local cb   = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", popup, "TOPLEFT", 16 + col * colW, -182 - row * 22)
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(def.label)
        cb:SetScript("OnClick", function(self)
            local f = GuildLootDB.settings.announceFilter
            if f then f[def.key] = self:GetChecked() end
        end)
        filterChecks[def.key] = cb
    end

    -- Frame-Höhe an Filter anpassen
    local rows = math.ceil(#FILTER_DEFS / 3)
    popup:SetHeight(190 + rows * 22 + 10)
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

-- ============================================================
-- Public API
-- ============================================================

--- Popup anzeigen wenn ITEM_ON empfangen (Observer + Player).
function UI.ShowPlayerPopup(link, category)
    BuildPopup()
    CancelAutoClose()

    popup._link = link
    selectedPrio = nil

    -- Alle Elemente sichtbar schalten (nach evt. FilterOnly-Modus)
    popup.itemIcon:Show()
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
    local itemName = ParseItemName(link)
    popup.linkLabel:SetText("|cffA335EE" .. itemName .. "|r")

    -- Prio-Buttons auffrischen
    local cfg = GetPrioCfg()
    for i, btn in ipairs(prioButtons) do
        local prio = cfg and cfg[i]
        local active = prio and prio.active
        local label  = (prio and prio.shortName ~= "") and prio.shortName or tostring(i)
        btn:SetText(label)
        btn:SetEnabled(active == true)
        btn:SetAlpha(active and 1.0 or 0.3)
    end

    -- Roll-Button zurücksetzen
    rollBtn:SetEnabled(false)
    rollBtn:SetAlpha(0.4)
    rollBtn:SetText("🎲 Roll")
    rollBtn:Show()
    winnerLabel:Hide()

    RefreshFilterChecks()
    popup:Show()
end

--- Popup ausblenden (ITEM_OFF).
function UI.HidePlayerPopup()
    if popup then
        CancelAutoClose()
        popup:Hide()
    end
end

--- Roll-Button aktivieren wenn ROLL_START und Spieler in der Liste.
function UI.EnablePlayerPopupRoll()
    if not popup or not popup:IsShown() then return end
    rollBtn:SetEnabled(true)
    rollBtn:SetAlpha(1.0)
    rollBtn:SetText("🎲 Roll")
end

--- Filter-Only-Ansicht: Popup ohne aktives Item zeigen (Dock-Klick im Player-Mode).
function UI.ShowPlayerPopupFilterOnly()
    BuildPopup()
    CancelAutoClose()
    popup._link = nil

    -- Item-Bereich ausblenden
    popup.itemIcon:Hide()
    popup.linkLabel:SetText("|cff888888Kein Item announced|r")
    for _, btn in ipairs(prioButtons) do btn:Hide() end
    rollBtn:Hide()
    winnerLabel:Hide()

    RefreshFilterChecks()
    popup:Show()
end

--- Gewinner-Anzeige wenn lokaler Spieler das Item bekommt (ASSIGN).
function UI.ShowPlayerPopupWin(link)
    if not popup then return end
    BuildPopup()
    CancelAutoClose()

    local itemName = ParseItemName(link)
    rollBtn:Hide()
    winnerLabel:SetText("|cff00ff00Du bekommst:|r " .. "|cffA335EE" .. itemName .. "|r")
    winnerLabel:Show()
    popup:Show()

    -- Auto-Close nach 6 Sekunden
    autoCloseTimer = C_Timer.NewTimer(6, function()
        popup:Hide()
        autoCloseTimer = nil
    end)
end
