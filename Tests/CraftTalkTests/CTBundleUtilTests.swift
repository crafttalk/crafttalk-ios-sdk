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
        XCTAssertEqual(CTBundleUtil.certificatePath(with: "CTCertificate", and: "der", in: [first, second]),
                       first.bundleURL.appendingPathComponent("CTCertificate.der").path)
        XCTAssertEqual(CTBundleUtil.certificatePath(with: "CTCertificate", and: "der", in: [second, first]),
                       second.bundleURL.appendingPathComponent("CTCertificate.der").path)
    }

    func testMissingCertificateFallsBackToNextBundleOrNil() throws {
        let empty = try bundle(["Other.der": Data([9])])
        let next = try bundle(["CTCertificate.cer": Data([1])])
        XCTAssertNil(CTBundleUtil.certificatePath(with: "CTCertificate", and: "cer", in: []))
        XCTAssertNil(CTBundleUtil.certificatePath(with: "CTCertificate", and: "cer", in: [empty]))
        XCTAssertEqual(CTBundleUtil.certificatePath(with: "CTCertificate", and: "cer", in: [empty, next]),
                       next.bundleURL.appendingPathComponent("CTCertificate.cer").path)
    }

    func testDefaultBundleOrderStartsWithMainWithoutDuplicates() {
        let bundles = CTBundleUtil.relevantBundles
        XCTAssertEqual(bundles.first, Bundle.main)
        XCTAssertEqual(Set(bundles.map { $0.bundleURL }).count, bundles.count)
    }
}
