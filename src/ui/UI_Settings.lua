-- GuildLoot – UI_Settings.lua
-- Settings-Panel

local GL = GuildLoot
local UI = GL.UI

-- ============================================================
-- Settings-Overlay
-- ============================================================

function UI.BuildSettingsPanel(parent)
    local outerPanel, panel = UI.CreateSidePanel("GuildLootSettingsPanel", parent, "Settings")

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
    local qualDD = UI.CreateOptionDropdown(panel, 100, {
        { value = 3, label = "|cff0070ddRare|r" },
        { value = 4, label = "|cffa335eeEpic|r" },
        { value = 5, label = "|cffff8000Legendary|r" },
    },
    function() return GuildLootDB.settings.minQuality or 4 end,
    function(v) GuildLootDB.settings.minQuality = v end)
    qualDD:SetPoint("LEFT", qualLbl, "RIGHT", 4, 0)
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

    local prioEntries = {}
    for _, s in ipairs({10,15,20,30,45,60}) do
        table.insert(prioEntries, { value = s, label = s .. "s" })
    end
    local ddPrio = UI.CreateOptionDropdown(panel, 90, prioEntries,
        function() return GuildLootDB.settings.prioSeconds or 15 end,
        function(v) GuildLootDB.settings.prioSeconds = v end)
    ddPrio:SetPoint("LEFT", timerLbl, "RIGHT", 4, 0)
    y = y - 28

    local rollLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rollLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    rollLbl:SetText("|cff888888Roll Phase:|r")

    local rollEntries = {}
    for _, s in ipairs({10,15,20,30}) do
        table.insert(rollEntries, { value = s, label = s .. "s" })
    end
    local ddRoll = UI.CreateOptionDropdown(panel, 90, rollEntries,
        function() return GuildLootDB.settings.rollSeconds or 15 end,
        function(v) GuildLootDB.settings.rollSeconds = v end)
    ddRoll:SetPoint("LEFT", rollLbl, "RIGHT", 4, 0)
    y = y - 28

    -- ── Sektion 3: Allgemein ──────────────────────────────────
    SectionHeader("General")

    -- Chat-Kanal Dropdown
    local chatLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chatLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    chatLbl:SetText("|cff888888Chat Channel:|r")

    local ddChat = UI.CreateOptionDropdown(panel, 120, {
        { value = "AUTO",          label = "Automatic" },
        { value = "RAID",          label = "Raid Chat" },
        { value = "INSTANCE_CHAT", label = "Instance Chat" },
        { value = "PARTY",         label = "Group Chat" },
        { value = "OFF",           label = "Off" },
    },
    function() return GuildLootDB.settings.chatChannel or "AUTO" end,
    function(v)
        GuildLootDB.settings.chatChannel = v
        GuildLootDB.settings.postToChat = (v ~= "OFF")
    end)
    ddChat:SetPoint("LEFT", chatLbl, "RIGHT", 4, 0)
    y = y - 30

    MakeCheck("Announce item start as raid warning", "raidWarnItem")
    MakeCheck("Whisper winner on assign", "whisperWinner")
    local cbDance = MakeCheck("Tanzende Figur bei leerem Loot", "danceEmptyState")
    cbDance:HookScript("OnClick", function() UI.RefreshLootTab() end)

    -- Export Format Dropdown
    local expFmtLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    expFmtLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    expFmtLbl:SetText("|cff888888Export Format:|r")

    local ddExpFmt = UI.CreateOptionDropdown(panel, 90, {
        { value = "JSON", label = "JSON" },
        { value = "CSV",  label = "CSV" },
    },
    function() return GuildLootDB.settings.exportFormat or "JSON" end,
    function(v) GuildLootDB.settings.exportFormat = v end)
    ddExpFmt:SetPoint("LEFT", expFmtLbl, "RIGHT", 4, 0)
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
                -- Neue Prio-Config an alle Raid-Mitglieder übertragen
                if GL.Comm and GL.Comm.SendSessionStart then
                    GL.Comm.SendSessionStart(session.id, session.label, session.startedAt, session.priorityConfig)
                end
                GL.Print("[ReqRT] Priority config applied and broadcast to raid.")
            end
        end
    end)
    y = y - 30

    -- Inhalt-Höhe anpassen damit ScrollFrame weiß wie weit er scrollen kann
    panel:SetHeight(math.abs(y) + 12)

    return outerPanel
end
