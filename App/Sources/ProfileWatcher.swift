import Foundation
import CoreServices

final class ProfileWatcher {
    static let shared = ProfileWatcher()

    private var stream: FSEventStreamRef?
    var onProfilesChanged: ((_ changedPaths: [String]) -> Void)?
    var onActiveProfileChanged: ((_ changedPaths: [String]) -> Void)?
    private var debounceTimer: Timer?

    private init() {}

    func startWatching() {
        stop()
        let root = ConfigAccess.defaultRoot
        let paths = [root.path] as CFArray
        var context = FSEventStreamContext(version: 0, info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        stream = FSEventStreamCreate(nil, { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            let watcher = Unmanaged<ProfileWatcher>.fromOpaque(clientCallBackInfo!).takeUnretainedValue()
            let evPaths = unsafeBitCast(eventPaths, to: UnsafeMutablePointer<UnsafePointer<CChar>?>.self)
            var changed: [String] = []
            for i in 0..<numEvents {
                if let cstr = evPaths[Int(i)] {
                    let path = String(cString: cstr)
                    // Ignore events under ~/.config/alacritty to avoid apply-trigger loops
                    if path.contains("/.config/alacritty/") { continue }
                    changed.append(path)
                }
            }
            // Debounce events to avoid thrashing
            DispatchQueue.main.async {
                watcher.debounceTimer?.invalidate()
                watcher.debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                    let activeDir = ActiveProfileStore.shared.activeProfile?.directory.path
                    if let activeDir, changed.contains(where: { $0.hasPrefix(activeDir) }) {
                        watcher.onActiveProfileChanged?(changed)
                    } else {
                        watcher.onProfilesChanged?(changed)
                    }
                }
            }
        }, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags)
        if let stream {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit {
        stop()
    }
}


