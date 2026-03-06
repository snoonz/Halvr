# Halvr

A lightweight macOS app to convert videos to HEVC (H.265) format.

Drag and drop your video files, and they'll be converted to HEVC using hardware-accelerated encoding or software encoding.

## Features

- Drag & drop or file picker to add videos
- Queue-based batch conversion
- Hardware encoding (`hevc_videotoolbox`) for speed, or software encoding (`libx265`) for quality
- Three quality presets: High Quality, Standard, Small Size
- Automatic HEVC detection — already-encoded files are skipped
- Add files while conversion is in progress
- English and Japanese UI (follows system language)

## Requirements

- macOS 14.0+
- [ffmpeg](https://formulae.brew.sh/formula/ffmpeg) installed via Homebrew

```sh
brew install ffmpeg
```

## Build

Install [Mint](https://github.com/yonaskolb/Mint), then:

```sh
bash bootstrap.sh
xcodebuild -scheme Halvr build
```

Or open `Halvr.xcodeproj` in Xcode after running `bootstrap.sh`.

## Supported Formats

| | Formats |
|---|---|
| Input | MP4, MOV, M4V |
| Output | HEVC/H.265 in MP4 |

## License

MIT
