import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: make_icns <iconset-dir> <output.icns>\n", stderr)
    exit(2)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let entries = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func bigEndian(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
}

var body = Data()
for (type, file) in entries {
    let image = try Data(contentsOf: directory.appendingPathComponent(file))
    body.append(Data(type.utf8))
    body.append(bigEndian(UInt32(image.count + 8)))
    body.append(image)
}

var result = Data("icns".utf8)
result.append(bigEndian(UInt32(body.count + 8)))
result.append(body)
try result.write(to: output, options: .atomic)

