-- RaidLootTracker – MinimapButton.lua
-- Minimap-Button: kompatibel mit Minimap-Button-Managern (ButtonBin, MBB etc.)

GuildLoot = GuildLoot or {}
local GL = GuildLoot
GL.UI = GL.UI or {}
local UI = GL.UI

-- ── Hilfsfunktion: Button am Minimap-Rand positionieren ──────────────────────
local function UpdateMinimapPos(b)
    local angle  = math.rad(GuildLootDB and GuildLootDB.settings.minimapAngle or 45)
    local radius = 80
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius,
        math.sin(angle) * radius)
end

-- ── Button erstellen ──────────────────────────────────────────────────────────
local btn = CreateFrame("Button", "RequiemRaidToolsMinimapButton", Minimap)
btn:SetSize(32, 32)
btn:SetFrameStrata("MEDIUM")
btn:EnableMouse(true)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Runder Rahmen (Standard-Minimap-Button-Optik)
local overlay = btn:CreateTexture(nil, "OVERLAY")
overlay:SetSize(54, 54)
overlay:SetPoint("TOPLEFT")
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

-- Icon — als .icon gespeichert damit Button-Manager es finden
local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 2, 1)
icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
btn.icon = icon   -- ← wichtig für ButtonBin / MBB / Bazooka etc.

-- ── Klick ────────────────────────────────────────────────────────────────────
btn:SetScript("OnClick", function(self, button)
    if GL.IsPlayerMode and GL.IsPlayerMode() then
        -- Raider Mode: Links = Popup, Rechts = Hauptfenster (direkt, kein IsPlayerMode-Guard)
        if button == "LeftButton" then
            if GL.UI and GL.UI.ShowPlayerPopupFilterOnly then GL.UI.ShowPlayerPopupFilterOnly() end
        elseif button == "RightButton" then
            if GL.UI and GL.UI.OpenMainWindow then GL.UI.OpenMainWindow() end
        end
    else
        -- ML / Observer: Links = Hauptfenster, Rechts = Popup
        if button == "LeftButton" then
            if GL.UI and GL.UI.Toggle then GL.UI.Toggle() end
        elseif button == "RightButton" then
            if GL.UI and GL.UI.ShowPlayerPopupFilterOnly then GL.UI.ShowPlayerPopupFilterOnly() end
        end
    end
end)

-- ── Ziehen (ohne Manager) ─────────────────────────────────────────────────────
btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function(b)
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        local angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
        if GuildLootDB then GuildLootDB.settings.minimapAngle = angle end
        UpdateMinimapPos(b)
    end)
end)

btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

-- ── Tooltip ──────────────────────────────────────────────────────────────────
btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("RequiemRaidTools", 1, 0.8, 0)
    if GL.IsPlayerMode and GL.IsPlayerMode() then
        GameTooltip:AddLine("Left-click: Loot Announce popup", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right-click: Open/close window", 0.9, 0.9, 0.9)
    else
        GameTooltip:AddLine("Left-click: Open/close window", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right-click: Loot Announce popup", 0.9, 0.9, 0.9)
    end
    GameTooltip:AddLine("Drag: Change position", 0.9, 0.9, 0.9)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ── Position beim Login setzen ───────────────────────────────────────────────
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    UpdateMinimapPos(btn)
end)

UI.minimapBtn = btn
