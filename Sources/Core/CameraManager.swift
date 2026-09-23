import AVFoundation
import UIKit

/// Central AVFoundation owner. Runs on sessionQueue, publishes to SwiftUI.
/// iPhone 11 Pro Max: prefers triple-camera virtual device for smooth zoom.
final class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    enum VideoQuality: String, CaseIterable, Identifiable {
        case hd30 = "1080p30"
        case hd60 = "1080p60"
        case k4_30 = "4K30"
        case k4_60 = "4K60"
        case slowMo240 = "1080p240"
        var id: String { rawValue }
    }

    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let movieOutput = AVCaptureMovieFileOutput()
    let metadataOutput = AVCaptureMetadataOutput()

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var currentDevice: AVCaptureDevice?
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var lastQRDate = Date.distantPast

    @Published var isSessionRunning = false
    @Published var currentZoom: CGFloat = 1.0
    @Published var lensLabel = "1x"
    @Published var lastPhoto: UIImage?
    @Published var lastVideoURL: URL?
    @Published var isRecording = false
    @Published var qrCode: String?
    @Published var errorMessage: String?
    @Published var torchOn = false
    @Published var videoQuality: VideoQuality = .hd30
    @Published var audioMuted = false
    @Published var focusLocked = false
    @Published var wbLocked = false
    @Published var iso: Float = 100
    @Published var shutter: Double = 1.0 / 120.0
    @Published var exposureBias: Float = 0
    @Published var wbTemp: Double = 5200
    @Published var wbTint: Double = 0
    @Published var style = PhotoStyle()
    @Published var styleOnCapture = true
    @Published var logLines: [String] = []

    private override init() {
        super.init()
    }

    // MARK: - Setup (plan.md P0/P1 entry)

    func log(_ msg: String) {
        let line = "[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] \(msg)"
        DispatchQueue.main.async {
            self.logLines.append(line)
            if self.logLines.count > 200 { self.logLines.removeFirst(self.logLines.count - 200) }
        }
    }

    var logText: String { logLines.joined(separator: "\n") }

    func checkPermissionsAndConfigure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if camStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    self.checkPermissionsAndConfigure()
                }
                return
            }
            guard camStatus == .authorized else {
                DispatchQueue.main.async { self.errorMessage = "Camera denied. Enable in Settings > Privacy > Camera." }
                self.log("camera permission denied: \(camStatus.rawValue)")
                return
            }
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if micStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    self.configureSession()
                }
            }
            self.configureSession()
        }
    }

    private func configureSession() {
        // Avoid double-configure on permission callbacks.
        if session.inputs.count > 0 && session.isRunning { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        // 1. Triple-camera virtual device first (11 Pro Max smooth switching),
        // fallback to dual-wide, then wide.
        let device: AVCaptureDevice? =
            device(of: .builtInTripleCamera, position: .back)
            ?? device(of: .builtInDualWideCamera, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

        guard let device else {
            DispatchQueue.main.async { self.errorMessage = "No camera device." }
            log("no camera device found")
            return
        }
        currentDevice = device

        do {
            // Video input
            if videoDeviceInput == nil {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                    videoDeviceInput = input
                }
            }
            // Audio input (P6: mic for video, mute toggles connection)
            if audioDeviceInput == nil,
               let mic = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: mic)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                    audioDeviceInput = audioInput
                }
            }
            // Photo: high-res + HEVC where available + depth (P1/P3)
            if photoOutput.connections.isEmpty, session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                photoOutput.isHighResolutionCaptureEnabled = true
                if photoOutput.isDepthDataDeliverySupported {
                    photoOutput.isDepthDataDeliveryEnabled = true
                }
                if #available(iOS 16.0, *), photoOutput.isPortraitEffectsMatteDeliverySupported {
                    photoOutput.isPortraitEffectsMatteDeliveryEnabled = true
                }
            }
            if movieOutput.connections.isEmpty, session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
            if metadataOutput.connections.isEmpty, session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                let wanted: [AVMetadataObject.ObjectType] = [.qr, .ean13, .aztec]
                let available = metadataOutput.availableMetadataObjectTypes
                metadataOutput.metadataObjectTypes = wanted.filter { available.contains($0) }
            }
            try device.lockForConfiguration()
            device.isSubjectAreaChangeMonitoringEnabled = true
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
            log("configured: \(device.localizedName) preset=.photo depth=\(photoOutput.isDepthDataDeliveryEnabled)")
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            log("configure failed: \(error.localizedDescription)")
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
                DispatchQueue.main.async { self.isSessionRunning = true }
                self.log("session started")
            }
        }
    }

    private func device(of type: AVCaptureDevice.DeviceType, position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [type],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
    }

    // MARK: - Lens / Zoom (smooth, plan.md §6 P2)

    /// Smooth ramp. Call from slider / 1x 2x 4x buttons.
    func setZoomSmooth(_ factor: CGFloat, rate: Float = 8.0) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                let maxZ = min(device.activeFormat.videoMaxZoomFactor, 8.0)
                let target = max(1.0, min(factor, maxZ))
                device.ramp(toVideoZoomFactor: target, withRate: rate)
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.currentZoom = target
                    self.lensLabel = target < 1.5 ? "1x" : target < 3.0 ? "2x" : String(format: "%.1fx", target)
                }
            } catch {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func setLensPreset(_ preset: Double) {
        // Triple virtual device: 1.0 = Wide, 2.0 = Tele, 4.0 = digital into Tele.
        setZoomSmooth(CGFloat(preset), rate: 12.0)
    }

    func switchFrontBack() {
        sessionQueue.async { [weak self] in
            guard let self, let currentInput = self.videoDeviceInput else { return }
            let newPosition: AVCaptureDevice.Position =
                currentInput.device.position == .back ? .front : .back
            // Front has no triple device: fall back to wide.
            let newDevice: AVCaptureDevice? = newPosition == .back
                ? (self.device(of: .builtInTripleCamera, position: .back)
                   ?? self.device(of: .builtInDualWideCamera, position: .back)
                   ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back))
                : AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            guard let newDevice else { return }
            do {
                self.session.beginConfiguration()
                self.session.removeInput(currentInput)
                // Changing lens resets zoom ramp state.
                try? self.currentDevice?.lockForConfiguration()
                self.currentDevice?.cancelVideoZoomRamp()
                self.currentDevice?.unlockForConfiguration()
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoDeviceInput = newInput
                    self.currentDevice = newDevice
                    try? newDevice.lockForConfiguration()
                    newDevice.isSubjectAreaChangeMonitoringEnabled = true
                    newDevice.unlockForConfiguration()
                    DispatchQueue.main.async {
                        self.currentZoom = 1.0
                        self.lensLabel = "1x"
                        self.torchOn = false
                        self.focusLocked = false
                    }
                    self.log("switched to \(newPosition == .back ? "back" : "front")")
                } else {
                    self.session.addInput(currentInput)
                }
                self.session.commitConfiguration()
            } catch {
                self.session.commitConfiguration()
                self.log("switch camera failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Photo (P1: shutter, torch, HEVC)

    func setTorch(_ on: Bool) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice,
                  device.hasTorch, device.isTorchAvailable else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.torchOn = on }
            } catch {
                self.log("torch failed: \(error.localizedDescription)")
            }
        }
    }

    func capturePhoto() {
        let settings: AVCapturePhotoSettings
        // HEVC where supported keeps 12MP files small (P1).
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.isHighResolutionPhotoEnabled = true
        if photoOutput.isDepthDataDeliverySupported {
            settings.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliveryEnabled
        }
        if let device = currentDevice, device.hasFlash, device.isFlashAvailable {
            settings.flashMode = .auto
        }
        if let codec = settings.availablePreviewPhotoPixelFormatTypes.first {
            settings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: codec]
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
        log("shutter")
    }

    // MARK: - Focus / Exposure tap (P1 AF/AE)

    /// point: normalized 0...1 in preview (tap-to-focus).
    func focusExpose(at point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                let p = CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = p
                }
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = p
                }
                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async { self?.focusLocked = false }
            } catch { }
        }
    }

    // MARK: - Video (basic + pro picker, P5)

    private func applyPresetForQuality(_ q: VideoQuality) {
        // Must be called inside begin/commit or before startRunning changes.
        switch q {
        case .hd30: session.sessionPreset = .hd1920x1080
        case .hd60: session.sessionPreset = .hd1920x1080
        case .k4_30, .k4_60:
            if session.canSetSessionPreset(.hd4K3840x2160) {
                session.sessionPreset = .hd4K3840x2160
            } else {
                session.sessionPreset = .high
            }
        case .slowMo240:
            session.sessionPreset = .hd1920x1080
            selectHighFPSFormat(fps: 240)
        }
        if q != .slowMo240 { restoreDefaultFPS() }
        // Stabilization: cinematicExtended on 11 Pro Max where supported.
        if let conn = movieOutput.connection(with: .video) {
            if conn.isVideoStabilizationSupported {
                conn.preferredVideoStabilizationMode = .cinematicExtended
            }
        }
    }

    private func selectHighFPSFormat(fps: Int) {
        guard let device = currentDevice else { return }
        // Best-effort: find first format supporting requested fps at 1080p.
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width <= 1920 else { continue }
            for range in format.videoSupportedFrameRateRanges {
                if range.minFrameRate <= 30 && range.maxFrameRate >= Double(fps) {
                    do {
                        try device.lockForConfiguration()
                        device.activeFormat = format
                        let dur = CMTimeMake(value: 1, timescale: Int32(fps))
                        device.activeVideoMinFrameDuration = dur
                        device.activeVideoMaxFrameDuration = dur
                        device.unlockForConfiguration()
                        log("slow-mo format \(dims.width)x\(dims.height) @\(fps)")
                        return
                    } catch { return }
                }
            }
        }
        log("no \(fps)fps format found")
    }

    private func restoreDefaultFPS() {
        guard let device = currentDevice else { return }
        try? device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTime.invalid
        device.activeVideoMaxFrameDuration = CMTime.invalid
        device.unlockForConfiguration()
    }

    func startVideoRecording() {
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }
            self.session.beginConfiguration()
            self.applyPresetForQuality(self.videoQuality)
            // Mute = disable audio connection instead of removing input.
            if let audioConn = self.movieOutput.connection(with: .audio) {
                audioConn.isEnabled = !self.audioMuted
            }
            self.session.commitConfiguration()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("vid_\(Int(Date().timeIntervalSince1970)).mov")
            try? FileManager.default.removeItem(at: url)
            // 4K60 needs longer fragment interval defaults; keep default.
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async { self.isRecording = true }
            self.log("rec start \(self.videoQuality.rawValue) muted=\(self.audioMuted)")
        }
    }

    func stopVideoRecording() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
    }

    // MARK: - Manual Pro controls (P7: ISO 34-2172, shutter 1/80000-1s)

    func setManualExposure(iso: Float, shutterSeconds: Double) {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                let fmt = device.activeFormat
                let clampedISO = max(fmt.minISO, min(iso, fmt.maxISO))
                let minDur = fmt.minExposureDuration.seconds
                let maxDur = fmt.maxExposureDuration.seconds
                // Plan range 1/80000 (0.0000125s) ... 1s, clamped to hardware.
                let clampedShutter = max(minDur, min(shutterSeconds, maxDur))
                let duration = CMTimeMakeWithSeconds(clampedShutter, preferredTimescale: 1_000_000)
                device.setExposureModeCustom(duration: duration, iso: clampedISO, completionHandler: nil)
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self?.iso = clampedISO
                    self?.shutter = clampedShutter
                }
            } catch {
                self?.log("manual exposure failed: \(error.localizedDescription)")
            }
        }
    }

    func lockFocus() {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice, device.isFocusModeSupported(.locked) else { return }
            try? device.lockForConfiguration()
            device.focusMode = .locked
            device.unlockForConfiguration()
            DispatchQueue.main.async { self?.focusLocked = true }
        }
    }

    func lockWhiteBalance() {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice,
                  device.isWhiteBalanceModeSupported(.locked) else { return }
            try? device.lockForConfiguration()
            device.whiteBalanceMode = .locked
            device.unlockForConfiguration()
            DispatchQueue.main.async { self?.wbLocked = true }
        }
    }

    // MARK: - Photographic bias: EV, ISO/shutter bias, warm/cool WB

    /// Exposure bias (EV), usually -3...+3. Applies in auto-exposure modes.
    func setExposureBias(_ ev: Float) {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                let clamped = max(device.minExposureTargetBias, min(ev, device.maxExposureTargetBias))
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
                DispatchQueue.main.async { self?.exposureBias = clamped }
            } catch {
                self?.log("EV bias failed: \(error.localizedDescription)")
            }
        }
    }

    /// Warm (3000K amber) ... neutral 5200K ... cool (8000K blue) + green/magenta tint.
    func setWhiteBalance(kelvin: Double, tint: Double = 0) {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice,
                  device.isWhiteBalanceModeSupported(.locked) else { return }
            do {
                try device.lockForConfiguration()
                let k = max(3000, min(kelvin, 8000))
                let t = max(-100, min(tint, 100))
                let tt = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(k), tint: Float(t))
                var gains = device.deviceWhiteBalanceGains(for: tt)
                gains.redGain = max(1.0, min(gains.redGain, device.maxWhiteBalanceGain))
                gains.greenGain = max(1.0, min(gains.greenGain, device.maxWhiteBalanceGain))
                gains.blueGain = max(1.0, min(gains.blueGain, device.maxWhiteBalanceGain))
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self?.wbTemp = k
                    self?.wbTint = t
                    self?.wbLocked = true
                    self?.style.temperature = k
                    self?.style.tint = t
                }
            } catch {
                self?.log("WB failed: \(error.localizedDescription)")
            }
        }
    }

    func autoWhiteBalance() {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice,
                  device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) else { return }
            try? device.lockForConfiguration()
            device.whiteBalanceMode = .continuousAutoWhiteBalance
            device.unlockForConfiguration()
            DispatchQueue.main.async { self?.wbLocked = false }
        }
    }

    func autoFocusExpose() {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentDevice else { return }
            try? device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            device.unlockForConfiguration()
            DispatchQueue.main.async {
                self?.focusLocked = false
                self?.wbLocked = false
            }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            log("photo error: \(error.localizedDescription)")
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        let style = self.style
        let applyStyle = self.styleOnCapture && !style.isNeutral
        let finalImage: UIImage = {
            if applyStyle, let styled = style.apply(to: image) { return styled }
            return image
        }()
        DispatchQueue.main.async { self.lastPhoto = finalImage }
        UIImageWriteToSavedPhotosAlbum(finalImage, nil, nil, nil)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            if error == nil {
                self.lastVideoURL = outputFileURL
                UISaveVideoAtPathToSavedPhotosAlbum(outputFileURL.path, nil, nil, nil)
                self.log("rec saved \(outputFileURL.lastPathComponent)")
            } else {
                let ns = error! as NSError
                // Cancelled-stop still yields a file; keep it.
                if ns.code != -11807 {
                    self.errorMessage = error!.localizedDescription
                }
                self.log("rec finished err=\(ns.code)")
            }
        }
        // Restore photo preset for stills (plan.md §5)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            self.restoreDefaultFPS()
            self.session.commitConfiguration()
        }
    }
}

// MARK: - QR / Metadata (P8)
extension CameraManager: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let str = obj.stringValue, !str.isEmpty else { return }
        // Throttle: same string max 1/sec.
        if str == qrCode && Date().timeIntervalSince(lastQRDate) < 1.0 { return }
        lastQRDate = Date()
        qrCode = str
    }
}
