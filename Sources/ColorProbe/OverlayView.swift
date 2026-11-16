import AppKit

struct Sample {
    var px: Int
    var py: Int
    var rgb: RGB
    var tableOrigin: CGPoint
}

final class OverlayView: NSView {
    let pixels: PixelBuffer
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    private(set) var samples: [Sample] = []
    private var undoStack: [[Sample]] = []

    private var mouse: CGPoint?
    private var downHit: Hit = .none
    private var downPoint: CGPoint = .zero
    private var grabOffset: CGPoint = .zero
    private var dragging = false
    private var toast: (text: String, until: Date)?
    private var toastTimer: Timer?
    private var escArmedUntil: Date?

    private enum Button { case save, cancel }
    private enum Hit {
        case none
        case toolbar
        case button(Button)
        case marker(Int)
        case table(Int, row: Int?)
    }

    private let markerRadius: CGFloat = 7
    private let tableDistance: CGFloat = 50
    private let pad: CGFloat = 8
    private let headerH: CGFloat = 22
    private let rowH: CGFloat = 17
    private let labelW: CGFloat = 40
    private let loupeCells = 11
    private let loupeCell: CGFloat = 10

    private let valueFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let labelFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
    private let headerFont = NSFont.systemFont(ofSize: 12, weight: .bold)
    private let smallFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    private let uiFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    private let uiBoldFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    init(frame: CGRect, pixels: PixelBuffer) {
        self.pixels = pixels
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
                                       owner: self))
    }

    private var scaleX: CGFloat { CGFloat(pixels.width) / max(bounds.width, 1) }
    private var scaleY: CGFloat { CGFloat(pixels.height) / max(bounds.height, 1) }

    private func pixel(at p: CGPoint) -> (Int, Int) {
        let x = Int(floor(p.x * scaleX)), y = Int(floor(p.y * scaleY))
        return (min(max(x, 0), pixels.width - 1), min(max(y, 0), pixels.height - 1))
    }

    private func center(_ s: Sample) -> CGPoint {
        CGPoint(x: (CGFloat(s.px) + 0.5) / scaleX, y: (CGFloat(s.py) + 0.5) / scaleY)
    }

    private func tableSize(_ s: Sample) -> CGSize {
        let valueW = s.rgb.formatRows.map { ($0.1 as NSString).size(withAttributes: [.font: valueFont]).width }.max() ?? 0
        let headerW = 14 + 6 + (headerTitle(0, s) as NSString).size(withAttributes: [.font: headerFont]).width
            + 10 + (coordText(s) as NSString).size(withAttributes: [.font: smallFont]).width
        let w = pad * 2 + max(labelW + valueW, headerW)
        let h = pad * 2 + headerH + rowH * CGFloat(s.rgb.formatRows.count)
        return CGSize(width: ceil(w), height: ceil(h))
    }

    private func tableRect(_ s: Sample) -> CGRect { CGRect(origin: s.tableOrigin, size: tableSize(s)) }

    private func rowRect(_ s: Sample, _ row: Int) -> CGRect {
        let r = tableRect(s)
        return CGRect(x: r.minX + 3, y: r.minY + pad + headerH + CGFloat(row) * rowH,
                      width: r.width - 6, height: rowH)
    }

    private func headerTitle(_ i: Int, _ s: Sample) -> String { "#\(i + 1)" }
    private func coordText(_ s: Sample) -> String { "x\(s.px) y\(s.py)" }

    private func autoTableOrigin(for c: CGPoint, size: CGSize, excluding index: Int? = nil) -> CGPoint {
        let d = tableDistance
        let candidates = [
            CGPoint(x: c.x + d, y: c.y - d - size.height),
            CGPoint(x: c.x + d, y: c.y + d),
            CGPoint(x: c.x - d - size.width, y: c.y - d - size.height),
            CGPoint(x: c.x - d - size.width, y: c.y + d),
        ]
        let area = bounds.insetBy(dx: 8, dy: 8)
        var obstacles: [CGRect] = []
        for (i, s) in samples.enumerated() where i != index {
            obstacles.append(tableRect(s).insetBy(dx: -4, dy: -4))
            let m = center(s)
            obstacles.append(CGRect(x: m.x - 10, y: m.y - 10, width: 20, height: 20))
        }
        let fitting = candidates.filter { area.contains(CGRect(origin: $0, size: size)) }
        if let free = fitting.first(where: { o in
            let r = CGRect(origin: o, size: size)
            return !obstacles.contains { $0.intersects(r) }
        }) { return free }
        func clamp(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, area.minX), area.maxX - size.width),
                    y: min(max(p.y, area.minY), area.maxY - size.height))
        }
        func overlap(_ o: CGPoint) -> CGFloat {
            let r = CGRect(origin: o, size: size)
            return obstacles.reduce(0) { acc, ob in
                let i = ob.intersection(r)
                return acc + (i.isNull ? 0 : i.width * i.height)
            }
        }
        var best = clamp(fitting.first ?? candidates[0])
        var bestOverlap = overlap(best)
        var radius = d
        while radius <= d + 600 {
            for k in 0..<16 {
                let a = CGFloat(k) / 16 * 2 * .pi - .pi / 4
                let tc = CGPoint(x: c.x + cos(a) * (radius + size.width / 2),
                                 y: c.y + sin(a) * (radius + size.height / 2))
                let o = clamp(CGPoint(x: tc.x - size.width / 2, y: tc.y - size.height / 2))
                let r = CGRect(origin: o, size: size)
                if r.insetBy(dx: -12, dy: -12).contains(c) { continue }
                let ov = overlap(o)
                if ov == 0 { return o }
                if ov < bestOverlap { best = o; bestOverlap = ov }
            }
            radius += 40
        }
        return best
    }

    private var toolbarAtBottom: Bool {
        guard let m = mouse else { return false }
        return m.y < 70
    }

    private func toolbarLayout() -> (bar: CGRect, hint: CGPoint, save: CGRect, cancel: CGRect) {
        let hint = hintText as NSString
        let hintW = hint.size(withAttributes: [.font: uiFont]).width
        let saveW = (L.save as NSString).size(withAttributes: [.font: uiBoldFont]).width + 20
        let cancelW = (L.cancel as NSString).size(withAttributes: [.font: uiFont]).width + 20
        let h: CGFloat = 36
        let w = 14 + hintW + 16 + cancelW + 8 + saveW + 6
        let y = toolbarAtBottom ? bounds.maxY - h - 12 : 12
        let bar = CGRect(x: (bounds.width - w) / 2, y: y, width: w, height: h).integral
        let btnH: CGFloat = 26
        let save = CGRect(x: bar.maxX - 6 - saveW, y: bar.midY - btnH / 2, width: saveW, height: btnH)
        let cancel = CGRect(x: save.minX - 8 - cancelW, y: save.minY, width: cancelW, height: btnH)
        return (bar, CGPoint(x: bar.minX + 14, y: bar.midY - 8), save, cancel)
    }

    private var hintText: String {
        L.hint(samples.count)
    }

    private func hitAt(_ p: CGPoint) -> Hit {
        let tb = toolbarLayout()
        if tb.save.contains(p) { return .button(.save) }
        if tb.cancel.contains(p) { return .button(.cancel) }
        if tb.bar.contains(p) { return .toolbar }
        for i in samples.indices.reversed() {
            let s = samples[i]
            if tableRect(s).contains(p) {
                let row = s.rgb.formatRows.indices.first { rowRect(s, $0).contains(p) }
                return .table(i, row: row)
            }
        }
        for i in samples.indices.reversed() where hypot(center(samples[i]).x - p.x, center(samples[i]).y - p.y) <= markerRadius + 3 {
            return .marker(i)
        }
        return .none
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill()
        drawAnnotations(interactive: true)
        guard let m = mouse else { return }
        let hit = hitAt(m)
        switch hit {
        case .none, .marker: drawLoupe(at: m)
        default: break
        }
        drawToolbar(hit: hit)
        drawToast()
    }

    func drawAnnotations(interactive: Bool) {
        let hover = interactive ? mouse.map(hitAt) : nil
        for s in samples { drawArrow(for: s) }
        for (i, s) in samples.enumerated() { drawMarker(i, s) }
        for (i, s) in samples.enumerated() {
            var hoverRow: Int?
            if case let .table(ti, row)? = hover, ti == i { hoverRow = row }
            drawTable(i, s, hoverRow: hoverRow)
        }
    }

    private func drawArrow(for s: Sample) {
        let c = center(s)
        let r = tableRect(s)
        if r.insetBy(dx: -2, dy: -2).contains(c) { return }
        let a = CGPoint(x: min(max(c.x, r.minX), r.maxX), y: min(max(c.y, r.minY), r.maxY))
        let dx = c.x - a.x, dy = c.y - a.y
        let len = hypot(dx, dy)
        guard len > markerRadius + 14 else { return }
        let ux = dx / len, uy = dy / len
        let tip = CGPoint(x: c.x - ux * (markerRadius + 3), y: c.y - uy * (markerRadius + 3))
        let headLen: CGFloat = 11, headW: CGFloat = 5.5
        let base = CGPoint(x: tip.x - ux * headLen, y: tip.y - uy * headLen)

        let line = NSBezierPath()
        line.move(to: a)
        line.line(to: base)
        line.lineCapStyle = .round
        let head = NSBezierPath()
        head.move(to: tip)
        head.line(to: CGPoint(x: base.x - uy * headW, y: base.y + ux * headW))
        head.line(to: CGPoint(x: base.x + uy * headW, y: base.y - ux * headW))
        head.close()
        head.lineJoinStyle = .round

        NSColor.white.setStroke()
        line.lineWidth = 4.5
        line.stroke()
        head.lineWidth = 3
        head.stroke()
        NSColor.black.setStroke()
        line.lineWidth = 1.75
        line.stroke()
        NSColor.black.setFill()
        head.fill()
    }

    private func drawMarker(_ i: Int, _ s: Sample) {
        let c = center(s)
        let ring = NSBezierPath(ovalIn: CGRect(x: c.x - markerRadius, y: c.y - markerRadius,
                                               width: markerRadius * 2, height: markerRadius * 2))
        NSColor.black.setStroke()
        ring.lineWidth = 5
        ring.stroke()
        NSColor.white.setStroke()
        ring.lineWidth = 2.5
        ring.stroke()

        let tc = CGPoint(x: tableRect(s).midX, y: tableRect(s).midY)
        var dx = c.x - tc.x, dy = c.y - tc.y
        let len = max(hypot(dx, dy), 0.001)
        dx /= len; dy /= len
        var bc = CGPoint(x: c.x + dx * 18, y: c.y + dy * 18)
        bc.x = min(max(bc.x, 12), bounds.width - 12)
        bc.y = min(max(bc.y, 10), bounds.height - 10)
        let text = "\(i + 1)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .bold),
                                                    .foregroundColor: NSColor.white]
        let ts = text.size(withAttributes: attrs)
        let bw = max(16, ts.width + 8)
        let badge = NSBezierPath(roundedRect: CGRect(x: bc.x - bw / 2, y: bc.y - 8, width: bw, height: 16),
                                 xRadius: 8, yRadius: 8)
        NSColor(white: 0, alpha: 0.82).setFill()
        badge.fill()
        NSColor.white.setStroke()
        badge.lineWidth = 1
        badge.stroke()
        text.draw(at: CGPoint(x: bc.x - ts.width / 2, y: bc.y - ts.height / 2), withAttributes: attrs)
    }

    private func drawTable(_ i: Int, _ s: Sample, hoverRow: Int?) {
        let r = tableRect(s)
        let bg = NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = CGSize(width: 0, height: -2)
        shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        shadow.set()
        NSColor(white: 1, alpha: 0.97).setFill()
        bg.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 0, alpha: 0.3).setStroke()
        bg.lineWidth = 1
        bg.stroke()

        let swatch = CGRect(x: r.minX + pad, y: r.minY + pad + 2, width: 14, height: 14)
        s.rgb.nsColor.setFill()
        NSBezierPath(roundedRect: swatch, xRadius: 3, yRadius: 3).fill()
        NSColor(white: 0, alpha: 0.35).setStroke()
        NSBezierPath(roundedRect: swatch, xRadius: 3, yRadius: 3).stroke()
        (headerTitle(i, s) as NSString).draw(at: CGPoint(x: swatch.maxX + 6, y: r.minY + pad + 1),
                                             withAttributes: [.font: headerFont, .foregroundColor: NSColor.black])
        let coord = coordText(s) as NSString
        let cw = coord.size(withAttributes: [.font: smallFont]).width
        coord.draw(at: CGPoint(x: r.maxX - pad - cw, y: r.minY + pad + 3),
                   withAttributes: [.font: smallFont, .foregroundColor: NSColor(white: 0.45, alpha: 1)])

        for (k, (label, value)) in s.rgb.formatRows.enumerated() {
            let rr = rowRect(s, k)
            if hoverRow == k {
                NSColor.systemBlue.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: rr, xRadius: 4, yRadius: 4).fill()
            }
            (label as NSString).draw(at: CGPoint(x: r.minX + pad, y: rr.minY + 2),
                                     withAttributes: [.font: labelFont, .foregroundColor: NSColor(white: 0.45, alpha: 1)])
            (value as NSString).draw(at: CGPoint(x: r.minX + pad + labelW, y: rr.minY + 1),
                                     withAttributes: [.font: valueFont, .foregroundColor: NSColor.black])
        }
    }

    private func drawLoupe(at p: CGPoint) {
        let (cx, cy) = pixel(at: p)
        let n = loupeCells, cell = loupeCell
        let size = CGFloat(n) * cell
        let labelH: CGFloat = 22
        var o = CGPoint(x: p.x + 24, y: p.y + 24)
        if o.x + size > bounds.maxX - 4 { o.x = p.x - 24 - size }
        if o.y + size + labelH > bounds.maxY - 4 { o.y = p.y - 24 - size - labelH }
        let rect = CGRect(origin: o, size: CGSize(width: size, height: size))
        let frame = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 10
        shadow.shadowColor = NSColor(white: 0, alpha: 0.5)
        shadow.set()
        NSColor.black.setFill()
        frame.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        frame.addClip()
        let half = n / 2
        for j in 0..<n {
            for i in 0..<n {
                let x = cx - half + i, y = cy - half + j
                let cr = CGRect(x: o.x + CGFloat(i) * cell, y: o.y + CGFloat(j) * cell, width: cell, height: cell)
                (pixels.contains(x: x, y: y) ? pixels.color(x: x, y: y).nsColor : NSColor(white: 0.15, alpha: 1)).setFill()
                cr.fill()
            }
        }
        let grid = NSBezierPath()
        for k in 1..<n {
            let v = CGFloat(k) * cell
            grid.move(to: CGPoint(x: o.x + v, y: o.y)); grid.line(to: CGPoint(x: o.x + v, y: o.y + size))
            grid.move(to: CGPoint(x: o.x, y: o.y + v)); grid.line(to: CGPoint(x: o.x + size, y: o.y + v))
        }
        NSColor(white: 0.5, alpha: 0.25).setStroke()
        grid.lineWidth = 0.5
        grid.stroke()
        let centerCell = CGRect(x: o.x + CGFloat(half) * cell, y: o.y + CGFloat(half) * cell, width: cell, height: cell)
        NSColor.black.setStroke()
        NSBezierPath(rect: centerCell.insetBy(dx: -1, dy: -1)).stroke()
        NSColor.white.setStroke()
        NSBezierPath(rect: centerCell).stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 1, alpha: 0.9).setStroke()
        frame.lineWidth = 1.5
        frame.stroke()

        let c = pixels.color(x: cx, y: cy)
        let label = "\(c.hex)  \(cx),\(cy)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: NSColor.white]
        let ls = label.size(withAttributes: attrs)
        let lr = CGRect(x: rect.midX - (ls.width + 14) / 2, y: rect.maxY + 4, width: ls.width + 14, height: labelH - 4)
        NSColor(white: 0, alpha: 0.82).setFill()
        NSBezierPath(roundedRect: lr, xRadius: 5, yRadius: 5).fill()
        label.draw(at: CGPoint(x: lr.minX + 7, y: lr.midY - ls.height / 2), withAttributes: attrs)
    }

    private func drawToolbar(hit: Hit) {
        let tb = toolbarLayout()
        let bar = NSBezierPath(roundedRect: tb.bar, xRadius: 10, yRadius: 10)
        NSColor(white: 0.1, alpha: 0.88).setFill()
        bar.fill()
        (hintText as NSString).draw(at: tb.hint, withAttributes: [.font: uiFont, .foregroundColor: NSColor(white: 0.9, alpha: 1)])

        var saveHover = false, cancelHover = false
        if case .button(.save) = hit { saveHover = true }
        if case .button(.cancel) = hit { cancelHover = true }

        NSColor(white: 1, alpha: cancelHover ? 0.28 : 0.16).setFill()
        NSBezierPath(roundedRect: tb.cancel, xRadius: 6, yRadius: 6).fill()
        drawCentered(L.cancel, in: tb.cancel, font: uiFont, color: .white)

        (saveHover ? NSColor.systemBlue.highlight(withLevel: 0.15) ?? .systemBlue : NSColor.systemBlue).setFill()
        NSBezierPath(roundedRect: tb.save, xRadius: 6, yRadius: 6).fill()
        drawCentered(L.save, in: tb.save, font: uiBoldFont, color: .white)
    }

    private func drawToast() {
        guard let t = toast, t.until > Date() else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: uiBoldFont, .foregroundColor: NSColor.white]
        let s = t.text as NSString
        let ts = s.size(withAttributes: attrs)
        let tb = toolbarLayout().bar
        let y = toolbarAtBottom ? tb.minY - 40 : tb.maxY + 10
        let r = CGRect(x: bounds.midX - (ts.width + 28) / 2, y: y, width: ts.width + 28, height: 30)
        NSColor(white: 0.1, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        s.draw(at: CGPoint(x: r.minX + 14, y: r.midY - ts.height / 2), withAttributes: attrs)
    }

    private func drawCentered(_ text: String, in r: CGRect, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let s = text as NSString
        let ts = s.size(withAttributes: attrs)
        s.draw(at: CGPoint(x: r.midX - ts.width / 2, y: r.midY - ts.height / 2), withAttributes: attrs)
    }

    private func showToast(_ text: String, seconds: TimeInterval = 1.4) {
        toast = (text, Date().addingTimeInterval(seconds))
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: seconds + 0.05, repeats: false) { [weak self] _ in
            self?.needsDisplay = true
        }
        needsDisplay = true
    }

    private func pushUndo() {
        undoStack.append(samples)
        if undoStack.count > 200 { undoStack.removeFirst() }
    }

    private func addSample(at p: CGPoint) {
        pushUndo()
        let (x, y) = pixel(at: p)
        var s = Sample(px: x, py: y, rgb: pixels.color(x: x, y: y), tableOrigin: .zero)
        s.tableOrigin = autoTableOrigin(for: center(s), size: tableSize(s))
        samples.append(s)
    }

    private func undo() {
        guard let prev = undoStack.popLast() else { NSSound.beep(); return }
        samples = prev
        needsDisplay = true
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        showToast(L.copied(value))
    }

    private func updateCursor(_ hit: Hit) {
        switch hit {
        case .button: NSCursor.pointingHand.set()
        case .toolbar: NSCursor.arrow.set()
        case .table(_, let row): (row != nil ? NSCursor.pointingHand : NSCursor.openHand).set()
        case .marker: NSCursor.openHand.set()
        case .none: NSCursor.crosshair.set()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(hitAt(convert(event.locationInWindow, from: nil)))
    }

    override func mouseMoved(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil)
        updateCursor(hitAt(mouse!))
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        downPoint = p
        dragging = false
        downHit = hitAt(p)
        switch downHit {
        case .marker(let i):
            let c = center(samples[i])
            grabOffset = CGPoint(x: p.x - c.x, y: p.y - c.y)
            NSCursor.closedHand.set()
        case .table(let i, _):
            let o = samples[i].tableOrigin
            grabOffset = CGPoint(x: p.x - o.x, y: p.y - o.y)
        default:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        if !dragging {
            guard hypot(p.x - downPoint.x, p.y - downPoint.y) > 3 else { return }
            switch downHit {
            case .marker, .table: pushUndo(); dragging = true
            default: return
            }
            NSCursor.closedHand.set()
        }
        switch downHit {
        case .marker(let i):
            let old = center(samples[i])
            let (x, y) = pixel(at: CGPoint(x: p.x - grabOffset.x, y: p.y - grabOffset.y))
            samples[i].px = x
            samples[i].py = y
            samples[i].rgb = pixels.color(x: x, y: y)
            let new = center(samples[i])
            samples[i].tableOrigin.x += new.x - old.x
            samples[i].tableOrigin.y += new.y - old.y
        case .table(let i, _):
            let size = tableSize(samples[i])
            var o = CGPoint(x: p.x - grabOffset.x, y: p.y - grabOffset.y)
            o.x = min(max(o.x, 0), bounds.width - size.width)
            o.y = min(max(o.y, 0), bounds.height - size.height)
            samples[i].tableOrigin = o
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragging = false
            downHit = .none
            if let m = mouse { updateCursor(hitAt(m)) }
            needsDisplay = true
        }
        if dragging { return }
        switch downHit {
        case .button(.save): onSave?()
        case .button(.cancel): onCancel?()
        case .table(let i, let row?): copy(samples[i].rgb.formatRows[row].1)
        case .none: addSample(at: downPoint)
        default: break
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch hitAt(p) {
        case .marker(let i), .table(let i, _):
            pushUndo()
            samples.remove(at: i)
            needsDisplay = true
        default:
            break
        }
    }

    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.contains(.command) && (chars == "z" || chars == "я") {
            undo()
            return
        }
        switch event.keyCode {
        case 36, 76:
            onSave?()
        case 53:
            if samples.isEmpty || (escArmedUntil.map { $0 > Date() } ?? false) {
                onCancel?()
            } else {
                escArmedUntil = Date().addingTimeInterval(2)
                showToast(L.escAgain, seconds: 2)
            }
        default:
            super.keyDown(with: event)
        }
    }

    func renderPNG(base: CGImage) -> Data? {
        let w = pixels.width, h = pixels.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scaleX, y: -scaleY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        drawAnnotations(interactive: false)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
