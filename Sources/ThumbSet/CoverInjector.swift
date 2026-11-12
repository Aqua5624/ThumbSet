import Foundation

// MARK: - MP4 カバー画像 (covr) の読み書き
//
// 映像・音声ストリームには一切触らず、moov > udta > meta > ilst > covr だけを
// 書き換える。ffmpeg で `-disposition attached_pic` を付けたときに出てくる
// カバー画像とまったく同じ場所・形式 (ffprobe では attached pic として見える)。
// 再エンコードしないので画質劣化ゼロ・処理も一瞬。
// moov が mdat より前にあるファイル (faststart) では、covr の増減分だけ
// stco / co64 のチャンクオフセットをずらす。

enum CoverInjectorError: Error, LocalizedError {
    case notMP4
    case boxNotFound(String)
    case unsupportedLayout(String)

    var errorDescription: String? {
        switch self {
        case .notMP4:
            return "MP4ファイルとして読み込めませんでした"
        case .boxNotFound(let name):
            return "MP4の構造が想定と違いました（\(name) が見つかりません）"
        case .unsupportedLayout(let detail):
            return "このMP4の配置には対応していません（\(detail)）"
        }
    }
}

enum MP4Cover {

    // MARK: 読み取り

    /// ファイルに既に付いているカバー画像のデータ (なければ nil)
    static func coverImageData(in fileData: Data) -> Data? {
        let bytes = [UInt8](fileData)
        guard let top = try? topLevelBoxes(bytes), let moov = top.first(where: { $0.type == "moov" }) else {
            return nil
        }
        guard let covr = findPath(bytes: bytes, root: moov, path: ["udta", "meta", "ilst", "covr"]) else {
            return nil
        }
        // covr の中身は data ボックス1つ。data の中身 = 種別(4) + ロケール(4) + 画像データ
        let contentStart = covr.start + covr.header
        guard let dataBox = firstChild(bytes: bytes, contentStart: contentStart, end: covr.end),
              dataBox.type == "data", dataBox.end - (dataBox.start + dataBox.header) > 8 else {
            return nil
        }
        let payloadStart = dataBox.start + dataBox.header + 8
        guard payloadStart < dataBox.end else { return nil }
        return Data(bytes[payloadStart..<dataBox.end])
    }

    // MARK: 書き込み

    /// カバー画像を付けた (または差し替えた) MP4 を output に書く
    static func inject(imageData: Data, isPNG: Bool, into input: URL, output: URL) throws {
        let fileData = try Data(contentsOf: input)
        var bytes = [UInt8](fileData)
        let top = try topLevelBoxes(bytes)
        guard let moov = top.first(where: { $0.type == "moov" }) else {
            throw CoverInjectorError.notMP4
        }
        guard moov.header == 8 else {
            throw CoverInjectorError.unsupportedLayout("moov が 64bit サイズ形式")
        }
        let covr = makeCovrBox(imageData: [UInt8](imageData), isPNG: isPNG)
        let moovBytes = Array(bytes[moov.start..<moov.end])
        var newMoov = setCover(inMoov: moovBytes, covr: covr)
        let delta = newMoov.count - moovBytes.count
        if delta != 0 {
            let mdatRanges = top.filter { $0.type == "mdat" }.map { $0.start..<$0.end }
            try adjustChunkOffsets(moovBytes: &newMoov, delta: delta,
                                   moovFileOffset: moov.start, originalMoovEnd: moov.end,
                                   mdatRanges: mdatRanges)
        }
        bytes.replaceSubrange(moov.start..<moov.end, with: newMoov)
        try Data(bytes).write(to: output, options: [.atomic])
    }

