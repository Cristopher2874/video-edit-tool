<#
.SYNOPSIS
Transcribe local media with FFmpeg and whisper.cpp, without uploads.
.EXAMPLE
.\tools\transcription\transcribe.ps1 -InputPath '.\local-work\shared\videos\recording.mp4' -OutputDirectory '.\local-work\transcription-jobs\job-001'
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$InputPath,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$OutputDirectory,
    [ValidatePattern('^(auto|[a-z]{2,3})$')][string]$Language = 'en',
    [string]$ModelPath,
    [string]$WhisperPath,
    [ValidateRange(1,256)][int]$Threads = 8,
    [string]$FFmpegPath = 'ffmpeg',
    [string]$AssetDirectory = $env:WHISPER_ASSET_DIR,
    [ValidateRange(0,2147483647)][int]$StartSeconds = 0,
    [ValidateRange(1,2147483647)][int]$DurationSeconds,
    [switch]$Overwrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Native exit codes are checked explicitly, including in PowerShell 7.3+.
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$logPath = $null
$stage = $null

function Resolve-LocalFile([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label file not found: '$Path'."
    }
    return (Get-Item -LiteralPath $Path).FullName
}

function Find-Executable([string]$Value, [string]$Label) {
    if (Test-Path -LiteralPath $Value -PathType Leaf) {
        return (Get-Item -LiteralPath $Value).FullName
    }
    $command = Get-Command -Name $Value -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw "$Label executable not found: '$Value'. Supply its full path or add it to PATH."
}

function Write-Log([string]$Message) {
    Add-Content -LiteralPath $logPath -Value $Message -Encoding UTF8
    Write-Host $Message
}

