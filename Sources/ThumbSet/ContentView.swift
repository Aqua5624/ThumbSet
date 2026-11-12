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

/// Liquid Glass のカードにする
private struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

private extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showVideoFileImporter = false
    @State private var showImageFileImporter = false
    @State private var videoPhotoItem: PhotosPickerItem?
    @State private var imagePhotoItem: PhotosPickerItem?

    private var canExport: Bool {
        model.info != nil && model.currentThumbImage != nil && !model.isBusy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 16) {
                        stepsIndicator
                        step1Video
                        if model.info != nil {
                            step2Thumbnail
                            step3Output
                        }
                        if let outputURL = model.outputURL {
                            resultSection(outputURL)
                        }
                        if !model.history.isEmpty {
                            historySection
                        }
                        if let busy = model.busyText {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(busy).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            .background {
                LinearGradient(colors: [Color.blue.opacity(0.16), Color.purple.opacity(0.10), Color.clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
            .navigationTitle("サムネ変更")
            .safeAreaInset(edge: .bottom) {
                if model.info != nil {
                    exportBar
                }
            }
            .sensoryFeedback(.success, trigger: model.notice)
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

    // MARK: 進み具合 + 下部の書き出しバー

    private var stepsIndicator: some View {
        HStack(spacing: 8) {
            stepChip(1, "動画", done: model.info != nil)
            stepChip(2, "サムネ", done: model.currentThumbImage != nil)
            stepChip(3, "書き出し", done: model.outputURL != nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepChip(_ num: Int, _ label: String, done: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(num).circle")
            Text(label)
        }
        .font(.footnote.bold())
        .foregroundStyle(done ? Color.green : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private var exportBar: some View {
        VStack(spacing: 4) {
            Button {
                Task { await model.exportVideo() }
            } label: {
                Label(model.isBusy ? "処理中…" : "サムネイルを変更した動画を作る", systemImage: "wand.and.stars")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .disabled(!canExport)
            Text(canExport ? "出力方法：\(model.outputMode.rawValue)" : "動画とサムネイルがそろうと押せるよ")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: 1. 動画を選ぶ

    private var step1Video: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("1. 動画を選ぶ", systemImage: "film")
                .font(.headline)
            HStack(spacing: 10) {
                Button {
                    showVideoFileImporter = true
                } label: {
                    Label("ファイル", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                PhotosPicker(selection: $videoPhotoItem, matching: .videos) {
                    Label("写真から", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
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
                    .frame(height: previewHeight(for: info.displaySize))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
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
                            .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .glassCard()
    }

    private func previewHeight(for size: CGSize) -> CGFloat {
        guard size.width > 0 else { return 220 }
        return size.height > size.width ? 300 : 200
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
                imagePickerControls
            } else {
                frameControls
            }
        }
        .glassCard()
    }

    private var imagePickerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    showImageFileImporter = true
                } label: {
                    Label("ファイル", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                PhotosPicker(selection: $imagePhotoItem, matching: .images) {
                    Label("写真から", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
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
            if let image = model.pickedImage, let info = model.info {
                // 仕上がりプレビュー：動画の縦横比で、切り取り設定どおりに表示
                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .modifier(FillOrFit(fill: model.fillToVideoSize))
                }
                .aspectRatio(info.displaySize, contentMode: .fit)
                .frame(maxHeight: 260)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                Text("仕上がりイメージ（動画のサイズに合わせた見え方）")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("サムネイルにしたい画像を選んでね")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var frameControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let preview = model.framePreview, let info = model.info {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: previewHeight(for: info.displaySize) + 40)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if let info = model.info {
                // フィルムストリップ：見て選べる
                if !model.filmstrip.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.filmstrip) { frame in
                                let selected = abs(frame.time - model.frameActualTime) < 0.05
                                Button {
                                    model.selectFilmFrame(frame)
                                } label: {
                                    Image(uiImage: frame.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 76, height: 56)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 3)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text("フレーム一覧からタップでも選べるよ")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { model.frameTime }, set: { model.frameTime = $0; model.scheduleFramePreview() }),
                       in: 0...max(0.01, info.duration))
                HStack(spacing: 8) {
                    stepButton("−1秒", system: "gobackward") { stepSeconds(-1) }
                    stepButton("−1f", system: "chevron.left") { model.stepFrame(-1) }
                    VStack(spacing: 0) {
                        Text(String(format: "%.3f 秒", model.frameActualTime))
                            .font(.footnote.monospaced().bold())
                        Text("フレーム \(Int(model.frameActualTime * Double(info.frameRate))) / \(String(format: "%.0f", Double(info.frameRate)))fps")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    stepButton("+1f", system: "chevron.right") { model.stepFrame(1) }
                    stepButton("+1秒", system: "goforward") { stepSeconds(1) }
                }
                HStack(spacing: 8) {
                    quickChip("最初のフレーム") { model.frameTime = 0; Task { await model.refreshFramePreview(exact: true) } }
                    quickChip("中央") { model.frameTime = info.duration / 2; Task { await model.refreshFramePreview(exact: true) } }
                    quickChip("末尾") { model.frameTime = max(0, info.duration - 0.05); Task { await model.refreshFramePreview(exact: true) } }
                }
                Text("よくある失敗は真っ黒な先頭フレーム。明るいフレームを選ぶのがおすすめだよ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stepSeconds(_ delta: Double) {
        guard let info = model.info else { return }
        model.frameTime = min(max(0, model.frameTime + delta), max(0, info.duration - 0.001))
        Task { await model.refreshFramePreview(exact: true) }
    }

    private func stepButton(_ label: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: system)
                .font(.footnote.bold())
                .padding(.horizontal, 6)
                .frame(minHeight: 40)
        }
        .buttonStyle(.glass)
    }

    private func quickChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.bold())
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.glass)
    }

    // MARK: 3. 出力方法

    private var step3Output: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("3. 出力方法", systemImage: "square.and.arrow.up")
                .font(.headline)
            ForEach(OutputMode.allCases, id: \.self) { mode in
                Button {
                    model.outputMode = mode
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: model.outputMode == mode ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model.outputMode == mode ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.rawValue).font(.subheadline.bold()).foregroundStyle(.primary)
                            Text(description(for: mode))
                                .font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
            if model.outputMode != .cover {
                HStack {
                    Text("差し込む長さ").font(.footnote)
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
            }
            Toggle(isOn: $model.fillToVideoSize) {
                Text("画像を動画サイズに切り取って合わせる")
                    .font(.footnote)
            }
            Text("書き出しは画面下のボタンからいつでも押せるよ")
                .font(.caption).foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private func description(for mode: OutputMode) -> String {
        switch mode {
        case .cover:
            return "映像・音声は元のまま無劣化で一瞬。ファイルアプリや対応プレイヤーでサムネイルとして出る方式（今まで私がやってた方式）"
        case .intro:
            return "動画の先頭フレーム自体がその画像になるから、Discord みたいに先頭フレームからサムネイルを作るサービスでも確実。代わりに再エンコードが入る"
        case .both:
            return "先頭差し込み＋カバー埋め込みの合わせ技。一番確実だけど再エンコードが入る"
        }
    }

    // MARK: 結果

    private func resultSection(_ outputURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("できた動画", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            VideoPreview(url: outputURL)
                .frame(height: model.outputInfo.map { previewHeight(for: $0.displaySize) } ?? 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
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
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("カバー画像が付いているのを確認できたよ")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 10) {
                ShareLink(item: outputURL) {
                    Label("共有・保存", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                Button {
                    Task { await model.saveOutputToPhotos() }
                } label: {
                    Label("写真に保存", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            if let thumbURL = model.thumbImageURL {
                ShareLink(item: thumbURL) {
                    Label("サムネ画像だけ共有（ドライブのサムネ設定用）", systemImage: "photo")
                        .font(.footnote)
                }
            }
        }
        .glassCard()
    }

    // MARK: 履歴

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("履歴（アプリ内に保存）", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            ForEach(model.history) { item in
                HStack(spacing: 10) {
                    if let t = model.historyThumbURL(item), let img = UIImage(contentsOfFile: t.path) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 56, height: 42)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "film")
                            .frame(width: 56, height: 42)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.sourceName)
                            .font(.footnote.bold())
                            .lineLimit(1)
                        Text("\(item.modeLabel) ・ \(item.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    ShareLink(item: model.historyURL(item)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.glass)
                    Button(role: .destructive) {
                        model.deleteHistory(item)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.glass)
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
            Text("履歴は最大30件。消すとアプリ内のファイルも消えるよ")
                .font(.caption).foregroundStyle(.secondary)
        }
        .glassCard()
    }
}

/// 画像プレビューを「切り取り（fill）」か「全体表示（fit）」か切り替える
private struct FillOrFit: ViewModifier {
    let fill: Bool
    func body(content: Content) -> some View {
        if fill {
            content.scaledToFill()
        } else {
            content.scaledToFit()
        }
    }
}
