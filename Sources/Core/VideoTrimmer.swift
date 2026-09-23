import AVFoundation

/// Audio-aware trim + export. Coding agent: connect to gallery trim UI.
enum VideoTrimmer {
    static func trim(inputURL: URL, startSeconds: Double, endSeconds: Double, completion: @escaping (URL?) -> Void) {
        let asset = AVURLAsset(url: inputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(nil)
            return
        }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outURL)
        session.outputURL = outURL
        session.outputFileType = .mp4
        let timescale: Int32 = 600
        session.timeRange = CMTimeRange(
            start: CMTimeMakeWithSeconds(startSeconds, preferredTimescale: timescale),
            duration: CMTimeMakeWithSeconds(max(0, endSeconds - startSeconds), preferredTimescale: timescale)
        )
        session.exportAsynchronously { completion(session.status == .completed ? outURL : nil) }
    }
}
