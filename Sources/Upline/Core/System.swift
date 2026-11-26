import AppKit
import CoreServices
import Network
import UserNotifications

// MARK: - File activity

/// Watches the code folders with FSEvents so Upline knows which project you're working in,
/// without needing Accessibility or Screen Recording permission.
final class ActivityMonitor {
    private var stream: FSEventStreamRef?
    private let onChange: ([String]) -> Void

    init(onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
    }

    deinit { stop() }

    func start(paths: [String]) {
        stop()
        let existing = paths.map(\.expandingTilde).filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<ActivityMonitor>.fromOpaque(info).takeUnretainedValue()
            let cfArray = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue()
            let list = (cfArray as? [String]) ?? []
            let relevant = list.prefix(count).filter { p in
                !p.contains("/node_modules/") && !p.contains("/.git/objects") && !p.contains("/DerivedData/")
                    && !p.contains("/.next/cache") && !p.contains("/.build/")
            }
            if !relevant.isEmpty {
                DispatchQueue.main.async { monitor.onChange(Array(relevant)) }
            }
        }
        stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 5.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagIgnoreSelf)
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "upline.fsevents"))
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

// MARK: - Wake and network

/// Fires when the Mac wakes, the screen unlocks, or the network comes back.
final class WakeObserver {
    private var tokens: [NSObjectProtocol] = []
    private let pathMonitor = NWPathMonitor()
    private var lastSatisfied: Bool?

    init(onWake: @escaping () -> Void, onNetwork: @escaping (Bool) -> Void) {
        let ws = NSWorkspace.shared.notificationCenter
        tokens.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in onWake() })
        tokens.append(ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in onWake() })
        tokens.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { _ in onWake() })

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self else { return }
                if self.lastSatisfied != ok {
                    self.lastSatisfied = ok
                    onNetwork(ok)
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "upline.path"))
    }

    deinit {
        tokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        pathMonitor.cancel()
    }
}

// MARK: - Notifications

enum Notifier {
    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func send(id: String, title: String, body: String, sound: Bool = true, url: URL? = nil) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "upline"
        if sound { content.sound = .default }
        if let url { content.userInfo = ["url": url.absoluteString] }
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
