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
    case photo = "PHOTO"
    case video = "VIDEO"
    case pro = "PRO"
}

struct CameraScreen: View {
    @StateObject private var camera = CameraManager.shared
    @AppStorage("accentHex") private var accentHex = AppTheme.defaultHex
    private var accent: Color { Color(hex: accentHex) }

    @State private var zoomSlider: Double = 1.0
    @State private var pinchBase: Double = 1.0
    @State private var focusPoint: CGPoint?
    @State private var showLog = false
    @State private var showTheme = false
    @State private var mode: CaptureMode = .photo
    @State private var iso: Float = 100
    @State private var shutterMs: Double = 8.3 // ~1/120
    @State private var ev: Float = 0
    @State private var wbK: Double = 5200
    @State private var wbTint: Double = 0
    @State private var sat: Double = 1.0
    @State private var con: Double = 1.0
    @State private var bri: Double = 0.0
    @State private var styleOn = true
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
                // Slim top bar (OPPO): flash left, status center, tools right
                HStack(spacing: 4) {
                    Button(action: { camera.setTorch(!camera.torchOn) }) {
                        Image(systemName: camera.torchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 15))
                            .padding(10).background(.black.opacity(0.45)).foregroundColor(camera.torchOn ? accent : .white).clipShape(Circle())
                    }
                    Spacer()
                    if camera.isRecording {
                        Text(recText)
                            .font(.caption.monospacedDigit()).foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6).background(.red).clipShape(Capsule())
                    } else {
                        Text(mode == .pro ? "PRO · \(camera.lensLabel)" : camera.lensLabel)
                            .font(.caption).foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 10).padding(.vertical, 6).background(.black.opacity(0.45)).clipShape(Capsule())
                    }
                    Spacer()
                    Button(action: { showTheme = true }) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 15))
                            .padding(10).background(.black.opacity(0.45)).foregroundColor(accent).clipShape(Circle())
                    }
                    Button(action: { showLog = true }) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 15))
                            .padding(10).background(.black.opacity(0.45)).foregroundColor(.white).clipShape(Circle())
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
                // Zoom rings (Hasselblad): dark circles, accent ring = active lens
                HStack(spacing: 12) {
                    ForEach([1.0, 2.0, 4.0], id: \.self) { v in
                        let selected = abs(zoomSlider - v) < 0.15
                        Button(v == 1.0 ? "1×" : v == 2.0 ? "2×" : "4×") {
                            zoomSlider = v
                            pinchBase = v
                            camera.setLensPreset(v)
                        }
                        .font(.system(size: 13, weight: selected ? .bold : .regular))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(selected ? accent : .white.opacity(0.6), lineWidth: selected ? 2.5 : 1))
                    }
                }
                Slider(value: $zoomSlider, in: 1...8, step: 0.1)
                    .tint(accent)
                    .padding(.horizontal, 28)
                    .onChange(of: zoomSlider) { old, new in
                        ZoomController.tickIfCrossed(old: old, new: new)
                        camera.setZoomSmooth(new, rate: 8.0)
                        pinchBase = new
                    }
                if mode == .pro {
                    manualPanel
                }
                // Quality row — video mode only
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

                // Mode carousel (OPPO): swipeable text tabs, accent = active
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 30) {
                        ForEach(CaptureMode.allCases, id: \.self) { m in
                            Button(action: { mode = m }) {
                                VStack(spacing: 3) {
                                    Text(m.rawValue)
                                        .font(.system(size: 14, weight: mode == m ? .bold : .regular))
                                        .foregroundColor(mode == m ? accent : .white.opacity(0.6))
                                    Circle()
                                        .fill(mode == m ? accent : .clear)
                                        .frame(width: 5, height: 5)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 2)
                .disabled(camera.isRecording)

                // OPPO shutter row: thumbnail | big shutter | flip
                HStack {
                    if let img = camera.lastPhoto {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent, lineWidth: mode == .video ? 0 : 2))
                    } else {
                        Image(systemName: "photo").font(.system(size: 28)).foregroundColor(.white.opacity(0.8))
                            .frame(width: 46, height: 46)
                    }
                    Spacer()
                    if mode == .video {
                        Button(action: {
                            if camera.isRecording {
                                camera.stopVideoRecording()
                                recStart = nil
                            } else {
                                camera.startVideoRecording()
                                recStart = Date()
                            }
                        }) {
                            ZStack {
                                Circle().fill(.red).frame(width: 72, height: 72)
                                Circle().stroke(.white, lineWidth: 5).frame(width: 72, height: 72)
                                if camera.isRecording {
                                    RoundedRectangle(cornerRadius: 6).fill(.white).frame(width: 26, height: 26)
                                }
                            }
                        }
                    } else {
                        Button(action: {
                            shutterFlash = true
                            camera.capturePhoto()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { shutterFlash = false }
                        }) {
                            // Hasselblad: orange disc, white halo ring
                            ZStack {
                                Circle().fill(accent).frame(width: 72, height: 72)
                                Circle().stroke(.white, lineWidth: 4).frame(width: 84, height: 84)
                            }
                        }
                    }
                    Spacer()
                    Button(action: { camera.switchFrontBack() }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 20))
                            .padding(11).background(.black.opacity(0.55)).foregroundColor(.white).clipShape(Circle())
                    }
                    .frame(width: 46, height: 46)
                    .disabled(camera.isRecording)
                    .opacity(camera.isRecording ? 0.4 : 1)
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 26)
            }
        }
        .sheet(isPresented: $showLog) { LogSheet(camera: camera) }
        .sheet(isPresented: $showTheme) { NavigationView { ThemeSettingsView() } }
        .onAppear {
            iso = camera.iso
            shutterMs = camera.shutter * 1000
            ev = camera.exposureBias
            wbK = camera.wbTemp
            wbTint = camera.wbTint
            sat = camera.style.saturation
            con = camera.style.contrast
            bri = camera.style.brightness
            styleOn = camera.styleOnCapture
        }
    }

    private var recText: String {
        guard let s = recStart else { return "REC" }
        let e = Int(Date().timeIntervalSince(s))
        return String(format: "REC %02d:%02d", e / 60, e % 60)
    }

    // Pro photographic panel: EV/ISO/shutter bias, warm-cool WB, color style
    private var manualPanel: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Exposure bias
                VStack(spacing: 6) {
                    HStack {
                        Text("Exposure").font(.caption.bold()).foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%+.1f EV", ev)).font(.caption).foregroundColor(accent)
                    }
                    HStack {
                        Text("EV \(String(format: "%+.1f", ev))").font(.caption).foregroundColor(.white).frame(width: 70, alignment: .leading)
                        Slider(value: Binding(get: { Double(ev) }, set: { ev = Float($0) }), in: -3...3, step: 0.1)
                            .tint(accent)
                            .onChange(of: ev) { _, v in camera.setExposureBias(v) }
                    }
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
                    HStack(spacing: 8) {
                        ForEach([-1.0, 0.0, 1.0], id: \.self) { b in
                            Button(b == 0 ? "EV 0" : String(format: "%+.0f", b)) { ev = Float(b); camera.setExposureBias(Float(b)) }
                                .font(.caption).padding(6)
                                .background(ev == Float(b) ? accent : .white.opacity(0.12))
                                .foregroundColor(ev == Float(b) ? .black : .white)
                                .clipShape(Capsule())
                        }
                        Spacer()
                        Button("Auto EV") { ev = 0; camera.setExposureBias(0); camera.autoFocusExpose() }
                            .font(.caption).foregroundColor(accent)
                    }
                }
                .padding(8).background(.black.opacity(0.5)).cornerRadius(10)

                // White balance: warm <-> cool
                VStack(spacing: 6) {
                    HStack {
                        Text("White balance").font(.caption.bold()).foregroundColor(.white)
                        Spacer()
                        Text("\(Int(wbK))K").font(.caption).foregroundColor(accent)
                    }
                    HStack {
                        Text("❄︎ Cool").font(.caption).foregroundColor(.blue)
                        Slider(value: $wbK, in: 3000...8000, step: 50)
                            .tint(accent)
                            .onChange(of: wbK) { _, v in camera.setWhiteBalance(kelvin: v, tint: wbTint) }
                        Text("Warm 🔥").font(.caption).foregroundColor(.orange)
                    }
                    HStack {
                        Text("Tint \(Int(wbTint))").font(.caption).foregroundColor(.white).frame(width: 70, alignment: .leading)
                        Slider(value: $wbTint, in: -100...100, step: 1)
                            .tint(accent)
                            .onChange(of: wbTint) { _, v in camera.setWhiteBalance(kelvin: wbK, tint: v) }
                    }
                    HStack(spacing: 8) {
                        ForEach([("Auto", 0.0), ("Tungsten", 3200.0), ("Day", 5200.0), ("Cloudy", 6000.0), ("Shade", 7000.0)], id: \.0) { name, k in
                            Button(name) {
                                if k == 0 { camera.autoWhiteBalance() }
                                else { wbK = k; camera.setWhiteBalance(kelvin: k, tint: wbTint) }
                            }
                            .font(.caption).padding(6)
                            .background(k != 0 && abs(wbK - k) < 1 ? accent : .white.opacity(0.12))
                            .foregroundColor(k != 0 && abs(wbK - k) < 1 ? .black : .white)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(8).background(.black.opacity(0.5)).cornerRadius(10)

                // Color style (applied on capture + gallery preview)
                VStack(spacing: 6) {
                    HStack {
                        Text("Color style").font(.caption.bold()).foregroundColor(.white)
                        Spacer()
                        Toggle("On capture", isOn: $styleOn)
                            .font(.caption).tint(accent)
                            .onChange(of: styleOn) { _, v in camera.styleOnCapture = v }
                    }
                    photoStyleRow("Saturation", value: $sat, range: 0...2, def: 1.0)
                    photoStyleRow("Contrast", value: $con, range: 0.5...1.5, def: 1.0)
                    photoStyleRow("Brightness", value: $bri, range: -0.5...0.5, def: 0.0)
                    HStack {
                        Button("Vivid") { sat = 1.4; con = 1.1; pushStyle() }
                        Button("Neutral") { sat = 1.0; con = 1.0; bri = 0.0; pushStyle() }
                        Button("Mono") { sat = 0.0; pushStyle() }
                        Spacer()
                        Button("Reset all") { resetStyle() }
                    }
                    .font(.caption).foregroundColor(accent)
                }
                .padding(8).background(.black.opacity(0.5)).cornerRadius(10)

                HStack(spacing: 12) {
                    Button(camera.focusLocked ? "Focus: Locked" : "Lock Focus") { camera.lockFocus() }
                    Button(camera.wbLocked ? "WB: Locked" : "Lock WB") { camera.lockWhiteBalance() }
                    Button("Auto") { camera.autoFocusExpose(); camera.autoWhiteBalance() }
                }
                .font(.caption).foregroundColor(accent)
                .padding(6).background(.black.opacity(0.5)).cornerRadius(8)
            }
        }
        .frame(maxHeight: 320)
        .padding(.horizontal)
    }

    private func photoStyleRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, def: Double) -> some View {
        HStack {
            Text("\(title) \(String(format: "%.2f", value.wrappedValue))").font(.caption).foregroundColor(.white).frame(width: 130, alignment: .leading)
            Slider(value: value, in: range)
                .tint(accent)
                .onChange(of: value.wrappedValue) { _, _ in pushStyle() }
            Button("⟲") { value.wrappedValue = def; pushStyle() }.font(.caption).foregroundColor(accent)
        }
    }

    private func pushStyle() {
        var s = camera.style
        s.saturation = sat
        s.contrast = con
        s.brightness = bri
        s.temperature = wbK
        s.tint = wbTint
        camera.style = s
    }

    private func resetStyle() {
        ev = 0; camera.setExposureBias(0)
        wbK = 5200; wbTint = 0; camera.autoWhiteBalance()
        sat = 1.0; con = 1.0; bri = 0.0
        camera.style = .neutral
        camera.styleOnCapture = true
        styleOn = true
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
