Add-Type -AssemblyName System.Drawing

$inputPath  = "$PSScriptRoot\treasure_chest2.png"
$outputDir  = "$PSScriptRoot\..\Media"
$outputPath = "$outputDir\icon.tga"

New-Item -ItemType Directory -Force $outputDir | Out-Null

# Laden und auf 64x64 skalieren
$src = [System.Drawing.Image]::FromFile((Resolve-Path $inputPath))
$bmp = New-Object System.Drawing.Bitmap(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($src, 0, 0, 64, 64)
$g.Dispose(); $src.Dispose()

# Weißen Hintergrund entfernen via Flood-Fill von den Ecken (Toleranz 25)
$tolerance = 25
$queue = New-Object System.Collections.Generic.Queue[System.Drawing.Point]
$visited = New-Object 'bool[,]' 64, 64

function IsWhitish($pixel) {
    return $pixel.R -ge (255 - $tolerance) -and
           $pixel.G -ge (255 - $tolerance) -and
           $pixel.B -ge (255 - $tolerance)
}

# Seed: alle vier Ecken
@([System.Drawing.Point]::new(0,0), [System.Drawing.Point]::new(63,0),
  [System.Drawing.Point]::new(0,63), [System.Drawing.Point]::new(63,63)) | ForEach-Object {
    $p = $bmp.GetPixel($_.X, $_.Y)
    if (IsWhitish $p) {
        $queue.Enqueue($_)
        $visited[$_.X, $_.Y] = $true
    }
}

$dirs = @([System.Drawing.Point]::new(1,0), [System.Drawing.Point]::new(-1,0),
          [System.Drawing.Point]::new(0,1), [System.Drawing.Point]::new(0,-1))

while ($queue.Count -gt 0) {
    $cur = $queue.Dequeue()
    $bmp.SetPixel($cur.X, $cur.Y, [System.Drawing.Color]::FromArgb(0, 255, 255, 255))
    foreach ($d in $dirs) {
        $nx = $cur.X + $d.X; $ny = $cur.Y + $d.Y
        if ($nx -ge 0 -and $nx -lt 64 -and $ny -ge 0 -and $ny -lt 64 -and -not $visited[$nx, $ny]) {
            $np = $bmp.GetPixel($nx, $ny)
            if (IsWhitish $np) {
                $visited[$nx, $ny] = $true
                $queue.Enqueue([System.Drawing.Point]::new($nx, $ny))
            }
        }
    }
}

# TGA schreiben (Typ 2, 32bpp BGRA, top-left origin)
$header = [byte[]]@(
    0, 0, 2,          # kein ID, kein Colormap, True-Color
    0, 0, 0, 0, 0,    # Colormap-Spec (leer)
    0, 0, 0, 0,       # X/Y Origin
    64, 0, 64, 0,     # Breite / Höhe (little-endian)
    32,               # Bits per Pixel
    0x28              # Image descriptor: 8 Alpha-Bits, top-left origin
)

$pixels = New-Object byte[] (64 * 64 * 4)
$i = 0
for ($y = 0; $y -lt 64; $y++) {   # top-to-bottom (passend zu 0x28)
    for ($x = 0; $x -lt 64; $x++) {
        $p = $bmp.GetPixel($x, $y)
        $pixels[$i++] = $p.B
        $pixels[$i++] = $p.G
        $pixels[$i++] = $p.R
        $pixels[$i++] = $p.A
    }
}
$bmp.Dispose()

$stream = [System.IO.File]::OpenWrite($outputPath)
$stream.Write($header, 0, $header.Length)
$stream.Write($pixels, 0, $pixels.Length)
$stream.Close()

Write-Host "Fertig: $outputPath"
