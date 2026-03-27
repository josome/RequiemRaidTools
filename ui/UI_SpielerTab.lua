-- GuildLoot – UI_SpielerTab.lua
-- Spieler-Tab: Build + Refresh

local GL = GuildLoot
local UI = GL.UI

local TAB_SPIELER = UI.TAB_SPIELER
local ColorDiff   = UI._H.ColorDiff

-- ============================================================
-- Tab-Widgets (file-local)
-- ============================================================

local playerRows = {}

-- ============================================================
-- Spieler-Panel bauen
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
    content:SetSize(600, 1)
    scroll:SetScrollChild(content)
    panel.content = content
    panel.scroll  = scroll
    panel.colW    = colW

    return panel
end

-- ============================================================
-- Spieler-Tab Refresh
-- ============================================================

function UI.RefreshSpielerTab()
    if UI.activeTab ~= TAB_SPIELER then return end
    if not UI.spielerPanel or not UI.spielerPanel.content then return end

    local scroll = UI.spielerPanel.scroll
    local w = scroll and scroll:GetWidth() or 0
    if w > 10 then
        UI.spielerPanel.content:SetWidth(w)
    end

    for _, r in ipairs(playerRows) do r:Hide() end
    playerRows = {}

    local participants = GuildLootDB.currentRaid.participants
    local absent       = GuildLootDB.currentRaid.absent
    local players      = GuildLootDB.players
    local colW         = UI.spielerPanel.colW
    local content      = UI.spielerPanel.content

    local yOff = 0
    for _, fullName in ipairs(participants) do
        local data     = players[fullName] or {}
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

        -- Spalten 3-5: Set, Waffe, Trinket
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
