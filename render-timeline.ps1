<#
.SYNOPSIS
Renders a JSON timeline: cards, full-frame narration, and resized presenter overlays.
.DESCRIPTION
Paths in the plan are relative to the plan file. Duration 0 means source end.
Overlay backgrounds may concatenate cuts and slow to narration length or hold their last frame.
The slow-tail mode uses speed for the main footage and stretches only tailSeconds.
Presenter audio is the only audio used. All scaling preserves aspect ratio, with opaque padding.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Plan,
    [string]$Output,
    [ValidateRange(0,60)][double]$PreviewSeconds = 0,
    [switch]$CheckOnly,
    [ValidateRange(0,51)][int]$Crf = 18,
    [ValidateSet('ultrafast','fast','medium','slow')][string]$Preset = 'medium',
    [string]$FFmpeg = 'ffmpeg', [string]$FFprobe = 'ffprobe',
    [switch]$Overwrite
)
. (Join-Path $PSScriptRoot 'video-common.ps1')
$planPath = Resolve-InputFile $Plan
$planFolder = Split-Path -Parent $planPath
$timeline = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$width = [int]$timeline.width; $height = [int]$timeline.height; $fps = [int]$timeline.fps
if ($width -lt 2 -or $height -lt 2 -or $width%2 -or $height%2 -or $fps -lt 1 -or $fps -gt 120) { throw 'Plan requires even positive width/height and fps 1..120.' }
if (@($timeline.segments).Count -eq 0) { throw 'Plan has no segments.' }
$encoder = Resolve-Executable $FFmpeg
$probe = Resolve-Executable $FFprobe
$paths = @(); $infos = @(); $inputArgs = @(); $filters = @(); $concat = ''; $total = 0.0
function Test-Range($info, [double]$start, [double]$duration) {
    if ([double]::IsNaN($start) -or [double]::IsInfinity($start) -or $start -lt 0 -or $start -ge $info.Duration) { throw 'Start must be within the source.' }
    if ([double]::IsNaN($duration) -or [double]::IsInfinity($duration) -or $duration -lt 0) { throw 'Duration must be finite and nonnegative.' }
    if ($duration -eq 0) { $duration = $info.Duration - $start }
    if ($start + $duration -gt $info.Duration + 0.001) { throw 'Cut extends past the source end.' }
    return $duration
}
function Get-FitFilter([int]$w, [int]$h) {
    return "scale=${w}:${h}:force_original_aspect_ratio=decrease:force_divisible_by=2:flags=lanczos,pad=${w}:${h}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,format=yuv420p"
}
# Register each source once, avoiding redundant decoders for repeated narration cuts.
foreach ($segment in $timeline.segments) {
    if ($segment.type -notin @('card','full','overlay')) { throw "Unknown segment type: $($segment.type)" }
    foreach ($file in @($segment.file, $segment.background)) {
        if (-not $file) { continue }
        $path = Resolve-InputFile (Join-Path $planFolder $file)
        if ($paths -contains $path) { continue }
        $paths += $path
        $isCard = $segment.type -eq 'card' -and $file -eq $segment.file
        if ($isCard) {
            $infos += $null
            $inputArgs += @('-loop','1','-framerate',[string]$fps,'-i',$path)
        } else {
            $infos += Get-MediaInfo $path $probe
            $inputArgs += @('-i',$path)
        }
    }
}
for ($i=0; $i -lt $timeline.segments.Count; $i++) {
    $segment = $timeline.segments[$i]
    $source = [array]::IndexOf($paths, (Resolve-InputFile (Join-Path $planFolder $segment.file)))
    $start = [double]$segment.start
    $duration = [double]$segment.duration
    if ($segment.type -eq 'card') {
        if ([double]::IsNaN($duration) -or [double]::IsInfinity($duration) -or $duration -le 0) { throw 'Cards require a finite positive duration.' }
    } else {
        $duration = Test-Range $infos[$source] $start $duration
        if (-not $infos[$source].HasAudio) { throw "Presenter has no audio: $($segment.file)" }
    }
    $shown = $duration
    if ($PreviewSeconds -gt 0) { $shown = [Math]::Min($duration, $PreviewSeconds) }
    $d = Format-Seconds $duration; $s = Format-Seconds $start; $p = Format-Seconds $shown
    $filters += "[${source}:v:0]trim=start=${s}:duration=${d},setpts=PTS-STARTPTS,fps=${fps},settb=AVTB[$i`src]"
    if ($segment.type -eq 'overlay') {
        $background = [array]::IndexOf($paths, (Resolve-InputFile (Join-Path $planFolder $segment.background)))
        if (@($segment.backgroundCuts).Count -eq 0) { throw 'An overlay requires backgroundCuts.' }
        $cutInputs = ''; $backgroundDuration = 0.0; $j = 0
        foreach ($cut in $segment.backgroundCuts) {
            $cutDuration = Test-Range $infos[$background] ([double]$cut.start) ([double]$cut.duration)
            $cs = Format-Seconds $cut.start; $cd = Format-Seconds $cutDuration
            $filters += "[${background}:v:0]trim=start=${cs}:duration=${cd},setpts=PTS-STARTPTS,settb=AVTB[b${i}c${j}]"
            $cutInputs += "[b${i}c${j}]"; $backgroundDuration += $cutDuration; $j++
        }
        $filters += "${cutInputs}concat=n=${j}:v=1:a=0[b$i]"
        $timing = ''
        if ($segment.fit -eq 'slow') {
            if ($backgroundDuration -gt $duration + 0.001) { throw 'Slow mode requires background duration <= narration duration.' }
            $factor = Format-Seconds ($duration / $backgroundDuration)
            $timing = "setpts=${factor}*(PTS-STARTPTS),"
        } elseif ($segment.fit -eq 'slow-tail') {
            $timing = (Get-TailSpeedFilter $backgroundDuration ([double]$segment.speed) ([double]$segment.tailSeconds) $duration) + ','
            Write-Host ("{0}: main screen at {1:P0}; final {2}s stretched to fill narration" -f $segment.name, $segment.speed, $segment.tailSeconds)
        } elseif ($segment.fit -ne 'hold') { throw 'Overlay fit must be slow, slow-tail or hold.' }
        $tw = [int]$segment.width; $th = [int]$segment.height; $x = [int]$segment.x; $y = [int]$segment.y
        if ($tw -lt 2 -or $th -lt 2 -or $tw%2 -or $th%2 -or $x -lt 0 -or $y -lt 0 -or $x%2 -or $y%2 -or $x+$tw -gt $width -or $y+$th -gt $height) { throw 'Overlay rectangle must fit canvas with even dimensions and coordinates.' }
        # One extra cloned tail handles frame rounding; trim always enforces narration length.
        $filters += "[b$i]${timing}fps=${fps},$(Get-FitFilter $width $height),tpad=stop_mode=clone:stop_duration=${d},trim=duration=${d},settb=AVTB[bg$i]"
        $filters += "[$i`src]$(Get-FitFilter $tw $th)[pip$i]"
        $filters += "[bg$i][pip$i]overlay=x=${x}:y=${y}:shortest=1,trim=duration=${p},setpts=PTS-STARTPTS[v$i]"
        if ($segment.fit -ne 'slow-tail') {
            Write-Host ("{0}: screen {1:N3}s -> {2:N3}s ({3:P2} average speed), presenter unchanged" -f $segment.name,$backgroundDuration,$duration,($backgroundDuration/$duration))
        }
    } else {
        $filters += "[$i`src]$(Get-FitFilter $width $height),trim=duration=${p},setpts=PTS-STARTPTS[v$i]"
    }
    if ($segment.type -eq 'card') {
        $filters += "anullsrc=r=48000:cl=stereo,atrim=duration=${p},asetpts=PTS-STARTPTS[a$i]"
    } else {
        $filters += "[${source}:a:0]atrim=start=${s}:duration=${p},asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,apad,atrim=duration=${p}[a$i]"
    }
    $concat += "[v$i][a$i]"; $total += $shown
    Write-Host ("{0}: {1:N3}s" -f $segment.name,$shown)
}
$filters += "${concat}concat=n=$($timeline.segments.Count):v=1:a=1[v][a]"
if (-not $Output) {
    $planName = [IO.Path]::GetFileNameWithoutExtension($planPath)
    $suffix = if ($PreviewSeconds -gt 0) { '-preview.mp4' } else { '-final.mp4' }
    $Output = Join-Path $planFolder ($planName + $suffix)
}
$out = Resolve-OutputFile $Output (@($planPath) + $paths) $Overwrite.IsPresent
Write-Host ("Output: {0}; {1}x{2} at {3} fps; planned {4:N3}s" -f $out,$width,$height,$fps,$total)
if ($CheckOnly) { return }
$arguments = @('-hide_banner',$(if ($Overwrite) {'-y'} else {'-n'}),'-filter_complex_threads','2') + $inputArgs
$arguments += @('-filter_complex',($filters -join ';'),'-map','[v]','-map','[a]',
    '-c:v','libx264','-preset',$Preset,'-crf',[string]$Crf,'-pix_fmt','yuv420p',
    '-c:a','aac','-b:a','192k','-ar','48000','-movflags','+faststart',$out)
Invoke-VideoEncode $encoder $arguments
Write-Host "Done: $out"
