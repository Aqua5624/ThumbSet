import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ThumbSource: String, CaseIterable {
    case image = "画像を選ぶ"
    case frame = "フレーム指定"
}

enum OutputMode: String, CaseIterable {
    case cover = "カバー埋め込み"
    case intro = "先頭に差し込む"
    case both = "両方"
}

struct MovieFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // 受け取り用の一時ファイルは消されることがあるので、その場で自分の場所へコピーする
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "-" + received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return MovieFile(url: dest)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var info: VideoInfo?
    @Published var thumbSource: ThumbSource = .frame
    @Published var pickedImage: UIImage?
    @Published var frameTime: Double = 0
    @Published var framePreview: UIImage?
    @Published var frameActualTime: Double = 0
    @Published var outputMode: OutputMode = .cover
    @Published var introDuration: Double = 0.2
    @Published var fillToVideoSize = true
    @Published var busyText: String?
    @Published var outputURL: URL?
    @Published var outputInfo: VideoInfo?
    @Published var thumbImageURL: URL?
    @Published var errorMessage: String?
    @Published var notice: String?

    // フレーム一覧 (フィルムストリップ) — タップでそのフレームを選べる
    struct FilmFrame: Identifiable {
        let id = UUID()
        let time: Double
        let image: UIImage
    }
    @Published var filmstrip: [FilmFrame] = []

    // 書き出し履歴 (アプリ内にファイルを残す)
    struct HistoryItem: Identifiable, Codable {
        var id = UUID()
        var date: Date
        var sourceName: String
        var modeLabel: String
        var outputFileName: String
        var thumbFileName: String?
    }
    @Published var history: [HistoryItem] = []

    static var exportsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThumbSetExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "thumbset.history"),
           let items = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            history = items
        }
    }

    private var workDir: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("thumbset-work", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var frameTask: Task<Void, Never>?

    var isBusy: Bool { busyText != nil }

    /// サムネイルとして使う画像 (画像タブ = 選択画像 / フレームタブ = プレビュー中のフレーム)
    var currentThumbImage: UIImage? {
        thumbSource == .image ? pickedImage : framePreview
    }

    // MARK: 動画の読み込み

    func importVideo(from url: URL, securityScoped: Bool) async {
        busyText = "動画を読み込み中…"
        defer { busyText = nil }
        do {
            if securityScoped { _ = url.startAccessingSecurityScopedResource() }
            defer { if securityScoped { url.stopAccessingSecurityScopedResource() } }
            let dest = workDir.appendingPathComponent(url.lastPathComponent.isEmpty ? "video.mp4" : url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            let loaded = try await VideoService.loadInfo(url: dest)
            info = loaded
            outputURL = nil
            outputInfo = nil
            frameTime = 0
            framePreview = nil
            filmstrip = []
            await refreshFramePreview(exact: true)
            buildFilmstrip()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: フレーム指定

    func refreshFramePreview(exact: Bool) async {
        guard let info else { return }
        do {
            let result = try await VideoService.frame(at: frameTime, from: info.url, exact: exact)
            // スライダーを動かし続けている間に古い結果で上書きしない
            if abs(result.actualSeconds - frameTime) < 1.0 || framePreview == nil {
                framePreview = result.image
                frameActualTime = result.actualSeconds
            }
        } catch {
            if framePreview == nil { errorMessage = error.localizedDescription }
        }
    }

    func scheduleFramePreview() {
        frameTask?.cancel()
        frameTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            await self?.refreshFramePreview(exact: false)
        }
    }

    /// 動画全体から等間隔にフレームを取り出してフィルムストリップを作る
    func buildFilmstrip() {
        guard let info else { return }
        let url = info.url
        let duration = info.duration
        Task { [weak self] in
            let count = 14
            var frames: [FilmFrame] = []
            for i in 0..<count {
                let t = duration * Double(i) / Double(count - 1)
                if let r = try? await VideoService.frame(at: min(t, max(0, duration - 0.05)), from: url, exact: false) {
                    frames.append(FilmFrame(time: r.actualSeconds, image: r.image))
                    if i % 4 == 0 { self?.filmstrip = frames }
                }
            }
            self?.filmstrip = frames
        }
    }

    func selectFilmFrame(_ frame: FilmFrame) {
        frameTime = frame.time
        Task { await refreshFramePreview(exact: true) }
    }

    func stepFrame(_ direction: Double) {
        guard let info else { return }
        let step = 1.0 / Double(info.frameRate)
        frameTime = min(max(0, frameTime + direction * step), max(0, info.duration - 0.001))
        Task { await refreshFramePreview(exact: true) }
    }

    // MARK: 書き出し

    func exportVideo() async {
        guard let info else { return }
        busyText = "書き出し中…"
        defer { busyText = nil }
        do {
            // フレーム指定のときは最後にそのフレームを正確に取り直す
            var thumb = currentThumbImage
            if thumbSource == .frame {
                thumb = try await VideoService.frame(at: frameTime, from: info.url, exact: true).image
                framePreview = thumb
            }
            guard let thumb else {
                errorMessage = thumbSource == .image ? "まずサムネイルにする画像を選んでね" : "フレームがまだ読み込めていません"
                return
            }
            // サムネイル画像単体もファイルにしておく (ドライブのサムネイル設定などに使える)
            let thumbData = VideoService.renderThumbnail(thumb, targetSize: info.displaySize, fill: fillToVideoSize)
                ?? thumb.jpegData(compressionQuality: 0.9)
            guard let thumbData, let thumbUIImage = UIImage(data: thumbData) else {
                errorMessage = "サムネイル画像の変換に失敗しました"
                return
            }
            let thumbFile = workDir.appendingPathComponent("thumbnail.jpg")
            try thumbData.write(to: thumbFile)
            thumbImageURL = thumbFile

            let baseName = info.url.deletingPathExtension().lastPathComponent
            let outURL = workDir.appendingPathComponent((baseName.isEmpty ? "video" : baseName) + "_thumb.mp4")
            try? FileManager.default.removeItem(at: outURL)

            switch outputMode {
            case .cover:
                try MP4Cover.inject(imageData: thumbData, isPNG: false, into: info.url, output: outURL)
            case .intro:
                let introURL = workDir.appendingPathComponent("intro.mp4")
                let fps = Int32(info.frameRate.rounded())
                try await IntroComposer.makeIntroVideo(image: thumbUIImage, displaySize: info.displaySize,
                                                       duration: introDuration, frameRate: fps > 0 ? fps : 30, output: introURL)
                try await IntroComposer.compose(originalURL: info.url, introURL: introURL, displaySize: info.displaySize, output: outURL)
            case .both:
                let introURL = workDir.appendingPathComponent("intro.mp4")
                let composedURL = workDir.appendingPathComponent("composed.mp4")
                let fps = Int32(info.frameRate.rounded())
                try await IntroComposer.makeIntroVideo(image: thumbUIImage, displaySize: info.displaySize,
                                                       duration: introDuration, frameRate: fps > 0 ? fps : 30, output: introURL)
                try await IntroComposer.compose(originalURL: info.url, introURL: introURL, displaySize: info.displaySize, output: composedURL)
                try MP4Cover.inject(imageData: thumbData, isPNG: false, into: composedURL, output: outURL)
            }
            outputURL = outURL
            outputInfo = try? await VideoService.loadInfo(url: outURL)
            notice = outputMode == .cover
                ? "カバー画像を付けたよ！映像・音声は元のまま（無劣化）だよ"
                : "先頭にサムネイル画像を差し込んだよ（再エンコード済み）"
            registerHistory(modeLabel: outputMode.rawValue, output: outURL, thumbData: thumbData)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 付いているカバーを外した版を作る
    func exportWithoutCover() async {
        guard let info else { return }
        busyText = "カバーを外しています…"
        defer { busyText = nil }
        do {
            let outURL = workDir.appendingPathComponent("video_nocover.mp4")
            try? FileManager.default.removeItem(at: outURL)
            try MP4Cover.removeCover(from: info.url, to: outURL)
            outputURL = outURL
            outputInfo = try? await VideoService.loadInfo(url: outURL)
            notice = "カバー画像を外した版を作ったよ"
            registerHistory(modeLabel: "カバー除去", output: outURL, thumbData: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: 履歴

    func registerHistory(modeLabel: String, output: URL, thumbData: Data?) {
        guard let info else { return }
        let id = UUID()
        let outName = id.uuidString + ".mp4"
        let dest = Self.exportsDir.appendingPathComponent(outName)
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: output, to: dest)
            var thumbName: String?
            if let thumbData {
                thumbName = id.uuidString + ".jpg"
                try thumbData.write(to: Self.exportsDir.appendingPathComponent(thumbName!))
            }
            let item = HistoryItem(date: Date(),
                                   sourceName: info.url.lastPathComponent,
                                   modeLabel: modeLabel,
                                   outputFileName: outName,
                                   thumbFileName: thumbName)
            history.insert(item, at: 0)
            // 30件を超えたら古いものから消す
            while history.count > 30 {
                let old = history.removeLast()
                removeHistoryFiles(old)
            }
            saveHistory()
        } catch {
            // 履歴に残せなくても書き出し自体は成功扱い
        }
    }

    func historyURL(_ item: HistoryItem) -> URL {
        Self.exportsDir.appendingPathComponent(item.outputFileName)
    }

    func historyThumbURL(_ item: HistoryItem) -> URL? {
        item.thumbFileName.map { Self.exportsDir.appendingPathComponent($0) }
    }

    func deleteHistory(_ item: HistoryItem) {
        removeHistoryFiles(item)
        history.removeAll { $0.id == item.id }
        saveHistory()
    }

    private func removeHistoryFiles(_ item: HistoryItem) {
        try? FileManager.default.removeItem(at: historyURL(item))
        if let t = historyThumbURL(item) { try? FileManager.default.removeItem(at: t) }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "thumbset.history")
        }
    }

    func saveOutputToPhotos() async {
        guard let outputURL else { return }
        do {
            try await VideoService.saveVideoToPhotos(url: outputURL)
            notice = "写真アプリに保存したよ"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
