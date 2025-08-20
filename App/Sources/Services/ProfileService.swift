import Foundation
import AppKit
import CoreServices
import Combine
#if canImport(Yams)
import Yams
#endif


enum ProfileServiceError: LocalizedError {
    case invalidProfileName
    case profileAlreadyExists(String)
    case profileNotFound(String)
    case cannotDeleteActiveProfile
    case deletionFailed(String)
    case fileNotFound(String)
    case wallpaperSetFailed(Error)
    case templateRenderingFailed(String, Error)
    case fileOperationFailed(String, Error)
    case permissionDenied(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidProfileName:
            return "Invalid profile name"
        case .profileAlreadyExists(let name):
            return "A profile with the name '\(name)' already exists"
        case .profileNotFound(let name):
            return "Profile '\(name)' not found"
        case .cannotDeleteActiveProfile:
            return "Cannot delete the currently active profile. Please switch to another profile first."
        case .deletionFailed(let reason):
            return "Failed to delete profile: \(reason)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .wallpaperSetFailed(let error):
            return "Failed to set wallpaper: \(error.localizedDescription)"
        case .templateRenderingFailed(let template, let error):
            return "Failed to render template '\(template)': \(error.localizedDescription)"
        case .fileOperationFailed(let operation, let error):
            return "File operation failed (\(operation)): \(error.localizedDescription)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .cannotDeleteActiveProfile:
            return "Switch to a different profile before attempting to delete this one."
        case .deletionFailed:
            return "Check that the profile folder is not in use and try again."
        default:
            return nil
        }
    }
}


private struct CachedProfile {
    let profile: Profile
    let cachedAt: Date
    let fileModificationDate: Date
    
    var isValid: Bool {
        let maxAge: TimeInterval = 300 // 5 minutes
        return Date().timeIntervalSince(cachedAt) < maxAge
    }
}


final class ProfileService: ObservableObject {
    
    
    @Published private(set) var profiles: [ProfileDescriptor] = []
    @Published private(set) var activeProfile: ProfileDescriptor?
    @Published private(set) var isApplying = false
    
    
    private let userDefaultsKey = "ActiveProfileDirectoryPath"
    private let cacheQueue = DispatchQueue(label: "com.ricebar.profile-cache", qos: .userInitiated)
    private var profileCache: [URL: CachedProfile] = [:]
    private var lastModificationDates: [URL: Date] = [:]
    
    private var stream: FSEventStreamRef?
    private var debounceTimer: Timer?
    
    private let fileSystemService: FileSystemService
    
    
    static let shared = ProfileService()
    
    private init() {
        self.fileSystemService = FileSystemService()
        
        ensureProfilesRoot()
        loadActiveProfileFromDefaults()
        reload()
        startWatching()
    }
    
    deinit {
        stopWatching()
    }
    
    
    func reload() {
        LoggerService.info("ProfileService: Starting reload of all profiles")
        let root = profilesRoot()
        let fm = FileManager.default
        var loaded: [ProfileDescriptor] = []
        
        cacheQueue.async { [weak self] in
            self?.profileCache.removeAll()
            self?.lastModificationDates.removeAll()
        }
        
        if let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            LoggerService.info("ProfileService: Found \(items.count) items in profiles directory")
            for url in items {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false else { continue }
                
                LoggerService.info("ProfileService: Loading profile from: \(url.lastPathComponent)")
                if let profile = loadProfile(at: url) {
                    loaded.append(ProfileDescriptor(profile: profile, directory: url))
                    LoggerService.info("ProfileService: Loaded profile '\(profile.name)' with wallpaper: \(profile.wallpaper ?? "none")")
                } else {
                    let defaults = defaultProfile(for: url)
                    loaded.append(ProfileDescriptor(profile: defaults, directory: url))
                    LoggerService.info("ProfileService: Created default profile '\(defaults.name)' with wallpaper: \(defaults.wallpaper ?? "none")")
                }
            }
        }
        
        LoggerService.info("ProfileService: Loaded \(loaded.count) profiles total")
        
