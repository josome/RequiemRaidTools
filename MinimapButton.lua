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
local btn = CreateFrame("Button", "RaidLootTrackerMinimapButton", Minimap)
btn:SetSize(32, 32)
btn:SetFrameStrata("MEDIUM")
btn:EnableMouse(true)
btn:RegisterForClicks("LeftButtonUp")
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
    if button == "LeftButton" then
        if GL.UI and GL.UI.Toggle then GL.UI.Toggle() end
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
    GameTooltip:AddLine("RaidLootTracker", 1, 0.8, 0)
    GameTooltip:AddLine("Linksklick: Fenster öffnen/schließen", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Ziehen: Position ändern", 0.9, 0.9, 0.9)
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
