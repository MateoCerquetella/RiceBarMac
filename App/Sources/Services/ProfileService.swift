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
    case fileOperationFailed(String, Error)
    case permissionDenied(String)
    case migrationUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidProfileName:
            return "Invalid profile name"
        case .profileAlreadyExists(let name):
            return "A profile with the name '\(name)' already exists"
        case .profileNotFound(let name):
            return "Profile '\(name)' not found"
        case .cannotDeleteActiveProfile:
            return "Cannot delete the currently active profile. Apply or restore another profile first."
        case .deletionFailed(let reason):
            return "Failed to delete profile: \(reason)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileOperationFailed(let operation, let error):
            return "File operation failed (\(operation)): \(error.localizedDescription)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .migrationUnavailable:
            return "No conflict-free legacy configuration is available to migrate."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .cannotDeleteActiveProfile:
            return "Undo the active transaction or apply a different profile before deleting this profile."
        case .deletionFailed, .fileOperationFailed, .permissionDenied:
            return "Check the affected path and its permissions, then try again."
        case .migrationUnavailable:
            return "Open both ~/.ricebar and ~/.ricebarmac and resolve the reported conflict without deleting either source."
        default:
            return nil
        }
    }
}

final class ProfileService: ObservableObject {
    @Published private(set) var profiles: [ProfileDescriptor] = []
    @Published private(set) var invalidProfiles: [InvalidProfileDescriptor] = []
    @Published private(set) var activeProfile: ProfileDescriptor?
    @Published private(set) var isApplying = false
    @Published private(set) var operationState: ProfileOperationSnapshot = .idle
    @Published private(set) var recoveryTransactions: [ApplyTransaction] = []
    @Published private(set) var canUndo = false
    @Published private(set) var migrationAvailability: LegacyMigrationAvailability = .none

    static let shared = ProfileService()

    private let rootURL: URL
    private let profilesURL: URL
    private let homeURL: URL
    private let fileSystem: FileSystemClient
    private let activeProfileStore: ActiveProfilePersisting
    private let coordinator: ProfileApplicationCoordinator
    private let migrationService: LegacyMigrationService
    private let fileManager: FileManager

    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private var watchingEnabled = false

    private init() {
        let home = Constants.userHome
        let root = Constants.ricebarRoot
        let fileSystem = LiveFileSystemClient()
        let activeStore: ActiveProfilePersisting
        let externalEffectClient: ExternalEffectClient
        if Constants.isUITesting {
            activeStore = VolatileActiveProfileStore()
            externalEffectClient = NoOpExternalEffectClient()
        } else {
            activeStore = UserDefaultsActiveProfileStore()
            externalEffectClient = LiveExternalEffectClient()
        }
        let planner = ProfilePlanner(home: home, fileSystem: fileSystem)
        let transactionStore = TransactionStore(rootURL: root, fileSystem: fileSystem)
        let executor = ProfileTransactionExecutor(
            fileSystem: fileSystem,
            transactionStore: transactionStore,
            activeProfileStore: activeStore,
            externalEffects: externalEffectClient
        )

        homeURL = home
        rootURL = root
        profilesURL = root.appendingPathComponent("profiles", isDirectory: true)
        self.fileSystem = fileSystem
        activeProfileStore = activeStore
        coordinator = ProfileApplicationCoordinator(planner: planner, executor: executor, activeProfileStore: activeStore)
        migrationService = LegacyMigrationService(home: home, fileSystem: fileSystem)
        fileManager = .default

        reload()
        configureWatching(enabled: ConfigService.shared.config.general.autoReloadProfiles)
        bindCoordinator()
    }

    deinit {
        stopWatching()
    }

    // MARK: - Read-only loading

