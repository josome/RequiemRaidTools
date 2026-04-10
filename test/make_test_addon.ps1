# make_test_addon.ps1
# Generiert RequiemRaidTools_Test aus dem Haupt-Addon.
# Ausfuehren: powershell -ExecutionPolicy Bypass -File test\make_test_addon.ps1

$src = "$PSScriptRoot\..\src"
$tocFile = "$PSScriptRoot\..\RequiemRaidTools.toc"
$dst = "$PSScriptRoot\..\RequiemRaidTools_Test"

Write-Host "Source: $src"
Write-Host "Target: $dst"

if (Test-Path $dst) {
    Remove-Item $dst -Recurse -Force
    Write-Host "Removed existing $dst"
}

Copy-Item "$src\*" $dst -Recurse
Copy-Item $tocFile "$dst\RequiemRaidTools.toc"
Write-Host "Copied source to $dst"

# TOC-Pfade anpassen: src/ Prefix entfernen (Test-Addon hat flache Struktur)
$toc = Get-Content "$dst\RequiemRaidTools.toc" -Raw -Encoding UTF8
$toc = $toc -replace '(?m)^src/', ''
Set-Content "$dst\RequiemRaidTools.toc" $toc -Encoding UTF8 -NoNewline

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
Rename-Item "$dst\RequiemRaidTools.toc" "RequiemRaidTools_Test.toc"

# TOC-Inhalt anpassen
$toc = Get-Content "$dst\RequiemRaidTools_Test.toc" -Raw -Encoding UTF8
$toc = $toc -replace '(## Title:)[^\r\n]*', '## Title: RLT Observer (Test)'
$toc = $toc -replace '(## SavedVariables:)[^\r\n]*', '## SavedVariables: GuildLootDBTest'
## Version wird direkt aus dem Stable-TOC übernommen (enthält bereits -beta)
Set-Content "$dst\RequiemRaidTools_Test.toc" $toc -Encoding UTF8 -NoNewline

Write-Host "TOC updated."
Write-Host ""
Write-Host "Done! Test addon at: $dst"
Write-Host ""
Write-Host "Wenn noch kein Symlink existiert, einmalig als Administrator ausfuehren:"
Write-Host '  mklink /D "C:\...\Interface\AddOns\RequiemRaidTools_Test" "' + $dst + '"'
