import Foundation
import Testing

@testable import Klassik

struct PartialAudioFileTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    func file(_ name: String = "audio.partial", capacity: Int64? = nil) throws -> PartialAudioFile {
        try PartialAudioFile(url: root.appending(path: name), capacity: capacity)
    }

    func read(_ file: PartialAudioFile, _ range: Range<Int64>) throws -> Data {
        var data = Data(count: range.count)
        _ = try data.withUnsafeMutableBytes {
            try file.read(at: range.lowerBound, count: range.count, into: $0.baseAddress!)
        }
        return data
    }

    @Test func aWholeFilePublishesWithoutCopying() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file()
        let data = Data(0..<100)
        try file.append(data)
        #expect(try read(file, 0..<100) == data)
        let target = root.appending(path: "audio.flac")
        try file.publish(to: target)
        #expect(try Data(contentsOf: target) == data)
        #expect(!FileManager.default.fileExists(atPath: file.url.path()))
        #expect(try read(file, 10..<20) == data.subdata(in: 10..<20))
    }

    @Test func aFullWindowProtectsUnreadBytes() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file(capacity: 16)
        try file.append(Data(0..<16))
        #expect(file.writableBytes == 0)
        #expect(throws: PartialAudioFile.Failure.full) { try file.append(Data([99])) }
        #expect(file.received == 16)
        #expect(try read(file, 0..<16) == Data(0..<16))
    }

    @Test func wrappingPreservesMetadataAndSourceCoordinates() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file(capacity: 16)
        try file.append(Data(0..<16))
        file.discard(before: 8)
        try file.append(Data(16..<20))
        #expect(file.ranges == [0..<4, 8..<20])
        #expect(try read(file, 0..<4) == Data(0..<4))
        #expect(try read(file, 8..<20) == Data(8..<20))
        #expect(throws: PartialAudioFile.Failure.invalidRange) { try read(file, 4..<8) }
        #expect(throws: PartialAudioFile.Failure.invalidRange) { try read(file, 2..<10) }
        #expect(throws: PartialAudioFile.Failure.incomplete) { try file.publish(to: root.appending(path: "audio")) }
        #expect(file.storedBytes == 16)
        #expect(try Data(contentsOf: file.url).count == 16)
    }

    @Test func manyWrapsStayBoundedAndNeverExposeStaleBytes() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file(capacity: 16)
        try file.append(Data(0..<16))
        for position in stride(from: 16, to: 200, by: 4) {
            file.discard(before: Int64(position - 8))
            try file.append(Data((position..<(position + 4)).map(UInt8.init)))
            let body = Int64(position - 8)..<Int64(position + 4)
            #expect(try read(file, body) == Data(body.map { UInt8($0) }))
            #expect(try read(file, 0..<4) == Data(0..<4))
            #expect(try Data(contentsOf: file.url).count == 16)
        }
    }

    @Test(arguments: [Int64(2), 7, 16, 31, 65_537])
    func arbitraryWindowsRetainOnlyTheirDeclaredRanges(capacity: Int64) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file(capacity: capacity)
        let source = Data((0..<Int(capacity * 3)).map { UInt8($0 % 251) })
        var cursor = 0
        while cursor < source.count {
            let count = min(Int(file.writableBytes), 127, source.count - cursor)
            if count == 0 {
                file.discard(before: file.received)
                continue
            }
            try file.append(source.subdata(in: cursor..<(cursor + count)))
            cursor += count
            for range in file.ranges {
                #expect(try read(file, range) == source.subdata(in: Int(range.lowerBound)..<Int(range.upperBound)))
            }
            #expect(try Data(contentsOf: file.url).count <= capacity)
        }
    }

    @Test func publishingReplacesTheTargetAtomically() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file()
        try file.append(Data([1, 2, 3]))
        let target = root.appending(path: "audio.flac")
        try Data([9]).write(to: target)
        try file.publish(to: target)
        #expect(try Data(contentsOf: target) == Data([1, 2, 3]))
        #expect(try read(file, 0..<3) == Data([1, 2, 3]))
    }

    @Test func aDownloadCopiesRetainedBytesAndRequestsOnlyHoles() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file(capacity: 16)
        try file.append(Data(0..<16))
        file.discard(before: 8)
        try file.append(Data(16..<20))
        let download = try self.file("download.partial")
        var requests: [Range<Int64>] = []
        try file.copy(to: download) { position, count in
            let range = position..<(position + Int64(count))
            requests.append(range)
            return Data(range.map(UInt8.init))
        }
        #expect(requests == [4..<8])
        #expect(try read(download, 0..<20) == Data(0..<20))
        #expect(try read(file, 8..<20) == Data(8..<20))
    }

    @Test func anUnreclaimedDownloadNeedsNoSecondRequest() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file(capacity: 16)
        try file.append(Data(0..<12))
        let download = try self.file("download.partial")
        try file.copy(to: download) { _, _ in
            Issue.record("Retained bytes must not load again")
            throw PartialAudioFile.Failure.incomplete
        }
        #expect(try read(download, 0..<12) == Data(0..<12))
    }

    @Test func missingBytesCannotPublishADownload() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file(capacity: 16)
        try file.append(Data(0..<16))
        file.discard(before: 8)
        let download = try self.file("download.partial")
        #expect(throws: PartialAudioFile.Failure.incomplete) {
            try file.copy(to: download) { _, _ in Data() }
        }
    }

    @Test func diskTruncationIsAnError() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file()
        try file.append(Data(0..<16))
        let handle = try FileHandle(forWritingTo: file.url)
        try handle.truncate(atOffset: 8)
        try handle.close()
        #expect(throws: PartialAudioFile.Failure.storage) { try read(file, 0..<16) }
    }

    @Test func invalidCoordinatesFailBeforeDiskAccess() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try file()
        var byte: UInt8 = 0
        #expect(throws: PartialAudioFile.Failure.invalidRange) {
            try file.read(at: .max, count: 2, into: &byte)
        }
        #expect(throws: PartialAudioFile.Failure.invalidRange) {
            try file.read(at: -1, count: 1, into: &byte)
        }
    }
}
