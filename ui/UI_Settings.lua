-- GuildLoot – UI_Settings.lua
-- Settings-Panel

local GL = GuildLoot
local UI = GL.UI

-- ============================================================
-- Settings-Overlay
-- ============================================================

function UI.BuildSettingsPanel(parent)
    local panel = CreateFrame("Frame", "GuildLootSettingsPanel", parent, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0.05, 0.05, 0.08, 1)

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

    return panel
end
