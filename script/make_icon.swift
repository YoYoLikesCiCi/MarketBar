import Foundation

// An ICNS file contains a length-prefixed PNG for each icon representation.
let representations = [
    ("icp4", "16x16"), ("ic11", "16x16@2x"),
    ("icp5", "32x32"), ("ic12", "32x32@2x"),
    ("ic07", "128x128"), ("ic13", "128x128@2x"),
    ("ic08", "256x256"), ("ic14", "256x256@2x"),
    ("ic09", "512x512"), ("ic10", "512x512@2x"),
]

func length(_ bytes: Int) -> Data {
    withUnsafeBytes(of: UInt32(bytes).bigEndian) { Data($0) }
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
var elements = Data()

for (type, name) in representations {
    let png = try Data(contentsOf: iconset.appendingPathComponent("icon_\(name).png"))
    elements.append(contentsOf: type.utf8)
    elements.append(length(png.count + 8))
    elements.append(png)
}

var icon = Data("icns".utf8)
icon.append(length(elements.count + 8))
icon.append(elements)
try icon.write(to: destination, options: .atomic)
