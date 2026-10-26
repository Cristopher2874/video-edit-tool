# Video editing tools

Reusable PowerShell tools for FFmpeg: cards, trimming, cropping, joining,
playback speed, presenter overlays and background music.

Run from this repository in Windows PowerShell 5.1 or PowerShell 7. Install
FFmpeg and FFprobe on PATH, or pass `-FFmpeg` / `-FFprobe` executable paths.
Keep `video-common.ps1` beside the editing scripts.

## Public tools, private work

The repository contains reusable scripts, this README, AGENTS.md and .gitignore.
Keep actual recordings, images, presentations, templates, notes, JSON plans,
previews, test evidence and rendered videos inside **`local-work/`**. That entire
folder is ignored by Git and is created locally; it is not part of a clone.

**Leave it ignored while using Codex.** Agents can read and edit local ignored
files by their explicit paths. There is no need to toggle .gitignore. Git ignore
rules prevent ordinary staging; they are not encryption or access control, and
`git add -f` can bypass them. They also do not untrack already committed files
or erase history. Before publishing, inspect what Git tracks and will include.

```text
repository/
  *.ps1                          reusable tools
  README.md, AGENTS.md, .gitignore
  local-work/                    PRIVATE; ignored, created locally
    shared/
      images/                    assets used by several episodes
      videos/
      templates/
    capsule-history/
      episode-001/
        cuts.md                  human notes, then prepared edit sheet
        videos/                  source recordings
        images/                  title cards and other images
        templates/               episode-specific presentations/templates
        plans/                   agent-generated JSON
        notes/                   technical notes and prior edit sheets
        renders/                 final videos and their versions
        preview/                 sample renders and screenshots
        logs/                    encode/check logs
        tests/                   episode-specific QA evidence
      episode-002/               separate history for the next episode
    tools/                       optional local check/helper scripts
    tests/                       optional synthetic test artifacts
    releases/                    optional clean public snapshots
```

## Start an episode

```powershell
.\new-capsule-workspace.ps1 -Name episode-001
```

This creates the private folders and a starter `cuts.md`. Running it again
preserves existing notes and media. You can also create the tree manually.
Use another name for the next episode; keep earlier episode folders intact.
Copy your own media into that episode's folders and replace the starter notes.

## Prepare, then render

Humans write short filenames, source times and plain-language instructions in
the selected episode's `cuts.md`. For example:

```text
videos/presenter.mp4: 00:01-00:23 full screen, keep voice.
videos/screen.mp4: keep all, behind presenter 00:23-02:05.
Presenter small over the old webcam, upper right. Resize, do not crop.
Presenter 02:05-end: full screen.
images/title.png: 2 seconds at both ends.
If the screen is too short, slow it down. Keep voice normal.
```

You do not need output timestamps, speed math, coordinates or JSON.

1. **Preparation chat:** "Read AGENTS.md and
   local-work/capsule-history/episode-001/cuts.md. Inspect the media and prepare
   a readable timeline with me. Do not render the final video yet."
   The agent preserves your source cuts, resolves timing and layout choices,
   updates the edit sheet and creates `plans/episode-plan.json`. Technical
   settings and long commands go in `notes/`; you review the edit sheet.
2. **Rendering chat:** "Read AGENTS.md and
   local-work/capsule-history/episode-001/cuts.md. Render the prepared timeline
   using the general scripts and verify the output."
   The agent checks the derived plan against the edit sheet, renders into
   `renders/`, records verification, and returns the finished video.

Always name the episode path when several exist. Each episode's `cuts.md`
remains the editorial source; humans do not need to maintain JSON. Relative
media paths in a plan resolve from that plan's folder. A JSON in `plans/`
normally uses `../videos/presenter.mp4`, not `videos/presenter.mp4`.

## Tool examples

Run these from the repository root, using your own files. Each command writes
inside the selected private workspace. Output folders must already exist.

```powershell
$work = '.\local-work\capsule-history\episode-001'
```

### Static image card

```powershell
.\image-to-video.ps1 -Image "$work\images\title.png" -Duration 2 -Output "$work\renders\title.mp4"
```

Defaults: silent, 1920x1080, 30 fps. Set `-Width`, `-Height`, `-FrameRate` as
needed. This tool fills the frame with center cropping if aspect ratios differ;
use the timeline renderer's fit-and-pad cards to retain an entire image.

### Trim time or crop a rectangle

```powershell
.\crop-video.ps1 -Video "$work\videos\screen.mp4" -Start 5 -Duration 20 -Output "$work\renders\excerpt.mp4"
.\crop-video.ps1 -Video "$work\videos\screen.mp4" -Width 640 -Height 360 -X 100 -Y 40 -Output "$work\renders\crop.mp4"
```

Spatial cropping removes pixels. Dimensions and offsets must be even and fit
within the source. Omit X/Y for a centered crop; omit dimensions to retain the
frame (odd source dimensions lose at most one edge pixel). Times are seconds;
`-Duration 0` means source end. Audio is retained. Cuts re-encode accurately.

