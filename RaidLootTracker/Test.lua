-- RaidLootTracker – Test.lua
-- Testhelfer für die Entwicklung. Nicht für den Produktiveinsatz.

GuildLoot = GuildLoot or {}
local GL = GuildLoot
GL.Test = GL.Test or {}

-- Fügt ein zufälliges episches Ausrüstungs-Item aus dem Inventar in Pending-Loot ein,
-- damit der komplette Loot-Flow (Prio → Roll → Vergabe) getestet werden kann.
function GL.Test.AddPendingItem()
    if not GuildLootDB.currentRaid.active then
        GL.Print("No active raid. Use /rlt start first.")
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
        GL.Print("No epic items found in inventory.")
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
    GL.Print("Test loot added: " .. chosen.link)
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

-- Simuliert einen laufenden Roll-Vorgang mit Fake-Kandidaten verschiedener Prios,
-- damit die Results-Sektion ohne echten Raid getestet werden kann.
function GL.Test.SimulateRoll()
    -- Raid sicherstellen
    if not GuildLootDB.currentRaid.active then
        GL.StartRaid("Test-Tier")
    end

    -- Episches Item aus Inventar holen (gleiche Logik wie AddPendingItem)
    local chosen = nil
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local name, _, rarity, _, _, _, _, _, equipLoc = GetItemInfo(link)
                local isEquip = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
                if rarity and rarity >= 4 and isEquip then
                    chosen = { link = link, name = name, equipLoc = equipLoc, quality = rarity }
                    break
                end
            end
        end
        if chosen then break end
    end

    if not chosen then
        GL.Print("SimulateRoll: No epic item found in inventory.")
        return
    end

    local itemID   = tonumber(chosen.link:match("item:(%d+)"))
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(chosen.link)
    local category = GL.GetItemCategory(itemID, equipLoc or chosen.equipLoc, chosen.quality)

    -- Alle laufenden Timer stoppen (kein ActivateItem, damit kein Prio-Timer gestartet wird)
    GL.Loot.ClearCurrentItem()

    -- currentItem direkt befüllen ohne Timer zu starten
    local realm = GetRealmName() or "Realm"
    local ci = GL.Loot.GetCurrentItem()
    ci.link     = chosen.link
    ci.name     = chosen.name
    ci.itemID   = itemID
    ci.quality  = chosen.quality
    ci.category = category
    ci.candidates = {
        ["TestPlayer1-" .. realm] = { prio = 1 },
        ["TestPlayer2-" .. realm] = { prio = 1 },
        ["TestPlayer3-" .. realm] = { prio = 1 },
        ["TestPlayer4-" .. realm] = { prio = 1 },
        ["TestPlayer5-" .. realm] = { prio = 2 },
        ["TestPlayer6-" .. realm] = { prio = 2 },
        ["TestPlayer7-" .. realm] = { prio = 3 },
    }
    ci.rollState.players = {
        TestPlayer1 = true,
        TestPlayer2 = true,
        TestPlayer3 = true,
        TestPlayer4 = true,
    }
    ci.rollState.results = { TestPlayer2 = 87, TestPlayer3 = 42 }

    -- Fake-Spieler zu Teilnehmern hinzufügen damit AssignLoot den realm-qualifizierten
    -- Namen aus candidates findet und winnerPrio korrekt auslesen kann
    local participants = GuildLootDB.currentRaid.participants
    for name in pairs(ci.candidates) do
        local found = false
        for _, p in ipairs(participants) do if p == name then found = true; break end end
        if not found then table.insert(participants, name) end
    end

    -- Ergebnisse sofort auswerten → Assign-Buttons direkt aktiv ohne "Evaluate"
    GL.Loot.FinalizeRoll()
    GL.Print("Roll simulation: TestPlayer2 won (87) — check the Loot tab to assign.")
end

-- Fügt einen fertigen Loot-Log-Eintrag mit echtem Item aus dem Inventar ein,
-- damit der Analyzer/Export mit itemID-verlinkten Einträgen getestet werden kann.
-- Verhält sich wie ein echter AssignLoot-Eintrag (inkl. itemID, category, difficulty, prio).
function GL.Test.AddLootEntry()
    if not GuildLootDB.currentRaid.active then
        GL.Print("No active raid. Use /rlt start first.")
        return
    end

    -- Episches Equip-Item aus Inventar suchen
    local chosen = nil
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local name, _, rarity, _, _, _, _, _, equipLoc = GetItemInfo(link)
                local isEquip = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
                if rarity and rarity >= 4 and isEquip then
                    chosen = { link = link, name = name, equipLoc = equipLoc, quality = rarity }
                    break
                end
            end
        end
        if chosen then break end
    end

    if not chosen then
        GL.Print("AddLootEntry: No epic equippable item found in inventory.")
        return
    end

    local itemID   = tonumber(chosen.link:match("item:(%d+)"))
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(chosen.link)
    local category = GL.GetItemCategory(itemID, equipLoc or chosen.equipLoc, chosen.quality)
    local diff     = GL.DetectDifficulty() or GuildLootDB.currentRaid.difficulty or "N"

    -- Fake-Spieler: abwechselnde Prios für abwechslungsreiche Testdaten
    local realm    = GetRealmName() or "Realm"
    local fakePlayers = {
        { name = "TestPlayer1-" .. realm, prio = 1 },
        { name = "TestPlayer2-" .. realm, prio = 2 },
        { name = "TestPlayer3-" .. realm, prio = 1 },
        { name = "TestPlayer4-" .. realm, prio = 3 },
    }
    local pick = fakePlayers[math.random(#fakePlayers)]

    local entry = {
        player     = pick.name,
        item       = chosen.link,
        link       = chosen.link,
        itemID     = itemID,
        quality    = chosen.quality,
        category   = category,
        difficulty = diff,
        winnerPrio = pick.prio,
        timestamp  = time(),
    }

    table.insert(GuildLootDB.currentRaid.lootLog, entry)
    GL.Print("Test loot entry added: " .. chosen.link .. " → " .. GL.ShortName(pick.name))
    if GL.UI and GL.UI.RefreshLogTab  then GL.UI.RefreshLogTab()  end
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end