    /// カバー画像を取り除いた MP4 を output に書く (付いていなければそのままコピー)
    static func removeCover(from input: URL, to output: URL) throws {
        let fileData = try Data(contentsOf: input)
        guard coverImageData(in: fileData) != nil else {
            try FileManager.default.copyItem(at: input, to: output)
            return
        }
        var bytes = [UInt8](fileData)
        let top = try topLevelBoxes(bytes)
        guard let moov = top.first(where: { $0.type == "moov" }) else {
            throw CoverInjectorError.notMP4
        }
        let moovBytes = Array(bytes[moov.start..<moov.end])
        var newMoov = setCover(inMoov: moovBytes, covr: nil)
        let delta = newMoov.count - moovBytes.count
        if delta != 0 {
            let mdatRanges = top.filter { $0.type == "mdat" }.map { $0.start..<$0.end }
            try adjustChunkOffsets(moovBytes: &newMoov, delta: delta,
                                   moovFileOffset: moov.start, originalMoovEnd: moov.end,
                                   mdatRanges: mdatRanges)
        }
        bytes.replaceSubrange(moov.start..<moov.end, with: newMoov)
        try Data(bytes).write(to: output, options: [.atomic])
    }

    // MARK: - ボックス走査

    struct Box {
        let type: String
        let start: Int   // ボックス先頭 (サイズフィールドの位置)
        let header: Int  // ヘッダ長 (通常8、64bitサイズで16)
        let end: Int     // start + size
        var contentStart: Int {
            // meta だけはヘッダの後に version/flags の4バイトが入る
            start + header + (type == "meta" ? 4 : 0)
        }
    }

    static func readU32(_ bytes: [UInt8], at pos: Int) -> UInt32 {
        UInt32(bytes[pos]) << 24 | UInt32(bytes[pos + 1]) << 16 | UInt32(bytes[pos + 2]) << 8 | UInt32(bytes[pos + 3])
    }

    static func readU64(_ bytes: [UInt8], at pos: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 { v = v << 8 | UInt64(bytes[pos + i]) }
        return v
    }

    static func writeU32(_ bytes: inout [UInt8], at pos: Int, value: UInt32) {
        bytes[pos] = UInt8(value >> 24 & 0xFF)
        bytes[pos + 1] = UInt8(value >> 16 & 0xFF)
        bytes[pos + 2] = UInt8(value >> 8 & 0xFF)
        bytes[pos + 3] = UInt8(value & 0xFF)
    }

    static func writeU64(_ bytes: inout [UInt8], at pos: Int, value: UInt64) {
        for i in 0..<8 { bytes[pos + i] = UInt8(value >> UInt64(56 - i * 8) & 0xFF) }
    }

    /// 範囲内のボックスを先頭から列挙する (壊れた構造では止まる)
    static func childBoxes(bytes: [UInt8], contentStart: Int, end: Int) -> [Box] {
        var result: [Box] = []
        var pos = contentStart
        while pos + 8 <= end {
            let rawSize = readU32(bytes, at: pos)
            let type = String(bytes: bytes[(pos + 4)..<(pos + 8)], encoding: .ascii) ?? ""
            var header = 8
            var size: Int
            if rawSize == 1 {
                guard pos + 16 <= end else { break }
                size = Int(readU64(bytes, at: pos + 8))
                header = 16
            } else if rawSize == 0 {
                size = end - pos
            } else {
                size = Int(rawSize)
            }
            guard size >= header, pos + size <= end else { break }
            result.append(Box(type: type, start: pos, header: header, end: pos + size))
            pos += size
        }
        return result
    }

    static func topLevelBoxes(_ bytes: [UInt8]) throws -> [Box] {
        let boxes = childBoxes(bytes: bytes, contentStart: 0, end: bytes.count)
        guard boxes.contains(where: { $0.type == "ftyp" }) || boxes.contains(where: { $0.type == "moov" }) else {
            throw CoverInjectorError.notMP4
        }
        return boxes
    }

    static func firstChild(bytes: [UInt8], contentStart: Int, end: Int) -> Box? {
        childBoxes(bytes: bytes, contentStart: contentStart, end: end).first
    }