        DispatchQueue.main.async {
            self.profiles = loaded
            self.restoreActiveProfileFromDefaults()
            LoggerService.info("ProfileService: Reload complete, active profile restored")
        }
    }
    
    func openProfilesFolder() {
        NSWorkspace.shared.open(profilesRoot())
    }
    
    func copyProfile(_ descriptor: ProfileDescriptor, to newName: String) throws -> ProfileDescriptor {
        let fm = FileManager.default
        let sanitized = sanitizeProfileName(newName)
        guard !sanitized.isEmpty else { throw ProfileServiceError.invalidProfileName }
        
        let dest = profilesRoot().appendingPathComponent(sanitized, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            throw ProfileServiceError.profileAlreadyExists(sanitized)
        }
        
        try fm.copyItem(at: descriptor.directory, to: dest)
        
        let transient = [".ricebar-last-apply.json"]
        for name in transient {
            let p = dest.appendingPathComponent(name)
            try? fm.removeItem(at: p)
        }
        
        reload()
        
        if let newDesc = profiles.first(where: { $0.directory == dest }) {
            return newDesc
        }
        return ProfileDescriptor(profile: defaultProfile(for: dest), directory: dest)
    }
    
    func createProfileFromCurrent(name: String) throws -> ProfileDescriptor {
        let fm = FileManager.default
        let sanitized = sanitizeProfileName(name)
        guard !sanitized.isEmpty else { throw ProfileServiceError.invalidProfileName }
        
        let dest = profilesRoot().appendingPathComponent(sanitized, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            throw ProfileServiceError.profileAlreadyExists(sanitized)
        }
        
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        var profile = Profile(name: sanitized)
        
        if let currentWallpaper = getCurrentWallpaper() {
            let wallpaperDest = dest.appendingPathComponent("wallpaper.\(currentWallpaper.pathExtension)")
            try fm.copyItem(at: currentWallpaper, to: wallpaperDest)
            profile.wallpaper = wallpaperDest.lastPathComponent
            LoggerService.info("Copied current wallpaper to new profile: \(wallpaperDest.lastPathComponent)")
        }
        
        let descriptor = ProfileDescriptor(profile: profile, directory: dest)
        
        try captureCodeEditorSettings(to: descriptor)
        
        try snapshotCurrentConfiguration(to: descriptor)
        
        let jsonURL = dest.appendingPathComponent("profile.json")
        try saveProfileToJSON(descriptor.profile, at: jsonURL)
        
        reload()
        
        if let newDesc = profiles.first(where: { $0.directory == dest }) {
            return newDesc
        }
        return descriptor
    }
    
    func createEmptyProfile(name: String) throws -> ProfileDescriptor {
        let fm = FileManager.default
        let sanitized = sanitizeProfileName(name)
        guard !sanitized.isEmpty else { throw ProfileServiceError.invalidProfileName }
        
        let dest = profilesRoot().appendingPathComponent(sanitized, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            throw ProfileServiceError.profileAlreadyExists(sanitized)
        }
        
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest.appendingPathComponent("home", isDirectory: true), withIntermediateDirectories: true)
        
        let descriptor = ProfileDescriptor(profile: Profile(name: sanitized), directory: dest)
        let jsonURL = dest.appendingPathComponent("profile.json")
        try saveProfileToJSON(descriptor.profile, at: jsonURL)
        
        reload()
        
        if let newDesc = profiles.first(where: { $0.directory == dest }) {
            return newDesc
        }
        return descriptor
    }
    
    func deleteProfile(_ descriptor: ProfileDescriptor) throws {
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: descriptor.directory.path) else {
            throw ProfileServiceError.profileNotFound(descriptor.profile.name)
        }
        
        invalidateCache(directory: descriptor.directory)
        
        do {
            var trashURL: NSURL?
            try fm.trashItem(at: descriptor.directory, resultingItemURL: &trashURL)
            
            if activeProfile?.directory == descriptor.directory {
                setActiveProfile(nil)
            }
            
            reload()
            
            LoggerService.info("Profile '\(descriptor.profile.name)' moved to trash successfully")
        } catch {
            throw ProfileServiceError.deletionFailed(error.localizedDescription)
        }
    }
    
    
    func applyProfile(_ descriptor: ProfileDescriptor, cleanConfig: Bool = false) throws {
        while ApplyActivity.isApplying {
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        ApplyActivity.begin()
        
        DispatchQueue.main.async {
            self.isApplying = true
        }
        
        defer {
            ApplyActivity.end()
            DispatchQueue.main.async {
                self.isApplying = false
            }
        }
        
        var actions: [ApplyAction] = []
        let profile = descriptor.profile
        
        if let wallpaperRel = profile.wallpaper {
            let url = descriptor.directory.appendingPathComponent(wallpaperRel)
            LoggerService.info("Profile specifies wallpaper: '\(wallpaperRel)' -> Full path: \(url.path)")
            try applyWallpaper(url: url)
        } else {
            LoggerService.info("Profile has no wallpaper specified")
        }
        
        try applyCodeEditorSettings(from: descriptor)
        
        fileSystemService.renderTemplates(for: descriptor)
        
        let targetHome = URL(fileURLWithPath: NSHomeDirectory())
        
        if cleanConfig {
            try backupAndCleanConfig(atHome: targetHome)
        }
        
        if let replacements = profile.replacements, !replacements.isEmpty {
            for repl in replacements {
                let src = descriptor.directory.appendingPathComponent(repl.source)
                let dst = URL(fileURLWithPath: repl.destination.expandingTildeInPath)
                let action = try replaceFile(source: src, destination: dst)
                actions.append(action)
            }
        } else {
            let homeOverlay = descriptor.directory.appendingPathComponent("home", isDirectory: true)
            if FileManager.default.fileExists(atPath: homeOverlay.path) {
                let overlayActions = try overlayDirectory(from: homeOverlay, to: targetHome)
                actions.append(contentsOf: overlayActions)
            }
        }
        
        if let term = profile.terminal {
            try applyTerminalConfig(term, base: descriptor.directory)
        }
        
        if let ide = profile.ide {
            try applyIDEConfig(ide, base: descriptor.directory)
        }
        
        if let scriptRel = profile.startupScript {
            let scriptURL = descriptor.directory.appendingPathComponent(scriptRel)
            try runScript(scriptURL)
        }
        
        ApplyRecordStore.save(ApplyRecord(timestamp: Date(), actions: actions), to: descriptor.directory)
        
        setActiveProfile(descriptor)
    }
    
    func applyProfileAsync(_ descriptor: ProfileDescriptor, cleanConfig: Bool = false) async throws {
        while ApplyActivity.isApplying {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        await MainActor.run {
            self.isApplying = true
        }
        
        ApplyActivity.begin()
        
        defer {
            ApplyActivity.end()
            Task { @MainActor in
                self.isApplying = false
            }
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    
                    var actions: [ApplyAction] = []
                    let profile = descriptor.profile
                    
                    if let wallpaperRel = profile.wallpaper {
                        let url = descriptor.directory.appendingPathComponent(wallpaperRel)
                        LoggerService.info("Profile specifies wallpaper: '\(wallpaperRel)' -> Full path: \(url.path)")
                        try self.applyWallpaper(url: url)
                    } else {
                        LoggerService.info("Profile has no wallpaper specified")
                    }
                    
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    
                    try self.applyCodeEditorSettings(from: descriptor)
                    
                    self.fileSystemService.renderTemplates(for: descriptor)
                    
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    
                    let targetHome = URL(fileURLWithPath: NSHomeDirectory())
                    
                    if cleanConfig {
                        try self.backupAndCleanConfig(atHome: targetHome)
                    }
                    
                    if let replacements = profile.replacements, !replacements.isEmpty {
                        for repl in replacements {
                            let src = descriptor.directory.appendingPathComponent(repl.source)
                            let dst = URL(fileURLWithPath: repl.destination.expandingTildeInPath)
                            let action = try self.replaceFile(source: src, destination: dst)
                            actions.append(action)
                        }
                    } else {
                        let homeOverlay = descriptor.directory.appendingPathComponent("home", isDirectory: true)
                        if FileManager.default.fileExists(atPath: homeOverlay.path) {
                            let overlayActions = try self.overlayDirectory(from: homeOverlay, to: targetHome)
                            actions.append(contentsOf: overlayActions)
                        }
                    }
                    
                    if let term = profile.terminal {
                        try self.applyTerminalConfig(term, base: descriptor.directory)
                    }
                    
                    if let ide = profile.ide {
                        try self.applyIDEConfig(ide, base: descriptor.directory)
                    }
                    
                    if let scriptRel = profile.startupScript {
                        let scriptURL = descriptor.directory.appendingPathComponent(scriptRel)
                        try self.runScript(scriptURL)
                    }
                    
                    ApplyRecordStore.save(ApplyRecord(timestamp: Date(), actions: actions), to: descriptor.directory)
                    
                    self.setActiveProfile(descriptor)
                    
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func revertLastApply(for descriptor: ProfileDescriptor) throws {
        guard let record = ApplyRecordStore.load(from: descriptor.directory) else { return }
        let fm = FileManager.default
        
        for action in record.actions {
            let dest = URL(fileURLWithPath: action.destination)
            if let backup = action.backup.map({ URL(fileURLWithPath: $0) }), fm.fileExists(atPath: backup.path) {
                if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                try fm.moveItem(at: backup, to: dest)
            } else {
                try? fm.removeItem(at: dest)
            }
        }
    }
    
    
    func setActiveProfile(_ descriptor: ProfileDescriptor?) {
        LoggerService.info("Setting active profile: \(descriptor?.profile.name ?? "nil")")
        
        if Thread.isMainThread {
            self.activeProfile = descriptor
        } else {
            DispatchQueue.main.sync {
                self.activeProfile = descriptor
            }
        }
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        
        Task.detached(priority: .background) {
            if let descriptor = descriptor {
                UserDefaults.standard.set(descriptor.directory.path, forKey: self.userDefaultsKey)
                LoggerService.info("Profile '\(descriptor.profile.name)' saved to UserDefaults")
            } else {
                UserDefaults.standard.removeObject(forKey: self.userDefaultsKey)
                LoggerService.info("Active profile cleared from UserDefaults")
            }
        }
    }
    
    
    func saveProfile(_ profile: Profile, at directory: URL) throws {
        let jsonURL = directory.appendingPathComponent("profile.json")
        try FileSystemUtilities.writeJSON(profile, to: jsonURL)
        invalidateCache(directory: directory)
    }
    
    func updateWallpaper(for descriptor: ProfileDescriptor, from sourceURL: URL) throws -> ProfileDescriptor {
        let fm = FileManager.default
        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let baseName = "wallpaper"
        var dest = descriptor.directory.appendingPathComponent("\(baseName).\(ext)")
        var idx = 2
        
        while fm.fileExists(atPath: dest.path) {
            dest = descriptor.directory.appendingPathComponent("\(baseName)-\(idx).\(ext)")
            idx += 1
        }
        
        try fileSystemService.copyFile(from: sourceURL, to: dest, createBackup: false)
        
        var updated = descriptor.profile
        updated.wallpaper = dest.lastPathComponent
        try saveProfile(updated, at: descriptor.directory)
        
        reload()
        
        let newDesc = profiles.first(where: { $0.directory == descriptor.directory }) ?? ProfileDescriptor(profile: updated, directory: descriptor.directory)
        return newDesc
    }
    
    
    private func startWatching() {
        stopWatching()
        let root = profilesRoot()
        let paths = [root.path] as CFArray
        var context = FSEventStreamContext(version: 0, info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        
        stream = FSEventStreamCreate(nil, { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            let profileService = Unmanaged<ProfileService>.fromOpaque(clientCallBackInfo!).takeUnretainedValue()
            let evPaths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
            var changed: [String] = []
            
            for i in 0..<numEvents {
                if let cstr = evPaths[Int(i)] {
                    let path = String(cString: cstr)
                    if path.contains("/\(Constants.alacrittyDirRelative)/") { continue }
                    changed.append(path)
                }
            }
            
            DispatchQueue.main.async {
                profileService.debounceTimer?.invalidate()
                profileService.debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                    profileService.handleFileSystemChanges(changed)
                }
            }
        }, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags)
        
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }
    
    private func stopWatching() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamSetDispatchQueue(stream, nil)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }
    
    private func handleFileSystemChanges(_ changedPaths: [String]) {
        let activeDir = activeProfile?.directory.path
        
        if let activeDir, changedPaths.contains(where: { $0.hasPrefix(activeDir) }) {
            guard !ApplyActivity.isApplying && !ApplyActivity.recentlyApplied(within: 2.0) else { return }
            guard let active = activeProfile else { return }
            
            Task {
                do {
                    try await self.applyProfileAsync(active, cleanConfig: false)
                } catch {
                    LoggerService.error("Auto-apply failed: \(error)")
                }
            }
        } else {
            LoggerService.info("File system watcher triggering reload due to changes: \(changedPaths)")
            reload()
        }
    }
    
    
    private func getProfileFromCache(at directory: URL) -> Profile? {
        return cacheQueue.sync {
            if let cached = profileCache[directory],
               cached.isValid,
               isFileUnchanged(at: directory, lastKnownDate: cached.fileModificationDate) {
                return cached.profile
            }
            
            if let profile = loadProfileFromDisk(at: directory) {
                cacheProfile(profile, at: directory)
                return profile
            }
            
            return nil
        }
    }
    
    private func invalidateCache(directory: URL) {
        cacheQueue.async { [weak self] in
            self?.profileCache.removeValue(forKey: directory)
            self?.lastModificationDates.removeValue(forKey: directory)
        }
    }
    
    private func cacheProfile(_ profile: Profile, at directory: URL) {
        let modificationDate = getModificationDate(for: directory)
        let cached = CachedProfile(
            profile: profile,
            cachedAt: Date(),
            fileModificationDate: modificationDate
        )
        
        profileCache[directory] = cached
        lastModificationDates[directory] = modificationDate
    }
    
    private func isFileUnchanged(at directory: URL, lastKnownDate: Date) -> Bool {
        let currentDate = getModificationDate(for: directory)
        return currentDate <= lastKnownDate
    }
    
    private func getModificationDate(for directory: URL) -> Date {
        for fileName in Constants.profileFileCandidates {
            let url = directory.appendingPathComponent(fileName)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let modificationDate = attributes[.modificationDate] as? Date {
                return modificationDate
            }
        }
        
        if let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
           let modificationDate = attributes[.modificationDate] as? Date {
            return modificationDate
        }
        
        return Date.distantPast
    }
}


private extension ProfileService {
    
    func profilesRoot() -> URL {
        return ConfigAccess.defaultRoot
    }
    
    func ensureProfilesRoot() {
        do {
            try ConfigAccess.ensureDirectoriesExist()
        } catch {
            LoggerService.error("Failed to create profiles directory: \(error)")
        }
    }
    
    func loadActiveProfileFromDefaults() {
        if let path = UserDefaults.standard.string(forKey: userDefaultsKey) {
            let url = URL(fileURLWithPath: path)
            if !FileManager.default.fileExists(atPath: url.path) {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        }
    }
    
    private func restoreActiveProfileFromDefaults() {
        guard let path = UserDefaults.standard.string(forKey: userDefaultsKey) else { 
            LoggerService.info("No active profile path in UserDefaults")
            return 
        }
        let url = URL(fileURLWithPath: path)
        
        LoggerService.info("Restoring active profile from UserDefaults: \(url.lastPathComponent)")
        
        if let descriptor = profiles.first(where: { $0.directory == url }) {
            LoggerService.info("Found matching profile, setting as active: \(descriptor.profile.name)")
            activeProfile = descriptor
        } else {
            LoggerService.warning("Profile no longer exists, clearing UserDefaults: \(url.lastPathComponent)")
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }
    
    func sanitizeProfileName(_ name: String) -> String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
    }
    
    func loadProfile(at directory: URL) -> Profile? {
        if let cached = getProfileFromCache(at: directory) {
            return cached
        }
        
        return loadProfileFromDisk(at: directory)
    }
    
    func loadProfileFromDisk(at directory: URL) -> Profile? {
        for name in Constants.profileFileCandidates {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    if name.hasSuffix(".json") {
                        var p = try JSONDecoder().decode(Profile.self, from: data)
                        if p.wallpaper == nil, let auto = firstImage(in: directory) { p.wallpaper = auto.lastPathComponent }
                        if p.hotkey == nil, let hk = readHotkey(at: directory) { p.hotkey = hk }
                        return p
                    } else {
                        #if canImport(Yams)
                        let str = String(decoding: data, as: UTF8.self)
                        var p = try YAMLDecoder().decode(Profile.self, from: str)
                        if p.wallpaper == nil, let auto = firstImage(in: directory) { p.wallpaper = auto.lastPathComponent }
                        if p.hotkey == nil, let hk = readHotkey(at: directory) { p.hotkey = hk }
                        return p
                        #else
                        var p = try JSONDecoder().decode(Profile.self, from: data)
                        if p.wallpaper == nil, let auto = firstImage(in: directory) { p.wallpaper = auto.lastPathComponent }
                        if p.hotkey == nil, let hk = readHotkey(at: directory) { p.hotkey = hk }
                        return p
                        #endif
                    }
                } catch {
                    LoggerService.error("Failed to load profile at \(directory.lastPathComponent): \(error)")
                }
            }
        }
        return nil
    }
    
    func defaultProfile(for directory: URL) -> Profile {
        var p = Profile(name: directory.lastPathComponent)
        if let hk = readHotkey(at: directory) { p.hotkey = hk }
        if let wp = firstImage(in: directory) { p.wallpaper = wp.lastPathComponent }
        return p
    }
    
    func readHotkey(at directory: URL) -> String? {
        let url = directory.appendingPathComponent("hotkey.txt")
        guard let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) else { return nil }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func firstImage(in directory: URL) -> URL? {
        let fm = FileManager.default
        let exts = Array(Constants.wallpaperExtensions)
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: []) else { 
            LoggerService.warning("Could not read directory contents: \(directory.path)")
            return nil 
        }
        
        LoggerService.info("Looking for wallpaper in \(directory.lastPathComponent), found \(items.count) items")
        
        let imageFiles = items.filter { exts.contains($0.pathExtension.lowercased()) }
        LoggerService.info("Found \(imageFiles.count) image files: \(imageFiles.map { $0.lastPathComponent }.joined(separator: ", "))")
        
        let preferredPrefixes = Constants.preferredWallpaperPrefixes
        if let preferred = items.first(where: { url in
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            let hasPreferredName = preferredPrefixes.contains(where: { name.hasPrefix($0) })
            let hasValidExt = exts.contains(url.pathExtension.lowercased())
            return hasValidExt && hasPreferredName
        }) {
            LoggerService.info("Selected preferred wallpaper: \(preferred.lastPathComponent)")
            return preferred
        }
        
        if let firstImage = items.first(where: { exts.contains($0.pathExtension.lowercased()) }) {
            LoggerService.info("Selected first available image: \(firstImage.lastPathComponent)")
            return firstImage
        }
        
        LoggerService.info("No wallpaper images found in directory")
        return nil
    }
    
    func saveProfileToJSON(_ profile: Profile, at url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(profile)
        try data.write(to: url, options: .atomic)
    }
    
    
    func snapshotCurrentConfiguration(to descriptor: ProfileDescriptor) throws {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let src = home.appendingPathComponent(".config", isDirectory: true)
        let dst = descriptor.directory.appendingPathComponent("home/.config", isDirectory: true)
        var isDir: ObjCBool = false
        
        if FileManager.default.fileExists(atPath: src.path, isDirectory: &isDir), isDir.boolValue {
            try copyDirectoryRecursively(from: src, to: dst)
        }
        
        try snapshotIDEConfigurations(to: descriptor, home: home)
    }
    
    func snapshotIDEConfigurations(to descriptor: ProfileDescriptor, home: URL) throws {
        let fm = FileManager.default
        
        let vscodeConfigDir = home.appendingPathComponent(Constants.vscodeConfigDir, isDirectory: true)
        if fm.fileExists(atPath: vscodeConfigDir.path) {
            let vscodeSnapshotDir = descriptor.directory.appendingPathComponent("vscode", isDirectory: true)
            try copyIDEConfigForSnapshot(from: vscodeConfigDir, to: vscodeSnapshotDir, ideType: .vscode)
        }
        
        let cursorConfigDir = home.appendingPathComponent(Constants.cursorConfigDir, isDirectory: true)
        if fm.fileExists(atPath: cursorConfigDir.path) {
            let cursorSnapshotDir = descriptor.directory.appendingPathComponent("cursor", isDirectory: true)
            try copyIDEConfigForSnapshot(from: cursorConfigDir, to: cursorSnapshotDir, ideType: .cursor)
        }
    }
    
    func copyIDEConfigForSnapshot(from srcDir: URL, to dstDir: URL, ideType: Constants.IDEType) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        
        let essentialFiles = [
            ideType.settingsFile,
            ideType.keybindingsFile
        ]
        
        for fileName in essentialFiles {
            let src = srcDir.appendingPathComponent(fileName)
            let dst = dstDir.appendingPathComponent(fileName)
            
            if fm.fileExists(atPath: src.path) {
                try fileSystemService.copyFile(from: src, to: dst, createBackup: false)
            }
        }
        
        let snippetsDir = srcDir.appendingPathComponent(ideType.snippetsDirectory, isDirectory: true)
        if fm.fileExists(atPath: snippetsDir.path) {
            let snippetsDst = dstDir.appendingPathComponent(ideType.snippetsDirectory, isDirectory: true)
            try copyDirectoryRecursively(from: snippetsDir, to: snippetsDst)
        }
    }
    
    func backupAndCleanConfig(atHome home: URL) throws {
        let fm = FileManager.default
        let configDir = home.appendingPathComponent(".config", isDirectory: true)
        var isDir: ObjCBool = false
        
        if fm.fileExists(atPath: configDir.path, isDirectory: &isDir), isDir.boolValue {
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = home.appendingPathComponent(".config.ricebar-backup-\(timestamp)", isDirectory: true)
            try? fm.removeItem(at: backup)
            try fm.moveItem(at: configDir, to: backup)
        }
        
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
    }
    
    func applyWallpaper(url: URL) throws {
        LoggerService.info("Attempting to apply wallpaper: \(url.path)")
        
        guard FileManager.default.fileExists(atPath: url.path) else { 
            LoggerService.error("Wallpaper file not found: \(url.path)")
            throw ProfileServiceError.fileNotFound(url.path) 
        }
        
        LoggerService.info("Wallpaper file exists, attempting to set for \(NSScreen.screens.count) screens")
        
        var lastError: Error?
        var successCount = 0
        
        for (index, screen) in NSScreen.screens.enumerated() {
            do {
                LoggerService.info("Setting wallpaper for screen \(index + 1)")
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                successCount += 1
                LoggerService.info("Successfully set wallpaper for screen \(index + 1)")
            } catch {
                lastError = error
                LoggerService.error("Wallpaper set failed for screen \(index + 1): \(error.localizedDescription)")
            }
        }
        
        if successCount == 0 {
            LoggerService.warning("All screens failed, trying AppleScript fallback")
            let script = """
            tell application "System Events"
              tell every desktop
                set picture to "\(url.path)"
              end tell
            end tell
            """
            var errorDict: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                LoggerService.info("Executing AppleScript wallpaper command")
                appleScript.executeAndReturnError(&errorDict)
                if let errorDict { 
                    LoggerService.error("AppleScript wallpaper error: \(errorDict)") 
                    throw ProfileServiceError.wallpaperSetFailed(NSError(domain: "AppleScript", code: -1, userInfo: [NSLocalizedDescriptionKey: "AppleScript failed: \(errorDict)"]))
                } else {
                    LoggerService.info("AppleScript wallpaper command executed successfully")
                }
            } else {
                LoggerService.error("Failed to create AppleScript")
                throw ProfileServiceError.wallpaperSetFailed(NSError(domain: "AppleScript", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create AppleScript"]))
            }
        } else {
            LoggerService.info("Wallpaper applied successfully to \(successCount)/\(NSScreen.screens.count) screens")
        }
    }
    
    @discardableResult
    func replaceFile(source: URL, destination: URL) throws -> ApplyAction {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { 
            throw ProfileServiceError.fileNotFound(source.path) 
        }
        
        try fileSystemService.ensureParentDirectoryExists(for: destination)
        
        var backupPath: String? = nil
        var kind: ApplyAction.Kind = .created
        
        if fm.fileExists(atPath: destination.path) {
            if fm.contentsEqual(atPath: source.path, andPath: destination.path) {
                return ApplyAction(kind: .updated, source: source.path, destination: destination.path, backup: nil)
            }
            
            let backup = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".bak")
            try? fm.removeItem(at: backup)
            try fm.moveItem(at: destination, to: backup)
            backupPath = backup.path
            kind = .updated
        }
        
        try fm.copyItem(at: source, to: destination)
        touchIfNeededForReload(destination)
        
        return ApplyAction(kind: kind, source: source.path, destination: destination.path, backup: backupPath)
    }
    
    func overlayDirectory(from sourceDir: URL, to targetDir: URL) throws -> [ApplyAction] {
        let fm = FileManager.default
        var actions: [ApplyAction] = []
        
        guard let enumerator = fm.enumerator(at: sourceDir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return actions }
        
        for case let fileURL as URL in enumerator {
            let relPath = fileURL.path.replacingOccurrences(of: sourceDir.path + "/", with: "")
            let dstURL = targetDir.appendingPathComponent(relPath)
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            let name = fileURL.lastPathComponent
            
            if isDir.boolValue {
                if shouldSkipInSnapshot(name: name) {
                    (enumerator as AnyObject).skipDescendants?()
                    continue
                }
                autoreleasepool { try? fm.createDirectory(at: dstURL, withIntermediateDirectories: true) }
            } else {
                if shouldSkipInSnapshot(name: name) { continue }
                autoreleasepool {
                    if let action = try? replaceFile(source: fileURL, destination: dstURL) {
                        actions.append(action)
                    }
                }
            }
        }
        
        return actions
    }
    
    func copyDirectoryRecursively(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        
        guard let enumerator = fm.enumerator(at: src, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        
        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            let name = fileURL.lastPathComponent
            
            if shouldSkipInSnapshot(name: name) {
                if isDir.boolValue { (enumerator as AnyObject).skipDescendants?() }
                continue
            }
            
            let rel = fileURL.path.replacingOccurrences(of: src.path + "/", with: "")
            let target = dst.appendingPathComponent(rel)
            
            if isDir.boolValue {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fileSystemService.copyFile(from: fileURL, to: target, createBackup: false)
            }
        }
    }
    
    func shouldSkipInSnapshot(name: String) -> Bool {
        if name == ".DS_Store" { return true }
        if name.hasSuffix(".bak") { return true }
        if name.hasPrefix("alacritty.ricebar-backup-") { return true }
        return false
    }
    
    func touchIfNeededForReload(_ destination: URL) {
        let path = destination.path
        guard path.contains("/\(Constants.alacrittyDirRelative)/") else { return }
        
        let now = Date()
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: path)
        
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let ymlPath = home.appendingPathComponent("\(Constants.alacrittyDirRelative)/\(Constants.alacrittyYml)").path
        let tomlPath = home.appendingPathComponent("\(Constants.alacrittyDirRelative)/\(Constants.alacrittyToml)").path
        
        if FileManager.default.fileExists(atPath: ymlPath) {
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: ymlPath)
        }
        if FileManager.default.fileExists(atPath: tomlPath) {
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: tomlPath)
        }
        
        fileSystemService.reloadAlacritty()
    }
    
    func applyTerminalConfig(_ terminal: Profile.Terminal, base: URL) throws {
        switch terminal.kind {
        case .alacritty:
            let home = URL(fileURLWithPath: NSHomeDirectory())
            if let themeRel = terminal.theme {
                let src = base.appendingPathComponent(themeRel)
                let keptExt = try copyAlacrittyConfig(from: src, toHome: home)
                archiveAlternateAlacrittyConfig(keepExt: keptExt, home: home)
            } else if let auto = findDefaultAlacrittyTheme(in: base) {
                let keptExt = try copyAlacrittyConfig(from: auto, toHome: home)
                archiveAlternateAlacrittyConfig(keepExt: keptExt, home: home)
            }
        case .terminalApp:
            break
        case .iterm2:
            break
        }
    }
    
    func findDefaultAlacrittyTheme(in base: URL) -> URL? {
        let fm = FileManager.default
        let candidates = [
            base.appendingPathComponent("alacritty.yml"),
            base.appendingPathComponent("alacritty.toml"),
            base.appendingPathComponent("alacritty/alacritty.yml"),
            base.appendingPathComponent("alacritty/alacritty.toml"),
        ]
        
        for url in candidates {
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
    
    @discardableResult
    func copyAlacrittyConfig(from src: URL, toHome home: URL) throws -> String {
        let ext = src.pathExtension.lowercased()
        let dstName = (ext == "toml") ? "alacritty.toml" : "alacritty.yml"
        let dst = home.appendingPathComponent(".config/alacritty/\(dstName)")
        _ = try replaceFile(source: src, destination: dst)
        return (ext == "toml") ? "toml" : "yml"
    }
    
    func archiveAlternateAlacrittyConfig(keepExt: String, home: URL) {
        let fm = FileManager.default
        let dir = home.appendingPathComponent(".config/alacritty", isDirectory: true)
        let altName = (keepExt == "toml") ? "alacritty.yml" : "alacritty.toml"
        let alt = dir.appendingPathComponent(altName)
        
        guard fm.fileExists(atPath: alt.path) else { return }
        
        try? fm.createDirectory(at: ConfigAccess.backupsRoot, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = ConfigAccess.backupsRoot.appendingPathComponent("alacritty_\(altName).\(timestamp)")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: alt, to: backup)
    }
    
    func applyIDEConfig(_ ide: Profile.IDE, base: URL) throws {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        
        switch ide.kind {
        case .vscode:
            try applyVSCodeConfig(ide, base: base, home: home)
        case .cursor:
            try applyCursorConfig(ide, base: base, home: home)
        }
    }
    
    func applyVSCodeConfig(_ ide: Profile.IDE, base: URL, home: URL) throws {
        let ideType = Constants.IDEType.vscode
        let configDir = home.appendingPathComponent(ideType.configDirectory, isDirectory: true)
        
        if let themeSpec = ide.theme {
            if themeSpec.hasPrefix("@id:") {
                let themeId = String(themeSpec.dropFirst(4))
                try applyBuiltInTheme(themeId: themeId, ideType: ideType, configDir: configDir)
            } else {
                let src = base.appendingPathComponent(themeSpec)
                try applyIDESettings(from: src, to: configDir, ideType: ideType)
            }
        } else {
            if let defaultConfig = findDefaultIDEConfig(in: base, for: ideType) {
                try applyIDESettings(from: defaultConfig, to: configDir, ideType: ideType)
            }
        }
        
        if let extensions = ide.extensions, !extensions.isEmpty {
            try installVSCodeExtensions(extensions)
        }
    }
    
    func applyCursorConfig(_ ide: Profile.IDE, base: URL, home: URL) throws {
        let ideType = Constants.IDEType.cursor
        let configDir = home.appendingPathComponent(ideType.configDirectory, isDirectory: true)
        
        if let themeSpec = ide.theme {
            if themeSpec.hasPrefix("@id:") {
                let themeId = String(themeSpec.dropFirst(4))
                try applyBuiltInTheme(themeId: themeId, ideType: ideType, configDir: configDir)
            } else {
                let src = base.appendingPathComponent(themeSpec)
                try applyIDESettings(from: src, to: configDir, ideType: ideType)
            }
        } else {
            if let defaultConfig = findDefaultIDEConfig(in: base, for: ideType) {
                try applyIDESettings(from: defaultConfig, to: configDir, ideType: ideType)
            }
        }
        
        if let extensions = ide.extensions, !extensions.isEmpty {
            try installCursorExtensions(extensions)
        }
    }
    
    func applyBuiltInTheme(themeId: String, ideType: Constants.IDEType, configDir: URL) throws {
        let availableThemes = try discoverAvailableThemes(for: ideType)
        
        guard let theme = availableThemes.first(where: { $0.name == themeId }) else {
            throw ProfileServiceError.fileNotFound("Theme '\(themeId)' not found in installed \(ideType.displayName) themes")
        }
        
        let fm = FileManager.default
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        try applyDiscoveredThemeToSettings(theme: theme, configDir: configDir, ideType: ideType)
        
        LoggerService.info("Applied theme '\(theme.displayName)' to \(ideType.displayName)")
    }
    
    func discoverAvailableThemes(for ideType: Constants.IDEType) throws -> [Constants.DiscoveredTheme] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let configDir = home.appendingPathComponent(ideType.configDirectory, isDirectory: true)
        
        var themes: [Constants.DiscoveredTheme] = []
        
        themes.append(contentsOf: getBuiltInThemes())
        
        let extensionsDir = configDir.appendingPathComponent("extensions", isDirectory: true)
        if FileManager.default.fileExists(atPath: extensionsDir.path) {
            themes.append(contentsOf: try discoverExtensionThemes(in: extensionsDir))
        }
        
        return themes
    }
    
    func getBuiltInThemes() -> [Constants.DiscoveredTheme] {
        return [
            Constants.DiscoveredTheme(
                name: "Default Dark+",
                displayName: "Dark+ (default dark)",
                extensionId: nil,
                source: .builtin
            ),
            Constants.DiscoveredTheme(
                name: "Default Light+",
                displayName: "Light+ (default light)",
                extensionId: nil,
                source: .builtin
            ),
            Constants.DiscoveredTheme(
                name: "Red",
                displayName: "Red",
                extensionId: nil,
                source: .builtin
            ),
            Constants.DiscoveredTheme(
                name: "Solarized Dark",
                displayName: "Solarized Dark",
                extensionId: nil,
                source: .builtin
            ),
            Constants.DiscoveredTheme(
                name: "Solarized Light",
                displayName: "Solarized Light",
                extensionId: nil,
                source: .builtin
            )
        ]
    }
    
    func discoverExtensionThemes(in extensionsDir: URL) throws -> [Constants.DiscoveredTheme] {
        let fm = FileManager.default
        var themes: [Constants.DiscoveredTheme] = []
        
        guard let extensionDirs = try? fm.contentsOfDirectory(at: extensionsDir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            return themes
        }
        
        for extensionDir in extensionDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: extensionDir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            
            let packageJsonPath = extensionDir.appendingPathComponent("package.json")
            guard fm.fileExists(atPath: packageJsonPath.path) else { continue }
            
            do {
                let packageData = try Data(contentsOf: packageJsonPath)
                guard let packageJson = try JSONSerialization.jsonObject(with: packageData) as? [String: Any] else { continue }
                
                if let contributes = packageJson["contributes"] as? [String: Any],
                   let extensionThemes = contributes["themes"] as? [[String: Any]] {
                    
                    let extensionId = packageJson["name"] as? String ?? extensionDir.lastPathComponent
                    
                    for themeInfo in extensionThemes {
                        if let label = themeInfo["label"] as? String {
                            themes.append(Constants.DiscoveredTheme(
                                name: label,
                                displayName: label,
                                extensionId: extensionId,
                                source: .extensionSource(path: extensionDir.path)
                            ))
                        }
                    }
                }
            } catch {
                LoggerService.warning("Failed to parse package.json for \(extensionDir.lastPathComponent): \(error)")
            }
        }
        
        return themes
    }
    
    func applyDiscoveredThemeToSettings(theme: Constants.DiscoveredTheme, configDir: URL, ideType: Constants.IDEType) throws {
        let settingsFile = configDir.appendingPathComponent(ideType.settingsFile)
        
        var settings: [String: Any] = [:]
        
        if FileManager.default.fileExists(atPath: settingsFile.path) {
            do {
                let data = try Data(contentsOf: settingsFile)
                if let existingSettings = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    settings = existingSettings
                }
            } catch {
                LoggerService.warning("Failed to load existing settings, creating new ones: \(error)")
            }
        }
        
        settings["workbench.colorTheme"] = theme.name
        
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsFile, options: .atomic)
        } catch {
            throw ProfileServiceError.fileOperationFailed("write settings", error)
        }
    }
    
    func getAvailableThemes(for ideType: Constants.IDEType) -> [Constants.DiscoveredTheme] {
        do {
            let themes = try discoverAvailableThemes(for: ideType)
            LoggerService.info("Found \(themes.count) themes for \(ideType.displayName):")
            for theme in themes {
                LoggerService.info("  - \(theme.name) (\(theme.source))")
            }
            return themes
        } catch {
            LoggerService.error("Failed to discover themes for \(ideType.displayName): \(error)")
            return []
        }
    }
    
    func findDefaultIDEConfig(in base: URL, for ideType: Constants.IDEType) -> URL? {
        let fm = FileManager.default
        let candidates = [
            base.appendingPathComponent(ideType.settingsFile),
            base.appendingPathComponent("vscode/\(ideType.settingsFile)"),
            base.appendingPathComponent("ide/\(ideType.settingsFile)"),
            base.appendingPathComponent("settings/\(ideType.settingsFile)")
        ]
        
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }
    
    func applyIDESettings(from src: URL, to configDir: URL, ideType: Constants.IDEType) throws {
        let fm = FileManager.default
        
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        let settingsDst = configDir.appendingPathComponent(ideType.settingsFile)
        _ = try replaceFile(source: src, destination: settingsDst)
        
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: src.path, isDirectory: &isDir), isDir.boolValue {
            try copyIDEConfigDirectory(from: src, to: configDir, ideType: ideType)
        }
    }
    
    func copyIDEConfigDirectory(from srcDir: URL, to dstDir: URL, ideType: Constants.IDEType) throws {
        let fm = FileManager.default
        
        guard let enumerator = fm.enumerator(at: srcDir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return }
        
        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: srcDir.path + "/", with: "")
            let dstURL = dstDir.appendingPathComponent(relativePath)
            
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            
            if isDir.boolValue {
                try fm.createDirectory(at: dstURL, withIntermediateDirectories: true)
            } else {
                let fileName = fileURL.lastPathComponent
                if shouldSkipIDEFile(fileName) { continue }
                
                _ = try replaceFile(source: fileURL, destination: dstURL)
            }
        }
    }
    
    func shouldSkipIDEFile(_ fileName: String) -> Bool {
        let skipPatterns = [
            ".DS_Store",
            "*.bak",
            "*.tmp",
            "*.log",
            "workspace.json",  // VS Code workspace-specific settings
            "tasks.json"       // VS Code tasks (usually project-specific)
        ]
        
        for pattern in skipPatterns {
            if pattern.hasPrefix("*") {
                let suffix = String(pattern.dropFirst())
                if fileName.hasSuffix(suffix) { return true }
            } else if fileName == pattern {
                return true
            }
        }
        
        return false
    }
    
    func installVSCodeExtensions(_ extensions: [String]) throws {
        guard isVSCodeInstalled() else {
            LoggerService.warning("VS Code not found, skipping extension installation")
            return
        }
        
        for extensionId in extensions {
            try installVSCodeExtension(extensionId)
        }
    }
    
    func isVSCodeInstalled() -> Bool {
        let fm = FileManager.default
        let commonPaths = [
            "/Applications/Visual Studio Code.app",
            "/usr/local/bin/code"
        ]
        
        return commonPaths.contains { fm.fileExists(atPath: $0) }
    }
    
    func installVSCodeExtension(_ extensionId: String) throws {
        guard let codePath = findVSCodeCLI() else {
            LoggerService.warning("VS Code CLI not found, cannot install extension: \(extensionId)")
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codePath)
        process.arguments = ["--install-extension", extensionId]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                LoggerService.info("Successfully installed VS Code extension: \(extensionId)")
            } else {
                LoggerService.warning("Failed to install VS Code extension: \(extensionId)")
            }
        } catch {
            LoggerService.warning("Failed to install VS Code extension \(extensionId): \(error)")
        }
    }
    
    func findVSCodeCLI() -> String? {
        let fm = FileManager.default
        let paths = [
            "/usr/local/bin/code",
            "/opt/homebrew/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
        ]
        
        return paths.first { fm.fileExists(atPath: $0) }
    }
    
    func installCursorExtensions(_ extensions: [String]) throws {
        guard isCursorInstalled() else {
            LoggerService.warning("Cursor not found, skipping extension installation")
            return
        }
        
        for extensionId in extensions {
            try installCursorExtension(extensionId)
        }
    }
    
    func isCursorInstalled() -> Bool {
        let fm = FileManager.default
        let commonPaths = [
            "/Applications/Cursor.app",
            "/usr/local/bin/cursor"
        ]
        
        return commonPaths.contains { fm.fileExists(atPath: $0) }
    }
    
    func installCursorExtension(_ extensionId: String) throws {
        guard let cursorPath = findCursorCLI() else {
            LoggerService.warning("Cursor CLI not found, cannot install extension: \(extensionId)")
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cursorPath)
        process.arguments = ["--install-extension", extensionId]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                LoggerService.info("Successfully installed Cursor extension: \(extensionId)")
            } else {
                LoggerService.warning("Failed to install Cursor extension: \(extensionId)")
            }
        } catch {
            LoggerService.warning("Failed to install Cursor extension \(extensionId): \(error)")
        }
    }
    
    func findCursorCLI() -> String? {
        let fm = FileManager.default
        let paths = [
            "/usr/local/bin/cursor",
            "/opt/homebrew/bin/cursor",
            "/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
        ]
        
        return paths.first { fm.fileExists(atPath: $0) }
    }
    
    func runScript(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { 
            throw ProfileServiceError.fileNotFound(url.path) 
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.currentDirectoryURL = url.deletingLastPathComponent()
        let quotedPath = "'\(url.path.replacingOccurrences(of: "'", with: "'\\''"))'"
        process.arguments = ["-lc", quotedPath]
        try process.run()
    }
    
    func getCurrentWallpaper() -> URL? {
        guard let mainScreen = NSScreen.main else { return nil }
        
        do {
            guard let wallpaperURL = try NSWorkspace.shared.desktopImageURL(for: mainScreen) else {
                LoggerService.warning("Desktop image URL returned nil for main screen")
                return nil
            }
            
            if FileManager.default.fileExists(atPath: wallpaperURL.path) {
                LoggerService.info("Found current wallpaper: \(wallpaperURL.path)")
                return wallpaperURL
            } else {
                LoggerService.warning("Current wallpaper file not accessible: \(wallpaperURL.path)")
                return nil
            }
        } catch {
            LoggerService.error("Failed to get current wallpaper: \(error)")
            
            return getCurrentWallpaperViaAppleScript()
        }
    }
    
    private func getCurrentWallpaperViaAppleScript() -> URL? {
        let script = """
        tell application "System Events"
            tell current desktop
                get picture
            end tell
        end tell
        """
        
        var errorDict: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        
        let result = appleScript.executeAndReturnError(&errorDict)
        
        if let errorDict = errorDict {
            LoggerService.error("AppleScript wallpaper error: \(errorDict)")
            return nil
        }
        
        guard let wallpaperPath = result.stringValue, !wallpaperPath.isEmpty else {
            LoggerService.warning("No wallpaper path returned from AppleScript")
            return nil
        }
        
        let wallpaperURL = URL(fileURLWithPath: wallpaperPath)
        if FileManager.default.fileExists(atPath: wallpaperURL.path) {
            LoggerService.info("Found current wallpaper via AppleScript: \(wallpaperPath)")
            return wallpaperURL
        } else {
            LoggerService.warning("Wallpaper from AppleScript not accessible: \(wallpaperPath)")
            return nil
        }
    }
    
    
    private func captureCodeEditorSettings(to descriptor: ProfileDescriptor) throws {
        let fm = FileManager.default
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        
        let vscodeDir = descriptor.directory.appendingPathComponent("vscode", isDirectory: true)
        try fm.createDirectory(at: vscodeDir, withIntermediateDirectories: true)
        
        let vscodeAppSupportPath = homeURL.appendingPathComponent("Library/Application Support/Code")
        let vscodeExtensionsPath = homeURL.appendingPathComponent(".vscode/extensions")
        
        let cursorAppSupportPath = homeURL.appendingPathComponent("Library/Application Support/Cursor")
        
        if fm.fileExists(atPath: vscodeAppSupportPath.path) {
            try captureEditorSettings(
                from: vscodeAppSupportPath,
                extensionsPath: vscodeExtensionsPath,
                to: vscodeDir.appendingPathComponent("vscode", isDirectory: true),
                editorName: "VS Code"
            )
        }
        
        if fm.fileExists(atPath: cursorAppSupportPath.path) {
            try captureEditorSettings(
                from: cursorAppSupportPath,
                extensionsPath: nil, // Cursor extensions are in Application Support
                to: vscodeDir.appendingPathComponent("cursor", isDirectory: true),
                editorName: "Cursor"
            )
        }
        
        LoggerService.info("Captured VS Code/Cursor settings for profile: \(descriptor.profile.name)")
    }
    
    private func captureEditorSettings(from appSupportPath: URL, extensionsPath: URL?, to destination: URL, editorName: String) throws {
        let fm = FileManager.default
        
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        
        let userPath = appSupportPath.appendingPathComponent("User")
        if fm.fileExists(atPath: userPath.path) {
            let userDest = destination.appendingPathComponent("User")
            
            let settingsFile = userPath.appendingPathComponent("settings.json")
            if fm.fileExists(atPath: settingsFile.path) {
                let settingsDest = userDest.appendingPathComponent("settings.json")
                try fm.createDirectory(at: userDest, withIntermediateDirectories: true)
                try fm.copyItem(at: settingsFile, to: settingsDest)
                LoggerService.info("Captured \(editorName) settings.json")
            }
            
            let keybindingsFile = userPath.appendingPathComponent("keybindings.json")
            if fm.fileExists(atPath: keybindingsFile.path) {
                let keybindingsDest = userDest.appendingPathComponent("keybindings.json")
                try fm.createDirectory(at: userDest, withIntermediateDirectories: true)
                try fm.copyItem(at: keybindingsFile, to: keybindingsDest)
                LoggerService.info("Captured \(editorName) keybindings.json")
            }
            
            let snippetsPath = userPath.appendingPathComponent("snippets")
            if fm.fileExists(atPath: snippetsPath.path) {
                let snippetsDest = userDest.appendingPathComponent("snippets")
                try fm.copyItem(at: snippetsPath, to: snippetsDest)
                LoggerService.info("Captured \(editorName) snippets")
            }
        }
        
        if let extensionsPath = extensionsPath, fm.fileExists(atPath: extensionsPath.path) {
            try captureExtensionsList(from: extensionsPath, to: destination, editorName: editorName)
        } else {
            let cachedExtensions = appSupportPath.appendingPathComponent("CachedExtensionVSIXs")
            if fm.fileExists(atPath: cachedExtensions.path) {
                try captureExtensionsList(from: cachedExtensions, to: destination, editorName: editorName)
            }
        }
        
        try extractThemeInfo(from: appSupportPath, to: destination, editorName: editorName)
    }
    
    private func captureExtensionsList(from extensionsPath: URL, to destination: URL, editorName: String) throws {
        let fm = FileManager.default
        
        guard let extensionDirs = try? fm.contentsOfDirectory(at: extensionsPath, includingPropertiesForKeys: nil) else {
            LoggerService.warning("Could not read \(editorName) extensions directory")
            return
        }
        
        var extensions: [String] = []
        
        for extensionDir in extensionDirs {
            let dirName = extensionDir.lastPathComponent
            
            guard !dirName.hasPrefix(".") && !dirName.hasSuffix(".json") else { continue }
            
            let components = dirName.components(separatedBy: "-")
            if components.count >= 2 {
                let versionIndex = components.count - 1
                let extensionId = components[0..<versionIndex].joined(separator: "-")
                extensions.append(extensionId)
            }
        }
        
        let extensionsFile = destination.appendingPathComponent("extensions.txt")
        let extensionsContent = extensions.sorted().joined(separator: "\n")
        try extensionsContent.write(to: extensionsFile, atomically: true, encoding: .utf8)
        
        LoggerService.info("Captured \(extensions.count) \(editorName) extensions")
    }
    
    private func extractThemeInfo(from appSupportPath: URL, to destination: URL, editorName: String) throws {
        let settingsFile = appSupportPath.appendingPathComponent("User/settings.json")
        
        guard let settingsData = try? Data(contentsOf: settingsFile),
              let settingsDict = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any] else {
            LoggerService.warning("Could not read \(editorName) settings for theme extraction")
            return
        }
        
        var themeInfo: [String: Any] = [:]
        
        if let colorTheme = settingsDict["workbench.colorTheme"] as? String {
            themeInfo["colorTheme"] = colorTheme
        }
        
        if let iconTheme = settingsDict["workbench.iconTheme"] as? String {
            themeInfo["iconTheme"] = iconTheme
        }
        
        if let productIconTheme = settingsDict["workbench.productIconTheme"] as? String {
            themeInfo["productIconTheme"] = productIconTheme
        }
        
        if let fontFamily = settingsDict["editor.fontFamily"] as? String {
            themeInfo["fontFamily"] = fontFamily
        }
        
        if let fontSize = settingsDict["editor.fontSize"] as? Int {
            themeInfo["fontSize"] = fontSize
        }
        
        if !themeInfo.isEmpty {
            let themeFile = destination.appendingPathComponent("theme-info.json")
            let themeData = try JSONSerialization.data(withJSONObject: themeInfo, options: .prettyPrinted)
            try themeData.write(to: themeFile)
            
            LoggerService.info("Captured \(editorName) theme info: \(themeInfo)")
        }
    }
    
    
    private func applyCodeEditorSettings(from descriptor: ProfileDescriptor) throws {
        let vscodeDir = descriptor.directory.appendingPathComponent("vscode", isDirectory: true)
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: vscodeDir.path) else {
            LoggerService.info("No VS Code/Cursor settings found in profile: \(descriptor.profile.name)")
            return
        }
        
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        
        let vscodeProfileDir = vscodeDir.appendingPathComponent("vscode", isDirectory: true)
        if fm.fileExists(atPath: vscodeProfileDir.path) {
            try applyEditorSettingsToSystem(
                from: vscodeProfileDir,
                to: homeURL.appendingPathComponent("Library/Application Support/Code"),
                extensionsTo: homeURL.appendingPathComponent(".vscode/extensions"),
                editorName: "VS Code"
            )
        }
        
        let cursorProfileDir = vscodeDir.appendingPathComponent("cursor", isDirectory: true)
        if fm.fileExists(atPath: cursorProfileDir.path) {
            try applyEditorSettingsToSystem(
                from: cursorProfileDir,
                to: homeURL.appendingPathComponent("Library/Application Support/Cursor"),
                extensionsTo: nil, // Cursor extensions are handled differently
                editorName: "Cursor"
            )
        }
        
        LoggerService.info("Applied VS Code/Cursor settings from profile: \(descriptor.profile.name)")
    }
    
    private func applyEditorSettingsToSystem(from profileDir: URL, to appSupportPath: URL, extensionsTo: URL?, editorName: String) throws {
        let fm = FileManager.default
        
        let userProfileDir = profileDir.appendingPathComponent("User")
        if fm.fileExists(atPath: userProfileDir.path) {
            let userSystemDir = appSupportPath.appendingPathComponent("User")
            
            try fm.createDirectory(at: userSystemDir, withIntermediateDirectories: true)
            
            let profileSettings = userProfileDir.appendingPathComponent("settings.json")
            if fm.fileExists(atPath: profileSettings.path) {
                let systemSettings = userSystemDir.appendingPathComponent("settings.json")
                
                if fm.fileExists(atPath: systemSettings.path) {
                    try fm.removeItem(at: systemSettings)
                }
                try fm.copyItem(at: profileSettings, to: systemSettings)
                LoggerService.info("Applied \(editorName) settings.json")
                
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            let profileKeybindings = userProfileDir.appendingPathComponent("keybindings.json")
            if fm.fileExists(atPath: profileKeybindings.path) {
                let systemKeybindings = userSystemDir.appendingPathComponent("keybindings.json")
                
                if fm.fileExists(atPath: systemKeybindings.path) {
                    try fm.removeItem(at: systemKeybindings)
                }
                try fm.copyItem(at: profileKeybindings, to: systemKeybindings)
                LoggerService.info("Applied \(editorName) keybindings.json")
            }
            
            let profileSnippets = userProfileDir.appendingPathComponent("snippets")
            if fm.fileExists(atPath: profileSnippets.path) {
                let systemSnippets = userSystemDir.appendingPathComponent("snippets")
                
                if fm.fileExists(atPath: systemSnippets.path) {
                    try fm.removeItem(at: systemSnippets)
                }
                try fm.copyItem(at: profileSnippets, to: systemSnippets)
                LoggerService.info("Applied \(editorName) snippets")
            }
        }
        
        let extensionsFile = profileDir.appendingPathComponent("extensions.txt")
        if fm.fileExists(atPath: extensionsFile.path) {
            if let extensionsContent = try? String(contentsOf: extensionsFile) {
                let extensions = extensionsContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
                if !extensions.isEmpty {
                    LoggerService.info("\(editorName) Extensions to install manually:")
                    for ext in extensions.prefix(10) { // Log first 10
                        LoggerService.info("  - \(ext)")
                    }
                    if extensions.count > 10 {
                        LoggerService.info("  ... and \(extensions.count - 10) more extensions")
                    }
                }
            }
        }
    }
}


private extension String {
    var expandingTildeInPath: String {
        return (self as NSString).expandingTildeInPath
    }
}