-- GuildLoot – UI_PlayerPopup.lua
-- Loot-Popup für Raider und Observer: Wrapper um UI_LootAnnounceWidget.
-- Popup-spezifisch: Frame, Drag, Titel, Close/Help/Enable-Buttons, auto-close Timer.

local GL = GuildLoot
local UI = GL.UI

-- ============================================================
-- Interner Zustand
-- ============================================================

local popup          = nil   -- das Frame
local helpPanel      = nil   -- Filter-Beschreibungs-Panel (links vom Popup)
local enableCheck    = nil   -- Checkbox: Popup aktiviert/deaktiviert
local widget         = nil   -- LootAnnounceWidget
local autoCloseTimer = nil

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

local function CancelAutoClose()
    if autoCloseTimer then autoCloseTimer:Cancel(); autoCloseTimer = nil end
end

--- Gibt zurück ob das Popup aktiviert ist (nil = auto: Raid → an, sonst aus).
local function IsPopupEnabled()
    local v = GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.popupEnabled
    if v == nil then return IsInRaid() end
    return v
end

local function RefreshEnableCheck()
    if enableCheck then enableCheck:SetChecked(IsPopupEnabled()) end
end

-- ============================================================
-- Help-Panel aufbauen (einmalig)
-- ============================================================

local function BuildHelpPanel()
    if helpPanel then return end

    local content
    helpPanel, content = UI.CreateSidePanel("GuildLootPlayerHelpPanel", UIParent, "Announce Filter")
    helpPanel:SetSize(230, 200)
    helpPanel:SetFrameStrata("HIGH")
    helpPanel:Hide()

    local y = -4
    for _, def in ipairs(UI.FILTER_DEFS) do
        local nameLbl = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 2, y)
        nameLbl:SetText("|cffffcc00" .. def.label .. ":|r")

        local descLbl = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        descLbl:SetPoint("TOPLEFT",  content, "TOPLEFT",  2, y - 13)
        descLbl:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, y - 13)
        descLbl:SetJustifyH("LEFT")
        descLbl:SetTextColor(0.7, 0.7, 0.7)
        descLbl:SetText(FILTER_HELP[def.key] or "")
        y = y - 30
    end

    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT",  content, "TOPLEFT",  2, y - 4)
    hint:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, y - 4)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.5, 0.8, 0.5)
    hint:SetText("Usable weapons always appear regardless of filter.")
    content:SetHeight(-(y - 4) + 8)
end

-- ============================================================
-- Popup-Frame aufbauen (einmalig)
-- ============================================================

local function BuildPopup()
    if popup then return end

    popup = CreateFrame("Frame", "GuildLootPlayerPopup", UIParent, "BackdropTemplate")
    popup:SetSize(340, 380)
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

    -- Titelzeile
    local titleBar = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleBar:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -10)
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata("RequiemRaidTools", "Version")) or "?"
    titleBar:SetText("|cffffcc00Loot Announce|r |cff888888v" .. version .. "|r")

    -- ── Top-Right: [✕ Close] [i Help] [☑ Enable] ─────────────

    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        if GL.Loot and GL.Loot.CancelPendingClear then GL.Loot.CancelPendingClear() end
        if helpPanel then helpPanel:Hide() end
        popup:Hide()
        if GuildLootDB and GuildLootDB.settings then
            GuildLootDB.settings.minimized = true
        end
    end)

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

    enableCheck = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
    enableCheck:SetSize(22, 22)
    enableCheck:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -52, -5)
    enableCheck:SetScript("OnClick", function(self)
        GuildLootDB.settings.popupEnabled = self:GetChecked()
    end)
    enableCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Popup enabled", 1, 1, 1)
        GameTooltip:AddLine("Uncheck to suppress automatic\nloot announcements.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    enableCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Gemeinsames Widget (yStart=-28: unterhalb der Titelzeile) ─
    widget = UI.BuildLootAnnounceWidget(popup, -28)

    -- Popup-Höhe ans Widget anpassen (4 Filter-Zeilen + Puffer)
    popup:SetHeight(28 + 60 + 26 + 30 + 10 + 36 + 26 + (4 * 22) + 20)
end

-- ============================================================
-- Public API
-- ============================================================

--- Popup anzeigen wenn ITEM_ON empfangen (Raider + Observer).
function UI.ShowPlayerPopup(link, category)
    local s = GuildLootDB and GuildLootDB.settings
    if s and not s.forcePlayerMode then
        local enabled = s.popupEnabled
        if enabled == nil then enabled = IsInRaid() end
        if not enabled then return end
    end

    BuildPopup()
    CancelAutoClose()
    widget:SetItem(link)

    -- Frame-Breite an Prio-Button-Breite anpassen
    popup:SetWidth(math.max(340, (widget.requiredWidth or 340)))

    RefreshEnableCheck()
    popup:Show()
end

--- Popup ausblenden (ITEM_OFF).
function UI.HidePlayerPopup()
    if popup then
        CancelAutoClose()
        if GL.Loot and GL.Loot.CancelPendingClear then GL.Loot.CancelPendingClear() end
        if helpPanel then helpPanel:Hide() end
        popup:Hide()
    end
end

--- Roll-Button aktivieren wenn ROLL_START und Spieler in der Liste.
function UI.EnablePlayerPopupRoll()
    if not popup or not popup:IsShown() then return end
    widget:EnableRoll()
end

--- Filter-Only-Ansicht: Popup ohne aktives Item zeigen (MMB-Klick im Raider-Mode).
--- Ignoriert popupEnabled — manuelles Öffnen funktioniert immer.
function UI.ShowPlayerPopupFilterOnly()
    BuildPopup()
    CancelAutoClose()
    widget:ShowFilterOnly()
    RefreshEnableCheck()
    popup:Show()
end

--- Gewinner-Anzeige wenn lokaler Spieler das Item bekommt (ASSIGN).
function UI.ShowPlayerPopupWin(link)
    if not popup then return end
    BuildPopup()
    CancelAutoClose()
    widget:ShowWin(link)
    popup:Show()

    autoCloseTimer = C_Timer.NewTimer(6, function()
        if helpPanel then helpPanel:Hide() end
        popup:Hide()
        autoCloseTimer = nil
    end)
end
