import XCTest
@testable import CraftTalk

final class CTVisitorTests: XCTestCase {
    private func json(_ visitor: CTVisitor) throws -> [String: Any] {
        let text = try XCTUnwrap(visitor.toJSON())
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func testHashUsesDocumentedFieldOrder() {
        let visitor = CTVisitor(firstName: "first", lastName: "last", email: "email", phone: "phone",
                                contract: "contract", birthday: "birthday", uuid: "id", salt: "salt")
        // Контрольные значения рассчитаны независимо через Python hashlib.
        XCTAssertEqual(visitor.hash, "d47dd65dd012fc39b4b1bc2d3a587a2c18abb8375aa44d343f01d2e256c3f6f1")
    }

    func testHashPreservesUnicodeUTF8() throws {
        let visitor = CTVisitor(firstName: "Анна", lastName: "姓", email: "a@b", phone: "+123",
                                contract: "договор", birthday: "2000-01-02", uuid: "ид", salt: "соль🔑")
        XCTAssertEqual(visitor.hash, "2ed987b1d04d5d82c4e83be12441d9672ff097abcbb1b28dc16fc21dd4f1784f")
        XCTAssertEqual(try json(visitor)["first_name"] as? String, "Анна")
    }

    func testNilAndEmptyFieldsHaveSameHashButDifferentJSON() throws {
        let absent = CTVisitor(uuid: "id", salt: "salt")
        let empty = CTVisitor(firstName: "", lastName: "", email: "", phone: "", contract: "", birthday: "", uuid: "id", salt: "salt")
        XCTAssertEqual(absent.hash, "3600a41e6da69439ff47add855d919e53a1672adf1a0868439b6b71fd548849f")
        XCTAssertEqual(empty.hash, absent.hash)
        XCTAssertEqual(Set(try json(absent).keys), ["uuid", "hash"])
        for key in ["first_name", "last_name", "email", "phone", "contract", "birthday"] {
            XCTAssertEqual(try json(empty)[key] as? String, "")
        }
    }

    func testEmptyUUIDAndSaltHaveStableHash() {
        XCTAssertEqual(CTVisitor(uuid: "", salt: "").hash, "cd372fb85148700fa88095e3492d3f9f5beb43e555e5ff26d95f5a6adc36f8e6")
    }

    func testExplicitHashIncludingEmptyStringWins() throws {
        for hash in ["", "backend-hash"] {
            let visitor = CTVisitor(uuid: "id", hash: hash, salt: "ignored")
            XCTAssertEqual(visitor.hash, hash)
            XCTAssertEqual(try json(visitor)["hash"] as? String, hash)
        }
    }

    func testJSONPreservesNestedCustomPropertiesAndEscaping() throws {
        let visitor = CTVisitor(firstName: "quote\"\nline", uuid: "id", customProperties: [
            "nested": ["items": [1, true, NSNull(), "текст"]], "a.b": "value", "@count": 7
        ], salt: "salt")
        let object = try json(visitor)
        XCTAssertEqual(object["first_name"] as? String, "quote\"\nline")
        XCTAssertEqual(object["a.b"] as? String, "value")
        XCTAssertEqual(object["@count"] as? Int, 7)
        let nested = try XCTUnwrap(object["nested"] as? [String: Any])
        let items = try XCTUnwrap(nested["items"] as? [Any])
        XCTAssertEqual(items.count, 4)
        XCTAssertTrue(items[2] is NSNull)
        XCTAssertEqual(items[3] as? String, "текст")
    }

    func testInvalidCustomPropertiesAreDiscardedAsAWhole() throws {
        for invalid in [Date(), Data([1]), Double.nan, Double.infinity, NSObject()] as [Any] {
            let visitor = CTVisitor(uuid: "id", hash: "hash", customProperties: ["valid": true, "nested": [invalid]], salt: "salt")
            let object = try json(visitor)
            XCTAssertEqual(Set(object.keys), ["uuid", "hash"])
            XCTAssertEqual(object["uuid"] as? String, "id")
        }
    }

    func testCustomPropertiesOverrideStandardFieldsOnlyInJSON() throws {
        let keys = ["uuid", "hash", "first_name", "last_name", "email", "phone", "contract", "birthday"]
        var custom = Dictionary(uniqueKeysWithValues: keys.map { ($0, "override") })
        custom["extra"] = "kept"
        let visitor = CTVisitor(firstName: "first", uuid: "id", hash: "hash", customProperties: custom, salt: "salt")
        let object = try json(visitor)
        for key in keys { XCTAssertEqual(object[key] as? String, "override") }
        XCTAssertEqual(object["extra"] as? String, "kept")
        XCTAssertEqual(visitor.uuid, "id")
        XCTAssertEqual(visitor.hash, "hash")
    }
}
