import XCTest
@testable import RiceBarMac

final class FileSystemUtilitiesTests: XCTestCase {
    
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RiceBarMacTests-\(UUID().uuidString)")
        
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    
    func testCreateDirectoryIfNeeded() {
        let testDir = tempDirectory.appendingPathComponent("testDir")
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: testDir.path))
        
        XCTAssertNoThrow(try FileSystemUtilities.createDirectoryIfNeeded(at: testDir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: testDir.path))
        
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
        
        try? "test content".write(to: testFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))
        
        XCTAssertNoThrow(try FileSystemUtilities.removeItemIfExists(at: testFile))
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path))
        
        XCTAssertNoThrow(try FileSystemUtilities.removeItemIfExists(at: testFile))
    }
    
    
    func testCopyFile() {
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        let destFile = tempDirectory.appendingPathComponent("dest.txt")
        let testContent = "test content"
        
        try? testContent.write(to: sourceFile, atomically: true, encoding: .utf8)
        
        XCTAssertNoThrow(try FileSystemUtilities.copyFile(from: sourceFile, to: destFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFile.path))
        
        let copiedContent = try? String(contentsOf: destFile, encoding: .utf8)
        XCTAssertEqual(copiedContent, testContent)
    }
    
    
    func testReadString() {
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        let testContent = "Hello, World!"
        
        try? testContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        XCTAssertNoThrow({
            let content = try FileSystemUtilities.readString(from: testFile)
            XCTAssertEqual(content, testContent)
        })
        
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
    
    
    func testJSONOperations() {
        let testFile = tempDirectory.appendingPathComponent("test.json")
        let testProfile = TestProfileFactory.createTestProfile(name: "JSONTestProfile")
        
        XCTAssertNoThrow(try FileSystemUtilities.writeJSON(testProfile, to: testFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))
        
        XCTAssertNoThrow({
            let readProfile = try FileSystemUtilities.readJSON(Profile.self, from: testFile)
            XCTAssertEqual(readProfile, testProfile)
        })
    }
    
    
    func testSafeWritePath() {
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory())
        let safeFile = homeDirectory.appendingPathComponent("safe.txt")
        let tmpFile = URL(fileURLWithPath: "/tmp/safe.txt")
        
        XCTAssertTrue(FileSystemUtilities.isSafeWritePath(safeFile))
        XCTAssertTrue(FileSystemUtilities.isSafeWritePath(tmpFile))
        
        let systemFile = URL(fileURLWithPath: "/System/test.txt")
        let binFile = URL(fileURLWithPath: "/usr/bin/test")
        
        XCTAssertFalse(FileSystemUtilities.isSafeWritePath(systemFile))
        XCTAssertFalse(FileSystemUtilities.isSafeWritePath(binFile))
    }
    
    
    func testURLExpandingTildeInPath() {
        let homeDirectory = NSHomeDirectory()
        let tildeURL = URL(fileURLWithPath: "~/test.txt")
        let expandedURL = tildeURL.expandingTildeInPath
        
        XCTAssertTrue(expandedURL.path.hasPrefix(homeDirectory))
        XCTAssertTrue(expandedURL.path.hasSuffix("test.txt"))
        
        let regularURL = URL(fileURLWithPath: "/tmp/test.txt")
        XCTAssertEqual(regularURL.expandingTildeInPath, regularURL)
    }
    
    func testExistingParentDirectory() {
        let tempFile = tempDirectory.appendingPathComponent("file.txt")
        let parentDir = tempFile.existingParentDirectory
        
        XCTAssertEqual(parentDir, tempDirectory)
        
        let deepFile = tempDirectory
            .appendingPathComponent("non")
            .appendingPathComponent("existent")
            .appendingPathComponent("path")
            .appendingPathComponent("file.txt")
        
        let existingParent = deepFile.existingParentDirectory
        XCTAssertEqual(existingParent, tempDirectory)
    }
    
    
    func testFileOperationPerformance() {
        let files = (0..<100).map { tempDirectory.appendingPathComponent("file\($0).txt") }
        
        measure {
            for file in files {
                try? FileSystemUtilities.writeString("test content", to: file)
            }
        }
        
        for file in files {
            try? FileSystemUtilities.removeItemIfExists(at: file)
        }
    }
}