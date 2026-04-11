-- RequiemRaidTools – Loot.lua
-- Kern: Shared State, Pending/Trash-Verwaltung, Loot-Erkennung
-- Roll-Logik: Loot_Roll.lua | Zuweisung: Loot_Assign.lua | Handel: Loot_Trade.lua

GuildLoot = GuildLoot or {}
local GL = GuildLoot
GL.Loot = GL.Loot or {}
local Loot = GL.Loot

-- ============================================================
-- Modul-lokaler Zustand (nicht persistent)
-- ============================================================

-- Offene Handelszuweisungen: { { itemID=N, shortName="X" }, ... }
-- Wird befüllt wenn ML ein Item zuweist; bei TRADE_SHOW abgeglichen.
Loot._pendingTrades = {}

-- Items die gerade im Handelsfenster liegen (Staging).
-- Werden erst bei erfolgreichem Handel endgültig verworfen; bei Abbruch zurück in _pendingTrades.
Loot._inTradeItems = {}

-- Items aus OnLootOpened/AddItemManually die noch auf GetItemInfo warten
Loot._deferredPendingItems = {}

-- pendingLoot wird direkt aus GuildLootDB gelesen (überlebt Reloads)
local function pendingLoot() return GuildLootDB.currentRaid.pendingLoot end
local function trashedLoot() return GuildLootDB.currentRaid.trashedLoot or {} end
local currentItem  = {
    link       = nil,
    name       = nil,
    itemID     = nil,
    itemLevel  = nil,
    category   = nil,
    candidates = {},   -- { [name] = { prio=1 } }
    prioState  = {     -- Prio-Sammelphase
        active   = false,
        timeLeft = 0,
        timer    = nil,
    },
    rollState  = {
        active   = false,
        players  = {},   -- set von Namen die rollen dürfen
        results  = {},   -- { [name] = rollValue }
        timer    = nil,
        timeLeft = 0,
    },
    winner     = nil,
    count      = 1,    -- Anzahl verfügbarer Kopien dieses Items
    winners    = {},   -- { shortName, ... } bei count > 1
    _tieReRoll = nil,  -- { confirmedWinners={}, spotsNeeded=N } während Tie-Re-Roll
}

-- Bereits verarbeitete Roll-IDs (verhindert Doppelverarbeitung bei mehrfachem Event-Fire)
local processedRolls = {}

-- ============================================================
-- Zugriffs-Helfer
-- ============================================================

function Loot.GetPendingLoot()  return pendingLoot()  end
function Loot.GetTrashedLoot()  return trashedLoot()  end
function Loot.GetCurrentItem()  return currentItem  end

-- Fügt ein Item manuell zur pendingLoot hinzu (bypass filter)
function Loot.AddItemManually(link)
    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return end

    local name, _, quality, _, _, _, _, _, equipLoc = GetItemInfo(link)
    if not name then
        -- Item-Info noch nicht gecacht → deferred
        table.insert(Loot._deferredPendingItems, { link = link, itemID = itemID, quality = 0, name = "?", manual = true })
        return
    end

    local category = GL.GetItemCategory(itemID, equipLoc or "", quality or 0)
    local item = { link = link, name = name, itemID = itemID, quality = quality or 0, category = category }
    table.insert(pendingLoot(), item)
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
    GL.Print("Item manuell hinzugefügt: " .. link)
end

-- Prüft Loot-Filter und fügt Item ggf. in pendingLoot ein
-- Prüft ob ein Item Warbound ist (nicht tradebar → uninteressant für Loot-Verteilung)
-- Enum.ItemBind: 8 = ToBnetAccount, 9 = ToBnetAccountUntilEquipped (warcraft.wiki.gg/wiki/Enum.ItemBind)
local function IsWarboundItem(itemID)
    local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(itemID)
    return bindType == 8 or bindType == 9
end

function Loot.TryAddPendingItem(item, equipLoc)
    local s = GuildLootDB.settings
    local category = GL.GetItemCategory(item.itemID, equipLoc, item.quality)

    -- Filter: Warbound Items (nicht tradebar)
    if IsWarboundItem(item.itemID) then return end

    -- Filter: nicht-ausrüstbare Items (Handwerksmaterialien, Reagenzien, etc.)
    if s.filterNonEquip then
        local isEquip = equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
        -- Ausnahme: Class-Tokens haben equipLoc="" sind aber "setItems"
        if not isEquip and category ~= "setItems" then return end
    end

    -- Filter: Kategorie-Filter
    local fc = s.filterCategories
    if fc and fc[category] == false then return end

    item.category = category
    table.insert(pendingLoot(), item)
end

-- ============================================================
-- Loot-Erkennung (LOOT_OPENED)
-- ============================================================

