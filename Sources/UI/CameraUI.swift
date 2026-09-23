//
//  CameraUI.swift
//  UI-only camera interface inspired by the supplied reference.
//
//  No AVFoundation, image capture, EXIF, filesystem, or camera logic is used here.
//  Replace CameraPreviewPlaceholder with your real camera preview and wire the
//  callbacks/state into your application's camera layer.
//

import SwiftUI

// MARK: - UI State

public enum CameraUIMode: String, CaseIterable {
    case night
    case video
    case photo
    case portrait
    case pro
    case xpan

    var title: String {
        rawValue.uppercased()
    }
}

public enum CameraUIPreset: String, CaseIterable {
    case natural
    case vivid
    case mono
    case imported

    var title: String {
        rawValue.uppercased()
    }
}

@MainActor
public final class CameraUIState: ObservableObject {
    @Published public var mode: CameraUIMode = .photo

    @Published public var zoom: Double = 1.0
    @Published public var iso: Int = 100
    @Published public var shutter: Double = 1.0 / 125.0
    @Published public var exposure: Double = 0.3
    @Published public var whiteBalance: Int = 5200
    @Published public var focusMode: String = "AUTO"

    @Published public var showSettings = false
    @Published public var showQRScanner = false
    @Published public var showEditor = false
    @Published public var showFocusBox = true

    @Published public var saturation: Double = 0.2
    @Published public var contrast: Double = 1.1
    @Published public var preset: CameraUIPreset = .natural

    public init() {}

    public func resetExposure() {
        exposure = 0
    }
}

// MARK: - Main Camera UI

public struct CameraUI<Preview: View>: View {
    @ObservedObject private var state: CameraUIState
    private let preview: Preview

    private let onCapture: () -> Void
    private let onSettings: () -> Void
    private let onQRScanner: () -> Void
    private let onGallery: () -> Void
    private let onFlipCamera: () -> Void
    private let onModeChanged: (CameraUIMode) -> Void
    private let onZoomChanged: (Double) -> Void
    private let onFocus: (CGPoint) -> Void

    @State private var shutterPressed = false
    @State private var captureFlash = false
    @State private var focusAnimating = false

    public init(
        state: CameraUIState,
        @ViewBuilder preview: () -> Preview,
        onCapture: @escaping () -> Void = {},
        onSettings: @escaping () -> Void = {},
        onQRScanner: @escaping () -> Void = {},
        onGallery: @escaping () -> Void = {},
        onFlipCamera: @escaping () -> Void = {},
        onModeChanged: @escaping (CameraUIMode) -> Void = { _ in },
        onZoomChanged: @escaping (Double) -> Void = { _ in },
        onFocus: @escaping (CGPoint) -> Void = { _ in }
    ) {
        self.state = state
        self.preview = preview()
        self.onCapture = onCapture
        self.onSettings = onSettings
        self.onQRScanner = onQRScanner
        self.onGallery = onGallery
        self.onFlipCamera = onFlipCamera
        self.onModeChanged = onModeChanged
        self.onZoomChanged = onZoomChanged
        self.onFocus = onFocus
    }

