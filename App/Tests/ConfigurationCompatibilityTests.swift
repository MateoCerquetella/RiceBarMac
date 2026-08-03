import Foundation
import XCTest
@testable import RiceBarMac

final class ConfigurationCompatibilityTests: XCTestCase {
    func testMissingKnownFieldsUseDefaultsAndUnknownFieldsAreIgnored() throws {
        let data = Data(#"{"general":{"launchAtLogin":true},"future":{"value":42}}"#.utf8)
        let config = try JSONDecoder().decode(RiceBarConfig.self, from: data)

        XCTAssertTrue(config.general.launchAtLogin)
        XCTAssertTrue(config.general.autoReloadProfiles)
        XCTAssertTrue(config.general.showNotifications)
        XCTAssertEqual(config.appearance.menuBarIcon, "🍚")
        XCTAssertEqual(config.shortcuts.profileShortcuts.count, 9)
    }

    func testMalformedConfigurationIsNeverOverwrittenDuringInitialization() throws {
        let home = try TemporaryHome()
        let root = try home.createDirectory(".ricebarmac")
        let configURL = root.appendingPathComponent("config.json")
        let original = Data("{ definitely-not-json".utf8)
        try original.write(to: configURL)

        let service = ConfigService(rootURL: root, fileSystem: LiveFileSystemClient())

        guard case .invalid = service.loadState else {
            return XCTFail("Expected invalid load state")
        }
        XCTAssertEqual(try Data(contentsOf: configURL), original)
        XCTAssertNotNil(service.lastError)
    }

    func testMissingConfigurationDoesNotCreateRootOnLoad() throws {
        let home = try TemporaryHome()
        let root = home.url.appendingPathComponent(".ricebarmac", isDirectory: true)

        let service = ConfigService(rootURL: root, fileSystem: LiveFileSystemClient())

        XCTAssertEqual(service.loadState, .missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testSaveCreatesBackupAndWritesDecodableConfiguration() throws {
        let home = try TemporaryHome()
        let root = try home.createDirectory(".ricebarmac")
        let configURL = root.appendingPathComponent("config.json")
        try Data(#"{"general":{"launchAtLogin":false}}"#.utf8).write(to: configURL)
        let service = ConfigService(rootURL: root, fileSystem: LiveFileSystemClient())

        service.config.general.showNotifications = false
        XCTAssertTrue(service.saveConfig())
        XCTAssertNotNil(service.lastBackupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.lastBackupURL!.path))
        let saved = try JSONDecoder().decode(RiceBarConfig.self, from: Data(contentsOf: configURL))
        XCTAssertFalse(saved.general.showNotifications)
    }

    func testOlderProfileDefaultsOrderAndOptionalCollections() throws {
        let profile = try JSONDecoder().decode(Profile.self, from: Data(#"{"name":"Legacy"}"#.utf8))
        XCTAssertEqual(profile.name, "Legacy")
        XCTAssertEqual(profile.order, 0)
        XCTAssertEqual(profile.replacements, [])
    }
}
