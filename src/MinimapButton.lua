-- RaidLootTracker – MinimapButton.lua
-- Minimap-Button via LibDataBroker-1.1 + LibDBIcon-1.0

GuildLoot = GuildLoot or {}
local GL = GuildLoot
GL.UI = GL.UI or {}

local LDB  = LibStub("LibDataBroker-1.1")
local icon = LibStub("LibDBIcon-1.0")

local dataobj = LDB:NewDataObject("RequiemRaidTools", {
    type = "launcher",
    icon = "Interface\\AddOns\\RequiemRaidTools\\Media\\icon",
    OnClick = function(self, button)
        if GL.IsPlayerMode and GL.IsPlayerMode() then
            -- Raider Mode: Links = Popup, Rechts = Hauptfenster
            if button == "LeftButton" then
                if GL.UI.ShowPlayerPopupFilterOnly then GL.UI.ShowPlayerPopupFilterOnly() end
            elseif button == "RightButton" then
                if GL.UI.OpenMainWindow then GL.UI.OpenMainWindow() end
            end
        else
            -- ML / Observer: Links = Hauptfenster, Rechts = Popup
            if button == "LeftButton" then
                if GL.UI.Toggle then GL.UI.Toggle() end
            elseif button == "RightButton" then
                if GL.UI.ShowPlayerPopupFilterOnly then GL.UI.ShowPlayerPopupFilterOnly() end
            end
        end
    end,
    OnTooltipShow = function(tt)
        tt:AddLine("RequiemRaidTools", 1, 0.8, 0)
        if GL.IsPlayerMode and GL.IsPlayerMode() then
            tt:AddLine("Left-click: Loot Announce popup", 0.9, 0.9, 0.9)
            tt:AddLine("Right-click: Open/close window", 0.9, 0.9, 0.9)
        else
            tt:AddLine("Left-click: Open/close window", 0.9, 0.9, 0.9)
            tt:AddLine("Right-click: Loot Announce popup", 0.9, 0.9, 0.9)
        end
        tt:AddLine("Drag: Change position", 0.9, 0.9, 0.9)
    end,
})

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if not RequiemRaidToolsMinimapIconDB then RequiemRaidToolsMinimapIconDB = {} end
    if RequiemRaidToolsMinimapIconDB.showInCompartment == nil then
        RequiemRaidToolsMinimapIconDB.showInCompartment = true
    end
    icon:Register("RequiemRaidTools", dataobj, RequiemRaidToolsMinimapIconDB)
    icon:RemoveButtonBorder("RequiemRaidTools")
    icon:SetButtonSize("RequiemRaidTools", 25)
    icon:SetButtonIcon("RequiemRaidTools", nil, 24)
    GL.UI.minimapBtn = icon:GetMinimapButton("RequiemRaidTools")
end)
