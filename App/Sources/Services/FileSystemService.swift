import Foundation
import AppKit
import Combine


enum FileSystemServiceError: LocalizedError {
    case fileNotFound(String)
    case permissionDenied(String)
    case unsafeWritePath(String)
    case templateRenderingFailed(String, Error)
    case directoryCreationFailed(String, Error)
    case fileCopyFailed(String, String, Error)
    case invalidEncoding(String)
    case jsonSerializationFailed(Error)
    case symlinkCreationFailed(String, String, Error)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .unsafeWritePath(let path):
            return "Unsafe write path: \(path)"
        case .templateRenderingFailed(let template, let error):
            return "Failed to render template '\(template)': \(error.localizedDescription)"
        case .directoryCreationFailed(let path, let error):
            return "Failed to create directory '\(path)': \(error.localizedDescription)"
        case .fileCopyFailed(let source, let destination, let error):
            return "Failed to copy '\(source)' to '\(destination)': \(error.localizedDescription)"
        case .invalidEncoding(let path):
            return "Invalid text encoding for file: \(path)"
        case .jsonSerializationFailed(let error):
            return "JSON serialization failed: \(error.localizedDescription)"
        case .symlinkCreationFailed(let source, let destination, let error):
            return "Failed to create symlink from '\(source)' to '\(destination)': \(error.localizedDescription)"
        }
    }
}

struct SymlinkAction: Codable {
    enum Kind: String, Codable {
        case created
        case replaced
    }
    
    let kind: Kind
    let source: String
    let destination: String
    let backup: String?
    
    init(kind: Kind, source: String, destination: String, backup: String? = nil) {
        self.kind = kind
        self.source = source
        self.destination = destination
        self.backup = backup
    }
}


private struct TemplateVariables {
    let variables: [String: String]
    let paletteColors: [String]
    
    init(profile: ProfileDescriptor) {
        var vars: [String: String] = [:]
        
        let varsURL = profile.directory.appendingPathComponent("variables.json")
        if let data = try? Data(contentsOf: varsURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in obj {
                vars[k] = String(describing: v)
            }
        }
        
        var palette: [String] = []
        if let wallpaperRel = profile.profile.wallpaper {
            let wpURL = profile.directory.appendingPathComponent(wallpaperRel)
            vars["wallpaperPath"] = wpURL.path
            palette = PaletteExtractor.extractPalette(from: wpURL, count: 6)
            for (idx, hex) in palette.enumerated() { 
                vars["palette\(idx)"] = hex 
            }
        }
        
        self.variables = vars
        self.paletteColors = palette
    }
}


private enum PaletteExtractor {
    
    static func extractPalette(from imageURL: URL, count: Int) -> [String] {
        guard let nsImage = NSImage(contentsOf: imageURL) else { return [] }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        
        let sampleSize = CGSize(width: 64, height: 64)
        guard let context = CGContext(
            data: nil,
            width: Int(sampleSize.width),
            height: Int(sampleSize.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(sampleSize.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(origin: .zero, size: sampleSize))
        guard let data = context.data else { return [] }
        
        let buffer = data.bindMemory(to: UInt8.self, capacity: Int(sampleSize.width * sampleSize.height * 4))
        var histogram: [UInt32: Int] = [:]
        let pixelCount = Int(sampleSize.width * sampleSize.height)
        
        for i in 0..<pixelCount {
            let base = i * 4
            let r = buffer[base]
            let g = buffer[base + 1]
            let b = buffer[base + 2]
            
            let rq = UInt32(r) >> 4
            let gq = UInt32(g) >> 4
            let bq = UInt32(b) >> 4
            
            let brightness = (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
            if brightness > 0.98 || brightness < 0.05 { continue }
            
            let key = (rq << 8) | (gq << 4) | bq
            histogram[key, default: 0] += 1
        }
        
        let sorted = histogram.sorted { $0.value > $1.value }
        var hexColors: [String] = []
        
        for (key, _) in sorted {
            if hexColors.count >= count { break }
            let rq = (key >> 8) & 0xF
            let gq = (key >> 4) & 0xF
            let bq = key & 0xF
            
            let r = UInt8((rq << 4) | 0x8)
            let g = UInt8((gq << 4) | 0x8)
            let b = UInt8((bq << 4) | 0x8)
            let hex = String(format: "#%02X%02X%02X", r, g, b)
            
            if !hexColors.contains(hex) { 
                hexColors.append(hex) 
            }
        }
        
        return hexColors
    }
}


final class FileSystemService: ObservableObject {
    
    
    private let operationQueue = DispatchQueue(label: "com.ricebar.filesystem", qos: .userInitiated)
    
    
    static let shared = FileSystemService()
    
    init() {}
    
    
    func createDirectoryIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw FileSystemServiceError.directoryCreationFailed(url.path, error)
            }
        }
    }
    
