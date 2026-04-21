import AppKit
import SwiftUI

struct MenuBarIconView: View {
    let phase: ConnectionPhase
    let proxyPhase: ProxyPhase
    let animationTime: TimeInterval

    private var isConnected: Bool {
        phase == .running && proxyPhase == .enabled
    }

    var body: some View {
        iconImage(time: animationTime, animated: isConnected)
    }

    private func iconImage(time: TimeInterval, animated: Bool) -> some View {
        Image(nsImage: MenuBarIconImageFactory.image(for: phase, proxyPhase: proxyPhase, time: time, isAnimated: animated))
            .renderingMode(.template)
            .accessibilityLabel(animated ? "Teleport connected" : "Teleport")
    }
}

enum MenuBarIconImageFactory {
    private static let size = NSSize(width: 18, height: 18)
    private static let particleSeeds: [Double] = [0.0, 0.14, 0.28, 0.42, 0.56, 0.7, 0.84]

    static func image(for phase: ConnectionPhase, proxyPhase: ProxyPhase, time: TimeInterval, isAnimated: Bool) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let outer = NSBezierPath(ovalIn: NSRect(x: 6.0, y: 1.8, width: 8.4, height: 14.4))
        let inner = NSBezierPath(ovalIn: NSRect(x: 7.8, y: 4.0, width: 4.9, height: 10.0))

        NSColor.labelColor.withAlphaComponent(outerAlpha(for: phase)).setStroke()
        outer.lineWidth = 1.8
        outer.stroke()

        if proxyPhase == .enabled {
            NSColor.labelColor.withAlphaComponent(fillAlpha(for: phase, time: time, isAnimated: isAnimated)).setFill()
            inner.fill()

            if isAnimated {
                drawParticles(time: time)
            }
        } else {
            NSColor.labelColor.withAlphaComponent(innerAlpha(for: phase)).setStroke()
            inner.lineWidth = 1.0
            inner.stroke()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func drawParticles(time: TimeInterval) {
        let portalEntryX: CGFloat = 12.45
        let portalCenterY: CGFloat = 9.0

        for (index, seed) in particleSeeds.enumerated() {
            let cycle = (time * 0.22 + seed).truncatingRemainder(dividingBy: 1)
            let progress = eased(progress: cycle)
            let startX = -2.4 - CGFloat(index) * 0.42
            let spawnYOffset = CGFloat(sin(Double(index) * 2.17) * 3.2 + cos(Double(index) * 1.41) * 1.4)
            let driftY = spawnYOffset * (1 - progress)
            let wave = CGFloat(sin((time * 1.2 + Double(index) * 1.37) * .pi) * 0.34)

            let x = startX + (portalEntryX - startX) * progress
            let y = portalCenterY + driftY + wave * (1 - progress) * 2.8

            let appear = min(max(cycle / 0.22, 0), 1)
            let fade = min(max((1 - cycle) / 0.18, 0), 1)
            let alpha = 0.24 + 0.52 * appear * fade
            let radius: CGFloat = 0.86 + 0.38 * (1 - progress)
            let rect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)

            NSColor.labelColor.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    private static func eased(progress: Double) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return CGFloat(1 - pow(1 - clamped, 2.2))
    }

    private static func outerAlpha(for phase: ConnectionPhase) -> CGFloat {
        switch phase {
        case .failed: return 0.95
        case .running: return 1.0
        case .starting, .stopping: return 0.9
        case .ready, .stopped: return 0.86
        case .unconfigured: return 0.7
        }
    }

    private static func innerAlpha(for phase: ConnectionPhase) -> CGFloat {
        switch phase {
        case .failed: return 0.7
        case .running: return 0.65
        case .starting, .stopping: return 0.55
        case .ready, .stopped: return 0.52
        case .unconfigured: return 0.42
        }
    }

    private static func fillAlpha(for phase: ConnectionPhase, time: TimeInterval, isAnimated: Bool) -> CGFloat {
        let base: CGFloat = switch phase {
        case .failed: 0.78
        case .running: 0.58
        case .starting, .stopping: 0.72
        case .ready, .stopped: 0.82
        case .unconfigured: 0.68
        }

        guard isAnimated else { return base }
        return base + 0.06 * CGFloat(sin(time * 2.4))
    }
}

#Preview {
    VStack(spacing: 12) {
        MenuBarIconView(phase: .unconfigured, proxyPhase: .disabled, animationTime: 0)
        MenuBarIconView(phase: .stopped, proxyPhase: .disabled, animationTime: 0)
        MenuBarIconView(phase: .running, proxyPhase: .disabled, animationTime: 0)
        MenuBarIconView(phase: .running, proxyPhase: .enabled, animationTime: Date().timeIntervalSinceReferenceDate)
    }
    .padding()
}
