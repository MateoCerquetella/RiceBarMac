import Foundation

#if DEBUG



protocol Testable {
    func resetForTesting()
    
    var testState: [String: Any] { get }
}

protocol TestableWithDependencies: Testable {
    func injectTestDependencies(_ dependencies: [String: Any])
}


final class MockFileSystem {
    private var files: [String: Data] = [:]
    private var directories: Set<String> = []
    
    func reset() {
        files.removeAll()
        directories.removeAll()
    }
    
    func createFile(at path: String, contents: Data) {
        files[path] = contents
        
        let parentPath = (path as NSString).deletingLastPathComponent
        if !parentPath.isEmpty && parentPath != "/" {
            directories.insert(parentPath)
        }
    }
    
    func createDirectory(at path: String) {
        directories.insert(path)
    }
    
    func fileExists(at path: String) -> Bool {
        return files.keys.contains(path) || directories.contains(path)
    }
    
    func readFile(at path: String) -> Data? {
        return files[path]
    }
    
    func deleteFile(at path: String) {
        files.removeValue(forKey: path)
    }
    
    var allFiles: [String] {
        return Array(files.keys)
    }
    
    var allDirectories: [String] {
        return Array(directories)
    }
}


enum TestProfileFactory {
    
    static func createTestProfile(name: String = "TestProfile") -> Profile {
        return Profile(name: name)
    }
    
    static func createCompleteTestProfile(name: String = "CompleteTestProfile") -> Profile {
        var profile = Profile(name: name)
        profile.order = 1
        profile.hotkey = "ctrl+cmd+1"
        profile.wallpaper = "wallpaper.jpg"
        profile.terminal = Profile.Terminal(kind: .alacritty)
        profile.terminal?.theme = "theme.yml"
        profile.replacements = [
            Profile.Replacement(source: "source.txt", destination: "~/destination.txt")
        ]
        profile.startupScript = "startup.sh"
        return profile
    }
    
    static func createTestDescriptor(
        profile: Profile? = nil,
        directory: URL? = nil
    ) -> ProfileDescriptor {
        let testProfile = profile ?? createTestProfile()
        let testDirectory = directory ?? URL(fileURLWithPath: "/tmp/test-profile")
        return ProfileDescriptor(profile: testProfile, directory: testDirectory)
    }
    
    static func createTestProfiles(count: Int = 3) -> [ProfileDescriptor] {
        return (1...count).map { index in
            let profile = createTestProfile(name: "TestProfile\(index)")
            let directory = URL(fileURLWithPath: "/tmp/test-profile-\(index)")
            return ProfileDescriptor(profile: profile, directory: directory)
        }
    }
}


enum TestValidation {
    
    static func validateProfile(
        _ profile: Profile,
        name: String? = nil,
        order: Int? = nil,
        hotkey: String? = nil,
        wallpaper: String? = nil
    ) -> Bool {
        if let expectedName = name, profile.name != expectedName { return false }
        if let expectedOrder = order, profile.order != expectedOrder { return false }
        if let expectedHotkey = hotkey, profile.hotkey != expectedHotkey { return false }
        if let expectedWallpaper = wallpaper, profile.wallpaper != expectedWallpaper { return false }
        return true
    }
    
    static func validateError<T: Error>(_ error: Error, type: T.Type) -> Bool {
        return error is T
    }
    
    static func validateURL(_ url: URL, existsInMockFS mockFS: MockFileSystem) -> Bool {
        return mockFS.fileExists(at: url.path)
    }
}


struct PerformanceMeasurement {
    let name: String
    let duration: TimeInterval
    let memoryUsage: UInt64?
    
    static func measure<T>(
        name: String = "Measurement",
        operation: () throws -> T
    ) rethrows -> (result: T, measurement: PerformanceMeasurement) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let startMemory = getCurrentMemoryUsage()
        
        let result = try operation()
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let endMemory = getCurrentMemoryUsage()
        
        let duration = endTime - startTime
        let memoryDelta = endMemory > startMemory ? endMemory - startMemory : nil
        
        let measurement = PerformanceMeasurement(
            name: name,
            duration: duration,
            memoryUsage: memoryDelta
        )
        
        return (result, measurement)
    }
    
    private static func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}


extension ProfileService: Testable {
    func resetForTesting() {
        reload()
    }
    
    var testState: [String: Any] {
        return [
            "profileCount": profiles.count,
            "profileNames": profiles.map { $0.profile.name },
            "isApplying": isApplying
        ]
    }
}

extension SystemService: Testable {
    func resetForTesting() {
        clearHotKeys()
        updateLaunchAtLoginStatus()
    }
    
    var testState: [String: Any] {
        return [
            "registeredHotKeys": registeredHotKeys,
            "isLaunchAtLoginEnabled": isLaunchAtLoginEnabled
        ]
    }
}

extension FileSystemService: Testable {
    func resetForTesting() {
    }
    
    var testState: [String: Any] {
        return [
            "serviceType": "FileSystemService",
            "isStateless": true
        ]
    }
}

#endif