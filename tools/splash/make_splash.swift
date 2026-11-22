import AVFoundation
import AppKit
import CoreText

// Generuje animację startową: logo „Subbi” (jak ikona aplikacji) przylatuje po łuku na środek ekranu.
// Użycie: make_splash <wyjście.mp4>
// Kolory jak w Theme.swift; pierwsza klatka to samo tło co ekran startowy (LaunchBackground).

let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
let W = 1080, H = 2340            // proporcje ekranu iPhone'a (19,5:9), w aplikacji aspectFill
let fps = 60
let duration = 2.2
let frameCount = Int(duration * Double(fps))

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
/// Przestrzeń, w której zapisujemy klatki: prymarne kolory sRGB/BT.709, gamma 1,961.
/// Systemy Apple wyświetlają wideo oznaczone jako BT.709 właśnie z gammą 1,961, więc kolory sRGB
/// zapisane w tej przestrzeni po odtworzeniu wracają do wartości z Theme.swift (zob. pomiar w README).
let videoSpace: CGColorSpace = {
    var white: [CGFloat] = [0.9505, 1.0, 1.0890], black: [CGFloat] = [0, 0, 0]
    var gamma: [CGFloat] = [1.961, 1.961, 1.961]
    var matrix: [CGFloat] = [0.4124, 0.2126, 0.0193,  0.3576, 0.7152, 0.1192,  0.1805, 0.0722, 0.9505]
    return CGColorSpace(calibratedRGBWhitePoint: &white, blackPoint: &black, gamma: &gamma, matrix: &matrix)!
}()
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}
let bg     = rgb(0.12, 0.16, 0.27)
let card   = rgb(0.18, 0.23, 0.36)
let accent = rgb(0.53, 1.00, 0.78)

// MARK: - Kafelek z logo (rysowany raz, potem tylko przekształcany)

let tileSide = CGFloat(W) * 0.36
let tileScale: CGFloat = 2 // zapas rozdzielczości na skalowanie z „przestrzeleniem”

func makeTile() -> CGImage {
    let px = Int(tileSide * tileScale)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let rect = CGRect(x: 0, y: 0, width: px, height: px)
    let path = CGPath(roundedRect: rect, cornerWidth: CGFloat(px) * 0.2237, cornerHeight: CGFloat(px) * 0.2237, transform: nil)
    ctx.addPath(path); ctx.clip()
    let gradient = CGGradient(colorsSpace: sRGB, colors: [card, bg] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(px)), end: .zero, options: [])

    // Napis „Subbi” – ta sama czcionka i proporcje co ikona aplikacji.
    let base = NSFont.systemFont(ofSize: 100, weight: .heavy)
    let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 100)! as CTFont
    func line(_ size: CGFloat) -> CTLine {
        let f = CTFontCreateCopyWithAttributes(font, size, nil, nil)
        return CTLineCreateWithAttributedString(NSAttributedString(string: "Subbi", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: f,
            kCTForegroundColorAttributeName as NSAttributedString.Key: accent,
            kCTKernAttributeName as NSAttributedString.Key: -size * 0.02,
        ]))
    }
    var size: CGFloat = 50, l = line(size), b = CTLineGetImageBounds(l, ctx)
    while b.width < CGFloat(px) * 0.72 { size += 2; l = line(size); b = CTLineGetImageBounds(l, ctx) }
    ctx.textPosition = CGPoint(x: (CGFloat(px) - b.width) / 2 - b.minX, y: (CGFloat(px) - b.height) / 2 - b.minY)
    CTLineDraw(l, ctx)

    // Delikatna jasna obwódka, żeby kafelek odcinał się od tła.
    ctx.resetClip(); ctx.addPath(path)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.10)); ctx.setLineWidth(CGFloat(px) * 0.008); ctx.strokePath()
    return ctx.makeImage()!
}
let tile = makeTile()

// MARK: - Ruch

func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }

let flyStart = 0.15, flyDuration = 0.9

struct Pose { var x, y, scale, angle, alpha: Double }

