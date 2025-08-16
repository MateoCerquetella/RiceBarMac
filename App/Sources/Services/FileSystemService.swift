import Foundation
import AppKit
import Combine

// MARK: - File System Service Errors

enum FileSystemServiceError: LocalizedError {
    case fileNotFound(String)
    case permissionDenied(String)
    case unsafeWritePath(String)
    case templateRenderingFailed(String, Error)
    case directoryCreationFailed(String, Error)
    case fileCopyFailed(String, String, Error)
    case invalidEncoding(String)
    case jsonSerializationFailed(Error)
    
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
        }
    }
}

// MARK: - Template Variables

private struct TemplateVariables {
    let variables: [String: String]
    let paletteColors: [String]
    
    init(profile: ProfileDescriptor) {
        var vars: [String: String] = [:]
        
        // Load variables.json if present
        let varsURL = profile.directory.appendingPathComponent("variables.json")
        if let data = try? Data(contentsOf: varsURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in obj {
                vars[k] = String(describing: v)
            }
        }
        
        // Add wallpaper path and palette if present
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

// MARK: - Palette Extractor

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
            
            // Quantize to 4 bits per channel to reduce distinct colors
            let rq = UInt32(r) >> 4
            let gq = UInt32(g) >> 4
            let bq = UInt32(b) >> 4
            
            // Skip near-white and near-black buckets to avoid extremes
            let brightness = (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
            if brightness > 0.98 || brightness < 0.05 { continue }
            
            let key = (rq << 8) | (gq << 4) | bq
            histogram[key, default: 0] += 1
        }
        
        // Sort buckets by frequency and map to hex color strings
        let sorted = histogram.sorted { $0.value > $1.value }
        var hexColors: [String] = []
        
        for (key, _) in sorted {
            if hexColors.count >= count { break }
            let rq = (key >> 8) & 0xF
            let gq = (key >> 4) & 0xF
            let bq = key & 0xF
            
            // Map bucket center back to 8-bit
            let r = UInt8((rq << 4) | 0x8)
            let g = UInt8((gq << 4) | 0x8)
            let b = UInt8((bq << 4) | 0x8)
            let hex = String(format: "#%02X%02X%02X", r, g, b)
            
            // Avoid near-duplicates
            if !hexColors.contains(hex) { 
                hexColors.append(hex) 
            }
        }
        
        return hexColors
    }
}

// MARK: - File System Service

/// Consolidated service for file system operations including file I/O, 
/// template rendering, and terminal integration.
final class FileSystemService: ObservableObject {
    
    // MARK: - Properties
    
    private let operationQueue = DispatchQueue(label: "com.ricebar.filesystem", qos: .userInitiated)
    
    // MARK: - Singleton
    
    static let shared = FileSystemService()
    
    init() {}
    
    // MARK: - Directory Operations
    
