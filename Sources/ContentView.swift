import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("accentHex") private var accentHex = AppTheme.defaultHex
    var body: some View {
        TabView {
            CameraScreen()
                .tabItem { Label("Camera", systemImage: "camera") }
            GalleryView()
                .tabItem { Label("Gallery", systemImage: "photo.on.rectangle") }
            NavigationView { ThemeSettingsView() }
                .tabItem { Label("Theme", systemImage: "paintpalette") }
        }
        .tint(Color(hex: accentHex))
    }
}

struct GalleryView: View {
    @StateObject private var camera = CameraManager.shared
    @AppStorage("accentHex") private var accentHex = AppTheme.defaultHex
    private var accent: Color { Color(hex: accentHex) }
    @State private var showLUTImporter = false
    @State private var lut: LUTEngine.CubeLUT?
    @State private var lutName = ""
    @State private var filteredImage: UIImage?
    @State private var trimStart = 0.0
    @State private var trimEnd = 5.0
    @State private var trimBusy = false
    @State private var trimResult: URL?
    @State private var trimMessage = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Last photo + LUT preview (P4/P8) + photo style
                    if let img = camera.lastPhoto {
                        let styled = camera.style.isNeutral ? img : (camera.style.apply(to: img) ?? img)
                        Image(uiImage: filteredImage ?? styled)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                            .padding(.horizontal)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(lut != nil ? accent : Color.clear, lineWidth: 2)
                                    .padding(.horizontal)
                            )
                        // Hasselblad style cards: NATURAL / VIVID / MONO / IMPORT
                        HStack(spacing: 12) {
                            styleCard(title: "NATURAL", systemImage: "circle", selected: camera.style.isNeutral) {
                                camera.style = .neutral
                            }
                            styleCard(title: "VIVID", systemImage: "sun.max", selected: camera.style.saturation > 1.2 && camera.style.contrast > 1.05) {
                                var s = camera.style; s.saturation = 1.4; s.contrast = 1.1; camera.style = s
                            }
                            styleCard(title: "MONO", systemImage: "circle.lefthalf.filled", selected: !camera.style.isNeutral && camera.style.saturation == 0) {
                                var s = camera.style; s.saturation = 0; camera.style = s
                            }
                            styleCard(title: "IMPORT", systemImage: "plus", selected: lut != nil) {
                                showLUTImporter = true
                            }
                        }
                        if !lutName.isEmpty {
                            HStack {
                                Text("LUT: \(lutName)").font(.caption).foregroundColor(.secondary)
                                Button("Clear") { lut = nil; filteredImage = nil; lutName = "" }
                                    .font(.caption)
                            }
                        }
                        if !camera.style.isNeutral {
                            Text("Style: \(Int(camera.style.temperature))K tint \(Int(camera.style.tint)) sat \(String(format: "%.2f", camera.style.saturation)) con \(String(format: "%.2f", camera.style.contrast))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Button("SAVE COPY") {
                            let base = filteredImage ?? img
                            let out = camera.style.apply(to: base) ?? base
                            UIImageWriteToSavedPhotosAlbum(out, nil, nil, nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No photo yet. Capture from Camera tab.")
                            .foregroundColor(.secondary)
                    }
                    if let qr = camera.qrCode {
                        Button(action: { UIPasteboard.general.string = qr }) {
                            Text("QR: \(qr) (tap to copy)")
                                .font(.footnote).padding(8)
                                .background(Color.black.opacity(0.07)).cornerRadius(8)
                        }
                    }
                    // Video + trim (P6)
                    if let url = camera.lastVideoURL {
                        Text("Video: \(url.lastPathComponent)").font(.footnote).foregroundColor(.secondary)
                        VideoPlayer(player: AVPlayer(url: url))
                            .frame(height: 220).cornerRadius(12).padding(.horizontal)
                        VStack {
                            HStack {
                                Text("Start \(trimStart, specifier: "%.1f")s")
                                Slider(value: $trimStart, in: 0...max(1, trimEnd - 0.5), step: 0.1)
                                    .tint(accent)
                            }
                            HStack {
                                Text("End \(trimEnd, specifier: "%.1f")s")
                                Slider(value: $trimEnd, in: max(0.5, trimStart + 0.5)...30, step: 0.1)
                                    .tint(accent)
                            }
                            Button(trimBusy ? "Trimming…" : "Trim + Export mp4") {
                                trimBusy = true
                                trimMessage = ""
                                VideoTrimmer.trim(inputURL: url, startSeconds: trimStart, endSeconds: trimEnd) { out in
                                    DispatchQueue.main.async {
                                        trimBusy = false
                                        trimResult = out
                                        trimMessage = out == nil ? "Trim failed." : "Trimmed: \(out!.lastPathComponent)"
                                        if let out { UISaveVideoAtPathToSavedPhotosAlbum(out.path, nil, nil, nil) }
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                            .disabled(trimBusy)
                            if !trimMessage.isEmpty {
                                Text(trimMessage).font(.caption).foregroundColor(.secondary)
                            }
                            if let r = trimResult {
                                VideoPlayer(player: AVPlayer(url: r)).frame(height: 200).cornerRadius(12)
                            }
                        }
                        .font(.footnote).padding(.horizontal)
                    } else {
                        Text("No video yet. Record from Camera tab.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    Text("Filters + .cube LUT import via LUTEngine (CIColorCube). Trim via VideoTrimmer.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding()
                }
                .padding(.vertical)
            }
            .navigationTitle("Gallery")
            .fileImporter(isPresented: $showLUTImporter, allowedContentTypes: [.init(filenameExtension: "cube") ?? .data]) {
                do {
                    let url = try $0.get()
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let loaded = LUTEngine.load(url: url) {
                            lut = loaded
                            lutName = url.lastPathComponent
                            if let img = camera.lastPhoto {
                                let t0 = Date()
                                filteredImage = LUTEngine.apply(to: img, lut: loaded)
                                camera.log("LUT \(lutName) size=\(loaded.size) in \(Int(Date().timeIntervalSince(t0) * 1000))ms")
                            }
                        }
                    }
                } catch {
                    camera.errorMessage = error.localizedDescription
                }
            }
            .onChange(of: camera.lastPhoto != nil) { _, hasPhoto in
                if hasPhoto, let img = camera.lastPhoto, let lut {
                    filteredImage = LUTEngine.apply(to: img, lut: lut)
                } else if !hasPhoto {
                    filteredImage = nil
                }
            }
        }
    }

    private func styleCard(title: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                    .foregroundColor(selected ? accent : .gray)
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(selected ? accent : .secondary)
            }
            .frame(width: 72, height: 96)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
