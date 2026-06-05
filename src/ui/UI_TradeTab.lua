-- GuildLoot – UI_TradeTab.lua
-- ============================================================================
-- DEBUG-WERKZEUG (temporär — fliegt evtl. später wieder raus).
-- Zweck: nach dem Zuweisen direkt sehen, ob der Loot mit dem richtigen Empfänger
-- in der Auto-Trade-Queue (Loot._pendingTrades) landet, ob sich die Liste füllt
-- bis der Loot abgeholt (getradet) wurde, und ob sie einen INSTANZWECHSEL übersteht.
-- Nur für den ML sichtbar (Tab-Button-Steuerung in UI.RefreshMLButton).
--
-- ZUM ENTFERNEN: alle Stellen mit dem Marker "DEBUG Trade-Tab" suchen:
--   - diese Datei + TOC-Eintrag src/ui/UI_TradeTab.lua
--   - src/ui/UI_Common.lua (TABS.TRADE / PLAYER-Nummerierung)
--   - src/ui/UI.lua (Alias, tabNames, initial Hide, Panel-Build, ShowTab,
--     Refresh, RefreshMLButton)
--   - src/loot/Loot_Assign.lua + src/loot/Loot_Trade.lua (RefreshTradeTab-Hooks)
-- ============================================================================

local GL = GuildLoot
local UI = GL.UI

local ROW_H = 22

-- ============================================================
-- Tab bauen (einmalig)
-- ============================================================

function UI.BuildTradeTab(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel:Hide()

    -- Kopfzeile mit Zähler
    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    panel.header = header

    -- Trennlinie
    local div = panel:CreateTexture(nil, "BACKGROUND")
    div:SetColorTexture(unpack(UI.COLORS.DIVIDER))
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  panel, "TOPLEFT",  12, -28)
    div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -28)

    -- Scrollbare Liste
    local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     panel, "TOPLEFT",     8, -34)
    sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    sf:HookScript("OnSizeChanged", function(self) content:SetWidth(self:GetWidth()) end)
    panel.content = content
    panel.rows = {}

    -- Leerzustand
    local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -44)
    empty:SetTextColor(0.6, 0.6, 0.6)
    empty:SetText("Keine offenen Trades.")
    empty:Hide()
    panel.empty = empty

    UI.tradePanel = panel
    return panel
end

-- ============================================================
-- Tab-Refresh (nur wenn sichtbar)
-- ============================================================

local function GetOrCreateRow(panel, idx)
    local row = panel.rows[idx]
    if row then return row end
    row = CreateFrame("Frame", nil, panel.content)
    row:SetHeight(ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT",  row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row:EnableMouse(true)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.rows[idx] = row
    return row
end

function UI.RefreshTradeTab()
    local panel = UI.tradePanel
    if not panel or not panel:IsShown() then return end

    for _, r in ipairs(panel.rows) do r:Hide() end

    local pending = (GL.Loot and GL.Loot._pendingTrades) or {}
    local staging = (GL.Loot and GL.Loot._inTradeItems) or {}
    panel.header:SetText(("|cffff4444[DEBUG]|r |cffffcc00Auto-Trade Queue|r  |cff888888(%d wartend, %d im Handel)|r")
        :format(#pending, #staging))

    local idx = 0
    local y   = -2
    local function addRow(itemID, who, inTrade)
        idx = idx + 1
        local row = GetOrCreateRow(panel, idx)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  panel.content, "TOPLEFT",  4, y)
        row:SetPoint("TOPRIGHT", panel.content, "TOPRIGHT", -4, y)

        local name = GetItemInfo(itemID)
        local tex  = select(10, GetItemInfo(itemID))
        row.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        local label   = name or ("item:" .. tostring(itemID))
        local nameCol = inTrade and "|cff888888" or "|cffffffff"
        local suffix  = inTrade and "  |cff888888(im Handel)|r" or ""
        row.text:SetText(nameCol .. label .. "|r  |cffaaaaaa→|r  |cff00ff00" .. (who or "?") .. "|r" .. suffix)

        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(itemID)
            GameTooltip:Show()
        end)
        row:Show()
        y = y - ROW_H
    end

    for _, pt in ipairs(pending) do addRow(pt.itemID, pt.shortName, false) end
    for _, pt in ipairs(staging) do addRow(pt.itemID, pt.shortName, true)  end

    panel.empty:SetShown(idx == 0)
    panel.content:SetHeight(math.max(1, -y + 4))
end
