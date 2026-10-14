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

function Resolve-InputFile([string]$Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Not a file: $Path" }
    return $resolved
}
function Resolve-OutputFile([string]$Path, [string[]]$Inputs, [bool]$Overwrite) {
    $resolved = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetExtension($resolved) -ne '.mp4') { throw 'Output must end in .mp4.' }
    foreach ($inputPath in $Inputs) {
        if ($resolved -eq $inputPath) { throw 'Output must differ from all input files.' }
    }
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $resolved) -PathType Container)) { throw 'Output folder does not exist.' }
    if ((Test-Path -LiteralPath $resolved) -and -not $Overwrite) { throw 'Output exists; use -Overwrite to replace it.' }
    return $resolved
}
function Invoke-VideoEncode([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "FFmpeg failed with exit code $LASTEXITCODE." }
}
function Format-Seconds([double]$Value) { return $Value.ToString('0.######', $culture) }
