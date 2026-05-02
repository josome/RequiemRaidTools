-- GuildLoot – UI_LootAnnounceWidget.lua
-- Gemeinsames Loot-Announce-Widget für Popup (Raider) und Roll-Tab (Observer).
-- Baut Icon, Item-Name, Prio-Buttons, Roll-Button, Gewinner-Label und Announce-Filter
-- in einen beliebigen Parent-Frame ein.

local GL = GuildLoot
local UI = GL.UI

-- ============================================================
-- Gemeinsame Konstanten (auch von außen nutzbar)
-- ============================================================

UI.FILTER_DEFS = {
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

local function GetPrioCfg()
    local db = GuildLootDB
    if db.activeContainerIdx and db.raidContainers then
        local s = db.raidContainers[db.activeContainerIdx]
        if s and s.priorityConfig then return s.priorityConfig end
    end
    return db.settings.priorities
end

-- ============================================================
-- Widget-Konstruktor
-- ============================================================

--- Baut das gemeinsame Loot-Announce-UI in parent und gibt ein Widget-Objekt zurück.
--- @param parent  Frame   Parent-Frame (Popup-Frame oder Roll-Tab-Panel)
--- @param yStart  number  Y-Offset des obersten Elements relativ zu parent (default: -16)
function UI.BuildLootAnnounceWidget(parent, yStart)
    yStart = yStart or -16

    local w            = {}
    local prioButtons  = {}
    local rollBtn, winnerLabel
    local filterChecks = {}

    -- Berechnete Y-Positionen (alle relativ zu parent TOPLEFT)
    local ICON_Y    = yStart
    local DIV1_Y    = yStart - 60   -- nach Icon (48px) + 12px Gap
    local PRIO_LBL_Y = DIV1_Y - 10
    local PRIO_Y    = DIV1_Y - 26
    local DIV2_Y    = PRIO_Y - 30   -- nach Prio-Buttons (22px) + 8px Gap
    local ROLL_Y    = DIV2_Y - 10
    local DIV3_Y    = ROLL_Y - 36   -- nach Roll-Button (22px) + 14px Gap
    local FILT_LBL_Y = DIV3_Y - 10
    local FILT_Y    = DIV3_Y - 26

    -- ── Item-Icon ─────────────────────────────────────────────
    local iconBtn = CreateFrame("Frame", nil, parent)
    iconBtn:SetSize(48, 48)
    iconBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, ICON_Y)
    iconBtn:EnableMouse(true)
    local icon = iconBtn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconBtn:SetScript("OnEnter", function(self)
        if w._link and w._link:find("|H") then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(w._link)
            GameTooltip:Show()
        end
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Item-Name (farbig, klickbar für Chat-Insert) ──────────
    local nameBtn = CreateFrame("Button", nil, parent)
    nameBtn:SetPoint("TOPLEFT",  iconBtn, "TOPRIGHT",  10, 0)
    nameBtn:SetPoint("TOPRIGHT", parent,  "TOPRIGHT", -16, ICON_Y)
    nameBtn:SetHeight(48)
    local nameFS = nameBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameFS:SetAllPoints()
    nameFS:SetJustifyH("LEFT")
    nameFS:SetJustifyV("TOP")
    nameFS:SetWordWrap(false)
    nameBtn:SetScript("OnClick", function()
        if w._link and w._link:find("|H") then ChatEdit_InsertLink(w._link) end
    end)
    nameBtn:SetScript("OnEnter", function(self)
        if w._link and w._link:find("|H") then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetHyperlink(w._link)
            GameTooltip:Show()
        end
    end)
    nameBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Divider 1 ─────────────────────────────────────────────
    local div1 = parent:CreateTexture(nil, "BACKGROUND")
    div1:SetColorTexture(0.4, 0.4, 0.4, 1)
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT",  parent, "TOPLEFT",  16, DIV1_Y)
    div1:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, DIV1_Y)

    -- ── Prio-Label ────────────────────────────────────────────
    local prioLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    prioLbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, PRIO_LBL_Y)
    prioLbl:SetText("|cffaaaaaa Priority:|r")

    -- ── Prio-Buttons (5 Stück, dynamische Breite) ─────────────
    for i = 1, 5 do
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetSize(56, 22)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 16 + (i - 1) * 60, PRIO_Y)
        btn:SetText(tostring(i))
        btn:SetScript("OnClick", function()
            if not btn:IsEnabled() then return end
            for _, b in ipairs(prioButtons) do b:SetAlpha(0.6) end
            btn:SetAlpha(1.0)
            local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or "SAY"
            SendChatMessage(tostring(i), channel)
        end)
        prioButtons[i] = btn
    end

    -- ── Divider 2 ─────────────────────────────────────────────
    local div2 = parent:CreateTexture(nil, "BACKGROUND")
    div2:SetColorTexture(0.4, 0.4, 0.4, 1)
    div2:SetHeight(1)
    div2:SetPoint("TOPLEFT",  parent, "TOPLEFT",  16, DIV2_Y)
    div2:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, DIV2_Y)

    -- ── Roll-Button ───────────────────────────────────────────
    rollBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    rollBtn:SetSize(100, 22)
    rollBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, ROLL_Y)
    rollBtn:SetText("Roll")
    rollBtn:SetEnabled(false)
    rollBtn:SetAlpha(0.4)
    rollBtn:SetScript("OnClick", function()
        RandomRoll(1, 100)
        rollBtn:SetEnabled(false)
        rollBtn:SetAlpha(0.4)
        rollBtn:SetText("Rolled")
    end)

    -- ── Gewinner-Label ────────────────────────────────────────
    winnerLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    winnerLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, ROLL_Y)
    winnerLabel:SetWidth(400)
    winnerLabel:SetJustifyH("LEFT")
    winnerLabel:Hide()

    -- ── Divider 3 ─────────────────────────────────────────────
    local div3 = parent:CreateTexture(nil, "BACKGROUND")
    div3:SetColorTexture(0.4, 0.4, 0.4, 1)
    div3:SetHeight(1)
    div3:SetPoint("TOPLEFT",  parent, "TOPLEFT",  16, DIV3_Y)
    div3:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, DIV3_Y)

    -- ── Filter-Label ──────────────────────────────────────────
    local filterLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, FILT_LBL_Y)
    filterLbl:SetText("|cffaaaaaa Announce Filter:|r")

    -- ── Filter-Checkboxen (3-Spalten-Grid) ───────────────────
    local COL_X = { [0]=0, [1]=110, [2]=260 }
    for _, def in ipairs(UI.FILTER_DEFS) do
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 16 + COL_X[def.col], FILT_Y - def.row * 22)
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(def.label)
        cb:SetScript("OnClick", function(self)
            local f = GuildLootDB.settings.announceFilter
            if f then f[def.key] = self:GetChecked() end
        end)
        filterChecks[def.key] = cb
    end

    -- ============================================================
    -- Interne Hilfsfunktionen
    -- ============================================================

    local MIN_BTN_W = 56
    local BTN_PAD   = 16
    local BTN_GAP   = 4

    local function RefreshPrioButtons()
        local cfg  = GetPrioCfg()
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
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, PRIO_Y)
            xOff = xOff + btnW + BTN_GAP
        end
        w.requiredWidth = math.max(340, xOff - BTN_GAP + 16)
    end

    local function RefreshFilterChecks()
        local f = GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.announceFilter or {}
        for key, cb in pairs(filterChecks) do
            cb:SetChecked(f[key] ~= false)
        end
    end

    -- ============================================================
    -- Widget-Methoden
    -- ============================================================

    --- Item anzeigen: Icon, Name, Prio-Buttons auffrischen.
    function w:SetItem(link)
        w._link = link
        local texture = select(10, GetItemInfo(link))
        icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        iconBtn:Show()
        nameFS:SetText(GL.ColoredItemName(link))
        -- Alle Elemente sichtbar (nach evt. FilterOnly-Modus)
        for _, btn in ipairs(prioButtons) do btn:Show() end
        rollBtn:Show()
        winnerLabel:Hide()
        rollBtn:SetEnabled(false)
        rollBtn:SetAlpha(0.4)
        rollBtn:SetText("Roll")
        RefreshPrioButtons()
        RefreshFilterChecks()
    end

    --- Leer-Zustand: kein Item announced.
    function w:Clear()
        w._link = nil
        icon:SetTexture(nil)
        iconBtn:Hide()
        nameFS:SetText("|cff888888No item announced|r")
        for _, btn in ipairs(prioButtons) do
            btn:SetEnabled(false)
            btn:SetAlpha(0.3)
        end
        rollBtn:SetEnabled(false)
        rollBtn:SetAlpha(0.4)
        rollBtn:SetText("Roll")
        rollBtn:Show()
        winnerLabel:Hide()
        RefreshFilterChecks()
    end

    --- Filter-Only-Modus: Item-Bereich und Prio-Buttons ausblenden.
    function w:ShowFilterOnly()
        w._link = nil
        iconBtn:Hide()
        nameFS:SetText("|cff888888No item announced|r")
        for _, btn in ipairs(prioButtons) do btn:Hide() end
        rollBtn:Hide()
        winnerLabel:Hide()
        RefreshFilterChecks()
    end

    --- Roll-Button aktivieren (ROLL_START).
    function w:EnableRoll()
        rollBtn:SetEnabled(true)
        rollBtn:SetAlpha(1.0)
        rollBtn:SetText("Roll")
    end

    --- Gewinner-Anzeige (ASSIGN für lokalen Spieler).
    function w:ShowWin(link)
        rollBtn:Hide()
        winnerLabel:SetText("|cff00ff00You receive:|r " .. GL.ColoredItemName(link))
        winnerLabel:Show()
    end

    --- Prio-Buttons neu aufbauen (z.B. nach Prio-Config-Änderung).
    function w:RefreshPrios()
        RefreshPrioButtons()
    end

    --- Filter-Checkboxen aus DB neu lesen.
    function w:RefreshFilter()
        RefreshFilterChecks()
    end

    -- Initialer Zustand
    w:Clear()

    return w
end
