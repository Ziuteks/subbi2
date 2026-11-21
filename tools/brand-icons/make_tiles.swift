import AppKit

// Składa kafelki ikon serwisów (tło + logo) i zapisuje je jako imagesety w katalogu zasobów.
// Użycie: make_tiles <katalog z SVG> <Assets.xcassets/Brands> <podgląd.png>
let src = CommandLine.arguments[1], outDir = CommandLine.arguments[2], previewPath = CommandLine.arguments[3]

struct Tile {
    let name: String      // nazwa zasobu: brand-<name>
    let file: String      // plik SVG
    let background: UInt32
    let tint: UInt32?     // nil = oryginalne kolory logo
    let fit: CGFloat      // jaka część kafelka (bok) może zająć logo
}

let tiles: [Tile] = [
    Tile(name: "netflix",      file: "si-netflix.svg",           background: 0x000000, tint: 0xE50914, fit: 0.62),
    Tile(name: "spotify",      file: "si-spotify.svg",           background: 0x000000, tint: 0x1ED760, fit: 0.66),
    Tile(name: "youtube",      file: "si-youtube.svg",           background: 0xFFFFFF, tint: 0xFF0000, fit: 0.68),
    Tile(name: "adobe",        file: "adobe-mark.svg",           background: 0xFA0F00, tint: 0xFFFFFF, fit: 0.58),
    Tile(name: "icloud",       file: "si-icloud.svg",            background: 0xFFFFFF, tint: 0x3693F3, fit: 0.66),
    Tile(name: "appletv",      file: "si-appletv.svg",           background: 0x000000, tint: 0xFFFFFF, fit: 0.66),
    Tile(name: "hbomax",       file: "si-hbomax.svg",            background: 0x000000, tint: 0xFFFFFF, fit: 0.74),
    Tile(name: "primevideo",   file: "wm-primevideo-square.svg", background: 0x1A98FF, tint: nil,      fit: 1.00),
    Tile(name: "disneyplus",   file: "wm-disneyplus.svg",        background: 0x0B1A4A, tint: 0xFFFFFF, fit: 0.78),
    Tile(name: "microsoft365", file: "wm-microsoft365.svg",      background: 0xFFFFFF, tint: nil,      fit: 0.66),
    Tile(name: "dropbox",      file: "si-dropbox.svg",           background: 0xFFFFFF, tint: 0x0061FF, fit: 0.62),
    Tile(name: "notion",       file: "si-notion.svg",            background: 0xFFFFFF, tint: 0x000000, fit: 0.64),
    Tile(name: "claude",       file: "si-claude.svg",            background: 0xF5F4EE, tint: 0xD97757, fit: 0.64),
    Tile(name: "chatgpt",      file: "wm-openai.svg",            background: 0x000000, tint: 0xFFFFFF, fit: 0.64),
    // PNG zamiast SVG: plik Gemini używa filtrów rozmycia, których CoreSVG nie obsługuje (zob. README).
    Tile(name: "gemini",       file: "wm-gemini.png",            background: 0xFFFFFF, tint: nil,      fit: 0.66),
]

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Kafelek o boku `px` pikseli – bez kanału alfa poza logo (tło pełne, zaokrąglenie robi aplikacja).
func render(_ t: Tile, px: Int) -> NSBitmapImageRep {
    let svg = NSImage(contentsOf: URL(fileURLWithPath: "\(src)/\(t.file)"))!
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let side = CGFloat(px)
    color(t.background).setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    let box = side * t.fit, s = svg.size
    let k = min(box / s.width, box / s.height)
    let rect = NSRect(x: (side - s.width * k) / 2, y: (side - s.height * k) / 2, width: s.width * k, height: s.height * k)
    let logo = NSImage(size: rect.size, flipped: false) { r in
        svg.draw(in: r)
        if let tint = t.tint {
            color(tint).set()
            r.fill(using: .sourceAtop) // kolor tylko tam, gdzie jest logo (zachowuje przezroczystość)
        }
        return true
    }
    logo.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
try! #"{"info":{"author":"xcode","version":1},"properties":{"provides-namespace":false}}"#
    .write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)

let base = 64 // pt – największy ServiceIcon w aplikacji ma 48 pt
for t in tiles {
    let set = "\(outDir)/brand-\(t.name).imageset"
    try? fm.removeItem(atPath: set)
    try! fm.createDirectory(atPath: set, withIntermediateDirectories: true)
    var images: [String] = []
    for scale in 1...3 {
        let file = "\(t.name)@\(scale)x.png"
        try! render(t, px: base * scale).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(set)/\(file)"))
        images.append(#"{"filename":"\#(file)","idiom":"universal","scale":"\#(scale)x"}"#)
    }
    try! #"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
        .write(toFile: "\(set)/Contents.json", atomically: true, encoding: .utf8)
}

// Podgląd: kafelki zaokrąglone jak w aplikacji, na tle aplikacji.
let cell = 140, cols = 6, rows = (tiles.count + cols - 1) / cols
let preview = NSImage(size: NSSize(width: cols * cell, height: rows * cell))
preview.lockFocus()
NSColor(srgbRed: 0.12, green: 0.16, blue: 0.27, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: cols * cell, height: rows * cell).fill()
for (i, t) in tiles.enumerated() {
    let x = CGFloat((i % cols) * cell + 22), y = CGFloat((rows - 1 - i / cols) * cell + 30)
    let img = NSImage(size: NSSize(width: 96, height: 96))
    img.addRepresentation(render(t, px: 192))
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 96, height: 96), xRadius: 24, yRadius: 24).addClip()
    img.draw(in: NSRect(x: x, y: y, width: 96, height: 96))
    NSGraphicsContext.restoreGraphicsState()
    (t.name as NSString).draw(at: NSPoint(x: x, y: y - 22), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13)])
}
preview.unlockFocus()
try! NSBitmapImageRep(data: preview.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: previewPath))
print("zapisano \(tiles.count) kafelków")
