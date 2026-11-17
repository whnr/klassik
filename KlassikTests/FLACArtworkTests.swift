import Foundation
import Testing

@testable import Klassik

struct FLACArtworkTests {
    private func integer(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) }
    }

    private func block(_ type: UInt8, _ body: Data) -> Data {
        Data([type]) + integer(body.count).dropFirst() + body
    }

    private func picture(_ image: Data, mime: String = "image/png", description: String = "Cover") -> Data {
        integer(3) + integer(mime.utf8.count) + Data(mime.utf8)
            + integer(description.utf8.count) + Data(description.utf8)
            + integer(8) + integer(8) + integer(24) + integer(0) + integer(image.count) + image
    }

    private func read(_ data: Data) throws -> Data? {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try data.write(to: file)
        return FLACArtwork.data(in: file)
    }

    @Test func findsArtworkAfterOtherMetadataWithoutReadingAudio() throws {
        let image = Data([1, 2, 3, 4])
        let file =
            Data("fLaC".utf8) + block(0, Data(count: 34)) + block(4, Data(count: 100))
            + block(0x86, picture(image)) + Data(count: 1_000)
        #expect(try read(file) == image)
    }

    @Test func rejectsTruncatedAndInvalidMetadata() throws {
        let body = picture(Data([1, 2, 3]))
        let valid = Data("fLaC".utf8) + block(0x86, body)
        for count in 0..<valid.count {
            #expect(try read(valid.prefix(count)) == nil)
        }
        for count in 0..<body.count {
            #expect(try read(Data("fLaC".utf8) + block(0x86, body.prefix(count))) == nil)
        }
        #expect(try read(Data("not FLAC".utf8)) == nil)
        #expect(try read(Data("fLaC".utf8) + block(0x80, Data(count: 34))) == nil)
        #expect(try read(Data("fLaC".utf8) + block(0x86, integer(3) + integer(Int(UInt32.max)))) == nil)
    }
}
