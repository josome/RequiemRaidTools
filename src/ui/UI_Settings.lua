-- GuildLoot – UI_Settings.lua
-- Settings-Panel

local GL = GuildLoot
local UI = GL.UI

-- ============================================================
-- Settings-Overlay
-- ============================================================

function UI.BuildSettingsPanel(parent)
    local outerPanel = CreateFrame("Frame", "GuildLootSettingsPanel", parent, "BackdropTemplate")
    outerPanel:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    outerPanel:SetBackdropColor(0.05, 0.05, 0.08, 1)

    -- ScrollFrame damit der Inhalt bei vielen Einstellungen scrollbar ist
    local scroll = CreateFrame("ScrollFrame", nil, outerPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     outerPanel, "TOPLEFT",     4,  -4)
    scroll:SetPoint("BOTTOMRIGHT", outerPanel, "BOTTOMRIGHT", -26, 4)

    local panel = CreateFrame("Frame", nil, scroll)
    panel:SetHeight(1)
    scroll:SetScrollChild(panel)
    scroll:HookScript("OnSizeChanged", function(self)
        panel:SetWidth(self:GetWidth())
    end)

    local y = -12  -- laufende Y-Position

    local function SectionHeader(label)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
        lbl:SetText("|cffffcc00" .. label .. "|r")
        y = y - 18
        local div = panel:CreateTexture(nil, "BACKGROUND")
        div:SetColorTexture(0.5, 0.5, 0.5, 0.5)
        div:SetHeight(1)
        div:SetPoint("TOPLEFT",  panel, "TOPLEFT",  12, y)
        div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, y)
        y = y - 8
        return lbl
    end

    local function MakeCheck(labelText, key, subtable)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
        cb.text:SetText(labelText)
        cb.text:ClearAllPoints()
        cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        local function getVal()
            if subtable then
                return GuildLootDB.settings[subtable] and GuildLootDB.settings[subtable][key]
            end
            return GuildLootDB.settings[key]
        end
        cb:SetChecked(getVal() ~= false)
        cb:SetScript("OnClick", function(self)
            if subtable then
                GuildLootDB.settings[subtable][key] = self:GetChecked()
            else
                GuildLootDB.settings[key] = self:GetChecked()
            end
        end)
        y = y - 24
        return cb
    end

    -- ── Sektion 1: Loot-Filter ────────────────────────────────
    SectionHeader("Loot Filter")

    -- Min. Qualität Dropdown
    local qualLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qualLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    qualLbl:SetText("Min. Quality:")
    local qualDD = CreateFrame("Frame", "GuildLootSettingsDD_minQuality", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(qualDD, 80)
    qualDD:SetPoint("LEFT", qualLbl, "RIGHT", -8, 0)
    local qualOpts   = { 3, 4, 5 }
    local qualLabels = { "|cff0070ddRare|r", "|cffa335eeEpic|r", "|cffff8000Legendary|r" }
    local function qualLabel(v)
        for i, q in ipairs(qualOpts) do if q == v then return qualLabels[i] end end
        return tostring(v)
    end
    UIDropDownMenu_SetText(qualDD, qualLabel(GuildLootDB.settings.minQuality or 4))
    UIDropDownMenu_Initialize(qualDD, function()
        for i, v in ipairs(qualOpts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = qualLabels[i]
            info.notCheckable = true
            info.func = function()
                GuildLootDB.settings.minQuality = v
                UIDropDownMenu_SetText(qualDD, qualLabels[i])
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    y = y - 30

    MakeCheck("Hide non-equippable items", "filterNonEquip")

    local catLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    catLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    catLbl:SetText("|cff888888Show categories:|r")
    y = y - 22

    -- Kategorie-Checkboxen in 2×2 Grid
    local function MakeCatCheck(labelText, key, col)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(18, 18)
        local xOff = (col == 1) and 20 or 200
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", xOff, y)
        cb.text:SetText(labelText)
        cb.text:ClearAllPoints()
        cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        local s = GuildLootDB.settings
        cb:SetChecked((s.filterCategories and s.filterCategories[key]) ~= false)
        cb:SetScript("OnClick", function(self)
            if not GuildLootDB.settings.filterCategories then
                GuildLootDB.settings.filterCategories = {}
            end
            GuildLootDB.settings.filterCategories[key] = self:GetChecked()
        end)
        return cb
    end
    MakeCatCheck("Weapons",   "weapons",  1)
    MakeCatCheck("Trinkets",  "trinket",  2)
    y = y - 24
    MakeCatCheck("Set Items", "setItems", 1)
    MakeCatCheck("Other",     "other",    2)
    y = y - 14

    -- ── Sektion 2: Timer ──────────────────────────────────────
    SectionHeader("Timers")

    local timerLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    timerLbl:SetText("|cff888888Prio Phase:|r")

    local ddPrio = CreateFrame("Frame", "GuildLootSettingsDD_prioSeconds", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(ddPrio, 80)
    UIDropDownMenu_SetText(ddPrio, (GuildLootDB.settings.prioSeconds or 15) .. "s")
    ddPrio:SetPoint("LEFT", timerLbl, "RIGHT", -8, 0)
    UIDropDownMenu_Initialize(ddPrio, function()
        for _, s in ipairs({10,15,20,30,45,60}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = s .. "s"
            info.notCheckable = true
            info.func = function()
                GuildLootDB.settings.prioSeconds = s
                UIDropDownMenu_SetText(ddPrio, s .. "s")
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    y = y - 28

    local rollLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rollLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    rollLbl:SetText("|cff888888Roll Phase:|r")

    local ddRoll = CreateFrame("Frame", "GuildLootSettingsDD_rollSeconds", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(ddRoll, 80)
    UIDropDownMenu_SetText(ddRoll, (GuildLootDB.settings.rollSeconds or 15) .. "s")
    ddRoll:SetPoint("LEFT", rollLbl, "RIGHT", -8, 0)
    UIDropDownMenu_Initialize(ddRoll, function()
        for _, s in ipairs({10,15,20,30}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = s .. "s"
            info.notCheckable = true
            info.func = function()
                GuildLootDB.settings.rollSeconds = s
                UIDropDownMenu_SetText(ddRoll, s .. "s")
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    y = y - 28

    -- ── Sektion 3: Allgemein ──────────────────────────────────
    SectionHeader("General")

    -- Chat-Kanal Dropdown
    local chatLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chatLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    chatLbl:SetText("|cff888888Chat Channel:|r")

    local chatOpts   = { "AUTO",        "RAID",       "INSTANCE_CHAT",   "PARTY",        "OFF" }
    local chatLabels = { "Automatic",   "Raid Chat",  "Instance Chat",   "Group Chat",   "Off" }
    local function getChatLabel(v)
        for i, c in ipairs(chatOpts) do if c == v then return chatLabels[i] end end
        return "Automatic"
    end
    local ddChat = CreateFrame("Frame", "GuildLootSettingsDD_chatChannel", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(ddChat, 100)
    ddChat:SetPoint("LEFT", chatLbl, "RIGHT", -8, 0)
    UIDropDownMenu_SetText(ddChat, getChatLabel(GuildLootDB.settings.chatChannel or "AUTO"))
    UIDropDownMenu_Initialize(ddChat, function()
        for i, v in ipairs(chatOpts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = chatLabels[i]
            info.notCheckable = true
            info.func = function()
                GuildLootDB.settings.chatChannel = v
                GuildLootDB.settings.postToChat = (v ~= "OFF")
                UIDropDownMenu_SetText(ddChat, chatLabels[i])
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    y = y - 30

    MakeCheck("Announce item start as raid warning", "raidWarnItem")
    MakeCheck("Whisper winner on assign", "whisperWinner")

    -- Export Format Dropdown
    local expFmtLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    expFmtLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    expFmtLbl:SetText("|cff888888Export Format:|r")

    local ddExpFmt = CreateFrame("Frame", "GuildLootSettingsDD_exportFormat", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(ddExpFmt, 80)
    ddExpFmt:SetPoint("LEFT", expFmtLbl, "RIGHT", -8, 0)
    UIDropDownMenu_SetText(ddExpFmt, GuildLootDB.settings.exportFormat or "JSON")
    UIDropDownMenu_Initialize(ddExpFmt, function()
        for _, v in ipairs({ "JSON", "CSV" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = v
            info.notCheckable = true
            info.func = function()
                GuildLootDB.settings.exportFormat = v
                UIDropDownMenu_SetText(ddExpFmt, v)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    y = y - 30

    -- ── Sektion 4: Priorities ─────────────────────────────────
    SectionHeader("Priorities")

    local function MakeEditBox(w, placeholder)
        local eb = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        eb:SetSize(w, 20)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(32)
        if placeholder then
            eb:SetText(placeholder)
        end
        return eb
    end

    local prioNames  = { "BIS", "OS", "", "Transmog", "" }
    local prioDescs  = { "Best In Slot", "Off-Spec", "", "Transmog", "" }

    local applyBtn  -- forward-declare so callback can reference it

    for i = 1, 5 do
        local pCfg = GuildLootDB.settings.priorities and GuildLootDB.settings.priorities[i] or {}
        local rowY  = y

        -- Checkbox aktiv
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(18, 18)
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, rowY)
        cb:SetChecked(pCfg.active == true)
        cb.text:SetText("")
        cb:SetScript("OnClick", function(self)
            if not GuildLootDB.settings.priorities then
                GuildLootDB.settings.priorities = {}
            end
            if not GuildLootDB.settings.priorities[i] then
                GuildLootDB.settings.priorities[i] = { active=false, shortName="", description="" }
            end
            GuildLootDB.settings.priorities[i].active = self:GetChecked()
        end)

        -- Label "Prio N:"
        local numLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        numLbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        numLbl:SetText("Prio " .. i .. ":")
        numLbl:SetWidth(40)

        -- EditBox ShortName
        local ebName = MakeEditBox(64, pCfg.shortName or prioNames[i] or "")
        ebName:SetPoint("LEFT", numLbl, "RIGHT", 4, 0)
        ebName:SetScript("OnEditFocusLost", function(self)
            if not GuildLootDB.settings.priorities then GuildLootDB.settings.priorities = {} end
            if not GuildLootDB.settings.priorities[i] then
                GuildLootDB.settings.priorities[i] = { active=false, shortName="", description="" }
            end
            GuildLootDB.settings.priorities[i].shortName = self:GetText()
        end)
        ebName:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

        -- EditBox Description
        local ebDesc = MakeEditBox(120, pCfg.description or prioDescs[i] or "")
        ebDesc:SetPoint("LEFT", ebName, "RIGHT", 4, 0)
        ebDesc:SetScript("OnEditFocusLost", function(self)
            if not GuildLootDB.settings.priorities then GuildLootDB.settings.priorities = {} end
            if not GuildLootDB.settings.priorities[i] then
                GuildLootDB.settings.priorities[i] = { active=false, shortName="", description="" }
            end
            GuildLootDB.settings.priorities[i].description = self:GetText()
        end)
        ebDesc:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

        y = y - 26
    end

    y = y - 4

    -- "Apply to current Raid Session" Button
    applyBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    applyBtn:SetSize(80, 22)
    applyBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 32, y)
    applyBtn:SetText("Apply")
    local function refreshApplyBtn()
        applyBtn:SetEnabled(GuildLootDB.activeContainerIdx ~= nil)
    end
    refreshApplyBtn()
    outerPanel:HookScript("OnShow", refreshApplyBtn)
    local applyArmed = false
    local applyTimer = nil
    applyBtn:SetScript("OnClick", function(self)
        local db = GuildLootDB
        if not db.activeContainerIdx then return end
        if not applyArmed then
            applyArmed = true
            self:SetText("|cffff4444Sure?|r")
            if applyTimer then applyTimer:Cancel() end
            applyTimer = C_Timer.NewTimer(3, function()
                applyArmed = false
                applyTimer = nil
                self:SetText("Apply")
            end)
        else
            if applyTimer then applyTimer:Cancel(); applyTimer = nil end
            applyArmed = false
            self:SetText("Apply")
            local session = db.raidContainers[db.activeContainerIdx]
            if session then
                session.priorityConfig = CopyTable(db.settings.priorities or {})
                GL.Print("[ReqRT] Priority config applied to current Raid Session.")
            end
        end
    end)
    y = y - 30

    -- Inhalt-Höhe anpassen damit ScrollFrame weiß wie weit er scrollen kann
    panel:SetHeight(math.abs(y) + 12)

    return outerPanel
end
