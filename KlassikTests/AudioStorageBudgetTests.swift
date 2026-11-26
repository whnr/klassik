import Foundation
import Testing

@testable import Klassik
@testable import KlassikEngine

struct AudioStorageBudgetTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    @Test func automaticFilesShareOneLimit() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let budget = AudioStorageBudget(limit: 16)
        let first = try PartialAudioFile(url: root.appending(path: "a"), capacity: 8, budget: budget)
        let next = try PartialAudioFile(url: root.appending(path: "b"), capacity: 8, budget: budget)
        try first.append(Data(0..<8))
        try next.append(Data(0..<8))
        #expect(budget.storedBytes == 16)
        #expect(throws: PartialAudioFile.Failure.full) { try next.append(Data([1])) }
        first.discard(before: 8)
        try first.append(Data(8..<14))
        #expect(budget.storedBytes == 16)
    }

    @Test func existingCacheFilesCompeteWithPartialFiles() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let budget = AudioStorageBudget(limit: 16)
        let old = root.appending(path: "old.flac")
        budget.synchronize([old: 10])
        let partial = try PartialAudioFile(url: root.appending(path: "audio.partial"), budget: budget)
        #expect(throws: PartialAudioFile.Failure.full) { try partial.append(Data(count: 8)) }
        #expect(partial.received == 0)
        #expect(try Data(contentsOf: partial.url).isEmpty)
        budget.synchronize([:])
        try partial.append(Data(count: 8))
        budget.synchronize([partial.url: 8])
        #expect(budget.storedBytes == 8)
    }

    @Test func unlinkingAnOpenFileKeepsItsReservation() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let budget = AudioStorageBudget(limit: 8)
        let url = root.appending(path: "audio.partial")
        var file: PartialAudioFile? = try PartialAudioFile(url: url, budget: budget)
        try file!.append(Data(count: 8))
        try FileManager.default.removeItem(at: url)
        budget.synchronize([:])
        #expect(budget.storedBytes == 8)
        file = nil
        #expect(budget.storedBytes == 0)
    }

    @Test func publicationKeepsOnePhysicalChargeAfterTheWriterCloses() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let budget = AudioStorageBudget(limit: 8)
        var file: PartialAudioFile? = try PartialAudioFile(url: root.appending(path: "audio.partial"), budget: budget)
        try file!.append(Data(count: 8))
        let target = root.appending(path: "audio.flac")
        try file!.publish(to: target)
        budget.synchronize([target: 8])
        #expect(budget.storedBytes == 8)
        file = nil
        #expect(budget.storedBytes == 8)
        try FileManager.default.removeItem(at: target)
        budget.synchronize([:])
        #expect(budget.storedBytes == 0)
    }

    @Test func anAbandonedPartialFileStillCounts() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let budget = AudioStorageBudget(limit: 8)
        var file: PartialAudioFile? = try PartialAudioFile(url: root.appending(path: "audio.partial"), budget: budget)
        try file!.append(Data(count: 8))
        file = nil
        #expect(budget.storedBytes == 8)
    }

    @Test func aLowerLimitRefusesGrowthUntilStorageFits() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let budget = AudioStorageBudget(limit: 16)
        let file = try PartialAudioFile(url: root.appending(path: "audio.partial"), budget: budget)
        try file.append(Data(count: 8))
        budget.limit = 4
        #expect(throws: PartialAudioFile.Failure.full) { try file.append(Data([1])) }
        #expect(budget.storedBytes == 8)
    }

    @Test func concurrentWritersCannotOverspendTheBudget() {
        defer { try? FileManager.default.removeItem(at: root) }
        let budget = AudioStorageBudget(limit: 64)
        let root = root
        DispatchQueue.concurrentPerform(iterations: 32) { index in
            do {
                let file = try PartialAudioFile(url: root.appending(path: "\(index).partial"), budget: budget)
                try file.append(Data(count: 16))
            } catch PartialAudioFile.Failure.full {
            } catch {
                Issue.record("Unexpected storage failure: \(error)")
            }
            #expect(budget.storedBytes <= 64)
        }
        #expect(budget.storedBytes == 64)
    }
}
