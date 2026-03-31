-- GuildLoot – UI_LootTab.lua
-- Loot-Tab: Build, Refresh, Kandidaten, Roll-Ergebnisse, Session-Loot

local GL = GuildLoot
local UI = GL.UI

local SIDEBAR_W = 240
local TAB_LOOT  = UI.TAB_LOOT

local ColorDiff       = UI._H.ColorDiff
local MakeButton      = UI._H.MakeButton

-- ============================================================
-- Tab-Widgets (file-local)
-- ============================================================

local pendingButtons       = {}
local pendingActiveTab     = "pending"   -- "pending" | "trash"

-- Minitab helpers (nach OPie/TenSettings-Vorbild, Options_Tab_* Atlas)
local minitabData = {}
local function minitab_deselect(b)
    local r = minitabData[b]
    if not r then return end
    r.Text:SetPoint("BOTTOM", 0, 6)
    r.Text:SetFontObject("GameFontNormalSmall")
    r.Left:SetAtlas("Options_Tab_Left", true)
    r.Middle:SetAtlas("Options_Tab_Middle", true)
    r.Right:SetAtlas("Options_Tab_Right", true)
    r.NormalBG:SetPoint("TOPRIGHT", -2, -15)
    r.HighlightBG:SetColorTexture(1,1,1,1)
    r.SelectedBG:SetColorTexture(0,0,0,0)
    b:SetNormalFontObject(GameFontNormalSmall)
end
local function minitab_select(b)
    local r = minitabData[b]
    if not r then return end
    r.Text:SetPoint("BOTTOM", 0, 8)
    r.Text:SetFontObject("GameFontHighlightSmall")
    r.Left:SetAtlas("Options_Tab_Active_Left", true)
    r.Middle:SetAtlas("Options_Tab_Active_Middle", true)
    r.Right:SetAtlas("Options_Tab_Active_Right", true)
    r.NormalBG:SetPoint("TOPRIGHT", -2, -12)
    r.HighlightBG:SetColorTexture(0,0,0,0)
    r.SelectedBG:SetColorTexture(1,1,1,1)
    b:SetNormalFontObject(GameFontHighlightSmall)
end
local function minitab_new(parent, text, onClick)
    local b, r = CreateFrame("Button", nil, parent), {}
    minitabData[b] = r
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b:SetFontString(fs)
    fs:ClearAllPoints()
    fs:SetPoint("BOTTOM", 0, 6)
    b:SetNormalFontObject(GameFontNormalSmall)
    b:SetDisabledFontObject(GameFontDisableSmall)
    b:SetHighlightFontObject(GameFontHighlightSmall)
    b:SetPushedTextOffset(0, 0)
    fs:SetText(text)
    r.Text = fs
    r.Left = b:CreateTexture(nil, "BACKGROUND")
    r.Left:SetPoint("BOTTOMLEFT")
    r.Right = b:CreateTexture(nil, "BACKGROUND")
    r.Right:SetPoint("BOTTOMRIGHT")
    r.Middle = b:CreateTexture(nil, "BACKGROUND")
    r.Middle:SetPoint("TOPLEFT",  r.Left,  "TOPRIGHT",  0, 0)
    r.Middle:SetPoint("TOPRIGHT", r.Right, "TOPLEFT",   0, 0)
    r.NormalBG = b:CreateTexture(nil, "BACKGROUND", nil, -2)
    r.NormalBG:SetPoint("BOTTOMLEFT", 2, 0)
    r.NormalBG:SetPoint("TOPRIGHT", -2, -15)
    r.NormalBG:SetColorTexture(1,1,1,1)
    r.NormalBG:SetGradient("VERTICAL",
        {r=0.1, g=0.1, b=0.1, a=0.85},
        {r=0.15, g=0.15, b=0.15, a=0.85})
    r.HighlightBG = b:CreateTexture(nil, "HIGHLIGHT")
    r.HighlightBG:SetPoint("BOTTOMLEFT", 2, 0)
    r.HighlightBG:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -2, 12)
    r.HighlightBG:SetGradient("VERTICAL",
        {r=1, g=1, b=1, a=0.15},
        {r=0, g=0, b=0, a=0})
    r.SelectedBG = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    r.SelectedBG:SetPoint("BOTTOMLEFT", 2, 0)
    r.SelectedBG:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -2, 16)
    r.SelectedBG:SetGradient("VERTICAL",
        {r=1, g=1, b=1, a=0.15},
        {r=0, g=0, b=0, a=0})
    b:SetSize(fs:GetStringWidth() + 40, 37)
    b:SetScript("OnClick", onClick)
    minitab_deselect(b)
    return b
