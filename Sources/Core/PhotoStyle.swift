import UIKit
import CoreImage

/// Custom photographic style: warm/cool + tint + color.
/// Applied to captured stills via Core Image (live preview stays native for 60fps).
struct PhotoStyle: Equatable {
    var temperature: Double = 5200  // Kelvin 3000 (warm) ... 8000 (cool)
    var tint: Double = 0            // -100 ... +100 green/magenta
    var saturation: Double = 1.0    // 0 ... 2
    var contrast: Double = 1.0      // 0.5 ... 1.5
    var brightness: Double = 0.0    // -0.5 ... +0.5

    static let neutral = PhotoStyle()

    var isNeutral: Bool { self == .neutral }

    func apply(to image: UIImage) -> UIImage? {
        guard let ci = CIImage(image: image) else { return nil }
        var out = ci
        // Warm/cool: map Kelvin to CITemperatureAndTint targetNeutral.
        if temperature != 5200 || tint != 0 {
            guard let f = CIFilter(name: "CITemperatureAndTint") else { return nil }
            f.setValue(out, forKey: kCIInputImageKey)
            // Neutral ~ D65; target shifts with temp. 3000K warm (+amber), 8000K cool (+blue).
            let t = CIVector(x: CGFloat((temperature - 5200) / 100), y: CGFloat(tint / 10))
            f.setValue(CIVector(x: 0, y: 0), forKey: "inputNeutral")
            f.setValue(t, forKey: "inputTargetNeutral")
            guard let r = f.outputImage else { return nil }
            out = r
        }
        if saturation != 1.0 || contrast != 1.0 || brightness != 0.0 {
            guard let f = CIFilter(name: "CIColorControls") else { return nil }
            f.setValue(out, forKey: kCIInputImageKey)
            f.setValue(saturation, forKey: kCIInputSaturationKey)
            f.setValue(brightness, forKey: kCIInputBrightnessKey)
            f.setValue(contrast, forKey: kCIInputContrastKey)
            guard let r = f.outputImage else { return nil }
            out = r
        }
        let ctx = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        guard let cg = ctx.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}
