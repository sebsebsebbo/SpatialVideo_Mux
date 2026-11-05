# FFmpeg and x264 source code (Windows build)

**SpatialVideo_Mux for Windows v1.12** bundles `ffmpeg.exe` and `ffprobe.exe` and runs them as separate programs. They are not linked into the app.

FFmpeg and x264 are licensed under the **GNU General Public License v3.0** ([LICENSE-GPLv3.txt](LICENSE-GPLv3.txt)). This folder holds the complete corresponding source code for the exact versions bundled in the Windows download, as the GPL requires.

## FFmpeg

| | |
|---|---|
| Version | `N-126239-g88ae625e69-20260821` |
| Commit | [`88ae625e698d7a1c0b7dcea8d915915acda3f054`](https://github.com/FFmpeg/FFmpeg/tree/88ae625e698d7a1c0b7dcea8d915915acda3f054) (21 Aug 2026) |
| Source | [FFmpeg/FFmpeg-88ae625e698d7a1c0b7dcea8d915915acda3f054.tar.gz](FFmpeg/) |
| SHA-256 | `2186489CF7425AF700D3639DA1AF275E743077AEAED34C91F439713D671D4603` |
| Build | Windows x64 GPL build by [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds), built with gcc 15.2.0 (crosstool-NG) |
| Configuration | [FFmpeg/build-configuration.txt](FFmpeg/build-configuration.txt) |

## x264

| | |
|---|---|
| Version | core 165 (`X264_BUILD 165`) |
| Commit | [`0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee`](https://code.videolan.org/videolan/x264/-/tree/0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee) |
| Source | [x264/x264-0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee.tar.gz](x264/) |
| SHA-256 | `D0967A1348C85DFDE363BB52610403BE898171493100561EFA0DD05D5FD1AE50` |

The x264 commit is the one pinned in BtbN/FFmpeg-Builds `scripts.d/50-x264.sh` at the time of this build ([build scripts as of 18 Aug 2026](https://github.com/BtbN/FFmpeg-Builds/tree/48576f197ad1c2afb2e0b8efe204919a1afbff54)).

## Other libraries

The bundled `ffmpeg.exe` is a full static build that also includes other open-source libraries (listed in the build configuration). The exact versions and source locations of all of them are pinned in the BtbN/FFmpeg-Builds scripts linked above.

## Links

- FFmpeg: https://ffmpeg.org – Copyright (c) 2000-2026 the FFmpeg developers
- x264: https://www.videolan.org/developers/x264.html – Copyright (C) 2003-2026 x264 project
