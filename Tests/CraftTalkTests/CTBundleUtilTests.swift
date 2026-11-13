import XCTest
@testable import CraftTalk

final class CTBundleUtilTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: nil)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func bundle(_ files: [String: Data]) throws -> Bundle {
        let name = UUID().uuidString
        let path = directory.appendingPathComponent(name + ".bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false, attributes: nil)
        let plist = ["CFBundleIdentifier": "com.crafttalk.tests." + name, "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: path.appendingPathComponent("Info.plist"))
        for (name, data) in files { try data.write(to: path.appendingPathComponent(name)) }
        return try XCTUnwrap(Bundle(url: path))
    }

    func testFirstBundleWinsForSameCertificateType() throws {
        let first = try bundle(["CTCertificate.der": Data([1])])
        let second = try bundle(["CTCertificate.der": Data([2])])
        XCTAssertEqual(CTBundleUtil.certificateData(in: [first, second]), Data([1]))
        XCTAssertEqual(CTBundleUtil.certificateData(in: [second, first]), Data([2]))
    }

    func testLegacyExtensionPriorityPrecedesBundlePriority() throws {
        let first = try bundle(["CTCertificate.cer": Data([1]), "CTCertificate.crt": Data([3])])
        let second = try bundle(["CTCertificate.der": Data([2])])
        XCTAssertEqual(CTBundleUtil.certificateData(in: [first, second]), Data([2]))
        XCTAssertEqual(CTBundleUtil.certificateData(in: [first]), Data([1]))
        let crt = try bundle(["CTCertificate.crt": Data([3])])
        XCTAssertEqual(CTBundleUtil.certificateData(in: [crt]), Data([3]))
    }

    func testMissingCertificateFallsBackToNextBundleOrNil() throws {
        let empty = try bundle(["Other.der": Data([9])])
        let next = try bundle(["CTCertificate.cer": Data([1])])
        XCTAssertNil(CTBundleUtil.certificateData(in: []))
        XCTAssertNil(CTBundleUtil.certificateData(in: [empty]))
        XCTAssertEqual(CTBundleUtil.certificateData(in: [empty, next]), Data([1]))
    }

    func testDefaultBundleOrderStartsWithMainWithoutDuplicates() {
        let bundles = CTBundleUtil.relevantBundles
        XCTAssertEqual(bundles.first, Bundle.main)
        XCTAssertEqual(Set(bundles.map { $0.bundleURL }).count, bundles.count)
    }

    func testCertificateLoadingIsLazyAndSecureConfigurationDoesNotReadLegacyResource() throws {
        let source = try bundle(["CTCertificate.der": Data([1, 2, 3])])
        var reads = 0
        let settings = ["CTChatBaseURL": "https://chat.example.com", "CTChatNamespace": "channel", "CTSalt": "salt"]
        let chat = CTChat(infoValue: { settings[$0] }, certificateBundles: { reads += 1; return [source] })
        try chat.configure(security: CTSecurityConfiguration())
        XCTAssertEqual(reads, 0)
        chat.configure()
        XCTAssertEqual(chat.certificate, Data([1, 2, 3]))
        XCTAssertEqual(chat.certificate, Data([1, 2, 3]))
        XCTAssertEqual(reads, 1)
    }
}
