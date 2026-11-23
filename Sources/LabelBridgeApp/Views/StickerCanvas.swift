import SwiftUI
import LabelCore

struct StickerOutline: Shape {
    let shape: StickerShape

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if shape == .twoCircles {
            let size = CGSize(width: rect.width / 2, height: rect.height)
            path.addEllipse(in: CGRect(origin: rect.origin, size: size))
            path.addEllipse(in: CGRect(origin: CGPoint(x: rect.midX, y: rect.minY), size: size))
        } else {
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 4, height: 4))
        }
        return path
    }
}

struct StickerArtwork: View {
    let design: StickerDesign
    let bitmap: Bitmap?

    var body: some View {
        GeometryReader { geometry in
            let outline = StickerOutline(shape: design.shape)
            ZStack {
                outline.fill(.white)
                if let bitmap {
                    Image(nsImage: bitmap.nsImage)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: geometry.size.width,
                               height: geometry.size.height * CGFloat(bitmap.height) / CGFloat(design.size.widthMM / 25.4 * LabelSize.dpi))
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .mask(outline)
                }
                outline.stroke(.gray.opacity(0.5), lineWidth: 1)
            }
        }
        .aspectRatio(design.size.lengthMM / design.size.widthMM, contentMode: .fit)
    }
}

struct StickerCanvas: View {
    let design: StickerDesign
    let bitmap: Bitmap?
    @Binding var selectedID: UUID?
    let onUpdate: (StickerObject) -> Void
    let onBegin: () -> Void
    let onEnd: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / design.size.lengthMM
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle()).onTapGesture { selectedID = nil }
                StickerArtwork(design: design, bitmap: bitmap).allowsHitTesting(false)
                ForEach(design.objects) { object in
                    ObjectHandles(object: object, paperSize: design.size, scale: scale, selected: selectedID == object.id,
                                  onSelect: { selectedID = object.id }, onUpdate: onUpdate,
                                  onBegin: onBegin, onEnd: onEnd)
                }
            }
            .coordinateSpace(name: "sticker-canvas")
        }
        .aspectRatio(design.size.lengthMM / design.size.widthMM, contentMode: .fit)
    }
}

private struct ObjectHandles: View {
    let object: StickerObject
    let paperSize: LabelSize
    let scale: Double
    let selected: Bool
    let onSelect: () -> Void
    let onUpdate: (StickerObject) -> Void
    let onBegin: () -> Void
    let onEnd: () -> Void
    @State private var moveStart: StickerFrame?
    @State private var resizeStart: StickerFrame?

    var body: some View {
        let frame = object.frame
        let width = frame.width * scale, height = frame.height * scale
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { onSelect() }
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("sticker-canvas"))
                    .onChanged { value in
                        onSelect()
                        if moveStart == nil { moveStart = frame; onBegin() }
                        guard let start = moveStart else { return }
                        var next = object
                        next.frame.x = start.x + value.translation.width / scale
                        next.frame.y = start.y + value.translation.height / scale
                        onUpdate(next)
                    }
                    .onEnded { _ in moveStart = nil; onEnd() })
            if selected {
                Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.accentColor, lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .position(x: width, y: height)
                    .help("Drag to resize")
                    .highPriorityGesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("sticker-canvas"))
                        .onChanged { value in
                            if resizeStart == nil { resizeStart = frame; onBegin() }
                            guard let start = resizeStart else { return }
                            var next = object
                            next.frame.width = min(max(start.width + value.translation.width / scale, 1), paperSize.lengthMM - start.x)
                            next.frame.height = min(max(start.height + value.translation.height / scale, 1), paperSize.widthMM - start.y)
                            onUpdate(next)
                        }
                        .onEnded { _ in resizeStart = nil; onEnd() })
            }
        }
        .frame(width: width, height: height)
        .offset(x: frame.x * scale, y: frame.y * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(object.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSelect() }
    }
}