    func reload() {
        var loaded: [ProfileDescriptor] = []
        var invalid: [InvalidProfileDescriptor] = []

        if (try? fileSystem.state(at: profilesURL).kind) == .directory,
           let directories = try? fileSystem.contentsOfDirectory(at: profilesURL) {
            for directory in directories.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                guard (try? fileSystem.state(at: directory).kind) == .directory else { continue }
                do {
                    let profile = try loadProfileDefinition(at: directory) ?? defaultProfile(for: directory)
                    try profile.validate()
                    loaded.append(ProfileDescriptor(profile: profile, directory: directory.standardizedFileURL))
                } catch {
                    invalid.append(InvalidProfileDescriptor(
                        directory: directory.standardizedFileURL,
                        source: profileSource(in: directory),
                        message: error.localizedDescription
                    ))
                }
            }
        }

        let savedPath = activeProfileStore.loadActiveProfilePath()
        let restored = savedPath.flatMap { path in
            loaded.first(where: { $0.directory.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path })
        }

        publishOnMain {
            self.profiles = loaded
            self.invalidProfiles = invalid
            self.activeProfile = restored
            self.migrationAvailability = self.migrationService.availability()
        }
    }

    func openProfilesFolder() {
        do {
            try ensureDirectoryHierarchy(profilesURL)
            NSWorkspace.shared.open(profilesURL)
            configureWatching(enabled: watchingEnabled)
        } catch {
            publishOperationError(error)
        }
    }

    // MARK: - Safe profile application

    func previewProfile(_ descriptor: ProfileDescriptor) async throws -> ProfileApplyPlan {
        try await coordinator.preview(descriptor)
    }

    @discardableResult
    func applyPlan(_ plan: ProfileApplyPlan) async throws -> ProfileApplyOutcome {
        let outcome = try await coordinator.apply(plan)
        await MainActor.run {
            self.activeProfile = self.profiles.first(where: { $0.directory.path == plan.profileDirectoryPath })
                ?? ProfileDescriptor(profile: Profile(name: plan.profileName), directory: URL(fileURLWithPath: plan.profileDirectoryPath))
        }
        await refreshTransactionMetadata()
        return outcome
    }

    @discardableResult
    func applyProfileAsync(_ descriptor: ProfileDescriptor, cleanConfig: Bool = false) async throws -> ProfileApplyOutcome {
        let plan = try await previewProfile(descriptor)
        return try await applyPlan(plan)
    }

    @discardableResult
    func undoLastApply() async throws -> ApplyTransaction {
        let transaction = try await coordinator.undoLatest()
        await MainActor.run {
            if let former = transaction.plan.formerActiveProfilePath {
                self.activeProfile = self.profiles.first(where: { $0.directory.path == former })
            } else {
                self.activeProfile = nil
            }
        }
        await refreshTransactionMetadata()
        return transaction
    }

    @discardableResult
    func recover(transactionID: UUID) async throws -> ApplyTransaction {
        let transaction = try await coordinator.recover(transactionID: transactionID)
        await MainActor.run {
            if let former = transaction.plan.formerActiveProfilePath {
                self.activeProfile = self.profiles.first(where: { $0.directory.path == former })
            } else {
                self.activeProfile = nil
            }
        }
        await refreshTransactionMetadata()
        return transaction
    }

    // MARK: - Explicit legacy migration

    @discardableResult
    func migrateLegacyConfiguration() throws -> LegacyMigrationRecord {
        let record = try migrationService.migrate()
        ConfigService.shared.reloadConfig()
        reload()
        configureWatching(enabled: ConfigService.shared.config.general.autoReloadProfiles)
        return record
    }

    // MARK: - Profile management

    func copyProfile(_ descriptor: ProfileDescriptor, to newName: String) throws -> ProfileDescriptor {
        let sanitized = try validatedProfileName(newName)
        let destination = profilesURL.appendingPathComponent(sanitized, isDirectory: true)
        guard try fileSystem.state(at: destination).kind == .absent else {
            throw ProfileServiceError.profileAlreadyExists(sanitized)
        }
        try ensureDirectoryHierarchy(profilesURL)
        let stage = profilesURL.appendingPathComponent(
            ".\(sanitized).ricebarmac-stage-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        do {
            try fileSystem.copyItem(at: descriptor.directory, to: stage)
            let transientNames = [".ricebar-last-apply.json"]
            for name in transientNames {
                try? fileSystem.removeItem(at: stage.appendingPathComponent(name))
            }
            if var copiedProfile = try loadProfileDefinition(at: stage) {
                copiedProfile.name = sanitized
                try saveProfileDefinition(copiedProfile, in: stage)
            }
            guard try fileSystem.state(at: destination).kind == .absent else {
                throw ProfileServiceError.profileAlreadyExists(sanitized)
            }
            try fileSystem.moveItem(at: stage, to: destination)
        } catch let error as ProfileServiceError {
            try? fileSystem.removeItem(at: stage)
            throw error
        } catch {
            try? fileSystem.removeItem(at: stage)
            throw ProfileServiceError.fileOperationFailed("copy profile", error)
        }
        reload()
        configureWatching(enabled: watchingEnabled)
        return profiles.first(where: { $0.directory.path == destination.path })
            ?? ProfileDescriptor(profile: defaultProfile(for: destination), directory: destination)
    }

    func createEmptyProfile(name: String) throws -> ProfileDescriptor {
        try createProfile(name: name, operation: "create profile") { _, _ in }
    }

    func createProfileFromCurrent(name: String) throws -> ProfileDescriptor {
        try createProfile(name: name, operation: "capture current setup") { directory, profile in
            if let wallpaper = currentWallpaperURL() {
                let extensionName = wallpaper.pathExtension.isEmpty ? "jpg" : wallpaper.pathExtension
                let wallpaperDestination = directory.appendingPathComponent("wallpaper.\(extensionName)")
                try fileSystem.copyItem(at: wallpaper, to: wallpaperDestination)
                profile.wallpaper = wallpaperDestination.lastPathComponent
            }
            try snapshotDirectoryIfPresent(
                homeURL.appendingPathComponent(".config", isDirectory: true),
                to: directory.appendingPathComponent("home/.config", isDirectory: true)
            )
            try captureEditorSettings(to: directory)
        }
    }

    func deleteProfile(_ descriptor: ProfileDescriptor) throws {
        guard try fileSystem.state(at: descriptor.directory).exists else {
            throw ProfileServiceError.profileNotFound(descriptor.displayName)
        }
        guard activeProfile?.directory != descriptor.directory else {
            throw ProfileServiceError.cannotDeleteActiveProfile
        }
        do {
            var resultingURL: NSURL?
            try fileManager.trashItem(at: descriptor.directory, resultingItemURL: &resultingURL)
            reload()
        } catch {
            throw ProfileServiceError.deletionFailed(error.localizedDescription)
        }
    }

    func updateWallpaper(for descriptor: ProfileDescriptor, from sourceURL: URL) throws -> ProfileDescriptor {
        guard try fileSystem.state(at: sourceURL).exists else {
            throw ProfileServiceError.fileNotFound(sourceURL.path)
        }
        let extensionName = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        var destination = descriptor.directory.appendingPathComponent("wallpaper.\(extensionName)")
        var index = 2
        while try fileSystem.state(at: destination).exists {
            destination = descriptor.directory.appendingPathComponent("wallpaper-\(index).\(extensionName)")
            index += 1
        }
        try fileSystem.copyItem(at: sourceURL, to: destination)
        var profile = descriptor.profile
        profile.wallpaper = destination.lastPathComponent
        try saveProfileDefinition(profile, in: descriptor.directory)
        reload()
        return profiles.first(where: { $0.directory.path == descriptor.directory.path })
            ?? ProfileDescriptor(profile: profile, directory: descriptor.directory)
    }

    func saveCurrentConfigToActiveProfile() throws {
        guard let activeProfile else {
            throw ProfileServiceError.profileNotFound("No active profile")
        }
        try saveCurrentConfigToSpecificProfile(activeProfile)
    }

    func saveCurrentConfigToSpecificProfile(_ descriptor: ProfileDescriptor) throws {
        try captureEditorSettings(to: descriptor.directory)
        reload()
    }

    private func createProfile(
        name: String,
        operation: String,
        populate: (_ directory: URL, _ profile: inout Profile) throws -> Void
    ) throws -> ProfileDescriptor {
        let sanitized = try validatedProfileName(name)
        let destination = profilesURL.appendingPathComponent(sanitized, isDirectory: true)
        guard try fileSystem.state(at: destination).kind == .absent else {
            throw ProfileServiceError.profileAlreadyExists(sanitized)
        }

        try ensureDirectoryHierarchy(profilesURL)
        let stage = profilesURL.appendingPathComponent(
            ".\(sanitized).ricebarmac-stage-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        var createdStage = false
        var profile = Profile(name: sanitized)

        do {
            try fileSystem.createDirectory(at: stage)
            createdStage = true
            try fileSystem.createDirectory(at: stage.appendingPathComponent("home", isDirectory: true))
            try populate(stage, &profile)
            try saveProfile(profile, at: stage.appendingPathComponent("profile.json"))
            guard try fileSystem.state(at: destination).kind == .absent else {
                throw ProfileServiceError.profileAlreadyExists(sanitized)
            }
            try fileSystem.moveItem(at: stage, to: destination)
            createdStage = false
        } catch let error as ProfileServiceError {
            if createdStage { try? fileSystem.removeItem(at: stage) }
            throw error
        } catch {
            if createdStage { try? fileSystem.removeItem(at: stage) }
            throw ProfileServiceError.fileOperationFailed(operation, error)
        }

        reload()
        configureWatching(enabled: watchingEnabled)
        return profiles.first(where: { $0.directory.path == destination.path })
            ?? ProfileDescriptor(profile: profile, directory: destination)
    }

    // MARK: - Watcher lifecycle

    func configureWatching(enabled: Bool) {
        watchingEnabled = enabled
        if enabled {
            startWatching()
        } else {
            stopWatching()
        }
    }

    private func startWatching() {
        stopWatching()
        guard (try? fileSystem.state(at: profilesURL).kind) == .directory else { return }

        let paths = [profilesURL.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot
        )
        stream = FSEventStreamCreate(
            nil,
            { _, clientInfo, eventCount, eventPaths, _, _ in
                guard let clientInfo else { return }
                let service = Unmanaged<ProfileService>.fromOpaque(clientInfo).takeUnretainedValue()
                let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
                var changed: [String] = []
                for index in 0..<eventCount {
                    if let path = paths[Int(index)] {
                        changed.append(String(cString: path))
                    }
                }
                service.handleMetadataChanges(changed)
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Constants.fileWatchDebounceInterval,
            flags
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    private func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamSetDispatchQueue(stream, nil)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func handleMetadataChanges(_ changedPaths: [String]) {
        guard watchingEnabled else { return }
        let relevant = changedPaths.contains { path in
            !path.contains(".ricebarmac-backup-") &&
            !path.contains(".ricebarmac-stage-") &&
            !path.contains("/transactions/")
        }
        guard relevant else { return }
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reload()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.fileWatchDebounceInterval, execute: workItem)
    }

    // MARK: - Coordinator state

    private func bindCoordinator() {
        Task { [weak self] in
            guard let self else { return }
            await coordinator.setStateHandler { [weak self] state in
                DispatchQueue.main.async {
                    self?.operationState = state
                    self?.isApplying = state.phase == .applying || state.phase == .rollingBack || state.phase == .undoing
                }
            }
            await refreshTransactionMetadata()
        }
    }

    private func refreshTransactionMetadata() async {
        let recovery = (try? await coordinator.incompleteTransactions()) ?? []
        let undoable = (try? await coordinator.latestUndoable()) != nil
        await MainActor.run {
            self.recoveryTransactions = recovery
            self.canUndo = undoable
        }
    }

    private func publishOperationError(_ error: Error) {
        publishOnMain {
            self.operationState = ProfileOperationSnapshot(
                phase: .failed,
                message: error.localizedDescription,
                completedActions: 0,
                totalActions: 0,
                queuePosition: nil,
                transactionID: nil,
                affectedPaths: []
            )
        }
    }

    // MARK: - Profile serialization

    private func loadProfileDefinition(at directory: URL) throws -> Profile? {
        guard let source = profileSource(in: directory) else { return nil }
        let data = try fileSystem.readData(at: source)
        var profile: Profile
        if source.pathExtension.lowercased() == "json" {
            profile = try JSONDecoder().decode(Profile.self, from: data)
        } else {
            #if canImport(Yams)
            profile = try YAMLDecoder().decode(Profile.self, from: String(decoding: data, as: UTF8.self))
            #else
            profile = try JSONDecoder().decode(Profile.self, from: data)
            #endif
        }
        if profile.wallpaper == nil, let wallpaper = firstImage(in: directory) {
            profile.wallpaper = wallpaper.lastPathComponent
        }
        if profile.hotkey == nil {
            profile.hotkey = readHotkey(in: directory)
        }
        return profile
    }

    private func profileSource(in directory: URL) -> URL? {
        Constants.profileFileCandidates
            .map { directory.appendingPathComponent($0) }
            .first(where: { (try? fileSystem.state(at: $0).exists) == true })
    }

    private func saveProfileDefinition(_ profile: Profile, in directory: URL) throws {
        let source = profileSource(in: directory) ?? directory.appendingPathComponent("profile.json")
        if source.pathExtension.lowercased() == "json" {
            try saveProfile(profile, at: source)
        } else {
            #if canImport(Yams)
            let string = try YAMLEncoder().encode(profile)
            try atomicReplace(Data(string.utf8), at: source)
            #else
            try saveProfile(profile, at: directory.appendingPathComponent("profile.json"))
            #endif
        }
    }

    private func saveProfile(_ profile: Profile, at url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try atomicReplace(try encoder.encode(profile), at: url)
    }

    private func atomicReplace(_ data: Data, at destination: URL) throws {
        try ensureDirectoryHierarchy(destination.deletingLastPathComponent())
        let identifier = UUID().uuidString.lowercased()
        let parent = destination.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".\(destination.lastPathComponent).ricebarmac-stage-\(identifier)")
        let backup = parent.appendingPathComponent(".\(destination.lastPathComponent).ricebarmac-backup-\(identifier)")
        try fileSystem.writeDataAtomically(data, to: stage)
        var movedOriginal = false
        do {
            if try fileSystem.state(at: destination).exists {
                try fileSystem.moveItem(at: destination, to: backup)
                movedOriginal = true
            }
            try fileSystem.moveItem(at: stage, to: destination)
        } catch {
            try? fileSystem.removeItem(at: stage)
            if movedOriginal, (try? fileSystem.state(at: destination).kind) == .absent {
                try? fileSystem.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    private func defaultProfile(for directory: URL) -> Profile {
        var profile = Profile(name: directory.lastPathComponent)
        profile.hotkey = readHotkey(in: directory)
        profile.wallpaper = firstImage(in: directory)?.lastPathComponent
        return profile
    }

    private func readHotkey(in directory: URL) -> String? {
        let url = directory.appendingPathComponent("hotkey.txt")
        guard let data = try? fileSystem.readData(at: url) else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstImage(in directory: URL) -> URL? {
        guard let items = try? fileSystem.contentsOfDirectory(at: directory) else { return nil }
        let images = items.filter { Constants.wallpaperExtensions.contains($0.pathExtension.lowercased()) }
        return images.first(where: { item in
            let name = item.deletingPathExtension().lastPathComponent.lowercased()
            return Constants.preferredWallpaperPrefixes.contains(where: { name.hasPrefix($0) })
        }) ?? images.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first
    }

    // MARK: - Capture helpers

    private func currentWallpaperURL() -> URL? {
        guard let screen = NSScreen.main,
              let url = try? NSWorkspace.shared.desktopImageURL(for: screen),
              (try? fileSystem.state(at: url).exists) == true else {
            return nil
        }
        return url
    }

    private func captureEditorSettings(to profileDirectory: URL) throws {
        try captureEditor(
            from: homeURL.appendingPathComponent("Library/Application Support/Code/User", isDirectory: true),
            to: profileDirectory.appendingPathComponent("vscode", isDirectory: true)
        )
        try captureEditor(
            from: homeURL.appendingPathComponent("Library/Application Support/Cursor/User", isDirectory: true),
            to: profileDirectory.appendingPathComponent("cursor", isDirectory: true)
        )
    }

    private func captureEditor(from sourceDirectory: URL, to destinationDirectory: URL) throws {
        guard try fileSystem.state(at: sourceDirectory).kind == .directory else { return }
        try ensureDirectoryHierarchy(destinationDirectory)
        for name in ["settings.json", "keybindings.json", "snippets"] {
            let source = sourceDirectory.appendingPathComponent(name)
            guard try fileSystem.state(at: source).exists else { continue }
            let destination = destinationDirectory.appendingPathComponent(name)
            try copyReplacing(source, at: destination)
        }
    }

    private func snapshotDirectoryIfPresent(_ source: URL, to destination: URL) throws {
        guard try fileSystem.state(at: source).kind == .directory else { return }
        try copyReplacing(source, at: destination)
    }

    private func copyReplacing(_ source: URL, at destination: URL) throws {
        try ensureDirectoryHierarchy(destination.deletingLastPathComponent())
        let identifier = UUID().uuidString.lowercased()
        let parent = destination.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".\(destination.lastPathComponent).ricebarmac-stage-\(identifier)")
        let backup = parent.appendingPathComponent(".\(destination.lastPathComponent).ricebarmac-backup-\(identifier)")
        guard try fileSystem.state(at: stage).kind == .absent,
              try fileSystem.state(at: backup).kind == .absent else {
            throw FileSystemClientError.collision(destination.path)
        }

        var staged = true
        var movedOriginal = false
        do {
            try fileSystem.copyItem(at: source, to: stage)
            if try fileSystem.state(at: destination).exists {
                try fileSystem.moveItem(at: destination, to: backup)
                movedOriginal = true
            }
            try fileSystem.moveItem(at: stage, to: destination)
            staged = false
        } catch {
            if staged { try? fileSystem.removeItem(at: stage) }
            if movedOriginal {
                do {
                    guard try fileSystem.state(at: destination).kind == .absent else {
                        throw FileSystemClientError.stalePath(destination.path)
                    }
                    try fileSystem.moveItem(at: backup, to: destination)
                } catch let rollbackError {
                    throw ProfileServiceError.fileOperationFailed(
                        "restore capture backup at \(backup.path)",
                        rollbackError
                    )
                }
            }
            throw error
        }
    }

    // MARK: - Path helpers

    private func validatedProfileName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.count <= Constants.maxProfileNameLength,
              value.rangeOfCharacter(from: Constants.invalidProfileNameCharacters) == nil,
              !Constants.reservedProfileNames.contains(value.lowercased()) else {
            throw ProfileServiceError.invalidProfileName
        }
        return value
    }

    private func ensureDirectoryHierarchy(_ directory: URL) throws {
        let state = try fileSystem.state(at: directory)
        if state.kind == .directory { return }
        if state.exists { throw FileSystemClientError.parentIsNotDirectory(directory.path) }
        let parent = directory.deletingLastPathComponent()
        if parent.path != directory.path { try ensureDirectoryHierarchy(parent) }
        do {
            try fileSystem.createDirectory(at: directory)
        } catch {
            if try fileSystem.state(at: directory).kind != .directory { throw error }
        }
    }

    private func publishOnMain(_ update: @escaping () -> Void) {
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }
}
