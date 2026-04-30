-- GuildLoot – UI_RollTab.lua
-- Roll-Tab im Hauptfenster: Prio-Buttons, Roll-Button, Gewinner-Anzeige für Observer.
-- Verhält sich identisch zum Player-Popup (gleicher Filter, gleicher Stale-Guard).

local GL = GuildLoot
local UI = GL.UI

-- ============================================================
-- Interner Zustand
-- ============================================================

local rollPanel    = nil  -- content-Frame (Parent: contentFrame)
local tabPrioButtons = {}
local tabRollBtn   = nil
local tabWinLabel  = nil
local tabLink      = nil  -- aktuell angezeigtes Item

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

-- ============================================================
-- Frame aufbauen (einmalig)
-- ============================================================

function UI.BuildRollTab(parent)
    if rollPanel then return rollPanel end

    rollPanel = CreateFrame("Frame", nil, parent)
    rollPanel:SetAllPoints()
    rollPanel:Hide()

    -- Item-Icon
    local iconBtn = CreateFrame("Frame", nil, rollPanel)
    iconBtn:SetSize(48, 48)
    iconBtn:SetPoint("TOPLEFT", rollPanel, "TOPLEFT", 16, -16)
    iconBtn:EnableMouse(true)
    local icon = iconBtn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconBtn:SetScript("OnEnter", function(self)
        if tabLink and tabLink:find("|H") then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(tabLink)
            GameTooltip:Show()
        end
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rollPanel.itemIcon    = icon
    rollPanel.itemIconBtn = iconBtn

    -- Item-Name (farbig, klickbar für Chat-Insert)
    local nameLbl = CreateFrame("Button", nil, rollPanel)
    nameLbl:SetPoint("TOPLEFT",  iconBtn, "TOPRIGHT",    10, 0)
    nameLbl:SetPoint("TOPRIGHT", rollPanel, "TOPRIGHT", -16, -16)
    nameLbl:SetHeight(48)
    local nameFS = nameLbl:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameFS:SetAllPoints()
    nameFS:SetJustifyH("LEFT")
    nameFS:SetJustifyV("TOP")
    nameFS:SetWordWrap(false)
    rollPanel.nameLabel = nameFS
    nameLbl:SetScript("OnClick", function()
        if tabLink and tabLink:find("|H") then ChatEdit_InsertLink(tabLink) end
    end)
    nameLbl:SetScript("OnEnter", function(self)
        if tabLink and tabLink:find("|H") then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetHyperlink(tabLink)
            GameTooltip:Show()
        end
    end)
    nameLbl:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Divider
    local div1 = rollPanel:CreateTexture(nil, "BACKGROUND")
    div1:SetColorTexture(0.4, 0.4, 0.4, 1)
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT",  rollPanel, "TOPLEFT",  16, -76)
    div1:SetPoint("TOPRIGHT", rollPanel, "TOPRIGHT", -16, -76)

    -- Prio-Label
    local prioLbl = rollPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    prioLbl:SetPoint("TOPLEFT", rollPanel, "TOPLEFT", 16, -86)
    prioLbl:SetText("|cffaaaaaa Priority:|r")

    -- Prio-Buttons (dynamische Breite wie im Popup)
    local MIN_BTN_W = 56
    local BTN_PAD   = 16
    local BTN_GAP   = 4
    local BTN_Y     = -102
    for i = 1, 5 do
        local btn = CreateFrame("Button", nil, rollPanel, "UIPanelButtonTemplate")
        btn:SetSize(MIN_BTN_W, 22)
        btn:SetPoint("TOPLEFT", rollPanel, "TOPLEFT", 16 + (i - 1) * (MIN_BTN_W + BTN_GAP), BTN_Y)
        btn:SetText(tostring(i))
        btn:SetScript("OnClick", function()
            if not btn:IsEnabled() then return end
            for _, b in ipairs(tabPrioButtons) do b:SetAlpha(0.6) end
            btn:SetAlpha(1.0)
            local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or "SAY"
            SendChatMessage(tostring(i), channel)
        end)
        tabPrioButtons[i] = btn
    end

    -- Divider 2
    local div2 = rollPanel:CreateTexture(nil, "BACKGROUND")
    div2:SetColorTexture(0.4, 0.4, 0.4, 1)
    div2:SetHeight(1)
    div2:SetPoint("TOPLEFT",  rollPanel, "TOPLEFT",  16, -132)
    div2:SetPoint("TOPRIGHT", rollPanel, "TOPRIGHT", -16, -132)

    -- Roll-Button
    tabRollBtn = CreateFrame("Button", nil, rollPanel, "UIPanelButtonTemplate")
    tabRollBtn:SetSize(120, 26)
    tabRollBtn:SetPoint("TOPLEFT", rollPanel, "TOPLEFT", 16, -142)
    tabRollBtn:SetText("Roll")
    tabRollBtn:SetEnabled(false)
    tabRollBtn:SetAlpha(0.4)
    tabRollBtn:SetScript("OnClick", function()
        RandomRoll(1, 100)
        tabRollBtn:SetEnabled(false)
        tabRollBtn:SetAlpha(0.4)
        tabRollBtn:SetText("Rolled")
    end)

    -- Gewinner-Label
    tabWinLabel = rollPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tabWinLabel:SetPoint("TOPLEFT", rollPanel, "TOPLEFT", 16, -142)
    tabWinLabel:SetWidth(400)
    tabWinLabel:SetJustifyH("LEFT")
    tabWinLabel:Hide()

    -- Leer-Zustand Label
    rollPanel.emptyLabel = rollPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rollPanel.emptyLabel:SetPoint("CENTER", rollPanel, "CENTER", 0, 40)
    rollPanel.emptyLabel:SetTextColor(0.5, 0.5, 0.5)
    rollPanel.emptyLabel:SetText("No item announced")

    UI.rollPanel = rollPanel
    return rollPanel
end

-- ============================================================
-- Prio-Buttons Refresh (Breite + Label + aktiv/inaktiv)
-- ============================================================

local function RefreshPrioButtons()
    local cfg = GetPrioCfg()
    local MIN_BTN_W = 56
    local BTN_PAD   = 16
    local BTN_GAP   = 4
    local xOff = 16
    for i, btn in ipairs(tabPrioButtons) do
        local prio   = cfg and cfg[i]
        local active = prio and prio.active
        local label  = (prio and prio.shortName ~= "") and prio.shortName or tostring(i)
        btn:SetText(label)
        btn:SetEnabled(active == true)
        btn:SetAlpha(active and 0.8 or 0.3)
        local textW = btn:GetFontString():GetStringWidth()
        local btnW  = math.max(MIN_BTN_W, math.ceil(textW) + BTN_PAD)
        btn:SetSize(btnW, 22)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", rollPanel, "TOPLEFT", xOff, -102)
        xOff = xOff + btnW + BTN_GAP
    end
end

-- ============================================================
-- Öffentliche API
-- ============================================================

--- Item anzeigen und Roll-Tab in den Vordergrund bringen (Observer-seitig).
function UI.UpdateRollTab(link, category)
    if not rollPanel then return end
    if GL.IsPlayerMode() then return end  -- Player-Mode-User bekommen das Popup

    tabLink = link

    -- Item-Icon
    local texture = select(10, GetItemInfo(link))
    if texture then
        rollPanel.itemIcon:SetTexture(texture)
    else
        rollPanel.itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Name farbig
    rollPanel.nameLabel:SetText(GL.ColoredItemName(link))
    rollPanel.emptyLabel:Hide()
    rollPanel.itemIconBtn:Show()

    -- Prio-Buttons
    RefreshPrioButtons()

    -- Roll-Button zurücksetzen
    tabRollBtn:SetEnabled(false)
    tabRollBtn:SetAlpha(0.4)
    tabRollBtn:SetText("Roll")
    tabRollBtn:Show()
    tabWinLabel:Hide()

    -- Auto-Switch zum Roll-Tab
    if GuildLootDB.settings.minimized then
        UI.Undock()  -- öffnet Hauptfenster; überschreiben wir danach
    end
    if UI.IsMainFrameShown() then
        UI.ShowTab(UI.TAB_ROLL)
    end
end

--- Roll-Button aktivieren wenn der lokale Spieler in der Roll-Liste ist (ROLL_START).
function UI.EnableRollTabRoll()
    if not rollPanel or not rollPanel:IsShown() then return end
    tabRollBtn:SetEnabled(true)
    tabRollBtn:SetAlpha(1.0)
    tabRollBtn:SetText("Roll")
end

--- Gewinner-Anzeige wenn lokaler Spieler das Item bekommt (ASSIGN).
function UI.ShowRollTabWin(link)
    if not rollPanel then return end
    tabRollBtn:Hide()
    tabWinLabel:SetText("|cff00ff00You receive:|r " .. GL.ColoredItemName(link))
    tabWinLabel:Show()
end

--- Tab-Inhalt leeren nach ITEM_OFF oder ASSIGN.
function UI.ClearRollTab()
    if not rollPanel then return end
    tabLink = nil
    rollPanel.nameLabel:SetText("")
    rollPanel.itemIcon:SetTexture(nil)
    rollPanel.emptyLabel:Show()
    rollPanel.itemIconBtn:Hide()
    for _, btn in ipairs(tabPrioButtons) do
        btn:SetEnabled(false)
        btn:SetAlpha(0.3)
    end
    tabRollBtn:SetEnabled(false)
    tabRollBtn:SetAlpha(0.4)
    tabRollBtn:SetText("Roll")
    tabRollBtn:Show()
    tabWinLabel:Hide()
end
