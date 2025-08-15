import XCTest
@testable import RiceBarMac

/// Unit tests for Profile and ProfileDescriptor
final class ProfileTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Reset any shared state
    }
    
    override func tearDown() {
        super.tearDown()
        // Clean up after tests
    }
    
    // MARK: - Profile Tests
    
    func testProfileInitialization() {
        let profile = Profile(name: "TestProfile")
        
        XCTAssertEqual(profile.name, "TestProfile")
        XCTAssertEqual(profile.order, 0)
        XCTAssertNil(profile.hotkey)
        XCTAssertNil(profile.wallpaper)
        XCTAssertNil(profile.terminal)
        XCTAssertNotNil(profile.replacements)
        XCTAssertTrue(profile.replacements?.isEmpty ?? false)
        XCTAssertNil(profile.startupScript)
    }
    
    func testProfileNameSanitization() {
        let profileWithSlash = Profile(name: "Test/Profile")
        XCTAssertEqual(profileWithSlash.name, "Test-Profile")
        
        let profileWithWhitespace = Profile(name: "  Test Profile  ")
        XCTAssertEqual(profileWithWhitespace.name, "Test Profile")
    }
    
    func testProfileValidation() {
        let validProfile = Profile(name: "ValidProfile")
        XCTAssertNoThrow(try validProfile.validate())
        
        let invalidProfile = Profile(name: "")
        XCTAssertThrowsError(try invalidProfile.validate())
    }
    
    func testProfileEquality() {
        let profile1 = Profile(name: "TestProfile")
        let profile2 = Profile(name: "TestProfile")
        let profile3 = Profile(name: "DifferentProfile")
        
        XCTAssertEqual(profile1, profile2)
        XCTAssertNotEqual(profile1, profile3)
    }
    
    func testProfileCodable() {
        let original = TestProfileFactory.createCompleteTestProfile()
        
        XCTAssertNoThrow({
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(Profile.self, from: data)
            XCTAssertEqual(original, decoded)
        })
    }
    
    // MARK: - ProfileDescriptor Tests
    
    func testProfileDescriptorInitialization() {
        let profile = TestProfileFactory.createTestProfile()
        let directory = URL(fileURLWithPath: "/tmp/test")
        let descriptor = ProfileDescriptor(profile: profile, directory: directory)
        
        XCTAssertEqual(descriptor.profile, profile)
        XCTAssertEqual(descriptor.directory, directory)
        XCTAssertEqual(descriptor.displayName, profile.name)
        XCTAssertEqual(descriptor.id, directory.lastPathComponent)
    }
    
    func testProfileDescriptorDisplayName() {
        let profile = Profile(name: "")
        let directory = URL(fileURLWithPath: "/tmp/TestDirectory")
        let descriptor = ProfileDescriptor(profile: profile, directory: directory)
        
        XCTAssertEqual(descriptor.displayName, "TestDirectory")
    }
    
    // MARK: - Terminal Configuration Tests
    
    func testTerminalConfiguration() {
        let terminal = Profile.Terminal(kind: .alacritty, theme: "dark-theme")
        
        XCTAssertEqual(terminal.kind, .alacritty)
        XCTAssertEqual(terminal.theme, "dark-theme")
    }
    
    func testTerminalKindCodable() {
        let kinds: [Profile.Terminal.Kind] = [.alacritty, .terminalApp, .iterm2]
        
        for kind in kinds {
            XCTAssertNoThrow({
                let data = try JSONEncoder().encode(kind)
                let decoded = try JSONDecoder().decode(Profile.Terminal.Kind.self, from: data)
                XCTAssertEqual(kind, decoded)
            })
        }
    }
    
    // MARK: - Replacement Tests
    
    func testReplacement() {
        let replacement = Profile.Replacement(source: "source.txt", destination: "~/destination.txt")
        
        XCTAssertEqual(replacement.source, "source.txt")
        XCTAssertEqual(replacement.destination, "~/destination.txt")
    }
    
    // MARK: - Performance Tests
    
    func testProfileCreationPerformance() {
        measure {
            for i in 0..<1000 {
                _ = Profile(name: "TestProfile\(i)")
            }
        }
    }
    
    func testProfileValidationPerformance() {
        let profiles = (0..<1000).map { Profile(name: "TestProfile\($0)") }
        
        measure {
            for profile in profiles {
                try? profile.validate()
            }
        }
    }
}