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
            self.restoreActiveProfileFromDefaults()
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
        var profile = Profile(name: sanitized)
        
        // Capture current wallpaper
        if let currentWallpaper = getCurrentWallpaper() {
            let wallpaperDest = dest.appendingPathComponent("wallpaper.\(currentWallpaper.pathExtension)")
            try fm.copyItem(at: currentWallpaper, to: wallpaperDest)
            profile.wallpaper = wallpaperDest.lastPathComponent
            LoggerService.info("Copied current wallpaper to new profile: \(wallpaperDest.lastPathComponent)")
        }
        
        let descriptor = ProfileDescriptor(profile: profile, directory: dest)
        
        // Capture VS Code/Cursor settings and extensions
        try captureCodeEditorSettings(to: descriptor)
        
        // Snapshot current ~/.config into home/.config
        try snapshotCurrentConfiguration(to: descriptor)
        
        // Save profile.json with wallpaper info
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
        // Wait for any current apply operation to complete
        while ApplyActivity.isApplying {
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // Use ApplyActivity to prevent conflicts
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
        
        // Apply wallpaper if specified
        if let wallpaperRel = profile.wallpaper {
            let url = descriptor.directory.appendingPathComponent(wallpaperRel)
            try applyWallpaper(url: url)
        }
        
        // Apply VS Code/Cursor settings
        try applyCodeEditorSettings(from: descriptor)
        
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
        
        // Apply IDE configuration
        if let ide = profile.ide {
            try applyIDEConfig(ide, base: descriptor.directory)
        }
        
        // Run startup script if specified
        if let scriptRel = profile.startupScript {
            let scriptURL = descriptor.directory.appendingPathComponent(scriptRel)
            try runScript(scriptURL)
        }
        
        // Save apply record
        ApplyRecordStore.save(ApplyRecord(timestamp: Date(), actions: actions), to: descriptor.directory)
        
        // Mark as active only after successful completion
        setActiveProfile(descriptor)
    }
    
    /// Async version of applyProfile that runs heavy operations on background queue
    func applyProfileAsync(_ descriptor: ProfileDescriptor, cleanConfig: Bool = false) async throws {
        // Wait for any current apply operation to complete
        while ApplyActivity.isApplying {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Set applying state immediately on main thread for responsive UI
        await MainActor.run {
            self.isApplying = true
        }
        
        // Use ApplyActivity to prevent conflicts
        ApplyActivity.begin()
        
        defer {
            ApplyActivity.end()
            Task { @MainActor in
                self.isApplying = false
            }
        }
        
        // Run heavy operations on background queue but coordinate properly with main thread
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var actions: [ApplyAction] = []
                    let profile = descriptor.profile
                    
                    // Apply wallpaper if specified
                    if let wallpaperRel = profile.wallpaper {
                        let url = descriptor.directory.appendingPathComponent(wallpaperRel)
                        try self.applyWallpaper(url: url)
                    }
                    
                    // Apply VS Code/Cursor settings
                    try self.applyCodeEditorSettings(from: descriptor)
                    
                    // Render templates into home/ first
                    self.fileSystemService.renderTemplates(for: descriptor)
                    
                    let targetHome = URL(fileURLWithPath: NSHomeDirectory())
                    
                    if cleanConfig {
                        try self.backupAndCleanConfig(atHome: targetHome)
                    }
                    
                    // Handle file replacements or overlays
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
                    
                    // Apply terminal configuration
                    if let term = profile.terminal {
                        try self.applyTerminalConfig(term, base: descriptor.directory)
                    }
                    
                    // Apply IDE configuration
                    if let ide = profile.ide {
                        try self.applyIDEConfig(ide, base: descriptor.directory)
                    }
                    
                    // Run startup script if specified
                    if let scriptRel = profile.startupScript {
                        let scriptURL = descriptor.directory.appendingPathComponent(scriptRel)
                        try self.runScript(scriptURL)
                    }
                    
                    // Save apply record
                    ApplyRecordStore.save(ApplyRecord(timestamp: Date(), actions: actions), to: descriptor.directory)
                    
                    // Mark as active only after successful completion
                    DispatchQueue.main.sync {
                        self.setActiveProfile(descriptor)
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
        // During init, just validate the path exists
        // Actual restoration happens after profiles are loaded
        if let path = UserDefaults.standard.string(forKey: userDefaultsKey) {
            let url = URL(fileURLWithPath: path)
            if !FileManager.default.fileExists(atPath: url.path) {
                // Clean up invalid path
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        }
    }
    
    private func restoreActiveProfileFromDefaults() {
        guard let path = UserDefaults.standard.string(forKey: userDefaultsKey) else { return }
        let url = URL(fileURLWithPath: path)
        
        // Find the matching profile descriptor
        if let descriptor = profiles.first(where: { $0.directory == url }) {
            activeProfile = descriptor
        } else {
            // Profile no longer exists, clear the setting
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
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
        
        // Snapshot IDE configurations
        try snapshotIDEConfigurations(to: descriptor, home: home)
    }
    
    func snapshotIDEConfigurations(to descriptor: ProfileDescriptor, home: URL) throws {
        let fm = FileManager.default
        
        // Snapshot VS Code configuration
        let vscodeConfigDir = home.appendingPathComponent(Constants.vscodeConfigDir, isDirectory: true)
        if fm.fileExists(atPath: vscodeConfigDir.path) {
            let vscodeSnapshotDir = descriptor.directory.appendingPathComponent("vscode", isDirectory: true)
            try copyIDEConfigForSnapshot(from: vscodeConfigDir, to: vscodeSnapshotDir, ideType: .vscode)
        }
        
        // Snapshot Cursor configuration
        let cursorConfigDir = home.appendingPathComponent(Constants.cursorConfigDir, isDirectory: true)
        if fm.fileExists(atPath: cursorConfigDir.path) {
            let cursorSnapshotDir = descriptor.directory.appendingPathComponent("cursor", isDirectory: true)
            try copyIDEConfigForSnapshot(from: cursorConfigDir, to: cursorSnapshotDir, ideType: .cursor)
        }
    }
    
    func copyIDEConfigForSnapshot(from srcDir: URL, to dstDir: URL, ideType: Constants.IDEType) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        
        // Copy essential files
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
        
        // Copy snippets directory if it exists
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
        
        // Check if theme is a built-in theme ID (starts with @id:)
        if let themeSpec = ide.theme {
            if themeSpec.hasPrefix("@id:") {
                let themeId = String(themeSpec.dropFirst(4))
                try applyBuiltInTheme(themeId: themeId, ideType: ideType, configDir: configDir)
            } else {
                // Handle as file path
                let src = base.appendingPathComponent(themeSpec)
                try applyIDESettings(from: src, to: configDir, ideType: ideType)
            }
        } else {
            // Auto-detect default IDE configuration files
            if let defaultConfig = findDefaultIDEConfig(in: base, for: ideType) {
                try applyIDESettings(from: defaultConfig, to: configDir, ideType: ideType)
            }
        }
        
        // Install extensions if specified
        if let extensions = ide.extensions, !extensions.isEmpty {
            try installVSCodeExtensions(extensions)
        }
    }
    
    func applyCursorConfig(_ ide: Profile.IDE, base: URL, home: URL) throws {
        let ideType = Constants.IDEType.cursor
        let configDir = home.appendingPathComponent(ideType.configDirectory, isDirectory: true)
        
        // Check if theme is a built-in theme ID (starts with @id:)
        if let themeSpec = ide.theme {
            if themeSpec.hasPrefix("@id:") {
                let themeId = String(themeSpec.dropFirst(4))
                try applyBuiltInTheme(themeId: themeId, ideType: ideType, configDir: configDir)
            } else {
                // Handle as file path
                let src = base.appendingPathComponent(themeSpec)
                try applyIDESettings(from: src, to: configDir, ideType: ideType)
            }
        } else {
            // Auto-detect default IDE configuration files
            if let defaultConfig = findDefaultIDEConfig(in: base, for: ideType) {
                try applyIDESettings(from: defaultConfig, to: configDir, ideType: ideType)
            }
        }
        
        // Install extensions if specified
        if let extensions = ide.extensions, !extensions.isEmpty {
            try installCursorExtensions(extensions)
        }
    }
    
    func applyBuiltInTheme(themeId: String, ideType: Constants.IDEType, configDir: URL) throws {
        // Discover available themes from the actual IDE installation
        let availableThemes = try discoverAvailableThemes(for: ideType)
        
        guard let theme = availableThemes.first(where: { $0.name == themeId }) else {
            throw ProfileServiceError.fileNotFound("Theme '\(themeId)' not found in installed \(ideType.displayName) themes")
        }
        
        let fm = FileManager.default
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Create or update settings.json with the theme
        try applyDiscoveredThemeToSettings(theme: theme, configDir: configDir, ideType: ideType)
        
        LoggerService.info("Applied theme '\(theme.displayName)' to \(ideType.displayName)")
    }
    
    func discoverAvailableThemes(for ideType: Constants.IDEType) throws -> [Constants.DiscoveredTheme] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let configDir = home.appendingPathComponent(ideType.configDirectory, isDirectory: true)
        
        var themes: [Constants.DiscoveredTheme] = []
        
        // Add built-in themes (these are always available)
        themes.append(contentsOf: getBuiltInThemes())
        
        // Discover themes from installed extensions
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
            
            // Look for package.json to get extension info
            let packageJsonPath = extensionDir.appendingPathComponent("package.json")
            guard fm.fileExists(atPath: packageJsonPath.path) else { continue }
            
            do {
                let packageData = try Data(contentsOf: packageJsonPath)
                guard let packageJson = try JSONSerialization.jsonObject(with: packageData) as? [String: Any] else { continue }
                
                // Extract themes from the extension
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
        
        // Load existing settings or create new ones
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
        
        // Update theme setting
        settings["workbench.colorTheme"] = theme.name
        
        // Write updated settings
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsFile, options: .atomic)
        } catch {
            throw ProfileServiceError.fileOperationFailed("write settings", error)
        }
    }
    
    /// Lists all available themes for an IDE (useful for debugging and user reference)
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
        
        // Ensure config directory exists
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Copy settings file
        let settingsDst = configDir.appendingPathComponent(ideType.settingsFile)
        _ = try replaceFile(source: src, destination: settingsDst)
        
        // Check if source is a directory (multiple config files)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: src.path, isDirectory: &isDir), isDir.boolValue {
            // Copy all files from source directory
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
                // Skip certain files that shouldn't be copied
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
        
        // Install each extension
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
        
        // Install each extension
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
        // Run script via absolute path, robustly quoted to handle spaces/special chars
        process.currentDirectoryURL = url.deletingLastPathComponent()
        let quotedPath = "'\(url.path.replacingOccurrences(of: "'", with: "'\\''"))'"
        process.arguments = ["-lc", quotedPath]
        try process.run()
    }
    
    /// Gets the current desktop wallpaper URL
    func getCurrentWallpaper() -> URL? {
        guard let mainScreen = NSScreen.main else { return nil }
        
        do {
            guard let wallpaperURL = try NSWorkspace.shared.desktopImageURL(for: mainScreen) else {
                LoggerService.warning("Desktop image URL returned nil for main screen")
                return nil
            }
            
            // Verify the file exists and is accessible
            if FileManager.default.fileExists(atPath: wallpaperURL.path) {
                LoggerService.info("Found current wallpaper: \(wallpaperURL.path)")
                return wallpaperURL
            } else {
                LoggerService.warning("Current wallpaper file not accessible: \(wallpaperURL.path)")
                return nil
            }
        } catch {
            LoggerService.error("Failed to get current wallpaper: \(error)")
            
            // Fallback: Try to get via AppleScript
            return getCurrentWallpaperViaAppleScript()
        }
    }
    
    /// Fallback method to get wallpaper via AppleScript
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
    
    // MARK: - VS Code/Cursor Settings Capture
    
    /// Captures current VS Code and Cursor settings and extensions
    private func captureCodeEditorSettings(to descriptor: ProfileDescriptor) throws {
        let fm = FileManager.default
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        
        // Create vscode directory in profile
        let vscodeDir = descriptor.directory.appendingPathComponent("vscode", isDirectory: true)
        try fm.createDirectory(at: vscodeDir, withIntermediateDirectories: true)
        
        // VS Code paths
        let vscodeAppSupportPath = homeURL.appendingPathComponent("Library/Application Support/Code")
        let vscodeExtensionsPath = homeURL.appendingPathComponent(".vscode/extensions")
        
        // Cursor paths  
        let cursorAppSupportPath = homeURL.appendingPathComponent("Library/Application Support/Cursor")
        
        // Capture VS Code settings
        if fm.fileExists(atPath: vscodeAppSupportPath.path) {
            try captureEditorSettings(
                from: vscodeAppSupportPath,
                extensionsPath: vscodeExtensionsPath,
                to: vscodeDir.appendingPathComponent("vscode", isDirectory: true),
                editorName: "VS Code"
            )
        }
        
        // Capture Cursor settings
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
    
    /// Helper method to capture settings from a specific code editor
    private func captureEditorSettings(from appSupportPath: URL, extensionsPath: URL?, to destination: URL, editorName: String) throws {
        let fm = FileManager.default
        
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        
        // Copy user settings
        let userPath = appSupportPath.appendingPathComponent("User")
        if fm.fileExists(atPath: userPath.path) {
            let userDest = destination.appendingPathComponent("User")
            
            // Copy settings.json
            let settingsFile = userPath.appendingPathComponent("settings.json")
            if fm.fileExists(atPath: settingsFile.path) {
                let settingsDest = userDest.appendingPathComponent("settings.json")
                try fm.createDirectory(at: userDest, withIntermediateDirectories: true)
                try fm.copyItem(at: settingsFile, to: settingsDest)
                LoggerService.info("Captured \(editorName) settings.json")
            }
            
            // Copy keybindings.json
            let keybindingsFile = userPath.appendingPathComponent("keybindings.json")
            if fm.fileExists(atPath: keybindingsFile.path) {
                let keybindingsDest = userDest.appendingPathComponent("keybindings.json")
                try fm.createDirectory(at: userDest, withIntermediateDirectories: true)
                try fm.copyItem(at: keybindingsFile, to: keybindingsDest)
                LoggerService.info("Captured \(editorName) keybindings.json")
            }
            
            // Copy snippets directory
            let snippetsPath = userPath.appendingPathComponent("snippets")
            if fm.fileExists(atPath: snippetsPath.path) {
                let snippetsDest = userDest.appendingPathComponent("snippets")
                try fm.copyItem(at: snippetsPath, to: snippetsDest)
                LoggerService.info("Captured \(editorName) snippets")
            }
        }
        
        // Generate extensions list
        if let extensionsPath = extensionsPath, fm.fileExists(atPath: extensionsPath.path) {
            try captureExtensionsList(from: extensionsPath, to: destination, editorName: editorName)
        } else {
            // For Cursor, look for cached extensions
            let cachedExtensions = appSupportPath.appendingPathComponent("CachedExtensionVSIXs")
            if fm.fileExists(atPath: cachedExtensions.path) {
                try captureExtensionsList(from: cachedExtensions, to: destination, editorName: editorName)
            }
        }
        
        // Extract theme information from settings
        try extractThemeInfo(from: appSupportPath, to: destination, editorName: editorName)
    }
    
    /// Captures the list of installed extensions
    private func captureExtensionsList(from extensionsPath: URL, to destination: URL, editorName: String) throws {
        let fm = FileManager.default
        
        guard let extensionDirs = try? fm.contentsOfDirectory(at: extensionsPath, includingPropertiesForKeys: nil) else {
            LoggerService.warning("Could not read \(editorName) extensions directory")
            return
        }
        
        var extensions: [String] = []
        
        for extensionDir in extensionDirs {
            let dirName = extensionDir.lastPathComponent
            
            // Skip system files
            guard !dirName.hasPrefix(".") && !dirName.hasSuffix(".json") else { continue }
            
            // Extract extension ID (format: publisher.name-version)
            let components = dirName.components(separatedBy: "-")
            if components.count >= 2 {
                let versionIndex = components.count - 1
                let extensionId = components[0..<versionIndex].joined(separator: "-")
                extensions.append(extensionId)
            }
        }
        
        // Write extensions list to file
        let extensionsFile = destination.appendingPathComponent("extensions.txt")
        let extensionsContent = extensions.sorted().joined(separator: "\n")
        try extensionsContent.write(to: extensionsFile, atomically: true, encoding: .utf8)
        
        LoggerService.info("Captured \(extensions.count) \(editorName) extensions")
    }
    
    /// Extracts theme information from settings
    private func extractThemeInfo(from appSupportPath: URL, to destination: URL, editorName: String) throws {
        let settingsFile = appSupportPath.appendingPathComponent("User/settings.json")
        
        guard let settingsData = try? Data(contentsOf: settingsFile),
              let settingsDict = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any] else {
            LoggerService.warning("Could not read \(editorName) settings for theme extraction")
            return
        }
        
        var themeInfo: [String: Any] = [:]
        
        // Extract theme-related settings
        if let colorTheme = settingsDict["workbench.colorTheme"] as? String {
            themeInfo["colorTheme"] = colorTheme
        }
        
        if let iconTheme = settingsDict["workbench.iconTheme"] as? String {
            themeInfo["iconTheme"] = iconTheme
        }
        
        if let productIconTheme = settingsDict["workbench.productIconTheme"] as? String {
            themeInfo["productIconTheme"] = productIconTheme
        }
        
        // Extract font settings
        if let fontFamily = settingsDict["editor.fontFamily"] as? String {
            themeInfo["fontFamily"] = fontFamily
        }
        
        if let fontSize = settingsDict["editor.fontSize"] as? Int {
            themeInfo["fontSize"] = fontSize
        }
        
        // Write theme info to file
        if !themeInfo.isEmpty {
            let themeFile = destination.appendingPathComponent("theme-info.json")
            let themeData = try JSONSerialization.data(withJSONObject: themeInfo, options: .prettyPrinted)
            try themeData.write(to: themeFile)
            
            LoggerService.info("Captured \(editorName) theme info: \(themeInfo)")
        }
    }
    
    // MARK: - VS Code/Cursor Settings Application
    
    /// Applies VS Code and Cursor settings from the profile
    private func applyCodeEditorSettings(from descriptor: ProfileDescriptor) throws {
        let vscodeDir = descriptor.directory.appendingPathComponent("vscode", isDirectory: true)
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: vscodeDir.path) else {
            LoggerService.info("No VS Code/Cursor settings found in profile: \(descriptor.profile.name)")
            return
        }
        
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        
        // Apply VS Code settings
        let vscodeProfileDir = vscodeDir.appendingPathComponent("vscode", isDirectory: true)
        if fm.fileExists(atPath: vscodeProfileDir.path) {
            try applyEditorSettingsToSystem(
                from: vscodeProfileDir,
                to: homeURL.appendingPathComponent("Library/Application Support/Code"),
                extensionsTo: homeURL.appendingPathComponent(".vscode/extensions"),
                editorName: "VS Code"
            )
        }
        
        // Apply Cursor settings
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
    
    /// Applies settings from profile to the system editor configuration
    private func applyEditorSettingsToSystem(from profileDir: URL, to appSupportPath: URL, extensionsTo: URL?, editorName: String) throws {
        let fm = FileManager.default
        
        // Apply user settings
        let userProfileDir = profileDir.appendingPathComponent("User")
        if fm.fileExists(atPath: userProfileDir.path) {
            let userSystemDir = appSupportPath.appendingPathComponent("User")
            
            // Create User directory if it doesn't exist
            try fm.createDirectory(at: userSystemDir, withIntermediateDirectories: true)
            
            // Apply settings.json
            let profileSettings = userProfileDir.appendingPathComponent("settings.json")
            if fm.fileExists(atPath: profileSettings.path) {
                let systemSettings = userSystemDir.appendingPathComponent("settings.json")
                
                // Remove existing settings and copy profile settings
                if fm.fileExists(atPath: systemSettings.path) {
                    try fm.removeItem(at: systemSettings)
                }
                try fm.copyItem(at: profileSettings, to: systemSettings)
                LoggerService.info("Applied \(editorName) settings.json")
                
                // Small delay to allow editor to detect file changes
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            // Apply keybindings.json
            let profileKeybindings = userProfileDir.appendingPathComponent("keybindings.json")
            if fm.fileExists(atPath: profileKeybindings.path) {
                let systemKeybindings = userSystemDir.appendingPathComponent("keybindings.json")
                
                // Remove existing keybindings and copy profile keybindings
                if fm.fileExists(atPath: systemKeybindings.path) {
                    try fm.removeItem(at: systemKeybindings)
                }
                try fm.copyItem(at: profileKeybindings, to: systemKeybindings)
                LoggerService.info("Applied \(editorName) keybindings.json")
            }
            
            // Apply snippets
            let profileSnippets = userProfileDir.appendingPathComponent("snippets")
            if fm.fileExists(atPath: profileSnippets.path) {
                let systemSnippets = userSystemDir.appendingPathComponent("snippets")
                
                // Remove existing snippets and copy profile snippets
                if fm.fileExists(atPath: systemSnippets.path) {
                    try fm.removeItem(at: systemSnippets)
                }
                try fm.copyItem(at: profileSnippets, to: systemSnippets)
                LoggerService.info("Applied \(editorName) snippets")
            }
        }
        
        // Show extension installation instructions
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

// MARK: - Extensions

private extension String {
    var expandingTildeInPath: String {
        return (self as NSString).expandingTildeInPath
    }
}