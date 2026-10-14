<#
.SYNOPSIS
Crops a video rectangle and/or trims a time range. Times are in seconds.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Video,
    [string]$Output,
    [double]$Start = 0,
    [double]$Duration = 0,
    [int]$Width = 0, [int]$Height = 0,
    [int]$X = -1, [int]$Y = -1,
    [string]$FFmpeg = 'ffmpeg', [string]$FFprobe = 'ffprobe',
    [switch]$Overwrite
)
. (Join-Path $PSScriptRoot 'video-common.ps1')
$path = Resolve-InputFile $Video
if (-not $Output) { $Output = Join-Path (Split-Path -Parent $path) ([IO.Path]::GetFileNameWithoutExtension($path) + '-cropped.mp4') }
$out = Resolve-OutputFile $Output @($path) $Overwrite.IsPresent
$encoder = Resolve-Executable $FFmpeg
$info = Get-MediaInfo $path (Resolve-Executable $FFprobe)
if ([double]::IsNaN($Start) -or [double]::IsInfinity($Start) -or $Start -lt 0 -or $Start -ge $info.Duration) { throw 'Start must be within the video.' }
if ([double]::IsNaN($Duration) -or [double]::IsInfinity($Duration) -or $Duration -lt 0 -or ($Duration -gt 0 -and $Start + $Duration -gt $info.Duration + 0.001)) { throw 'Duration must fit within the video; 0 means to the end.' }
if ($Width -eq 0) { $Width = $info.Width - ($info.Width % 2) }
if ($Height -eq 0) { $Height = $info.Height - ($info.Height % 2) }
if ($X -eq -1) { $X = 2 * [Math]::Floor(($info.Width-$Width)/4) }
if ($Y -eq -1) { $Y = 2 * [Math]::Floor(($info.Height-$Height)/4) }
if ($Width -lt 2 -or $Height -lt 2 -or $Width%2 -or $Height%2 -or $X -lt 0 -or $Y -lt 0 -or $X%2 -or $Y%2 -or $X+$Width -gt $info.Width -or $Y+$Height -gt $info.Height) { throw 'Crop must fit within the source; dimensions and offsets must be even pixels.' }
$arguments = @('-hide_banner',$(if ($Overwrite) {'-y'} else {'-n'}),'-ss',(Format-Seconds $Start),'-i',$path)
if ($Duration -gt 0) { $arguments += @('-t',(Format-Seconds $Duration)) }
$arguments += @('-map','0:v:0','-map','0:a:0?','-vf',"crop=${Width}:${Height}:${X}:${Y},setsar=1",'-c:v','libx264','-crf','20','-preset','medium','-pix_fmt','yuv420p','-c:a','aac','-movflags','+faststart',$out)
Invoke-VideoEncode $encoder $arguments
Write-Host "Done: $out"
