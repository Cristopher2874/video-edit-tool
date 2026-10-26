<#
.SYNOPSIS
Changes video speed. Use -Mute for screen footage; otherwise audio tempo follows video.
.DESCRIPTION
With -TailSeconds and -TargetDuration, keep the main footage at -Speed and
stretch only its final TailSeconds to fill TargetDuration. This mode requires -Mute.
.EXAMPLE
.\change-speed.ps1 -Video .\local-work\shared\videos\screen.mp4 -Speed 0.8 -Mute -Output .\local-work\shared\videos\screen-slow.mp4
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Video,
    [Parameter(Mandatory=$true)][ValidateRange(0.5,2.0)][double]$Speed,
    [string]$Output,
    [switch]$Mute,
    [double]$TailSeconds = 0,
    [double]$TargetDuration = 0,
    [ValidateRange(1,120)][int]$FrameRate = 25,
    [string]$FFmpeg = 'ffmpeg', [string]$FFprobe = 'ffprobe',
    [switch]$Overwrite
)
. (Join-Path $PSScriptRoot 'video-common.ps1')
$path = Resolve-InputFile $Video
if (-not $Output) { $Output = Join-Path (Split-Path -Parent $path) ([IO.Path]::GetFileNameWithoutExtension($path) + '-speed.mp4') }
$out = Resolve-OutputFile $Output @($path) $Overwrite.IsPresent
$encoder = Resolve-Executable $FFmpeg
$info = Get-MediaInfo $path (Resolve-Executable $FFprobe)
$speedText = Format-Seconds $Speed
$timing = "setpts=(PTS-STARTPTS)/${speedText}"
$tailMode = $PSBoundParameters.ContainsKey('TailSeconds') -or $PSBoundParameters.ContainsKey('TargetDuration')
if ($tailMode) {
    if (-not $Mute) { throw 'Tail extension requires -Mute; presenter audio must remain separate.' }
    $timing = Get-TailSpeedFilter $info.Duration $Speed $TailSeconds $TargetDuration
    $target = Format-Seconds $TargetDuration
    $timing += ",tpad=stop_mode=clone:stop_duration=${target},trim=duration=${target}"
}
$arguments = @('-hide_banner',$(if ($Overwrite) {'-y'} else {'-n'}),'-i',$path,
    '-map','0:v:0','-vf',"${timing},fps=${FrameRate},pad=ceil(iw/2)*2:ceil(ih/2)*2,setsar=1",
    '-c:v','libx264','-crf','18','-preset','medium','-pix_fmt','yuv420p')
if ($info.HasAudio -and -not $Mute) {
    $arguments += @('-map','0:a:0','-af',"asetpts=PTS-STARTPTS,atempo=${speedText}",'-c:a','aac','-b:a','192k')
} else { $arguments += '-an' }
$arguments += @('-movflags','+faststart',$out)
Invoke-VideoEncode $encoder $arguments
Write-Host "Done: $out"
