import Foundation

final class ProfilePlanner: @unchecked Sendable {
    private let home: URL
    private let fileSystem: FileSystemClient
    private let safety: PathSafetyValidator
    private let now: @Sendable () -> Date
    private let nextID: @Sendable () -> UUID

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: FileSystemClient = LiveFileSystemClient(),
        now: @escaping @Sendable () -> Date = { Date() },
        nextID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.home = home.standardizedFileURL
        self.fileSystem = fileSystem
        self.safety = PathSafetyValidator(home: home, fileSystem: fileSystem)
        self.now = now
        self.nextID = nextID
    }

    func makePlan(
        for descriptor: ProfileDescriptor,
        formerActiveProfilePath: String?
    ) -> ProfileApplyPlan {
        let transactionID = nextID()
        var builder = Builder(
            transactionID: transactionID,
            descriptor: descriptor,
            formerActiveProfilePath: formerActiveProfilePath,
            home: home,
            fileSystem: fileSystem,
            safety: safety,
            nextID: nextID
        )

        do {
            try descriptor.validate()
        } catch {
            builder.addIssue(.invalidProfile, error.localizedDescription, descriptor.directory.path)
        }

        builder.planProfile()

        if builder.actions.count >= 1_000 {
            builder.addWarning(
                .largePlan,
                "This profile contains \(builder.actions.count) filesystem actions. Applying it may take some time.",
                nil
            )
        }

        return ProfileApplyPlan(
            id: transactionID,
            createdAt: now(),
            profileID: descriptor.id,
            profileName: descriptor.displayName,
            profileDirectoryPath: descriptor.directory.standardizedFileURL.path,
            formerActiveProfilePath: formerActiveProfilePath,
            userHomePath: home.path,
            actions: builder.actions,
            externalEffects: builder.externalEffects,
            warnings: builder.warnings,
            issues: builder.issues
        )
    }
}

private extension ProfilePlanner {
    struct Builder {
        let transactionID: UUID
        let descriptor: ProfileDescriptor
        let formerActiveProfilePath: String?
        let home: URL
        let fileSystem: FileSystemClient
        let safety: PathSafetyValidator
        let nextID: @Sendable () -> UUID

        var actions: [PlannedFileAction] = []
        var externalEffects: [ProfileExternalEffect] = []
        var warnings: [ProfilePlanWarning] = []
        var issues: [ProfilePlanIssue] = []

        private var plannedDestinations: [String: PlannedFileAction] = [:]

        init(
            transactionID: UUID,
            descriptor: ProfileDescriptor,
            formerActiveProfilePath: String?,
            home: URL,
            fileSystem: FileSystemClient,
            safety: PathSafetyValidator,
            nextID: @escaping @Sendable () -> UUID
        ) {
            self.transactionID = transactionID
            self.descriptor = descriptor
            self.formerActiveProfilePath = formerActiveProfilePath
            self.home = home
            self.fileSystem = fileSystem
            self.safety = safety
            self.nextID = nextID
        }

        mutating func planProfile() {
            let profile = descriptor.profile

            if let replacements = profile.replacements, !replacements.isEmpty {
                for replacement in replacements.sorted(by: { $0.destination < $1.destination }) {
                    let source = descriptor.directory.appendingPathComponent(replacement.source).standardizedFileURL
                    let destination = expandedDestination(replacement.destination)
                    addSymlink(source: source, destination: destination)
                }
            } else {
                let overlay = descriptor.directory.appendingPathComponent("home", isDirectory: true)
                planOverlay(from: overlay, to: home)
            }

            planTerminal(profile.terminal)
            planEditors(profile)

            if let wallpaper = profile.wallpaper {
                let source = descriptor.directory.appendingPathComponent(wallpaper).standardizedFileURL
                if validateSource(source) {
                    externalEffects.append(ProfileExternalEffect(id: nextID(), kind: .wallpaper, path: source.path, arguments: []))
                    addWarning(.nonReversibleEffect, "Wallpaper changes run after the reversible filesystem commit.", source.path)
                }
            }

            if let script = profile.startupScript {
                let source = descriptor.directory.appendingPathComponent(script).standardizedFileURL
                if validateSource(source) {
                    externalEffects.append(ProfileExternalEffect(id: nextID(), kind: .startupScript, path: source.path, arguments: []))
                    addWarning(.nonReversibleEffect, "The startup script cannot be rolled back and runs only after commit.", source.path)
                }
            }

            if profile.systemTheme != nil {
                addWarning(
                    .unsupportedIntegration,
                    "System-theme declarations are not implemented in v0.20 and will not be applied.",
                    nil
                )
            }
        }

