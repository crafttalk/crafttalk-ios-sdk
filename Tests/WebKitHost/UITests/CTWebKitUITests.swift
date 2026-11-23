import XCTest
import UIKit

final class CTWebKitUITests: XCTestCase {
    private let app = XCUIApplication()
    private var ports: [String: Int] = [:]
    private var identifier = ""
    private var session: URLSession!
    private var pageID = ""
    private var pageRequestCount = 0
    private var draftBeforeAction = "unsent draft"

    override func setUpWithError() throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "config", withExtension: "json", subdirectory: "Runtime"))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        ports = try XCTUnwrap(config["ports"] as? [String: Int])
        identifier = try XCTUnwrap(config["uiCase"] as? String)
        session = URLSession(configuration: .ephemeral)
        _ = try control(["reset": true])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    override func tearDown() {
        if let failure = testRun, failure.failureCount > 0, app.state == .runningForeground {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
            print("Состояние при ошибке:", (try? state()) ?? [:])
            print(app.debugDescription)
        }
        app.terminate()
        session.invalidateAndCancel()
    }

    func testPublicConfigurationVisitorInputPushAndClose() throws {
        try prepare(links: "")
        app.launchArguments.append("with-push-token")
        app.launch()
        try open()
        try waitState { ($0["page"] as? [String: Any])?["autocorrect"] as? String == "on" }
        let page = try XCTUnwrap(try state()["page"] as? [String: Any])
        let visitor = try XCTUnwrap(page["visitor"] as? [String: Any])
        XCTAssertEqual(visitor["uuid"] as? String, "ui-visitor")
        XCTAssertEqual(visitor["hash"] as? String, "ui-hash")
        XCTAssertEqual(visitor["first_name"] as? String, "Тест")
        XCTAssertEqual(visitor["nested"] as? [String: Int], ["value": 7])
        XCTAssertEqual(page["accept"] as? String, "image/jpg,image/jpeg,image/gif,image/img,.doc,.docx,.pdf,.txt")
        let records = try control(["wait": "webchat/channel/set-user-subscription"])
        let pushes = records.filter { $0["route"] as? String == "webchat/channel/set-user-subscription" }
        XCTAssertEqual(pushes.count, 1)
        XCTAssertEqual(pushes.first?["method"] as? String, "POST")
        let body = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(pushes.first?["body"] as? String)))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["subscription": "synthetic-ui-token", "uuid": "ui-visitor"])
        app.buttons["Close Chat"].tap()
        XCTAssertTrue(app.buttons["Open secure"].waitForExistence(timeout: 5))
    }

    func testPublicLegacyConfigurationPassesExplicitVisitorHashToPage() throws {
        try prepare(links: "")
        app.launch()
        try open(legacy: true)
        let page = try freshPage()
        let visitor = try XCTUnwrap(page["visitor"] as? [String: Any])
        XCTAssertEqual(visitor["uuid"] as? String, "ui-visitor")
        XCTAssertEqual(visitor["hash"] as? String, "ui-hash")
        XCTAssertEqual(visitor["first_name"] as? String, "Тест")
        XCTAssertEqual(try records("webchat/channel").count, 1)
        XCTAssertEqual(try state()["errors"] as? [String], [])
    }

    func testRepeatedSecureOpenAndCloseLoadsChatEachTime() throws {
        try assertRepeatedOpenAndClose(legacy: false)
    }

    func testRepeatedLegacyOpenAndCloseLoadsChatEachTime() throws {
        try assertRepeatedOpenAndClose(legacy: true)
    }

    private func assertRepeatedOpenAndClose(legacy: Bool) throws {
        try prepare(links: "")
        app.launch()
        for _ in 0..<3 {
            try open(legacy: legacy)
            try waitState { $0["chatOnTop"] as? Bool == true && $0["webViewInWindow"] as? Bool == true }
            app.buttons["Close Chat"].tap()
            XCTAssertTrue(app.buttons["Open secure"].waitForExistence(timeout: 5))
            try waitState { $0["chatOnTop"] as? Bool == false && $0["webViewInWindow"] as? Bool == false }
        }
        XCTAssertEqual(try records("webchat/channel").count, 3)
    }

    func testCancelledInteractiveBackPreservesActiveDownload() throws {
        let contents = String(repeating: "interactive-download|", count: 4096)
        var file = attachment()
        file["body"] = Data(contents.utf8).base64EncodedString()
        file["holdAfterHeaders"] = true
        file["oneUse"] = true
        try prepare(links: link("Download", route: "held"), routes: ["held": file])
        app.launchArguments.append("interactive-back")
        app.launch()
        try open()
        try tapLink("Download")
        defer { _ = try? control(["release": "held"]) }
        try waitState { ($0["directories"] as? [String])?.count == 1 }
        let directories = try XCTUnwrap(try state()["directories"] as? [String])
        try cancelInteractiveBack()
        XCTAssertEqual(try state()["directories"] as? [String], directories)
        XCTAssertEqual(try state()["presented"] as? String, "")
        _ = try control(["release": "held"])
        try closeShare(expected: contents)
        try assertDraftAndNoFiles()
        XCTAssertEqual(try records("held").count, 1)
        XCTAssertEqual(try records("webchat/channel").count, 1)
        XCTAssertEqual(try state()["errors"] as? [String], [])
    }

    private func cancelInteractiveBack() throws {
        let before = try state()
        let starts = try XCTUnwrap(before["interactiveStarts"] as? Int)
        let cancellations = try XCTUnwrap(before["interactiveCancellations"] as? Int)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        try waitState { ($0["interactiveStarts"] as? Int ?? 0) > starts && ($0["interactiveCancellations"] as? Int ?? 0) > cancellations && $0["chatOnTop"] as? Bool == true }
        XCTAssertEqual(try state()["webViewInWindow"] as? Bool, true)
    }

    func testDocumentPickerUploadsSelectedFileWithoutReloadingChat() throws {
        try prepare(links: "<button onclick=\"document.getElementById('webchat-file-input').click()\">Attach document</button>", script: """
            document.getElementById('webchat-file-input').onchange = async function() {
              const file = this.files[0];
              const result = await fetch('\(url("upload"))', {method:'POST', body:file, headers:{'X-File-Name':file.name}});
              if (result.ok) document.getElementById('marker').textContent = 'Uploaded ' + file.name;
            };
            """, routes: ["upload": response("ok", mime: "text/plain")])
        app.launchArguments.append("seed-upload-file")
        app.launch()
        try open()
        app.webViews.buttons["Attach document"].tap()
        let choose = app.buttons["Choose File"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5), app.debugDescription)
        choose.tap()
        try waitState { $0["presented"] as? String == "UIDocumentPickerViewController" }
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS 'sdk-upload'")).firstMatch
        let browse = app.buttons["Browse"].firstMatch
        let local = app.cells.matching(NSPredicate(format: "label BEGINSWITH 'On My'")).firstMatch
        // Выбираем только появившееся состояние: публикация Browse может запаздывать.
        let initial = waitForFirstElement([file, local, browse])
        if initial == 2 {
            waitUntilHittable(browse)
            browse.tap()
        }
        if initial != 0 && waitForFirstElement([file, local]) == 1 {
            local.tap()
            let folder = app.cells.matching(NSPredicate(format: "label CONTAINS 'CraftTalk UI Host'")).firstMatch
            XCTAssertTrue(folder.waitForExistence(timeout: 30), app.debugDescription)
            folder.tap()
        }
        XCTAssertTrue(file.waitForExistence(timeout: 30), app.debugDescription)
        file.tap()
        try waitState { ($0["page"] as? [String: Any])?["marker"] as? String == "Uploaded sdk-upload.txt" }
        let uploads = try records("upload")
        XCTAssertEqual(uploads.count, 1)
        XCTAssertEqual(uploads.first?["method"] as? String, "POST")
        XCTAssertEqual(Data(base64Encoded: uploads.first?["body"] as? String ?? ""), Data("synthetic-picker-upload".utf8))
        XCTAssertEqual(try records("webchat/channel").count, 1)
        try assertDraftAndNoFiles()
        XCTAssertEqual(try state()["errors"] as? [String], [])
    }

    func testRotationPreservesDraftAndDownloadMenu() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        try prepare(links: "<button onclick=\"document.getElementById('draft').blur()\">Done editing</button>" + link("Download", route: "file"),
                    routes: ["file": attachment()])
        app.launch()
        try open()
        let draft = app.webViews.textFields["Draft"]
        draft.tap()
        draft.typeText("-rotation-check")
        let edited = try XCTUnwrap(draft.value as? String)
        XCTAssertTrue(edited.contains("-rotation-check"))
        app.webViews.buttons["Done editing"].tap()
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            try waitState {
                guard let width = $0["viewWidth"] as? Double, let height = $0["viewHeight"] as? Double else { return false }
                return width > 0 && height > 0 && (orientation == .portrait ? height > width : width > height)
            }
            XCTAssertTrue(draft.isHittable)
            XCTAssertTrue(app.webViews.links["Download"].isHittable)
            try assertDraftAndNoFiles(expectedDraft: edited)
            try tapLink("Download")
            try closeShare()
            try assertDraftAndNoFiles(expectedDraft: edited)
        }
        XCTAssertEqual(try records("webchat/channel").count, 1)
        XCTAssertEqual(try records("file").count, 2)
        XCTAssertEqual(try state()["errors"] as? [String], [])
    }

    func testSecureChatSurvivesBackgroundAndDownloadsAfterReturn() throws {
        try assertChatSurvivesBackground(legacy: false)
    }

    func testLegacyChatSurvivesBackgroundAndOpensBlobPreviewAfterReturn() throws {
        try assertChatSurvivesBackground(legacy: true)
    }

    private func assertChatSurvivesBackground(legacy: Bool) throws {
        let downloads = [("First download", "first-resume-file"), ("Second download", "second-resume-file")]
        var routes: [String: [String: Any]] = [:]
        var links = "<button onclick=\"document.getElementById('draft').blur()\">Done editing</button>"
        var script = ""
        for (index, download) in downloads.enumerated() {
            let route = "resume-\(index)"
            if legacy {
                links += "<a id='\(route)' style='display:block;margin:20px 0'>\(download.0)</a>"
                script += "document.getElementById('\(route)').href=URL.createObjectURL(new Blob(['\(download.1)'],{type:'text/plain'}));"
            } else {
                links += link(download.0, route: route)
                var file = attachment()
                file["body"] = Data(download.1.utf8).base64EncodedString()
                file["oneUse"] = true
                routes[route] = file
            }
        }
        try prepare(links: links, script: script, routes: routes)
        if legacy { app.launchArguments.append("label-preview-buttons") }
        app.launch()
        try open(legacy: legacy)
        let draft = app.webViews.textFields["Draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap()
        draft.typeText("-background-check")
        let edited = try XCTUnwrap(draft.value as? String)
        XCTAssertTrue(edited.contains("-background-check"))
        XCTAssertNotEqual(edited, "unsent draft")
        app.webViews.buttons["Done editing"].tap()
        try waitState { ($0["page"] as? [String: Any])?["draft"] as? String == edited }

        for (index, download) in downloads.enumerated() {
            try backgroundAndReturn()
            try waitState { $0["chatOnTop"] as? Bool == true && $0["webViewInWindow"] as? Bool == true }
            try assertDraftAndNoFiles(expectedDraft: edited)
            XCTAssertTrue(draft.isHittable)
            XCTAssertEqual((try state()["page"] as? [String: Any])?["url"] as? String, url("webchat/channel"))
            if legacy {
                _ = try openBlobPreview(download.0, contents: download.1)
                app.buttons["BlobPreviewBack"].tap()
                try assertBlobPreviewClosed(expectedDraft: edited)
            } else {
                try tapLink(download.0)
                try closeShare(expected: download.1)
                try assertDraftAndNoFiles(expectedDraft: edited)
                let requests = try records("resume-\(index)")
                XCTAssertEqual(requests.count, 1)
                XCTAssertEqual(requests.first?["method"] as? String, "GET")
                XCTAssertTrue((requests.first?["headers"] as? [String: String])?["cookie"]?.contains("session=synthetic-webview") == true)
            }
        }
        XCTAssertEqual(try records("webchat/channel").count, 1)
        XCTAssertEqual(try state()["errors"] as? [String], [])
        app.buttons["Close Chat"].tap()
        XCTAssertTrue(app.buttons["Open secure"].waitForExistence(timeout: 5))
    }

    func testLegacyPreviewSurvivesBackgroundAndCanShareAfterReturn() throws {
        try prepareBlobPreview()
        let file = try openBlobPreview("First preview", contents: "first-preview-content")
        try backgroundAndReturn()
        XCTAssertEqual(try previewFiles()[file], Data("first-preview-content".utf8))
        XCTAssertTrue(app.webViews.staticTexts["first-preview-content"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["BlobPreviewShare"].tap()
        try waitState { $0["presented"] as? String == "UIActivityViewController" }
        try dismissShare()
        XCTAssertEqual(try previewFiles()[file], Data("first-preview-content".utf8))
        app.buttons["BlobPreviewBack"].tap()
        try assertBlobPreviewClosed()
        XCTAssertEqual(try records("webchat/channel").count, 1)
        XCTAssertEqual(try state()["errors"] as? [String], [])
    }

    private func backgroundAndReturn() throws {
        let before = try state()
        let backgrounds = try XCTUnwrap(before["backgroundCount"] as? Int)
        let activations = try XCTUnwrap(before["activationCount"] as? Int)
        XCUIDevice.shared.press(.home)
        let background = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let state = self?.app.state else { return false }
            return state == .runningBackground || state == .runningBackgroundSuspended
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [background], timeout: 10), .completed)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        // Проверяем настоящие callbacks приложения, а не только старый снимок страницы.
        try waitState { ($0["backgroundCount"] as? Int ?? 0) > backgrounds && ($0["activationCount"] as? Int ?? 0) > activations }
    }

    func testAllowedNavigationAndNewWindowStayInChat() throws {
        for target in ["_self", "_blank"] {
            try prepare(links: link("Navigate", route: "next", target: target), routes: ["next": response("<div id='marker'>Next page</div>")])
            app.launch()
            try open()
            try tapLink("Navigate")
            try waitState { ($0["page"] as? [String: Any])?["marker"] as? String == "Next page" }
            XCTAssertEqual(try state()["presented"] as? String, "")
            XCTAssertEqual(try records("next").count, 1)
            app.terminate()
            _ = try control(["reset": true])
        }
    }

    func testRealExternalLinkOpensSafariAndPreservesChat() throws {
        let external = url("external", profile: "system", host: "127.0.0.1")
        try prepare(links: "<a href='\(external)'>External</a>", routes: ["external": response("External page")])
        app.launch()
        try open(editDraft: true)
        try tapLink("External")
        try closeSafari()
        try assertDraftAndNoFiles()
        XCTAssertEqual(try records("external").count, 1)
    }

    func testAllowedClickCannotAuthorizeRedirectToExternalHost() throws {
        try prepare(links: link("Redirect", route: "redirect"), routes: [
            "redirect": response("", status: 302, headers: ["Location": url("blocked", profile: "system", host: "127.0.0.1")]),
            "blocked": response("Must not load")])
        app.launch()
        try open()
        try tapLink("Redirect")
        try waitForError()
        XCTAssertEqual(try records("redirect").count, 1)
        XCTAssertEqual(try records("blocked").count, 0)
        XCTAssertEqual(try state()["presented"] as? String, "")
    }

    func testAutomaticExternalNavigationDoesNotOpenSafari() throws {
        try prepare(links: "", script: "location.href='\(url("blocked", profile: "system", host: "127.0.0.1"))';", routes: ["blocked": response("Must not load")])
        app.launch()
        try open()
        try waitForError()
        XCTAssertEqual(try records("blocked").count, 0)
        XCTAssertEqual(try state()["presented"] as? String, "")
    }

    func testOpenAndClosedShadowDOMRecognizeRealExternalClicks() throws {
        for mode in ["open", "closed"] {
            let external = url("external", profile: "system", host: "127.0.0.1")
            try prepare(links: "<div id='shadow'></div>", script: "document.getElementById('shadow').attachShadow({mode:'\(mode)'}).innerHTML='<a href=\"\(external)\">Shadow link</a>';",
                        routes: ["external": response("External page")])
            app.launch()
            try open()
            try tapLink("Shadow link")
            try closeSafari()
            try assertDraftAndNoFiles()
            app.terminate()
            _ = try control(["reset": true])
        }
    }

    func testTelephoneAndMailLinksAreHandedOffWithoutReplacingChat() throws {
        try prepare(links: "<a href='tel:15555550100'>Telephone</a><a href='mailto:synthetic@example.invalid'>Email</a>")
        app.launch()
        try open(editDraft: true)
        XCTAssertEqual(try state()["openedSchemes"] as? [String], [])
        try tapLink("Telephone")
        try tapLink("Email")
        try waitState { $0["openedSchemes"] as? [String] == ["tel", "mailto"] }
        try assertDraftAndNoFiles()
    }

    func testDownloadAttributeMIMEAndDispositionPreservePageAndOneUseGET() throws {
        for (route, attribute, mime, disposition) in [("attribute", " download", "text/html", ""),
                                                    ("report.pdf", "", "application/pdf", ""),
                                                    ("webchat/channel/file/opaque", "", "text/html", "attachment; filename=report.bin")] {
            var spec = response("synthetic-file", mime: mime, headers: disposition.isEmpty ? [:] : ["Content-Disposition": disposition])
            spec["oneUse"] = true
            try prepare(links: "<a href='\(url(route))'\(attribute)>Download</a>", routes: [route: spec])
            app.launch()
            try open(editDraft: true)
            try tapLink("Download")
            try closeShare()
            try assertDraftAndNoFiles()
            let requests = try records(route)
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?["method"] as? String, "GET")
            XCTAssertTrue((requests.first?["headers"] as? [String: String])?["cookie"]?.contains("session=synthetic-webview") == true)
            app.terminate()
            _ = try control(["reset": true])
        }
    }

    func testPOSTDownloadPreservesBodyWithoutReplay() throws {
        var spec = response("post-file", mime: "application/octet-stream", headers: ["Content-Disposition": "attachment; filename=post.bin"])
        spec["oneUse"] = true
        try prepare(links: "<form method='POST' action='\(url("post"))'><input type='hidden' name='ticket' value='one-use'><button type='submit'>Submit file</button></form>", routes: ["post": spec])
        app.launch()
        try open(editDraft: true)
        app.webViews.buttons["Submit file"].tap()
        try closeShare(expected: "post-file")
        try assertDraftAndNoFiles()
        let requests = try records("post")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?["method"] as? String, "POST")
        XCTAssertEqual(Data(base64Encoded: requests.first?["body"] as? String ?? ""), Data("ticket=one-use".utf8))
    }

    func testPOSTRedirectDownloadPreservesBodyAndCookiesWithoutReplay() throws {
        var spec = attachment()
        spec["oneUse"] = true
        try prepare(links: "<form method='POST' action='\(url("redirect"))'><input type='hidden' name='ticket' value='one-use'><button type='submit'>Submit file</button></form>", routes: [
            "redirect": response("", status: 307, headers: ["Location": url("file")]), "file": spec])
        app.launch()
        try open(editDraft: true)
        app.webViews.buttons["Submit file"].tap()
        try closeShare()
        try assertDraftAndNoFiles()
        for route in ["redirect", "file"] {
            let requests = try records(route)
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?["method"] as? String, "POST")
            XCTAssertEqual(Data(base64Encoded: requests.first?["body"] as? String ?? ""), Data("ticket=one-use".utf8))
            XCTAssertTrue((requests.first?["headers"] as? [String: String])?["cookie"]?.contains("session=synthetic-webview") == true)
        }
    }

    func testAllowedCrossHostRedirectDownloadsOnce() throws {
        try prepare(links: link("Download", route: "redirect"), routes: [
            "redirect": response("", status: 302, headers: ["Location": url("file", host: "127.0.0.1")]), "file": attachment()])
        app.launchArguments.append("allow-target")
        app.launch()
        try open(editDraft: true)
        try tapLink("Download")
        try closeShare()
        try assertDraftAndNoFiles()
        XCTAssertEqual(try records("redirect").count, 1)
        let requests = try records("file")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?["host"] as? String, "127.0.0.1:\(ports["valid"]!)")
        XCTAssertFalse((requests.first?["headers"] as? [String: String])?["cookie"]?.contains("session=synthetic-webview") == true)
    }

    func testIframeDownloadsKeepMainPage() throws {
        try assertIframeDownload(route: "file")
    }

    func testIframeRedirectDownloadsKeepMainPage() throws {
        try assertIframeDownload(route: "redirect")
    }

    private func assertIframeDownload(route: String) throws {
        for target in ["download-frame", "inside-frame"] {
            var file = attachment()
            file["oneUse"] = true
            try prepare(links: "<iframe name='download-frame' title='Download frame' src='\(url("frame"))'></iframe>" + link("Download", route: route, target: target),
                        routes: ["frame": response(target == "inside-frame" ? link("Frame download", route: route) : "Frame ready"), "file": file,
                                 "redirect": response("", status: 302, headers: ["Location": url("file")])])
            app.launch()
            try open(editDraft: true)
            try tapLink(target == "inside-frame" ? "Frame download" : "Download")
            try closeShare()
            try assertDraftAndNoFiles()
            let requests = try control([:]).filter { ["redirect", "file"].contains($0["route"] as? String ?? "") }
            XCTAssertEqual(requests.compactMap { $0["route"] as? String }, route == "redirect" ? ["redirect", "file"] : ["file"])
            XCTAssertTrue(requests.allSatisfy { $0["method"] as? String == "GET" })
            XCTAssertTrue(requests.allSatisfy { ($0["headers"] as? [String: String])?["cookie"]?.contains("session=synthetic-webview") == true })
            XCTAssertEqual(try records("webchat/channel").count, 1)
            XCTAssertEqual((try state()["page"] as? [String: Any])?["url"] as? String, url("webchat/channel"))
            app.terminate()
            _ = try control(["reset": true])
        }
    }

    func testRelaunchIsolatesFilesAndWebsiteDataAfterInterruptedScenario() throws {
        let seed = """
            <button onclick="localStorage.setItem('previous-case','stale');document.cookie='previous-case=stale;path=/';
              document.getElementById('marker').textContent='State seeded'">Seed storage</button>
            """
        try prepare(links: link("Leave attachment open", route: "interrupted") + seed, script: """
            if (localStorage.getItem('previous-case') || document.cookie.includes('previous-case=')) {
              document.getElementById('marker').textContent='State leaked from previous launch';
            }
            """, routes: ["interrupted": attachment()])
        app.launch()
        try open()
        let previousLaunch = try XCTUnwrap(try state()["launchID"] as? String)
        app.webViews.buttons["Seed storage"].tap()
        try waitState { ($0["page"] as? [String: Any])?["marker"] as? String == "State seeded" }
        try tapLink("Leave attachment open")
        try waitState { ($0["files"] as? [[String: Any]])?.count == 1 && $0["presented"] as? String == "UIActivityViewController" }
        // Намеренно обрываем сценарий без dismiss и уборки: проверяем изоляцию, не cleanup SDK.
        app.terminate()
        app.launch()
        try waitState { ($0["launchID"] as? String).map { $0 != previousLaunch } == true }
        XCTAssertEqual(try state()["resetDirectoryCount"] as? Int, 1)
        XCTAssertEqual(try state()["directories"] as? [String], [])
        XCTAssertTrue((try state()["files"] as? [[String: Any]])?.isEmpty == true)
        try open()
        try assertDraftAndNoFiles()
    }

    func testJavaScriptObservationFailureClearsCachedPageAndRecovers() throws {
        try prepare(links: """
            <button onclick="window.savedPageID=window.testPageID;
              Object.defineProperty(window,'testPageID',{configurable:true,get(){throw new Error('synthetic observation failure')}})">Break observation</button>
            <button onclick="Object.defineProperty(window,'testPageID',{configurable:true,writable:true,value:window.savedPageID})">Restore observation</button>
            """)
        app.launch()
        try open(editDraft: true)
        XCTAssertEqual(try freshPage()["pageID"] as? String, pageID)
        app.webViews.buttons["Break observation"].tap()
        try waitState { $0["pageObservationError"] as? String == "evaluateJavaScript: WKErrorDomain code=4" }
        let failed = try state()
        XCTAssertTrue(try XCTUnwrap(failed["page"] as? [String: Any]).isEmpty, "Ошибочное чтение сохранило прежний снимок")
        app.webViews.buttons["Restore observation"].tap()
        try assertDraftAndNoFiles()
        XCTAssertEqual(try state()["errors"] as? [String], [])
    }

    func testUnreadableAttachmentIsReportedByObserver() throws {
        app.launchArguments.append("seed-unreadable-attachment")
        app.launch()
        // Ошибка стенда ожидается только здесь; обычный state() превращает её в XCTest failure.
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let state = try? self?.state(validateObservation: false) else { return false }
            return (state["observationErrors"] as? [String])?.contains { $0.contains("read unreadable.bin:") } == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 10), .completed)
        let snapshot = try state(validateObservation: false)
        XCTAssertEqual((snapshot["directories"] as? [String])?.count, 1)
        XCTAssertEqual((snapshot["observationErrors"] as? [String])?.count, 1)
    }

    func testDownloadTLSHTTPAndRedirectFailuresAllowRetry() throws {
        for (route, profile, spec) in [("tls", "wrong-host", attachment()), ("http", "valid", attachment(status: 500)),
                                       ("redirect", "valid", response("", status: 302, headers: ["Location": url("blocked", host: "127.0.0.1")])),
                                       ("downgrade", "valid", response("", status: 302, headers: ["Location": url("blocked", profile: "http")]))] {
            try prepare(links: "<a href='\(url(route, profile: profile))' download>Failure</a>" + link("Retry", route: "retry"),
                        routes: [route: spec, "retry": attachment(), "blocked": attachment()])
            app.launch()
            try open(editDraft: true)
            try tapLink("Failure")
            try waitForError()
            try assertDraftAndNoFiles()
            try tapLink("Retry")
            try closeShare()
            try assertDraftAndNoFiles()
            let errors = try XCTUnwrap(try state()["errors"] as? [String])
            if profile == "wrong-host" {
                XCTAssertEqual(try records(route).count, 0)
                XCTAssertTrue(errors.contains { $0.contains("stage=tls") })
            }
            if route == "http" { XCTAssertTrue(errors.contains { $0.contains("stage=download") && $0.contains("domain=HTTP code=500") }) }
            if route == "redirect" || route == "downgrade" { XCTAssertEqual(try records("blocked").count, 0) }
            app.terminate()
            _ = try control(["reset": true])
        }
    }

    private func open(legacy: Bool = false, editDraft: Bool = false) throws {
        let previousPageID = pageID
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let openButton = app.buttons[legacy ? "Open legacy" : "Open secure"]
        waitUntilHittable(openButton)
        openButton.tap()
        try waitState(timeout: 30) {
            guard let page = $0["page"] as? [String: Any], let identifier = page["pageID"] as? String else { return false }
            return page["marker"] as? String == "Chat ready" && !identifier.isEmpty && identifier != previousPageID
        }
        pageID = try XCTUnwrap((try state()["page"] as? [String: Any])?["pageID"] as? String)
        pageRequestCount = try records("webchat/channel").count
        draftBeforeAction = "unsent draft"
        // Готовность DOM не означает, что WebKit уже опубликовал accessibility-дерево.
        waitUntilHittable(app.webViews.textFields["Draft"])
        if editDraft {
            let draft = app.webViews.textFields["Draft"]
            draft.tap()
            // Короткий маркер проверяет реальный ввод без длинной последовательности клавиш в CI.
            draft.typeText("-edited")
            waitForValue(draft) { $0.contains("-edited") }
            draftBeforeAction = try XCTUnwrap(draft.value as? String)
            XCTAssertTrue(draftBeforeAction.contains("-edited"))
            app.webViews.buttons["Finish draft"].tap()
            try waitState { ($0["page"] as? [String: Any])?["draft"] as? String == self.draftBeforeAction }
        }
    }

    func testConcurrentWKDownloadIsRejectedAndCanRetryAfterFirstCompletes() throws {
        let firstContents = String(repeating: "first-download-content|", count: 4096)
        let secondContents = "second-download-content"
        var first = attachment()
        first["body"] = Data(firstContents.utf8).base64EncodedString()
        first["holdAfterHeaders"] = true
        first["oneUse"] = true
        let links = link("First download", route: "first") + link("Second download", route: "second")
        // Повтор — отдельное нажатие; без кеша журнал различает обе попытки.
        let second = response(secondContents, mime: "application/octet-stream",
                              headers: ["Content-Disposition": "attachment; filename=second.bin", "Cache-Control": "no-store"])
        try prepare(links: links, routes: ["first": first, "second": second])
        app.launch()
        try open()
        try tapLink("First download")
        defer { _ = try? control(["release": "first"]) }
        try waitState { ($0["directories"] as? [String])?.count == 1 && $0["presented"] as? String == "" }
        let originalDirectories = try XCTUnwrap(try state()["directories"] as? [String])
        XCTAssertEqual(try state()["errors"] as? [String], [])

        try tapLink("Second download")
        try waitState { ($0["errors"] as? [String])?.contains { $0.contains("stage=download") && $0.contains("domain=CTChat code=6") } == true }
        let errors = try XCTUnwrap(try state()["errors"] as? [String])
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(try XCTUnwrap(errors.first).contains("host=localhost"))
        XCTAssertEqual(try state()["directories"] as? [String], originalDirectories)
        XCTAssertEqual(try state()["presented"] as? String, "")
        XCTAssertEqual((try state()["page"] as? [String: Any])?["draft"] as? String, "unsent draft")
        XCTAssertEqual(try records("second").count, 1)

        _ = try control(["release": "first"])
        try closeShare(expected: firstContents)
        try assertDraftAndNoFiles()
        try waitState { ($0["directories"] as? [String])?.isEmpty == true }
        try tapLink("Second download")
        try closeShare(expected: secondContents)
        try assertDraftAndNoFiles()
        try waitState { ($0["directories"] as? [String])?.isEmpty == true }
        XCTAssertEqual(try state()["errors"] as? [String], errors)
        XCTAssertEqual(try records("webchat/channel").count, 1)
        XCTAssertEqual((try state()["page"] as? [String: Any])?["url"] as? String, url("webchat/channel"))
        for (route, count) in [("first", 1), ("second", 2)] {
            let requests = try records(route)
            XCTAssertEqual(requests.count, count, route)
            XCTAssertTrue(requests.allSatisfy { $0["method"] as? String == "GET" })
            XCTAssertTrue(requests.allSatisfy { ($0["headers"] as? [String: String])?["cookie"]?.contains("session=synthetic-webview") == true })
        }
    }

    func testUnavailablePresentationRemovesCompletedDownload() throws {
        var spec = attachment()
        spec["holdAfterHeaders"] = true
        spec["body"] = Data(repeating: 65, count: 65536).base64EncodedString()
        try prepare(links: link("Download", route: "held"), routes: ["held": spec])
        app.launch()
        try open()
        try tapLink("Download")
        try waitState { ($0["directories"] as? [String])?.count == 1 }
        app.buttons["Block UI"].tap()
        XCTAssertTrue(app.alerts["Another presentation"].waitForExistence(timeout: 5))
        _ = try control(["release": "held"])
        try waitState { ($0["directories"] as? [String])?.isEmpty == true && $0["presented"] as? String == "UIAlertController" }
        app.buttons["Dismiss blocker"].tap()
        try assertDraftAndNoFiles()
    }

    func testTruncatedWKDownloadCleansUpAndAllowsRetry() throws {
        var broken = attachment()
        broken["truncate"] = true
        broken["holdAfterHeaders"] = true
        broken["body"] = Data(repeating: 65, count: 65536).base64EncodedString()
        try prepare(links: "<a href='\(url("broken"))' download>Broken</a>" + link("Retry", route: "retry"), routes: ["broken": broken, "retry": attachment()])
        app.launch()
        try open(editDraft: true)
        try tapLink("Broken")
        try waitState { ($0["directories"] as? [String])?.count == 1 }
        _ = try control(["release": "broken"])
        try waitForError()
        try assertDraftAndNoFiles()
        try tapLink("Retry")
        try closeShare()
        try assertDraftAndNoFiles()
    }

    func testLegacyPreviewBackReturnsToEditedDraftAndAllowsAnotherPreview() throws {
        try prepareBlobPreview()
        for (title, contents) in [("First preview", "first-preview-content"), ("Second preview", "second-preview-content")] {
            _ = try openBlobPreview(title, contents: contents)
            app.buttons["BlobPreviewBack"].tap()
            try assertBlobPreviewClosed()
        }
        XCTAssertEqual(try records("webchat/channel").count, 1)
        XCTAssertEqual(try state()["errors"] as? [String], [])
    }

    func testLegacyPreviewShareCanRepeatWithoutDeletingPreviewFile() throws {
        try prepareBlobPreview()
        let file = try openBlobPreview("First preview", contents: "first-preview-content")
        for _ in 0..<2 {
            app.buttons["BlobPreviewShare"].tap()
            try waitState { $0["presented"] as? String == "UIActivityViewController" }
            try dismissShare()
            XCTAssertEqual(try previewFiles()[file], Data("first-preview-content".utf8))
            XCTAssertTrue(app.webViews.staticTexts["first-preview-content"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["BlobPreviewShare"].isHittable)
        }
        app.buttons["BlobPreviewBack"].tap()
        try assertBlobPreviewClosed()
        XCTAssertEqual(try records("webchat/channel").count, 1)
        XCTAssertEqual(try state()["errors"] as? [String], [])
    }

    func testSecureBlobOpensPreviewAndBackReturnsToEditedDraft() throws {
        try prepareBlobPreview(legacy: false)
        _ = try openBlobPreview("First preview", contents: "first-preview-content")
        app.buttons["BlobPreviewBack"].tap()
        try assertBlobPreviewClosed()
        XCTAssertEqual(try records("webchat/channel").count, 1)
        XCTAssertEqual(try state()["errors"] as? [String], [])
    }

    private func prepareBlobPreview(legacy: Bool = true) throws {
        try prepare(links: "<a id='first'>First preview</a><br><a id='second'>Second preview</a>", script: """
            document.getElementById('first').href=URL.createObjectURL(new Blob(['first-preview-content'],{type:'text/plain'}));
            document.getElementById('second').href=URL.createObjectURL(new Blob(['second-preview-content'],{type:'text/plain'}));
            """)
        app.launchArguments.append("label-preview-buttons")
        app.launch()
        try open(legacy: legacy, editDraft: true)
    }

    private func openBlobPreview(_ title: String, contents: String) throws -> String {
        let before = Set(try previewFiles().keys)
        try tapLink(title)
        try waitState { ($0["previewFiles"] as? [[String: Any]])?.contains {
            guard let name = $0["name"] as? String else { return false }
            return !before.contains(name)
        } == true }
        XCTAssertTrue(app.webViews.staticTexts[contents].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["BlobPreviewBack"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["BlobPreviewBack"].isHittable)
        XCTAssertTrue(app.buttons["BlobPreviewShare"].isHittable)
        let added = try previewFiles().filter { !before.contains($0.key) }
        XCTAssertEqual(added.count, 1)
        let file = try XCTUnwrap(added.first)
        XCTAssertEqual((file.key as NSString).pathExtension, "txt")
        XCTAssertEqual(file.value, Data(contents.utf8))
        return file.key
    }

    private func previewFiles() throws -> [String: Data] {
        let files = try XCTUnwrap(try state()["previewFiles"] as? [[String: String]])
        let entries = try files.map {
            (try XCTUnwrap($0["name"]), try XCTUnwrap($0["body"].flatMap { Data(base64Encoded: $0) }))
        }
        return Dictionary(uniqueKeysWithValues: entries)
    }

    private func assertBlobPreviewClosed(expectedDraft: String? = nil) throws {
        XCTAssertFalse(app.buttons["BlobPreviewBack"].exists)
        XCTAssertFalse(app.buttons["BlobPreviewShare"].exists)
        try assertDraftPreserved(expectedDraft: expectedDraft)
        XCTAssertEqual((try freshPage())["url"] as? String, url("webchat/channel"))
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 30) {
        // Не ждём первого тика predicate, если элемент уже готов.
        if element.exists && element.isHittable { return }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed,
                       "Элемент недоступен для нажатия: \(element)")
    }

    private func waitForFirstElement(_ elements: [XCUIElement]) -> Int {
        if let index = elements.firstIndex(where: { $0.exists }) { return index }
        var found: Int?
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            found = elements.firstIndex(where: { $0.exists })
            return found != nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed,
                       "Не появилось ни одно ожидаемое состояние системного экрана")
        return found ?? -1
    }

    private func waitForValue(_ element: XCUIElement, matching condition: @escaping (String) -> Bool) {
        if let value = element.value as? String, condition(value) { return }
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = element.value as? String else { return false }
            return condition(value)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 10), .completed,
                       "Accessibility не подтвердил завершение ввода")
    }

    private func deleteTypedCharacter() {
        let delete = app.keyboards.keys["delete"].firstMatch
        // На свежем симуляторе подсказка Slide to Type может закрыть клавиатуру уже после ввода.
        let introduction = app.otherElements["UIContinuousPathIntroductionView"].buttons["Continue"]
        let available = {
            (delete.exists && delete.isHittable) || (introduction.exists && introduction.isHittable)
        }
        if !available() {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in available() }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed,
                           "Не появилась клавиша Delete или подсказка Slide to Type")
        }
        if introduction.exists && introduction.isHittable {
            introduction.tap()
        }
        waitUntilHittable(delete)
        // Нажимаем один раз: повтор мог бы удалить часть исходного черновика.
        delete.tap()
    }

    func testOffscreenDownloadLinkScrollsIntoView() throws {
        var file = attachment()
        file["oneUse"] = true
        try prepare(links: "<div style='height:2000px'></div>" + link("Offscreen download", route: "file"),
                    routes: ["file": file])
        app.launch()
        try open()
        let download = app.webViews.links["Offscreen download"].firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 30))
        XCTAssertFalse(download.isHittable, "Ссылка должна находиться ниже видимой области")
        try tapLink("Offscreen download")
        try closeShare()
        try waitState {
            ($0["files"] as? [[String: Any]])?.isEmpty == true &&
            ($0["directories"] as? [String])?.isEmpty == true
        }
        let page = try freshPage()
        XCTAssertEqual(page["pageID"] as? String, pageID)
        XCTAssertEqual(page["draft"] as? String, draftBeforeAction)
        XCTAssertEqual(try records("file").count, 1)
        XCTAssertEqual(try records("webchat/channel").count, pageRequestCount)
        XCTAssertEqual(try state()["errors"] as? [String], [])
    }

    private func tapLink(_ title: String) throws {
        let link = app.webViews.links[title].firstMatch
        // tap() сам прокручивает к ссылке; isHittable до прокрутки может оставаться false.
        XCTAssertTrue(link.waitForExistence(timeout: 30), title)
        link.tap()
    }

    private func closeSafari() throws {
        XCTAssertTrue(app.webViews.staticTexts["External page"].firstMatch.waitForExistence(timeout: 30))
        let done = app.buttons["Done"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: done)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        // Xcode 27.2 / iOS 18.6: tap() иногда не доставляет нажатие удалённому Safari-сервису.
        // Вернуть tap() можно после проверки обоих Safari-сценариев на обновлённом окружении.
        done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func closeShare(expected: String = "synthetic-file") throws {
        try waitState {
            $0["presented"] as? String == "UIActivityViewController" &&
            ($0["files"] as? [[String: Any]])?.count == 1
        }
        let files = try XCTUnwrap(try state()["files"] as? [[String: Any]])
        XCTAssertEqual(Data(base64Encoded: files[0]["body"] as? String ?? ""), Data(expected.utf8))
        try dismissShare()
    }

    private func dismissShare() throws {
        let isPad = try state()["idiom"] as? String == "pad"
        // Системное меню использует Close или close в разных сборках iOS/Xcode.
        let close = app.buttons.matching(NSPredicate(format: "identifier == 'header.closeButton' OR label ==[c] 'close'")).firstMatch
        if isPad {
            // У popover нет телефонной кнопки Close; закрываем настоящим нажатием вне меню.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.12)).tap()
            try waitState { $0["presented"] as? String == "" }
        } else {
            // На свежем симуляторе сервис ShareSheet в CI запускался около 26 секунд.
            // Загрузка SDK уже проверена выше; здесь ждём доступности системной кнопки.
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                close.exists && close.isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed,
                           "Системное меню не предоставило доступную кнопку закрытия")
            close.tap()
            try waitState { $0["presented"] as? String == "" }
        }
    }

    private func assertDraftAndNoFiles(expectedDraft: String? = nil) throws {
        try waitState {
            ($0["files"] as? [[String: Any]])?.isEmpty == true &&
            ($0["directories"] as? [String])?.isEmpty == true && $0["presented"] as? String == ""
        }
        try assertDraftPreserved(expectedDraft: expectedDraft)
    }

    private func assertDraftPreserved(expectedDraft: String? = nil) throws {
        let expected = expectedDraft ?? draftBeforeAction
        let draft = app.webViews.textFields["Draft"]
        let accessible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: draft)
        XCTAssertEqual(XCTWaiter.wait(for: [accessible], timeout: 5), .completed, "Чат недоступен после завершения действия")
        XCTAssertEqual(draft.value as? String, expected)
        let page = try freshPage()
        XCTAssertEqual(page["draft"] as? String, expected)
        XCTAssertEqual(page["pageID"] as? String, pageID, "Страница была заменена или перезагружена")

        // Проверяем реальный ввод и возвращаем черновик к исходному значению для следующего действия.
        draft.tap()
        draft.typeText("x")
        waitForValue(draft) { $0 != expected && $0.count == expected.count + 1 }
        let edited = try XCTUnwrap(draft.value as? String)
        XCTAssertNotEqual(edited, expected)
        XCTAssertEqual(edited.count, expected.count + 1)
        deleteTypedCharacter()
        waitForValue(draft) { $0 == expected }
        XCTAssertEqual(draft.value as? String, expected)
        app.webViews.buttons["Finish draft"].tap()
        let restored = try freshPage()
        XCTAssertEqual(restored["draft"] as? String, expected)
        XCTAssertEqual(restored["pageID"] as? String, pageID)
        XCTAssertEqual(try records("webchat/channel").count, pageRequestCount, "Повторная загрузка страницы чата")
    }

    private func freshPage() throws -> [String: Any] {
        // Дожидаемся чтения, начатого после контрольного снимка; уже запущенный JS не подходит.
        let started = try XCTUnwrap(try state()["pageObservationStarted"] as? Int)
        var observed: [String: Any]?
        try waitState {
            guard let completed = $0["pageObservationCompleted"] as? Int, completed > started else { return false }
            observed = $0
            return true
        }
        let snapshot = try XCTUnwrap(observed)
        XCTAssertEqual(snapshot["pageObservationError"] as? String, "", "Ошибка свежего чтения страницы")
        return try XCTUnwrap(snapshot["page"] as? [String: Any])
    }

    private func waitForError() throws {
        try waitState { ($0["errors"] as? [String])?.isEmpty == false }
    }

    private func records(_ route: String) throws -> [[String: Any]] {
        try control([:]).filter { $0["route"] as? String == route }
    }

    private func link(_ title: String, route: String, target: String = "_self") -> String {
        "<a href='\(url(route))' target='\(target)' style='display:block;margin:20px 0'>\(title)</a>"
    }

    private func attachment(status: Int = 200) -> [String: Any] {
        response("synthetic-file", mime: "application/octet-stream", status: status, headers: ["Content-Disposition": "attachment; filename=file.bin"])
    }

    private func url(_ route: String, profile: String = "valid", host: String = "localhost") -> String {
        "\(profile == "http" ? "http" : "https")://\(host):\(ports[profile]!)/case/\(identifier)/\(route)"
    }

    private func response(_ text: String, mime: String = "text/html", status: Int = 200, headers: [String: String] = [:]) -> [String: Any] {
        var headers = headers
        headers["Content-Type"] = mime
        return ["body": Data(text.utf8).base64EncodedString(), "status": status, "headers": headers]
    }

    private func prepare(links: String, script: String = "", routes: [String: [String: Any]] = [:]) throws {
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="font:18px sans-serif"><div id="marker">Chat ready</div>
        <input id="draft" class="webchat-userinput" aria-label="Draft" value="unsent draft">
        <button onclick="document.getElementById('draft').blur()">Finish draft</button>
        <input id="webchat-file-input" type="file" style="display:none">
        \(links)<script>
        window.testPageID = crypto.randomUUID();
        window.addEventListener('load', function(){
          window.testVisitor = window.__WebchatUserCallback();
          document.cookie='session=synthetic-webview;path=/;SameSite=Lax';
          \(script)
        });</script></body></html>
        """
        var all = routes
        all["webchat/channel"] = response(html)
        all["webchat/channel/set-user-subscription"] = response("ok", mime: "text/plain")
        _ = try control(["routes": all])
    }

    private func state(validateObservation: Bool = true) throws -> [String: Any] {
        let snapshot = try XCTUnwrap(control(["state": true]).first)
        if validateObservation, let errors = snapshot["observationErrors"] as? [String] {
            XCTAssertEqual(errors, [], "Ошибка наблюдения стенда; пустой список файлов не доказывает очистку")
        }
        return snapshot
    }

    private func waitState(timeout: TimeInterval = 10, _ condition: @escaping ([String: Any]) -> Bool) throws {
        let predicate = NSPredicate { [weak self] _, _ in
            guard let value = try? self?.state() else { return false }
            return condition(value)
        }
        let done = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: timeout), .completed, "Последнее состояние: \((try? state()) ?? [:])")
    }

    private func control(_ command: [String: Any]) throws -> [[String: Any]] {
        var request = URLRequest(url: URL(string: "https://127.0.0.1:\(ports["system"]!)/control/\(identifier)")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: command)
        let done = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>?
        session.dataTask(with: request) { data, _, error in
            result = error.map { .failure($0) } ?? .success(data ?? Data())
            done.signal()
        }.resume()
        guard done.wait(timeout: .now() + 15) == .success else { throw URLError(.timedOut) }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(result).get()) as? [[String: Any]])
    }
}
