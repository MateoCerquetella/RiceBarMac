import Foundation
import Darwin

enum FileSystemClientError: LocalizedError, Sendable {
    case inspectionFailed(String, Int32)
    case unsupportedObject(String)
    case destinationOutsideHome(String)
    case sourceOutsideProfile(String)
    case unsafeParentSymlink(String)
    case parentIsNotDirectory(String)
    case symlinkLoop(String)
    case stalePath(String)
    case collision(String)

    var errorDescription: String? {
        switch self {
        case .inspectionFailed(let path, let code):
            return "Could not inspect '\(path)' (errno \(code))."
        case .unsupportedObject(let path):
            return "Unsupported filesystem object at '\(path)'."
        case .destinationOutsideHome(let path):
            return "Destination escapes the user home: \(path)"
        case .sourceOutsideProfile(let path):
            return "Source escapes the selected profile: \(path)"
        case .unsafeParentSymlink(let path):
            return "A parent symlink resolves outside the user home: \(path)"
        case .parentIsNotDirectory(let path):
            return "A destination parent is not a directory: \(path)"
        case .symlinkLoop(let path):
            return "A symlink loop was detected at: \(path)"
        case .stalePath(let path):
            return "The filesystem changed after preview: \(path)"
        case .collision(let path):
            return "A reserved staging or backup path already exists: \(path)"
        }
    }
}

protocol FileSystemClient: Sendable {
    func state(at url: URL) throws -> FileObjectState
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func enumeratedContents(at url: URL) throws -> [URL]
    func readData(at url: URL) throws -> Data
    func createDirectory(at url: URL) throws
    func copyItem(at source: URL, to destination: URL) throws
    func createSymbolicLink(at destination: URL, pointingTo source: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
    func writeDataAtomically(_ data: Data, to url: URL) throws
    func setPermissions(_ permissions: UInt16, at url: URL) throws
}

final class LiveFileSystemClient: FileSystemClient, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func state(at url: URL) throws -> FileObjectState {
        var info = stat()
        let result = url.path.withCString { path in
            lstat(path, &info)
        }

        if result != 0 {
            if errno == ENOENT || errno == ENOTDIR {
                return .absent
            }
            throw FileSystemClientError.inspectionFailed(url.path, errno)
        }

        let objectType = info.st_mode & mode_t(S_IFMT)
        let kind: FileObjectState.Kind
        switch objectType {
        case mode_t(S_IFREG): kind = .regularFile
        case mode_t(S_IFDIR): kind = .directory
        case mode_t(S_IFLNK): kind = .symbolicLink
        default: kind = .other
        }

        let target: String?
        if kind == .symbolicLink {
            target = try fileManager.destinationOfSymbolicLink(atPath: url.path)
        } else {
            target = nil
        }

        let seconds = TimeInterval(info.st_mtimespec.tv_sec)
        let nanoseconds = TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000

        return FileObjectState(
            kind: kind,
            permissions: UInt16(info.st_mode & mode_t(0o7777)),
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            size: UInt64(max(0, info.st_size)),
            modificationDate: Date(timeIntervalSince1970: seconds + nanoseconds),
            symlinkTarget: target
        )
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
    }

    func enumeratedContents(at url: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            return []
        }

        var result: [URL] = []
        for case let item as URL in enumerator {
            result.append(item)
        }
        return result
    }

    func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        try fileManager.copyItem(at: source, to: destination)
    }

    func createSymbolicLink(at destination: URL, pointingTo source: URL) throws {
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try fileManager.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        guard try state(at: url).exists else { return }
        try fileManager.removeItem(at: url)
    }

    func writeDataAtomically(_ data: Data, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if try state(at: parent).kind == .absent {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }

    func setPermissions(_ permissions: UInt16, at url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: permissions)], ofItemAtPath: url.path)
    }
}

struct PathSafetyValidator: Sendable {
    let home: URL
    let fileSystem: FileSystemClient

    init(home: URL, fileSystem: FileSystemClient) {
        self.home = home.standardizedFileURL
        self.fileSystem = fileSystem
    }

    func standardized(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    func isStrictlyInsideHome(_ url: URL) -> Bool {
        isStrictlyInside(url, root: home)
    }

    func isStrictlyInside(_ url: URL, root: URL) -> Bool {
        let candidate = standardized(url).path
        let rootPath = standardized(root).path
        return candidate != rootPath && candidate.hasPrefix(rootPath + "/")
    }

    func validateSource(_ source: URL, profileDirectory: URL) throws {
        let normalized = standardized(source)
        let normalizedProfile = standardized(profileDirectory)
        guard isStrictlyInside(normalized, root: normalizedProfile) else {
            throw FileSystemClientError.sourceOutsideProfile(source.path)
        }
        let resolved = normalized.resolvingSymlinksInPath().standardizedFileURL
        guard isStrictlyInside(resolved, root: normalizedProfile) else {
            throw FileSystemClientError.sourceOutsideProfile(source.path)
        }
    }

    func validateDestination(_ destination: URL) throws -> [ParentPathFingerprint] {
        let normalized = standardized(destination)
        guard isStrictlyInsideHome(normalized) else {
            throw FileSystemClientError.destinationOutsideHome(destination.path)
        }

        let relative = String(normalized.path.dropFirst(home.path.count + 1))
        let components = relative.split(separator: "/").map(String.init)
        guard components.count > 1 else { return [] }

        var current = home
        var fingerprints: [ParentPathFingerprint] = []
        for component in components.dropLast() {
            current.appendPathComponent(component)
            let state = try fileSystem.state(at: current)
            if state.kind == .absent {
                continue
            }
            if state.kind == .symbolicLink {
                let resolved = try resolveSymlink(at: current)
                guard resolved.path == home.path || isStrictlyInsideHome(resolved) else {
                    throw FileSystemClientError.unsafeParentSymlink(current.path)
                }
            } else if state.kind != .directory {
                throw FileSystemClientError.parentIsNotDirectory(current.path)
            }
            fingerprints.append(ParentPathFingerprint(path: current.path, state: state.fingerprint))
        }
        return fingerprints
    }

    func resolveSymlink(at url: URL) throws -> URL {
        var current = standardized(url)
        var visited = Set<String>()

        for _ in 0..<64 {
            guard visited.insert(current.path).inserted else {
                throw FileSystemClientError.symlinkLoop(url.path)
            }
            let state = try fileSystem.state(at: current)
            guard state.kind == .symbolicLink, let target = state.symlinkTarget else {
                return current.resolvingSymlinksInPath().standardizedFileURL
            }
            if target.hasPrefix("/") {
                current = URL(fileURLWithPath: target).standardizedFileURL
            } else {
                current = current.deletingLastPathComponent().appendingPathComponent(target).standardizedFileURL
            }
        }
        throw FileSystemClientError.symlinkLoop(url.path)
    }

    func parentFingerprintsStillMatch(_ fingerprints: [ParentPathFingerprint]) throws -> Bool {
        for expected in fingerprints {
            let current = try fileSystem.state(at: URL(fileURLWithPath: expected.path)).fingerprint
            guard current.kind == expected.state.kind,
                  current.device == expected.state.device,
                  current.inode == expected.state.inode,
                  current.symlinkTarget == expected.state.symlinkTarget else {
                return false
            }
        }
        return true
    }
}