        mutating func planTerminal(_ terminal: Profile.Terminal?) {
            guard let terminal else { return }
            switch terminal.kind {
            case .alacritty:
                let candidates: [URL]
                if let theme = terminal.theme {
                    candidates = [descriptor.directory.appendingPathComponent(theme)]
                } else {
                    candidates = [
                        descriptor.directory.appendingPathComponent("alacritty.yml"),
                        descriptor.directory.appendingPathComponent("alacritty.toml"),
                        descriptor.directory.appendingPathComponent("alacritty/alacritty.yml"),
                        descriptor.directory.appendingPathComponent("alacritty/alacritty.toml")
                    ]
                }
                guard let source = candidates.first(where: { (try? fileSystem.state(at: $0).exists) == true }) else {
                    if terminal.theme != nil {
                        addIssue(.missingSource, "The configured Alacritty theme was not found.", candidates.first?.path)
                    }
                    return
                }
                let usesToml = source.pathExtension.lowercased() == "toml"
                let destinationName = usesToml ? "alacritty.toml" : "alacritty.yml"
                let alternateName = usesToml ? "alacritty.yml" : "alacritty.toml"
                let directory = home.appendingPathComponent(".config/alacritty", isDirectory: true)
                addSymlink(source: source, destination: directory.appendingPathComponent(destinationName))
                addRemovalIfPresent(directory.appendingPathComponent(alternateName))
                externalEffects.append(ProfileExternalEffect(id: nextID(), kind: .reloadAlacritty, path: nil, arguments: []))
                addWarning(.nonReversibleEffect, "Alacritty reload runs after the reversible configuration commit.", nil)
            case .terminalApp:
                addWarning(.unsupportedIntegration, "Terminal.app themes are not implemented and will not be applied.", nil)
            case .iterm2:
                addWarning(.unsupportedIntegration, "iTerm2 themes are not implemented and will not be applied.", nil)
            }
        }

        mutating func planEditors(_ profile: Profile) {
            if let ide = profile.ide {
                planExplicitEditor(ide)
            }

            planEditorDirectory(
                sourceDirectory: descriptor.directory.appendingPathComponent("vscode", isDirectory: true),
                destinationDirectory: home.appendingPathComponent("Library/Application Support/Code/User", isDirectory: true)
            )
            planEditorDirectory(
                sourceDirectory: descriptor.directory.appendingPathComponent("cursor", isDirectory: true),
                destinationDirectory: home.appendingPathComponent("Library/Application Support/Cursor/User", isDirectory: true)
            )

            let capturedRoot = descriptor.directory.appendingPathComponent("vscode", isDirectory: true)
            planEditorDirectory(
                sourceDirectory: capturedRoot.appendingPathComponent("vscode/User", isDirectory: true),
                destinationDirectory: home.appendingPathComponent("Library/Application Support/Code/User", isDirectory: true)
            )
            planEditorDirectory(
                sourceDirectory: capturedRoot.appendingPathComponent("cursor/User", isDirectory: true),
                destinationDirectory: home.appendingPathComponent("Library/Application Support/Cursor/User", isDirectory: true)
            )
        }

