-- RaidLootTracker – Test.lua
-- Testhelfer für die Entwicklung. Nicht für den Produktiveinsatz.

GuildLoot = GuildLoot or {}
local GL = GuildLoot
GL.Test = GL.Test or {}

-- Fügt ein zufälliges episches Ausrüstungs-Item aus dem Inventar in Pending-Loot ein,
-- damit der komplette Loot-Flow (Prio → Roll → Vergabe) getestet werden kann.
function GL.Test.AddPendingItem()
    if not GuildLootDB.activeContainerIdx then
        GL.Print("No active raid. Use /reqrt start first.")
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

-- Simuliert die Prio-Sammelphase mit Fake-Kandidaten, damit der X-Button (Prio löschen)
-- ohne echten Raid getestet werden kann.
function GL.Test.SimulatePrio()
    if not GuildLootDB.activeContainerIdx then
        GL.StartRaid("Test-Tier")
    end

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
        GL.Print("SimulatePrio: No epic item found in inventory.")
        return
    end

    local itemID  = tonumber(chosen.link:match("item:(%d+)"))
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(chosen.link)
    local category = GL.GetItemCategory(itemID, equipLoc or chosen.equipLoc, chosen.quality)

    GL.Loot.ClearCurrentItem()

    local realm = GetRealmName() or "Realm"
    local ci = GL.Loot.GetCurrentItem()
    ci.link      = chosen.link
    ci.name      = chosen.name
    ci.itemID    = itemID
    ci.quality   = chosen.quality
    ci.category  = category
    -- Prio-Phase aktiv, kein laufender Roll
    ci.prioState = { active = true, timeLeft = 30, timer = nil }
    ci.rollState = { active = false, players = {}, results = {}, timer = nil, timeLeft = 0 }
    ci.candidates = {
        ["TestPlayer1-" .. realm] = { prio = 1 },
        ["TestPlayer2-" .. realm] = { prio = 2 },
        ["TestPlayer3-" .. realm] = { prio = 2 },
        ["TestPlayer4-" .. realm] = { prio = 4 },
    }

    local participants = GuildLootDB.currentRaid.participants
    for name in pairs(ci.candidates) do
        local found = false
        for _, p in ipairs(participants) do if p == name then found = true; break end end
        if not found then table.insert(participants, name) end
    end

    if GL.UI and GL.UI.RefreshLootTab     then GL.UI.RefreshLootTab()     end
    if GL.UI and GL.UI.RefreshCandidates  then GL.UI.RefreshCandidates()  end
    GL.Print("Prio simulation active — X-Button pro Kandidat sichtbar (nur als ML).")
end

