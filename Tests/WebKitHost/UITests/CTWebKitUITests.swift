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
        app.launch()
        app.buttons["Open secure"].tap()
        try waitState { ($0["page"] as? [String: Any])?["autocorrect"] as? String == "on" }
        let page = try XCTUnwrap(try state()["page"] as? [String: Any])
        let visitor = try XCTUnwrap(page["visitor"] as? [String: Any])
        XCTAssertEqual(visitor["uuid"] as? String, "ui-visitor")
        XCTAssertEqual(visitor["hash"] as? String, "ui-hash")
        XCTAssertEqual(visitor["first_name"] as? String, "Тест")
        XCTAssertEqual(page["accept"] as? String, "image/jpg,image/jpeg,image/gif,image/img,.doc,.docx,.pdf,.txt")
        let records = try control(["wait": "webchat/channel/set-user-subscription"])
        let pushes = records.filter { $0["route"] as? String == "webchat/channel/set-user-subscription" }
        XCTAssertEqual(pushes.count, 1)
        let body = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(pushes.first?["body"] as? String)))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["subscription": "synthetic-ui-token", "uuid": "ui-visitor"])
        app.buttons["Close Chat"].tap()
        XCTAssertTrue(app.buttons["Open secure"].waitForExistence(timeout: 5))
    }

    func testPublicSecureConfigurationComputesVisitorHashFromBundleSalt() throws {
        try assertPublicVisitorHash(legacy: false)
    }

    func testPublicLegacyConfigurationComputesVisitorHashFromBundleSalt() throws {
        try assertPublicVisitorHash(legacy: true)
    }

    private func assertPublicVisitorHash(legacy: Bool) throws {
        try prepare(links: "")
        app.launchArguments.append("compute-visitor-hash")
        app.launch()
        try open(legacy: legacy)
        let page = try XCTUnwrap(try state()["page"] as? [String: Any])
        let visitor = try XCTUnwrap(page["visitor"] as? [String: Any])
        XCTAssertEqual(visitor["uuid"] as? String, "ui-visitor")
        XCTAssertEqual(visitor["first_name"] as? String, "Тест")
        // Независимый эталон Python hashlib: SHA256(salt + hex(SHA256(salt + "ui-visitorТест"))).
        // Salt "synthetic-ui-salt" берётся SDK из Bundle.main, без подстановки внутренних полей.
        XCTAssertEqual(visitor["hash"] as? String, "4f15d687ff2be31acf6ed466a55549a0d49dcbb5824de4f9491bf8584fa383d4")
        XCTAssertEqual(try records("webchat/channel").count, 1)
    }

    func testRepeatedOpenAndCloseLoadsChatEachTime() throws {
        try assertRepeatedOpenAndClose(legacy: false)
    }

    func testRepeatedLegacyOpenAndCloseReleasesControllerAndWebView() throws {
        try assertRepeatedOpenAndClose(legacy: true)
    }

    private func assertRepeatedOpenAndClose(legacy: Bool) throws {
        try prepare(links: "")
        app.launch()
        for _ in 0..<3 {
            try open(legacy: legacy)
            try waitState { $0["controllerAlive"] as? Bool == true && $0["webViewAlive"] as? Bool == true && $0["aliveCount"] as? Int == 1 }
            app.buttons["Close Chat"].tap()
            XCTAssertTrue(app.buttons["Open secure"].waitForExistence(timeout: 5))
            try assertChatReleased()
        }
        XCTAssertEqual(try records("webchat/channel").count, 3)
    }

    private func assertChatReleased() throws {
        try waitState { $0["controllerAlive"] as? Bool == false && $0["webViewAlive"] as? Bool == false && $0["aliveCount"] as? Int == 0 }
    }

    func testCancelledInteractiveBackPreservesActiveDownload() throws {
        let contents = String(repeating: "interactive-download|", count: 4096)
        var file = attachment()
        file["body"] = Data(contents.utf8).base64EncodedString()
        file["holdAfterHeaders"] = true
        file["oneUse"] = true
        try prepare(links: link("Download", route: "held"), routes: ["held": file])
        app.launchArguments.append(contentsOf: ["interactive-back", "without-push-token"])
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

    func testCancelledInteractiveBackPreservesLegacyPreview() throws {
        app.launchArguments.append("interactive-back")
        try prepareLegacyPreviewButtons()
        try openLegacyPreview("First preview", contents: "first-preview-content")
        let directories = try XCTUnwrap(try state()["directories"] as? [String])
        try cancelInteractiveBack()
        XCTAssertEqual(try state()["directories"] as? [String], directories)
        try assertLegacyPreviewFile(contents: "first-preview-content")
        XCTAssertTrue(app.webViews.staticTexts["first-preview-content"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["LegacyPreviewBack"].tap()
        try assertLegacyPreviewClosed()
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
        XCTAssertEqual(try state()["aliveCount"] as? Int, 1)
        XCTAssertEqual(try state()["webViewAlive"] as? Bool, true)
    }

    func testDocumentPickerUploadsSelectedFileWithoutReloadingChat() throws {
        try prepare(links: "<button onclick=\"document.getElementById('webchat-file-input').click()\">Attach document</button>", script: """
            document.getElementById('webchat-file-input').onchange = async function() {
              const file = this.files[0];
              const result = await fetch('\(url("upload"))', {method:'POST', body:file, headers:{'X-File-Name':file.name}});
              if (result.ok) document.getElementById('marker').textContent = 'Uploaded ' + file.name;
            };
            """, routes: ["upload": response("ok", mime: "text/plain")])
        app.launchArguments.append(contentsOf: ["seed-upload-file", "without-push-token"])
        app.launch()
        try open()
        app.webViews.buttons["Attach document"].tap()
        let choose = app.buttons["Choose File"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5), app.debugDescription)
        choose.tap()
        try waitState { $0["presented"] as? String == "UIDocumentPickerViewController" }
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS 'sdk-upload'")).firstMatch
        // iPhone может сразу открыть Documents, а iPad начинает с Recents.
        if !file.waitForExistence(timeout: 2) {
            let browse = app.buttons["Browse"]
            if browse.exists { browse.tap() }
            if !file.waitForExistence(timeout: 2) {
                let local = app.cells.matching(NSPredicate(format: "label BEGINSWITH 'On My'")).firstMatch
                XCTAssertTrue(local.waitForExistence(timeout: 5), app.debugDescription)
                local.tap()
                let folder = app.cells.matching(NSPredicate(format: "label CONTAINS 'CraftTalk UI Host'")).firstMatch
                XCTAssertTrue(folder.waitForExistence(timeout: 5), app.debugDescription)
                folder.tap()
            }
        }
        XCTAssertTrue(file.waitForExistence(timeout: 5), app.debugDescription)
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
        app.launchArguments.append("without-push-token")
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

    func testLegacyChatSurvivesBackgroundAndDownloadsAfterReturn() throws {
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
                script += "document.getElementById('\(route)').href=URL.createObjectURL(new Blob(['\(download.1)'],{type:'application/octet-stream'}));"
            } else {
                links += link(download.0, route: route)
                var file = attachment()
                file["body"] = Data(download.1.utf8).base64EncodedString()
                file["oneUse"] = true
                routes[route] = file
            }
        }
        try prepare(links: links, script: script, routes: routes)
        app.launchArguments.append("without-push-token")
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
            try waitState { $0["controllerAlive"] as? Bool == true && $0["webViewAlive"] as? Bool == true && $0["aliveCount"] as? Int == 1 }
            try assertDraftAndNoFiles(expectedDraft: edited)
            XCTAssertTrue(draft.isHittable)
            XCTAssertEqual((try state()["page"] as? [String: Any])?["url"] as? String, url("webchat/channel"))
            try tapLink(download.0)
            try closeShare(expected: download.1)
            try assertDraftAndNoFiles(expectedDraft: edited)
            try waitState { ($0["directories"] as? [String])?.isEmpty == true }
            if !legacy {
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
        try assertChatReleased()
    }

    func testLegacyPreviewSurvivesBackgroundAndCanShareAfterReturn() throws {
        try prepareLegacyPreviewButtons()
        try openLegacyPreview("First preview", contents: "first-preview-content")
        let directories = try XCTUnwrap(try state()["directories"] as? [String])
        try backgroundAndReturn()
        try assertLegacyPreviewFile(contents: "first-preview-content")
        XCTAssertEqual(try state()["directories"] as? [String], directories)
        XCTAssertTrue(app.webViews.staticTexts["first-preview-content"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["LegacyPreviewShare"].tap()
        try closeShare(expected: "first-preview-content")
        try waitState { $0["presented"] as? String == "" && ($0["files"] as? [[String: Any]])?.count == 1 }
        app.buttons["LegacyPreviewBack"].tap()
        try assertLegacyPreviewClosed()
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

    func testRealExternalLinkOpensSafariButProgrammaticClickIsRejected() throws {
        let external = url("external", profile: "system", host: "127.0.0.1")
        try prepare(links: "<a id='external' href='\(external)'>External</a><button onclick=\"document.getElementById('external').click()\">Programmatic</button>",
                    routes: ["external": response("External page")])
        app.launch()
        try open()
        app.webViews.buttons["Programmatic"].tap()
        try waitForError()
        XCTAssertEqual(try records("external").count, 0)
        XCTAssertEqual(try state()["presented"] as? String, "")
        try tapLink("External")
        try closeSafari()
        try assertDraftAndNoFiles()
        app.webViews.buttons["Programmatic"].tap()
        try waitState { ($0["errors"] as? [String])?.count ?? 0 >= 2 }
        XCTAssertEqual(try state()["presented"] as? String, "")
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

    func testIframeExternalClickAndForgedActivationCannotOpenSafari() throws {
        let external = url("external", profile: "system", host: "127.0.0.1")
        let child = "<a href='\(external)'>Frame external</a><script>try { webkit.messageHandlers.ctSecureLinkActivation.postMessage({token:'fake',url:'\(external)'}); } catch(e) {}</script>"
        try prepare(links: "<iframe title='Child' src='\(url("child"))'></iframe>", routes: ["child": response(child), "external": response("Must not load")])
        app.launch()
        try open()
        try tapLink("Frame external")
        try waitForError()
        XCTAssertEqual(try state()["presented"] as? String, "")
        XCTAssertEqual(try records("external").count, 0)
    }

    func testTelephoneAndMailRequireRealMainFrameClick() throws {
        try prepare(links: "<a id='phone' href='tel:15555550100'>Telephone</a><a href='mailto:synthetic@example.invalid'>Email</a><button onclick=\"document.getElementById('phone').click();document.getElementById('marker').textContent='Script done'\">Script phone</button>")
        app.launch()
        try open()
        app.webViews.buttons["Script phone"].tap()
        try waitState { ($0["page"] as? [String: Any])?["marker"] as? String == "Script done" }
        XCTAssertEqual(try state()["openedSchemes"] as? [String], [])
        try tapLink("Telephone")
        try tapLink("Email")
        try waitState { $0["openedSchemes"] as? [String] == ["tel", "mailto"] }
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

    func testBlobDownloadAndRepeatedDownloadCleanUpFiles() throws {
        try prepare(links: "<a id='blob'>Blob file</a>", script: "document.getElementById('blob').href=URL.createObjectURL(new Blob(['blob-bytes'],{type:'application/octet-stream'}));")
        app.launch()
        try open(editDraft: true)
        for _ in 0..<2 {
            try tapLink("Blob file")
            try closeShare(expected: "blob-bytes")
            try assertDraftAndNoFiles()
        }
        XCTAssertTrue(try records("blob").isEmpty)
        app.buttons["Close Chat"].tap()
        XCTAssertTrue(app.buttons["Open secure"].waitForExistence(timeout: 5))
        try assertChatReleased()
    }

    func testMalformedBlobMessagesPreserveActualChatPageAndEditedDraft() throws {
        try prepare(links: """
            <a id='blob'>Initialize blob bridge</a>
            <button onclick="webkit.messageHandlers.readBlob.postMessage(42);
              webkit.messageHandlers.readBlob.postMessage('');
              webkit.messageHandlers.readBlob.postMessage('data:application/pdf;base64,invalid!')">Invalid blobs</button>
            """, script: "document.getElementById('blob').href=URL.createObjectURL(new Blob(['bridge-ready'],{type:'application/octet-stream'}));")
        app.launchArguments.append("without-push-token")
        app.launch()
        try open(editDraft: true)
        // Сам SDK регистрирует readBlob после настоящей blob-навигации.
        try tapLink("Initialize blob bridge")
        try closeShare(expected: "bridge-ready")
        try assertDraftAndNoFiles()
        XCTAssertEqual(try state()["errors"] as? [String], [])
        app.webViews.buttons["Invalid blobs"].tap()
        try waitState { ($0["errors"] as? [String])?.count == 3 }
        let errors = try XCTUnwrap(try state()["errors"] as? [String])
        XCTAssertTrue(errors.allSatisfy { $0.contains("stage=download") && $0.contains("domain=NSURLErrorDomain code=-1016") })
        try assertDraftAndNoFiles()
        XCTAssertTrue(app.webViews.textFields["Draft"].isHittable)
    }

    func testRelaunchIsolatesFilesAndWebsiteDataAfterInterruptedScenario() throws {
        try prepare(links: """
            <a id='blob'>Leave attachment open</a>
            <button onclick="localStorage.setItem('previous-case','stale');document.cookie='previous-case=stale;path=/';
              document.getElementById('marker').textContent='State seeded'">Seed storage</button>
            """, script: """
            if (localStorage.getItem('previous-case') || document.cookie.includes('previous-case=')) {
              document.getElementById('marker').textContent='State leaked from previous launch';
            }
            document.getElementById('blob').href=URL.createObjectURL(new Blob(['unfinished'],{type:'application/octet-stream'}));
            """)
        app.launchArguments.append("without-push-token")
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
        app.launchArguments.append("without-push-token")
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

    func testLegacyConfigurationPinAndBlobCleanup() throws {
        try prepare(links: "<a id='blob'>Legacy blob</a>", script: "document.getElementById('blob').href=URL.createObjectURL(new Blob(['legacy-blob'],{type:'application/octet-stream'}));")
        app.launch()
        try open(legacy: true)
        try tapLink("Legacy blob")
        try closeShare(expected: "legacy-blob")
        try assertDraftAndNoFiles()
        app.buttons["Close Chat"].tap()
        XCTAssertTrue(app.buttons["Open secure"].waitForExistence(timeout: 5))
    }

    private func open(legacy: Bool = false, editDraft: Bool = false) throws {
        let previousPageID = pageID
        app.buttons[legacy ? "Open legacy" : "Open secure"].tap()
        try waitState {
            guard let page = $0["page"] as? [String: Any], let identifier = page["pageID"] as? String else { return false }
            return page["marker"] as? String == "Chat ready" && !identifier.isEmpty && identifier != previousPageID
        }
        pageID = try XCTUnwrap((try state()["page"] as? [String: Any])?["pageID"] as? String)
        pageRequestCount = try records("webchat/channel").count
        draftBeforeAction = "unsent draft"
        if editDraft {
            let draft = app.webViews.textFields["Draft"]
            draft.tap()
            draft.typeText("-edited-before-download")
            draftBeforeAction = try XCTUnwrap(draft.value as? String)
            XCTAssertTrue(draftBeforeAction.contains("-edited-before-download"))
            app.webViews.buttons["Finish draft"].tap()
            try waitState { ($0["page"] as? [String: Any])?["draft"] as? String == self.draftBeforeAction }
        }
    }

    func testExpiredActivationCannotAuthorizeDelayedProgrammaticClick() throws {
        let external = url("blocked", profile: "system", host: "127.0.0.1")
        try prepare(links: "<a id='delayed' href='\(external)'>Delayed link</a>",
                    script: "document.getElementById('delayed').addEventListener('click',function(e){if(e.isTrusted){e.preventDefault();setTimeout(()=>this.click(),6100);}});",
                    routes: ["blocked": response("Must not load")])
        app.launch()
        try open()
        try tapLink("Delayed link")
        try waitForError()
        XCTAssertEqual(try records("blocked").count, 0)
        XCTAssertEqual(try state()["presented"] as? String, "")
    }

    func testConcurrentWKDownloadIsRejectedAndCanRetryAfterFirstCompletes() throws {
        try assertConcurrentDownload(secondIsBlob: false)
    }

    func testBlobDuringWKDownloadIsRejectedAndCanRetryAfterFirstCompletes() throws {
        try assertConcurrentDownload(secondIsBlob: true)
    }

    private func assertConcurrentDownload(secondIsBlob: Bool) throws {
        let firstContents = String(repeating: "first-download-content|", count: 4096)
        let secondContents = "second-download-content"
        var first = attachment()
        first["body"] = Data(firstContents.utf8).base64EncodedString()
        first["holdAfterHeaders"] = true
        first["oneUse"] = true
        var routes = ["first": first]
        var links = link("First download", route: "first")
        var script = ""
        if secondIsBlob {
            links += "<a id='second' style='display:block;margin:20px 0'>Second download</a>"
            script = "document.getElementById('second').href=URL.createObjectURL(new Blob(['\(secondContents)'],{type:'application/octet-stream'}));"
        } else {
            links += link("Second download", route: "second")
            // Повтор — второе явное нажатие; запрещаем кеш, чтобы журнал различал обе попытки.
            routes["second"] = response(secondContents, mime: "application/octet-stream",
                                        headers: ["Content-Disposition": "attachment; filename=second.bin", "Cache-Control": "no-store"])
        }
        try prepare(links: links, script: script, routes: routes)
        app.launchArguments.append("without-push-token")
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
        if !secondIsBlob {
            // Второй GET уже дошёл до сервера: SDK отклоняет полученный WKDownload, не повторяя запрос.
            XCTAssertEqual(try records("second").count, 1)
        }

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
        for (route, count) in secondIsBlob ? [("first", 1)] : [("first", 1), ("second", 2)] {
            let requests = try records(route)
            XCTAssertEqual(requests.count, count, route)
            XCTAssertTrue(requests.allSatisfy { $0["method"] as? String == "GET" })
            XCTAssertTrue(requests.allSatisfy { ($0["headers"] as? [String: String])?["cookie"]?.contains("session=synthetic-webview") == true })
        }
    }

    func testClosingChatReleasesControllerAndCleansActiveDownload() throws {
        var spec = attachment()
        spec["holdAfterHeaders"] = true
        spec["body"] = Data(repeating: 65, count: 65536).base64EncodedString()
        try prepare(links: link("Download", route: "held"), routes: ["held": spec])
        app.launch()
        try open()
        try tapLink("Download")
        try waitState { ($0["directories"] as? [String])?.count == 1 }
        app.buttons["Close Chat"].tap()
        XCTAssertTrue(app.buttons["Open secure"].waitForExistence(timeout: 5))
        try assertChatReleased()
        try waitState { ($0["directories"] as? [String])?.isEmpty == true && $0["presented"] as? String == "" }
        _ = try control(["release": "held"])
        XCTAssertEqual(try records("held").count, 1)
        try open()
        app.buttons["Close Chat"].tap()
        XCTAssertTrue(app.buttons["Open secure"].waitForExistence(timeout: 5))
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

    func testLegacyPreviewBackRemovesFileAndAllowsAnotherPreview() throws {
        try prepareLegacyPreviewButtons()
        for (title, contents) in [("First preview", "first-preview-content"), ("Second preview", "second-preview-content")] {
            try openLegacyPreview(title, contents: contents)
            app.buttons["LegacyPreviewBack"].tap()
            try assertLegacyPreviewClosed()
        }
        XCTAssertEqual(try records("webchat/channel").count, 1)
        XCTAssertEqual(try state()["errors"] as? [String], [])
    }

    func testLegacyPreviewShareCanRepeatWithoutDeletingPreviewFile() throws {
        try prepareLegacyPreviewButtons()
        try openLegacyPreview("First preview", contents: "first-preview-content")
        let originalDirectories = try XCTUnwrap(try state()["directories"] as? [String])
        for _ in 0..<2 {
            app.buttons["LegacyPreviewShare"].tap()
            try waitState { $0["presented"] as? String == "UIActivityViewController" }
            try closeShare(expected: "first-preview-content")
            try waitState { $0["presented"] as? String == "" && ($0["files"] as? [[String: Any]])?.count == 1 }
            XCTAssertEqual(try state()["directories"] as? [String], originalDirectories)
            try assertLegacyPreviewFile(contents: "first-preview-content")
            XCTAssertTrue(app.webViews.staticTexts["first-preview-content"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["LegacyPreviewShare"].isHittable)
        }
        app.buttons["LegacyPreviewBack"].tap()
        try assertLegacyPreviewClosed()
        XCTAssertEqual(try records("webchat/channel").count, 1)
        XCTAssertEqual(try state()["errors"] as? [String], [])
    }

    private func prepareLegacyPreviewButtons() throws {
        try prepare(links: "<a id='first'>First preview</a><br><a id='second'>Second preview</a>", script: """
            document.getElementById('first').href=URL.createObjectURL(new Blob(['first-preview-content'],{type:'text/plain'}));
            document.getElementById('second').href=URL.createObjectURL(new Blob(['second-preview-content'],{type:'text/plain'}));
            """)
        // Legacy push использует системное доверие; частный pin стенда проверяет только WebView.
        app.launchArguments.append(contentsOf: ["label-preview-buttons", "without-push-token"])
        app.launch()
        try open(legacy: true)
    }

    private func openLegacyPreview(_ title: String, contents: String) throws {
        try tapLink(title)
        try waitState { ($0["files"] as? [[String: Any]])?.count == 1 }
        XCTAssertTrue(app.webViews.staticTexts[contents].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["LegacyPreviewBack"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["LegacyPreviewBack"].isHittable)
        XCTAssertTrue(app.buttons["LegacyPreviewShare"].isHittable)
        try assertLegacyPreviewFile(contents: contents)
    }

    private func assertLegacyPreviewFile(contents: String) throws {
        let files = try XCTUnwrap(try state()["files"] as? [[String: Any]])
        XCTAssertEqual(files.count, 1)
        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(Data(base64Encoded: file["body"] as? String ?? ""), Data(contents.utf8))
        XCTAssertEqual((file["name"] as? String).map { ($0 as NSString).pathExtension }, "txt")
    }

    private func assertLegacyPreviewClosed() throws {
        try assertDraftAndNoFiles()
        try waitState { ($0["directories"] as? [String])?.isEmpty == true }
        XCTAssertFalse(app.buttons["LegacyPreviewBack"].exists)
        XCTAssertFalse(app.buttons["LegacyPreviewShare"].exists)
        XCTAssertTrue(app.webViews.textFields["Draft"].isHittable)
        XCTAssertEqual((try state()["page"] as? [String: Any])?["url"] as? String, url("webchat/channel"))
    }

    func testLegacyPreviewIsRemovedWhenChatCloses() throws {
        try prepare(links: "<a id='blob'>Preview</a>", script: "document.getElementById('blob').href=URL.createObjectURL(new Blob(['legacy-preview-content'],{type:'text/plain'}));")
        app.launch()
        try open(legacy: true)
        try tapLink("Preview")
        try waitState { ($0["files"] as? [[String: Any]])?.count == 1 }
        XCTAssertTrue(app.webViews.staticTexts["legacy-preview-content"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Close Chat"].tap()
        try waitState { ($0["files"] as? [[String: Any]])?.isEmpty == true }
        try assertChatReleased()
    }

    func testAutomaticIframeDownloadIsCancelledOnIOS18() throws {
        for target in ["_self", "_top"] {
            let child = "<a id='file' href='\(url("file"))' target='\(target)' download>File</a><script>window.onload=()=>document.getElementById('file').click()</script>"
            try prepare(links: "<iframe title='Automatic frame' src='\(url("child"))'></iframe>", routes: ["child": response(child), "file": attachment()])
            app.launch()
            try open()
            _ = try control(["wait": "file"])
            XCTAssertEqual(try records("file").count, 1)
            let unwanted = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
                guard let state = try? self?.state() else { return false }
                return state["presented"] as? String == "UIActivityViewController" || (state["files"] as? [[String: Any]])?.isEmpty == false
            }, object: nil)
            unwanted.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [unwanted], timeout: 3), .completed)
            try assertDraftAndNoFiles()
            app.terminate()
            _ = try control(["reset": true])
        }
    }

    private func tapLink(_ title: String) throws {
        let link = app.webViews.links[title].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10), title)
        link.tap()
    }

    private func closeSafari() throws {
        XCTAssertTrue(app.webViews.staticTexts["External page"].firstMatch.waitForExistence(timeout: 10))
        let done = app.buttons["Done"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: done)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        // Xcode 27.2 / iOS 18.6: tap() иногда не доставляет нажатие удалённому Safari-сервису.
        // Вернуть tap() можно после проверки обоих Safari-сценариев на обновлённом окружении.
        done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func closeShare(expected: String = "synthetic-file") throws {
        let isPad = try state()["idiom"] as? String == "pad"
        let close = app.buttons["Close"].firstMatch
        if isPad {
            try waitState { $0["presented"] as? String == "UIActivityViewController" }
        } else {
            XCTAssertTrue(close.waitForExistence(timeout: 10), app.debugDescription)
        }
        try waitState { ($0["files"] as? [[String: Any]])?.count == 1 }
        let files = try XCTUnwrap(try state()["files"] as? [[String: Any]])
        XCTAssertEqual(Data(base64Encoded: files[0]["body"] as? String ?? ""), Data(expected.utf8))
        if isPad {
            // У popover нет телефонной кнопки Close; закрываем настоящим нажатием вне меню.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.12)).tap()
            try waitState { $0["presented"] as? String == "" }
        } else {
            close.tap()
        }
    }

    private func assertDraftAndNoFiles(expectedDraft: String? = nil) throws {
        try waitState {
            ($0["files"] as? [[String: Any]])?.isEmpty == true &&
            ($0["directories"] as? [String])?.isEmpty == true && $0["presented"] as? String == ""
        }
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
        let edited = try XCTUnwrap(draft.value as? String)
        XCTAssertNotEqual(edited, expected)
        XCTAssertEqual(edited.count, expected.count + 1)
        draft.typeText(XCUIKeyboardKey.delete.rawValue)
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