        mutating func planExplicitEditor(_ ide: Profile.IDE) {
            let destinationDirectory: URL
            let extensionKind: ProfileExternalEffect.Kind
            let fallbackDirectory: URL
            switch ide.kind {
            case .vscode:
                destinationDirectory = home.appendingPathComponent("Library/Application Support/Code/User", isDirectory: true)
                extensionKind = .installVSCodeExtensions
                fallbackDirectory = descriptor.directory.appendingPathComponent("vscode", isDirectory: true)
            case .cursor:
                destinationDirectory = home.appendingPathComponent("Library/Application Support/Cursor/User", isDirectory: true)
                extensionKind = .installCursorExtensions
                fallbackDirectory = descriptor.directory.appendingPathComponent("cursor", isDirectory: true)
            }

            if let theme = ide.theme, theme.hasPrefix("@id:") {
                let themeName = String(theme.dropFirst(4))
                planEditorTheme(themeName, settingsURL: destinationDirectory.appendingPathComponent("settings.json"))
            } else if let theme = ide.theme {
                let source = descriptor.directory.appendingPathComponent(theme).standardizedFileURL
                if (try? fileSystem.state(at: source).kind) == .directory {
                    planEditorDirectory(sourceDirectory: source, destinationDirectory: destinationDirectory)
                } else {
                    addSymlink(source: source, destination: destinationDirectory.appendingPathComponent("settings.json"))
                }
            } else {
                planEditorDirectory(sourceDirectory: fallbackDirectory, destinationDirectory: destinationDirectory)
            }

            if let extensions = ide.extensions?.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), !extensions.isEmpty {
                externalEffects.append(ProfileExternalEffect(id: nextID(), kind: extensionKind, path: nil, arguments: extensions))
                addWarning(.nonReversibleEffect, "Editor extension installation runs after commit and cannot be rolled back.", nil)
            }
        }

