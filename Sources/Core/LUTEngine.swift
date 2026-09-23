import UIKit
import CoreImage

/// .cube LUT loader + applier via CIColorCube. Coding agent: wire fileImporter to load(url:).
enum LUTEngine {
    struct CubeLUT {
        let size: Int
        let data: Data // Float32 RGBA, size^3 * 4
    }

    static func load(url: URL) -> CubeLUT? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var size = 0
        var rgb: [Float] = []
        rgb.reserveCapacity(32 * 32 * 32 * 3)

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("TITLE")
                || line.hasPrefix("DOMAIN_") { continue }
            if line.hasPrefix("LUT_3D_SIZE") {
                size = Int(line.components(separatedBy: .whitespaces).last ?? "") ?? 0
                continue
            }
            if line.hasPrefix("LUT_1D") { return nil } // not supported
            let parts = line.components(separatedBy: .whitespaces).compactMap { Float($0) }
            if parts.count == 3 {
                rgb.append(contentsOf: parts)
            }
        }
        guard size >= 2, rgb.count == size * size * size * 3 else { return nil }

        // CIColorCube expects RGBA float32
        var rgba = Data()
        rgba.reserveCapacity(size * size * size * 4 * 4)
        var i = 0
        while i < rgb.count {
            var r = rgb[i], g = rgb[i+1], b = rgb[i+2]
            var a: Float = 1.0
            withUnsafeBytes(of: &r) { rgba.append(contentsOf: $0) }
            withUnsafeBytes(of: &g) { rgba.append(contentsOf: $0) }
            withUnsafeBytes(of: &b) { rgba.append(contentsOf: $0) }
            withUnsafeBytes(of: &a) { rgba.append(contentsOf: $0) }
            i += 3
        }
        return CubeLUT(size: size, data: rgba)
    }

    static func apply(to image: UIImage, lut: CubeLUT) -> UIImage? {
        guard let ci = CIImage(image: image) else { return nil }
        guard let filter = CIFilter(name: "CIColorCube") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(lut.size, forKey: "inputCubeDimension")
        filter.setValue(lut.data, forKey: "inputCubeData")
        guard let out = filter.outputImage else { return nil }
        let ctx = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        guard let cg = ctx.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}
