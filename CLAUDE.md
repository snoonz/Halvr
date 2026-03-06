# Halvr

macOS HEVC video converter app. SwiftUI + ffmpeg-kit.

## Build

```sh
bash bootstrap.sh        # Run XcodeGen via Mint → generate .xcodeproj
xcodebuild -scheme Halvr build
```

Re-generate after changing `project.yml`: `mint run xcodegen generate`

## Dependencies

- Mint (Mintfile): XcodeGen 2.33.0, SwiftGen 6.6.2, SwiftLint 0.50.3

## Supported Formats

- Input: MP4, MOV, M4V (metadata read via AVFoundation)
- Output: HEVC/H.265 in MP4 container

## Architecture

### Queue Management

`ConverterViewModel` manages the queue with a `[QueueItem]` array. Each `QueueItem` has its own status:
- `pending` → `converting(progress)` → `completed(outputURL)` / `skipped(error)`

The drop zone is always visible. Files can be added during or after conversion. Added files are automatically enqueued and processed sequentially once the current conversion finishes.

### Conversion Engine

Uses ffmpeg-kit's `FFmpegKit.executeAsync()`. Progress is tracked via StatisticsCallback.

- `VideoConverting` protocol → `FFmpegConverter` implementation
- `VideoMetadataReading` protocol → `VideoMetadataReader` implementation (AVFoundation)
- Encoder selection: `hevc_videotoolbox` (HW, fast) / `libx265` (SW, high quality)
- Quality by preset: videotoolbox uses `-q:v`, libx265 uses `-crf`
- Cancel: `FFmpegKit.cancel(sessionId)`
- Partial output files are automatically deleted on cancel or error

### Output Filename

`OutputPathResolver.resolve()` generates `{original_name}_HEVC.mp4`. Appends `_1`, `_2` suffix when a file with the same name exists.

## File Structure

```
Halvr/
├── HalvrApp.swift                 # @main, hiddenTitleBar, 280x420 fixed size
├── Models/
│   ├── ConversionState.swift       # QueueItem + QueueItemStatus + ErrorInfo
│   ├── ConversionSettings.swift    # ExportPreset, EncoderType (videotoolbox/libx265)
│   └── VideoMetadata.swift         # duration, resolution, codec, fileSize, isAlreadyHEVC
├── Services/
│   ├── VideoConverter.swift        # ConversionError, VideoConverting, FFmpegConverter
│   ├── VideoMetadataReader.swift   # Metadata extraction from AVURLAsset, FourCC codec detection
│   ├── OutputPathResolver.swift    # Output path generation + deduplication
│   └── SupportedFormats.swift      # UTType definitions, format validation
├── ViewModels/
│   └── ConverterViewModel.swift    # @Observable @MainActor, dynamic queue management / add-during-conversion
├── Views/
│   ├── ContentView.swift           # Always-visible drop zone + queue list layout
│   ├── DropZoneView.swift          # Dashed drop zone (compact/normal), onDrop + onTapGesture
│   ├── QueueListView.swift         # Queue list (status display, remove/clear/cancel)
│   └── CustomTitleBar.swift        # "Convert Video" title, settings button
├── Extensions/
│   └── URL+VideoHelpers.swift
└── Resources/
    ├── Halvr.entitlements          # Hardened Runtime (no App Sandbox)
    └── Localizable.xcstrings       # String Catalog (en/ja)
```

## Notes

- `FFmpegConverter` is `@unchecked Sendable` (manual currentSessionId management)
- App Sandbox disabled (required for ffmpeg external process execution, not intended for distribution)
- HEVC detection: compares against `kCMVideoCodecType_HEVC` via FourCC (AVFoundation)
- UI localized for English and Japanese (follows OS language, uses String Catalog)
