import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct VideoPreview: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                if player == nil { player = AVPlayer(url: url) }
            }
            .onDisappear { player?.pause() }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showVideoFileImporter = false
    @State private var showImageFileImporter = false
    @State private var videoPhotoItem: PhotosPickerItem?
    @State private var imagePhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    step1Video
                    if model.info != nil {
                        step2Thumbnail
                        step3Output
                    }
                    if let outputURL = model.outputURL {
                        resultSection(outputURL)
                    }
                    if let busy = model.busyText {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(busy).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("サムネ変更")
            .alert("エラー", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .alert("完了", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
                Button("OK") { model.notice = nil }
            } message: {
                Text(model.notice ?? "")
            }
        }
    }

    // MARK: 1. 動画を選ぶ

    private var step1Video: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("1. 動画を選ぶ", systemImage: "film")
                .font(.headline)
            HStack {
                Button {
                    showVideoFileImporter = true
                } label: {
                    Label("ファイル", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                PhotosPicker(selection: $videoPhotoItem, matching: .videos) {
                    Label("写真から", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .onChange(of: videoPhotoItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let movie = try? await item.loadTransferable(type: MovieFile.self) {
                            await model.importVideo(from: movie.url, securityScoped: false)
                        }
                    }
                }
            }
            .fileImporter(isPresented: $showVideoFileImporter, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .video]) { result in
                if case .success(let url) = result {
                    Task { await model.importVideo(from: url, securityScoped: true) }
                }
            }
            if let info = model.info {
                VideoPreview(url: info.url)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 12) {
                    Text(info.sizeText)
                    Text(info.durationText)
                    Text(info.fileSizeText)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                if let cover = info.existingCover {
                    HStack(spacing: 10) {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("いま付いているカバー画像")
                                .font(.footnote).bold()
                            Button("カバーを外した版を作る", role: .destructive) {
                                Task { await model.exportWithoutCover() }
                            }
                            .font(.footnote)
                        }
                    }
                }
            } else {
                Text("MP4 などの動画ファイルを選んでね。Discord の釣り動画みたいに、サムネイルだけ差し替えられるよ。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: 2. サムネイルを決める

    private var step2Thumbnail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2. サムネイルを決める", systemImage: "photo")
                .font(.headline)
            Picker("サムネイルの決め方", selection: $model.thumbSource) {
                ForEach(ThumbSource.allCases, id: \.self) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)

            if model.thumbSource == .image {
                HStack {
                    Button {
                        showImageFileImporter = true
                    } label: {
                        Label("ファイル", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    PhotosPicker(selection: $imagePhotoItem, matching: .images) {
                        Label("写真から", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    .onChange(of: imagePhotoItem) { _, item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                                model.pickedImage = image
                                model.thumbSource = .image
                            }
                        }
                    }
                }
                .fileImporter(isPresented: $showImageFileImporter, allowedContentTypes: [.image]) { result in
                    if case .success(let url) = result {
                        Task {
                            let scoped = url.startAccessingSecurityScopedResource()
                            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                                model.pickedImage = image
                            }
                        }
                    }
                }
                if let image = model.pickedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Text("サムネイルにしたい画像を選んでね")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                frameControls
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var frameControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preview = model.framePreview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if let info = model.info {
                Slider(value: Binding(get: { model.frameTime }, set: { model.frameTime = $0; model.scheduleFramePreview() }),
                       in: 0...max(0.01, info.duration))
                HStack {
                    Button { model.stepFrame(-1) } label: { Image(systemName: "chevron.left") }
                    Button { model.stepFrame(1) } label: { Image(systemName: "chevron.right") }
                    Text(String(format: "%.3f 秒", model.frameActualTime))
                        .font(.footnote.monospaced())
                    Text("(フレーム \(Int(model.frameActualTime * Double(info.frameRate))) / \(String(format: "%.0f", Double(info.frameRate)))fps)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                HStack {
                    Button("先頭") { model.frameTime = 0; Task { await model.refreshFramePreview(exact: true) } }
                    Button("中央") { model.frameTime = info.duration / 2; Task { await model.refreshFramePreview(exact: true) } }
                    Button("末尾") { model.frameTime = max(0, info.duration - 0.05); Task { await model.refreshFramePreview(exact: true) } }
                }
                .font(.footnote)
                .buttonStyle(.bordered)
                Text("スライダーで大まかに探して、◀ ▶ で1フレームずつ詰めてね。黒いフレームは避けるのがおすすめ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 3. 出力方法

    private var step3Output: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("3. 出力方法", systemImage: "square.and.arrow.up")
                .font(.headline)
            Picker("出力方法", selection: $model.outputMode) {
                ForEach(OutputMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(outputModeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.outputMode != .cover {
                HStack {
                    Text("差し込む長さ")
                    Spacer()
                    Picker("差し込む長さ", selection: $model.introDuration) {
                        Text("0.1秒").tag(0.1)
                        Text("0.2秒").tag(0.2)
                        Text("0.5秒").tag(0.5)
                        Text("1.0秒").tag(1.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                .font(.footnote)
            }
            Toggle(isOn: $model.fillToVideoSize) {
                Text("画像を動画サイズに切り取って合わせる")
                    .font(.footnote)
            }
            Button {
                Task { await model.exportVideo() }
            } label: {
                Label("サムネイルを変更した動画を作る", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy || model.currentThumbImage == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var outputModeDescription: String {
        switch model.outputMode {
        case .cover:
            return "カバー埋め込み：映像・音声は元のまま無劣化で一瞬で終わるよ。ファイルアプリや対応プレイヤーでサムネイルとして出る方式（今まで私がやってた方式）"
        case .intro:
            return "先頭に差し込む：動画の先頭フレーム自体がその画像になるから、先頭フレームからサムネイルを作るサービス（Discord など）でも確実。代わりに再エンコードが入るよ"
        case .both:
            return "両方：先頭差し込み＋カバー埋め込みの合わせ技。一番確実だけど再エンコードが入るよ"
        }
    }

    // MARK: 結果

    private func resultSection(_ outputURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("できた動画", systemImage: "checkmark.circle.fill")
                .font(.headline)
            VideoPreview(url: outputURL)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            if let out = model.outputInfo {
                HStack(spacing: 12) {
                    Text(out.sizeText)
                    Text(out.durationText)
                    Text(out.fileSizeText)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                if let cover = out.existingCover {
                    HStack(spacing: 8) {
                        Image(uiImage: cover)
                            .resizable().scaledToFit().frame(height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text("カバー画像が付いているのを確認できたよ")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                ShareLink(item: outputURL) {
                    Label("共有・保存", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await model.saveOutputToPhotos() }
                } label: {
                    Label("写真に保存", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.bordered)
            }
            if let thumbURL = model.thumbImageURL {
                ShareLink(item: thumbURL) {
                    Label("サムネ画像だけ共有（ドライブのサムネ設定用）", systemImage: "photo")
                        .font(.footnote)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
