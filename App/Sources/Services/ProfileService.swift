import Foundation
import AppKit
import CoreServices
import Combine
#if canImport(Yams)
import Yams
#endif

// MARK: - Profile Service Errors

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

// MARK: - Profile Cache

private struct CachedProfile {
    let profile: Profile
    let cachedAt: Date
    let fileModificationDate: Date
    
    var isValid: Bool {
        let maxAge: TimeInterval = 300 // 5 minutes
        return Date().timeIntervalSince(cachedAt) < maxAge
    }
}

// MARK: - Profile Service

/// Consolidated service for all profile-related operations including management, 
/// application, caching, and file system watching.
final class ProfileService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var profiles: [ProfileDescriptor] = []
    @Published private(set) var activeProfile: ProfileDescriptor?
    @Published private(set) var isApplying = false
    
    // MARK: - Private Properties
    
    private let userDefaultsKey = "ActiveProfileDirectoryPath"
    private let cacheQueue = DispatchQueue(label: "com.ricebar.profile-cache", qos: .userInitiated)
    private var profileCache: [URL: CachedProfile] = [:]
    private var lastModificationDates: [URL: Date] = [:]
    
    // File System Watching
    private var stream: FSEventStreamRef?
    private var debounceTimer: Timer?
    
    // Profile Application
    private let fileSystemService: FileSystemService
    
    // MARK: - Singleton
    
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
    
    // MARK: - Profile Management
    
    /// Reloads all profiles from the file system
    func reload() {
        let root = profilesRoot()
        let fm = FileManager.default
        var loaded: [ProfileDescriptor] = []
        
        if let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            for url in items {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false else { continue }
                
                if let profile = loadProfile(at: url) {
                    loaded.append(ProfileDescriptor(profile: profile, directory: url))
                } else {
                    let defaults = defaultProfile(for: url)
                    loaded.append(ProfileDescriptor(profile: defaults, directory: url))
                }
            }
        }
        
        DispatchQueue.main.async {
            self.profiles = loaded
        }
    }
    
    /// Opens the profiles folder in Finder
    func openProfilesFolder() {
        NSWorkspace.shared.open(profilesRoot())
    }
    
    /// Creates a copy of an existing profile
    func copyProfile(_ descriptor: ProfileDescriptor, to newName: String) throws -> ProfileDescriptor {
        let fm = FileManager.default
        let sanitized = sanitizeProfileName(newName)
        guard !sanitized.isEmpty else { throw ProfileServiceError.invalidProfileName }
        
        let dest = profilesRoot().appendingPathComponent(sanitized, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            throw ProfileServiceError.profileAlreadyExists(sanitized)
        }
        
        try fm.copyItem(at: descriptor.directory, to: dest)
        
        // Remove transient files in the copy
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
    
    /// Creates a new profile from the current system configuration
    func createProfileFromCurrent(name: String) throws -> ProfileDescriptor {
        let fm = FileManager.default
        let sanitized = sanitizeProfileName(name)
        guard !sanitized.isEmpty else { throw ProfileServiceError.invalidProfileName }
        
        let dest = profilesRoot().appendingPathComponent(sanitized, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            throw ProfileServiceError.profileAlreadyExists(sanitized)
        }
        
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let descriptor = ProfileDescriptor(profile: Profile(name: sanitized), directory: dest)
        
        // Snapshot current ~/.config into home/.config
        try snapshotCurrentConfiguration(to: descriptor)
        
        // Save a minimal profile.json for clarity
        let jsonURL = dest.appendingPathComponent("profile.json")
        try saveProfileToJSON(descriptor.profile, at: jsonURL)
        
        reload()
        
        if let newDesc = profiles.first(where: { $0.directory == dest }) {
            return newDesc
        }
        return descriptor
    }
    
    /// Creates a new empty profile
    func createEmptyProfile(name: String) throws -> ProfileDescriptor {
        let fm = FileManager.default
        let sanitized = sanitizeProfileName(name)
        guard !sanitized.isEmpty else { throw ProfileServiceError.invalidProfileName }
        
        let dest = profilesRoot().appendingPathComponent(sanitized, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            throw ProfileServiceError.profileAlreadyExists(sanitized)
        }
        
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        // Create empty home dir
        try fm.createDirectory(at: dest.appendingPathComponent("home", isDirectory: true), withIntermediateDirectories: true)
        
        // Save minimal profile.json
        let descriptor = ProfileDescriptor(profile: Profile(name: sanitized), directory: dest)
        let jsonURL = dest.appendingPathComponent("profile.json")
        try saveProfileToJSON(descriptor.profile, at: jsonURL)
        
        reload()
        
        if let newDesc = profiles.first(where: { $0.directory == dest }) {
            return newDesc
        }
        return descriptor
    }
    
    /// Deletes a profile and its directory
    func deleteProfile(_ descriptor: ProfileDescriptor) throws {
        let fm = FileManager.default
        
        // Verify the profile directory exists
        guard fm.fileExists(atPath: descriptor.directory.path) else {
            throw ProfileServiceError.profileNotFound(descriptor.profile.name)
        }
        
        // Invalidate cache for this profile
        invalidateCache(directory: descriptor.directory)
        
        do {
            // Move to trash instead of permanent deletion for safety
            var trashURL: NSURL?
            try fm.trashItem(at: descriptor.directory, resultingItemURL: &trashURL)
            
            // Clear the active profile if it was the one deleted
            if activeProfile?.directory == descriptor.directory {
                setActiveProfile(nil)
            }
            
            // Reload profiles to update the list
            reload()
            
            LoggerService.info("Profile '\(descriptor.profile.name)' moved to trash successfully")
        } catch {
            throw ProfileServiceError.deletionFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Profile Application
    
    /// Applies a profile to the system
    func applyProfile(_ descriptor: ProfileDescriptor, cleanConfig: Bool = false) throws {
        // Allow reentrant calls from the same profile to avoid deadlocks
        if isApplying && activeProfile?.directory == descriptor.directory {
            LoggerService.info("Skipping redundant apply for already active profile: \(descriptor.profile.name)")
            return
        }
        
        DispatchQueue.main.async {
            self.isApplying = true
        }
        
        defer {
            DispatchQueue.main.async {
                self.isApplying = false
            }
        }
        
        var actions: [ApplyAction] = []
        let profile = descriptor.profile
        
        // Mark active early so file watcher reacts to the correct directory
        setActiveProfile(descriptor)
        
        // Apply wallpaper if specified
        if let wallpaperRel = profile.wallpaper {
            let url = descriptor.directory.appendingPathComponent(wallpaperRel)
            try applyWallpaper(url: url)
        }
        
        // Render templates into home/ first
        fileSystemService.renderTemplates(for: descriptor)
        
        let targetHome = URL(fileURLWithPath: NSHomeDirectory())
        
        if cleanConfig {
            try backupAndCleanConfig(atHome: targetHome)
        }
        
        // Handle file replacements or overlays
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
        
        // Apply terminal configuration
        if let term = profile.terminal {
            try applyTerminalConfig(term, base: descriptor.directory)
        }
        
        // Run startup script if specified
        if let scriptRel = profile.startupScript {
            let scriptURL = descriptor.directory.appendingPathComponent(scriptRel)
            try runScript(scriptURL)
        }
        
        // Save apply record
        ApplyRecordStore.save(ApplyRecord(timestamp: Date(), actions: actions), to: descriptor.directory)
    }
    
    /// Reverts the last profile application
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
    
    // MARK: - Active Profile Management
    
    /// Sets the active profile
    func setActiveProfile(_ descriptor: ProfileDescriptor?) {
        DispatchQueue.main.async {
            self.activeProfile = descriptor
        }
        
        if let descriptor = descriptor {
            UserDefaults.standard.set(descriptor.directory.path, forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }
    
    // MARK: - Profile Metadata Updates
    
    /// Saves profile metadata to disk
    func saveProfile(_ profile: Profile, at directory: URL) throws {
        let jsonURL = directory.appendingPathComponent("profile.json")
        try FileSystemUtilities.writeJSON(profile, to: jsonURL)
        invalidateCache(directory: directory)
    }
    
    /// Updates wallpaper for a profile
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
    
    // MARK: - File System Watching
    
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
                    // Ignore events under ~/.config/alacritty to avoid apply-trigger loops
                    if path.contains("/\(Constants.alacrittyDirRelative)/") { continue }
                    changed.append(path)
                }
            }
            
            // Debounce events to avoid thrashing
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
            // Auto-apply when files inside the active profile change
            // Use longer window to prevent interference with manual switches
            guard !isApplying && !ApplyActivity.recentlyApplied(within: 2.0) else { return }
            guard let active = activeProfile else { return }
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.applyProfile(active, cleanConfig: false)
                } catch {
                    LoggerService.error("Auto-apply failed: \(error)")
                }
            }
        } else {
            // General profile changes, reload the list
            reload()
        }
    }
    
    // MARK: - Caching
    
    private func getProfileFromCache(at directory: URL) -> Profile? {
        return cacheQueue.sync {
            // Check if we have a valid cached version
            if let cached = profileCache[directory],
               cached.isValid,
               isFileUnchanged(at: directory, lastKnownDate: cached.fileModificationDate) {
                return cached.profile
            }
            
            // Load from disk and cache
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
        // Check modification date of profile configuration files
        for fileName in Constants.profileFileCandidates {
            let url = directory.appendingPathComponent(fileName)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let modificationDate = attributes[.modificationDate] as? Date {
                return modificationDate
            }
        }
        
        // Fallback to directory modification date
        if let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
           let modificationDate = attributes[.modificationDate] as? Date {
            return modificationDate
        }
        
        return Date.distantPast
    }
}

