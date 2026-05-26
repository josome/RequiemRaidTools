-- GuildLoot – UI_DropPanel.lua
-- Drop-Panel zum manuellen Hinzufügen eines Items via Drag & Drop oder Klick.
-- Wird in BuildMainFrame über UI.BuildDropPanel(mainFrame) instantiiert
-- und das Frame in UI.dropPanel hinterlegt.

local GL = GuildLoot
local UI = GL.UI

--- Erstellt das Drop-Panel rechts neben dem Hauptfenster und hängt es als
--- UI.dropPanel an. Wird ein Item per Cursor abgelegt oder geklickt, ruft
--- es GL.Loot.AddItemManually(link) auf und schließt sich nach kurzem
--- grünen Aufleuchten.
--- @param parent Frame  Hauptfenster (mainFrame) — Drop-Panel ankert daran
--- @return Frame
function UI.BuildDropPanel(parent)
    local dropPanel = CreateFrame("Frame", "RLTDropPanel", UIParent, "BasicFrameTemplateWithInset")
    dropPanel:SetSize(180, 110)
    dropPanel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, 0)
    dropPanel:SetFrameStrata("DIALOG")
    dropPanel:SetClampedToScreen(true)
    dropPanel:Hide()
    dropPanel.TitleText:SetText("Item hinzufügen")

    -- Drop-Zone innen
    local dropZone = CreateFrame("Button", nil, dropPanel, "BackdropTemplate")
    dropZone:SetPoint("TOPLEFT",     dropPanel, "TOPLEFT",     8, -28)
    dropZone:SetPoint("BOTTOMRIGHT", dropPanel, "BOTTOMRIGHT", -8,   8)
    dropZone:SetBackdrop(UI.BACKDROPS.DARK)
    dropZone:SetBackdropColor(0.05, 0.05, 0.1, 1)
    dropZone:SetBackdropBorderColor(0.4, 0.4, 0.6, 1)
    dropZone:EnableMouse(true)
    dropZone:RegisterForDrag("LeftButton")

    -- Icon
    local dropIcon = dropZone:CreateTexture(nil, "ARTWORK")
    dropIcon:SetSize(32, 32)
    dropIcon:SetPoint("CENTER", dropZone, "CENTER", 0, 10)
    dropIcon:SetTexture("Interface\\Buttons\\UI-GuildButton-OfficerNote-Up")
    dropIcon:SetAlpha(0.5)

    local dropHint = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dropHint:SetPoint("CENTER", dropZone, "CENTER", 0, -12)
    dropHint:SetText("|cff888888Item hier ablegen|r")

    -- Hover: aufleuchten
    dropZone:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.25, 1)
        self:SetBackdropBorderColor(1, 0.8, 0, 1)
        dropIcon:SetAlpha(1)
    end)
    dropZone:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.05, 0.05, 0.1, 1)
        self:SetBackdropBorderColor(0.4, 0.4, 0.6, 1)
        dropIcon:SetAlpha(0.5)
    end)

    local function tryDrop()
        local infoType, _, itemLink = GetCursorInfo()
        if infoType == "item" and itemLink then
            ClearCursor()
            GL.Loot.AddItemManually(itemLink)
            -- kurz grün aufleuchten
            dropZone:SetBackdropBorderColor(0, 1, 0, 1)
            C_Timer.After(0.5, function()
                dropZone:SetBackdropBorderColor(0.4, 0.4, 0.6, 1)
                dropPanel:Hide()
            end)
        end
    end
    dropZone:SetScript("OnReceiveDrag", tryDrop)
    dropZone:SetScript("OnClick",       tryDrop)

    UI.dropPanel = dropPanel
    return dropPanel
end
