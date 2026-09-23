import AVFoundation
import UIKit

/// Smooth zoom helper: always ramp, never jump. Throttle SwiftUI slider via CADisplayLink.
enum ZoomController {
    /// Ramp device zoom at given rate. Clamped to device max (capped 8x for 11 Pro Max UX).
    static func ramp(_ device: AVCaptureDevice?, to factor: CGFloat, rate: Float = 8.0) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            let maxZ = min(device.activeFormat.videoMaxZoomFactor, 8.0)
            let target = max(1.0, min(factor, maxZ))
            // ramp(toVideoZoomFactor:) animates across virtual-device switch points
            // (ultra -> wide -> tele) so no visible jump on triple camera.
            device.ramp(toVideoZoomFactor: target, withRate: rate)
            device.unlockForConfiguration()
        } catch { }
    }

    static func cancel(_ device: AVCaptureDevice?) {
        guard let device else { return }
        try? device.lockForConfiguration()
        device.cancelVideoZoomRamp()
        device.unlockForConfiguration()
    }

    /// Haptic tick when crossing 2x / 4x — call from slider observer.
    static func tickIfCrossed(old: Double, new: Double) {
        let marks: [Double] = [2.0, 4.0]
        for m in marks {
            if (old < m && new >= m) || (old > m && new <= m) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                break
            }
        }
    }
}
