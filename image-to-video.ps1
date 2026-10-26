<#
.SYNOPSIS
Creates a silent, static MP4 from an image.

.EXAMPLE
.\image-to-video.ps1 -Image '.\local-work\shared\images\title.png'

.EXAMPLE
.\image-to-video.ps1 -Image 'C:\Videos\end-card.png' -Duration 2 -Output 'C:\Videos\outro.mp4'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Image,

    [string]$Output,

    [double]$Duration = 2,

    [int]$Width = 1920,

    [int]$Height = 1080,

    [int]$FrameRate = 30,

    [string]$FFmpeg = 'ffmpeg',

    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'
$culture = [System.Globalization.CultureInfo]::InvariantCulture

function Resolve-Executable([string]$name) {
    if (Test-Path -LiteralPath $name -PathType Leaf) {
        return (Resolve-Path -LiteralPath $name).Path
    }
    $command = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Could not find $name. Install FFmpeg and put ffmpeg on PATH, or pass -FFmpeg with its full path."
    }
    return $command.Source
}

if ([double]::IsNaN($Duration) -or [double]::IsInfinity($Duration) -or $Duration -le 0) {
    throw 'Duration must be a positive number of seconds.'
}
if ($Width -lt 2 -or $Height -lt 2 -or $Width % 2 -ne 0 -or $Height % 2 -ne 0) {
    throw 'Width and Height must be positive, even pixel counts.'
}
if ($FrameRate -lt 1 -or $FrameRate -gt 120) {
    throw 'FrameRate must be between 1 and 120.'
}

$imagePath = (Resolve-Path -LiteralPath $Image -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
    throw "Image is not a file: $Image"
}

if (-not $Output) {
    $folder = Split-Path -Parent $imagePath
    $name = [System.IO.Path]::GetFileNameWithoutExtension($imagePath)
    $Output = Join-Path $folder ($name + '-2s.mp4')
    if ($Duration -ne 2) {
        $Output = Join-Path $folder ($name + '-static.mp4')
    }
}
$outputPath = [System.IO.Path]::GetFullPath($Output)
if ([System.IO.Path]::GetExtension($outputPath).ToLowerInvariant() -ne '.mp4') {
    throw 'The output filename must end in .mp4.'
}
if ([string]::Equals($outputPath, $imagePath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Choose an output file different from the image.'
}
if (-not (Test-Path -LiteralPath (Split-Path -Parent $outputPath) -PathType Container)) {
    throw 'The output folder does not exist.'
}
if ((Test-Path -LiteralPath $outputPath) -and -not $Overwrite) {
    throw "Output already exists: $outputPath. Pass -Overwrite to replace it."
}

$ffmpegExe = Resolve-Executable $FFmpeg

# Fill the frame without borders; crop equally from opposite sides when needed.
$videoFilter = "scale=${Width}:${Height}:force_original_aspect_ratio=increase,crop=${Width}:${Height},setsar=1,format=yuv420p"
$durationText = $Duration.ToString('0.######', $culture)
$ffmpegArgs = @(
    '-hide_banner', $(if ($Overwrite) { '-y' } else { '-n' }),
    '-loop', '1', '-framerate', [string]$FrameRate, '-i', $imagePath,
    '-t', $durationText, '-vf', $videoFilter,
    '-an', '-c:v', 'libx264', '-preset', 'medium', '-crf', '20',
    '-pix_fmt', 'yuv420p', '-movflags', '+faststart', $outputPath
)

Write-Host "Creating: $outputPath"
& $ffmpegExe @ffmpegArgs
if ($LASTEXITCODE -ne 0) {
    throw "FFmpeg failed with exit code $LASTEXITCODE."
}
Write-Host "Done: $outputPath"
