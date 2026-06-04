-- GuildLoot – UI_DockTab.lua
-- Dock-Tab (angedockter Button am linken Bildschirmrand, minimierter Zustand).
-- BuildDockTab/RefreshDockTab werden aus UI.lua heraus aufgerufen; das Frame
-- liegt in UI.dockTab. Orchestrierung (Dock/Undock/Toggle/OnZoneChanged) bleibt
-- in UI.lua, weil sie zusätzlich das Hauptfenster steuert.

local GL = GuildLoot
local UI = GL.UI

-- ============================================================
-- Dock-Tab bauen
-- ============================================================

function UI.BuildDockTab()
    if UI.dockTab then return end

    local dockTab = CreateFrame("Button", "GuildLootDockTab", UIParent, "BackdropTemplate")
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
        GameTooltip:SetText("RequiemRaidTools", 1, 0.8, 0)
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
    title:SetText("|cff00ccffR|r")

    local title2 = dockTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title2:SetPoint("TOP", title, "BOTTOM", 0, -2)
    title2:SetText("|cff00ccffT|r")

    UI.dockLootCount = dockTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.dockLootCount:SetPoint("CENTER", dockTab, "CENTER", 0, 0)
    UI.dockLootCount:SetText("")

    UI.dockMLCheck = dockTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.dockMLCheck:SetPoint("BOTTOM", dockTab, "BOTTOM", 0, 22)
    UI.dockMLCheck:SetText("")

    UI.dockRaidDot = dockTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.dockRaidDot:SetPoint("BOTTOM", dockTab, "BOTTOM", 0, 8)
    UI.dockRaidDot:SetText("")

    dockTab:Hide()
    UI.dockTab = dockTab
end

-- ============================================================
-- Dock-Tab Refresh (Loot-Count, ML-Status, Raid-Status)
-- ============================================================

function UI.RefreshDockTab()
    if not UI.dockTab then return end
    local pending = (GL.Loot and GL.Loot.GetPendingLoot) and #GL.Loot.GetPendingLoot() or 0
    if pending > 0 then
        UI.dockLootCount:SetText("|cffffcc00" .. pending .. "|r\n|cff888888Item(s)|r")
    else
        UI.dockLootCount:SetText("")
    end
    if UI.dockMLCheck then
        if GL.IsMasterLooter() then
            UI.dockMLCheck:SetText("|cff00ff00☑|r")
        else
            UI.dockMLCheck:SetText("|cff555555☐|r")
        end
    end
    if GuildLootDB.activeContainerIdx then
        UI.dockRaidDot:SetText("|cff00ff00☑|r")
    else
        UI.dockRaidDot:SetText("|cff555555☐|r")
    end
end
