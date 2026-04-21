import AppKit
import SwiftUI

struct MenuBarIconView: View {
    let phase: ConnectionPhase
    let proxyPhase: ProxyPhase

    var body: some View {
        Image(nsImage: MenuBarIconImageFactory.image(for: phase, proxyPhase: proxyPhase))
            .renderingMode(.template)
            .accessibilityLabel("Teleport")
    }
}

enum MenuBarIconImageFactory {
    static func image(for phase: ConnectionPhase, proxyPhase: ProxyPhase) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let outer = NSBezierPath(ovalIn: NSRect(x: 4.6, y: 1.8, width: 8.8, height: 14.4))
        let inner = NSBezierPath(ovalIn: NSRect(x: 6.4, y: 4.0, width: 5.2, height: 10.0))

        NSColor.labelColor.withAlphaComponent(outerAlpha(for: phase)).setStroke()
        outer.lineWidth = 1.8
        outer.stroke()

        if proxyPhase == .enabled {
            NSColor.labelColor.withAlphaComponent(fillAlpha(for: phase)).setFill()
            inner.fill()
        } else {
            NSColor.labelColor.withAlphaComponent(innerAlpha(for: phase)).setStroke()
            inner.lineWidth = 1.0
            inner.stroke()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
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

    private static func fillAlpha(for phase: ConnectionPhase) -> CGFloat {
        switch phase {
        case .failed: return 0.85
        case .running: return 0.95
        case .starting, .stopping: return 0.82
        case .ready, .stopped: return 0.9
        case .unconfigured: return 0.75
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        MenuBarIconView(phase: .unconfigured, proxyPhase: .disabled)
        MenuBarIconView(phase: .stopped, proxyPhase: .disabled)
        MenuBarIconView(phase: .running, proxyPhase: .disabled)
        MenuBarIconView(phase: .running, proxyPhase: .enabled)
    }
    .padding()
}
