import Foundation

// Linux 上で CoverInjector を単体検証するための CLI
// usage: covertool inject <in.mp4> <cover.jpg> <out.mp4>
//        covertool remove <in.mp4> <out.mp4>
//        covertool read <in.mp4> <out.jpg>   (カバーが無ければ exit 3)

let args = CommandLine.arguments
guard args.count >= 2 else { exit(2) }
do {
    switch args[1] {
    case "inject":
        let image = try Data(contentsOf: URL(fileURLWithPath: args[3]))
        let isPNG = image.starts(with: [0x89, 0x50, 0x4E, 0x47])
        try MP4Cover.inject(imageData: image, isPNG: isPNG,
                            into: URL(fileURLWithPath: args[2]),
                            output: URL(fileURLWithPath: args[4]))
    case "remove":
        try MP4Cover.removeCover(from: URL(fileURLWithPath: args[2]),
                                 to: URL(fileURLWithPath: args[3]))
    case "read":
        let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        guard let cover = MP4Cover.coverImageData(in: data) else { exit(3) }
        try cover.write(to: URL(fileURLWithPath: args[3]))
    default:
        exit(2)
    }
} catch {
    FileHandle.standardError.write("ERROR: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
