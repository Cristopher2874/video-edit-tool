# Add the Nitro 101 intro to a recording

## Make a static intro or outro from an image

`image-to-video.ps1` creates a silent MP4 that displays one image for two seconds by default. The image fills a 1920×1080 frame; if its proportions differ, the edges are cropped evenly. You can use the resulting clip at the start or end of a recording.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\video-tools\image-to-video.ps1' -Image '.\video-tools\nitro-101-intro-card.png' -Output '.\video-tools\my-intro.mp4'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\video-tools\image-to-video.ps1' -Image 'C:\Videos\end-card.png' -Output 'C:\Videos\my-outro.mp4' -Duration 2
```

`-Output` is optional. Without it, the script saves beside the image as `<image-name>-2s.mp4` (or `<image-name>-static.mp4` for another duration). Use `-Width`, `-Height`, and `-FrameRate` to match your recording; the defaults are 1920, 1080, and 30. Existing outputs are protected unless you pass `-Overwrite`. The script requires FFmpeg but does not require FFprobe; pass `-FFmpeg` with the executable's full path if it is not on PATH.

For an existing video intro, use `add-intro.ps1` as described below. To add the same static clip at the end, place the generated MP4 after your recording in your video editor.

## Add an intro to a recording

`add-intro.ps1` places the [two-second intro](nitro-101-intro-2s.mp4) before a Zoom recording and writes a new MP4. It keeps the recording's audio, with silence during the intro. It also works with a recording that has no audio.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- FFmpeg **and** FFprobe installed. Check with `ffmpeg -version` and `ffprobe -version`. If needed, get FFmpeg from the [official download page](https://ffmpeg.org/download.html) and add its `bin` folder to your PATH.

## Run

From the repository folder in PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\video-tools\add-intro.ps1' -Recording 'C:\Videos\zoom-recording.mp4'
```

The output appears beside the recording as `zoom-recording-with-intro.mp4`.

Choose another output name if you prefer:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\video-tools\add-intro.ps1' -Recording 'C:\Videos\zoom-recording.mp4' -Output 'C:\Videos\episode-01.mp4'
```

The script never replaces an existing output unless you add `-Overwrite`. To use another intro, pass `-Intro 'C:\Videos\other-intro.mp4'`. If FFmpeg is not on PATH, pass full executable paths with `-FFmpeg` and `-FFprobe`.

The video is encoded as H.264 and the audio as AAC. Both clips are scaled or letterboxed to the recording's dimensions and frame rate, so processing a long Zoom recording may take a while. The original files are left intact.

## This project

From any PowerShell folder, the full-path command is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Cristopher Hdz\Documents\projects\nitro-101\discover\video-tools\add-intro.ps1" -Recording "C:\Users\Cristopher Hdz\Documents\projects\nitro-101\discover\video-tools\0_nitro_capsule.mp4" -Intro "C:\Users\Cristopher Hdz\Documents\projects\nitro-101\discover\video-tools\nitro-101-intro-2s.mp4"
```
