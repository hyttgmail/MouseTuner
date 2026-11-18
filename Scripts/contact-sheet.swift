// 把 render-icon.sh 的输出拼成 contact-sheet.png：两行（26 / 27 代），每行 6 种外观，浅色与深色背景交替
import AppKit

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let renditions = ["Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"]
let cell = 280.0, size = 256.0
let sheet = NSImage(size: NSSize(width: cell * 6, height: cell * 2))
sheet.lockFocus()
for (row, gen) in ["27", "26"].enumerated() {
    for (col, name) in renditions.enumerated() {
        let rect = NSRect(x: Double(col) * cell, y: Double(row) * cell, width: cell, height: cell)
        (name.hasSuffix("Dark") ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        rect.fill()
        NSImage(contentsOf: dir.appendingPathComponent("\(gen)-\(name).png"))?
            .draw(in: rect.insetBy(dx: (cell - size) / 2, dy: (cell - size) / 2))
    }
}
sheet.unlockFocus()
let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("contact-sheet.png"))
print(dir.appendingPathComponent("contact-sheet.png").path)
