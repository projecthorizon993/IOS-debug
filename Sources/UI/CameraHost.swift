import SwiftUI
import AVFoundation

/// Binds the UI-only kit (CameraUIState in CameraUI.swift) to the real engine.
/// CameraUI.swift stays untouched: all AVFoundation lives here.
struct CameraHostView: View {
    @StateObject private var camera = CameraManager.shared
    @StateObject private var ui = CameraUIState()
    @State private var lastZoom = 1.0
    @State private var recStart: Date?

    var body: some View {
        ZStack {
            CameraUI(
                state: ui,
                preview: { PreviewView(session: camera.session) },
                onCapture: capture,
                onSettings: { ui.showSettings = true },
                onQRScanner: { ui.showQRScanner = true },
                onGallery: { ui.showEditor = true },
                onFlipCamera: {
                    guard !camera.isRecording else { return }
                    camera.switchFrontBack()
                },
                onModeChanged: modeChanged,
                onZoomChanged: zoomChanged,
                onFocus: focus
            )

            // REC indicator (the kit has none): overlay while recording.
            if camera.isRecording {
                VStack {
                    Text(recText)
                        .font(.caption.monospacedDigit()).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.red).clipShape(Capsule())
                        .padding(.top, 64)
                    Spacer()
                }
            }
        }
        .onAppear {
            camera.checkPermissionsAndConfigure()
            ui.iso = Int(camera.iso)
            ui.shutter = camera.shutter
            ui.exposure = Double(camera.exposureBias)
            ui.whiteBalance = Int(camera.wbTemp)
            ui.saturation = camera.style.saturation - 1.0
            ui.contrast = camera.style.contrast
            ui.focusMode = camera.focusLocked ? "LOCKED" : "AUTO"
            lastZoom = ui.zoom
        }
        .onChange(of: ui.exposure) { _, v in camera.setExposureBias(Float(v)) }
        .onChange(of: ui.shutter) { _, v in
            camera.setManualExposure(iso: camera.iso, shutterSeconds: v)
        }
        .onChange(of: ui.whiteBalance) { _, v in
            camera.setWhiteBalance(kelvin: Double(v), tint: camera.wbTint)
        }
        .onChange(of: ui.preset) { _, p in applyPreset(p) }
        .onChange(of: ui.saturation) { _, _ in pushEditorStyle() }
        .onChange(of: ui.contrast) { _, _ in pushEditorStyle() }
        .onChange(of: camera.isRecording) { _, rec in
            recStart = rec ? Date() : nil
        }
        .sheet(isPresented: $ui.showEditor) {
            CameraEditorUI(state: ui, image: { editorImage }) {
                ui.showEditor = false
            } onSaveCopy: {
                saveEditorCopy()
            }
        }
        .sheet(isPresented: $ui.showSettings) { HostSettingsSheet() }
        .sheet(isPresented: $ui.showQRScanner) { qrSheet }
    }

    // MARK: - Callbacks

    private func capture() {
        if ui.mode == .video {
            camera.isRecording ? camera.stopVideoRecording() : camera.startVideoRecording()
        } else {
            // photo / portrait / night / pro / xpan all capture stills;
            // night uses auto low-light boost, portrait uses depth/matte.
            camera.capturePhoto()
        }
    }

    private func modeChanged(_ m: CameraUIMode) {
        if m != .video && camera.isRecording {
            camera.stopVideoRecording()
        }
        camera.log("ui mode \(m.rawValue)")
    }

    private func zoomChanged(_ zoom: Double) {
        ZoomController.tickIfCrossed(old: lastZoom, new: zoom)
        lastZoom = zoom
        // 0.6× pill clamps to 1.0 on device (no ultra-wide virtual zoom-out).
        camera.setZoomSmooth(CGFloat(max(1.0, zoom)))
        ui.zoom = max(0.6, zoom)
    }

    private func focus(_ location: CGPoint) {
        // The kit's focus strip reports points in its own 170pt area, so only
        // the horizontal axis maps cleanly; height is pinned to mid-frame.
        // (For pixel-exact tap-focus the strip must cover the full preview.)
        let w = UIScreen.main.bounds.width
        guard w > 0 else { return }
        camera.focusExpose(at: CGPoint(x: min(1, max(0, location.x / w)), y: 0.5))
    }

    // MARK: - Editor -> PhotoStyle

    /// Kit saturation is an offset (editor shows +0.2); engine uses multiplier.
    private func pushEditorStyle() {
        var s = camera.style
        s.saturation = max(0, 1.0 + ui.saturation)
        s.contrast = ui.contrast
        camera.style = s
    }

    private func applyPreset(_ p: CameraUIPreset) {
        switch p {
        case .natural:
            ui.saturation = 0.0
            ui.contrast = 1.0
        case .vivid:
            ui.saturation = 0.4
            ui.contrast = 1.15
        case .mono:
            ui.saturation = -1.0
        case .imported:
            // .cube LUT import lives in the Gallery tab.
            camera.log("editor: imported preset needs a .cube from Gallery")
        }
        pushEditorStyle()
    }

    private var editorImage: some View {
        Group {
            if let img = camera.lastPhoto {
                Image(uiImage: camera.style.apply(to: img) ?? img)
                    .resizable()
                    .scaledToFit()
            } else {
                CameraPreviewPlaceholder()
            }
        }
    }

    private func saveEditorCopy() {
        guard let img = camera.lastPhoto else { return }
        let out = camera.style.apply(to: img) ?? img
        UIImageWriteToSavedPhotosAlbum(out, nil, nil, nil)
        camera.log("editor saved copy")
    }

    private var recText: String {
        guard let s = recStart else { return "REC" }
        let e = Int(Date().timeIntervalSince(s))
        return String(format: "REC %02d:%02d", e / 60, e % 60)
    }

    private var qrSheet: some View {
        NavigationView {
            VStack(spacing: 16) {
                if let qr = camera.qrCode {
                    Text(qr).font(.body).multilineTextAlignment(.center).padding()
                    Button("Copy") { UIPasteboard.general.string = qr }
                } else {
                    Image(systemName: "qrcode").font(.system(size: 60)).foregroundColor(.gray)
                    Text("Point the camera at a QR code.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("QR Scanner")
            .toolbar {
                Button("Done") { ui.showQRScanner = false }
            }
        }
    }
}

private struct HostSettingsSheet: View {
    var body: some View {
        NavigationView {
            List {
                NavigationLink("Theme accent") { ThemeSettingsView() }
                NavigationLink("Logs") { LogSheet(camera: CameraManager.shared) }
            }
            .navigationTitle("Settings")
        }
    }
}
