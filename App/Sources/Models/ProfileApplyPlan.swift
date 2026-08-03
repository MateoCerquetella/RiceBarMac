import Foundation

struct PathFingerprint: Codable, Equatable, Hashable, Sendable {
    let kind: FileObjectState.Kind
    let device: UInt64?
    let inode: UInt64?
    let size: UInt64?
    let modificationDate: Date?
    let symlinkTarget: String?
}

struct FileObjectState: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case absent
        case regularFile
        case directory
        case symbolicLink
        case other
    }

    let kind: Kind
    let permissions: UInt16?
    let device: UInt64?
    let inode: UInt64?
    let size: UInt64?
    let modificationDate: Date?
    let symlinkTarget: String?

    static let absent = FileObjectState(
        kind: .absent,
        permissions: nil,
        device: nil,
        inode: nil,
        size: nil,
        modificationDate: nil,
        symlinkTarget: nil
    )

    var exists: Bool { kind != .absent }

    var fingerprint: PathFingerprint {
        PathFingerprint(
            kind: kind,
            device: device,
            inode: inode,
            size: size,
            modificationDate: modificationDate,
            symlinkTarget: symlinkTarget
        )
    }

    var displayName: String {
        switch kind {
        case .absent: return "Nothing"
        case .regularFile: return "File"
        case .directory: return "Directory"
        case .symbolicLink: return "Symbolic link"
        case .other: return "Filesystem object"
        }
    }
}

struct ParentPathFingerprint: Codable, Equatable, Hashable, Sendable {
    let path: String
    let state: PathFingerprint
}

struct PlannedFileAction: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case createDirectory
        case replaceWithSymlink
        case replaceWithCopy
        case writeData
        case remove
    }

    let id: UUID
    let index: Int
    let kind: Kind
    let sourcePath: String?
    let sourceState: FileObjectState?
    let destinationPath: String
    let backupPath: String
    let stagingPath: String
    let beforeState: FileObjectState
    let parentFingerprints: [ParentPathFingerprint]
    let data: Data?

    var changesExistingItem: Bool { beforeState.exists }

    var displaySummary: String {
        switch kind {
        case .createDirectory:
            return "Create directory \(destinationPath)"
        case .replaceWithSymlink:
            return "Link \(destinationPath) → \(sourcePath ?? "unknown source")"
        case .replaceWithCopy:
            return "Copy \(sourcePath ?? "unknown source") → \(destinationPath)"
        case .writeData:
            return "Write \(destinationPath)"
        case .remove:
            return "Remove \(destinationPath) (recoverable backup: \(backupPath))"
        }
    }
}

struct ProfileExternalEffect: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case wallpaper
        case reloadAlacritty
        case installVSCodeExtensions
        case installCursorExtensions
        case startupScript
    }

    let id: UUID
    let kind: Kind
    let path: String?
    let arguments: [String]

    var displaySummary: String {
        switch kind {
        case .wallpaper: return "Set wallpaper to \(path ?? "unknown file")"
        case .reloadAlacritty: return "Reload Alacritty"
        case .installVSCodeExtensions: return "Install VS Code extensions: \(arguments.joined(separator: ", "))"
        case .installCursorExtensions: return "Install Cursor extensions: \(arguments.joined(separator: ", "))"
        case .startupScript: return "Run startup script \(path ?? "unknown script")"
        }
    }
}

struct ProfilePlanWarning: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Code: String, Codable, Sendable {
        case replacesExistingItem
        case nonReversibleEffect
        case unsupportedIntegration
        case largePlan
    }

    let id: UUID
    let code: Code
    let message: String
    let affectedPath: String?
}

struct ProfilePlanIssue: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Code: String, Codable, Sendable {
        case missingSource
        case sourceOutsideProfile
        case destinationOutsideHome
        case destinationIsHome
        case protectedDestination
        case unsafeParentSymlink
        case parentIsNotDirectory
        case recursiveMapping
        case duplicateDestination
        case conflictingDestination
        case backupCollision
        case stagingCollision
        case unreadablePath
        case invalidProfile
    }

    let id: UUID
    let code: Code
    let message: String
    let affectedPath: String?
}

struct ProfileApplyPlan: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let profileID: String
    let profileName: String
    let profileDirectoryPath: String
    let formerActiveProfilePath: String?
    let userHomePath: String
    let actions: [PlannedFileAction]
    let externalEffects: [ProfileExternalEffect]
    let warnings: [ProfilePlanWarning]
    let issues: [ProfilePlanIssue]

    var isValid: Bool { issues.isEmpty }

    var previewText: String {
        var sections: [String] = []
        if actions.isEmpty {
            sections.append("No reversible filesystem changes.")
        } else {
            sections.append(actions.map { "\($0.index + 1). \($0.displaySummary)" }.joined(separator: "\n"))
        }
        if !externalEffects.isEmpty {
            sections.append("After commit:\n" + externalEffects.map { "• \($0.displaySummary)" }.joined(separator: "\n"))
        }
        if !warnings.isEmpty {
            sections.append("Warnings:\n" + warnings.map { "• \($0.message)" }.joined(separator: "\n"))
        }
        if !issues.isEmpty {
            sections.append("Cannot apply:\n" + issues.map { "• \($0.message)" }.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }
}

struct ProfilePlanningError: LocalizedError, Sendable {
    let issues: [ProfilePlanIssue]

    var errorDescription: String? {
        guard !issues.isEmpty else { return "The profile could not be planned." }
        return issues.map(\.message).joined(separator: "\n")
    }
}
