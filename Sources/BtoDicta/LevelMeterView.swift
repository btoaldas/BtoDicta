import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Medidor de voz (el latido)

final class LevelMeterView: NSView {
    private var levels = [Float](repeating: 0, count: 6)

    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
        needsDisplay = true
    }

    func reset() {
        levels = [Float](repeating: 0, count: levels.count)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let barWidth: CGFloat = 3
        let gap: CGFloat = 2
        let midY = bounds.midY
        for (i, level) in levels.enumerated() {
            let h = max(3, CGFloat(level) * bounds.height * 0.9)
            let x = CGFloat(i) * (barWidth + gap)
            let rect = NSRect(x: x, y: midY - h / 2, width: barWidth, height: h)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            NSColor.systemRed.withAlphaComponent(0.55 + 0.45 * CGFloat(level)).setFill()
            path.fill()
        }
    }
}

