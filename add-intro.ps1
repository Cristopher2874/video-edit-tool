<#
.SYNOPSIS
Prepends the Nitro 101 intro to a recording with FFmpeg.

.EXAMPLE
.\add-intro.ps1 -Recording 'C:\Videos\zoom-recording.mp4'

.EXAMPLE
.\add-intro.ps1 -Recording 'C:\Videos\zoom-recording.mp4' -Output 'C:\Videos\episode-01.mp4' -Overwrite
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Recording,

    [string]$Output,

    [string]$Intro = (Join-Path $PSScriptRoot '.\nitro-101-intro-2s.mp4'),

    [string]$FFmpeg = 'ffmpeg',

    [string]$FFprobe = 'ffprobe',

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
        throw "Could not find $name. Install FFmpeg and put ffmpeg and ffprobe on PATH, or pass -FFmpeg and -FFprobe with their full paths."
    }
    return $command.Source
}

function Get-MediaInfo([string]$file, [string]$probe) {
    $json = & $probe -v error -show_entries 'stream=codec_type,width,height,avg_frame_rate:format=duration' -of json $file | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "ffprobe could not read: $file"
    }
    $data = $json | ConvertFrom-Json
    $video = @($data.streams | Where-Object { $_.codec_type -eq 'video' }) | Select-Object -First 1
    if (-not $video) {
        throw "No video stream found in: $file"
    }
    $audio = @($data.streams | Where-Object { $_.codec_type -eq 'audio' }) | Select-Object -First 1
    $duration = 0.0
    if (-not [double]::TryParse([string]$data.format.duration, [System.Globalization.NumberStyles]::Float, $culture, [ref]$duration) -or $duration -le 0) {
        throw "Could not determine video duration for: $file"
    }
    return [pscustomobject]@{
        Width    = [int]$video.width
        Height   = [int]$video.height
        FrameRate = [string]$video.avg_frame_rate
        HasAudio = [bool]$audio
        Duration = $duration
    }
}

$recordingPath = (Resolve-Path -LiteralPath $Recording).Path
$introPath = (Resolve-Path -LiteralPath $Intro).Path
$ffmpegExe = Resolve-Executable $FFmpeg
$ffprobeExe = Resolve-Executable $FFprobe

if (-not $Output) {
    $folder = Split-Path -Parent $recordingPath
    $name = [System.IO.Path]::GetFileNameWithoutExtension($recordingPath)
    $Output = Join-Path $folder ($name + '-with-intro.mp4')
}
$outputPath = [System.IO.Path]::GetFullPath($Output)
if ([System.IO.Path]::GetExtension($outputPath).ToLowerInvariant() -ne '.mp4') {
    throw 'The output filename must end in .mp4.'
}
if ($outputPath -eq $recordingPath -or $outputPath -eq $introPath) {
    throw 'Choose an output file different from the recording and intro.'
}
if (-not (Test-Path -LiteralPath (Split-Path -Parent $outputPath) -PathType Container)) {
    throw 'The output folder does not exist.'
}
if ((Test-Path -LiteralPath $outputPath) -and -not $Overwrite) {
    throw "Output already exists: $outputPath. Pass -Overwrite to replace it."
}

$introInfo = Get-MediaInfo $introPath $ffprobeExe
$recordingInfo = Get-MediaInfo $recordingPath $ffprobeExe
$width = $recordingInfo.Width + ($recordingInfo.Width % 2)
$height = $recordingInfo.Height + ($recordingInfo.Height % 2)

# Use the recording's frame rate when ffprobe reports a valid one; otherwise use 30 fps.
$frameRate = $recordingInfo.FrameRate
$parts = $frameRate.Split('/')
$rate = 0.0
if ($parts.Count -eq 2) {
    $numerator = 0.0
    $denominator = 0.0
    if ([double]::TryParse($parts[0], [ref]$numerator) -and
        [double]::TryParse($parts[1], [ref]$denominator) -and $denominator -gt 0) {
        $rate = $numerator / $denominator
    }
}
if ($rate -le 0 -or $rate -gt 120) { $frameRate = '30' }

$introDuration = $introInfo.Duration.ToString('0.######', $culture)
$recordingDuration = $recordingInfo.Duration.ToString('0.######', $culture)
$videoFilter = ('fps={0}:start_time=0,scale={1}:{2}:force_original_aspect_ratio=decrease,pad={1}:{2}:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p,settb=AVTB,setpts=PTS-STARTPTS' -f $frameRate, $width, $height)
$introAudioSource = if ($introInfo.HasAudio) { '[0:a:0]' } else { '[2:a:0]' }
$audioSource = if ($recordingInfo.HasAudio) { '[1:a:0]' } else { '[3:a:0]' }
$filter = ('[0:v:0]{0}[v0];[1:v:0]{0}[v1];{2}aresample=48000,atrim=duration={1},asetpts=PTS-STARTPTS,aformat=sample_rates=48000:channel_layouts=stereo[a0];{3}aresample=async=1:first_pts=0,asetpts=PTS-STARTPTS,aformat=sample_rates=48000:channel_layouts=stereo[a1];[v0][a0][v1][a1]concat=n=2:v=1:a=1[v][a]' -f $videoFilter, $introDuration, $introAudioSource, $audioSource)

$ffmpegArgs = @('-hide_banner', $(if ($Overwrite) { '-y' } else { '-n' }), '-i', $introPath, '-i', $recordingPath,
          '-f', 'lavfi', '-t', $introDuration, '-i', 'anullsrc=r=48000:cl=stereo')
if (-not $recordingInfo.HasAudio) {
    $ffmpegArgs += @('-f', 'lavfi', '-t', $recordingDuration, '-i', 'anullsrc=r=48000:cl=stereo')
}
$ffmpegArgs += @('-filter_complex', $filter, '-map', '[v]', '-map', '[a]',
           '-c:v', 'libx264', '-preset', 'medium', '-crf', '20',
           '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', $outputPath)

Write-Host "Creating: $outputPath"
& $ffmpegExe @ffmpegArgs
if ($LASTEXITCODE -ne 0) {
    throw "FFmpeg failed with exit code $LASTEXITCODE."
}
Write-Host "Done: $outputPath"
