# Local transcription jobs

Standalone PowerShell tool; independent of any UI, connector or backend. Media
conversion and speech recognition run locally. The script makes no network
requests, uploads or automatic downloads.

## Setup

These dependencies are publicly available; users do not need access to another
developer's machine or project. Use Windows PowerShell 5.1 or PowerShell 7.
The steps below target 64-bit Intel/AMD Windows and run from the repository root.

### 1. Download FFmpeg

Open the [FFmpeg download page](https://ffmpeg.org/download.html), then under
**Windows EXE Files** choose a linked Windows build provider (Gyan or BtbN).
FFmpeg itself distributes source code; those providers supply Windows binaries.
Download a Windows x64 ZIP build (for example, Gyan's essentials ZIP), extract
it, and locate `bin\ffmpeg.exe`. Do not download a source-code archive.

Add the extracted `bin` folder to your user PATH and open a new terminal, then
check it:

```powershell
ffmpeg -version
```

Alternatively, leave PATH unchanged and pass the actual executable location
to every transcription command, for example
`-FFmpegPath 'C:\tools\ffmpeg\bin\ffmpeg.exe'`.

### 2. Download whisper.cpp and its English model

The tested version is [whisper.cpp v1.9.2](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.2).
Under **Assets**, download **whisper-bin-x64.zip**, the Windows CPU package.
The model is a separate download: obtain
[ggml-base.en.bin](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin)
from the model host linked by the
[official model instructions](https://github.com/ggml-org/whisper.cpp/tree/master/models).
You do not need Python, an API key, or a cloud account for transcription.

For a fresh setup, these commands download and extract both into the ignored
shared folder. They stop if the destination files already exist; reuse those
files instead of downloading again.

```powershell
$assets = Join-Path (Get-Location) 'local-work\shared\transcription'
New-Item -ItemType Directory -Path $assets -Force | Out-Null
$zip = Join-Path $assets 'whisper-bin-x64.zip'
$engine = Join-Path $assets 'whisper-bin'
$model = Join-Path $assets 'ggml-base.en.bin'
if ((Test-Path -LiteralPath $zip) -or (Test-Path -LiteralPath $engine) -or (Test-Path -LiteralPath $model)) {
    throw 'Transcription dependencies already exist here. Reuse them or choose a new asset directory.'
}
Invoke-WebRequest -UseBasicParsing `
  -Uri 'https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.2/whisper-bin-x64.zip' `
  -OutFile $zip -ErrorAction Stop
Expand-Archive -LiteralPath $zip -DestinationPath $engine -ErrorAction Stop
Invoke-WebRequest -UseBasicParsing `
  -Uri 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin' `
  -OutFile $model -ErrorAction Stop
& (Join-Path $engine 'Release\whisper-cli.exe') --version
Get-Item -LiteralPath $model
```

Keep the extracted DLLs beside `whisper-cli.exe`; do not copy only the executable.
The script discovers this layout automatically. If using a different package
layout, locate `whisper-cli.exe` and supply `-WhisperPath` explicitly.
For languages other than English or `-Language auto`, download
[ggml-base.bin](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin)
instead, save it alongside the English model, and select `-Language es` (for
example) or `-Language auto`. The `.en` model supports English only.

### 3. Try a short local transcription

Replace the input path with your own recording. After the setup above, no asset
paths are required:

```powershell
.\tools\transcription\transcribe.ps1 `
  -InputPath 'C:\media\my recording.mp4' `
  -OutputDirectory '.\local-work\transcription-jobs\first-test' `
  -DurationSeconds 20
```

Add `-FFmpegPath` if FFmpeg is not on PATH. Omit `-DurationSeconds` for the full
recording and choose a new output directory for each run.

Setup downloads are separate from transcription. Once installed, the tool
works offline. Existing executable/model files can stay in another project:
pass `-AssetDirectory` or the explicit paths; nothing needs to be copied.

Suggested layout (all dependencies and jobs are ignored by Git):

```text
local-work/
  shared/transcription/
    ggml-base.en.bin
    whisper-bin/Release/whisper-cli.exe   (plus its DLLs)
  transcription-jobs/
    job-001/
    job-002/
```

Create a separate output directory for each job; the script creates it for you.
Use `local-work/transcription-jobs/` for standalone jobs. An episode can instead
keep its transcripts under its own `local-work/capsule-history/<episode>/` tree.

## Usage

Run from the repository root. Replace the generic media path with your file:

```powershell
.\tools\transcription\transcribe.ps1 `
  -InputPath '.\local-work\shared\videos\recording.mp4' `
  -OutputDirectory '.\local-work\transcription-jobs\job-001'
```

Reuse dependencies already in another folder (containing the model and
`whisper-bin\Release\whisper-cli.exe`):

```powershell
.\tools\transcription\transcribe.ps1 `
  -InputPath 'C:\media\recording with spaces.mp4' `
  -OutputDirectory '.\local-work\transcription-jobs\job-002' `
  -AssetDirectory 'C:\local assets\speech'
```

Explicit dependencies, language and a short segment:

```powershell
.\tools\transcription\transcribe.ps1 `
  -InputPath 'C:\media\recording with spaces.mp4' `
  -OutputDirectory '.\local-work\transcription-jobs\sample' `
  -WhisperPath 'C:\local assets\speech\whisper-bin\Release\whisper-cli.exe' `
  -ModelPath 'C:\local assets\speech\ggml-base.en.bin' `
  -Language en -Threads 8 -StartSeconds 10 -DurationSeconds 20
```

Omit `-DurationSeconds` to process to the end. Segment subtitle timestamps start
at zero relative to the extracted segment, not the original recording.
`-StartSeconds` is a nonnegative integer; duration is a positive integer.

Default language is `en`, default threads is `8` (allowed: 1-256), and inference
uses the CPU (`-ng`). For `auto` or another Whisper language code, explicitly
choose a suitable multilingual model or provide `ggml-base.bin` in the assets.

Discovery order: explicit executable/model paths; `-AssetDirectory` (defaults
to the `WHISPER_ASSET_DIR` environment variable); this repository's
`local-work/shared/transcription`; legacy `local_assets` and its immediate
subdirectories. Whisper also falls back to PATH. Supported executable layouts
within assets: `whisper-bin/Release`, `Release`, the asset root, and
`build/bin/Release`. Models can be in the asset root or `models/`.
FFmpeg uses PATH unless `-FFmpegPath` is supplied. Relative paths resolve from
your current working directory; automatic repository paths resolve from the
script location. Explicit invalid paths fail rather than silently falling back.

## Outputs and errors

Each job contains `audio.wav` (mono, 16 kHz, PCM s16le), `transcript.txt`,
`transcript.srt`, `transcript.json`, and `transcription.log`. The log includes
dependency paths, Whisper version, argument arrays, native output and exit codes.
The first audio stream is selected. Media without audio fails with FFmpeg's
diagnostic. Transcripts may be empty for silence; review recognition accuracy.

Existing outputs block the run. Prefer a new job directory; add `-Overwrite`
only to replace this job's five named files. Other files are preserved.
Processing uses a unique `.run-*` subdirectory, publishes the four result files
only after both commands succeed and JSON parses, and retains partial processing
files on failure. Publication of multiple files is not transactional if disk or
permission errors occur. With `-Overwrite`, the diagnostic log is replaced at
startup even if a later step fails. Earlier result files remain until publishing.
Errors before log creation appear in PowerShell; subsequent errors also appear
in the log. A terminating failure yields a nonzero exit when run with
`powershell.exe -NoProfile -File` or `pwsh -NoProfile -File`.

Keep recordings, binaries, DLLs, models and generated outputs under ignored
`local-work/` (or outside the repository). Never force-add private job content.