    public var body: some View {
        ZStack {
            preview
                .ignoresSafeArea()

            CameraPreviewOverlay()

            VStack(spacing: 0) {
                CameraTopBar(
                    onSettings: onSettings,
                    onFlash: {}
                )

                Spacer(minLength: 10)

                focusArea

                Spacer(minLength: 10)

                if state.mode == .pro {
                    ProCameraControls(
                        state: state
                    )
                } else {
                    StandardCameraControls(
                        state: state,
                        onQRScanner: onQRScanner,
                        onZoomChanged: { zoom in
                            onZoomChanged(zoom)
                        }
                    )
                }

                CameraModeSelector(
                    selected: state.mode,
                    onSelect: { mode in
                        withAnimation(.cameraSpring) {
                            state.mode = mode
                        }
                        onModeChanged(mode)
                    }
                )

                CameraBottomBar(
                    onGallery: onGallery,
                    onCapture: capture,
                    onFlipCamera: onFlipCamera
                )
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    private var focusArea: some View {
        GeometryReader { proxy in
            ZStack {
                if state.showFocusBox {
                    FocusBox(
                        animating: focusAnimating
                    )
                }

                VStack {
                    Spacer()

                    Button {
                        onQRScanner()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "qrcode")
                            Text("Scan QR Code")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.72))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { location in
                focusAnimating = true
                onFocus(location)

                withAnimation(.easeOut(duration: 0.18)) {
                    focusAnimating = false
                }
            }
        }
        .frame(height: 170)
    }

    private func capture() {
        withAnimation(.spring(response: 0.16, dampingFraction: 0.65)) {
            shutterPressed = true
        }

        captureFlash = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) {
                shutterPressed = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            captureFlash = false
        }

        onCapture()
    }
}

// MARK: - Camera Overlay

private struct CameraPreviewOverlay: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.25), location: 0),
                .init(color: .clear, location: 0.25),
                .init(color: .clear, location: 0.62),
                .init(color: .black.opacity(0.82), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Top Bar

private struct CameraTopBar: View {
    let onSettings: () -> Void
    let onFlash: () -> Void

    var body: some View {
        HStack {
            CameraCircleButton(
                systemName: "bolt.fill",
                action: onFlash
            )

            Spacer()

            HStack(spacing: 7) {
                Text("HASSELBLAD")
                    .foregroundStyle(.white.opacity(0.54))

                Text("|")
                    .foregroundStyle(.white.opacity(0.28))

                Text("X-PAN")
                    .foregroundStyle(.white.opacity(0.72))
            }
            .font(.system(size: 11, weight: .medium))
            .tracking(1.35)

            Spacer()

            CameraCircleButton(
                systemName: "gearshape.fill",
                action: onSettings
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

private struct CameraCircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.34))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

// MARK: - Focus

private struct FocusBox: View {
    let animating: Bool

    var body: some View {
        Rectangle()
            .stroke(.orange.opacity(0.9), lineWidth: 1.5)
            .frame(
                width: animating ? 50 : 62,
                height: animating ? 50 : 62
            )
            .animation(
                .easeOut(duration: 0.18),
                value: animating
            )
    }
}

// MARK: - Standard Controls

private struct StandardCameraControls: View {
    @ObservedObject var state: CameraUIState
    let onQRScanner: () -> Void
    let onZoomChanged: (Double) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZoomSelector(
                value: state.zoom,
                onSelect: { zoom in
                    withAnimation(.cameraSpring) {
                        state.zoom = zoom
                    }
                    onZoomChanged(zoom)
                }
            )
            .padding(.bottom, 24)

            ParameterStrip(
                items: [
                    ("ISO", "\(state.iso)", false),
                    ("S", shutterText(state.shutter), false),
                    ("EV", exposureText(state.exposure), true),
                    ("WB", "\(state.whiteBalance)K", false),
                    ("MF", state.focusMode, false)
                ]
            )

            ExposureControls(
                value: state.exposure,
                onChange: { value in
                    state.exposure = value
                },
                onReset: state.resetExposure
            )
            .padding(.top, 19)
        }
    }
}

// MARK: - Pro Controls

private struct ProCameraControls: View {
    @ObservedObject var state: CameraUIState

    var body: some View {
        VStack(spacing: 0) {
            ParameterStrip(
                items: [
                    ("ISO", "\(state.iso)", false),
                    ("SHUTTER", shutterText(state.shutter), true),
                    ("EV", exposureText(state.exposure), false),
                    ("FOCUS", state.focusMode, false),
                    ("WB", "\(state.whiteBalance)K", false)
                ]
            )

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(shutterText(state.shutter))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))

                Text("SEC")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.top, 25)

            ShutterSpeedRuler(
                value: state.shutter,
                onChange: { state.shutter = $0 }
            )
            .padding(.top, 9)
        }
    }
}

// MARK: - Zoom

private struct ZoomSelector: View {
    let value: Double
    let onSelect: (Double) -> Void

    private let zooms: [Double] = [0.6, 1.0, 2.0, 4.0]