### Join clips with an optional intro

```powershell
.\add-intro.ps1 -Recording @("$work\renders\part1.mp4", "$work\renders\part2.mp4") -FrameRate 25 -Output "$work\renders\joined.mp4"
.\add-intro.ps1 -Intro "$work\renders\title.mp4" -Recording "$work\renders\joined.mp4" -Output "$work\renders\with-title.mp4"
```

Clips play in order; `-Videos` aliases `-Recording`. `-Intro` is optional.
Silent clips get silence; short audio is padded. Canvas dimensions match the
first recording with letterboxing. Default frame rate is 30 fps. Use arrays
inside a PowerShell session or script, rather than multiple arguments to
`powershell.exe -File`.

### Change playback speed

```powershell
.\change-speed.ps1 -Video "$work\videos\screen.mp4" -Speed 0.8 -Mute -Output "$work\renders\screen-slow.mp4"
.\change-speed.ps1 -Video "$work\renders\selected.mp4" -Speed 0.95 -Mute -TailSeconds 2 -TargetDuration 92 -Output "$work\renders\tail-extended.mp4"
```

Speed range: 0.5x-2x; below 1 slows down. `-Mute` discards audio; otherwise audio
changes tempo while keeping pitch. Defaults: 25 fps, H.264 CRF 18. Odd frame
sizes are padded to even dimensions. Tail mode requires `-Mute`, a tail shorter
than the source and a target at least as long as the source at the main speed.
It stretches only the tail to fill remaining time; only the tail can go below 0.5x.

### Render a prepared timeline

```powershell
.\render-timeline.ps1 -Plan "$work\plans\episode-plan.json" -Output "$work\renders\final.mp4" -CheckOnly
.\render-timeline.ps1 -Plan "$work\plans\episode-plan.json" -PreviewSeconds 2 -Output "$work\preview\sample.mp4"
.\render-timeline.ps1 -Plan "$work\plans\episode-plan.json" -Output "$work\renders\final.mp4"
```

`-CheckOnly` probes and validates without encoding. `-PreviewSeconds` samples
the beginning of each stage, not the beginning of the complete movie. Defaults:
H.264 CRF 18, medium preset, stereo AAC 192 kb/s at 48 kHz, MP4 fast-start.
`-Crf` and `-Preset` control encoding. Use explicit outputs in private folders;
without `-Output`, the plan filename plus `-final.mp4` or `-preview.mp4` is used.

### Add music

```powershell
.\add-music.ps1 -Video "$work\renders\final.mp4" -Music "$work\videos\music.mp3" -MusicVolume 0.15 -Output "$work\renders\with-music.mp4"
```

Music loops and mixes with original audio. Defaults: music 20%, original 100%.
`-OriginalVolume` adjusts speech; `-ReplaceAudio` discards original audio.
A peak limiter is included; automatic speech ducking is not. Video is copied
and must already be MP4-compatible. Audio becomes AAC.

All editing tools preserve input paths and refuse existing outputs unless
`-Overwrite` is supplied. Image/speed/crop/music/join tools derive output names
beside their input when omitted. Keep inputs and outputs inside local-work.

## Plan format (for agents)

Plans have `width`, `height`, `fps` and ordered `segments`. Segment types:

- `card`: `file`, positive `duration`; silent static image.
- `full`: `file`, `start`, `duration`; source audio required.
- `overlay`: presenter `file`, `start`, `duration`, plus `background`, ordered
  `backgroundCuts` (start/duration pairs), `fit`, and tile `x`, `y`, `width`, `height`.

Times are seconds. Non-card duration 0 means source end. Canvas dimensions,
tile sizes and coordinates must be even. All resizing preserves aspect ratio
with opaque black padding. Background audio is discarded; only presenter audio
and card silence are used. Sources render directly in one encode.

Overlay timing modes leave presenter speed unchanged:

- `slow`: stretches selected screens to narration length; screens must be no longer.
- `hold`: normal speed, holds a short background or trims a long one.
- `slow-tail`: joins cuts, uses `speed` for the main section and stretches only
  the final `tailSeconds` to narration length.

Spatial crops and music use the separate tools, with exact steps in private
render notes. Do not assume extra JSON fields implement unsupported operations.

## Before sharing the tools

Keep local-work ignored. Review `git status --short` and `git ls-files` before
committing. `git ls-files -- local-work` must be empty. Ignored files remain
accessible locally; use explicit paths or `rg --files --hidden --no-ignore local-work`
when a search omits them. Never force-add private assets.

If an older repository history contains private references, a clean current
working tree does not erase them. Publish a fresh snapshot of the generic root
scripts, README.md, AGENTS.md and .gitignore into a new repository when a clean
history is required; exclude the old .git directory and local-work. Git ignore
rules are a guardrail, not a substitute for reviewing the published files.
