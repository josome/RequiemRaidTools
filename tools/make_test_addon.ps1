# make_test_addon.ps1
# Generiert RaidLootTracker_Test aus dem Haupt-Addon.
# Ausfuehren: powershell -ExecutionPolicy Bypass -File tools\make_test_addon.ps1

$src = "$PSScriptRoot\..\RaidLootTracker"
$dst = "$PSScriptRoot\..\RaidLootTracker_Test"

Write-Host "Source: $src"
Write-Host "Target: $dst"

if (Test-Path $dst) {
    Remove-Item $dst -Recurse -Force
    Write-Host "Removed existing $dst"
}

Copy-Item $src $dst -Recurse
Write-Host "Copied source to $dst"

# Lua + TOC: Namespace und DB-Name ersetzen
Get-ChildItem $dst -Recurse -Include *.lua, *.toc | ForEach-Object {
    $content = Get-Content $_.FullName -Raw -Encoding UTF8
    $content = $content -replace 'GuildLootDB', 'GuildLootDBTest'
    $content = $content -replace '\bGuildLoot\b', 'GuildLootTest'
    # Frame-Namen in String-Literalen: "GuildLoot..." → "GuildLootTest..." (Regex \b greift nicht vor Großbuchstaben)
    $content = $content -replace '"GuildLoot', '"GuildLootTest'
    Set-Content $_.FullName $content -Encoding UTF8 -NoNewline
}
Write-Host "Replaced namespaces in Lua/TOC files"

# TOC umbenennen
Rename-Item "$dst\RaidLootTracker.toc" "RaidLootTracker_Test.toc"

# TOC-Inhalt anpassen
$toc = Get-Content "$dst\RaidLootTracker_Test.toc" -Raw -Encoding UTF8
$toc = $toc -replace '(## Title:)[^\r\n]*', '## Title: RLT Observer (Test)'
$toc = $toc -replace '(## SavedVariables:)[^\r\n]*', '## SavedVariables: GuildLootDBTest'
## Version wird direkt aus dem Stable-TOC übernommen (enthält bereits -beta)
Set-Content "$dst\RaidLootTracker_Test.toc" $toc -Encoding UTF8 -NoNewline

Write-Host "TOC updated."
Write-Host ""
Write-Host "Done! Test addon at: $dst"
Write-Host ""
Write-Host "Wenn noch kein Symlink existiert, einmalig als Administrator ausfuehren:"
Write-Host '  mklink /D "C:\...\Interface\AddOns\RaidLootTracker_Test" "' + $dst + '"'