// MARK: - Private Implementation

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
            if FileManager.default.fileExists(atPath: url.path) {
                // Will be loaded when profiles are reloaded
                // This is deferred to avoid circular dependencies during init
            }
        }
    }
    
    func sanitizeProfileName(_ name: String) -> String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
    }
    
    func loadProfile(at directory: URL) -> Profile? {
        // Try cache first
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
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: []) else { return nil }
        
        // Prefer files named like wallpaper/background/bg first
        let preferredPrefixes = Constants.preferredWallpaperPrefixes
        if let preferred = items.first(where: { url in
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            return exts.contains(url.pathExtension.lowercased()) && preferredPrefixes.contains(where: { name.hasPrefix($0) })
        }) {
            return preferred
        }
        
        // Otherwise first image
        return items.first { exts.contains($0.pathExtension.lowercased()) }
    }
    
    func saveProfileToJSON(_ profile: Profile, at url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(profile)
        try data.write(to: url, options: .atomic)
    }
    
    // MARK: - Profile Application Implementation
    
    func snapshotCurrentConfiguration(to descriptor: ProfileDescriptor) throws {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let src = home.appendingPathComponent(".config", isDirectory: true)
        let dst = descriptor.directory.appendingPathComponent("home/.config", isDirectory: true)
        var isDir: ObjCBool = false
        
        if FileManager.default.fileExists(atPath: src.path, isDirectory: &isDir), isDir.boolValue {
            try copyDirectoryRecursively(from: src, to: dst)
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
        
        // Recreate empty .config for overlay
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
    }
    
    func applyWallpaper(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { 
            throw ProfileServiceError.fileNotFound(url.path) 
        }
        
        var lastError: Error?
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            } catch {
                lastError = error
                LoggerService.error("Wallpaper set failed for screen: \(error.localizedDescription)")
            }
        }
        
        if lastError != nil {
            // Fallback via AppleScript to set all desktops
            let script = """
            tell application "System Events"
              tell every desktop
                set picture to "\(url.path)"
              end tell
            end tell
            """
            var errorDict: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&errorDict)
                if let errorDict { LoggerService.error("AppleScript wallpaper error: \(errorDict)") }
            }
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
            // Skip heavy work if content is identical
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
        
        // IMPORTANT: do NOT skip hidden files; we need to copy `.config/**` and other dotfiles
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
        
        // Nudge both common config filenames so Alacritty notices
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let ymlPath = home.appendingPathComponent("\(Constants.alacrittyDirRelative)/\(Constants.alacrittyYml)").path
        let tomlPath = home.appendingPathComponent("\(Constants.alacrittyDirRelative)/\(Constants.alacrittyToml)").path
        
        if FileManager.default.fileExists(atPath: ymlPath) {
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: ymlPath)
        }
        if FileManager.default.fileExists(atPath: tomlPath) {
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: tomlPath)
        }
        
        // Ask a running Alacritty to reload its config if available
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
        
        // Move to backups folder to avoid Alacritty loading the wrong file
        try? fm.createDirectory(at: ConfigAccess.backupsRoot, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = ConfigAccess.backupsRoot.appendingPathComponent("alacritty_\(altName).\(timestamp)")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: alt, to: backup)
    }
    
    func runScript(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { 
            throw ProfileServiceError.fileNotFound(url.path) 
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Run script via absolute path, robustly quoted to handle spaces/special chars
        process.currentDirectoryURL = url.deletingLastPathComponent()
        let quotedPath = "'\(url.path.replacingOccurrences(of: "'", with: "'\\''"))'"
        process.arguments = ["-lc", quotedPath]
        try process.run()
    }
}

// MARK: - Extensions

private extension String {
    var expandingTildeInPath: String {
        return (self as NSString).expandingTildeInPath
    }
}