import XCTest
@testable import RiceBarMac

/// Unit tests for FileSystemUtilities
final class FileSystemUtilitiesTests: XCTestCase {
    
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        // Create a temporary directory for testing
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RiceBarMacTests-\(UUID().uuidString)")
        
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        super.tearDown()
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    // MARK: - Directory Operations Tests
    
    func testCreateDirectoryIfNeeded() {
        let testDir = tempDirectory.appendingPathComponent("testDir")
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: testDir.path))
        
        XCTAssertNoThrow(try FileSystemUtilities.createDirectoryIfNeeded(at: testDir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: testDir.path))
        
        // Should not throw when directory already exists
        XCTAssertNoThrow(try FileSystemUtilities.createDirectoryIfNeeded(at: testDir))
    }
    
    func testEnsureParentDirectoryExists() {
        let testFile = tempDirectory
            .appendingPathComponent("nested")
            .appendingPathComponent("directory")
            .appendingPathComponent("file.txt")
        
        XCTAssertNoThrow(try FileSystemUtilities.ensureParentDirectoryExists(for: testFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.deletingLastPathComponent().path))
    }
    
    func testRemoveItemIfExists() {
        let testFile = tempDirectory.appendingPathComponent("testFile.txt")
        
        // Create a test file
        try? "test content".write(to: testFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))
        
        // Remove it
        XCTAssertNoThrow(try FileSystemUtilities.removeItemIfExists(at: testFile))
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path))
        
        // Should not throw when file doesn't exist
        XCTAssertNoThrow(try FileSystemUtilities.removeItemIfExists(at: testFile))
    }
    
    // MARK: - File Operations Tests
    
    func testCopyFile() {
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        let destFile = tempDirectory.appendingPathComponent("dest.txt")
        let testContent = "test content"
        
        // Create source file
        try? testContent.write(to: sourceFile, atomically: true, encoding: .utf8)
        
        XCTAssertNoThrow(try FileSystemUtilities.copyFile(from: sourceFile, to: destFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFile.path))
        
        let copiedContent = try? String(contentsOf: destFile, encoding: .utf8)
        XCTAssertEqual(copiedContent, testContent)
    }
    
    func testCopyFileWithBackup() {
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        let destFile = tempDirectory.appendingPathComponent("dest.txt")
        let backupFile = destFile.appendingPathExtension("bak")
        
        let sourceContent = "new content"
        let existingContent = "existing content"
        
        // Create files
        try? sourceContent.write(to: sourceFile, atomically: true, encoding: .utf8)
        try? existingContent.write(to: destFile, atomically: true, encoding: .utf8)
        
        XCTAssertNoThrow(try FileSystemUtilities.copyFile(from: sourceFile, to: destFile, createBackup: true))
        
        // Check that destination has new content
        let newContent = try? String(contentsOf: destFile, encoding: .utf8)
        XCTAssertEqual(newContent, sourceContent)
        
        // Check that backup was created with old content
        let backupContent = try? String(contentsOf: backupFile, encoding: .utf8)
        XCTAssertEqual(backupContent, existingContent)
    }
    
    func testReadString() {
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        let testContent = "Hello, World!"
        
        try? testContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        XCTAssertNoThrow({
            let content = try FileSystemUtilities.readString(from: testFile)
            XCTAssertEqual(content, testContent)
        })
        
        // Test file not found
        let nonExistentFile = tempDirectory.appendingPathComponent("nonexistent.txt")
        XCTAssertThrowsError(try FileSystemUtilities.readString(from: nonExistentFile))
    }
    
    func testWriteString() {
        let testFile = tempDirectory.appendingPathComponent("output.txt")
        let testContent = "Test output content"
        
        XCTAssertNoThrow(try FileSystemUtilities.writeString(testContent, to: testFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))
        
        let readContent = try? String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(readContent, testContent)
    }
    
    // MARK: - JSON Operations Tests
    
    func testJSONOperations() {
        let testFile = tempDirectory.appendingPathComponent("test.json")
        let testProfile = TestProfileFactory.createTestProfile(name: "JSONTestProfile")
        
        // Test writing JSON
        XCTAssertNoThrow(try FileSystemUtilities.writeJSON(testProfile, to: testFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))
        
        // Test reading JSON
        XCTAssertNoThrow({
            let readProfile = try FileSystemUtilities.readJSON(Profile.self, from: testFile)
            XCTAssertEqual(readProfile, testProfile)
        })
    }
    
    // MARK: - Validation Tests
    
    func testSafeWritePath() {
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory())
        let safeFile = homeDirectory.appendingPathComponent("safe.txt")
        let tmpFile = URL(fileURLWithPath: "/tmp/safe.txt")
        
        XCTAssertTrue(FileSystemUtilities.isSafeWritePath(safeFile))
        XCTAssertTrue(FileSystemUtilities.isSafeWritePath(tmpFile))
        
        // Test unsafe paths
        let systemFile = URL(fileURLWithPath: "/System/test.txt")
        let binFile = URL(fileURLWithPath: "/usr/bin/test")
        
        XCTAssertFalse(FileSystemUtilities.isSafeWritePath(systemFile))
        XCTAssertFalse(FileSystemUtilities.isSafeWritePath(binFile))
    }
    
    // MARK: - URL Extension Tests
    
    func testURLExpandingTildeInPath() {
        let homeDirectory = NSHomeDirectory()
        let tildeURL = URL(fileURLWithPath: "~/test.txt")
        let expandedURL = tildeURL.expandingTildeInPath
        
        XCTAssertTrue(expandedURL.path.hasPrefix(homeDirectory))
        XCTAssertTrue(expandedURL.path.hasSuffix("test.txt"))
        
        // Test non-tilde path
        let regularURL = URL(fileURLWithPath: "/tmp/test.txt")
        XCTAssertEqual(regularURL.expandingTildeInPath, regularURL)
    }
    
    func testExistingParentDirectory() {
        let tempFile = tempDirectory.appendingPathComponent("file.txt")
        let parentDir = tempFile.existingParentDirectory
        
        XCTAssertEqual(parentDir, tempDirectory)
        
        // Test deeply nested path
        let deepFile = tempDirectory
            .appendingPathComponent("non")
            .appendingPathComponent("existent")
            .appendingPathComponent("path")
            .appendingPathComponent("file.txt")
        
        let existingParent = deepFile.existingParentDirectory
        XCTAssertEqual(existingParent, tempDirectory)
    }
    
    // MARK: - Performance Tests
    
    func testFileOperationPerformance() {
        let files = (0..<100).map { tempDirectory.appendingPathComponent("file\($0).txt") }
        
        measure {
            for file in files {
                try? FileSystemUtilities.writeString("test content", to: file)
            }
        }
        
        // Clean up
        for file in files {
            try? FileSystemUtilities.removeItemIfExists(at: file)
        }
    }
}