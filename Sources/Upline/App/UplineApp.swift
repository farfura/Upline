import AppKit
import SwiftUI
import UserNotifications

@main
struct UplineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(store)
        } label: {
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Notifier.available {
            UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        }
        MainActor.assumeIsolated {
            let store = Store.shared
            store.start()
            if !store.config.onboarded {
                WindowManager.shared.showOnboarding()
            }
        }
    }
}

struct MenuBarLabel: View {
    @Environment(Store.self) private var store

    var body: some View {
        let health = store.overall
        let problems = store.problemServices.filter { $0.tier != .stale }.count
        HStack(spacing: 3) {
            Image(nsImage: StatusIcon.image(health: health, offline: store.network.problem != nil, busy: store.isScanning))
            if problems > 0 {
                Text("\(problems)").font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
        }
    }
}

/// Draws the menu bar glyph: a tiny radar. Template (adapts to the menu bar) while all is well,
/// with a colored core when something needs attention.
enum StatusIcon {
    static func image(health: Health, offline: Bool, busy: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let alert = health.isProblem || offline
        let tint: NSColor = offline ? NSColor(srgbRed: 1, green: 0.76, blue: 0.3, alpha: 1) : nsColor(health)

        let img = NSImage(size: size, flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY)
            let ink = alert ? NSColor.labelColor : NSColor.black

            let outer = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            outer.lineWidth = 1.4
            ink.withAlphaComponent(0.95).setStroke()
            outer.stroke()

            let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 5.2, dy: 5.2))
            inner.lineWidth = 1
            ink.withAlphaComponent(0.55).setStroke()
            inner.stroke()

            // Sweep line toward the upper right
            let beam = NSBezierPath()
            beam.move(to: c)
            beam.line(to: NSPoint(x: c.x + 5.6, y: c.y + 5.6))
            beam.lineWidth = 1.4
            beam.lineCapStyle = .round
            ink.setStroke()
            beam.stroke()

            if busy {
                let blip = NSBezierPath(ovalIn: NSRect(x: c.x + 2.2, y: c.y - 5.2, width: 2.4, height: 2.4))
                ink.setFill()
                blip.fill()
            }

            let coreR: CGFloat = alert ? 3.4 : 1.8
            let core = NSBezierPath(ovalIn: NSRect(x: c.x - coreR, y: c.y - coreR, width: coreR * 2, height: coreR * 2))
            (alert ? tint : ink).setFill()
            core.fill()
            return true
        }
        img.isTemplate = !alert
        return img
    }

    private static func nsColor(_ h: Health) -> NSColor {
        switch h {
        case .majorOutage: NSColor(srgbRed: 1, green: 0.30, blue: 0.42, alpha: 1)
        case .partialOutage: NSColor(srgbRed: 1, green: 0.54, blue: 0.24, alpha: 1)
        case .degraded, .suspected: NSColor(srgbRed: 1, green: 0.76, blue: 0.3, alpha: 1)
        default: NSColor.labelColor
        }
    }
}

// MARK: - Windows

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var onboarding: NSWindow?
    private var settings: NSWindow?

    func showOnboarding() {
        if let w = onboarding { present(w); return }
        let view = OnboardingView(close: { [weak self] in self?.onboarding?.close() })
            .environment(Store.shared)
        let w = makeWindow(title: "Welcome to Upline", content: view, size: NSSize(width: 780, height: 540))
        w.isReleasedWhenClosed = false
        onboarding = w
        present(w)
    }

    func showSettings() {
        if let w = settings { present(w); return }
        let w = makeWindow(title: "Upline Settings", content: SettingsView().environment(Store.shared), size: NSSize(width: 680, height: 480))
        w.isReleasedWhenClosed = false
        settings = w
        present(w)
    }

    private func makeWindow<V: View>(title: String, content: V, size: NSSize) -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.title = title
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(srgbRed: 0.016, green: 0.024, blue: 0.043, alpha: 1)
        w.contentView = NSHostingView(rootView: content.ignoresSafeArea())
        w.center()
        return w
    }

    private func present(_ w: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }
}
