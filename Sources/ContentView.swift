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
                        HStack {
                            Button("Import .cube LUT") { showLUTImporter = true }
                            if lut != nil {
                                Button("Clear LUT") { lut = nil; filteredImage = nil; lutName = "" }
                            }
                            if lut != nil {
                                Button("Save filtered") {
                                    if let out = filteredImage {
                                        UIImageWriteToSavedPhotosAlbum(out, nil, nil, nil)
                                    }
                                }
                            }
                        }
                        .font(.footnote)
                        .tint(accent)
                        if !lutName.isEmpty {
                            Text("LUT: \(lutName)").font(.caption).foregroundColor(.secondary)
                        }
                        if !camera.style.isNeutral {
                            Text("Style: \(Int(camera.style.temperature))K tint \(Int(camera.style.tint)) sat \(String(format: "%.2f", camera.style.saturation)) con \(String(format: "%.2f", camera.style.contrast))")
                                .font(.caption).foregroundColor(.secondary)
                            HStack {
                                Button("Save styled") {
                                    if let out = camera.style.apply(to: img) {
                                        UIImageWriteToSavedPhotosAlbum(out, nil, nil, nil)
                                    }
                                }
                                Button("Reset style") { camera.style = .neutral }
                            }
                            .font(.footnote)
                            .tint(accent)
                        }
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
}
