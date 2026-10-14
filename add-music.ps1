<#
.SYNOPSIS
Loops music to video length, mixing original audio by default.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Video,
    [Parameter(Mandatory=$true)][string]$Music,
    [string]$Output,
    [ValidateRange(0,10)][double]$MusicVolume = 0.2,
    [ValidateRange(0,10)][double]$OriginalVolume = 1,
    [switch]$ReplaceAudio,
    [string]$FFmpeg = 'ffmpeg', [string]$FFprobe = 'ffprobe',
    [switch]$Overwrite
)
. (Join-Path $PSScriptRoot 'video-common.ps1')
$path = Resolve-InputFile $Video
$musicPath = Resolve-InputFile $Music
if (-not $Output) { $Output = Join-Path (Split-Path -Parent $path) ([IO.Path]::GetFileNameWithoutExtension($path) + '-with-music.mp4') }
$out = Resolve-OutputFile $Output @($path,$musicPath) $Overwrite.IsPresent
$encoder = Resolve-Executable $FFmpeg
$probe = Resolve-Executable $FFprobe
$info = Get-MediaInfo $path $probe
$audioJson = & $probe -v error -select_streams a:0 -show_entries stream=codec_type -of json $musicPath | Out-String
if ($LASTEXITCODE -ne 0 -or @((ConvertFrom-Json $audioJson).streams).Count -eq 0) { throw 'Music must contain an audio stream.' }
$duration = Format-Seconds $info.Duration
$filter = "[1:a:0]asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,volume=$(Format-Seconds $MusicVolume)[music];"
if ($info.HasAudio -and -not $ReplaceAudio) {
    $filter += "[0:a:0]asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,volume=$(Format-Seconds $OriginalVolume)[original];[original][music]amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.95:level=0,atrim=duration=${duration}[a]"
} else { $filter += "[music]atrim=duration=${duration}[a]" }
$arguments = @('-hide_banner',$(if ($Overwrite) {'-y'} else {'-n'}),'-i',$path,'-stream_loop','-1','-i',$musicPath,'-filter_complex',$filter,'-map','0:v:0','-map','[a]','-t',$duration,'-c:v','copy','-c:a','aac','-b:a','192k','-movflags','+faststart',$out)
Invoke-VideoEncode $encoder $arguments
Write-Host "Done: $out"