    func ensureParentDirectoryExists(for fileURL: URL) throws {
        try createDirectoryIfNeeded(at: fileURL.deletingLastPathComponent())
    }
    
    func removeItemIfExists(at url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
    
    
    func copyFile(from source: URL, to destination: URL, createBackup: Bool = true) throws {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: source.path) else {
            throw FileSystemServiceError.fileNotFound(source.path)
        }
        
        guard isSafeWritePath(destination) else {
            throw FileSystemServiceError.unsafeWritePath(destination.path)
        }
        
        try ensureParentDirectoryExists(for: destination)
        
        do {
            if createBackup && fileManager.fileExists(atPath: destination.path) {
                let backupURL = destination.appendingPathExtension("bak")
                try removeItemIfExists(at: backupURL) // Remove old backup
                try fileManager.moveItem(at: destination, to: backupURL)
            } else if fileManager.fileExists(atPath: destination.path) {
                try removeItemIfExists(at: destination)
            }
            
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw FileSystemServiceError.fileCopyFailed(source.path, destination.path, error)
        }
    }
    
    // MARK: - Symlink Management
    
    func createSymlink(from source: URL, to destination: URL, createBackup: Bool = true) throws {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: source.path) else {
            throw FileSystemServiceError.fileNotFound(source.path)
        }
        
        guard isSafeWritePath(destination) else {
            throw FileSystemServiceError.unsafeWritePath(destination.path)
        }
        
        try ensureParentDirectoryExists(for: destination)
        
