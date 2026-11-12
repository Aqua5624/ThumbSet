import AVFoundation
import Photos
import UIKit

struct VideoInfo {
    let url: URL
    let duration: Double          // 秒
    let displaySize: CGSize       // 回転を適用した表示サイズ
    let frameRate: Float          // 公称フレームレート (不明なら 30)
    let fileSize: Int64
    let existingCover: UIImage?   // 既に付いているカバー画像

    var durationText: String {
        let m = Int(duration) / 60
        let s = duration - Double(m * 60)
        return String(format: "%d:%05.2f", m, s)
    }
    var sizeText: String {
        "\(Int(displaySize.width))×\(Int(displaySize.height))"
    }
    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

enum VideoServiceError: Error, LocalizedError {
    case noVideoTrack
    case frameFailed
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "動画トラックが見つかりませんでした"
        case .frameFailed: return "その位置のフレームを取り出せませんでした"
        case .exportFailed(let detail): return "書き出しに失敗しました（\(detail)）"
        }
    }
}

enum VideoService {

    static func loadInfo(url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw VideoServiceError.noVideoTrack }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let displaySize = CGSize(width: abs(rect.width), height: abs(rect.height))
        let fps = (try? await track.load(.nominalFrameRate)) ?? 30
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        var cover: UIImage? = nil
        if let data = try? Data(contentsOf: url), let coverData = MP4Cover.coverImageData(in: data) {
            cover = UIImage(data: coverData)
        }
        return VideoInfo(url: url, duration: duration.isFinite ? duration : 0,
                         displaySize: displaySize, frameRate: fps > 0 ? fps : 30,
                         fileSize: fileSize ?? 0, existingCover: cover)
    }

    /// 指定時刻のフレームを取り出す。exact = true で前後の許容なし (そのフレームそのもの)
    static func frame(at seconds: Double, from url: URL, exact: Bool) async throws -> (image: UIImage, actualSeconds: Double) {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        let tolerance = exact ? CMTime.zero : CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let requested = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: requested)]) { _, cgImage, actualTime, result, error in
                if let cgImage, result == .succeeded {
                    continuation.resume(returning: (UIImage(cgImage: cgImage), actualTime.seconds))
                } else {
                    continuation.resume(throwing: error ?? VideoServiceError.frameFailed)
                }
            }
        }
    }

    /// サムネイル画像を動画サイズに合わせて描き直し、JPEG データにする。
    /// fill = 中央切り取りで全面 / fit = 全体を収めて余白は黒
    static func renderThumbnail(_ image: UIImage, targetSize: CGSize, fill: Bool) -> Data? {
        let size = CGSize(width: max(2, targetSize.width.rounded()), height: max(2, targetSize.height.rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            let scale = fill
                ? max(size.width / imageSize.width, size.height / imageSize.height)
                : min(size.width / imageSize.width, size.height / imageSize.height)
            let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return rendered.jpegData(compressionQuality: 0.9)
    }

    /// 写真アプリへ動画を保存する
    static func saveVideoToPhotos(url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw VideoServiceError.exportFailed("写真への保存が許可されていません")
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    /// 写真アプリへ画像を保存する
    static func saveImageToPhotos(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw VideoServiceError.exportFailed("写真への保存が許可されていません")
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}
