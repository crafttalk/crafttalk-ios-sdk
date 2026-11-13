import XCTest
@testable import CraftTalk

final class CTAttachmentRulesTests: XCTestCase {
    func testDownloadAttributeRecognizesExtensionlessLinks() throws {
        let url = try XCTUnwrap(URL(string: "https://chat.example.com/once?token=synthetic"))
        XCTAssertTrue(CTAttachmentRules.isAttachmentLink(url, hasDownloadAttribute: true))
        XCTAssertFalse(CTAttachmentRules.isAttachmentLink(url, hasDownloadAttribute: false))
    }

    func testKnownExtensionsAndSDKFileEndpointAreRecognized() throws {
        for path in ["report.PDF", "archive.zip?token=test", "image.png", "movie.mp4", "webchat/channel/file/opaque"] {
            let url = try XCTUnwrap(URL(string: "https://chat.example.com/" + path))
            XCTAssertTrue(CTAttachmentRules.isAttachmentLink(url, hasDownloadAttribute: false), path)
        }
    }

    func testHTMLAndLookalikeEndpointsRemainNavigation() throws {
        for path in ["index.html", "index.xhtml", "page?name=file.pdf", "webchat/channel/profile/id", "other/file/id", "webchat-file/id"] {
            let url = try XCTUnwrap(URL(string: "https://chat.example.com/" + path))
            XCTAssertFalse(CTAttachmentRules.isAttachmentLink(url, hasDownloadAttribute: false), path)
        }
    }

    func testSafeFilenamePreservesBasenameAndUnicode() {
        for (input, expected) in [("../nested/отчёт.pdf", "отчёт.pdf"), ("/private/file.txt", "file.txt"), ("archive.zip", "archive.zip")] {
            XCTAssertEqual(CTAttachmentRules.safeFilename(input), expected)
        }
    }

    func testFilenameUsesUnixBasenameAndFallbackForEmptyOrDotNames() {
        for input in [nil, "", ".", "..", "../.."] {
            XCTAssertEqual(CTAttachmentRules.safeFilename(input), "download")
        }
        XCTAssertEqual(CTAttachmentRules.safeFilename("..\\folder\\report.pdf"), "..\\folder\\report.pdf")
        XCTAssertEqual(CTAttachmentRules.safeFilename("a\nb.pdf"), "a\nb.pdf")
    }

    func testPercentEncodedSeparatorsCannotEscapeDirectory() {
        let directory = URL(fileURLWithPath: "/tmp/isolated", isDirectory: true)
        for input in ["%2F..%2Fsecret", "..%5Csecret", "%2e%2e"] {
            let url = directory.appendingPathComponent(CTAttachmentRules.safeFilename(input))
            XCTAssertEqual(url.deletingLastPathComponent(), directory)
            XCTAssertEqual(url.lastPathComponent, input)
        }
    }

    func testMIMEAndPreviewClassification() throws {
        for (name, mime) in [("photo.jpg", "image/jpeg"), ("file.pdf", "application/pdf"), ("movie.mp4", "video/mp4"), ("unknown.crafttalkunknown", "application/octet-stream")] {
            let url = URL(fileURLWithPath: "/tmp/" + name)
            XCTAssertEqual(url.mimeType(), mime)
            switch CTPreviewType(fileURL: url) {
            case .image(let actual): XCTAssertEqual(actual, url); XCTAssertEqual(mime, "image/jpeg")
            case .pdf(let actual): XCTAssertEqual(actual, url); XCTAssertEqual(mime, "application/pdf")
            case .video(let actual): XCTAssertEqual(actual, url); XCTAssertEqual(mime, "video/mp4")
            case nil: XCTAssertEqual(mime, "application/octet-stream")
            }
        }
        XCTAssertNil(CTPreviewType(fileURL: URL(fileURLWithPath: "/tmp/archive.zip")))
        XCTAssertNil(CTPreviewType(fileURL: URL(fileURLWithPath: "/tmp/no-extension")))
    }
}