    static func findPath(bytes: [UInt8], root: Box, path: [String]) -> Box? {
        var current = root
        for component in path {
            let children = childBoxes(bytes: bytes, contentStart: current.contentStart, end: current.end)
            guard let next = children.first(where: { $0.type == component }) else { return nil }
            current = next
        }
        return current
    }

    // MARK: - ボックス組み立て

    static func makeBox(type: String, content: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 8)
        writeU32(&out, at: 0, value: UInt32(8 + content.count))
        out.replaceSubrange(4..<8, with: [UInt8](type.utf8))
        out.append(contentsOf: content)
        return out
    }

    /// ffmpeg が作る meta > hdlr と同じバイト列 (handler = mdir / appl)
    static let metaHdlr: [UInt8] = [
        0x00, 0x00, 0x00, 0x21, 0x68, 0x64, 0x6C, 0x72,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x6D, 0x64, 0x69, 0x72, 0x61, 0x70, 0x70, 0x6C,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]

    static func makeCovrBox(imageData: [UInt8], isPNG: Bool) -> [UInt8] {
        var dataContent = [UInt8](repeating: 0, count: 8)
        writeU32(&dataContent, at: 0, value: isPNG ? 14 : 13) // 13 = JPEG, 14 = PNG
        dataContent.append(contentsOf: imageData)
        return makeBox(type: "covr", content: makeBox(type: "data", content: dataContent))
    }

    static func makeMetaBox(ilstContent: [UInt8]) -> [UInt8] {
        var content = [UInt8](repeating: 0, count: 4) // version/flags
        content.append(contentsOf: metaHdlr)
        content.append(contentsOf: makeBox(type: "ilst", content: ilstContent))
        return makeBox(type: "meta", content: content)
    }

    /// moov バイト列に対して covr をセット (nil で削除) した新しい moov バイト列を返す
    static func setCover(inMoov moovBytes: [UInt8], covr: [UInt8]?) -> [UInt8] {
        let moov = Box(type: "moov", start: 0, header: 8, end: moovBytes.count)
        // udta を取り出す (なければ空の udta を作る)
        let udtaChildren = childBoxes(bytes: moovBytes, contentStart: moov.contentStart, end: moov.end)
        let udtaBox = udtaChildren.first(where: { $0.type == "udta" })
        let udtaBytes: [UInt8] = udtaBox.map { Array(moovBytes[$0.start..<$0.end]) } ?? makeBox(type: "udta", content: [])
        let newUdta = setCoverInUdta(udtaBytes: udtaBytes, covr: covr)
        return replaceChildAbsolute(parentBytes: moovBytes, parent: moov, targetType: "udta", newBytes: newUdta)
    }

    static func setCoverInUdta(udtaBytes: [UInt8], covr: [UInt8]?) -> [UInt8] {
        let udta = Box(type: "udta", start: 0, header: 8, end: udtaBytes.count)
        let children = childBoxes(bytes: udtaBytes, contentStart: udta.contentStart, end: udta.end)
        let metaBox = children.first(where: { $0.type == "meta" })
        let metaBytes: [UInt8] = metaBox.map { Array(udtaBytes[$0.start..<$0.end]) } ?? makeMetaBox(ilstContent: [])
        let newMeta = setCoverInMeta(metaBytes: metaBytes, covr: covr)
        return replaceChildAbsolute(parentBytes: udtaBytes, parent: udta, targetType: "meta", newBytes: newMeta)
    }

    static func setCoverInMeta(metaBytes: [UInt8], covr: [UInt8]?) -> [UInt8] {
        let meta = Box(type: "meta", start: 0, header: 8, end: metaBytes.count)
        let children = childBoxes(bytes: metaBytes, contentStart: meta.contentStart, end: meta.end)
        let ilstBox = children.first(where: { $0.type == "ilst" })
        let ilstBytes: [UInt8] = ilstBox.map { Array(metaBytes[$0.start..<$0.end]) } ?? makeBox(type: "ilst", content: [])
        // ilst の中身: covr 以外 (©too など) は保持して covr だけ差し替える
        let ilst = Box(type: "ilst", start: 0, header: 8, end: ilstBytes.count)
        let newIlst = replaceChildAbsolute(parentBytes: ilstBytes, parent: ilst, targetType: "covr", newBytes: covr)
        return replaceChildAbsolute(parentBytes: metaBytes, parent: meta, targetType: "ilst", newBytes: newIlst)
    }

    /// 親ボックス単体のバイト列 (先頭が親の開始位置) の中で子を差し替える
    static func replaceChildAbsolute(parentBytes: [UInt8], parent: Box, targetType: String, newBytes: [UInt8]?) -> [UInt8] {
        let children = childBoxes(bytes: parentBytes, contentStart: parent.contentStart, end: parent.end)
        var out: [UInt8] = []
        out.append(contentsOf: parentBytes[0..<parent.contentStart])
        var replaced = false
        for child in children {
            if child.type == targetType {
                if let newBytes { out.append(contentsOf: newBytes) }
                replaced = true
            } else {
                out.append(contentsOf: parentBytes[child.start..<child.end])
            }
        }
        if !replaced, let newBytes {
            out.append(contentsOf: newBytes)
        }
        // サイズを実際の長さに合わせる (32bit ヘッダ前提)
        if parent.header == 8 {
            writeU32(&out, at: 0, value: UInt32(out.count))
        }
        return out
    }

    // MARK: - チャンクオフセット調整

    static let containerTypes: Set<String> = ["moov", "trak", "mdia", "minf", "stbl", "edts", "dinf", "udta"]

    static func adjustChunkOffsets(moovBytes: inout [UInt8], delta: Int, moovFileOffset: Int, originalMoovEnd: Int, mdatRanges: [Range<Int>]) throws {
        // stco / co64 ボックスの位置を moov 内から集める
        var offsetBoxes: [Box] = []
        collectOffsetBoxes(bytes: moovBytes, contentStart: 8, end: moovBytes.count, into: &offsetBoxes)
        if offsetBoxes.isEmpty { return }

        // 判定: moov が全 mdat より前 (faststart) なら全エントリをずらす。
        // moov が全 mdat より後ならずらさない。それ以外 (インターリーブ) は未対応。
        let moovBeforeData = mdatRanges.allSatisfy { $0.lowerBound >= originalMoovEnd }
        let moovAfterData = mdatRanges.allSatisfy { $0.upperBound <= moovFileOffset }
        if moovAfterData { return }
        guard moovBeforeData else {
            throw CoverInjectorError.unsupportedLayout("moov と mdat が混ざった配置")
        }
        for box in offsetBoxes {
            let is64 = box.type == "co64"
            let countPos = box.start + box.header + 4
            guard countPos + 4 <= box.end else { continue }
            let count = Int(readU32(moovBytes, at: countPos))
            var pos = countPos + 4
            for _ in 0..<count {
                if is64 {
                    guard pos + 8 <= box.end else { break }
                    let v = readU64(moovBytes, at: pos)
                    writeU64(&moovBytes, at: pos, value: UInt64(Int64(v) + Int64(delta)))
                    pos += 8
                } else {
                    guard pos + 4 <= box.end else { break }
                    let v = readU32(moovBytes, at: pos)
                    writeU32(&moovBytes, at: pos, value: UInt32(Int64(v) + Int64(delta)))
                    pos += 4
                }
            }
        }
    }

    static func collectOffsetBoxes(bytes: [UInt8], contentStart: Int, end: Int, into result: inout [Box]) {
        for box in childBoxes(bytes: bytes, contentStart: contentStart, end: end) {
            if box.type == "stco" || box.type == "co64" {
                result.append(box)
            } else if containerTypes.contains(box.type) {
                collectOffsetBoxes(bytes: bytes, contentStart: box.contentStart, end: box.end, into: &result)
            }
        }
    }
}
