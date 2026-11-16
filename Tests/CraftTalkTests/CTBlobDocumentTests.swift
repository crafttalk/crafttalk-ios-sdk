import XCTest
@testable import CraftTalk

final class CTBlobDocumentTests: XCTestCase {
    private var directory: URL!
    private let mimeTypes = ["txt": "text/plain", "pdf": "application/pdf", "bin": "application/octet-stream"]

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: nil)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testRejectsMalformedMessagesWithoutCreatingFiles() throws {
        let messages: [Any] = [42, NSNull(), ["data": "private"], "", "data:", "data:application/pdf",
                               "data:application/pdf;base64", "application/pdf;base64,QQ==",
                               "data:application/pdf,QQ==", "data:application/pdf;utf8,QQ==",
                               "data:application/pdf;base64,%%%", "data:application/pdf;base64,A"]
        for message in messages {
            XCTAssertThrowsError(try CTBlobDocument(messageBody: message, mimeTypes: mimeTypes).write(in: directory)) { error in
                guard let error = error as? CTChatError else { return XCTFail("Ожидалась CTChatError") }
                XCTAssertEqual(error.stage, .download)
                XCTAssertEqual(error.domain, NSURLErrorDomain)
                XCTAssertEqual(error.code, NSURLErrorCannotDecodeContentData)
                XCTAssertNil(error.host)
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    func testUnknownAndMissingMIMEProduceBinaryFiles() throws {
        for header in ["data:application/x-crafttalk-test;base64,", "data:;base64,"] {
            let document = try CTBlobDocument(messageBody: header + "AAEC/w==", mimeTypes: mimeTypes)
            let file = try document.write(in: directory)
            XCTAssertEqual(file.url.lastPathComponent, "download.bin")
            XCTAssertEqual(try Data(contentsOf: file.url), Data([0, 1, 2, 255]))
        }
    }

    func testKnownMIMEWithParametersPreservesBytes() throws {
        let document = try CTBlobDocument(messageBody: "data:TEXT/PLAIN;charset=utf-8;base64,0J/RgNC40LLQtdGC", mimeTypes: mimeTypes)
        let file = try document.write(in: directory)
        XCTAssertEqual(file.url.lastPathComponent, "download.txt")
        XCTAssertEqual(try String(contentsOf: file.url, encoding: .utf8), "Привет")
    }

    func testEmptyPayloadProducesEmptyFile() throws {
        let file = try CTBlobDocument(messageBody: "data:application/pdf;base64,", mimeTypes: mimeTypes).write(in: directory)
        XCTAssertEqual(try Data(contentsOf: file.url), Data())
    }

    func testFilesHaveIsolatedDirectoriesAndAreRemovedWithTheirOwner() throws {
        let document = try CTBlobDocument(messageBody: "data:application/pdf;base64,QQ==", mimeTypes: mimeTypes)
        var first: CTBlobFile? = try document.write(in: directory)
        let second = try document.write(in: directory)
        let firstURL = try XCTUnwrap(first?.url)
        XCTAssertNotEqual(firstURL.deletingLastPathComponent(), second.url.deletingLastPathComponent())
        XCTAssertEqual(firstURL.deletingLastPathComponent().deletingLastPathComponent(), directory)
        first = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.deletingLastPathComponent().path))
        XCTAssertEqual(try Data(contentsOf: second.url), Data([65]))
        second.remove()
        second.remove()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    func testWriteFailureLeavesNoPartialFilesAndAllowsRetry() throws {
        let blockedDirectory = directory.appendingPathComponent("occupied")
        try Data([1]).write(to: blockedDirectory)
        let document = try CTBlobDocument(messageBody: "data:application/pdf;base64,QQ==", mimeTypes: mimeTypes)
        XCTAssertThrowsError(try document.write(in: blockedDirectory)) { error in
            guard let error = error as? CTChatError else { return XCTFail("Ожидалась CTChatError") }
            XCTAssertEqual(error.stage, .download)
            XCTAssertEqual(error.domain, NSCocoaErrorDomain)
            XCTAssertNil(error.host)
            XCTAssertFalse(error.localizedDescription.contains("occupied"))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["occupied"])
        XCTAssertEqual(try Data(contentsOf: blockedDirectory), Data([1]))
        let retry = try document.write(in: directory)
        XCTAssertEqual(try Data(contentsOf: retry.url), Data([65]))
    }

    func testMalformedMessageDoesNotPreventNextDocument() throws {
        XCTAssertThrowsError(try CTBlobDocument(messageBody: "data:application/pdf;base64,private!", mimeTypes: mimeTypes))
        let file = try CTBlobDocument(messageBody: "data:application/pdf;base64,QQ==", mimeTypes: mimeTypes).write(in: directory)
        XCTAssertEqual(try Data(contentsOf: file.url), Data([65]))
    }
}