        mutating func planEditorTheme(_ themeName: String, settingsURL: URL) {
            var settings: [String: Any] = [:]
            do {
                if try fileSystem.state(at: settingsURL).exists {
                    let data = try fileSystem.readData(at: settingsURL)
                    guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        addIssue(.unreadablePath, "Editor settings are not a JSON object.", settingsURL.path)
                        return
                    }
                    settings = decoded
                }
                settings["workbench.colorTheme"] = themeName
                let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
                addAction(kind: .writeData, source: nil, destination: settingsURL, data: data)
            } catch {
                addIssue(.unreadablePath, "Could not prepare editor settings: \(error.localizedDescription)", settingsURL.path)
            }
        }

        mutating func planEditorDirectory(sourceDirectory: URL, destinationDirectory: URL) {
            guard (try? fileSystem.state(at: sourceDirectory).kind) == .directory else { return }
            let recognized = ["settings.json", "keybindings.json", "snippets"]
            for name in recognized {
                let source = sourceDirectory.appendingPathComponent(name)
                guard let state = try? fileSystem.state(at: source), state.exists else { continue }
                if state.kind == .directory {
                    planOverlay(from: source, to: destinationDirectory.appendingPathComponent(name, isDirectory: true))
                } else {
                    addSymlink(source: source, destination: destinationDirectory.appendingPathComponent(name))
                }
            }
        }

        mutating func planOverlay(from sourceDirectory: URL, to destinationDirectory: URL) {
            guard let rootState = try? fileSystem.state(at: sourceDirectory), rootState.kind == .directory else { return }
            do {
                let entries = try fileSystem.enumeratedContents(at: sourceDirectory).sorted { $0.path < $1.path }
                for source in entries {
                    let name = source.lastPathComponent
                    if shouldSkip(name) { continue }
                    let relative = String(source.standardizedFileURL.path.dropFirst(sourceDirectory.standardizedFileURL.path.count + 1))
                    let destination = destinationDirectory.appendingPathComponent(relative)
                    let state = try fileSystem.state(at: source)
                    switch state.kind {
                    case .directory:
                        addDirectoryIfNeeded(destination)
                    case .regularFile, .symbolicLink:
                        addSymlink(source: source, destination: destination)
                    case .absent:
                        addIssue(.missingSource, "A profile source disappeared during preview.", source.path)
                    case .other:
                        addIssue(.unreadablePath, "Unsupported profile source object.", source.path)
                    }
                }
            } catch {
                addIssue(.unreadablePath, "Could not enumerate profile files: \(error.localizedDescription)", sourceDirectory.path)
            }
        }

        mutating func addDirectoryIfNeeded(_ destination: URL) {
            do {
                let state = try fileSystem.state(at: destination)
                if state.kind == .directory { return }
                if state.exists {
                    addIssue(.parentIsNotDirectory, "A required directory path is occupied by \(state.displayName.lowercased()).", destination.path)
                    return
                }
                addMissingParentDirectories(for: destination)
                addAction(kind: .createDirectory, source: nil, destination: destination, data: nil)
            } catch {
                addIssue(.unreadablePath, error.localizedDescription, destination.path)
            }
        }

        mutating func addSymlink(source: URL, destination: URL) {
            guard validateSource(source) else { return }
            do {
                let sourceState = try fileSystem.state(at: source)
                guard sourceState.exists else {
                    addIssue(.missingSource, "Profile source does not exist.", source.path)
                    return
                }
                let normalizedSource = source.standardizedFileURL.path
                let normalizedDestination = destination.standardizedFileURL.path
                if normalizedSource == normalizedDestination ||
                    normalizedSource.hasPrefix(normalizedDestination + "/") ||
                    normalizedDestination.hasPrefix(normalizedSource + "/") {
                    addIssue(.recursiveMapping, "Source and destination recursively contain one another.", destination.path)
                    return
                }

                let before = try fileSystem.state(at: destination)
                if before.kind == .symbolicLink,
                   let currentTarget = before.symlinkTarget,
                   resolvedLinkTarget(currentTarget, at: destination) == source.standardizedFileURL {
                    return
                }
                addMissingParentDirectories(for: destination)
                addAction(kind: .replaceWithSymlink, source: source, destination: destination, data: nil)
            } catch {
                addIssue(.unreadablePath, error.localizedDescription, source.path)
            }
        }

        mutating func addRemovalIfPresent(_ destination: URL) {
            do {
                if try fileSystem.state(at: destination).exists {
                    addAction(kind: .remove, source: nil, destination: destination, data: nil)
                }
            } catch {
                addIssue(.unreadablePath, error.localizedDescription, destination.path)
            }
        }

        mutating func addMissingParentDirectories(for destination: URL) {
            let normalized = destination.standardizedFileURL
            guard safety.isStrictlyInsideHome(normalized) else { return }
            let relative = String(normalized.deletingLastPathComponent().path.dropFirst(home.path.count))
            let components = relative.split(separator: "/").map(String.init)
            var current = home
            for component in components {
                current.appendPathComponent(component, isDirectory: true)
                do {
                    let state = try fileSystem.state(at: current)
                    if state.kind == .absent && plannedDestinations[current.path] == nil {
                        addAction(kind: .createDirectory, source: nil, destination: current, data: nil)
                    }
                } catch {
                    addIssue(.unreadablePath, error.localizedDescription, current.path)
                }
            }
        }

        mutating func addAction(kind: PlannedFileAction.Kind, source: URL?, destination: URL, data: Data?) {
            let normalizedDestination = destination.standardizedFileURL
            let destinationPath = normalizedDestination.path

            if isProtectedDestination(normalizedDestination) {
                addIssue(
                    .protectedDestination,
                    "Profiles cannot modify RiceBarMac's configuration, migration, backup, or transaction storage.",
                    destinationPath
                )
                return
            }

            do {
                let parentFingerprints = try safety.validateDestination(normalizedDestination)
                let beforeState = try fileSystem.state(at: normalizedDestination)
                let hiddenBase = ".\(normalizedDestination.lastPathComponent)"
                let parent = normalizedDestination.deletingLastPathComponent()
                let suffix = "\(transactionID.uuidString.lowercased())-\(actions.count)"
                let backup = parent.appendingPathComponent("\(hiddenBase).ricebarmac-backup-\(suffix)")
                let stage = parent.appendingPathComponent("\(hiddenBase).ricebarmac-stage-\(suffix)")

                if try fileSystem.state(at: backup).exists {
                    addIssue(.backupCollision, "The reserved backup path already exists.", backup.path)
                    return
                }
                if try fileSystem.state(at: stage).exists {
                    addIssue(.stagingCollision, "The reserved staging path already exists.", stage.path)
                    return
                }

                if let existing = plannedDestinations[destinationPath] {
                    if existing.kind == kind && existing.sourcePath == source?.standardizedFileURL.path {
                        return
                    }
                    addIssue(.duplicateDestination, "More than one action targets the same destination.", destinationPath)
                    return
                }

                for existing in plannedDestinations.values {
                    let existingPath = existing.destinationPath
                    let nestedConflict = destinationPath.hasPrefix(existingPath + "/") && existing.kind != .createDirectory
                    let ancestorConflict = existingPath.hasPrefix(destinationPath + "/") && kind != .createDirectory
                    if nestedConflict || ancestorConflict {
                        addIssue(.conflictingDestination, "Planned destinations have an incompatible ancestor relationship.", destinationPath)
                        return
                    }
                }

                let action = PlannedFileAction(
                    id: nextID(),
                    index: actions.count,
                    kind: kind,
                    sourcePath: source?.standardizedFileURL.path,
                    sourceState: try source.map { try fileSystem.state(at: $0) },
                    destinationPath: destinationPath,
                    backupPath: backup.path,
                    stagingPath: stage.path,
                    beforeState: beforeState,
                    parentFingerprints: parentFingerprints,
                    data: data
                )
                actions.append(action)
                plannedDestinations[destinationPath] = action

                if beforeState.exists && kind != .createDirectory {
                    addWarning(
                        .replacesExistingItem,
                        "\(beforeState.displayName) at \(destinationPath) will be preserved at \(backup.path).",
                        destinationPath
                    )
                }
            } catch let error as FileSystemClientError {
                switch error {
                case .destinationOutsideHome:
                    addIssue(.destinationOutsideHome, error.localizedDescription, destinationPath)
                case .unsafeParentSymlink, .symlinkLoop:
                    addIssue(.unsafeParentSymlink, error.localizedDescription, destinationPath)
                case .parentIsNotDirectory:
                    addIssue(.parentIsNotDirectory, error.localizedDescription, destinationPath)
                default:
                    addIssue(.unreadablePath, error.localizedDescription, destinationPath)
                }
            } catch {
                addIssue(.unreadablePath, error.localizedDescription, destinationPath)
            }
        }

        mutating func validateSource(_ source: URL) -> Bool {
            do {
                try safety.validateSource(source, profileDirectory: descriptor.directory)
                let state = try fileSystem.state(at: source)
                guard state.exists else {
                    addIssue(.missingSource, "Profile source does not exist.", source.path)
                    return false
                }
                guard state.kind != .other else {
                    addIssue(.unreadablePath, "Unsupported profile source object.", source.path)
                    return false
                }
                return true
            } catch let error as FileSystemClientError {
                switch error {
                case .sourceOutsideProfile:
                    addIssue(.sourceOutsideProfile, error.localizedDescription, source.path)
                default:
                    addIssue(.unreadablePath, error.localizedDescription, source.path)
                }
                return false
            } catch {
                addIssue(.unreadablePath, error.localizedDescription, source.path)
                return false
            }
        }

        mutating func addIssue(_ code: ProfilePlanIssue.Code, _ message: String, _ path: String?) {
            if issues.contains(where: { $0.code == code && $0.affectedPath == path && $0.message == message }) { return }
            issues.append(ProfilePlanIssue(id: nextID(), code: code, message: message, affectedPath: path))
        }

        mutating func addWarning(_ code: ProfilePlanWarning.Code, _ message: String, _ path: String?) {
            if warnings.contains(where: { $0.code == code && $0.affectedPath == path && $0.message == message }) { return }
            warnings.append(ProfilePlanWarning(id: nextID(), code: code, message: message, affectedPath: path))
        }

        func expandedDestination(_ path: String) -> URL {
            if path == "~" { return home }
            if path.hasPrefix("~/") {
                return home.appendingPathComponent(String(path.dropFirst(2))).standardizedFileURL
            }
            return URL(fileURLWithPath: path).standardizedFileURL
        }

        func resolvedLinkTarget(_ target: String, at destination: URL) -> URL {
            if target.hasPrefix("/") {
                return URL(fileURLWithPath: target).standardizedFileURL
            }
            return destination.deletingLastPathComponent().appendingPathComponent(target).standardizedFileURL
        }

        func isProtectedDestination(_ destination: URL) -> Bool {
            let normalized = destination.standardizedFileURL.path
            guard normalized.hasPrefix(home.path + "/") else { return false }
            let relative = String(normalized.dropFirst(home.path.count + 1))
            guard let firstComponent = relative.split(separator: "/").first else { return false }
            return firstComponent == ".ricebar" ||
                firstComponent == ".ricebarmac" ||
                firstComponent.hasPrefix(".ricebarmac-")
        }

        func shouldSkip(_ name: String) -> Bool {
            name == ".DS_Store" || name.hasSuffix(".bak") || name.contains(".ricebarmac-backup-") || name.contains(".ricebarmac-stage-")
        }
    }
}
