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
        XCTAssertEqual(config.appearance.menuBarIcon, "RB")
        XCTAssertEqual(config.shortcuts.profileShortcuts.count, 9)

        let existingIcon = String(UnicodeScalar(0x1F35A)!)
        let customData = Data(#"{"appearance":{"menuBarIcon":"\#(existingIcon)"}}"#.utf8)
        let customConfig = try JSONDecoder().decode(RiceBarConfig.self, from: customData)
        XCTAssertEqual(customConfig.appearance.menuBarIcon, existingIcon)
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

        let previous = service.config
        service.updateGeneralSetting(\.showNotifications, to: !previous.general.showNotifications)

        XCTAssertEqual(service.config, previous)
        XCTAssertEqual(try Data(contentsOf: configURL), original)
        guard case .invalid = service.loadState else {
            return XCTFail("A rejected save must keep the invalid load state")
        }
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

    func testExternalConfigChangeIsNotOverwritten() throws {
        let home = try TemporaryHome()
        let root = try home.createDirectory(".ricebarmac")
        let configURL = root.appendingPathComponent("config.json")
        try Data(#"{"general":{"showNotifications":true}}"#.utf8).write(to: configURL)
        let service = ConfigService(rootURL: root, fileSystem: LiveFileSystemClient())
        let previous = service.config
        let external = Data("{ externally-edited".utf8)
        try external.write(to: configURL)

        service.updateGeneralSetting(\.showNotifications, to: false)

        XCTAssertEqual(service.config, previous)
        XCTAssertEqual(try Data(contentsOf: configURL), external)
        guard case .invalid = service.loadState else {
            return XCTFail("An external change must require an explicit reload")
        }
    }

    func testConfigChangeDuringStagingIsNotOverwritten() throws {
        let home = try TemporaryHome()
        let root = try home.createDirectory(".ricebarmac")
        let configURL = root.appendingPathComponent("config.json")
        try Data(#"{"general":{"showNotifications":true}}"#.utf8).write(to: configURL)
        let fileSystem = FaultInjectingFileSystemClient()
        let service = ConfigService(rootURL: root, fileSystem: fileSystem)
        let external = Data("{ changed-during-staging".utf8)
        fileSystem.afterMutation = { count, _ in
            guard count == 1 else { return }
            try external.write(to: configURL)
        }
        service.config.general.showNotifications = false

        XCTAssertFalse(service.saveConfig())

        XCTAssertEqual(try Data(contentsOf: configURL), external)
        XCTAssertNil(service.lastBackupURL)
        guard case .invalid = service.loadState else {
            return XCTFail("A concurrent edit must require an explicit reload")
        }
    }

    func testConfigCreatedAfterBackupIsPreservedAlongsideOriginalBackup() throws {
        let home = try TemporaryHome()
        let root = try home.createDirectory(".ricebarmac")
        let configURL = root.appendingPathComponent("config.json")
        let original = Data(#"{"general":{"showNotifications":true}}"#.utf8)
        try original.write(to: configURL)
        let fileSystem = FaultInjectingFileSystemClient()
        let service = ConfigService(rootURL: root, fileSystem: fileSystem)
        let external = Data("{ created-after-backup".utf8)
        fileSystem.afterMutation = { count, _ in
            guard count == 2 else { return }
            try external.write(to: configURL)
        }
        service.config.general.showNotifications = false

        XCTAssertFalse(service.saveConfig())

        XCTAssertEqual(try Data(contentsOf: configURL), external)
        let backup = try XCTUnwrap(service.lastBackupURL)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        guard case .invalid = service.loadState else {
            return XCTFail("An ambiguous commit must require explicit recovery")
        }
    }

    func testOlderProfileDefaultsOrderAndOptionalCollections() throws {
        let profile = try JSONDecoder().decode(Profile.self, from: Data(#"{"name":"Legacy"}"#.utf8))
        XCTAssertEqual(profile.name, "Legacy")
        XCTAssertEqual(profile.order, 0)
        XCTAssertEqual(profile.replacements, [])
    }
}