-- Simuliert einen laufenden Roll-Vorgang mit Fake-Kandidaten verschiedener Prios,
-- damit die Results-Sektion ohne echten Raid getestet werden kann.
-- Wenn bereits ein Item aktiv ist (z.B. per /rlt test + < aktiviert), wird dieses
-- beibehalten und nur Roll-Ergebnisse + Kandidaten werden ergänzt.
function GL.Test.SimulateRoll()
    -- Raid sicherstellen
    if not GuildLootDB.activeContainerIdx then
        GL.StartRaid("Test-Tier")
    end

    local ci = GL.Loot.GetCurrentItem()
    local realm = GetRealmName() or "Realm"

    -- Bereits aktives Item behalten; nur wenn keins aktiv ist selbst eins suchen
    if not ci.link then
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

        -- Prio-Timer stoppen bevor currentItem überschrieben wird
        if ci.prioState and ci.prioState.timer then ci.prioState.timer:Cancel() end
        if ci.rollState  and ci.rollState.timer  then ci.rollState.timer:Cancel()  end

        ci.link     = chosen.link
        ci.name     = chosen.name
        ci.itemID   = itemID
        ci.quality  = chosen.quality
        ci.category = category
        ci.count    = 1
        ci.winners  = {}
        ci._tieReRoll = nil
    end

    -- Fake-Kandidaten setzen (vorhandene bleiben erhalten wenn bereits welche da sind)
    if not next(ci.candidates) then
        ci.candidates = {
            ["TestPlayer1-" .. realm] = { prio = 1 },
            ["TestPlayer2-" .. realm] = { prio = 1 },
            ["TestPlayer3-" .. realm] = { prio = 1 },
            ["TestPlayer4-" .. realm] = { prio = 1 },
            ["TestPlayer5-" .. realm] = { prio = 2 },
            ["TestPlayer6-" .. realm] = { prio = 2 },
            ["TestPlayer7-" .. realm] = { prio = 4 },
        }
    end

    -- Fake-Roll-Ergebnisse für die Prio-1-Spieler (oder vorhandene rollState.players)
    ci.rollState.players = ci.rollState.players
    if not next(ci.rollState.players) then
        ci.rollState.players = {
            TestPlayer1 = true, TestPlayer2 = true,
            TestPlayer3 = true, TestPlayer4 = true,
        }
    end
    ci.rollState.results = { TestPlayer2 = 87, TestPlayer3 = 42 }

    -- Fake-Spieler zu Teilnehmern hinzufügen
    local participants = GuildLootDB.currentRaid.participants
    for name in pairs(ci.candidates) do
        local found = false
        for _, p in ipairs(participants) do if p == name then found = true; break end end
        if not found then table.insert(participants, name) end
    end

    -- Ergebnisse sofort auswerten → Assign-Button direkt aktiv
    GL.Loot.FinalizeRoll()
    GL.Print("Roll simulation: TestPlayer2 won (87) — check the Loot tab to assign.")
end

-- Fügt einen fertigen Loot-Log-Eintrag mit echtem Item aus dem Inventar ein,
-- damit der Analyzer/Export mit itemID-verlinkten Einträgen getestet werden kann.
-- Verhält sich wie ein echter AssignLoot-Eintrag (inkl. itemID, category, difficulty, prio).
function GL.Test.AddLootEntry()
    if not GuildLootDB.activeContainerIdx then
        GL.Print("No active raid. Use /reqrt start first.")
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

    local db  = GuildLootDB
    local idx = db.activeContainerIdx
    if idx and db.raidContainers and db.raidContainers[idx] then
        entry.raidID    = db.currentRaid.id or ""
        entry.sessionID = db.raidContainers[idx].id
        table.insert(db.raidContainers[idx].lootLog, entry)
    end
    GL.Print("Test loot entry added: " .. chosen.link .. " → " .. GL.ShortName(pick.name))
    if GL.UI and GL.UI.RefreshLogTab  then GL.UI.RefreshLogTab()  end
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

-- Füllt currentRaid.pendingLoot mit count Items (ohne Session zu starten).
-- Verwendung: /reqrt testpending [anzahl]   (default 2)
function GL.Test.SimulatePending(count)
    count = tonumber(count) or 2
    if count < 1 or count > 10 then
        GL.Print("testpending: count muss zwischen 1 und 10 liegen.")
        return
    end
    if GuildLootDB.activeContainerIdx then
        GL.Print("testpending: Session ist offen — erst schließen.")
        return
    end
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
        GL.Print("testpending: Kein episches Equip-Item im Inventar gefunden.")
        return
    end
    local itemID   = tonumber(chosen.link:match("item:(%d+)"))
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(chosen.link)
    local category = GL.GetItemCategory(itemID, equipLoc or chosen.equipLoc, chosen.quality)
    local realm = GetRealmName() or "Realm"
    local pl = GuildLootDB.currentRaid.pendingLoot
    for _ = 1, count do
        table.insert(pl, {
            link     = chosen.link,
            name     = chosen.name,
            itemID   = itemID,
            quality  = chosen.quality,
            category = category,
        })
    end
    local fakePlayers = {
        "TestPlayer1-" .. realm,
        "TestPlayer2-" .. realm,
        "TestPlayer3-" .. realm,
        "TestPlayer4-" .. realm,
        "TestPlayer5-" .. realm,
        "TestPlayer6-" .. realm,
    }
    local participants = GuildLootDB.currentRaid.participants
    for _, name in ipairs(fakePlayers) do
        local found = false
        for _, p in ipairs(participants) do if p == name then found = true; break end end
        if not found then table.insert(participants, name) end
    end
    GL.Print(string.format("testpending: %d× %s in pendingLoot.", count, chosen.name))