function Loot.OnLootOpened()
    if not GL.IsMasterLooter() then return end  -- Observer ignorieren das Loot-Fenster
    local minQ = GuildLootDB.settings.minQuality or 4

    -- Alle qualifizierten Items aus dem Loot-Fenster sammeln
    local lootItems = {}
    for slot = 1, GetNumLootItems() do
        local _, name, _, _, quality, _, isQuestItem = GetLootSlotInfo(slot)
        if quality and quality >= minQ and not isQuestItem then
            local link = GetLootSlotLink(slot)
            if link then
                local itemID = tonumber(link:match("item:(%d+)"))
                table.insert(lootItems, { link = link, name = name or "?", itemID = itemID, quality = quality })
            end
        end
    end

    -- Wie oft ist jeder Link bereits in pendingLoot?
    local pendingCounts = {}
    for _, p in ipairs(pendingLoot()) do
        pendingCounts[p.link] = (pendingCounts[p.link] or 0) + 1
    end

    -- Nur Items hinzufügen die noch nicht (oder nicht oft genug) in pendingLoot sind
    -- → erlaubt mehrfache Drops desselben Items
    local lootCounts = {}
    local toAdd = {}
    for _, item in ipairs(lootItems) do
        lootCounts[item.link] = (lootCounts[item.link] or 0) + 1
        if lootCounts[item.link] > (pendingCounts[item.link] or 0) then
            table.insert(toAdd, item)
        end
    end

    if #toAdd > 0 then
        for _, item in ipairs(toAdd) do
            local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(item.link)
            if equipLoc ~= nil then
                Loot.TryAddPendingItem(item, equipLoc)
            else
                table.insert(Loot._deferredPendingItems, item)
            end
        end
        if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
    end
end

function Loot.OnLootClosed()
    -- pendingLoot einfrieren — Liste bleibt erhalten bis alle Items vergeben sind
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

-- Wird bei START_LOOT_ROLL aufgerufen: erkennt Items aus WoW's Group-Loot-Roll-Fenster
-- und fügt sie zu pendingLoot hinzu — auch wenn der ML die Leiche nie selbst geöffnet hat.
function Loot.OnLootRollStart(rollID)
    if not GL.IsMasterLooter() then return end
    if not GuildLootDB.currentRaid.active then return end
    if processedRolls[rollID] then return end
    processedRolls[rollID] = true

    local link = GetLootRollItemLink(rollID)
    if not link then return end

    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return end

    -- Qualitätsfilter: GetLootRollItemInfo gibt u.a. quality zurück
    local minQ = GuildLootDB.settings.minQuality or 4
    local _, name, _, quality = GetLootRollItemInfo(rollID)
    if not quality or quality < minQ then return end

    -- equipLoc für Kategorie-Erkennung (GetItemInfo ist gecacht wenn Item bekannt)
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    local item = { link = link, name = name or "?", itemID = itemID, quality = quality }

    if equipLoc ~= nil then
        Loot.TryAddPendingItem(item, equipLoc)
    else
        -- GetItemInfo noch nicht verfügbar → deferred (GET_ITEM_INFO_RECEIVED löst aus)
        table.insert(Loot._deferredPendingItems, item)
    end

    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

-- ============================================================
-- Pending/Trash Verwaltung
-- ============================================================

function Loot.RemovePendingItem(link)
    if not GL.IsMasterLooter() then return end
    local pl = pendingLoot()
    for i, p in ipairs(pl) do
        if p.link == link then
            table.insert(trashedLoot(), p)  -- in Trash verschieben statt löschen
            table.remove(pl, i)
            break
        end
    end
    if currentItem.link == link then
        Loot.ClearCurrentItem()
        if GL.Comm then GL.Comm.SendItemClear() end
    end
end

function Loot.RestoreFromTrash(link)
    if not GL.IsMasterLooter() then return end
    local tl = trashedLoot()
    for i, p in ipairs(tl) do
        if p.link == link then
            table.insert(pendingLoot(), p)
            table.remove(tl, i)
            break
        end
    end
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

function Loot.DeleteFromTrash(link)
    if not GL.IsMasterLooter() then return end
    local tl = trashedLoot()
    for i, p in ipairs(tl) do
        if p.link == link then
            table.remove(tl, i)
            break
        end
    end
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

function Loot.TrashActiveItem()
    if not GL.IsMasterLooter() then return end
    local link = currentItem.link
    if not link then return end
    Loot.ClearCurrentItem()
    if GL.Comm then GL.Comm.SendItemClear() end
    Loot.RemovePendingItem(link)
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

function Loot.ResetCurrentItem()
    if not GL.IsMasterLooter() then return end
    local itemLink = currentItem.link
    Loot.ClearCurrentItem()
    if GL.Comm then GL.Comm.SendItemClear() end
    GL.Print("Item reset: " .. (itemLink or "?"))
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end

function Loot.CancelPrio()
    if not GL.IsMasterLooter() then return end
    if not currentItem.prioState.active then return end
    Loot.ClearCurrentItem()
    if GL.Comm then GL.Comm.SendItemClear() end
    GL.Print("Prio phase cancelled.")
    if GL.UI and GL.UI.RefreshLootTab then GL.UI.RefreshLootTab() end
end
