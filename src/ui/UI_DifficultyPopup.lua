-- GuildLoot – UI_DifficultyPopup.lua
-- Schwierigkeitsgrad-Popup: erscheint beim Assign wenn die Difficulty
-- des Empfängers unbekannt ist. Drei Buttons (N/H/M) lösen entweder
-- AssignLootConfirm aus oder rufen einen optionalen Callback auf.

local GL = GuildLoot
local UI = GL.UI

local MakeButton = UI._H.MakeButton

local difficultyPopup

--- Zeigt das Difficulty-Popup zentriert über dem Hauptfenster.
--- @param recipientShortName string  Empfänger für AssignLootConfirm (falls callback nil)
--- @param callback           function|nil  function(diff) — alternative Aktion (z.B. AssignAllWinners)
function UI.ShowDifficultyPopup(recipientShortName, callback)
    if difficultyPopup then difficultyPopup:Hide() end

    local popup = CreateFrame("Frame", "GuildLootDiffPopup", UIParent, "BackdropTemplate")
    popup:SetBackdrop(UI.BACKDROPS.DIALOG_SM)
    popup:SetFrameStrata("DIALOG")
    popup:SetSize(240, 100)
    popup:SetPoint("CENTER", _G["GuildLootMainFrame"] or UIParent, "CENTER")
    difficultyPopup = popup

    local lbl = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOP", popup, "TOP", 0, -12)
    lbl:SetText("Schwierigkeitsgrad auswählen:")

    local function MakeDiffBtn(text, diff, xPos)
        local btn = MakeButton(popup, text, 60, 24, function()
            popup:Hide()
            if callback then
                callback(diff)
            else
                GL.Loot.AssignLootConfirm(recipientShortName, diff)
            end
        end)
        btn:SetPoint("BOTTOM", popup, "BOTTOM", xPos, 12)
        return btn
    end

    MakeDiffBtn("Normal", "N", -80)
    MakeDiffBtn("Heroic", "H",  -10)
    MakeDiffBtn("Mythic", "M",   60)

    popup:Show()
end
