# CameraApp — Plan (iPhone 11 Pro Max first, Android later)

## 1. Goal
Native iOS camera app, starting on iPhone 11 Pro Max. Sideload for free (no $99 dev account). Android later via Kotlin + CameraX.

## 2. Target hardware
- iPhone 11 Pro Max: A13, Triple 12MP (13mm Ultra f/2.4 / 26mm Wide f/1.8 OIS / 52mm Tele f/2.0 OIS)
- Smart HDR, Night Mode (auto only, no public API), Deep Fusion, 4K60 + Extended Dynamic Range, 1080p240 slow-mo
- Min SDK: iOS 17.0, Xcode 16+, Swift 5.9, SwiftUI + AVFoundation

## 3. Stack (chosen)
- Native Swift / SwiftUI + `AVCaptureSession` on background queue
- Preview via `UIViewRepresentable` + `AVCaptureVideoPreviewLayer` (never SwiftUI canvas for viewfinder)
- XcodeGen (`project.yml`) so Windows can edit without `.xcodeproj` conflicts
- GitHub Actions `macos-15` builds unsigned IPA -> Sideloadly on Windows -> iPhone

Repo layout (scaffolded):
```
project.yml
Sources/Info.plist
Sources/App.swift
Sources/ContentView.swift
Sources/Core/CameraManager.swift  # session, photo, video, QR, manual
Sources/Core/ZoomController.swift # smooth ramp
Sources/Core/LUTEngine.swift      # .cube -> CIColorCube
Sources/Core/VideoTrimmer.swift   # AVAssetExportSession trim
Sources/UI/CameraView.swift       # preview + controls
.github/workflows/ios-build.yml   # unsigned IPA
```

Permissions (`Sources/Info.plist`):
`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSPhotoLibraryUsageDescription`

## 4. Features

### v1 Photo MVP
- [x] scaffold session + permissions
- [ ] shutter, AF/AE, torch, HEVC + high-res
- [ ] lens: prefer `builtInTripleCamera` virtual device, fallback dual -> wide
- [ ] zoom 1-8x smooth (see §6), presets 1x/2x/4x + slider + haptics
- [ ] portrait depth (`isDepthDataDeliveryEnabled`) + custom blur toggle
- [ ] night: `automaticallyEnablesLowLightBoostWhenAvailable` + longer auto exposure
- [ ] gallery thumbnail + save via `UIImageWriteToSavedPhotosAlbum`

### v2 Video
- Basic: `AVCaptureMovieFileOutput`, 1080p/4K30, front/back switch, `.cinematicExtended` stabilization
- Pro: 4K60 wide/tele, 1080p240 slow-mo, timelapse sampling, focus/exposure lock while recording
- Audio + trim: mic meter + mute, `VideoTrimmer.trim` export mp4
- Session switches `.photo` <-> `.high` via `beginConfiguration()`

### v3 Pro + extras
- Manual: `setExposureModeCustom(duration:iso:)` ISO 34-2172, shutter 1/80000-1s, WB lock, focus lock
- LUT: import `.cube` via fileImporter -> `LUTEngine.load` -> `CIColorCube` preview + export
- QR: `AVCaptureMetadataOutput` [.qr, .ean13, .aztec] + overlay + tap-copy

## 5. Video/audio details
- Container `.mov` capture -> export `.mp4` highest quality
- Keep one session for photo+video, don't duplicate
- Restore `.photo` preset after recording stops

## 6. Smooth zoom + smoothness (key request)
- Always `ramp(toVideoZoomFactor:withRate:)` never direct set — animates across ultra->wide->tele switch points
- Cap 8x (`min(activeFormat.videoMaxZoomFactor, 8)`)
- Slider throttled, `CADisplayLink` ideal, haptic tick at 2x/4x via `ZoomController.tickIfCrossed`
- Preview 60fps, minimize SwiftUI redraws (preview is UIKit layer)
- Test on device: drag slider fast 1x->8x, tap 1x/2x/4x, no jump or stall

## 7. Free sideload loop (no paid account)
1. Edit on Windows, push to `main`
2. Actions: `xcodegen generate` -> `xcodebuild archive CODE_SIGNING_ALLOWED=NO` -> zip `Payload/*.app` -> `CameraApp-unsigned.ipa` artifact
3. Download IPA on Windows
4. Sideloadly (needs iTunes + iCloud from Apple.com, not Store) + USB cable + free Apple ID -> Install
5. Phone: `Settings > General > VPN & Device Management > Trust`, enable `Settings > Privacy & Security > Developer Mode`, reboot
6. Limits: reinstall every 7 days, 3 apps max, no live Xcode logs -> use in-app log export to Files

## 8. Agent task order
- P0 green build: `xcodegen generate` clean, IPA uploads
- P1 photo MVP
- P2 smooth zoom
- P3 portrait + night
- P4 gallery + filters
- P5 video basic + pro picker
- P6 trim + audio
- P7 manual controls UI
- P8 LUT import + QR overlay
- P9 sideload polish: permission errors, log view, Developer Mode hint

Each phase done = installs via Sideloadly and works on 11 Pro Max first launch.

## 9. Test checklist (11 Pro Max device)
- [ ] fresh install asks camera/mic/photos, preview starts
- [ ] photo saves to library
- [ ] 1x/2x/4x + slider smooth, no jump
- [ ] portrait + low-light no crash
- [ ] 30s 4K video saves + plays
- [ ] trim exports
- [ ] manual ISO/shutter visible change
- [ ] 33-size .cube applies <100ms preview
- [ ] QR detects and shows string

## 10. Android later
- Parity with Kotlin + CameraX + `Camera2` vendor extensions
- Reuse LUT logic via OpenGL, same UX presets
- Paid Play signing when ready, keep iOS bundle `com.sideload.cameraapp` separate