        do {
            if fileManager.fileExists(atPath: destination.path) || isSymlink(destination) {
                if createBackup && !isSymlink(destination) {
                    // Only backup real files, not symlinks
                    let backupURL = destination.appendingPathExtension("ricebar-backup")
                    try removeItemIfExists(at: backupURL)
                    try fileManager.moveItem(at: destination, to: backupURL)
                } else {
                    try removeItemIfExists(at: destination)
                }
            }
            
            try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
        } catch {
            throw FileSystemServiceError.symlinkCreationFailed(source.path, destination.path, error)
        }
    }
    
    func createSymlinkTree(from sourceDir: URL, to targetDir: URL, createBackup: Bool = true) throws {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: sourceDir.path) else {
            throw FileSystemServiceError.fileNotFound(sourceDir.path)
        }
        
        // Atomic symlink replacement using temporary directory
        let tempTarget = targetDir.appendingPathExtension("ricebar-new")
        try removeItemIfExists(at: tempTarget)
        
        // Create the symlink at temporary location
        try createSymlink(from: sourceDir, to: tempTarget, createBackup: false)
        
        // Atomic replacement
        if fileManager.fileExists(atPath: targetDir.path) || isSymlink(targetDir) {
            if createBackup && !isSymlink(targetDir) {
                let backupTarget = targetDir.appendingPathExtension("ricebar-backup")
                try removeItemIfExists(at: backupTarget)
                try fileManager.moveItem(at: targetDir, to: backupTarget)
            } else {
                try removeItemIfExists(at: targetDir)
            }
        }
        
        // Move temporary symlink to final location
        try fileManager.moveItem(at: tempTarget, to: targetDir)
    }
    
    func overlaySymlinkDirectory(from sourceDir: URL, to targetDir: URL, createBackup: Bool = true) throws -> [SymlinkAction] {
        let fileManager = FileManager.default
        var actions: [SymlinkAction] = []
        
        guard let enumerator = fileManager.enumerator(at: sourceDir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            return actions
        }
        
        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: sourceDir.path + "/", with: "")
            let targetURL = targetDir.appendingPathComponent(relativePath)
            
            var isDir: ObjCBool = false
            _ = fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            
            if isDir.boolValue {
                // Create directory structure
                try createDirectoryIfNeeded(at: targetURL)
            } else {
                // Create individual file symlinks
                let action = try createFileSymlink(source: fileURL, destination: targetURL, createBackup: createBackup)
                actions.append(action)
            }
        }
        
        return actions
    }
    
    private func createFileSymlink(source: URL, destination: URL, createBackup: Bool) throws -> SymlinkAction {
        let fileManager = FileManager.default
        var backupPath: String? = nil
        var kind: SymlinkAction.Kind = .created
        
        if fileManager.fileExists(atPath: destination.path) || isSymlink(destination) {
            if !isSymlink(destination) && createBackup {
                // Backup real files
                let backup = destination.appendingPathExtension("ricebar-backup")
                try removeItemIfExists(at: backup)
                try fileManager.moveItem(at: destination, to: backup)
                backupPath = backup.path
                kind = .replaced
            } else {
                // Remove existing symlinks or files without backup
                try removeItemIfExists(at: destination)
                kind = .replaced
            }
        }
        
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
        
        return SymlinkAction(
            kind: kind,
            source: source.path,
            destination: destination.path,
            backup: backupPath
        )
    }
    
    func isSymlink(_ url: URL) -> Bool {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            return resourceValues.isSymbolicLink == true
        } catch {
            return false
        }
    }
    
    func readSymlink(_ url: URL) throws -> URL {
        guard isSymlink(url) else {
            throw FileSystemServiceError.fileNotFound("Not a symlink: \(url.path)")
        }
        
        let destinationPath = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
        return URL(fileURLWithPath: destinationPath)
    }
    
    func removeSymlinkTree(at url: URL, restoreBackups: Bool = true) throws {
        let fileManager = FileManager.default
        
        if isSymlink(url) {
            try removeItemIfExists(at: url)
            
            if restoreBackups {
                let backup = url.appendingPathExtension("ricebar-backup")
                if fileManager.fileExists(atPath: backup.path) {
                    try fileManager.moveItem(at: backup, to: url)
                }
            }
        }
    }
    
    func readString(from url: URL, encoding: String.Encoding = .utf8) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileSystemServiceError.fileNotFound(url.path)
        }
        
        do {
            return try String(contentsOf: url, encoding: encoding)
        } catch {
            throw FileSystemServiceError.invalidEncoding(url.path)
        }
    }
    
    func writeString(_ content: String, to url: URL, encoding: String.Encoding = .utf8) throws {
        guard isSafeWritePath(url) else {
            throw FileSystemServiceError.unsafeWritePath(url.path)
        }
        
        try ensureParentDirectoryExists(for: url)
        try content.write(to: url, atomically: true, encoding: encoding)
    }
    
    
    func readJSON<T: Codable>(_ type: T.Type, from url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileSystemServiceError.fileNotFound(url.path)
        }
        
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw FileSystemServiceError.jsonSerializationFailed(error)
        }
    }
    
    func writeJSON<T: Codable>(_ object: T, to url: URL, prettyPrinted: Bool = true) throws {
        guard isSafeWritePath(url) else {
            throw FileSystemServiceError.unsafeWritePath(url.path)
        }
        
        do {
            let encoder = JSONEncoder()
            if prettyPrinted {
                encoder.outputFormatting = [.prettyPrinted]
            }
            let data = try encoder.encode(object)
            try ensureParentDirectoryExists(for: url)
            try data.write(to: url, options: .atomic)
        } catch {
            throw FileSystemServiceError.jsonSerializationFailed(error)
        }
    }
    
    
    func renderTemplates(for descriptor: ProfileDescriptor) {
        let templatesRoot = descriptor.directory.appendingPathComponent("templates/home", isDirectory: true)
        let outputRoot = descriptor.directory.appendingPathComponent("home", isDirectory: true)
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: templatesRoot.path) else { return }
        
        let templateVars = TemplateVariables(profile: descriptor)
        
        guard let enumerator = fm.enumerator(at: templatesRoot, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: []) else { return }
        
        var processedCount = 0
        let maxTemplates = 100 // Prevent runaway processing
        
        for case let tplURL as URL in enumerator {
            processedCount += 1
            if processedCount > maxTemplates {
                break
            }
            
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: tplURL.path, isDirectory: &isDir), isDir.boolValue { continue }
            
            let rel = tplURL.path.replacingOccurrences(of: templatesRoot.path + "/", with: "")
            let outURL = outputRoot.appendingPathComponent(rel)
            
            do {
                if let templateModDate = try? tplURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   let outputModDate = try? outURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   templateModDate <= outputModDate {
                    let content = try String(contentsOf: tplURL, encoding: .utf8)
                    let rendered = renderTemplate(content: content, with: templateVars.variables)
                    
                    if let existing = try? String(contentsOf: outURL, encoding: .utf8), existing == rendered {
                        continue // No changes needed
                    }
                }
                
                try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let content = try String(contentsOf: tplURL, encoding: .utf8)
                let rendered = renderTemplate(content: content, with: templateVars.variables)
                
                if let existing = try? String(contentsOf: outURL, encoding: .utf8), existing == rendered {
                    continue
                }
                
                try rendered.write(to: outURL, atomically: true, encoding: .utf8)
            } catch {
            }
        }
        
        if processedCount > 0 {
        }
    }
    
    private func renderTemplate(content: String, with variables: [String: String]) -> String {
        var result = content
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }
    
    
    func reloadAlacritty() {
        let cmd = """
        ( /opt/homebrew/bin/alacritty msg config reload \
          || /usr/local/bin/alacritty msg config reload \
          || alacritty msg config reload \
          || "/Applications/Alacritty.app/Contents/MacOS/alacritty" msg config reload \
          || killall -USR1 Alacritty \
        ) >/dev/null 2>&1 || true
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", cmd]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
        } catch {
        }
    }
    
    
    func isSafeWritePath(_ url: URL) -> Bool {
        let path = url.path
        let homeDirectory = NSHomeDirectory()
        
        guard path.hasPrefix(homeDirectory) || path.hasPrefix("/tmp") || path.hasPrefix("/var/tmp") else {
            return false
        }
        
        let unsafePaths = [
            "/System",
            "/Library/System",
            "/usr/bin",
            "/usr/sbin",
            "/bin",
            "/sbin"
        ]
        
        return !unsafePaths.contains { path.hasPrefix($0) }
    }
    
    func fileExists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    func modificationDate(for url: URL) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }
    
    func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}


enum TemplateEngine {
    @available(*, deprecated, message: "Use FileSystemService.shared.renderTemplates(for:) instead")
    static func renderTemplates(for descriptor: ProfileDescriptor) {
        FileSystemService.shared.renderTemplates(for: descriptor)
    }
}


@available(*, deprecated, message: "Use FileSystemService.shared methods instead")
enum FileSystemUtilities {
    static func createDirectoryIfNeeded(at url: URL) throws {
        try FileSystemService.shared.createDirectoryIfNeeded(at: url)
    }
    
    static func ensureParentDirectoryExists(for fileURL: URL) throws {
        try FileSystemService.shared.ensureParentDirectoryExists(for: fileURL)
    }
    
    static func removeItemIfExists(at url: URL) throws {
        try FileSystemService.shared.removeItemIfExists(at: url)
    }
    
    static func copyFile(from source: URL, to destination: URL, createBackup: Bool = true) throws {
        try FileSystemService.shared.copyFile(from: source, to: destination, createBackup: createBackup)
    }
    
    static func readString(from url: URL, encoding: String.Encoding = .utf8) throws -> String {
        return try FileSystemService.shared.readString(from: url, encoding: encoding)
    }
    
    static func writeString(_ content: String, to url: URL, encoding: String.Encoding = .utf8) throws {
        try FileSystemService.shared.writeString(content, to: url, encoding: encoding)
    }
    
    static func readJSON<T: Codable>(_ type: T.Type, from url: URL) throws -> T {
        return try FileSystemService.shared.readJSON(type, from: url)
    }
    
    static func writeJSON<T: Codable>(_ object: T, to url: URL, prettyPrinted: Bool = true) throws {
        try FileSystemService.shared.writeJSON(object, to: url, prettyPrinted: prettyPrinted)
    }
    
    static func isSafeWritePath(_ url: URL) -> Bool {
        return FileSystemService.shared.isSafeWritePath(url)
    }
}


@available(*, deprecated, message: "Use FileSystemService.shared.reloadAlacritty() instead")
enum ReloadHelper {
    static func reloadAlacritty() {
        FileSystemService.shared.reloadAlacritty()
    }
}


extension URL {
    var expandingTildeInPath: URL {
        if path.hasPrefix("~") {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return self
    }
    
    var existingParentDirectory: URL? {
        var current = self.deletingLastPathComponent()
        while current.path != "/" && current.path != current.deletingLastPathComponent().path {
            if FileManager.default.fileExists(atPath: current.path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return current.path == "/" ? current : nil
    }
}