function Invoke-LocalTool([string]$Executable, [string[]]$Arguments) {
    # JSON preserves exact argument boundaries in the diagnostic log. The call
    # operator passes the array directly; no shell expression is constructed.
    Write-Log ("Executable: $Executable`nArguments: " + (ConvertTo-Json -InputObject $Arguments -Compress))
    $previousPreference = $ErrorActionPreference
    try {
        # Windows PowerShell represents native stderr as ErrorRecord objects.
        $ErrorActionPreference = 'Continue'
        & $Executable @Arguments 2>&1 | ForEach-Object { Write-Log ([string]$_) }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    Write-Log "Exit code: $code"
    if ($code -ne 0) { throw "'$Executable' failed with exit code $code. See '$logPath'." }
}

try {
    $source = Resolve-LocalFile $InputPath 'Input media'
    $output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
    $names = @('audio.wav', 'transcript.txt', 'transcript.srt', 'transcript.json', 'transcription.log')
    $destinations = @($names | ForEach-Object { Join-Path $output $_ })
    foreach ($explicitPath in @($ModelPath, $WhisperPath, $FFmpegPath)) {
        if ($explicitPath -and (Test-Path -LiteralPath $explicitPath -PathType Leaf)) {
            if ($destinations -contains (Get-Item -LiteralPath $explicitPath).FullName) {
                throw "An output would replace a dependency: '$explicitPath'. Choose another output directory."
            }
        }
    }
    foreach ($destination in $destinations) {
        if ($destination -eq $source) { throw 'The input media cannot be one of the output files, even with -Overwrite.' }
        if (Test-Path -LiteralPath $destination) {
            if (-not $Overwrite) { throw "Output already exists: '$destination'. Choose a new job directory or pass -Overwrite." }
            if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw "Output is not a file: '$destination'." }
        }
    }
    [IO.Directory]::CreateDirectory($output) | Out-Null
    $logCandidate = Join-Path $output 'transcription.log'
    $mode = if ($Overwrite) { [IO.FileMode]::Create } else { [IO.FileMode]::CreateNew }
    $stream = [IO.File]::Open($logCandidate, $mode, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $stream.Dispose()
    $logPath = $logCandidate
    Write-Log ("Started: " + (Get-Date -Format o))
    Write-Log "Input: $source`nOutput: $output`nLanguage: $Language; CPU threads: $Threads"

    $assetRoots = @()
    if ($AssetDirectory) {
        if (-not (Test-Path -LiteralPath $AssetDirectory -PathType Container)) { throw "Asset directory not found: '$AssetDirectory'." }
        $assetRoots += (Get-Item -LiteralPath $AssetDirectory).FullName
    }
    $assetRoots += Join-Path $repoRoot 'local-work\shared\transcription'
    $legacyAssets = Join-Path $repoRoot 'local_assets'
    if (Test-Path -LiteralPath $legacyAssets -PathType Container) {
        $assetRoots += $legacyAssets
        $assetRoots += @(Get-ChildItem -LiteralPath $legacyAssets -Directory | ForEach-Object { $_.FullName })
    }
    $encoder = Find-Executable $FFmpegPath 'FFmpeg'
    if (-not $WhisperPath) {
        foreach ($root in $assetRoots) {
            foreach ($relative in @('whisper-bin\Release\whisper-cli.exe', 'Release\whisper-cli.exe', 'whisper-cli.exe', 'build\bin\Release\whisper-cli.exe')) {
                $candidate = Join-Path $root $relative
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { $WhisperPath = $candidate; break }
            }
            if ($WhisperPath) { break }
        }
        if (-not $WhisperPath) { $WhisperPath = 'whisper-cli.exe' }
    }
    $whisper = Find-Executable $WhisperPath 'whisper.cpp (use -WhisperPath or -AssetDirectory)'
    if (-not $ModelPath) {
        $modelName = if ($Language -eq 'en') { 'ggml-base.en.bin' } else { 'ggml-base.bin' }
        foreach ($root in $assetRoots) {
            foreach ($relative in @($modelName, "models\$modelName")) {
                $candidate = Join-Path $root $relative
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { $ModelPath = $candidate; break }
            }
            if ($ModelPath) { break }
        }
        if (-not $ModelPath) { throw "Model $modelName not found. Supply -ModelPath or -AssetDirectory. No model is downloaded automatically." }
    }
    $model = Resolve-LocalFile $ModelPath 'Whisper model'
    foreach ($dependency in @($encoder, $whisper, $model)) {
        if ($destinations -contains $dependency) { throw "An output would replace a dependency: '$dependency'. Choose another output directory." }
    }
    if ($Language -ne 'en' -and [IO.Path]::GetFileName($model) -match '\.en(?:[.-]|$)') {
        throw 'An English-only .en model requires -Language en. Use a multilingual model for other languages or auto detection.'
    }
    Write-Log "FFmpeg: $encoder`nWhisper: $whisper`nModel: $model"
    Invoke-LocalTool $whisper @('--version')

    # Process in a unique private subdirectory so failed runs cannot publish
    # stale transcripts or replace earlier successful media/transcripts.
    $stage = Join-Path $output ('.run-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($stage) | Out-Null
    $wav = Join-Path $stage 'audio.wav'
    $ffArgs = @('-hide_banner', '-loglevel', 'error', '-nostdin', '-n')
    if ($StartSeconds -gt 0) { $ffArgs += @('-ss', [string]$StartSeconds) }
    $ffArgs += @('-i', $source)
    if ($PSBoundParameters.ContainsKey('DurationSeconds')) { $ffArgs += @('-t', [string]$DurationSeconds) }
    $ffArgs += @('-map', '0:a:0', '-vn', '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', $wav)
    Invoke-LocalTool $encoder $ffArgs
    if (-not (Test-Path -LiteralPath $wav) -or (Get-Item -LiteralPath $wav).Length -le 44) {
        throw 'FFmpeg produced no usable audio. Check the audio stream and requested segment.'
    }
    Invoke-LocalTool $whisper @('-m', $model, '-f', $wav, '-l', $Language, '-t', [string]$Threads, '-ng', '-otxt', '-osrt', '-oj', '-of', (Join-Path $stage 'transcript'))
    foreach ($name in $names[0..3]) {
        if (-not (Test-Path -LiteralPath (Join-Path $stage $name) -PathType Leaf)) { throw "Expected output missing: $name. Check the Whisper log." }
    }
    $null = Get-Content -LiteralPath (Join-Path $stage 'transcript.json') -Raw | ConvertFrom-Json
    foreach ($name in $names[0..3]) {
        # File.Copy's overwrite flag also protects against late collisions.
        [IO.File]::Copy((Join-Path $stage $name), (Join-Path $output $name), $Overwrite.IsPresent)
    }
    foreach ($name in $names[0..3]) { Remove-Item -LiteralPath (Join-Path $stage $name) }
    Remove-Item -LiteralPath $stage
    $stage = $null
    Write-Log ('Completed: ' + (Get-Date -Format o))
    Write-Host "Transcription ready: $output"
} catch {
    $message = $_.Exception.Message
    if ($logPath) {
        try {
            Write-Log "ERROR: $message"
            if ($stage) { Write-Log "Partial processing files retained at: $stage" }
        } catch { Write-Warning 'Could not append to the diagnostic log.' }
    }
    throw $message
}