    var body: some View {
        HStack(spacing: 15) {
            ForEach(zooms, id: \.self) { zoom in
                let selected = abs(value - zoom) < 0.01

                Button {
                    onSelect(zoom)
                } label: {
                    Text(zoomTitle(zoom))
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.28))
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(
                                    selected ? .white : .white.opacity(0.28),
                                    lineWidth: selected ? 1.0 : 0.8
                                )
                        }
                        .scaleEffect(selected ? 1.04 : 1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .animation(.cameraSpring, value: selected)
            }
        }
    }

    private func zoomTitle(_ zoom: Double) -> String {
        switch zoom {
        case 0.6: return "0.6"
        case 1.0: return "1×"
        default: return String(format: "%.0f", zoom)
        }
    }
}

// MARK: - Parameter Strip

private struct ParameterStrip: View {
    let items: [(String, String, Bool)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                VStack(spacing: 7) {
                    Text(items[index].0)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .tracking(0.7)

                    Text(items[index].1)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            items[index].2 ? .orange : .white
                        )
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Exposure

private struct ExposureControls: View {
    let value: Double
    let onChange: (Double) -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 15) {
                ExposureButton(title: "-1") {
                    onChange(max(-3, value - 1))
                }

                ExposureButton(
                    title: "0",
                    selected: abs(value) < 0.001
                ) {
                    onChange(0)
                }

                ExposureButton(title: "+1") {
                    onChange(min(3, value + 1))
                }

                Button("RESET", action: onReset)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.38))
                    .buttonStyle(.plain)
            }

            ExposureRuler(value: value, onChange: onChange)
        }
    }
}

private struct ExposureButton: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 34, height: 26)
                .background(.white.opacity(selected ? 0.18 : 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

private struct ExposureRuler: View {
    let value: Double
    let onChange: (Double) -> Void

    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let center = proxy.size.width / 2
                let spacing: CGFloat = 14
                let offset = CGFloat(value) * -spacing * 3

                ZStack {
                    Canvas { context, size in
                        for i in -16...16 {
                            let x = center + CGFloat(i) * spacing + offset
                            let height: CGFloat = i % 3 == 0 ? 10 : 5

                            var path = Path()
                            path.move(
                                to: CGPoint(
                                    x: x,
                                    y: size.height - height
                                )
                            )
                            path.addLine(
                                to: CGPoint(
                                    x: x,
                                    y: size.height
                                )
                            )

                            context.stroke(
                                path,
                                with: .color(.white.opacity(0.32)),
                                lineWidth: 1
                            )
                        }
                    }

                    Path { path in
                        path.move(to: CGPoint(x: center, y: 0))
                        path.addLine(to: CGPoint(x: center - 4, y: 6))
                        path.addLine(to: CGPoint(x: center + 4, y: 6))
                        path.closeSubpath()
                    }
                    .fill(.white)
                }
            }
            .frame(height: 14)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if dragStart == nil {
                            dragStart = value
                        }

                        let start = dragStart ?? value
                        let delta = -Double(gesture.translation.width / 42)

                        onChange(
                            min(3, max(-3, start + delta))
                        )
                    }
                    .onEnded { _ in
                        dragStart = nil
                    }
            )

            HStack {
                ForEach(-3...3, id: \.self) { number in
                    Text(number == 0 ? "0" : number > 0 ? "+\(number)" : "\(number)")
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 8))
            .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 42)
    }
}

// MARK: - Pro Shutter Ruler

private struct ShutterSpeedRuler: View {
    let value: Double
    let onChange: (Double) -> Void

    private let speeds: [Double] = [
        1.0 / 1000,
        1.0 / 500,
        1.0 / 250,
        1.0 / 125,
        1.0 / 60
    ]

    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let center = proxy.size.width / 2
                let nearestIndex = nearestSpeedIndex(value)

                Canvas { context, size in
                    for i in 0..<21 {
                        let x = CGFloat(i) * (size.width / 20)

                        let height: CGFloat =
                            i % 5 == 0 ? 10 : 5

                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height - height))
                        path.addLine(to: CGPoint(x: x, y: size.height))

