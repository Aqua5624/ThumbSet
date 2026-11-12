import AVFoundation
import UIKit

// MARK: - 先頭差し込みモード
//
// サムネイル画像だけの短い動画 (イントロ) を作って、本編の先頭に繋げる。
// Discord のように「動画の先頭フレームからサムネイルを作る」サービスでも
// 確実にサムネイルがその画像になる。繋ぎ直すので再エンコードが入る
// (カバー埋め込みモードと違って無劣化ではない)。

enum IntroComposer {

    /// 画像1枚から duration 秒の無音動画を作る (サイズは displaySize、偶数に丸める)
    static func makeIntroVideo(image: UIImage, displaySize: CGSize, duration: Double, frameRate: Int32, output: URL) async throws {
        let width = Int(displaySize.width.rounded()) & ~1
        let height = Int(displaySize.height.rounded()) & ~1
        guard width >= 2, height >= 2 else { throw VideoServiceError.exportFailed("動画のサイズが不正です") }
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        guard writer.canAdd(input) else { throw VideoServiceError.exportFailed("イントロ動画の作成に失敗しました") }
        writer.add(input)
        guard writer.startWriting() else {
            throw VideoServiceError.exportFailed(writer.error?.localizedDescription ?? "イントロ動画の作成に失敗しました")
        }
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else { throw VideoServiceError.exportFailed("ピクセルバッファが作れませんでした") }
        let frameCount = max(1, Int((duration * Double(frameRate)).rounded()))
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
                if writer.status == .failed {
                    throw VideoServiceError.exportFailed(writer.error?.localizedDescription ?? "イントロ動画の作成に失敗しました")
                }
            }
            var bufferOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &bufferOut)
            guard let buffer = bufferOut else { throw VideoServiceError.exportFailed("ピクセルバッファが作れませんでした") }
            try draw(image: image, into: buffer, width: width, height: height)
            let time = CMTime(value: CMTimeValue(frame), timescale: frameRate)
            if !adaptor.append(buffer, withPresentationTime: time) {
                throw VideoServiceError.exportFailed("イントロ動画の作成に失敗しました")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw VideoServiceError.exportFailed(writer.error?.localizedDescription ?? "イントロ動画の作成に失敗しました")
        }
    }

    /// 画像をピクセルバッファ全面に aspect-fill で描く
    private static func draw(image: UIImage, into buffer: CVPixelBuffer, width: Int, height: Int) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let cgImage = image.cgImage else {
            throw VideoServiceError.exportFailed("画像の描画に失敗しました")
        }
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = max(CGFloat(width) / imageSize.width, CGFloat(height) / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let rect = CGRect(x: (CGFloat(width) - drawSize.width) / 2, y: (CGFloat(height) - drawSize.height) / 2,
                          width: drawSize.width, height: drawSize.height)
        // CGContext は左下原点なので座標系を反転してから描く (rect は中央配置なので反転後も同じ位置)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: rect)
    }

    /// イントロ + 本編 を繋いで書き出す。本編の音声はイントロ分だけ後ろにずれる (イントロ中は無音)
    static func compose(originalURL: URL, introURL: URL, displaySize: CGSize, output: URL) async throws {
        let original = AVURLAsset(url: originalURL)
        let intro = AVURLAsset(url: introURL)
        let originalDuration = try await original.load(.duration)
        let introDuration = try await intro.load(.duration)
        guard let originalVideo = try await original.loadTracks(withMediaType: .video).first,
              let introVideo = try await intro.loadTracks(withMediaType: .video).first else {
            throw VideoServiceError.noVideoTrack
        }
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoServiceError.exportFailed("合成トラックが作れませんでした")
        }
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: introDuration), of: introVideo, at: .zero)
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: originalDuration), of: originalVideo, at: introDuration)

        if let originalAudio = try await original.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: originalDuration), of: originalAudio, at: introDuration)
        }

        // 向きの合成: イントロは表示向きで作ってあるので恒等、本編は preferredTransform を表示矩形に合わせる
        let naturalSize = try await originalVideo.load(.naturalSize)
        let preferred = try await originalVideo.load(.preferredTransform)
        let naturalRect = CGRect(origin: .zero, size: naturalSize)
        let transformedRect = naturalRect.applying(preferred)
        let normalize = CGAffineTransform(translationX: -transformedRect.origin.x, y: -transformedRect.origin.y).concatenating(preferred)

        let renderWidth = Int(displaySize.width.rounded()) & ~1
        let renderHeight = Int(displaySize.height.rounded()) & ~1
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        layerInstruction.setTransform(.identity, at: .zero)
        layerInstruction.setTransform(normalize, at: introDuration)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: CMTimeAdd(introDuration, originalDuration))
        instruction.layerInstructions = [layerInstruction]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = CGSize(width: renderWidth, height: renderHeight)
        let fps = (try? await originalVideo.load(.nominalFrameRate)) ?? 30
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, Int32(fps.rounded()))))

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoServiceError.exportFailed("書き出しセッションが作れませんでした")
        }
        try? FileManager.default.removeItem(at: output)
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = videoComposition
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: session.error ?? VideoServiceError.exportFailed("書き出しが中断されました"))
                default:
                    continuation.resume(throwing: VideoServiceError.exportFailed("書き出しが中断されました"))
                }
            }
        }
    }
}
