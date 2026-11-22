import SwiftUI
import LabelCore

/// One label drawn at true proportions (with the unprintable strips shown).
struct LabelPreview: View {
    let text: String
    let size: LabelSize
    let style: TextStyle

    var body: some View {
        let result = TextRenderer.render(text, size: size, style: style)
        let ratio = size.lengthMM / size.widthMM
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.white)
            Image(nsImage: result.bitmap.nsImage)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
                .padding(.vertical, 6)        // the 12 mm print band inside the label
            if result.warning != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(4)
                    .help("Too long: shortened with “…”")
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4)))
    }
}

extension Bitmap {
    var nsImage: NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                                   colorSpaceName: .deviceWhite, bytesPerRow: width, bitsPerPixel: 8)!
        let p = rep.bitmapData!
        for y in 0..<height { for x in 0..<width { p[y * width + x] = isBlack(x: x, y: y) ? 0 : 255 } }
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }
}