                        context.stroke(
                            path,
                            with: .color(.white.opacity(0.28)),
                            lineWidth: 1
                        )
                    }

                    context.stroke(
                        Path { path in
                            path.move(
                                to: CGPoint(x: center, y: 0)
                            )
                            path.addLine(
                                to: CGPoint(x: center, y: size.height)
                            )
                        },
                        with: .color(.white.opacity(0.45)),
                        lineWidth: 1
                    )
                }
                .overlay(alignment: .top) {
                    Text(shutterText(speeds[nearestIndex]))
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .hidden()
                }
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if dragStart == nil {
                            dragStart = value
                        }

                        let start = dragStart ?? value
                        let progress = Double(gesture.translation.width / 1000)

                        let result = min(
                            1.0 / 60,
                            max(1.0 / 1000, start + progress)
                        )

                        onChange(result)
                    }
                    .onEnded { _ in
                        dragStart = nil
                    }
            )

            HStack {
                Text("1/1000")
                Spacer()
                Text("1/60")
            }
            .font(.system(size: 8))
            .foregroundStyle(.white.opacity(0.32))
        }
        .padding(.horizontal, 42)
    }

    private func nearestSpeedIndex(_ value: Double) -> Int {
        speeds.enumerated().min {
            abs($0.element - value) < abs($1.element - value)
        }?.offset ?? 3
    }
}

// MARK: - Modes

private struct CameraModeSelector: View {
    let selected: CameraUIMode
    let onSelect: (CameraUIMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CameraUIMode.allCases, id: \.self) { mode in
                Button {
                    onSelect(mode)
                } label: {
                    VStack(spacing: 7) {
                        Text(mode.title)
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(
                                selected == mode
                                    ? .white
                                    : .white.opacity(0.38)
                            )

                        Capsule()
                            .fill(
                                selected == mode
                                    ? .orange
                                    : .clear
                            )
                            .frame(width: 4, height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 27)
    }
}

// MARK: - Bottom Bar

private struct CameraBottomBar: View {
    let onGallery: () -> Void
    let onCapture: () -> Void
    let onFlipCamera: () -> Void

    @State private var pressed = false

    var body: some View {
        HStack {
            Button(action: onGallery) {
                Image(systemName: "photo")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 60, height: 64)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                onCapture()
            } label: {
                Circle()
                    .fill(.orange)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Circle()
                            .stroke(.white, lineWidth: 3)
                            .padding(-6)
                    }
                    .scaleEffect(pressed ? 0.9 : 1)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            withAnimation(.cameraPress) {
                                pressed = true
                            }
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.cameraPress) {
                            pressed = false
                        }
                    }
            )

            Spacer()

            Button(action: onFlipCamera) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 60, height: 64)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 11)
        .padding(.bottom, 17)
    }
}

// MARK: - Editor UI

public struct CameraEditorUI<ImageContent: View>: View {
    @ObservedObject private var state: CameraUIState
    private let image: ImageContent

    private let onCancel: () -> Void
    private let onSaveCopy: () -> Void

    public init(
        state: CameraUIState,
        @ViewBuilder image: () -> ImageContent,
        onCancel: @escaping () -> Void = {},
        onSaveCopy: @escaping () -> Void = {}
    ) {
        self.state = state
        self.image = image()
        self.onCancel = onCancel
        self.onSaveCopy = onSaveCopy
    }

    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                editorHeader

                image
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 445)
                    .clipped()

                metadataCard

                Spacer(minLength: 15)

                adjustmentRow(
                    title: "SATURATION",
                    value: String(format: "%+.1f", state.saturation)
                )

                adjustmentRow(
                    title: "CONTRAST",
                    value: String(format: "%.1f", state.contrast)
                )

                PresetSelector(
                    selected: state.preset,
                    onSelect: { preset in
                        withAnimation(.cameraSpring) {
                            state.preset = preset
                        }
                    }
                )

                Spacer(minLength: 10)

                editorBottomBar
            }
        }
        .preferredColorScheme(.dark)
    }

    private var editorHeader: some View {
        HStack {
            EditorCircleButton(systemName: "chevron.left", action: onCancel)

            Spacer()

            VStack(spacing: 4) {
                Text("HASSELBLAD MASTERS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.45)

                Text("JULY 24, 2024 • 18:42")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.38))
            }

            Spacer()

            EditorCircleButton(
                systemName: "square.and.arrow.up",
                action: {}
            )
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 11)
    }

    private var metadataCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HASSELBLAD")
                    .font(.system(size: 10, weight: .bold))

                Text("AMBASSADOR EDITION")
                    .font(.system(size: 7, weight: .medium))
            }

            Spacer(minLength: 4)

            metadataItem("80mm", "F/2.8")
            metadataItem("1/250s", "ISO 100")
            metadataItem("EV -0.3", "WB 5200K")

            Circle()
                .stroke(.black.opacity(0.12), lineWidth: 1)
                .frame(width: 32, height: 32)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(.white)
    }

    private func metadataItem(_ top: String, _ bottom: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(top)
                .font(.system(size: 8, weight: .semibold))

            Text(bottom)
                .font(.system(size: 7))
        }
    }

    private func adjustmentRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.15)
                .foregroundStyle(.white.opacity(0.45))

            Spacer()

            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
    }

    private var editorBottomBar: some View {
        HStack {
            Button("CANCEL", action: onCancel)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.42))
                .buttonStyle(.plain)

            Spacer()

            Button(action: onSaveCopy) {
                Text("SAVE COPY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 25)
                    .padding(.vertical, 12)
                    .background(.orange)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}

private struct EditorCircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.06))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Presets

