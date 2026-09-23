import SwiftUI
import AVFoundation

struct PreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.session = session
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.session = session
    }
}

final class PreviewUIView: UIView {
    var session: AVCaptureSession? {
        didSet { setup() }
    }
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private func setup() {
        previewLayer?.removeFromSuperlayer()
        guard let session else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.addSublayer(layer)
        previewLayer = layer
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

enum CaptureMode: String, CaseIterable {
    case photo = "Photo"
    case video = "Video"
}

struct CameraScreen: View {
    @StateObject private var camera = CameraManager.shared
    @AppStorage("accentHex") private var accentHex = AppTheme.defaultHex
    private var accent: Color { Color(hex: accentHex) }

    @State private var zoomSlider: Double = 1.0
    @State private var pinchBase: Double = 1.0
    @State private var focusPoint: CGPoint?
    @State private var showManual = false
    @State private var showLog = false
    @State private var showTheme = false
    @State private var mode: CaptureMode = .photo
    @State private var iso: Float = 100
    @State private var shutterMs: Double = 8.3 // ~1/120
    @State private var recStart: Date?
    @State private var shutterFlash = false

    var body: some View {
        ZStack {
            GeometryReader { geo in
                PreviewView(session: camera.session)
                    .ignoresSafeArea()
                    .onAppear { camera.checkPermissionsAndConfigure() }
                    // Tap-to-focus (P1 AF/AE): normalized point -> device.
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let loc = value.location
                                let norm = CGPoint(
                                    x: loc.x / max(1, geo.size.width),
                                    y: loc.y / max(1, geo.size.height)
                                )
                                focusPoint = loc
                                camera.focusExpose(at: norm)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    focusPoint = nil
                                }
                            }
                    )
                    // Pinch zoom (P2): ramp, never jump.
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                let target = pinchBase * value.magnification
                                zoomSlider = min(8, max(1, target))
                                camera.setZoomSmooth(zoomSlider, rate: 8.0)
                            }
                            .onEnded { _ in pinchBase = zoomSlider }
                    )
            }
            .ignoresSafeArea()

            // Shutter flash
            if shutterFlash {
                Color.white.opacity(0.55).ignoresSafeArea()
            }

            // Focus reticle (tinted with custom color)
            if let fp = focusPoint {
                Image(systemName: "viewfinder")
                    .font(.system(size: 44))
                    .foregroundColor(accent)
                    .position(fp)
            }

            VStack {
                // Top bar: lens label, torch, theme, log
                HStack {
                    Text(camera.lensLabel)
                        .font(.headline).foregroundColor(.black)
                        .padding(8).background(accent).clipShape(Capsule())
                    Spacer()
                    if camera.isRecording {
                        Text(recText)
                            .font(.caption.monospacedDigit()).foregroundColor(.white)
                            .padding(8).background(.red).clipShape(Capsule())
                    }
                    Button(action: { camera.setTorch(!camera.torchOn) }) {
                        Image(systemName: camera.torchOn ? "bolt.fill" : "bolt.slash.fill")
                            .padding(10).background(.black.opacity(0.55)).foregroundColor(camera.torchOn ? accent : .white).clipShape(Circle())
                    }
                    Button(action: { showTheme = true }) {
                        Image(systemName: "paintpalette.fill")
                            .padding(10).background(.black.opacity(0.55)).foregroundColor(accent).clipShape(Circle())
                    }
                    Button(action: { showLog = true }) {
                        Image(systemName: "doc.text")
                            .padding(10).background(.black.opacity(0.55)).foregroundColor(.white).clipShape(Circle())
                    }
                }
                .padding(.horizontal)

                Spacer()
                if let err = camera.errorMessage {
                    HStack {
                        Text(err).font(.footnote).foregroundColor(.red).padding(6)
                        if err.lowercased().contains("denied") || err.lowercased().contains("settings") {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }.font(.footnote)
                        }
                    }
                    .background(.black.opacity(0.6)).cornerRadius(8)
                    .padding(.horizontal)
                }
                if let qr = camera.qrCode {
                    Button(action: { UIPasteboard.general.string = qr }) {
                        Text("QR: \(qr) (tap to copy)").font(.footnote).padding(6).background(.black.opacity(0.6)).foregroundColor(.white).cornerRadius(8)
                    }
                }
                // Mode selector (capture vs video)
                Picker("Mode", selection: $mode) {
                    ForEach(CaptureMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .tint(accent)
                .padding(.horizontal)
                .background(.black.opacity(0.35).cornerRadius(10))
                .padding(.horizontal, 60)

                // Lens presets: smooth ramp across triple camera (P2), selected = accent
                HStack(spacing: 16) {
                    ForEach([1.0, 2.0, 4.0], id: \.self) { v in
                        let selected = abs(zoomSlider - v) < 0.15
                        Button(v == 1.0 ? "1x" : v == 2.0 ? "2x" : "4x") {
                            zoomSlider = v
                            pinchBase = v
                            camera.setLensPreset(v)
                        }
                        .padding(10)
                        .background(selected ? accent : Color.black.opacity(0.55))
                        .foregroundColor(selected ? .black : .white)
                        .clipShape(Circle())
                    }
                    Button(action: { camera.switchFrontBack() }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .padding(10).background(.black.opacity(0.55)).foregroundColor(.white).clipShape(Circle())
                    }
                    Button(action: { showManual.toggle() }) {
                        Image(systemName: showManual ? "slider.horizontal.3" : "dial.low")
                            .padding(10).background(showManual ? accent : .black.opacity(0.55)).foregroundColor(showManual ? .black : .white).clipShape(Circle())
                    }
                }
                Slider(value: $zoomSlider, in: 1...8, step: 0.1)
                    .tint(accent)
                    .padding(.horizontal)
                    .onChange(of: zoomSlider) { old, new in
                        ZoomController.tickIfCrossed(old: old, new: new)
                        camera.setZoomSmooth(new, rate: 8.0)
                        pinchBase = new
                    }
                if showManual {
                    manualPanel
                }
                // Quality picker (P5) + mute — video mode emphasized
                if mode == .video || camera.isRecording {
                    HStack {
                        Picker("Quality", selection: $camera.videoQuality) {
                            ForEach(CameraManager.VideoQuality.allCases) { q in
                                Text(q.rawValue).tag(q)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.white)
                        Button(action: { camera.audioMuted.toggle() }) {
                            Image(systemName: camera.audioMuted ? "mic.slash.fill" : "mic.fill")
                                .foregroundColor(camera.audioMuted ? .red : accent).padding(8)
                        }
                    }
                    .background(.black.opacity(0.45)).cornerRadius(10)
                    .padding(.horizontal, 8)
                }

                // Capture + video shutter row
                HStack(spacing: 40) {
                    // Gallery thumbnail (P4)
                    if let img = camera.lastPhoto {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent, lineWidth: mode == .photo ? 2 : 0))
                    } else {
                        Image(systemName: "photo").font(.system(size: 30)).foregroundColor(.white.opacity(0.8))
                    }
                    // Photo capture
                    Button(action: {
                        shutterFlash = true
                        camera.capturePhoto()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { shutterFlash = false }
                    }) {
                        Circle().fill(mode == .photo ? .white : .gray).frame(width: 70, height: 70)
                            .overlay(Circle().stroke(accent, lineWidth: 3))
                    }
                    // Video capture
                    Button(action: {
                        if camera.isRecording {
                            camera.stopVideoRecording()
                            recStart = nil
                        } else {
                            mode = .video
                            camera.startVideoRecording()
                            recStart = Date()
                        }
                    }) {
                        Image(systemName: camera.isRecording ? "stop.circle.fill" : "video.circle.fill")
                            .font(.system(size: 44)).foregroundColor(camera.isRecording ? .red : (mode == .video ? accent : .white))
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showLog) { LogSheet(camera: camera) }
        .sheet(isPresented: $showTheme) { NavigationView { ThemeSettingsView() } }
        .onAppear {
            iso = camera.iso
            shutterMs = camera.shutter * 1000
        }
    }

    private var recText: String {
        guard let s = recStart else { return "REC" }
        let e = Int(Date().timeIntervalSince(s))
        return String(format: "REC %02d:%02d", e / 60, e % 60)
    }

    // P7 manual panel: ISO 34-2172, shutter 1/80000-1s, WB/focus lock
    private var manualPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("ISO \(Int(iso))").font(.caption).foregroundColor(.white).frame(width: 70, alignment: .leading)
                Slider(value: Binding(get: { Double(iso) }, set: { iso = Float($0) }), in: 34...2172, step: 1)
                    .tint(accent)
                    .onChange(of: iso) { _, v in camera.setManualExposure(iso: v, shutterSeconds: Double(shutterMs) / 1000) }
            }
            HStack {
                Text(shutterLabel).font(.caption).foregroundColor(.white).frame(width: 70, alignment: .leading)
                Slider(value: $shutterMs, in: 0.0125...1000, step: 0.5)
                    .tint(accent)
                    .onChange(of: shutterMs) { _, v in camera.setManualExposure(iso: iso, shutterSeconds: v / 1000) }
            }
            HStack(spacing: 12) {
                Button(camera.focusLocked ? "Focus: Locked" : "Lock Focus") { camera.lockFocus() }
                Button(camera.wbLocked ? "WB: Locked" : "Lock WB") { camera.lockWhiteBalance() }
                Button("Auto") { camera.autoFocusExpose() }
            }
            .font(.caption).foregroundColor(accent)
            .padding(6).background(.black.opacity(0.5)).cornerRadius(8)
        }
        .padding(.horizontal)
    }

    private var shutterLabel: String {
        let s = shutterMs / 1000
        if s >= 1 { return String(format: "%.1fs", s) }
        return "1/\(Int(round(1 / max(s, 0.0000125))))"
    }
}

struct LogSheet: View {
    @ObservedObject var camera: CameraManager
    var body: some View {
        NavigationView {
            ScrollView {
                Text("Sideload build: no Xcode console. Copy logs if install fails.\nSettings > General > VPN & Device Management > Trust, enable Developer Mode, reboot.")
                    .font(.caption).foregroundColor(.secondary).padding()
                Text(camera.logText.isEmpty ? "No logs yet." : camera.logText)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Logs")
            .toolbar {
                Button("Copy") { UIPasteboard.general.string = camera.logText }
                Button("Clear") { camera.logLines.removeAll() }
            }
        }
    }
}
