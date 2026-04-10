#!/bin/bash
# make_test_addon.sh
# Generiert RequiemRaidTools_Test aus dem Haupt-Addon.
# Ausfuehren: bash test/make_test_addon.sh

SRC="$(dirname "$0")/../src"
TOCFILE="$(dirname "$0")/../RequiemRaidTools.toc"
DST="$(dirname "$0")/../RequiemRaidTools_Test"

echo "Source: $SRC"
echo "Target: $DST"

# Altes Test-Addon entfernen
if [ -d "$DST" ]; then
    rm -rf "$DST"
    echo "Removed existing $DST"
fi

# Kopieren
cp -r "$SRC/." "$DST"
cp "$TOCFILE" "$DST/RequiemRaidTools.toc"
echo "Copied source to $DST"

# TOC-Pfade anpassen: src/ und test/ Prefixe entfernen (Test-Addon hat flache Struktur)
sed -i 's|^src/||g' "$DST/RequiemRaidTools.toc"
sed -i 's|^test/||g' "$DST/RequiemRaidTools.toc"

# Lua + TOC: alle Namen ersetzen die WoW-weit eindeutig sein muessen
find "$DST" -type f \( -name "*.lua" -o -name "*.toc" \) | while read -r file; do
    # SavedVariables und Lua-Namespace
    sed -i 's/GuildLootDB/GuildLootDBTest/g' "$file"
    sed -i 's/\bGuildLoot\b/GuildLootTest/g' "$file"
    # Frame-Namen in String-Literalen: "GuildLoot..." → "GuildLootTest..." (\b greift nicht vor Großbuchstaben)
    sed -i 's/"GuildLoot/"GuildLootTest/g' "$file"
    # Addon-Name im ADDON_LOADED-Check
    sed -i 's/"RequiemRaidTools"/"RequiemRaidTools_Test"/g' "$file"
    # Slash-Command umbenennen: /reqrt -> /reqrtt
    sed -i 's|SLASH_REQUIEMRAIDTOOLS|SLASH_REQUIEMRAIDTOOLSTEST|g' "$file"
    sed -i 's|SlashCmdList\["REQUIEMRAIDTOOLS"\]|SlashCmdList["REQUIEMRAIDTOOLSTEST"]|g' "$file"
    sed -i "s|SLASH_REQUIEMRAIDTOOLSTEST1 = \"/reqrt\"|SLASH_REQUIEMRAIDTOOLSTEST1 = \"/reqrtt\"|g" "$file"
    # Hardcodierte WoW-Frame-Namen (RaidLoot* und RLT_*)
    sed -i 's/RequiemRaidToolsMinimapButton/RequiemRaidToolsTestMinimapButton/g' "$file"
    sed -i 's/RaidLootExportPopup/RaidLootTestExportPopup/g' "$file"
    sed -i 's/RaidLootExportScroll/RaidLootTestExportScroll/g' "$file"
    sed -i 's/RLT_ML_REQUEST/RLTT_ML_REQUEST/g' "$file"
done
echo "Replaced namespaces and frame names in Lua/TOC files"

# TOC umbenennen
mv "$DST/RequiemRaidTools.toc" "$DST/RequiemRaidTools_Test.toc"

# TOC-Inhalt anpassen
sed -i 's/## Title:.*/## Title: RLT Observer (Test)/' "$DST/RequiemRaidTools_Test.toc"
sed -i 's/## SavedVariables:.*/## SavedVariables: GuildLootDBTest/' "$DST/RequiemRaidTools_Test.toc"
# Version wird direkt aus dem Stable-TOC übernommen (enthält bereits -beta)

# Test.lua im Observer nicht benötigt
rm -f "$DST/Test.lua"
sed -i '/Test.lua/d' "$DST/RequiemRaidTools_Test.toc"
echo "Removed Test.lua from Observer addon"

echo "TOC updated."
echo ""
echo "Done! Test addon at: $DST"
