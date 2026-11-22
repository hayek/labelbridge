import AppKit

public enum PDFLabelsError: Error { case notPDF, unreadable }

/// Turns each page of a PDF (from the Print dialog) into one label bitmap:
/// the page is scaled to fit the printable area (between the end margins, inside the print band) and centred.
public enum PDFLabels {
    public static func bitmaps(from data: Data, size: LabelSize) throws -> [Bitmap] {
        guard data.starts(with: Array("%PDF".utf8)) else { throw PDFLabelsError.notPDF }
        guard let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider), doc.numberOfPages > 0 else {
            throw PDFLabelsError.unreadable
        }
        let (length, height) = size.canvasPixels
        let margin = LabelSize.endMarginPixels
        let area = CGRect(x: margin, y: 0, width: length - 2 * margin, height: height)
        return (1...doc.numberOfPages).compactMap { n in
            guard let page = doc.page(at: n) else { return nil }
            return render(page, into: area, canvas: (length, height))
        }
    }

    static func render(_ page: CGPDFPage, into area: CGRect, canvas: (Int, Int)) -> Bitmap {
        let (w, h) = canvas
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        var box = page.getBoxRect(.cropBox)
        // A portrait page is turned so its long side runs along the label.
        let rotate = box.height > box.width
        if rotate { box = CGRect(x: box.minX, y: box.minY, width: box.height, height: box.width) }
        let scale = min(area.width / box.width, area.height / box.height)
        let drawn = CGSize(width: box.width * scale, height: box.height * scale)
        ctx.translateBy(x: area.midX - drawn.width / 2, y: area.midY - drawn.height / 2)
        ctx.scaleBy(x: scale, y: scale)
        if rotate { ctx.translateBy(x: box.width, y: 0); ctx.rotate(by: .pi / 2) }
        let crop = page.getBoxRect(.cropBox)
        ctx.translateBy(x: -crop.minX, y: -crop.minY)
        ctx.drawPDFPage(page)

        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var pixels = [Bool](repeating: false, count: w * h)
        // CGContext memory is top row first.
        for y in 0..<h { for x in 0..<w where p[y * w + x] < 128 { pixels[y * w + x] = true } }
        return Bitmap(width: w, height: h, pixels: pixels)
    }
}

extension PDFLabels {
    /// The label size the Print dialog chose, read from the first page (rounded to whole mm).
    public static func labelSize(of data: Data) -> LabelSize? {
        guard let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider),
              let box = doc.page(at: 1)?.getBoxRect(.mediaBox), box.width > 0, box.height > 0 else { return nil }
        let mm = { (pt: CGFloat) in (Double(pt) / 72 * 25.4).rounded() }
        return LabelSize(mm(box.width), mm(box.height))
    }
}
