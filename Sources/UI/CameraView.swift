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

struct CameraScreen: View {
    @StateObject private var camera = CameraManager.shared
    @State private var zoomSlider: Double = 1.0
    @State private var pinchBase: Double = 1.0
    @State private var focusPoint: CGPoint?
    @State private var showManual = false
    @State private var showLog = false
    @State private var iso: Float = 100
    @State private var shutterMs: Double = 8.3 // ~1/120
    @State private var recStart: Date?

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

            // Focus reticle
            if let fp = focusPoint {
                Image(systemName: "viewfinder")
                    .font(.system(size: 44))
                    .foregroundColor(.yellow)
                    .position(fp)
            }

            VStack {
                // Top bar: lens label, torch, log
                HStack {
                    Text(camera.lensLabel)
                        .font(.headline).foregroundColor(.white)
                        .padding(8).background(.black.opacity(0.55)).clipShape(Capsule())
                    Spacer()
                    if camera.isRecording {
                        Text(recText)
                            .font(.caption.monospacedDigit()).foregroundColor(.red)
                            .padding(8).background(.black.opacity(0.55)).clipShape(Capsule())
                    }
                    Button(action: { camera.setTorch(!camera.torchOn) }) {
                        Image(systemName: camera.torchOn ? "bolt.fill" : "bolt.slash.fill")
                            .padding(10).background(.black.opacity(0.55)).foregroundColor(camera.torchOn ? .yellow : .white).clipShape(Circle())
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
                // Lens presets: smooth ramp across triple camera (P2)
                HStack(spacing: 16) {
                    ForEach([1.0, 2.0, 4.0], id: \.self) { v in
                        Button(v == 1.0 ? "1x" : v == 2.0 ? "2x" : "4x") {
                            zoomSlider = v
                            pinchBase = v
                            camera.setLensPreset(v)
                        }
                        .padding(10)
                        .background(.black.opacity(0.55))
                        .foregroundColor(.white)
                        .clipShape(Circle())
                    }
                    Button(action: { camera.switchFrontBack() }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .padding(10).background(.black.opacity(0.55)).foregroundColor(.white).clipShape(Circle())
                    }
                    Button(action: { showManual.toggle() }) {
                        Image(systemName: showManual ? "slider.horizontal.3" : "dial.low")
                            .padding(10).background(.black.opacity(0.55)).foregroundColor(.white).clipShape(Circle())
                    }
                }
                Slider(value: $zoomSlider, in: 1...8, step: 0.1)
                    .padding(.horizontal)
                    .onChange(of: zoomSlider) { old, new in
                        ZoomController.tickIfCrossed(old: old, new: new)
                        camera.setZoomSmooth(new, rate: 8.0)
                        pinchBase = new
                    }
                if showManual {
                    manualPanel
                }
                // Quality picker (P5) + mute
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
                            .foregroundColor(.white).padding(8)
                    }
                }
                .background(.black.opacity(0.45)).cornerRadius(10)
                .padding(.horizontal, 8)

                HStack(spacing: 40) {
                    // Gallery thumbnail (P4)
                    if let img = camera.lastPhoto {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "photo").font(.system(size: 30)).foregroundColor(.white.opacity(0.8))
                    }
                    Button(action: { camera.capturePhoto() }) {
                        Circle().fill(.white).frame(width: 70, height: 70)
                            .overlay(Circle().stroke(.black, lineWidth: 2))
                    }
                    Button(action: {
                        if camera.isRecording {
                            camera.stopVideoRecording()
                            recStart = nil
                        } else {
                            camera.startVideoRecording()
                            recStart = Date()
                        }
                    }) {
                        Image(systemName: camera.isRecording ? "stop.circle.fill" : "video.circle.fill")
                            .font(.system(size: 44)).foregroundColor(camera.isRecording ? .red : .white)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showLog) { LogSheet(camera: camera) }
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
                    .onChange(of: iso) { _, v in camera.setManualExposure(iso: v, shutterSeconds: Double(shutterMs) / 1000) }
            }
            HStack {
                Text(shutterLabel).font(.caption).foregroundColor(.white).frame(width: 70, alignment: .leading)
                Slider(value: $shutterMs, in: 0.0125...1000, step: 0.5)
                    .onChange(of: shutterMs) { _, v in camera.setManualExposure(iso: iso, shutterSeconds: v / 1000) }
            }
            HStack(spacing: 12) {
                Button(camera.focusLocked ? "Focus: Locked" : "Lock Focus") { camera.lockFocus() }
                Button(camera.wbLocked ? "WB: Locked" : "Lock WB") { camera.lockWhiteBalance() }
                Button("Auto") { camera.autoFocusExpose() }
            }
            .font(.caption).foregroundColor(.white)
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