end
local activeItemLabel
local activeItemCategoryLabel
local candidateRows        = {}
local rollResultRows       = {}
local sessionLootRows      = {}
local countdownLabel
local resetItemBtn
local trashItemBtn
local startRollBtn

local function sessionHidden()  return GuildLootDB.currentRaid.sessionHidden  end
local function sessionChecked() return GuildLootDB.currentRaid.sessionChecked end

-- ============================================================
-- Loot-Panel bauen
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

    local tabPending = minitab_new(sidebar, "Pending Loot", function()
        pendingActiveTab = "pending"
        UI.RefreshLootTab()
    end)
    tabPending:SetPoint("BOTTOMLEFT", sidebar, "TOPLEFT", 4, -29)

    local tabTrash = minitab_new(sidebar, "Trash bin", function()
        pendingActiveTab = "trash"
        UI.RefreshLootTab()
    end)
    tabTrash:SetPoint("LEFT", tabPending, "RIGHT", 5, 0)

    panel.tabPending = tabPending
    panel.tabTrash   = tabTrash

    local pendingScroll = CreateFrame("ScrollFrame", "GuildLootPendingScroll", sidebar, "UIPanelScrollFrameTemplate")
    pendingScroll:SetPoint("TOPLEFT",     sidebar, "TOPLEFT",    0,  -34)
    pendingScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -22,  4)
    local pendingContent = CreateFrame("Frame", nil, pendingScroll)
    pendingContent:SetSize(pendingScroll:GetWidth(), 1)
    pendingScroll:SetScrollChild(pendingContent)
    panel.pendingFrame   = sidebar
    panel.pendingContent = pendingContent
    panel.pendingScroll  = pendingScroll

    -- Empty-State: Schatztruhe wenn keine Items pending
    local emptyTex = pendingScroll:CreateTexture(nil, "BACKGROUND")
    emptyTex:SetTexture("Interface\\Icons\\INV_Misc_Chest_Special")
    emptyTex:SetSize(64, 64)
    emptyTex:SetPoint("CENTER", pendingScroll, "CENTER", 0, 0)
    emptyTex:SetAlpha(0.12)
    emptyTex:Hide()
    panel.pendingEmptyTex = emptyTex

    -- ── HAUPT-BEREICH ─────────────────────────────────────────
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
    activeItemLabel:SetPoint("RIGHT", main, "RIGHT", -195, 0)
    activeItemLabel:SetJustifyH("LEFT")
    activeItemLabel:SetText("No active item")

    local activeItemHover = CreateFrame("Frame", nil, main)
    activeItemHover:SetPoint("LEFT",  activeItemIcon, "RIGHT", 6, 0)
    activeItemHover:SetPoint("RIGHT", main, "RIGHT", -195, 0)
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

    trashItemBtn = MakeButton(main, "Trash", 80, 22, function()
        GL.Loot.TrashActiveItem()
    end)
    trashItemBtn:SetPoint("RIGHT", resetItemBtn, "LEFT", -4, 0)
    trashItemBtn:SetPoint("TOP",   divA, "BOTTOM", 0, -2)

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

    -- Buttons: Roll-Aktion + Countdown
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
    resultScroll:SetHeight(120)
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

    -- Results und Session Loot gleichmäßig aufteilen
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
    if UI.activeTab ~= TAB_LOOT then return end
    if not UI.lootPanel then return end

    local ci    = GL.Loot.GetCurrentItem()
    local isML  = GL.IsMasterLooter()
    local isTrashed = (pendingActiveTab == "trash")
    local items = isTrashed and GL.Loot.GetTrashedLoot() or GL.Loot.GetPendingLoot()

    -- Tab-Highlighting
    if UI.lootPanel.tabPending then
        if isTrashed then
            minitab_deselect(UI.lootPanel.tabPending)
            minitab_select(UI.lootPanel.tabTrash)
        else
            minitab_select(UI.lootPanel.tabPending)
            minitab_deselect(UI.lootPanel.tabTrash)
        end
    end

    -- Pending / Trash Rows
    for _, btn in ipairs(pendingButtons) do btn:Hide() end
    pendingButtons = {}
    local pf = UI.lootPanel.pendingContent
    pf:SetWidth(SIDEBAR_W - 26)
    local yOff = -2
    local ROW_H = 30
    for _, item in ipairs(items) do
        local row = CreateFrame("Frame", nil, pf)
        row:SetPoint("TOPLEFT",  pf, "TOPLEFT",  0, yOff)
        row:SetPoint("TOPRIGHT", pf, "TOPRIGHT", 0, yOff)
        row:SetHeight(ROW_H)

        local leftBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        leftBtn:SetSize(22, 22)
        leftBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
        if isTrashed then
            leftBtn:SetText("<")
            leftBtn:SetScript("OnClick", function()
                GL.Loot.RestoreFromTrash(item.link)
            end)
            leftBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Zurück in Pending", 1, 1, 1)
                GameTooltip:Show()
            end)
        else
            leftBtn:SetText("<")
            leftBtn:SetScript("OnClick", function()
                GL.Loot.ReleaseItem(item.link)
            end)
            leftBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Item auswählen", 1, 1, 1)
                GameTooltip:Show()
            end)
        end
        leftBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if not isML then leftBtn:Disable() end

        local rightBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        rightBtn:SetSize(22, 22)
        rightBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        if isTrashed then
            local deletePending = false
            local deleteTimer   = nil
            rightBtn:SetText("×")
            rightBtn:SetScript("OnClick", function()
                if not GL.IsMasterLooter() then return end
                if deletePending then
                    if deleteTimer then deleteTimer:Cancel(); deleteTimer = nil end
                    deletePending = false
                    rightBtn:SetText("×")
                    GL.Loot.DeleteFromTrash(item.link)
                else
                    deletePending = true
                    rightBtn:SetText("|cffff4444Sure?|r")
                    deleteTimer = C_Timer.NewTimer(3, function()
                        deletePending = false
                        deleteTimer   = nil
                        rightBtn:SetText("×")
                    end)
                end
            end)
            if not isML then rightBtn:Disable() end
        else
            rightBtn:SetText("×")
            rightBtn:SetScript("OnClick", function()
                GL.Loot.RemovePendingItem(item.link)
                UI.RefreshLootTab()
            end)
            if not isML then rightBtn:Disable() end
        end

        local pendingIcon = CreateFrame("Frame", nil, row)
        pendingIcon:SetSize(24, 24)
        pendingIcon:SetPoint("LEFT", leftBtn, "RIGHT", 4, 0)
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

        local rightAnchor = rightBtn
        local linkBtn = CreateFrame("Frame", nil, row)
        linkBtn:SetPoint("LEFT",  pendingIcon, "RIGHT", 4, 0)
        linkBtn:SetPoint("RIGHT", rightAnchor, "LEFT", -4, 0)
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

    local totalH = math.max(1, (#items * (ROW_H + 2)) + 8)
    pf:SetHeight(totalH)

    -- Empty-State Textur
    if UI.lootPanel.pendingEmptyTex then
        if #items == 0 and not isTrashed then
            UI.lootPanel.pendingEmptyTex:Show()
        else
            UI.lootPanel.pendingEmptyTex:Hide()
        end
    end

    -- Aktives Item
    if ci.link then
        activeItemLabel:SetText(ci.link)
        local catNames = { weapons="Weapon", trinket="Trinket", setItems="Set/Token", other="Other" }
        activeItemCategoryLabel:SetText("[" .. (catNames[ci.category] or "?") .. "]")
        resetItemBtn:SetEnabled(isML)
        if trashItemBtn then trashItemBtn:SetShown(true) ; trashItemBtn:SetEnabled(isML) end
        if UI.lootPanel.activeItemIconTex then
            local icon = select(10, GetItemInfo(ci.link))
            UI.lootPanel.activeItemIconTex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
    else
        activeItemLabel:SetText("|cff888888No active item|r")
        activeItemCategoryLabel:SetText("")
        resetItemBtn:SetEnabled(false)
        if trashItemBtn then trashItemBtn:SetShown(false) end
        if UI.lootPanel.activeItemIconTex then UI.lootPanel.activeItemIconTex:SetTexture(nil) end
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
    local ci      = GL.Loot.GetCurrentItem()
    local content = UI.lootPanel and UI.lootPanel.candContent
    if not content then GL.Print("[DBG] RefreshCandidates: no content"); return end
    for _, r in ipairs(candidateRows) do r:Hide() end
    candidateRows = {}

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
    local content = UI.lootPanel and UI.lootPanel.resultContent
    if not content then return end
    for _, r in ipairs(rollResultRows) do r:Hide() end
    rollResultRows = {}

    local bestPrio = nil
    for _, data in pairs(ci.candidates) do
        if bestPrio == nil or data.prio < bestPrio then bestPrio = data.prio end
    end

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
    local content = UI.lootPanel and UI.lootPanel.sessionContent
    if not content then return end
    local sw = UI.lootPanel.sessionScroll and UI.lootPanel.sessionScroll:GetWidth() or 0
    if sw > 10 then content:SetWidth(sw) end

    for _, r in ipairs(sessionLootRows) do r:Hide() end
    sessionLootRows = {}

    local log = GuildLootDB.currentRaid.lootLog
    local ROW_H = 26
    local yOff  = 0
    local shown = 0

    for i = #log, 1, -1 do
        local entry = log[i]
        local k = tostring(entry.timestamp) .. (entry.player or "")
        if not sessionHidden()[k] then
            local isChecked = sessionChecked()[k] or false
            local row = CreateFrame("Frame", nil, content)
            row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOff)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
            row:SetHeight(ROW_H)

            local nameText, itemLbl, iconFrame

            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cb:SetSize(18, 18)
            cb:SetPoint("LEFT", row, "LEFT", 0, 0)

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

            local xBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            xBtn:SetSize(18, 18)
            xBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            xBtn:SetText("×")
            xBtn:SetScript("OnClick", function()
                sessionHidden()[k] = true
                UI.RefreshSessionLoot()
            end)

            nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameText:SetPoint("LEFT", iconFrame, "RIGHT", 4, 0)
            nameText:SetWidth(100)
            nameText:SetJustifyH("LEFT")
            nameText:SetText("|cffffcc00" .. GL.ShortName(entry.player or "?") .. "|r")

            local diffLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            diffLbl:SetPoint("LEFT", nameText, "RIGHT", 2, 0)
            diffLbl:SetWidth(20)
            diffLbl:SetText(ColorDiff(entry.difficulty))

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

            itemLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            itemLbl:SetPoint("LEFT",  diffLbl, "RIGHT",  4,  0)
            itemLbl:SetPoint("RIGHT", xBtn,    "LEFT",  -4,  0)
            itemLbl:SetJustifyH("LEFT")
            itemLbl:SetText(entry.item or "?")

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