/// Położenie logo w chwili t (współrzędne od lewego górnego rogu).
func pose(at t: Double) -> Pose {
    let p = easeOutCubic((t - flyStart) / flyDuration)
    // Krzywa Béziera: spod prawego dolnego rogu, łukiem na środek.
    let (x0, y0) = (Double(W) * 0.95, Double(H) * 1.18)
    let (cx, cy) = (Double(W) * 1.10, Double(H) * 0.40)
    let (x1, y1) = (Double(W) * 0.50, Double(H) * 0.50)
    let x = (1 - p) * (1 - p) * x0 + 2 * (1 - p) * p * cx + p * p * x1
    let y = (1 - p) * (1 - p) * y0 + 2 * (1 - p) * p * cy + p * p * y1
    // Skala jak tłumiona sprężyna: 0,35 → lekkie przestrzelenie (~1,1) → 1.
    let s = max(t - flyStart, 0)
    let scale = 1 - 0.65 * exp(-5 * s) * cos(9 * s)
    let angle = -30 * (1 - p) * Double.pi / 180
    let alpha = clamp((t - flyStart) / 0.2)
    return Pose(x: x, y: y, scale: scale, angle: angle, alpha: alpha)
}

func draw(_ ctx: CGContext, _ pose: Pose, alpha: Double, shadow: Bool) {
    guard alpha > 0.001 else { return }
    ctx.saveGState()
    ctx.translateBy(x: pose.x, y: Double(H) - pose.y) // CoreGraphics liczy od dołu
    ctx.rotate(by: -pose.angle)
    ctx.scaleBy(x: pose.scale, y: pose.scale)
    ctx.setAlpha(alpha)
    if shadow { ctx.setShadow(offset: CGSize(width: 0, height: -tileSide * 0.06), blur: tileSide * 0.18, color: rgb(0, 0, 0, 0.45)) }
    ctx.draw(tile, in: CGRect(x: -tileSide / 2, y: -tileSide / 2, width: tileSide, height: tileSide))
    ctx.restoreGState()
}

func renderFrame(_ ctx: CGContext, t: Double) {
    ctx.setFillColor(bg)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let current = pose(at: t)

    // Smuga ruchu: kilka „duchów” z poprzednich chwil, tylko podczas lotu.
    let flying = 1 - clamp((t - flyStart - flyDuration * 0.55) / (flyDuration * 0.3))
    if t > flyStart && flying > 0 {
        for k in stride(from: 6, through: 1, by: -1) {
            draw(ctx, pose(at: t - Double(k) * 0.022), alpha: current.alpha * flying * 0.16 * (1 - Double(k) / 7), shadow: false)
        }
    }

    // Poświata po wylądowaniu: miętowy pierścień rozchodzący się od logo.
    let glowStart = flyStart + flyDuration * 0.62
    let g = (t - glowStart) / 0.75
    if g > 0 && g < 1 {
        let radius = tileSide * (0.55 + 0.75 * easeOutCubic(g))
        let a = 0.35 * (1 - g)
        let center = CGPoint(x: Double(W) / 2, y: Double(H) / 2)
        let ring = CGGradient(colorsSpace: sRGB, colors: [rgb(0.53, 1, 0.78, 0), rgb(0.53, 1, 0.78, a), rgb(0.53, 1, 0.78, 0)] as CFArray,
                              locations: [0.55, 0.8, 1])!
        ctx.drawRadialGradient(ring, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    draw(ctx, current, alpha: current.alpha, shadow: true)
}

// MARK: - Zapis MP4 (H.264, BT.709)

try? FileManager.default.removeItem(at: outURL)
let writer = try! AVAssetWriter(outputURL: outURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: W,
    AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000,
                                      AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
    AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: W,
    kCVPixelBufferHeightKey as String: H,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

for i in 0..<frameCount {
    while !input.isReadyForMoreMediaData { usleep(1000) }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    let pb = buffer!
    CVBufferSetAttachment(pb, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
    CVBufferSetAttachment(pb, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
    CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    CVPixelBufferLockBaseAddress(pb, [])
    // Kolory sRGB przeliczane przy rysowaniu na przestrzeń wideo (inaczej tło po odtworzeniu jest jaśniejsze).
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: W, height: H, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: videoSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.interpolationQuality = .high
    renderFrame(ctx, t: Double(i) / Double(fps))
    CVPixelBufferUnlockBaseAddress(pb, [])
    adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
if writer.status != .completed { fatalError("Błąd zapisu: \(String(describing: writer.error))") }
let bytes = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? 0
print("zapisano \(outURL.lastPathComponent): \(frameCount) klatek, \(W)x\(H)@\(fps), \(bytes / 1024) KB")
