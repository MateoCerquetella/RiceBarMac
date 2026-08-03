import Foundation
import XCTest
@testable import RiceBarMac

private final class SnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ProfileOperationSnapshot] = []

    func append(_ value: ProfileOperationSnapshot) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func contains(_ phase: ProfileOperationSnapshot.Phase) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return values.contains(where: { $0.phase == phase })
    }
}

final class ProfileApplicationCoordinatorTests: XCTestCase {
    func testConcurrentRequestsAreQueuedAndNeverMutateTogether() async throws {
        let home = try TemporaryHome()
        let firstDestination = home.url.appendingPathComponent(".config/first")
        let secondDestination = home.url.appendingPathComponent(".config/second")
        let firstDescriptor = try makeProfileDescriptor(home: home.url, name: "First", replacementDestination: firstDestination)
        let secondDescriptor = try makeProfileDescriptor(home: home.url, name: "Second", replacementDestination: secondDestination)
        let fileSystem = FaultInjectingFileSystemClient()
        fileSystem.mutationDelay = 0.01
        let planner = ProfilePlanner(home: home.url, fileSystem: fileSystem)
        let activeStore = MemoryActiveProfileStore()
        let executor = makeExecutor(
            home: home.url,
            fileSystem: fileSystem,
            transactionStore: MemoryTransactionStore(),
            activeStore: activeStore
        )
        let coordinator = ProfileApplicationCoordinator(planner: planner, executor: executor, activeProfileStore: activeStore)
        let recorder = SnapshotRecorder()
        await coordinator.setStateHandler { recorder.append($0) }
        let firstPlan = planner.makePlan(for: firstDescriptor, formerActiveProfilePath: nil)
        let secondPlan = planner.makePlan(for: secondDescriptor, formerActiveProfilePath: nil)

        async let first = coordinator.apply(firstPlan)
        try await Task.sleep(nanoseconds: 5_000_000)
        async let second = coordinator.apply(secondPlan)
        _ = try await (first, second)

        XCTAssertEqual(fileSystem.maximumConcurrentMutations, 1)
        XCTAssertTrue(recorder.contains(.queued))
        XCTAssertEqual(try fileSystem.state(at: firstDestination).kind, .symbolicLink)
        XCTAssertEqual(try fileSystem.state(at: secondDestination).kind, .symbolicLink)
    }

    func testCancelledQueuedRequestNeverMutatesItsDestination() async throws {
        let home = try TemporaryHome()
        let firstDestination = home.url.appendingPathComponent(".config/first")
        let secondDestination = home.url.appendingPathComponent(".config/second")
        let firstDescriptor = try makeProfileDescriptor(home: home.url, name: "First", replacementDestination: firstDestination)
        let secondDescriptor = try makeProfileDescriptor(home: home.url, name: "Second", replacementDestination: secondDestination)
        let fileSystem = FaultInjectingFileSystemClient()
        fileSystem.mutationDelay = 0.02
        let planner = ProfilePlanner(home: home.url, fileSystem: fileSystem)
        let activeStore = MemoryActiveProfileStore()
        let executor = makeExecutor(
            home: home.url,
            fileSystem: fileSystem,
            transactionStore: MemoryTransactionStore(),
            activeStore: activeStore
        )
        let coordinator = ProfileApplicationCoordinator(planner: planner, executor: executor, activeProfileStore: activeStore)
        let firstPlan = planner.makePlan(for: firstDescriptor, formerActiveProfilePath: nil)
        let secondPlan = planner.makePlan(for: secondDescriptor, formerActiveProfilePath: nil)

        let firstTask = Task { try await coordinator.apply(firstPlan) }
        try await Task.sleep(nanoseconds: 5_000_000)
        let secondTask = Task { try await coordinator.apply(secondPlan) }
        secondTask.cancel()
        _ = try await firstTask.value
        do {
            _ = try await secondTask.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }

        XCTAssertEqual(try fileSystem.state(at: secondDestination).kind, .absent)
    }

    @MainActor
    func testThousandFileApplyKeepsMainActorResponsive() async throws {
        let home = try TemporaryHome()
        let descriptor = try makeProfileDescriptor(home: home.url, name: "Large")
        for index in 0..<1_000 {
            let relative = String(format: "home/.config/large/%04d.conf", index)
            let file = descriptor.directory.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("value-\(index)".utf8).write(to: file)
        }
        let fileSystem = FaultInjectingFileSystemClient()
        fileSystem.mutationDelay = 0.0002
        let planner = ProfilePlanner(home: home.url, fileSystem: fileSystem)
        let activeStore = MemoryActiveProfileStore()
        let executor = makeExecutor(
            home: home.url,
            fileSystem: fileSystem,
            transactionStore: MemoryTransactionStore(),
            activeStore: activeStore
        )
        let coordinator = ProfileApplicationCoordinator(planner: planner, executor: executor, activeProfileStore: activeStore)
        let plan = planner.makePlan(for: descriptor, formerActiveProfilePath: nil)
        XCTAssertGreaterThanOrEqual(plan.actions.count, 1_000)

        var heartbeat = 0
        let heartbeatTask = Task { @MainActor in
            while !Task.isCancelled {
                heartbeat += 1
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }

        _ = try await coordinator.apply(plan)
        heartbeatTask.cancel()

        XCTAssertGreaterThan(heartbeat, 5)
        XCTAssertEqual(fileSystem.maximumConcurrentMutations, 1)
    }
}
