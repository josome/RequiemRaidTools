#!/bin/bash
# make_test_addon.sh
# Generiert RaidLootTracker_Test aus dem Haupt-Addon.
# Ausfuehren: bash tools/make_test_addon.sh

SRC="$(dirname "$0")/../RaidLootTracker"
DST="$(dirname "$0")/../RaidLootTracker_Test"

echo "Source: $SRC"
echo "Target: $DST"

# Altes Test-Addon entfernen
if [ -d "$DST" ]; then
    rm -rf "$DST"
    echo "Removed existing $DST"
fi

# Kopieren
cp -r "$SRC" "$DST"
echo "Copied source to $DST"

# Lua + TOC: alle Namen ersetzen die WoW-weit eindeutig sein muessen
find "$DST" -type f \( -name "*.lua" -o -name "*.toc" \) | while read -r file; do
    # SavedVariables und Lua-Namespace
    sed -i 's/GuildLootDB/GuildLootDBTest/g' "$file"
    sed -i 's/\bGuildLoot\b/GuildLootTest/g' "$file"
    # Frame-Namen in String-Literalen: "GuildLoot..." → "GuildLootTest..." (\b greift nicht vor Großbuchstaben)
    sed -i 's/"GuildLoot/"GuildLootTest/g' "$file"
    # Addon-Name im ADDON_LOADED-Check
    sed -i 's/"RaidLootTracker"/"RaidLootTracker_Test"/g' "$file"
    # Slash-Command umbenennen: /rlt -> /rltt
    sed -i 's|SLASH_RAIDLOOTTRACKER|SLASH_RAIDLOOTTRACKERTEST|g' "$file"
    sed -i 's|SlashCmdList\["RAIDLOOTTRACKER"\]|SlashCmdList["RAIDLOOTTRACKERTEST"]|g' "$file"
    sed -i "s|SLASH_RAIDLOOTTRACKER1 = \"/rlt\"|SLASH_RAIDLOOTTRACKERTEST1 = \"/rltt\"|g" "$file"
    # Hardcodierte WoW-Frame-Namen (RaidLoot* und RLT_*)
    sed -i 's/RaidLootTrackerMinimapButton/RaidLootTrackerTestMinimapButton/g' "$file"
    sed -i 's/RaidLootExportPopup/RaidLootTestExportPopup/g' "$file"
    sed -i 's/RaidLootExportScroll/RaidLootTestExportScroll/g' "$file"
    sed -i 's/RLT_ML_REQUEST/RLTT_ML_REQUEST/g' "$file"
done
echo "Replaced namespaces and frame names in Lua/TOC files"

# TOC umbenennen
mv "$DST/RaidLootTracker.toc" "$DST/RaidLootTracker_Test.toc"

# TOC-Inhalt anpassen
sed -i 's/## Title:.*/## Title: RLT Observer (Test)/' "$DST/RaidLootTracker_Test.toc"
sed -i 's/## SavedVariables:.*/## SavedVariables: GuildLootDBTest/' "$DST/RaidLootTracker_Test.toc"
# Version wird direkt aus dem Stable-TOC übernommen (enthält bereits -beta)

# Test.lua im Observer nicht benötigt
rm -f "$DST/Test.lua"
sed -i '/Test.lua/d' "$DST/RaidLootTracker_Test.toc"
echo "Removed Test.lua from Observer addon"

echo "TOC updated."
echo ""
echo "Done! Test addon at: $DST"
