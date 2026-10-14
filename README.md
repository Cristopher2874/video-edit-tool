# Quick video tools

PowerShell scripts for image cards, joining clips, cropping/trimming, and music.
Run examples from this folder in Windows PowerShell 5.1 or PowerShell 7+.
Install FFmpeg and FFprobe on PATH, or supply `-FFmpeg` and `-FFprobe` paths
(image-to-video only requires FFmpeg).

## Image to video

```powershell
.\image-to-video.ps1 -Image '.\friday_demos_image.png' -Duration 2 -Output '.\intro.mp4'
```

Creates a silent static card. Defaults: two seconds, 1920x1080, 30 fps.
Use `-Width`, `-Height`, `-FrameRate` to customize. Images fill the frame with
center cropping. Without `-Output`, saves beside the image as `<name>-2s.mp4`
or `<name>-static.mp4` for other durations.

## Join clips, with an optional intro

```powershell
.\add-intro.ps1 -Intro '.\friday-demos-intro-2s.mp4' -Recording '.\ffmpeg_demo.mp4' -Output '.\episode.mp4'
.\add-intro.ps1 -Recording @('.\part1.mp4', '.\part2.mp4', '.\outro.mp4') -Output '.\joined.mp4'
```

`-Videos` is an alias for `-Recording`. Clips play in the supplied order.
An explicit `-Intro` goes first; omitting it joins just the supplied recordings.
The old implicit Nitro intro was removed because that asset was not migrated.
Each clip retains its audio; silent clips get silence and short audio is padded.
Video dimensions match the first recording with letterboxing to preserve aspect
ratio. All clips use 30 fps by default (`-FrameRate` overrides this).
The default output is `<first-recording>-with-intro.mp4` with an intro,
or `<first-recording>-joined.mp4` otherwise.

Use array syntax in a PowerShell session or a `.ps1` script; when launching
`powershell.exe -File`, a single `-Recording` value works directly.

## Crop a rectangle or trim time

```powershell
.\crop-video.ps1 -Video '.\joined.mp4' -Width 1080 -Height 1080 -Output '.\square.mp4'
.\crop-video.ps1 -Video '.\joined.mp4' -Start 5 -Duration 20 -Output '.\excerpt.mp4'
.\crop-video.ps1 -Video '.\joined.mp4' -Width 640 -Height 360 -X 100 -Y 40 -Start 2 -Duration 8
```

Spatial cropping removes pixels without resizing. Dimensions must fit the
source and be even. Offsets are even pixels measured from the top left;
omit them for a centered crop. Omit dimensions to retain the full frame
(odd source dimensions lose at most one edge pixel). Times are seconds;
`-Duration 0` means to the end. Default output: `<video>-cropped.mp4`.
Audio is retained when present. Cropping/trimming re-encodes for accurate cuts.

## Add background music

```powershell
.\add-music.ps1 -Video '.\excerpt.mp4' -Music '.\music.mp3' -MusicVolume 0.15
.\add-music.ps1 -Video '.\excerpt.mp4' -Music '.\music.mp3' -ReplaceAudio -MusicVolume 0.8
```

Music loops to the video duration. By default it mixes with the original audio
at 20% volume while the original stays at 100%. `-OriginalVolume` adjusts that
level; `-ReplaceAudio` discards it. Silent videos also work. Mixing uses a peak
limiter, but does not automatically lower music during speech. Video is copied
without re-encoding; it must already use an MP4-compatible codec. Audio becomes
AAC. Default output: `<video>-with-music.mp4`.

All scripts require an existing output folder, write MP4, protect input paths,
and refuse existing outputs unless `-Overwrite` is supplied. Joining and cropping
encode H.264/AAC, which can take time on long recordings. Keep `video-common.ps1`
beside the three editing scripts; it provides shared validation and media probing.