private struct PresetSelector: View {
    let selected: CameraUIPreset
    let onSelect: (CameraUIPreset) -> Void

    @Namespace private var presetNamespace

    var body: some View {
        HStack(spacing: 10) {
            ForEach(CameraUIPreset.allCases, id: \.self) { preset in
                Button {
                    onSelect(preset)
                } label: {
                    VStack(spacing: 7) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.08))

                            if preset == .imported {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.42))
                            } else {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.white.opacity(0.06))
                                    .frame(width: 28, height: 25)
                            }
                        }
                        .frame(height: 38)

                        Text(preset.title)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(7)
                    .background {
                        if selected == preset {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.orange, lineWidth: 1)
                                .matchedGeometryEffect(
                                    id: "presetSelection",
                                    in: presetNamespace
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .animation(.cameraSpring, value: selected)
    }
}

// MARK: - Placeholder Preview

/// A development-only preview background.
/// Replace this with your application's real camera preview.
public struct CameraPreviewPlaceholder: View {
    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.24, green: 0.38, blue: 0.48),
                        Color(red: 0.73, green: 0.62, blue: 0.42),
                        Color(red: 0.12, green: 0.13, blue: 0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Minimal geometric scene so the UI can be tested without a camera.
                VStack {
                    Spacer()

                    HStack(alignment: .bottom, spacing: 0) {
                        Rectangle()
                            .fill(.black.opacity(0.32))
                            .frame(width: proxy.size.width * 0.42)

                        Triangle()
                            .fill(.black.opacity(0.38))
                            .frame(
                                width: proxy.size.width * 0.55,
                                height: proxy.size.height * 0.28
                            )

                        Rectangle()
                            .fill(.black.opacity(0.42))
                            .frame(width: proxy.size.width * 0.22)
                    }
                    .frame(maxWidth: .infinity)
                }
                .ignoresSafeArea()
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

// MARK: - Formatting

private func shutterText(_ seconds: Double) -> String {
    if seconds >= 1 {
        return String(format: "%.1f", seconds)
    }

    let denominator = Int(round(1.0 / seconds))
    return "1/\(denominator)"
}

private func exposureText(_ value: Double) -> String {
    if abs(value) < 0.05 {
        return "0"
    }

    return String(format: "%+.1f", value)
}

// MARK: - Animations

private extension Animation {
    static let cameraSpring =
        Animation.spring(response: 0.28, dampingFraction: 0.78)

    static let cameraPress =
        Animation.spring(response: 0.16, dampingFraction: 0.68)
}

// MARK: - Demo

#Preview("Camera UI") {
    CameraUI(
        state: CameraUIState(),
        preview: {
            CameraPreviewPlaceholder()
        }
    )
}

#Preview("Pro UI") {
    let state = CameraUIState()
    state.mode = .pro
    state.iso = 400
    state.shutter = 1.0 / 250.0
    state.exposure = -0.7
    state.whiteBalance = 4800
    state.focusMode = "AF-C"

    return CameraUI(
        state: state,
        preview: {
            CameraPreviewPlaceholder()
        }
    )
}

#Preview("Editor UI") {
    let state = CameraUIState()

    return CameraEditorUI(
        state: state,
        image: {
            CameraPreviewPlaceholder()
        }
    )
}