end

-- Simuliert einen Mehrfach-Drop (count > 1) mit Cross-Tier-Kandidaten.
-- Testet: count-Erkennung, Cross-Tier StartRoll, Top-N FinalizeRoll, Assign All.
-- Verwendung: /reqrt testmulti [anzahl]   (default 2)
function GL.Test.SimulateMultiRoll(count)
    count = tonumber(count) or 2
    if count < 2 or count > 5 then
        GL.Print("testmulti: count muss zwischen 2 und 5 liegen.")
        return
    end

    if not GuildLootDB.activeContainerIdx then
        GL.StartRaid("Test-Tier")
    end

    -- Episches Item aus Inventar suchen
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
        GL.Print("testmulti: No epic item found in inventory.")
        return
    end

    local itemID   = tonumber(chosen.link:match("item:(%d+)"))
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(chosen.link)
    local category = GL.GetItemCategory(itemID, equipLoc or chosen.equipLoc, chosen.quality)

    -- pendingLoot mit `count` Kopien füllen
    local pl = GuildLootDB.currentRaid.pendingLoot
    for _ = 1, count do
        table.insert(pl, {
            link    = chosen.link,
            name    = chosen.name,
            itemID  = itemID,
            quality = chosen.quality,
            category = category,
        })
    end

    -- currentItem direkt befüllen (simuliert ActivateItem ohne echten Timer)
    GL.Loot.ClearCurrentItem()
    local realm = GetRealmName() or "Realm"
    local ci = GL.Loot.GetCurrentItem()
    ci.link      = chosen.link
    ci.name      = chosen.name
    ci.itemID    = itemID
    ci.quality   = chosen.quality
    ci.category  = category
    ci.count     = count
    ci.winners   = {}
    ci._tieReRoll = nil
    ci.prioState  = { active = true, timeLeft = 30, timer = nil }
    ci.rollState  = { active = false, players = {}, results = {}, timer = nil, timeLeft = 0 }

    -- Kandidaten: 1x Prio1, 3x Prio2, 2x Prio4 → Cross-Tier gut abgedeckt
    -- Kandidaten: 1×Prio1, 3×Prio2, 2×Prio4
    ci.candidates = {
        ["TestPlayer1-" .. realm] = { prio = 1 },
        ["TestPlayer2-" .. realm] = { prio = 2 },
        ["TestPlayer3-" .. realm] = { prio = 2 },
        ["TestPlayer4-" .. realm] = { prio = 2 },
        ["TestPlayer5-" .. realm] = { prio = 4 },
        ["TestPlayer6-" .. realm] = { prio = 4 },
    }

    local participants = GuildLootDB.currentRaid.participants
    for name in pairs(ci.candidates) do
        local found = false
        for _, p in ipairs(participants) do if p == name then found = true; break end end
        if not found then table.insert(participants, name) end
    end

    -- Cross-Tier Roll simulieren: Prio1 + Prio2 rollen (1+3=4 >= count)
    -- Fake-Ergebnisse: TestPlayer1=72 (Prio1→immer #1), TestPlayer3=88 (bester Prio2)
    ci.rollState.active  = true
    ci.rollState.players = {
        TestPlayer1 = true, TestPlayer2 = true,
        TestPlayer3 = true, TestPlayer4 = true,
    }
    ci.rollState.results = {
        TestPlayer1 = 72,
        TestPlayer2 = 55,
        TestPlayer3 = 88,
        TestPlayer4 = 33,
    }

    -- Direkt auswerten → Winners werden gesetzt, "Assign All (N)" erscheint
    GL.Loot.FinalizeRoll()

    GL.Print("testmulti: " .. count .. "x Drop simuliert — Gewinner bestimmt. 'Assign All (" .. count .. ")' klicken.")
end

-- Erstellt einen Unassigned-Raid-Snapshot (ohne Session) mit Fake-Loot-Einträgen.
-- Verwendung: /reqrt testunassigned
function GL.Test.AddUnassignedRaid()
    local db    = GuildLootDB
    local realm = GetRealmName() or "Realm"
    local ts    = time() - math.random(3, 14) * 86400

    local fakeItems = {
        { link = "|cffa335ee|Hitem:212426::::::::80:::::|h[Ovi'nax's Mercurial Egg]|h|r",   name = "Ovi'nax's Mercurial Egg",   category = "trinket" },
        { link = "|cffa335ee|Hitem:212436::::::::80:::::|h[Sikran's Shadow Scepter]|h|r",    name = "Sikran's Shadow Scepter",    category = "weapons" },
        { link = "|cffa335ee|Hitem:212449::::::::80:::::|h[Ansurek's Silken Wraps]|h|r",     name = "Ansurek's Silken Wraps",     category = "other"   },
    }
    local fakePlayers = {
        "Myriella-Malfurion", "Darbolosch-Malfurion", "Borgotho-Antonidas",
    }
    local diffs = { "N", "H", "M" }
    local diff  = diffs[math.random(#diffs)]

    local raidID = string.format("%08x", ts % 0xFFFFFFFF)
    local lootLog = {}
    for i = 1, math.random(2, 3) do
        local item   = fakeItems[((i - 1) % #fakeItems) + 1]
        local player = fakePlayers[((i - 1) % #fakePlayers) + 1]
        table.insert(lootLog, {
            player     = player .. "-" .. realm,
            item       = item.name,
            link       = item.link,
            category   = item.category,
            difficulty = diff,
            winnerPrio = (i % 2 == 0) and 2 or 1,
            timestamp  = ts + i * 300,
            raidID     = raidID,
        })
    end

    local snap = {
        id           = raidID,
        tier         = "Nerub'ar Palace",
        difficulty   = diff,
        startedAt    = ts,
        closedAt     = ts + 5400,
        participants = fakePlayers,
        lootLog      = lootLog,
        trashedLoot  = {},
    }

    db.unassignedRaids = db.unassignedRaids or {}
    table.insert(db.unassignedRaids, snap)
    GL.Print(string.format("testunassigned: Unassigned Raid '%s %s' mit %d Loot-Einträgen erstellt.",
        snap.tier, diff, #lootLog))
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end

-- Erstellt eine vollständige Test-Session mit zwei Raids und mehreren Loot-Einträgen.
-- Kein Inventar nötig — verwendet Hard-coded Item-IDs aus Nerub'ar Palace.
-- Verwendung: /reqrt testsetup
function GL.Test.SetupTestSession()
    local db = GuildLootDB
    if db.activeContainerIdx then
        GL.Print("testsetup: Erst aktive Session schließen.")
        return
    end

    local realm = GetRealmName() or "Realm"
    local fakeItems = {
        { link = "|cffa335ee|Hitem:212426::::::::80:::::|h[Ovi'nax's Mercurial Egg]|h|r",   name = "Ovi'nax's Mercurial Egg",   category = "trinket"  },
        { link = "|cffa335ee|Hitem:212449::::::::80:::::|h[Ansurek's Silken Wraps]|h|r",     name = "Ansurek's Silken Wraps",     category = "other"    },
        { link = "|cffa335ee|Hitem:212436::::::::80:::::|h[Sikran's Shadow Scepter]|h|r",    name = "Sikran's Shadow Scepter",    category = "weapons"  },
        { link = "|cffa335ee|Hitem:212429::::::::80:::::|h[Nexus-Princess' Pursuit]|h|r",    name = "Nexus-Princess' Pursuit",    category = "trinket"  },
        { link = "|cffa335ee|Hitem:212456::::::::80:::::|h[Web-Weaver's Wristguards]|h|r",   name = "Web-Weaver's Wristguards",   category = "other"    },
        { link = "|cffa335ee|Hitem:212433::::::::80:::::|h[Voidweaver's Astral Bangle]|h|r", name = "Voidweaver's Astral Bangle", category = "other"    },
    }
    local fakePlayers = {
        "Myriella-Malfurion", "Darbolosch-Malfurion", "Borgotho-Antonidas",
        "Valourstrasz-Silvermoon", "Øneshoot-Malfurion", "Barbossbär-Antonidas",
    }
    local bosses1 = { "Ulgrax the Devourer", "The Bloodbound Horror", "Sikran" }
    local bosses2 = { "Nexus-Princess Ky'veza", "The Silken Court", "Queen Ansurek" }

    -- Raid-ID-Helfer
    local function fakeRaidID(tier, diff, ts)
        return string.format("%08x", (ts + #tier + #diff) % 0xFFFFFFFF)
    end

    -- Session anlegen
    local ts = time() - 7 * 86400  -- eine Woche her
    local kw = tonumber(date("%V", ts))
    local yr = tonumber(date("%Y", ts))
    local session = {
        id          = string.format("%04d-W%02d-testdata", yr, kw),
        label       = string.format("KW %02d %d (Test)", kw, yr),
        startedAt   = ts,
        closedAt    = ts + 14400,
        lootLog     = {},
        trashedLoot = {},
        raidMeta    = {},
    }

    -- Raid 1: Mythic, Nerub'ar Palace
    local r1id = fakeRaidID("Nerub'ar Palace", "M", ts)
    session.raidMeta[r1id] = {
        tier         = "Nerub'ar Palace",
        difficulty   = "M",
        startedAt    = ts,
        closedAt     = ts + 7200,
        participants = fakePlayers,
    }
    for i = 1, 4 do
        local item   = fakeItems[i]
        local player = fakePlayers[((i - 1) % #fakePlayers) + 1]
        table.insert(session.lootLog, {
            player     = player .. "-" .. realm,
            item       = item.name,
            link       = item.link,
            category   = item.category,
            difficulty = "M",
            winnerPrio = (i % 2 == 0) and 2 or 1,
            boss       = bosses1[((i - 1) % #bosses1) + 1],
            timestamp  = ts + i * 300,
            raidID     = r1id,
            sessionID  = session.id,
        })
    end

    -- Raid 2: Heroic, Nerub'ar Palace
    local r2ts = ts + 86400
    local r2id = fakeRaidID("Nerub'ar Palace", "H", r2ts)
    session.raidMeta[r2id] = {
        tier         = "Nerub'ar Palace",
        difficulty   = "H",
        startedAt    = r2ts,
        closedAt     = r2ts + 5400,
        participants = fakePlayers,
    }
    for i = 5, 6 do
        local item   = fakeItems[i]
        local player = fakePlayers[((i - 1) % #fakePlayers) + 1]
        table.insert(session.lootLog, {
            player     = player .. "-" .. realm,
            item       = item.name,
            link       = item.link,
            category   = item.category,
            difficulty = "H",
            winnerPrio = 1,
            boss       = bosses2[((i - 1) % #bosses2) + 1],
            timestamp  = r2ts + (i - 4) * 400,
            raidID     = r2id,
            sessionID  = session.id,
        })
    end

    table.insert(db.raidContainers, session)
    GL.Print(string.format("testsetup: Session '%s' mit 2 Raids und %d Loot-Einträgen erstellt.",
        session.label, #session.lootLog))
    if GL.UI and GL.UI.Refresh then GL.UI.Refresh() end
end
