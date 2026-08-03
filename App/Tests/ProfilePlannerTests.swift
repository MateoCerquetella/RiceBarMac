import Foundation
import XCTest
@testable import RiceBarMac

final class ProfilePlannerTests: XCTestCase {
    func testPreviewIsReadOnlyAndContainsExactBackupPath() throws {
        let home = try TemporaryHome()
        let destination = try home.write(".config/example.conf", "original")
        let descriptor = try makeProfileDescriptor(home: home.url, replacementDestination: destination)
        let before = try Data(contentsOf: destination)
        let planner = ProfilePlanner(home: home.url, fileSystem: LiveFileSystemClient())

        let plan = planner.makePlan(for: descriptor, formerActiveProfilePath: nil)

        XCTAssertTrue(plan.isValid, plan.issues.map(\.message).joined(separator: "\n"))
        XCTAssertEqual(try Data(contentsOf: destination), before)
        XCTAssertEqual(plan.actions.last?.destinationPath, destination.path)
        XCTAssertTrue(plan.actions.last?.backupPath.contains(plan.id.uuidString.lowercased()) == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.actions.last!.backupPath))
    }

    func testDestinationOutsideHomeIsRejectedBeforeMutation() throws {
        let home = try TemporaryHome()
        let descriptor = try makeProfileDescriptor(
            home: home.url,
            replacementDestination: URL(fileURLWithPath: "/tmp/ricebarmac-escape")
        )
        let planner = ProfilePlanner(home: home.url, fileSystem: LiveFileSystemClient())

        let plan = planner.makePlan(for: descriptor, formerActiveProfilePath: nil)

        XCTAssertFalse(plan.isValid)
        XCTAssertTrue(plan.issues.contains(where: { $0.code == .destinationOutsideHome }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/ricebarmac-escape"))
    }

    func testRecursiveMappingIsRejected() throws {
        let home = try TemporaryHome()
        let descriptor = try makeProfileDescriptor(home: home.url)
        var profile = descriptor.profile
        profile.replacements = [
            Profile.Replacement(source: "home", destination: descriptor.directory.appendingPathComponent("home/nested").path)
        ]
        let recursive = ProfileDescriptor(profile: profile, directory: descriptor.directory)

        let plan = ProfilePlanner(home: home.url).makePlan(for: recursive, formerActiveProfilePath: nil)

        XCTAssertTrue(plan.issues.contains(where: { $0.code == .recursiveMapping }))
    }

    func testParentSymlinkEscapingHomeIsRejected() throws {
        let home = try TemporaryHome()
        let linkedParent = home.url.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: linkedParent.path, withDestinationPath: "/tmp")
        let descriptor = try makeProfileDescriptor(home: home.url, replacementDestination: linkedParent.appendingPathComponent("settings"))

        let plan = ProfilePlanner(home: home.url).makePlan(for: descriptor, formerActiveProfilePath: nil)

        XCTAssertTrue(plan.issues.contains(where: { $0.code == .unsafeParentSymlink }))
    }

    func testManagedStorageDestinationIsRejected() throws {
        let home = try TemporaryHome()
        let destination = home.url.appendingPathComponent(".ricebarmac/transactions/overwrite.json")
        let descriptor = try makeProfileDescriptor(home: home.url, replacementDestination: destination)

        let plan = ProfilePlanner(home: home.url).makePlan(for: descriptor, formerActiveProfilePath: nil)

        XCTAssertFalse(plan.isValid)
        XCTAssertTrue(plan.issues.contains(where: { $0.code == .protectedDestination }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testHomeOverlayOrderingIsDeterministic() throws {
        let home = try TemporaryHome()
        let descriptor = try makeProfileDescriptor(home: home.url)
        try Data("z".utf8).write(to: descriptor.directory.appendingPathComponent("home/z.conf"))
        try FileManager.default.createDirectory(at: descriptor.directory.appendingPathComponent("home/.config"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: descriptor.directory.appendingPathComponent("home/.config/a.conf"))
        let planner = ProfilePlanner(home: home.url)

        let first = planner.makePlan(for: descriptor, formerActiveProfilePath: nil)
        let second = planner.makePlan(for: descriptor, formerActiveProfilePath: nil)

        XCTAssertEqual(first.actions.map(\.destinationPath), second.actions.map(\.destinationPath))
        XCTAssertEqual(first.actions.map(\.destinationPath), first.actions.map(\.destinationPath).sorted())
    }
}
