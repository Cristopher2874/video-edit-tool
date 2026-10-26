<#
.SYNOPSIS
Creates a private episode workspace under ignored local-work/capsule-history.
.EXAMPLE
.\new-capsule-workspace.ps1 -Name episode-001
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$')]
    [string]$Name
)
$ErrorActionPreference = 'Stop'
$privateRoot = Join-Path $PSScriptRoot 'local-work'
$episode = Join-Path (Join-Path $privateRoot 'capsule-history') $Name
foreach ($directory in @('videos','images','templates','plans','notes','renders','logs','preview','tests')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $episode $directory) | Out-Null
}
foreach ($directory in @('images','videos','templates')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $privateRoot "shared/$directory") | Out-Null
}
$cuts = Join-Path $episode 'cuts.md'
# Repeat runs create missing folders but never replace an existing edit sheet.
if (-not (Test-Path -LiteralPath $cuts)) {
    $starter = @'
# Episode: NAME_PLACEHOLDER

Status: raw notes

## Files and cuts

- `videos/presenter.mp4`: 00:01-00:23 full screen; keep voice.
- `videos/screen.mp4`: keep all, behind presenter 00:23-02:05.
- Presenter 00:23-02:05: small tile over the old webcam, upper right.
- Presenter 02:05-end: full screen.
- `images/title.png`: 2 seconds at the beginning and end, silent.

## Other instructions

- Keep the whole presenter frame when making it smaller; do not crop it.
- Keep screen text readable.
- If timings do not match: <slow screen / hold last frame / ask me>.
- Crops: <file, time range, area to keep; or none>.
- Music: <describe, or none>.

Replace these examples with your notes. Source paths here are relative to this
episode folder. Rough timestamps and plain language are enough. Ask the agent
to prepare this cuts.md first, then ask another chat to render the prepared plan.
'@
    # CreateNew also protects notes if another process creates the file concurrently.
    $stream = [IO.File]::Open($cuts, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($starter.Replace('NAME_PLACEHOLDER', $Name))
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
}
Write-Host "Private workspace ready: $episode"
[pscustomobject]@{ Workspace=$episode; Cuts=$cuts; Plans=(Join-Path $episode 'plans'); Renders=(Join-Path $episode 'renders') }
