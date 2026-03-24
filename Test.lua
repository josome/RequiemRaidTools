-- RaidLootTracker – Test.lua
-- Testhelfer für die Entwicklung. Nicht für den Produktiveinsatz.

GuildLoot = GuildLoot or {}
local GL = GuildLoot
GL.Test = GL.Test or {}

-- Fügt ein zufälliges episches Ausrüstungs-Item aus dem Inventar in Pending-Loot ein,
-- damit der komplette Loot-Flow (Prio → Roll → Vergabe) getestet werden kann.
function GL.Test.AddPendingItem()
    if not GuildLootDB.currentRaid.active then
        GL.Print("Kein aktiver Raid. Zuerst /rlt start.")
        return
    end

    local epicItems = {}
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local name, _, rarity, _, _, _, _, _, equipLoc = GetItemInfo(link)
                local isEquip = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
                if rarity and rarity >= 4 and isEquip then
                    table.insert(epicItems, { link = link, name = name, equipLoc = equipLoc })
                end
            end
        end
    end

    if #epicItems == 0 then
        GL.Print("Keine epischen Items im Inventar gefunden.")
        return
    end

    local chosen = epicItems[math.random(#epicItems)]
    local itemID = tonumber(chosen.link:match("item:(%d+)"))
    local _, _, rarity = GetItemInfo(chosen.link)
    local item = {
        link    = chosen.link,
        name    = chosen.name or "?",
        itemID  = itemID,
        quality = rarity,
    }

    -- Eigenen Spieler zur Teilnehmerliste hinzufügen damit IsParticipant() nicht abblockt
    local me = UnitName("player") .. "-" .. (GetRealmName() or "")
    local inList = false
    for _, p in ipairs(GuildLootDB.currentRaid.participants) do
        if p == me or GL.ShortName(p) == UnitName("player") then inList = true; break end
    end
    if not inList then
        table.insert(GuildLootDB.currentRaid.participants, me)
    end

    GL.Loot.TryAddPendingItem(item, chosen.equipLoc or "")
    GL.Print("Test-Loot hinzugefügt: " .. chosen.link)
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end