    /// Safely creates a directory if it doesn't exist
    /// - Parameter url: The directory URL to create
    /// - Throws: FileSystemServiceError if creation fails
    func createDirectoryIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                LoggerService.info("Created directory: \(url.path)")
            } catch {
                throw FileSystemServiceError.directoryCreationFailed(url.path, error)
            }
        }
    }
    
    /// Ensures parent directory exists for a file path
    /// - Parameter fileURL: The file URL whose parent directory should exist
    /// - Throws: FileSystemServiceError if creation fails
    func ensureParentDirectoryExists(for fileURL: URL) throws {
        try createDirectoryIfNeeded(at: fileURL.deletingLastPathComponent())
    }
    
    /// Safely removes a file or directory if it exists
    /// - Parameter url: The URL to remove
    /// - Throws: FileSystemServiceError if removal fails
    func removeItemIfExists(at url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            LoggerService.info("Removed item: \(url.path)")
        }
    }
    
    // MARK: - File Operations
    
    /// Safely copies a file with backup support
    /// - Parameters:
    ///   - source: Source file URL
    ///   - destination: Destination file URL
    ///   - createBackup: Whether to create a backup if destination exists
    /// - Throws: FileSystemServiceError if operation fails
    func copyFile(from source: URL, to destination: URL, createBackup: Bool = true) throws {
        let fileManager = FileManager.default
        
        // Ensure source exists
        guard fileManager.fileExists(atPath: source.path) else {
            throw FileSystemServiceError.fileNotFound(source.path)
        }
        
        // Validate destination path is safe
        guard isSafeWritePath(destination) else {
            throw FileSystemServiceError.unsafeWritePath(destination.path)
        }
        
        // Create parent directory if needed
        try ensureParentDirectoryExists(for: destination)
        
        do {
            // Create backup if destination exists and backup is requested
            if createBackup && fileManager.fileExists(atPath: destination.path) {
                let backupURL = destination.appendingPathExtension("bak")
                try removeItemIfExists(at: backupURL) // Remove old backup
                try fileManager.moveItem(at: destination, to: backupURL)
                LoggerService.info("Created backup: \(backupURL.path)")
            } else if fileManager.fileExists(atPath: destination.path) {
                try removeItemIfExists(at: destination)
            }
            
            // Perform the copy
            try fileManager.copyItem(at: source, to: destination)
            LoggerService.info("Copied file: \(source.path) -> \(destination.path)")
        } catch {
            throw FileSystemServiceError.fileCopyFailed(source.path, destination.path, error)
        }
    }
    
    /// Safely reads string content from a file
    /// - Parameters:
    ///   - url: File URL to read from
    ///   - encoding: Text encoding to use
    /// - Returns: String content of the file
    /// - Throws: FileSystemServiceError if reading fails
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
    
    /// Safely writes string content to a file
    /// - Parameters:
    ///   - content: String content to write
    ///   - url: Destination file URL
    ///   - encoding: Text encoding to use
    /// - Throws: FileSystemServiceError if writing fails
    func writeString(_ content: String, to url: URL, encoding: String.Encoding = .utf8) throws {
        guard isSafeWritePath(url) else {
            throw FileSystemServiceError.unsafeWritePath(url.path)
        }
        
        try ensureParentDirectoryExists(for: url)
        try content.write(to: url, atomically: true, encoding: encoding)
        LoggerService.info("Wrote file: \(url.path)")
    }
    
    // MARK: - JSON Operations
    
    /// Safely reads and decodes JSON from a file
    /// - Parameters:
    ///   - type: The type to decode to
    ///   - url: File URL to read from
    /// - Returns: Decoded object
    /// - Throws: FileSystemServiceError if reading or decoding fails
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
    
    /// Safely encodes and writes JSON to a file
    /// - Parameters:
    ///   - object: Object to encode
    ///   - url: Destination file URL
    ///   - prettyPrinted: Whether to format JSON with indentation
    /// - Throws: FileSystemServiceError if encoding or writing fails
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
            LoggerService.info("Wrote JSON file: \(url.path)")
        } catch {
            throw FileSystemServiceError.jsonSerializationFailed(error)
        }
    }
    
    // MARK: - Template Engine
    
    /// Renders templates for a profile descriptor
    /// - Parameter descriptor: Profile descriptor containing templates
    func renderTemplates(for descriptor: ProfileDescriptor) {
        let templatesRoot = descriptor.directory.appendingPathComponent("templates/home", isDirectory: true)
        let outputRoot = descriptor.directory.appendingPathComponent("home", isDirectory: true)
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: templatesRoot.path) else { return }
        
        let templateVars = TemplateVariables(profile: descriptor)
        
        // Do not skip hidden files so templates for dotfiles are rendered
        guard let enumerator = fm.enumerator(at: templatesRoot, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: []) else { return }
        
        var processedCount = 0
        let maxTemplates = 100 // Prevent runaway processing
        
        for case let tplURL as URL in enumerator {
            // Safety check to prevent infinite processing
            processedCount += 1
            if processedCount > maxTemplates {
                LoggerService.warning("Template processing limit reached (\(maxTemplates)), stopping early")
                break
            }
            
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: tplURL.path, isDirectory: &isDir), isDir.boolValue { continue }
            
            let rel = tplURL.path.replacingOccurrences(of: templatesRoot.path + "/", with: "")
            let outURL = outputRoot.appendingPathComponent(rel)
            
            do {
                // Check if template is newer than output before processing
                if let templateModDate = try? tplURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   let outputModDate = try? outURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   templateModDate <= outputModDate {
                    // Template is older than output, skip unless content changed
                    let content = try String(contentsOf: tplURL, encoding: .utf8)
                    let rendered = renderTemplate(content: content, with: templateVars.variables)
                    
                    if let existing = try? String(contentsOf: outURL, encoding: .utf8), existing == rendered {
                        continue // No changes needed
                    }
                }
                
                try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let content = try String(contentsOf: tplURL, encoding: .utf8)
                let rendered = renderTemplate(content: content, with: templateVars.variables)
                
                // Skip unnecessary write if content hasn't changed
                if let existing = try? String(contentsOf: outURL, encoding: .utf8), existing == rendered {
                    continue
                }
                
                try rendered.write(to: outURL, atomically: true, encoding: .utf8)
                LoggerService.debug("Rendered template: \(tplURL.lastPathComponent) -> \(outURL.lastPathComponent)")
            } catch {
                LoggerService.error("Template render error for \(tplURL.lastPathComponent): \(error)")
            }
        }
        
        if processedCount > 0 {
            LoggerService.info("Template rendering completed: \(processedCount) templates processed")
        }
    }
    
    /// Renders a template string with variables
    /// - Parameters:
    ///   - content: Template content with {{variable}} placeholders
    ///   - variables: Dictionary of variables to substitute
    /// - Returns: Rendered template content
    private func renderTemplate(content: String, with variables: [String: String]) -> String {
        var result = content
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }
    
    // MARK: - Terminal Integration
    
    /// Reloads Alacritty configuration
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
            LoggerService.info("Triggered Alacritty config reload")
        } catch {
            LoggerService.error("Failed to reload Alacritty config: \(error)")
        }
    }
    
    // MARK: - File System Validation
    
    /// Checks if a path is safe to write to (not system directories)
    /// - Parameter url: URL to validate
    /// - Returns: True if the path is safe for writing
    func isSafeWritePath(_ url: URL) -> Bool {
        let path = url.path
        let homeDirectory = NSHomeDirectory()
        
        // Must be within home directory or user-controlled paths
        guard path.hasPrefix(homeDirectory) || path.hasPrefix("/tmp") || path.hasPrefix("/var/tmp") else {
            return false
        }
        
        // Avoid system-critical directories
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
    
    /// Checks if a file exists at the given URL
    /// - Parameter url: URL to check
    /// - Returns: True if file exists
    func fileExists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Gets the modification date of a file
    /// - Parameter url: File URL
    /// - Returns: Modification date or nil if file doesn't exist
    func modificationDate(for url: URL) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }
    
    /// Sets the modification date of a file
    /// - Parameters:
    ///   - date: New modification date
    ///   - url: File URL
    /// - Throws: Error if setting the date fails
    func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}

// MARK: - Template Engine (Deprecated - kept for compatibility)

enum TemplateEngine {
    @available(*, deprecated, message: "Use FileSystemService.shared.renderTemplates(for:) instead")
    static func renderTemplates(for descriptor: ProfileDescriptor) {
        FileSystemService.shared.renderTemplates(for: descriptor)
    }
}

// MARK: - File System Utilities (Deprecated - kept for compatibility)

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

// MARK: - Reload Helper (Deprecated - kept for compatibility)

@available(*, deprecated, message: "Use FileSystemService.shared.reloadAlacritty() instead")
enum ReloadHelper {
    static func reloadAlacritty() {
        FileSystemService.shared.reloadAlacritty()
    }
}

// MARK: - URL Extensions

extension URL {
    /// Safely expands tilde paths
    var expandingTildeInPath: URL {
        if path.hasPrefix("~") {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return self
    }
    
    /// Returns the first existing parent directory
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