# SpatialVideo_Mux

A small macOS app and larger window 11 app that converts Apple **spatial (MV‑HEVC) videos** — like those shot on iPhone 15 Pro / 16 / maybe Vision Pro (untested) — into **3D side‑by‑side** MP4s ready to upload to **YouTube 3D** via a provided link.

It extracts the left and right eye views, lays them side by side, tags the stream
(the flag YouTube uses to detect 3D), and copies the original audio.

<Center>
<img src="SpatialVideo_Mux-macOS-arm64-v1.0.6%20screenshot.png" style="width: 50%; height: 50%" alt="Screenshot of SpatialVideo_Mux-macOS-arm64-v1.0.1">
</Center>

## Formats

|    Option   | Per‑eye size |             Output          |                        Use                         |
|-------------|--------------|-----------------------------|----------------------------------------------------|
| **3D HSBS** |   960×1080   | 1920×1080 half side‑by‑side | For 3D TV and Sharing your 3D content with friends |
| **3D FSBS** |   1920×1080  | 3840×1080 full side‑by‑side | Best for YouTube upload for VR                     |

## Requirements

- **Apple Silicon Mac** (the bundled ffmpeg is arm64).
- macOS 15 or later.

## Install

This app is distributed outside the Mac App Store and is **now apple notarized**. 
To open it:

1. **Uncompress zip file**
2. Move **SpatialVideo_Mux-macOS-arm64-v1.0.7** to your Applications folder if using macOS otherwise in Windows just run the SpatialVideo_Mux.exe
3. macOS : **Right‑click** the app → **Open** → **Open** again in the dialog. (You only need to do this once.)


## How to use

1. Click **Select Spatial Video** and choose an iPhone Spatial recorded video.
2. Pick **3D HSBS** or **3D FSBS** - Description changes depending which type you select.
3. **Enable 3D YouTube tag** when uploading to YouTube for VR YouTube playback in FSBS.
4. Click **Export Video** and choose where to save.
5. Upload the result to YouTube — it will be detected as 3D automatically.
6. Open YouTube VR app and playback your video to watch it with third dimension features added.


**Important note**
Spatial videos recorded on iPhone models 15 Pro and up can be transferred using the Airdrop function into macOS. I’m not fortunate enough to have tested the Apple Vision Pro so I don’t know if its recorded Spatial videos work in my app. 


## Built with FFmpeg and x264 within Xcode August 2026.

This app bundles and runs [FFmpeg](https://ffmpeg.org) as a **separate program** —
launched at runtime as its own process to decode MV‑HEVC and encode the output. 
FFmpeg is not linked into the app, and its source is not part of the app's own code.

The FFmpeg build used here comes from [FFmpeg](https://github.com/FFmpeg/FFmpeg and is licensed under the **GNU General Public License, version 3**.
The full corresponding source code for that build is available at:
**https://github.com/FFmpeg/FFmpeg**

Huge thanks to **x264 Project and the FFmpeg Development team** — without their work on this app would not be
possible. 🙏

## License

**SpatialVideo Mux is copyright software.** Copyright © 2026 Sebastian Gonzalez.

x264 and FFmpeg are licensed under: The GNU General Public License v3.0 (GPLv3).

The x264 Project: https://www.videolan.org/developers/x264.html Copyright (C) 2003-2026 x264 project.

The FFmpeg Project https://ffmpeg.org Copyright (c) 2000-2026 the FFmpeg project.

The corresponding source code for the bundled GPL components is available at:

The x264 Project: https://code.videolan.org/videolan/x264

FFmpeg: https://github.com/FFmpeg/FFmpeg/tree/n9.0



With thanks to both the FFmpeg development and the x264 project for their software, and for both my partner Matt for suffering through this and Claude for helping me persevere.
