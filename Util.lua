-- GuildLoot – Util.lua
-- Hilfsfunktionen (keine WoW-Events, keine Frames)

GuildLoot = GuildLoot or {}
local GL = GuildLoot

-- ============================================================
-- Kategorie-Erkennung
-- ============================================================

local WEAPON_SLOTS = {
    INVTYPE_WEAPON         = true,
    INVTYPE_MAINHAND       = true,
    INVTYPE_OFFHAND        = true,
    INVTYPE_2HWEAPON       = true,
    INVTYPE_RANGED         = true,
    INVTYPE_RANGEDRIGHT    = true,
    INVTYPE_SHIELD         = true,
    INVTYPE_HOLDABLE       = true,
}

-- Temporärer unsichtbarer Tooltip für Tooltip-Scans
local scanTooltip = CreateFrame("GameTooltip", "GuildLootScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- Prüft ob ein Item eine Klassen-Einschränkung im Tooltip hat (Token-Erkennung)
local function HasClassRestriction(itemID)
    scanTooltip:ClearLines()
    scanTooltip:SetItemByID(itemID)
    for i = 1, scanTooltip:NumLines() do
        local line = _G["GuildLootScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText() or ""
            -- DE: "Klassen:", EN: "Classes:"
            if text:find("[Kk]lassen:") or text:find("[Cc]lasses:") then
                return true
            end
        end
    end
    return false
end

--- Bestimmt die Loot-Kategorie eines Items.
--- @param itemID number
--- @param itemEquipLoc string  z.B. "INVTYPE_WEAPON"
--- @param quality number       Blizzard item quality (4=epic, 5=legendary)
--- @return string  "setItems"|"weapons"|"trinket"|"other"
function GL.GetItemCategory(itemID, itemEquipLoc, quality)
    -- 1. Direkte Tier-Teile (Set-Armor mit Set-ID)
    if C_Item and C_Item.GetItemSetID then
        local setID = C_Item.GetItemSetID(itemID)
        if setID and setID ~= 0 then
            return "setItems"
        end
    end

    -- 2. Klassen-Token (kein Equip-Slot, Epic+, hat Klassen-Einschränkung)
    if (itemEquipLoc == "" or itemEquipLoc == "INVTYPE_NON_EQUIP_IGNORE") and quality >= 4 then
        if HasClassRestriction(itemID) then
            return "setItems"
        end
    end

    -- 3. Waffe
    if WEAPON_SLOTS[itemEquipLoc] then
        return "weapons"
    end

    -- 4. Trinket
    if itemEquipLoc == "INVTYPE_TRINKET" then
        return "trinket"
    end

    -- 5. Alles andere
    return "other"
end

-- ============================================================
-- Schwierigkeitsgrad-Erkennung
-- ============================================================

--- Erkennt N/H/M:
--- 1. Primär: GetInstanceInfo() difficultyID (zuverlässig wenn in Instanz)
--- 2. Fallback: Item-Level-Ranges
--- @return string|nil  "N"|"H"|"M" oder nil
function GL.DetectDifficulty(itemLevel)
    -- Primär: Instanz-Schwierigkeit direkt auslesen
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType == "raid" or instanceType == "party" then
        if difficultyID == 14 or difficultyID == 1  then return "N" end
        if difficultyID == 15 or difficultyID == 2  then return "H" end
        if difficultyID == 16 or difficultyID == 8  then return "M" end
        if difficultyID == 17                        then return "N" end  -- LFR
    end

    -- Fallback: Item-Level-Ranges
    if not itemLevel then return nil end
    local ranges = GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.difficultyRanges
    if not ranges then return nil end

    if itemLevel >= ranges.N.min and itemLevel <= ranges.N.max then return "N" end
    if itemLevel >= ranges.H.min and itemLevel <= ranges.H.max then return "H" end
    if itemLevel >= ranges.M.min and itemLevel <= ranges.M.max then return "M" end

    return nil
end

-- ============================================================
-- Chat-Parsing
-- ============================================================

--- Extrahiert die führende Prio-Zahl (1–4) aus einer Chat-Nachricht.
--- Akzeptiert: "1", "2", "1up", "1bis", "2 UP" etc.
--- @param message string
--- @return number|nil  1–4 oder nil
function GL.ParseLootInput(message)
    if not message then return nil end
    local digit = message:match("^%s*([1-4])")
    if digit then
        return tonumber(digit)
    end
    return nil
end

-- ============================================================
-- Hilfsfunktionen
-- ============================================================

function GL.IsOfficer()
    return UnitIsOfficer and UnitIsOfficer("player") or false
end

function GL.IsMasterLooter()
    return GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.isMasterLooter == true
end

function GL.GetTimestamp()
    return time()
end

function GL.FormatTimestamp(ts)
    if not ts then return "" end
    return date("%d.%m.%Y %H:%M", ts)
end

--- Gibt den Namen in Klassenfarbe zurück (nutzt RAID_CLASS_COLORS wie native WoW-Addons)
function GL.ColoredName(name, classFileName)
    if not classFileName then return name end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFileName]
    if c then
        return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name)
    end
    return name
end

function GL.TableContains(t, value)
    for _, v in ipairs(t) do
        if v == value then return true end
    end
    return false
end

--- Gibt den kürzesten Spielernamen zurück (ohne Realm wenn gleicher Realm)
function GL.ShortName(fullName)
    if not fullName then return "" end
    local name = fullName:match("^([^%-]+)")
    return name or fullName
end
