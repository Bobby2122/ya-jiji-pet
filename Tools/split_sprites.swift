import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 6 else {
    fputs("usage: split_sprites <input.png> <output-dir> <columns> <rows> <prefix>\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let columns = Int(CommandLine.arguments[3]), columns > 0,
      let rows = Int(CommandLine.arguments[4]), rows > 0 else {
    fputs("columns and rows must be positive integers\n", stderr)
    exit(2)
}
let prefix = CommandLine.arguments[5]

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("could not decode input image\n", stderr)
    exit(1)
}

for row in 0..<rows {
    for column in 0..<columns {
        let x0 = column * image.width / columns
        let x1 = (column + 1) * image.width / columns
        let y0 = row * image.height / rows
        let y1 = (row + 1) * image.height / rows
        let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        guard let cell = image.cropping(to: rect) else { continue }
        let name = String(format: "%@-r%02d-c%02d.png", prefix, row, column)
        let destinationURL = outputURL.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { continue }
        CGImageDestinationAddImage(destination, cell, nil)
        guard CGImageDestinationFinalize(destination) else {
            fputs("could not write \(destinationURL.path)\n", stderr)
            exit(1)
        }
    }
}

