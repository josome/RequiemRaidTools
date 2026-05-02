-- GuildLoot – UI_RollTab.lua
-- Roll-Tab im Hauptfenster: Wrapper um UI_LootAnnounceWidget für Observer.
-- Tab-spezifisch: Panel-Erstellung, Auto-Switch-Logik, IsPlayerMode-Guard.

local GL = GuildLoot
local UI = GL.UI

-- ============================================================
-- Interner Zustand
-- ============================================================

local rollPanel = nil  -- content-Frame (Parent: contentFrame)
local widget    = nil  -- LootAnnounceWidget

-- ============================================================
-- Frame aufbauen (einmalig)
-- ============================================================

function UI.BuildRollTab(parent)
    if rollPanel then return rollPanel end

    rollPanel = CreateFrame("Frame", nil, parent)
    rollPanel:SetAllPoints()
    rollPanel:Hide()

    widget = UI.BuildLootAnnounceWidget(rollPanel)
    widget:ShowFilterOnly()  -- initialer Zustand: keine Buttons (wie Popup ohne Item)

    UI.rollPanel = rollPanel
    return rollPanel
end

-- ============================================================
-- Öffentliche API
-- ============================================================

--- Item anzeigen und Roll-Tab in den Vordergrund bringen (Observer-seitig).
function UI.UpdateRollTab(link, category)
    if not rollPanel then return end
    if GL.IsPlayerMode() then return end  -- Raider bekommen das Popup

    widget:SetItem(link)

    -- Auto-Switch zum Roll-Tab
    if GuildLootDB.settings.minimized then
        UI.Undock()
    end
    if UI.IsMainFrameShown() then
        UI.ShowTab(UI.TAB_ROLL)
    end
end

--- Roll-Button aktivieren wenn der lokale Spieler in der Roll-Liste ist (ROLL_START).
function UI.EnableRollTabRoll()
    if not rollPanel or not rollPanel:IsShown() then return end
    widget:EnableRoll()
end

--- Gewinner-Anzeige wenn lokaler Spieler das Item bekommt (ASSIGN).
function UI.ShowRollTabWin(link)
    if not rollPanel then return end
    widget:ShowWin(link)
end

--- Tab-Inhalt leeren nach ITEM_OFF oder ASSIGN.
function UI.ClearRollTab()
    if not rollPanel then return end
    widget:ShowFilterOnly()  -- Buttons ausblenden wie im Popup (kein Item = kein Prio/Roll)
end
