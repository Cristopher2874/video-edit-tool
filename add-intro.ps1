<#
.SYNOPSIS
Joins clips in order, optionally prepending an intro. Normalizes video and audio.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][Alias('Videos')][string[]]$Recording,
    [string]$Output,
    [string]$Intro,
    [ValidateRange(1,120)][int]$FrameRate = 30,
    [string]$FFmpeg = 'ffmpeg',
    [string]$FFprobe = 'ffprobe',
    [switch]$Overwrite
)
. (Join-Path $PSScriptRoot 'video-common.ps1')
if ($Recording.Count -eq 0) { throw 'Provide at least one recording.' }
$recordingPaths = @($Recording | ForEach-Object { Resolve-InputFile $_ })
$paths = @()
if ($Intro) { $paths += Resolve-InputFile $Intro }
$paths += $recordingPaths
if (-not $Output) {
    $suffix = if ($Intro) { '-with-intro.mp4' } else { '-joined.mp4' }
    $Output = Join-Path (Split-Path -Parent $recordingPaths[0]) ([IO.Path]::GetFileNameWithoutExtension($recordingPaths[0]) + $suffix)
}
$outputPath = Resolve-OutputFile $Output $paths $Overwrite.IsPresent
$encoder = Resolve-Executable $FFmpeg
$probe = Resolve-Executable $FFprobe
$infos = @($paths | ForEach-Object { Get-MediaInfo $_ $probe })
$base = Get-MediaInfo $recordingPaths[0] $probe
$width = $base.Width + ($base.Width % 2)
$height = $base.Height + ($base.Height % 2)
$arguments = @('-hide_banner', $(if ($Overwrite) { '-y' } else { '-n' }))
foreach ($path in $paths) { $arguments += @('-i', $path) }
$filters = @()
$concat = ''
for ($i=0; $i -lt $paths.Count; $i++) {
    $duration = Format-Seconds $infos[$i].Duration
    $filters += "[${i}:v:0]setpts=PTS-STARTPTS,fps=${FrameRate},scale=${width}:${height}:force_original_aspect_ratio=decrease,pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p,settb=AVTB[v$i]"
    if ($infos[$i].HasAudio) {
        $filters += "[${i}:a:0]asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,apad,atrim=duration=${duration}[a$i]"
    } else {
        $filters += "anullsrc=r=48000:cl=stereo,atrim=duration=${duration},asetpts=PTS-STARTPTS[a$i]"
    }
    $concat += "[v$i][a$i]"
}
$filters += "${concat}concat=n=$($paths.Count):v=1:a=1[v][a]"
$arguments += @('-filter_complex', ($filters -join ';'), '-map','[v]','-map','[a]', '-c:v','libx264','-preset','medium','-crf','20','-c:a','aac','-b:a','192k','-movflags','+faststart',$outputPath)
Invoke-VideoEncode $encoder $arguments
Write-Host "Done: $outputPath"
