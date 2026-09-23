import SwiftUI

// MARK: - Custom color theme (capture + video UI)

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r, g, b: Double
        if h.count == 6 {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
        } else {
            r = 1; g = 0.62; b = 0.04 // fallback orange #FF9F0A
        }
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

enum AppTheme {
    static let defaultHex = "#FF9F0A"
    static let presets = ["#FF9F0A", "#0A84FF", "#30D158", "#FF375F", "#BF5AF2", "#FFD60A", "#FFFFFF"]
}

struct ThemeSettingsView: View {
    @AppStorage("accentHex") private var accentHex = AppTheme.defaultHex
    private var accent: Binding<Color> {
        Binding(
            get: { Color(hex: accentHex) },
            set: { accentHex = $0.toHex() }
        )
    }

    var body: some View {
        Form {
            Section("Custom color") {
                ColorPicker("Capture accent", selection: accent)
                HStack {
                    ForEach(AppTheme.presets, id: \.self) { hex in
                        Button(action: { accentHex = hex }) {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle().stroke(accentHex == hex ? Color.primary : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Applies to shutter ring, lens presets, sliders, REC + trim.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Preview") {
                HStack(spacing: 12) {
                    Circle().fill(Color(hex: accentHex)).frame(width: 44, height: 44)
                    RoundedRectangle(cornerRadius: 8).fill(Color(hex: accentHex)).frame(width: 80, height: 32)
                    Text("1x").padding(8).background(Color(hex: accentHex)).foregroundColor(.black).clipShape(Capsule())
                }
            }
        }
        .navigationTitle("Theme")
    }
}
